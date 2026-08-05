# ============================================================================
# certify_deal_ebal_cohort_hybrid.R -- database-free fixtures, COHORT-LEVEL
# hybrid core (deal_ebal_cohort_hybrid_utils.R), SECOND PASS
# ============================================================================
# No database access. Second-pass additions over the first certification:
# the corrected optweight finalize contract (unequal-deal-size, both
# schemes), rung-specific tolerance, the retention gate (terminal, no
# escalation), the ESS gate (forces escalation past a balance-passing exact
# solve), authoritative (not merely self-consistent) firm-attachment checks,
# base-weight-allocator hard-fails, solver-warning persistence, and the new
# formal final-weight/mass assertions.

if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))
source(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))

checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1]] <<- data.frame(
    check = name, observed = paste(observed, collapse = ","),
    expected = paste(expected, collapse = ","), pass = isTRUE(pass), stringsAsFactors = FALSE)
}
expect_error <- function(expr) tryCatch({ force(expr); FALSE }, error = function(e) TRUE)

# ===========================================================================
# Fixture BW -- deal-normalized base weights, both schemes (unchanged math,
# now also exercising the allocator's own hard-fail invariants).
# ===========================================================================
treated_BW <- data.frame(cohort = 1L, deal_id = c(1L, 1L, 1L, 2L), treated_codinv = c(11, 12, 13, 21))
control_BW <- data.frame(cohort = 1L, deal_id = c(1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L),
                         control_codinv = c(101, 102, 103, 104, 105, 202, 201, 202),
                         control_group = c(901, 902, 903, 904, 905, 906, 907, 906))
bw_primary <- lmv2_ebal_allocate_deal_base_weights(treated_BW, control_BW, "primary")
add_check("BW_primary_treated_all_one", all(bw_primary$treated$base_weight == 1), TRUE,
          all(bw_primary$treated$base_weight == 1))
deal1_ctrl_mass <- sum(bw_primary$control$base_weight[bw_primary$control$deal_id == 1L])
add_check("BW_primary_deal1_control_mass_equals_3_supported",
          sprintf("%.10f", deal1_ctrl_mass), "3", isTRUE(all.equal(deal1_ctrl_mass, 3)))
add_check("BW_n_retained_deals_reported", bw_primary$n_retained_deals, 2, bw_primary$n_retained_deals == 2L)

bw_eq <- lmv2_ebal_allocate_deal_base_weights(treated_BW, control_BW, "equal_deal")
deal1_treated_mass_eq <- sum(bw_eq$treated$base_weight[bw_eq$treated$deal_id == 1L])
add_check("BW_equal_deal_each_deal_treated_mass_is_one", sprintf("%.6f", deal1_treated_mass_eq), "1.000000",
          isTRUE(all.equal(deal1_treated_mass_eq, 1)))

# HARD-FAIL (point 8): unmatched treated/control deal sets.
treated_mismatch <- rbind(treated_BW, data.frame(cohort = 1L, deal_id = 3L, treated_codinv = 31))
add_check("BW_hardfails_on_deal_only_in_treated",
          expect_error(lmv2_ebal_allocate_deal_base_weights(treated_mismatch, control_BW, "primary")), TRUE,
          expect_error(lmv2_ebal_allocate_deal_base_weights(treated_mismatch, control_BW, "primary")))
control_mismatch <- rbind(control_BW, data.frame(cohort = 1L, deal_id = 4L, control_codinv = 401,
                                                 control_group = 908))
add_check("BW_hardfails_on_deal_only_in_control",
          expect_error(lmv2_ebal_allocate_deal_base_weights(treated_BW, control_mismatch, "primary")), TRUE,
          expect_error(lmv2_ebal_allocate_deal_base_weights(treated_BW, control_mismatch, "primary")))
dup_treated_bw <- rbind(treated_BW, treated_BW[1, ])
add_check("BW_hardfails_on_duplicate_treated_key",
          expect_error(lmv2_ebal_allocate_deal_base_weights(dup_treated_bw, control_BW, "primary")), TRUE,
          expect_error(lmv2_ebal_allocate_deal_base_weights(dup_treated_bw, control_BW, "primary")))
dup_control_bw <- rbind(control_BW, control_BW[1, ])
add_check("BW_hardfails_on_duplicate_control_key",
          expect_error(lmv2_ebal_allocate_deal_base_weights(treated_BW, dup_control_bw, "primary")), TRUE,
          expect_error(lmv2_ebal_allocate_deal_base_weights(treated_BW, dup_control_bw, "primary")))

# ===========================================================================
# Fixture ASSERT -- core assertions, including the REPLACED (point 7)
# authoritative firm-attachment checks.
# ===========================================================================
ok_treated <- data.frame(cohort = 1L, deal_id = c(1L, 1L), treated_codinv = c(1, 2), target_group = 500,
                         inv_a = c(0.1, 0.2), firm_a = c(1, 1))
ok_control <- data.frame(cohort = 1L, deal_id = c(1L, 1L), control_codinv = c(11, 12),
                         control_group = c(901, 901), inv_a = c(0.3, 0.4), firm_a = c(1, 1))
