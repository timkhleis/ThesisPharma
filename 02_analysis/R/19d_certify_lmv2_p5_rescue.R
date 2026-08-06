# Database-free certification fixtures for the P5.1 rescue overlay.

expect_true <- function(value, label) {
  if (!isTRUE(value)) stop("FAIL: ", label)
}
expect_equal <- function(value, expected, label, tolerance = 1e-12) {
  ok <- if (is.numeric(value) && is.numeric(expected)) {
    length(value) == length(expected) &&
      all(abs(value - expected) <= tolerance)
  } else {
    identical(value, expected)
  }
  if (!ok) {
    stop(
      "FAIL: ", label, "; observed=", paste(value, collapse = ","),
      "; expected=", paste(expected, collapse = ","))
  }
}

# U2 timing boundaries are inclusive at g-5 and g+5.
expect_true(
  lmv2_p5_rescue_u2_eligible(numeric(), numeric(), 2000L),
  "never-event firm is U2 eligible")
expect_true(
  !lmv2_p5_rescue_u2_eligible(2005, numeric(), 2000L),
  "target at g+5 is excluded")
expect_true(
  lmv2_p5_rescue_u2_eligible(2006, numeric(), 2000L),
  "target after g+5 is admitted")
expect_true(
  !lmv2_p5_rescue_u2_eligible(numeric(), 1995, 2000L),
  "acquirer event at g-5 is excluded")
expect_true(
  !lmv2_p5_rescue_u2_eligible(numeric(), 2005, 2000L),
  "acquirer event at g+5 is excluded")
expect_true(
  lmv2_p5_rescue_u2_eligible(numeric(), c(1994, 2006), 2000L),
  "acquirer events outside the clean window are admitted")

# Stage application changes only the intended distance/balance split and
# cohort floor.
original_p3 <- LMV2_P3
original_inv_vars <- LMV2_HYBRID_INV_VARS
original_floor <- LMV2_COHORT_RETENTION_MIN
on.exit({
  LMV2_P3 <<- original_p3
  LMV2_HYBRID_INV_VARS <<- original_inv_vars
  LMV2_COHORT_RETENTION_MIN <<- original_floor
}, add = TRUE)

lmv2_p5_rescue_apply_stage("u2_inventor_first")
expect_equal(
  LMV2_P3$stage_2$scalar_variables,
  LMV2_P5_RESCUE$original_distance_variables,
  "inventor-first Stage-2 variables")
expect_equal(
  LMV2_HYBRID_INV_VARS,
  LMV2_P5_RESCUE$original_distance_variables,
  "inventor-first balance variables")
expect_equal(
  LMV2_P5_MIN_CONTROLS_PER_TREATED, 3L,
  "inventor-first minimum control count")
expect_equal(
  LMV2_P5_MIN_FIRMS_PER_TREATED, 2L,
  "inventor-first minimum firm count")

lmv2_p5_rescue_apply_stage("u2_reduced")
expect_equal(
  LMV2_P3$stage_2$scalar_variables,
  LMV2_P5_RESCUE$reduced_distance_variables,
  "reduced Stage-2 variables")
expect_equal(
  LMV2_HYBRID_INV_VARS,
  LMV2_P5_RESCUE$reduced_balance_variables,
  "exclusivity retained for exact balance")
expect_equal(
  LMV2_COHORT_RETENTION_MIN, 0.60,
  "rescue cohort floor")
expect_equal(
  LMV2_P5_RESCUE$gates$deal_70_effective_firm_review, 2.50,
  "deal-70 effective-firm review trigger")
expect_equal(
  LMV2_P5_RESCUE$gates$deal_70_leave_one_firm_out_max_shift_sd,
  0.10,
  "deal-70 leave-one-firm-out threshold")

lmv2_p5_rescue_apply_stage("u2_reduced_knn")
expect_true(
  isTRUE(LMV2_P5_KNN_MODE),
  "adaptive k-nearest mode is installed")
expect_equal(
  LMV2_P5_KNN_K, 5L,
  "adaptive k-nearest k is hash-pinned")
expect_equal(
  LMV2_P5_KNN_SANITY_QUANTILE, 0.99,
  "adaptive k-nearest sanity quantile is hash-pinned")
expect_true(
  is.infinite(STAGE2_CALIPER),
  "adaptive k-nearest replaces the downstream absolute caliper")

lmv2_p5_rescue_apply_stage("u2_reduced_stage1_2")
expect_equal(
  STAGE1_CALIPERS, 2.0,
  "industry-support diagnostic uses Stage-1 caliper 2.0")
