# ============================================================================
# Full-cohort DiD closeout: design, balance, quantity, and support exhibits
# ============================================================================
#
# This script assembles already-frozen P5/P6 results. It does not alter the
# support roster, balance constraints, weights, outcome panel, or estimand.
#
# Run from the repository root on `main`:
# Rscript 02_analysis/R/26a_build_lmv2_fullcohort_closeout.R

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (pkg in c("DBI", "duckdb", "digest", "ggplot2", "gridExtra")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}
source(file.path(BASE, "R", "00_lmv2_visual_style.R"))

THESIS_ROOT <- normalizePath(
  ".", winslash = "/", mustWork = TRUE)
P5_ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2")
AUDIT_ROOT <- file.path(BASE, "output", "audit", "local_match_v2")
OUT_DIR <- file.path(AUDIT_ROOT, "P6_FULLCOHORT_RESULTS_PACKAGE")
FIG_DIR <- file.path(
  BASE, "output", "figures", "local_match_v2", "fullcohort_results")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

must_exist <- function(path) {
  if (!file.exists(path)) stop("Missing required input: ", path)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}
read_csv <- function(path) {
  utils::read.csv(must_exist(path), stringsAsFactors = FALSE)
}
assert_close <- function(actual, expected, tolerance, label) {
  if (length(actual) != 1L || length(expected) != 1L ||
      !is.finite(actual) || !is.finite(expected) ||
      abs(actual - expected) > tolerance) {
    stop(
      label, " mismatch: actual=", format(actual, digits = 16),
      ", expected=", format(expected, digits = 16))
  }
  invisible(TRUE)
}

# Tooth-test the numerical guard.
guard_fired <- FALSE
tryCatch(
  assert_close(0, 1, 1e-9, "guard tooth-test"),
  error = function(e) guard_fired <<- TRUE)
if (!guard_fired) stop("assert_close tooth-test did not fire")

# ---------------------------------------------------------------------------
# D0: authoritative descriptive-artifact manifest
# ---------------------------------------------------------------------------

DATA_SECTION <- file.path(
  THESIS_ROOT, "02_analysis", "output", "results", "data_section")
descriptive_paths <- c(
  file.path(DATA_SECTION, "table1_descriptive_statistics.tex"),
  file.path(DATA_SECTION, "table1_sample_construction.csv"),
  file.path(DATA_SECTION, "table3_overall_descriptive_statistics.csv"),
  file.path(DATA_SECTION, "table4_largest_deals_by_target_inventors.csv"),
  file.path(DATA_SECTION, "table4_deal_inventor_concentration.tex"),
  file.path(DATA_SECTION, "data_section_deal_concentration_paragraph.tex"))
descriptive_paths <- vapply(
  descriptive_paths, must_exist, character(1), USE.NAMES = FALSE)
descriptive_manifest <- data.frame(
  package = "D0_descriptive_statistics",
  artifact = basename(descriptive_paths),
  source_path = descriptive_paths,
  sha256 = vapply(
    descriptive_paths, digest::digest, character(1),
    file = TRUE, algo = "sha256"),
  stringsAsFactors = FALSE)
utils::write.csv(
  descriptive_manifest,
  file.path(OUT_DIR, "d0_descriptive_artifact_manifest.csv"),
  row.names = FALSE)

# ---------------------------------------------------------------------------
# D1: conventional CS, recruitment-clock fingerprint, and unmatched placebo
# ---------------------------------------------------------------------------

CS_PATH <- file.path(
  THESIS_ROOT, "02_analysis", "output", "results", "supervisor_memo",
  "did_dynamic_simultaneous_bands.csv")
GAP_PATH <- file.path(
  THESIS_ROOT, "02_analysis", "output", "audit", "qualifying_year_split",
  "qualifying_gap_by_event_time.csv")
RAW_DIR <- file.path(AUDIT_ROOT, "P6_APPENDIX_RAW_DID")
cs <- read_csv(CS_PATH)
gap <- read_csv(GAP_PATH)
raw_dynamic <- read_csv(file.path(RAW_DIR, "raw_did_dynamic_estimates.csv"))
raw_paths <- read_csv(
  file.path(RAW_DIR, "raw_did_standardized_mean_paths.csv"))
