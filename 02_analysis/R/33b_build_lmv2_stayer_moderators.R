# ============================================================================
# 33b_build_lmv2_stayer_moderators.R -- outcome-blind stayer moderators
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
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
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "33a_lmv2_stayer_heterogeneity_config.R"))

cfg <- LMV2_STAYER_HET
out_dir <- cfg$output_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
temp_dir <- file.path(out_dir, "duckdb_tmp_build")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

required <- c(
  cfg$inputs$s3_weights, cfg$inputs$s3_manifest,
  cfg$inputs$s3_certification, cfg$inputs$s3_summary,
  cfg$inputs$full_moderators, cfg$inputs$full_moderator_manifest,
  cfg$inputs$panel_manifest, cfg$freeze_path
)
if (!all(file.exists(required))) {
  stop("Missing stayer moderator input: ",
       paste(required[!file.exists(required)], collapse = ", "))
}
s3_cert <- utils::read.csv(
  cfg$inputs$s3_certification, stringsAsFactors = FALSE
)
if (!nrow(s3_cert) || !all(s3_cert$pass)) {
  stop("Certified P5b S3 design contains a failed check")
}
s3_manifest <- utils::read.csv(
  cfg$inputs$s3_manifest, stringsAsFactors = FALSE
)
s3_weight_row <- s3_manifest[
  s3_manifest$artifact == basename(cfg$inputs$s3_weights), ,
  drop = FALSE
]
if (nrow(s3_weight_row) != 1L ||
    s3_weight_row$sha256 != digest::digest(
      file = cfg$inputs$s3_weights, algo = "sha256"
    )) {
  stop("P5b S3 weights differ from their certified manifest")
}
full_manifest <- utils::read.csv(
  cfg$inputs$full_moderator_manifest, stringsAsFactors = FALSE
)
if (nrow(full_manifest) != 1L ||
    full_manifest$moderator_sha256 != digest::digest(
      file = cfg$inputs$full_moderators, algo = "sha256"
    )) {
  stop("Full-cohort moderator layer is stale; rerun 32b")
}

panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
stamp_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$",
  full.names = TRUE
))
expected_shards <- length(unique(unlist(cfg$estimand$samples)))
if (length(panel_files) != expected_shards ||
    length(stamp_files) != expected_shards) {
  stop("Certified P6 panel bundle is incomplete")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", cfg$execution$threads))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))
input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, cfg$inputs$panel_manifest
)
if (!isTRUE(input_checks$pass[[1]])) {
  stop("Inherited certified P6 panel failed validation")
}

t0 <- Sys.time()
panel_sql <- lmv2_panel_sql(panel_files)
weights_sql <- sprintf(
  "read_parquet(%s)",
  lmv2_sql_string(normalizePath(
    cfg$inputs$s3_weights, winslash = "/", mustWork = TRUE
  ))
)
moderator_sql <- sprintf(
  "read_parquet(%s)",
  lmv2_sql_string(normalizePath(
    cfg$inputs$full_moderators, winslash = "/", mustWork = TRUE
  ))
)

DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE stayer_weights AS
SELECT *
FROM %s
WHERE spec=%s AND support_variant=%s
", weights_sql, lmv2_sql_string(cfg$construction$primary_spec),
   lmv2_sql_string(cfg$construction$primary_support)))

# The P5b row key differs from P5a. Map it to the certified conceptual P6 row
# without reading an outcome; treatment and control arms are joined separately
# so the control firm's identity remains explicit.
DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE base_units AS
SELECT
  roster_row_id,CAST(deal_id AS INTEGER) deal_id,
  CAST(cohort AS INTEGER) cohort,arm,CAST(codinv AS BIGINT) codinv,
  CAST(focal_group_1 AS BIGINT) focal_group_1
