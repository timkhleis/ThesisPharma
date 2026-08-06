# ============================================================================
# deal_ebal_cohort_hybrid_utils.R -- COHORT-LEVEL hybrid EB core (PILOT)
# ============================================================================
# Amendment (2026-07-24) over the within-deal hybrid core
# (deal_ebal_hybrid_utils.R, now a secondary diagnostic tool, not the primary
# design): the primary estimand is the cohort-level ATT for a treated
# inventor, which does not require every individual deal to reproduce its own
# target firm exactly -- only the CROSS-DEAL, COHORT-POOLED weighted
# comparison needs to balance.
#
# CORRECTED (2026-07-24, second pass) after a critical optweight contract bug
# was reported and independently verified: optweight's raw fit$weights are
# NEVER already multiplied by s.weights -- confirmed empirically identical
# with/without s.weights on the treated side (always exactly 1), and the
# control side differs with/without s.weights, proving s.weights informs the
# solve but is never baked into the returned vector. This is EXACTLY the same
# contract as WeightIt's ebal path (raw treated tilt is always 1 there too),
# so the already-certified lmv2_ebal_finalize_weights() is reused UNCHANGED
# for optweight results -- no new bespoke mass-reconciliation logic. Verified
# directly: prescribed equal-deal treated base weights (1/3,1/3,1/3,1) and
# masses (2/2) are exactly restored by lmv2_ebal_finalize_weights(fit, D, sw).
#
# Also corrected this pass: rung-specific tolerance (0.05 rung requires
# realized <=0.05+eps, not <=0.10), a retention gate that is CHECKED FIRST and
# is terminal (no escalation attempted if support itself is inadequate -- no
# solver can restore inventors that were never admitted), an ESS gate on
# every rung (reusing the already-locked LMV2_P4_EBAL$stage_2$ess_ratio
# thresholds), authoritative (not just internally-consistent) firm-attachment
# checks, hard-fail base-weight-allocator invariants, and persisted (not
# discarded) solver warnings.
#
# Architecture:
#   Stage 1 (deal-specific): recruitment/support selection only -- caliper-
#     admissible firms per deal, >=5-firm gate, produces NO final weights.
#   Stage 2 support edges (deal-specific): control inventor x deal
#     admissibility via recency/IPC4/covariate-completeness/distance.
#   Roster: treated = one row per (cohort, deal_id, treated_codinv); control =
#     one row per unique (cohort, deal_id, control_codinv, control_group) --
#     the SAME control inventor may appear in multiple deal stacks.
#   Base weights: deal-normalized so no deal dominates merely by having a
#     larger donor pool.
#   ONE weighting solve PER COHORT (never pooled across cohorts, never
#     per-deal) on the stacked roster, balancing the combined 8-covariate
#     vector (5 inventor + 3 firm_-prefixed).
#   Feasibility hierarchy, GLOBAL per cohort: retention gate (terminal if
#     failed) -> exact EB (needs balance AND ESS) -> optweight tol=0.05
#     (needs realized <=0.05+eps AND ESS) -> optweight tol=0.10 (needs
#     realized <=0.10+eps AND ESS) -> infeasible. Never mixed deal by deal.
#   Deal-level balance and max weight share are DIAGNOSTIC/WARNING only,
#     never a gate on the primary cohort ATT.
#
# Reuses deal_ebal_hybrid_utils.R's LMV2_HYBRID_INV_VARS/FIRM_VARS,
# lmv2_ebal_deal_supported(), lmv2_ebal_nearest_within_caliper(), and the
# certified 17g solver/standardization/balance/finalize primitives. Nothing
# in 15*/16*/17g is edited. No outcome, treatment effect, event panel, or P6
# object is read here.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))

