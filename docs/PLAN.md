# grafeoR Improvement Plan

## Goal

Keep `grafeoR` focused on the embedded LPG/GQL workflow while making it
reliable and idiomatic for R users. Prioritize correctness,
parameterized queries, bulk data movement, and CRAN portability before
adding every upstream Grafeo capability.

## Priority 0: Engine and result correctness

- Upgrade `grafeo-common` and `grafeo-engine` from `0.5.23` to the
  latest validated upstream release, currently `0.5.42`.
- Update the Rust bridge for upstream API changes, including private
  `QueryResult` rows and non-exhaustive `Value` enums.
- Re-vendor dependencies and verify Linux, macOS, and Windows builds.
- Add an explicit persistent-database migration note. Grafeo 0.5.35
  changed the on-disk format and requires databases created by 0.5.34 or
  earlier to be recreated; the current package is based on 0.5.23.
- Preserve `Int64` values exactly. Values outside R’s exact IEEE-754
  range must not be converted through `f64`; use an exact character
  representation by default or optional
  [`bit64::integer64`](https://rdrr.io/pkg/bit64/man/bit64-package.html)
  support.
- Make result-frame construction use `column_types`, including for
  zero-row results. Preserve logical, numeric, character, temporal, raw,
  vector, list, and map values where possible.
- Add regression tests for integer boundaries, `NULL`, typed empty
  results, temporal values, nested values, and persistence reopen.

## Priority 1: R-facing query and data APIs

### Parameterized queries

Add `params = list()` to:

- `db$execute(query, params = list())`
- `db$query(query, params = list())`
- `tx$execute(query, params = list())`
- `tx$query(query, params = list())`

Implement a single R-to-Grafeo value encoder for logical, integer,
double, character, raw, `Date`, `POSIXct`, vectors, lists, and named
maps. Document parameter naming and unsupported values clearly.

### Bulk data-frame integration

Add vectorized operations that avoid one native call per row:

- `db$import_nodes(data, labels, id_col = NULL)`
- `db$import_edges(data, source, target, type)`
- `db$nodes()` and `db$edges()` for tabular export

Use transaction-backed batching and return inserted IDs/counts. Update
the OpenFlights example to use these APIs and retain a smaller
query-based example for teaching GQL.

### Database controls

Add the most useful upstream controls without exposing the full Rust
configuration surface:

- `read_only` database opening with shared-lock semantics.
- `isolation` on `db$begin()`, supporting snapshot, read-committed, and
  serializable modes.
- Query timeout and memory/spill options after the basic API is stable.
- [`grafeo_capabilities()`](https://hadimaster65555.github.io/grafeoR/reference/grafeo_capabilities.md)
  reporting compiled query languages and optional features.

Keep `path = NULL` as the in-memory default; remove redundant
`in_memory = FALSE` from documentation examples while retaining
compatibility for now.

## Priority 1: Errors and lifecycle

- Preserve upstream machine-readable error codes and retryability in R
  conditions.
- Add subclasses such as `grafeo_query_syntax_error`,
  `grafeo_query_execution_error`, `grafeo_transaction_conflict`, and
  `grafeo_storage_error`.
- Keep the original query and backend error code available as condition
  fields.
- Add
  [`with_grafeo_db()`](https://hadimaster65555.github.io/grafeoR/reference/with_grafeo_db.md)
  and
  [`with_grafeo_transaction()`](https://hadimaster65555.github.io/grafeoR/reference/with_grafeo_transaction.md)
  helpers for guaranteed cleanup and rollback.
- Ensure closing a database invalidates or safely coordinates any active
  transactions.

## Priority 2: CRAN and project quality

- Add GitHub Actions checks for Linux, macOS, and Windows, including R
  release/devel and the required Rust toolchain.
- Test offline compilation from the vendored archive and check that the
  linked Grafeo version matches the lockfile.
- Add `^docs$` and `^PLAN\\.md$` to `.Rbuildignore`; the current source
  tarball is slightly above CRAN’s preferred 10 MB limit largely because
  generated documentation is included.
- Keep vendored Rust source, but add an `inst/COPYRIGHTS` or equivalent
  third-party license inventory.
- Add `NEWS.md`, `BugReports`, `cran-comments.md`, and a `CITATION` file
  before CRAN submission.
- Run `R CMD check --as-cran` on the built tarball and verify that
  examples remain short and offline.

## Later milestones

1.  Add Cypher support behind a language argument once the LPG/GQL API
    is stable.
2.  Add optional `igraph`/`tidygraph` conversion helpers for R graph
    workflows.
3.  Add vector and text search for GraphRAG and recommendation use
    cases.
4.  Add chunked query results after Grafeo’s streaming API is promoted
    beyond experimental status.
5.  Treat RDF/SPARQL as a separate milestone because it introduces a
    second graph model and larger feature/build requirements.

Do not enable all upstream languages, RDF, vector search, and server
functionality in one release. Keep the first public release small enough
to build and test reliably across CRAN platforms.

## Acceptance tests

- [`grafeo_version()`](https://hadimaster65555.github.io/grafeoR/reference/grafeo_version.md)
  reports the upgraded engine version.
- Existing in-memory, persistent, transaction, and OpenFlights tests
  pass.
- A query returning `9223372036854775807` round-trips exactly.
- Zero-row results retain declared column types.
- Parameterized queries work identically for database and transaction
  handles.
- Bulk node/edge import round-trips through tabular export.
- Read-only databases reject mutations and allow concurrent readers.
- Transaction isolation selection is validated and surfaced in errors.
- Query/storage errors expose stable classes, codes, and retryability.
- `R CMD check --as-cran` passes on all supported platforms.

## References

- Grafeo repository: <https://github.com/GrafeoDB/grafeo>
- Grafeo API reference: <https://grafeo.dev/api/>
- Grafeo Python database API: <https://grafeo.dev/api/python/database/>
- Grafeo release history: <https://github.com/GrafeoDB/grafeo/releases>
- CRAN Repository Policy:
  <https://cran.r-project.org/web/packages/policies.html>