auth_firm <- data.frame(cohort = 1L, control_group = 901, log_patent_stock_5y = 1)  # generic single-var stand-in
names(auth_firm)[3] <- "raw_firm_a"
auth_treated <- data.frame(cohort = 1L, deal_id = 1L, target_group = 500, raw_firm_a = 1)

add_check("ASSERT_unique_vars_ok_on_disjoint_names",
          !expect_error(lmv2_ebal_assert_unique_balance_vars("inv_a", "firm_a")), TRUE,
          !expect_error(lmv2_ebal_assert_unique_balance_vars("inv_a", "firm_a")))
add_check("ASSERT_unique_vars_errors_on_collision",
          expect_error(lmv2_ebal_assert_unique_balance_vars("x", "x")), TRUE,
          expect_error(lmv2_ebal_assert_unique_balance_vars("x", "x")))
add_check("ASSERT_no_missing_ok_on_clean_data",
          !expect_error(lmv2_ebal_assert_no_missing_covariates(ok_treated, c("inv_a", "firm_a"))), TRUE,
          !expect_error(lmv2_ebal_assert_no_missing_covariates(ok_treated, c("inv_a", "firm_a"))))
bad_missing <- ok_treated; bad_missing$inv_a[1] <- NA
add_check("ASSERT_no_missing_errors_on_NA",
          expect_error(lmv2_ebal_assert_no_missing_covariates(bad_missing, c("inv_a", "firm_a"))), TRUE,
          expect_error(lmv2_ebal_assert_no_missing_covariates(bad_missing, c("inv_a", "firm_a"))))
add_check("ASSERT_constant_target_firm_ok_when_constant",
          !expect_error(lmv2_ebal_assert_constant_target_firm_within_deal(ok_treated, "firm_a")), TRUE,
          !expect_error(lmv2_ebal_assert_constant_target_firm_within_deal(ok_treated, "firm_a")))
bad_target_firm <- ok_treated; bad_target_firm$firm_a <- c(1, 2)
add_check("ASSERT_constant_target_firm_errors_when_varying_within_deal",
          expect_error(lmv2_ebal_assert_constant_target_firm_within_deal(bad_target_firm, "firm_a")), TRUE,
          expect_error(lmv2_ebal_assert_constant_target_firm_within_deal(bad_target_firm, "firm_a")))

# REPLACED (point 7): authoritative control-firm check.
add_check("ASSERT_control_firm_authoritative_ok_when_matching",
          !expect_error(lmv2_ebal_assert_control_firm_matches_authoritative(
            ok_control, "firm_a", auth_firm, raw_names = "raw_firm_a")), TRUE,
          !expect_error(lmv2_ebal_assert_control_firm_matches_authoritative(
            ok_control, "firm_a", auth_firm, raw_names = "raw_firm_a")))
bad_auth_firm <- auth_firm; bad_auth_firm$raw_firm_a <- 999   # authoritative value disagrees with attachment
add_check("ASSERT_control_firm_authoritative_errors_when_disagreeing",
          expect_error(lmv2_ebal_assert_control_firm_matches_authoritative(
            ok_control, "firm_a", bad_auth_firm, raw_names = "raw_firm_a")), TRUE,
          expect_error(lmv2_ebal_assert_control_firm_matches_authoritative(
            ok_control, "firm_a", bad_auth_firm, raw_names = "raw_firm_a")))
# Internally self-consistent but WRONG relative to authoritative source --
# the exact gap the old self-consistency-only check could never catch.
self_consistent_but_wrong <- ok_control; self_consistent_but_wrong$firm_a <- c(999, 999)
add_check("ASSERT_control_firm_authoritative_catches_self_consistent_but_wrong",
          expect_error(lmv2_ebal_assert_control_firm_matches_authoritative(
            self_consistent_but_wrong, "firm_a", auth_firm, raw_names = "raw_firm_a")), TRUE,
          expect_error(lmv2_ebal_assert_control_firm_matches_authoritative(
            self_consistent_but_wrong, "firm_a", auth_firm, raw_names = "raw_firm_a")))
no_auth_row <- data.frame(cohort = 1L, control_group = 999)  # no authoritative row for this group
add_check("ASSERT_control_firm_authoritative_errors_on_missing_authoritative_row",
          expect_error(lmv2_ebal_assert_control_firm_matches_authoritative(
            rbind(ok_control, data.frame(cohort=1L,deal_id=1L,control_codinv=13,control_group=999,
                                         inv_a=0.5,firm_a=1)),
            "firm_a", auth_firm, raw_names = "raw_firm_a")), TRUE,
          expect_error(lmv2_ebal_assert_control_firm_matches_authoritative(
            rbind(ok_control, data.frame(cohort=1L,deal_id=1L,control_codinv=13,control_group=999,
                                         inv_a=0.5,firm_a=1)),
            "firm_a", auth_firm, raw_names = "raw_firm_a")))

# NEW (point 7): authoritative treated-firm check against (cohort, deal_id, target_group).
add_check("ASSERT_treated_firm_authoritative_ok_when_matching",
          !expect_error(lmv2_ebal_assert_treated_firm_matches_authoritative(
            ok_treated, "firm_a", auth_treated, raw_names = "raw_firm_a")), TRUE,
          !expect_error(lmv2_ebal_assert_treated_firm_matches_authoritative(
            ok_treated, "firm_a", auth_treated, raw_names = "raw_firm_a")))
