# ============================================================================
# 17j_certify_lmv2_p4_ebal.R -- synthetic P4-EB acceptance checks (database-free)
# ============================================================================
# Every check runs on in-memory fixtures against the pure engine in
# 17g_lmv2_p4_ebal_utils.R. No database connection is opened. Check 0 (the
# base-weight semantics fixture) runs first, standalone: it is the same
# empirical determination recorded in the amendment, re-verified here so the
# certified package proves its own documented convention rather than merely
# asserting it. The end-to-end section near the bottom exercises
# lmv2_ebal_stage1_pipeline()/lmv2_ebal_stage2_pipeline()/
# lmv2_ebal_terminal_gate() directly -- the exact functions 17h/17i call --
# so the fixtures test production logic, never a parallel reimplementation.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))

audit_dir <- lmv2_ebal_read_arg("audit-dir", required = FALSE)
if (is.na(audit_dir)) audit_dir <- LMV2_P4_EBAL_PATHS$audit
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

checks <- list()
add_check <- function(check, observed, expected, pass) {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = check, observed = as.character(observed),
    expected = as.character(expected), pass = isTRUE(pass),
    stringsAsFactors = FALSE
  )
}

# =============================================================================
# Check 0: base-weight semantics -- CONTROL side. fit$weights is the tilt
# factor only; the final control weight is s.weights * fit$weights.
# =============================================================================
bw_data <- data.frame(X = c(1.6, 1.6, 0, 1, 2), D = c(1L, 1L, 0L, 0L, 0L))
bw_sw <- c(1, 1, 1, 2, 1)
bw_fitted <- lmv2_ebal_fit_cohort("X", bw_data, s_weights = bw_sw, maxit = 100000L)
bw_final <- lmv2_ebal_finalize_weights(bw_fitted$fit, bw_data$D, bw_sw)
ctrl <- bw_data$D == 0
target <- 1.6
mean_weights_alone <- sum(bw_fitted$fit$weights[ctrl] * bw_data$X[ctrl]) /
  sum(bw_fitted$fit$weights[ctrl])
mean_weights_times_sw <- sum(bw_fitted$fit$weights[ctrl] * bw_sw[ctrl] * bw_data$X[ctrl]) /
  sum(bw_fitted$fit$weights[ctrl] * bw_sw[ctrl])
add_check("base_weight_semantics_weights_alone_does_not_balance_control",
          sprintf("%.4f", mean_weights_alone), sprintf("not %.4f", target),
          abs(mean_weights_alone - target) > 0.01)
add_check("base_weight_semantics_weights_times_sweights_balances_control",
          sprintf("%.6f", mean_weights_times_sw), sprintf("%.6f", target),
          abs(mean_weights_times_sw - target) < 1e-4)
add_check("finalize_weights_control_side_implements_sw_times_fit_weights",
          sprintf("%.6f", sum(bw_final$weight[ctrl] * bw_data$X[ctrl]) / sum(bw_final$weight[ctrl])),
          sprintf("%.6f", target),
          bw_final$ok && abs(sum(bw_final$weight[ctrl] * bw_data$X[ctrl]) /
                              sum(bw_final$weight[ctrl]) - target) < 1e-4)
add_check("finalize_weights_control_mass_equals_treated_mass",
          sprintf("%.6f", sum(bw_final$weight[ctrl])), sprintf("%.6f", sum(bw_final$weight[bw_data$D == 1])),
          abs(sum(bw_final$weight[ctrl]) - sum(bw_final$weight[bw_data$D == 1])) < 1e-8)

# =============================================================================
# Check 0b: base-weight semantics -- TREATED side (the corrected finding).
# fit$weights[D==1] is always a constant regardless of input s.weights;
# unequal treated s.weights shift the target the controls are tilted
# toward; the final treated weight must be s.weights verbatim.
# =============================================================================
ts_X <- c(10, 10, 0, 0, 6, 12)
ts_D <- c(1L, 1L, 1L, 0L, 0L, 0L)
run_treated_side <- function(sw_treated) {
  sw <- c(sw_treated, 1, 1, 1)
  dat <- data.frame(X = ts_X, D = ts_D)
  fitted <- lmv2_ebal_fit_cohort("X", dat, s_weights = sw, maxit = 100000L)
  final <- lmv2_ebal_finalize_weights(fitted$fit, ts_D, sw)
  list(fit_weights_treated = fitted$fit$weights[ts_D == 1], final = final)
}
uniform_run <- run_treated_side(c(1, 1, 1))
unequal_run <- run_treated_side(c(0.5, 0.5, 1))
uniform_target <- sum(uniform_run$final$weight[ts_D == 0] * ts_X[ts_D == 0]) /
  sum(uniform_run$final$weight[ts_D == 0])
unequal_target <- sum(unequal_run$final$weight[ts_D == 0] * ts_X[ts_D == 0]) /
  sum(unequal_run$final$weight[ts_D == 0])
add_check("fit_weights_treated_side_is_always_constant",
          paste(c(uniform_run$fit_weights_treated, unequal_run$fit_weights_treated), collapse = ","),
          "1,1,1,1,1,1",
          all(abs(uniform_run$fit_weights_treated - 1) < 1e-8) &&
            all(abs(unequal_run$fit_weights_treated - 1) < 1e-8))
add_check("unequal_treated_sweights_shift_the_target",
          sprintf("uniform=%.4f unequal=%.4f", uniform_target, unequal_target),
          "uniform=6.6667 unequal=5.0000",
          abs(uniform_target - 20 / 3) < 1e-3 && abs(unequal_target - 5) < 1e-3)
add_check("finalize_weights_treated_side_is_verbatim_sweights_not_forced_to_one",
          paste(unequal_run$final$weight[ts_D == 1], collapse = ","), "0.5,0.5,1",
          isTRUE(all.equal(unequal_run$final$weight[ts_D == 1], c(0.5, 0.5, 1))))
add_check("finalize_weights_control_mass_equals_treated_mass_unequal_scheme",
          sprintf("%.6f,%.6f", sum(unequal_run$final$weight[ts_D == 0]), sum(unequal_run$final$weight[ts_D == 1])),
          "2.000000,2.000000",
          abs(sum(unequal_run$final$weight[ts_D == 0]) - 2) < 1e-4 &&
            abs(sum(unequal_run$final$weight[ts_D == 1]) - 2) < 1e-8)

# =============================================================================
# Exact balance / two-tier convergence classification
# =============================================================================
add_check("classify_exact_at_boundary", lmv2_ebal_classify(1e-6)$tier, "exact",
          identical(lmv2_ebal_classify(1e-6)$tier, "exact"))
add_check("classify_acceptable_just_above_exact", lmv2_ebal_classify(1e-6 * 1.5)$tier, "acceptable",
          identical(lmv2_ebal_classify(1e-6 * 1.5)$tier, "acceptable"))
add_check("classify_acceptable_at_residual_boundary", lmv2_ebal_classify(1e-3)$tier, "acceptable",
          identical(lmv2_ebal_classify(1e-3)$tier, "acceptable") &&
            isTRUE(lmv2_ebal_classify(1e-3)$converged))
add_check("classify_fails_just_above_residual_boundary",
          lmv2_ebal_classify(1e-3 * 1.001)$tier, "failed_residual_balance_tolerance",
          identical(lmv2_ebal_classify(1e-3 * 1.001)$tier, "failed_residual_balance_tolerance") &&
            !isTRUE(lmv2_ebal_classify(1e-3 * 1.001)$converged))
add_check("classify_nonfinite_fails", lmv2_ebal_classify(NA_real_)$tier,
          "failed_residual_balance_tolerance",
          identical(lmv2_ebal_classify(NA_real_)$tier, "failed_residual_balance_tolerance"))

exact_data <- data.frame(X1 = c(1.75, 1, 2), D = c(1L, 0L, 0L))
exact_fit <- lmv2_ebal_run_cohort("X1", exact_data, s_weights = c(1, 1, 1))
add_check("exact_balance_on_synthetic_two_control_case",
          paste(exact_fit$status, exact_fit$tier, sep = ","), "pass,exact",
          identical(exact_fit$status, "pass") && identical(exact_fit$tier, "exact") &&
            exact_fit$maxdiff < 1e-6)

# =============================================================================
# Solver failure / mass / weight-validity handling
# =============================================================================
err_fit <- simpleError("solver did not converge")
err_final <- lmv2_ebal_finalize_weights(err_fit, c(1L, 0L, 0L), c(1, 1, 1))
add_check("solver_error_yields_no_feasible_entropy_solution",
          paste(err_final$ok, err_final$reason), "FALSE no_feasible_entropy_solution",
          !err_final$ok && identical(err_final$reason, "no_feasible_entropy_solution"))

zero_mass_fit <- list(weights = c(NA_real_, 0, 0))
zero_mass_final <- lmv2_ebal_finalize_weights(zero_mass_fit, c(1L, 0L, 0L), c(1, 1, 1))
add_check("zero_control_mass_yields_inadequate_control_mass",
          paste(zero_mass_final$ok, zero_mass_final$reason), "FALSE inadequate_control_mass",
          !zero_mass_final$ok && identical(zero_mass_final$reason, "inadequate_control_mass"))

neg_fit <- list(weights = c(NA_real_, 2, -0.5))
neg_final <- lmv2_ebal_finalize_weights(neg_fit, c(1L, 0L, 0L), c(1, 1, 1))
add_check("negative_control_weight_flagged_not_ok",
          paste(neg_final$ok, neg_final$weights_ok), "TRUE FALSE",
          neg_final$ok && !neg_final$weights_ok)

zero_treated_sw_fit <- list(weights = c(NA_real_, 1, 1))
zero_treated_final <- lmv2_ebal_finalize_weights(zero_treated_sw_fit, c(1L, 0L, 0L), c(0, 1, 1))
add_check("zero_treated_sweight_flagged_not_ok",
          paste(zero_treated_final$ok, zero_treated_final$weights_ok), "TRUE FALSE",
          zero_treated_final$ok && !zero_treated_final$weights_ok)

# =============================================================================
# Empty treated/control cell
# =============================================================================
empty_ctrl <- data.frame(X1 = c(1, 1.1), D = c(1L, 1L))
empty_res <- lmv2_ebal_run_cohort("X1", empty_ctrl, s_weights = c(1, 1))
add_check("empty_control_cell_flagged", empty_res$status, "empty_treated_or_control_cell",
          identical(empty_res$status, "empty_treated_or_control_cell"))
