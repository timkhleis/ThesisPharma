# ============================================================================
# Cassi--Ornaghi fwCit5w supplement under the frozen P5c/P6 design
# ============================================================================
#
# The source is selected ex ante because it is the original study's five-year
# forward-citation field, not because of the resulting coefficient. The
# supplement leaves the frozen P6 panel and weights unchanged and joins the
# citation source only by inventor and calendar year.
#
# Run from the lmv2-p6-outcomes worktree root:
# Rscript 02_analysis/R/26b_estimate_lmv2_cassi_fwcit5w.R

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
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
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

THESIS_ROOT <- normalizePath(
  file.path(BASE, "..", "..", ".."), winslash = "/", mustWork = TRUE)
AUDIT_ROOT <- file.path(BASE, "output", "audit", "local_match_v2")
PANEL_ROOT <- file.path(AUDIT_ROOT, "P6_P5C_PANEL_COUNT_ACTIVE")
PANEL_DIR <- file.path(PANEL_ROOT, "panel_matched")
OUT_DIR <- file.path(AUDIT_ROOT, "P6_CASSI_FWCIT5W")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

CASSI_PATH <- normalizePath(
  file.path(
    THESIS_ROOT, "01_Data", "CassiOrnaghiPaperData",
    "inventor_production.csv"),
  winslash = "/", mustWork = TRUE)
panel_files <- sort(list.files(
  PANEL_DIR, pattern = "[.]parquet$", full.names = TRUE))
stamp_files <- sort(list.files(
  PANEL_DIR, pattern = "_stamp[.]csv$", full.names = TRUE))
panel_manifest <- normalizePath(
  file.path(PANEL_ROOT, "p6_manifest.csv"),
  winslash = "/", mustWork = TRUE)
if (length(panel_files) != 17L || length(stamp_files) != 17L) {
  stop("Expected exactly 17 panel shards and 17 stamps")
}

LMV2_P6_ESTIMATION$outcomes <- rbind(
  LMV2_P6_ESTIMATION$outcomes,
  data.frame(
    outcome = c(
      "fwcit5w_cassi_total",
      "fwcit5w_cassi_observed",
      "fwcit5w_cassi_per_patent"),
    designation = c(
      "secondary_leading", "secondary_diagnostic",
      "secondary_diagnostic"),
    interpretation = c(
      "Cassi--Ornaghi five-year forward citations, inventor-year total",
      "same total with unmatched current-data active years set missing",
      "Cassi--Ornaghi five-year forward citations per source patent"),
    stringsAsFactors = FALSE))

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=8")
DBI::dbExecute(con, "SET memory_limit='5GB'")

input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, panel_manifest)
utils::write.csv(
  input_checks, file.path(OUT_DIR, "cassi_input_checks.csv"),
  row.names = FALSE)

panel_sql <- lmv2_panel_sql(panel_files)
cassi_q <- lmv2_sql_string(CASSI_PATH)
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE cassi_source AS
  SELECT
    CAST(codinv AS BIGINT) AS codinv,
    CAST(year AS INTEGER) AS calendar_year,
    CAST(patent AS DOUBLE) AS cassi_patent_count,
    CAST(fwCit5w AS DOUBLE) AS fwcit5w
  FROM read_csv_auto(
    %s, header=TRUE, sample_size=-1, all_varchar=FALSE)
", cassi_q))

source_audit <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS source_rows,
    COUNT(DISTINCT (codinv, calendar_year)) AS unique_inventor_years,
    SUM(fwcit5w IS NULL) AS missing_fwcit5w,
    SUM(fwcit5w < 0) AS negative_fwcit5w,
    MIN(calendar_year) AS minimum_year,
    MAX(calendar_year) AS maximum_year,
    AVG(fwcit5w) AS mean_fwcit5w,
    MAX(fwcit5w) AS maximum_fwcit5w
  FROM cassi_source")
