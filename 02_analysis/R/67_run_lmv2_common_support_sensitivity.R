# ============================================================================
# 67_run_lmv2_common_support_sensitivity.R -- full-cohort support sensitivity
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))

required <- c("DBI", "duckdb", "digest", "ggplot2")
for (pkg in required) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

VERSION <- "lmv2_common_support_sensitivity_1993_v2"
FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_1993_selection_extensions_freeze.md")
FREEZE_SHA256 <-
  "3f4ea043dc48eefee6e3b60e0c0396584c5477898db7c2c56249f659cc490aa6"
if (!identical(
    digest::digest(file = FREEZE_PATH, algo = "sha256"),
    FREEZE_SHA256)) {
  stop("Selection-extension freeze has drifted")
}

source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "20a_lmv2_p6_selection_sensitivity_config.R"))

AUDIT_ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
ROSTER_PATH <- file.path(
  AUDIT_ROOT, "P5C_P6_HANDOFF", "p5c_p6_primary_weighted_roster.parquet")
HEADLINE_PATH <- file.path(
  AUDIT_ROOT, "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv")
COVERAGE_PATH <- file.path(
  AUDIT_ROOT, "P5_PRODUCTION_FINAL", "finalized",
  "realized_coverage_by_cohort.csv")
OUTPUT_DIR <- file.path(AUDIT_ROOT, "COMMON_SUPPORT_SENSITIVITY")
DB_PATH <- file.path(BASE, "output", "thesis_foundation.duckdb")

inputs <- c(DB_PATH, ROSTER_PATH, HEADLINE_PATH, COVERAGE_PATH)
if (any(!file.exists(inputs))) {
  stop("A common-support input is missing: ",
       paste(inputs[!file.exists(inputs)], collapse = "; "))
}
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

write_csv <- function(x, name) {
  utils::write.csv(
    x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = "")
}
sql_string <- function(x) {
  paste0("'", gsub("'", "''", normalizePath(
    x, winslash = "/", mustWork = TRUE), fixed = TRUE), "'")
}

