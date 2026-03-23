na_token <- paste0(intToUtf8(92), "N")

airports_url <- paste0(
  "https://raw.githubusercontent.com/jpatokal/openflights/master/data/",
  "airports.dat"
)
routes_url <- paste0(
  "https://raw.githubusercontent.com/jpatokal/openflights/master/data/",
  "routes.dat"
)

airports <- read.csv(
  airports_url,
  header = FALSE,
  stringsAsFactors = FALSE,
  na.strings = na_token
)
routes <- read.csv(
  routes_url,
  header = FALSE,
  stringsAsFactors = FALSE,
  na.strings = na_token
)

colnames(airports) <- c(
  "airport_id", "name", "city", "country", "iata", "icao",
  "lat", "lng", "altitude", "timezone", "dst", "tz", "type", "source"
)
colnames(routes) <- c(
  "airline", "airline_id", "source_iata", "source_id", "dest_iata",
  "dest_id", "codeshare", "stops", "equipment"
)

airports <- subset(
  airports,
  type == "airport" & !is.na(iata) & nchar(iata) == 3L &
    !is.na(lat) & !is.na(lng)
)
routes <- subset(
  routes,
  !is.na(source_iata) & !is.na(dest_iata) &
    nchar(source_iata) == 3L & nchar(dest_iata) == 3L
)

route_counts <- sort(table(routes$source_iata), decreasing = TRUE)
top_iata <- names(route_counts)[seq_len(20L)]

selected_airports <- airports[
  match(top_iata, airports$iata),
  c("iata", "name", "city", "country", "lat", "lng")
]
selected_airports$snapshot_outbound_routes <- as.integer(route_counts[top_iata])
colnames(selected_airports)[5:6] <- c("latitude", "longitude")

selected_routes <- merge(routes, selected_airports["iata"], by.x = "source_iata", by.y = "iata")
selected_routes <- merge(selected_routes, selected_airports["iata"], by.x = "dest_iata", by.y = "iata")
selected_routes <- unique(
  selected_routes[, c("airline", "source_iata", "dest_iata", "stops", "equipment")]
)
selected_routes <- selected_routes[
  order(selected_routes$source_iata, selected_routes$dest_iata, selected_routes$airline),
]
selected_routes$stops <- ifelse(is.na(selected_routes$stops), 0L, as.integer(selected_routes$stops))
selected_routes$equipment[is.na(selected_routes$equipment)] <- ""
selected_routes$airline[is.na(selected_routes$airline) | !nzchar(selected_routes$airline)] <- "NA"

dir.create("inst/extdata", recursive = TRUE, showWarnings = FALSE)
write.csv(
  selected_airports,
  "inst/extdata/openflights_top20_airports.csv",
  row.names = FALSE,
  na = ""
)
write.csv(
  selected_routes,
  "inst/extdata/openflights_top20_routes.csv",
  row.names = FALSE,
  na = ""
)