raw_post <- read_csv(file.path(RAW_DIR, "raw_did_post_att.csv"))
raw_pre <- read_csv(file.path(RAW_DIR, "raw_did_joint_pretrend.csv"))

cs_plot_data <- cs[cs$outcome == "active_patenting", ]
p_cs <- ggplot2::ggplot(
  cs_plot_data,
  ggplot2::aes(event_time, att, ymin = ci_low, ymax = ci_high)) +
  ggplot2::geom_hline(yintercept = 0, colour = LMV2_COLOURS["mid_grey"]) +
  ggplot2::geom_vline(
    xintercept = -0.5, colour = LMV2_COLOURS["mid_grey"],
    linetype = "dashed") +
  ggplot2::geom_errorbar(
    width = 0.12, colour = LMV2_COLOURS["brick"]) +
  ggplot2::geom_line(colour = LMV2_COLOURS["brick"], linewidth = 0.7) +
  ggplot2::geom_point(colour = LMV2_COLOURS["brick"], size = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    title = "A. Conventional CS(2021) is not credible as-is",
    subtitle = "All not-yet-treated controls; no placebo cohorts or matching.",
    x = "Event time", y = "ATT: probability of patenting") +
  lmv2_theme(10, "none")

gap_plot_data <- gap[
  gap$outcome == "log_patent_count" &
    gap$qualifying_gap %in% 1:5, ]
gap_plot_data$qualifying_gap <- factor(gap_plot_data$qualifying_gap)
p_gap <- ggplot2::ggplot(
  gap_plot_data,
  ggplot2::aes(
    event_time, estimate, colour = qualifying_gap,
    group = qualifying_gap)) +
  ggplot2::geom_vline(
    xintercept = -0.5, colour = LMV2_COLOURS["mid_grey"],
    linetype = "dashed") +
  ggplot2::geom_line(linewidth = 0.75) +
  ggplot2::geom_point(size = 1.5) +
  ggplot2::scale_colour_manual(values = LMV2_CATEGORICAL_5) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    title = "B. The pre-deal hump follows the recruitment clock",
    subtitle = "Each qualifying-year group peaks in its own qualifying year.",
    x = "Event time", y = "Mean log(1 + patents)",
    colour = "Qualifying-year gap") +
  lmv2_theme(10, "bottom") +
  ggplot2::theme(legend.title = ggplot2::element_text(size = 8))

raw_paths <- raw_paths[raw_paths$specification == "full_cohort_unmatched", ]
raw_paths$group <- ifelse(
  raw_paths$arm == "treated",
  "Acquisition-treated", "Placebo-treated controls")
p_raw_paths <- ggplot2::ggplot(
  raw_paths,
  ggplot2::aes(
    event_time, mean_patent_count, colour = group,
    linetype = group, shape = group)) +
  ggplot2::geom_vline(
    xintercept = -0.5, colour = LMV2_COLOURS["mid_grey"]) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 2) +
  ggplot2::scale_colour_manual(values = stats::setNames(
    unname(LMV2_COLOURS[c("forest", "slate_blue")]),
    c("Acquisition-treated", "Placebo-treated controls"))) +
  ggplot2::scale_linetype_manual(values = c(
    "Acquisition-treated" = "solid",
    "Placebo-treated controls" = "longdash")) +
  ggplot2::scale_shape_manual(values = c(
    "Acquisition-treated" = 16,
    "Placebo-treated controls" = 17)) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    title = "C. Placebo timing aligns clocks but not lifecycles",
    subtitle = "Unmatched placebo-cohort paths retain pre-period differences.",
    x = "Event time", y = "Mean patent applications") +
  lmv2_theme(10, "bottom")

raw_dynamic_full <- raw_dynamic[
  raw_dynamic$specification == "full_cohort_unmatched", ]
p_raw_att <- ggplot2::ggplot(
  raw_dynamic_full,
  ggplot2::aes(
    event_time, estimate, ymin = ci_low, ymax = ci_high)) +
  ggplot2::geom_hline(yintercept = 0, colour = LMV2_COLOURS["mid_grey"]) +
  ggplot2::geom_vline(
    xintercept = -0.5, colour = LMV2_COLOURS["mid_grey"]) +
  ggplot2::geom_errorbar(
    width = 0.12, colour = LMV2_COLOURS["slate_blue"]) +
  ggplot2::geom_line(colour = LMV2_COLOURS["slate_blue"], linewidth = 0.75) +
  ggplot2::geom_point(colour = LMV2_COLOURS["slate_blue"], size = 1.9) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    title = "D. Unmatched placebo DiD",
    subtitle = "Post ATT is near zero, but the joint pretrend test rejects.",
    x = "Event time", y = "Difference-in-differences estimate") +
  lmv2_theme(10, "none")

