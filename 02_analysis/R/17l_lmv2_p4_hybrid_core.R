# ============================================================================
# deal_ebal_hybrid_utils.R -- hybrid within-deal EB core (PILOT, for review)
# ============================================================================
# Design change under review (2026-07-24), NOT yet committed to the 17* files:
#
#   OLD (sequential, archived): Stage-1 firm EB -> firm weights -> base-weight
#   allocation to inventors -> Stage-2 inventor EB (inventor covariates only)
#   -> reaggregated firm-balance CHECK. Failure mode: the Stage-2 inventor
#   reweighting UNDOES the Stage-1 firm balance (deal 329 passed both solvers
#   yet had reaggregated firm SMDs 0.28-0.40).
#
#   NEW (hybrid): Stage 1 is recruitment/support-selection ONLY -- it defines
#   which firms (and hence control inventors) are eligible, and produces NO
#   final firm entropy weights. A SINGLE within-deal Stage-2 entropy solve then
#   balances the COMBINED vector of inventor covariates AND each inventor's
#   attached firm covariates at once. Firm balance is enforced INSIDE the one
#   solve, so there is no separate Stage-1 balance left for Stage 2 to undo.
#
# Control inventors enter the single solve with UNIFORM s.weights (there are no
# firm-EB weights to propagate). The certified lmv2_ebal_run_cohort() solver is
# reused verbatim -- uniform treated s.weights make the primary treated weight
# exactly 1 by its own finalize convention. Nothing in 15*/16*/17g is edited.
#
# No outcome, treatment effect, event panel, or P6 object is read here.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))

# The locked hybrid balance vector: 5 inventor covariates + 3 attached firm
# covariates. Firm covariates are carried on EACH inventor (treated inventors
# carry their target firm's values; control inventors carry their own focal
# firm's values), so the single solve balances the inventor-weighted mean of
# firm size to the target -- exactly the quantity the old reaggregation gate
# checked after the fact.
#
# CRITICAL: the attached firm covariates MUST carry a `firm_` prefix. The raw
# firm-covariate names (log_patent_stock_5y, log_inventor_count_5y,
# patent_trajectory) collide with the inventor covariate `patent_trajectory`
# (an inventor's OWN trajectory) -- if both entered the combined vector under
# the same name, c(inv, firm) would silently dedupe to 7 balance moments and
# one trajectory (inventor's or firm's) would go UNBALANCED. The harness must
# attach firm covariates under these prefixed names on every inventor row.
LMV2_HYBRID_INV_VARS  <- LMV2_P3$stage_2$scalar_variables
LMV2_HYBRID_FIRM_VARS <- c("firm_log_patent_stock_5y", "firm_log_inventor_count_5y",
                           "firm_patent_trajectory")
# Raw source column -> attached (prefixed) name, for the DB-facing harness.
LMV2_HYBRID_FIRM_ATTACH_MAP <- c(log_patent_stock_5y = "firm_log_patent_stock_5y",
                                 log_inventor_count_5y = "firm_log_inventor_count_5y",
                                 patent_trajectory = "firm_patent_trajectory")

# ---------------------------------------------------------------------------
# Recruitment support gate: a deal is "supported" only if at least `min_firms`
# distinct control firms survive the Stage-1 caliper (before any solve). Pure,
# no default caliper baked in -- the caller passes the eligible-firm count.
# ---------------------------------------------------------------------------
lmv2_ebal_deal_supported <- function(n_eligible_firms, min_firms = 5L) {
  isTRUE(is.finite(n_eligible_firms) && n_eligible_firms >= min_firms)
}

# ---------------------------------------------------------------------------
# Deterministic nearest-n-within-caliper computational cap. Within every
# (cohort, deal_id), keep the n firms with the smallest distance; ties broken
# by ascending control_group so the result is fully deterministic and twice-run
# identical. Never a random or arbitrary-smaller cap -- only this fixed rule.
# ---------------------------------------------------------------------------
lmv2_ebal_nearest_within_caliper <- function(admissible_edges, n) {
  required <- c("cohort", "deal_id", "control_group", "distance")
  if (!all(required %in% names(admissible_edges))) stop("Admissible firm-edge schema invalid")
  if (!nrow(admissible_edges)) return(admissible_edges)
  ord <- admissible_edges[order(admissible_edges$cohort, admissible_edges$deal_id,
                                admissible_edges$distance, admissible_edges$control_group), ,
                          drop = FALSE]
  key <- paste(ord$cohort, ord$deal_id)
  rank_within <- stats::ave(seq_len(nrow(ord)), key, FUN = seq_along)
  ord[rank_within <= n, , drop = FALSE]
}