con <- DBI::dbConnect(duckdb::duckdb(), DB_PATH, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=4")

eligible <- DBI::dbGetQuery(con, "
  SELECT CAST(cohort AS INTEGER) cohort,
         CAST(deal_id AS INTEGER) deal_id,
         CAST(codinv AS BIGINT) codinv,
         CAST(patent_count_5y AS DOUBLE) patent_count_5y,
         CAST(active_pre_years AS DOUBLE) active_pre_years,
         log_patent_count_5y, patent_trajectory, career_age,
         focal_group_tenure, focal_group_exclusivity
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort BETWEEN 1993 AND 2010
  ORDER BY cohort, deal_id, codinv")
supported <- DBI::dbGetQuery(con, sprintf("
  SELECT CAST(cohort AS INTEGER) cohort,
         CAST(deal_id AS INTEGER) deal_id,
         CAST(codinv AS BIGINT) codinv,
         weight
  FROM read_parquet(%s)
  WHERE arm='treated'
  ORDER BY cohort, deal_id, codinv", sql_string(ROSTER_PATH)))

eligible_key <- eligible[c("cohort", "deal_id", "codinv")]
supported_key <- supported[c("cohort", "deal_id", "codinv")]
if (anyDuplicated(eligible_key)) stop("Eligible treated keys are duplicated")
if (anyDuplicated(supported_key)) stop("Supported treated keys are duplicated")
eligible_id <- do.call(paste, c(eligible_key, sep = ":"))
supported_id <- do.call(paste, c(supported_key, sep = ":"))
if (!all(supported_id %in% eligible_id)) {
  stop("The P5c supported roster is not a subset of the P3 eligible roster")
}
eligible$supported <- eligible_id %in% supported_id
unsupported <- eligible[!eligible$supported, , drop = FALSE]

coverage_source <- utils::read.csv(COVERAGE_PATH, stringsAsFactors = FALSE)
source_eligible <- sum(coverage_source$eligible)
source_supported <- sum(coverage_source$supported)
if (nrow(eligible) != source_eligible ||
    nrow(supported) != source_supported) {
  stop("Support counts do not reconcile to the frozen coverage audit")
}
if (any(abs(supported$weight - 1) > 1e-12)) {
  stop("Supported treated inventors are not equally weighted")
}

coverage <- nrow(supported) / nrow(eligible)
headline <- utils::read.csv(HEADLINE_PATH, stringsAsFactors = FALSE)
headline <- headline[
  headline$summary == "average_annual_t1_to_t5" &
    headline$governing %in% TRUE &
    headline$outcome %in% c("patent_count", "active_patenting"), ]
if (nrow(headline) != 2L) {
  stop("Expected one governing count and active-patenting headline row")
}

winsorized_sd <- function(x, probs) {
  q <- stats::quantile(x, probs = probs, na.rm = TRUE, names = FALSE)
  z <- pmin(pmax(x, q[[1]]), q[[2]])
  list(sd = stats::sd(z), lower = q[[1]], upper = q[[2]])
}

pre_scales <- list(
  patent_count = winsorized_sd(
    eligible$patent_count_5y / 5,
    LMV2_P6_SELECTION$pre_outcome_winsorization),
  active_patenting = winsorized_sd(
    eligible$active_pre_years / 5,
    LMV2_P6_SELECTION$pre_outcome_winsorization))
scale_table <- do.call(rbind, lapply(names(pre_scales), function(outcome) {
  z <- pre_scales[[outcome]]
  data.frame(
    outcome = outcome, pre_window = "-5:-1",
    winsor_lower_probability = LMV2_P6_SELECTION$pre_outcome_winsorization[[1]],
    winsor_upper_probability = LMV2_P6_SELECTION$pre_outcome_winsorization[[2]],
    lower_value = z$lower, upper_value = z$upper, sigma_pre = z$sd,
    population = "all_eligible_treated_inventors",
    stringsAsFactors = FALSE)
}))

scenarios <- list()
reversals <- list()
for (outcome in c("patent_count", "active_patenting")) {
  h <- headline[headline$outcome == outcome, ]
  sigma_pre <- pre_scales[[outcome]]$sd
  z <- lmv2_p6_common_support_sensitivity(
    h$estimate, coverage, sigma_pre)
  shift <- (1 - coverage) * z$delta * sigma_pre
  z$outcome <- outcome
  z$conditional_ci_low <- h$ci_low + shift
  z$conditional_ci_high <- h$ci_high + shift
  z$inference <- paste0(
    "conditional_on_delta_shift_of_", h$inference)
  scenarios[[outcome]] <- z
  r <- lmv2_p6_common_support_reversal(
    h$estimate, coverage, sigma_pre)
  r$outcome <- outcome
  r$supported_ci_low <- h$ci_low
  r$supported_ci_high <- h$ci_high
  reversals[[outcome]] <- r
}
scenarios <- do.call(rbind, scenarios)
reversals <- do.call(rbind, reversals)

active_h <- headline[headline$outcome == "active_patenting", ]
active_bounds <- data.frame(
  outcome = "active_patenting",
  unsupported_att_lower = -1,
  unsupported_att_upper = 1,
  all_eligible_att_lower =
    coverage * active_h$estimate + (1 - coverage) * (-1),
  all_eligible_att_upper =
    coverage * active_h$estimate + (1 - coverage) * 1,
  support_coverage = coverage,
  interpretation =
    "logical_binary_outcome_bound; does not impose selection_on_observables",
  stringsAsFactors = FALSE)

count_pre_raw <- eligible$patent_count_5y / 5
count_scale <- pre_scales$patent_count
count_pre_winsorized <- pmin(
  pmax(count_pre_raw, count_scale$lower), count_scale$upper)
supported_count_raw <- mean(count_pre_raw[eligible$supported])
unsupported_count_raw <- mean(count_pre_raw[!eligible$supported])
supported_count_winsorized <- mean(
  count_pre_winsorized[eligible$supported])
unsupported_count_winsorized <- mean(
  count_pre_winsorized[!eligible$supported])
count_reversal_row <- reversals[reversals$outcome == "patent_count", ]
count_headline_row <- headline[headline$outcome == "patent_count", ]
pre_productivity_context <- data.frame(
  outcome = "patent_count",
  supported_raw_mean_annual = supported_count_raw,
  unsupported_raw_mean_annual = unsupported_count_raw,
  raw_gap_unsupported_minus_supported =
    unsupported_count_raw - supported_count_raw,
  supported_winsorized_mean_annual = supported_count_winsorized,
  unsupported_winsorized_mean_annual = unsupported_count_winsorized,
  winsorized_gap_unsupported_minus_supported =
    unsupported_count_winsorized - supported_count_winsorized,
  frozen_sigma_pre = count_scale$sd,
  predeal_gap_in_frozen_sd =
    (unsupported_count_winsorized - supported_count_winsorized) /
      count_scale$sd,
  reversal_unsupported_att =
    count_reversal_row$att_unsupported_reversal,
  reversal_effect_gap_unsupported_minus_supported =
    count_reversal_row$att_unsupported_reversal -
      count_headline_row$estimate,
  reversal_effect_gap_in_frozen_sd = count_reversal_row$delta_reversal,
  comparison_note = paste(
    "The pre-deal statistic is a level difference; the reversal statistic",
    "is a treatment-effect difference. The former calibrates plausibility",
    "but does not identify unsupported-tail effect heterogeneity."),
  stringsAsFactors = FALSE)

summary_one <- function(x, variable) {
  groups <- split(x, eligible$supported)
  rows <- lapply(names(groups), function(g) {
    z <- groups[[g]][[variable]]
    data.frame(
      variable = variable,
      support_status = if (g == "TRUE") "supported" else "unsupported",
      n = sum(!is.na(z)), mean = mean(z, na.rm = TRUE),
      sd = stats::sd(z, na.rm = TRUE),
      p10 = stats::quantile(z, 0.10, na.rm = TRUE),
      p25 = stats::quantile(z, 0.25, na.rm = TRUE),
      median = stats::median(z, na.rm = TRUE),
      p75 = stats::quantile(z, 0.75, na.rm = TRUE),
      p90 = stats::quantile(z, 0.90, na.rm = TRUE),
      stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  s <- out[out$support_status == "supported", ]
  u <- out[out$support_status == "unsupported", ]
  pooled_sd <- sqrt((s$sd^2 + u$sd^2) / 2)
  out$smd_supported_minus_unsupported <-
    if (pooled_sd > 0) (s$mean - u$mean) / pooled_sd else NA_real_
  out$unsupported_to_supported_sd <-
    if (s$sd > 0) u$sd / s$sd else NA_real_
  out
}

description_variables <- c(
  "patent_count_5y", "active_pre_years", "log_patent_count_5y",
  "patent_trajectory", "career_age", "focal_group_tenure",
  "focal_group_exclusivity")
descriptives <- do.call(rbind, lapply(
  description_variables, function(v) summary_one(eligible, v)))

exclusion_reasons <- data.frame(
  population = c("eligible", "supported", "unsupported"),
  inventors = c(nrow(eligible), nrow(supported), nrow(unsupported)),
  definition = c(
    "P3 outcome-blind eligible treated-inventor roster",
    "eligible inventor present in certified P5c local-support cover",
    "eligible-minus-supported anti-join: outcome-blind local-support exclusion"),
  stringsAsFactors = FALSE)

write_csv(scale_table, "common_support_preoutcome_scales.csv")
write_csv(descriptives, "common_support_descriptives.csv")
write_csv(
  pre_productivity_context,
  "common_support_predeal_productivity_context.csv")
write_csv(exclusion_reasons, "common_support_exclusion_reasons.csv")
write_csv(scenarios, "common_support_scenario_grid.csv")
write_csv(reversals, "common_support_reversal_thresholds.csv")
write_csv(active_bounds, "common_support_active_logical_bounds.csv")

count_scenarios <- scenarios[scenarios$outcome == "patent_count", ]
plot <- ggplot2::ggplot(
  count_scenarios,
  ggplot2::aes(x = delta, y = att_all)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey45", linewidth = 0.4) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = conditional_ci_low, ymax = conditional_ci_high),
    fill = "#0072B2", alpha = 0.18) +
  ggplot2::geom_line(colour = "#0072B2", linewidth = 0.8) +
  ggplot2::geom_point(colour = "#0072B2", size = 1.8) +
  ggplot2::labs(
    x = expression(delta~"(unsupported effect difference, pre-outcome SDs)"),
    y = "Implied annual ATT for all eligible inventors",
    title = "Common-support sensitivity of the patent-count estimate",
    subtitle = "Intervals are conditional on each assumed unsupported-tail effect") +
  ggplot2::theme_minimal(base_size = 11)
ggplot2::ggsave(
  file.path(OUTPUT_DIR, "figure_common_support_sensitivity.png"),
  plot, width = 7.2, height = 4.6, dpi = 180)

delta_zero <- scenarios[scenarios$delta == 0, ]
certification <- data.frame(
  check = c(
    "extension_freeze_hash_matches", "legacy_selection_freeze_loads",
    "eligible_keys_unique", "supported_keys_unique",
    "supported_is_subset_of_eligible",
    "support_counts_reconcile_to_frozen_coverage",
    "supported_treated_weights_equal_one", "all_18_cohorts_present",
    "unsupported_is_exact_eligible_minus_supported",
    "delta_zero_reproduces_supported_att",
    "conditional_intervals_are_ordered",
    "predeal_productivity_context_is_same_scale",
    "active_logical_bound_is_ordered", "pqii_is_excluded"),
  pass = c(
    TRUE, TRUE, !anyDuplicated(eligible_key), !anyDuplicated(supported_key),
    all(supported_id %in% eligible_id),
    nrow(eligible) == source_eligible &&
      nrow(supported) == source_supported,
    all(abs(supported$weight - 1) <= 1e-12),
    identical(sort(unique(eligible$cohort)), 1993:2010),
    nrow(unsupported) == nrow(eligible) - nrow(supported) &&
      !any(do.call(paste, c(unsupported[c(
        "cohort", "deal_id", "codinv")], sep = ":")) %in% supported_id),
    all(abs(delta_zero$att_all - delta_zero$att_supported) < 1e-12),
    all(scenarios$conditional_ci_low <= scenarios$conditional_ci_high),
    isTRUE(all.equal(
      pre_productivity_context$predeal_gap_in_frozen_sd,
      pre_productivity_context$
        winsorized_gap_unsupported_minus_supported /
        pre_productivity_context$frozen_sigma_pre,
      tolerance = 1e-12)),
    active_bounds$all_eligible_att_lower <=
      active_bounds$all_eligible_att_upper,
    !"pqii_scaled" %in% scenarios$outcome),
  stringsAsFactors = FALSE)
write_csv(certification, "common_support_certification.csv")
if (!all(certification$pass)) {
  stop("Common-support sensitivity certification failed")
}

source_files <- c(
  FREEZE_PATH,
  file.path(BASE, "R", "20a_lmv2_p6_selection_sensitivity_config.R"),
  file.path(BASE, "R", "67_run_lmv2_common_support_sensitivity.R"))
manifest <- data.frame(
  version = VERSION, freeze_sha256 = FREEZE_SHA256,
  source_sha256 = digest::digest(
    vapply(source_files, digest::digest, character(1),
           file = TRUE, algo = "sha256"),
    algo = "sha256", serialize = TRUE),
  roster_sha256 = digest::digest(file = ROSTER_PATH, algo = "sha256"),
  headline_sha256 = digest::digest(file = HEADLINE_PATH, algo = "sha256"),
  eligible_inventors = nrow(eligible),
  supported_inventors = nrow(supported),
  unsupported_inventors = nrow(unsupported),
  support_coverage = coverage,
  certified = all(certification$pass), stringsAsFactors = FALSE)
write_csv(manifest, "common_support_manifest.csv")

count_reversal <- reversals[reversals$outcome == "patent_count", ]
lines <- c(
  "# Full-cohort common-support sensitivity",
  "",
  sprintf(
    "The certified P5c design supports %s of %s eligible treated inventors (%.2f percent).",
    format(nrow(supported), big.mark = ","),
    format(nrow(eligible), big.mark = ","), 100 * coverage),
  sprintf(
    "The unsupported tail would require an average patent-count ATT of +%.3f patents per inventor-year (+%.3f over five years) to set the equally weighted all-eligible-inventor ATT to zero.",
    count_reversal$att_unsupported_reversal,
    5 * count_reversal$att_unsupported_reversal),
  sprintf(
    "On the frozen pre-outcome scale, the reversal threshold is %.3f standard deviations.",
    count_reversal$delta_reversal),
  sprintf(
    "Before treatment, unsupported inventors averaged %.3f patents per year versus %.3f among supported inventors (raw gap %.3f). On the same winsorized scale used for sensitivity calibration, the gap is %.3f patents per year, or %.3f standard deviations.",
    pre_productivity_context$unsupported_raw_mean_annual,
    pre_productivity_context$supported_raw_mean_annual,
    pre_productivity_context$raw_gap_unsupported_minus_supported,
    pre_productivity_context$winsorized_gap_unsupported_minus_supported,
    pre_productivity_context$predeal_gap_in_frozen_sd),
  "The pre-deal comparison is a level difference, whereas the reversal threshold is a treatment-effect difference; it is a plausibility calibration, not a formal bound.",
  "Scenario confidence intervals are conditional on delta. No unsupported-tail outcome is estimated, and PQII is excluded.")
writeLines(lines, file.path(OUTPUT_DIR, "common_support_results.md"))

message("Common-support sensitivity package complete and certified")