design_sequence <- gridExtra::arrangeGrob(
  p_cs, p_gap, p_raw_paths, p_raw_att, ncol = 2)
lmv2_save_figure(
  design_sequence,
  file.path(FIG_DIR, "figure_d1_design_sequence"),
  width = 11, height = 8.2)

raw_summary <- data.frame(
  comparison = c(
    "Unmatched placebo average annual ATT, t=1..5",
    "Unmatched placebo joint pretrend, t=-5..-2"),
  estimate = c(
    raw_post$estimate[
      raw_post$specification == "full_cohort_unmatched" &
        raw_post$summary == "average_annual_t1_to_t5"],
    raw_pre$f_stat[raw_pre$specification == "full_cohort_unmatched"]),
  p_value = c(
    raw_post$p_value[
      raw_post$specification == "full_cohort_unmatched" &
        raw_post$summary == "average_annual_t1_to_t5"],
    raw_pre$p_value[raw_pre$specification == "full_cohort_unmatched"]),
  statistic = c("ATT", "F statistic"),
  stringsAsFactors = FALSE)
utils::write.csv(
  raw_summary, file.path(OUT_DIR, "d1_design_sequence_summary.csv"),
  row.names = FALSE)

# ---------------------------------------------------------------------------
# D2: final support, retention, ESS, and balance
# ---------------------------------------------------------------------------

FINAL_P5 <- file.path(P5_ROOT, "P5_PRODUCTION_FINAL", "finalized")
gates <- read_csv(file.path(FINAL_P5, "realized_gate_checks.csv"))
coverage <- read_csv(file.path(FINAL_P5, "realized_coverage_by_cohort.csv"))
selection <- read_csv(
  file.path(FINAL_P5, "realized_retained_vs_unsupported.csv"))
P5C_PROD <- file.path(P5_ROOT, "P5C_ANNUAL_TRAJECTORY", "production")
diag <- read_csv(file.path(P5C_PROD, "p5c_cell_diagnostics.csv"))
diag <- diag[grepl("^b64ec", diag$execution_hash), ]
if (nrow(diag) != 17L) stop("Expected 17 frozen P5c diagnostics")

balance_files <- list.files(
  file.path(P5C_PROD, "balance"),
  pattern = "_b64ecb850b84[.]csv$", full.names = TRUE)
if (length(balance_files) != 17L) {
  stop("Expected 17 frozen P5c balance files")
}
balance <- do.call(rbind, lapply(balance_files, read_csv))
balance <- balance[
  balance$stage %in% c("before", "after") &
    !duplicated(balance[c("cohort", "variable", "stage")]), ]
balance_max <- stats::aggregate(
  abs_difference ~ variable + stage, balance, max)
names(balance_max)[names(balance_max) == "abs_difference"] <- "max_abs_smd"

pretty_variable <- c(
  patent_count_m5 = "Patent count t=-5",
  patent_count_m4 = "Patent count t=-4",
  patent_count_m3 = "Patent count t=-3",
  patent_count_m2 = "Patent count t=-2",
  patent_count_m1 = "Patent count t=-1",
  active_patenting_m5 = "Active patenting t=-5",
  active_patenting_m4 = "Active patenting t=-4",
  active_patenting_m3 = "Active patenting t=-3",
  active_patenting_m2 = "Active patenting t=-2",
  active_patenting_m1 = "Active patenting t=-1",
  career_age = "Career age",
  focal_group_exclusivity = "Focal-group exclusivity",
  firm_log_patent_stock_5y = "Firm patent stock",
  firm_log_inventor_count_5y = "Firm inventor count",
  firm_patent_trajectory = "Firm patent trajectory")
balance_max$label <- unname(pretty_variable[balance_max$variable])
if (anyNA(balance_max$label)) {
  stop(
    "Unlabelled balance variables: ",
    paste(unique(balance_max$variable[is.na(balance_max$label)]), collapse = ", "))
}
before_order <- balance_max[
  balance_max$stage == "before", c("label", "max_abs_smd")]
