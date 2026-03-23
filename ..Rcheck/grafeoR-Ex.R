pkgname <- "grafeoR"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
library('grafeoR')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("grafeo_db")
### * grafeo_db

flush(stderr()); flush(stdout())

### Name: grafeo_db
### Title: Create an embedded Grafeo database handle
### Aliases: grafeo_db

### ** Examples

db <- grafeo_db()
db$execute("INSERT (:Person {name: 'Alix', age: 30})")
db$query("MATCH (p:Person) RETURN p.name, p.age")
db$close()



### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
