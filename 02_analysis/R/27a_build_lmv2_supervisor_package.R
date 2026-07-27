#!/usr/bin/env Rscript

# =============================================================================
# 27a_build_lmv2_supervisor_package.R
#
# Purpose
# -------
# Build the concise, shareable supervisor package for the Local Match v2
# full-cohort results. The script reads certified P5c/P6 result files and the
# already-produced stage-14 descriptive tables. It does not re-estimate any
# outcome and it does not modify or archive the analysis pipeline.
#
# Inputs
# ------
# - Certified P6 full-cohort result tables and certifications.
# - Certified quantity-communication tables and certification.
# - Certified initially retained-inventor design and result summaries.
# - Stage-14 descriptive LaTeX tables from the thesis root.
# - Final P6 figure PDFs.
# - A human-readable LaTeX template in 02_analysis/notes/.
#
# Outputs
# -------
# 02_analysis/output/results/local_match_v2/supervisor_package/
# - local_match_v2_supervisor_results.tex
# - local_match_v2_supervisor_results.pdf
# - local_match_v2_supervisor_email.txt
# - generated_values.tex and generated result tables
# - source_manifest.csv, output_manifest.csv, certification.csv
# - copied figure and descriptive-table assets
#
# Assumptions
# -----------
# - The P6 and quantity-package certification files contain only passing rows.
# - The stage-14 descriptive package exists in the main thesis root.
# - pdflatex is available on PATH.
#
# Execution
# ---------
# From the lmv2-p6-outcomes worktree root:
#   & 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' `
#     02_analysis\R\27a_build_lmv2_supervisor_package.R
#
# Design principle
# ----------------
# Numerical claims are formatted from certified CSVs. The prose and document
# hierarchy live in a readable LaTeX template. A staging directory is built
# first; only a fully compiled and certified package replaces the prior output.
# =============================================================================

options(stringsAsFactors = FALSE, scipen = 999)

# ---- Path discovery ----------------------------------------------------------

script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) == 1L) {
    return(normalizePath(sub("^--file=", "", hit), winslash = "/", mustWork = TRUE))
  }
  normalizePath(file.path(getwd(), "02_analysis", "R",
                          "27a_build_lmv2_supervisor_package.R"),
                winslash = "/", mustWork = TRUE)
}

SCRIPT_FILE <- script_path()
SCRIPT_DIR <- dirname(SCRIPT_FILE)
ANALYSIS_DIR <- normalizePath(file.path(SCRIPT_DIR, ".."),
                              winslash = "/", mustWork = TRUE)
WORKTREE_ROOT <- normalizePath(file.path(ANALYSIS_DIR, ".."),
                               winslash = "/", mustWork = TRUE)
THESIS_ROOT <- normalizePath(file.path(WORKTREE_ROOT, "..", ".."),
                             winslash = "/", mustWork = TRUE)

P6_DIR <- file.path(
  ANALYSIS_DIR, "output", "audit", "local_match_v2",
  "P6_FULLCOHORT_RESULTS_PACKAGE"
)
QUANTITY_DIR <- file.path(
  ANALYSIS_DIR, "output", "audit", "local_match_v2",
  "P6_QUANTITY_COMMUNICATION_PACKAGE"
)
STAYER_ROOT_CANDIDATES <- c(
  file.path(ANALYSIS_DIR, "output", "audit", "local_match_v2"),
  "C:/Users/timkh/.codex/worktrees/081f/Thesis/02_analysis/output/audit/local_match_v2"
)
STAYER_ROOT <- STAYER_ROOT_CANDIDATES[
  dir.exists(file.path(STAYER_ROOT_CANDIDATES, "P5B_STAYER_S3")) &
    dir.exists(file.path(STAYER_ROOT_CANDIDATES, "P5B_STAYER_S4_RESULTS"))
][1]
if (is.na(STAYER_ROOT)) {
  stop("Certified stayer-result directories were not found.", call. = FALSE)
}
STAYER_S3_DIR <- file.path(STAYER_ROOT, "P5B_STAYER_S3")
STAYER_S4_DIR <- file.path(STAYER_ROOT, "P5B_STAYER_S4_RESULTS")
FIGURE_DIR <- file.path(
  ANALYSIS_DIR, "output", "figures", "local_match_v2", "fullcohort_results"
)
DESCRIPTIVE_DIR <- file.path(
  THESIS_ROOT, "02_analysis", "output", "results", "data_section"
)
TEMPLATE_FILE <- file.path(
  ANALYSIS_DIR, "notes", "local_match_v2_supervisor_package_template.tex"
)

OUTPUT_PARENT <- file.path(
  ANALYSIS_DIR, "output", "results", "local_match_v2"
)
OUTPUT_DIR <- file.path(OUTPUT_PARENT, "supervisor_package")
STAGING_DIR <- file.path(
  OUTPUT_PARENT, sprintf(".supervisor_package_staging_%s", Sys.getpid())
)

# ---- Small, explicit helpers -------------------------------------------------

stopf <- function(fmt, ...) stop(sprintf(fmt, ...), call. = FALSE)

require_files <- function(paths) {
  missing <- paths[!file.exists(paths)]
  if (length(missing)) {
    stopf("Required input(s) missing:\n%s", paste(missing, collapse = "\n"))
  }
  invisible(paths)
}

read_csv <- function(path) {
  utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}

write_utf8 <- function(lines, path) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeLines(enc2utf8(lines), con = con, useBytes = TRUE)
  invisible(path)
}

fmt_num <- function(x, digits = 4L) {
  if (length(x) != 1L || !is.finite(x)) stopf("Expected one finite number.")
  formatC(x, format = "f", digits = digits)
}

fmt_abs <- function(x, digits = 4L) fmt_num(abs(x), digits)

fmt_pct <- function(x, digits = 1L) fmt_num(100 * x, digits)

fmt_int <- function(x) {
  format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE)
}

fmt_p <- function(x) {
  if (x < 0.0001) return("<0.0001")
  fmt_num(x, 4L)
}

