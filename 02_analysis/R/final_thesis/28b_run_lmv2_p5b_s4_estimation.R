# Estimate the frozen P5b S4 initially-retained quantity package.
#
# Usage:
# Rscript 02_analysis/R/final_thesis/28b_run_lmv2_p5b_s4_estimation.R
#   [--output-dir=<directory>] [--smoke]
#
# Completed cohort-window/outcome/specification cells are checkpointed as RDS
# files and reused only when their S4 execution hash matches.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}

source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
config <- lmv2_p5b_s4_config()
output_arg <- get_arg("--output-dir")
if (!is.na(output_arg)) config$output_dir <- output_arg
smoke <- "--smoke" %in% args

source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()
shared_lib <- file.path(Sys.getenv("USERPROFILE"), "Documents", "Thesis",
                        ".r_libs")
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
required_packages <- c(
  "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

BASE <- normalizePath(
  file.path(config$p6_root, "02_analysis"),
  winslash = "/", mustWork = TRUE)
source(file.path(config$p6_r_dir, "15a_lmv2_design_lock.R"))
source(file.path(config$p6_r_dir, "18a_lmv2_outcome_config.R"))
source(file.path(config$p6_r_dir, "19a_lmv2_p6_estimation_config.R"))
source(file.path(config$p6_r_dir, "19b_lmv2_p6_estimation_core.R"))

if (!identical(
  as.character(utils::packageVersion("fwildclusterboot")),
  LMV2_P6_ESTIMATION$inference$package_version
)) {
  stop("fwildclusterboot version differs from the frozen version")
}

required_inputs <- c(
  config$base_panel_dir, config$base_p6_manifest, config$s3_weights,
  config$s3_manifest, config$s3_certification, config$freeze_file,
  config$source_files, config$external_core_files)
missing_inputs <- required_inputs[!file.exists(required_inputs) &
                                    !dir.exists(required_inputs)]
if (length(missing_inputs)) {
  stop("Missing S4 input: ", paste(missing_inputs, collapse = ", "))
}

s3_certification <- utils::read.csv(
  config$s3_certification, stringsAsFactors = FALSE)
if (!nrow(s3_certification) || !all(s3_certification$pass)) {
  stop("S3 certification is missing or contains a failed check")
}
s3_manifest <- utils::read.csv(
  config$s3_manifest, stringsAsFactors = FALSE)
s3_weight_manifest <- s3_manifest[
  s3_manifest$artifact == basename(config$s3_weights), ]
if (nrow(s3_weight_manifest) != 1L ||
    !identical(
      digest::digest(
        config$s3_weights, algo = "sha256", file = TRUE,
        serialize = FALSE),
      s3_weight_manifest$sha256[[1L]])) {
  stop("S3 production weights do not match their certified manifest")
}

panel_files <- sort(list.files(
  config$base_panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE))
stamp_files <- sort(list.files(
  config$base_panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$",
  full.names = TRUE))
if (length(panel_files) != length(LMV2_P6_CONFIG$cohorts) ||
    length(stamp_files) != length(LMV2_P6_CONFIG$cohorts)) {
  stop("Expected one certified P6 panel shard and stamp per cohort")
}

dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
config$output_dir <- normalizePath(
  config$output_dir, winslash = "/", mustWork = TRUE)
checkpoint_dir <- file.path(config$output_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
execution_hash <- lmv2_p5b_s4_hash(config)

write_csv <- function(x, path) {
  utils::write.csv(x, path, row.names = FALSE, na = "")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
duckdb_tmp <- file.path(config$output_dir, "duckdb_tmp")
dir.create(duckdb_tmp, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(duckdb_tmp)))

base_input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, config$base_p6_manifest)
if (!isTRUE(base_input_checks$pass[[1L]])) {
  stop("The certified P6 outcome panel failed its input checks")
}
write_csv(
  base_input_checks,
  file.path(config$output_dir, "s4_base_panel_certification.csv"))

panel_source <- lmv2_panel_sql(panel_files)
DBI::dbExecute(con, sprintf("
  CREATE OR REPLACE TEMP TABLE s4_base_outcomes AS
  SELECT
    roster_row_id,
    CAST(deal_id AS INTEGER) AS deal_id,
    CAST(cohort AS INTEGER) AS cohort,
    arm,
    CAST(codinv AS BIGINT) AS codinv,
    CAST(focal_group_1 AS BIGINT) AS focal_group_1,
    CAST(event_time AS INTEGER) AS event_time,
    CAST(patent_count AS DOUBLE) AS patent_count,
    CAST(active_patenting AS DOUBLE) AS active_patenting
  FROM %s
", panel_source))
DBI::dbExecute(con, sprintf("
  CREATE OR REPLACE TEMP TABLE s4_weights AS
  SELECT * FROM read_parquet(%s)
", lmv2_sql_string(config$s3_weights)))

# Map every S3 row to exactly one certified P6 conceptual roster row. Splitting
# the arms avoids an OR join and makes the control-firm identity explicit.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE s4_unit_map AS
  WITH base_units AS (
    SELECT
      roster_row_id, deal_id, cohort, arm, codinv, focal_group_1
    FROM s4_base_outcomes
    WHERE event_time=-1
  ),
  treated_map AS (
    SELECT
      w.spec, w.support_variant, b.roster_row_id,
      w.final_weight, w.established_early_recruitment
    FROM s4_weights w
    JOIN base_units b
      ON w.cohort=b.cohort
     AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv
     AND b.arm='treated'
    WHERE w.treated=1
  ),
  control_map AS (
    SELECT
      w.spec, w.support_variant, b.roster_row_id,
      w.final_weight, w.established_early_recruitment
    FROM s4_weights w
    JOIN base_units b
      ON w.cohort=b.cohort
     AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv
     AND w.control_group=b.focal_group_1
     AND b.arm='control'
    WHERE w.treated=0
  )
  SELECT * FROM treated_map
  UNION ALL
  SELECT * FROM control_map
")

mapping_checks <- DBI::dbGetQuery(con, sprintf("
  WITH expected AS (
    SELECT spec, COUNT(*) AS n
    FROM s4_weights GROUP BY spec
  ),
  observed AS (
    SELECT spec, COUNT(*) AS n,
      COUNT(DISTINCT roster_row_id) AS unique_rows
    FROM s4_unit_map GROUP BY spec
  ),
  panel_counts AS (
    SELECT m.spec, COUNT(*) AS n
    FROM s4_unit_map m
    JOIN s4_base_outcomes p USING (roster_row_id)
    GROUP BY m.spec
  )
  SELECT
    (SELECT COUNT(*) FROM s4_weights) AS weight_rows,
    (SELECT COUNT(*) FROM s4_unit_map) AS mapped_rows,
    (SELECT COUNT(*) FROM s4_unit_map
     GROUP BY spec,roster_row_id HAVING COUNT(*)<>1 LIMIT 1)
       AS duplicate_map_positive,
    (SELECT COUNT(DISTINCT spec) FROM s4_unit_map) AS specifications,
    (SELECT MIN(n) FROM (
       SELECT spec, COUNT(DISTINCT cohort) AS n
       FROM s4_weights GROUP BY spec)) AS minimum_cohorts,
    (SELECT COUNT(*) FROM expected e
       FULL JOIN observed o USING(spec)
       WHERE e.n IS DISTINCT FROM o.n
          OR o.unique_rows IS DISTINCT FROM o.n) AS bad_spec_maps,
    (SELECT COUNT(*) FROM expected e
       JOIN panel_counts p USING(spec)
       WHERE p.n<>11*e.n) AS bad_panel_counts
"))
mapping_checks$pass <-
  mapping_checks$weight_rows == mapping_checks$mapped_rows &&
  is.na(mapping_checks$duplicate_map_positive) &&
  mapping_checks$specifications == length(config$production_specs) &&
  mapping_checks$minimum_cohorts == length(LMV2_P6_CONFIG$cohorts) &&
  mapping_checks$bad_spec_maps == 0L &&
  mapping_checks$bad_panel_counts == 0L
if (!isTRUE(mapping_checks$pass[[1L]])) {
  stop("S3 weights do not map one-to-one into the certified P6 panel")
}
write_csv(
  mapping_checks,
  file.path(config$output_dir, "s4_weight_panel_mapping.csv"))

specs <- if (smoke) config$production_specs[1:2] else
  config$production_specs
samples <- if (smoke) list(smoke_1993_1995 = 1993:1995) else
  config$samples
outcomes <- config$outcomes
bootstrap_reps <- if (smoke) 199L else config$bootstrap_replications

cells <- expand.grid(
  spec = specs,
  sample = names(samples),
  outcome = outcomes,
  stringsAsFactors = FALSE)
results <- vector("list", nrow(cells))
run_started <- Sys.time()

for (i in seq_len(nrow(cells))) {
  spec <- cells$spec[[i]]
  sample_id <- cells$sample[[i]]
  outcome <- cells$outcome[[i]]
  checkpoint <- file.path(
    checkpoint_dir,
    paste(spec, sample_id, outcome, "rds", sep = "__"))

  if (file.exists(checkpoint)) {
    prior <- readRDS(checkpoint)
    if (identical(prior$execution_hash, execution_hash) &&
        identical(prior$spec, spec) &&
        identical(prior$sample, sample_id) &&
        identical(prior$outcome, outcome) &&
        identical(prior$bootstrap_replications, bootstrap_reps)) {
      message(sprintf(
        "[%d/%d] checkpoint %s | %s | %s",
        i, nrow(cells), spec, sample_id, outcome))
      results[[i]] <- prior
      next
    }
  }

  message(sprintf(
    "[%d/%d] estimating %s | %s | %s",
    i, nrow(cells), spec, sample_id, outcome))
  step_started <- Sys.time()
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE s4_panel AS
    SELECT
      p.roster_row_id, p.deal_id, p.cohort, p.arm, p.codinv,
      p.event_time, m.final_weight AS weight,
      p.patent_count, p.active_patenting
    FROM s4_base_outcomes p
    JOIN s4_unit_map m USING (roster_row_id)
    WHERE m.spec=%s
  ", lmv2_sql_string(spec)))

  panel_checks <- DBI::dbGetQuery(con, "
    WITH units AS (
      SELECT roster_row_id, COUNT(*) n,
        MIN(event_time) min_e, MAX(event_time) max_e
      FROM s4_panel GROUP BY roster_row_id
    ),
    masses AS (
      SELECT cohort,
        SUM(weight) FILTER (WHERE arm='treated' AND event_time=-1) tm,
        SUM(weight) FILTER (WHERE arm='control' AND event_time=-1) cm
      FROM s4_panel GROUP BY cohort
    )
    SELECT
      (SELECT COUNT(*) FROM units) units,
      (SELECT COUNT(*) FROM units
       WHERE n<>11 OR min_e<>-5 OR max_e<>5) bad_units,
      (SELECT COUNT(*) FROM masses WHERE ABS(tm-cm)>1e-7) bad_masses,
      (SELECT COUNT(DISTINCT cohort) FROM s4_panel) cohorts
  ")
  if (panel_checks$bad_units != 0L ||
      panel_checks$bad_masses != 0L ||
      panel_checks$cohorts != length(LMV2_P6_CONFIG$cohorts)) {
    stop("S4 joined panel invariant failed for ", spec)
  }

  cohort_set <- samples[[sample_id]]
  deal_counts <- lmv2_design_deal_counts(
    con, "s4_panel", cohort_set)
  fitted <- lmv2_fit_outcome(
    con, "s4_panel", outcome, sample_id, cohort_set,
    bootstrap_reps, deal_counts)
  for (part in c("dynamic", "pretrend", "headline", "coverage")) {
    fitted[[part]]$spec <- spec
    fitted[[part]]$support_variant <-
      config$s3$weight_specs[[spec]]$support
  }
  result <- list(
    execution_hash = execution_hash,
    spec = spec,
    sample = sample_id,
    outcome = outcome,
    bootstrap_replications = bootstrap_reps,
    runtime_minutes = as.numeric(
      difftime(Sys.time(), step_started, units = "mins")),
    fitted = fitted)
  temp_checkpoint <- paste0(checkpoint, ".tmp")
  saveRDS(result, temp_checkpoint, compress = "xz")
  if (file.exists(checkpoint)) unlink(checkpoint)
  if (!file.rename(temp_checkpoint, checkpoint)) {
    stop("Could not publish checkpoint: ", checkpoint)
  }
  results[[i]] <- result
  rm(fitted, result)
  gc()
}

bind_part <- function(part) {
  do.call(rbind, lapply(results, function(x) x$fitted[[part]]))
}
dynamic <- bind_part("dynamic")
pretrend <- bind_part("pretrend")
headline <- bind_part("headline")
coverage <- bind_part("coverage")
progress <- do.call(rbind, lapply(results, function(x) {
  data.frame(
    spec = x$spec, sample = x$sample, outcome = x$outcome,
    bootstrap_replications = x$bootstrap_replications,
    runtime_minutes = x$runtime_minutes,
    stringsAsFactors = FALSE)
}))

write_csv(
  dynamic, file.path(config$output_dir, "s4_event_study_dynamic.csv"))
write_csv(
  pretrend, file.path(config$output_dir, "s4_joint_pretrend_tests.csv"))
write_csv(
  headline, file.path(config$output_dir, "s4_headline_post_att.csv"))
write_csv(
  coverage, file.path(config$output_dir, "s4_outcome_pair_coverage.csv"))
write_csv(
  progress, file.path(config$output_dir, "s4_estimation_progress.csv"))

source_hashes <- vapply(
  config$source_files, digest::digest, character(1),
  algo = "sha256", file = TRUE)
external_hashes <- vapply(
  config$external_core_files, digest::digest, character(1),
  algo = "sha256", file = TRUE)
manifest <- data.frame(
  version = config$version,
  run_mode = if (smoke) "smoke_nonproduction" else "production",
  execution_hash = execution_hash,
  freeze_sha256 = digest::digest(
    config$freeze_file, algo = "sha256", file = TRUE,
    serialize = FALSE),
  s3_weights_sha256 = s3_weight_manifest$sha256[[1L]],
  s3_execution_hash = unique(s3_manifest$execution_hash)[[1L]],
  base_p6_manifest_sha256 = digest::digest(
    config$base_p6_manifest, algo = "sha256", file = TRUE,
    serialize = FALSE),
  base_panel_bundle_md5 = digest::digest(
    vapply(panel_files, tools::md5sum, character(1)),
    algo = "sha256", serialize = TRUE),
  source_bundle_sha256 = digest::digest(
    c(source_hashes, external_hashes),
    algo = "sha256", serialize = TRUE),
  specifications = paste(specs, collapse = ";"),
  samples = paste(names(samples), collapse = ";"),
  outcomes = paste(outcomes, collapse = ";"),
  bootstrap_replications = bootstrap_reps,
  cells = nrow(cells),
  mapping_certification_pass = isTRUE(mapping_checks$pass[[1L]]),
  selected_group_estimand = TRUE,
  principal_stratum_att = FALSE,
  runtime_minutes = as.numeric(
    difftime(Sys.time(), run_started, units = "mins")),
  stringsAsFactors = FALSE)
write_csv(
  manifest, file.path(config$output_dir, "s4_estimation_manifest.csv"))

message(sprintf(
  "S4 %s estimation complete: %d cells in %.2f minutes",
  manifest$run_mode, nrow(cells), manifest$runtime_minutes))