# ---------------------------------------------------------------------------
# The single within-deal hybrid solve. `treated_roster` / `control_roster`
# each already carry all of inv_vars and firm_vars (attachment happened
# upstream in the DB-facing harness). Returns the full certified-solver result
# plus before/after SMDs split into inventor vs firm groups for reporting.
# ---------------------------------------------------------------------------
lmv2_ebal_hybrid_solve <- function(treated_roster, control_roster,
                                   inv_vars = LMV2_HYBRID_INV_VARS,
                                   firm_vars = LMV2_HYBRID_FIRM_VARS) {
  balance_vars <- c(inv_vars, firm_vars)
  if (!all(balance_vars %in% names(treated_roster))) stop("treated_roster missing balance vars")
  if (!all(balance_vars %in% names(control_roster))) stop("control_roster missing balance vars")
  roster <- rbind(
    cbind(D = 1L, treated_roster[balance_vars]),
    cbind(D = 0L, control_roster[balance_vars]))
  s_weights <- rep(1, nrow(roster))   # UNIFORM -- no firm-EB weights to propagate

  # Before-balance under uniform weights, on the SAME standardization the
  # solver uses internally (identical lmv2_ebal_standardize_cohort call).
  std <- lmv2_ebal_standardize_cohort(balance_vars, roster)
  use_vars <- setdiff(balance_vars, std$zero_variance)
  before <- lmv2_ebal_covariate_balance(use_vars, std$data, roster$D, s_weights)

  eb <- lmv2_ebal_run_cohort(balance_vars, roster, D_col = "D", s_weights = s_weights)
  after <- if (!is.null(eb$balance)) eb$balance else
    data.frame(variable = character(), abs_difference = numeric())

  split_max <- function(tbl, vs) {
    sub <- if (nrow(tbl)) tbl$abs_difference[tbl$variable %in% vs] else numeric()
    if (length(sub)) max(sub) else NA_real_
  }
  list(eb = eb, balance_before = before, balance_after = after,
       smd_inventor_before = split_max(before, inv_vars),
       smd_firm_before = split_max(before, firm_vars),
       smd_inventor_after = split_max(after, inv_vars),
       smd_firm_after = split_max(after, firm_vars),
       max_smd_after = if (nrow(after)) max(after$abs_difference) else NA_real_,
       n_treated = eb$n_treated, n_control = eb$n_control)
}

# ---------------------------------------------------------------------------
# Exact-vs-approximate feasibility classification (point 9). Exact entropy
# balancing either converges to its target moments (~0 SMD, tier exact/
# acceptable) or FAILS -- on failure WeightIt returns unusable NA/0 weights,
# so there is no "loose but usable" EB solution to measure. Attaining
# max|SMD| <= approx_tol when exact EB is infeasible requires a DISTINCT
# approximate-balancing estimator (proposed: optweight with tols=approx_tol,
# i.e. Zubizarreta-style stable balancing weights) that is NOT yet approved.
# This function therefore reports exact feasibility fully and FLAGS the
# approximate case as pending -- it never silently relaxes constraints.
# ---------------------------------------------------------------------------
lmv2_ebal_hybrid_feasibility <- function(eb, approx_tol = 0.10) {
  if (identical(eb$status, "pass")) {
    return(list(feasible = TRUE, mode = "exact_ebal", tier = eb$tier,
               realized_max_smd = eb$maxdiff, needs_approximate = FALSE))
  }
  list(feasible = FALSE, mode = "exact_infeasible", tier = eb$status,
       realized_max_smd = NA_real_, needs_approximate = TRUE, approx_tol = approx_tol)
}

# ---------------------------------------------------------------------------
# Equal-deal weights: a PURE rescale of the completed primary within-deal
# stack by 1/n_supported_treated -- never a second solve. Primary treated
# weights are 1 each (n_supported of them); dividing everything by n_supported
# makes equal-deal treated weights sum to exactly 1 within the deal.
# ---------------------------------------------------------------------------
lmv2_ebal_equal_deal_from_primary <- function(primary_treated, primary_control, n_supported) {
  stopifnot(n_supported > 0, length(primary_treated) == n_supported)
  list(treated = primary_treated / n_supported,
       control = primary_control / n_supported,
       treated_sum = sum(primary_treated / n_supported))
}
