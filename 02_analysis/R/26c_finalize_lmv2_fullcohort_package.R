# ============================================================================
# Final full-cohort results package: secondary outcomes and certification
# ============================================================================
#
# Requires successful runs of 26a and 26b. This script adds the final
# secondary-outcome exhibit, consolidates inference/timing diagnostics, and
# certifies the supervisor package without changing any estimates.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (pkg in c("digest", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}
source(file.path(BASE, "R", "00_lmv2_visual_style.R"))

AUDIT_ROOT <- file.path(BASE, "output", "audit", "local_match_v2")
OUT_DIR <- file.path(AUDIT_ROOT, "P6_FULLCOHORT_RESULTS_PACKAGE")
CIT_DIR <- file.path(AUDIT_ROOT, "P6_CASSI_FWCIT5W")
CORE_DIR <- file.path(AUDIT_ROOT, "P6_P5C_ESTIMATION_COUNT_ACTIVE")
LOYO_DIR <- file.path(AUDIT_ROOT, "P6_PACKAGE1_LOYO_GRID")
FIG_DIR <- file.path(
  BASE, "output", "figures", "local_match_v2", "fullcohort_results")
MEMO_PATH <- file.path(
  BASE, "notes", "local_match_v2_quantity_results_for_supervisors.md")

must_exist <- function(path) {
  if (!file.exists(path)) stop("Missing required input: ", path)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}
read_csv <- function(path) {
  utils::read.csv(must_exist(path), stringsAsFactors = FALSE)
}

closeout_cert <- read_csv(
  file.path(OUT_DIR, "fullcohort_certification.csv"))
citation_cert <- read_csv(file.path(CIT_DIR, "cassi_certification.csv"))
if (!all(closeout_cert$pass) || !all(citation_cert$pass)) {
  stop("Upstream closeout or citation certification failed")
}

core <- read_csv(file.path(CORE_DIR, "p6_headline_post_att.csv"))
citation <- read_csv(file.path(CIT_DIR, "cassi_fwcit5w_headline.csv"))
core_dynamic <- read_csv(file.path(CORE_DIR, "p6_event_study_dynamic.csv"))
citation_dynamic <- read_csv(
  file.path(CIT_DIR, "cassi_fwcit5w_dynamic.csv"))
core_pretrend <- read_csv(
  file.path(CORE_DIR, "p6_joint_pretrend_tests.csv"))
citation_pretrend <- read_csv(
  file.path(CIT_DIR, "cassi_fwcit5w_pretrend.csv"))

core_keep <- core[
  core$summary == "average_annual_t1_to_t5" &
    core$governing &
    core$outcome %in% c(
      "active_patenting", "pqii_scaled", "tech_drift"), ]
citation_keep <- citation[
  citation$summary == "average_annual_t1_to_t5" &
    citation$governing &
    citation$outcome == "fwcit5w_cassi_total", ]
secondary <- rbind(
  core_keep[c(
    "outcome", "sample", "estimate", "ci_low", "ci_high", "p_value",
    "inference", "nominal_treated_deals", "effective_treated_deals")],
  citation_keep[c(
    "outcome", "sample", "estimate", "ci_low", "ci_high", "p_value",
    "inference", "nominal_treated_deals", "effective_treated_deals")])
if (nrow(secondary) != 8L) {
  stop("Expected four outcomes in two samples")
}

outcome_labels <- c(
  active_patenting = "Probability of patenting",
  pqii_scaled = "Patent quality (OECD PQII)",
  tech_drift = "TechDrift",
  fwcit5w_cassi_total = "Five-year forward citations")
secondary$outcome_label <- unname(outcome_labels[secondary$outcome])
secondary$outcome_label <- factor(
  secondary$outcome_label,
  levels = rev(unname(outcome_labels)))
secondary$sample_label <- factor(
  secondary$sample,
  levels = c("full_1994_2010", "buffered_1994_2008"),
  labels = c("Full cohorts: 1994-2010", "Censoring-clean: 1994-2008"))

