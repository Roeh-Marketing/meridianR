test_that("priors and model_spec construct", {
  skip_if_no_meridian()
  p <- prior_distribution(roi_m = prior_lognormal(0.2, 0.9))
  expect_s3_class(p, "meridian_prior")

  spec <- model_spec(prior = p, max_lag = 4, media_effects_dist = "log_normal")
  expect_s3_class(spec, "meridian_model_spec")
})

test_that("model_spec forwards prior types and adstock options", {
  skip_if_no_meridian()
  spec <- model_spec(
    prior = prior_distribution(contribution_m = prior_beta(c(2, 1), c(15, 20))),
    media_prior_type = "contribution",
    adstock_decay_spec = "binomial",
    max_lag = 6
  )
  expect_equal(reticulate::py_to_r(spec$effective_media_prior_type), "contribution")
  expect_equal(reticulate::py_to_r(spec$max_lag), 6L)
  expect_match(paste(cli::cli_fmt(print(spec)), collapse = "\n"), "media_prior_type: contribution")
})

test_that("meridian_model builds and samples the prior", {
  skip_if_no_meridian()
  df <- toy_df()
  input <- as_meridian_input(
    df,
    kpi = "kpi", geo = "geo", population = "population",
    media_spend = "tv_spend", media = "tv_impr", media_channels = "TV",
    controls = "price"
  )
  mmm <- meridian_model(input, model_spec(max_lag = 4))
  expect_s3_class(mmm, "meridian_model")
  expect_false("posterior" %in% model_groups(mmm))

  sample_prior(mmm, 20)
  expect_true("prior" %in% model_groups(mmm))
})

test_that("save_model / load_model round-trip in both formats", {
  skip_if_no_meridian()
  mmm <- fitted_toy_model()
  dir <- withr::local_tempdir()

  pkl <- suppressWarnings(save_model(mmm, file.path(dir, "m.pkl")))
  expect_true(file.exists(pkl))
  expect_s3_class(suppressWarnings(load_model(pkl)), "meridian_model")

  skip_if_not(schema_serde_available(), "Meridian schema extra not installed")
  bin <- save_model(mmm, file.path(dir, "m.binpb"))
  expect_true(file.size(bin) > 0)
  m2 <- load_model(bin)
  expect_s3_class(m2, "meridian_model")
  expect_true("posterior" %in% model_groups(m2))

  auto <- save_model(mmm, file.path(dir, "m"))
  expect_equal(basename(auto), "m.binpb")
})
