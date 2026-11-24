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

# Classify an installed Meridian version against the tested window.
meridian_version_status <- function(version,
                                    min = meridian_min_version,
                                    max = meridian_max_version) {
  v <- tryCatch(numeric_version(version), error = function(e) NULL)
  if (is.null(v) || length(v) != 1L || is.na(v)) return("unknown")
  if (v < numeric_version(min)) return("too_old")
  if (v > numeric_version(max)) return("untested")
  "supported"
}

# Warn (once, when Meridian is first imported) if the active environment holds
# a Meridian release outside the window meridianR is tested against. Newer
# releases are allowed -- the adapters above may cover them -- but the user
# should know they are off the tested path.
check_meridian_version <- function(module = reticulate::import("meridian")) {
  version <- tryCatch(
    reticulate::py_to_r(module[["__version__"]]),
    error = function(e) NA_character_
  )
  status <- meridian_version_status(version)
  if (identical(status, "too_old")) {
    cli::cli_warn(c(
      "Meridian {version} is older than the oldest supported release ({meridian_min_version}).",
      "i" = "Upgrade with {.run meridianR::install_meridian()}."
    ), class = "meridianR_version_warning")
  } else if (identical(status, "untested")) {
    cli::cli_warn(c(
      "Meridian {version} is newer than the newest tested release ({meridian_max_version}).",
      "i" = "Most features should work; pin a tested release with {.code install_meridian(meridian_version = \"{meridian_max_version}\")} if you hit errors."
    ), class = "meridianR_version_warning")
  }
  invisible(status)
}

# Meridian's selected backend controls the precision expected for priors.
meridian_float_dtype <- function() {
  ensure_meridian()
  meridian$backend$np_float_dtype
}
