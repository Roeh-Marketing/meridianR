# meridianR

An R interface to [Google
Meridian](https://developers.google.com/meridian), a Bayesian Marketing
Mix Modeling (MMM) library. meridianR wraps the Meridian Python package
with [reticulate](https://rstudio.github.io/reticulate/), following the
design of [keras3](https://keras3.posit.co/): faithful bindings to
Meridian’s data, model, and analysis objects, plus an idiomatic R layer
with tidy data in and out, S3
[`print()`](https://rdrr.io/r/base/print.html)/[`summary()`](https://rdrr.io/r/base/summary.html),
and pipe-friendly verbs.

## Installation

Install the development version from GitHub:

``` r

# install.packages("pak")
pak::pak("Roeh-Marketing/meridianR")
```

Then provision the Python side (Meridian and its JAX / TensorFlow stack)
once:

``` r

library(meridianR)
install_meridian()
```

`install_meridian(gpu = TRUE)` installs the CUDA build, and
`install_meridian(meridian_version = "1.7.1")` pins an older supported
release. If no suitable Python (3.11–3.13) is found, one is installed
first (via `uv` when available). If you skip this step, reticulate
provisions an environment automatically on first use.

## Quick start

``` r

library(meridianR)

# 1. Assemble input data from a long-format data frame
input <- as_meridian_input(
  sales,
  kpi            = "conversions",
  time           = "week",
  geo            = "region",
  population     = "population",
  media_spend    = c("tv_spend", "search_spend"),
  media_channels = c("TV", "Search"),
  controls       = "price_index"
)

# 2. Configure priors and the model specification. `conversions` is a
#    non-revenue KPI, so a scale-free contribution prior ("TV drives ~13% of
#    conversions, Search ~6%") is easier to reason about than an ROI prior.
spec <- model_spec(
  max_lag          = 8,
  knots            = 10,
  media_prior_type = "contribution",
  prior            = prior_distribution(contribution_m = prior_beta(c(3, 2), c(20, 30)))
)

# 3. Fit
mmm <- meridian_model(input, spec)
fit(mmm, n_chains = 4, n_adapt = 1000, n_burnin = 500, n_keep = 1000)

summary(mmm)
rhat_summary(mmm)
plot_roi(mmm)
```

See
[`vignette("getting-started")`](https://roeh-marketing.github.io/meridianR/articles/getting-started.md)
and
[`vignette("analysis")`](https://roeh-marketing.github.io/meridianR/articles/analysis.md)
for the full walkthrough, and `scripts/learn_meridianR.R` in the source
repository for a guided tour of every prior (including adstock) with
prior-vs-posterior experiments.

## Choosing the Python environment

Meridian needs Python 3.11–3.13, and
[`install_meridian()`](https://roeh-marketing.github.io/meridianR/reference/install_meridian.md)
provisions it together with tested Meridian releases in the range
**1.7.1 through 2.2.1** in the `r-meridian` virtual environment. It
installs 2.2.1 by default. The boundary versions have passed the
integration suite; intermediate releases are included in the supported
range but are not individually listed in the test matrix yet. You can
choose an exact version in this range with `meridian_version`. When
Meridian is first imported, meridianR warns if the active environment
holds a release outside this window.

meridianR uses **Meridian’s default backend**: JAX from Meridian 2.2
(where TensorFlow is deprecated upstream), TensorFlow before that.
`use_backend("tensorflow")` or `use_backend("jax")` overrides it; call
it before Meridian is first imported.

[`save_model()`](https://roeh-marketing.github.io/meridianR/reference/save_model.md)
writes Meridian’s versioned schema format for `.binpb` / `.txtpb` paths
(readable across Meridian versions) and the legacy pickle format for
`.pkl` paths.

reticulate can only bind **one** Python per R session, and an
interpreter pinned by `RETICULATE_PYTHON` or your IDE takes precedence
over meridianR’s default. If another Python is initialized first you
will see:

    ERROR: The requested version of Python (...) cannot be used, as another version
    of Python (...) has already been initialized.

To fix it, point reticulate at `r-meridian` **before** anything else
touches Python, then restart R:

- In **RStudio**: Tools -\> Global Options -\> Python -\> Select -\>
  Virtual Environments -\> `r-meridian` (or set it per project), then
  restart the session.

- In a **fresh session**, as the first line:

  ``` r

  reticulate::use_virtualenv("r-meridian", required = TRUE)
  library(meridianR)
  ```

meridianR warns at load time when `RETICULATE_PYTHON` points elsewhere.

## Python warnings

Meridian emits warnings through Python’s `warnings` module, which
normally print raw (file path, line number, and all). meridianR reroutes
them so they appear as ordinary R warnings of class
`meridian_python_warning` – cli-formatted and silenceable with
[`suppressWarnings()`](https://rdrr.io/r/base/warning.html). To keep the
raw Python output instead, set
`options(meridianR.reformat_warnings = FALSE)` before first use.

## Status

meridianR is in early development. The current release covers data
loading, model specification, priors, MCMC fitting, and analysis (tidy
metrics and ggplot2 charts). Budget optimization is on the roadmap.

Everything in Meridian remains reachable through the `meridian` module
handle, the low-level escape hatch beneath the wrappers.