fmt_sci_tex <- function(x, digits = 1L) {
  if (length(x) != 1L || !is.finite(x) || x == 0) return("0")
  exponent <- floor(log10(abs(x)))
  coefficient <- x / (10^exponent)
  sprintf("%s\\times 10^{%d}", fmt_num(coefficient, digits), exponent)
}

tex_macro <- function(name, value) {
  sprintf("\\newcommand{\\%s}{%s}", name, value)
}

tex_ci <- function(est, lo, hi, digits = 4L) {
  sprintf("$%s$ & $[%s,\\ %s]$",
          fmt_num(est, digits), fmt_num(lo, digits), fmt_num(hi, digits))
}

md5 <- function(paths) {
  unname(tools::md5sum(paths))
}

is_subpath <- function(path, parent) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  parent <- normalizePath(parent, winslash = "/", mustWork = TRUE)
  startsWith(tolower(paste0(path, "/")), tolower(paste0(parent, "/")))
}

safe_reset_dir <- function(path, parent, expected_basename = NULL) {
  if (!is_subpath(path, parent)) {
    stopf("Refusing to reset directory outside expected parent: %s", path)
  }
  if (!is.null(expected_basename) && basename(path) != expected_basename) {
    stopf("Refusing to reset unexpected directory name: %s", path)
  }
  if (dir.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(path)) stopf("Could not create directory: %s", path)
  invisible(path)
}

copy_checked <- function(from, to) {
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(from, to, overwrite = TRUE, copy.date = TRUE)
  if (!isTRUE(ok) || !file.exists(to)) {
    stopf("Failed to copy %s to %s", from, to)
  }
  invisible(to)
}

# ---- Declared inputs ---------------------------------------------------------

input_files <- c(
  SCRIPT_FILE,
  TEMPLATE_FILE,
  file.path(P6_DIR, "d1_design_sequence_summary.csv"),
  file.path(P6_DIR, "d2_design_summary.csv"),
  file.path(P6_DIR, "d3_patent_count_loyo.csv"),
  file.path(P6_DIR, "d4_margin_decomposition.csv"),
  file.path(P6_DIR, "d5_secondary_outcomes.csv"),
  file.path(P6_DIR, "d5_all_outcomes_pretrend_tests.csv"),
  file.path(P6_DIR, "final_package_certification.csv"),
  file.path(QUANTITY_DIR, "quantity_results_appendix.csv"),
  file.path(QUANTITY_DIR, "quantity_post_weighted_means.csv"),
  file.path(QUANTITY_DIR, "quantity_loyo_heldout_placebos.csv"),
  file.path(QUANTITY_DIR, "quantity_loyo_sign_breakdown.csv"),
  file.path(QUANTITY_DIR, "quantity_package_certification.csv"),
  file.path(STAYER_S3_DIR, "s3_summary.csv"),
  file.path(STAYER_S3_DIR, "s3_certification.csv"),
  file.path(STAYER_S4_DIR, "s4_certification.csv"),
  file.path(STAYER_S4_DIR, "reporting", "s4_governing_results.csv"),
  file.path(STAYER_S4_DIR, "reporting",
            "s4_primary_inference_comparison.csv"),
  file.path(STAYER_S4_DIR, "reporting", "s4_primary_magnitude.csv"),
  file.path(STAYER_S4_DIR, "reporting",
            "s4_loyo_heldout_diagnostics.csv"),
  file.path(STAYER_S4_DIR, "reporting",
            "figure_s4_patent_paths_and_event_study.pdf"),
  file.path(DESCRIPTIVE_DIR, "table1_sample_construction.tex"),
  file.path(DESCRIPTIVE_DIR, "table3_overall_descriptives.tex"),
  file.path(DESCRIPTIVE_DIR, "table4_deal_inventor_concentration.tex"),
  file.path(DESCRIPTIVE_DIR, "output_manifest.csv"),
  file.path(FIGURE_DIR, "figure_d1_design_sequence.pdf"),
  file.path(FIGURE_DIR, "figure_d2_love_plot.pdf"),
  file.path(FIGURE_DIR, "figure_d3_patent_count_loyo.pdf"),
  file.path(FIGURE_DIR, "figure_d5a_all_outcomes_event_study_full.pdf")
)
require_files(input_files)

# ---- Read and validate certified sources ------------------------------------

d1 <- read_csv(file.path(P6_DIR, "d1_design_sequence_summary.csv"))
d2 <- read_csv(file.path(P6_DIR, "d2_design_summary.csv"))
d3 <- read_csv(file.path(P6_DIR, "d3_patent_count_loyo.csv"))
d4 <- read_csv(file.path(P6_DIR, "d4_margin_decomposition.csv"))
d5 <- read_csv(file.path(P6_DIR, "d5_secondary_outcomes.csv"))
pretests <- read_csv(file.path(P6_DIR, "d5_all_outcomes_pretrend_tests.csv"))
appendix <- read_csv(file.path(QUANTITY_DIR, "quantity_results_appendix.csv"))
post_means <- read_csv(file.path(QUANTITY_DIR, "quantity_post_weighted_means.csv"))
placebos <- read_csv(file.path(QUANTITY_DIR, "quantity_loyo_heldout_placebos.csv"))
breakdown <- read_csv(file.path(QUANTITY_DIR, "quantity_loyo_sign_breakdown.csv"))
p6_cert <- read_csv(file.path(P6_DIR, "final_package_certification.csv"))
quantity_cert <- read_csv(file.path(
  QUANTITY_DIR, "quantity_package_certification.csv"
))
stayer_s3_summary <- read_csv(file.path(STAYER_S3_DIR, "s3_summary.csv"))
stayer_s3_cert <- read_csv(file.path(STAYER_S3_DIR, "s3_certification.csv"))
stayer_s4_cert <- read_csv(file.path(STAYER_S4_DIR, "s4_certification.csv"))
stayer_results <- read_csv(file.path(
  STAYER_S4_DIR, "reporting", "s4_governing_results.csv"
))
stayer_inference <- read_csv(file.path(
  STAYER_S4_DIR, "reporting", "s4_primary_inference_comparison.csv"
))
stayer_magnitude <- read_csv(file.path(
  STAYER_S4_DIR, "reporting", "s4_primary_magnitude.csv"
))
stayer_placebos <- read_csv(file.path(
  STAYER_S4_DIR, "reporting", "s4_loyo_heldout_diagnostics.csv"
))

