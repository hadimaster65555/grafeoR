# Run an expression in a transaction with rollback on error

Run an expression in a transaction with rollback on error

## Usage

``` r
with_grafeo_transaction(db, code, isolation = "snapshot")
```

## Arguments

- db:

  A
  [`grafeo_db()`](https://hadimaster65555.github.io/grafeoR/reference/grafeo_db.md)
  handle.

- code:

  An expression to evaluate in the transaction.

- isolation:

  Transaction isolation level.

## Value

The value of `code`, after a successful commit.
