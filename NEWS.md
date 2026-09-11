# grafeoR 0.0.0.9000

## New features

* Upgraded the embedded Grafeo engine to 0.5.42 and re-vendored Rust
  dependencies for offline package builds.
* Added named parameter support to database and transaction execution.
* Added transaction-backed node and edge bulk import plus tabular node and
  edge export.
* Added read-only opening, transaction isolation selection, query timeout and
  memory/spill configuration, capabilities reporting, and lifecycle helpers.
* Added structured Grafeo error codes, retryability, and R condition classes.

## Compatibility

* Persistent databases made with Grafeo 0.5.34 or earlier must be recreated
  because the upstream on-disk format changed in Grafeo 0.5.35.
* Grafeo `INT64` values that cannot be represented exactly by an R numeric are
  returned as decimal character strings.
