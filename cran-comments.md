## Test environments

* Local macOS arm64, R 4.5.2, Rust 1.95.0-nightly.
* The package was installed with `R CMD INSTALL --preclean .` using the
  vendored `src/rust/vendor.tar.xz` archive and Cargo offline mode.
* `R CMD check --as-cran` was run against the built `grafeoR_0.1.0.tar.gz`
  source package, including the HTML and PDF manuals.
* GitHub Actions run for commit `2892676` passed R release and R-devel checks
  on Ubuntu, macOS, and Windows, plus a dedicated Ubuntu R-devel
  `--as-cran` preflight with the PDF manual and HTML Tidy checks.

## R CMD check results

`R CMD check --as-cran grafeoR_0.1.0.tar.gz` completed with no errors or
warnings. The only NOTE is the expected `New submission` incoming-feasibility
message.

## Downstream dependencies

The package has no reverse dependencies.