LMV2_COHORT_PREFERRED_SMD <- 0.05
LMV2_COHORT_ACCEPTABLE_SMD <- 0.10
LMV2_COHORT_SMD_EPS <- 1e-8                      # floating-point slack ONLY, not a substantive loosening
# NUMERICAL-CORRUPTION SAFEGUARDS ONLY (explicitly, per review): these two
# thresholds exist to catch obviously-broken solver output (a real observed
# case: optweight returned finite weights up to 2.1 BILLION on a genuinely
# infeasible target, alongside status="primal infeasible"). They are set
# many orders of magnitude above anything a legitimate, even heavily
# concentrated, real solution could produce -- nothing in this codebase has
# ever produced a real final weight above single/low-double digits. They
# are NOT, and must never become, a substantive overlap/concentration gate:
# ESS (lmv2_ebal_ess_gate) and realized balance (rung tolerance) are the only
# meaningful diagnostics for whether a solution is credible. Max weight share
# stays a REPORTED WARNING (point 10), never a rejection threshold.
LMV2_COHORT_PATHOLOGICAL_WEIGHT_MAX <- 1e6        # any single FINAL weight above this is numerically broken
LMV2_COHORT_PATHOLOGICAL_MAX_TO_MEAN <- 1e4       # ratio beyond this indicates numerical breakdown, not "bad overlap"
# ESS gate (point 9): reuses the ALREADY-LOCKED pre-E2 amendment thresholds
# (17f_lmv2_p4_ebal_config.R, Stage-2 ess_ratio) rather than inventing a new
# number. Applied uniformly at every rung (exact, optweight 0.05, optweight
# 0.10) for consistency; the instruction singles out exact EB explicitly,
# applying it everywhere is the more defensible general principle -- flagged
# for override if a narrower scope was intended.
LMV2_COHORT_ESS_RATIO_ACCEPTABLE <- LMV2_P4_EBAL$stage_2$ess_ratio$acceptable
LMV2_COHORT_ESS_RATIO_PREFERRED <- LMV2_P4_EBAL$stage_2$ess_ratio$preferred
# Retention gate (point 9): reuses the ALREADY-LOCKED P0 design-lock
# acceptable-tier inventor retention floor (15a_lmv2_design_lock.R). Retention
# failure is about which inventors were ADMITTED at all -- no weighting
# method, exact or approximate, can restore an excluded inventor, so this is
# checked FIRST and is terminal.
LMV2_COHORT_RETENTION_MIN <- LMV2_LOCK$pilot$stage_2_acceptable$inventor_retention_min

# =============================================================================
# CORE ASSERTIONS. Every one stop()s on violation.
# =============================================================================

lmv2_ebal_assert_unique_balance_vars <- function(inv_vars, firm_vars) {
  both <- c(inv_vars, firm_vars)
  if (anyDuplicated(both)) {
    stop("Balance-variable names are not unique: ", paste(both[duplicated(both)], collapse = ", "))
  }
  if (length(intersect(inv_vars, firm_vars))) {
    stop("inv_vars and firm_vars overlap: ", paste(intersect(inv_vars, firm_vars), collapse = ", "))
  }
  invisible(TRUE)
}

lmv2_ebal_assert_no_missing_covariates <- function(data, vars, context = "roster") {
  bad <- vars[vapply(vars, function(v) !all(is.finite(data[[v]])), logical(1))]
  if (length(bad)) {
    stop(sprintf("%s has missing/non-finite values in: %s", context, paste(bad, collapse = ", ")))
  }
  invisible(TRUE)
}

lmv2_ebal_assert_constant_target_firm_within_deal <- function(treated_rows, firm_vars) {
  key <- paste(treated_rows$cohort, treated_rows$deal_id)
  for (v in firm_vars) {
    n_distinct <- stats::ave(treated_rows[[v]], key, FUN = function(x) length(unique(x)))
    if (any(n_distinct > 1)) {
      bad_deals <- unique(key[n_distinct > 1])
      stop(sprintf("Target-firm attachment for %s is not constant within deal(s): %s",
                   v, paste(bad_deals, collapse = "; ")))
    }
  }
  invisible(TRUE)
}

# CORRECTED (point 7): authoritative comparison against firm covariates keyed
# by (cohort, control_group) -- not merely internal self-consistency within
# control_rows. `authoritative_firm_covars` must have columns cohort,
# control_group, and the RAW (un-prefixed) firm covariate names.
lmv2_ebal_assert_control_firm_matches_authoritative <- function(control_rows, firm_vars,
                                                                 authoritative_firm_covars,
                                                                 raw_names = names(LMV2_HYBRID_FIRM_ATTACH_MAP),
                                                                 tol = 1e-8) {
  stopifnot(length(firm_vars) == length(raw_names))
  auth <- authoritative_firm_covars[c("cohort", "control_group", raw_names)]
  names(auth) <- c("cohort", "control_group", firm_vars)
  chk <- merge(unique(control_rows[c("cohort", "control_group", firm_vars)]), auth,
              by = c("cohort", "control_group"), suffixes = c("_attached", "_authoritative"),
              all.x = TRUE)
  missing_auth <- chk[!stats::complete.cases(chk[paste0(firm_vars, "_authoritative")]), ]
  if (nrow(missing_auth)) {
    stop("Control firm attachment has no authoritative covariate row for control_group(s): ",
         paste(unique(missing_auth$control_group), collapse = ", "))
  }
  for (v in firm_vars) {
    diff <- abs(chk[[paste0(v, "_attached")]] - chk[[paste0(v, "_authoritative")]])
    if (any(diff > tol)) {
      bad <- chk$control_group[diff > tol]
      stop(sprintf("Control firm attachment for %s disagrees with authoritative (cohort, control_group) for: %s",
                   v, paste(bad, collapse = ", ")))
    }
  }
  invisible(TRUE)
}

