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
grafeo_db_open <- function(path = NULL, wal = TRUE) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_open, path, wal))
}

#' @keywords internal
grafeo_db_close <- function(db) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_close, db))
}

#' @keywords internal
grafeo_db_execute_raw <- function(db, query) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_execute_raw, db, query))
}

#' @keywords internal
grafeo_db_query_raw <- function(db, query) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_query_raw, db, query))
}

#' @keywords internal
grafeo_db_begin_transaction <- function(db) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_begin_transaction, db))
}

#' @keywords internal
grafeo_db_info <- function(db) {
  unwrap_extendr_result(.Call(wrap__grafeo_db_info, db))
}

#' @keywords internal
grafeo_tx_execute_raw <- function(tx, query) {
  unwrap_extendr_result(.Call(wrap__grafeo_tx_execute_raw, tx, query))
}

#' @keywords internal
grafeo_tx_query_raw <- function(tx, query) {
  unwrap_extendr_result(.Call(wrap__grafeo_tx_query_raw, tx, query))
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
grafeo_engine_version <- function() {
  unwrap_extendr_result(.Call(wrap__grafeo_engine_version))
}

# nolint end
