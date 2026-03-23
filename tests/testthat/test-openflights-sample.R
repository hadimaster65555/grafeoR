test_that("bundled OpenFlights sample data loads cleanly", {
  sample <- openflights_sample_data()

  expect_named(sample, c("airports", "routes", "metadata"))
  expect_true(is.data.frame(sample$airports))
  expect_true(is.data.frame(sample$routes))
  expect_equal(nrow(sample$airports), 20L)
  expect_equal(nrow(sample$routes), 1129L)
  expect_true(all(c(
    "iata", "name", "city", "country",
    "latitude", "longitude", "snapshot_outbound_routes"
  ) %in% names(sample$airports)))
  expect_true(all(c(
    "airline", "source_iata", "dest_iata", "stops", "equipment"
  ) %in% names(sample$routes)))
  expect_match(sample$metadata$dataset, "OpenFlights")
  expect_true(any(grepl("openflights.org", sample$metadata$source_urls, fixed = TRUE)))
})
