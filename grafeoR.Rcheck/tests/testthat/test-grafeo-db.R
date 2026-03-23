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
