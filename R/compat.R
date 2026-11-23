# Small adapters for Meridian API differences across supported releases.

# Meridian 2.0 standardized R-hat field names by adding an underscore before
# `hat`. Keep meridianR's public tibble column names stable across versions.
normalize_rhat_names <- function(x) {
  aliases <- c(
    avg_r_hat = "avg_rhat",
    max_r_hat = "max_rhat",
    percent_bad_r_hat = "percent_bad_rhat"
  )
  for (alias in names(aliases)) {
    canonical <- unname(aliases[[alias]])
    if (alias %in% names(x) && !canonical %in% names(x)) {
      names(x)[names(x) == alias] <- canonical
    }
  }
  x
}

# Meridian's selected backend controls the precision expected for priors.
meridian_float_dtype <- function() {
  ensure_meridian()
  meridian$backend$np_float_dtype
}
