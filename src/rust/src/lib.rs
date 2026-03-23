use std::cell::RefCell;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use extendr_api::prelude::*;
use grafeo_common::types::Value;
use grafeo_engine::config::StorageFormat;
use grafeo_engine::database::QueryResult;
use grafeo_engine::{Config, GrafeoDB, Session, VERSION};

struct DbHandle {
    inner: Arc<GrafeoDB>,
    closed: AtomicBool,
}

impl DbHandle {
    fn new(db: GrafeoDB) -> Self {
        Self {
            inner: Arc::new(db),
            closed: AtomicBool::new(false),
        }
    }

    fn ensure_open(&self) -> Result<()> {
        if self.closed.load(Ordering::SeqCst) {
            Err(Error::Other("Grafeo database handle is closed".to_string()))
        } else {
            Ok(())
        }
    }

    fn close(&self) -> Result<bool> {
        let was_closed = self.closed.swap(true, Ordering::SeqCst);
        if !was_closed {
            self.inner.close().map_err(engine_error)?;
        }
        Ok(!was_closed)
    }
}

struct TxHandle {
    _db: Arc<GrafeoDB>,
    session: RefCell<Session>,
    active: AtomicBool,
}

impl TxHandle {
    fn new(db: Arc<GrafeoDB>, session: Session) -> Self {
        Self {
            _db: db,
            session: RefCell::new(session),
            active: AtomicBool::new(true),
        }
    }

    fn ensure_active(&self) -> Result<()> {
        if self.active.load(Ordering::SeqCst) {
            Ok(())
        } else {
            Err(Error::Other(
                "Grafeo transaction is no longer active".to_string(),
            ))
        }
    }

    fn mark_inactive(&self) {
        self.active.store(false, Ordering::SeqCst);
    }
}

fn engine_error(err: impl std::fmt::Display) -> Error {
    Error::Other(err.to_string())
}

fn robj_to_optional_string(path: &Robj) -> Result<Option<String>> {
    if path.is_null() {
        return Ok(None);
    }

    path.as_str()
        .map(ToOwned::to_owned)
        .map(Some)
        .ok_or_else(|| Error::Other("`path` must be NULL or a character scalar".to_string()))
}

fn option_string_to_robj(value: Option<String>) -> Robj {
    value.map_or(NULL.into(), |text| r!(text))
}

fn option_f64_to_robj(value: Option<f64>) -> Robj {
    value.map_or(NULL.into(), |number| r!(number))
}

fn option_u64_to_robj(value: Option<u64>) -> Robj {
    value.map_or(NULL.into(), |number| r!(number as f64))
}

fn encode_value(value: &Value) -> Robj {
    match value {
        Value::Null => NULL.into(),
        Value::Bool(value) => r!(*value),
        Value::Int64(value) => r!(*value),
        Value::Float64(value) => r!(*value),
        Value::String(value) => r!(value.as_str()),
        Value::Bytes(value) => Robj::from(value.to_vec()),
        Value::Timestamp(value) => r!(value.to_string()),
        Value::Date(value) => r!(value.to_string()),
        Value::Time(value) => r!(value.to_string()),
        Value::Duration(value) => r!(value.to_string()),
        Value::ZonedDatetime(value) => r!(value.to_string()),
        Value::List(values) => {
            let items: Vec<Robj> = values.iter().map(encode_value).collect();
            Robj::from(List::from_values(items))
        }
        Value::Map(values) => {
            let names: Vec<&str> = values.keys().map(|key| key.as_str()).collect();
            let items: Vec<Robj> = values.values().map(encode_value).collect();
            Robj::from(List::from_names_and_values(names, items).unwrap())
        }
        Value::Vector(values) => {
            let items: Vec<f64> = values.iter().map(|value| f64::from(*value)).collect();
            r!(items)
        }
        Value::Path { nodes, edges } => {
            let node_items: Vec<Robj> = nodes.iter().map(encode_value).collect();
            let edge_items: Vec<Robj> = edges.iter().map(encode_value).collect();
            Robj::from(list!(
                nodes = List::from_values(node_items),
                edges = List::from_values(edge_items)
            ))
        }
    }
}

fn encode_query_result(result: QueryResult) -> Robj {
    let column_types: Vec<String> = result
        .column_types
        .iter()
        .map(ToString::to_string)
        .collect();
    let row_items: Vec<Robj> = result
        .rows
        .into_iter()
        .map(|row| {
            let values: Vec<Robj> = row.iter().map(encode_value).collect();
            Robj::from(
                List::from_names_and_values(result.columns.iter().map(String::as_str), values)
                    .unwrap(),
            )
        })
        .collect();

    Robj::from(list!(
        columns = result.columns,
        column_types = column_types,
        rows = List::from_values(row_items),
        execution_time_ms = option_f64_to_robj(result.execution_time_ms),
        rows_scanned = option_u64_to_robj(result.rows_scanned),
        status_message = option_string_to_robj(result.status_message),
        gql_status = result.gql_status.as_str()
    ))
}