if (
    source_audit$source_rows != source_audit$unique_inventor_years ||
    source_audit$missing_fwcit5w != 0 ||
    source_audit$negative_fwcit5w != 0
) {
  stop("Cassi--Ornaghi source fails uniqueness or value audit")
}

DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE cassi_panel AS
  SELECT
    p.*,
    c.cassi_patent_count,
    c.fwcit5w AS cassi_fwcit5w_raw,
    CAST(COALESCE(c.fwcit5w, 0) AS DOUBLE) AS fwcit5w_cassi_total,
    CAST(
      CASE
        WHEN c.codinv IS NOT NULL THEN c.fwcit5w
        WHEN p.patent_count = 0 THEN 0
        ELSE NULL
      END AS DOUBLE
    ) AS fwcit5w_cassi_observed,
    CAST(
      CASE
        WHEN c.cassi_patent_count > 0
          THEN c.fwcit5w / c.cassi_patent_count
        ELSE NULL
      END AS DOUBLE
    ) AS fwcit5w_cassi_per_patent,
    c.codinv IS NOT NULL AS cassi_source_matched
  FROM %s p
  LEFT JOIN cassi_source c
    ON p.codinv = c.codinv
   AND p.calendar_year = c.calendar_year
", panel_sql))

panel_audit <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS panel_rows,
    COUNT(*) FILTER (patent_count > 0) AS current_active_rows,
    COUNT(*) FILTER (
      patent_count > 0 AND cassi_source_matched
    ) AS current_active_source_matched,
    AVG(CAST(cassi_source_matched AS INTEGER))
      FILTER (patent_count > 0) AS active_source_match_rate,
    COUNT(*) FILTER (
      patent_count > 0 AND cassi_source_matched
      AND ABS(patent_count - cassi_patent_count) < 1e-12
    ) AS exact_patent_count_matches,
    corr(patent_count, cassi_patent_count)
      FILTER (patent_count > 0 AND cassi_source_matched)
      AS patent_count_correlation,
    corr(fwd_cits5_scaled, cassi_fwcit5w_raw)
      FILTER (cassi_source_matched)
      AS oecd_cassi_citation_correlation
  FROM cassi_panel")
if (
    panel_audit$panel_rows != 5509966 ||
    panel_audit$active_source_match_rate < 0.90 ||
    panel_audit$patent_count_correlation < 0.95
) {
  stop("Cassi panel linkage audit failed")
}

