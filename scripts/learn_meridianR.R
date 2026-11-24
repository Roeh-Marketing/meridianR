# =============================================================================
#  Learning meridianR: a guided, run-it-yourself tour
# =============================================================================
#
#  Work through this file top to bottom, one section at a time (Ctrl/Cmd+Enter
#  in RStudio or VS Code). Sections are marked `# ---- Title ----` so they show
#  up in the editor outline.
#
#  What you will see:
#    1. The sample data, and how it becomes Meridian input data
#    2. EVERY prior Meridian uses: what it is, its default, and what it looks
#       like, including the adstock (carryover) and Hill (saturation) priors
#    3. What Meridian *actually* uses for this dataset (it rewrites some priors)
#    4. Adstock options in depth: geometric vs. binomial, max_lag, the alpha
#       prior, per-channel specs, hill_before_adstock
#    5. Prior checks BEFORE fitting: what the priors imply for ROI/contribution
#    6. Fitting, convergence diagnostics, standard summaries and charts
#    7. Prior vs. posterior: what did the data teach the model?
#    8. A small experiment harness for changing priors and comparing models
#
#  The `sales` data is simulated, so we KNOW the true answers. That makes it a
#  good sandbox for prior experiments: you can see whether a prior moves the
#  model towards or away from the truth. The truth is in `data-raw/sales.R`.
#
#  Runtime: each model fit takes roughly 30-90 seconds on a laptop CPU with the
#  settings below. Section 8 fits several models.
# =============================================================================


# ---- 0. Setup ---------------------------------------------------------------

# Bind the Meridian Python environment BEFORE anything else touches Python.
# (Create it once with meridianR::install_meridian() if you have not already.)
reticulate::use_virtualenv("r-meridian", required = TRUE)

library(meridianR)
library(ggplot2)

meridian_version() # tested range: 1.7.1 - 2.2.1
reticulate::py_config() # which Python / backend you are on

SEED <- 2025

# MCMC settings. Short runs are fine for exploring; use more draws (e.g.
# n_adapt = 2000, n_burnin = 1000, n_keep = 2000) before trusting results.
MCMC <- list(n_chains = 4, n_adapt = 1000, n_burnin = 500, n_keep = 1000)
PRIOR_DRAWS <- 500

# The data-generating truth for `sales` (see data-raw/sales.R). Note: the
# simulation's Hill `ec` is defined on adstocked *spend*, while Meridian uses
# impressions/clicks, so treat the ec/slope truths as approximate.
truth <- data.frame(
  channel             = c("TV", "Search"),
  alpha               = c(0.55, 0.30), # geometric adstock decay rate
  ec                  = c(0.80, 0.60), # Hill half-saturation point
  slope               = c(1.30, 1.10), # Hill slope
  pct_of_contribution = c(0.14, 0.07) / 1.21 * 100 # ~11.6% and ~5.8% of KPI
)
truth


# ---- 0b. Helper functions (run once, no need to study them) -----------------
#
# Small helpers to turn Meridian's Python objects into R data frames. They are
# defined here (rather than in the package) so you can see exactly what they do.

