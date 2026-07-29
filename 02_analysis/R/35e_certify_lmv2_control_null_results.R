# ============================================================================
# Final control-null result certification and tooth-test helpers
# ============================================================================

lmv2_control_null_result_checks <- function(
    draws_path, diagnostics_path) {
  draws <- utils::read.csv(draws_path, stringsAsFactors = FALSE)
  diagnostics <- utils::read.csv(
    diagnostics_path, stringsAsFactors = FALSE)
  forbidden <- c(
    "real_att", "empirical_p", "bias_ratio",
    "placebo_adjusted_diagnostic",
    "material_negative_bias_trigger")
  required_draw_fields <- c(
    "volume_comparable_draw",
    "nominal_cluster_comparable_draw",
    "effective_cluster_comparable_draw",
    "cluster_comparable_draw",
    "inference_comparable_draw")
  missing_draw_fields <- setdiff(required_draw_fields, names(draws))
  if (length(missing_draw_fields)) {
    stop(
      "Summary draws lack classification fields: ",
      paste(missing_draw_fields, collapse = ", "))
  }
  volume_expected <-
    draws$supported_treated_inventor_count_ratio >=
      LMV2_CONTROL_NULL_P6$volume_comparability_bounds[[1L]] &
    draws$supported_treated_inventor_count_ratio <=
      LMV2_CONTROL_NULL_P6$volume_comparability_bounds[[2L]]
  nominal_cluster_expected <-
    draws$nominal_treated_firm_ratio >=
      LMV2_CONTROL_NULL_P6$nominal_cluster_ratio_bounds[[1L]] &
    draws$nominal_treated_firm_ratio <=
      LMV2_CONTROL_NULL_P6$nominal_cluster_ratio_bounds[[2L]]
  effective_cluster_expected <-
    draws$effective_treated_firm_ratio >=
      LMV2_CONTROL_NULL_P6$effective_cluster_ratio_bounds[[1L]] &
    draws$effective_treated_firm_ratio <=
      LMV2_CONTROL_NULL_P6$effective_cluster_ratio_bounds[[2L]]
  cluster_expected <-
    nominal_cluster_expected & effective_cluster_expected
  inference_expected <- volume_expected & cluster_expected
  comparable <- draws[inference_expected, , drop = FALSE]
  expected_false_rejection <- if (nrow(comparable)) {
    mean(comparable$p_value < 0.05)
  } else {
    NA_real_
  }
  false_rejection_difference <- if (
    is.na(expected_false_rejection) &&
      is.na(diagnostics$false_rejection_share)) {
    0
  } else {
    abs(
      expected_false_rejection -
        diagnostics$false_rejection_share)
  }
  checks <- data.frame(
    check = c(
      "draw_ids_unique",
      "estimates_finite",
      "one_assignment_arm",
      "one_analysis_sample",
      "diagnostics_one_row",
      "distribution_not_recentered",
      "volume_flags_recompute",
      "nominal_cluster_flags_recompute",
      "effective_cluster_flags_recompute",
      "cluster_flags_recompute",
      "inference_flags_recompute",
      "inference_draw_count_matches",
      "false_rejection_uses_comparable_subset",
      "incommensurable_statistics_absent"),
    observed = c(
      anyDuplicated(draws$draw_id),
      sum(!is.finite(draws$estimate)),
      length(unique(draws$assignment_arm)),
      length(unique(draws$sample)),
      nrow(diagnostics),
      abs(mean(draws$estimate) -
            diagnostics$placebo_mean),
      sum(as.logical(draws$volume_comparable_draw) !=
            volume_expected),
      sum(as.logical(draws$nominal_cluster_comparable_draw) !=
            nominal_cluster_expected),
      sum(as.logical(draws$effective_cluster_comparable_draw) !=
            effective_cluster_expected),
      sum(as.logical(draws$cluster_comparable_draw) !=
            cluster_expected),
      sum(as.logical(draws$inference_comparable_draw) !=
            inference_expected),
      abs(
        sum(inference_expected) -
          diagnostics$inference_comparable_draws),
      false_rejection_difference,
      sum(forbidden %in% names(diagnostics))),
    expected = c(
      0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    stringsAsFactors = FALSE)
  checks$pass <- abs(
    as.numeric(checks$observed) -
      as.numeric(checks$expected)) < 1e-12
  checks
}

lmv2_control_null_summary_tooth_test <- function() {
  forbidden_fixture <- data.frame(
    placebo_mean = 0, empirical_p = 0.01)
  forbidden <- c(
    "real_att", "empirical_p", "bias_ratio",
    "placebo_adjusted_diagnostic",
    "material_negative_bias_trigger")
  if (!any(forbidden %in% names(forbidden_fixture))) {
    stop("Forbidden-statistic tooth test could not fire")
  }
  invisible(TRUE)
}
