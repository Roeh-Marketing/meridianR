# Installation and Python environment management.

meridian_default_version <- "2.2.1"
meridian_min_version <- "1.7.1"
meridian_max_version <- "2.2.1"

#' Install Meridian and its Python dependencies
#'
#' Creates (or reuses) a persistent Python virtual environment and installs the
#' `google-meridian` package together with the backend of your choice. Once
#' installed, meridianR will use this environment automatically in future
#' sessions.
#'
#' If you skip this step, meridianR still works: [reticulate::py_require()] (set
#' up on load) will provision an ephemeral environment containing Meridian the
#' first time Python is used. `install_meridian()` is recommended when you want
#' a reusable environment, a specific Meridian version, or GPU support.
#'
#' If no Python interpreter satisfying `python_version` is found, one is
#' installed first -- with `uv` when it is on the `PATH`, otherwise with
#' [reticulate::install_python()].
#'
#' @param envname Name of (or path to) the virtual environment to install into.
#'   Defaults to `"r-meridian"`.
#' @param ... Additional arguments passed to [reticulate::py_install()].
#' @param backend `NULL` (default) to use Meridian's own default backend --
#'   JAX from Meridian 2.2, TensorFlow before that -- or `"tensorflow"` /
#'   `"jax"` to choose one. `"jax"` also installs the `google-meridian[jax]`
#'   extra (needed on Meridian 1.x). An explicit choice applies to the current
#'   session; use [use_backend()] at the start of later sessions.
#' @param gpu Logical; if `TRUE`, install the CUDA GPU build
#'   (`google-meridian[and-cuda]`). Ignored on platforms without CUDA support.
#' @param meridian_version Exact version of `google-meridian` to install.
#'   Supported versions currently range from 1.7.1 through 2.2.1; the default
#'   is the newest tested release.
#' @param python_version Python version constraint used when creating a new
#'   environment. Meridian's JAX dependency needs Python >= 3.11, and
#'   TensorFlow does not yet publish wheels for Python 3.14.
#' @param new_env If `TRUE`, any existing environment of the same name is
#'   removed before installing. Defaults to `TRUE` only for the default
#'   `"r-meridian"` environment.
#'
#' @return The environment name, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' # Default CPU install of the newest tested Meridian release
#' install_meridian()
#'
#' # A specific supported release, in its own environment
#' install_meridian("r-meridian-1.7.1", meridian_version = "1.7.1")
#'
#' # GPU build
#' install_meridian(gpu = TRUE)
#'
#' # Force a backend instead of Meridian's default
#' install_meridian(backend = "tensorflow")
#' }
install_meridian <- function(envname = "r-meridian",
                             ...,
                             backend = NULL,
                             gpu = FALSE,
                             meridian_version = meridian_default_version,
                             python_version = ">=3.11,<3.14",
                             new_env = identical(envname, "r-meridian")) {
  if (!is.null(backend)) {
    backend <- match.arg(backend, c("tensorflow", "jax"))
  }
  validate_meridian_version(meridian_version)
  pkg <- meridian_pip_spec(
    backend = backend,
    gpu = gpu,
    meridian_version = meridian_version
  )

  python_floor <- regmatches(
    python_version,
    regexpr("[0-9]+\\.[0-9]+", python_version)
  )
  if (!length(python_floor) || !nzchar(python_floor) ||
      numeric_version(python_floor) < "3.11") {
    cli::cli_abort("Meridian requires Python 3.11 or newer in this package.")
  }

  if (isTRUE(new_env) && reticulate::virtualenv_exists(envname)) {
    reticulate::virtualenv_remove(envname, confirm = FALSE)
  }

  # reticulate's uv-backed provisioning may otherwise use a user cache that
  # is not writable in managed or containerized environments.
  old_uv_cache <- Sys.getenv("UV_CACHE_DIR", unset = NA_character_)
  if (is.na(old_uv_cache)) {
    uv_cache <- file.path(tempdir(), "meridianR-uv-cache")
    dir.create(uv_cache, recursive = TRUE, showWarnings = FALSE)
    Sys.setenv(UV_CACHE_DIR = uv_cache)
    on.exit(Sys.unsetenv("UV_CACHE_DIR"), add = TRUE)
  }
  on.exit({
    if (!is.na(old_uv_cache)) Sys.setenv(UV_CACHE_DIR = old_uv_cache)
  }, add = TRUE)

  # py_install() creates virtual environments but does not install Python
  # itself, so make sure an interpreter satisfying `python_version` exists.
  ensure_python_starter(python_version, python_floor)

  tryCatch(
    reticulate::py_install(
      packages = pkg,
      envname = envname,
      pip = TRUE,
      python_version = python_version,
      ...
    ),
    error = function(e) {
      cli::cli_abort(
        c(
          "Could not install Meridian into {.val {envname}}.",
          "i" = "Requested Python: {.val {python_version}}; package: {.val {pkg}}.",
          "i" = "Check that Python can be downloaded and that the environment path is writable.",
          "x" = conditionMessage(e)
        ),
        parent = e
      )
    }
  )

  options(meridianR.virtualenv = envname)
  if (!is.null(backend)) options(meridianR.backend = backend)

  cli::cli_alert_success("Installed {.val {pkg}} into virtualenv {.val {envname}}.")
  cli::cli_alert_info(
    "Restart R to use it, or call reticulate::use_virtualenv({.val {envname}}) first."
  )
  invisible(envname)
}

