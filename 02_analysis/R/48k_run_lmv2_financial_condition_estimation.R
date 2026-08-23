#!/usr/bin/env Rscript

# Estimate the financial-condition robustness specifications after the
# outcome-blind 48j design has been frozen. The runner adds no observations,
# covariates, or cohorts. It reports: R1 certified headline; R1b headline
# weights restricted to the feasible deal set; R2 restricted roster solved on
# the original balance vector; R3 the identical roster plus financial balance.

options(stringsAsFactors = FALSE, scipen = 999)

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NA_character_) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  if (length(hit) != 1L) stop("Duplicate argument: ", flag)
  sub(paste0("^", flag, "="), "", hit)
}

CODE_ROOT <- get_arg("--code-root", "02_analysis")
PANEL_DIR <- get_arg("--panel-dir")
DESIGN_DIR <- get_arg("--design-dir")
HEADLINE_FILE <- get_arg("--headline-file")
OUTPUT_DIR <- get_arg("--output-dir")
BOOTSTRAP_REPS <- as.integer(get_arg("--bootstrap-reps", "9999"))

if (any(is.na(c(PANEL_DIR, DESIGN_DIR, HEADLINE_FILE, OUTPUT_DIR)))) {
  stop(paste0("48k requires --panel-dir=, --design-dir=, --headline-file=, ",
              "and --output-dir="))
}
for (path in c(PANEL_DIR, DESIGN_DIR)) {
  if (!dir.exists(path)) stop("Input directory missing: ", path)
}
if (!file.exists(HEADLINE_FILE)) stop("Headline file missing: ", HEADLINE_FILE)
if (dir.exists(OUTPUT_DIR) && length(list.files(
    OUTPUT_DIR, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", OUTPUT_DIR)
}
if (!is.finite(BOOTSTRAP_REPS) || BOOTSTRAP_REPS < 199L) {
  stop("At least 199 bootstrap replications are required")
}

BASE <- normalizePath(CODE_ROOT, winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c(
    "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = "")
}
sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

manifest_path <- file.path(DESIGN_DIR, "financial_design_manifest.csv")
gates_path <- file.path(DESIGN_DIR, "financial_reporting_gates.csv")
cohorts_path <- file.path(DESIGN_DIR, "financial_feasible_cohorts.csv")
deals_path <- file.path(DESIGN_DIR, "financial_feasible_deals.csv")
required_design <- c(manifest_path, gates_path, cohorts_path, deals_path,
  file.path(DESIGN_DIR, "weights", "financial_linked_original_balance.parquet"),
  file.path(DESIGN_DIR, "weights", "financial_adjusted.parquet"))
if (!all(file.exists(required_design))) {
  stop("Frozen financial design is incomplete: ",
       paste(required_design[!file.exists(required_design)], collapse = ", "))
}
manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
if (nrow(manifest) != 1L || !isTRUE(manifest$analysis_authorized[[1]])) {
  stop("Financial design did not authorize appendix estimation")
}
cohorts <- sort(utils::read.csv(cohorts_path)$cohort)
deals <- sort(utils::read.csv(deals_path)$deal_id)
if (!identical(length(cohorts), as.integer(manifest$restricted_cohorts)) ||
    !identical(length(deals), as.integer(manifest$restricted_deals))) {
  stop("Frozen cohort/deal lists disagree with the design manifest")
}

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$", full.names = TRUE
))
panel_cohorts <- as.integer(sub("^.*_c([0-9]+)\\.parquet$", "\\1", panel_files))
if (!identical(panel_cohorts, 1993:2010)) {
  stop("Base P6 panel must contain exactly the 1993--2010 cohorts")
}
base_panel_sql <- lmv2_panel_sql(panel_files)
cohort_sql <- paste(cohorts, collapse = ",")
deal_sql <- paste(deals, collapse = ",")

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")

# R1b: preserve the original P5c weights and original donor rows for retained
# deal stacks, changing only the sample composition. Control mass is
# renormalised within cohort because deletion need not preserve arm mass.
composition_sql <- sprintf(paste0(
  "(WITH f AS (SELECT * FROM %s WHERE cohort IN (%s) AND deal_id IN (%s)), ",
  "m AS (SELECT cohort, SUM(weight) FILTER(arm='treated' AND event_time=-1) tm, ",
  "SUM(weight) FILTER(arm='control' AND event_time=-1) cm FROM f GROUP BY cohort) ",
  "SELECT f.* EXCLUDE(weight), CASE WHEN arm='treated' THEN 1.0 ",
  "ELSE f.weight*m.tm/m.cm END::DOUBLE weight FROM f JOIN m USING(cohort))"
), base_panel_sql, cohort_sql, deal_sql)

make_weighted_panel_sql <- function(weight_path) {
  sprintf(paste0(
    "(SELECT p.* EXCLUDE(weight), w.final_weight::DOUBLE weight ",
    "FROM %s p INNER JOIN read_parquet(%s) w USING(roster_row_id) ",
    "WHERE p.cohort IN (%s))"
  ), base_panel_sql,
  sql_string(normalizePath(weight_path, winslash = "/", mustWork = TRUE)),
  cohort_sql)
}

specs <- list(
  composition_restricted_frozen_weights = composition_sql,
  financial_linked_original_balance = make_weighted_panel_sql(
    file.path(DESIGN_DIR, "weights", "financial_linked_original_balance.parquet")),
  financial_adjusted = make_weighted_panel_sql(
    file.path(DESIGN_DIR, "weights", "financial_adjusted.parquet"))
)

certify_panel <- function(specification, panel_sql) {
  out <- DBI::dbGetQuery(con, sprintf(paste0(
    "WITH p AS (SELECT * FROM %s), ",
    "u AS (SELECT roster_row_id, COUNT(*) n, COUNT(DISTINCT cohort) nc, ",
    "COUNT(DISTINCT deal_id) nd, COUNT(DISTINCT arm) na, ",
    "COUNT(DISTINCT codinv) ni, MIN(event_time) mine, MAX(event_time) maxe ",
    "FROM p GROUP BY roster_row_id), ",
    "m AS (SELECT cohort, SUM(weight) FILTER(arm='treated' AND event_time=-1) tm, ",
    "SUM(weight) FILTER(arm='control' AND event_time=-1) cm FROM p GROUP BY cohort) ",
    "SELECT COUNT(*) panel_rows, (SELECT COUNT(*) FROM u) units, ",
    "(SELECT COUNT(*) FROM u WHERE n<>11 OR nc<>1 OR nd<>1 OR na<>1 OR ni<>1 ",
    "OR mine<>-5 OR maxe<>5) bad_units, ",
    "(SELECT COUNT(*) FROM m WHERE ABS(tm-cm)>1e-7) bad_masses, ",
    "COUNT(*) FILTER(weight IS NULL OR NOT isfinite(weight) OR weight<=0) bad_weights, ",
    "COUNT(*) FILTER(arm='treated' AND ABS(weight-1)>1e-12) bad_treated_weights, ",
    "COUNT(DISTINCT cohort) cohorts, COUNT(DISTINCT deal_id) deals FROM p"
  ), panel_sql))
  out$specification <- specification
  out$pass <- out$bad_units == 0 & out$bad_masses == 0 &
    out$bad_weights == 0 & out$bad_treated_weights == 0 &
    out$cohorts == length(cohorts) & out$deals == length(deals)
  out
}

dynamic <- list()
pretrend <- list()
headline <- list()
coverage <- list()
certification <- list()

for (i in seq_along(specs)) {
  specification <- names(specs)[[i]]
  panel_sql <- specs[[i]]
  message(sprintf("[%d/%d] %s", i, length(specs), specification))
  certification[[i]] <- certify_panel(specification, panel_sql)
  if (!isTRUE(certification[[i]]$pass[[1]])) {
    stop("Panel certification failed for ", specification)
  }
  counts <- lmv2_design_deal_counts(con, panel_sql, cohorts)
  fitted <- lmv2_fit_outcome(
    con, panel_sql, "patent_count", specification, cohorts,
    BOOTSTRAP_REPS, counts
  )
  for (object in c("dynamic", "pretrend", "headline", "coverage")) {
    fitted[[object]]$specification <- specification
    fitted[[object]]$financial_reference <- manifest$financial_reference[[1]]
  }
  dynamic[[i]] <- fitted$dynamic
  pretrend[[i]] <- fitted$pretrend
  headline[[i]] <- fitted$headline
  coverage[[i]] <- fitted$coverage
}

headline_existing <- utils::read.csv(
  HEADLINE_FILE, stringsAsFactors = FALSE, check.names = FALSE)
headline_existing <- headline_existing[
  headline_existing$specification == "headline_all18" &
    headline_existing$outcome == "patent_count" &
    headline_existing$summary == "average_annual_t1_to_t5", ]
if (nrow(headline_existing) != 3L ||
    max(abs(headline_existing$estimate - (-0.0520603086129782))) > 1e-10) {
  stop("Certified headline comparison row is missing or stale")
}
headline_existing$specification <- "headline_full_sample"
headline_existing$financial_reference <- "not_applicable"

headline_all <- rbind(
  headline_existing[names(headline[[1]])],
  do.call(rbind, headline)
)
dynamic_all <- do.call(rbind, dynamic)
pretrend_all <- do.call(rbind, pretrend)
coverage_all <- do.call(rbind, coverage)
certification_all <- do.call(rbind, certification)

write_csv(certification_all, "financial_estimation_certification.csv")
write_csv(dynamic_all, "financial_dynamic.csv")
write_csv(pretrend_all, "financial_pretrend.csv")
write_csv(headline_all, "financial_headline.csv")
write_csv(coverage_all, "financial_coverage.csv")

governing <- headline_all[
  headline_all$summary == "average_annual_t1_to_t5" &
    headline_all$inference == "two_way_deal_inventor", ]
r2 <- governing$estimate[
  governing$specification == "financial_linked_original_balance"]
r3 <- governing$estimate[governing$specification == "financial_adjusted"]
comparison <- data.frame(
  comparison = "financial_adjusted_minus_linked_benchmark",
  estimate_difference = r3 - r2,
  relative_to_linked_absolute_estimate = (r3 - r2) / abs(r2),
  formal_difference_test = FALSE,
  interpretation = paste(
    "Descriptive paired-roster comparison; no formal test is claimed because",
    "the two specifications use different estimated weight systems."
  ),
  stringsAsFactors = FALSE
)
write_csv(comparison, "financial_weight_adjustment_comparison.csv")

estimation_manifest <- data.frame(
  version = "lmv2_financial_condition_estimation_v1",
  financial_reference = manifest$financial_reference[[1]],
  bootstrap_replications = BOOTSTRAP_REPS,
  specifications = paste(c("headline_full_sample", names(specs)), collapse = ";"),
  design_manifest_sha256 = digest::digest(
    manifest_path, file = TRUE, algo = "sha256"),
  panel_bundle_sha256 = digest::digest(vapply(
    panel_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
    algo = "sha256"),
  all_certification_pass = all(certification_all$pass),
  main_text_eligible = manifest$main_text_eligible[[1]],
  placement = manifest$placement[[1]],
  stringsAsFactors = FALSE
)
write_csv(estimation_manifest, "financial_estimation_manifest.csv")
message("Financial-condition estimation complete: ", manifest$financial_reference[[1]])