validate_certification <- function(x, label) {
  if (!all(c("check", "pass") %in% names(x))) {
    stopf("%s certification has an unexpected schema.", label)
  }
  passed <- tolower(as.character(x$pass)) == "true"
  if (anyNA(passed) || !all(passed)) {
    failed <- x$check[is.na(passed) | !passed]
    stopf("%s certification failed: %s", label, paste(failed, collapse = ", "))
  }
  TRUE
}

design_value <- function(label, data = d2) {
  out <- data$value[data$statistic == label]
  if (length(out) != 1L || !is.finite(out)) {
    stopf("Expected one finite design statistic named '%s'.", label)
  }
  out
}

validate_design <- function(data) {
  eligible_i <- design_value("Eligible treated inventors", data)
  supported_i <- design_value("Supported treated inventors", data)
  retention_i <- design_value("Inventor retention", data)
  eligible_d <- design_value("Eligible deals", data)
  supported_d <- design_value("Supported/estimating deals", data)
  retention_d <- design_value("Deal retention", data)

  if (supported_i > eligible_i || supported_d > eligible_d) {
    stopf("Supported counts cannot exceed eligible counts.")
  }
  if (abs(supported_i / eligible_i - retention_i) > 1e-10) {
    stopf("Inventor-retention statistic is inconsistent with counts.")
  }
  if (abs(supported_d / eligible_d - retention_d) > 1e-10) {
    stopf("Deal-retention statistic is inconsistent with counts.")
  }
  TRUE
}

invisible(validate_certification(p6_cert, "P6 full-cohort"))
invisible(validate_certification(quantity_cert, "Quantity communication"))
invisible(validate_certification(stayer_s3_cert, "Stayer design"))
invisible(validate_certification(stayer_s4_cert, "Stayer results"))
invisible(validate_design(d2))

stayer_value <- function(label) {
  out <- suppressWarnings(as.numeric(
    stayer_s3_summary$value[stayer_s3_summary$metric == label]
  ))
  if (length(out) != 1L || !is.finite(out)) {
    stopf("Expected one finite stayer statistic named '%s'.", label)
  }
  out
}

headline <- d3[d3$design == "P5c headline" &
                 d3$sample == "full_1994_2010", , drop = FALSE]
if (nrow(headline) != 1L) stopf("Expected one full-sample headline result.")

buffered <- appendix[
  appendix$design == "P5c headline" &
    appendix$sample == "buffered_1994_2008" &
    appendix$effect_scale == "per inventor-year",
  , drop = FALSE
]
if (nrow(buffered) != 1L) stopf("Expected one buffered headline result.")

loyo <- d3[grepl("^LOYO:", d3$design), , drop = FALSE]
if (nrow(loyo) != 5L) stopf("Expected exactly five LOYO rows.")

expected_outcomes <- c(
  "active_patenting", "pqii_scaled", "tech_drift", "fwcit5w_cassi_total"
)
if (!all(expected_outcomes %in% d5$outcome)) {
  stopf("Secondary-outcome table is incomplete.")
}
if (nrow(placebos) != 5L || !setequal(placebos$held_out_event_time, -5:-1)) {
  stopf("Held-out placebo grid is incomplete.")
}
if (nrow(post_means) != 2L || !setequal(post_means$arm, c("treated", "control"))) {
  stopf("Post-period weighted means are incomplete.")
}
if (nrow(breakdown) != 1L) stopf("Expected one sign-breakdown row.")

# Tooth-test the count/retention guard with a real positive case. This proves
# the check can fail, rather than merely appearing in the certification list.
bad_d2 <- d2
bad_d2$value[bad_d2$statistic == "Supported treated inventors"] <-
  design_value("Eligible treated inventors") + 1
guard_tooth_test_fired <- inherits(
  try(validate_design(bad_d2), silent = TRUE), "try-error"
)
if (!guard_tooth_test_fired) {
  stopf("Design-validation tooth test did not fire.")
}

# ---- Extract formatted values ------------------------------------------------

eligible_inventors <- design_value("Eligible treated inventors")
supported_inventors <- design_value("Supported treated inventors")
eligible_deals <- design_value("Eligible deals")
supported_deals <- design_value("Supported/estimating deals")
inventor_retention <- design_value("Inventor retention")
deal_retention <- design_value("Deal retention")
min_retention <- design_value("Minimum cohort inventor retention")
min_ess_ratio <- design_value("Minimum reuse-adjusted ESS / treated count")
max_smd <- design_value("Maximum post-weighting absolute SMD")
effective_deals <- design_value("Effective treated deals")

raw_att <- d1$estimate[
  d1$comparison == "Unmatched placebo average annual ATT, t=1..5"
]
raw_p <- d1$p_value[
  d1$comparison == "Unmatched placebo average annual ATT, t=1..5"
]
if (length(raw_att) != 1L || length(raw_p) != 1L) {
  stopf("Raw placebo ATT row missing or duplicated.")
}

comparable_loyo <- loyo[loyo$design != "LOYO: hold out t=-1", , drop = FALSE]
max_loyo_deviation <- max(abs(comparable_loyo$estimate - headline$estimate))
max_loyo_pct <- max_loyo_deviation / abs(headline$estimate)

control <- post_means[post_means$arm == "control", , drop = FALSE]
treated <- post_means[post_means$arm == "treated", , drop = FALSE]
extensive <- d4[d4$margin == "Extensive: probability of patenting", ]
intensive <- d4[d4$margin == "Intensive: patents per active inventor-year", ]
if (nrow(extensive) != 1L || nrow(intensive) != 1L) {
  stopf("Margin decomposition is incomplete.")
}

secondary_row <- function(outcome, sample) {
  out <- d5[d5$outcome == outcome & d5$sample == sample, , drop = FALSE]
  if (nrow(out) != 1L) {
    stopf("Expected one secondary row for %s / %s.", outcome, sample)
  }
  out
}

