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

load_openflights_sample <- function() {
  sample <- tryCatch(openflights_sample_data(), error = function(...) NULL)
  if (!is.null(sample)) {
    return(sample)
  }

  script_path <- get_script_path()
  if (is.null(script_path)) {
    stop("Could not locate the bundled OpenFlights sample data.", call. = FALSE)
  }

  pkg_root <- normalizePath(
    file.path(dirname(script_path), "..", ".."),
    mustWork = FALSE
  )

  list(
    airports = utils::read.csv(
      file.path(pkg_root, "inst", "extdata", "openflights_top20_airports.csv"),
      stringsAsFactors = FALSE
    ),
    routes = utils::read.csv(
      file.path(pkg_root, "inst", "extdata", "openflights_top20_routes.csv"),
      stringsAsFactors = FALSE
    )
  )
}

gql_string <- function(x) {
  if (is.null(x) || is.na(x)) {
    return("NULL")
  }

  value <- gsub("\\\\", "\\\\\\\\", as.character(x), perl = TRUE)
  value <- gsub("\"", "\\\\\"", value, fixed = TRUE)
  paste0("\"", value, "\"")
}

load_openflights_graph <- function(db, sample) {
  tx <- db$begin()
  on.exit(
    if (tx$is_active()) {
      try(tx$rollback(), silent = TRUE)
    },
    add = TRUE
  )

  airports <- sample$airports
  routes <- sample$routes

  for (i in seq_len(nrow(airports))) {
    row <- airports[i, ]
    tx$execute(sprintf(
      paste0(
        "INSERT (:Airport {",
        "iata: %s, name: %s, city: %s, country: %s, ",
        "lat: %.6f, lng: %.6f, snapshot_outbound_routes: %d",
        "})"
      ),
      gql_string(row$iata),
      gql_string(row$name),
      gql_string(row$city),
      gql_string(row$country),
      row$latitude,
      row$longitude,
      as.integer(row$snapshot_outbound_routes)
    ))
  }

  for (i in seq_len(nrow(routes))) {
    row <- routes[i, ]
    tx$execute(sprintf(
      paste0(
        "MATCH (src:Airport {iata: %s}), (dst:Airport {iata: %s}) ",
        "INSERT (src)-[:ROUTE {airline: %s, stops: %d, equipment: %s}]->(dst)"
      ),
      gql_string(row$source_iata),
      gql_string(row$dest_iata),
      gql_string(row$airline),
      as.integer(row$stops),
      gql_string(row$equipment)
    ))
  }

  tx$commit()
  invisible(db)
}

query_openflights_analysis <- function(db) {
  airports <- db$query(
    paste(
      "MATCH (a:Airport)",
      "RETURN a.iata, a.name, a.city, a.country, a.lat, a.lng,",
      "a.snapshot_outbound_routes",
      "ORDER BY a.snapshot_outbound_routes DESC, a.iata"
    )
  )

  routes <- db$query(
    paste(
      "MATCH (src:Airport)-[r:ROUTE]->(dst:Airport)",
      "RETURN src.iata, src.lat, src.lng, dst.iata, dst.lat, dst.lng, r.airline"
    )
  )

  route_segments <- stats::aggregate(
    routes$r.airline,
    by = list(
      source_iata = routes$src.iata,
      source_lat = routes$src.lat,
      source_lng = routes$src.lng,
      dest_iata = routes$dst.iata,
      dest_lat = routes$dst.lat,
      dest_lng = routes$dst.lng
    ),
    FUN = length
  )
  names(route_segments)[names(route_segments) == "x"] <- "airline_count"
  route_segments <- route_segments[
    order(
      -route_segments$airline_count,
      route_segments$source_iata,
      route_segments$dest_iata
    ),
    ,
  ]

  list(
    airports = airports,
    route_segments = route_segments
  )
}

plot_top_hubs <- function(airports) {
  top_hubs <- airports[seq_len(min(10L, nrow(airports))), , drop = FALSE]
  top_hubs$airport <- factor(
    paste(top_hubs$a.iata, top_hubs$a.city, sep = " - "),
    levels = rev(paste(top_hubs$a.iata, top_hubs$a.city, sep = " - "))
  )

  ggplot2::ggplot(
    top_hubs,
    ggplot2::aes(
      x = airport,
      y = a.snapshot_outbound_routes,
      fill = a.country
    )
  ) +
    ggplot2::geom_col(width = 0.75, color = "white") +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_brewer(palette = "Set2") +
    ggplot2::labs(
      title = "Top OpenFlights Hubs in the Bundled Snapshot",
      subtitle = "20-airport sample packaged with grafeoR",
      x = NULL,
      y = "Snapshot outbound routes",
      fill = "Country"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      legend.position = "bottom"
    )
}

