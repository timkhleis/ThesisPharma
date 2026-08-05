# ============================================================================
# 48e_run_lmv2_transformed_outcomes.R -- dated appendix outcome amendment
# ============================================================================
# Adds two quantity checks without altering the frozen headline outcome set:
# fractional patent applications and log(1 + integer patent applications).

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}
PANEL_DIR <- get_arg("--panel-dir")
CODE_ROOT <- get_arg("--code-root")
OUTPUT_DIR <- get_arg("--output-dir")
SMOKE <- "--smoke" %in% args
if (any(is.na(c(PANEL_DIR, CODE_ROOT, OUTPUT_DIR)))) {
  stop("48e requires --panel-dir=, --code-root=, and --output-dir=")
}
if (!dir.exists(PANEL_DIR) || !dir.exists(CODE_ROOT)) stop("Input directory missing")
if (dir.exists(OUTPUT_DIR) && length(list.files(
  OUTPUT_DIR, all.files = TRUE, no.. = TRUE
))) stop("Output directory must be new or empty: ", OUTPUT_DIR)

BASE <- normalizePath(CODE_ROOT, mustWork = TRUE)
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

amended_outcomes <- data.frame(
  outcome = c("fractional_patent_count", "log1p_patent_count"),
  designation = c("amended_appendix", "amended_appendix"),
  interpretation = c(
    "inventor-team fractional patent applications",
    "log one plus integer patent applications"
  ),
  stringsAsFactors = FALSE
)
LMV2_P6_ESTIMATION$outcomes <- rbind(
  LMV2_P6_ESTIMATION$outcomes, amended_outcomes
)

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
cohorts <- as.integer(sub(
  "^.*_c([0-9]+)\\.parquet$", "\\1", panel_files
))
if (!identical(cohorts, 1993:2010)) stop("Panel cohort set is not 1993:2010")
base_panel_sql <- lmv2_panel_sql(panel_files)
panel_sql <- sprintf(
  "(SELECT *, LN(1.0 + CAST(patent_count AS DOUBLE)) AS log1p_patent_count FROM %s)",
  base_panel_sql
)

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) utils::write.csv(
  x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = ""
)
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", LMV2_P6_ESTIMATION$execution$duckdb_memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", LMV2_P6_ESTIMATION$execution$threads
))
temp_dir <- file.path(OUTPUT_DIR, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))

input_check <- DBI::dbGetQuery(con, sprintf(
  paste0(
    "SELECT COUNT(*) AS panel_rows, ",
    "COUNT(*) FILTER(WHERE fractional_patent_count IS NULL) AS missing_fractional, ",
    "COUNT(*) FILTER(WHERE fractional_patent_count<0) AS negative_fractional, ",
    "COUNT(*) FILTER(WHERE patent_count<0) AS negative_count FROM %s"
  ), panel_sql
))
input_check$pass <- input_check$missing_fractional == 0 &
  input_check$negative_fractional == 0 & input_check$negative_count == 0
if (!isTRUE(input_check$pass[[1]])) stop("Transformed-outcome input gate failed")
write_csv(input_check, "transformed_outcome_input_certification.csv")

bootstrap_reps <- if (SMOKE) 199L else LMV2_P6_ESTIMATION$inference$replications
counts <- lmv2_design_deal_counts(con, panel_sql, cohorts)
fits <- lapply(amended_outcomes$outcome, function(outcome) {
  lmv2_fit_outcome(
    con, panel_sql, outcome, paste0(outcome, "_all18"), cohorts,
    bootstrap_reps, counts
  )
})
for (object in c("dynamic", "pretrend", "headline", "coverage")) {
  write_csv(
    do.call(rbind, lapply(fits, `[[`, object)),
    paste0("transformed_outcome_", object, ".csv")
  )
}

manifest <- data.frame(
  version = "lmv2_transformed_outcomes_v1",
  amendment_date = "2026-08-03",
  run_mode = if (SMOKE) "smoke_nonproduction" else "production",
  outcomes = paste(amended_outcomes$outcome, collapse = ";"),
  reporting_location = "appendix_unconditional",
  changes_frozen_headline = FALSE,
  bootstrap_replications = bootstrap_reps,
  panel_bundle_sha256 = digest::digest(
    vapply(panel_files, tools::md5sum, character(1)),
    algo = "sha256", serialize = TRUE
  ),
  runner_sha256 = digest::digest(
    file = "02_analysis/R/48e_run_lmv2_transformed_outcomes.R",
    algo = "sha256"
  ),
  stringsAsFactors = FALSE
)
write_csv(manifest, "transformed_outcome_manifest.csv")
message("Transformed-outcome robustness complete: ", manifest$run_mode)