active_full <- secondary_row("active_patenting", "full_1994_2010")
pqii_full <- secondary_row("pqii_scaled", "full_1994_2010")
citation_full <- secondary_row("fwcit5w_cassi_total", "full_1994_2010")

stayer_headline <- stayer_results[
  stayer_results$inference == "deal_wild_bootstrap_t" &
    stayer_results$outcome == "patent_count" &
    stayer_results$sample == "full_1994_2010" &
    stayer_results$spec == "primary_count_active_scale",
  , drop = FALSE
]
stayer_two_way <- stayer_inference[
  stayer_inference$inference == "two_way_deal_inventor" &
    stayer_inference$outcome == "patent_count" &
    stayer_inference$sample == "full_1994_2010" &
    stayer_inference$spec == "primary_count_active_scale",
  , drop = FALSE
]
stayer_buffered <- stayer_results[
  stayer_results$inference == "deal_wild_bootstrap_t" &
    stayer_results$outcome == "patent_count" &
    stayer_results$sample == "buffered_1994_2008" &
    stayer_results$spec == "primary_count_active_scale",
  , drop = FALSE
]
stayer_mag <- stayer_magnitude[
  stayer_magnitude$sample == "full_1994_2010" &
    stayer_magnitude$outcome == "patent_count",
  , drop = FALSE
]
if (nrow(stayer_headline) != 1L || nrow(stayer_two_way) != 1L ||
    nrow(stayer_buffered) != 1L || nrow(stayer_mag) != 1L) {
  stopf("Certified stayer headline rows are missing or duplicated.")
}
stayer_eligible <- stayer_value("primary_eligible_treated")
stayer_supported <- stayer_value("primary_supported_treated")
stayer_retention <- stayer_value("primary_pooled_retention")
stayer_deals <- stayer_value("primary_supported_deals")
stayer_effective_deals <- stayer_value("primary_effective_treated_deals")
stayer_max_smd <- stayer_value("production_max_smd_after")
stayer_largest_deal_share <- stayer_value("primary_largest_deal_share")
stayer_m3 <- stayer_placebos[
  stayer_placebos$sample == "full_1994_2010" &
    stayer_placebos$outcome == "patent_count" &
    stayer_placebos$event_time == -3,
  , drop = FALSE
]
stayer_m2 <- stayer_placebos[
  stayer_placebos$sample == "full_1994_2010" &
    stayer_placebos$outcome == "patent_count" &
    stayer_placebos$event_time == -2,
  , drop = FALSE
]
if (nrow(stayer_m3) != 1L || nrow(stayer_m2) != 1L) {
  stopf("Certified stayer held-out diagnostics are incomplete.")
}

input_hashes <- md5(input_files)
hash_seed <- tempfile("supervisor_build_hash_")
write_utf8(paste(input_hashes, collapse = ""), hash_seed)
build_id <- substr(md5(hash_seed), 1L, 12L)
unlink(hash_seed)

# ---- Prepare staging directory and assets -----------------------------------

dir.create(OUTPUT_PARENT, recursive = TRUE, showWarnings = FALSE)
safe_reset_dir(STAGING_DIR, OUTPUT_PARENT)
dir.create(file.path(STAGING_DIR, "assets"), recursive = TRUE, showWarnings = FALSE)

asset_sources <- c(
  file.path(DESCRIPTIVE_DIR, "table1_sample_construction.tex"),
  file.path(DESCRIPTIVE_DIR, "table3_overall_descriptives.tex"),
  file.path(DESCRIPTIVE_DIR, "table4_deal_inventor_concentration.tex"),
  file.path(FIGURE_DIR, "figure_d1_design_sequence.pdf"),
  file.path(FIGURE_DIR, "figure_d2_love_plot.pdf"),
  file.path(FIGURE_DIR, "figure_d3_patent_count_loyo.pdf"),
  file.path(FIGURE_DIR, "figure_d5a_all_outcomes_event_study_full.pdf"),
  file.path(STAYER_S4_DIR, "reporting",
            "figure_s4_patent_paths_and_event_study.pdf")
)
for (src in asset_sources) {
  copy_checked(src, file.path(STAGING_DIR, "assets", basename(src)))
}

# Stage-14 tables are valid stand-alone floats. In this short memo they should
# appear exactly where introduced; otherwise LaTeX can insert a descriptive
# table midway through the design narrative. Only the copied assets are
# modified--the certified stage-14 originals remain untouched.
descriptive_tex_assets <- file.path(
  STAGING_DIR, "assets",
  c("table1_sample_construction.tex", "table3_overall_descriptives.tex",
    "table4_deal_inventor_concentration.tex")
)
for (path in descriptive_tex_assets) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- gsub("\\\\begin\\{table\\}\\[!htbp\\]",
                "\\\\begin{table}[H]", lines, perl = TRUE)
  write_utf8(lines, path)
}

# Clarify that the 11 rows per inventor are constructed event-time cells, not
# observed patent records. The exact multiples (29,170*11 and 24,468*11) are a
# feature of the balanced g-5,...,g+5 grid.
sample_table_path <- file.path(
  STAGING_DIR, "assets", "table1_sample_construction.tex"
)
sample_lines <- readLines(sample_table_path, warn = FALSE, encoding = "UTF-8")
sample_lines <- sub(
  "Inventor-year observations",
  "Potential event-time cells",
  sample_lines,
  fixed = TRUE
)
note_line <- grep("\\\\textit\\{Notes:\\}", sample_lines)
if (length(note_line) != 1L) stopf("Unexpected sample-table note structure.")
sample_lines[note_line] <- paste0(
  "\\textit{Notes:} Event-time cells form the potential balanced ",
  "$g-5$ to $g+5$ grid (eleven cells per inventor, including zero-patent ",
  "years); they are not observed patent records."
)
write_utf8(sample_lines, sample_table_path)

