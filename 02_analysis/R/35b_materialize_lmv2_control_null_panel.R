# ============================================================================
# Materialize one certified control-null P6 patent-count panel
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}

db_path <- normalizePath(
  arg("db"), winslash = "/", mustWork = TRUE)
roster_path <- normalizePath(
  arg("roster"), winslash = "/", mustWork = TRUE)
assignment_manifest_path <- normalizePath(
  arg("assignment-manifest"), winslash = "/", mustWork = TRUE)
source_stamp_path <- normalizePath(
  arg("source-stamp"), winslash = "/", mustWork = TRUE)
output_dir <- arg("output-dir")

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (package in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(
  BASE, "R", "18c_materialize_lmv2_outcome_panel.R"))
source(file.path(
  BASE, "R", "35a_lmv2_control_null_config.R"))

assignment <- utils::read.csv(
  assignment_manifest_path, stringsAsFactors = FALSE)
if (nrow(assignment) != 1L) {
  stop("Assignment manifest must contain one draw")
}
analysis_cohorts <- as.integer(strsplit(
  assignment$analysis_cohorts, ";", fixed = TRUE)[[1]])
if (anyNA(analysis_cohorts) || !length(analysis_cohorts)) {
  stop("Assignment manifest has invalid analysis cohorts")
}
sample_id <- if (identical(analysis_cohorts, 1994:2010)) {
  "full_1994_2010"
} else if (identical(analysis_cohorts, 1994:2008)) {
  "buffered_1994_2008"
} else {
  stop("Unsupported control-null cohort grid")
}
real_supported_treated_inventors <-
  LMV2_CONTROL_NULL_P6$real_supported_treated_inventors[[sample_id]]
real_nominal_treated_deals <-
  LMV2_CONTROL_NULL_P6$real_nominal_treated_deals[[sample_id]]
real_effective_treated_deals <-
  LMV2_CONTROL_NULL_P6$real_effective_treated_deals[[sample_id]]
if (!is.finite(real_supported_treated_inventors) ||
    !is.finite(real_nominal_treated_deals) ||
    !is.finite(real_effective_treated_deals)) {
  stop("Missing real-design benchmark for sample ", sample_id)
}
source_stamp <- utils::read.csv(
  source_stamp_path, stringsAsFactors = FALSE)
