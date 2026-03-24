# grafeoR

`grafeoR` provides R bindings for the embedded [Grafeo](https://grafeo.dev/) graph database, implemented in Rust with `extendr` and `rextendr`.

Current package scope:

- embedded Grafeo database handles
- in-memory and persistent databases
- GQL execution and query results as base `data.frame`s
- ACID-style transaction handles
- bundled real-world OpenFlights sample data
- a visualization example built with `ggplot2`

The package is currently focused on the embedded LPG/GQL workflow. It does not yet expose Grafeo server features, RDF/SPARQL support, or higher-level graph analysis helpers.

## Status

The current development snapshot has been validated locally with:

- `R CMD INSTALL . -l /tmp/grafeoR-lib`
- `R_LIBS=/tmp/grafeoR-lib Rscript inst/examples/openflights-example.R`
- `R CMD build .`
- `R CMD check --no-manual grafeoR_0.0.0.9000.tar.gz`

Latest local package check result: `Status: OK`.

## Requirements

- R >= 4.2
- Rust stable >= 1.91.1
- Cargo

`ggplot2` is only needed for the visualization example and vignette, not for the core database API.

## Install

Install `remotes` if needed, then install directly from GitHub:

```r
install.packages("remotes")
remotes::install_github("hadimaster65555/grafeoR")
```

Or install into a custom library:

```r
install.packages("remotes")
remotes::install_github("hadimaster65555/grafeoR", lib = "/path/to/R/library")
```

## Quick Start

```r
library(grafeoR)

db <- grafeo_db()

db$execute("INSERT (:Person {name: 'Alix', age: 30})")
db$execute("INSERT (:Person {name: 'Gus', age: 41})")

people <- db$query("MATCH (p:Person) RETURN p.name, p.age")
people

tx <- db$begin()
tx$execute("INSERT (:Person {name: 'Committed'})")
tx$commit()

db$info()
grafeo_version()

db$close()
```

## Real-World Example: OpenFlights

The package bundles a compact OpenFlights subset for offline demos and smoke tests:

- 20 airports with the highest outbound route counts in the upstream snapshot
- 1,129 airline route records whose endpoints are both inside that 20-airport subset

Load the bundled data directly in R:

```r
library(grafeoR)

sample <- openflights_sample_data()

dim(sample$airports)
dim(sample$routes)
sample$metadata
```

Run the full real-world example:

```bash
Rscript inst/examples/openflights-example.R
```

That script:

- loads the bundled OpenFlights sample into an in-memory Grafeo database
- inserts airports as nodes and routes as edges
- queries airport and route data back into R
- saves `openflights-top-hubs.png` and `openflights-route-map.png`

## Vignettes And Examples

Vignettes:

- [Getting Started](vignettes/getting-started.Rmd)
- [OpenFlights Analysis](vignettes/openflights-analysis.Rmd)

Runnable examples:

- [Basic example](inst/examples/basic-example.R)
- [OpenFlights example](inst/examples/openflights-example.R)

## API Surface

User-facing functions:

- `grafeo_db()`
- `grafeo_version()`
- `openflights_sample_data()`

`grafeo_db()` returns an R6 database handle with:

- `db$execute(query)`
- `db$query(query)`
- `db$begin()`
- `db$info()`
- `db$close()`

Transactions use an R6 handle with:

- `tx$execute(query)`
- `tx$query(query)`
- `tx$commit()`
- `tx$rollback()`

## Example: Persistent Database

```r
library(grafeoR)

db <- grafeo_db(path = "example.grafeo", in_memory = FALSE)
db$execute("INSERT (:Person {name: 'Persistent'})")
db$close()

db <- grafeo_db(path = "example.grafeo", in_memory = FALSE)
db$query("MATCH (p:Person) RETURN p.name")
db$close()
```

## OpenFlights Attribution

The bundled sample data is derived from OpenFlights:

- https://openflights.org/data.php
- https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat
- https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat

The bundled attribution note is in [inst/extdata/openflights-README.md](inst/extdata/openflights-README.md).

OpenFlights states that the Airport, Airline, Plane and Route databases are made available under the Open Database License (ODbL) v1.0, with individual contents under the Database Contents License (DbCL) v1.0.

## Upstream Grafeo

- Grafeo GitHub: https://github.com/GrafeoDB/grafeo
- Grafeo docs: https://grafeo.dev/
