# ============================================================================
# certify_deal_ebal_hybrid.R -- database-free fixtures for the hybrid core
# ============================================================================
# Verifies the new hybrid within-deal EB logic in isolation, with no database
# access: the combined inventor+firm single solve, the support gate, the
# deterministic nearest-n cap, exact/approximate feasibility classification,
# the uniform-s.weights / treated-weight-one invariant, and the equal-deal
# rescale. Run before any DB-facing hybrid pilot.

if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))

checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1]] <<- data.frame(
    check = name, observed = paste(observed, collapse = ","),
    expected = paste(expected, collapse = ","), pass = isTRUE(pass), stringsAsFactors = FALSE)
}

# ===========================================================================
# Fixture A -- combined-vector single solve achieves firm balance that uniform
# weights do NOT. inv_vars = x1, firm_vars = f1. Target (treated) point is the
# interior (0,0) of the control cloud, so the joint solve is feasible; control
# COUNTS are asymmetric so uniform weights leave f1 (and x1) off-target.
# ===========================================================================
treated_A <- data.frame(x1 = c(0, 0), f1 = c(0, 0))          # 2 treated inv, target firm f1=0
control_A <- data.frame(x1 = c(-1, 1, -1, 1, 1),
                        f1 = c(-2, -2, 2, 2, -2))            # uniform f1 mean = -0.4, x1 mean = 0.2
solA <- lmv2_ebal_hybrid_solve(treated_A, control_A, inv_vars = "x1", firm_vars = "f1")

add_check("A_solver_converges", solA$eb$status, "pass", identical(solA$eb$status, "pass"))
add_check("A_firm_imbalanced_before_solve", round(solA$smd_firm_before, 3),
          ">0.10", is.finite(solA$smd_firm_before) && solA$smd_firm_before > 0.10)
add_check("A_firm_balanced_after_solve", format(solA$smd_firm_after, scientific = TRUE),
          "<=1e-3", is.finite(solA$smd_firm_after) && solA$smd_firm_after <= 1e-3)
add_check("A_inventor_balanced_after_solve", format(solA$smd_inventor_after, scientific = TRUE),
          "<=1e-3", is.finite(solA$smd_inventor_after) && solA$smd_inventor_after <= 1e-3)
add_check("A_max_smd_after_within_tolerance", format(solA$max_smd_after, scientific = TRUE),
          "<=1e-3", is.finite(solA$max_smd_after) && solA$max_smd_after <= 1e-3)

# ---- uniform s.weights => primary treated weights all exactly 1 (no base
#      weights consumed), and control weights strictly positive.
add_check("A_treated_weights_all_one", paste(unique(solA$eb$treated_weight), collapse = ","),
          "1", all(solA$eb$treated_weight == 1))
add_check("A_control_weights_positive", all(solA$eb$control_weight > 0), TRUE,
          all(solA$eb$control_weight > 0))

# ---- before/after tables split correctly into inventor vs firm covariates.
add_check("A_balance_after_has_both_covariates",
          paste(sort(solA$balance_after$variable), collapse = ","), "f1,x1",
          setequal(solA$balance_after$variable, c("x1", "f1")))

# ---- feasibility classifier: exact/acceptable => feasible, no approximate.
featA <- lmv2_ebal_hybrid_feasibility(solA$eb)
add_check("A_feasibility_exact_ebal", paste(featA$feasible, featA$needs_approximate),
          "TRUE FALSE", isTRUE(featA$feasible) && !isTRUE(featA$needs_approximate))

# ---- equal-deal rescale: sum of equal-deal treated weights == 1 exactly;
#      equal-deal control == primary control / n_supported.
n_sup_A <- length(solA$eb$treated_weight)
eqA <- lmv2_ebal_equal_deal_from_primary(solA$eb$treated_weight, solA$eb$control_weight, n_sup_A)
add_check("A_equal_deal_treated_sums_to_one", sprintf("%.10f", eqA$treated_sum), "1",
          isTRUE(all.equal(eqA$treated_sum, 1)))
add_check("A_equal_deal_control_is_primary_over_n",
          isTRUE(all.equal(eqA$control, solA$eb$control_weight / n_sup_A)), TRUE,
          isTRUE(all.equal(eqA$control, solA$eb$control_weight / n_sup_A)))

# ===========================================================================
# Fixture B -- target firm covariate OUTSIDE the control support range: exact
# EB is infeasible; must be FLAGGED exact_infeasible + needs_approximate, never
# silently passed. Target f1 = 10, controls f1 in [-2, 2].
# ===========================================================================
treated_B <- data.frame(x1 = c(0, 0), f1 = c(10, 10))
control_B <- data.frame(x1 = c(-1, 1, -1, 1, 1), f1 = c(-2, -2, 2, 2, -2))
solB <- lmv2_ebal_hybrid_solve(treated_B, control_B, inv_vars = "x1", firm_vars = "f1")
featB <- lmv2_ebal_hybrid_feasibility(solB$eb)
add_check("B_exact_solve_does_not_pass", solB$eb$status != "pass", TRUE, solB$eb$status != "pass")
add_check("B_flagged_infeasible_needs_approximate",
          paste(featB$feasible, featB$mode, featB$needs_approximate),
          "FALSE exact_infeasible TRUE",
          !isTRUE(featB$feasible) && identical(featB$mode, "exact_infeasible") &&
            isTRUE(featB$needs_approximate))

# ===========================================================================
# Fixture C -- support gate: >=5 distinct control firms required.
# ===========================================================================
add_check("C_support_gate_4_firms_unsupported", lmv2_ebal_deal_supported(4L), FALSE,
          !lmv2_ebal_deal_supported(4L))
