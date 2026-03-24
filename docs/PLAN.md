# grafeoR Implementation Plan

## Summary

Build `grafeoR` as a CRAN-first R package that embeds Grafeo through
Rust using `extendr`/`rextendr`, with an idiomatic R-facing API and a
deliberately small v1 scope:

- Embedded database only
- LPG model only
- GQL only
- R6 wrappers over Rust-backed handles
- Persistent databases implemented as Grafeo single-file storage by
  default

## Public API

- `grafeo_db(path = NULL, in_memory = is.null(path), wal = !is.null(path))`
- `db$execute(query)`
- `db$query(query)`
- `db$begin()`
- `tx$execute(query)`
- `tx$query(query)`
- `tx$commit()`
- `tx$rollback()`
- `db$info()`
- `db$close()`
- [`grafeo_version()`](https://hadimaster65555.github.io/grafeoR/reference/grafeo_version.md)

Result handling:

- `query()` returns a base `data.frame`
- `execute()` returns a `grafeo_result` object with `data`, metrics,
  status, and query metadata
- Complex Grafeo values remain available through list-columns when no
  safe atomic coercion exists

## Implementation

- Use `rextendr` package scaffolding with a Rust static library in
  `src/rust/`
- Bind Grafeo via `extendr` external pointers for database and
  transaction handles
- Depend on `grafeo-engine` with a minimal feature set: `gql`, `wal`,
  `grafeo-file`, `spill`, `mmap`, `regex`
- Enable `extendr-api` `result_condition` support so backend errors
  become classed R errors instead of Rust panics
- Vendor Rust crates into `src/rust/vendor.tar.xz` for offline
  CRAN-style builds
- Expose an idiomatic R6 facade in `R/grafeo.R`
- Add result coercion and print helpers in `R/results.R`
- Add tests in `tests/testthat/`
- Add a quick-start vignette in `vignettes/getting-started.Rmd`

## Validation

- Source install succeeds with vendored Rust dependencies
- Package test suite passes
- Persistent reopen/close flow passes
- `R CMD build` succeeds
- `R CMD check --no-manual grafeoR_0.0.0.9000.tar.gz` completes with
  `Status: OK`

## Assumptions

- Stable Rust toolchain floor is `rustc >= 1.91.1`
- Package metadata still uses placeholder maintainer information and
  should be replaced before publishing
- v1 intentionally excludes RDF, SPARQL, Cypher, GraphQL, Gremlin,
  vector search, server client support, and a low-level public Rust
  mirror API