empty_trt <- data.frame(X1 = c(1, 1.1), D = c(0L, 0L))
empty_res2 <- lmv2_ebal_run_cohort("X1", empty_trt, s_weights = c(1, 1))
add_check("empty_treated_cell_flagged", empty_res2$status, "empty_treated_or_control_cell",
          identical(empty_res2$status, "empty_treated_or_control_cell"))

# =============================================================================
# ESS and concentration diagnostics (report-only, hand-computed values)
# =============================================================================
add_check("ess_hand_value", format(lmv2_ebal_ess(c(1, 1, 2))), format(16 / 6),
          abs(lmv2_ebal_ess(c(1, 1, 2)) - 16 / 6) < 1e-9)
conc <- lmv2_ebal_concentration(c(1, 1, 2))
add_check("concentration_hand_values",
          paste(round(conc$max_share, 4), round(conc$top5_share, 4),
               round(conc$top1pct_share, 4), conc$n_materially_weighted, sep = ","),
          "0.5,1,0.5,3",
          abs(conc$max_share - 0.5) < 1e-9 && abs(conc$top5_share - 1) < 1e-9 &&
            abs(conc$top1pct_share - 0.5) < 1e-9 && conc$n_materially_weighted == 3L)
# Activated by the pre-E2 amendment (were diagnostic-only through E1) --
# lmv2_ebal_ess_concentration_gate() fixtures below exercise the gate itself.
add_check("concentration_and_ess_are_active_gates",
          paste(LMV2_P4_EBAL$active_gates, collapse = ","),
          "inadequate_ess,excessive_weight_concentration",
          identical(LMV2_P4_EBAL$active_gates,
                    c("inadequate_ess", "excessive_weight_concentration")))
add_check("stage1_ess_concentration_thresholds_locked",
          paste(LMV2_P4_EBAL$stage_1$ess_ratio$preferred, LMV2_P4_EBAL$stage_1$ess_ratio$acceptable,
               LMV2_P4_EBAL$stage_1$max_share$preferred, LMV2_P4_EBAL$stage_1$max_share$acceptable),
          "1 0.5 0.2 0.35",
          identical(LMV2_P4_EBAL$stage_1$ess_ratio, list(preferred = 1.0, acceptable = 0.5)) &&
            identical(LMV2_P4_EBAL$stage_1$max_share, list(preferred = 0.20, acceptable = 0.35)))
add_check("stage2_ess_concentration_thresholds_locked",
          paste(LMV2_P4_EBAL$stage_2$ess_ratio$preferred, LMV2_P4_EBAL$stage_2$ess_ratio$acceptable,
               LMV2_P4_EBAL$stage_2$max_share$preferred, LMV2_P4_EBAL$stage_2$max_share$acceptable),
          "1 0.5 0.1 0.2",
          identical(LMV2_P4_EBAL$stage_2$ess_ratio, list(preferred = 1.0, acceptable = 0.5)) &&
            identical(LMV2_P4_EBAL$stage_2$max_share, list(preferred = 0.10, acceptable = 0.20)))
add_check("deferred_calipers_and_resolution_now_locked",
          paste(LMV2_P4_EBAL$stage_1$caliper, LMV2_P4_EBAL$stage_2$caliper,
               LMV2_P4_EBAL$stage_2$technology_resolution),
          "1 1.5 ipc4",
          identical(LMV2_P4_EBAL$stage_1$caliper, 1.0) &&
            identical(LMV2_P4_EBAL$stage_2$caliper, 1.5) &&
            identical(LMV2_P4_EBAL$stage_2$technology_resolution, "ipc4"))

# =============================================================================
# Stage-1: admissible edges (deal-level, retained) vs. unique firm pool
# (collapsed) -- two distinct interfaces, never one.
# =============================================================================
edges1 <- data.frame(cohort = c(1L, 1L, 1L), deal_id = c(1L, 1L, 2L),
                     control_group = c(10, 20, 10), distance = c(1, 3, 0.5))
admissible1 <- lmv2_ebal_stage1_admissible_edges(edges1, 2)
add_check("stage1_admissible_edges_retains_deal_id_and_applies_caliper",
          paste(nrow(admissible1), paste(sort(admissible1$deal_id), collapse = ";"), sep = "|"),
          "2|1;2",
          nrow(admissible1) == 2L && "deal_id" %in% names(admissible1) &&
            identical(sort(admissible1$deal_id), c(1L, 2L)))
pool1 <- lmv2_ebal_stage1_unique_firm_pool(admissible1)
add_check("stage1_unique_firm_pool_collapses_and_counts_deals",
          paste(sort(pool1$control_group), collapse = ","), "10",
          identical(sort(pool1$control_group), 10) &&
            pool1$n_admissible_treated_deals[pool1$control_group == 10] == 2L &&
            !("deal_id" %in% names(pool1)))

# =============================================================================
# Stage-2: admissible edges, eligible controls, supported treated -- three
# distinct interfaces, never collapsed.
# =============================================================================
edges2 <- data.frame(cohort = c(1L, 1L, 1L),
                     deal_id = c(1L, 1L, 1L),
                     treated_codinv = c(100, 100, 200),
                     control_codinv = c(11, 12, 11),
                     control_group = c(1000, 2000, 1000),
                     distance = c(0.5, 3, 0.9))
admissible2 <- lmv2_ebal_stage2_admissible_edges(edges2, 2)
add_check("stage2_admissible_edges_applies_caliper_retains_grain",
          paste(nrow(admissible2), paste(sort(unique(admissible2$treated_codinv)), collapse = ";"), sep = "|"),
          "2|100;200",
          nrow(admissible2) == 2L && identical(sort(unique(admissible2$treated_codinv)), c(100, 200)))
eligible2 <- lmv2_ebal_stage2_eligible_controls(admissible2)
add_check("stage2_eligible_controls_unions_across_treated",
          paste(sort(eligible2$control_codinv), collapse = ","), "11",
          identical(sort(eligible2$control_codinv), 11) &&
            eligible2$n_admissible_treated_inventors[eligible2$control_codinv == 11] == 2L)
elig_firms2 <- lmv2_ebal_stage2_eligible_firms(eligible2)
add_check("stage2_eligible_firms_derived_from_eligible_controls",
          paste(elig_firms2$control_group, collapse = ","), "1000",
          identical(elig_firms2$control_group, 1000))

treated_spine2 <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = c(100, 200, 300))
support2 <- lmv2_ebal_stage2_supported_treated(admissible2, treated_spine2)
add_check("stage2_supported_treated_correct_grain_not_control_row_count",
          paste(nrow(support2$supported), nrow(support2$excluded), support2$excluded$reason, sep = "|"),
          "2|1|no_admissible_control_inventor",
          nrow(support2$supported) == 2L && nrow(support2$excluded) == 1L &&
            identical(support2$excluded$treated_codinv, 300) &&
            identical(support2$excluded$reason, "no_admissible_control_inventor"))

# =============================================================================
# Stage-1 roster: pre-filter admits only firms with >=1 Stage-2-eligible
# inventor -- the "zero lost mass by construction" mechanism.
# =============================================================================
candidate_pool <- data.frame(cohort = c(1L, 1L, 1L), control_group = c(10, 20, 30),
                             n_admissible_treated_deals = c(2L, 1L, 1L))
eligible_firms_fix <- data.frame(cohort = c(1L, 1L), control_group = c(10, 20))
treated_firm_covars_fix <- data.frame(
  cohort = c(1L, 1L), deal_id = c(1L, 2L),
  log_patent_stock_5y = c(1, 1.1), log_inventor_count_5y = c(1, 1.1),
  patent_trajectory = c(0, 0)
)
control_firm_covars_fix <- data.frame(
  cohort = rep(1L, 3), control_group = c(10, 20, 30),
  log_patent_stock_5y = c(1, 1, 1), log_inventor_count_5y = c(1, 1, 1),
  patent_trajectory = c(0, 0, 0)
)
roster_fix <- lmv2_ebal_stage1_roster(candidate_pool, eligible_firms_fix,
                                      treated_firm_covars_fix, control_firm_covars_fix)
add_check("stage1_roster_excludes_firm_with_zero_eligible_inventors",
          paste(roster_fix$excluded_firms$control_group, roster_fix$excluded_firms$reason),
          "30 zero_stage2_eligible_inventors",
          identical(roster_fix$excluded_firms$control_group, 30) &&
            identical(roster_fix$excluded_firms$reason, "zero_stage2_eligible_inventors"))
add_check("stage1_roster_control_side_only_admitted_firms",
          paste(sort(roster_fix$roster$control_group[roster_fix$roster$D == 0L]), collapse = ","),
          "10,20",
          identical(sort(roster_fix$roster$control_group[roster_fix$roster$D == 0L]), c(10, 20)))
add_check("stage1_roster_treated_side_has_two_deals",
          sum(roster_fix$roster$D == 1L), 2L,
          sum(roster_fix$roster$D == 1L) == 2L)

# =============================================================================
# Base-weight allocation: equal split, zero lost mass by construction
# =============================================================================
stage1_w <- data.frame(cohort = rep(1L, 2), control_group = c(10, 20), weight = c(0.6, 0.4))
eligible_controls_fix <- data.frame(
  cohort = rep(1L, 4), control_codinv = c(101, 102, 103, 201),
  control_group = c(10, 10, 10, 20)
)
base_w <- lmv2_ebal_allocate_base_weights(stage1_w, eligible_controls_fix)
add_check("base_weight_equal_split_three_inventor_firm",
          paste(base_w$base_weight[base_w$control_codinv %in% c(101, 102, 103)], collapse = ","),
          "0.2,0.2,0.2",
          all(abs(base_w$base_weight[base_w$control_codinv %in% c(101, 102, 103)] - 0.2) < 1e-12))
add_check("base_weight_single_inventor_firm_gets_full_mass",
          base_w$base_weight[base_w$control_codinv == 201], 0.4,
          abs(base_w$base_weight[base_w$control_codinv == 201] - 0.4) < 1e-12)
add_check("base_weight_conserves_total_mass_per_firm",
          sprintf("%.6f", sum(base_w$base_weight)), sprintf("%.6f", sum(stage1_w$weight)),
          abs(sum(base_w$base_weight) - sum(stage1_w$weight)) < 1e-9)

