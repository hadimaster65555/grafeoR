## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----eval = FALSE-------------------------------------------------------------
# library(grafeoR)
# 
# db <- grafeo_db()

## ----eval = FALSE-------------------------------------------------------------
# db$execute("INSERT (:Person {name: 'Alix', age: 30})")
# db$execute("INSERT (:Person {name: 'Gus', age: 41})")

## ----eval = FALSE-------------------------------------------------------------
# people <- db$query("MATCH (p:Person) RETURN p.name, p.age")
# people

## ----eval = FALSE-------------------------------------------------------------
# tx <- db$begin()
# tx$execute("INSERT (:Person {name: 'Transaction Demo'})")
# tx$commit()

## ----eval = FALSE-------------------------------------------------------------
# db$info()
# grafeo_version()

## ----eval = FALSE-------------------------------------------------------------
# db$close()

