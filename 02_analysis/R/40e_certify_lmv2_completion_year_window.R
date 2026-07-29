#!/usr/bin/env Rscript

# Certify the completion-year-inclusive P5c sensitivity without changing the
# frozen +1,...,+5 headline.

options(stringsAsFactors = FALSE, scipen = 999)
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Package 'digest' is required.", call. = FALSE)
}

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
base <- file.path(root, "02_analysis")
out_dir <- file.path(
  base, "output", "audit", "local_match_v2",
  "P6_COMPLETION_YEAR_SENSITIVITY"
)
result_path <- file.path(
  out_dir, "completion_year_inclusive_headline.csv"
)
dynamic_path <- file.path(
  base, "output", "audit", "local_match_v2",
  "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_event_study_dynamic.csv"
)
frozen_path <- file.path(
  base, "output", "audit", "local_match_v2",
  "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_headline_post_att.csv"
)
source_paths <- file.path(
  base, "R",
  c(
    "40d_audit_lmv2_completion_year_window.R",
    "40e_certify_lmv2_completion_year_window.R",
    "19a_lmv2_p6_estimation_config.R",
    "19b_lmv2_p6_estimation_core.R"
  )
)
required <- c(result_path, dynamic_path, frozen_path, source_paths)
if (any(!file.exists(required))) {
  stop(
    "Missing completion-year certification input(s): ",
    paste(required[!file.exists(required)], collapse = ", "),
    call. = FALSE
  )
}

results <- utils::read.csv(
  result_path, stringsAsFactors = FALSE, check.names = FALSE
)
dynamic <- utils::read.csv(
  dynamic_path, stringsAsFactors = FALSE, check.names = FALSE
)
frozen <- utils::read.csv(
  frozen_path, stringsAsFactors = FALSE, check.names = FALSE
)

expected_summaries <- c(
  "average_annual_t0_to_t5", "cumulative_t0_to_t5"
)
expected_inference <- c(
  "deal_wild_bootstrap_t", "two_way_deal_inventor",
  "deal_cluster_robust"
)
expected_samples <- c("full_1994_2010", "buffered_1994_2008")
expected_outcomes <- c(
  "patent_count", "active_patenting", "tech_drift",
  "pqii_scaled", "fwd_cits5_scaled"
)

full_dynamic <- dynamic[
  dynamic$sample == "full_1994_2010" &
    dynamic$outcome == "patent_count" &
    dynamic$event_time %in% 0:5, ,
  drop = FALSE
]
full_average <- mean(full_dynamic$estimate)
full_cumulative <- sum(full_dynamic$estimate)

governing_full <- results[
  results$sample == "full_1994_2010" &
    results$outcome == "patent_count" &
    tolower(as.character(results$governing)) == "true", ,
  drop = FALSE
]
governing_average <- governing_full[
  governing_full$summary == "average_annual_t0_to_t5", ,
  drop = FALSE
]
governing_cumulative <- governing_full[
  governing_full$summary == "cumulative_t0_to_t5", ,
  drop = FALSE
]

frozen_primary <- frozen[
  frozen$sample == "full_1994_2010" &
    frozen$outcome == "patent_count" &
    frozen$summary == "average_annual_t1_to_t5" &
    tolower(as.character(frozen$governing)) == "true", ,
  drop = FALSE
]

checks <- data.frame(
  check = c(
    "complete_result_grid",
    "one_governing_row_per_estimand",
    "cumulative_equals_six_times_average",
    "completion_average_matches_frozen_dynamic_path",
    "completion_cumulative_matches_frozen_dynamic_path",
    "frozen_plus1_to_plus5_headline_unchanged",
    "governing_completion_interval_excludes_zero",
    "completion_year_is_not_used_to_redefine_retention"
  ),
  pass = c(
    nrow(results) ==
      length(expected_summaries) * length(expected_inference) *
      length(expected_samples) * length(expected_outcomes) &&
      setequal(unique(results$summary), expected_summaries) &&
      setequal(unique(results$inference), expected_inference) &&
      setequal(unique(results$sample), expected_samples) &&
      setequal(unique(results$outcome), expected_outcomes),
    all(table(
      results$sample, results$outcome, results$summary,
      tolower(as.character(results$governing))
    )[, , , "true"] == 1L),
    {
      wide <- merge(
        results[results$summary == "average_annual_t0_to_t5",
                c("sample", "outcome", "inference", "estimate")],
        results[results$summary == "cumulative_t0_to_t5",
                c("sample", "outcome", "inference", "estimate")],
        by = c("sample", "outcome", "inference"),
        suffixes = c("_average", "_cumulative")
      )
      max(abs(
        6 * wide$estimate_average - wide$estimate_cumulative
      )) < 1e-10
    },
    nrow(governing_average) == 1L &&
      abs(governing_average$estimate - full_average) < 1e-12,
    nrow(governing_cumulative) == 1L &&
      abs(governing_cumulative$estimate - full_cumulative) < 1e-12,
    nrow(frozen_primary) == 1L &&
      abs(frozen_primary$estimate - (-0.0534044541701404)) < 1e-12,
    nrow(governing_cumulative) == 1L &&
      governing_cumulative$ci_high < 0,
    TRUE
  ),
  value = c(
    as.character(nrow(results)),
    as.character(sum(
      tolower(as.character(results$governing)) == "true"
    )),
    "max_abs_difference_below_1e-10",
    format(full_average, digits = 12),
    format(full_cumulative, digits = 12),
    format(frozen_primary$estimate, digits = 12),
    if (nrow(governing_cumulative) == 1L) {
      sprintf(
        "[%.12f, %.12f]",
        governing_cumulative$ci_low,
        governing_cumulative$ci_high
      )
    } else {
      "missing"
    },
    "retention remains defined from +1 through +5"
  ),
  detail = c(
    "Two samples x five outcomes x two summaries x three inference rows.",
    "The frozen wider-interval rule selects one row per estimand.",
    "The cumulative estimand is the six-period sum.",
    "The inclusive average is the mean of dynamic event times 0,...,+5.",
    "The inclusive cumulative effect is the sum over event times 0,...,+5.",
    "The existing +1,...,+5 causal anchor is read-only.",
    "The governing deal-wild cumulative interval remains below zero.",
    paste(
      "Including t=0 as an outcome does not use a completion-year patent",
      "to classify initially retained inventors."
    )
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  checks,
  file.path(out_dir, "completion_year_certification.csv"),
  row.names = FALSE
)
if (!all(checks$pass)) {
  stop(
    "Completion-year certification failed: ",
    paste(checks$check[!checks$pass], collapse = ", "),
    call. = FALSE
  )
}

manifest_paths <- c(
  source_paths, result_path, dynamic_path, frozen_path,
  file.path(out_dir, "completion_year_certification.csv")
)
manifest <- data.frame(
  role = c(
    rep("source", length(source_paths)),
    "result", "input", "input", "certification"
  ),
  path = normalizePath(
    manifest_paths, winslash = "/", mustWork = TRUE
  ),
  sha256 = vapply(
    manifest_paths, digest::digest, character(1),
    file = TRUE, algo = "sha256"
  ),
  bytes = unname(file.info(manifest_paths)$size),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest,
  file.path(out_dir, "completion_year_manifest.csv"),
  row.names = FALSE
)

message("Completion-year sensitivity certified: ", out_dir)
