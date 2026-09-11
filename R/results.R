#' @keywords internal
new_grafeo_result <- function(raw, query = NULL) {
  columns <- raw$columns %||% character()
  column_types <- raw$column_types %||% character()
  rows <- raw$rows %||% list()
  data <- build_query_frame(rows, columns, column_types)

  structure(
    list(
      data = data,
      columns = columns,
      column_types = column_types,
      execution_time_ms = raw$execution_time_ms,
      rows_scanned = raw$rows_scanned,
      status_message = raw$status_message,
      gql_status = raw$gql_status %||% "00000",
      query = query
    ),
    class = "grafeo_result"
  )
}

build_query_frame <- function(rows, columns, column_types = character()) {
  if (length(columns) == 0L) {
    return(data.frame())
  }

  normalized <- lapply(seq_along(columns), function(i) {
    column <- columns[[i]]
    values <- lapply(rows, function(row) row[[column]])
    coerce_result_column(values, column_types[[i]] %||% "")
  })

  names(normalized) <- columns
  frame <- list2DF(normalized)
  names(frame) <- columns
  frame
}

coerce_result_column <- function(values, column_type = "") {
  count <- length(values)
  non_null <- Filter(Negate(is.null), values)

  if (!length(non_null)) {
    return(typed_missing_column(count, column_type))
  }

  is_scalar <- function(x) {
    is.atomic(x) && !is.object(x) && !is.list(x) && length(x) == 1L
  }

  if (column_type %in% c("BOOL", "BOOLEAN")) {
    out <- rep(NA, count)
    idx <- !vapply(values, is.null, logical(1))
    out[idx] <- vapply(values[idx], function(value) {
      if (is.logical(value)) value[[1L]] else as.logical(value[[1L]])
    }, logical(1))
    return(as.logical(out))
  }

  if (column_type %in% c("INT8", "INT16", "INT32", "INT64", "INTEGER")) {
    idx <- !vapply(values, is.null, logical(1))
    if (all(vapply(values[idx], function(value) {
      is.atomic(value) && !is.object(value) && length(value) == 1L &&
        is.numeric(value) && is.finite(value)
    }, logical(1)))) {
      out <- rep(NA_real_, count)
      out[idx] <- vapply(values[idx], as.numeric, numeric(1))
      return(out)
    }
    out <- rep(NA_character_, count)
    out[idx] <- vapply(values[idx], as.character, character(1))
    return(out)
  }

  if (column_type %in% c("FLOAT32", "FLOAT64", "DOUBLE")) {
    out <- rep(NA_real_, count)
    idx <- !vapply(values, is.null, logical(1))
    out[idx] <- vapply(values[idx], as.numeric, numeric(1))
    return(out)
  }

  if (column_type %in% c("DATE")) {
    out <- rep(NA_character_, count)
    idx <- !vapply(values, is.null, logical(1))
    out[idx] <- vapply(values[idx], as.character, character(1))
    return(as.Date(out))
  }

  if (column_type %in% c("TIMESTAMP", "ZONED DATETIME")) {
    out <- rep(NA_character_, count)
    idx <- !vapply(values, is.null, logical(1))
    out[idx] <- vapply(values[idx], as.character, character(1))
    parsed <- suppressWarnings(as.POSIXct(out, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"))
    if (!anyNA(parsed[!is.na(out)])) {
      return(parsed)
    }
    return(out)
  }

  if (column_type %in% c("STRING", "CHARACTER")) {
    out <- rep(NA_character_, count)
    idx <- !vapply(values, is.null, logical(1))
    out[idx] <- vapply(values[idx], as.character, character(1))
    return(out)
  }

  if (all(vapply(non_null, function(x) is_scalar(x) && is.logical(x), logical(1)))) {
    out <- rep(NA, count)
    idx <- !vapply(values, is.null, logical(1))
    out[idx] <- unlist(values[idx], use.names = FALSE)
    return(as.logical(out))
  }

  if (all(vapply(non_null, function(x) is_scalar(x) && is.numeric(x), logical(1)))) {
    nums <- vapply(non_null, as.numeric, numeric(1))
    idx <- !vapply(values, is.null, logical(1))

    out <- rep(NA_real_, count)
    out[idx] <- unlist(values[idx], use.names = FALSE)
    return(out)
  }

  if (all(vapply(non_null, function(x) is_scalar(x) && is.character(x), logical(1)))) {
    out <- rep(NA_character_, count)
    idx <- !vapply(values, is.null, logical(1))
    out[idx] <- unlist(values[idx], use.names = FALSE)
    return(out)
  }

  values
}

typed_missing_column <- function(count, column_type) {
  if (column_type %in% c("BOOL", "BOOLEAN")) {
    return(rep(NA, count))
  }
  if (column_type %in% c("FLOAT32", "FLOAT64", "DOUBLE")) {
    return(rep(NA_real_, count))
  }
  if (column_type == "DATE") {
    return(as.Date(rep(NA_character_, count)))
  }
  if (column_type %in% c("TIMESTAMP", "ZONED DATETIME")) {
    return(structure(rep(NA_real_, count), class = c("POSIXct", "POSIXt"), tzone = "UTC"))
  }
  if (column_type %in% c("STRING", "CHARACTER", "INT8", "INT16", "INT32", "INT64", "INTEGER")) {
    return(rep(NA_character_, count))
  }
  # Grafeo reports `ANY` for projections whose type cannot be inferred from an
  # empty result. A character column is the least lossy base-R fallback and
  # avoids turning a declared zero-row scalar into an unusable list column.
  rep(NA_character_, count)
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

#' Print a Grafeo query result
#'
#' @param x A `grafeo_result`.
#' @param ... Unused.
#'
#' @return `x`, invisibly.
#' @export
print.grafeo_result <- function(x, ...) {
  cat("<grafeo_result>\n")
  cat("  rows:", nrow(x$data), "\n")
  cat("  columns:", ncol(x$data), "\n")
  cat("  gql_status:", x$gql_status, "\n")

  if (!is.null(x$status_message)) {
    cat("  status:", x$status_message, "\n")
  }

  if (!is.null(x$execution_time_ms)) {
    cat("  execution_time_ms:", format(x$execution_time_ms, trim = TRUE), "\n")
  }

  if (!is.null(x$rows_scanned)) {
    cat("  rows_scanned:", format(x$rows_scanned, trim = TRUE), "\n")
  }

  if (nrow(x$data) > 0L || ncol(x$data) > 0L) {
    print(utils::head(x$data, 10L))
  }

  invisible(x)
}

#' Convert a Grafeo result to a data frame
#'
#' @param x A `grafeo_result`.
#' @param ... Unused.
#'
#' @return A base `data.frame`.
#' @export
as.data.frame.grafeo_result <- function(x, ...) {
  x$data
}
