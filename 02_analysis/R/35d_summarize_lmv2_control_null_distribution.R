# ============================================================================
# Summarize the control-only pipeline-falsification distribution
# ============================================================================
# This is not a randomization distribution for the real acquisition ATT.
# Consequently, it reports centering for every completed draw and estimates
# false rejection only among draws comparable to the real design in both
# supported inventor volume and effective treated-cluster count. It never
# compares placebo estimates with the real ATT.

lmv2_control_null_summarize <- function(draw_root, output_dir) {
  headline_paths <- list.files(
    draw_root, pattern = "^control_null_headline\\.csv$",
    recursive = TRUE, full.names = TRUE)
  rows <- lapply(headline_paths, function(path) {
    x <- utils::read.csv(path, stringsAsFactors = FALSE)
    hit <- x[
      x$outcome == "patent_count" &
        x$summary == "average_annual_t1_to_t5" &
        x$inference == "deal_wild_bootstrap_t", ,
      drop = FALSE]
    if (nrow(hit) != 1L) return(NULL)
    hit$path <- path
    hit
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) stop("No certified control-null estimates found")
  placebo <- do.call(rbind, rows)
  placebo$draw_id <- as.integer(sub(
    ".*draw_([0-9]+).*", "\\1", placebo$path))
  if (!"assignment_arm" %in% names(placebo) ||
      length(unique(placebo$assignment_arm)) != 1L) {
    stop("Summary input must contain exactly one assignment arm")
  }
  if (!"sample" %in% names(placebo) ||
      length(unique(placebo$sample)) != 1L) {
    stop("Summary input must contain exactly one analysis sample")
  }
  if (!all(c(
      "treated_inventor_count_ratio",
      "supported_treated_inventor_count_ratio",
      "nominal_treated_firms",
      "nominal_treated_firm_ratio",
      "effective_treated_firms",
      "max_treated_firm_weight_share",
      "effective_treated_firm_ratio") %in% names(placebo))) {
    stop("Placebo estimates lack volume or cluster diagnostics")
  }

  estimates <- placebo$estimate
  ratio_bounds <-
    LMV2_CONTROL_NULL_P6$volume_comparability_bounds
  cluster_bounds <-
    LMV2_CONTROL_NULL_P6$effective_cluster_ratio_bounds
  nominal_cluster_bounds <-
    LMV2_CONTROL_NULL_P6$nominal_cluster_ratio_bounds
  placebo$volume_comparable_draw <-
    placebo$supported_treated_inventor_count_ratio >=
      ratio_bounds[[1L]] &
      placebo$supported_treated_inventor_count_ratio <=
      ratio_bounds[[2L]]
  placebo$nominal_cluster_comparable_draw <-
    placebo$nominal_treated_firm_ratio >=
      nominal_cluster_bounds[[1L]] &
      placebo$nominal_treated_firm_ratio <=
      nominal_cluster_bounds[[2L]]
  placebo$effective_cluster_comparable_draw <-
    placebo$effective_treated_firm_ratio >=
      cluster_bounds[[1L]] &
      placebo$effective_treated_firm_ratio <=
      cluster_bounds[[2L]]
  placebo$cluster_comparable_draw <-
    placebo$nominal_cluster_comparable_draw &
      placebo$effective_cluster_comparable_draw
  placebo$inference_comparable_draw <-
    placebo$volume_comparable_draw &
      placebo$cluster_comparable_draw
  inference_subset <- placebo[
    placebo$inference_comparable_draw, , drop = FALSE]
  placebo_mean <- mean(estimates)
  placebo_sd <- stats::sd(estimates)
  diagnostics <- data.frame(
    assignment_arm = unique(placebo$assignment_arm),
    sample = unique(placebo$sample),
    predicted_placebo_sign = if (
      "predicted_placebo_sign" %in% names(placebo)) {
      unique(placebo$predicted_placebo_sign)
    } else {
      NA_character_
    },
    draws = length(estimates),
    volume_comparable_draws =
      sum(placebo$volume_comparable_draw),
    cluster_comparable_draws =
      sum(placebo$cluster_comparable_draw),
    nominal_cluster_comparable_draws =
      sum(placebo$nominal_cluster_comparable_draw),
    effective_cluster_comparable_draws =
      sum(placebo$effective_cluster_comparable_draw),
    inference_comparable_draws = nrow(inference_subset),
    placebo_mean = placebo_mean,
    placebo_mean_monte_carlo_se =
      if (length(estimates) > 1L) {
        placebo_sd / sqrt(length(estimates))
      } else {
        NA_real_
      },
    placebo_sd = placebo_sd,
    placebo_median = stats::median(estimates),
    placebo_p025 =
      stats::quantile(estimates, 0.025, names = FALSE),
    placebo_p975 =
      stats::quantile(estimates, 0.975, names = FALSE),
    negative_share = mean(estimates < 0),
    mean_treated_inventor_count_ratio =
      mean(placebo$treated_inventor_count_ratio),
    mean_supported_treated_inventor_count_ratio =
      mean(placebo$supported_treated_inventor_count_ratio),
    mean_nominal_treated_firms =
      mean(placebo$nominal_treated_firms),
    mean_nominal_treated_firm_ratio =
      mean(placebo$nominal_treated_firm_ratio),
    mean_effective_treated_firms =
      mean(placebo$effective_treated_firms),
    mean_effective_treated_firm_ratio =
      mean(placebo$effective_treated_firm_ratio),
    mean_max_treated_firm_weight_share =
      mean(placebo$max_treated_firm_weight_share),
    false_rejection_share = if (nrow(inference_subset)) {
      mean(inference_subset$p_value < 0.05)
    } else {
      NA_real_
    },
    interval_coverage_zero = if (nrow(inference_subset)) {
      mean(
        inference_subset$ci_low <= 0 &
          inference_subset$ci_high >= 0)
    } else {
      NA_real_
    },
    stringsAsFactors = FALSE)

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    placebo,
    file.path(output_dir, "control_null_att_draws.csv"),
    row.names = FALSE)
  utils::write.csv(
    diagnostics,
    file.path(output_dir, "control_null_centering_summary.csv"),
    row.names = FALSE)

  grDevices::png(
    file.path(output_dir, "control_null_att_distribution.png"),
    width = 1800, height = 1100, res = 180)
  graphics::hist(
    estimates, breaks = "FD",
    col = "#A9C4B4", border = "white",
    main = "Random-firm pipeline-falsification distribution",
    xlab = "Average annual placebo ATT, t=+1 to +5")
  graphics::abline(v = 0, col = "#707070", lwd = 2)
  graphics::abline(v = placebo_mean, col = "#315C53", lwd = 3)
  graphics::legend(
    "topright",
    legend = c("Zero", sprintf("Placebo mean = %.3f", placebo_mean)),
    col = c("#707070", "#315C53"), lwd = c(2, 3), bty = "n")
  grDevices::dev.off()

  invisible(list(draws = placebo, diagnostics = diagnostics))
}