zero_elig_stage1_w <- data.frame(cohort = 1L, control_group = 99, weight = 0.5)
zero_elig_support <- data.frame(cohort = integer(), control_codinv = numeric(),
                                control_group = numeric())
add_check("allocate_base_weights_errors_when_eligible_controls_entirely_empty",
          tryCatch({ lmv2_ebal_allocate_base_weights(zero_elig_stage1_w, zero_elig_support); "no_error" },
                  error = function(e) "error_raised"),
          "error_raised",
          identical(tryCatch(lmv2_ebal_allocate_base_weights(zero_elig_stage1_w, zero_elig_support),
                             error = function(e) "error_raised"),
                    "error_raised"))
partial_support <- data.frame(cohort = 1L, control_codinv = 501, control_group = 88)
add_check("allocate_base_weights_errors_when_specific_firm_missing_support",
          tryCatch({ lmv2_ebal_allocate_base_weights(zero_elig_stage1_w, partial_support); "no_error" },
                  error = function(e) "error_raised"),
          "error_raised",
          identical(tryCatch(lmv2_ebal_allocate_base_weights(zero_elig_stage1_w, partial_support),
                             error = function(e) "error_raised"),
                    "error_raised"))

# =============================================================================
# Stage-2 roster: primary vs. equal-deal treated weighting; common support
# is ENFORCED by the roster builder itself (an unsupported treated inventor
# in `treated_inv_covars` must never reach the roster).
# =============================================================================
treated_inv_fix <- data.frame(
  cohort = rep(1L, 3), deal_id = c(1L, 1L, 2L), treated_codinv = c(11, 12, 21),
  log_patent_count_5y = c(1, 1, 1), patent_trajectory = c(0, 0, 0),
  career_age = c(5, 5, 5), focal_group_tenure = c(2, 2, 2), focal_group_exclusivity = c(1, 1, 1)
)
control_inv_fix <- data.frame(
  cohort = integer(), control_codinv = numeric(), control_group = numeric(),
  log_patent_count_5y = numeric(), patent_trajectory = numeric(), career_age = numeric(),
  focal_group_tenure = numeric(), focal_group_exclusivity = numeric()
)
base_w_fix <- data.frame(cohort = integer(), control_codinv = numeric(), control_group = numeric(),
                         base_weight = numeric())
supported_fix <- treated_inv_fix[c("cohort", "deal_id", "treated_codinv")]
roster_primary <- lmv2_ebal_stage2_roster(base_w_fix, treated_inv_fix, control_inv_fix,
                                          supported_fix, "primary")
roster_equal_deal <- lmv2_ebal_stage2_roster(base_w_fix, treated_inv_fix, control_inv_fix,
                                             supported_fix, "equal_deal")
add_check("stage2_roster_primary_treated_weight_is_one",
          paste(roster_primary$base_weight[roster_primary$D == 1L], collapse = ","), "1,1,1",
          all(roster_primary$base_weight[roster_primary$D == 1L] == 1))
eq <- roster_equal_deal[order(roster_equal_deal$treated_codinv), ]
eq <- eq[eq$D == 1L, ]
add_check("stage2_roster_equal_deal_splits_within_deal",
          paste(eq$base_weight, collapse = ","), "0.5,0.5,1",
          isTRUE(all.equal(eq$base_weight, c(0.5, 0.5, 1))))
add_check("stage2_roster_two_schemes_are_genuinely_different",
          !isTRUE(all.equal(roster_primary$base_weight[roster_primary$D == 1L],
                            roster_equal_deal$base_weight[roster_equal_deal$D == 1L])),
          TRUE,
          !isTRUE(all.equal(roster_primary$base_weight[roster_primary$D == 1L],
                            roster_equal_deal$base_weight[roster_equal_deal$D == 1L])))

supported_partial <- supported_fix[supported_fix$treated_codinv != 12, , drop = FALSE]
roster_partial <- lmv2_ebal_stage2_roster(base_w_fix, treated_inv_fix, control_inv_fix,
                                          supported_partial, "primary")
add_check("stage2_roster_enforces_common_support_itself_not_just_caller_promise",
          paste(sort(roster_partial$treated_codinv[roster_partial$D == 1L]), collapse = ","), "11,21",
          identical(sort(roster_partial$treated_codinv[roster_partial$D == 1L]), c(11, 21)) &&
            !(12 %in% roster_partial$treated_codinv[roster_partial$D == 1L]))

# =============================================================================
# Deal-specific Stage-2 candidate pairs: a firm admissible only for Deal A
# must never supply candidate controls for Deal B, even within the same
# cohort. This is the exact shared join 17h/17i must both use -- never a
# cohort-wide cross join of every treated inventor against every eligible
# (or positive-weight) firm, which would silently bypass the Stage-1,
# deal-specific admissibility check entirely.
# =============================================================================
admissible_edges_dealspecific <- data.frame(
  cohort = c(1L, 1L, 1L), deal_id = c(1L, 2L, 1L), control_group = c(10, 20, 30)
)  # firm 10 admissible only for deal 1; firm 20 only for deal 2; firm 30
   # admissible for deal 1 too, but has no donors at all (must contribute nothing)
donor_firms_dealspecific <- data.frame(
  cohort = c(1L, 1L), control_codinv = c(101, 201), control_group = c(10, 20)
)
treated_dealspecific <- data.frame(
  cohort = c(1L, 1L), deal_id = c(1L, 2L), treated_codinv = c(1001, 2001)
)
pairs_dealspecific <- lmv2_ebal_build_stage2_candidate_pairs(
  admissible_edges_dealspecific, donor_firms_dealspecific, treated_dealspecific)
add_check("build_stage2_candidate_pairs_firm_admissible_only_for_deal_a_never_supplies_deal_b",
          paste(sprintf("(%s,%s,%s)", pairs_dealspecific$deal_id, pairs_dealspecific$treated_codinv,
                       pairs_dealspecific$control_codinv), collapse = ";"),
          "(1,1001,101);(2,2001,201)",
          nrow(pairs_dealspecific) == 2L &&
            !any(pairs_dealspecific$deal_id == 2L & pairs_dealspecific$control_codinv == 101) &&
            !any(pairs_dealspecific$deal_id == 1L & pairs_dealspecific$control_codinv == 201) &&
            setequal(paste(pairs_dealspecific$deal_id, pairs_dealspecific$control_codinv),
                     c("1 101", "2 201")))
add_check("build_stage2_candidate_pairs_firm_with_no_donors_contributes_nothing",
          any(pairs_dealspecific$control_group == 30), FALSE,
          !any(pairs_dealspecific$control_group == 30))

# =============================================================================
# Cohort-scoped frozen-firm restriction: the same control_group id can
# recur across pseudo-event cohorts. A firm weighted in cohort 1 but not
# cohort 2 must never have its cohort-2 edges admitted merely because the
# same firm id carries positive Stage-1 weight elsewhere -- restricted by
# (cohort, control_group), never control_group alone. This must run BEFORE
# lmv2_ebal_build_stage2_candidate_pairs(), so the extra (cohort, firm)
# combination never reaches technology-similarity or distance construction.
# =============================================================================
stage1_weights_multi_cohort <- data.frame(
  cohort = c(1L, 3L), control_group = c(10, 99), weight = c(0.6, 0.4)
)  # firm 10 weighted only in cohort 1
admissible_edges_multi_cohort <- data.frame(
  cohort = c(1L, 2L), deal_id = c(1L, 5L), control_group = c(10, 10)
)  # firm 10 admissible in BOTH cohort 1 (frozen) and cohort 2 (NOT frozen --
   # same firm id, unrelated pseudo-event cohort)
restricted <- lmv2_ebal_restrict_to_frozen_firms(admissible_edges_multi_cohort, stage1_weights_multi_cohort)
add_check("restrict_to_frozen_firms_is_cohort_scoped_not_firm_id_alone",
          paste(nrow(restricted), paste(restricted$cohort, collapse = ","), sep = "|"), "1|1",
          nrow(restricted) == 1L && identical(restricted$cohort, 1L) && identical(restricted$deal_id, 1L))

buggy_firm_id_only_restriction <- admissible_edges_multi_cohort[
  admissible_edges_multi_cohort$control_group %in% unique(stage1_weights_multi_cohort$control_group), ]
add_check("restrict_to_frozen_firms_fixes_the_firm_id_only_regression",
          paste(nrow(buggy_firm_id_only_restriction), nrow(restricted), sep = ","), "2,1",
          nrow(buggy_firm_id_only_restriction) == 2L && nrow(restricted) == 1L)

donor_firms_multi_cohort <- data.frame(
  cohort = c(1L, 2L), control_codinv = c(101, 102), control_group = c(10, 10)
)
treated_multi_cohort <- data.frame(
  cohort = c(1L, 2L), deal_id = c(1L, 5L), treated_codinv = c(1001, 5001)
)
pairs_multi_cohort <- lmv2_ebal_build_stage2_candidate_pairs(
  restricted, donor_firms_multi_cohort, treated_multi_cohort)
add_check("restrict_to_frozen_firms_excludes_cohort_b_edge_before_pair_construction",
          paste(nrow(pairs_multi_cohort), paste(unique(pairs_multi_cohort$cohort), collapse = ","), sep = "|"),
          "1|1",
          nrow(pairs_multi_cohort) == 1L && identical(unique(pairs_multi_cohort$cohort), 1L))

# =============================================================================
# Regression: lmv2_prepare_stage2_edges()'s (16c, certified P3 engine)
# `shared_ipc4` argument must be keyed by (cohort, treated_codinv,
# control_codinv) ONLY. A deal_id column there collides with the edges'
# own deal_id on that internal merge (which is NOT keyed by deal_id) and
# gets silently suffixed to deal_id.x/deal_id.y instead of merged, breaking
# every subsequent deal_id reference inside the function. This exact defect
# was present in both 17h and 17i (both built shared_flags from the full
# pair_key_cols, including deal_id) and was found only by running the real,
# non-outcome pre-E2 diagnostics against the real database -- it would have
# crashed the very first real Stage-2 execution. Certified here so the
# correct construction (pair_key_cols[-2], dropping deal_id) can never
# regress back to the broken one undetected.
prep_treated <- data.frame(cohort = 1L, deal_id = 1L, codinv = 11, recency_bin = 0,
                           log_patent_count_5y = 1, patent_trajectory = 0, career_age = 5,
                           focal_group_tenure = 2, focal_group_exclusivity = 0.5)
