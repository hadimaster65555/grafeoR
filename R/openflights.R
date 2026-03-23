#' Load the bundled OpenFlights sample dataset
#'
#' `openflights_sample_data()` returns a compact real-world subset of the
#' OpenFlights airport and route data bundled with `grafeoR`. The sample keeps
#' the 20 airports with the highest outbound route counts in the upstream
#' snapshot and the airline route records whose source and destination are both
#' in that subset.
#'
#' The data is intended for examples, demos, and smoke tests that exercise the
#' Grafeo bindings with non-trivial graph data while remaining fully offline.
#'
#' @return A named list with `airports`, `routes`, and `metadata`.
#' @export
#'
#' @examples
#' sample <- openflights_sample_data()
#' dim(sample$airports)
#' dim(sample$routes)
openflights_sample_data <- function() {
  airports_path <- system.file(
    "extdata",
    "openflights_top20_airports.csv",
    package = "grafeoR"
  )
  routes_path <- system.file(
    "extdata",
    "openflights_top20_routes.csv",
    package = "grafeoR"
  )

  if (!nzchar(airports_path) || !nzchar(routes_path)) {
    grafeo_abort(
      "Bundled OpenFlights sample files were not found.",
      classes = c("grafeo_io_error", "grafeo_error")
    )
  }

  list(
    airports = utils::read.csv(airports_path, stringsAsFactors = FALSE),
    routes = utils::read.csv(routes_path, stringsAsFactors = FALSE),
    metadata = list(
      dataset = "OpenFlights top-20 airport subset",
      source_urls = c(
        "https://openflights.org/data.php",
        "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat",
        "https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat"
      ),
      license = paste(
        "Open Database License (ODbL) v1.0 and",
        "Database Contents License (DbCL) v1.0"
      ),
      note = paste(
        "The bundled sample contains 20 airports with the highest outbound",
        "route counts in the upstream snapshot and 1,129 airline route",
        "records whose endpoints are both in that subset."
      )
    )
  )
}
