# ============================================================================
# 48d_materialize_lmv2_sensitivity_superset.R
# ============================================================================
# Materializes outcomes once for the union of all pre-solved cohort-2000
# dependence-sensitivity rosters. The union is deduplicated at the conceptual
# unit level; downstream estimators join each specification's weights by
# (deal, arm, inventor, focal group). This is necessary because re-solving the
# design introduces valid donors absent from the frozen headline roster.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}

DB_PATH <- get_arg("--db")
CODE_ROOT <- get_arg("--code-root")
P4_ROOT <- get_arg("--p4-root")
SENSITIVITY_ROOT <- get_arg("--sensitivity-root")
REFIT_ROOT <- get_arg("--refit-root")
BASE_STAMP <- get_arg("--base-stamp")
OUTPUT_DIR <- get_arg("--output-dir")
if (any(is.na(c(
    DB_PATH, CODE_ROOT, P4_ROOT, SENSITIVITY_ROOT, REFIT_ROOT,
    BASE_STAMP, OUTPUT_DIR)))) {
  stop(paste0(
    "48d requires --db=, --code-root=, --p4-root=, ",
    "--sensitivity-root=, --refit-root=, --base-stamp=, --output-dir="))
}
for (path in c(
    DB_PATH, CODE_ROOT, P4_ROOT, SENSITIVITY_ROOT, REFIT_ROOT, BASE_STAMP)) {
  if (!file.exists(path) && !dir.exists(path)) stop("Input not found: ", path)
}
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
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "18c_materialize_lmv2_outcome_panel.R"))

one_file <- function(path, label) {
  hit <- Sys.glob(path)
  if (length(hit) != 1L) stop(label, " expected one file; found ", length(hit))
  normalizePath(hit, winslash = "/", mustWork = TRUE)
}
weight_files <- c(
  no_deal70 = one_file(file.path(
    SENSITIVITY_ROOT, "N", "weights", "main",
    "weights_2000_primary_*.parquet"
  ), "no_deal70"),
  omit_henkel = one_file(file.path(
    SENSITIVITY_ROOT, "H", "weights", "main",
    "weights_2000_primary_*.parquet"
  ), "omit_henkel")
)
refit_dirs <- sort(list.dirs(
  REFIT_ROOT, recursive = FALSE,
  full.names = TRUE
))
for (refit_dir in refit_dirs) {
  status_path <- file.path(refit_dir, "deal70_refit_status.csv")
  if (!file.exists(status_path)) next
  status <- utils::read.csv(status_path, stringsAsFactors = FALSE)
  if (nrow(status) != 1L || identical(status$mode[[1]], "infeasible")) next
  firm <- as.character(status$omitted_control_group[[1]])
  weight_files[[paste0("omit_firm_", firm)]] <- one_file(file.path(
    refit_dir, "weights", "main", "weights_2000_primary_*.parquet"
  ), paste0("omit_firm_", firm))
}
if (length(weight_files) != 10L) stop("Expected 10 feasible sensitivity rosters")

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
panel_dir <- file.path(OUTPUT_DIR, "panel_matched")
dir.create(panel_dir, showWarnings = FALSE)
profile_dir <- file.path(OUTPUT_DIR, "profiles")

con <- DBI::dbConnect(
  duckdb::duckdb(), normalizePath(DB_PATH, winslash = "/", mustWork = TRUE),
  read_only = TRUE
)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
quote_path <- function(path) as.character(DBI::dbQuoteString(con, path))

weight_union <- paste(vapply(seq_along(weight_files), function(i) sprintf(
  "SELECT %s AS specification, * FROM read_parquet(%s)",
  DBI::dbQuoteString(con, names(weight_files)[[i]]),
  quote_path(weight_files[[i]])
), character(1)), collapse = " UNION ALL ")

