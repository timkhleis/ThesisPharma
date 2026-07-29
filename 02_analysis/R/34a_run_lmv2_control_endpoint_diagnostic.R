#!/usr/bin/env Rscript

# ============================================================================
# 34a_run_lmv2_control_endpoint_diagnostic.R
#
# C1 diagnostic: re-estimate the frozen full-cohort patent-count contrast
# after excluding P5c control units whose focal group exits the patent record
# before g+5. The treated roster and its weights are unchanged. This is a
# post-window, sample-definition diagnostic and never replaces the frozen
# P5c headline.
# ============================================================================

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
required <- c(
  "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng"
)
for (pkg in required) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

if (!identical(
  as.character(utils::packageVersion("fwildclusterboot")),
  LMV2_P6_ESTIMATION$inference$package_version
)) {
  stop("fwildclusterboot version differs from the frozen P6 version")
}

AUDIT <- file.path(BASE, "output", "audit", "local_match_v2")
RESULTS <- file.path(BASE, "output", "results", "local_match_v2")
PANEL_DIR <- file.path(
  AUDIT, "P6_P5C_PANEL_COUNT_ACTIVE", "panel_matched"
)
P6_MANIFEST <- file.path(
  AUDIT, "P6_P5C_PANEL_COUNT_ACTIVE", "p6_manifest.csv"
)
PRIMARY_HEADLINE <- file.path(
  AUDIT, "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_headline_post_att.csv"
)
PRIMARY_DYNAMIC <- file.path(
  AUDIT, "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_event_study_dynamic.csv"
)
RETAINED_HEADLINE <- file.path(
  RESULTS, "stayer_heterogeneity", "table_stayer_aggregate_effects.csv"
)
OUTPUT_DIR <- file.path(AUDIT, "C1_CONTROL_ENDPOINT_DIAGNOSTIC")
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

input_paths <- c(
  p6_manifest = P6_MANIFEST,
  primary_headline = PRIMARY_HEADLINE,
  primary_dynamic = PRIMARY_DYNAMIC,
  retained_headline = RETAINED_HEADLINE
)
missing_inputs <- input_paths[!file.exists(input_paths)]
if (length(missing_inputs)) {
  stop("Missing input(s): ", paste(missing_inputs, collapse = ", "))
}

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
stamp_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$",
  full.names = TRUE
))
if (!length(panel_files) || !length(stamp_files)) {
  stop("Certified P5c panel shards or stamps are missing")
}

write_csv <- function(x, name) {
  utils::write.csv(
    x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = ""
  )
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'",
  LMV2_P6_ESTIMATION$execution$duckdb_memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", LMV2_P6_ESTIMATION$execution$threads
))
temp_dir <- file.path(OUTPUT_DIR, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))

# Re-run the frozen input certification before applying the diagnostic filter.
input_certification <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, P6_MANIFEST
)
write_csv(input_certification, "control_endpoint_input_certification.csv")

raw_panel_sql <- lmv2_panel_sql(panel_files)
filtered_panel_sql <- paste0(
  "(SELECT * FROM ", raw_panel_sql, " WHERE arm='treated' OR ",
  "NOT COALESCE(control_firm_exits_before_g_plus_5, FALSE))"
)

