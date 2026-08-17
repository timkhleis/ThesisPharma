# ============================================================================
# 12a_verginer_ebal_config.R -- Verginer-variable entropy balancing constants
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()

DESIGN_VERSION <- "verginer_ebal_v1"

CONTROL_GROUP <- "notyettreated"
EVENT_LO <- -5L
EVENT_HI <- 5L
EVENT_WINDOW <- EVENT_LO:EVENT_HI
TREATMENT_YEAR <- "treatment_year"
SAMPLE <- "merged_sample"
ANTICIPATION <- 0L
BASE_PERIOD <- "varying"

OUTCOMES <- c("log1p_patents", "log1p_citations", "vr_rd_activity", "vr_left")
OUTCOME_LABELS <- c(
  log1p_patents = "Log(1 + patents)",
  log1p_citations = "Log(1 + OECD five-year forward citations)",
  vr_rd_activity = "R&D activity (forward-looking)",
  vr_left = "Left merged entity (forward-looking)"
)
PAPER_BENCHMARKS <- c(
  log1p_patents = -0.136,
  log1p_citations = -0.350,
  vr_rd_activity = -0.063,
  vr_left = 0.135
)

VR_RAW_COVARS <- c("vr_age", "vr_tenure", "vr_exclusivity", "vr_common_ipc")
VR_LOGCAT_RHS <- ~ log_vr_age + log_vr_tenure + vr_exclusivity + factor(vr_common_ipc_cat)
VR_RAW_RHS <- ~ vr_age + vr_tenure + vr_exclusivity + vr_common_ipc

EXPECTED_N_INVENTORS <- 29533L
EXPECTED_N_DEALS <- 348L
CELL_EQUIVALENCE_TOL <- 1e-8
CELL_EQUIVALENCE_STRICT_TOL <- 1e-10
BALANCE_TOL <- 1e-6
NUMERICAL_ACCEPTANCE_TOL <- 1e-3
SOLVER_RESIDUAL_TOL <- NUMERICAL_ACCEPTANCE_TOL
LARGE_RESIDUAL_TOL <- NUMERICAL_ACCEPTANCE_TOL
EBAL_MAXIT <- 100000L
BOOTSTRAP_DEVELOPMENT <- 199L
BOOTSTRAP_FINAL <- 999L
BOOTSTRAP_SUCCESS_MIN <- 0.95
SEED <- 20260720L

DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
DERIVED_DIR <- file.path(BASE, "output", "parquet", "derived", "verginer_ebal")
AUDIT_DIR <- file.path(BASE, "output", "audit", "verginer_ebal")
RESULTS_DIR <- file.path(BASE, "output", "results", "verginer_ebal")
FIGS_DIR <- file.path(BASE, "output", "figures", "verginer_ebal")
NOTES_DIR <- file.path(BASE, "notes")
for (d in c(DERIVED_DIR, AUDIT_DIR, RESULTS_DIR, FIGS_DIR, NOTES_DIR)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

COVARIATES_PARQUET <- file.path(DERIVED_DIR, "verginer_ebal_covariates.parquet")
PANEL_PARQUET <- file.path(DERIVED_DIR, "verginer_ebal_panel_complete_case.parquet")
UNITS_PARQUET <- file.path(DERIVED_DIR, "verginer_ebal_units_complete_case.parquet")
CHECKPOINT_NOTE <- file.path(NOTES_DIR, "verginer_ebal_checkpoint.md")
DESIGN_DECISION_NOTE <- file.path(NOTES_DIR, "verginer_ebal_design_decision_checkpoint.md")

required_packages_12 <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0L) {
    stop("Missing required package(s): ", paste(missing, collapse = ", "))
  }
  invisible(TRUE)
}

sql_path_12 <- function(path) {
  gsub("\\\\", "/", normalizePath(path, winslash = "/", mustWork = FALSE))
}

connect_thesis_readonly <- function() {
  required_packages_12(c("DBI", "duckdb"))
  con <- DBI::dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
  try(DBI::dbExecute(con, "PRAGMA memory_limit='10GB'"), silent = TRUE)
  try(DBI::dbExecute(con, "PRAGMA threads=4"), silent = TRUE)
  con
}

write_audit_12 <- function(df, name) {
  df <- as.data.frame(df)
  df <- cbind(design_version = rep(DESIGN_VERSION, nrow(df)), df)
  utils::write.csv(df, file.path(AUDIT_DIR, name), row.names = FALSE, na = "")
  invisible(file.path(AUDIT_DIR, name))
}

write_result_12 <- function(df, name) {
  df <- as.data.frame(df)
  df <- cbind(design_version = rep(DESIGN_VERSION, nrow(df)), df)
  utils::write.csv(df, file.path(RESULTS_DIR, name), row.names = FALSE, na = "")
  invisible(file.path(RESULTS_DIR, name))
}

read_parquet_12 <- function(path) {
  required_packages_12(c("DBI", "duckdb"))
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", sql_path_12(path)))
}

write_parquet_12 <- function(df, path) {
  required_packages_12(c("DBI", "duckdb"))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "to_write", df, overwrite = TRUE)
  DBI::dbExecute(con, sprintf(
    "COPY to_write TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
    sql_path_12(path)
  ))
  invisible(path)
}

banner_12 <- function(x) {
  message("\n", strrep("=", 76), "\n== ", x, "\n", strrep("=", 76))
}

section_12 <- function(x) message("\n-- ", x)

run_mode_12 <- function(args = commandArgs(trailingOnly = TRUE)) {
  if ("--final" %in% args) "FINAL" else "DEVELOPMENT"
}

bootstrap_iters_12 <- function(mode) {
  if (identical(mode, "FINAL")) BOOTSTRAP_FINAL else BOOTSTRAP_DEVELOPMENT
}

invisible(DESIGN_VERSION)