# NEW (point 7): treated attachments verified against (cohort, deal_id,
# target_group) -- treated_rows must carry a target_group column so the join
# is literal and explicit, and `authoritative_treated_target` must have
# columns cohort, deal_id, target_group, and the RAW firm covariate names.
lmv2_ebal_assert_treated_firm_matches_authoritative <- function(treated_rows, firm_vars,
                                                                 authoritative_treated_target,
                                                                 raw_names = names(LMV2_HYBRID_FIRM_ATTACH_MAP),
                                                                 tol = 1e-8) {
  stopifnot("target_group" %in% names(treated_rows), length(firm_vars) == length(raw_names))
  auth <- authoritative_treated_target[c("cohort", "deal_id", "target_group", raw_names)]
  names(auth) <- c("cohort", "deal_id", "target_group", firm_vars)
  chk <- merge(unique(treated_rows[c("cohort", "deal_id", "target_group", firm_vars)]), auth,
              by = c("cohort", "deal_id", "target_group"), suffixes = c("_attached", "_authoritative"),
              all.x = TRUE)
  missing_auth <- chk[!stats::complete.cases(chk[paste0(firm_vars, "_authoritative")]), ]
  if (nrow(missing_auth)) {
    stop("Treated firm attachment has no authoritative row for (cohort, deal_id, target_group): ",
         paste(sprintf("(%s,%s,%s)", missing_auth$cohort, missing_auth$deal_id, missing_auth$target_group),
              collapse = "; "))
  }
  for (v in firm_vars) {
    diff <- abs(chk[[paste0(v, "_attached")]] - chk[[paste0(v, "_authoritative")]])
    if (any(diff > tol)) {
      bad <- which(diff > tol)
      stop(sprintf("Treated firm attachment for %s disagrees with authoritative target_group for deal(s): %s",
                   v, paste(sprintf("(%s,%s)", chk$cohort[bad], chk$deal_id[bad]), collapse = "; ")))
    }
  }
  invisible(TRUE)
}

lmv2_ebal_validate_cohort_roster <- function(treated_rows, control_rows, inv_vars, firm_vars,
                                             authoritative_firm_covars = NULL,
                                             authoritative_treated_target = NULL) {
  lmv2_ebal_assert_unique_balance_vars(inv_vars, firm_vars)
  req_t <- c("cohort", "deal_id", "treated_codinv", inv_vars, firm_vars)
  req_c <- c("cohort", "deal_id", "control_codinv", "control_group", inv_vars, firm_vars)
  if (!all(req_t %in% names(treated_rows))) stop("treated_rows missing required columns")
  if (!all(req_c %in% names(control_rows))) stop("control_rows missing required columns")
  if (anyDuplicated(treated_rows[c("cohort", "deal_id", "treated_codinv")])) {
    stop("treated_rows has duplicate (cohort, deal_id, treated_codinv) keys")
  }
  if (anyDuplicated(control_rows[c("cohort", "deal_id", "control_codinv", "control_group")])) {
    stop("control_rows has duplicate (cohort, deal_id, control_codinv, control_group) keys")
  }
  lmv2_ebal_assert_no_missing_covariates(treated_rows, c(inv_vars, firm_vars), "treated_rows")
  lmv2_ebal_assert_no_missing_covariates(control_rows, c(inv_vars, firm_vars), "control_rows")
  lmv2_ebal_assert_constant_target_firm_within_deal(treated_rows, firm_vars)
  if (!is.null(authoritative_firm_covars)) {
    lmv2_ebal_assert_control_firm_matches_authoritative(control_rows, firm_vars, authoritative_firm_covars)
  }
  if (!is.null(authoritative_treated_target)) {
    lmv2_ebal_assert_treated_firm_matches_authoritative(treated_rows, firm_vars, authoritative_treated_target)
  }
  invisible(TRUE)
}

# NEW (point 3, 4): formal post-hoc invariant assertions on FINAL weights.
lmv2_ebal_assert_final_treated_weights_equal_base <- function(final_treated_weight, base_treated_weight,
                                                               tol = 1e-8) {
  if (length(final_treated_weight) != length(base_treated_weight)) {
    stop("final and base treated weight vectors differ in length")
  }
  bad <- abs(final_treated_weight - base_treated_weight) > tol
  if (any(bad)) {
    stop(sprintf("Final treated weights disagree with prescribed base weights at %d position(s); max diff = %.3e",
                 sum(bad), max(abs(final_treated_weight - base_treated_weight))))
  }
  invisible(TRUE)
}

lmv2_ebal_assert_masses_agree <- function(final_treated_weight, final_control_weight,
                                          scheme = c("primary", "equal_deal"), n_retained_deals = NULL,
                                          tol = 1e-6) {
  scheme <- match.arg(scheme)
  treated_mass <- sum(final_treated_weight)
  control_mass <- sum(final_control_weight)
  if (abs(treated_mass - control_mass) > tol) {
    stop(sprintf("Final treated mass (%.6f) and control mass (%.6f) disagree (scheme=%s)",
                 treated_mass, control_mass, scheme))
  }
  if (scheme == "primary") {
    if (!isTRUE(all.equal(treated_mass, length(final_treated_weight), tolerance = tol))) {
      stop(sprintf("Primary scheme: treated mass (%.6f) should equal n_supported_treated (%d)",
                   treated_mass, length(final_treated_weight)))
    }
  } else {
    if (is.null(n_retained_deals)) stop("equal_deal scheme requires n_retained_deals to verify mass")
    if (!isTRUE(all.equal(treated_mass, n_retained_deals, tolerance = tol))) {
      stop(sprintf("Equal-deal scheme: treated mass (%.6f) should equal n_retained_deals (%d)",
                   treated_mass, n_retained_deals))
    }
  }
  invisible(TRUE)
}

