# Load the bundled OpenFlights sample dataset

`openflights_sample_data()` returns a compact real-world subset of the
OpenFlights airport and route data bundled with `grafeoR`. The sample
keeps the 20 airports with the highest outbound route counts in the
upstream snapshot and the airline route records whose source and
destination are both in that subset.

## Usage

``` r
openflights_sample_data()
```

## Value

A named list with `airports`, `routes`, and `metadata`.

## Details

The data is intended for examples, demos, and smoke tests that exercise
the Grafeo bindings with non-trivial graph data while remaining fully
offline.

## Examples

``` r
sample <- openflights_sample_data()
dim(sample$airports)
#> [1] 20  7
dim(sample$routes)
#> [1] 1129    5
```