/// Open a Grafeo database handle.
/// @noRd
#[extendr]
fn grafeo_db_open(path: Robj, wal: bool) -> Result<ExternalPtr<DbHandle>> {
    let path = robj_to_optional_string(&path)?;
    let mut config = if let Some(path) = path {
        let mut config = Config::persistent(path).with_storage_format(StorageFormat::SingleFile);
        config.wal_enabled = wal;
        config
    } else {
        Config::in_memory()
    };
    config.wal_enabled = config.path.is_some() && config.wal_enabled;

    let db = GrafeoDB::with_config(config).map_err(engine_error)?;
    Ok(ExternalPtr::new(DbHandle::new(db)))
}

/// Close a Grafeo database handle.
/// @noRd
#[extendr]
fn grafeo_db_close(db: ExternalPtr<DbHandle>) -> Result<bool> {
    db.ensure_open()?;
    db.close()
}

/// Execute a GQL statement directly against the database.
/// @noRd
#[extendr]
fn grafeo_db_execute_raw(db: ExternalPtr<DbHandle>, query: &str) -> Result<Robj> {
    db.ensure_open()?;
    let result = db
        .inner
        .execute_language(query, "gql", None)
        .map_err(engine_error)?;
    Ok(encode_query_result(result))
}

/// Execute a GQL query directly against the database.
/// @noRd
#[extendr]
fn grafeo_db_query_raw(db: ExternalPtr<DbHandle>, query: &str) -> Result<Robj> {
    grafeo_db_execute_raw(db, query)
}

/// Start a transaction on the database.
/// @noRd
#[extendr]
fn grafeo_db_begin_transaction(db: ExternalPtr<DbHandle>) -> Result<ExternalPtr<TxHandle>> {
    db.ensure_open()?;
    let mut session = db.inner.session();
    session.begin_transaction().map_err(engine_error)?;
    Ok(ExternalPtr::new(TxHandle::new(
        Arc::clone(&db.inner),
        session,
    )))
}

/// Return high-level database metadata.
/// @noRd
#[extendr]
fn grafeo_db_info(db: ExternalPtr<DbHandle>) -> Result<Robj> {
    db.ensure_open()?;
    let info = db.inner.info();
    Ok(Robj::from(list!(
        graph_model = db.inner.graph_model().to_string(),
        node_count = info.node_count as f64,
        edge_count = info.edge_count as f64,
        is_persistent = info.is_persistent,
        path = option_string_to_robj(info.path.map(|path| path.display().to_string())),
        wal_enabled = info.wal_enabled,
        version = info.version,
        current_graph = option_string_to_robj(db.inner.current_graph())
    )))
}

/// Execute a GQL statement inside a transaction.
/// @noRd
#[extendr]
fn grafeo_tx_execute_raw(tx: ExternalPtr<TxHandle>, query: &str) -> Result<Robj> {
    tx.ensure_active()?;
    let result = tx.session.borrow().execute(query).map_err(engine_error)?;
    Ok(encode_query_result(result))
}

/// Execute a GQL query inside a transaction.
/// @noRd
#[extendr]
fn grafeo_tx_query_raw(tx: ExternalPtr<TxHandle>, query: &str) -> Result<Robj> {
    grafeo_tx_execute_raw(tx, query)
}

/// Commit a Grafeo transaction.
/// @noRd
#[extendr]
fn grafeo_tx_commit(tx: ExternalPtr<TxHandle>) -> Result<()> {
    tx.ensure_active()?;
    tx.session.borrow_mut().commit().map_err(engine_error)?;
    tx.mark_inactive();
    Ok(())
}

/// Roll back a Grafeo transaction.
/// @noRd
#[extendr]
fn grafeo_tx_rollback(tx: ExternalPtr<TxHandle>) -> Result<()> {
    tx.ensure_active()?;
    tx.session.borrow_mut().rollback().map_err(engine_error)?;
    tx.mark_inactive();
    Ok(())
}

/// Return the linked Grafeo engine version.
/// @noRd
#[extendr]
fn grafeo_engine_version() -> String {
    VERSION.to_string()
}

extendr_module! {
    mod grafeoR;
    fn grafeo_db_open;
    fn grafeo_db_close;
    fn grafeo_db_execute_raw;
    fn grafeo_db_query_raw;
    fn grafeo_db_begin_transaction;
    fn grafeo_db_info;
    fn grafeo_tx_execute_raw;
    fn grafeo_tx_query_raw;
    fn grafeo_tx_commit;
    fn grafeo_tx_rollback;
    fn grafeo_engine_version;
}
