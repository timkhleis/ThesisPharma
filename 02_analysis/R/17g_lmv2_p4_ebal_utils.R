# ============================================================================
# 17g_lmv2_p4_ebal_utils.R -- pure entropy-balancing engine for P4-EB
# ============================================================================
# Database-free. Every function here takes an already-materialized data
# frame and returns a data frame or list; no DBI/duckdb calls appear in this
# file. The solver pattern (standardize, call WeightIt::weightit(method =
# "ebal"), classify balance) is ported from 12c_verginer_ebal_utils.R's
# cell_engine_12 -- never sourced, because 12c requires
# 12a_verginer_ebal_config.R, which defines outcome-bearing globals
# (OUTCOMES, PAPER_BENCHMARKS) at top level and forces unrelated did/ggplot2
# dependencies that an outcome-blind package must not carry.
#
# The one convention 12c never exercises is non-unit s.weights on the
# TREATED side: 12c always passes s.weights = rep(1, n) for every unit, and
# 12c's own control-side finalize logic was proven correct only for that
# uniform-treated case. This package's equal-deal Stage-2 solve is the first
# real use of unequal treated s.weights (1 / inventors-in-deal, so every
# deal contributes equal aggregate treated mass), and an empirical probe
# (see local_match_v2_p4_ebal_amendment.md) established two facts that
# together fully determine lmv2_ebal_finalize_weights() below:
#   1. WeightIt::weightit(method="ebal")'s returned fit$weights[D==1] is
#      always a constant (observed: always 1) REGARDLESS of the s.weights
#      passed in for treated units -- the solver never echoes back the
#      treated-side s.weights, so fit$weights is uninformative for the
#      treated arm and must never be used there.
#   2. Unequal treated s.weights DO change the moment target the solver
#      tilts the controls toward (confirmed: a target of 6.667 under
#      uniform treated weights vs. 5.0 under 1/n-per-deal weights, both
#      recovered exactly by the controls once s.weights is applied).
# Consequently: the treated arm's final weight is the caller-supplied
# s.weights, verbatim, never fit$weights and never forced to a constant.
# The control arm's final weight is s.weights * fit$weights, rescaled so
# total control mass equals total treated mass under THIS solve's target
# (which differs by scheme). For Stage 1 and the primary Stage-2 solve,
# treated s.weights are uniformly 1, so this reduces to the original
# 12c-style behavior exactly; the equal-deal solve is where the distinction
# is load-bearing.

# ----------------------------------------------------------------------------
# Standardization, solve, finalize, classify -- the atomic per-cohort solve.
# ----------------------------------------------------------------------------

# Standardizes `vars` in `data` by that data's own mean/sd (one cohort's
# treated-plus-eligible-candidate population, per the locked
# within-cohort-treated-plus-eligible-candidate-pool convention). A
# zero-variance column is set to 0 (contributes nothing to the distance/
# balance) and recorded in `scaler$zero_variance`, never silently included
# as-is. `scaler` (variable, mean, sd, zero_variance) is the actual
# standardization population summary used for THIS roster and THIS cohort;
# it is what must be persisted downstream (e.g. into the Stage-1 freeze) and
# reused by the firm-reaggregation gate -- never a different table's
# scaler (such as P3's own distance-caliper scaler, which is computed over
# a different, unfiltered population).
lmv2_ebal_standardize_cohort <- function(vars, data) {
  out <- data
  rows <- lapply(vars, function(v) {
    x <- data[[v]]
    finite <- is.finite(x)
    s <- if (any(finite)) stats::sd(x[finite]) else NA_real_
    m <- if (any(finite)) mean(x[finite]) else NA_real_
    degenerate <- !is.finite(s) || s < LMV2_P3_DISTANCE_EPSILON
    out[[v]] <<- if (degenerate) rep(0, nrow(data)) else (x - m) / s
    data.frame(variable = v, mean = m, sd = if (degenerate) NA_real_ else s,
              zero_variance = degenerate, stringsAsFactors = FALSE)
  })
  scaler <- do.call(rbind, rows)
  list(data = out, zero_variance = scaler$variable[scaler$zero_variance], scaler = scaler)
}

# One WeightIt::weightit(method = "ebal") solve for one cohort. `s_weights`
# are the base/prior weights entering the tilt (uniform ones at Stage 1;
# Stage-1-allocated base weights at Stage 2, for controls; a per-scheme
# treated weighting for treated units -- see lmv2_ebal_stage2_roster()).
# Errors are caught, never thrown, so the caller can classify the failure
# state.
lmv2_ebal_fit_cohort <- function(vars, data, D_col = "D", s_weights,
                                 estimand = "ATT", moments = 1,
                                 maxit = LMV2_P4_EBAL$tolerances$maxit) {
  stopifnot(nrow(data) == length(s_weights), D_col %in% names(data))
  std <- lmv2_ebal_standardize_cohort(vars, data)
  use_vars <- setdiff(vars, std$zero_variance)
  if (!length(use_vars)) {
    return(list(fit = simpleError("no non-degenerate balance variables"),
               zero_variance = std$zero_variance, formula_vars = use_vars,
               standardized_data = std$data, scaler = std$scaler))
  }
  form <- stats::as.formula(paste(D_col, "~", paste(use_vars, collapse = " + ")))
  fit <- tryCatch(
    WeightIt::weightit(form, data = std$data, method = "ebal", estimand = estimand,
                       moments = moments, s.weights = s_weights, maxit = maxit),
    error = function(e) e
  )
  list(fit = fit, zero_variance = std$zero_variance, formula_vars = use_vars,
       standardized_data = std$data, scaler = std$scaler)
}

# Resolved convention (see file header and the amendment): treated final
# weight = s.weights, verbatim (WeightIt never touches the treated arm, and
# unequal treated s.weights are precisely how a scheme's target moment is
# defined -- forcing them to 1 would silently discard the equal-deal
# scheme's entire target). Control final weight = s.weights * fit$weights,
# rescaled so total control mass equals total treated mass under this
# solve's own target. `ok = FALSE` distinguishes a solver error from a
# degenerate mass from a downstream weight defect, so the caller can assign
# the correct failure-state label.
lmv2_ebal_finalize_weights <- function(fit, D, s_weights) {
  n <- length(D)
  if (inherits(fit, "condition")) {
    return(list(ok = FALSE, reason = "no_feasible_entropy_solution",
               weight = rep(NA_real_, n)))
  }
  raw <- fit$weights
  combined <- ifelse(D == 1, s_weights, raw * s_weights)
  control_mass_pre_rescale <- sum(combined[D == 0])
  treated_mass <- sum(combined[D == 1])
  if (!is.finite(control_mass_pre_rescale) || control_mass_pre_rescale <= 0) {
    return(list(ok = FALSE, reason = "inadequate_control_mass",
               weight = combined, control_mass_pre_rescale = control_mass_pre_rescale,
               treated_mass = treated_mass))
  }
  rescale <- treated_mass / control_mass_pre_rescale
  out <- combined
  out[D == 0] <- combined[D == 0] * rescale
  weights_ok <- all(is.finite(out)) && all(out[D == 0] > 0) && all(out[D == 1] > 0)
  list(ok = TRUE, weight = out, treated_weight = out[D == 1], control_weight = out[D == 0],
       control_mass_pre_rescale = control_mass_pre_rescale,
       treated_mass = treated_mass, rescale_factor = rescale, weights_ok = weights_ok)
}