before_order <- before_order[order(before_order$max_abs_smd), ]
balance_max$label <- factor(
  balance_max$label, levels = before_order$label)
balance_max$stage_label <- factor(
  balance_max$stage,
  levels = c("before", "after"),
  labels = c("Before entropy balancing", "After entropy balancing"))

p_love <- ggplot2::ggplot(
  balance_max,
  ggplot2::aes(
    max_abs_smd, label, colour = stage_label, shape = stage_label)) +
  ggplot2::geom_vline(
    xintercept = 0.1, linetype = "dashed",
    colour = LMV2_COLOURS["amber"]) +
  ggplot2::geom_point(size = 2.5) +
  ggplot2::scale_colour_manual(values = stats::setNames(
    unname(LMV2_COLOURS[c("brick", "forest")]),
    c("Before entropy balancing", "After entropy balancing"))) +
  ggplot2::scale_shape_manual(values = c(
    "Before entropy balancing" = 17,
    "After entropy balancing" = 16)) +
  ggplot2::labs(
    title = "Entropy balancing removes observable pre-treatment differences",
    subtitle = paste(
      "Each point is the largest absolute SMD across 17 acquisition cohorts;",
      "the dashed line marks 0.10."),
    x = "Maximum absolute standardized mean difference",
    y = NULL) +
  lmv2_theme(10.5, "bottom")
lmv2_save_figure(
  p_love, file.path(FIG_DIR, "figure_d2_love_plot"),
  width = 7.7, height = 5.8)

design_summary <- data.frame(
  statistic = c(
    "Eligible treated inventors",
    "Supported treated inventors",
    "Inventor retention",
    "Eligible deals",
    "Supported/estimating deals",
    "Deal retention",
    "Minimum cohort inventor retention",
    "Minimum reuse-adjusted ESS / treated count",
    "Maximum post-weighting absolute SMD",
    "Effective treated deals"),
  value = c(
    sum(coverage$eligible),
    sum(coverage$supported),
    gates$realized[gates$gate == "aggregate_inventor_coverage"],
    343,
    341,
    gates$realized[gates$gate == "aggregate_deal_coverage"],
    min(coverage$coverage),
    min(diag$reuse_adjusted_ess_ratio),
    max(diag$max_all_balanced_smd_after),
    36.9368780846092),
  unit = c(
    "inventors", "inventors", "share", "deals", "deals", "share",
    "share", "ratio", "SMD", "effective deals"),
  stringsAsFactors = FALSE)
assert_close(
  design_summary$value[
    design_summary$statistic == "Inventor retention"],
  27078 / 29170, 1e-12, "Inventor retention")
assert_close(
  design_summary$value[design_summary$statistic == "Deal retention"],
  341 / 343, 1e-12, "Deal retention")
utils::write.csv(
  design_summary, file.path(OUT_DIR, "d2_design_summary.csv"),
  row.names = FALSE)
utils::write.csv(
  balance_max, file.path(OUT_DIR, "d2_balance_max_by_variable.csv"),
  row.names = FALSE)
utils::write.csv(
  selection, file.path(OUT_DIR, "d2_supported_vs_unsupported.csv"),
  row.names = FALSE)

# ---------------------------------------------------------------------------
# D3: headline and leave-one-pre-year-out (LOYO) stability
# ---------------------------------------------------------------------------

QUANTITY_DIR <- file.path(AUDIT_ROOT, "P6_QUANTITY_COMMUNICATION_PACKAGE")
quantity <- read_csv(file.path(QUANTITY_DIR, "quantity_results_appendix.csv"))
loyo <- quantity[
  quantity$sample == "full_1994_2010" &
    quantity$effect_scale == "per inventor-year" &
    (quantity$design == "P5c headline" |
       grepl("^LOYO:", quantity$design)), ]
loyo$order <- match(
  loyo$design,
  c(
    "P5c headline", "LOYO: hold out t=-5", "LOYO: hold out t=-4",
    "LOYO: hold out t=-3", "LOYO: hold out t=-2",
    "LOYO: hold out t=-1"))
loyo <- loyo[order(loyo$order), ]
loyo$label <- c(
  "Headline: balance all five years", "Hold out t=-5", "Hold out t=-4",
  "Hold out t=-3", "Hold out t=-2", "Hold out t=-1")
