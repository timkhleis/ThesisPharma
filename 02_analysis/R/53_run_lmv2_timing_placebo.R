#!/usr/bin/env Rscript

# Outcome-blind timing falsification for a treatment date shifted three years
# early. With pseudo-treatment g-3, pseudo event times +1 and +2 equal true
# event times -2 and -1. True event time -4 is the pseudo -1 reference. The
# requested +3 late shift is not estimated: its pre/post comparison contains
# years after the real acquisition and therefore is not a valid placebo.

options(stringsAsFactors = FALSE, scipen = 999)
args <- commandArgs(trailingOnly = TRUE)
SMOKE <- "--smoke" %in% args
outcome_arg <- sub(
  "^--outcomes=", "", grep("^--outcomes=", args, value = TRUE)
)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

LMV2_P6_ESTIMATION$reference_event_time <- -4L
LMV2_P6_ESTIMATION$pretrend_window <- -5L
LMV2_P6_ESTIMATION$post_window <- -2:-1
outcomes <- if (length(outcome_arg)) {
  trimws(strsplit(outcome_arg[[1L]], ",", fixed = TRUE)[[1L]])
} else c("patent_count", "active_patenting")
if (!length(outcomes) ||
    !all(outcomes %in% LMV2_P6_ESTIMATION$outcomes$outcome)) {
  stop("Requested outcomes are empty or unknown")
}

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
PANEL_DIR <- file.path(ROOT, "P6_BASE", "panel_matched")
P6_MANIFEST <- file.path(ROOT, "P6_BASE", "p6_manifest.csv")
OUT <- file.path(ROOT, if (SMOKE) "TIMING_PLACEBO_SMOKE" else "TIMING_PLACEBO_EARLY3")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$", full.names = TRUE
))
stamp_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$", full.names = TRUE
))
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", LMV2_P6_ESTIMATION$execution$threads
))
temp_dir <- file.path(OUT, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))

checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, P6_MANIFEST
)
panel_sql <- lmv2_panel_sql(panel_files)
cohorts <- if (SMOKE) 1993:1995 else 1993:2010
sample_id <- if (SMOKE) "smoke_1993_1995" else "full_1993_2010"
reps <- if (SMOKE) 199L else LMV2_P6_ESTIMATION$inference$replications
deal_counts <- lmv2_design_deal_counts(con, panel_sql, cohorts)

headline <- list()
dynamic <- list()
for (i in seq_along(outcomes)) {
  outcome <- outcomes[[i]]
  message(sprintf("[%d/%d] early timing placebo | %s", i, length(outcomes), outcome))
  fit <- lmv2_fit_outcome(
    con, panel_sql, outcome, sample_id, cohorts, reps, deal_counts
  )
  z <- fit$headline
  z$summary[z$summary == "average_annual_t1_to_t5"] <-
    "pseudo_average_gminus2_gminus1"
  z$summary[z$summary == "cumulative_t1_to_t5"] <-
    "pseudo_cumulative_gminus2_gminus1"
  z$pseudo_treatment_shift <- -3L
  z$pseudo_reference_true_event_time <- -4L
  headline[[i]] <- z
  d <- fit$dynamic
  d$pseudo_event_time <- d$event_time + 3L
  dynamic[[i]] <- d
  rm(fit)
  gc()
}
headline <- do.call(rbind, headline)
dynamic <- do.call(rbind, dynamic)
write_csv(headline, "timing_placebo_headline.csv")
write_csv(dynamic, "timing_placebo_dynamic.csv")

late_design <- data.frame(
  requested_shift = 3L,
  status = "not_estimated_invalid_placebo",
  reason = paste(
    "A g+3 pseudo-treatment uses observations after the real acquisition",
    "as its pre-period and cannot test absence of an acquisition effect."
  )
)
write_csv(late_design, "timing_placebo_late3_design_decision.csv")
cert <- data.frame(
  check = c(
    "input_certification", "contains_1993", "early_shift_is_minus3",
    "early_pseudo_post_is_strictly_pretreatment",
    "late_shift_not_misreported_as_placebo", "all_outcomes_completed"
  ),
  pass = c(
    isTRUE(checks$pass[[1L]]), 1993L %in% cohorts, TRUE,
    all(LMV2_P6_ESTIMATION$post_window < 0),
    identical(late_design$status, "not_estimated_invalid_placebo"),
    length(unique(headline$outcome)) == length(outcomes)
  ),
  note = c(
    "certified P6 panel", paste(range(cohorts), collapse = "--"),
    "pseudo treatment g-3", "true event times -2 and -1",
    late_design$reason, paste(outcomes, collapse = ";")
  )
)
write_csv(cert, "timing_placebo_certification.csv")
message("Timing-placebo package written to: ", OUT)
if (!SMOKE && !all(cert$pass)) quit(status = 1L)
