# ============================================================================
# 40d_audit_lmv2_completion_year_window.R
# Completion-year-inclusive sensitivity for the certified full-cohort design.
# ============================================================================
# Purpose:
#   Re-estimate the average post-acquisition contrast over event times 0,...,5
#   without changing the frozen P5c roster, weights, outcomes, or event-study
#   coefficients. The production headline remains event times +1,...,+5.
#
# Inputs:
#   Certified P5c matched event panels produced by P6_P5C_PANEL_COUNT_ACTIVE.
#
# Outputs:
#   A CSV containing the completion-year-inclusive average and cumulative
#   contrasts under the same wild-bootstrap and clustered inference procedures
#   used by the production estimator.

options(stringsAsFactors = FALSE)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_candidates <- c(
  file.path(normalizePath(".", winslash = "/", mustWork = TRUE), ".r_libs"),
  file.path(
    normalizePath(".", winslash = "/", mustWork = TRUE),
    "..", "..", ".r_libs"
  )
)
shared_candidates <- shared_candidates[dir.exists(shared_candidates)]
if (length(shared_candidates)) {
  .libPaths(unique(c(shared_candidates, .libPaths())))
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

input_dir <- file.path(
  BASE, "output", "audit", "local_match_v2",
  "P6_P5C_PANEL_COUNT_ACTIVE"
)
panel_dir <- file.path(input_dir, "panel_matched")
output_dir <- file.path(
  BASE, "output", "audit", "local_match_v2",
  "P6_COMPLETION_YEAR_SENSITIVITY"
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

panel_files <- sort(list.files(
  panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
if (length(panel_files) != length(LMV2_P6_CONFIG$cohorts)) {
  stop("The certified P5c panel bundle is incomplete.")
}

# This is the only estimand change. It is deliberately local to this audit.
LMV2_P6_ESTIMATION$post_window <- 0:5

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'",
  LMV2_P6_ESTIMATION$execution$duckdb_memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", LMV2_P6_ESTIMATION$execution$threads
))

panel_sql <- lmv2_panel_sql(panel_files)
results <- list()

for (sample_id in names(LMV2_P6_ESTIMATION$samples)) {
  cohorts <- LMV2_P6_ESTIMATION$samples[[sample_id]]
  deal_counts <- lmv2_design_deal_counts(con, panel_sql, cohorts)

  for (outcome in LMV2_P6_ESTIMATION$core_outcomes) {
    message("Estimating ", outcome, " / ", sample_id)
    fit <- lmv2_fit_outcome(
      con = con,
      panel_sql = panel_sql,
      outcome = outcome,
      sample_id = sample_id,
      cohorts = cohorts,
      bootstrap_reps = LMV2_P6_ESTIMATION$inference$replications,
      design_deal_counts = deal_counts
    )
    out <- fit$headline
    out$summary <- ifelse(
      grepl("^cumulative_", out$summary),
      "cumulative_t0_to_t5",
      "average_annual_t0_to_t5"
    )
    results[[paste(sample_id, outcome, sep = "::")]] <- out
    checkpoint <- do.call(rbind, results)
    row.names(checkpoint) <- NULL
    utils::write.csv(
      checkpoint,
      file.path(output_dir, "completion_year_inclusive_headline.partial.csv"),
      row.names = FALSE,
      na = ""
    )
  }
}

results <- do.call(rbind, results)
row.names(results) <- NULL
utils::write.csv(
  results,
  file.path(output_dir, "completion_year_inclusive_headline.csv"),
  row.names = FALSE,
  na = ""
)

message("Completion-year sensitivity complete: ", output_dir)