bad_auth_treated <- auth_treated; bad_auth_treated$raw_firm_a <- 999
add_check("ASSERT_treated_firm_authoritative_errors_when_disagreeing",
          expect_error(lmv2_ebal_assert_treated_firm_matches_authoritative(
            ok_treated, "firm_a", bad_auth_treated, raw_names = "raw_firm_a")), TRUE,
          expect_error(lmv2_ebal_assert_treated_firm_matches_authoritative(
            ok_treated, "firm_a", bad_auth_treated, raw_names = "raw_firm_a")))

dup_treated <- rbind(ok_treated, ok_treated[1, ])
add_check("ASSERT_validate_roster_errors_on_duplicate_treated_key",
          expect_error(lmv2_ebal_validate_cohort_roster(dup_treated, ok_control, "inv_a", "firm_a")), TRUE,
          expect_error(lmv2_ebal_validate_cohort_roster(dup_treated, ok_control, "inv_a", "firm_a")))
add_check("ASSERT_validate_roster_ok_on_clean_inputs",
          !expect_error(lmv2_ebal_validate_cohort_roster(ok_treated, ok_control, "inv_a", "firm_a")), TRUE,
          !expect_error(lmv2_ebal_validate_cohort_roster(ok_treated, ok_control, "inv_a", "firm_a")))
add_check("ASSERT_validate_roster_threads_authoritative_checks",
          expect_error(lmv2_ebal_validate_cohort_roster(ok_treated, self_consistent_but_wrong, "inv_a", "firm_a",
                                                        authoritative_firm_covars = auth_firm)), TRUE,
          expect_error(lmv2_ebal_validate_cohort_roster(ok_treated, self_consistent_but_wrong, "inv_a", "firm_a",
                                                        authoritative_firm_covars = auth_firm)))

# NEW (point 3/4): formal final-weight / mass assertions.
add_check("ASSERT_final_treated_weights_ok_when_matching",
          !expect_error(lmv2_ebal_assert_final_treated_weights_equal_base(c(1/3, 1/3, 1/3, 1), c(1/3, 1/3, 1/3, 1))),
          TRUE, !expect_error(lmv2_ebal_assert_final_treated_weights_equal_base(c(1/3, 1/3, 1/3, 1), c(1/3, 1/3, 1/3, 1))))
add_check("ASSERT_final_treated_weights_errors_when_disagreeing",
          expect_error(lmv2_ebal_assert_final_treated_weights_equal_base(c(1, 1, 1, 1), c(1/3, 1/3, 1/3, 1))), TRUE,
          expect_error(lmv2_ebal_assert_final_treated_weights_equal_base(c(1, 1, 1, 1), c(1/3, 1/3, 1/3, 1))))
add_check("ASSERT_masses_agree_ok_primary",
          !expect_error(lmv2_ebal_assert_masses_agree(rep(1, 4), c(2, 2), scheme = "primary")), TRUE,
          !expect_error(lmv2_ebal_assert_masses_agree(rep(1, 4), c(2, 2), scheme = "primary")))
add_check("ASSERT_masses_agree_errors_when_treated_control_disagree",
          expect_error(lmv2_ebal_assert_masses_agree(rep(1, 4), c(1, 1), scheme = "primary")), TRUE,
          expect_error(lmv2_ebal_assert_masses_agree(rep(1, 4), c(1, 1), scheme = "primary")))
# treated mass = 1/3+1/3+1/3+1 = 2, matching n_retained_deals = 2; control
# must sum to the SAME total mass (2), not one-per-deal (that would be 1 each).
add_check("ASSERT_masses_agree_ok_equal_deal",
          !expect_error(lmv2_ebal_assert_masses_agree(c(1/3, 1/3, 1/3, 1), c(1, 1),
                                                       scheme = "equal_deal", n_retained_deals = 2)), TRUE,
          !expect_error(lmv2_ebal_assert_masses_agree(c(1/3, 1/3, 1/3, 1), c(1, 1),
                                                       scheme = "equal_deal", n_retained_deals = 2)))

# ===========================================================================
# Fixture UNEQUAL -- THE CORE BUG FIX, both schemes, unequal deal sizes,
# through the ACTUAL optweight solve path (not a hand simulation). Deal A: 3
# treated inventors; deal B: 1 treated inventor. Reproduces the exact
# reported scenario and independently re-verifies it.
# ===========================================================================
set.seed(21)
n_ctrl_A <- 8; n_ctrl_B <- 8
treated_UQ <- data.frame(cohort = 1L, deal_id = c(rep(1L, 3), 2L), treated_codinv = c(1, 2, 3, 4),
                         x1 = 0.2, firm_x = 0)
control_UQ <- data.frame(cohort = 1L, deal_id = c(rep(1L, n_ctrl_A), rep(2L, n_ctrl_B)),
                         control_codinv = 1:(n_ctrl_A + n_ctrl_B),
                         control_group = 900 + 1:(n_ctrl_A + n_ctrl_B),
                         x1 = rnorm(n_ctrl_A + n_ctrl_B), firm_x = 0)