dodge <- ggplot2::position_dodge(width = 0.46)
p_secondary <- ggplot2::ggplot(
  secondary,
  ggplot2::aes(
    estimate, outcome_label, xmin = ci_low, xmax = ci_high,
    colour = sample_label, shape = sample_label)) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"]) +
  ggplot2::geom_errorbar(
    orientation = "y", width = 0.14, linewidth = 0.65,
    position = dodge) +
  ggplot2::geom_point(size = 2.5, position = dodge) +
  ggplot2::scale_colour_manual(values = stats::setNames(
    unname(LMV2_COLOURS[c("forest", "slate_blue")]),
    levels(secondary$sample_label))) +
  ggplot2::scale_shape_manual(values = stats::setNames(
    c(16, 17), levels(secondary$sample_label))) +
  ggplot2::labs(
    title = "Secondary outcomes are mixed and composition-oriented",
    subtitle = paste(
      "Average annual ATT over t=1,...,5 with governing 95% intervals.",
      "Outcomes use different native units."),
    x = "Average annual ATT", y = NULL,
    caption = paste0(
      "Forward citations use the original Cassi--Ornaghi fwCit5w source.\n",
      "PQII remains secondary because OECD linkage and late-sample coverage ",
      "are incomplete.")) +
  lmv2_theme(10.5, "bottom")
lmv2_save_figure(
  p_secondary, file.path(FIG_DIR, "figure_d5_secondary_outcomes"),
  width = 8.1, height = 5.1)
utils::write.csv(
  secondary, file.path(OUT_DIR, "d5_secondary_outcomes.csv"),
  row.names = FALSE)

# Full dynamic DiD paths for every reported outcome. The ordinary P5c
# pre-period coefficients are zero by construction; the separate LOYO figure
# remains the genuine placebo diagnostic.
dynamic <- rbind(
  core_dynamic[
    core_dynamic$outcome %in% c(
      "patent_count", "active_patenting", "pqii_scaled", "tech_drift"), ],
  citation_dynamic[
    citation_dynamic$outcome == "fwcit5w_cassi_total", ])
dynamic_labels <- c(
  patent_count = "Patent applications",
  active_patenting = "Probability of patenting",
  pqii_scaled = "Patent quality (OECD PQII)",
  tech_drift = "TechDrift",
  fwcit5w_cassi_total = "Five-year forward citations")
dynamic$outcome_label <- unname(dynamic_labels[dynamic$outcome])
dynamic$outcome_label <- factor(
  dynamic$outcome_label, levels = unname(dynamic_labels))
utils::write.csv(
  dynamic, file.path(OUT_DIR, "d5_all_outcomes_dynamic.csv"),
  row.names = FALSE)
pretrend <- rbind(
  core_pretrend[
    core_pretrend$outcome %in% c(
      "patent_count", "active_patenting", "pqii_scaled", "tech_drift"), ],
  citation_pretrend[
    citation_pretrend$outcome == "fwcit5w_cassi_total", ])
utils::write.csv(
  pretrend, file.path(OUT_DIR, "d5_all_outcomes_pretrend_tests.csv"),
  row.names = FALSE)

loyo_paths <- c(
  "Hold out t=-5" = file.path(
    AUDIT_ROOT, "P6_PACKAGE1_ESTIMATION_LOYO_M5",
    "p6_headline_post_att.csv"),
  "Hold out t=-4" = file.path(
    AUDIT_ROOT, "P6_P5C_ESTIMATION_LOYO_M4",
    "p6_headline_post_att.csv"),
  "Hold out t=-3" = file.path(
    AUDIT_ROOT, "P6_P5C_ESTIMATION_LOYO_M3",
    "p6_headline_post_att.csv"),
  "Hold out t=-2" = file.path(
    AUDIT_ROOT, "P6_PACKAGE1_ESTIMATION_LOYO_M2",
    "p6_headline_post_att.csv"),
  "Hold out t=-1" = file.path(
    AUDIT_ROOT, "P6_PACKAGE1D_ESTIMATION_LOYO_M1",
    "p6_headline_post_att.csv"))
secondary_loyo <- core[
  core$summary == "average_annual_t1_to_t5" &
    core$sample == "full_1994_2010" &
    core$governing &
    core$outcome %in% c(
      "active_patenting", "pqii_scaled", "tech_drift"), ]
secondary_loyo$design <- "Headline"
for (design_name in names(loyo_paths)) {
  dat <- read_csv(loyo_paths[[design_name]])
  dat <- dat[
    dat$summary == "average_annual_t1_to_t5" &
      dat$sample == "full_1994_2010" &
      dat$governing &
      dat$outcome %in% c(
        "active_patenting", "pqii_scaled", "tech_drift"), ]
  dat$design <- design_name
  secondary_loyo <- rbind(secondary_loyo, dat)
}
utils::write.csv(
  secondary_loyo, file.path(OUT_DIR, "d5_secondary_loyo.csv"),
  row.names = FALSE)

