# Run an expression with an automatically closed database

Run an expression with an automatically closed database

## Usage

``` r
with_grafeo_db(code, path = NULL, ...)
```

## Arguments

- code:

  An expression evaluated with `db` available in the calling
  environment.

- path:

  Database path passed to
  [`grafeo_db()`](https://hadimaster65555.github.io/grafeoR/reference/grafeo_db.md).

- ...:

  Additional arguments passed to
  [`grafeo_db()`](https://hadimaster65555.github.io/grafeoR/reference/grafeo_db.md).

## Value

The value of `code`.