# Focal-group tenure can exceed patent career age because the affiliation
# spell may begin before the inventor's first patent. The statistic is valid
# but distracting in a short supervisor memo, so omit only the copied display
# row; the certified stage-14 source table remains unchanged.
descriptive_table_path <- file.path(
  STAGING_DIR, "assets", "table3_overall_descriptives.tex"
)
descriptive_lines <- readLines(
  descriptive_table_path, warn = FALSE, encoding = "UTF-8"
)
tenure_row <- grepl("^Focal-group tenure \\(years\\)", descriptive_lines)
if (sum(tenure_row) != 1L) stopf("Unexpected focal-tenure row structure.")
descriptive_lines <- descriptive_lines[!tenure_row]
write_utf8(descriptive_lines, descriptive_table_path)

# ---- Generate values and tables ---------------------------------------------

value_lines <- c(
  tex_macro("BuildDate", format(Sys.Date(), "%d %B %Y")),
  tex_macro("BuildID", build_id),
  tex_macro("EligibleInventors", fmt_int(eligible_inventors)),
  tex_macro("SupportedInventors", fmt_int(supported_inventors)),
  tex_macro("EligibleDeals", fmt_int(eligible_deals)),
  tex_macro("SupportedDeals", fmt_int(supported_deals)),
  tex_macro("InventorRetentionPct", fmt_pct(inventor_retention)),
  tex_macro("DealRetentionPct", fmt_pct(deal_retention)),
  tex_macro("MinimumRetentionPct", fmt_pct(min_retention)),
  tex_macro("MinESSPct", fmt_pct(min_ess_ratio)),
  tex_macro("EffectiveDeals", fmt_num(effective_deals, 1L)),
  tex_macro("MaxSMD", fmt_sci_tex(max_smd)),
  tex_macro("RawPlaceboATT", fmt_num(raw_att, 4L)),
  tex_macro("RawPlaceboP", fmt_p(raw_p)),
  tex_macro("HeadlineATT", fmt_num(headline$estimate, 4L)),
  tex_macro("AnnualMagnitude", fmt_abs(headline$estimate, 3L)),
  tex_macro("HeadlineLow", fmt_num(headline$ci_low, 4L)),
  tex_macro("HeadlineHigh", fmt_num(headline$ci_high, 4L)),
  tex_macro("HeadlineP", fmt_p(headline$p_value)),
  tex_macro("CumulativeMagnitude", fmt_abs(5 * headline$estimate, 3L)),
  tex_macro("PreDeclinePct",
            fmt_pct(abs(headline$relative_to_pre_treatment_output))),
  tex_macro("CounterfactualDeclinePct",
            fmt_pct(abs(headline$relative_to_matched_post_counterfactual))),
  tex_macro("BufferedATT", fmt_num(buffered$estimate, 4L)),
  tex_macro("BufferedP", fmt_p(buffered$p_value)),
  tex_macro("LOYOMin", fmt_num(min(comparable_loyo$estimate), 4L)),
  tex_macro("LOYOMax", fmt_num(max(comparable_loyo$estimate), 4L)),
  tex_macro("MaxLOYOPct", fmt_pct(max_loyo_pct)),
  tex_macro("BreakdownMultiple",
            fmt_num(breakdown$breakdown_multiple_of_maximum_heldout_gap, 2L)),
  tex_macro("ControlPostMean", fmt_num(control$patent_mean, 3L)),
  tex_macro("TreatedPostMean", fmt_num(treated$patent_mean, 3L)),
  tex_macro("ControlActivePct", fmt_pct(control$active_rate, 2L)),
  tex_macro("TreatedActivePct", fmt_pct(treated$active_rate, 2L)),
  tex_macro("ActiveDropPP",
            fmt_num(100 * (control$active_rate - treated$active_rate), 2L)),
  tex_macro("ControlIntensive", fmt_num(control$patents_per_active_year, 2L)),
  tex_macro("TreatedIntensive", fmt_num(treated$patents_per_active_year, 2L)),
  tex_macro("ExtensiveSharePct", fmt_pct(extensive$share_of_total_decline)),
  tex_macro("IntensiveSharePct", fmt_pct(intensive$share_of_total_decline)),
  tex_macro("ActiveP", fmt_p(active_full$p_value)),
  tex_macro("PQIIP", fmt_p(pqii_full$p_value)),
  tex_macro("CitationP", fmt_p(citation_full$p_value)),
  tex_macro("StayerEligible", fmt_int(stayer_eligible)),
  tex_macro("StayerSupported", fmt_int(stayer_supported)),
  tex_macro("StayerRetentionPct", fmt_pct(stayer_retention)),
  tex_macro("StayerDeals", fmt_int(stayer_deals)),
  tex_macro("StayerEffectiveDeals", fmt_num(stayer_effective_deals, 1L)),
  tex_macro("StayerMaxSMD", fmt_sci_tex(stayer_max_smd)),
  tex_macro("StayerLargestDealPct", fmt_pct(stayer_largest_deal_share)),
  tex_macro("StayerATT", fmt_num(stayer_headline$estimate, 3L)),
  tex_macro("StayerCumulative", fmt_num(stayer_mag$cumulative_five_year_att, 3L)),
  tex_macro("StayerCounterfactual", fmt_num(
    stayer_mag$matched_counterfactual_post_mean, 3L
  )),
  tex_macro("StayerObserved", fmt_num(
    stayer_mag$observed_treated_post_mean, 3L
  )),
  tex_macro("StayerCounterfactualPct", fmt_pct(
    abs(stayer_mag$att_share_of_counterfactual)
  )),
  tex_macro("StayerPrePct", fmt_pct(
    abs(stayer_mag$att_share_of_pre_treatment_mean)
  )),
  tex_macro("StayerWildLow", fmt_num(stayer_headline$ci_low, 3L)),
  tex_macro("StayerWildHigh", fmt_num(stayer_headline$ci_high, 3L)),
  tex_macro("StayerWildP", fmt_p(stayer_headline$p_value)),
  tex_macro("StayerTwoWayLow", fmt_num(stayer_two_way$ci_low, 3L)),
  tex_macro("StayerTwoWayHigh", fmt_num(stayer_two_way$ci_high, 3L)),
  tex_macro("StayerTwoWayP", fmt_p(stayer_two_way$p_value)),
  tex_macro("StayerBufferedATT", fmt_num(stayer_buffered$estimate, 3L)),
  tex_macro("StayerBufferedP", fmt_p(stayer_buffered$p_value)),
  tex_macro("StayerMThreeGap", fmt_num(stayer_m3$estimate, 3L)),
  tex_macro("StayerMTwoGap", fmt_num(stayer_m2$estimate, 3L))
)
write_utf8(value_lines, file.path(STAGING_DIR, "generated_values.tex"))