# =============================================================================
# Deal-normalized base weights (point 5/8 of the original amendment; point 8
# of this correction adds hard-fail invariants).
# =============================================================================
lmv2_ebal_allocate_deal_base_weights <- function(treated_rows, control_rows,
                                                 scheme = c("primary", "equal_deal")) {
  scheme <- match.arg(scheme)
  if (anyDuplicated(treated_rows[c("cohort", "deal_id", "treated_codinv")])) {
    stop("allocate_deal_base_weights: duplicate (cohort, deal_id, treated_codinv) in treated_rows")
  }
  if (anyDuplicated(control_rows[c("cohort", "deal_id", "control_codinv", "control_group")])) {
    stop("allocate_deal_base_weights: duplicate (cohort, deal_id, control_codinv, control_group) in control_rows")
  }
  # HARD-FAIL (point 8): treated and control deal sets must match exactly --
  # a deal present in one side and silently absent from the other must never
  # be dropped by an inner merge without an explicit error.
  key <- function(d) paste(d$cohort, d$deal_id)
  t_deals <- unique(key(treated_rows)); c_deals <- unique(key(control_rows))
  only_t <- setdiff(t_deals, c_deals); only_c <- setdiff(c_deals, t_deals)
  if (length(only_t) || length(only_c)) {
    stop("allocate_deal_base_weights: treated/control deal sets do not match. Only in treated: ",
        paste(only_t, collapse = "; "), ". Only in control: ", paste(only_c, collapse = "; "))
  }

  n_treated_by_deal <- stats::aggregate(treated_codinv ~ cohort + deal_id, data = treated_rows,
                                        FUN = length)
  names(n_treated_by_deal)[3] <- "n_supported_treated"
  n_control_by_deal <- stats::aggregate(control_codinv ~ cohort + deal_id, data = control_rows,
                                        FUN = length)
  names(n_control_by_deal)[3] <- "n_control_rows"

  if (scheme == "primary") {
    treated_w <- merge(treated_rows[c("cohort", "deal_id", "treated_codinv")], n_treated_by_deal,
                       by = c("cohort", "deal_id"))
    treated_w$base_weight <- 1
    treated_w$n_supported_treated <- NULL
    deal_target <- n_treated_by_deal
    names(deal_target)[3] <- "target_mass"
  } else {
    treated_w <- merge(treated_rows[c("cohort", "deal_id", "treated_codinv")], n_treated_by_deal,
                       by = c("cohort", "deal_id"))
    treated_w$base_weight <- 1 / treated_w$n_supported_treated
    treated_w$n_supported_treated <- NULL
    deal_target <- data.frame(n_treated_by_deal[c("cohort", "deal_id")], target_mass = 1)
  }
  ctrl_alloc <- merge(n_control_by_deal, deal_target, by = c("cohort", "deal_id"))
  ctrl_alloc$per_row_weight <- ctrl_alloc$target_mass / ctrl_alloc$n_control_rows
  control_w <- merge(control_rows[c("cohort", "deal_id", "control_codinv", "control_group")],
                     ctrl_alloc[c("cohort", "deal_id", "per_row_weight")], by = c("cohort", "deal_id"))
  names(control_w)[names(control_w) == "per_row_weight"] <- "base_weight"

  # HARD-FAIL (point 8): within-deal mass conservation -- defensive check on
  # this function's OWN arithmetic, so a future edit that breaks it errors
  # immediately rather than silently corrupting downstream solves.
  realized_treated_mass <- stats::aggregate(base_weight ~ cohort + deal_id, data = treated_w, FUN = sum)
  realized_control_mass <- stats::aggregate(base_weight ~ cohort + deal_id, data = control_w, FUN = sum)
  cmp <- merge(realized_treated_mass, realized_control_mass, by = c("cohort", "deal_id"),
              suffixes = c("_treated", "_control"))
  bad_mass <- abs(cmp$base_weight_treated - cmp$base_weight_control) > 1e-8
  if (any(bad_mass)) {
    stop("allocate_deal_base_weights: within-deal mass non-conservation for: ",
        paste(sprintf("(%s,%s)", cmp$cohort[bad_mass], cmp$deal_id[bad_mass]), collapse = "; "))
  }

  list(treated = treated_w, control = control_w, scheme = scheme,
      n_retained_deals = nrow(unique(treated_rows[c("cohort", "deal_id")])))
}