loyo$label <- factor(loyo$label, levels = rev(loyo$label))
loyo$type <- ifelse(
  loyo$design == "P5c headline", "Headline estimate",
  "Robustness estimate")

p_loyo <- ggplot2::ggplot(
  loyo,
  ggplot2::aes(
    estimate, label, xmin = ci_low, xmax = ci_high, colour = type)) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"]) +
  ggplot2::geom_errorbar(
    orientation = "y", width = 0.18, linewidth = 0.65) +
  ggplot2::geom_point(size = 2.6) +
  ggplot2::scale_colour_manual(values = stats::setNames(
    unname(LMV2_COLOURS[c("forest", "slate_blue")]),
    c("Headline estimate", "Robustness estimate"))) +
  ggplot2::labs(
    title = "The patent-count result survives every held-out pre-year",
    subtitle = paste(
      "Average annual ATT over t=1,...,5; 95% deal-level wild-bootstrap",
      "confidence intervals."),
    x = "Patent applications per inventor-year", y = NULL) +
  lmv2_theme(10.5, "bottom")
lmv2_save_figure(
  p_loyo, file.path(FIG_DIR, "figure_d3_patent_count_loyo"),
  width = 7.4, height = 4.5)
utils::write.csv(
  loyo, file.path(OUT_DIR, "d3_patent_count_loyo.csv"),
  row.names = FALSE)

# ---------------------------------------------------------------------------
# D4: extensive/intensive accounting decomposition
# ---------------------------------------------------------------------------

margins <- read_csv(
  file.path(QUANTITY_DIR, "quantity_margin_decomposition.csv"))
post_means <- read_csv(
  file.path(QUANTITY_DIR, "quantity_post_weighted_means.csv"))
headlines <- read_csv(
  file.path(AUDIT_ROOT, "P6_P5C_ESTIMATION_COUNT_ACTIVE",
            "p6_headline_post_att.csv"))
active <- headlines[
  headlines$outcome == "active_patenting" &
    headlines$sample == "full_1994_2010" &
    headlines$inference == "deal_wild_bootstrap_t", ]
active <- active[which.min(abs(active$estimate)), ]
if (nrow(active) != 1L) stop("Missing annual active-patenting headline")

margins$label <- c(
  "Probability of patenting\n(extensive margin)",
  "Patents in active years\n(intensive margin)")
margins$label <- factor(
  margins$label,
  levels = c(
    "Probability of patenting\n(extensive margin)",
    "Patents in active years\n(intensive margin)"))
p_margin <- ggplot2::ggplot(
  margins,
  ggplot2::aes(label, contribution, fill = label)) +
  ggplot2::geom_hline(yintercept = 0, colour = LMV2_COLOURS["mid_grey"]) +
  ggplot2::geom_col(width = 0.62) +
  ggplot2::geom_text(
    ggplot2::aes(
      y = contribution / 2,
      label = paste0(round(100 * share_of_total_decline, 1), "%")),
    colour = "white", fontface = "bold", size = 3.5) +
  ggplot2::scale_fill_manual(values = stats::setNames(
    unname(LMV2_COLOURS[c("forest", "slate_blue")]),
    c(
      "Probability of patenting\n(extensive margin)",
      "Patents in active years\n(intensive margin)"))) +
  ggplot2::labs(
    title = "Most of the patent decline occurs on the extensive margin",
    subtitle = paste0(
      "Active-patenting ATT: ",
      sprintf("%.1f", 100 * active$estimate), " pp; 95% CI [",
      sprintf("%.1f", 100 * active$ci_low), ", ",
      sprintf("%.1f", 100 * active$ci_high), "] pp."),
    x = NULL, y = "Contribution to annual patent-count ATT",
    caption = paste0(
      "Shapley accounting decomposition. The intensive component is ",
      "descriptive;\nits substantive interpretation is deferred to the ",
      "initially retained sample.")) +
  lmv2_theme(10.5, "none")
lmv2_save_figure(
  p_margin, file.path(FIG_DIR, "figure_d4_margin_decomposition"),
  width = 7.2, height = 4.4)
utils::write.csv(
  margins, file.path(OUT_DIR, "d4_margin_decomposition.csv"),
  row.names = FALSE)