FROM %s
WHERE event_time=-1
", panel_sql))
DBI::dbExecute(con, "
CREATE OR REPLACE TEMP TABLE stayer_map AS
SELECT
  b.roster_row_id,w.final_weight,w.established_early_recruitment
FROM stayer_weights w
JOIN base_units b
  ON w.treated=1 AND b.arm='treated'
 AND w.cohort=b.cohort AND w.deal_id=b.deal_id AND w.codinv=b.codinv
UNION ALL
SELECT
  b.roster_row_id,w.final_weight,w.established_early_recruitment
FROM stayer_weights w
JOIN base_units b
  ON w.treated=0 AND b.arm='control'
 AND w.cohort=b.cohort AND w.deal_id=b.deal_id AND w.codinv=b.codinv
 AND w.control_group=b.focal_group_1
")
DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE stayer_moderators AS
SELECT
  m.*,CAST(s.final_weight AS DOUBLE) raw_weight,
  s.established_early_recruitment
FROM stayer_map s
JOIN %s m USING (roster_row_id)
", moderator_sql))

moderator_path <- normalizePath(
  file.path(out_dir, "stayer_moderators.parquet"),
  winslash = "/", mustWork = FALSE
)
if (file.exists(moderator_path) && !file.remove(moderator_path)) {
  stop("Could not replace stale stayer moderator artifact")
}
DBI::dbExecute(con, sprintf("
COPY (
  SELECT * FROM stayer_moderators
  ORDER BY cohort,deal_id,arm,codinv,roster_row_id
) TO %s (FORMAT PARQUET,COMPRESSION ZSTD)
", lmv2_sql_string(moderator_path)))

audit <- DBI::dbGetQuery(con, "
SELECT
  (SELECT COUNT(*) FROM stayer_weights) expected_rows,
  (SELECT COUNT(*) FROM stayer_map) mapped_rows,
  (SELECT COUNT(DISTINCT roster_row_id) FROM stayer_map) unique_mapped_rows,
  (SELECT COUNT(*) FROM stayer_moderators) moderator_rows,
  (SELECT COUNT(DISTINCT roster_row_id) FROM stayer_moderators) unique_rows,
  (SELECT COUNT(*) FROM stayer_moderators WHERE raw_weight<=0 OR
    raw_weight IS NULL OR NOT isfinite(raw_weight)) invalid_weights,
  (SELECT COUNT(*) FROM stayer_moderators
    WHERE focal_group_tenure<0 OR focal_group_tenure>career_age)
    tenure_clock_violations,
  (SELECT COUNT(*) FROM stayer_moderators
    WHERE last_team_input_year>=cohort) team_future_violations,
  (SELECT COUNT(*) FROM stayer_moderators
    WHERE inv_last_year>=cohort OR acq_last_year>=cohort)
    techfit_future_violations,
  (SELECT COUNT(DISTINCT cohort) FROM stayer_moderators) cohorts,
  (SELECT COUNT(DISTINCT deal_id) FROM stayer_moderators
    WHERE arm='treated') treated_deals,
  (SELECT COUNT(*) FROM stayer_moderators
    WHERE arm='treated') treated_inventors,
  (SELECT COUNT(*) FROM stayer_moderators
    WHERE arm='control') control_rows
")
s3_summary <- utils::read.csv(
  cfg$inputs$s3_summary, stringsAsFactors = FALSE
)
metric <- function(name) {
  z <- s3_summary$value[s3_summary$metric == name]
  if (length(z) != 1L) stop("Missing S3 summary metric: ", name)
  as.numeric(z)
}
checks <- data.frame(
  check = c(
    "all_primary_p5b_rows_map_once",
    "one_moderator_row_per_p5b_row",
    "all_weights_positive_and_finite",
    "all_amended_cohorts_present",
    "treated_count_reproduces_s3",
    "treated_deal_count_reproduces_s3",
    "control_count_reproduces_s3",
    "tenure_and_career_use_same_t_minus_1_clock",
    "team_inputs_are_strictly_pre_treatment",
    "techfit_inputs_are_strictly_pre_treatment"
  ),
  pass = c(
    audit$expected_rows == audit$mapped_rows &&
      audit$mapped_rows == audit$unique_mapped_rows,
    audit$expected_rows == audit$moderator_rows &&
      audit$moderator_rows == audit$unique_rows,
    audit$invalid_weights == 0,
    audit$cohorts == expected_shards,
    audit$treated_inventors == metric("primary_supported_treated"),
    audit$treated_deals == metric("primary_supported_deals"),
    audit$control_rows == metric("primary_control_rows"),
    audit$tenure_clock_violations == 0,
    audit$team_future_violations == 0,
    audit$techfit_future_violations == 0
  ),
  stringsAsFactors = FALSE
)
lmv2_stayer_het_assert(checks)

team_counts <- DBI::dbGetQuery(con, "
SELECT arm,team_any,COUNT(*) roster_rows,
  COUNT(DISTINCT codinv) distinct_inventors,
  COUNT(DISTINCT deal_id) nominal_deals
FROM stayer_moderators GROUP BY arm,team_any ORDER BY arm,team_any
")
techfit_funnel <- DBI::dbGetQuery(con, "
SELECT 'full_history' variant,techfit_full_reason reason,arm,
  COUNT(*) roster_rows,COUNT(DISTINCT codinv) distinct_inventors,
  COUNT(DISTINCT deal_id) nominal_deals
FROM stayer_moderators GROUP BY techfit_full_reason,arm
UNION ALL
SELECT 'five_year',techfit_5y_reason,arm,
  COUNT(*),COUNT(DISTINCT codinv),COUNT(DISTINCT deal_id)
FROM stayer_moderators GROUP BY techfit_5y_reason,arm
ORDER BY variant,reason,arm
")
utils::write.csv(
  audit, file.path(out_dir, "moderator_build_audit.csv"), row.names = FALSE
)
utils::write.csv(
  checks, file.path(out_dir, "moderator_build_certification.csv"),
  row.names = FALSE
)
utils::write.csv(
  team_counts, file.path(out_dir, "team_persistence_counts.csv"),
  row.names = FALSE
)
utils::write.csv(
  techfit_funnel, file.path(out_dir, "techfit_coverage_funnel.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  design_hash = lmv2_stayer_het_hash(),
  source_sha256 = digest::digest(
    file = file.path(BASE, "R", "33b_build_lmv2_stayer_moderators.R"),
    algo = "sha256"
  ),
  s3_weights_sha256 = digest::digest(
    file = cfg$inputs$s3_weights, algo = "sha256"
  ),
  inherited_moderators_sha256 = digest::digest(
    file = cfg$inputs$full_moderators, algo = "sha256"
  ),
  moderator_sha256 = digest::digest(
    file = moderator_path, algo = "sha256"
  ),
  moderator_rows = audit$moderator_rows,
  treated_inventors = audit$treated_inventors,
  treated_deals = audit$treated_deals,
  outcome_columns_written = 0L,
  runtime_minutes = as.numeric(
    difftime(Sys.time(), t0, units = "mins")
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "moderator_build_manifest.csv"),
  row.names = FALSE
)
message(
  "Certified stayer moderators: ", manifest$moderator_rows,
  " rows in ", round(manifest$runtime_minutes, 2), " minutes."
)