# Post-standardization weighted mean difference (control minus treated) is
# already in SD units, so this is directly comparable to exact_tol/
# residual_tol without a further division. Generic in `w[D==1]`, so it is
# correct regardless of whether treated weights are uniform (Stage 1,
# primary Stage 2) or the equal-deal scheme's unequal weights.
lmv2_ebal_covariate_balance <- function(vars, data_std, D, w) {
  if (!length(vars)) {
    return(data.frame(variable = character(), treated_mean = numeric(),
                      control_mean = numeric(), difference = numeric(),
                      abs_difference = numeric()))
  }
  do.call(rbind, lapply(vars, function(v) {
    tm <- sum(w[D == 1] * data_std[[v]][D == 1]) / sum(w[D == 1])
    cm <- sum(w[D == 0] * data_std[[v]][D == 0]) / sum(w[D == 0])
    data.frame(variable = v, treated_mean = tm, control_mean = cm,
              difference = cm - tm, abs_difference = abs(cm - tm),
              stringsAsFactors = FALSE)
  }))
}

lmv2_ebal_balance_maxdiff <- function(vars, data_std, D, w) {
  if (!length(vars)) return(0)
  max(lmv2_ebal_covariate_balance(vars, data_std, D, w)$abs_difference)
}

lmv2_ebal_classify <- function(maxdiff, exact_tol = LMV2_P4_EBAL$tolerances$exact_tol,
                               residual_tol = LMV2_P4_EBAL$tolerances$residual_tol) {
  if (!is.finite(maxdiff)) return(list(tier = "failed_residual_balance_tolerance", converged = FALSE))
  if (maxdiff <= exact_tol) return(list(tier = "exact", converged = TRUE))
  if (maxdiff <= residual_tol) return(list(tier = "acceptable", converged = TRUE))
  list(tier = "failed_residual_balance_tolerance", converged = FALSE)
}

lmv2_ebal_ess <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (!length(w)) return(0)
  sum(w)^2 / sum(w^2)
}

# `w` must already be one row per unique unit (a Stage-1/Stage-2 roster row
# is one unique control firm/inventor within its cohort by construction), so
# no reuse-adjustment is needed here; cross-cohort reuse is a clustering
# concern handled by the caller, never by this function.
lmv2_ebal_concentration <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (!length(w)) {
    return(list(max_share = NA_real_, top5_share = NA_real_,
               top1pct_share = NA_real_, n_materially_weighted = NA_integer_))
  }
  total <- sum(w)
  sw <- sort(w, decreasing = TRUE)
  k1pct <- max(1L, ceiling(0.01 * length(w)))
  list(max_share = sw[1] / total,
       top5_share = sum(sw[seq_len(min(5L, length(sw)))]) / total,
       top1pct_share = sum(sw[seq_len(k1pct)]) / total,
       n_materially_weighted = sum(w / total > 0.01))
}

# Master per-cohort dispatcher: fit, finalize, classify, diagnose. Returns
# one of the taxonomy's active-gating statuses, or "pass" with a tier.
# `inadequate_ess`/`excessive_weight_concentration` are never returned here
# as a failing status -- E1's ESS and concentration thresholds are diagnostic
# only (see the amendment, "Deferred E2 choices"); this function always
# reports ess/concentration in the output regardless of status. `data` must
# already be one row per unique unit (a roster row is one unique control
# firm/inventor within its cohort by construction), so ESS/concentration
# need no separate unit-id argument or reuse-adjustment here. `treated_weight`
# and `control_weight` are exposed separately (not only the combined
# `weight` vector) so no downstream caller can accidentally assume treated
# weight one for both estimands.
lmv2_ebal_run_cohort <- function(vars, data, D_col = "D", s_weights,
                                 exact_tol = LMV2_P4_EBAL$tolerances$exact_tol,
                                 residual_tol = LMV2_P4_EBAL$tolerances$residual_tol,
                                 maxit = LMV2_P4_EBAL$tolerances$maxit,
                                 estimand = "ATT", moments = 1) {
  stopifnot(nrow(data) == length(s_weights))
  D <- data[[D_col]]
  if (!any(D == 1) || !any(D == 0)) {
    return(list(status = "empty_treated_or_control_cell",
               weight = rep(NA_real_, nrow(data)),
               n_treated = sum(D == 1), n_control = sum(D == 0)))
  }
  fitted <- lmv2_ebal_fit_cohort(vars, data, D_col, s_weights, estimand, moments, maxit)
  finalize <- lmv2_ebal_finalize_weights(fitted$fit, D, s_weights)
  base <- list(zero_variance = fitted$zero_variance, formula_vars = fitted$formula_vars,
              scaler = fitted$scaler, n_treated = sum(D == 1), n_control = sum(D == 0),
              control_mass_pre_rescale = finalize$control_mass_pre_rescale,
              treated_mass = finalize$treated_mass, rescale_factor = finalize$rescale_factor)
  if (!finalize$ok) {
    return(c(list(status = finalize$reason, weight = finalize$weight), base))
  }
  if (!finalize$weights_ok) {
    return(c(list(status = "zero_negative_or_undefined_weight", weight = finalize$weight,
                 treated_weight = finalize$treated_weight, control_weight = finalize$control_weight),
            base))
  }
  maxdiff <- lmv2_ebal_balance_maxdiff(fitted$formula_vars, fitted$standardized_data,
                                       D, finalize$weight)
  balance_table <- lmv2_ebal_covariate_balance(fitted$formula_vars, fitted$standardized_data,
                                               D, finalize$weight)
  cls <- lmv2_ebal_classify(maxdiff, exact_tol, residual_tol)
  ess <- lmv2_ebal_ess(finalize$control_weight)
  conc <- lmv2_ebal_concentration(finalize$control_weight)
  c(list(status = if (cls$converged) "pass" else "failed_residual_balance_tolerance",
        tier = cls$tier, weight = finalize$weight, treated_weight = finalize$treated_weight,
        control_weight = finalize$control_weight, maxdiff = maxdiff, balance = balance_table,
        ess = ess, concentration = conc),
   base)
}

# ----------------------------------------------------------------------------
# Stage-1: admissible deal-firm edges and the unique firm pool derived from
# them -- two distinct interfaces, never collapsed into one. The deal-level
# edges are needed downstream to build Stage-2 inventor pairs (a control
# inventor is only locally admissible for a treated inventor whose DEAL
# admits that inventor's firm); the unique firm pool is what the Stage-1
# entropy solver balances.
# ----------------------------------------------------------------------------

# `edges`: cohort, deal_id, control_group, distance (Stage-1 firm edges at a
# single chosen distance variant/resolution; caller selects the distance
# column before calling). `caliper` is a required, explicit deferred-choice
# parameter (see the amendment) -- there is no default. Returns one row per
# (cohort, deal_id, control_group) surviving the caliper.
lmv2_ebal_stage1_admissible_edges <- function(edges, caliper) {
  required <- c("cohort", "deal_id", "control_group", "distance")
  if (!all(required %in% names(edges))) stop("Stage-1 edge schema invalid")
  keep <- lmv2_apply_total_caliper(edges$distance, caliper)
  x <- unique(edges[keep, required])
  x[order(x$cohort, x$deal_id, x$control_group), ]
}