if (nrow(source_stamp) != 1L) {
  stop("Source P6 stamp must contain one row")
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(
  output_dir, winslash = "/", mustWork = TRUE)
con <- DBI::dbConnect(
  duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=2")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
DBI::dbExecute(con, sprintf(
  "CREATE OR REPLACE TEMP VIEW control_null_roster AS
   SELECT * FROM read_parquet(%s)",
  DBI::dbQuoteString(con, roster_path)))

q <- function(sql) DBI::dbGetQuery(con, sql)$n
membership <- data.frame(
  check = c(
    "treated_rows_match_assignment",
    "pseudo_treated_inventor_not_control",
    "pseudo_target_group_not_control"),
  observed = c(
    q(sprintf(
      "SELECT COUNT(*) n FROM control_null_roster r
       WHERE r.arm='treated' AND NOT EXISTS (
         SELECT 1 FROM read_parquet(%s) t
         WHERE t.cohort=r.cohort
           AND CAST(t.deal_id AS BIGINT)=r.deal_id
           AND CAST(t.codinv AS BIGINT)=r.codinv
           AND CAST(t.target_group AS BIGINT)=r.focal_group_1)",
      DBI::dbQuoteString(con, assignment$treated_primary_path))),
    q("SELECT COUNT(*) n FROM (
         SELECT DISTINCT codinv FROM control_null_roster
         WHERE arm='treated'
         INTERSECT
         SELECT DISTINCT codinv FROM control_null_roster
         WHERE arm='control')"),
    q("SELECT COUNT(*) n FROM (
         SELECT DISTINCT cohort,focal_group_1 FROM control_null_roster
         WHERE arm='treated'
         INTERSECT
         SELECT DISTINCT cohort,focal_group_1 FROM control_null_roster
         WHERE arm='control')")),
  expected = 0,
  stringsAsFactors = FALSE)
membership$pass <- membership$observed == membership$expected
utils::write.csv(
  membership,
  file.path(output_dir, "control_null_membership_certification.csv"),
  row.names = FALSE)
if (!all(membership$pass)) {
  stop(
    "Control-null membership certification failed: ",
    paste(membership$check[!membership$pass], collapse = ", "))
}

source_hashes <- vapply(
  file.path(BASE, "R", c(
    "18a_lmv2_outcome_config.R",
    "18c_materialize_lmv2_outcome_panel.R",
    "35a_lmv2_control_null_config.R",
    "35b_materialize_lmv2_control_null_panel.R")),
  digest::digest, character(1), file = TRUE, algo = "sha256")
provenance <- list(
  p0_design_hash = source_stamp$p0_design_hash,
  p6_design_hash = source_stamp$p6_design_hash,
  amendments_sha256 = source_stamp$amendments_sha256,
  preanalysis_freeze_sha256 =
    source_stamp$preanalysis_freeze_sha256,
  p2_interface_hashes = strsplit(
    source_stamp$interface_hashes, ";", fixed = TRUE)[[1]],
  ingredient_build_hash = source_stamp$ingredient_build_hash,
  source_bundle_sha256 = digest::digest(
    list(
      source_hashes = source_hashes,
      roster_sha256 = digest::digest(
        file = roster_path, algo = "sha256"),
      assignment_manifest_sha256 = digest::digest(
        file = assignment_manifest_path, algo = "sha256")),
    algo = "sha256"))

started <- Sys.time()
shards <- materialize_lmv2_event_panel(
  con = con,
  roster_tbl = "control_null_roster",
  schema = LMV2_CONTROL_NULL_P6$ingredient_schema,
  out_dir = output_dir,
  provenance = provenance,
  config = LMV2_P6_CONFIG,
  allow_restart = TRUE,
  roster_mode = LMV2_CONTROL_NULL_P6$roster_mode,
  cohorts_to_run = analysis_cohorts)
utils::write.csv(
  shards,
  file.path(output_dir, "control_null_panel_shards.csv"),
  row.names = FALSE)
cluster_diagnostics <- DBI::dbGetQuery(con, "
  WITH deal_mass AS (
    SELECT deal_id,SUM(weight) AS mass
    FROM control_null_roster
    WHERE arm='treated'
    GROUP BY deal_id
  ), shares AS (
    SELECT mass/SUM(mass) OVER () AS share
    FROM deal_mass
  )
  SELECT
    COUNT(*) AS nominal_treated_firms,
    1/SUM(share*share) AS effective_treated_firms,
    MAX(share) AS max_treated_firm_weight_share
  FROM shares")
manifest <- data.frame(
  version = LMV2_CONTROL_NULL_P6_VERSION,
  draw_id = assignment$draw_id,
  assignment_arm = assignment$assignment_arm,
  analysis_cohorts = assignment$analysis_cohorts,
  sample_id = sample_id,
  predicted_placebo_sign = assignment$predicted_placebo_sign,
  treated_inventor_count_ratio =
    assignment$treated_inventor_count_ratio,
  supported_pseudo_treated_inventors = q(
    "SELECT COUNT(*) n FROM (
       SELECT DISTINCT cohort,deal_id,codinv
       FROM control_null_roster
       WHERE arm='treated')"),
  supported_treated_inventor_count_ratio = q(
    "SELECT COUNT(*) n FROM (
       SELECT DISTINCT cohort,deal_id,codinv
       FROM control_null_roster
       WHERE arm='treated')") /
    real_supported_treated_inventors,
  unique_pseudo_firms = assignment$unique_pseudo_firms,
  pseudo_patent_continuity_share =
    assignment$pseudo_patent_continuity_share,
  nominal_treated_firms =
    cluster_diagnostics$nominal_treated_firms,
  nominal_treated_firm_ratio =
    cluster_diagnostics$nominal_treated_firms /
    real_nominal_treated_deals,
  effective_treated_firms =
    cluster_diagnostics$effective_treated_firms,
  max_treated_firm_weight_share =
    cluster_diagnostics$max_treated_firm_weight_share,
  effective_treated_firm_ratio =
    cluster_diagnostics$effective_treated_firms /
    real_effective_treated_deals,
  roster_path = roster_path,
  roster_sha256 = digest::digest(
    file = roster_path, algo = "sha256"),
  assignment_manifest_sha256 = digest::digest(
    file = assignment_manifest_path, algo = "sha256"),
  panel_rows = sum(vapply(
    file.path(
      output_dir,
      sprintf("lmv2_event_panel_c%d.parquet", analysis_cohorts)),
    function(path) DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM read_parquet(%s)",
      DBI::dbQuoteString(con, path)))$n,
    numeric(1))),
  elapsed_seconds = as.numeric(
    difftime(Sys.time(), started, units = "secs")),
  certification_pass = TRUE,
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest,
  file.path(output_dir, "control_null_panel_manifest.csv"),
  row.names = FALSE)
