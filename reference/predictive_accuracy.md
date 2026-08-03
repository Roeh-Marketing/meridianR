# Predictive accuracy metrics

Predictive accuracy metrics

## Usage

``` r
predictive_accuracy(model, ...)
```

## Arguments

- model:

  A fitted `meridian_model` or a
  [`analyzer()`](https://roeh-marketing.github.io/meridianR/reference/analyzer.md).

- ...:

  Further arguments passed to `predictive_accuracy()`.

## Value

A tibble of predictive-accuracy metrics (e.g. R-squared, MAPE, wMAPE) by
evaluation set.

## See also

Other analysis accessors:
[`adstock_decay()`](https://roeh-marketing.github.io/meridianR/reference/adstock_decay.md),
[`expected_vs_actual()`](https://roeh-marketing.github.io/meridianR/reference/expected_vs_actual.md),
[`hill_curves()`](https://roeh-marketing.github.io/meridianR/reference/hill_curves.md),
[`response_curves()`](https://roeh-marketing.github.io/meridianR/reference/response_curves.md),
[`rhat_summary()`](https://roeh-marketing.github.io/meridianR/reference/rhat_summary.md),
[`summary_metrics()`](https://roeh-marketing.github.io/meridianR/reference/summary_metrics.md)