# Collapses admissible deal-firm edges to one row per unique (cohort,
# control_group), with a diagnostic count of how many distinct treated deals
# admit that firm. This -- never the deal-level edges -- is what enters the
# Stage-1 entropy solver: a control firm must appear only once in the roster.
lmv2_ebal_stage1_unique_firm_pool <- function(admissible_firm_edges) {
  required <- c("cohort", "deal_id", "control_group")
  if (!all(required %in% names(admissible_firm_edges))) stop("Admissible-edge schema invalid")
  x <- admissible_firm_edges
  if (!nrow(x)) {
    return(data.frame(cohort = integer(), control_group = numeric(),
                      n_admissible_treated_deals = integer()))
  }
  n_deals <- stats::aggregate(x$deal_id, x[c("cohort", "control_group")],
                              function(v) length(unique(v)))
  names(n_deals)[3] <- "n_admissible_treated_deals"
  n_deals[order(n_deals$cohort, n_deals$control_group), ]
}

# ----------------------------------------------------------------------------
# Stage-2: admissible inventor edges, unique eligible controls, and
# supported treated inventors -- three distinct interfaces, never collapsed
# into one. Retention accounting requires the (cohort, deal_id,
# treated_codinv) grain; collapsing it away (as an earlier version of this
# file did) makes every treated inventor look "retained" and corrupts
# retention to a meaningless control-row count.
# ----------------------------------------------------------------------------

# Restricts admissible firm edges to firms holding POSITIVE Stage-1 weight
# IN THAT SPECIFIC COHORT -- a semi-join on (cohort, control_group), never
# on control_group alone. The same firm id can legitimately recur across
# pseudo-event cohorts; a firm weighted in cohort A but not cohort B must
# never have its cohort-B edges admitted merely because the same id
# happens to carry positive weight somewhere else. This must run BEFORE
# lmv2_ebal_build_stage2_candidate_pairs(), so the extra (cohort, firm)
# combinations never reach technology-similarity or distance construction
# in the first place -- filtering them out only afterward would let them
# already influence within-cohort scaling and calipers.
lmv2_ebal_restrict_to_frozen_firms <- function(admissible_firm_edges, stage1_weights) {
  required <- c("cohort", "control_group")
  if (!all(required %in% names(admissible_firm_edges))) stop("Admissible firm-edge schema invalid")
  if (!all(c(required, "weight") %in% names(stage1_weights))) stop("Stage-1 weight schema invalid")
  frozen <- unique(stage1_weights[stage1_weights$weight > 0, required, drop = FALSE])
  key <- function(d) paste(d$cohort, d$control_group)
  admissible_firm_edges[key(admissible_firm_edges) %in% key(frozen), , drop = FALSE]
}

# Deal-specific candidate pairs, built by joining treated inventors to
# control donors THROUGH the deal-level admissible firm edges -- never by
# crossing every treated inventor in a cohort against every admissible (or
# positive-weight) firm in the cohort. A firm admissible only for Deal A
# must never supply candidate controls for Deal B, even if that firm ends
# up with positive Stage-1 weight: Stage-1 admissibility is deal-specific,
# and Stage 2 must preserve that specificity, not silently widen it to
# "any eligible firm in the cohort." This is the one join both 17h (before
# the Stage-1 solve, over ALL caliper-admissible candidate firms) and 17i
# (after the Stage-1 solve, over positive-weight firms only) must use, so
# the restriction can never regress independently in either caller.
# `admissible_firm_edges`: cohort, deal_id, control_group (from
# lmv2_ebal_stage1_admissible_edges(), optionally pre-filtered by the
# caller to a specific firm subset, e.g. positive-Stage-1-weight firms).
# `donor_firms`: cohort, control_codinv, control_group (the raw donor
# roster, before any technology/recency filtering). `treated_spine`:
# cohort, deal_id, treated_codinv. Returns cohort, deal_id, treated_codinv,
# control_codinv, control_group -- ready for technology/recency filtering
# and lmv2_prepare_stage2_edges().
lmv2_ebal_build_stage2_candidate_pairs <- function(admissible_firm_edges, donor_firms, treated_spine) {
  required_edges <- c("cohort", "deal_id", "control_group")
  required_donors <- c("cohort", "control_codinv", "control_group")
  required_treated <- c("cohort", "deal_id", "treated_codinv")
  if (!all(required_edges %in% names(admissible_firm_edges))) stop("Admissible firm-edge schema invalid")
  if (!all(required_donors %in% names(donor_firms))) stop("Donor-firm schema invalid")
  if (!all(required_treated %in% names(treated_spine))) stop("Treated-spine schema invalid")
  pool <- unique(admissible_firm_edges[required_edges])
  pairs <- merge(pool, donor_firms[required_donors], by = c("cohort", "control_group"))
  pairs <- merge(treated_spine[required_treated], pairs, by = c("cohort", "deal_id"))
  pairs[order(pairs$cohort, pairs$deal_id, pairs$treated_codinv, pairs$control_codinv),
       c("cohort", "deal_id", "treated_codinv", "control_codinv", "control_group")]
}

# `stage2_edges`: output of lmv2_prepare_stage2_edges()$edges (already
# shared-IPC4- and recency-gap-filtered, one row per treated-control pair
# admissible at the DEAL level -- i.e. already restricted to pairs whose
# control firm is admissible for that treated inventor's deal). Applies the
# Stage-2 caliper only; never collapses deal_id/treated_codinv away.
lmv2_ebal_stage2_admissible_edges <- function(stage2_edges, caliper) {
  required <- c("cohort", "deal_id", "treated_codinv", "control_codinv",
                "control_group", "distance")
  if (!all(required %in% names(stage2_edges))) stop("Stage-2 edge schema invalid")
  keep <- lmv2_apply_total_caliper(stage2_edges$distance, caliper)
  x <- unique(stage2_edges[keep, required])
  x[order(x$cohort, x$deal_id, x$treated_codinv, x$control_codinv), ]
}

# Unique eligible control inventors (cohort-level union across all treated
# inventors), derived from admissible edges -- used to build the Stage-2
# donor pool. Never used to determine treated retention (see
# lmv2_ebal_stage2_supported_treated() for that).
lmv2_ebal_stage2_eligible_controls <- function(admissible_edges) {
  required <- c("cohort", "control_codinv", "control_group")
  if (!all(required %in% names(admissible_edges))) stop("Admissible-edge schema invalid")
  if (!nrow(admissible_edges)) {
    return(data.frame(cohort = integer(), control_codinv = numeric(),
                      control_group = numeric(), n_admissible_treated_inventors = integer()))
  }
  eligible <- unique(admissible_edges[required])
  n_treated <- stats::aggregate(admissible_edges$treated_codinv,
                                admissible_edges[c("cohort", "control_codinv")],
                                function(v) length(unique(v)))
  names(n_treated)[3] <- "n_admissible_treated_inventors"
  eligible <- merge(eligible, n_treated, by = c("cohort", "control_codinv"), sort = FALSE)
  eligible[order(eligible$cohort, eligible$control_codinv), ]
}

lmv2_ebal_stage2_eligible_firms <- function(eligible_controls) {
  required <- c("cohort", "control_group")
  if (!all(required %in% names(eligible_controls))) stop("Eligible-controls schema invalid")
  unique(eligible_controls[required])
}