# ---------------------------------------------------------------------------
# D6: supported/unsupported scenario and treated-deal influence summaries
# ---------------------------------------------------------------------------

eligible_path <- must_exist(file.path(
  AUDIT_ROOT, "P6_V3_PRODUCTION_FINAL_FREEZE",
  "p6_all_eligible_treated_preperiod.parquet"))
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
eligible_q <- gsub("'", "''", eligible_path, fixed = TRUE)
inventor_pre <- DBI::dbGetQuery(
  con, paste0(
    "SELECT cohort, deal_id, codinv, supported, ",
    "AVG(patent_count) AS mean_pre_patents ",
    "FROM read_parquet('", eligible_q, "') ",
    "WHERE event_time BETWEEN -5 AND -1 ",
    "GROUP BY cohort, deal_id, codinv, supported"))
if (nrow(inventor_pre) != 29170L) {
  stop("Expected 29,170 eligible treated inventors")
}
q <- stats::quantile(
  inventor_pre$mean_pre_patents, c(0.01, 0.99), na.rm = TRUE)
winsorized <- pmin(pmax(inventor_pre$mean_pre_patents, q[[1]]), q[[2]])
sigma_pre <- stats::sd(winsorized)
p_supported <- mean(inventor_pre$supported)
headline_att <- loyo$estimate[loyo$design == "P5c headline"]
delta_grid <- c(-3, -2, -1.5, -1, -.5, 0, .5, 1, 1.5, 2, 3)
support_scenarios <- data.frame(
  delta = delta_grid,
  unsupported_att = headline_att + delta_grid * sigma_pre,
  all_eligible_att = NA_real_,
  stringsAsFactors = FALSE)
support_scenarios$all_eligible_att <-
  p_supported * headline_att +
  (1 - p_supported) * support_scenarios$unsupported_att
unsupported_reversal <-
  -p_supported / (1 - p_supported) * headline_att
delta_reversal <-
  -headline_att / ((1 - p_supported) * sigma_pre)
support_summary <- data.frame(
  statistic = c(
    "Supported share",
    "Unsupported share",
    "Winsorized pre-period SD",
    "Supported ATT",
    "Unsupported ATT required for all-eligible zero",
    "Delta-SD breakdown value"),
  value = c(
    p_supported, 1 - p_supported, sigma_pre, headline_att,
    unsupported_reversal, delta_reversal),
  stringsAsFactors = FALSE)
utils::write.csv(
  support_scenarios, file.path(OUT_DIR, "d6_common_support_scenarios.csv"),
  row.names = FALSE)
utils::write.csv(
  support_summary, file.path(OUT_DIR, "d6_common_support_summary.csv"),
  row.names = FALSE)

panel_dir <- must_exist(file.path(
  AUDIT_ROOT, "P6_P5C_PANEL_COUNT_ACTIVE", "panel_matched"))
panel_glob <- paste0(panel_dir, "/*.parquet")
panel_q <- gsub("'", "''", panel_glob, fixed = TRUE)
deal_share <- DBI::dbGetQuery(
  con, paste0(
    "WITH deals AS (",
    " SELECT deal_id, SUM(weight) AS treated_weight",
    " FROM read_parquet('", panel_q, "')",
    " WHERE arm='treated' AND event_time=-1",
    " GROUP BY deal_id",
    "), total AS (SELECT SUM(treated_weight) AS total_weight FROM deals)",
    " SELECT deal_id, treated_weight, treated_weight/total_weight AS share",
    " FROM deals CROSS JOIN total ORDER BY share DESC"))
deal_influence_summary <- data.frame(
  statistic = c(
    "Number of treated deals",
    "Largest treated-weight share",
    "Top-5 treated-weight share",
    "Herfindahl effective treated deals"),
  value = c(
    nrow(deal_share), max(deal_share$share),
    sum(utils::head(deal_share$share, 5)),
    1 / sum(deal_share$share^2)),
  stringsAsFactors = FALSE)
assert_close(
  deal_influence_summary$value[
    deal_influence_summary$statistic ==
      "Herfindahl effective treated deals"],
  36.9368780846092, 1e-8, "Effective treated deals")
utils::write.csv(
  deal_share, file.path(OUT_DIR, "d6_treated_deal_weight_shares.csv"),
  row.names = FALSE)
