#!/usr/bin/env Rscript

# Re-estimate the certified Local Match v2 outcome family over event times
# +1..+3. The matching roster, cohort weights, reference year, and inference
# are unchanged; only the post-treatment contrast is shortened.

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

LMV2_P6_ESTIMATION$post_window <- 1:3
outcomes <- if (length(outcome_arg)) {
  trimws(strsplit(outcome_arg[[1L]], ",", fixed = TRUE)[[1L]])
} else {
  LMV2_P6_ESTIMATION$core_outcomes
}
if (!length(outcomes) ||
    !all(outcomes %in% LMV2_P6_ESTIMATION$outcomes$outcome)) {
  stop("Requested outcomes are empty or unknown")
}

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
PANEL_DIR <- file.path(ROOT, "P6_BASE", "panel_matched")
P6_MANIFEST <- file.path(ROOT, "P6_BASE", "p6_manifest.csv")
OUT <- file.path(ROOT, if (SMOKE) "P6_SHORT_WINDOW_SMOKE" else "P6_SHORT_WINDOW_T1_T3")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$", full.names = TRUE
))
stamp_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$", full.names = TRUE
))
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}

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
write_csv(checks, "short_window_input_certification.csv")
panel_sql <- lmv2_panel_sql(panel_files)
cohorts <- if (SMOKE) 1993:1995 else 1993:2010
sample_id <- if (SMOKE) "smoke_1993_1995" else "full_1993_2010"
reps <- if (SMOKE) 199L else LMV2_P6_ESTIMATION$inference$replications
deal_counts <- lmv2_design_deal_counts(con, panel_sql, cohorts)

headline <- list()
pretrend <- list()
coverage <- list()
for (i in seq_along(outcomes)) {
  outcome <- outcomes[[i]]
  message(sprintf("[%d/%d] short window | %s", i, length(outcomes), outcome))
  fit <- lmv2_fit_outcome(
    con, panel_sql, outcome, sample_id, cohorts, reps, deal_counts
  )
  z <- fit$headline
  z$summary[z$summary == "average_annual_t1_to_t5"] <- "average_annual_t1_to_t3"
  z$summary[z$summary == "cumulative_t1_to_t5"] <- "cumulative_t1_to_t3"
  headline[[i]] <- z
  pretrend[[i]] <- fit$pretrend
  coverage[[i]] <- fit$coverage
  rm(fit)
  gc()
}

headline <- do.call(rbind, headline)
pretrend <- do.call(rbind, pretrend)
coverage <- do.call(rbind, coverage)
write_csv(headline, "short_window_headline.csv")
write_csv(pretrend, "short_window_pretrend.csv")
write_csv(coverage, "short_window_pair_coverage.csv")

cert <- data.frame(
  check = c(
    "input_certification", "post_window_is_1_to_3",
    "contains_1993", "all_outcomes_completed"
  ),
  pass = c(
    isTRUE(checks$pass[[1L]]),
    identical(LMV2_P6_ESTIMATION$post_window, 1:3),
    1993L %in% cohorts,
    length(unique(headline$outcome)) == length(outcomes)
  ),
  note = c(
    "certified P6 panel and stamps", "1;2;3",
    paste(range(cohorts), collapse = "--"), paste(outcomes, collapse = ";")
  )
)
write_csv(cert, "short_window_certification.csv")
message("Short-window package written to: ", OUT)
if (!SMOKE && !all(cert$pass)) quit(status = 1L)