prep_controls <- data.frame(cohort = 1L, codinv = 101, focal_group = 10, recency_bin = 0,
                            log_patent_count_5y = 1, patent_trajectory = 0, career_age = 5,
                            focal_group_tenure = 2, focal_group_exclusivity = 0.5)
prep_pair_map <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = 11, control_codinv = 101)
prep_similarity <- data.frame(cohort = 1L, treated_codinv = 11, control_codinv = 101, cosine = 0.5)

shared_correct <- data.frame(cohort = 1L, treated_codinv = 11, control_codinv = 101, shared_ipc4 = TRUE)
prep_correct <- lmv2_prepare_stage2_edges(prep_treated, prep_controls, prep_pair_map,
                                          prep_similarity, shared_correct, "ipc4")
add_check("prepare_stage2_edges_shared_ipc4_without_deal_id_keeps_clean_deal_id_column",
          paste("deal_id" %in% names(prep_correct$edges), "deal_id.x" %in% names(prep_correct$edges),
               sep = ","),
          "TRUE,FALSE",
          "deal_id" %in% names(prep_correct$edges) && !("deal_id.x" %in% names(prep_correct$edges)) &&
            identical(prep_correct$edges$deal_id, 1L))

shared_wrong <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = 11, control_codinv = 101,
                           shared_ipc4 = TRUE)
prep_wrong <- tryCatch(lmv2_prepare_stage2_edges(prep_treated, prep_controls, prep_pair_map,
                                                 prep_similarity, shared_wrong, "ipc4"),
                       error = function(e) "error")
add_check("prepare_stage2_edges_shared_ipc4_with_deal_id_reproduces_the_regression",
          if (identical(prep_wrong, "error")) "error" else
            paste("deal_id" %in% names(prep_wrong$edges), "deal_id.x" %in% names(prep_wrong$edges), sep = ","),
          "regression reproduced: error, or deal_id.x present without clean deal_id",
          identical(prep_wrong, "error") ||
            (!("deal_id" %in% names(prep_wrong$edges)) && "deal_id.x" %in% names(prep_wrong$edges)))

# =============================================================================
# Post-Stage-2 firm-reaggregation gate: estimand-correct target, hard
# failure on missing target/scaler, 0.05/0.10 tiers, zero-variance handling.
# =============================================================================
s2w <- data.frame(cohort = rep(1L, 2), control_group = c(100, 200), weight = c(0.5, 1.5))
firm_covars_fix <- data.frame(
  cohort = rep(1L, 2), control_group = c(100, 200),
  log_patent_stock_5y = c(1, 2), log_inventor_count_5y = c(0, 1), patent_trajectory = c(0, 0)
)
sd_fix <- data.frame(cohort = rep(1L, 3),
                     variable = c("log_patent_stock_5y", "log_inventor_count_5y", "patent_trajectory"),
                     mean = c(1.5, 0.5, 0), sd = c(1, 1, 1), zero_variance = c(FALSE, FALSE, FALSE))
target_exact <- data.frame(cohort = rep(1L, 3),
                           variable = c("log_patent_stock_5y", "log_inventor_count_5y", "patent_trajectory"),
                           treated_mean = c(1.75, 0.75, 0))
gate_exact <- lmv2_ebal_stage2_firm_reaggregation_gate(s2w, firm_covars_fix, target_exact, sd_fix)
add_check("firm_reaggregation_gate_exact_match_is_preferred",
          paste(gate_exact$status, gate_exact$tier, round(gate_exact$max_abs_smd, 6), sep = ","),
          "pass,preferred,0", identical(gate_exact$status, "pass") &&
            identical(gate_exact$tier, "preferred") && gate_exact$max_abs_smd < 1e-9)

target_acc <- target_exact
target_acc$treated_mean[target_acc$variable == "log_patent_stock_5y"] <- 1.75 - 0.07
gate_acc <- lmv2_ebal_stage2_firm_reaggregation_gate(s2w, firm_covars_fix, target_acc, sd_fix)
add_check("firm_reaggregation_gate_acceptable_tier",
          paste(gate_acc$status, gate_acc$tier, sep = ","), "pass,acceptable",
          identical(gate_acc$status, "pass") && identical(gate_acc$tier, "acceptable"))

target_fail <- target_exact
target_fail$treated_mean[target_fail$variable == "log_patent_stock_5y"] <- 5
gate_fail <- lmv2_ebal_stage2_firm_reaggregation_gate(s2w, firm_covars_fix, target_fail, sd_fix)
add_check("firm_reaggregation_gate_fails_beyond_acceptable",
          paste(gate_fail$status, gate_fail$tier, sep = ","),
          "stage2_firm_reaggregation_failure,stage2_firm_reaggregation_failure",
          identical(gate_fail$status, "stage2_firm_reaggregation_failure"))

target_missing <- target_exact[target_exact$variable != "log_patent_stock_5y", , drop = FALSE]
gate_missing_target <- lmv2_ebal_stage2_firm_reaggregation_gate(s2w, firm_covars_fix, target_missing, sd_fix)
add_check("firm_reaggregation_gate_hard_fails_on_missing_target_not_smd_zero",
          gate_missing_target$status, "stage2_firm_reaggregation_failure",
          identical(gate_missing_target$status, "stage2_firm_reaggregation_failure") &&
            isTRUE(gate_missing_target$hard_fail) &&
            "missing_target_or_scaler" %in% gate_missing_target$detail$status)

sd_missing <- sd_fix[sd_fix$variable != "log_patent_stock_5y", , drop = FALSE]
gate_missing_scaler <- lmv2_ebal_stage2_firm_reaggregation_gate(s2w, firm_covars_fix, target_exact, sd_missing)
add_check("firm_reaggregation_gate_hard_fails_on_missing_scaler_not_smd_zero",
          gate_missing_scaler$status, "stage2_firm_reaggregation_failure",
          identical(gate_missing_scaler$status, "stage2_firm_reaggregation_failure") &&
            isTRUE(gate_missing_scaler$hard_fail) &&
            "missing_target_or_scaler" %in% gate_missing_scaler$detail$status)

sd_zero_var_recorded <- sd_fix
sd_zero_var_recorded$sd[sd_zero_var_recorded$variable == "log_patent_stock_5y"] <- NA_real_
sd_zero_var_recorded$zero_variance[sd_zero_var_recorded$variable == "log_patent_stock_5y"] <- TRUE
gate_zero_var <- lmv2_ebal_stage2_firm_reaggregation_gate(s2w, firm_covars_fix, target_fail,
                                                          sd_zero_var_recorded)
add_check("firm_reaggregation_gate_recorded_zero_variance_is_smd_zero_not_hard_fail",
          paste(gate_zero_var$status, gate_zero_var$tier, sep = ","), "pass,preferred",
          identical(gate_zero_var$status, "pass") && !isTRUE(gate_zero_var$hard_fail))

sd_unrecorded_degenerate <- sd_fix
sd_unrecorded_degenerate$sd[sd_unrecorded_degenerate$variable == "log_patent_stock_5y"] <- 0
gate_unrecorded_degenerate <- lmv2_ebal_stage2_firm_reaggregation_gate(
  s2w, firm_covars_fix, target_exact, sd_unrecorded_degenerate)
add_check("firm_reaggregation_gate_unrecorded_degenerate_scaler_is_hard_fail",
          gate_unrecorded_degenerate$status, "stage2_firm_reaggregation_failure",
          identical(gate_unrecorded_degenerate$status, "stage2_firm_reaggregation_failure") &&
            "unrecorded_degenerate_scaler" %in% gate_unrecorded_degenerate$detail$status)

movement <- lmv2_ebal_stage1_prior_movement(
  gate_exact$firm_mass,
  data.frame(cohort = rep(1L, 2), control_group = c(100, 200), weight = c(0.6, 1.4)))
add_check("stage1_prior_movement_reported_not_gated",
          paste(round(movement$movement, 6), collapse = ","), "-0.1,0.1",
          isTRUE(all.equal(sort(movement$movement), c(-0.1, 0.1))))

# =============================================================================
# Treated firm target: built from RETAINED treated inventors, per estimand.
# =============================================================================
supported_target_fix <- data.frame(cohort = c(1L, 1L, 1L), deal_id = c(1L, 1L, 2L),
                                   treated_codinv = c(11, 12, 21))
treated_firm_covars_target_fix <- data.frame(cohort = c(1L, 1L), deal_id = c(1L, 2L),
                                             log_patent_stock_5y = c(2, 4),
                                             log_inventor_count_5y = c(1, 1),
                                             patent_trajectory = c(0, 0))
target_primary <- lmv2_ebal_treated_firm_target(supported_target_fix, treated_firm_covars_target_fix, "primary")
target_equal <- lmv2_ebal_treated_firm_target(supported_target_fix, treated_firm_covars_target_fix, "equal_deal")
add_check("treated_firm_target_primary_weights_by_retained_inventor_count",
          target_primary$treated_mean[target_primary$variable == "log_patent_stock_5y"],
          (2 * 2 + 4 * 1) / 3,
          abs(target_primary$treated_mean[target_primary$variable == "log_patent_stock_5y"] -
                (2 * 2 + 4 * 1) / 3) < 1e-9)
add_check("treated_firm_target_equal_deal_weights_each_deal_equally",
          target_equal$treated_mean[target_equal$variable == "log_patent_stock_5y"], 3,
          abs(target_equal$treated_mean[target_equal$variable == "log_patent_stock_5y"] - 3) < 1e-9)

# =============================================================================
# Retention summary and gate
# =============================================================================
treated_spine_ret <- data.frame(
  cohort = c(1L, 1L, 1L, 1L, 2L, 2L),
  deal_id = c(1L, 1L, 2L, 2L, 3L, 3L),
  treated_codinv = c(11, 12, 21, 22, 31, 32)
)
supported_ret <- treated_spine_ret[c(1, 2, 3), ]  # deal 1 fully retained, deal 2 half, deal 3 dropped
retention <- lmv2_ebal_retention_summary(supported_ret, treated_spine_ret)
add_check("retention_summary_inventor_retention_is_treated_inventor_count_not_control_rows",
          sprintf("%.4f", retention$overall$inventor_retention), sprintf("%.4f", 3 / 6),
          abs(retention$overall$inventor_retention - 3 / 6) < 1e-9)
