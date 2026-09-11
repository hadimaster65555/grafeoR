# Create an embedded Grafeo database handle

`grafeo_db()` opens an embedded Grafeo database backed by the Rust
engine. Use `path = NULL` for an in-memory database, or provide a
filesystem path for a persistent database.

## Usage

``` r
grafeo_db(
  path = NULL,
  in_memory = is.null(path),
  wal = !is.null(path),
  read_only = FALSE,
  query_timeout = NULL,
  memory_limit = NULL,
  spill_path = NULL
)
```

## Arguments

- path:

  A single path string for a persistent database, or `NULL` for an
  in-memory database.

- in_memory:

  Whether to open an in-memory database. Defaults to `is.null(path)`.

- wal:

  Whether write-ahead logging should be enabled for persistent
  databases. Ignored for in-memory and read-only databases.

- read_only:

  Open a persistent database with a shared lock and reject mutations.

- query_timeout:

  Optional query timeout in milliseconds.

- memory_limit:

  Optional execution/storage memory limit in bytes.

- spill_path:

  Optional directory for spilling query intermediates.

## Value

A `GrafeoDB` R6 object.

## Examples

``` r
db <- grafeo_db()
db$execute("INSERT (:Person {name: 'Alix', age: 30})")
#> <grafeo_result>
#>   rows: 1 
#>   columns: 1 
#>   gql_status: 00000 
#>   execution_time_ms: 1.074834
#>   rows_scanned: 1 
#>               _anon_0
#> 1 0, Person, 30, Alix
db$query("MATCH (p:Person) RETURN p.name, p.age")
#>   p.name p.age
#> 1   Alix    30
db$close()
```