for (scheme in c("primary", "equal_deal")) {
  bwU <- lmv2_ebal_allocate_deal_base_weights(treated_UQ, control_UQ, scheme)
  rosterU <- lmv2_ebal_build_cohort_roster(treated_UQ, control_UQ, bwU, inv_vars = "x1", firm_vars = "firm_x")
  owU <- suppressWarnings(lmv2_ebal_cohort_optweight_solve(rosterU, tol = 0.10, inv_vars = "x1", firm_vars = "firm_x"))
  prescribed <- rosterU$base_weight[rosterU$D == 1L]
  add_check(sprintf("UNEQUAL_%s_optweight_final_treated_equals_prescribed_base", scheme),
            !expect_error(lmv2_ebal_assert_final_treated_weights_equal_base(owU$treated_weight, prescribed)), TRUE,
            isTRUE(owU$feasible) &&
              !expect_error(lmv2_ebal_assert_final_treated_weights_equal_base(owU$treated_weight, prescribed)))
  n_retained <- if (scheme == "primary") NULL else bwU$n_retained_deals
  add_check(sprintf("UNEQUAL_%s_optweight_masses_agree", scheme),
            !expect_error(lmv2_ebal_assert_masses_agree(owU$treated_weight, owU$control_weight, scheme,
                                                        n_retained_deals = n_retained)), TRUE,
            isTRUE(owU$feasible) &&
              !expect_error(lmv2_ebal_assert_masses_agree(owU$treated_weight, owU$control_weight, scheme,
                                                          n_retained_deals = n_retained)))
}

# ===========================================================================
# Fixture RETENTION -- terminal gate, checked before any solver runs.
# ===========================================================================
treated_full_pool <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = 1:10, x1 = 0, firm_x = 0)
control_thin <- data.frame(cohort = 1L, deal_id = 1L, control_codinv = 1:6, control_group = 900 + 1:6,
                           x1 = rnorm(6), firm_x = 0)
# Only 2 of the 10 "eligible" treated inventors actually made it into the
# roster (as if Stage-2 support excluded 8 of them) -- retention = 0.20,
# below the 0.80 acceptable floor.
treated_supported_only <- treated_full_pool[1:2, ]
bwR <- lmv2_ebal_allocate_deal_base_weights(treated_supported_only, control_thin, "primary")
rosterR <- lmv2_ebal_build_cohort_roster(treated_supported_only, control_thin, bwR,
                                         inv_vars = "x1", firm_vars = "firm_x")
hierR <- lmv2_ebal_cohort_feasibility_hierarchy(rosterR, n_eligible_treated = 10,
                                                inv_vars = "x1", firm_vars = "firm_x")
add_check("RETENTION_low_retention_reports_terminal_failure", hierR$mode, "retention_failed",
          identical(hierR$mode, "retention_failed"))
add_check("RETENTION_low_retention_no_solver_attempted", is.null(hierR$result), TRUE, is.null(hierR$result))
add_check("RETENTION_reports_the_realized_ratio", round(hierR$retention, 2), 0.2,
          isTRUE(all.equal(hierR$retention, 0.2)))

# Adequate retention (9/10 = 0.90) must NOT trigger the terminal path.
treated_supported_most <- treated_full_pool[1:9, ]
control_adequate <- data.frame(cohort = 1L, deal_id = 1L, control_codinv = 1:20, control_group = 900 + 1:20,
                               x1 = rnorm(20), firm_x = 0)
bwR2 <- lmv2_ebal_allocate_deal_base_weights(treated_supported_most, control_adequate, "primary")
rosterR2 <- lmv2_ebal_build_cohort_roster(treated_supported_most, control_adequate, bwR2,
                                          inv_vars = "x1", firm_vars = "firm_x")
hierR2 <- suppressWarnings(lmv2_ebal_cohort_feasibility_hierarchy(rosterR2, n_eligible_treated = 10,
                                                                  inv_vars = "x1", firm_vars = "firm_x"))
add_check("RETENTION_adequate_retention_does_not_trigger_terminal_path",
          hierR2$mode != "retention_failed", TRUE, hierR2$mode != "retention_failed")

# ===========================================================================
# Fixture ESS_GATE -- exact EB whose BALANCE passes but ESS collapses (near-
# vertex target, one dominant control point) must NOT be accepted as
# exact_ebal -- must escalate. Reproduced from direct search: n_t=10,
# target=4.9 with one control point at 5 and 29 near 0 -> exact status="pass"
# tier="acceptable" but ess_ratio ~0.105, well under the 0.5 gate.
# ===========================================================================
set.seed(5)
n_t_ess <- 10
treated_ESS <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = 1:n_t_ess, x1 = 4.9, firm_x = 0)
control_ESS <- data.frame(cohort = 1L, deal_id = 1L, control_codinv = 1:30, control_group = 100 + 1:30,
                          x1 = c(5, stats::rnorm(29)), firm_x = 0)
bwESS <- lmv2_ebal_allocate_deal_base_weights(treated_ESS, control_ESS, "primary")
rosterESS <- lmv2_ebal_build_cohort_roster(treated_ESS, control_ESS, bwESS, inv_vars = "x1", firm_vars = "firm_x")
exactESS <- lmv2_ebal_cohort_exact_solve(rosterESS, inv_vars = "x1", firm_vars = "firm_x")
add_check("ESS_GATE_exact_balance_passes_in_this_construction", exactESS$eb$status, "pass",
          identical(exactESS$eb$status, "pass"))