py_helpers <- reticulate::py_run_string("
def tidy_draws(idata, group, var):
    # One row per chain x draw x coordinate, e.g. alpha_m by media_channel.
    return getattr(idata, group)[var].to_dataframe().reset_index()

def dist_params(d):
    import numpy as np
    # Unwrap Meridian's per-channel BatchBroadcast wrapper (only that one:
    # TFP's LogNormal is itself a transformed Normal and must stay as is).
    inner = d.distribution if type(d).__name__ == 'BatchBroadcast' else d
    out = {'distribution': type(inner).__name__}
    params = dict(inner.parameters)
    if out['distribution'] == 'TransformedDistribution':
        # e.g. ec_rf = 0.1 + LogNormal(0.7, 0.4)
        base, bij = inner.distribution, inner.bijector
        out['distribution'] = type(base).__name__ + ' + ' + type(bij).__name__
        params = dict(base.parameters)
        if getattr(bij, 'shift', None) is not None:
            params['shift'] = bij.shift
    skip = ('validate_args', 'allow_nan_stats', 'name',
            'force_probs_to_zero_outside_support')
    for k, v in params.items():
        if k in skip or v is None:
            continue
        try:
            out[k] = [float(x) for x in np.atleast_1d(v)]
        except Exception:
            out[k] = type(v).__name__   # e.g. a nested distribution/bijector
    return out

def prior_fields(prior):
    import dataclasses
    return [f.name for f in dataclasses.fields(prior)]
", local = TRUE, convert = FALSE)

# Draws of one parameter from a model's prior or posterior, as a data frame.
get_draws <- function(model, var, group = c("posterior", "prior")) {
  group <- match.arg(group)
  df <- reticulate::py_to_r(py_helpers$tidy_draws(model$inference_data, group, var))
  names(df)[names(df) == var] <- "value"
  df$parameter <- var
  df$group <- group
  df
}

# One-row-per-prior table: parameter name, distribution family, parameters.
# Works on a prior_distribution() or on a model's `prior_broadcast` (the priors
# after Meridian has expanded them to one per channel / geo / knot).
prior_table <- function(prior, fields = NULL) {
  fields <- fields %||% reticulate::py_to_r(py_helpers$prior_fields(prior))
  rows <- lapply(fields, function(f) {
    p <- reticulate::py_to_r(py_helpers$dist_params(reticulate::py_get_attr(prior, f)))
    vals <- p[setdiff(names(p), "distribution")]
    fmt <- vapply(names(vals), function(k) {
      v <- vals[[k]]
      if (is.numeric(v)) {
        v <- unique(signif(v, 3)) # collapse identical per-channel values
        paste0(k, "=", paste(v, collapse = "/"))
      } else {
        paste0(k, "=<", v, ">")
      }
    }, character(1))
    data.frame(parameter = f, distribution = p$distribution,
               parameters = paste(fmt, collapse = ", "))
  })
  do.call(rbind, rows)
}

# Analytic density of a (scalar) prior on a grid, using R's d*() functions.
prior_density <- function(prior, field, x = NULL, label = field) {
  p <- reticulate::py_to_r(py_helpers$dist_params(reticulate::py_get_attr(prior, field)))
  first <- function(k) p[[k]][1]
  dist <- p$distribution
  if (is.null(x)) {
    x <- switch(dist,
      Uniform         = seq(first("low"), first("high"), length.out = 400),
      Beta            = seq(0.001, 0.999, length.out = 400),
      LogNormal       = seq(1e-4, qlnorm(0.995, first("loc"), first("scale")), length.out = 400),
      HalfNormal      = seq(0, 3 * first("scale"), length.out = 400),
      Normal          = first("loc") + seq(-3, 3, length.out = 400) * first("scale"),
      TruncatedNormal = seq(first("low"), min(first("high"), first("loc") + 4 * first("scale")), length.out = 400),
      Deterministic   = first("loc"),
      seq(0, 1, length.out = 2)
    )
  }
  y <- switch(dist,
    Uniform    = dunif(x, first("low"), first("high")),
    Beta       = dbeta(x, first("concentration1"), first("concentration0")),
    LogNormal  = dlnorm(x, first("loc"), first("scale")),
    HalfNormal = 2 * dnorm(x, 0, first("scale")),
    Normal     = dnorm(x, first("loc"), first("scale")),
    TruncatedNormal = {
      m <- first("loc"); s <- first("scale"); lo <- first("low"); hi <- first("high")
      ifelse(x < lo | x > hi, 0,
             dnorm(x, m, s) / (pnorm(hi, m, s) - pnorm(lo, m, s)))
    },
    Deterministic = NA_real_, # a point mass; drawn as a vertical line
    rep(NA_real_, length(x))
  )
  data.frame(parameter = label, distribution = dist, x = x, density = y)
}

# Adstock weight at lag l, relative to lag 0 -- Meridian's exact formulas
# (meridian.model.adstock_hill.compute_decay_weights). Meridian then
# normalizes the weights over the window 0..max_lag so they sum to 1.
adstock_weights <- function(alpha, max_lag = 8, type = c("geometric", "binomial")) {
  type <- match.arg(type)
  l <- 0:max_lag
  W <- max_lag + 1 # window size
  if (type == "geometric") alpha^l else (1 - l / W)^(1 / alpha - 1)
}

# Hill saturation, as Meridian defines it on median-scaled media units.
hill <- function(x, ec, slope) x^slope / (x^slope + ec^slope)

`%||%` <- function(a, b) if (is.null(a)) b else a


# ---- 1. The sample data -----------------------------------------------------

data("sales")
str(sales)
summary(sales)

# Weekly conversions by region: a strong trend + seasonality baseline.
ggplot(sales, aes(week, conversions, colour = region)) +
  geom_line() +
  labs(title = "Weekly conversions by region", x = NULL, y = "Conversions")

# Media spend over time (summed across regions).
spend <- aggregate(cbind(tv_spend, search_spend) ~ week, data = sales, FUN = sum)
spend_long <- rbind(
  data.frame(week = spend$week, channel = "TV", spend = spend$tv_spend),
  data.frame(week = spend$week, channel = "Search", spend = spend$search_spend)
)
ggplot(spend_long, aes(week, spend, colour = channel)) +
  geom_line() +
  scale_y_continuous(labels = scales::label_comma()) +
  labs(title = "Weekly media spend (all regions)", x = NULL, y = "Spend")

colSums(sales[c("tv_spend", "search_spend")]) # total spend by channel


# ---- 2. Build Meridian input data -------------------------------------------
#
# `conversions` is a NON-REVENUE KPI and we have no revenue_per_kpi, so ROI will
# be measured in conversions per dollar (small numbers, ~0.01). Keep that in
# mind when reading any ROI prior: the default ROI prior is written for a
# revenue KPI (dollars per dollar). Meridian warns about this, as you will see.

input <- as_meridian_input(
  sales,
  kpi            = "conversions",
  time           = "week",
  geo            = "region",
  population     = "population",
  media_spend    = c("tv_spend", "search_spend"),
  media          = c("tv_impressions", "search_clicks"),
  media_channels = c("TV", "Search"),
  controls       = "price_index"
)
input


# ---- 3. The full prior menu: Meridian's defaults -----------------------------
#
# `prior_distribution()` with no arguments gives Meridian's default priors.
# Parameter names follow a pattern:
#
#   suffix  _m   paid media        _rf  paid reach & frequency
#           _om  organic media     _orf organic reach & frequency
#           _c   control vars      _n   non-media treatments
#
#   MEDIA EFFECT SIZE (only ONE family is active per channel type, chosen by
#   model_spec(media_prior_type = ...)):
#     roi_m           ROI prior            (media_prior_type = "roi", default)
#     mroi_m          marginal ROI prior   (media_prior_type = "mroi")
#     contribution_m  share of KPI driven  (media_prior_type = "contribution")
#     beta_m          raw coefficient      (media_prior_type = "coefficient")
#
#   ADSTOCK (carryover)
#     alpha_m         decay rate in [0, 1]; higher = longer carryover
#
#   HILL SATURATION (diminishing returns)
#     ec_m            half-saturation point, in median-scaled media units
#     slope_m         Hill slope; > 1 gives an S-shape (fixed at 1 by default
#                     for media, so curves are concave)
#
#   HIERARCHY / GEO VARIATION
#     eta_m           geo-to-geo variation of the media effect
#     tau_g_excl_baseline  geo intercepts (relative to the baseline geo)
#
#   BASELINE + CONTROLS + NOISE
#     knot_values     time-varying baseline (spline knot values)
#     gamma_c, xi_c   control-variable effect and its geo variation
#     gamma_n, xi_n   non-media treatment effect and its geo variation
#     sigma           residual noise
#
# Everything except roi/mroi/contribution lives on the model's internal SCALED
# KPI scale (population-scaled and standardized), which is why e.g. gamma_c has
# a generic Normal(0, 5).

default_prior <- prior_distribution()
prior_table(default_prior)

# Picture the key paid-media priors. (slope_m is a point mass at 1.)
media_fields <- c("alpha_m", "ec_m", "slope_m", "roi_m", "mroi_m",
                  "contribution_m", "beta_m", "eta_m")
dens <- do.call(rbind, lapply(media_fields, prior_density, prior = default_prior))
point_mass <- dens[dens$distribution == "Deterministic", ]

ggplot(dens[!is.na(dens$density), ], aes(x, density)) +
  geom_area(fill = "#4C72B0", alpha = 0.3) +
  geom_line(colour = "#4C72B0") +
  geom_vline(data = point_mass, aes(xintercept = x), colour = "#4C72B0", linewidth = 1) +
  facet_wrap(~ parameter, scales = "free", ncol = 4) +
  labs(title = "Meridian's default paid-media priors",
       subtitle = "slope_m is fixed at 1 (vertical line)", x = NULL, y = "Density")

# And the baseline / control / noise priors.
other_fields <- c("knot_values", "tau_g_excl_baseline", "gamma_c", "xi_c", "sigma")
dens2 <- do.call(rbind, lapply(other_fields, prior_density, prior = default_prior))
ggplot(dens2, aes(x, density)) +
  geom_area(fill = "#55A868", alpha = 0.3) +
  geom_line(colour = "#55A868") +
  facet_wrap(~ parameter, scales = "free", ncol = 3) +
  labs(title = "Default baseline, control and noise priors (scaled KPI units)",
       x = NULL, y = "Density")


# ---- 3b. What Meridian ACTUALLY uses for this dataset ------------------------
#
# The defaults above are not the whole story. When the model is built, Meridian
# (a) broadcasts each prior to one per channel / geo / knot, and
# (b) for a non-revenue KPI without revenue_per_kpi, REPLACES the ROI prior with
#     one derived from a total-media-contribution prior (mean 40%, sd 20%).
# `prior_broadcast` shows the priors the model will really sample from.

spec_default <- model_spec() # every option at Meridian's default
spec_default # prints the adstock/saturation/prior-type settings

mmm_default <- meridian_model(input, spec_default)
prior_table(mmm_default$prior_broadcast,
            fields = c("roi_m", "alpha_m", "ec_m", "slope_m", "eta_m", "sigma"))
# roi_m is now LogNormal(-3.8, 0.59) instead of LogNormal(0.2, 0.9): a median
# ROI of exp(-3.8) ~ 0.023 conversions per dollar.

# The default number of baseline knots for a GEO model is one per time period
# (104 here). That is very flexible and can slow convergence. We will use
# fewer knots below.
reticulate::py_to_r(mmm_default$knot_info$n_knots)


# ---- 4. Adstock in depth -----------------------------------------------------
#
# Adstock spreads each week's media effect over the following weeks. Settings:
#
#   model_spec(max_lag = 8)                   # weeks of carryover considered
#   model_spec(adstock_decay_spec = "geometric")  # or "binomial"
#   model_spec(adstock_decay_spec = list(TV = "binomial", Search = "geometric"))
#   model_spec(hill_before_adstock = FALSE)   # order of saturation vs. adstock
#   prior_distribution(alpha_m = ...)         # the decay-rate prior
#
# GEOMETRIC: weight(l) = alpha^l. Peaks immediately, decays exponentially.
# BINOMIAL:  weight(l) = (1 - l / (max_lag + 1))^(1 / alpha - 1). Decays to zero
#            at the end of the window, so max_lag directly bounds the carryover;
#            alpha near 1 = a flat, long effect, alpha near 0 = immediate only.
# In both, higher alpha means longer carryover.

alphas <- c(0.1, 0.3, 0.5, 0.7, 0.9)
decay_grid <- do.call(rbind, lapply(c("geometric", "binomial"), function(type) {
  do.call(rbind, lapply(alphas, function(a) {
    data.frame(type = type, alpha = factor(a), lag = 0:8,
               weight = adstock_weights(a, max_lag = 8, type = type))
  }))
}))
ggplot(decay_grid, aes(lag, weight, colour = alpha)) +
  geom_line() + geom_point(size = 1) +
  facet_wrap(~ type) +
  scale_x_continuous(breaks = 0:8) +
  labs(title = "Adstock decay shapes for different alpha (max_lag = 8)",
       x = "Weeks after exposure", y = "Weight relative to week 0")

# max_lag matters a lot for binomial (it sets where the decay hits zero) and
# little for geometric with small alpha.
lag_grid <- do.call(rbind, lapply(c(4, 8, 13), function(L) {
  rbind(
    data.frame(max_lag = factor(L), type = "geometric", lag = 0:L,
               weight = adstock_weights(0.5, L, "geometric")),
    data.frame(max_lag = factor(L), type = "binomial", lag = 0:L,
               weight = adstock_weights(0.5, L, "binomial"))
  )
}))
ggplot(lag_grid, aes(lag, weight, colour = max_lag)) +
  geom_line() + geom_point(size = 1) +
  facet_wrap(~ type) +
  labs(title = "Effect of max_lag (alpha = 0.5)",
       x = "Weeks after exposure", y = "Weight relative to week 0")

# The PRIOR on alpha translates into a prior over decay curves. The default
# Uniform(0, 1) is deliberately vague. Compare some alternatives you might try:
alpha_priors <- list(
  "Uniform(0,1)  [default]"     = function(n) runif(n),
  "Beta(1,3)  short carryover"  = function(n) rbeta(n, 1, 3),
  "Beta(3,1)  long carryover"   = function(n) rbeta(n, 3, 1),
  "Beta(5,5)  centred on 0.5"   = function(n) rbeta(n, 5, 5)
)
set.seed(SEED)
implied <- do.call(rbind, lapply(names(alpha_priors), function(nm) {
  a <- alpha_priors[[nm]](4000)
  w <- t(vapply(a, adstock_weights, numeric(9), max_lag = 8, type = "geometric"))
  data.frame(prior = nm, lag = 0:8,
             median = apply(w, 2, median),
             lo = apply(w, 2, quantile, 0.05),
             hi = apply(w, 2, quantile, 0.95))
}))
ggplot(implied, aes(lag, median)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "#4C72B0", alpha = 0.25) +
  geom_line(colour = "#4C72B0") +
  facet_wrap(~ prior) +
  labs(title = "Prior-implied geometric decay curves (median and 90% band)",
       subtitle = "Truth for this data: TV alpha = 0.55, Search alpha = 0.30",
       x = "Weeks after exposure", y = "Weight relative to week 0")

# Density view of the same alpha priors:
alpha_dens <- data.frame(
  x = rep(seq(0.001, 0.999, length.out = 300), 4),
  prior = rep(names(alpha_priors), each = 300)
)
alpha_dens$density <- with(alpha_dens, ifelse(
  grepl("Uniform", prior), 1,
  ifelse(grepl("Beta\\(1,3", prior), dbeta(x, 1, 3),
  ifelse(grepl("Beta\\(3,1", prior), dbeta(x, 3, 1), dbeta(x, 5, 5)))))
ggplot(alpha_dens, aes(x, density, colour = prior)) +
  geom_line() +
  geom_vline(xintercept = truth$alpha, linetype = "dashed", colour = "grey40") +
  labs(title = "alpha_m prior options (dashed = true TV / Search alpha)",
       x = "alpha", y = "Density", colour = NULL)

# How to set these in meridianR. A single value applies to all channels; a
# vector gives one prior per media channel, in channel order (TV, Search).
prior_distribution(alpha_m = prior_beta(1, 3))
prior_distribution(alpha_m = prior_beta(c(3, 2), c(3, 4))) # TV: Beta(3,3), Search: Beta(2,4)


# ---- 4b. Hill saturation priors ---------------------------------------------
#
# Media is scaled so that 1 = the channel's median (population-scaled) weekly
# media. ec_m is the point where the channel reaches HALF its maximum effect.
# Default: ec_m ~ TruncatedNormal(0.8, 0.8, [0.1, 10]); slope_m fixed at 1.

set.seed(SEED)
x_media <- seq(0, 4, length.out = 200)
ec_draws <- {
  e <- rnorm(20000, 0.8, 0.8)
  head(e[e > 0.1 & e < 10], 2000)
}
hill_prior <- function(label, ec, slope) {
  curves <- vapply(seq_along(ec), function(i) hill(x_media, ec[i], slope[i]), numeric(length(x_media)))
  data.frame(prior = label, x = x_media,
             median = apply(curves, 1, median),
             lo = apply(curves, 1, quantile, 0.05),
             hi = apply(curves, 1, quantile, 0.95))
}
hill_implied <- rbind(
  hill_prior("default: slope = 1 (concave)", ec_draws, rep(1, length(ec_draws))),
  hill_prior("slope ~ LogNormal(0.7, 0.4) (S-shaped allowed)", ec_draws,
             rlnorm(length(ec_draws), 0.7, 0.4))
)
ggplot(hill_implied, aes(x, median)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "#C44E52", alpha = 0.2) +
  geom_line(colour = "#C44E52") +
  facet_wrap(~ prior) +
  labs(title = "Prior-implied Hill saturation curves (median and 90% band)",
       x = "Media units (1 = median weekly level)", y = "Fraction of max effect")

# Setting them:
prior_distribution(
  ec_m    = prior_truncated_normal(loc = 1, scale = 0.5, low = 0.1, high = 5),
  slope_m = prior_lognormal(0.7, 0.4) # let the curve be S-shaped
)


# ---- 5. Prior checks BEFORE fitting -----------------------------------------
#
# The most useful habit when choosing priors: sample ONLY the prior and look at
# what it implies for the business metrics you care about (ROI, % contribution).
# This takes seconds, no MCMC needed.

# Our baseline spec: Meridian defaults, except 10 knots for a smoother baseline
# and faster convergence (see section 3b).
spec_base <- model_spec(max_lag = 8, knots = 10)

prior_check <- function(spec, n = PRIOR_DRAWS) {
  m <- meridian_model(input, spec)
  sample_prior(m, n, seed = SEED)
  sm <- summary_metrics(m, include_posterior = FALSE)
  sm[sm$metric %in% c("mean", "ci_lo", "ci_hi"),
     c("channel", "metric", "roi", "pct_of_contribution")]
}

# Default priors: media is expected to drive ~28% of conversions (90% interval
# roughly 12-50%). The truth is ~17%.
prior_check(spec_base)

# An informed CONTRIBUTION prior is often the most natural choice for a
# non-revenue KPI: "TV drives ~10-15% of conversions, Search ~5%".
# Beta(a, b) has mean a / (a + b).
spec_contrib <- model_spec(
  max_lag = 8, knots = 10,
  media_prior_type = "contribution",
  prior = prior_distribution(contribution_m = prior_beta(c(3, 2), c(20, 30)))
)
prior_check(spec_contrib)


# ---- 6. Fit the baseline model ----------------------------------------------

mmm <- meridian_model(input, spec_base)
mmm # not sampled yet

fit(mmm,
    prior_draws = PRIOR_DRAWS,
    n_chains = MCMC$n_chains, n_adapt = MCMC$n_adapt,
    n_burnin = MCMC$n_burnin, n_keep = MCMC$n_keep,
    seed = SEED)

mmm
summary(mmm)


# ---- 6a. Convergence diagnostics ---------------------------------------------
#
# R-hat compares chains; values near 1.0 mean the chains agree. Above ~1.1-1.2
# means "run longer / reparameterize / revisit priors" before trusting results.

rhat_summary(mmm)
plot_rhat(mmm)

# Trace plot for the adstock decay rates: chains should overlap like noise.
alpha_post <- get_draws(mmm, "alpha_m", "posterior")
ggplot(alpha_post, aes(draw, value, colour = factor(chain))) +
  geom_line(alpha = 0.6, linewidth = 0.3) +
  facet_wrap(~ media_channel, ncol = 1) +
  labs(title = "Trace plot: alpha_m", colour = "chain", y = "alpha")


# ---- 6b. Model fit ------------------------------------------------------------

predictive_accuracy(mmm) # R-squared, MAPE, wMAPE (geo and national level)
plot_model_fit(mmm)      # expected vs. actual over time, with baseline

# Reuse one analyzer for many accessor calls (faster than rebuilding each time).
a <- analyzer(mmm)


# ---- 6c. Standard summaries ---------------------------------------------------

sm <- summary_metrics(a)
names(sm) # spend, impressions, roi, mroi, incremental_outcome, contribution, cpik...

# Posterior means per channel: the core MMM table.
sm[sm$distribution == "posterior" & sm$metric == "mean",
   c("channel", "spend", "incremental_outcome", "pct_of_contribution",
     "roi", "mroi", "cpik")]

# Credible intervals for ROI and contribution:
sm[sm$distribution == "posterior" & sm$metric %in% c("ci_lo", "mean", "ci_hi"),
   c("channel", "metric", "roi", "pct_of_contribution")]

plot_roi(a)
plot_contribution(a)
plot_response_curves(a)  # incremental conversions vs. spend
plot_hill_curves(a)      # saturation
plot_adstock_decay(a)    # carryover

# The analysis accessors return prior AND posterior rows, so you can plot both:
ad <- adstock_decay(a)
ggplot(ad, aes(time_units, mean, colour = distribution, fill = distribution)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15, colour = NA) +
  geom_line() +
  facet_wrap(~ channel) +
  labs(title = "Adstock decay: prior vs. posterior", x = "Weeks", y = "Weight")

hc <- hill_curves(a)
ggplot(hc[!is.na(hc$mean), ], aes(media_units, mean, colour = distribution, fill = distribution)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15, colour = NA) +
  geom_line() +
  facet_wrap(~ channel, scales = "free_x") +
  labs(title = "Hill curves: prior vs. posterior", y = "Fraction of max effect")

# Response curves as a table (e.g. what happens at 50% / 150% of current spend).
rc <- response_curves(a, spend_multipliers = c(0.5, 1, 1.5, 2))
rc[rc$metric == "mean", c("channel", "spend_multiplier", "spend", "incremental_outcome")]


# ---- 7. Prior vs. posterior: did the data move the priors? ------------------
#
# If a posterior looks just like its prior, the data had little to say about
# that parameter, and your prior choice is driving the result. Those are the
# parameters where prior experiments matter most.

pp_vars <- c("alpha_m", "ec_m", "roi_m", "beta_m")
pp <- do.call(rbind, lapply(pp_vars, function(v) {
  rbind(get_draws(mmm, v, "prior"), get_draws(mmm, v, "posterior"))
}))
# Trim extreme prior tails so the posterior is visible.
pp <- do.call(rbind, lapply(split(pp, list(pp$parameter, pp$media_channel)), function(d) {
  d[d$value <= quantile(d$value, 0.99), ]
}))

truth_long <- rbind(
  data.frame(parameter = "alpha_m", media_channel = truth$channel, value = truth$alpha),
  data.frame(parameter = "ec_m", media_channel = truth$channel, value = truth$ec)
)

ggplot(pp, aes(value, fill = group)) +
  geom_density(alpha = 0.4, colour = NA) +
  geom_vline(data = truth_long, aes(xintercept = value), linetype = "dashed") +
  facet_wrap(media_channel ~ parameter, scales = "free", ncol = 4) +
  labs(title = "Prior vs. posterior (dashed = simulation truth)",
       x = NULL, fill = NULL)

# Contribution share vs. truth:
post_contrib <- sm[sm$distribution == "posterior" & sm$metric %in% c("mean", "ci_lo", "ci_hi") &
                   sm$channel != "All Channels", c("channel", "metric", "pct_of_contribution")]
merge(reshape(as.data.frame(post_contrib), idvar = "channel", timevar = "metric",
              direction = "wide"),
      truth[c("channel", "pct_of_contribution")], by = "channel",
      suffixes = c("", "_truth"))


# ---- 8. Experiment harness: change priors, compare models ---------------------
#
# Add / edit entries in `variants` and re-run this section. Each entry is a
# model_spec(). Ideas to try:
#   * alpha_m priors: Beta(1,3), Beta(3,1), Beta(5,5), per-channel vectors
#   * adstock_decay_spec = "binomial", or per channel list(TV = "binomial")
#   * max_lag = 2, 4, 13
#   * hill_before_adstock = TRUE
#   * media_prior_type = "contribution" with informative / misleading Beta priors
#   * media_prior_type = "roi" with an explicit roi_m = prior_lognormal(log(0.02), 0.5)
#   * slope_m = prior_lognormal(0.7, 0.4) to allow S-shaped curves
#   * knots = 4 / 20 / NULL (default 104), or enable_aks = TRUE
#   * media_effects_dist = "normal", unique_sigma_for_each_geo = TRUE

variants <- list(
  baseline = spec_base,

  short_carryover = model_spec(
    max_lag = 8, knots = 10,
    prior = prior_distribution(alpha_m = prior_beta(1, 3))
  ),

  binomial_adstock = model_spec(
    max_lag = 8, knots = 10,
    adstock_decay_spec = "binomial"
  ),

  informed_contribution = spec_contrib,

  misleading_contribution = model_spec(
    max_lag = 8, knots = 10,
    media_prior_type = "contribution",
    # "Media drives ~1% of conversions" -- tight and wrong (truth ~17%).
    prior = prior_distribution(contribution_m = prior_beta(2, 200))
  )
)

fit_variant <- function(spec) {
  m <- meridian_model(input, spec)
  fit(m, prior_draws = PRIOR_DRAWS,
      n_chains = MCMC$n_chains, n_adapt = MCMC$n_adapt,
      n_burnin = MCMC$n_burnin, n_keep = MCMC$n_keep, seed = SEED)
  m
}

# Reuse the baseline we already fit; fit the rest (~1 min each).
models <- list(baseline = mmm)
for (nm in setdiff(names(variants), names(models))) {
  message("Fitting variant: ", nm)
  models[[nm]] <- fit_variant(variants[[nm]])
}

# Collect posterior summaries from every variant into one table.
compare <- do.call(rbind, lapply(names(models), function(nm) {
  s <- summary_metrics(models[[nm]], include_prior = FALSE)
  s <- s[s$channel != "All Channels" & s$metric %in% c("mean", "ci_lo", "ci_hi"),
         c("channel", "metric", "roi", "pct_of_contribution")]
  s$variant <- nm
  s
}))
compare_wide <- reshape(as.data.frame(compare), idvar = c("variant", "channel"),
                        timevar = "metric", direction = "wide")
compare_wide$variant <- factor(compare_wide$variant, levels = names(models))
compare_wide[order(compare_wide$channel, compare_wide$variant), ]

# Contribution share by variant vs. truth.
ggplot(compare_wide, aes(variant, pct_of_contribution.mean, colour = variant)) +
  geom_pointrange(aes(ymin = pct_of_contribution.ci_lo, ymax = pct_of_contribution.ci_hi)) +
  geom_hline(data = truth, aes(yintercept = pct_of_contribution), linetype = "dashed") +
  facet_wrap(~ channel, scales = "free_y") +
  coord_flip() +
  labs(title = "% of conversions driven by media, by prior choice",
       subtitle = "Dashed line = simulation truth", x = NULL, y = "% of contribution") +
  theme(legend.position = "none")

# ROI by variant.
ggplot(compare_wide, aes(variant, roi.mean, colour = variant)) +
  geom_pointrange(aes(ymin = roi.ci_lo, ymax = roi.ci_hi)) +
  facet_wrap(~ channel, scales = "free_y") +
  coord_flip() +
  labs(title = "ROI (conversions per $) by prior choice", x = NULL, y = "ROI") +
  theme(legend.position = "none")

# Adstock posterior by variant vs. truth.
alpha_cmp <- do.call(rbind, lapply(names(models), function(nm) {
  d <- get_draws(models[[nm]], "alpha_m", "posterior")
  d$variant <- nm
  d
}))
alpha_cmp$variant <- factor(alpha_cmp$variant, levels = names(models))
ggplot(alpha_cmp, aes(value, variant, fill = variant)) +
  geom_violin(alpha = 0.5, colour = NA) +
  geom_vline(data = transform(truth, media_channel = channel), aes(xintercept = alpha),
             linetype = "dashed") +
  facet_wrap(~ media_channel) +
  labs(title = "Posterior alpha_m by variant (dashed = truth)",
       subtitle = "Note: alpha means something different under binomial adstock",
       x = "alpha", y = NULL) +
  theme(legend.position = "none")

# Fit quality and convergence by variant.
do.call(rbind, lapply(names(models), function(nm) {
  pa <- predictive_accuracy(models[[nm]])
  rh <- rhat_summary(models[[nm]])
  data.frame(
    variant = nm,
    r2_national = pa$value[pa$metric == "R_Squared" & pa$geo_granularity == "national"],
    mape_geo = pa$value[pa$metric == "MAPE" & pa$geo_granularity == "geo"],
    max_rhat = max(rh$max_rhat)
  )
}))
# Typical lesson: the fit statistics barely change across priors, while ROI and
# contribution can move a lot. Fit alone cannot tell you which prior is right.


# ---- 9. Save, reload, and Meridian's own report -------------------------------
#
# The extension picks the format: .binpb = Meridian's versioned schema format
# (reloadable by other Meridian versions); .pkl = legacy pickle (same version
# only, deprecated in Meridian 2.2).

path <- file.path(tempdir(), "mmm_baseline.binpb")
save_model(mmm, path)
mmm2 <- load_model(path)
mmm2

model_report(mmm, file.path(tempdir(), "meridian_summary.html"))
# browseURL(file.path(tempdir(), "meridian_summary.html"))


# ---- 10. Escape hatch: anything in Meridian's Python API -----------------------
#
# The `meridian` object is the raw Python module. For example, the full list
# of fields on the prior container, or the adstock functions available:

reticulate::py_to_r(py_helpers$prior_fields(default_prior))
meridian$constants$ADSTOCK_DECAY_FUNCTIONS
mmm$model_spec$adstock_decay_spec