design_table <- c(
  "\\small",
  "\\begin{tabularx}{\\textwidth}{@{}Y r@{}}",
  "\\toprule",
  "Statistic & Value \\\\",
  "\\midrule",
  sprintf("Supported treated inventors & %s of %s (%s\\%%) \\\\",
          fmt_int(supported_inventors), fmt_int(eligible_inventors),
          fmt_pct(inventor_retention)),
  sprintf("Supported acquisition deals & %s of %s (%s\\%%) \\\\",
          fmt_int(supported_deals), fmt_int(eligible_deals),
          fmt_pct(deal_retention)),
  sprintf("Minimum cohort inventor retention & %s\\%% \\\\",
          fmt_pct(min_retention)),
  sprintf("Minimum reuse-adjusted control ESS / treated count & %s\\%% \\\\",
          fmt_pct(min_ess_ratio)),
  sprintf("Maximum post-weighting absolute SMD & $%s$ \\\\",
          fmt_sci_tex(max_smd)),
  sprintf("Nominal / effective treated deals & %s / %s \\\\",
          fmt_int(supported_deals), fmt_num(effective_deals, 1L)),
  "\\bottomrule",
  "\\end{tabularx}",
  "\\sourceNote{Counts and diagnostics are read from the frozen P5c roster and",
  "certified P6 design summary. ESS incorporates control reuse.}"
)
write_utf8(design_table, file.path(STAGING_DIR, "generated_design_table.tex"))