add_check("C_support_gate_5_firms_supported", lmv2_ebal_deal_supported(5L), TRUE,
          lmv2_ebal_deal_supported(5L))
add_check("C_support_gate_6_firms_supported", lmv2_ebal_deal_supported(6L), TRUE,
          lmv2_ebal_deal_supported(6L))
add_check("C_support_gate_zero_firms_unsupported", lmv2_ebal_deal_supported(0L), FALSE,
          !lmv2_ebal_deal_supported(0L))

# ===========================================================================
# Fixture D -- deterministic nearest-n-within-caliper cap. 60 firms, distinct
# distances = control_group id; cap 50 keeps control_group 1..50 (the 50
# smallest distances). A tie block is broken by ascending control_group. Twice-
# run identical.
# ===========================================================================
edges_D <- data.frame(cohort = 1L, deal_id = 1L, control_group = 1:60, distance = as.numeric(1:60))
capD <- lmv2_ebal_nearest_within_caliper(edges_D, 50L)
add_check("D_cap_keeps_exactly_50", nrow(capD), 50, nrow(capD) == 50L)
add_check("D_cap_keeps_50_smallest_distances",
          paste(range(capD$control_group), collapse = "-"), "1-50",
          setequal(capD$control_group, 1:50))
# tie block: 4 firms all at distance 5, cap 2 -> keep the two smallest ids.
edges_tie <- data.frame(cohort = 1L, deal_id = 1L, control_group = c(40, 10, 30, 20),
                        distance = c(5, 5, 5, 5))
capTie <- lmv2_ebal_nearest_within_caliper(edges_tie, 2L)
add_check("D_ties_broken_by_ascending_control_group",
          paste(sort(capTie$control_group), collapse = ","), "10,20",
          setequal(capTie$control_group, c(10, 20)))
capD2 <- lmv2_ebal_nearest_within_caliper(edges_D, 50L)
add_check("D_cap_deterministic_twice_run",
          isTRUE(all.equal(capD, capD2)), TRUE, isTRUE(all.equal(capD, capD2)))
# per-deal independence: two deals, cap applies within each.
edges_two <- rbind(
  data.frame(cohort = 1L, deal_id = 1L, control_group = 1:3, distance = c(1, 2, 3)),
  data.frame(cohort = 1L, deal_id = 2L, control_group = 4:6, distance = c(1, 2, 3)))
capTwo <- lmv2_ebal_nearest_within_caliper(edges_two, 2L)
add_check("D_cap_applies_within_each_deal",
          paste(sort(capTwo$control_group), collapse = ","), "1,2,4,5",
          setequal(capTwo$control_group, c(1, 2, 4, 5)))

# ===========================================================================
# Fixture E -- the full 8-covariate real balance vector solves on a feasible
# synthetic deal (guards against a construction bug in the 5-inventor + 3-firm
# variable wiring, not just the 2-var minimal case). Treated = interior point.
# ===========================================================================
set.seed(20260724L)
iv <- LMV2_HYBRID_INV_VARS; fv <- LMV2_HYBRID_FIRM_VARS
mk_controls <- function(n) {
  d <- as.data.frame(lapply(c(iv, fv), function(v) stats::rnorm(n)))
  names(d) <- c(iv, fv); d
}
control_E <- mk_controls(60)
# treated at the column means of the control cloud (guaranteed interior/feasible)
treated_E <- as.data.frame(lapply(c(iv, fv), function(v) rep(mean(control_E[[v]]), 4)))
names(treated_E) <- c(iv, fv)
solE <- lmv2_ebal_hybrid_solve(treated_E, control_E)   # uses default 5+3 vars
add_check("E_full_8var_vector_converges", solE$eb$status, "pass", identical(solE$eb$status, "pass"))
add_check("E_full_8var_all_smd_within_tol", format(solE$max_smd_after, scientific = TRUE),
          "<=1e-3", is.finite(solE$max_smd_after) && solE$max_smd_after <= 1e-3)
add_check("E_full_8var_reports_all_8_covariates", nrow(solE$balance_after), 8,
          nrow(solE$balance_after) == 8L)
add_check("E_full_8var_treated_weights_one", all(solE$eb$treated_weight == 1), TRUE,
          all(solE$eb$treated_weight == 1))

# ---- Regression guard: the inventor and attached-firm covariate name sets
#      must be DISJOINT, so the combined 8-moment vector never silently
#      dedupes to 7 (patent_trajectory collision). Also assert firm trajectory
#      is present under its prefixed name in the solved balance table.
add_check("E_inv_and_firm_var_names_disjoint",
          length(intersect(LMV2_HYBRID_INV_VARS, LMV2_HYBRID_FIRM_VARS)), 0,
          length(intersect(LMV2_HYBRID_INV_VARS, LMV2_HYBRID_FIRM_VARS)) == 0L)
add_check("E_firm_trajectory_present_and_balanced",
          "firm_patent_trajectory" %in% solE$balance_after$variable, TRUE,
          "firm_patent_trajectory" %in% solE$balance_after$variable &&
            "patent_trajectory" %in% solE$balance_after$variable)

# ===========================================================================
report <- do.call(rbind, checks)
cat(sprintf("\n=== hybrid core certification: %d checks, %d failing ===\n",
            nrow(report), sum(!report$pass)))
print(report[, c("check", "pass")], row.names = FALSE)
utils::write.csv(report, file.path(AUDIT_OUT_DIR, "certify_deal_ebal_hybrid_results.csv"), row.names = FALSE)
if (any(!report$pass)) {
  cat("\nFAILING CHECKS:\n"); print(report[!report$pass, ], row.names = FALSE)
  stop("hybrid core certification FAILED")
}
cat("\nALL HYBRID CORE CHECKS PASS.\n")