# Treated inventors retained in common support, keyed by (cohort, deal_id,
# treated_codinv) -- the grain retention accounting requires. `treated_spine`
# is the population entering the Stage-2 caliper check (after upstream
# funnel steps: deal lost at Stage 1, missing covariates, etc. -- see
# lmv2_ebal_funnel_step()). A treated inventor is "supported" iff it has
# >=1 admissible edge in `admissible_edges`; the caller must have already
# restricted `admissible_edges` to positive-Stage-1-weight firms (this
# function does not check that itself, so it can also be used, if ever
# needed, on the pre-Stage-1-result candidate edges for diagnostics).
lmv2_ebal_stage2_supported_treated <- function(admissible_edges, treated_spine) {
  required <- c("cohort", "deal_id", "treated_codinv")
  if (!all(required %in% names(treated_spine))) stop("Treated-spine schema invalid")
  supported_keys <- if (nrow(admissible_edges)) unique(admissible_edges[required]) else
    treated_spine[FALSE, required]
  key <- function(d) paste(d$cohort, d$deal_id, d$treated_codinv, sep = "\r")
  supported_idx <- key(treated_spine) %in% key(supported_keys)
  excluded <- treated_spine[!supported_idx, , drop = FALSE]
  if (nrow(excluded)) excluded$reason <- "no_admissible_control_inventor"
  list(supported = treated_spine[supported_idx, , drop = FALSE],
       excluded = excluded)
}

# ----------------------------------------------------------------------------
# Roster construction (unique-unit grain, cohort-level union of candidates).
# ----------------------------------------------------------------------------

# Pre-filters `firm_pool` (the unique Stage-1 admissible firm pool) to firms
# already known to have >=1 Stage-2-eligible inventor (`eligible_firms`,
# from lmv2_ebal_stage2_eligible_firms()), so a firm never receives Stage-1
# weight it could later lose entirely at Stage 2 (zero lost mass by
# construction). Firms admissible by the firm caliper but excluded at this
# pre-check are returned separately with an explicit reason, never dropped
# silently.
lmv2_ebal_stage1_roster <- function(firm_pool, eligible_firms,
                                    treated_firm_covars, control_firm_covars) {
  fvars <- c("log_patent_stock_5y", "log_inventor_count_5y", "patent_trajectory")
  stopifnot(all(c("cohort", "deal_id") %in% names(treated_firm_covars)),
            all(fvars %in% names(treated_firm_covars)),
            all(c("cohort", "control_group") %in% names(control_firm_covars)),
            all(fvars %in% names(control_firm_covars)))
  key <- function(d) paste(d$cohort, d$control_group)
  admitted_idx <- key(firm_pool) %in% key(eligible_firms)
  admitted <- firm_pool[admitted_idx, , drop = FALSE]
  excluded <- firm_pool[!admitted_idx, , drop = FALSE]
  if (nrow(excluded)) excluded$reason <- "zero_stage2_eligible_inventors"

  # rep(value, nrow(.)) throughout, not bare scalar assignment: this R
  # installation's data.frame $<- does not recycle a length-1 value onto a
  # zero-row frame (errors instead), and roster construction must handle
  # zero-row cohorts (e.g. a cohort with no admitted control firms).
  ctrl <- merge(admitted, control_firm_covars, by = c("cohort", "control_group"), sort = FALSE)
  ctrl$side <- rep("control", nrow(ctrl)); ctrl$D <- rep(0L, nrow(ctrl))
  ctrl$deal_id <- rep(NA_integer_, nrow(ctrl))

  trt <- treated_firm_covars[c("cohort", "deal_id", fvars)]
  trt$side <- rep("treated", nrow(trt)); trt$D <- rep(1L, nrow(trt))
  trt$control_group <- rep(NA_real_, nrow(trt))
  trt$n_admissible_treated_deals <- rep(NA_integer_, nrow(trt))

  common <- c("cohort", "side", "D", "deal_id", "control_group", fvars,
             "n_admissible_treated_deals")
  roster <- rbind(trt[common], ctrl[common])
  roster <- roster[order(roster$cohort, -roster$D, roster$control_group), ]
  list(roster = roster, excluded_firms = excluded[c("cohort", "control_group", "reason")])
}

# Equal-split allocation of each Stage-1 firm's entropy weight across its
# Stage-2-eligible inventors. Every positive-weight firm is asserted (not
# merely hoped) to have local support, because Stage-1 admission already
# required it -- a violation here is an internal roster-construction defect,
# never a legitimate lost-mass case.
lmv2_ebal_allocate_base_weights <- function(stage1_weights, eligible_controls) {
  required_w <- c("cohort", "control_group", "weight")
  required_ec <- c("cohort", "control_codinv", "control_group")
  if (!all(required_w %in% names(stage1_weights))) stop("Stage-1 weight schema invalid")
  if (!all(required_ec %in% names(eligible_controls))) stop("Eligible-controls schema invalid")
  pos <- stage1_weights[stage1_weights$weight > 0, , drop = FALSE]
  if (!nrow(pos)) {
    return(data.frame(cohort = integer(), control_codinv = numeric(),
                      control_group = numeric(), base_weight = numeric()))
  }
  key <- function(d) paste(d$cohort, d$control_group)
  ls <- eligible_controls[key(eligible_controls) %in% key(pos), , drop = FALSE]

  # Every positive-weight firm must already have local support -- Stage-1
  # admission required this (lmv2_ebal_stage1_roster's pre-filter). Checking
  # only the firms that happen to survive the merge below would silently
  # pass even if a positive-weight firm is entirely absent from
  # `eligible_controls`; this check catches that case explicitly, as a
  # roster-construction defect, never a legitimate lost-mass case to work
  # around.
  missing_firms <- pos[!(key(pos) %in% key(ls)), , drop = FALSE]
  if (nrow(missing_firms)) {
    stop("lmv2_ebal_allocate_base_weights: positive-weight firm(s) have zero ",
        "Stage-2 local support -- roster pre-filter invariant violated: ",
        paste(sprintf("(cohort=%s, control_group=%s)", missing_firms$cohort,
                      missing_firms$control_group), collapse = "; "))
  }

  n_elig <- stats::aggregate(ls$control_codinv, ls[c("cohort", "control_group")],
                             function(v) length(unique(v)))
  names(n_elig)[3] <- "n_eligible"
  stopifnot(all(n_elig$n_eligible >= 1L))

  wt <- merge(unique(ls[c("cohort", "control_codinv", "control_group")]),
             pos[c("cohort", "control_group", "weight")],
             by = c("cohort", "control_group"), sort = FALSE)
  wt <- merge(wt, n_elig, by = c("cohort", "control_group"), sort = FALSE)
  wt$base_weight <- wt$weight / wt$n_eligible

  conserved <- stats::aggregate(wt$base_weight, wt[c("cohort", "control_group")], sum)
  names(conserved)[3] <- "allocated"
  conserved <- merge(conserved, pos[c("cohort", "control_group", "weight")],
                     by = c("cohort", "control_group"), sort = FALSE)
  stopifnot(all(abs(conserved$allocated - conserved$weight) < 1e-9))

  wt <- wt[order(wt$cohort, wt$control_group, wt$control_codinv), ]
  wt[c("cohort", "control_codinv", "control_group", "base_weight")]
}

