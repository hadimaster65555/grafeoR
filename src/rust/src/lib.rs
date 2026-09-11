use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use extendr_api::prelude::*;
use grafeo_common::types::{Date, NodeId, PropertyKey, Timestamp, Value};
use grafeo_common::utils::error::Error as EngineError;
use grafeo_engine::config::StorageFormat;
use grafeo_engine::database::QueryResult;
use grafeo_engine::transaction::IsolationLevel;
use grafeo_engine::{AccessMode, Config, GrafeoDB, Session, VERSION};

struct DbHandle {
    inner: Arc<GrafeoDB>,
    closed: Arc<AtomicBool>,
    read_only: bool,
}

impl DbHandle {
    fn new(db: GrafeoDB, read_only: bool) -> Self {
        Self {
            inner: Arc::new(db),
            closed: Arc::new(AtomicBool::new(false)),
            read_only,
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
    db_closed: Arc<AtomicBool>,
    read_only: bool,
    session: RefCell<Session>,
    active: AtomicBool,
}

impl TxHandle {
    fn new(
        db: Arc<GrafeoDB>,
        db_closed: Arc<AtomicBool>,
        read_only: bool,
        session: Session,
    ) -> Self {
        Self {
            _db: db,
            db_closed,
            read_only,
            session: RefCell::new(session),
            active: AtomicBool::new(true),
        }
    }

    fn ensure_active(&self) -> Result<()> {
        if self.db_closed.load(Ordering::SeqCst) {
            Err(Error::Other("Grafeo database handle is closed".to_string()))
        } else if self.active.load(Ordering::SeqCst) {
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

fn engine_error(err: EngineError) -> Error {
    let code = err.error_code();
    Error::Other(format!(
        "[{} retryable={}] {}",
        code.as_str(),
        code.is_retryable(),
        err
    ))
}

fn read_only_error() -> Error {
    Error::Other(
        "[GRAFEO-S001 retryable=false] database was opened read-only; mutation rejected".into(),
    )
}

fn query_is_mutating(query: &str) -> bool {
    query
        .split(|character: char| !character.is_ascii_alphabetic())
        .map(|token| token.to_ascii_uppercase())
        .any(|token| {
            matches!(
                token.as_str(),
                "INSERT"
                    | "CREATE"
                    | "DELETE"
                    | "SET"
                    | "REMOVE"
                    | "MERGE"
                    | "DROP"
                    | "UPDATE"
                    | "LOAD"
            )
        })
}

fn ensure_write_allowed(read_only: bool, query: &str) -> Result<()> {
    if read_only && query_is_mutating(query) {
        Err(read_only_error())
    } else {
        Ok(())
    }
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
    value.map_or(NULL.into(), |number| r!(number.to_string()))
}

fn encode_value(value: &Value) -> Robj {
    match value {
        Value::Null => NULL.into(),
        Value::Bool(value) => r!(*value),
        // Keep values in R's exact integer/double range convenient, but never
        // route larger values through an imprecise IEEE-754 conversion.
        Value::Int64(value) if i32::try_from(*value).is_ok() => r!(*value as i32),
        Value::Int64(value) if value.unsigned_abs() <= 9_007_199_254_740_991 => {
            r!(*value as f64)
        }
        Value::Int64(value) => r!(value.to_string()),
        Value::Float64(value) => r!(*value),
        Value::String(value) => r!(value.as_str()),
        Value::Bytes(value) => Robj::from(Raw::from_bytes(value)),
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
        // These distributed counter variants are not yet given a dedicated
        // R class; preserve their structure as a named map.
        Value::GCounter(values) => Robj::from(
            List::from_names_and_values(
                values.keys().map(String::as_str),
                values.values().map(|value| r!(value.to_string())),
            )
            .unwrap(),
        ),
        Value::OnCounter { pos, neg } => Robj::from(list!(
            pos = List::from_names_and_values(
                pos.keys().map(String::as_str),
                pos.values().map(|value| r!(value.to_string()))
            )
            .unwrap(),
            neg = List::from_names_and_values(
                neg.keys().map(String::as_str),
                neg.values().map(|value| r!(value.to_string()))
            )
            .unwrap()
        )),
        _ => r!(value.to_string()),
    }
}

fn encode_query_result(result: QueryResult) -> Robj {
    let columns = result.columns.clone();
    let column_types: Vec<String> = result
        .column_types
        .iter()
        .map(ToString::to_string)
        .collect();
    let row_items: Vec<Robj> = result
        .rows()
        .iter()
        .map(|row| {
            let values: Vec<Robj> = row.iter().map(encode_value).collect();
            Robj::from(
                List::from_names_and_values(columns.iter().map(String::as_str), values).unwrap(),
            )
        })
        .collect();

    Robj::from(list!(
        columns = columns,
        column_types = column_types,
        rows = List::from_values(row_items),
        execution_time_ms = option_f64_to_robj(result.execution_time_ms),
        rows_scanned = option_u64_to_robj(result.rows_scanned),
        status_message = option_string_to_robj(result.status_message),
        gql_status = result.gql_status.as_str()
    ))
}

fn robj_to_optional_u64(value: &Robj, name: &str) -> Result<Option<u64>> {
    if value.is_null() {
        return Ok(None);
    }

    if let Some(value) = value.as_integer() {
        return u64::try_from(value)
            .map(Some)
            .map_err(|_| Error::Other(format!("`{name}` must be non-negative")));
    }

    if let Some(value) = value.as_real() {
        if value.is_finite() && value >= 0.0 && value.fract() == 0.0 {
            let value = value as u128;
            if value <= u64::MAX as u128 {
                return Ok(Some(value as u64));
            }
        }
    }

    Err(Error::Other(format!(
        "`{name}` must be NULL or a non-negative whole-number scalar"
    )))
}

fn scalar_to_i64(value: &Robj, name: &str) -> Result<i64> {
    if let Some(value) = value.as_integer() {
        return Ok(i64::from(value));
    }
    if let Some(value) = value.as_real() {
        if value.is_finite() && value.fract() == 0.0 && value >= i64::MIN as f64 {
            let value = value as i128;
            if value <= i64::MAX as i128 {
                return Ok(value as i64);
            }
        }
    }
    if let Some(value) = value.as_str() {
        return value
            .parse::<i64>()
            .map_err(|_| Error::Other(format!("`{name}` must contain an integer ID")));
    }
    Err(Error::Other(format!("`{name}` must contain integer IDs")))
}

fn robj_to_value(value: &Robj) -> Result<Value> {
    if value.is_null() {
        return Ok(Value::Null);
    }

    if value.inherits("Date") {
        let days = value
            .as_real()
            .ok_or_else(|| Error::Other("Date parameters must be scalar and non-missing".into()))?;
        if !days.is_finite() || days < i32::MIN as f64 || days > i32::MAX as f64 {
            return Ok(Value::Null);
        }
        return Ok(Value::Date(Date::from_days(days as i32)));
    }

    if value.inherits("POSIXct") {
        let seconds = value.as_real().ok_or_else(|| {
            Error::Other("POSIXct parameters must be scalar and non-missing".into())
        })?;
        if !seconds.is_finite() {
            return Ok(Value::Null);
        }
        let micros = (seconds * 1_000_000.0).round();
        if micros < i64::MIN as f64 || micros > i64::MAX as f64 {
            return Err(Error::Other(
                "POSIXct value is outside Grafeo's range".into(),
            ));
        }
        return Ok(Value::Timestamp(Timestamp::from_micros(micros as i64)));
    }

    if value.is_logical() {
        let values = value
            .as_logical_slice()
            .ok_or_else(|| Error::Other("logical parameters must not be empty".into()))?;
        if values.len() == 1 {
            return Ok(if values[0].is_na() {
                Value::Null
            } else {
                Value::Bool(values[0].is_true())
            });
        }
        return Ok(Value::List(
            values
                .iter()
                .map(|value| {
                    if value.is_na() {
                        Value::Null
                    } else {
                        Value::Bool(value.is_true())
                    }
                })
                .collect::<Vec<_>>()
                .into(),
        ));
    }

    if value.is_integer() {
        let values = value
            .as_integer_slice()
            .ok_or_else(|| Error::Other("integer parameters must not be empty".into()))?;
        if values.len() == 1 {
            return Ok(if values[0] == i32::MIN {
                Value::Null
            } else {
                Value::Int64(i64::from(values[0]))
            });
        }
        return Ok(Value::List(
            values
                .iter()
                .map(|value| {
                    if *value == i32::MIN {
                        Value::Null
                    } else {
                        Value::Int64(i64::from(*value))
                    }
                })
                .collect::<Vec<_>>()
                .into(),
        ));
    }

    if value.is_real() {
        let values = value
            .as_real_slice()
            .ok_or_else(|| Error::Other("numeric parameters must not be empty".into()))?;
        if values.len() == 1 {
            return Ok(if values[0].is_nan() {
                Value::Null
            } else {
                Value::Float64(values[0])
            });
        }
        // Grafeo vectors are f32 by design. R users can pass a named list to
        // request a map or an integer vector when exact scalar values matter.
        if values.iter().all(|value| value.is_finite()) {
            return Ok(Value::Vector(
                values
                    .iter()
                    .map(|value| *value as f32)
                    .collect::<Vec<_>>()
                    .into(),
            ));
        }
        return Ok(Value::List(
            values
                .iter()
                .map(|value| {
                    if value.is_nan() {
                        Value::Null
                    } else {
                        Value::Float64(*value)
                    }
                })
                .collect::<Vec<_>>()
                .into(),
        ));
    }

    if value.is_string() {
        let values = value
            .as_str_iter()
            .ok_or_else(|| Error::Other("character parameters must not be empty".into()))?;
        let values: Vec<Value> = values
            .map(|value| {
                if value.is_na() {
                    Value::Null
                } else {
                    Value::String(value.to_string().into())
                }
            })
            .collect();
        return if values.len() == 1 {
            Ok(values.into_iter().next().unwrap_or(Value::Null))
        } else {
            Ok(Value::List(values.into()))
        };
    }

    if value.is_raw() {
        let bytes = value
            .as_raw_slice()
            .ok_or_else(|| Error::Other("raw parameters could not be read".into()))?;
        return Ok(Value::Bytes(bytes.to_vec().into()));
    }

    if let Some(list) = value.as_list() {
        let entries: Vec<(String, Robj)> = list
            .iter()
            .map(|(name, value)| (name.to_string(), value))
            .collect();
        let named = !entries.is_empty() && entries.iter().all(|(name, _)| !name.is_empty());
        if named {
            let mut map = BTreeMap::new();
            for (name, value) in entries {
                map.insert(PropertyKey::new(name), robj_to_value(&value)?);
            }
            return Ok(Value::Map(Arc::new(map)));
        }
        return Ok(Value::List(
            list.values()
                .map(|value| robj_to_value(&value))
                .collect::<Result<Vec<_>>>()?
                .into(),
        ));
    }

    Err(Error::Other(
        "unsupported parameter value; use logical, integer, numeric, character, raw, Date, POSIXct, list, or named list values".into(),
    ))
}

fn robj_to_params(params: &Robj) -> Result<Option<HashMap<String, Value>>> {
    if params.is_null() {
        return Ok(None);
    }
    let list = params
        .as_list()
        .ok_or_else(|| Error::Other("`params` must be NULL or a named list".into()))?;
    let mut result = HashMap::new();
    for (name, value) in list.iter() {
        if name.is_empty() {
            return Err(Error::Other(
                "all query parameters must be named (for example, list(name = 'Alix'))".into(),
            ));
        }
        result.insert(name.to_string(), robj_to_value(&value)?);
    }
    Ok(Some(result))
}

/// Open a Grafeo database handle.
/// @noRd
#[extendr]
fn grafeo_db_open(
    path: Robj,
    wal: bool,
    read_only: bool,
    query_timeout_ms: Robj,
    memory_limit: Robj,
    spill_path: Robj,
) -> Result<ExternalPtr<DbHandle>> {
    let path = robj_to_optional_string(&path)?;
    if read_only && path.is_none() {
        return Err(Error::Other(
            "`read_only = TRUE` requires a persistent `path`".into(),
        ));
    }

    let mut config = if read_only {
        Config::read_only(path.clone().expect("path checked above"))
    } else if let Some(path) = path {
        let mut config = Config::persistent(path).with_storage_format(StorageFormat::SingleFile);
        config.wal_enabled = wal;
        config
    } else {
        Config::in_memory()
    };
    config.wal_enabled = config.path.is_some() && config.wal_enabled;

    if read_only {
        config.access_mode = AccessMode::ReadOnly;
        config.wal_enabled = false;
    }
    if let Some(timeout_ms) = robj_to_optional_u64(&query_timeout_ms, "query_timeout")? {
        config = config.with_query_timeout(Duration::from_millis(timeout_ms));
    }
    if let Some(memory_limit) = robj_to_optional_u64(&memory_limit, "memory_limit")? {
        config.memory_limit = Some(usize::try_from(memory_limit).map_err(|_| {
            Error::Other("`memory_limit` is larger than the platform supports".into())
        })?);
    }
    if !spill_path.is_null() {
        let spill_path = robj_to_optional_string(&spill_path)?.ok_or_else(|| {
            Error::Other("`spill_path` must be NULL or a character scalar".into())
        })?;
        config.spill_path = Some(spill_path.into());
    }

    let db = GrafeoDB::with_config(config).map_err(engine_error)?;
    Ok(ExternalPtr::new(DbHandle::new(db, read_only)))
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
fn grafeo_db_execute_raw(db: ExternalPtr<DbHandle>, query: &str, params: Robj) -> Result<Robj> {
    db.ensure_open()?;
    ensure_write_allowed(db.read_only, query)?;
    let params = robj_to_params(&params)?;
    let result = db
        .inner
        .execute_language(query, "gql", params)
        .map_err(engine_error)?;
    Ok(encode_query_result(result))
}

/// Execute a GQL query directly against the database.
/// @noRd
#[extendr]
fn grafeo_db_query_raw(db: ExternalPtr<DbHandle>, query: &str, params: Robj) -> Result<Robj> {
    grafeo_db_execute_raw(db, query, params)
}

/// Start a transaction on the database.
/// @noRd
#[extendr]
fn grafeo_db_begin_transaction(
    db: ExternalPtr<DbHandle>,
    isolation: &str,
) -> Result<ExternalPtr<TxHandle>> {
    db.ensure_open()?;
    let mut session = db.inner.session();
    let isolation = match isolation.to_ascii_lowercase().as_str() {
        "snapshot" | "snapshot_isolation" => IsolationLevel::SnapshotIsolation,
        "read_committed" | "read-committed" => IsolationLevel::ReadCommitted,
        "serializable" => IsolationLevel::Serializable,
        _ => {
            return Err(Error::Other(
                "`isolation` must be one of 'snapshot', 'read_committed', or 'serializable'".into(),
            ));
        }
    };
    session
        .begin_transaction_with_isolation(isolation)
        .map_err(engine_error)?;
    Ok(ExternalPtr::new(TxHandle::new(
        Arc::clone(&db.inner),
        Arc::clone(&db.closed),
        db.read_only,
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
        node_count = info.node_count.to_string(),
        edge_count = info.edge_count.to_string(),
        is_persistent = info.is_persistent,
        path = option_string_to_robj(info.path.map(|path| path.display().to_string())),
        wal_enabled = info.wal_enabled,
        read_only = db.read_only,
        version = info.version,
        current_graph = option_string_to_robj(db.inner.current_graph())
    )))
}

/// Execute a GQL statement inside a transaction.
/// @noRd
#[extendr]
fn grafeo_tx_execute_raw(tx: ExternalPtr<TxHandle>, query: &str, params: Robj) -> Result<Robj> {
    tx.ensure_active()?;
    ensure_write_allowed(tx.read_only, query)?;
    let result = if let Some(params) = robj_to_params(&params)? {
        tx.session
            .borrow()
            .execute_with_params(query, params)
            .map_err(engine_error)?
    } else {
        tx.session.borrow().execute(query).map_err(engine_error)?
    };
    Ok(encode_query_result(result))
}

/// Execute a GQL query inside a transaction.
/// @noRd
#[extendr]
fn grafeo_tx_query_raw(tx: ExternalPtr<TxHandle>, query: &str, params: Robj) -> Result<Robj> {
    grafeo_tx_execute_raw(tx, query, params)
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

fn row_properties(row: &Robj, skipped: &[&str]) -> Result<Vec<(String, Value)>> {
    let row = row
        .as_list()
        .ok_or_else(|| Error::Other("bulk import rows must be named lists".into()))?;
    let mut properties = Vec::new();
    for (name, value) in row.iter() {
        if name.is_empty() || skipped.iter().any(|skip| *skip == name) {
            continue;
        }
        properties.push((name.to_string(), robj_to_value(&value)?));
    }
    Ok(properties)
}

fn rows_from_robj(rows: &Robj) -> Result<List> {
    rows.as_list()
        .ok_or_else(|| Error::Other("bulk import data must be a list of rows".into()))
}

/// Bulk-create nodes from a list of named row lists in one native call.
/// @noRd
#[extendr]
fn grafeo_db_import_nodes(db: ExternalPtr<DbHandle>, rows: Robj, labels: Robj) -> Result<Robj> {
    db.ensure_open()?;
    if db.read_only {
        return Err(read_only_error());
    }
    let labels = labels
        .as_str_vector()
        .ok_or_else(|| Error::Other("`labels` must be one or more character labels".into()))?;
    if labels.is_empty() || labels.iter().any(|label| label.is_empty()) {
        return Err(Error::Other(
            "`labels` must contain at least one non-empty label".into(),
        ));
    }
    let label_refs: Vec<&str> = labels.to_vec();
    let rows = rows_from_robj(&rows)?;
    let mut session = db.inner.session();
    session.begin_transaction().map_err(engine_error)?;

    let result: Result<Vec<String>> = (|| {
        let mut ids = Vec::with_capacity(rows.len());
        for row in rows.values() {
            let properties = row_properties(&row, &[])?;
            let node_id = session
                .create_node_with_props(
                    &label_refs,
                    properties
                        .iter()
                        .map(|(key, value)| (key.as_str(), value.clone())),
                )
                .map_err(engine_error)?;
            ids.push(node_id.to_string());
        }
        Ok(ids)
    })();

    match result {
        Ok(ids) => {
            session.commit().map_err(engine_error)?;
            let count = ids.len() as f64;
            Ok(Robj::from(list!(ids = ids, count = count)))
        }
        Err(error) => {
            let _ = session.rollback();
            Err(error)
        }
    }
}

/// Bulk-create edges from a list of named row lists in one native call.
/// @noRd
#[extendr]
fn grafeo_db_import_edges(
    db: ExternalPtr<DbHandle>,
    rows: Robj,
    source: &str,
    target: &str,
    edge_type: &str,
) -> Result<Robj> {
    db.ensure_open()?;
    if db.read_only {
        return Err(read_only_error());
    }
    if source.is_empty() || target.is_empty() || edge_type.is_empty() {
        return Err(Error::Other(
            "`source`, `target`, and `type` must be non-empty strings".into(),
        ));
    }
    let rows = rows_from_robj(&rows)?;
    let mut session = db.inner.session();
    session.begin_transaction().map_err(engine_error)?;

    let result: Result<Vec<String>> = (|| {
        let mut ids = Vec::with_capacity(rows.len());
        for row in rows.values() {
            let entries: Vec<(String, Robj)> = row
                .as_list()
                .ok_or_else(|| Error::Other("bulk import rows must be named lists".into()))?
                .iter()
                .map(|(name, value)| (name.to_string(), value))
                .collect();
            let source_value = entries
                .iter()
                .find(|(name, _)| name == source)
                .map(|(_, value)| value.clone())
                .ok_or_else(|| Error::Other(format!("source column `{source}` is missing")))?;
            let target_value = entries
                .iter()
                .find(|(name, _)| name == target)
                .map(|(_, value)| value.clone())
                .ok_or_else(|| Error::Other(format!("target column `{target}` is missing")))?;
            let source_id = u64::try_from(scalar_to_i64(&source_value, source)?)
                .map_err(|_| Error::Other(format!("`{source}` IDs must be non-negative")))?;
            let target_id = u64::try_from(scalar_to_i64(&target_value, target)?)
                .map_err(|_| Error::Other(format!("`{target}` IDs must be non-negative")))?;
            let properties = row_properties(&row, &[source, target])?;
            let edge_id = session
                .create_edge_with_props(
                    NodeId::new(source_id),
                    NodeId::new(target_id),
                    edge_type,
                    properties
                        .iter()
                        .map(|(key, value)| (key.as_str(), value.clone())),
                )
                .map_err(engine_error)?;
            ids.push(edge_id.to_string());
        }
        Ok(ids)
    })();

    match result {
        Ok(ids) => {
            session.commit().map_err(engine_error)?;
            let count = ids.len() as f64;
            Ok(Robj::from(list!(ids = ids, count = count)))
        }
        Err(error) => {
            let _ = session.rollback();
            Err(error)
        }
    }
}

/// Return the linked Grafeo engine version.
/// @noRd
#[extendr]
fn grafeo_engine_version() -> String {
    VERSION.to_string()
}

/// Return the query languages and optional capabilities compiled into the
/// embedded engine.
/// @noRd
#[extendr]
fn grafeo_capabilities_raw() -> Robj {
    let languages = vec!["gql"];

    Robj::from(list!(
        languages = languages,
        lpg = true,
        persistence = true,
        wal = true,
        read_only = true,
        spill = true,
        mmap = true,
        regex = true
    ))
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
    fn grafeo_db_import_nodes;
    fn grafeo_db_import_edges;
    fn grafeo_engine_version;
    fn grafeo_capabilities_raw;
}
