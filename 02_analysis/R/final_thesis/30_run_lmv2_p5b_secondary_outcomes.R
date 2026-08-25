# Estimate the predesignated secondary outcomes for the frozen initially
# retained-inventor design. The script changes neither S3 support nor weights.

source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
config <- lmv2_p5b_s4_config()
source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()
shared_lib <- file.path(Sys.getenv("USERPROFILE"), "Documents", "Thesis",
                        ".r_libs")
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))

required_packages <- c(
  "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
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

primary_spec <- "primary_count_active_scale"
secondary_outcomes <- c(
  "tech_drift",
  "pqii_scaled",
  "pqii_observed",
  "pqii_conditional_mean",
  "fwcit5w_cassi_total",
  "fwcit5w_cassi_per_patent")
LMV2_P6_ESTIMATION$outcomes <- rbind(
  LMV2_P6_ESTIMATION$outcomes,
  data.frame(
    outcome = c("fwcit5w_cassi_total", "fwcit5w_cassi_per_patent"),
    designation = c("secondary_leading", "secondary_diagnostic"),
    interpretation = c(
      "Cassi--Ornaghi five-year forward citations, inventor-year total",
      "Cassi--Ornaghi five-year forward citations per source patent"),
    stringsAsFactors = FALSE))

audit_root <- file.path(
  config$p6_root, "02_analysis", "output", "audit",
  "local_match_v2_1993_amendment")
panel_root <- file.path(audit_root, "P6_P5C_COUNT_ACTIVE")
panel_dir <- file.path(panel_root, "panel_matched")
panel_manifest <- file.path(panel_root, "p6_manifest.csv")
panel_files <- sort(list.files(
  panel_dir, pattern = "^lmv2_event_panel_c[0-9]+[.]parquet$",
  full.names = TRUE))
stamp_files <- sort(list.files(
  panel_dir, pattern = "^lmv2_event_panel_c[0-9]+_stamp[.]csv$",
  full.names = TRUE))
cassi_path <- normalizePath(
  file.path(
    config$p6_root, "..", "..", "01_Data", "CassiOrnaghiPaperData",
    "inventor_production.csv"),
  winslash = "/", mustWork = TRUE)
out_dir <- file.path(
  config$base, "02_analysis", "output", "audit",
  "local_match_v2_1993_amendment",
  "P5B_STAYER_S6_SECONDARY_OUTCOMES")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

required_inputs <- c(
  panel_files, stamp_files, panel_manifest, config$s3_weights,
  config$s3_manifest, config$s3_certification, cassi_path)
missing_inputs <- required_inputs[!file.exists(required_inputs)]
if (length(panel_files) != length(LMV2_P6_CONFIG$cohorts) ||
    length(stamp_files) != length(LMV2_P6_CONFIG$cohorts) ||
    length(missing_inputs)) {
  stop("Missing or incomplete S6 inputs: ",
       paste(missing_inputs, collapse = ", "))
}

write_csv <- function(x, name) {
  utils::write.csv(x, file.path(out_dir, name), row.names = FALSE, na = "")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=8")
DBI::dbExecute(con, "SET memory_limit='5GB'")

input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, panel_manifest)
if (!isTRUE(input_checks$pass[[1L]])) {
  stop("The certified full P6 outcome panel failed validation")
}
write_csv(input_checks, "s6_input_checks.csv")

DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE s6_weights AS
  SELECT *
  FROM read_parquet(%s)
  WHERE spec=%s
", lmv2_sql_string(config$s3_weights), lmv2_sql_string(primary_spec)))

panel_source <- lmv2_panel_sql(panel_files)
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE s6_base AS
  SELECT *
  FROM %s
", panel_source))

DBI::dbExecute(con, "
  CREATE TEMP TABLE s6_unit_map AS
  WITH base_units AS (
    SELECT
      roster_row_id, deal_id, cohort, arm, codinv, focal_group_1
    FROM s6_base
    WHERE event_time=-1
  ),
  treated_map AS (
    SELECT b.roster_row_id,w.final_weight
    FROM s6_weights w
    JOIN base_units b
      ON w.cohort=b.cohort
     AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv
     AND b.arm='treated'
    WHERE w.treated=1
  ),
  control_map AS (
    SELECT b.roster_row_id,w.final_weight
    FROM s6_weights w
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

mapping <- DBI::dbGetQuery(con, "
  SELECT
    (SELECT COUNT(*) FROM s6_weights) weight_rows,
    (SELECT COUNT(*) FROM s6_unit_map) mapped_rows,
    (SELECT COUNT(DISTINCT roster_row_id) FROM s6_unit_map) unique_rows,
    (SELECT COUNT(*) FROM s6_base b
      JOIN s6_unit_map m USING(roster_row_id)) panel_rows
")
mapping$pass <-
  mapping$weight_rows == mapping$mapped_rows &&
  mapping$mapped_rows == mapping$unique_rows &&
  mapping$panel_rows == 11 * mapping$mapped_rows
if (!isTRUE(mapping$pass[[1L]])) stop("S6 weight-to-panel mapping failed")
write_csv(mapping, "s6_mapping_checks.csv")

DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE cassi_source AS
  SELECT
    CAST(codinv AS BIGINT) codinv,
    CAST(year AS INTEGER) calendar_year,
    CAST(patent AS DOUBLE) cassi_patent_count,
    CAST(fwCit5w AS DOUBLE) fwcit5w
  FROM read_csv_auto(
    %s, header=TRUE, sample_size=-1, all_varchar=FALSE)
", lmv2_sql_string(cassi_path)))

cassi_audit <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) source_rows,
    COUNT(DISTINCT (codinv,calendar_year)) unique_rows,
    SUM(fwcit5w IS NULL) missing_fwcit5w,
    SUM(fwcit5w<0) negative_fwcit5w
  FROM cassi_source
")
if (
  cassi_audit$source_rows != cassi_audit$unique_rows ||
  cassi_audit$missing_fwcit5w != 0L ||
  cassi_audit$negative_fwcit5w != 0L
) stop("Cassi--Ornaghi citation source failed validation")
write_csv(cassi_audit, "s6_cassi_source_audit.csv")

DBI::dbExecute(con, "
  CREATE TEMP TABLE s6_panel AS
  SELECT
    b.* REPLACE(m.final_weight AS weight),
    CAST(COALESCE(c.fwcit5w,0) AS DOUBLE) fwcit5w_cassi_total,
    CAST(
      CASE WHEN c.cassi_patent_count>0
        THEN c.fwcit5w/c.cassi_patent_count
        ELSE NULL END AS DOUBLE
    ) fwcit5w_cassi_per_patent,
    c.codinv IS NOT NULL cassi_source_matched
  FROM s6_base b
  JOIN s6_unit_map m USING(roster_row_id)
  LEFT JOIN cassi_source c
    ON b.codinv=c.codinv
   AND b.calendar_year=c.calendar_year
")

coverage_audit <- DBI::dbGetQuery(con, "
  SELECT
    arm,
    COUNT(*) FILTER(patent_count>0) active_rows,
    COUNT(*) FILTER(patent_count>0 AND cassi_source_matched)
      active_rows_cassi_matched,
    active_rows_cassi_matched/active_rows active_cassi_match_rate,
    SUM(weight) FILTER(tech_drift IS NOT NULL)/SUM(weight)
      techdrift_weight_coverage,
    SUM(weight) FILTER(pqii_scaled IS NOT NULL)/SUM(weight)
      pqii_weight_coverage
  FROM s6_panel
  GROUP BY arm
")
if (any(coverage_audit$active_cassi_match_rate < 0.90)) {
  stop("Cassi citation linkage is below 90% for an analysis arm")
}
write_csv(coverage_audit, "s6_secondary_coverage_audit.csv")

all_dynamic <- list()
all_pretrend <- list()
all_headline <- list()
all_coverage <- list()
run_started <- Sys.time()
for (sample_id in names(config$samples)) {
  cohorts <- config$samples[[sample_id]]
  deal_counts <- lmv2_design_deal_counts(con, "s6_panel", cohorts)
  for (outcome in secondary_outcomes) {
    message("Estimating ", outcome, " / ", sample_id)
    fit <- lmv2_fit_outcome(
      con, "s6_panel", outcome, sample_id, cohorts,
      config$bootstrap_replications, deal_counts)
    key <- paste(outcome, sample_id, sep = "__")
    all_dynamic[[key]] <- fit$dynamic
    all_pretrend[[key]] <- fit$pretrend
    all_headline[[key]] <- fit$headline
    all_coverage[[key]] <- fit$coverage
  }
}

dynamic <- do.call(rbind, all_dynamic)
pretrend <- do.call(rbind, all_pretrend)
headline <- do.call(rbind, all_headline)
pair_coverage <- do.call(rbind, all_coverage)
write_csv(dynamic, "s6_secondary_dynamic.csv")
write_csv(pretrend, "s6_secondary_pretrend.csv")
write_csv(headline, "s6_secondary_headline.csv")
write_csv(pair_coverage, "s6_secondary_pair_coverage.csv")

governing <- headline[
  headline$summary == "average_annual_t1_to_t5" &
    headline$governing, ]
certification <- data.frame(
  check = c(
    "full_p6_panel_validation_passes",
    "weights_map_one_to_one",
    "cassi_source_unique",
    "cassi_active_match_above_90pct",
    "all_governing_results_present",
    "all_governing_intervals_ordered"),
  pass = c(
    isTRUE(input_checks$pass[[1L]]),
    isTRUE(mapping$pass[[1L]]),
    cassi_audit$source_rows == cassi_audit$unique_rows,
    all(coverage_audit$active_cassi_match_rate >= 0.90),
    nrow(governing) ==
      length(secondary_outcomes) * length(config$samples),
    all(governing$ci_low <= governing$ci_high)),
  stringsAsFactors = FALSE)
if (!all(certification$pass)) {
  stop("S6 certification failed: ",
       paste(certification$check[!certification$pass], collapse = ", "))
}
write_csv(certification, "s6_certification.csv")

source_paths <- c(
  config$s3_weights, panel_manifest, cassi_path,
  file.path(config$base, "02_analysis", "R", "final_thesis",
            "30_run_lmv2_p5b_secondary_outcomes.R"),
  config$external_core_files)
manifest <- data.frame(
  source_path = normalizePath(
    source_paths, winslash = "/", mustWork = TRUE),
  sha256 = vapply(
    source_paths, digest::digest, character(1),
    algo = "sha256", file = TRUE),
  stringsAsFactors = FALSE)
write_csv(manifest, "s6_source_manifest.csv")
write_csv(data.frame(
  primary_spec = primary_spec,
  outcomes = paste(secondary_outcomes, collapse = ";"),
  samples = paste(names(config$samples), collapse = ";"),
  bootstrap_replications = config$bootstrap_replications,
  runtime_minutes = as.numeric(
    difftime(Sys.time(), run_started, units = "mins")),
  stringsAsFactors = FALSE),
  "s6_run_manifest.csv")

message("S6 secondary outcomes estimated and certified: ", out_dir)
