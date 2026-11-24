#' Save and load a Meridian model
#'
#' `save_model()` serializes a Meridian model -- including its inference data --
#' to a file, and `load_model()` restores it.
#'
#' Meridian has two file formats, and the file extension selects which one is
#' used:
#'
#' * **Schema** (`.binpb` binary, or `.txtpb` / `.textproto` text): Meridian's
#'   versioned protobuf format, via `meridian.schema.serde.meridian_serde`. It
#'   can be read by other Meridian versions and is the format Meridian
#'   recommends from 2.2 on. It needs the `google-meridian[schema]` extra,
#'   which [install_meridian()] installs.
#' * **Pickle** (`.pkl`, `.pickle`, `.joblib`): Meridian's legacy
#'   `save_mmm()` / `load_mmm()`. Only guaranteed to reload with the same
#'   Meridian version, and deprecated in Meridian 2.2.
#'
#' Any other extension (or none) uses the schema format when it is available --
#' `.binpb` is appended to the file name -- and falls back to pickle otherwise.
#'
#' @param model A `meridian_model`.
#' @param path File path to write to or read from.
#'
#' @return `save_model()` returns the path actually written, invisibly (it can
#'   differ from `path` when an extension was added); `load_model()` returns a
#'   `meridian_model`.
#' @export
#'
#' @examples
#' \dontrun{
#' save_model(mmm, "mmm.binpb")   # schema format (recommended)
#' mmm2 <- load_model("mmm.binpb")
#'
#' save_model(mmm, "mmm.pkl")     # legacy pickle format
#' }
save_model <- function(model, path) {
  ensure_meridian()
  format <- model_file_format(path)
  if (identical(format, "auto")) {
    if (schema_serde_available()) {
      path <- paste0(path, ".binpb")
      format <- "schema"
      cli::cli_alert_info("Saving in Meridian's schema format as {.path {path}}.")
    } else {
      format <- "pickle"
    }
  }

  if (identical(format, "schema")) {
    schema_serde()$save_meridian(model, path)
  } else {
    meridian$model$model$save_mmm(model, path)
  }
  invisible(path)
}

#' @rdname save_model
#' @export
load_model <- function(path) {
  ensure_meridian()
  mmm <- if (identical(model_file_format(path), "schema")) {
    schema_serde()$load_meridian(path)
  } else {
    meridian$model$model$load_mmm(path)
  }
  add_class(mmm, "meridian_model")
}

# Map a file extension to a serialization format: "schema", "pickle", or
# "auto" (no recognized extension).
model_file_format <- function(path) {
  base <- basename(path)
  ext <- if (grepl(".", base, fixed = TRUE)) tolower(sub(".*\\.", "", base)) else ""
  if (ext %in% c("binpb", "txtpb", "textproto")) {
    "schema"
  } else if (ext %in% c("pkl", "pickle", "joblib")) {
    "pickle"
  } else {
    "auto"
  }
}

# Meridian's schema serializer module, or NULL if the `schema` extra is missing.
schema_serde_module <- function() {
  tryCatch(
    reticulate::import("meridian.schema.serde.meridian_serde"),
    error = function(e) NULL
  )
}

schema_serde_available <- function() {
  mod <- schema_serde_module()
  !is.null(mod) && reticulate::py_has_attr(mod, "save_meridian")
}

schema_serde <- function(call = rlang::caller_env()) {
  if (!schema_serde_available()) {
    cli::cli_abort(
      c(
        "Meridian's schema serializer is not available.",
        "i" = "It needs the {.code google-meridian[schema]} extra; reinstall with {.run meridianR::install_meridian()}.",
        "i" = "Or use a {.file .pkl} path for the legacy pickle format."
      ),
      call = call
    )
  }
  schema_serde_module()
}
