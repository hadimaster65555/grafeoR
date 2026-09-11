test_that("in-memory database executes and queries data", {
  db <- grafeo_db()
  on.exit(db$close(), add = TRUE)

  result <- db$execute("INSERT (:Person {name: 'Alix', age: 30})")

  expect_s3_class(result, "grafeo_result")
  expect_true(is.data.frame(result$data))

  rows <- db$query("MATCH (p:Person) RETURN p.name, p.age")

  expect_true(is.data.frame(rows))
  expect_identical(names(rows), c("p.name", "p.age"))
  expect_equal(nrow(rows), 1L)
  expect_equal(rows[["p.name"]][[1]], "Alix")
})

test_that("transactions commit and rollback cleanly", {
  db <- grafeo_db()
  on.exit(db$close(), add = TRUE)

  tx <- db$begin()
  tx$execute("INSERT (:Person {name: 'Committed'})")
  tx$commit()

  committed <- db$query("MATCH (p:Person {name: 'Committed'}) RETURN p.name")
  expect_equal(nrow(committed), 1L)

  tx <- db$begin()
  tx$execute("INSERT (:Person {name: 'RolledBack'})")
  tx$rollback()

  rolled_back <- db$query("MATCH (p:Person {name: 'RolledBack'}) RETURN p.name")
  expect_equal(nrow(rolled_back), 0L)
})

test_that("persistent databases reopen with stored data", {
  path <- file.path(
    tempdir(),
    paste0("grafeor-", as.integer(Sys.time()), "-", sample.int(1e6, 1))
  )
  on.exit(unlink(path, recursive = TRUE, force = TRUE), add = TRUE)

  db <- grafeo_db(path = path, in_memory = FALSE)
  db$execute("INSERT (:Person {name: 'Persistent'})")
  db$close()

  reopened <- grafeo_db(path = path, in_memory = FALSE)
  on.exit(reopened$close(), add = TRUE)

  rows <- reopened$query("MATCH (p:Person) RETURN p.name")

  expect_equal(nrow(rows), 1L)
  expect_equal(rows[["p.name"]][[1]], "Persistent")
})

test_that("invalid queries raise classed grafeo errors", {
  db <- grafeo_db()
  on.exit(db$close(), add = TRUE)

  expect_error(
    db$query("THIS IS NOT VALID GQL"),
    class = "grafeo_query_error"
  )
})

test_that("database info and version are available", {
  db <- grafeo_db()
  on.exit(db$close(), add = TRUE)

  info <- db$info()

  expect_true(is.list(info))
  expect_identical(info$graph_model, "LPG")
  expect_true(is.character(grafeo_version()))
  expect_length(grafeo_version(), 1L)
})

test_that("parameterized queries work for databases and transactions", {
  db <- grafeo_db()
  on.exit(db$close(), add = TRUE)

  db$execute(
    "INSERT (:Person {name: $name, age: $age, active: $active})",
    params = list(name = "Param", age = 42L, active = TRUE)
  )
  rows <- db$query(
    "MATCH (p:Person) WHERE p.name = $name RETURN p.name, p.age, p.active",
    params = list(name = "Param")
  )
  expect_equal(rows$p.name, "Param")
  expect_equal(rows$p.age, 42)
  expect_true(rows$p.active)

  tx <- db$begin(isolation = "serializable")
  tx$execute(
    "INSERT (:Person {name: $name})",
    params = list(name = "TxParam")
  )
  tx$commit()
  expect_equal(
    nrow(db$query("MATCH (p:Person {name: 'TxParam'}) RETURN p.name")),
    1L
  )
})

test_that("large integers, typed values, and nested values are preserved", {
  db <- grafeo_db()
  on.exit(db$close(), add = TRUE)

  huge <- db$query("RETURN 9223372036854775807 AS huge")
  expect_identical(huge$huge, "9223372036854775807")

  temporal <- db$query("RETURN DATE '2024-01-02' AS day")
  expect_s3_class(temporal$day, "Date")

  db$execute(
    "INSERT (:Typed {meta: $meta})",
    params = list(meta = list(source = "test", values = c(1L, 2L)))
  )
  nested <- db$query("MATCH (n:Typed) RETURN n.meta")
  expect_equal(nested$n.meta[[1L]]$source, "test")

  empty <- db$query(
    "MATCH (missing:NoSuchLabel) RETURN missing.name AS name"
  )
  expect_equal(nrow(empty), 0L)
  expect_type(empty$name, "character")
})

test_that("bulk import and tabular export round-trip", {
  db <- grafeo_db()
  on.exit(db$close(), add = TRUE)

  node_data <- data.frame(
    key = c("a", "b"),
    name = c("A", "B"),
    score = c(1.5, 2.5),
    stringsAsFactors = FALSE
  )
  nodes <- db$import_nodes(node_data, labels = "Thing", id_col = "key")
  expect_equal(nodes$count, 2L)
  expect_equal(nodes$keys, node_data$key)

  edge_data <- data.frame(
    source = nodes$ids[[1L]],
    target = nodes$ids[[2L]],
    weight = 3L,
    stringsAsFactors = FALSE
  )
  edges <- db$import_edges(edge_data, "source", "target", "LINK")
  expect_equal(edges$count, 1L)
  expect_equal(nrow(db$nodes()), 2L)
  expect_equal(nrow(db$edges()), 1L)
  expect_equal(db$edges()$type, "LINK")
})

test_that("read-only handles, capabilities, and lifecycle helpers work", {
  path <- file.path(tempdir(), paste0("grafeor-read-only-", sample.int(1e6, 1)))
  on.exit(unlink(path, recursive = TRUE, force = TRUE), add = TRUE)

  with_grafeo_db({
    db$execute("INSERT (:Person {name: 'Stored'})")
  }, path = path)

  db <- grafeo_db(path = path, read_only = TRUE)
  on.exit(db$close(), add = TRUE)
  expect_true(db$info()$read_only)
  expect_error(
    db$execute("INSERT (:Person {name: 'Rejected'})"),
    class = "grafeo_storage_error"
  )

  expect_true(isTRUE(grafeo_capabilities()$read_only))
  expect_error(db$begin("not-an-isolation-level"), class = "grafeo_argument_error")
})

test_that("backend errors retain code, query, and retryability", {
  db <- grafeo_db()
  on.exit(db$close(), add = TRUE)

  error <- tryCatch(db$query("THIS IS NOT VALID GQL"), error = identity)
  expect_s3_class(error, "grafeo_query_error")
  expect_true(is.character(error$code) || is.null(error$code))
  expect_identical(error$query, "THIS IS NOT VALID GQL")
  expect_type(error$retryable, "logical")
})