# Stage-2 roster. `supported_treated` (from lmv2_ebal_stage2_supported_treated())
# is used to RESTRICT `treated_inv_covars` to common support inside this
# function itself -- common support is enforced here, not merely assumed
# from caller discipline. `treated_weighting = "primary"` gives every
# retained treated inventor initial weight 1; `"equal_deal"` gives every
# retained treated inventor initial weight 1 / (retained inventors in its
# deal), so each deal contributes equal total mass -- a genuinely different
# treated target distribution, requiring its own solve, never a
# renormalization of the primary solve's result.
lmv2_ebal_stage2_roster <- function(base_weights, treated_inv_covars, control_inv_covars,
                                    supported_treated,
                                    treated_weighting = c("primary", "equal_deal")) {
  treated_weighting <- match.arg(treated_weighting)
  ivars <- c("log_patent_count_5y", "patent_trajectory", "career_age",
            "focal_group_tenure", "focal_group_exclusivity")
  stopifnot(all(c("cohort", "deal_id", "treated_codinv") %in% names(treated_inv_covars)),
            all(ivars %in% names(treated_inv_covars)),
            all(c("cohort", "control_codinv", "control_group") %in% names(control_inv_covars)),
            all(ivars %in% names(control_inv_covars)),
            all(c("cohort", "deal_id", "treated_codinv") %in% names(supported_treated)))

  key <- function(d) paste(d$cohort, d$deal_id, d$treated_codinv, sep = "\r")
  trt <- treated_inv_covars[key(treated_inv_covars) %in% key(supported_treated), , drop = FALSE]
  trt <- trt[c("cohort", "deal_id", "treated_codinv", ivars)]

  # control_group is authoritative from base_weights (the Stage-1 allocation
  # target); dropped from control_inv_covars before merging so the two
  # sources never collide into control_group.x/control_group.y.
  ctrl_ids <- unique(base_weights[c("cohort", "control_codinv", "control_group", "base_weight")])
  covars_no_group <- control_inv_covars[setdiff(names(control_inv_covars), "control_group")]
  ctrl <- merge(ctrl_ids, covars_no_group, by = c("cohort", "control_codinv"), sort = FALSE)
  ctrl$side <- rep("control", nrow(ctrl)); ctrl$D <- rep(0L, nrow(ctrl))
  ctrl$deal_id <- rep(NA_integer_, nrow(ctrl)); ctrl$treated_codinv <- rep(NA_real_, nrow(ctrl))

  trt$side <- rep("treated", nrow(trt)); trt$D <- rep(1L, nrow(trt))
  trt$control_codinv <- rep(NA_real_, nrow(trt)); trt$control_group <- rep(NA_real_, nrow(trt))
  if (treated_weighting == "primary") {
    trt$base_weight <- rep(1, nrow(trt))
  } else {
    grp <- paste(trt$cohort, trt$deal_id)
    counts <- table(grp)
    trt$base_weight <- 1 / as.numeric(counts[grp])
  }

  common <- c("cohort", "side", "D", "deal_id", "treated_codinv", "control_codinv",
             "control_group", ivars, "base_weight")
  roster <- rbind(trt[common], ctrl[common])
  roster[order(roster$cohort, -roster$D, roster$deal_id, roster$treated_codinv,
              roster$control_codinv), ]
}

# ----------------------------------------------------------------------------
# Retention accounting: keyed by (cohort, deal_id, treated_codinv) via
# `supported`/`treated_spine`, never by counting control-weight rows.
# ----------------------------------------------------------------------------

lmv2_ebal_retention_summary <- function(supported, treated_spine, deal_category = NULL) {
  required <- c("cohort", "deal_id", "treated_codinv")
  stopifnot(all(required %in% names(supported)), all(required %in% names(treated_spine)))
  deal_key <- function(d) paste(d$cohort, d$deal_id, sep = "\r")

  summarize <- function(elig, ret) {
    ed <- unique(elig[c("cohort", "deal_id")])
    rd <- unique(ret[c("cohort", "deal_id")])
    n_ed <- nrow(ed)
    n_rd <- sum(deal_key(ed) %in% deal_key(rd))
    data.frame(
      n_eligible_inventors = nrow(elig), n_retained_inventors = nrow(ret),
      inventor_retention = if (nrow(elig) > 0) nrow(ret) / nrow(elig) else NA_real_,
      n_eligible_deals = n_ed, n_retained_deals = n_rd,
      deal_retention = if (n_ed > 0) n_rd / n_ed else NA_real_
    )
  }

  overall <- summarize(treated_spine, supported)
  by_cohort <- do.call(rbind, lapply(sort(unique(treated_spine$cohort)), function(g) {
    cbind(cohort = g, summarize(treated_spine[treated_spine$cohort == g, , drop = FALSE],
                                supported[supported$cohort == g, , drop = FALSE]))
  }))

  by_category <- NULL
  if (!is.null(deal_category)) {
    stopifnot(all(c("cohort", "deal_id", "category") %in% names(deal_category)))
    te_cat <- merge(treated_spine, deal_category, by = c("cohort", "deal_id"), sort = FALSE)
    ts_cat <- merge(supported, deal_category, by = c("cohort", "deal_id"), sort = FALSE)
    by_category <- do.call(rbind, lapply(sort(unique(te_cat$category)), function(cat) {
      cbind(category = cat, summarize(te_cat[te_cat$category == cat, , drop = FALSE],
                                      ts_cat[ts_cat$category == cat, , drop = FALSE]))
    }))
  }
  list(overall = overall, by_cohort = by_cohort, by_category = by_category)
}

# Applies the locked pilot retention tiers (LMV2_LOCK$pilot$stage_2_*, wired
# through LMV2_P4_EBAL$stage_2$preferred/acceptable in 17f) -- no new
# numbers are introduced here: preferred >=90% inventor and >=90% deal
# retention; acceptable >=80% inventor and >=85% deal retention; every
# cohort >=50% inventor retention; no target-size category loses every
# retained inventor.
lmv2_ebal_retention_gate <- function(retention,
                                     preferred = LMV2_P4_EBAL$stage_2$preferred,
                                     acceptable = LMV2_P4_EBAL$stage_2$acceptable) {
  ov <- retention$overall
  bc <- retention$by_cohort
  cohort_floor_ok <- nrow(bc) > 0 &&
    isTRUE(all(!is.na(bc$inventor_retention) &
                bc$inventor_retention >= acceptable$minimum_cohort_retention))
  category_preserved <- if (is.null(retention$by_category)) TRUE else
    isTRUE(all(retention$by_category$n_retained_inventors > 0))

  preferred_pass <- isTRUE(ov$inventor_retention >= preferred$inventor_retention) &&
    isTRUE(ov$deal_retention >= preferred$deal_retention) &&
    cohort_floor_ok && category_preserved
  acceptable_pass <- isTRUE(ov$inventor_retention >= acceptable$inventor_retention_min) &&
    isTRUE(ov$deal_retention >= acceptable$deal_retention) &&
    cohort_floor_ok && category_preserved

  tier <- if (preferred_pass) "preferred" else if (acceptable_pass) "acceptable" else "failed_retention"
  list(tier = tier, pass = tier != "failed_retention",
       label = lmv2_ebal_retention_label(ov$inventor_retention),
       cohort_floor_ok = cohort_floor_ok, category_preserved = category_preserved)
}

# Reuses the locked common-support label threshold
# (LMV2_LOCK$estimands$common_support_label_below_retention) -- no new
# numbers are introduced here.
lmv2_ebal_retention_label <- function(inventor_retention,
                                      threshold = LMV2_P4_EBAL$estimand$common_support_label_below_retention) {
  if (!is.finite(inventor_retention) || inventor_retention < threshold) "common-support ATT"
  else LMV2_P4_EBAL$estimand$primary
}

