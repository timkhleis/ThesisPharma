#!/usr/bin/env Rscript

# Independent certification of the financial-condition robustness artifacts.
# This script does not estimate any model. It verifies the frozen common
# roster, weight integrity, balance, panel certification, reported inference,
# and the outcome-blind placement decision.

options(stringsAsFactors = FALSE, scipen = 999)

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NA_character_) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  if (length(hit) != 1L) stop("Duplicate argument: ", flag)
  sub(paste0("^", flag, "="), "", hit)
}

CODE_ROOT <- get_arg("--code-root", "02_analysis")
DESIGN_DIR <- get_arg("--design-dir")
ESTIMATION_DIR <- get_arg("--estimation-dir")
OUTPUT_DIR <- get_arg("--output-dir", ESTIMATION_DIR)
if (any(is.na(c(DESIGN_DIR, ESTIMATION_DIR, OUTPUT_DIR)))) {
  stop("48l requires --design-dir= and --estimation-dir=")
}

BASE <- normalizePath(CODE_ROOT, winslash = "/", mustWork = TRUE)
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

read_csv <- function(dir, name) {
  path <- file.path(dir, name)
  if (!file.exists(path)) stop("Missing certification input: ", path)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
design <- read_csv(DESIGN_DIR, "financial_design_manifest.csv")
gates <- read_csv(DESIGN_DIR, "financial_reporting_gates.csv")
balance <- read_csv(DESIGN_DIR, "financial_balance_before_after.csv")
diagnostics <- read_csv(DESIGN_DIR, "financial_weight_diagnostics.csv")
estimation <- read_csv(ESTIMATION_DIR, "financial_estimation_manifest.csv")
panel_cert <- read_csv(ESTIMATION_DIR, "financial_estimation_certification.csv")
headline <- read_csv(ESTIMATION_DIR, "financial_headline.csv")
comparison <- read_csv(
  ESTIMATION_DIR, "financial_weight_adjustment_comparison.csv")

linked_path <- file.path(
  DESIGN_DIR, "weights", "financial_linked_original_balance.parquet")
adjusted_path <- file.path(
  DESIGN_DIR, "weights", "financial_adjusted.parquet")
if (!all(file.exists(c(linked_path, adjusted_path)))) {
  stop("Certified weight files are missing")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
q <- function(path) DBI::dbQuoteString(
  con, normalizePath(path, winslash = "/", mustWork = TRUE))
weight_checks <- DBI::dbGetQuery(con, sprintf(paste0(
  "WITH l AS (SELECT * FROM read_parquet(%s)), ",
  "a AS (SELECT * FROM read_parquet(%s)), ",
  "roster_diff AS ((SELECT roster_row_id FROM l EXCEPT SELECT roster_row_id FROM a) ",
  "UNION ALL (SELECT roster_row_id FROM a EXCEPT SELECT roster_row_id FROM l)), ",
  "allw AS (SELECT 'linked' spec,* FROM l UNION ALL SELECT 'adjusted' spec,* FROM a), ",
  "m AS (SELECT spec,cohort,SUM(final_weight) FILTER(treated=1) tm, ",
  "SUM(final_weight) FILTER(treated=0) cm FROM allw GROUP BY spec,cohort) ",
  "SELECT (SELECT COUNT(*) FROM roster_diff) roster_differences, ",
  "COUNT(*) FILTER(final_weight IS NULL OR NOT isfinite(final_weight) OR final_weight<=0) bad_weights, ",
  "COUNT(*) FILTER(treated=1 AND ABS(final_weight-1)>1e-12) bad_treated_weights, ",
  "(SELECT COUNT(*) FROM m WHERE ABS(tm-cm)>1e-7) bad_cohort_masses, ",
  "COUNT(DISTINCT roster_row_id) unique_roster_rows, COUNT(*) total_weight_rows FROM allw"
), q(linked_path), q(adjusted_path)))

annual <- headline[headline$summary == "average_annual_t1_to_t5", ]
expected_specs <- c(
  "headline_full_sample", "composition_restricted_frozen_weights",
  "financial_linked_original_balance", "financial_adjusted"
)
after <- balance[balance$stage == "after" & is.finite(balance$abs_difference), ]
common_diag <- diagnostics[diagnostics$common_feasible_cohort, ]

checks <- data.frame(
  check = c(
    "design_authorized_appendix_estimation",
    "design_and_estimation_reference_agree",
    "design_manifest_hash_agrees",
    "identical_linked_and_adjusted_rosters",
    "finite_positive_weights",
    "treated_weights_equal_one",
    "cohort_arm_masses_equal",
    "all_after_balance_smd_below_0_10",
    "all_common_design_cells_pass",
    "all_estimation_panels_pass",
    "four_specifications_three_inference_rows",
    "headline_reproduces_certified_att",
    "all_reported_p_values_valid",
    "paired_roster_difference_labelled_descriptive",
    "placement_is_outcome_blind"
  ),
  pass = c(
    isTRUE(design$analysis_authorized[[1]]),
    identical(as.character(design$financial_reference[[1]]),
              as.character(estimation$financial_reference[[1]])),
    identical(
      digest::digest(file.path(DESIGN_DIR, "financial_design_manifest.csv"),
                     file = TRUE, algo = "sha256"),
      estimation$design_manifest_sha256[[1]]),
    weight_checks$roster_differences == 0,
    weight_checks$bad_weights == 0,
    weight_checks$bad_treated_weights == 0,
    weight_checks$bad_cohort_masses == 0,
    nrow(after) > 0 && max(after$abs_difference) <= 0.10,
    nrow(common_diag) > 0 && all(common_diag$passed),
    nrow(panel_cert) == 3L && all(panel_cert$pass),
    nrow(annual) == 12L &&
      setequal(unique(annual$specification), expected_specs) &&
      setequal(unique(annual$inference), c(
        "deal_wild_bootstrap_t", "two_way_deal_inventor",
        "deal_cluster_robust")),
    max(abs(annual$estimate[annual$specification == "headline_full_sample"] -
              (-0.0520603086129782))) <= 1e-10,
    all(annual$p_value[is.finite(annual$p_value)] >= 0 &
          annual$p_value[is.finite(annual$p_value)] <= 1),
    !isTRUE(comparison$formal_difference_test[[1]]),
    identical(design$placement[[1]], if (all(gates$pass)) {
      "main_table_and_appendix"
    } else "appendix_only") &&
      identical(design$placement[[1]], estimation$placement[[1]])
  ),
  stringsAsFactors = FALSE
)
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  checks, file.path(OUTPUT_DIR, "financial_robustness_certification.csv"),
  row.names = FALSE)
if (!all(checks$pass)) {
  stop("Financial robustness certification failed: ",
       paste(checks$check[!checks$pass], collapse = ", "))
}

tw <- annual[annual$inference == "two_way_deal_inventor", ]
row_for <- function(spec) tw[tw$specification == spec, , drop = FALSE]
r2 <- row_for("financial_linked_original_balance")
r3 <- row_for("financial_adjusted")
report <- c(
  "# Financial-condition robustness certification",
  "",
  paste0("Financial reference: `", design$financial_reference[[1]], "`."),
  sprintf(
    "The common feasible sample contains %d treated inventors from %d acquisitions in %d cohorts (effective deal count %.2f).",
    design$restricted_treated, design$restricted_deals,
    design$restricted_cohorts, design$effective_treated_deals),
  sprintf(
    "Linked-sample benchmark: ATT %.4f (SE %.4f, 95%% CI [%.4f, %.4f], p=%.3f).",
    r2$estimate, r2$se, r2$ci_low, r2$ci_high, r2$p_value),
  sprintf(
    "Financially adjusted: ATT %.4f (SE %.4f, 95%% CI [%.4f, %.4f], p=%.3f).",
    r3$estimate, r3$se, r3$ci_low, r3$ci_high, r3$p_value),
  sprintf(
    "Descriptive R3-R2 difference: %.4f annual patents per inventor.",
    comparison$estimate_difference),
  paste0("Outcome-blind placement decision: `", design$placement[[1]], "`."),
  "",
  "All certification checks passed."
)
writeLines(
  report, file.path(OUTPUT_DIR, "financial_robustness_certified_summary.md"),
  useBytes = TRUE)
message("Financial robustness certification passed: ",
        design$financial_reference[[1]])
