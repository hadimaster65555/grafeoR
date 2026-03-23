#!/usr/bin/env Rscript

get_script_path <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (!length(file_arg)) {
    return(NULL)
  }

  normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = FALSE)
}

load_grafeoR <- function() {
  if (requireNamespace("grafeoR", quietly = TRUE)) {
    suppressPackageStartupMessages(library(grafeoR))
    return(invisible(TRUE))
  }

  script_path <- get_script_path()
  if (is.null(script_path)) {
    stop("Could not locate the example script path.", call. = FALSE)
  }

  pkg_root <- normalizePath(
    file.path(dirname(script_path), "..", ".."),
    mustWork = FALSE
  )

  if (!file.exists(file.path(pkg_root, "DESCRIPTION"))) {
    stop(
      "grafeoR is not installed and the package root could not be inferred.",
      call. = FALSE
    )
  }

  if (!requireNamespace("pkgload", quietly = TRUE)) {
    stop(
      "Install grafeoR first, or install pkgload to run this example from the source tree.",
      call. = FALSE
    )
  }

  pkgload::load_all(pkg_root, export_all = FALSE, helpers = FALSE, quiet = TRUE)
  invisible(TRUE)
}

run_basic_example <- function() {
  load_grafeoR()

  cat("grafeoR version:", grafeo_version(), "\n\n")

  cat("== In-memory database ==\n")
  db <- grafeo_db()
  on.exit(try(db$close(), silent = TRUE), add = TRUE)

  db$execute("INSERT (:Person {name: 'Alix', age: 30})")
  db$execute("INSERT (:Person {name: 'Gus', age: 41})")

  people <- db$query("MATCH (p:Person) RETURN p.name, p.age")
  print(people)

  stopifnot(nrow(people) == 2L)
  stopifnot(all(c("p.name", "p.age") %in% names(people)))

  cat("\n== Transactions ==\n")
  tx <- db$begin()
  tx$execute("INSERT (:Person {name: 'Committed'})")
  tx$commit()

  committed <- db$query("MATCH (p:Person {name: 'Committed'}) RETURN p.name")
  print(committed)
  stopifnot(nrow(committed) == 1L)

  tx <- db$begin()
  tx$execute("INSERT (:Person {name: 'RolledBack'})")
  tx$rollback()

  rolled_back <- db$query("MATCH (p:Person {name: 'RolledBack'}) RETURN p.name")
  print(rolled_back)
  stopifnot(nrow(rolled_back) == 0L)

  db$close()

  cat("\n== Persistent database ==\n")
  db_path <- file.path(
    tempdir(),
    paste0("grafeo-basic-example-", as.integer(Sys.time()), ".grafeo")
  )
  wal_path <- paste0(db_path, ".wal")
  on.exit(unlink(db_path, recursive = TRUE, force = TRUE), add = TRUE)
  on.exit(unlink(wal_path, recursive = TRUE, force = TRUE), add = TRUE)

  persistent <- grafeo_db(path = db_path, in_memory = FALSE)
  persistent$execute("INSERT (:Person {name: 'Persistent'})")
  persistent$close()

  reopened <- grafeo_db(path = db_path, in_memory = FALSE)
  on.exit(try(reopened$close(), silent = TRUE), add = TRUE)

  persisted <- reopened$query("MATCH (p:Person) RETURN p.name")
  print(persisted)

  stopifnot(nrow(persisted) == 1L)
  stopifnot(identical(persisted[["p.name"]][[1L]], "Persistent"))

  reopened$close()

  cat("\nBasic grafeoR example completed successfully.\n")
}

if (identical(environment(), globalenv())) {
  run_basic_example()
}