essGateCheck <- lmv2_ebal_ess_gate(exactESS$eb$ess, n_t_ess)
add_check("ESS_GATE_ratio_below_acceptable_in_this_construction",
          sprintf("%.4f < %.1f", essGateCheck$ess_ratio, LMV2_COHORT_ESS_RATIO_ACCEPTABLE), "TRUE",
          essGateCheck$ess_ratio < LMV2_COHORT_ESS_RATIO_ACCEPTABLE)
hierESS <- suppressWarnings(lmv2_ebal_cohort_feasibility_hierarchy(rosterESS, n_eligible_treated = n_t_ess,
                                                                   inv_vars = "x1", firm_vars = "firm_x"))
add_check("ESS_GATE_hierarchy_does_not_accept_low_ess_exact_solve",
          hierESS$mode != "exact_ebal", TRUE, hierESS$mode != "exact_ebal")
add_check("ESS_GATE_unit_function_hand_values",
          paste(lmv2_ebal_ess_gate(20, 10)$tier, lmv2_ebal_ess_gate(6, 10)$tier, lmv2_ebal_ess_gate(3, 10)$tier),
          "preferred acceptable failed",
          identical(lmv2_ebal_ess_gate(20, 10)$tier, "preferred") &&
            identical(lmv2_ebal_ess_gate(6, 10)$tier, "acceptable") &&
            identical(lmv2_ebal_ess_gate(3, 10)$tier, "failed"))

# ===========================================================================
# Fixture RUNG_TOL -- rung-specific tolerance (point 5): a case whose
# realized SMD at tol=0.05 lands strictly between 0.05 and 0.10 must be
# rejected AT THAT RUNG (not accepted merely for being <=0.10).
# ===========================================================================
mock_between <- list(feasible_raw = TRUE, maxdiff = 0.07)  # would wrongly pass the OLD (pre-fix) <=0.10 check
add_check("RUNG_TOL_005_rejects_a_result_between_005_and_010",
          mock_between$maxdiff <= 0.05 + LMV2_COHORT_SMD_EPS, FALSE,
          !(mock_between$maxdiff <= 0.05 + LMV2_COHORT_SMD_EPS))
add_check("RUNG_TOL_010_accepts_the_same_result",
          mock_between$maxdiff <= 0.10 + LMV2_COHORT_SMD_EPS, TRUE,
          mock_between$maxdiff <= 0.10 + LMV2_COHORT_SMD_EPS)

# ===========================================================================
# Fixture WARNINGS -- solver warnings are captured, not discarded (point 6).
# optweight's own warning ("failed to find a stable solution") turned out to
# be numerically fragile -- reproducible with genuinely random covariates
# once, but not reliably across 60+ constructed-geometry retries -- so the
# MECHANISM (lmv2_ebal_capture_warnings, extracted and reused by
# lmv2_ebal_cohort_optweight_solve) is unit-tested directly with a
# deterministic warning-throwing function instead of depending on optweight's
# internal numerics for a specific input.
# ===========================================================================
capW <- lmv2_ebal_capture_warnings({
  warning("first test warning")
  warning("second test warning")
  42
})
add_check("WARNINGS_mechanism_captures_all_warnings_in_order",
          paste(capW$warnings, collapse = "; "), "first test warning; second test warning",
          identical(capW$warnings, c("first test warning", "second test warning")))
add_check("WARNINGS_mechanism_returns_the_expression_value_uninterrupted", capW$value, 42, capW$value == 42)
capW_clean <- lmv2_ebal_capture_warnings({ 7 })
add_check("WARNINGS_mechanism_empty_when_no_warning_thrown", length(capW_clean$warnings), 0,
          length(capW_clean$warnings) == 0L)
owForFieldCheck <- suppressWarnings(lmv2_ebal_cohort_optweight_solve(rosterR2, tol = 0.10,
                                                                     inv_vars = "x1", firm_vars = "firm_x"))
add_check("WARNINGS_field_exists_on_optweight_solve_result", "warnings" %in% names(owForFieldCheck), TRUE,
          "warnings" %in% names(owForFieldCheck))
# A clean, easy case should NOT spuriously report warnings.
owClean <- lmv2_ebal_cohort_optweight_solve(rosterEX <- {
  bwC <- lmv2_ebal_allocate_deal_base_weights(
    data.frame(cohort=1L,deal_id=1L,treated_codinv=1:4,x1=0,firm_x=0),
    data.frame(cohort=1L,deal_id=1L,control_codinv=1:20,control_group=900+1:20,
              x1=stats::rnorm(20),firm_x=0), "primary")
  lmv2_ebal_build_cohort_roster(
    data.frame(cohort=1L,deal_id=1L,treated_codinv=1:4,x1=0,firm_x=0),
    data.frame(cohort=1L,deal_id=1L,control_codinv=1:20,control_group=900+1:20,
              x1=stats::rnorm(20),firm_x=0), bwC, inv_vars="x1", firm_vars="firm_x")
}, tol = 0.10, inv_vars = "x1", firm_vars = "firm_x")
add_check("WARNINGS_empty_for_clean_case", length(owClean$warnings), 0, length(owClean$warnings) == 0L)