add_check("retention_summary_deal_retention_counts_deals_with_ge1_retained",
          sprintf("%.4f", retention$overall$deal_retention), sprintf("%.4f", 2 / 3),
          abs(retention$overall$deal_retention - 2 / 3) < 1e-9)
add_check("retention_summary_by_cohort_matches_hand_counts",
          paste(retention$by_cohort$n_eligible_inventors, retention$by_cohort$n_retained_inventors,
               sep = ":", collapse = ","),
          "4:3,2:0",
          identical(retention$by_cohort$n_eligible_inventors, c(4L, 2L)) &&
            identical(retention$by_cohort$n_retained_inventors, c(3L, 0L)))

deal_category_ret <- data.frame(cohort = c(1L, 1L, 2L), deal_id = c(1L, 2L, 3L),
                                category = c("big", "small", "small"))
retention_cat <- lmv2_ebal_retention_summary(supported_ret, treated_spine_ret, deal_category_ret)
add_check("retention_by_category_correct",
          paste(retention_cat$by_category$category, retention_cat$by_category$n_retained_inventors,
               sep = ":", collapse = ","),
          "big:2,small:1",
          identical(as.character(retention_cat$by_category$category), c("big", "small")) &&
            identical(retention_cat$by_category$n_retained_inventors, c(2L, 1L)))

mk_retention <- function(inv_ret, deal_ret, cohort_ok = TRUE, category_ok = TRUE) {
  list(overall = data.frame(inventor_retention = inv_ret, deal_retention = deal_ret),
      by_cohort = data.frame(inventor_retention = if (cohort_ok) c(inv_ret, inv_ret) else c(inv_ret, 0.1)),
      by_category = if (category_ok) NULL else
        data.frame(n_retained_inventors = c(5L, 0L)))
}
gate_preferred <- lmv2_ebal_retention_gate(mk_retention(0.95, 0.95))
gate_acceptable <- lmv2_ebal_retention_gate(mk_retention(0.85, 0.87))
gate_failed <- lmv2_ebal_retention_gate(mk_retention(0.5, 0.5))
gate_cohort_floor_fail <- lmv2_ebal_retention_gate(mk_retention(0.95, 0.95, cohort_ok = FALSE))
gate_category_fail <- lmv2_ebal_retention_gate(mk_retention(0.95, 0.95, category_ok = FALSE))
add_check("retention_gate_tiers",
          paste(gate_preferred$tier, gate_acceptable$tier, gate_failed$tier,
               gate_cohort_floor_fail$tier, gate_category_fail$tier, sep = ","),
          "preferred,acceptable,failed_retention,failed_retention,failed_retention",
          identical(gate_preferred$tier, "preferred") && identical(gate_acceptable$tier, "acceptable") &&
            identical(gate_failed$tier, "failed_retention") &&
            identical(gate_cohort_floor_fail$tier, "failed_retention") &&
            identical(gate_category_fail$tier, "failed_retention"))
add_check("retention_gate_cohort_floor_and_category_flags",
          paste(gate_cohort_floor_fail$cohort_floor_ok, gate_category_fail$category_preserved, sep = ","),
          "FALSE,FALSE",
          !gate_cohort_floor_fail$cohort_floor_ok && !gate_category_fail$category_preserved)

# =============================================================================
# Retention-tier labeling (reuses the locked common-support threshold, 0.90)
# =============================================================================
add_check("retention_label_boundary_at_ninety_percent",
          paste(lmv2_ebal_retention_label(0.90), lmv2_ebal_retention_label(0.8999), sep = "|"),
          paste(LMV2_LOCK$estimands$primary, "common-support ATT", sep = "|"),
          identical(lmv2_ebal_retention_label(0.90), LMV2_LOCK$estimands$primary) &&
            identical(lmv2_ebal_retention_label(0.8999), "common-support ATT"))

# =============================================================================
# Exclusion funnel: mutually exclusive terminal reasons, no silent deletion
# =============================================================================
state <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = c(1, 2, 3),
                    terminal_reason = NA_character_, stringsAsFactors = FALSE)
survive1 <- paste(1, 1, c(2, 3), sep = "\r")
state <- lmv2_ebal_funnel_step(state, survive1, "no_admissible_control_firm")
survive2 <- paste(1, 1, c(3), sep = "\r")
state <- lmv2_ebal_funnel_step(state, survive2, "no_local_support")
add_check("funnel_step_mutually_exclusive_reasons",
          paste(ifelse(is.na(state$terminal_reason), "pending", state$terminal_reason), collapse = ","),
          "no_admissible_control_firm,no_local_support,pending",
          identical(state$terminal_reason, c("no_admissible_control_firm", "no_local_support", NA_character_)))

# =============================================================================
# Stage-2-matches-Stage-1-freeze verification
# =============================================================================
freeze_ok <- data.frame(stage2_caliper = 2, technology_resolution = "ipc4")
freeze_inf <- data.frame(stage2_caliper = NA_real_, technology_resolution = "ipc4")
add_check("verify_stage2_matches_freeze_pass",
          lmv2_ebal_verify_stage2_matches_freeze(freeze_ok, 2, "ipc4")$ok, TRUE,
          isTRUE(lmv2_ebal_verify_stage2_matches_freeze(freeze_ok, 2, "ipc4")$ok))
add_check("verify_stage2_matches_freeze_inf_caliper",
          lmv2_ebal_verify_stage2_matches_freeze(freeze_inf, Inf, "ipc4")$ok, TRUE,
          isTRUE(lmv2_ebal_verify_stage2_matches_freeze(freeze_inf, Inf, "ipc4")$ok))
add_check("verify_stage2_matches_freeze_caliper_mismatch",
          lmv2_ebal_verify_stage2_matches_freeze(freeze_ok, 1.5, "ipc4")$caliper_ok, FALSE,
          !lmv2_ebal_verify_stage2_matches_freeze(freeze_ok, 1.5, "ipc4")$caliper_ok)
add_check("verify_stage2_matches_freeze_resolution_mismatch",
          lmv2_ebal_verify_stage2_matches_freeze(freeze_ok, 2, "ipc_main_group")$resolution_ok, FALSE,
          !lmv2_ebal_verify_stage2_matches_freeze(freeze_ok, 2, "ipc_main_group")$resolution_ok)

# =============================================================================
# Determinism and non-degenerate weights (final weights are not fixed 1/3 or 1/5)
# =============================================================================
het_data <- data.frame(X1 = c(2.2, 1.8, 0.1, 1.0, 2.0, 3.0, 0.5),
                       X2 = c(1.1, 0.9, 3.0, 0.5, 1.5, 0.2, 2.5),
                       D = c(1L, 1L, 0L, 0L, 0L, 0L, 0L))
het_sw <- c(1, 1, 1, 3, 1, 2, 1)
r1 <- lmv2_ebal_run_cohort(c("X1", "X2"), het_data, s_weights = het_sw)
r2 <- lmv2_ebal_run_cohort(c("X1", "X2"), het_data, s_weights = het_sw)
add_check("deterministic_output_given_fixed_input",
          identical(r1$weight, r2$weight), TRUE, identical(r1$weight, r2$weight))
control_w <- r1$weight[het_data$D == 0]
add_check("final_weights_not_fixed_one_fifth_or_one_third",
          sprintf("var=%.6f", stats::var(control_w)), "var>0",
          identical(r1$status, "pass") && stats::var(control_w) > 1e-10 &&
            !isTRUE(all.equal(control_w, rep(control_w[1], length(control_w)))))

# =============================================================================
# Genuine equal-deal SOLVER fixture with two unequal-size deals (item 1).
# Deal A: 3 treated inventors at X=10. Deal B: 1 treated inventor at X=0.
# Primary target (inventor-weighted) = 7.5. Equal-deal target (deal-
# weighted) = 5. Controls X = 0, 6, 12 (base weight 1 each) bracket both.
# =============================================================================
treated_ed <- data.frame(
  cohort = 1L, deal_id = c(1L, 1L, 1L, 2L), treated_codinv = c(101, 102, 103, 201),
  log_patent_count_5y = c(10, 10, 10, 0), patent_trajectory = 0, career_age = 0,
  focal_group_tenure = 0, focal_group_exclusivity = 0
)
control_ed <- data.frame(
  cohort = 1L, control_codinv = c(901, 902, 903), control_group = c(9001, 9002, 9003),
  log_patent_count_5y = c(0, 6, 12), patent_trajectory = 0, career_age = 0,
  focal_group_tenure = 0, focal_group_exclusivity = 0
)
base_w_ed <- data.frame(cohort = 1L, control_codinv = c(901, 902, 903),
                        control_group = c(9001, 9002, 9003), base_weight = 1)
supported_ed <- treated_ed[c("cohort", "deal_id", "treated_codinv")]

roster_ed_primary <- lmv2_ebal_stage2_roster(base_w_ed, treated_ed, control_ed, supported_ed, "primary")
roster_ed_equal <- lmv2_ebal_stage2_roster(base_w_ed, treated_ed, control_ed, supported_ed, "equal_deal")

trt_mass_primary <- tapply(roster_ed_primary$base_weight[roster_ed_primary$D == 1L],
                           roster_ed_primary$deal_id[roster_ed_primary$D == 1L], sum)
trt_mass_equal <- tapply(roster_ed_equal$base_weight[roster_ed_equal$D == 1L],
                         roster_ed_equal$deal_id[roster_ed_equal$D == 1L], sum)
# as.numeric(), not unname(): tapply() returns a 1-D array, and unname()
# strips names but not the array dim attribute, which would otherwise make
# all.equal() report a spurious "target is array, current is numeric"
# attribute mismatch even when the values themselves are correct.
add_check("equal_deal_fixture_primary_treated_mass_proportional_to_inventor_count",
          paste(trt_mass_primary, collapse = ","), "3,1",
          isTRUE(all.equal(as.numeric(trt_mass_primary[c("1", "2")]), c(3, 1))))
add_check("equal_deal_fixture_equal_deal_treated_mass_is_equal_per_deal",
          paste(trt_mass_equal, collapse = ","), "1,1",
          isTRUE(all.equal(as.numeric(trt_mass_equal[c("1", "2")]), c(1, 1))))