# Activates the ESS and weight-concentration gates locked in the pre-E2
# amendment (LMV2_P4_EBAL$stage_1/stage_2$ess_ratio and $max_share),
# derived from non-outcome candidate-pool-size diagnostics -- never from
# inspecting actual solved weights. `per_cohort`: a stage pipeline's
# per-cohort solve list (lmv2_ebal_stage1_pipeline()$per_cohort or
# lmv2_ebal_stage2_pipeline()$per_cohort); each element's `$ess`,
# `$concentration$max_share`, and `$n_treated` (deals at Stage 1, inventors
# at Stage 2) are read directly, never recomputed. A missing cohort or a
# missing/non-finite diagnostic fails the gate, exactly like the retention
# gate -- nothing is silently skipped.
lmv2_ebal_ess_concentration_gate <- function(per_cohort, ess_ratio, max_share) {
  if (!length(per_cohort)) {
    return(list(tier = "failed_ess_concentration", pass = FALSE, detail = data.frame()))
  }
  detail <- do.call(rbind, lapply(names(per_cohort), function(nm) {
    r <- per_cohort[[nm]]
    ess <- if (is.null(r$ess)) NA_real_ else r$ess
    share <- if (is.null(r$concentration)) NA_real_ else r$concentration$max_share
    n_units <- if (is.null(r$n_treated)) NA_real_ else r$n_treated
    ratio <- if (is.finite(ess) && is.finite(n_units) && n_units > 0) ess / n_units else NA_real_
    data.frame(cohort = nm, ess = ess, n_treated = n_units, ess_ratio = ratio, max_share = share,
              stringsAsFactors = FALSE)
  }))
  preferred_pass <- isTRUE(all(!is.na(detail$ess_ratio) & detail$ess_ratio >= ess_ratio$preferred)) &&
    isTRUE(all(!is.na(detail$max_share) & detail$max_share <= max_share$preferred))
  acceptable_pass <- isTRUE(all(!is.na(detail$ess_ratio) & detail$ess_ratio >= ess_ratio$acceptable)) &&
    isTRUE(all(!is.na(detail$max_share) & detail$max_share <= max_share$acceptable))
  tier <- if (preferred_pass) "preferred" else if (acceptable_pass) "acceptable" else "failed_ess_concentration"
  list(tier = tier, pass = tier != "failed_ess_concentration", detail = detail)
}

# ----------------------------------------------------------------------------
# Post-Stage-2 firm-balance gate: re-aggregate final inventor weights to the
# firm level and compare against the estimand-correct treated target, never
# against the original Stage-1 prior (movement from the prior is reported
# separately as a diagnostic, never gated).
# ----------------------------------------------------------------------------

# Estimand-correct treated firm target for the firm-reaggregation gate,
# built from RETAINED (supported) treated inventors only -- never the
# unrestricted P3 population. `treated_firm_covars`: cohort, deal_id, plus
# the three firm balance variables (the DEAL's target firm's covariates,
# not the inventor's own). Primary: deals weighted by retained-inventor
# count; equal_deal: every retained deal contributes equal weight.
lmv2_ebal_treated_firm_target <- function(supported_treated, treated_firm_covars,
                                          treated_weighting = c("primary", "equal_deal")) {
  treated_weighting <- match.arg(treated_weighting)
  fvars <- c("log_patent_stock_5y", "log_inventor_count_5y", "patent_trajectory")
  stopifnot(all(c("cohort", "deal_id") %in% names(treated_firm_covars)),
            all(fvars %in% names(treated_firm_covars)))
  if (!nrow(supported_treated)) {
    return(data.frame(cohort = integer(), variable = character(), treated_mean = numeric()))
  }
  deal_counts <- stats::aggregate(rep(1L, nrow(supported_treated)),
                                  supported_treated[c("cohort", "deal_id")], sum)
  names(deal_counts)[3] <- "n_retained_inventors"
  deal_counts$firm_weight <- if (treated_weighting == "primary") deal_counts$n_retained_inventors else
    rep(1, nrow(deal_counts))
  tf <- merge(deal_counts, treated_firm_covars, by = c("cohort", "deal_id"), sort = FALSE)
  do.call(rbind, lapply(fvars, function(v) {
    do.call(rbind, lapply(sort(unique(tf$cohort)), function(g) {
      tg <- tf[tf$cohort == g, , drop = FALSE]
      target <- if (nrow(tg) && sum(tg$firm_weight) > 0) {
        sum(tg$firm_weight * tg[[v]]) / sum(tg$firm_weight)
      } else NA_real_
      data.frame(cohort = g, variable = v, treated_mean = target)
    }))
  }))
}

# `treated_firm_target`: data.frame(cohort, variable, treated_mean), built
# by lmv2_ebal_treated_firm_target() from retained treated inventors under
# THIS estimand. `cohort_firm_scaler`: data.frame(cohort, variable, mean,
# sd, zero_variance) -- the ACTUAL Stage-1 entropy-balancing standardization
# population's scaler (from lmv2_ebal_run_cohort()$scaler, persisted across
# cohorts by the caller), never the broader P3 distance-caliper scaler,
# which is computed over a different (unfiltered) population. A missing
# target or a missing scaler row is a hard certification failure (a real
# construction defect), not smd=0; a genuinely zero-variance variable may
# be treated as smd=0 only when the scaler explicitly records
# zero_variance=TRUE for it.
lmv2_ebal_stage2_firm_reaggregation_gate <- function(
    stage2_control_weights, control_firm_covars, treated_firm_target, cohort_firm_scaler,
    preferred_max_smd = LMV2_P4_EBAL$stage_2$firm_reaggregation_preferred_max_smd,
    acceptable_max_smd = LMV2_P4_EBAL$stage_2$firm_reaggregation_acceptable_max_smd) {
  required <- c("cohort", "control_group", "weight")
  if (!all(required %in% names(stage2_control_weights))) stop("Stage-2 control-weight schema invalid")
  fvars <- c("log_patent_stock_5y", "log_inventor_count_5y", "patent_trajectory")
  stopifnot(all(fvars %in% names(control_firm_covars)))

  firm_mass <- stats::aggregate(stage2_control_weights$weight,
                                stage2_control_weights[c("cohort", "control_group")], sum)
  names(firm_mass)[3] <- "firm_mass"
  fm <- merge(firm_mass, control_firm_covars, by = c("cohort", "control_group"), sort = FALSE)

  detail <- do.call(rbind, lapply(fvars, function(v) {
    do.call(rbind, lapply(sort(unique(fm$cohort)), function(g) {
      fg <- fm[fm$cohort == g, , drop = FALSE]
      trg_row <- treated_firm_target[treated_firm_target$cohort == g &
                                       treated_firm_target$variable == v, , drop = FALSE]
      sd_row <- cohort_firm_scaler[cohort_firm_scaler$cohort == g &
                                     cohort_firm_scaler$variable == v, , drop = FALSE]
      missing_target <- nrow(trg_row) != 1L || !is.finite(trg_row$treated_mean[1])
      missing_scaler <- nrow(sd_row) != 1L
      if (missing_target || missing_scaler) {
        return(data.frame(cohort = g, variable = v, control_mean = NA_real_,
                          treated_target = NA_real_, smd = NA_real_,
                          status = "missing_target_or_scaler"))
      }
      control_mean <- if (nrow(fg) && sum(fg$firm_mass) > 0) {
        sum(fg$firm_mass * fg[[v]]) / sum(fg$firm_mass)
      } else NA_real_
      if (isTRUE(sd_row$zero_variance[1])) {
        return(data.frame(cohort = g, variable = v, control_mean = control_mean,
                          treated_target = trg_row$treated_mean[1], smd = 0,
                          status = "zero_variance_omitted"))
      }
      if (!is.finite(sd_row$sd[1]) || sd_row$sd[1] < LMV2_P3_DISTANCE_EPSILON) {
        return(data.frame(cohort = g, variable = v, control_mean = control_mean,
                          treated_target = trg_row$treated_mean[1], smd = NA_real_,
                          status = "unrecorded_degenerate_scaler"))
      }
      if (!is.finite(control_mean)) {
        return(data.frame(cohort = g, variable = v, control_mean = NA_real_,
                          treated_target = trg_row$treated_mean[1], smd = NA_real_,
                          status = "empty_control_mass"))
      }
      smd <- (control_mean - trg_row$treated_mean[1]) / sd_row$sd[1]
      data.frame(cohort = g, variable = v, control_mean = control_mean,
                treated_target = trg_row$treated_mean[1], smd = smd, status = "ok")
    }))
  }))
  hard_fail <- any(!detail$status %in% c("ok", "zero_variance_omitted"))
  max_abs_smd <- if (hard_fail) Inf else max(abs(detail$smd))
  tier <- if (hard_fail) "stage2_firm_reaggregation_failure"
         else if (max_abs_smd <= preferred_max_smd) "preferred"
         else if (max_abs_smd <= acceptable_max_smd) "acceptable"
         else "stage2_firm_reaggregation_failure"
  list(status = if (tier == "stage2_firm_reaggregation_failure") tier else "pass",
       tier = tier, max_abs_smd = max_abs_smd, hard_fail = hard_fail,
       detail = detail, firm_mass = fm)
}