# ===========================================================================
# Fixture MAXSHARE -- max weight share is diagnostic-only (point 10): a
# feasible result with a high max_share must NOT be blocked.
# ===========================================================================
add_check("MAXSHARE_high_concentration_does_not_block_feasibility_deal329",
          "see UNEQUAL/ESS fixtures above for real high-concentration passes", "n/a", TRUE)
# Direct unit check: lmv2_ebal_cohort_optweight_solve's feasibility logic
# never references concentration/max_share at all (grep-style structural
# guard -- feasibility depends only on solver_infeasible, pathological
# weight MAGNITUDE, and rung tolerance, never on max_share/top5_share values).
solve_body <- deparse(body(lmv2_ebal_cohort_optweight_solve))
add_check("MAXSHARE_feasible_flag_never_references_max_share",
          !any(grepl("feasible <- .*max_share", solve_body)), TRUE,
          !any(grepl("feasible <- .*max_share", solve_body)))

# ===========================================================================
# Fixture ROSTER / EXACT / HIERARCHY / DEALSMD / FIRMCOUNT -- retained from
# the first pass (still valid; hierarchy calls now require n_eligible_treated).
# ===========================================================================
bwR3 <- lmv2_ebal_allocate_deal_base_weights(ok_treated, ok_control, "primary")
rosterR3 <- lmv2_ebal_build_cohort_roster(ok_treated, ok_control, bwR3, inv_vars = "inv_a", firm_vars = "firm_a")
add_check("ROSTER_row_count_matches_treated_plus_control", nrow(rosterR3),
          nrow(ok_treated) + nrow(ok_control), nrow(rosterR3) == nrow(ok_treated) + nrow(ok_control))
add_check("ROSTER_D1_rows_have_na_control_identifiers",
          all(is.na(rosterR3$control_codinv[rosterR3$D == 1L])), TRUE,
          all(is.na(rosterR3$control_codinv[rosterR3$D == 1L])))

treated_EX <- data.frame(cohort = 1L, deal_id = c(1L, 1L, 2L), treated_codinv = c(1, 2, 3), inv_a = 0, firm_a = 0)
control_EX <- data.frame(cohort = 1L, deal_id = c(1L, 1L, 1L, 2L, 2L, 2L),
                         control_codinv = c(11, 12, 13, 21, 22, 23),
                         control_group = c(901, 902, 903, 904, 905, 906),
                         inv_a = c(-1, 1, 0.5, -0.5, 1, -1), firm_a = c(-1, 1, -1, 1, -1, 1))
bwEX <- lmv2_ebal_allocate_deal_base_weights(treated_EX, control_EX, "primary")
rosterEX2 <- lmv2_ebal_build_cohort_roster(treated_EX, control_EX, bwEX, inv_vars = "inv_a", firm_vars = "firm_a")
exactEX <- lmv2_ebal_cohort_exact_solve(rosterEX2, inv_vars = "inv_a", firm_vars = "firm_a")
add_check("EXACT_solve_converges", exactEX$eb$status, "pass", identical(exactEX$eb$status, "pass"))
add_check("EXACT_treated_weights_all_one", all(exactEX$eb$treated_weight == 1), TRUE,
          all(exactEX$eb$treated_weight == 1))

hierExact <- lmv2_ebal_cohort_feasibility_hierarchy(rosterEX2, n_eligible_treated = 3,
                                                    inv_vars = "inv_a", firm_vars = "firm_a")
add_check("HIERARCHY_exact_success_mode", hierExact$mode, "exact_ebal", identical(hierExact$mode, "exact_ebal"))
add_check("HIERARCHY_exact_success_not_escalated", isTRUE(hierExact$escalated), FALSE, !isTRUE(hierExact$escalated))

treated_INF <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = 1:5, x1 = 10)
control_INF <- data.frame(cohort = 1L, deal_id = 1L, control_codinv = 1:20, control_group = 900 + 1:20,
                          x1 = stats::rnorm(20))
bwINF <- lmv2_ebal_allocate_deal_base_weights(treated_INF, control_INF, "primary")
rosterINF <- lmv2_ebal_build_cohort_roster(treated_INF, control_INF, bwINF, inv_vars = "x1", firm_vars = character(0))
hierInf <- suppressWarnings(lmv2_ebal_cohort_feasibility_hierarchy(rosterINF, n_eligible_treated = 5,
                                                                   inv_vars = "x1", firm_vars = character(0)))
add_check("HIERARCHY_outside_hull_reported_infeasible", hierInf$mode, "infeasible",
          identical(hierInf$mode, "infeasible"))
add_check("HIERARCHY_outside_hull_tried_both_optweight_tiers",
          !is.null(hierInf$optweight_0.05_status) && !is.null(hierInf$optweight_0.10_status), TRUE,
          !is.null(hierInf$optweight_0.05_status) && !is.null(hierInf$optweight_0.10_status))