solve_ed_primary <- lmv2_ebal_run_cohort("log_patent_count_5y", roster_ed_primary,
                                         s_weights = roster_ed_primary$base_weight)
solve_ed_equal <- lmv2_ebal_run_cohort("log_patent_count_5y", roster_ed_equal,
                                       s_weights = roster_ed_equal$base_weight)
ed_target_primary <- sum(solve_ed_primary$control_weight * control_ed$log_patent_count_5y) /
  sum(solve_ed_primary$control_weight)
ed_target_equal <- sum(solve_ed_equal$control_weight * control_ed$log_patent_count_5y) /
  sum(solve_ed_equal$control_weight)
add_check("equal_deal_fixture_primary_balance_hits_inventor_weighted_target",
          sprintf("%.4f", ed_target_primary), sprintf("%.4f", 7.5),
          identical(solve_ed_primary$status, "pass") && abs(ed_target_primary - 7.5) < 1e-3)
add_check("equal_deal_fixture_equal_deal_balance_hits_deal_weighted_target",
          sprintf("%.4f", ed_target_equal), sprintf("%.4f", 5),
          identical(solve_ed_equal$status, "pass") && abs(ed_target_equal - 5) < 1e-3)
add_check("equal_deal_fixture_two_solves_produce_different_control_weights",
          !isTRUE(all.equal(solve_ed_primary$control_weight, solve_ed_equal$control_weight)), TRUE,
          !isTRUE(all.equal(solve_ed_primary$control_weight, solve_ed_equal$control_weight)))
add_check("equal_deal_fixture_control_mass_equals_appropriate_treated_mass",
          sprintf("%.4f,%.4f", sum(solve_ed_primary$control_weight), sum(solve_ed_equal$control_weight)),
          "4.0000,2.0000",
          abs(sum(solve_ed_primary$control_weight) - 4) < 1e-3 &&
            abs(sum(solve_ed_equal$control_weight) - 2) < 1e-3)

# =============================================================================
# Terminal gate: each of the required failure reasons, individually, plus a
# full-pass case.
# =============================================================================
mk_pass_cohort <- function(g) list(status = "pass", tier = "exact", maxdiff = 1e-7, cohort = g)
mk_fail_cohort <- function(g) list(status = "failed_residual_balance_tolerance", tier = NA_character_,
                                   maxdiff = 0.5, cohort = g)
mk_scheme_result <- function(per_cohort, firm_gate_status = "pass",
                             firm_mass_cohorts = names(per_cohort),
                             weight_cohorts = names(per_cohort),
                             retention_pass = TRUE, cohort_floor_ok = TRUE, category_preserved = TRUE,
                             ess_concentration_pass = TRUE) {
  list(per_cohort = per_cohort,
      weights = data.frame(cohort = as.integer(weight_cohorts)),
      firm_gate = list(status = firm_gate_status,
                       firm_mass = data.frame(cohort = as.integer(firm_mass_cohorts))),
      retention_gate = list(pass = retention_pass, cohort_floor_ok = cohort_floor_ok,
                            category_preserved = category_preserved),
      ess_concentration_gate = list(pass = ess_concentration_pass))
}

full_pass <- mk_scheme_result(list(`1` = mk_pass_cohort(1L), `2` = mk_pass_cohort(2L)))
gate_full_pass <- lmv2_ebal_terminal_gate(full_pass, c(1L, 2L))
add_check("terminal_gate_full_pass", paste(gate_full_pass$pass, length(gate_full_pass$reasons)), "TRUE 0",
          gate_full_pass$pass && length(gate_full_pass$reasons) == 0L)

missing_cohort_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L)))
gate_missing_cohort <- lmv2_ebal_terminal_gate(missing_cohort_result, c(1L, 2L))
add_check("terminal_gate_missing_cohort_in_solver_results",
          paste(gate_missing_cohort$pass, "missing_cohort_in_solver_results" %in% gate_missing_cohort$reasons),
          "FALSE TRUE",
          !gate_missing_cohort$pass && "missing_cohort_in_solver_results" %in% gate_missing_cohort$reasons)

failed_balance_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L), `2` = mk_fail_cohort(2L)))
gate_failed_balance <- lmv2_ebal_terminal_gate(failed_balance_result, c(1L, 2L))
add_check("terminal_gate_cohort_inventor_balance_failed",
          "cohort_inventor_balance_failed" %in% gate_failed_balance$reasons, TRUE,
          "cohort_inventor_balance_failed" %in% gate_failed_balance$reasons)

firm_gate_failed_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L), `2` = mk_pass_cohort(2L)),
                                            firm_gate_status = "stage2_firm_reaggregation_failure")
gate_firm_failed <- lmv2_ebal_terminal_gate(firm_gate_failed_result, c(1L, 2L))
add_check("terminal_gate_firm_reaggregation_failed",
          "firm_reaggregation_failed" %in% gate_firm_failed$reasons, TRUE,
          "firm_reaggregation_failed" %in% gate_firm_failed$reasons)

firm_gate_missing_cohort_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L), `2` = mk_pass_cohort(2L)),
                                                    firm_mass_cohorts = "1")
gate_firm_missing_cohort <- lmv2_ebal_terminal_gate(firm_gate_missing_cohort_result, c(1L, 2L))
add_check("terminal_gate_firm_reaggregation_missing_cohort",
          "firm_reaggregation_missing_cohort" %in% gate_firm_missing_cohort$reasons, TRUE,
          "firm_reaggregation_missing_cohort" %in% gate_firm_missing_cohort$reasons)

retention_fail_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L), `2` = mk_pass_cohort(2L)),
                                          retention_pass = FALSE)
gate_retention_fail <- lmv2_ebal_terminal_gate(retention_fail_result, c(1L, 2L))
add_check("terminal_gate_retention_below_acceptable_tier",
          "retention_below_acceptable_tier" %in% gate_retention_fail$reasons, TRUE,
          "retention_below_acceptable_tier" %in% gate_retention_fail$reasons)

cohort_floor_fail_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L), `2` = mk_pass_cohort(2L)),
                                             cohort_floor_ok = FALSE)
gate_cohort_floor_fail_terminal <- lmv2_ebal_terminal_gate(cohort_floor_fail_result, c(1L, 2L))
add_check("terminal_gate_cohort_below_fifty_percent_floor",
          "cohort_below_fifty_percent_floor" %in% gate_cohort_floor_fail_terminal$reasons, TRUE,
          "cohort_below_fifty_percent_floor" %in% gate_cohort_floor_fail_terminal$reasons)

category_fail_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L), `2` = mk_pass_cohort(2L)),
                                         category_preserved = FALSE)
gate_category_fail_terminal <- lmv2_ebal_terminal_gate(category_fail_result, c(1L, 2L))
add_check("terminal_gate_target_size_category_disappeared",
          "target_size_category_disappeared" %in% gate_category_fail_terminal$reasons, TRUE,
          "target_size_category_disappeared" %in% gate_category_fail_terminal$reasons)

nonfinite_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L),
                                          `2` = list(status = "pass", tier = "exact",
                                                    maxdiff = NA_real_, cohort = 2L)))
gate_nonfinite <- lmv2_ebal_terminal_gate(nonfinite_result, c(1L, 2L))
add_check("terminal_gate_nonfinite_diagnostics",
          "nonfinite_diagnostics" %in% gate_nonfinite$reasons, TRUE,
          "nonfinite_diagnostics" %in% gate_nonfinite$reasons)

ess_concentration_fail_result <- mk_scheme_result(list(`1` = mk_pass_cohort(1L), `2` = mk_pass_cohort(2L)),
                                                  ess_concentration_pass = FALSE)
gate_ess_concentration_fail <- lmv2_ebal_terminal_gate(ess_concentration_fail_result, c(1L, 2L))
add_check("terminal_gate_stage2_ess_concentration_below_acceptable_tier",
          "stage2_ess_concentration_below_acceptable_tier" %in% gate_ess_concentration_fail$reasons, TRUE,
          "stage2_ess_concentration_below_acceptable_tier" %in% gate_ess_concentration_fail$reasons)

# =============================================================================
# lmv2_ebal_ess_concentration_gate() unit fixtures: preferred/acceptable/fail
# tiers, both on ESS ratio and on max single-unit share, plus the empty-input
# edge case. Hand-computable per_cohort inputs; not the terminal gate above.
# =============================================================================
ratio_thresholds <- list(preferred = 1.0, acceptable = 0.5)
share_thresholds <- list(preferred = 0.20, acceptable = 0.35)

mk_ess_cohort <- function(g, ess, n_treated, max_share) {
  list(ess = ess, n_treated = n_treated, concentration = list(max_share = max_share))
}

ess_preferred <- list(`1` = mk_ess_cohort(1L, ess = 10, n_treated = 10, max_share = 0.10))
gate_ess_preferred <- lmv2_ebal_ess_concentration_gate(ess_preferred, ratio_thresholds, share_thresholds)
add_check("ess_concentration_gate_preferred_tier", gate_ess_preferred$tier, "preferred",
          identical(gate_ess_preferred$tier, "preferred") && gate_ess_preferred$pass)

ess_acceptable <- list(`1` = mk_ess_cohort(1L, ess = 6, n_treated = 10, max_share = 0.30))
gate_ess_acceptable <- lmv2_ebal_ess_concentration_gate(ess_acceptable, ratio_thresholds, share_thresholds)
add_check("ess_concentration_gate_acceptable_tier", gate_ess_acceptable$tier, "acceptable",
          identical(gate_ess_acceptable$tier, "acceptable") && gate_ess_acceptable$pass)

ess_fail_ratio <- list(`1` = mk_ess_cohort(1L, ess = 3, n_treated = 10, max_share = 0.10))
gate_ess_fail_ratio <- lmv2_ebal_ess_concentration_gate(ess_fail_ratio, ratio_thresholds, share_thresholds)
add_check("ess_concentration_gate_fails_on_low_ess_ratio", gate_ess_fail_ratio$tier,
          "failed_ess_concentration",
          identical(gate_ess_fail_ratio$tier, "failed_ess_concentration") && !gate_ess_fail_ratio$pass)