build_dynamic_plot <- function(sample_id, title, stem) {
  dat <- dynamic[dynamic$sample == sample_id, ]
  if (
    nrow(dat) != 55L ||
    !all(table(dat$outcome) == 11L) ||
    any(!is.finite(dat$estimate)) ||
    any(dat$ci_low > dat$ci_high)
  ) {
    stop("Dynamic outcome panel is incomplete for ", sample_id)
  }
  plot <- ggplot2::ggplot(
    dat,
    ggplot2::aes(
      event_time, estimate, ymin = ci_low, ymax = ci_high,
      group = outcome_label)) +
    ggplot2::geom_hline(
      yintercept = 0, colour = LMV2_COLOURS["mid_grey"]) +
    ggplot2::geom_vline(
      xintercept = -0.5, colour = LMV2_COLOURS["mid_grey"]) +
    ggplot2::geom_ribbon(
      fill = LMV2_COLOURS["pale_sage"], colour = NA, alpha = 0.8) +
    ggplot2::geom_line(
      colour = LMV2_COLOURS["forest"], linewidth = 0.75) +
    ggplot2::geom_point(
      colour = LMV2_COLOURS["forest"], size = 1.6) +
    ggplot2::facet_wrap(
      ggplot2::vars(outcome_label), scales = "free_y", ncol = 2) +
    ggplot2::scale_x_continuous(breaks = -5:5) +
    ggplot2::labs(
      title = title,
      subtitle = paste(
        "Matched DiD coefficients relative to t=-1;",
        "95% two-way deal/inventor-clustered intervals."),
      x = "Event time", y = "Difference-in-differences estimate",
      caption = paste0(
        "Patent-count and active-patenting pre-period coefficients are zero ",
        "by construction; LOYO provides their non-mechanical placebo tests.\n",
        "PQII, TechDrift, and forward citations were not balance targets, so ",
        "their pre-period paths are genuine diagnostics.")) +
    lmv2_theme(10, "none") +
    ggplot2::theme(
      panel.spacing = grid::unit(1.0, "lines"),
      strip.text = ggplot2::element_text(size = 9.5))
  lmv2_save_figure(
    plot, file.path(FIG_DIR, stem), width = 9.4, height = 8.0)
}

build_dynamic_plot(
  "full_1994_2010",
  "Event studies for all outcomes: full cohorts",
  "figure_d5a_all_outcomes_event_study_full")
build_dynamic_plot(
  "buffered_1994_2008",
  "Event studies for all outcomes: censoring-clean cohorts",
  "figure_d5b_all_outcomes_event_study_buffered")

# Put wild-bootstrap and two-way intervals side-by-side for the full sample.
core_inference <- core[
  core$summary == "average_annual_t1_to_t5" &
    core$sample == "full_1994_2010" &
    core$outcome %in% c(
      "patent_count", "active_patenting", "pqii_scaled", "tech_drift") &
    core$inference %in% c(
      "deal_wild_bootstrap_t", "two_way_deal_inventor"), ]
citation_inference <- citation[
  citation$summary == "average_annual_t1_to_t5" &
    citation$sample == "full_1994_2010" &
    citation$outcome == "fwcit5w_cassi_total" &
    citation$inference %in% c(
      "deal_wild_bootstrap_t", "two_way_deal_inventor"), ]
inference <- rbind(
  core_inference, citation_inference)
utils::write.csv(
  inference, file.path(OUT_DIR, "d6_inference_comparison.csv"),
  row.names = FALSE)

timing_validity <- read_csv(
  file.path(LOYO_DIR, "package1_timing_placebo_validity.csv"))
timing_minus3 <- read_csv(
  file.path(LOYO_DIR, "package1_timing_placebo_minus3.csv"))
utils::write.csv(
  timing_validity, file.path(OUT_DIR, "d6_timing_placebo_validity.csv"),
  row.names = FALSE)
utils::write.csv(
  timing_minus3, file.path(OUT_DIR, "d6_timing_placebo_minus3.csv"),
  row.names = FALSE)

memo_text <- paste(readLines(must_exist(MEMO_PATH), warn = FALSE), collapse = "\n")
required_memo_phrases <- c(
  "## Decisions requested from supervisors",
  "## Executive summary",
  "standard Callaway--Sant'Anna (2021) DiD",
  "full universe of not-yet-treated inventors",
  "without placebo",
  "How much technological-relatedness analysis belongs in the main text?")
memo_checks <- vapply(
  required_memo_phrases,
  function(x) grepl(x, memo_text, fixed = TRUE),
  logical(1))