expect_equal(
  STAGE2_CALIPER, 1.5,
  "industry-support diagnostic preserves the absolute Stage-2 caliper")
expect_true(
  !LMV2_P5_KNN_MODE,
  "industry-support diagnostic is not adaptive k-nearest")

# Per-inventor k-nearest selects distant sparse-tail units locally rather than
# filtering them by a global candidate-distance quantile.
edges <- data.frame(
  cohort = rep(2000L, 10),
  deal_id = rep(c(1L, 2L), each = 5),
  treated_codinv = rep(c(101, 102), each = 5),
  control_codinv = 201:210,
  control_group = c(1, 1, 2, 2, 3, 4, 4, 5, 5, 6),
  distance = c(0.2, 0.3, 0.4, 0.8, 1.0, 3.2, 3.3, 3.5, 4.0, 4.5)
)
knn <- lmv2_p5_rescue_select_knn(
  edges, k = 3L, max_distance = 5)
expect_equal(
  sort(unique(knn$edges$treated_codinv)), c(101, 102),
  "k-nearest retains ordinary and sparse-tail treated units")
expect_true(
  all(tapply(
    knn$edges$control_group, knn$edges$treated_codinv,
    function(z) length(unique(z))) >= 2L),
  "k-nearest enforces two-firm diversification")
bounded <- lmv2_p5_rescue_select_knn(
  edges, k = 3L, max_distance = 3)
expect_equal(
  unique(bounded$unsupported$treated_codinv), 102,
  "sanity bound rejects pathological nearest distances")

# Gate fixture: cohort, deal, and quartile thresholds all bind independently.
n <- 40L
fixture <- data.frame(
  cohort = rep(c(2000L, 2009L), each = n / 2),
  deal_id = rep(1:8, each = 5),
  codinv = seq_len(n),
  log_patent_count_5y = seq(0.01, 1, length.out = n),
  career_age = rep(1:5, length.out = n),
  focal_group_exclusivity = rep(c(0.8, 0.9, 1), length.out = n),
  focal_group_tenure = rep(1:4, length.out = n),
  supported = rep(c(TRUE, TRUE, TRUE, TRUE, FALSE), length.out = n)
)
gate <- lmv2_p5_rescue_score_gates(fixture)
expect_equal(
  gate$checks$realized[
    gate$checks$gate == "aggregate_inventor_coverage"],
  0.80, "aggregate coverage gate arithmetic")
expect_true(
  nrow(gate$by_quartile) == 4L,
  "all productivity quartiles reported")
expect_true(
  gate$pass &&
    !gate$checks$terminal[
      gate$checks$gate == "maximum_absolute_selection_smd"],
  "selection SMD remains reported but is not a P5.2 terminal gate")

# Deal-level dependence is computed from final control weights. Equal mass
# across three firms has effective firm count 3 and constant covariates make
# every leave-one-firm-out shift exactly zero.
diagnostic_roster <- data.frame(
  cohort = rep(2000L, 8),
  deal_id = rep(70L, 8),
  D = c(1L, 1L, rep(0L, 6)),
  treated_codinv = c(1, 2, rep(NA_real_, 6)),
  control_codinv = c(NA_real_, NA_real_, 11:16),
  control_group = c(NA_real_, NA_real_, rep(101:103, each = 2)),
  stringsAsFactors = FALSE)
for (variable in unique(c(
    LMV2_HYBRID_INV_VARS, LMV2_HYBRID_FIRM_VARS))) {
  diagnostic_roster[[variable]] <- 1
}
diagnostic_context <- list(
  roster = diagnostic_roster,
  result = list(weight = rep(1, nrow(diagnostic_roster))),
  cohort = 2000L,
  scheme = "primary")
dependence_fixture <-
  lmv2_p5_rescue_compute_dependence(diagnostic_context)
expect_equal(
  dependence_fixture$dependence$effective_firm_count,
  3,
  "equal three-firm mass has effective firm count three")
expect_true(
  !dependence_fixture$dependence$effective_firm_review_trigger,
  "three-firm fixture does not trigger the 2.5 review rule")
expect_true(
  nrow(dependence_fixture$leave_one_firm_out) ==
    3L * length(unique(c(
      LMV2_HYBRID_INV_VARS, LMV2_HYBRID_FIRM_VARS))) &&
    all(dependence_fixture$leave_one_firm_out$pass),
  "constant-covariate leave-one-firm-out fixture passes")

message("19d P5.1 rescue certification: ALL FIXTURES PASS")
