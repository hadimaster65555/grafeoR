# Getting Started with grafeoR

`grafeoR` exposes the embedded Grafeo graph database through an
idiomatic R API. The package opens either an in-memory database for ad
hoc work or a persistent database on disk, while query execution is
handled by Grafeo’s Rust engine.

## Open a database

``` r

library(grafeoR)

db <- grafeo_db()
```

## Insert data

``` r

db$execute("INSERT (:Person {name: 'Alix', age: 30})")
db$execute("INSERT (:Person {name: 'Gus', age: 41})")
```

## Query rows back into R

``` r

people <- db$query("MATCH (p:Person) RETURN p.name, p.age")
people
```

## Use transactions

``` r

tx <- db$begin()
tx$execute("INSERT (:Person {name: 'Transaction Demo'})")
tx$commit()
```

## Inspect metadata

``` r

db$info()
grafeo_version()
```

## Close the database

``` r

db$close()
```