# Diagnostic only: how far the Stage-2-implied firm mass moved from the
# original Stage-1 entropy weight. Movement is expected and is never gated.
lmv2_ebal_stage1_prior_movement <- function(firm_mass, stage1_weights) {
  m <- merge(firm_mass[c("cohort", "control_group", "firm_mass")],
            stage1_weights[c("cohort", "control_group", "weight")],
            by = c("cohort", "control_group"), sort = FALSE)
  m$movement <- m$firm_mass - m$weight
  m[order(m$cohort, m$control_group), ]
}

# ----------------------------------------------------------------------------
# Exclusion accounting.
# ----------------------------------------------------------------------------

# Ported, generalized form of the funnel-step pattern used elsewhere in the
# package: assigns `reason` to any unit still pending (terminal_reason NA)
# that is not present in `surviving_keys`. Every exclusion is logged with an
# explicit reason; nothing is ever silently complete-case-deleted.
lmv2_ebal_funnel_step <- function(state, surviving_keys, reason) {
  stopifnot(all(c("cohort", "deal_id", "treated_codinv", "terminal_reason") %in% names(state)))
  key <- paste(state$cohort, state$deal_id, state$treated_codinv, sep = "\r")
  newly_lost <- is.na(state$terminal_reason) & !(key %in% surviving_keys)
  state$terminal_reason[newly_lost] <- reason
  state
}

# Stage 1 must remain frozen while Stage 2 runs, under the EXACT caliper and
# technology resolution it was built with (LMV2_LOCK$production$
# stage_1_must_remain_frozen_during_stage_2): those choices determined which
# firms/inventors were eligible and therefore which firms received Stage-1
# weight in the first place. `freeze`: a one-row data.frame with
# `stage2_caliper` (NA meaning Inf) and `technology_resolution`, as written
# by 17h. Pure and testable so this check is certified without running 17i.
lmv2_ebal_verify_stage2_matches_freeze <- function(freeze, stage2_caliper, technology_resolution) {
  freeze_caliper <- if (is.na(freeze$stage2_caliper)) Inf else freeze$stage2_caliper
  caliper_ok <- isTRUE(all.equal(freeze_caliper, stage2_caliper))
  resolution_ok <- identical(freeze$technology_resolution, technology_resolution)
  list(ok = caliper_ok && resolution_ok, caliper_ok = caliper_ok, resolution_ok = resolution_ok)
}

# ----------------------------------------------------------------------------
# Full-cohort-set pipelines: pure orchestration shared by the DB-facing
# runners (17h/17i) and the database-free certification fixtures (17j), so
# the fixtures exercise the exact sequence production runs, never a
# parallel reimplementation of it.
# ----------------------------------------------------------------------------

# Stage-1 pipeline: firm admissible edges -> unique firm pool (pre-filtered
# by Stage-2 eligibility, computed from `stage2_candidate_edges` -- Stage-2
# edges for ALL firm-caliper-admissible candidate firms, not yet restricted
# to Stage-1's positive-weight subset) -> per-cohort entropy solve.
lmv2_ebal_stage1_pipeline <- function(firm_edges, stage2_candidate_edges,
                                      stage1_caliper, stage2_caliper,
                                      treated_firm_covars, control_firm_covars, cohorts) {
  admissible_firm_edges <- lmv2_ebal_stage1_admissible_edges(firm_edges, stage1_caliper)
  firm_pool <- lmv2_ebal_stage1_unique_firm_pool(admissible_firm_edges)

  candidate_admissible <- lmv2_ebal_stage2_admissible_edges(stage2_candidate_edges, stage2_caliper)
  eligible_firms <- lmv2_ebal_stage2_eligible_firms(
    lmv2_ebal_stage2_eligible_controls(candidate_admissible))

  roster_result <- lmv2_ebal_stage1_roster(firm_pool, eligible_firms,
                                           treated_firm_covars, control_firm_covars)
  roster <- roster_result$roster

  per_cohort <- lapply(cohorts, function(g) {
    rg <- roster[roster$cohort == g, , drop = FALSE]
    out <- lmv2_ebal_run_cohort(LMV2_P4_EBAL$stage_1$balance_variables, rg,
                                s_weights = rep(1, nrow(rg)))
    out$cohort <- g
    out$roster_control_group <- rg$control_group[rg$D == 0L]
    out
  })
  names(per_cohort) <- as.character(cohorts)

  weights <- do.call(rbind, lapply(per_cohort, function(r) {
    if (!identical(r$status, "pass")) return(NULL)
    data.frame(cohort = r$cohort, control_group = r$roster_control_group,
              weight = r$control_weight, stringsAsFactors = FALSE)
  }))
  if (is.null(weights)) weights <- data.frame(cohort = integer(), control_group = numeric(),
                                              weight = numeric())
  scalers <- do.call(rbind, lapply(per_cohort, function(r) {
    if (is.null(r$scaler)) return(NULL)
    cbind(cohort = r$cohort, r$scaler)
  }))
  if (is.null(scalers)) scalers <- data.frame(cohort = integer(), variable = character(),
                                              mean = numeric(), sd = numeric(),
                                              zero_variance = logical())

  ess_concentration_gate <- lmv2_ebal_ess_concentration_gate(
    per_cohort, LMV2_P4_EBAL$stage_1$ess_ratio, LMV2_P4_EBAL$stage_1$max_share)

  list(admissible_firm_edges = admissible_firm_edges, firm_pool = firm_pool,
       stage2_candidate_admissible_edges = candidate_admissible,
       eligible_firms = eligible_firms, excluded_firms = roster_result$excluded_firms,
       per_cohort = per_cohort, weights = weights, scalers = scalers,
       ess_concentration_gate = ess_concentration_gate,
       all_cohorts_pass = length(per_cohort) > 0 &&
         all(vapply(per_cohort, function(r) identical(r$status, "pass"), logical(1))))
}

