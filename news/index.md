# Changelog

## meridianR 0.0.0.9001

Initial development release (data and modeling core).

- Python provisioning now requires Python \>= 3.11 and defaults to the
  tested Meridian 2.2.1 release, with supported versions constrained to
  1.7.1–2.2.1.

- Added compatibility adapters for Meridian’s renamed R-hat fields and
  backend-specific prior numeric precision.

- Meridian’s version is checked when it is first imported: meridianR
  warns (class `meridianR_version_warning`) if the active release is
  outside the tested window.

- [`install_meridian()`](https://roeh-marketing.github.io/meridianR/reference/install_meridian.md)
  now bounds Python to 3.11–3.13 (TensorFlow has no 3.14 wheels yet)
  and, when no suitable interpreter exists, installs one with `uv`
  before falling back to
  [`reticulate::install_python()`](https://rstudio.github.io/reticulate/reference/install_python.html).

- [`model_spec()`](https://roeh-marketing.github.io/meridianR/reference/model_spec.md)
  gains `media_prior_type`; `paid_media_prior_type` (deprecated in
  Meridian) is kept for compatibility.
  [`print()`](https://rdrr.io/r/base/print.html) on a model spec shows
  the effective media and RF prior types.

- [`install_meridian()`](https://roeh-marketing.github.io/meridianR/reference/install_meridian.md)
  and the on-load requirement now default to Meridian’s own backend
  (`backend = NULL`): JAX from Meridian 2.2, TensorFlow before. Pass
  `backend = "tensorflow"` or `"jax"` to choose.

- [`install_meridian()`](https://roeh-marketing.github.io/meridianR/reference/install_meridian.md)
  always installs the `google-meridian[schema]` extra.

- [`save_model()`](https://roeh-marketing.github.io/meridianR/reference/save_model.md)
  /
  [`load_model()`](https://roeh-marketing.github.io/meridianR/reference/save_model.md)
  support Meridian’s schema serializer, chosen by file extension:
  `.binpb` / `.txtpb` / `.textproto` use the versioned schema format,
  `.pkl` the legacy (deprecated) pickle format. Paths without a
  recognized extension get `.binpb` when the schema extra is available.

- First public scaffold of the package.

- Python provisioning via
  [`reticulate::py_require()`](https://rstudio.github.io/reticulate/reference/py_require.html)
  with an
  [`install_meridian()`](https://roeh-marketing.github.io/meridianR/reference/install_meridian.md)
  helper;
  [`use_backend()`](https://roeh-marketing.github.io/meridianR/reference/use_backend.md)
  selects the TensorFlow or JAX backend.

- Data interface:
  [`as_meridian_input()`](https://roeh-marketing.github.io/meridianR/reference/as_meridian_input.md),
  the fluent
  [`input_data_builder()`](https://roeh-marketing.github.io/meridianR/reference/input_data_builder.md)
  with `with_*()` verbs, and faithful
  [`coord_to_columns()`](https://roeh-marketing.github.io/meridianR/reference/coord_to_columns.md)
  /
  [`csv_loader()`](https://roeh-marketing.github.io/meridianR/reference/csv_loader.md)
  /
  [`data_frame_loader()`](https://roeh-marketing.github.io/meridianR/reference/csv_loader.md)
  bindings.

- Model configuration:
  [`model_spec()`](https://roeh-marketing.github.io/meridianR/reference/model_spec.md),
  [`prior_distribution()`](https://roeh-marketing.github.io/meridianR/reference/prior_distribution.md),
  and the `prior_*()` distribution constructors.

- Fitting:
  [`meridian_model()`](https://roeh-marketing.github.io/meridianR/reference/meridian_model.md),
  [`sample_prior()`](https://roeh-marketing.github.io/meridianR/reference/sample_prior.md),
  [`sample_posterior()`](https://roeh-marketing.github.io/meridianR/reference/sample_prior.md),
  [`fit()`](https://generics.r-lib.org/reference/fit.html), and
  [`save_model()`](https://roeh-marketing.github.io/meridianR/reference/save_model.md)
  /
  [`load_model()`](https://roeh-marketing.github.io/meridianR/reference/save_model.md).

- S3 [`print()`](https://rdrr.io/r/base/print.html) /
  [`summary()`](https://rdrr.io/r/base/summary.html) for input data,
  model specifications, and models.

- Analysis layer:
  [`analyzer()`](https://roeh-marketing.github.io/meridianR/reference/analyzer.md)
  plus tidy accessors returning tibbles
  ([`summary_metrics()`](https://roeh-marketing.github.io/meridianR/reference/summary_metrics.md),
  [`response_curves()`](https://roeh-marketing.github.io/meridianR/reference/response_curves.md),
  [`hill_curves()`](https://roeh-marketing.github.io/meridianR/reference/hill_curves.md),
  [`adstock_decay()`](https://roeh-marketing.github.io/meridianR/reference/adstock_decay.md),
  [`expected_vs_actual()`](https://roeh-marketing.github.io/meridianR/reference/expected_vs_actual.md),
  [`rhat_summary()`](https://roeh-marketing.github.io/meridianR/reference/rhat_summary.md),
  [`predictive_accuracy()`](https://roeh-marketing.github.io/meridianR/reference/predictive_accuracy.md)).

- ggplot2-native plots
  ([`plot_model_fit()`](https://roeh-marketing.github.io/meridianR/reference/plot_model_fit.md),
  [`plot_roi()`](https://roeh-marketing.github.io/meridianR/reference/plot_roi.md),
  [`plot_contribution()`](https://roeh-marketing.github.io/meridianR/reference/plot_contribution.md),
  [`plot_response_curves()`](https://roeh-marketing.github.io/meridianR/reference/plot_response_curves.md),
  [`plot_hill_curves()`](https://roeh-marketing.github.io/meridianR/reference/plot_hill_curves.md),
  [`plot_adstock_decay()`](https://roeh-marketing.github.io/meridianR/reference/plot_adstock_decay.md),
  [`plot_rhat()`](https://roeh-marketing.github.io/meridianR/reference/plot_rhat.md))
  with
  [`autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html)
  / [`plot()`](https://rdrr.io/r/graphics/plot.default.html) dispatch by
  `type`, plus
  [`model_report()`](https://roeh-marketing.github.io/meridianR/reference/model_report.md)
  for Meridian’s built-in HTML summary.
