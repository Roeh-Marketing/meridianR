# meridianR 0.0.0.9001

Initial development release (data and modeling core).

* Python provisioning now requires Python >= 3.11 and defaults to the tested
  Meridian 2.2.1 release, with supported versions constrained to 1.7.1--2.2.1.
* Added compatibility adapters for Meridian's renamed R-hat fields and
  backend-specific prior numeric precision.
* Meridian's version is checked when it is first imported: meridianR warns
  (class `meridianR_version_warning`) if the active release is outside the
  tested window.
* `install_meridian()` now bounds Python to 3.11--3.13 (TensorFlow has no 3.14
  wheels yet) and, when no suitable interpreter exists, installs one with `uv`
  before falling back to `reticulate::install_python()`.
* `model_spec()` gains `media_prior_type`; `paid_media_prior_type` (deprecated
  in Meridian) is kept for compatibility. `print()` on a model spec shows the
  effective media and RF prior types.
* `install_meridian()` and the on-load requirement now default to
  Meridian's own backend (`backend = NULL`): JAX from Meridian 2.2,
  TensorFlow before. Pass `backend = "tensorflow"` or `"jax"` to choose.
* `install_meridian()` always installs the `google-meridian[schema]` extra.
* `save_model()` / `load_model()` support Meridian's schema serializer, chosen
  by file extension: `.binpb` / `.txtpb` / `.textproto` use the versioned
  schema format, `.pkl` the legacy (deprecated) pickle format. Paths without a
  recognized extension get `.binpb` when the schema extra is available.

* First public scaffold of the package.
* Python provisioning via `reticulate::py_require()` with an `install_meridian()`
  helper; `use_backend()` selects the TensorFlow or JAX backend.
* Data interface: `as_meridian_input()`, the fluent `input_data_builder()` with
  `with_*()` verbs, and faithful `coord_to_columns()` / `csv_loader()` /
  `data_frame_loader()` bindings.
* Model configuration: `model_spec()`, `prior_distribution()`, and the
  `prior_*()` distribution constructors.
* Fitting: `meridian_model()`, `sample_prior()`, `sample_posterior()`, `fit()`,
  and `save_model()` / `load_model()`.
* S3 `print()` / `summary()` for input data, model specifications, and models.
* Analysis layer: `analyzer()` plus tidy accessors returning tibbles
  (`summary_metrics()`, `response_curves()`, `hill_curves()`, `adstock_decay()`,
  `expected_vs_actual()`, `rhat_summary()`, `predictive_accuracy()`).
* ggplot2-native plots (`plot_model_fit()`, `plot_roi()`, `plot_contribution()`,
  `plot_response_curves()`, `plot_hill_curves()`, `plot_adstock_decay()`,
  `plot_rhat()`) with `autoplot()` / `plot()` dispatch by `type`, plus
  `model_report()` for Meridian's built-in HTML summary.
