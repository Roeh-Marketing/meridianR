# =============================================================================
#  meridianR Python environments: a guided tour of every setup option
# =============================================================================
#
#  meridianR runs Meridian (a Python library) through reticulate. This script
#  shows how to inspect, create, update, choose, and remove the Python
#  environments it uses.
#
#  HOW TO USE THIS FILE
#  * Sections marked [SAFE] only look at things -- run them freely.
#  * Recipes that install or delete things are wrapped in `if (FALSE) { ... }`,
#    so sourcing the whole file never changes anything. To use a recipe, put
#    the cursor on the line you want and run just that line (Ctrl/Cmd+Enter).
#  * reticulate binds ONE Python per R session, and it cannot be changed
#    afterwards. Many recipes therefore say "restart R first"
#    (RStudio: Session > Restart R; VS Code: restart the R terminal).
#
#  TESTED RANGE: Meridian 1.7.1 - 2.2.1 on Python 3.11 - 3.13.
# =============================================================================


# ---- 0. Key ideas (read first) -----------------------------------------------
#
#  ENV NAME vs ENV PATH
#    install_meridian("r-meridian")   a NAME -> lives in reticulate's env root,
#                                     usually ~/.virtualenvs/r-meridian. Shared
#                                     by every project on the machine.
#    install_meridian("./.venv")      a PATH -> lives exactly there, e.g. inside
#                                     one project folder.
#
#  WHAT install_meridian() DOES
#    1. Finds a Python 3.11-3.13 interpreter (system, PATH, or uv-managed).
#       If there is none, installs one with `uv` (or pyenv as a fallback).
#    2. For the default name "r-meridian": DELETES any existing env of that
#       name and builds it fresh (new_env = TRUE). For any other name/path it
#       reuses an existing env and installs into it (new_env = FALSE).
#    3. pip-installs google-meridian[schema]==<version> (+ [jax] / [and-cuda]
#       if requested).
#
#  WHICH ENV A SESSION USES (first match wins)
#    1. RETICULATE_PYTHON environment variable (e.g. in ~/.Renviron, or set
#       by your IDE's Python interpreter setting)
#    2. reticulate::use_virtualenv(...) called before Python starts
#    3. library(meridianR): the env named by option `meridianR.virtualenv`
#       (default "r-meridian"), if it exists
#    4. Otherwise: an automatic, cached, temporary env built by
#       reticulate::py_require() with the tested Meridian release.
#
#  A virtual env depends on the Python it was built from. If that interpreter
#  is deleted, the env breaks and must be rebuilt.


# ---- 1. Inspect what you have [SAFE] ------------------------------------------
#
# None of this starts Python in the current session.

library(reticulate)

# FIRST: is the meridianR installed in your R library up to date? Everything in
# this script assumes version 0.0.0.9001 or later. An older copy has an older
# install_meridian() (no meridian_version argument, Python >= 3.10, unpinned
# Meridian), which builds a different environment than described here.
packageVersion("meridianR")
"meridian_version" %in% names(formals(meridianR::install_meridian))
# If outdated, reinstall from the source folder (then restart R):
#   devtools::install("~/Documents/roeh/meridianR")
# or, while developing, use devtools::load_all() instead of library(meridianR).

virtualenv_root()   # where NAMED envs live (default ~/.virtualenvs)
virtualenv_list()   # all named envs in that root
virtualenv_exists("r-meridian")

# Python interpreters install_meridian() could build an env from:
virtualenv_starter(">=3.11,<3.14", all = TRUE)
virtualenv_starter(all = TRUE)  # every interpreter found, any version

# Which Python and which Meridian is inside an env -- without activating it.
env_report <- function(env) {
  if (!virtualenv_exists(env)) {
    return(data.frame(env = env, python = NA, meridian = "env not found"))
  }
  py <- virtualenv_python(env)
  ver <- system2(py, c("-c", shQuote("import sys; print(sys.version.split()[0])")),
                 stdout = TRUE, stderr = FALSE)
  show <- suppressWarnings(system2(py, c("-m", "pip", "show", "google-meridian"),
                                   stdout = TRUE, stderr = FALSE))
  mer <- sub("^Version: ", "", grep("^Version:", show, value = TRUE))
  base <- grep("^home", readLines(file.path(dirname(dirname(py)), "pyvenv.cfg")), value = TRUE)
  data.frame(env = env, python = ver,
             meridian = if (length(mer)) mer else "not installed",
             built_from = sub("^home = ", "", base))
}
do.call(rbind, lapply(virtualenv_list(), env_report))