coverage_audit <- DBI::dbGetQuery(con, "
  SELECT
    sample,
    event_time,
    arm,
    SUM(weight) AS design_weight,
    SUM(weight) FILTER (fwcit5w_cassi_observed IS NOT NULL)
      AS observed_weight,
    SUM(weight) FILTER (fwcit5w_cassi_observed IS NOT NULL)
      / SUM(weight) AS observed_weight_share,
    SUM(weight) FILTER (cassi_source_matched AND patent_count > 0)
      / NULLIF(SUM(weight) FILTER (patent_count > 0), 0)
      AS active_source_match_weight_share
  FROM (
    SELECT *,
      CASE
        WHEN cohort BETWEEN 1994 AND 2008 THEN 'buffered_1994_2008'
        ELSE 'full_1994_2010'
      END AS sample
    FROM cassi_panel
  )
  GROUP BY sample, event_time, arm
  ORDER BY sample, event_time, arm")

utils::write.csv(
  source_audit, file.path(OUT_DIR, "cassi_source_audit.csv"),
  row.names = FALSE)
utils::write.csv(
  panel_audit, file.path(OUT_DIR, "cassi_panel_linkage_audit.csv"),
  row.names = FALSE)
utils::write.csv(
  coverage_audit, file.path(OUT_DIR, "cassi_coverage_by_event_arm.csv"),
  row.names = FALSE)

outcomes <- c(
  "fwcit5w_cassi_total",
  "fwcit5w_cassi_observed",
  "fwcit5w_cassi_per_patent")
all_dynamic <- list()
all_pretrend <- list()
all_headline <- list()
all_coverage <- list()

for (sample_id in names(LMV2_P6_ESTIMATION$samples)) {
  cohorts <- LMV2_P6_ESTIMATION$samples[[sample_id]]
  deal_counts <- lmv2_design_deal_counts(con, "cassi_panel", cohorts)
  for (outcome in outcomes) {
    message("Estimating ", outcome, " / ", sample_id)
    fit <- lmv2_fit_outcome(
      con = con,
      panel_sql = "cassi_panel",
      outcome = outcome,
      sample_id = sample_id,
      cohorts = cohorts,
      bootstrap_reps = LMV2_P6_ESTIMATION$inference$replications,
      design_deal_counts = deal_counts)
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
rownames(dynamic) <- NULL
rownames(pretrend) <- NULL
rownames(headline) <- NULL
rownames(pair_coverage) <- NULL

utils::write.csv(
  dynamic, file.path(OUT_DIR, "cassi_fwcit5w_dynamic.csv"),
  row.names = FALSE)
utils::write.csv(
  pretrend, file.path(OUT_DIR, "cassi_fwcit5w_pretrend.csv"),
  row.names = FALSE)
utils::write.csv(
  headline, file.path(OUT_DIR, "cassi_fwcit5w_headline.csv"),
  row.names = FALSE)
utils::write.csv(
  pair_coverage, file.path(OUT_DIR, "cassi_fwcit5w_pair_coverage.csv"),
  row.names = FALSE)

governing_annual <- headline[
  headline$summary == "average_annual_t1_to_t5" &
    headline$governing, ]
if (
  nrow(governing_annual) !=
    length(outcomes) * length(LMV2_P6_ESTIMATION$samples) ||
  any(!is.finite(governing_annual$estimate)) ||
  any(governing_annual$ci_low > governing_annual$ci_high)
) {
  stop("Citation output certification failed")
}

source_paths <- c(
  CASSI_PATH, panel_files, stamp_files, panel_manifest,
  file.path(BASE, "R", "18a_lmv2_outcome_config.R"),
  file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"),
  file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"),
  file.path(BASE, "R", "26b_estimate_lmv2_cassi_fwcit5w.R"))
manifest <- data.frame(
  source_path = normalizePath(
    source_paths, winslash = "/", mustWork = TRUE),
  sha256 = vapply(
    source_paths, digest::digest, character(1),
    file = TRUE, algo = "sha256"),
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest, file.path(OUT_DIR, "cassi_source_manifest.csv"),
  row.names = FALSE)

certification <- data.frame(
  check = c(
    "original_panel_validation_passes",
    "source_unique_at_inventor_year",
    "source_has_no_missing_fwcit5w",
    "source_has_no_negative_fwcit5w",
    "panel_row_count_preserved",
    "active_source_match_rate_above_90pct",
    "patent_count_correlation_above_95pct",
    "all_six_governing_estimates_present",
    "all_governing_intervals_ordered"),
  pass = c(
    isTRUE(input_checks$pass[[1]]),
    source_audit$source_rows == source_audit$unique_inventor_years,
    source_audit$missing_fwcit5w == 0,
    source_audit$negative_fwcit5w == 0,
    panel_audit$panel_rows == 5509966,
    panel_audit$active_source_match_rate > 0.90,
    panel_audit$patent_count_correlation > 0.95,
    nrow(governing_annual) == 6,
    all(governing_annual$ci_low <= governing_annual$ci_high)),
  stringsAsFactors = FALSE)
if (!all(certification$pass)) {
  stop(
    "Citation certification failed: ",
    paste(certification$check[!certification$pass], collapse = ", "))
}
utils::write.csv(
  certification, file.path(OUT_DIR, "cassi_certification.csv"),
  row.names = FALSE)

message("Cassi--Ornaghi citation supplement built and certified: ", OUT_DIR)