plot_route_map <- function(airports, route_segments) {
  labels <- airports[seq_len(min(10L, nrow(airports))), , drop = FALSE]

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = route_segments,
      ggplot2::aes(
        x = source_lng,
        y = source_lat,
        xend = dest_lng,
        yend = dest_lat,
        linewidth = airline_count,
        alpha = airline_count
      ),
      color = "#0f4c5c",
      lineend = "round"
    ) +
    ggplot2::geom_point(
      data = airports,
      ggplot2::aes(
        x = a.lng,
        y = a.lat,
        size = a.snapshot_outbound_routes
      ),
      shape = 21,
      fill = "#ffbf69",
      color = "#7f5539",
      stroke = 0.4
    ) +
    ggplot2::geom_text(
      data = labels,
      ggplot2::aes(
        x = a.lng,
        y = a.lat,
        label = a.iata
      ),
      size = 3,
      nudge_y = 3,
      check_overlap = TRUE
    ) +
    ggplot2::coord_quickmap() +
    ggplot2::scale_linewidth(range = c(0.2, 1.3), guide = "none") +
    ggplot2::scale_alpha(range = c(0.15, 0.7), guide = "none") +
    ggplot2::scale_size(range = c(2.5, 7), guide = "none") +
    ggplot2::labs(
      title = "Airline Routes Within the Bundled OpenFlights Top-20 Subgraph",
      subtitle = "Segment width reflects the number of airline records between each airport pair",
      x = "Longitude",
      y = "Latitude"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      plot.background = ggplot2::element_rect(fill = "#f8f4ec", color = NA),
      panel.background = ggplot2::element_rect(fill = "#f8f4ec", color = NA)
    )
}

save_openflights_plots <- function(hub_plot, route_plot, output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  hub_path <- file.path(output_dir, "openflights-top-hubs.png")
  route_path <- file.path(output_dir, "openflights-route-map.png")

  ggplot2::ggsave(hub_path, plot = hub_plot, width = 9, height = 6, dpi = 160)
  ggplot2::ggsave(route_path, plot = route_plot, width = 11, height = 6.5, dpi = 160)

  list(
    top_hubs = hub_path,
    route_map = route_path
  )
}

run_openflights_example <- function(output_dir = NULL) {
  load_grafeoR()

  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Install ggplot2 to run the OpenFlights visualization example.", call. = FALSE)
  }

  if (is.null(output_dir)) {
    output_dir <- file.path(
      tempdir(),
      paste0("grafeoR-openflights-", format(Sys.time(), "%Y%m%d-%H%M%S"))
    )
  }

  sample <- load_openflights_sample()
  db <- grafeo_db()
  on.exit(try(db$close(), silent = TRUE), add = TRUE)

  cat("grafeoR version:", grafeo_version(), "\n")
  cat("Airports in sample:", nrow(sample$airports), "\n")
  cat("Routes in sample:", nrow(sample$routes), "\n\n")

  load_openflights_graph(db, sample)

  info <- db$info()
  stopifnot(identical(as.integer(info$node_count), nrow(sample$airports)))
  stopifnot(identical(as.integer(info$edge_count), nrow(sample$routes)))

  analysis <- query_openflights_analysis(db)

  cat("Top hubs from the bundled snapshot:\n")
  print(utils::head(
    analysis$airports[, c("a.iata", "a.city", "a.country", "a.snapshot_outbound_routes")],
    10L
  ))

  cat("\nTop route segments inside the top-20 subgraph:\n")
  print(utils::head(analysis$route_segments, 10L))

  hub_plot <- plot_top_hubs(analysis$airports)
  route_plot <- plot_route_map(analysis$airports, analysis$route_segments)
  plot_paths <- save_openflights_plots(hub_plot, route_plot, output_dir)

  if (interactive()) {
    print(hub_plot)
    print(route_plot)
  }

  cat("\nSaved plots:\n")
  cat(" -", plot_paths$top_hubs, "\n")
  cat(" -", plot_paths$route_map, "\n")
  cat("\nOpenFlights example completed successfully.\n")

  invisible(
    list(
      data = sample,
      analysis = analysis,
      plots = plot_paths
    )
  )
}

if (identical(environment(), globalenv())) {
  run_openflights_example()
}
