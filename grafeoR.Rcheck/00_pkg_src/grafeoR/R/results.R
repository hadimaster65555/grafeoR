#' @keywords internal
new_grafeo_result <- function(raw, query = NULL) {
  columns <- raw$columns %||% character()
  rows <- raw$rows %||% list()
  data <- build_query_frame(rows, columns)

  structure(
    list(
      data = data,
      columns = columns,
      column_types = raw$column_types %||% character(),
      execution_time_ms = raw$execution_time_ms,
      rows_scanned = raw$rows_scanned,
      status_message = raw$status_message,
      gql_status = raw$gql_status %||% "00000",
      query = query
    ),
    class = "grafeo_result"
  )
}

build_query_frame <- function(rows, columns) {
  if (length(columns) == 0L) {
    return(data.frame())
  }

  normalized <- lapply(columns, function(column) {
    values <- lapply(rows, function(row) row[[column]])
    coerce_result_column(values)
  })

  names(normalized) <- columns
  frame <- list2DF(normalized)
  names(frame) <- columns
  frame
}

coerce_result_column <- function(values) {
  count <- length(values)
  non_null <- Filter(Negate(is.null), values)

  if (!length(non_null)) {
    return(rep(NA, count))
  }

  is_scalar <- function(x) {
    is.atomic(x) && !is.object(x) && !is.list(x) && length(x) == 1L
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

    if (all(abs(nums - trunc(nums)) < .Machine$double.eps^0.5) &&
        any(abs(nums) > (2^53 - 1))) {
      out <- rep(NA_character_, count)
      out[idx] <- vapply(
        values[idx],
        function(x) format(as.numeric(x), scientific = FALSE, trim = TRUE),
        character(1)
      )
      return(out)
    }

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
