# ============================================================================
# Fast positive/negative tests for the control-null summary guards
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "35a_lmv2_control_null_config.R"))
source(file.path(
  BASE, "R", "35d_summarize_lmv2_control_null_distribution.R"))
source(file.path(
  BASE, "R", "35e_certify_lmv2_control_null_results.R"))

root <- file.path(tempdir(), "lmv2_control_null_summary_fixture")
unlink(root, recursive = TRUE)
dir.create(root, recursive = TRUE)
for (i in 1:2) {
  draw_dir <- file.path(
    root, sprintf("draw_%04d", 1000L + i), "estimate")
  dir.create(draw_dir, recursive = TRUE)
  fixture <- data.frame(
    outcome = "patent_count",
    sample = "full_1994_2010",
    summary = "average_annual_t1_to_t5",
    inference = "deal_wild_bootstrap_t",
    estimate = c(-0.01, 0.01)[[i]],
    p_value = c(0.01, 0.5)[[i]],
    ci_low = -0.03,
    ci_high = 0.03,
    assignment_arm = "unrestricted",
    predicted_placebo_sign = "zero",
    treated_inventor_count_ratio = c(0.95, 1.02)[[i]],
    supported_treated_inventor_count_ratio =
      c(0.94, 0.50)[[i]],
    nominal_treated_firms = c(340, 80)[[i]],
    nominal_treated_firm_ratio = c(1.00, 0.23)[[i]],
    effective_treated_firms = c(37, 8)[[i]],
    max_treated_firm_weight_share = c(0.08, 0.30)[[i]],
    effective_treated_firm_ratio = c(1.00, 0.21)[[i]])
  utils::write.csv(
    fixture,
    file.path(draw_dir, "control_null_headline.csv"),
    row.names = FALSE)
}

summary_dir <- file.path(root, "summary")
lmv2_control_null_summarize(root, summary_dir)
checks <- lmv2_control_null_result_checks(
  file.path(summary_dir, "control_null_att_draws.csv"),
  file.path(summary_dir, "control_null_centering_summary.csv"))
lmv2_control_null_summary_tooth_test()
stopifnot(all(checks$pass))
summary <- utils::read.csv(
  file.path(summary_dir, "control_null_centering_summary.csv"),
  stringsAsFactors = FALSE)
stopifnot(
  abs(summary$placebo_mean) < 1e-12,
  summary$volume_comparable_draws == 1L,
  summary$cluster_comparable_draws == 1L,
  summary$nominal_cluster_comparable_draws == 1L,
  summary$effective_cluster_comparable_draws == 1L,
  summary$inference_comparable_draws == 1L,
  summary$false_rejection_share == 1)

# Corrupting a derived comparability flag must make certification fail.
draws_path <- file.path(
  summary_dir, "control_null_att_draws.csv")
corrupt <- utils::read.csv(draws_path, stringsAsFactors = FALSE)
corrupt$cluster_comparable_draw[[1L]] <-
  !as.logical(corrupt$cluster_comparable_draw[[1L]])
utils::write.csv(corrupt, draws_path, row.names = FALSE)
corrupt_checks <- lmv2_control_null_result_checks(
  draws_path,
  file.path(summary_dir, "control_null_centering_summary.csv"))
stopifnot(
  !corrupt_checks$pass[
    corrupt_checks$check == "cluster_flags_recompute"])
message("Control-null summary fixtures passed")