DBI::dbExecute(con, sprintf(
  paste0(
    "CREATE OR REPLACE TEMP TABLE robustness_sensitivity_roster AS ",
    "WITH weights AS (%1$s), mapped AS (SELECT ",
    "CAST(w.deal_id AS BIGINT) deal_id, CAST(w.cohort AS INTEGER) cohort, ",
    "CASE WHEN w.treated=1 THEN 'treated' ELSE 'control' END arm, ",
    "CAST(w.codinv AS BIGINT) codinv, ",
    "CASE WHEN w.treated=1 THEN t.status_eligible ELSE TRUE END status_eligible, ",
    "CAST(CASE WHEN w.treated=1 THEN t.target_group ELSE w.control_group END AS BIGINT) focal_group_1, ",
    "CAST(CASE WHEN w.treated=1 THEN t.acquirer_group ELSE NULL END AS BIGINT) focal_group_2, ",
    "(w.treated=1) use_target_company_path, ",
    "CASE WHEN w.treated=1 THEN t.qualification_route ELSE NULL END qualification_route, ",
    "CASE WHEN w.treated=1 THEN t.target_to_acquirer_transition_strict ELSE NULL END ",
    "target_to_acquirer_transition_strict, ",
    "CASE WHEN w.treated=1 THEN t.latest_pre_candidate_group_count ELSE NULL END ",
    "latest_pre_candidate_group_count, ",
    "CASE WHEN w.treated=1 THEN t.multi_exposure_inventor ELSE NULL END multi_exposure_inventor, ",
    "CASE WHEN w.treated=1 THEN t.big_deal ELSE NULL END big_deal ",
    "FROM weights w LEFT JOIN lmv2_treated_primary t ON w.treated=1 ",
    "AND t.deal_id=w.deal_id AND CAST(t.codinv AS DOUBLE)=w.codinv), ",
    "units AS (SELECT DISTINCT * FROM mapped), counts AS (SELECT ",
    "COUNT(*) FILTER(arm='treated') nt, COUNT(*) FILTER(arm='control') nc FROM units) ",
    "SELECT u.*, md5(CONCAT_WS('|', u.cohort, u.deal_id, u.arm, u.codinv, ",
    "u.focal_group_1)) roster_row_id, CASE WHEN u.arm='treated' THEN 1.0 ",
    "ELSE c.nt::DOUBLE/c.nc END weight FROM units u CROSS JOIN counts c"
  ), weight_union
))

membership <- certify_lmv2_roster_membership(
  con, "robustness_sensitivity_roster"
)
utils::write.csv(
  membership, file.path(OUTPUT_DIR, "sensitivity_roster_membership.csv"),
  row.names = FALSE, na = ""
)
if (!all(membership$pass)) stop("Sensitivity roster membership certification failed")

base_stamp <- utils::read.csv(BASE_STAMP, stringsAsFactors = FALSE)
if (nrow(base_stamp) != 1L) stop("Base stamp must contain one row")
needed <- c(
  "p0_design_hash", "p6_design_hash", "amendments_sha256",
  "preanalysis_freeze_sha256", "interface_hashes", "ingredient_build_hash"
)
if (!all(needed %in% names(base_stamp))) stop("Base stamp lacks provenance fields")
provenance <- list(
  p0_design_hash = base_stamp$p0_design_hash[[1]],
  p6_design_hash = base_stamp$p6_design_hash[[1]],
  amendments_sha256 = base_stamp$amendments_sha256[[1]],
  preanalysis_freeze_sha256 = base_stamp$preanalysis_freeze_sha256[[1]],
  p2_interface_hashes = strsplit(
    base_stamp$interface_hashes[[1]], ";", fixed = TRUE
  )[[1]],
  ingredient_build_hash = base_stamp$ingredient_build_hash[[1]],
  source_bundle_sha256 = digest::digest(list(
    materializer = digest::digest(
      file = file.path(BASE, "R", "18c_materialize_lmv2_outcome_panel.R"),
      algo = "sha256"
    ),
    runner = digest::digest(
      file = "02_analysis/R/48d_materialize_lmv2_sensitivity_superset.R",
      algo = "sha256"
    ),
    weights = vapply(weight_files, tools::md5sum, character(1))
  ), algo = "sha256", serialize = TRUE)
)

robustness_config <- LMV2_P6_CONFIG
robustness_config$cohorts <- 2000L
robustness_config$buffered_cohorts <- 2000L
shards <- materialize_lmv2_event_panel(
  con, "robustness_sensitivity_roster", "p6", panel_dir,
  provenance, config = robustness_config,
  allow_restart = FALSE, roster_mode = "production",
  cohorts_to_run = 2000L, profile_dir = profile_dir
)
utils::write.csv(
  shards, file.path(OUTPUT_DIR, "sensitivity_panel_shards.csv"),
  row.names = FALSE, na = ""
)

roster_counts <- DBI::dbGetQuery(con, "
  SELECT arm, COUNT(*) units, SUM(weight) mass,
         COUNT(DISTINCT deal_id) deals,
         COUNT(DISTINCT focal_group_1) focal_groups
  FROM robustness_sensitivity_roster GROUP BY arm ORDER BY arm")
utils::write.csv(
  roster_counts, file.path(OUTPUT_DIR, "sensitivity_roster_counts.csv"),
  row.names = FALSE, na = ""
)
manifest <- data.frame(
  version = "lmv2_sensitivity_superset_panel_v1",
  cohort = 2000L,
  specifications = paste(names(weight_files), collapse = ";"),
  conceptual_roster_units = sum(roster_counts$units),
  panel_path = shards$shard[[1]],
  panel_md5 = unname(tools::md5sum(shards$shard[[1]])),
  source_weight_bundle_sha256 = digest::digest(
    vapply(weight_files, tools::md5sum, character(1)),
    algo = "sha256", serialize = TRUE
  ),
  outcome_blind_design_weights = TRUE,
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(OUTPUT_DIR, "sensitivity_superset_manifest.csv"),
  row.names = FALSE, na = ""
)
message("Sensitivity superset panel complete: ", manifest$conceptual_roster_units, " units")