source_paths <- c(
  file.path(OUT_DIR, "fullcohort_source_manifest.csv"),
  file.path(OUT_DIR, "fullcohort_certification.csv"),
  file.path(CIT_DIR, "cassi_source_manifest.csv"),
  file.path(CIT_DIR, "cassi_certification.csv"),
  file.path(CIT_DIR, "cassi_fwcit5w_headline.csv"),
  file.path(CIT_DIR, "cassi_fwcit5w_dynamic.csv"),
  file.path(CIT_DIR, "cassi_fwcit5w_pretrend.csv"),
  file.path(CORE_DIR, "p6_headline_post_att.csv"),
  file.path(CORE_DIR, "p6_event_study_dynamic.csv"),
  file.path(CORE_DIR, "p6_joint_pretrend_tests.csv"),
  file.path(LOYO_DIR, "package1_timing_placebo_validity.csv"),
  file.path(LOYO_DIR, "package1_timing_placebo_minus3.csv"),
  unname(loyo_paths),
  MEMO_PATH,
  file.path(BASE, "R", "00_lmv2_visual_style.R"),
  file.path(BASE, "R", "26a_build_lmv2_fullcohort_closeout.R"),
  file.path(BASE, "R", "26b_estimate_lmv2_cassi_fwcit5w.R"),
  file.path(BASE, "R", "26c_finalize_lmv2_fullcohort_package.R"))
source_paths <- vapply(
  source_paths, must_exist, character(1), USE.NAMES = FALSE)
manifest <- data.frame(
  source_path = source_paths,
  sha256 = vapply(
    source_paths, digest::digest, character(1),
    file = TRUE, algo = "sha256"),
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest, file.path(OUT_DIR, "final_package_source_manifest.csv"),
  row.names = FALSE)

final_cert <- data.frame(
  check = c(
    "d0_d4_d6_closeout_certification_passes",
    "cassi_citation_certification_passes",
    "four_secondary_outcomes_two_samples",
    "full_sample_citation_source_total_present",
    "buffered_citation_source_total_present",
    "wild_and_two_way_inference_consolidated",
    "timing_placebo_validity_copied",
    "secondary_figure_png_exists",
    "secondary_figure_pdf_exists",
    "full_event_study_png_exists",
    "full_event_study_pdf_exists",
    "buffered_event_study_png_exists",
    "buffered_event_study_pdf_exists",
    "all_dynamic_outcomes_complete",
    "all_pretrend_tests_complete",
    "secondary_loyo_grid_complete",
    paste0("memo_contains:", required_memo_phrases)),
  pass = c(
    all(closeout_cert$pass),
    all(citation_cert$pass),
    nrow(secondary) == 8L,
    any(
      secondary$outcome == "fwcit5w_cassi_total" &
        secondary$sample == "full_1994_2010"),
    any(
      secondary$outcome == "fwcit5w_cassi_total" &
        secondary$sample == "buffered_1994_2008"),
    nrow(inference) == 10L,
    nrow(timing_validity) == 2L,
    file.exists(file.path(
      FIG_DIR, "figure_d5_secondary_outcomes.png")),
    file.exists(file.path(
      FIG_DIR, "figure_d5_secondary_outcomes.pdf")),
    file.exists(file.path(
      FIG_DIR, "figure_d5a_all_outcomes_event_study_full.png")),
    file.exists(file.path(
      FIG_DIR, "figure_d5a_all_outcomes_event_study_full.pdf")),
    file.exists(file.path(
      FIG_DIR, "figure_d5b_all_outcomes_event_study_buffered.png")),
    file.exists(file.path(
      FIG_DIR, "figure_d5b_all_outcomes_event_study_buffered.pdf")),
    nrow(dynamic) == 110L &&
      all(table(dynamic$outcome, dynamic$sample) == 11L),
    nrow(pretrend) == 10L &&
      all(table(pretrend$outcome, pretrend$sample) == 1L),
    nrow(secondary_loyo) == 18L &&
      all(table(secondary_loyo$outcome) == 6L),
    memo_checks),
  stringsAsFactors = FALSE)
utils::write.csv(
  final_cert, file.path(OUT_DIR, "final_package_certification.csv"),
  row.names = FALSE)
if (!all(final_cert$pass)) {
  stop(
    "Final package certification failed: ",
    paste(final_cert$check[!final_cert$pass], collapse = ", "))
}

message("Final full-cohort results package certified: ", OUT_DIR)
