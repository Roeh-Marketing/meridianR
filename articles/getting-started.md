# Getting started with meridianR

`meridianR` is an R interface to [Google
Meridian](https://developers.google.com/meridian), a Bayesian Marketing
Mix Modeling (MMM) library. It wraps the Meridian Python package with
[reticulate](https://rstudio.github.io/reticulate/), pairing faithful
bindings to Meridian’s objects with an idiomatic R layer.

## Installation

Meridian runs on Python (JAX or TensorFlow, with TensorFlow
Probability). Install it once into a persistent `r-meridian`
environment:

``` r

meridianR::install_meridian()
```

This installs the newest tested Meridian release (2.2.1); any release
from 1.7.1 to 2.2.1 can be chosen with `meridian_version`. If no Python
3.11–3.13 is available, one is installed first. Use
`install_meridian(gpu = TRUE)` for the CUDA build. If you skip this
step, `meridianR` still works: reticulate provisions an environment
automatically the first time you use a Meridian function.

In each new session, bind that environment before anything else touches
Python, then load the package:

``` r

reticulate::use_virtualenv("r-meridian", required = TRUE)
library(meridianR)
meridian_version()
```

meridianR uses Meridian’s default compute backend: JAX from Meridian 2.2
(where TensorFlow is deprecated), TensorFlow before that. Call
`use_backend("tensorflow")` or `use_backend("jax")` before first use to
choose one explicitly.

## Assemble input data

Meridian expects long-format data: one row per geo-by-time, with columns
for the KPI, population, media spend, and any controls.
[`as_meridian_input()`](https://roeh-marketing.github.io/meridianR/reference/as_meridian_input.md)
turns such a data frame into a Meridian `InputData` object.

``` r

data("sales")

input <- as_meridian_input(
  sales,
  kpi            = "conversions",
  time           = "week",
  geo            = "region",
  population     = "population",
  media_spend    = c("tv_spend", "search_spend"),
  media          = c("tv_impressions", "search_clicks"),
  media_channels = c("TV", "Search"),
  controls       = "price_index"
)
input
```

If you only have spend (no impressions), omit `media` and spend is used
as the media metric. For a national (single-geo) model, pass
`national = TRUE`.

For step-by-step control, use the fluent builder instead:

``` r

input <- input_data_builder("non_revenue", geo = "region", time = "week") |>
  with_kpi(sales, kpi_col = "conversions") |>
  with_population(sales) |>
  with_media(sales,
    media_cols       = c("tv_impressions", "search_clicks"),
    media_spend_cols = c("tv_spend", "search_spend"),
    media_channels   = c("TV", "Search")) |>
  build_input_data()
```

## Configure priors and the model specification

[`model_spec()`](https://roeh-marketing.github.io/meridianR/reference/model_spec.md)
controls the adstock/lag, saturation, and priors. Meridian’s defaults
are well chosen, so a minimal spec is often all you need:

``` r

spec <- model_spec(max_lag = 8, media_effects_dist = "log_normal")
spec
```

**Priors and KPI scale.** `conversions` is a non-revenue KPI and we did
not supply `revenue_per_kpi`, so Meridian places a prior on each
channel’s *total media contribution* by default – no per-channel
calibration needed. You can override priors with
[`prior_distribution()`](https://roeh-marketing.github.io/meridianR/reference/prior_distribution.md)
and the `prior_*()` constructors, but they must match your KPI’s scale.
In particular, an ROI prior such as `prior_lognormal(0.2, 0.9)` (median
ROI ~ 1.2) describes a **revenue** KPI, where ROI is dollars per dollar.
For a conversions KPI, ROI is *conversions* per dollar – typically far
below 1 – so that prior would be off by orders of magnitude and
massively over-credit media. Either keep the default, supply
`revenue_per_kpi` so ROI is dollar-based, or customize a scale-free
prior such as the adstock decay rate `alpha_m` (which always lives on
`[0, 1]`):

``` r

model_spec(
  max_lag = 8,
  prior   = prior_distribution(alpha_m = prior_beta(3, 3))
)
```

For a non-revenue KPI, the most natural informative prior is usually on
each channel’s **share of the KPI**. Switch the prior family with
`media_prior_type` and supply `contribution_m` (one value per channel,
in channel order):

``` r

model_spec(
  max_lag          = 8,
  media_prior_type = "contribution",
  prior            = prior_distribution(contribution_m = prior_beta(c(3, 2), c(20, 30)))
)
```

The other choices are `"roi"` (the default, `roi_m`), `"mroi"`
(`mroi_m`), and `"coefficient"` (`beta_m`). Adstock is controlled by
`max_lag`, the `adstock_decay_spec` (`"geometric"` or `"binomial"`, or a
named list per channel), and the `alpha_m` prior.

**Baseline knots.** For a geo model, Meridian’s default is one baseline
knot per time period (104 here), which is very flexible and can converge
slowly. A smaller number, e.g. `model_spec(knots = 10)`, or automatic
knot selection with `model_spec(enable_aks = TRUE)` often fits faster
and mixes better. Check
[`rhat_summary()`](https://roeh-marketing.github.io/meridianR/reference/rhat_summary.md)
after fitting.

## Fit the model

Create the model, then draw from the prior and posterior.
[`fit()`](https://generics.r-lib.org/reference/fit.html) does both:

``` r

mmm <- meridian_model(input, spec)

fit(mmm, n_chains = 7, n_adapt = 500, n_burnin = 500, n_keep = 1000)

mmm
summary(mmm)
```

Sampling **modifies the model in place** (draws are stored on the
model’s ArviZ `inference_data`), so
[`sample_prior()`](https://roeh-marketing.github.io/meridianR/reference/sample_prior.md),
[`sample_posterior()`](https://roeh-marketing.github.io/meridianR/reference/sample_prior.md),
and [`fit()`](https://generics.r-lib.org/reference/fit.html) all return
the same model object.

## Save and reload

``` r

save_model(mmm, "mmm.binpb")
mmm <- load_model("mmm.binpb")
```

The `.binpb` extension selects Meridian’s versioned schema format, which
other Meridian versions can read. A `.pkl` path uses the legacy pickle
format instead; it only reloads under the same Meridian version and is
deprecated from Meridian 2.2.

## Drop down to Python

Everything in Meridian is reachable through the `meridian` module
handle, the low-level escape hatch beneath the wrappers:

``` r

meridian$analysis$analyzer$Analyzer(mmm)
```

For tidy metrics, diagnostics, and ggplot2 charts of a fitted model, see
[`vignette("analysis")`](https://roeh-marketing.github.io/meridianR/articles/analysis.md).
