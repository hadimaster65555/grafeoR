## Test environments

* Local macOS arm64, R 4.5.2, Rust 1.95.0-nightly.
* The package was installed with `R CMD INSTALL --preclean .` using the
  vendored `src/rust/vendor.tar.xz` archive and Cargo offline mode.
* `R CMD check --as-cran` is run against the built source tarball before a
  release submission.

## R CMD check results

`R CMD check --as-cran --no-manual` completed with no package-specific errors.
The local run reports the expected development-snapshot incoming note and one
warning because the host does not provide the optional `checkbashisms` script.
A full `--as-cran` run additionally requires `pdflatex` to render the PDF
manual; the package's code, examples, tests, and vignettes pass independently.

## Downstream dependencies

The package has no reverse dependencies.
