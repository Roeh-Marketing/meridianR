# Install Meridian and its Python dependencies

Creates (or reuses) a persistent Python virtual environment and installs
the `google-meridian` package together with the backend of your choice.
Once installed, meridianR will use this environment automatically in
future sessions.

## Usage

``` r
install_meridian(
  envname = "r-meridian",
  ...,
  backend = NULL,
  gpu = FALSE,
  meridian_version = meridian_default_version,
  python_version = ">=3.11,<3.14",
  new_env = identical(envname, "r-meridian")
)
```

## Arguments

- envname:

  Name of (or path to) the virtual environment to install into. Defaults
  to `"r-meridian"`.

- ...:

  Additional arguments passed to
  [`reticulate::py_install()`](https://rstudio.github.io/reticulate/reference/py_install.html).

- backend:

  `NULL` (default) to use Meridian's own default backend – JAX from
  Meridian 2.2, TensorFlow before that – or `"tensorflow"` / `"jax"` to
  choose one. `"jax"` also installs the `google-meridian[jax]` extra
  (needed on Meridian 1.x). An explicit choice applies to the current
  session; use
  [`use_backend()`](https://roeh-marketing.github.io/meridianR/reference/use_backend.md)
  at the start of later sessions.

- gpu:

  Logical; if `TRUE`, install the CUDA GPU build
  (`google-meridian[and-cuda]`). Ignored on platforms without CUDA
  support.

- meridian_version:

  Exact version of `google-meridian` to install. Supported versions
  currently range from 1.7.1 through 2.2.1; the default is the newest
  tested release.

- python_version:

  Python version constraint used when creating a new environment.
  Meridian's JAX dependency needs Python \>= 3.11, and TensorFlow does
  not yet publish wheels for Python 3.14.

- new_env:

  If `TRUE`, any existing environment of the same name is removed before
  installing. Defaults to `TRUE` only for the default `"r-meridian"`
  environment.

## Value

The environment name, invisibly.

## Details

If you skip this step, meridianR still works:
[`reticulate::py_require()`](https://rstudio.github.io/reticulate/reference/py_require.html)
(set up on load) will provision an ephemeral environment containing
Meridian the first time Python is used. `install_meridian()` is
recommended when you want a reusable environment, a specific Meridian
version, or GPU support.

If no Python interpreter satisfying `python_version` is found, one is
installed first – with `uv` when it is on the `PATH`, otherwise with
[`reticulate::install_python()`](https://rstudio.github.io/reticulate/reference/install_python.html).

## Examples

``` r
if (FALSE) { # \dontrun{
# Default CPU install of the newest tested Meridian release
install_meridian()

# A specific supported release, in its own environment
install_meridian("r-meridian-1.7.1", meridian_version = "1.7.1")

# GPU build
install_meridian(gpu = TRUE)

# Force a backend instead of Meridian's default
install_meridian(backend = "tensorflow")
} # }
```