ess_fail_share <- list(`1` = mk_ess_cohort(1L, ess = 10, n_treated = 10, max_share = 0.50))
gate_ess_fail_share <- lmv2_ebal_ess_concentration_gate(ess_fail_share, ratio_thresholds, share_thresholds)
add_check("ess_concentration_gate_fails_on_high_max_share", gate_ess_fail_share$tier,
          "failed_ess_concentration",
          identical(gate_ess_fail_share$tier, "failed_ess_concentration") && !gate_ess_fail_share$pass)

ess_multi_cohort_worst_wins <- list(`1` = mk_ess_cohort(1L, ess = 10, n_treated = 10, max_share = 0.10),
                                    `2` = mk_ess_cohort(2L, ess = 3, n_treated = 10, max_share = 0.10))
gate_ess_multi <- lmv2_ebal_ess_concentration_gate(ess_multi_cohort_worst_wins, ratio_thresholds, share_thresholds)
add_check("ess_concentration_gate_one_bad_cohort_fails_whole_gate", gate_ess_multi$tier,
          "failed_ess_concentration",
          identical(gate_ess_multi$tier, "failed_ess_concentration") && !gate_ess_multi$pass)

gate_ess_empty <- lmv2_ebal_ess_concentration_gate(list(), ratio_thresholds, share_thresholds)
add_check("ess_concentration_gate_empty_per_cohort_fails", gate_ess_empty$pass, FALSE,
          !gate_ess_empty$pass)

# =============================================================================
# End-to-end database-free fixture: firm edges -> firm union -> inventor
# edges -> supported treated inventors -> Stage-1 EB -> base-weight
# allocation -> primary Stage-2 EB -> equal-deal Stage-2 EB -> retention ->
# firm reaggregation -> terminal design gate. Calls the exact pipeline
# functions 17h/17i call (lmv2_ebal_stage1_pipeline, lmv2_ebal_stage2_pipeline,
# lmv2_ebal_terminal_gate), never a parallel reimplementation.
#
# Golden path: cohort 1, two deals (deal 1: 2 treated inventors, deal 2: 2
# treated inventors), three candidate firms (10, 20 both admissible for
# deal 1's caliper radius but only firm 20 for deal 1 specifically, firm 40
# admissible for both deals), one candidate firm (30) admissible by the
# FIRM caliper but with zero Stage-2 edges (must be pre-filtered out).
# =============================================================================
build_e2e_inputs <- function() {
  firm_edges <- data.frame(
    cohort = 1L, deal_id = c(1L, 2L, 1L, 2L, 1L, 2L),
    control_group = c(10, 10, 20, 30, 40, 40),
    distance = c(0.3, 0.35, 0.4, 0.5, 0.45, 0.5)
  )
  stage2_candidate_edges <- data.frame(
    cohort = 1L,
    deal_id = c(1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L, 2L, 2L, 2L),
    treated_codinv = c(1001, 1002, 1001, 1002, 1001, 1002,
                       2001, 2001, 2002, 2002, 2002),
    control_codinv = c(101, 101, 201, 201, 401, 402,
                       101, 401, 101, 401, 402),
    control_group = c(10, 10, 20, 20, 40, 40,
                      10, 40, 10, 40, 40),
    distance = c(0.3, 0.35, 0.4, 0.45, 0.3, 0.5,
                0.5, 0.4, 0.6, 0.5, 0.55)
  )
  treated_firm_covars <- data.frame(
    cohort = c(1L, 1L), deal_id = c(1L, 2L),
    log_patent_stock_5y = c(2, 4), log_inventor_count_5y = c(1, 1), patent_trajectory = c(0, 0)
  )
  control_firm_covars <- data.frame(
    cohort = c(1L, 1L, 1L), control_group = c(10, 20, 40),
    log_patent_stock_5y = c(1, 5, 3), log_inventor_count_5y = c(1, 1, 1), patent_trajectory = c(0, 0, 0)
  )
  treated_spine <- data.frame(
    cohort = 1L, deal_id = c(1L, 1L, 2L, 2L), treated_codinv = c(1001, 1002, 2001, 2002)
  )
  treated_inv_covars <- data.frame(
    cohort = 1L, deal_id = c(1L, 1L, 2L, 2L), treated_codinv = c(1001, 1002, 2001, 2002),
    log_patent_count_5y = 1.5, patent_trajectory = 0, career_age = 5,
    focal_group_tenure = 2, focal_group_exclusivity = 0.5
  )
  control_inv_covars <- data.frame(
    cohort = 1L, control_codinv = c(101, 201, 401, 402), control_group = c(10, 20, 40, 40),
    log_patent_count_5y = c(1, 1, 1, 3), patent_trajectory = 0, career_age = 5,
    focal_group_tenure = 2, focal_group_exclusivity = 0.5
  )
  list(firm_edges = firm_edges, stage2_candidate_edges = stage2_candidate_edges,
      treated_firm_covars = treated_firm_covars, control_firm_covars = control_firm_covars,
      treated_spine = treated_spine, treated_inv_covars = treated_inv_covars,
      control_inv_covars = control_inv_covars)
}

run_e2e <- function(inputs, stage1_caliper = 1.0, stage2_caliper = 1.0, cohorts = 1L) {
  stage1_result <- lmv2_ebal_stage1_pipeline(
    firm_edges = inputs$firm_edges, stage2_candidate_edges = inputs$stage2_candidate_edges,
    stage1_caliper = stage1_caliper, stage2_caliper = stage2_caliper,
    treated_firm_covars = inputs$treated_firm_covars, control_firm_covars = inputs$control_firm_covars,
    cohorts = cohorts
  )
  run_scheme <- function(scheme) {
    lmv2_ebal_stage2_pipeline(
      stage1_result = stage1_result, stage2_candidate_edges = inputs$stage2_candidate_edges,
      stage2_caliper = stage2_caliper, treated_spine = inputs$treated_spine,
      treated_inv_covars = inputs$treated_inv_covars, treated_firm_covars = inputs$treated_firm_covars,
      control_inv_covars = inputs$control_inv_covars, control_firm_covars = inputs$control_firm_covars,
      deal_category = NULL, treated_weighting = scheme, cohorts = cohorts
    )
  }
  primary <- run_scheme("primary")
  equal_deal <- run_scheme("equal_deal")
  list(stage1_result = stage1_result, primary = primary, equal_deal = equal_deal,
      gate_primary = lmv2_ebal_terminal_gate(primary, cohorts),
      gate_equal_deal = lmv2_ebal_terminal_gate(equal_deal, cohorts))
}

e2e_inputs <- build_e2e_inputs()
e2e <- run_e2e(e2e_inputs)

add_check("e2e_golden_path_stage1_excludes_firm30_zero_eligible",
          paste(e2e$stage1_result$excluded_firms$control_group, collapse = ","), "30",
          identical(e2e$stage1_result$excluded_firms$control_group, 30))
add_check("e2e_golden_path_stage1_all_cohorts_pass", e2e$stage1_result$all_cohorts_pass, TRUE,
          isTRUE(e2e$stage1_result$all_cohorts_pass))
add_check("e2e_golden_path_full_retention",
          sprintf("%.4f,%.4f", e2e$primary$retention$overall$inventor_retention,
                 e2e$equal_deal$retention$overall$inventor_retention),
          "1.0000,1.0000",
          abs(e2e$primary$retention$overall$inventor_retention - 1) < 1e-9 &&
            abs(e2e$equal_deal$retention$overall$inventor_retention - 1) < 1e-9)
# The golden-path pool is intentionally tiny (4 Stage-2 controls) so it can
# be hand-verified; the pre-E2 amendment's max_share thresholds are derived
# from real, thousands-of-unit pools and a single control legitimately
# holding 30% of a 4-control pool is expected, not a defect. This asserts
# the golden path is clean on every OTHER terminal-gate condition and fails
# ONLY on the newly-activated ESS/concentration reason -- proving the gate
# is genuinely wired into both schemes rather than silently bypassed.
add_check("e2e_golden_path_terminal_gate_clean_except_ess_concentration",
          paste(setdiff(e2e$gate_primary$reasons, "stage2_ess_concentration_below_acceptable_tier"),
               collapse = ","),
          "",
          identical(setdiff(e2e$gate_primary$reasons, "stage2_ess_concentration_below_acceptable_tier"),
                    character(0)) &&
            identical(setdiff(e2e$gate_equal_deal$reasons, "stage2_ess_concentration_below_acceptable_tier"),
                      character(0)))
add_check("e2e_golden_path_ess_concentration_fails_on_max_share_not_ratio",
          paste(round(e2e$primary$ess_concentration_gate$detail$ess_ratio, 4) >= 0.5,
               round(e2e$primary$ess_concentration_gate$detail$max_share, 4) > 0.35),
          "TRUE TRUE",
          isTRUE(e2e$primary$ess_concentration_gate$detail$ess_ratio >=
                   LMV2_P4_EBAL$stage_2$ess_ratio$acceptable) &&
            isTRUE(e2e$primary$ess_concentration_gate$detail$max_share >
                     LMV2_P4_EBAL$stage_2$max_share$acceptable))
add_check("e2e_golden_path_stage1_ess_concentration_passes",
          e2e$stage1_result$ess_concentration_gate$pass, TRUE,
          isTRUE(e2e$stage1_result$ess_concentration_gate$pass))
add_check("e2e_golden_path_base_weight_allocation_split_firm40",
          sprintf("%.4f", e2e$primary$base_weights$base_weight[e2e$primary$base_weights$control_codinv == 401] /
                    e2e$primary$base_weights$base_weight[e2e$primary$base_weights$control_codinv == 402]),
          "1.0000",
          abs(e2e$primary$base_weights$base_weight[e2e$primary$base_weights$control_codinv == 401] -
                e2e$primary$base_weights$base_weight[e2e$primary$base_weights$control_codinv == 402]) < 1e-9)

# --- Treated weights are persisted (not just computed and discarded): one
# row per supported treated inventor, primary weights all 1, equal-deal
# weights sum to 1 within every retained deal.
add_check("e2e_treated_weights_one_row_per_supported_treated_inventor",
          paste(nrow(e2e$primary$treated_weights), nrow(e2e$primary$supported_treated),
               nrow(e2e$equal_deal$treated_weights), nrow(e2e$equal_deal$supported_treated), sep = ","),
          "4,4,4,4",
          nrow(e2e$primary$treated_weights) == nrow(e2e$primary$supported_treated) &&
            nrow(e2e$equal_deal$treated_weights) == nrow(e2e$equal_deal$supported_treated))