unit_audit <- DBI::dbGetQuery(con, sprintf("
  WITH p AS (
    SELECT roster_row_id, arm, weight,
           MIN(COALESCE(control_firm_exits_before_g_plus_5, FALSE)::INTEGER)
             AS min_exit,
           MAX(COALESCE(control_firm_exits_before_g_plus_5, FALSE)::INTEGER)
             AS max_exit
    FROM %s
    GROUP BY roster_row_id, arm, weight
  )
  SELECT
    COUNT(*) AS units_before,
    COUNT(*) FILTER (WHERE arm='treated') AS treated_units_before,
    COUNT(*) FILTER (WHERE arm='control') AS control_units_before,
    COUNT(*) FILTER (
      WHERE arm='control' AND max_exit=0
    ) AS control_units_after,
    COUNT(*) FILTER (
      WHERE arm='control' AND max_exit=1
    ) AS control_units_removed,
    SUM(weight) FILTER (WHERE arm='control') AS control_weight_before,
    SUM(weight) FILTER (
      WHERE arm='control' AND max_exit=0
    ) AS control_weight_after,
    COUNT(*) FILTER (WHERE min_exit<>max_exit) AS nonconstant_unit_flags,
    COUNT(*) FILTER (
      WHERE arm='treated' AND max_exit<>0
    ) AS treated_flagged
  FROM p
", raw_panel_sql))
write_csv(unit_audit, "control_endpoint_unit_audit.csv")

cohort_audit <- DBI::dbGetQuery(con, sprintf("
  WITH p AS (
    SELECT cohort, roster_row_id, arm, MAX(weight) AS weight,
           MAX(COALESCE(
             control_firm_exits_before_g_plus_5, FALSE
           )::INTEGER) AS exits
    FROM %s
    GROUP BY cohort, roster_row_id, arm
  )
  SELECT cohort,
    COUNT(*) FILTER (WHERE arm='treated') AS treated_units,
    COUNT(*) FILTER (WHERE arm='control') AS control_units_before,
    COUNT(*) FILTER (
      WHERE arm='control' AND exits=0
    ) AS control_units_after,
    SUM(weight) FILTER (WHERE arm='control') AS control_weight_before,
    SUM(weight) FILTER (
      WHERE arm='control' AND exits=0
    ) AS control_weight_after
  FROM p
  GROUP BY cohort
  ORDER BY cohort
", raw_panel_sql))
cohort_audit$control_unit_retention_share <-
  cohort_audit$control_units_after / cohort_audit$control_units_before
cohort_audit$control_weight_retention_share <-
  cohort_audit$control_weight_after / cohort_audit$control_weight_before
write_csv(cohort_audit, "control_endpoint_cohort_audit.csv")

# The diagnostic intentionally preserves the frozen P5c entropy weights. It
# does not re-solve the balancing problem after controls are removed. Quantify
# the resulting residual imbalance so this sample restriction cannot be
# mistaken for a newly balanced design.
balance_audit <- DBI::dbGetQuery(con, sprintf("
  WITH long_panel AS (
    SELECT event_time, arm, weight, 'patent_count' AS outcome,
           patent_count::DOUBLE AS y
    FROM %1$s
    WHERE event_time BETWEEN -5 AND -1
    UNION ALL
    SELECT event_time, arm, weight, 'active_patenting' AS outcome,
           active_patenting::DOUBLE AS y
    FROM %1$s
    WHERE event_time BETWEEN -5 AND -1
  ),
  arm_moments AS (
    SELECT outcome, event_time, arm,
           SUM(weight) AS weight_sum,
           SUM(weight * y) / SUM(weight) AS weighted_mean,
           GREATEST(
             SUM(weight * y * y) / SUM(weight) -
               POWER(SUM(weight * y) / SUM(weight), 2),
             0
           ) AS weighted_variance
    FROM long_panel
    GROUP BY outcome, event_time, arm
  )
  SELECT outcome, event_time,
         MAX(weight_sum) FILTER (WHERE arm='treated') AS treated_weight,
         MAX(weight_sum) FILTER (WHERE arm='control') AS control_weight,
         MAX(weighted_mean) FILTER (WHERE arm='treated') AS treated_mean,
         MAX(weighted_mean) FILTER (WHERE arm='control') AS control_mean,
         MAX(weighted_mean) FILTER (WHERE arm='treated') -
           MAX(weighted_mean) FILTER (WHERE arm='control') AS residual_gap,
         SQRT((
           MAX(weighted_variance) FILTER (WHERE arm='treated') +
           MAX(weighted_variance) FILTER (WHERE arm='control')
         ) / 2) AS pooled_sd,
         CASE
           WHEN SQRT((
             MAX(weighted_variance) FILTER (WHERE arm='treated') +
             MAX(weighted_variance) FILTER (WHERE arm='control')
           ) / 2) > 0
           THEN (
             MAX(weighted_mean) FILTER (WHERE arm='treated') -
             MAX(weighted_mean) FILTER (WHERE arm='control')
           ) / SQRT((
             MAX(weighted_variance) FILTER (WHERE arm='treated') +
             MAX(weighted_variance) FILTER (WHERE arm='control')
           ) / 2)
           ELSE NULL
         END AS residual_smd
  FROM arm_moments
  GROUP BY outcome, event_time
  ORDER BY outcome, event_time
", filtered_panel_sql))
write_csv(balance_audit, "control_endpoint_balance_audit.csv")
max_abs_residual_smd <- max(
  abs(balance_audit$residual_smd), na.rm = TRUE
)

sample_id <- "full_1994_2010_control_group_active_through_g_plus_5"
cohorts <- LMV2_P6_ESTIMATION$samples$full_1994_2010
deal_counts <- lmv2_design_deal_counts(
  con, filtered_panel_sql, cohorts
)
fitted <- lmv2_fit_outcome(
  con = con,
  panel_sql = filtered_panel_sql,
  outcome = "patent_count",
  sample_id = sample_id,
  cohorts = cohorts,
  bootstrap_reps = LMV2_P6_ESTIMATION$inference$replications,
  design_deal_counts = deal_counts
)

write_csv(fitted$dynamic, "control_endpoint_dynamic.csv")
write_csv(fitted$pretrend, "control_endpoint_pretrend.csv")
write_csv(fitted$headline, "control_endpoint_headline.csv")
write_csv(fitted$coverage, "control_endpoint_coverage.csv")

primary_dynamic <- utils::read.csv(
  PRIMARY_DYNAMIC, stringsAsFactors = FALSE, check.names = FALSE
)
primary_dynamic <- primary_dynamic[
  primary_dynamic$outcome == "patent_count" &
    primary_dynamic$sample == "full_1994_2010", ,
  drop = FALSE
]
diagnostic_dynamic <- fitted$dynamic[
  fitted$dynamic$outcome == "patent_count", ,
  drop = FALSE
]
if (
  nrow(primary_dynamic) != 11L ||
    nrow(diagnostic_dynamic) != 11L ||
    !identical(primary_dynamic$event_time, diagnostic_dynamic$event_time)
) {
  stop("Expected aligned frozen and diagnostic event-time paths from -5 to +5")
}
dynamic_comparison <- data.frame(
  event_time = primary_dynamic$event_time,
  frozen_estimate = primary_dynamic$estimate,
  frozen_se = primary_dynamic$se,
  frozen_df = primary_dynamic$df,
  frozen_ci_low = primary_dynamic$ci_low,
  frozen_ci_high = primary_dynamic$ci_high,
  diagnostic_estimate = diagnostic_dynamic$estimate,
  diagnostic_se = diagnostic_dynamic$se,
  diagnostic_df = diagnostic_dynamic$df,
  diagnostic_ci_low = diagnostic_dynamic$ci_low,
  diagnostic_ci_high = diagnostic_dynamic$ci_high,
  stringsAsFactors = FALSE
)
write_csv(dynamic_comparison, "control_endpoint_dynamic_comparison.csv")

primary <- utils::read.csv(
  PRIMARY_HEADLINE, stringsAsFactors = FALSE, check.names = FALSE
)
primary <- primary[
  primary$outcome == "patent_count" &
    primary$sample == "full_1994_2010" &
    primary$summary == "average_annual_t1_to_t5" &
    primary$governing, ,
  drop = FALSE
]
if (nrow(primary) != 1L) {
  stop("Expected exactly one governing frozen P5c patent-count headline")
}

diagnostic <- fitted$headline[
  fitted$headline$summary == "average_annual_t1_to_t5" &
    fitted$headline$governing, ,
  drop = FALSE
]
if (nrow(diagnostic) != 1L) {
  stop("Expected exactly one governing endpoint-filter diagnostic")
}

retained <- utils::read.csv(
  RETAINED_HEADLINE, stringsAsFactors = FALSE, check.names = FALSE
)
retained <- retained[
  retained$outcome == "patent_count" &
    retained$sample == "full_1994_2010" &
    retained$inference == "two_way_deal_inventor", ,
  drop = FALSE
]
if (nrow(retained) != 1L) {
  stop("Expected exactly one retained two-way patent-count headline")
}

comparison <- data.frame(
  specification = c(
    "frozen_full_cohort_p5c",
    "full_cohort_control_group_active_through_g_plus_5",
    "initially_retained_selected_group"
  ),
  estimate = c(
    primary$estimate, diagnostic$estimate, retained$estimate
  ),
  ci_low = c(primary$ci_low, diagnostic$ci_low, retained$ci_low),
  ci_high = c(primary$ci_high, diagnostic$ci_high, retained$ci_high),
  p_value = c(primary$p_value, diagnostic$p_value, retained$p_value),
  inference = c(
    primary$inference, diagnostic$inference, retained$inference
  ),
  role = c("primary", "diagnostic", "selected_group_companion"),
  stringsAsFactors = FALSE
)
comparison$distance_to_retained <- retained$estimate - comparison$estimate
comparison$share_of_primary_retained_gap_closed <- c(
  0,
  (diagnostic$estimate - primary$estimate) /
    (retained$estimate - primary$estimate),
  1
)
write_csv(comparison, "control_endpoint_comparison.csv")

post_path <- dynamic_comparison[
  dynamic_comparison$event_time %in% 1:5, , drop = FALSE
]
post_path <- post_path[order(post_path$event_time), , drop = FALSE]
frozen_monotone_attenuation <- all(
  diff(abs(post_path$frozen_estimate)) <= 1e-12
)
diagnostic_monotone_attenuation <- all(
  diff(abs(post_path$diagnostic_estimate)) <= 1e-12
)

checks <- data.frame(
  check = c(
    "upstream_input_certification_passes",
    "unit_flag_constant",
    "treated_roster_unchanged",
    "filter_removes_controls",
    "remaining_control_weight_positive_each_cohort",
    "diagnostic_estimate_finite",
    "entropy_weights_resolved_on_restricted_pool",
    "restricted_pool_max_abs_preperiod_smd_reported",
    "restricted_negative_period_gaps_are_not_LOYO",
    "frozen_post_path_attenuates_monotonically",
    "diagnostic_post_path_attenuates_monotonically",
    "frozen_primary_estimate_unchanged",
    "retained_estimate_unchanged",
    "comparison_roles_are_distinct"
  ),
  pass = c(
    isTRUE(input_certification$pass[[1]]),
    unit_audit$nonconstant_unit_flags[[1]] == 0,
    unit_audit$treated_flagged[[1]] == 0,
    unit_audit$control_units_removed[[1]] > 0 &&
      unit_audit$control_units_after[[1]] > 0,
    all(
      is.finite(cohort_audit$control_weight_after) &
        cohort_audit$control_weight_after > 0
    ),
    all(is.finite(unlist(
      diagnostic[c("estimate", "ci_low", "ci_high", "p_value")]
    ))),
    TRUE,
    is.finite(max_abs_residual_smd),
    TRUE,
    frozen_monotone_attenuation,
    diagnostic_monotone_attenuation,
    abs(primary$estimate[[1]] - (-0.0534044541701404)) < 1e-12,
    abs(retained$estimate[[1]] - (-0.107230613905157)) < 1e-10,
    identical(
      comparison$role,
      c("primary", "diagnostic", "selected_group_companion")
    )
  ),
  value = c(
    as.character(input_certification$pass[[1]]),
    as.character(unit_audit$nonconstant_unit_flags[[1]]),
    as.character(unit_audit$treated_flagged[[1]]),
    as.character(unit_audit$control_units_removed[[1]]),
    format(min(cohort_audit$control_weight_after), digits = 12),
    format(diagnostic$estimate[[1]], digits = 12),
    "FALSE",
    format(max_abs_residual_smd, digits = 12),
    "TRUE",
    as.character(frozen_monotone_attenuation),
    as.character(diagnostic_monotone_attenuation),
    format(primary$estimate[[1]], digits = 12),
    format(retained$estimate[[1]], digits = 12),
    paste(comparison$role, collapse = ";")
  ),
  detail = c(
    "Frozen P5c shards certified before filtering.",
    "Endpoint flag must be constant within roster unit.",
    "The endpoint filter applies to controls only.",
    "Diagnostic must differ in support from frozen P5c.",
    "Every cohort retains positive control weight.",
    "Endpoint-filter estimate and inference are finite.",
    paste(
      "Expected FALSE: the diagnostic reuses frozen P5c entropy weights",
      "after filtering controls; it is not a newly balanced design."
    ),
    paste(
      "Maximum absolute residual SMD across patent count and active",
      "patenting at t=-5,...,-1 is recorded in the balance audit."
    ),
    paste(
      "No restricted-pool LOYO was run. Negative-period differences are",
      "residual imbalances after filtering, not held-out validation gaps."
    ),
    "Absolute patent-count effects weakly decline from t=+1 to t=+5.",
    "Absolute patent-count effects weakly decline from t=+1 to t=+5.",
    "Frozen P5c result is read-only.",
    "Frozen retained result is read-only.",
    "Diagnostic cannot replace either existing estimand."
  ),
  stringsAsFactors = FALSE
)
write_csv(checks, "control_endpoint_certification.csv")
if (!all(checks$pass)) {
  stop(
    "Control-endpoint diagnostic certification failed: ",
    paste(checks$check[!checks$pass], collapse = ", ")
  )
}

source_files <- file.path(BASE, "R", c(
  "18a_lmv2_outcome_config.R",
  "19a_lmv2_p6_estimation_config.R",
  "19b_lmv2_p6_estimation_core.R",
  "34a_run_lmv2_control_endpoint_diagnostic.R"
))
artifact_files <- file.path(OUTPUT_DIR, c(
  "control_endpoint_input_certification.csv",
  "control_endpoint_unit_audit.csv",
  "control_endpoint_cohort_audit.csv",
  "control_endpoint_balance_audit.csv",
  "control_endpoint_dynamic.csv",
  "control_endpoint_dynamic_comparison.csv",
  "control_endpoint_pretrend.csv",
  "control_endpoint_headline.csv",
  "control_endpoint_coverage.csv",
  "control_endpoint_comparison.csv",
  "control_endpoint_certification.csv"
))
manifest_paths <- c(
  source_files, input_paths, panel_files, stamp_files, artifact_files
)
manifest <- data.frame(
  role = c(
    rep("source", length(source_files)),
    rep("input", length(input_paths) + length(panel_files) +
          length(stamp_files)),
    rep("artifact", length(artifact_files))
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
write_csv(manifest, "control_endpoint_manifest.csv")

message(
  "C1 control-endpoint diagnostic certified: ",
  normalizePath(OUTPUT_DIR, winslash = "/", mustWork = TRUE)
)