loyo_order <- match(
  c("LOYO: hold out t=-5", "LOYO: hold out t=-4", "LOYO: hold out t=-3",
    "LOYO: hold out t=-2", "LOYO: hold out t=-1"),
  loyo$design
)
loyo_sorted <- loyo[loyo_order, , drop = FALSE]
loyo_labels <- c("$t=-5$", "$t=-4$", "$t=-3$", "$t=-2$", "$t=-1$*")
loyo_rows <- vapply(seq_len(nrow(loyo_sorted)), function(i) {
  sprintf("%s & %s & $[%s,\\ %s]$ & %s \\\\",
          loyo_labels[i],
          fmt_num(loyo_sorted$estimate[i], 4L),
          fmt_num(loyo_sorted$ci_low[i], 4L),
          fmt_num(loyo_sorted$ci_high[i], 4L),
          fmt_p(loyo_sorted$p_value[i]))
}, character(1))
loyo_table <- c(
  "\\begin{table}[H]",
  "\\centering",
  "\\caption{Post-treatment effects under each LOYO design}",
  "\\label{tab:loyo}",
  "\\small",
  "\\begin{tabular}{lrrr}",
  "\\toprule",
  "Held-out year & ATT & 95\\% CI & $p$-value \\\\",
  "\\midrule",
  loyo_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\sourceNote{Average annual ATT over $t=+1,\\ldots,+5$. Governing",
  "deal-level wild-bootstrap inference. *The $t=-1$ design uses $t=-4$ as",
  "its reference and is not point-comparable to the other rows.}",
  "\\end{table}"
)
write_utf8(loyo_table, file.path(STAGING_DIR, "generated_loyo_table.tex"))

margin_table <- c(
  "\\begin{table}[H]",
  "\\centering",
  "\\caption{Extensive- and intensive-margin decomposition}",
  "\\label{tab:margins}",
  "\\small",
  "\\begin{tabularx}{0.82\\textwidth}{@{}Yrr@{}}",
  "\\toprule",
  "Component & Contribution & Share of decline \\\\",
  "\\midrule",
  sprintf("Probability of patenting & %s & %s\\%% \\\\",
          fmt_num(extensive$contribution, 4L),
          fmt_pct(extensive$share_of_total_decline)),
  sprintf("Patents in active inventor-years & %s & %s\\%% \\\\",
          fmt_num(intensive$contribution, 4L),
          fmt_pct(intensive$share_of_total_decline)),
  "\\midrule",
  sprintf("Total annual patent-count ATT & %s & 100.0\\%% \\\\",
          fmt_num(extensive$contribution + intensive$contribution, 4L)),
  "\\bottomrule",
  "\\end{tabularx}",
  "\\sourceNote{Contributions are in patents per inventor-year and sum exactly",
  "to the headline ATT. The intensive component is descriptive because active",
  "patenting is itself a post-treatment outcome.}",
  "\\end{table}"
)
write_utf8(margin_table, file.path(STAGING_DIR, "generated_margin_table.tex"))

placebos <- placebos[order(placebos$held_out_event_time), , drop = FALSE]
placebo_rows <- vapply(seq_len(nrow(placebos)), function(i) {
  sprintf("$t=%d$ & %s & $[%s,\\ %s]$ \\\\",
          placebos$held_out_event_time[i],
          fmt_num(placebos$estimate[i], 3L),
          fmt_num(placebos$ci_low[i], 3L),
          fmt_num(placebos$ci_high[i], 3L))
}, character(1))
placebo_table <- c(
  "\\begin{table}[H]",
  "\\centering",
  "\\caption{Genuinely held-out pre-period gaps}",
  "\\label{tab:placebos}",
  "\\small",
  "\\begin{tabular}{lrr}",
  "\\toprule",
  "Held-out year & Gap & 95\\% CI \\\\",
  "\\midrule",
  placebo_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\sourceNote{Each row comes from a separately weighted design that excludes",
  "the named year from its patent-count and active-patenting balance targets.}",
  "\\end{table}"
)
write_utf8(placebo_table, file.path(STAGING_DIR, "generated_placebo_table.tex"))

secondary_specs <- data.frame(
  outcome = expected_outcomes,
  label = c("Probability of patenting", "OECD PQII", "TechDrift",
            "Five-year forward citations"),
  stringsAsFactors = FALSE
)
secondary_rows <- vapply(seq_len(nrow(secondary_specs)), function(i) {
  full <- secondary_row(secondary_specs$outcome[i], "full_1994_2010")
  buff <- secondary_row(secondary_specs$outcome[i], "buffered_1994_2008")
  sprintf(
    "%s & %s $[%s,\\ %s]$ & %s $[%s,\\ %s]$ \\\\",
    secondary_specs$label[i],
    fmt_num(full$estimate, 4L), fmt_num(full$ci_low, 4L),
    fmt_num(full$ci_high, 4L),
    fmt_num(buff$estimate, 4L), fmt_num(buff$ci_low, 4L),
    fmt_num(buff$ci_high, 4L)
  )
}, character(1))
secondary_table <- c(
  "\\begin{table}[H]",
  "\\centering",
  "\\caption{Average annual effects on secondary outcomes}",
  "\\label{tab:secondary}",
  "\\footnotesize",
  "\\begin{tabularx}{\\textwidth}{@{}Yrr@{}}",
  "\\toprule",
  "Outcome & 1994--2010 ATT [95\\% CI] & 1994--2008 ATT [95\\% CI] \\\\",
  "\\midrule",
  secondary_rows,
  "\\bottomrule",
  "\\end{tabularx}",
  "\\sourceNote{The probability, TechDrift, and citation rows use deal-level",
  "wild-bootstrap inference. PQII uses the prominent two-way deal/inventor",
  "clustered interval because OECD linkage changes the observed inventor set.}",
  "\\end{table}"
)
write_utf8(secondary_table, file.path(STAGING_DIR, "generated_secondary_table.tex"))

stayer_table <- c(
  "\\begin{table}[H]",
  "\\centering",
  "\\caption{Initially retained inventors: design and patent-count result}",
  "\\label{tab:stayer-brief}",
  "\\small",
  "\\begin{tabularx}{\\textwidth}{@{}Y r@{}}",
  "\\toprule",
  "Statistic & Certified result \\\\",
  "\\midrule",
  sprintf("Matched initially retained inventors & %s of %s (%s\\%%) \\\\",
          fmt_int(stayer_supported), fmt_int(stayer_eligible),
          fmt_pct(stayer_retention)),
  sprintf("Nominal / effective treated deals & %s / %s \\\\",
          fmt_int(stayer_deals), fmt_num(stayer_effective_deals, 1L)),
  sprintf("Maximum post-weighting absolute SMD & $%s$ \\\\",
          fmt_sci_tex(stayer_max_smd)),
  sprintf("Observed / matched counterfactual post mean & %s / %s \\\\",
          fmt_num(stayer_mag$observed_treated_post_mean, 3L),
          fmt_num(stayer_mag$matched_counterfactual_post_mean, 3L)),
  sprintf("Annual ATT; five-year cumulative ATT & %s; %s \\\\",
          fmt_num(stayer_headline$estimate, 3L),
          fmt_num(stayer_mag$cumulative_five_year_att, 3L)),
  sprintf("Deal wild-bootstrap 95\\%% CI; $p$-value & $[%s,\\ %s]$; %s \\\\",
          fmt_num(stayer_headline$ci_low, 3L),
          fmt_num(stayer_headline$ci_high, 3L),
          fmt_p(stayer_headline$p_value)),
  sprintf("Two-way clustered 95\\%% CI; $p$-value & $[%s,\\ %s]$; %s \\\\",
          fmt_num(stayer_two_way$ci_low, 3L),
          fmt_num(stayer_two_way$ci_high, 3L),
          fmt_p(stayer_two_way$p_value)),
  "\\bottomrule",
  "\\end{tabularx}",
  "\\sourceNote{Separate initially retained-inventor support and entropy",
  "weights. The deal-level wild bootstrap governs the headline inference;",
  "the two-way deal/inventor interval is shown because controls can recur.}",
  "\\end{table}"
)
write_utf8(stayer_table, file.path(STAGING_DIR, "generated_stayer_table.tex"))

# ---- Materialize the memo and email -----------------------------------------

memo_tex <- file.path(STAGING_DIR, "local_match_v2_supervisor_results.tex")
copy_checked(TEMPLATE_FILE, memo_tex)
memo_text <- paste(readLines(memo_tex, warn = FALSE, encoding = "UTF-8"),
                   collapse = "\n")
if (grepl("@@[A-Z0-9_]+@@", memo_text, perl = TRUE)) {
  stopf("Unresolved template placeholder found in the supervisor memo.")
}

email_lines <- c(
  "Subject: Thesis results package - full target-inventor cohort",
  "",
  "Dear Professors,",
  "",
  "I am sending a short results package for the full target-inventor-cohort",
  "analysis. The attached memo is designed for a 15-20 minute read and begins",
  "with the decisions on which I would particularly value your guidance:",
  "",
  "1. whether the proposed 35-page thesis structure is appropriately balanced;",
  paste0(
    "2. whether the technological-relatedness section should remain a full ",
    "main-text section or be shortened, with the extended tests moved to the ",
    "appendix."
  ),
  "",
  sprintf(
    paste0("The main estimate is %s fewer patents per inventor-year over the ",
           "five post-acquisition years (95%% CI [%s, %s], p=%s)."),
    fmt_abs(headline$estimate, 4L), fmt_num(headline$ci_low, 4L),
    fmt_num(headline$ci_high, 4L), fmt_p(headline$p_value)
  ),
  sprintf(
    paste0("This corresponds to a %s%% decline relative to average pre-deal ",
           "output and %s%% of the matched post-deal counterfactual."),
    fmt_pct(abs(headline$relative_to_pre_treatment_output)),
    fmt_pct(abs(headline$relative_to_matched_post_counterfactual))
  ),
  "",
  "The memo also explains why the conventional unmatched Callaway-Sant'Anna",
  "design is not credible in this sample, how recruitment clocks and inventor",
  "lifecycles motivate the placebo-cohort and entropy-balancing design, and how",
  "the result behaves when each pre-treatment year is left out of the balance",
  "constraints. All LOYO estimates remain negative and significant, although",
  "the held-out t=-3 and t=-2 gaps make us wary about parallel trends and",
  "limit the strength of the causal interpretation.",
  "",
  "The memo now also includes a one-page summary for initially retained",
  "inventors. Its separately balanced estimate is economically larger but",
  "less precise, and I present it as a selected-group result rather than as an",
  "unqualified causal effect for an always-retained population.",
  "",
  "I would be very grateful for your feedback on the proposed structure, the",
  "appropriate strength of the causal wording, and the scope of the",
  "technological-relatedness section.",
  "",
  "Best regards,",
  "Tim"
)
write_utf8(email_lines, file.path(STAGING_DIR,
                                  "local_match_v2_supervisor_email.txt"))

# ---- Compile LaTeX -----------------------------------------------------------

pdflatex <- Sys.which("pdflatex")
if (!nzchar(pdflatex)) stopf("pdflatex was not found on PATH.")

old_wd <- getwd()
on.exit(setwd(old_wd), add = TRUE)
setwd(STAGING_DIR)
compile_log <- file.path(STAGING_DIR, "pdflatex_build.log")
if (file.exists(compile_log)) unlink(compile_log)

for (pass in 1:2) {
  status <- system2(
    pdflatex,
    args = c("-interaction=nonstopmode", "-halt-on-error",
             "local_match_v2_supervisor_results.tex"),
    stdout = compile_log,
    stderr = compile_log
  )
  if (is.null(status) || is.na(status) || status != 0) {
    stopf("pdflatex failed on pass %d. See %s", pass, compile_log)
  }
}
setwd(old_wd)

memo_pdf <- file.path(STAGING_DIR, "local_match_v2_supervisor_results.pdf")
require_files(memo_pdf)

# Remove TeX intermediates after a successful build. The source, final PDF,
# and all reproducibility manifests remain; transient compiler files do not.
tex_intermediates <- list.files(
  STAGING_DIR, pattern = "\\.(aux|log|out)$", full.names = TRUE
)
if (length(tex_intermediates)) unlink(tex_intermediates, force = TRUE)

# ---- Manifests and certification --------------------------------------------

source_manifest <- data.frame(
  source = normalizePath(input_files, winslash = "/", mustWork = TRUE),
  md5 = input_hashes,
  stringsAsFactors = FALSE
)
utils::write.csv(source_manifest, file.path(STAGING_DIR, "source_manifest.csv"),
                 row.names = FALSE, na = "")

certification <- data.frame(
  check = c(
    "p6_certification_passes",
    "quantity_certification_passes",
    "stayer_design_certification_passes",
    "stayer_results_certification_passes",
    "design_guard_tooth_test_fired",
    "stage14_descriptive_tables_present",
    "five_loyo_rows_present",
    "secondary_outcome_grid_complete",
    "no_unresolved_template_placeholders",
    "memo_omits_shapley_label",
    "memo_omits_buffered_appendix_figure",
    "memo_tex_exists",
    "memo_pdf_exists",
    "email_draft_exists"
  ),
  pass = c(
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    guard_tooth_test_fired,
    all(file.exists(file.path(
      STAGING_DIR, "assets",
      c("table1_sample_construction.tex", "table3_overall_descriptives.tex",
        "table4_deal_inventor_concentration.tex")
    ))),
    nrow(loyo) == 5L,
    all(expected_outcomes %in% d5$outcome),
    !grepl("@@[A-Z0-9_]+@@", memo_text, perl = TRUE),
    !grepl("Shapley", memo_text, fixed = TRUE),
    !grepl("figure_d5b_all_outcomes_event_study_buffered", memo_text,
           fixed = TRUE),
    file.exists(memo_tex),
    file.exists(memo_pdf),
    file.exists(file.path(STAGING_DIR, "local_match_v2_supervisor_email.txt"))
  ),
  stringsAsFactors = FALSE
)
if (!all(certification$pass)) {
  stopf("Supervisor-package certification failed: %s",
        paste(certification$check[!certification$pass], collapse = ", "))
}
utils::write.csv(certification, file.path(STAGING_DIR, "certification.csv"),
                 row.names = FALSE, na = "")

output_files <- list.files(STAGING_DIR, recursive = TRUE, full.names = TRUE)
output_manifest <- data.frame(
  artifact = substring(normalizePath(output_files, winslash = "/"),
                       nchar(normalizePath(STAGING_DIR, winslash = "/")) + 2L),
  bytes = file.info(output_files)$size,
  md5 = md5(output_files),
  stringsAsFactors = FALSE
)
utils::write.csv(output_manifest, file.path(STAGING_DIR, "output_manifest.csv"),
                 row.names = FALSE, na = "")

# Publish only after the staged build has compiled and certified. The output
# directory is dedicated to this package, so resetting it cannot affect
# analysis inputs or other result packages.
safe_reset_dir(OUTPUT_DIR, OUTPUT_PARENT, expected_basename = "supervisor_package")
published <- list.files(STAGING_DIR, all.files = TRUE, no.. = TRUE,
                        full.names = TRUE)
for (src in published) {
  dest <- file.path(OUTPUT_DIR, basename(src))
  if (dir.exists(src)) {
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
    children <- list.files(src, all.files = TRUE, no.. = TRUE,
                           recursive = TRUE, full.names = TRUE)
    for (child in children) {
      rel <- substring(normalizePath(child, winslash = "/"),
                       nchar(normalizePath(src, winslash = "/")) + 2L)
      copy_checked(child, file.path(dest, rel))
    }
  } else {
    copy_checked(src, dest)
  }
}

safe_reset_dir(STAGING_DIR, OUTPUT_PARENT)
unlink(STAGING_DIR, recursive = TRUE, force = TRUE)

message("Supervisor package built and certified.")
message("PDF: ", file.path(OUTPUT_DIR, "local_match_v2_supervisor_results.pdf"))
message("LaTeX: ", file.path(OUTPUT_DIR, "local_match_v2_supervisor_results.tex"))
message("Email: ", file.path(OUTPUT_DIR, "local_match_v2_supervisor_email.txt"))
