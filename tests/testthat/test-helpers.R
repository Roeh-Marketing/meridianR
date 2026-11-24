test_that("compact drops NULL elements", {
  expect_equal(compact(list(a = 1, b = NULL, c = 2)), list(a = 1, c = 2))
  expect_equal(compact(list()), list())
})

test_that("as_py_int coerces to integer and preserves NULL", {
  expect_null(as_py_int(NULL))
  expect_identical(as_py_int(8), 8L)
  expect_identical(as_py_int(c(2, 3)), c(2L, 3L))
})

test_that("named_cols is NULL-safe and tags columns", {
  expect_length(named_cols("controls", NULL), 0)
  x <- named_cols("media", c("a", "b"))
  expect_equal(unname(x), c("a", "b"))
  expect_equal(names(x), c("media", "media"))
})

test_that("meridian_pip_spec builds the right extras", {
  expect_equal(meridian_pip_spec("tensorflow", FALSE), "google-meridian==2.2.1")
  expect_equal(meridian_pip_spec("jax", FALSE), "google-meridian[jax]==2.2.1")
  expect_equal(meridian_pip_spec("tensorflow", TRUE), "google-meridian[and-cuda]==2.2.1")
  expect_equal(meridian_pip_spec("jax", TRUE), "google-meridian[and-cuda,jax]==2.2.1")
  expect_equal(
    meridian_pip_spec("tensorflow", FALSE, meridian_version = "2.1.0"),
    "google-meridian==2.1.0"
  )
})

test_that("Meridian installer only accepts versions in the verified window", {
  expect_true(validate_meridian_version("1.7.1"))
  expect_true(validate_meridian_version("2.2.1"))
  expect_error(validate_meridian_version("1.7.0"), "Supported Meridian versions")
  expect_error(validate_meridian_version("2.2.2"), "Supported Meridian versions")
  expect_error(validate_meridian_version("latest"), "exact release version")
})

test_that("R-hat output column names are stable across Meridian versions", {
  old <- tibble::tibble(avg_rhat = 1, max_rhat = 1, percent_bad_rhat = 1)
  new <- tibble::tibble(avg_r_hat = 1, max_r_hat = 1, percent_bad_r_hat = 1)
  expect_named(normalize_rhat_names(old), names(old))
  expect_named(normalize_rhat_names(new), names(old))
})