# =============================================================================
# Roster construction (unchanged in spirit; now threads through the
# authoritative-attachment arguments).
# =============================================================================
lmv2_ebal_build_cohort_roster <- function(treated_rows, control_rows, base_weights,
                                          inv_vars = LMV2_HYBRID_INV_VARS,
                                          firm_vars = LMV2_HYBRID_FIRM_VARS,
                                          authoritative_firm_covars = NULL,
                                          authoritative_treated_target = NULL) {
  lmv2_ebal_validate_cohort_roster(treated_rows, control_rows, inv_vars, firm_vars,
                                   authoritative_firm_covars, authoritative_treated_target)
  balance_vars <- c(inv_vars, firm_vars)
  treated_full <- merge(treated_rows, base_weights$treated,
                        by = c("cohort", "deal_id", "treated_codinv"))
  control_full <- merge(control_rows, base_weights$control,
                        by = c("cohort", "deal_id", "control_codinv", "control_group"))
  rbind(
    data.frame(D = 1L, treated_full[c("cohort", "deal_id", "treated_codinv")],
              control_codinv = NA_real_, control_group = NA_real_,
              base_weight = treated_full$base_weight, treated_full[balance_vars],
              stringsAsFactors = FALSE),
    data.frame(D = 0L, control_full[c("cohort", "deal_id")], treated_codinv = NA_real_,
              control_codinv = control_full$control_codinv, control_group = control_full$control_group,
              base_weight = control_full$base_weight, control_full[balance_vars],
              stringsAsFactors = FALSE))
}

# =============================================================================
# ESS gate (point 9), applied uniformly at every rung.
# =============================================================================
lmv2_ebal_ess_gate <- function(ess, n_supported_treated) {
  if (!is.finite(ess) || !is.finite(n_supported_treated) || n_supported_treated <= 0) {
    return(list(pass = FALSE, tier = NA_character_, ess_ratio = NA_real_))
  }
  ratio <- ess / n_supported_treated
  tier <- if (ratio >= LMV2_COHORT_ESS_RATIO_PREFERRED) "preferred" else
    if (ratio >= LMV2_COHORT_ESS_RATIO_ACCEPTABLE) "acceptable" else "failed"
  list(pass = ratio >= LMV2_COHORT_ESS_RATIO_ACCEPTABLE, tier = tier, ess_ratio = ratio)
}

# =============================================================================
# Retention gate (point 9): terminal, checked BEFORE any solver is attempted.
# =============================================================================
lmv2_ebal_retention_gate <- function(n_supported_treated, n_eligible_treated) {
  if (!is.finite(n_eligible_treated) || n_eligible_treated <= 0) {
    return(list(pass = FALSE, retention = NA_real_))
  }
  retention <- n_supported_treated / n_eligible_treated
  list(pass = retention >= LMV2_COHORT_RETENTION_MIN, retention = retention)
}

# =============================================================================
# The single cohort-level stacked solve (exact EB path).
# =============================================================================
lmv2_ebal_cohort_exact_solve <- function(roster, inv_vars = LMV2_HYBRID_INV_VARS,
                                         firm_vars = LMV2_HYBRID_FIRM_VARS) {
  balance_vars <- c(inv_vars, firm_vars)
  eb <- lmv2_ebal_run_cohort(balance_vars, roster, s_weights = roster$base_weight)
  list(mode = "exact_ebal", eb = eb, roster = roster)
}