# Make sure reticulate can find a Python interpreter satisfying `constraint` to
# seed the virtual environment. When none exists, provision one: prefer uv
# (fast, prebuilt, already used by reticulate), falling back to pyenv via
# reticulate::install_python() (which compiles from source).
ensure_python_starter <- function(constraint, floor) {
  if (!is.null(reticulate::virtualenv_starter(constraint))) {
    return(invisible(TRUE))
  }
  cli::cli_alert_info(
    "No Python satisfying {.val {constraint}} found; installing Python {floor}."
  )
  uv <- Sys.which("uv")
  if (nzchar(uv)) {
    status <- system2(uv, c("python", "install", floor))
    if (identical(status, 0L) &&
        !is.null(reticulate::virtualenv_starter(constraint))) {
      return(invisible(TRUE))
    }
  }
  tryCatch(
    reticulate::install_python(version = paste0(floor, ":latest"), optimized = FALSE),
    error = function(e) {
      cli::cli_abort(
        c(
          "Could not install Python {.val {floor}}.",
          "i" = "Meridian needs Python {.val {constraint}}.",
          "i" = "Install a compatible Python (e.g. {.code uv python install {floor}}) and retry.",
          "x" = conditionMessage(e)
        ),
        parent = e
      )
    }
  )
  invisible(TRUE)
}

validate_meridian_version <- function(version) {
  if (length(version) != 1L || is.na(version) ||
      !grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", version)) {
    cli::cli_abort("{.arg meridian_version} must be an exact release version.")
  }
  version <- numeric_version(version)
  if (version < numeric_version(meridian_min_version) ||
      version > numeric_version(meridian_max_version)) {
    cli::cli_abort(
      "Supported Meridian versions are {.val {meridian_min_version}} through {.val {meridian_max_version}}."
    )
  }
  invisible(TRUE)
}

# Build the pip requirement string with the appropriate extras. The `schema`
# extra is always included: it provides Meridian's schema-based model
# serializer used by save_model() / load_model().
meridian_pip_spec <- function(backend = NULL, gpu = FALSE,
                              meridian_version = meridian_default_version) {
  extras <- character()
  if (isTRUE(gpu)) extras <- c(extras, "and-cuda")
  if (identical(backend, "jax")) extras <- c(extras, "jax")
  extras <- c(extras, "schema")
  sprintf(
    "google-meridian[%s]==%s",
    paste(extras, collapse = ","), meridian_version
  )
}

#' Select the Meridian compute backend
#'
#' Meridian can run on a TensorFlow or a JAX backend. Meridian 1.x defaults to
#' TensorFlow; from Meridian 2.2, JAX is the default and TensorFlow is
#' deprecated upstream.
#' The backend is read from the `MERIDIAN_BACKEND` environment variable when the
#' Meridian Python module is first imported, so for a reliable switch call
#' `use_backend()` *before* any other meridianR function in a session. If
#' Meridian is already loaded, `use_backend()` additionally attempts a runtime
#' switch, which may not take full effect until the session is restarted.
#'
#' @param backend `"tensorflow"` or `"jax"`.
#'
#' @return The selected backend, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' use_backend("jax")
#' }
use_backend <- function(backend = c("tensorflow", "jax")) {
  backend <- match.arg(backend)
  options(meridianR.backend = backend)
  Sys.setenv(MERIDIAN_BACKEND = backend)

  if (meridian_available()) {
    meridian$backend$config$set_backend(backend)
    cli::cli_alert_info(
      "Meridian is already loaded; backend switched to {.val {backend}} at runtime. Restart R if you hit backend errors."
    )
  } else {
    cli::cli_alert_success("Meridian backend set to {.val {backend}}.")
  }
  invisible(backend)
}

#' Is the Meridian Python package available?
#'
#' Checks whether the `meridian` Python module can be imported in the active
#' reticulate configuration. The first call may initialize Python (and, if no
#' environment is configured, trigger [reticulate::py_require()] provisioning).
#'
#' @return `TRUE` or `FALSE`.
#' @export
meridian_available <- function() {
  reticulate::py_module_available("meridian")
}

#' Installed Meridian version
#'
#' @return A string with the Meridian Python package version.
#' @export
meridian_version <- function() {
  ensure_meridian()
  reticulate::py_to_r(meridian[["__version__"]])
}

# Internal: error helpfully if Meridian cannot be imported, distinguishing
# "not installed" from "the wrong Python interpreter is active" (a common
# reticulate pitfall when an IDE or RETICULATE_PYTHON pins another environment).
ensure_meridian <- function(call = rlang::caller_env()) {
  if (meridian_available()) {
    return(invisible(TRUE))
  }

  venv <- getOption("meridianR.virtualenv", default = "r-meridian")
  cfg <- tryCatch(reticulate::py_config(), error = function(e) NULL)
  active <- if (!is.null(cfg)) {
    sprintf("%s (Python %s)", cfg$python, cfg$version)
  } else {
    "none initialized"
  }

  msg <- c("Meridian could not be imported.", "i" = "Active Python: {active}.")
  if (reticulate::virtualenv_exists(venv)) {
    msg <- c(
      msg,
      "i" = "Meridian is installed in the {.val {venv}} environment, but a different Python is active.",
      ">" = "Restart R, then run {.code reticulate::use_virtualenv(\"{venv}\", required = TRUE)} before anything else -- or set your IDE's Python interpreter to that environment."
    )
  } else {
    msg <- c(
      msg,
      "i" = "Install it with {.run meridianR::install_meridian()}, or point reticulate at an existing environment with {.fn reticulate::use_virtualenv} and restart R."
    )
  }
  cli::cli_abort(msg, call = call)
}