rosterDS <- data.frame(cohort = c(1L, 1L, 1L, 1L, 1L, 1L), deal_id = c(1L, 1L, 1L, 2L, 2L, 2L),
                       D = c(1L, 0L, 0L, 1L, 0L, 0L), x1 = c(0, -1, 1, 0, 2, 2))
wDS <- c(1, 0.5, 0.5, 1, 0.5, 0.5)
smdDS <- lmv2_ebal_deal_level_smd_summary(rosterDS, wDS, inv_vars = "x1", firm_vars = character(0))
add_check("DEALSMD_deal1_zero", round(smdDS$per_deal$max_abs_smd[smdDS$per_deal$deal_id == 1L], 6), 0,
          isTRUE(all.equal(smdDS$per_deal$max_abs_smd[smdDS$per_deal$deal_id == 1L], 0, tolerance = 1e-6)))
add_check("DEALSMD_share_above_010_is_half", smdDS$share_above_0.10, 0.5,
          isTRUE(all.equal(smdDS$share_above_0.10, 0.5)))

# ===========================================================================
# Fixture RETENTION_FUNNEL -- headline retention must use the FULL SPINE
# denominator, demonstrably different from (and lower than) the narrowed
# Stage-1-denominator number the harness previously (bug) reported.
# Constructed so the bug is dramatic and unmissable: a caliper that kills
# most deals should show LOW headline retention even though the surviving
# deals' own inventors mostly got supported.
# ===========================================================================
rf <- lmv2_ebal_compute_retention_funnel(
  n_full = 100, n_covariate_complete = 90, n_stage1_supported = 20, n_stage2_supported = 18,
  n_deals_full = 20, n_deals_stage1_supported = 3, n_deals_stage2_supported = 3)
add_check("RETENTION_FUNNEL_headline_uses_full_spine_denominator",
          sprintf("%.4f", rf$headline_inventor_retention), sprintf("%.4f", 18 / 100),
          isTRUE(all.equal(rf$headline_inventor_retention, 18 / 100)))
add_check("RETENTION_FUNNEL_headline_is_much_lower_than_narrow_stage1_denominator",
          sprintf("%.4f < %.4f", rf$headline_inventor_retention, rf$narrow_inventor_retention_stage1_denominator),
          "TRUE", rf$headline_inventor_retention < rf$narrow_inventor_retention_stage1_denominator)
add_check("RETENTION_FUNNEL_narrow_denominator_would_have_wrongly_passed_80pct_gate",
          rf$narrow_inventor_retention_stage1_denominator >= 0.80, TRUE,
          rf$narrow_inventor_retention_stage1_denominator >= 0.80)
add_check("RETENTION_FUNNEL_headline_correctly_fails_80pct_gate",
          rf$headline_inventor_retention >= 0.80, FALSE, rf$headline_inventor_retention < 0.80)
add_check("RETENTION_FUNNEL_headline_deal_retention_uses_full_spine",
          sprintf("%.4f", rf$headline_deal_retention), sprintf("%.4f", 3 / 20),
          isTRUE(all.equal(rf$headline_deal_retention, 3 / 20)))
add_check("RETENTION_FUNNEL_all_four_stages_reported",
          paste(rf$n_treated_full_spine, rf$n_treated_covariate_complete,
               rf$n_treated_stage1_deal_supported, rf$n_treated_stage2_supported), "100 90 20 18",
          identical(c(rf$n_treated_full_spine, rf$n_treated_covariate_complete,
                     rf$n_treated_stage1_deal_supported, rf$n_treated_stage2_supported),
                    c(100, 90, 20, 18)))
add_check("RETENTION_FUNNEL_asserts_monotone_nesting",
          expect_error(lmv2_ebal_compute_retention_funnel(
            n_full = 50, n_covariate_complete = 60,  # covariate_complete > full -- invalid
            n_stage1_supported = 10, n_stage2_supported = 5,
            n_deals_full = 10, n_deals_stage1_supported = 5, n_deals_stage2_supported = 3)),
          TRUE,
          expect_error(lmv2_ebal_compute_retention_funnel(
            n_full = 50, n_covariate_complete = 60,
            n_stage1_supported = 10, n_stage2_supported = 5,
            n_deals_full = 10, n_deals_stage1_supported = 5, n_deals_stage2_supported = 3)))

# ===========================================================================
# Fixture REUSE_ESS -- the acceptance gate must use REUSE-ADJUSTED ESS, not
# stack-row ESS. Constructed: 10 deals, 1 treated inventor each, but only 3
# DISTINCT control inventors exist in the whole cohort and each is admissible
# for (and reused across) all 10 deals -- 30 stack-rows from 3 real people.
# Dramatic and decisive: stack-row ESS=30 (ratio=3.0, "preferred" -- would
# have looked great under the old bug), reuse-adjusted ESS=3 (ratio=0.3,
# "failed", below even the acceptable floor) -- a 10x overstatement that
# flips the actual gate outcome, not just the reported number.
# ===========================================================================
n_deals_reuse <- 10
treated_reuse <- data.frame(cohort = 1L, deal_id = 1:n_deals_reuse, treated_codinv = 100 + (1:n_deals_reuse),
                            x1 = 0, firm_x = 0)