# Is anything pinning the interpreter for every session?
Sys.getenv("RETICULATE_PYTHON")   # "" means not pinned
Sys.getenv("MERIDIAN_BACKEND")    # "" means Meridian's default backend
getOption("meridianR.virtualenv") # NULL means "r-meridian"
file.exists("~/.Renviron"); file.exists("~/.Rprofile"); file.exists(".Rprofile")


# ---- 2. Build the default environment ----------------------------------------
#
# Result: ~/.virtualenvs/r-meridian with the newest tested Meridian (2.2.1),
# Meridian's default backend (JAX on 2.2), and the [schema] extra used by
# save_model(). If r-meridian already exists it is DELETED and rebuilt.
# Takes a few minutes (downloads ~1 GB of wheels). Then restart R.

if (FALSE) {
  meridianR::install_meridian()
}


# ---- 3. A specific Meridian version ------------------------------------------
#
# Any exact release from 1.7.1 to 2.2.1. Versions outside that range are
# refused. Giving each version its own env name keeps them side by side.

if (FALSE) {
  # Older supported release in its own named env:
  meridianR::install_meridian("r-meridian-1.7.1", meridian_version = "1.7.1")

  # Replace the default env with a specific version:
  meridianR::install_meridian(meridian_version = "2.1.0")
}


# ---- 4. A specific location -------------------------------------------------
#
# Option A: a PATH instead of a name -> the env lives exactly there.
# Good for a self-contained project. Add the folder to .gitignore.

if (FALSE) {
  meridianR::install_meridian("./.venv")                        # in this project
  meridianR::install_meridian("~/envs/meridian-2.2.1")           # anywhere else
  meridianR::install_meridian("./.venv", meridian_version = "1.7.1")
}

# Option B: move the ROOT for all named envs. Put this in ~/.Renviron (then
# restart R) so every session agrees:
#   RETICULATE_VIRTUALENV_ROOT=~/my-python-envs
# After that, install_meridian() creates ~/my-python-envs/r-meridian.


# ---- 5. Add to / update an EXISTING environment --------------------------------
#
# new_env = FALSE keeps the env and pip-installs into it. Use it to upgrade or
# downgrade Meridian in place, or to add extras, without rebuilding.
# Restart R first if that env is the one currently loaded.

if (FALSE) {
  # Change the Meridian version inside the existing default env:
  meridianR::install_meridian(new_env = FALSE, meridian_version = "2.2.1")

  # Add the JAX extra to an existing env:
  meridianR::install_meridian(new_env = FALSE, backend = "jax")

  # Non-default names/paths already reuse the env (new_env = FALSE by default):
  meridianR::install_meridian("./.venv", meridian_version = "2.2.1")

  # Add OTHER Python packages to an env (not Meridian-specific):
  reticulate::py_install(c("polars", "seaborn"), envname = "r-meridian", pip = TRUE)
  reticulate::virtualenv_install("r-meridian", "scikit-learn")
}


# ---- 6. Choose the Python version / interpreter ------------------------------

if (FALSE) {
  # A version constraint (must stay within 3.11-3.13):
  meridianR::install_meridian(python_version = "3.12")
  meridianR::install_meridian(python_version = ">=3.12,<3.14")

  # Install a specific Python yourself first (uv is fast, prebuilt):
  system("uv python install 3.12")

  # Full control: create the env from an exact interpreter, then install
  # Meridian into it with new_env = FALSE.
  py <- reticulate::virtualenv_starter("3.12")
  reticulate::virtualenv_create("r-meridian-py312", python = py)
  meridianR::install_meridian("r-meridian-py312", new_env = FALSE)
}


# ---- 7. Backend: JAX vs TensorFlow, and GPU ------------------------------------
#
# Default (backend = NULL): Meridian decides -- JAX on 2.2+, TensorFlow on 1.x.
# TensorFlow is deprecated from Meridian 2.2.

if (FALSE) {
  # Install for a specific backend:
  meridianR::install_meridian(backend = "jax")         # adds the [jax] extra
  meridianR::install_meridian(backend = "tensorflow")

  # CUDA GPU build (Linux with NVIDIA GPUs; not macOS):
  meridianR::install_meridian(gpu = TRUE)
  meridianR::install_meridian(gpu = TRUE, backend = "jax")
}

# The backend is chosen when Meridian is first imported, so in each session:
if (FALSE) {
  reticulate::use_virtualenv("r-meridian", required = TRUE)
  library(meridianR)
  use_backend("tensorflow")  # BEFORE any other meridianR call
}
# To make it permanent, add to ~/.Renviron:   MERIDIAN_BACKEND=tensorflow