utils::write.csv(
  deal_influence_summary,
  file.path(OUT_DIR, "d6_treated_deal_influence_summary.csv"),
  row.names = FALSE)

# ---------------------------------------------------------------------------
# Source manifest and certification
# ---------------------------------------------------------------------------

source_paths <- c(
  CS_PATH, GAP_PATH,
  file.path(RAW_DIR, "raw_did_dynamic_estimates.csv"),
  file.path(RAW_DIR, "raw_did_standardized_mean_paths.csv"),
  file.path(RAW_DIR, "raw_did_post_att.csv"),
  file.path(RAW_DIR, "raw_did_joint_pretrend.csv"),
  file.path(FINAL_P5, "realized_gate_checks.csv"),
  file.path(FINAL_P5, "realized_coverage_by_cohort.csv"),
  file.path(FINAL_P5, "realized_retained_vs_unsupported.csv"),
  file.path(P5C_PROD, "p5c_cell_diagnostics.csv"),
  balance_files,
  file.path(QUANTITY_DIR, "quantity_results_appendix.csv"),
  file.path(QUANTITY_DIR, "quantity_margin_decomposition.csv"),
  file.path(QUANTITY_DIR, "quantity_post_weighted_means.csv"),
  file.path(AUDIT_ROOT, "P6_P5C_ESTIMATION_COUNT_ACTIVE",
            "p6_headline_post_att.csv"),
  eligible_path)
source_paths <- vapply(
  source_paths, must_exist, character(1), USE.NAMES = FALSE)
manifest <- data.frame(
  source_path = source_paths,
  sha256 = vapply(
    source_paths, digest::digest, character(1),
    file = TRUE, algo = "sha256"),
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest, file.path(OUT_DIR, "fullcohort_source_manifest.csv"),
  row.names = FALSE)

figure_stems <- file.path(
  FIG_DIR,
  c(
    "figure_d1_design_sequence", "figure_d2_love_plot",
    "figure_d3_patent_count_loyo", "figure_d4_margin_decomposition"))
certification <- data.frame(
  check = c(
    "descriptive_manifest_complete",
    "standard_cs_source_present",
    "raw_placebo_att_reproduced",
    "raw_pretrend_rejection_reproduced",
    "final_inventor_retention_reproduced",
    "final_deal_retention_reproduced",
    "all_17_balance_cells_present",
    "post_balance_smd_below_1e_6",
    "all_loyo_estimates_negative",
    "all_loyo_wild_intervals_exclude_zero",
    "margin_decomposition_sums_to_headline",
    "common_support_population_complete",
    "effective_deals_reproduced",
    "all_figures_png_and_pdf_exist"),
  pass = c(
    nrow(descriptive_manifest) == length(descriptive_paths),
    file.exists(CS_PATH),
    abs(raw_summary$estimate[1] - (-0.00280886656939743)) < 1e-12,
    raw_summary$p_value[2] < 0.001,
    abs(sum(coverage$supported) / sum(coverage$eligible) - 27078 / 29170) <
      1e-12,
    abs(gates$realized[gates$gate == "aggregate_deal_coverage"] -
          341 / 343) < 1e-12,
    length(balance_files) == 17L,
    max(balance_max$max_abs_smd[balance_max$stage == "after"]) < 1e-6,
    all(loyo$estimate < 0),
    all(loyo$ci_high < 0),
    abs(sum(margins$contribution) - headline_att) < 1e-8,
    nrow(inventor_pre) == 29170L,
    abs(
      deal_influence_summary$value[
        deal_influence_summary$statistic ==
          "Herfindahl effective treated deals"] -
        36.9368780846092) < 1e-8,
    all(file.exists(c(paste0(figure_stems, ".png"),
                      paste0(figure_stems, ".pdf"))))),
  stringsAsFactors = FALSE)
if (!all(certification$pass)) {
  utils::write.csv(
    certification, file.path(OUT_DIR, "fullcohort_certification.csv"),
    row.names = FALSE)
  stop(
    "Closeout certification failed: ",
    paste(certification$check[!certification$pass], collapse = ", "))
}
utils::write.csv(
  certification, file.path(OUT_DIR, "fullcohort_certification.csv"),
  row.names = FALSE)

message(
  "Full-cohort closeout built and certified: ", OUT_DIR,
  "\nFigures: ", FIG_DIR)