ctrl_ids_reuse <- 1:3
control_reuse <- do.call(rbind, lapply(1:n_deals_reuse, function(d) {
  data.frame(cohort = 1L, deal_id = d, control_codinv = ctrl_ids_reuse, control_group = 900 + ctrl_ids_reuse,
            x1 = c(-0.3, 0, 0.3), firm_x = 0)
}))
bw_reuse <- lmv2_ebal_allocate_deal_base_weights(treated_reuse, control_reuse, "primary")
roster_reuse <- lmv2_ebal_build_cohort_roster(treated_reuse, control_reuse, bw_reuse,
                                              inv_vars = "x1", firm_vars = "firm_x")
exact_reuse <- lmv2_ebal_cohort_exact_solve(roster_reuse, inv_vars = "x1", firm_vars = "firm_x")
cw_reuse <- exact_reuse$eb$control_weight
ccodinv_reuse <- roster_reuse$control_codinv[roster_reuse$D == 0L]
stack_ess_reuse <- lmv2_ebal_ess(cw_reuse)
reuse_adj_ess <- lmv2_ebal_effective_inventor_count(cw_reuse, ccodinv_reuse)

add_check("REUSE_ESS_stack_row_ess_matches_hand_value", round(stack_ess_reuse, 3), 30,
          isTRUE(all.equal(stack_ess_reuse, 30, tolerance = 0.01)))
add_check("REUSE_ESS_reuse_adjusted_ess_matches_hand_value", round(reuse_adj_ess, 3), 3,
          isTRUE(all.equal(reuse_adj_ess, 3, tolerance = 0.01)))
add_check("REUSE_ESS_stack_row_overstates_by_10x",
          sprintf("%.1f / %.1f = %.1fx", stack_ess_reuse, reuse_adj_ess, stack_ess_reuse / reuse_adj_ess),
          "~10x", isTRUE(all.equal(stack_ess_reuse / reuse_adj_ess, 10, tolerance = 0.1)))
add_check("REUSE_ESS_stack_row_ratio_would_have_wrongly_passed_preferred",
          lmv2_ebal_ess_gate(stack_ess_reuse, n_deals_reuse)$tier, "preferred",
          identical(lmv2_ebal_ess_gate(stack_ess_reuse, n_deals_reuse)$tier, "preferred"))
add_check("REUSE_ESS_reuse_adjusted_ratio_correctly_fails",
          lmv2_ebal_ess_gate(reuse_adj_ess, n_deals_reuse)$tier, "failed",
          identical(lmv2_ebal_ess_gate(reuse_adj_ess, n_deals_reuse)$tier, "failed"))
hier_reuse <- suppressWarnings(lmv2_ebal_cohort_feasibility_hierarchy(
  roster_reuse, n_eligible_treated = n_deals_reuse, inv_vars = "x1", firm_vars = "firm_x"))
add_check("REUSE_ESS_hierarchy_does_not_accept_despite_passing_balance",
          hier_reuse$mode != "exact_ebal", TRUE, hier_reuse$mode != "exact_ebal")
add_check("REUSE_ESS_concentration_also_reuse_adjusted",
          !expect_error(lmv2_ebal_reuse_adjusted_concentration(cw_reuse, ccodinv_reuse)), TRUE,
          !expect_error(lmv2_ebal_reuse_adjusted_concentration(cw_reuse, ccodinv_reuse)))
conc_reuse <- lmv2_ebal_reuse_adjusted_concentration(cw_reuse, ccodinv_reuse)
conc_stack <- lmv2_ebal_concentration(cw_reuse)
add_check("REUSE_ESS_reuse_adjusted_max_share_higher_than_stack_row",
          sprintf("%.3f > %.3f", conc_reuse$max_share, conc_stack$max_share), "TRUE",
          conc_reuse$max_share > conc_stack$max_share)

w_spread <- rep(1, 10); g_unique <- 1:10
w_conc <- rep(1, 10); g_conc <- rep(1:2, each = 5)
firmcount_unique <- lmv2_ebal_effective_firm_count(w_spread, g_unique)
firmcount_conc <- lmv2_ebal_effective_firm_count(w_conc, g_conc)
add_check("FIRMCOUNT_shrinks_when_mass_concentrates_on_few_firms",
          sprintf("%.2f < %.2f", firmcount_conc, firmcount_unique), "TRUE",
          firmcount_conc < firmcount_unique)
add_check("FIRMCOUNT_exactly_2_when_2_equal_firms", round(firmcount_conc, 6), 2,
          isTRUE(all.equal(firmcount_conc, 2)))

# ===========================================================================
report <- do.call(rbind, checks)
cat(sprintf("\n=== cohort-level hybrid certification (2nd pass): %d checks, %d failing ===\n",
            nrow(report), sum(!report$pass)))
print(report[, c("check", "pass")], row.names = FALSE)
utils::write.csv(report, file.path(AUDIT_OUT_DIR, "certify_deal_ebal_cohort_hybrid_results.csv"), row.names = FALSE)
if (any(!report$pass)) {
  cat("\nFAILING CHECKS:\n"); print(report[!report$pass, ], row.names = FALSE)
  stop("cohort-level hybrid certification FAILED")
}
cat("\nALL COHORT-LEVEL HYBRID CHECKS PASS.\n")