add_check("e2e_treated_weights_primary_all_equal_one",
          paste(unique(e2e$primary$treated_weights$weight), collapse = ","), "1",
          all(e2e$primary$treated_weights$weight == 1))
equal_deal_deal_sums <- tapply(e2e$equal_deal$treated_weights$weight,
                               e2e$equal_deal$treated_weights$deal_id, sum)
add_check("e2e_treated_weights_equal_deal_sums_to_one_per_deal",
          paste(as.numeric(equal_deal_deal_sums), collapse = ","), "1,1",
          isTRUE(all.equal(as.numeric(equal_deal_deal_sums), rep(1, length(equal_deal_deal_sums)))))

# --- Mutation 1: a deal-level edge is accidentally discarded before support
# construction (simulate the pre-fix regression: collapse firm_edges to a
# unique-firm table BEFORE building stage2_candidate_edges, exactly as the
# original bug did) -- the resulting Stage-2 edges lose per-deal admissibility
# and the pipeline's pair construction step (17h/17i, not this pure pipeline)
# would silently pass every deal's inventors against every candidate firm.
# Certified here at the interface level: admissible_firm_edges must retain
# deal_id, and collapsing it away (as `unique(firm_edges[c("cohort",
# "control_group")])`) measurably loses information the unique firm pool
# needs to reconstruct per-deal admissibility.
collapsed_wrongly <- unique(e2e_inputs$firm_edges[c("cohort", "control_group")])
add_check("e2e_mutation_deal_level_edge_collapse_loses_deal_id",
          "deal_id" %in% names(collapsed_wrongly), FALSE,
          !("deal_id" %in% names(collapsed_wrongly)))
add_check("e2e_admissible_firm_edges_retains_deal_id_by_contrast",
          "deal_id" %in% names(e2e$stage1_result$admissible_firm_edges), TRUE,
          "deal_id" %in% names(e2e$stage1_result$admissible_firm_edges))

# --- Mutation 1b: reproduce the second-review regression directly -- a
# cohort-wide cross join (every treated inventor x every positive-weight
# firm, ignoring deal_id) produces MORE pairs than the correct deal-
# specific join, and specifically produces pairs that never should have
# existed (e.g. firm 20, admissible only for deal 1, illegitimately
# supplying deal 2). The correct join must never do this.
frozen_e2e <- e2e$stage1_result$weights[e2e$stage1_result$weights$weight > 0, ]
donor_firms_e2e <- unique(e2e_inputs$stage2_candidate_edges[c("cohort", "control_codinv", "control_group")])
correct_pairs <- lmv2_ebal_build_stage2_candidate_pairs(
  e2e$stage1_result$admissible_firm_edges[
    e2e$stage1_result$admissible_firm_edges$control_group %in% frozen_e2e$control_group, ],
  donor_firms_e2e, e2e_inputs$treated_spine)
buggy_cross_join <- merge(unique(frozen_e2e["control_group"]),
                          donor_firms_e2e[c("cohort", "control_codinv", "control_group")],
                          by = "control_group")
buggy_cross_join <- merge(e2e_inputs$treated_spine, buggy_cross_join, by = "cohort")
add_check("e2e_mutation_buggy_cross_join_produces_illegitimate_cross_deal_pairs",
          paste(nrow(correct_pairs), nrow(buggy_cross_join),
               any(correct_pairs$deal_id == 2L & correct_pairs$control_group == 20), sep = ","),
          "expected: correct < buggy, firm20 never in deal2 under correct join",
          nrow(correct_pairs) < nrow(buggy_cross_join) &&
            !any(correct_pairs$deal_id == 2L & correct_pairs$control_group == 20) &&
            any(buggy_cross_join$deal_id == 2L & buggy_cross_join$control_group == 20))

# --- Mutation 2: an unsupported treated inventor must never enter Stage 2.
# Drop all of 2002's Stage-2 edges.
inputs_unsupported <- e2e_inputs
inputs_unsupported$stage2_candidate_edges <- inputs_unsupported$stage2_candidate_edges[
  inputs_unsupported$stage2_candidate_edges$treated_codinv != 2002, , drop = FALSE]
e2e_unsupported <- run_e2e(inputs_unsupported)
add_check("e2e_mutation_unsupported_treated_inventor_excluded_from_stage2",
          2002 %in% e2e_unsupported$primary$per_cohort[["1"]]$roster_control_ids$control_codinv,
          FALSE,
          !(2002 %in% e2e_unsupported$primary$supported_treated$treated_codinv))
add_check("e2e_mutation_unsupported_treated_inventor_lowers_retention",
          sprintf("%.4f", e2e_unsupported$primary$retention$overall$inventor_retention),
          sprintf("%.4f", 0.75),
          abs(e2e_unsupported$primary$retention$overall$inventor_retention - 0.75) < 1e-9)
add_check("e2e_mutation_unsupported_treated_inventor_logged_with_reason",
          e2e_unsupported$primary$excluded_treated$reason, "no_admissible_control_inventor",
          identical(e2e_unsupported$primary$excluded_treated$treated_codinv, 2002) &&
            identical(e2e_unsupported$primary$excluded_treated$reason, "no_admissible_control_inventor"))

# --- Mutation 3: retention must count treated inventors, not control rows
# (already directly certified above by
# retention_summary_inventor_retention_is_treated_inventor_count_not_control_rows;
# here confirmed again in the full pipeline context: the golden path has 4
# treated inventors but a different number of control rows, yet retention
# reads exactly 1.0, not some control-row-count-derived fraction).
add_check("e2e_retention_denominator_is_treated_inventor_count",
          e2e$primary$retention$overall$n_eligible_inventors, 4L,
          identical(e2e$primary$retention$overall$n_eligible_inventors, 4L))

# --- Mutation 4: a cohort missing from final output must fail the terminal
# gate (simulate by asking for cohorts = c(1L, 2L) when only cohort 1 has
# any data at all -- cohort 2 will hit the empty-cell path, which is not
# "pass", and 2 is not the same set as 1 for the missing-cohort check
# either way).
e2e_missing_cohort <- run_e2e(e2e_inputs, cohorts = c(1L, 2L))
add_check("e2e_mutation_missing_cohort_fails_terminal_gate",
          paste(e2e_missing_cohort$gate_primary$pass,
               "cohort_inventor_balance_failed" %in% e2e_missing_cohort$gate_primary$reasons,
               sep = ","),
          "FALSE,TRUE",
          !e2e_missing_cohort$gate_primary$pass &&
            "cohort_inventor_balance_failed" %in% e2e_missing_cohort$gate_primary$reasons)

# --- Mutation 5: equal-deal treated weights must not be reset to one.
add_check("e2e_mutation_equal_deal_weights_not_reset_to_one",
          any(e2e$equal_deal$per_cohort[["1"]]$treated_weight != 1),
          TRUE,
          any(abs(e2e$equal_deal$per_cohort[["1"]]$treated_weight - 1) > 1e-9))

# --- Mutation 6: Stage-2 configuration differing from the Stage-1 freeze
# must be caught (pure check already certified above via
# verify_stage2_matches_freeze_*; confirmed again using this fixture's own
# freeze-shaped output).
e2e_freeze <- data.frame(stage2_caliper = 1.0, technology_resolution = "ipc4")
add_check("e2e_mutation_stage2_config_mismatch_detected",
          lmv2_ebal_verify_stage2_matches_freeze(e2e_freeze, 1.5, "ipc4")$ok, FALSE,
          !lmv2_ebal_verify_stage2_matches_freeze(e2e_freeze, 1.5, "ipc4")$ok)

# --- Mutation 7: a missing firm target or scaler must fail the terminal
# gate through the firm-reaggregation gate (drop the persisted scaler row
# for log_patent_stock_5y entirely).
stage1_result_missing_scaler <- e2e$stage1_result
stage1_result_missing_scaler$scalers <- stage1_result_missing_scaler$scalers[
  stage1_result_missing_scaler$scalers$variable != "log_patent_stock_5y", , drop = FALSE]
primary_missing_scaler <- lmv2_ebal_stage2_pipeline(
  stage1_result = stage1_result_missing_scaler, stage2_candidate_edges = e2e_inputs$stage2_candidate_edges,
  stage2_caliper = 1.0, treated_spine = e2e_inputs$treated_spine,
  treated_inv_covars = e2e_inputs$treated_inv_covars, treated_firm_covars = e2e_inputs$treated_firm_covars,
  control_inv_covars = e2e_inputs$control_inv_covars, control_firm_covars = e2e_inputs$control_firm_covars,
  deal_category = NULL, treated_weighting = "primary", cohorts = 1L
)
gate_missing_scaler_e2e <- lmv2_ebal_terminal_gate(primary_missing_scaler, 1L)
add_check("e2e_mutation_missing_firm_scaler_fails_terminal_gate",
          paste(gate_missing_scaler_e2e$pass, "firm_reaggregation_failed" %in% gate_missing_scaler_e2e$reasons,
               sep = ","),
          "FALSE,TRUE",
          !gate_missing_scaler_e2e$pass && "firm_reaggregation_failed" %in% gate_missing_scaler_e2e$reasons)

# =============================================================================
# Report
# =============================================================================
checks_df <- do.call(rbind, checks)
checks_df$p4_ebal_version <- LMV2_P4_EBAL_VERSION
checks_df$p4_ebal_config_hash <- LMV2_P4_EBAL_CONFIG_HASH
checks_df <- checks_df[c("p4_ebal_version", "p4_ebal_config_hash", "check", "observed",
                         "expected", "pass")]
lmv2_ebal_write_csv(checks_df, audit_dir, "p4_ebal_acceptance_checks.csv")

status <- data.frame(
  p4_ebal_version = LMV2_P4_EBAL_VERSION, p4_ebal_config_hash = LMV2_P4_EBAL_CONFIG_HASH,
  checks = nrow(checks_df), failures = sum(!checks_df$pass), pass = all(checks_df$pass),
  stringsAsFactors = FALSE
)
lmv2_ebal_write_csv(status, audit_dir, "p4_ebal_package_status.csv")
print(status)
if (!status$pass) stop("P4-EB certification failed; inspect p4_ebal_acceptance_checks.csv")
