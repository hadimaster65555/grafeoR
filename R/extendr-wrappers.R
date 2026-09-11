# nolint start

NULL

unwrap_extendr_result <- function(value) {
  if (inherits(value, "extendr_error")) {
    detail <- value$value
    message <- if (is.null(detail)) {
      "extendr backend error"
    } else {
      as.character(detail)
    }
    stop(message, call. = FALSE)
  }

  value
}

#' @keywords internal
grafeo_db_open <- function(
    path = NULL,
    wal = TRUE,
    read_only = FALSE,
    query_timeout_ms = NULL,
    memory_limit = NULL,
    spill_path = NULL
) {
  unwrap_extendr_result(.Call(
    wrap__grafeo_db_open,
    path,
    wal,
    read_only,
    query_timeout_ms,
    memory_limit,
    spill_path
  ))
}

#' @keywords internal
grafeo_db_close <- function(db) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_close, db))
}

#' @keywords internal
grafeo_db_execute_raw <- function(db, query, params = list()) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_execute_raw, db, query, params))
}

#' @keywords internal
grafeo_db_query_raw <- function(db, query, params = list()) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_query_raw, db, query, params))
}

#' @keywords internal
grafeo_db_begin_transaction <- function(db, isolation = "snapshot") {
  unwrap_extendr_result(.Call(wrap__grafeo_db_begin_transaction, db, isolation))
}

#' @keywords internal
grafeo_db_info <- function(db) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_info, db))
}

#' @keywords internal
grafeo_tx_execute_raw <- function(tx, query, params = list()) {
  unwrap_extendr_result(.Call(wrap__grafeo_tx_execute_raw, tx, query, params))
}

#' @keywords internal
grafeo_tx_query_raw <- function(tx, query, params = list()) {
  unwrap_extendr_result(.Call(wrap__grafeo_tx_query_raw, tx, query, params))
}

#' @keywords internal
grafeo_tx_commit <- function(tx) {
  unwrap_extendr_result(.Call(wrap__grafeo_tx_commit, tx))
}

#' @keywords internal
grafeo_tx_rollback <- function(tx) {
  unwrap_extendr_result(.Call(wrap__grafeo_tx_rollback, tx))
}

#' @keywords internal
grafeo_db_import_nodes_raw <- function(db, rows, labels) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_import_nodes, db, rows, labels))
}

#' @keywords internal
grafeo_db_import_edges_raw <- function(db, rows, source, target, type) {
  unwrap_extendr_result(.Call(
    wrap__grafeo_db_import_edges,
    db,
    rows,
    source,
    target,
    type
  ))
}

#' @keywords internal
grafeo_engine_version <- function() {
  unwrap_extendr_result(.Call(wrap__grafeo_engine_version))
}

#' @keywords internal
grafeo_capabilities_raw <- function() {
  unwrap_extendr_result(.Call(wrap__grafeo_capabilities_raw))
}

# nolint end