# ---- 8. Use a particular environment in a session ----------------------------
#
# Restart R, then run ONE of these as the very first lines.

if (FALSE) {
  # (a) The default env -- nothing to do; library(meridianR) finds it:
  library(meridianR)

  # (b) Any named or path env, explicitly:
  reticulate::use_virtualenv("r-meridian-1.7.1", required = TRUE)
  library(meridianR)

  reticulate::use_virtualenv("./.venv", required = TRUE)
  library(meridianR)

  # (c) Tell meridianR which env to look for (e.g. in a project .Rprofile,
  #     so it is set before the package loads):
  options(meridianR.virtualenv = "r-meridian-1.7.1")
  library(meridianR)

  # (d) Pin one interpreter for ALL sessions, in ~/.Renviron or the project's
  #     .Renviron (overrides everything else -- remove it to undo):
  #   RETICULATE_PYTHON=~/.virtualenvs/r-meridian/bin/python
}

# RStudio alternative: Tools > Global Options > Python > Select >
# Virtual Environments > r-meridian. (Per project: Tools > Project Options.)


# ---- 9. No install at all: the automatic environment ---------------------------
#
# If no r-meridian env exists and nothing is pinned, the first Meridian call
# makes reticulate build a cached, throwaway env with the tested release
# (google-meridian[schema]==2.2.1). Nothing to manage, but slower the first
# time and not reusable outside reticulate.

if (FALSE) {
  # Restart R, with no r-meridian env and no RETICULATE_PYTHON set:
  library(meridianR)
  meridian_version()
}


# ---- 10. Verify the active environment -----------------------------------------
#
# These DO start Python, which locks this session to whichever env was chosen.

if (FALSE) {
  library(meridianR)
  meridian_available()     # can Meridian be imported?
  meridian_version()       # warns if outside the tested range
  reticulate::py_config()  # which interpreter / env is active
  reticulate::py_list_packages()[c("package", "version")]
  meridian$backend$config$get_backend()   # JAX or TensorFlow
  reticulate::py_module_available("meridian.schema.serde.meridian_serde") # schema extra?
}


# ---- 11. Run several Meridian versions side by side ------------------------------
#
# One env per version, one version per R session. Switch by restarting R and
# binding a different env first (section 8). For example, to check that a
# model gives similar answers on two releases:

if (FALSE) {
  meridianR::install_meridian("r-meridian-1.7.1", meridian_version = "1.7.1")
  meridianR::install_meridian("r-meridian-2.2.1", meridian_version = "2.2.1")
  # Session 1:  reticulate::use_virtualenv("r-meridian-1.7.1", required = TRUE)
  # Session 2:  reticulate::use_virtualenv("r-meridian-2.2.1", required = TRUE)
  # Save models as .binpb (schema format) so either version can read them.
}


# ---- 12. Remove environments and interpreters -----------------------------------
#
# Restart R first if the env is in use.

if (FALSE) {
  reticulate::virtualenv_remove("r-meridian-1.7.1", confirm = FALSE)  # named env
  reticulate::virtualenv_remove("./.venv", confirm = FALSE)           # path env
  unlink("./.venv", recursive = TRUE)                                 # same, by hand

  # uv-managed interpreters (envs built from them will break):
  system("uv python list --only-installed")
  system("uv python uninstall 3.11")
}


# ---- 13. Troubleshooting ------------------------------------------------------------
#
# "The requested version of Python ... cannot be used, as another version of
#  Python ... has already been initialized"
#   -> Python started before use_virtualenv(). Restart R and call
#      use_virtualenv() first, or check RETICULATE_PYTHON / your IDE setting.
#
# "Meridian X is older than the oldest supported release"
#   -> the active env has an old Meridian. Upgrade in place (section 5) or
#      rebuild (section 2).
#
# "Some Python package requirements declared via py_require() are not
#  installed in the selected Python environment"
#   -> the active env lacks the tested Meridian release or the [schema]
#      extra. Upgrade it with install_meridian(new_env = FALSE).
#
# "No Python satisfying '>=3.11,<3.14' found"
#   -> install_meridian() will try to install one; if that fails, run
#      `uv python install 3.12` in a terminal and retry.
#
# Env exists but Python errors on start ("No such file or directory")
#   -> the interpreter it was built from was deleted. Check `built_from` in
#      env_report() (section 1) and rebuild the env.
#
# "Meridian's schema serializer is not available" from save_model()
#   -> the env lacks the [schema] extra: install_meridian(new_env = FALSE),
#      or save to a .pkl path instead.