# Reusable warning-capture idiom (point 6), extracted so the mechanism is
# independently unit-testable without depending on optweight's numerically
# fragile warning behavior (a real trigger was found once with genuinely
# random covariates and could not be reliably reproduced across 60+ retries
# with constructed geometry -- the MECHANISM is what must be verified, not a
# specific optweight input). Returns list(value=..., warnings=character(0+)).
lmv2_ebal_capture_warnings <- function(expr) {
  captured <- character(0)
  value <- withCallingHandlers(expr, warning = function(w) {
    captured <<- c(captured, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  list(value = value, warnings = captured)
}

# =============================================================================
# Approximate solve via optweight. CORRECTED: final weights are constructed
# via the certified lmv2_ebal_finalize_weights(fit, D, s_weights) -- verified
# empirically to give the correct contract (optweight's raw treated tilt is
# always exactly 1, identical to WeightIt/ebal, so treated final = s.weights
# verbatim and control final = raw_tilt * s.weights, then rescaled to match
# treated mass -- exactly the ebal convention, reused unchanged). Every
# result is STILL independently reclassified from the actual final weights
# (never trust fit$info$status alone -- a real test case returned "solved"
# with realized SMD 0.105 against a requested tol of 0.05). Solver warnings
# are CAPTURED, not discarded (point 6).
# =============================================================================
lmv2_ebal_cohort_optweight_solve <- function(roster, tol, inv_vars = LMV2_HYBRID_INV_VARS,
                                             firm_vars = LMV2_HYBRID_FIRM_VARS) {
  if (!requireNamespace("optweight", quietly = TRUE)) stop("optweight package not installed")
  balance_vars <- c(inv_vars, firm_vars)
  std <- lmv2_ebal_standardize_cohort(balance_vars, roster)
  use_vars <- setdiff(balance_vars, std$zero_variance)
  if (!length(use_vars)) {
    return(list(mode = "optweight", tol = tol, status = "no_non_degenerate_balance_variables",
               feasible = FALSE, pathological = NA, warnings = character(0)))
  }
  form <- stats::as.formula(paste("D ~", paste(use_vars, collapse = " + ")))
  D <- roster$D
  attempt <- tryCatch(
    lmv2_ebal_capture_warnings(
      optweight::optweight(form, data = std$data, tols = tol, estimand = "ATT",
                           s.weights = roster$base_weight)),
    error = function(e) e)
  if (inherits(attempt, "condition")) {
    return(list(mode = "optweight", tol = tol, status = "solver_error", feasible = FALSE,
               pathological = NA, error = conditionMessage(attempt), warnings = character(0)))
  }
  fit <- attempt$value
  captured_warnings <- attempt$warnings

  # CORRECTED: reuse the certified finalize convention instead of using
  # fit$weights directly -- fit$weights alone does NOT incorporate
  # roster$base_weight (verified: raw treated tilt is always exactly 1
  # regardless of s.weights; s.weights informs the solve but is never baked
  # into the returned vector).
  finalize <- lmv2_ebal_finalize_weights(fit, D, roster$base_weight)

  solver_infeasible <- !is.null(fit$info$status) && grepl("infeasible", fit$info$status, fixed = TRUE)
  finalize_ok <- isTRUE(finalize$ok) && isTRUE(finalize$weights_ok)
  ctrl_w <- if (finalize_ok) finalize$control_weight else numeric(0)
  trt_w <- if (finalize_ok) finalize$treated_weight else numeric(0)
  pathological <- !finalize_ok || !length(ctrl_w) ||
    max(ctrl_w) > LMV2_COHORT_PATHOLOGICAL_WEIGHT_MAX ||
    (mean(ctrl_w) > 0 && max(ctrl_w) / mean(ctrl_w) > LMV2_COHORT_PATHOLOGICAL_MAX_TO_MEAN)

  balance_after <- if (finalize_ok) lmv2_ebal_covariate_balance(use_vars, std$data, D, finalize$weight) else
    data.frame(variable = character(), abs_difference = numeric())
  realized_max_smd <- if (nrow(balance_after)) max(balance_after$abs_difference) else NA_real_
  ess <- if (finalize_ok) lmv2_ebal_ess(ctrl_w) else NA_real_
  conc <- if (finalize_ok) lmv2_ebal_concentration(ctrl_w) else
    list(max_share = NA_real_, top5_share = NA_real_)

  # CORRECTED (point 5): rung-specific tolerance -- 0.05 rung requires
  # realized <=0.05+eps, NOT <=0.10; 0.10 rung requires realized <=0.10+eps.
  meets_rung_tol <- is.finite(realized_max_smd) && realized_max_smd <= tol + LMV2_COHORT_SMD_EPS
  feasible <- !solver_infeasible && !pathological && meets_rung_tol
  tier <- if (!feasible) NA_character_ else
    if (realized_max_smd <= LMV2_COHORT_PREFERRED_SMD + LMV2_COHORT_SMD_EPS) "preferred" else "acceptable"

  list(mode = "optweight", tol = tol,
       status = if (feasible) "pass" else if (solver_infeasible) "solver_infeasible" else
         if (pathological) "pathological_weights" else "exceeds_rung_tolerance",
       feasible = feasible, tier = tier, solver_reported_status = fit$info$status,
       solver_infeasible = solver_infeasible, pathological = pathological,
       weight = if (finalize_ok) finalize$weight else rep(NA_real_, length(D)),
       treated_weight = trt_w, control_weight = ctrl_w,
       maxdiff = realized_max_smd, balance = balance_after, ess = ess, concentration = conc,
       warnings = captured_warnings)
}

# =============================================================================
# The GLOBAL per-cohort hierarchy. CORRECTED order (point 9): retention gate
# FIRST and terminal (no escalation if support itself is inadequate) -> exact
# EB (needs balance AND ESS) -> optweight tol=0.05 (needs rung tolerance AND
# ESS) -> optweight tol=0.10 (same) -> infeasible. Never escalates past 0.10.
# `n_eligible_treated` is the count BEFORE the Stage-2 support screen (i.e.
# the deal-eligible/covariate-complete treated population), so retention is
# measured against what could in principle have been supported.
# =============================================================================
lmv2_ebal_cohort_feasibility_hierarchy <- function(roster, n_eligible_treated,
                                                   inv_vars = LMV2_HYBRID_INV_VARS,
                                                   firm_vars = LMV2_HYBRID_FIRM_VARS) {
  n_supported_treated <- sum(roster$D == 1L)
  retention <- lmv2_ebal_retention_gate(n_supported_treated, n_eligible_treated)
  if (!isTRUE(retention$pass)) {
    return(list(mode = "retention_failed", tier = NA_character_, result = NULL, roster = roster,
               escalated = FALSE, retention = retention$retention))
  }
  # A control inventor can legitimately appear in multiple deal stacks (point
  # 3 of the architecture) -- the certified solver's own `ess` field is a
  # STACK-ROW Kish ESS, which counts each of those repeated rows as an
  # independent unit, overstating effective support and understating
  # concentration. The ACCEPTANCE GATE uses the REUSE-ADJUSTED ESS (weights
  # summed to (cohort, control_codinv) first, per review correction); both
  # values are reported (ess_info) so the reader can see the raw optimization
  # problem's own ESS alongside the number that actually gates.
  control_codinv_vec <- roster$control_codinv[roster$D == 0L]
  ess_info_for <- function(control_weight) {
    list(stack_row_ess = lmv2_ebal_ess(control_weight),
        reuse_adjusted_ess = lmv2_ebal_effective_inventor_count(control_weight, control_codinv_vec),
        stack_row_concentration = lmv2_ebal_concentration(control_weight),
        reuse_adjusted_concentration = lmv2_ebal_reuse_adjusted_concentration(control_weight, control_codinv_vec))
  }

  exact <- lmv2_ebal_cohort_exact_solve(roster, inv_vars, firm_vars)
  if (identical(exact$eb$status, "pass")) {
    ess_info <- ess_info_for(exact$eb$control_weight)
    ess_gate <- lmv2_ebal_ess_gate(ess_info$reuse_adjusted_ess, n_supported_treated)
    if (isTRUE(ess_gate$pass)) {
      return(list(mode = "exact_ebal", tier = exact$eb$tier, result = exact$eb, roster = roster,
                 escalated = FALSE, retention = retention$retention, ess_gate = ess_gate,
                 ess_info = ess_info))
    }
  }

  ow05 <- lmv2_ebal_cohort_optweight_solve(roster, tol = 0.05, inv_vars = inv_vars, firm_vars = firm_vars)
  if (isTRUE(ow05$feasible)) {
    ess_info_05 <- ess_info_for(ow05$control_weight)
    ess_gate_05 <- lmv2_ebal_ess_gate(ess_info_05$reuse_adjusted_ess, n_supported_treated)
    if (isTRUE(ess_gate_05$pass)) {
      return(list(mode = "optweight_0.05", tier = ow05$tier, result = ow05, roster = roster,
                 escalated = TRUE, exact_status = exact$eb$status, retention = retention$retention,
                 ess_gate = ess_gate_05, ess_info = ess_info_05))
    }
  }

  ow10 <- lmv2_ebal_cohort_optweight_solve(roster, tol = 0.10, inv_vars = inv_vars, firm_vars = firm_vars)
  if (isTRUE(ow10$feasible)) {
    ess_info_10 <- ess_info_for(ow10$control_weight)
    ess_gate_10 <- lmv2_ebal_ess_gate(ess_info_10$reuse_adjusted_ess, n_supported_treated)
    if (isTRUE(ess_gate_10$pass)) {
      return(list(mode = "optweight_0.10", tier = ow10$tier, result = ow10, roster = roster,
                 escalated = TRUE, exact_status = exact$eb$status, optweight_0.05_status = ow05$status,
                 retention = retention$retention, ess_gate = ess_gate_10, ess_info = ess_info_10))
    }
  }

  list(mode = "infeasible", tier = NA_character_, result = ow10, roster = roster, escalated = TRUE,
      exact_status = exact$eb$status, optweight_0.05_status = ow05$status,
      optweight_0.10_status = ow10$status, retention = retention$retention)
}

# =============================================================================
# Diagnostics: inventor ESS, effective firm count, deal-level SMD summary.
# Max weight share stays a REPORTED WARNING (point 10) -- never gates.
# =============================================================================
lmv2_ebal_effective_firm_count <- function(control_weight, control_group) {
  firm_w <- stats::aggregate(w ~ g, data = data.frame(w = control_weight, g = control_group), FUN = sum)
  lmv2_ebal_ess(firm_w$w)
}

# REUSE-ADJUSTED control-inventor ESS (review correction): the same control
# inventor can legitimately occur in multiple deal stacks within one cohort
# (point 3 of the architecture). A naive Kish ESS over stack ROWS counts each
# occurrence as an independent unit, overstating effective support. This
# aggregates weight to (cohort, control_codinv) FIRST -- one entry per unique
# inventor, however many deal stacks it appears in -- before computing ESS.
# This is the ESS the acceptance gate uses (lmv2_ebal_cohort_feasibility_
# hierarchy()); lmv2_ebal_ess() on the raw stack-row vector is still reported
# separately as a diagnostic on the optimization problem itself.
lmv2_ebal_effective_inventor_count <- function(control_weight, control_codinv) {
  inv_w <- stats::aggregate(w ~ c, data = data.frame(w = control_weight, c = control_codinv), FUN = sum)
  lmv2_ebal_ess(inv_w$w)
}

# Concentration (max/top5 share), likewise recomputed after aggregating
# repeated control-inventor weights -- still a WARNING only (point 10),
# never a gate, but the stack-row version alone would understate how
# concentrated support really is on a small number of distinct inventors.
lmv2_ebal_reuse_adjusted_concentration <- function(control_weight, control_codinv) {
  inv_w <- stats::aggregate(w ~ c, data = data.frame(w = control_weight, c = control_codinv), FUN = sum)
  lmv2_ebal_concentration(inv_w$w)
}

lmv2_ebal_deal_level_smd_summary <- function(roster, weight, inv_vars = LMV2_HYBRID_INV_VARS,
                                             firm_vars = LMV2_HYBRID_FIRM_VARS) {
  balance_vars <- c(inv_vars, firm_vars)
  std <- lmv2_ebal_standardize_cohort(balance_vars, roster)$data
  std$weight <- weight
  deals <- unique(roster[c("cohort", "deal_id")])
  per_deal <- do.call(rbind, lapply(seq_len(nrow(deals)), function(i) {
    g <- deals$cohort[i]; d <- deals$deal_id[i]
    sub <- std[std$cohort == g & std$deal_id == d, ]
    t_sub <- sub[sub$D == 1, ]; c_sub <- sub[sub$D == 0, ]
    if (!nrow(t_sub) || !nrow(c_sub) || sum(c_sub$weight) <= 0) {
      empty <- data.frame(
        cohort = g, deal_id = d, max_abs_smd = NA_real_)
      for (v in balance_vars) empty[[paste0("signed_smd_", v)]] <- NA_real_
      return(empty)
    }
    diffs <- vapply(balance_vars, function(v) {
      tm <- sum(t_sub$weight * t_sub[[v]]) / sum(t_sub$weight)
      cm <- sum(c_sub$weight * c_sub[[v]]) / sum(c_sub$weight)
      cm - tm
    }, numeric(1))
    out <- data.frame(
      cohort = g, deal_id = d, max_abs_smd = max(abs(diffs)))
    for (v in balance_vars) {
      out[[paste0("signed_smd_", v)]] <- diffs[[v]]
    }
    out
  }))
  valid <- per_deal$max_abs_smd[is.finite(per_deal$max_abs_smd)]
  list(per_deal = per_deal,
       median = if (length(valid)) stats::median(valid) else NA_real_,
       p90 = if (length(valid)) stats::quantile(valid, 0.90, names = FALSE) else NA_real_,
       max = if (length(valid)) max(valid) else NA_real_,
       share_above_0.10 = if (length(valid)) mean(valid > 0.10) else NA_real_,
       share_above_0.25 = if (length(valid)) mean(valid > 0.25) else NA_real_)
}

# =============================================================================
# Retention funnel (review correction): HEADLINE retention must be measured
# against the COMPLETE primary pilot spine (every treated inventor in the
# cohort, before ANY filtering), never against an intermediate stage that a
# restrictive Stage-1 profile has already narrowed -- doing so let a
# restrictive caliper that had already killed most deals still "pass" an 80%
# retention gate, because the deals it killed had already been removed from
# the denominator. All four funnel stages are reported so the reader can see
# exactly where loss happens (data completeness vs. Stage-1 vs. Stage-2), but
# only n_full -> n_stage2_supported is the number that gates anything.
# =============================================================================
lmv2_ebal_compute_retention_funnel <- function(n_full, n_covariate_complete, n_stage1_supported,
                                               n_stage2_supported,
                                               n_deals_full, n_deals_stage1_supported, n_deals_stage2_supported) {
  stopifnot(n_full >= n_covariate_complete, n_covariate_complete >= n_stage1_supported,
           n_stage1_supported >= n_stage2_supported,
           n_deals_full >= n_deals_stage1_supported, n_deals_stage1_supported >= n_deals_stage2_supported)
  list(
    n_treated_full_spine = n_full, n_treated_covariate_complete = n_covariate_complete,
    n_treated_stage1_deal_supported = n_stage1_supported, n_treated_stage2_supported = n_stage2_supported,
    n_deals_full_spine = n_deals_full, n_deals_stage1_supported = n_deals_stage1_supported,
    n_deals_stage2_supported = n_deals_stage2_supported,
    headline_inventor_retention = if (n_full > 0) n_stage2_supported / n_full else NA_real_,
    headline_deal_retention = if (n_deals_full > 0) n_deals_stage2_supported / n_deals_full else NA_real_,
    narrow_inventor_retention_stage1_denominator = if (n_stage1_supported > 0)
      n_stage2_supported / n_stage1_supported else NA_real_)
}
