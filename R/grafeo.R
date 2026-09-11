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
#'   databases. Ignored for in-memory and read-only databases.
#' @param read_only Open a persistent database with a shared lock and reject
#'   mutations.
#' @param query_timeout Optional query timeout in milliseconds.
#' @param memory_limit Optional execution/storage memory limit in bytes.
#' @param spill_path Optional directory for spilling query intermediates.
#'
#' @return A `GrafeoDB` R6 object.
#' @export
#'
#' @examples
#' db <- grafeo_db()
#' db$execute("INSERT (:Person {name: 'Alix', age: 30})")
#' db$query("MATCH (p:Person) RETURN p.name, p.age")
#' db$close()
grafeo_db <- function(
    path = NULL,
    in_memory = is.null(path),
    wal = !is.null(path),
    read_only = FALSE,
    query_timeout = NULL,
    memory_limit = NULL,
    spill_path = NULL
) {
  in_memory <- validate_flag(in_memory, "in_memory")
  wal <- validate_flag(wal, "wal")
  read_only <- validate_flag(read_only, "read_only")
  query_timeout <- validate_optional_limit(query_timeout, "query_timeout")
  memory_limit <- validate_optional_limit(memory_limit, "memory_limit")

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
  if (read_only && is.null(path)) {
    grafeo_abort(
      "`read_only = TRUE` requires a persistent `path`.",
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  if (!is.null(spill_path) &&
      (!is.character(spill_path) || length(spill_path) != 1L || is.na(spill_path))) {
    grafeo_abort(
      "`spill_path` must be NULL or a single non-missing character string.",
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }

  raw_ptr <- with_grafeo_errors(
    grafeo_db_open(
      path,
      if (isTRUE(in_memory)) FALSE else wal,
      read_only,
      query_timeout,
      memory_limit,
      spill_path
    )
  )

  GrafeoDB$new(raw_ptr = raw_ptr, read_only = read_only)
}

#' Return the linked Grafeo engine version
#'
#' @return A single character string.
#' @export
grafeo_version <- function() {
  grafeo_engine_version()
}

#' Report the compiled Grafeo capabilities
#'
#' @return A named list describing the compiled query languages and optional
#'   engine features.
#' @export
grafeo_capabilities <- function() {
  grafeo_capabilities_raw()
}

GrafeoDB <- R6Class(
  classname = "GrafeoDB",
  private = list(
    ptr = NULL,
    closed = FALSE,
    read_only = FALSE,
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
    initialize = function(raw_ptr, read_only = FALSE) {
      private$ptr <- raw_ptr
      private$read_only <- isTRUE(read_only)
    },
    execute = function(query, params = list()) {
      private$ensure_open()
      validate_query(query)
      validate_params(params)
      raw <- with_grafeo_errors(
        grafeo_db_execute_raw(private$ptr, query, params),
        query = query
      )
      new_grafeo_result(raw, query = query)
    },
    query = function(query, params = list()) {
      private$ensure_open()
      validate_query(query)
      validate_params(params)
      raw <- with_grafeo_errors(
        grafeo_db_query_raw(private$ptr, query, params),
        query = query
      )
      new_grafeo_result(raw, query = query)$data
    },
    begin = function(isolation = "snapshot") {
      private$ensure_open()
      isolation <- validate_isolation(isolation)
      tx_ptr <- with_grafeo_errors(
        grafeo_db_begin_transaction(private$ptr, isolation)
      )
      GrafeoTx$new(raw_ptr = tx_ptr)
    },
    import_nodes = function(data, labels, id_col = NULL) {
      private$ensure_open()
      validate_import_data(data)
      labels <- validate_labels(labels)
      id_col <- validate_column_name(data, id_col, "id_col", allow_null = TRUE)
      if (!is.null(id_col) && (anyNA(data[[id_col]]) || anyDuplicated(data[[id_col]]))) {
        grafeo_abort(
          sprintf("`%s` must contain unique, non-missing node keys.", id_col),
          classes = c("grafeo_argument_error", "grafeo_error")
        )
      }
      rows <- dataframe_rows(data)
      result <- with_grafeo_errors(
        grafeo_db_import_nodes_raw(private$ptr, rows, labels)
      )
      output <- list(
        ids = as.character(result$ids),
        count = length(result$ids),
        id_col = id_col
      )
      if (!is.null(id_col)) {
        output$keys <- as.character(data[[id_col]])
        names(output$ids) <- output$keys
      }
      output
    },
    import_edges = function(data, source, target, type) {
      private$ensure_open()
      validate_import_data(data)
      source <- validate_column_name(data, source, "source")
      target <- validate_column_name(data, target, "target")
      type <- validate_scalar_character(type, "type")
      rows <- dataframe_rows(data)
      result <- with_grafeo_errors(
        grafeo_db_import_edges_raw(private$ptr, rows, source, target, type)
      )
      list(ids = as.character(result$ids), count = length(result$ids))
    },
    nodes = function() {
      private$ensure_open()
      values <- self$query("MATCH (n) RETURN n")[["n"]]
      flatten_graph_entities(values, "node")
    },
    edges = function() {
      private$ensure_open()
      values <- self$query("MATCH ()-[e]->() RETURN e")[["e"]]
      flatten_graph_entities(values, "edge")
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
          cat("  read_only:", isTRUE(info$read_only), "\n")
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
    execute = function(query, params = list()) {
      private$ensure_active()
      validate_query(query)
      validate_params(params)
      raw <- with_grafeo_errors(
        grafeo_tx_execute_raw(private$ptr, query, params),
        query = query
      )
      new_grafeo_result(raw, query = query)
    },
    query = function(query, params = list()) {
      private$ensure_active()
      validate_query(query)
      validate_params(params)
      raw <- with_grafeo_errors(
        grafeo_tx_query_raw(private$ptr, query, params),
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

validate_optional_limit <- function(x, name) {
  if (is.null(x)) {
    return(NULL)
  }
  if (!is.numeric(x) || length(x) != 1L || is.na(x) ||
      !is.finite(x) || x < 0 || x != floor(x)) {
    grafeo_abort(
      sprintf("`%s` must be NULL or a non-negative whole-number scalar.", name),
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  as.numeric(x)
}

validate_scalar_character <- function(x, name) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    grafeo_abort(
      sprintf("`%s` must be a single non-empty character string.", name),
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  x
}

validate_params <- function(params) {
  if (is.null(params)) {
    return(invisible(TRUE))
  }
  if (!is.list(params)) {
    grafeo_abort(
      "`params` must be NULL or a named list.",
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  param_names <- names(params)
  if (length(params) > 0L &&
      (is.null(param_names) || any(!nzchar(param_names)))) {
    grafeo_abort(
      "All query parameters must be named, for example `list(name = 'Alix')`.",
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  invisible(TRUE)
}

validate_isolation <- function(isolation) {
  isolation <- validate_scalar_character(isolation, "isolation")
  isolation <- tolower(isolation)
  if (isolation %in% c("snapshot", "snapshot_isolation")) {
    return("snapshot")
  }
  if (isolation %in% c("read_committed", "read-committed")) {
    return("read_committed")
  }
  if (identical(isolation, "serializable")) {
    return(isolation)
  }
  grafeo_abort(
    "`isolation` must be one of 'snapshot', 'read_committed', or 'serializable'.",
    classes = c("grafeo_argument_error", "grafeo_error")
  )
}

validate_import_data <- function(data) {
  if (!is.data.frame(data)) {
    grafeo_abort(
      "`data` must be a data.frame.",
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  if (is.null(names(data)) || any(!nzchar(names(data)))) {
    grafeo_abort(
      "All data-frame columns must have non-empty names.",
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  invisible(TRUE)
}

validate_labels <- function(labels) {
  if (!is.character(labels) || !length(labels) || any(is.na(labels)) ||
      any(!nzchar(labels))) {
    grafeo_abort(
      "`labels` must contain one or more non-empty character labels.",
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  labels
}

validate_column_name <- function(data, value, name, allow_null = FALSE) {
  if (allow_null && is.null(value)) {
    return(NULL)
  }
  value <- validate_scalar_character(value, name)
  if (!value %in% names(data)) {
    grafeo_abort(
      sprintf("Column `%s` named by `%s` is not present in `data`.", value, name),
      classes = c("grafeo_argument_error", "grafeo_error")
    )
  }
  value
}

dataframe_rows <- function(data) {
  if (!nrow(data)) {
    return(list())
  }
  unname(lapply(seq_len(nrow(data)), function(i) {
    as.list(data[i, , drop = FALSE])
  }))
}

flatten_graph_entities <- function(values, kind = c("node", "edge")) {
  kind <- match.arg(kind)
  if (is.null(values) || !length(values)) {
    structural <- if (kind == "node") {
      list(id = character(), labels = list())
    } else {
      list(
        id = character(),
        source = character(),
        target = character(),
        type = character()
      )
    }
    return(as.data.frame(structural, stringsAsFactors = FALSE))
  }

  as_entity_list <- function(value) {
    if (is.list(value)) {
      return(value)
    }
    list()
  }
  first_field <- function(entity, candidates) {
    hit <- candidates[candidates %in% names(entity)]
    if (length(hit)) entity[[hit[[1L]]]] else NULL
  }
  reserved <- if (kind == "node") {
    c("_id", "id", "_labels", "labels", "properties")
  } else {
    c("_id", "id", "_source", "source", "_target", "target",
      "_type", "type", "properties")
  }

  parsed <- lapply(values, function(value) {
    entity <- as_entity_list(value)
    props <- entity$properties
    if (!is.list(props)) {
      props <- entity[setdiff(names(entity), reserved)]
    }
    common <- if (kind == "node") {
      list(
        id = as.character(first_field(entity, c("_id", "id")) %||% NA_character_),
        labels = list(first_field(entity, c("_labels", "labels")) %||% character())
      )
    } else {
      list(
        id = as.character(first_field(entity, c("_id", "id")) %||% NA_character_),
        source = as.character(first_field(entity, c("_source", "source")) %||% NA_character_),
        target = as.character(first_field(entity, c("_target", "target")) %||% NA_character_),
        type = as.character(first_field(entity, c("_type", "type")) %||% NA_character_)
      )
    }
    c(common, props)
  })

  property_names <- unique(unlist(lapply(parsed, function(row) {
    setdiff(names(row), names(if (kind == "node") {
      list(id = NULL, labels = NULL)
    } else {
      list(id = NULL, source = NULL, target = NULL, type = NULL)
    }))
  }), use.names = FALSE))
  columns <- if (kind == "node") c("id", "labels") else c("id", "source", "target", "type")
  columns <- c(columns, property_names)
  frame <- lapply(columns, function(column) {
    coerce_result_column(lapply(parsed, function(row) row[[column]]), "")
  })
  names(frame) <- columns
  frame <- list2DF(frame)
  names(frame) <- columns
  frame
}

#' Run an expression with an automatically closed database
#'
#' @param code An expression evaluated with `db` available in the calling
#'   environment.
#' @param path Database path passed to [grafeo_db()].
#' @param ... Additional arguments passed to [grafeo_db()].
#' @return The value of `code`.
#' @export
with_grafeo_db <- function(code, path = NULL, ...) {
  db <- grafeo_db(path = path, ...)
  on.exit(db$close(), add = TRUE)
  eval(substitute(code), envir = list2env(list(db = db), parent = parent.frame()))
}

#' Run an expression in a transaction with rollback on error
#'
#' @param db A [grafeo_db()] handle.
#' @param code An expression to evaluate in the transaction.
#' @param isolation Transaction isolation level.
#' @return The value of `code`, after a successful commit.
#' @export
with_grafeo_transaction <- function(db, code, isolation = "snapshot") {
  tx <- db$begin(isolation = isolation)
  on.exit(
    if (tx$is_active()) try(tx$rollback(), silent = TRUE),
    add = TRUE
  )
  value <- eval(
    substitute(code),
    envir = list2env(list(db = db, tx = tx), parent = parent.frame())
  )
  if (tx$is_active()) tx$commit()
  value
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

grafeo_abort <- function(
    message,
    classes = "grafeo_error",
    query = NULL,
    code = NULL,
    retryable = FALSE,
    backend_message = NULL
) {
  stop(
    structure(
      list(
        message = message,
        call = NULL,
        query = query,
        code = code,
        retryable = isTRUE(retryable),
        backend_message = backend_message
      ),
      class = c(classes, "error", "condition")
    )
  )
}

classify_grafeo_backend_error <- function(message) {
  match <- regmatches(message, regexec(
    "^\\[(GRAFEO-[A-Z][0-9]{3}) retryable=(true|false)\\] (.*)$",
    message,
    perl = TRUE
  ))[[1L]]
  if (!length(match)) {
    return(list(code = NULL, retryable = FALSE, message = message, class = "grafeo_backend_error"))
  }
  code <- match[[2L]]
  retryable <- identical(match[[3L]], "true")
  clean_message <- match[[4L]]
  class <- if (startsWith(code, "GRAFEO-Q001")) {
    "grafeo_query_syntax_error"
  } else if (startsWith(code, "GRAFEO-Q")) {
    "grafeo_query_execution_error"
  } else if (startsWith(code, "GRAFEO-T")) {
    if (grepl("conflict|serialization|deadlock", clean_message, ignore.case = TRUE)) {
      "grafeo_transaction_conflict"
    } else {
      "grafeo_transaction_error"
    }
  } else if (startsWith(code, "GRAFEO-S")) {
    "grafeo_storage_error"
  } else {
    "grafeo_backend_error"
  }
  list(code = code, retryable = retryable, message = clean_message, class = class)
}

with_grafeo_errors <- function(expr, query = NULL) {
  tryCatch(
    expr,
    error = function(err) {
      if (inherits(err, "grafeo_error")) {
        stop(err)
      }

      detail <- classify_grafeo_backend_error(conditionMessage(err))
      classes <- if (is.null(query)) {
        c(detail$class, "grafeo_backend_error", "grafeo_error")
      } else {
        c(detail$class, "grafeo_query_error", "grafeo_error")
      }

      grafeo_abort(
        detail$message,
        classes = unique(classes),
        query = query,
        code = detail$code,
        retryable = detail$retryable,
        backend_message = conditionMessage(err)
      )
    }
  )
}
