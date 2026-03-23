#' Create an embedded Grafeo database handle
#'
#' `grafeo_db()` opens an embedded Grafeo database backed by the Rust engine.
#' Use `path = NULL` for an in-memory database, or provide a filesystem path for
#' a persistent database.
#'
#' @param path A single path string for a persistent database, or `NULL` for an
#'   in-memory database.
#' @param in_memory Whether to open an in-memory database. Defaults to
#'   `is.null(path)`.
#' @param wal Whether write-ahead logging should be enabled for persistent
#'   databases. Ignored for in-memory databases.
#'
#' @return A `GrafeoDB` R6 object.
#' @export
#'
#' @examples
#' db <- grafeo_db()
#' db$execute("INSERT (:Person {name: 'Alix', age: 30})")
#' db$query("MATCH (p:Person) RETURN p.name, p.age")
#' db$close()
grafeo_db <- function(path = NULL, in_memory = is.null(path), wal = !is.null(path)) {
  in_memory <- validate_flag(in_memory, "in_memory")
  wal <- validate_flag(wal, "wal")

  if (is.null(path)) {
    if (!in_memory) {
      grafeo_abort(
        "`path` is NULL, so `in_memory` must be TRUE.",
        classes = c("grafeo_argument_error", "grafeo_error")
      )
    }
  } else {
    if (!is.character(path) || length(path) != 1L || is.na(path)) {
      grafeo_abort(
        "`path` must be NULL or a single non-missing character string.",
        classes = c("grafeo_argument_error", "grafeo_error")
      )
    }
    if (in_memory) {
      grafeo_abort(
        "A persistent `path` cannot be combined with `in_memory = TRUE`.",
        classes = c("grafeo_argument_error", "grafeo_error")
      )
    }
  }

  raw_ptr <- with_grafeo_errors(
    grafeo_db_open(path, if (isTRUE(in_memory)) FALSE else wal)
  )

  GrafeoDB$new(raw_ptr = raw_ptr)
}

#' Return the linked Grafeo engine version
#'
#' @return A single character string.
#' @export
grafeo_version <- function() {
  grafeo_engine_version()
}

GrafeoDB <- R6Class(
  classname = "GrafeoDB",
  private = list(
    ptr = NULL,
    closed = FALSE,
    ensure_open = function() {
      if (isTRUE(private$closed) || is.null(private$ptr)) {
        grafeo_abort(
          "Grafeo database handle is closed.",
          classes = c("grafeo_state_error", "grafeo_error")
        )
      }
      invisible(TRUE)
    },
    finalize = function() {
      if (!isTRUE(private$closed) && !is.null(private$ptr)) {
        try(grafeo_db_close(private$ptr), silent = TRUE)
      }
      private$closed <- TRUE
      private$ptr <- NULL
    }
  ),
  public = list(
    initialize = function(raw_ptr) {
      private$ptr <- raw_ptr
    },
    execute = function(query) {
      private$ensure_open()
      validate_query(query)
      raw <- with_grafeo_errors(
        grafeo_db_execute_raw(private$ptr, query),
        query = query
      )
      new_grafeo_result(raw, query = query)
    },
    query = function(query) {
      private$ensure_open()
      validate_query(query)
      raw <- with_grafeo_errors(
        grafeo_db_query_raw(private$ptr, query),
        query = query
      )
      new_grafeo_result(raw, query = query)$data
    },
    begin = function() {
      private$ensure_open()
      tx_ptr <- with_grafeo_errors(grafeo_db_begin_transaction(private$ptr))
      GrafeoTx$new(raw_ptr = tx_ptr)
    },
    info = function() {
      private$ensure_open()
      with_grafeo_errors(grafeo_db_info(private$ptr))
    },
    close = function() {
      if (!isTRUE(private$closed) && !is.null(private$ptr)) {
        with_grafeo_errors(grafeo_db_close(private$ptr))
        private$closed <- TRUE
        private$ptr <- NULL
      }
      invisible(self)
    },
    is_closed = function() {
      isTRUE(private$closed)
    },
    print = function(...) {
      cat("<GrafeoDB>\n")
      cat("  state:", if (isTRUE(private$closed)) "closed" else "open", "\n")

      if (!isTRUE(private$closed)) {
        info <- try(self$info(), silent = TRUE)
        if (!inherits(info, "try-error")) {
          cat("  mode:", info$graph_model, "\n")
          cat("  nodes:", format(info$node_count, trim = TRUE), "\n")
          cat("  edges:", format(info$edge_count, trim = TRUE), "\n")
          cat("  persistent:", info$is_persistent, "\n")
          if (!is.null(info$path)) {
            cat("  path:", info$path, "\n")
          }
        }
      }

      invisible(self)
    },
    summary = function(...) {
      self$info()
    }
  )
)

GrafeoTx <- R6Class(
  classname = "GrafeoTx",
  private = list(
    ptr = NULL,
    active = TRUE,
    ensure_active = function() {
      if (!isTRUE(private$active) || is.null(private$ptr)) {
        grafeo_abort(
          "Grafeo transaction is no longer active.",
          classes = c("grafeo_transaction_error", "grafeo_error")
        )
      }
      invisible(TRUE)
    },
    finalize = function() {
      if (isTRUE(private$active) && !is.null(private$ptr)) {
        try(grafeo_tx_rollback(private$ptr), silent = TRUE)
      }
      private$active <- FALSE
      private$ptr <- NULL
    }
  ),
  public = list(
    initialize = function(raw_ptr) {
      private$ptr <- raw_ptr
    },
    execute = function(query) {
      private$ensure_active()
      validate_query(query)
      raw <- with_grafeo_errors(
        grafeo_tx_execute_raw(private$ptr, query),
        query = query
      )
      new_grafeo_result(raw, query = query)
    },
    query = function(query) {
      private$ensure_active()
      validate_query(query)
      raw <- with_grafeo_errors(
        grafeo_tx_query_raw(private$ptr, query),
        query = query
      )
      new_grafeo_result(raw, query = query)$data
    },
    commit = function() {
      private$ensure_active()
      with_grafeo_errors(grafeo_tx_commit(private$ptr))
      private$active <- FALSE
      private$ptr <- NULL
      invisible(self)
    },
    rollback = function() {
      private$ensure_active()
      with_grafeo_errors(grafeo_tx_rollback(private$ptr))
      private$active <- FALSE
      private$ptr <- NULL
      invisible(self)
    },
    is_active = function() {
      isTRUE(private$active)
    },
    print = function(...) {
      cat("<GrafeoTx>\n")
      cat("  active:", isTRUE(private$active), "\n")
      invisible(self)
    }
  )
)

validate_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    grafeo_abort(
      sprintf("`%s` must be a single TRUE or FALSE value.", name),
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  x
}

validate_query <- function(query) {
  if (!is.character(query) || length(query) != 1L || is.na(query) || !nzchar(query)) {
    grafeo_abort(
      "`query` must be a single non-empty character string.",
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  invisible(TRUE)
}

grafeo_abort <- function(message, classes = "grafeo_error", query = NULL) {
  stop(
    structure(
      list(message = message, call = NULL, query = query),
      class = c(classes, "error", "condition")
    )
  )
}

with_grafeo_errors <- function(expr, query = NULL) {
  tryCatch(
    expr,
    error = function(err) {
      if (inherits(err, "grafeo_error")) {
        stop(err)
      }

      classes <- if (is.null(query)) {
        c("grafeo_backend_error", "grafeo_error")
      } else {
        c("grafeo_query_error", "grafeo_error")
      }

      grafeo_abort(conditionMessage(err), classes = classes, query = query)
    }
  )
}