# Stage-2 pipeline (one scheme): restrict Stage-2 candidate edges to
# positive-weight Stage-1 firms -> eligible controls / supported treated ->
# base-weight allocation -> roster -> per-cohort solve -> retention -> firm
# reaggregation against the estimand-correct target built from retained
# treated inventors only.
lmv2_ebal_stage2_pipeline <- function(stage1_result, stage2_candidate_edges, stage2_caliper,
                                      treated_spine, treated_inv_covars, treated_firm_covars,
                                      control_inv_covars, control_firm_covars,
                                      deal_category = NULL,
                                      treated_weighting = c("primary", "equal_deal"), cohorts) {
  treated_weighting <- match.arg(treated_weighting)
  key <- function(d) paste(d$cohort, d$control_group)
  pos_firms <- stage1_result$weights[stage1_result$weights$weight > 0,
                                     c("cohort", "control_group"), drop = FALSE]
  candidate_admissible <- lmv2_ebal_stage2_admissible_edges(stage2_candidate_edges, stage2_caliper)
  admissible_edges <- candidate_admissible[key(candidate_admissible) %in% key(pos_firms), , drop = FALSE]

  eligible_controls <- lmv2_ebal_stage2_eligible_controls(admissible_edges)
  support <- lmv2_ebal_stage2_supported_treated(admissible_edges, treated_spine)
  supported <- support$supported

  base_weights <- lmv2_ebal_allocate_base_weights(stage1_result$weights, eligible_controls)
  roster <- lmv2_ebal_stage2_roster(base_weights, treated_inv_covars, control_inv_covars,
                                    supported, treated_weighting)

  per_cohort <- lapply(cohorts, function(g) {
    rg <- roster[roster$cohort == g, , drop = FALSE]
    out <- lmv2_ebal_run_cohort(LMV2_P4_EBAL$stage_2$balance_variables, rg,
                                s_weights = rg$base_weight)
    out$cohort <- g
    out$roster_control_ids <- rg[rg$D == 0L, c("control_codinv", "control_group")]
    out$roster_treated_ids <- rg[rg$D == 1L, c("deal_id", "treated_codinv")]
    out
  })
  names(per_cohort) <- as.character(cohorts)

  weights <- do.call(rbind, lapply(per_cohort, function(r) {
    if (!identical(r$status, "pass")) return(NULL)
    data.frame(cohort = r$cohort, control_codinv = r$roster_control_ids$control_codinv,
              control_group = r$roster_control_ids$control_group,
              weight = r$control_weight, stringsAsFactors = FALSE)
  }))
  if (is.null(weights)) weights <- data.frame(cohort = integer(), control_codinv = numeric(),
                                              control_group = numeric(), weight = numeric())

  # Treated weights (verbatim s.weights, per lmv2_ebal_finalize_weights()) --
  # critical for the equal-deal scheme, whose treated weights are NOT all 1
  # and are otherwise computed only to be discarded inside per_cohort,
  # unreachable by any downstream estimation step.
  treated_weights <- do.call(rbind, lapply(per_cohort, function(r) {
    if (!identical(r$status, "pass")) return(NULL)
    data.frame(cohort = r$cohort, deal_id = r$roster_treated_ids$deal_id,
              treated_codinv = r$roster_treated_ids$treated_codinv,
              weight = r$treated_weight, stringsAsFactors = FALSE)
  }))
  if (is.null(treated_weights)) {
    treated_weights <- data.frame(cohort = integer(), deal_id = integer(),
                                  treated_codinv = numeric(), weight = numeric())
  }

  retention <- lmv2_ebal_retention_summary(supported, treated_spine, deal_category)
  retention_gate <- lmv2_ebal_retention_gate(retention)

  firm_target <- lmv2_ebal_treated_firm_target(supported, treated_firm_covars, treated_weighting)
  firm_gate <- if (nrow(weights)) {
    lmv2_ebal_stage2_firm_reaggregation_gate(weights, control_firm_covars, firm_target,
                                             stage1_result$scalers)
  } else {
    list(status = "empty_treated_or_control_cell", tier = NA_character_, max_abs_smd = NA_real_,
        hard_fail = TRUE, detail = data.frame(), firm_mass = data.frame())
  }
  movement <- if (nrow(firm_gate$firm_mass)) {
    lmv2_ebal_stage1_prior_movement(firm_gate$firm_mass, stage1_result$weights)
  } else {
    data.frame(cohort = integer(), control_group = numeric(), firm_mass = numeric(),
              weight = numeric(), movement = numeric())
  }

  ess_concentration_gate <- lmv2_ebal_ess_concentration_gate(
    per_cohort, LMV2_P4_EBAL$stage_2$ess_ratio, LMV2_P4_EBAL$stage_2$max_share)

  list(scheme = treated_weighting, admissible_edges = admissible_edges,
       eligible_controls = eligible_controls, supported_treated = supported,
       excluded_treated = support$excluded, base_weights = base_weights,
       per_cohort = per_cohort, weights = weights, treated_weights = treated_weights,
       all_cohorts_pass = length(per_cohort) > 0 &&
         all(vapply(per_cohort, function(r) identical(r$status, "pass"), logical(1))),
       retention = retention, retention_gate = retention_gate,
       firm_target = firm_target, firm_gate = firm_gate, prior_movement = movement,
       ess_concentration_gate = ess_concentration_gate)
}

# Terminal design gate: requires, for one scheme's Stage-2 pipeline result,
# that every expected cohort produced a solver result, every cohort's
# inventor balance passed, firm reaggregation passed with every expected
# (weight-bearing) cohort represented, retention met at least the acceptable
# tier, no cohort fell below the 50% floor, no target-size category
# disappeared, Stage-2 ESS and weight concentration meet at least the
# acceptable tier locked in the pre-E2 amendment, and all required
# diagnostics are finite. A missing or failed cohort can never silently
# drop out of the aggregation and thereby pass: every check here compares
# against the full expected cohort set, not against whatever happens to
# survive upstream filtering.
lmv2_ebal_terminal_gate <- function(scheme_result, cohorts) {
  reasons <- character(0)
  expected <- as.character(cohorts)

  cohorts_present <- names(scheme_result$per_cohort)
  if (!setequal(cohorts_present, expected)) reasons <- c(reasons, "missing_cohort_in_solver_results")

  cohort_pass <- vapply(scheme_result$per_cohort, function(r) identical(r$status, "pass"), logical(1))
  if (!length(cohort_pass) || !all(cohort_pass)) reasons <- c(reasons, "cohort_inventor_balance_failed")

  if (!identical(scheme_result$firm_gate$status, "pass")) reasons <- c(reasons, "firm_reaggregation_failed")
  expected_firm_cohorts <- unique(scheme_result$weights$cohort)
  observed_firm_cohorts <- if (is.null(scheme_result$firm_gate$firm_mass) ||
                               !nrow(scheme_result$firm_gate$firm_mass)) integer(0) else
    unique(scheme_result$firm_gate$firm_mass$cohort)
  if (!setequal(as.character(expected_firm_cohorts), as.character(observed_firm_cohorts))) {
    reasons <- c(reasons, "firm_reaggregation_missing_cohort")
  }

  if (!isTRUE(scheme_result$retention_gate$pass)) reasons <- c(reasons, "retention_below_acceptable_tier")
  if (!isTRUE(scheme_result$retention_gate$cohort_floor_ok)) {
    reasons <- c(reasons, "cohort_below_fifty_percent_floor")
  }
  if (!isTRUE(scheme_result$retention_gate$category_preserved)) {
    reasons <- c(reasons, "target_size_category_disappeared")
  }

  maxdiffs <- vapply(scheme_result$per_cohort, function(r) if (is.null(r$maxdiff)) NA_real_ else r$maxdiff,
                     numeric(1))
  if (!length(maxdiffs) || !all(is.finite(maxdiffs))) reasons <- c(reasons, "nonfinite_diagnostics")

  if (!isTRUE(scheme_result$ess_concentration_gate$pass)) {
    reasons <- c(reasons, "stage2_ess_concentration_below_acceptable_tier")
  }

  list(pass = length(reasons) == 0L, reasons = reasons)
}
