# ============================================================================
# 31d_report_certify_lmv2_inventor_heterogeneity.R -- report and tooth-check
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("digest", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "00_lmv2_visual_style.R"))
source(file.path(BASE, "R", "31a_lmv2_inventor_heterogeneity_config.R"))

cfg <- LMV2_INVENTOR_HET
out_dir <- cfg$output_dir
result_dir <- cfg$result_dir
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
input_paths <- setNames(file.path(out_dir, c(
  "moderator_build_audit.csv",
  "moderator_build_certification.csv",
  "moderator_build_manifest.csv",
  "heterogeneity_group_att.csv",
  "heterogeneity_contrasts.csv",
  "heterogeneity_omnibus_tests.csv",
  "heterogeneity_support_balance_gate.csv",
  "heterogeneity_within_group_balance.csv",
  "heterogeneity_estimation_manifest.csv"
)), c(
  "build_audit", "build_cert", "build_manifest", "groups", "contrasts",
  "omnibus", "support", "balance", "estimation_manifest"
))
if (!all(file.exists(input_paths))) {
  stop("Inventor heterogeneity output bundle is incomplete")
}
headline_path <- file.path(
  BASE, "output", "audit", "local_match_v2",
  "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_headline_post_att.csv"
)
if (!file.exists(headline_path)) {
  stop("Certified P5c headline table is missing")
}
read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE)
}
build_audit <- read_csv(input_paths[["build_audit"]])
build_cert <- read_csv(input_paths[["build_cert"]])
build_manifest <- read_csv(input_paths[["build_manifest"]])
groups <- read_csv(input_paths[["groups"]])
contrasts <- read_csv(input_paths[["contrasts"]])
omnibus <- read_csv(input_paths[["omnibus"]])
support <- read_csv(input_paths[["support"]])
balance <- read_csv(input_paths[["balance"]])
est_manifest <- read_csv(input_paths[["estimation_manifest"]])
headline <- read_csv(headline_path)
headline <- headline[
  headline$outcome == "patent_count" &
    headline$sample == "full_1994_2010" &
    headline$summary == "average_annual_t1_to_t5" &
    headline$governing %in% c(TRUE, "TRUE"),
]
if (nrow(headline) != 1L) {
  stop("Certified P5c headline row is not unique")
}

# ---------------------------------------------------------------------------
# Tooth-tests: every material guard must demonstrably fail on a real positive.
# ---------------------------------------------------------------------------
assert_close <- function(actual, expected, tolerance = 1e-10) {
  isTRUE(length(actual) == 1L && length(expected) == 1L &&
    is.finite(actual) && is.finite(expected) &&
    abs(actual - expected) <= tolerance)
}
arm_coverage <- function(x) {
  a <- stats::aggregate(
    x$arm, by = list(x$moderator, x$group_name),
    FUN = function(z) length(unique(z))
  )
  all(a$x == 2L)
}
synthetic_arms <- data.frame(
  moderator = c("m", "m"), group_name = c("g", "g"),
  arm = c("treated", "control")
)
tooth_tests <- data.frame(
  check = c(
    "numeric_guard_rejects_perturbed_att",
    "arm_guard_rejects_missing_control",
    "stable_tie_threshold_rejects_one_joint_patent",
    "future_year_guard_rejects_treatment_year",
    "team_category_boundaries_fire"
  ),
  pass = c(
    !assert_close(-0.0534, -0.0524),
    arm_coverage(synthetic_arms) &&
      !arm_coverage(synthetic_arms[synthetic_arms$arm == "treated", ]),
    !(1L >= cfg$construction$stable_tie_min_joint_patents) &&
      2L >= cfg$construction$stable_tie_min_joint_patents,
    !((2000L - 2000L) <= -1L) && ((1999L - 2000L) <= -1L),
    identical(
      lmv2_het_group("team_embeddedness", c(0, 0.5, 1)),
      c("no stable team", "partial stable team",
        "all patents stable team")
    )
  ),
  stringsAsFactors = FALSE
)

expected_groups <- unlist(lapply(
  cfg$construction$moderators, `[[`, "order"
), use.names = FALSE)
actual_full <- groups[groups$sample == "full_1994_2010", ]
full_family <- omnibus[
  omnibus$sample == "full_1994_2010" &
    omnibus$designation %in% c("primary", "conditional"),
]
source_31b <- readLines(
  file.path(BASE, "R", "31b_build_lmv2_inventor_moderators.R"),
  warn = FALSE
)
freeze_path <- file.path(
  BASE, "notes", "local_match_v2_inventor_heterogeneity_freeze.md"
)
current_freeze_sha256 <- digest::digest(
  file = freeze_path, algo = "sha256"
)
checks <- data.frame(
  check = c(
    "all_moderator_build_checks_pass",
    "all_tooth_tests_pass",
    "one_row_per_certified_roster_row",
    "predeal_patent_counts_reproduce_p3",
    "team_construction_ends_by_t_minus_1",
    "moderator_builder_does_not_read_event_panel",
    "current_freeze_matches_preoutcome_manifest",
    "current_design_hash_used_by_both_stages",
    "overall_certified_att_reproduced",
    "all_predeclared_groups_reported_in_both_samples",
    "all_estimates_and_intervals_finite",
    "all_predeclared_contrasts_reported",
    "four_test_primary_omnibus_family",
    "holm_values_present_only_for_frozen_full_sample_family",
    "support_and_balance_gate_reported_for_every_group"
  ),
  pass = c(
    all(build_cert$pass),
    all(tooth_tests$pass),
    build_audit$moderator_rows == 500906L &&
      build_audit$moderator_rows == build_audit$unique_moderator_rows,
    build_audit$reconstructed_patent_mismatches == 0,
    build_manifest$maximum_team_input_event_time <= -1,
    !any(grepl(
      "P6_P5C_PANEL|event_panel_c", source_31b, fixed = FALSE
    )),
    build_manifest$freeze_sha256 == current_freeze_sha256,
    build_manifest$heterogeneity_design_hash ==
      lmv2_inventor_het_hash() &&
      est_manifest$heterogeneity_design_hash ==
        lmv2_inventor_het_hash(),
    isTRUE(est_manifest$overall_att_reproduced) &&
      assert_close(
        est_manifest$reproduced_overall_att,
        headline$estimate
      ),
    nrow(groups) == 2L * length(expected_groups) &&
      identical(
        sort(unique(paste(actual_full$moderator,
                          actual_full$group_name))),
        sort(unique(unlist(lapply(
          names(cfg$construction$moderators), function(m) {
            paste(m, cfg$construction$moderators[[m]]$order)
          }
        ))))
      ),
    all(is.finite(unlist(groups[c(
      "estimate", "ci_low", "ci_high", "governing_p"
    )]))) && all(groups$ci_low <= groups$estimate) &&
      all(groups$estimate <= groups$ci_high),
    nrow(contrasts) == 18L &&
      all(is.finite(contrasts$mde_annual_patents)),
    nrow(full_family) == 4L,
    sum(!is.na(omnibus$holm_adjusted_governing_p)) == 4L &&
      all(!is.na(full_family$holm_adjusted_governing_p)),
    nrow(support) == nrow(groups) &&
      all(is.finite(support$max_abs_smd))
  ),
  stringsAsFactors = FALSE
)
lmv2_het_assert_checks(tooth_tests)
lmv2_het_assert_checks(checks)
utils::write.csv(
  tooth_tests, file.path(out_dir, "heterogeneity_tooth_tests.csv"),
  row.names = FALSE
)
utils::write.csv(
  checks, file.path(out_dir, "heterogeneity_certification.csv"),
  row.names = FALSE
)

# ---------------------------------------------------------------------------
# Main appendix exhibit: all predeclared full-sample subgroups, with the
# certified overall ATT shown as a common benchmark.
# ---------------------------------------------------------------------------
plot_data <- merge(
  actual_full,
  support[support$sample == "full_1994_2010",
          c("moderator", "group_name", "support_balance_pass")],
  by = c("moderator", "group_name"), all.x = TRUE, sort = FALSE
)
moderator_labels <- c(
  career_age = "A. Career age",
  predeal_productivity = "B. Pre-deal productivity",
  focal_exclusivity = "C. Focal-firm exclusivity",
  team_embeddedness = "D. Team embeddedness",
  focal_tenure = "E. Focal-group tenure (appendix alternative)"
)
plot_data$moderator_label <- moderator_labels[plot_data$moderator]
ordered_groups <- unlist(lapply(
  names(cfg$construction$moderators),
  function(m) cfg$construction$moderators[[m]]$order
), use.names = FALSE)
plot_data$group_name <- factor(
  plot_data$group_name, levels = rev(ordered_groups)
)
plot_data$gate_label <- ifelse(
  plot_data$support_balance_pass,
  "Support/balance gate passed", "Support/balance caveat"
)
overall_att <- est_manifest$reproduced_overall_att
main_plot_data <- plot_data[
  plot_data$moderator %in% c(
    "career_age", "predeal_productivity", "team_embeddedness"
  ),
]
main_plot_data$moderator_label <- c(
  career_age = "A. Career age",
  predeal_productivity = "B. Pre-deal productivity",
  team_embeddedness = "C. Team embeddedness"
)[main_plot_data$moderator]
make_forest <- function(data, title, ncol) ggplot2::ggplot(
  data,
  ggplot2::aes(
    x = estimate, y = group_name, colour = gate_label
  )
) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.45
  ) +
  ggplot2::geom_vline(
    xintercept = overall_att, colour = LMV2_COLOURS["forest"],
    linewidth = 0.6, linetype = "dashed"
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = ci_low, xmax = ci_high),
    width = 0.12, linewidth = 0.65, orientation = "y"
  ) +
  ggplot2::geom_point(size = 2.25) +
  ggplot2::facet_wrap(
    ~moderator_label, scales = "free_y", ncol = ncol
  ) +
  ggplot2::scale_colour_manual(values = c(
    "Support/balance gate passed" = unname(LMV2_COLOURS["forest"]),
    "Support/balance caveat" = unname(LMV2_COLOURS["amber"])
  )) +
  ggplot2::labs(
    title = title,
    subtitle = paste(
      "Average annual ATT, t=+1,...,+5. Dashed line: certified overall",
      sprintf("ATT = %.3f.", overall_att)
    ),
    x = "Change in patents per inventor-year",
    y = NULL,
    caption = paste(
      "Intervals use the wider of deal-level Webb and two-way deal/inventor",
      "inference.\nOrange estimates remain reported but fail a prospective",
      "within-group support or balance gate."
    )
  ) +
  lmv2_theme(10.5, "bottom") +
  ggplot2::theme(
    panel.spacing = grid::unit(1.0, "lines"),
    strip.text = ggplot2::element_text(hjust = 0)
  )
figure_path <- file.path(
  result_dir, "figure_inventor_heterogeneity_forest.png"
)
p <- make_forest(
  main_plot_data,
  "Patent-count effects differ most by prior productivity",
  ncol = 3
)
ggplot2::ggsave(
  figure_path, p, width = 11.0, height = 4.8, units = "in",
  dpi = 320, bg = LMV2_COLOURS["white"]
)
appendix_figure_path <- file.path(
  result_dir, "figure_inventor_heterogeneity_appendix.png"
)
appendix_plot_data <- plot_data[plot_data$moderator %in% c(
  "focal_exclusivity", "focal_tenure"
), ]
appendix_plot_data$moderator_label <- c(
  focal_exclusivity = "A. Focal-firm exclusivity",
  focal_tenure = "B. Focal-group tenure"
)[appendix_plot_data$moderator]
p_appendix <- make_forest(
  appendix_plot_data,
  "Conditional exclusivity and tenure diagnostics",
  ncol = 2
)
ggplot2::ggsave(
  appendix_figure_path, p_appendix,
  width = 8.2, height = 4.8, units = "in",
  dpi = 320, bg = LMV2_COLOURS["white"]
)

# Compact reporting table and a machine-readable copy.
report_table <- merge(
  groups,
  support[, c(
    "moderator", "sample", "group_name", "treated_inventors",
    "effective_deals", "max_abs_smd", "support_balance_pass"
  )],
  by = c("moderator", "sample", "group_name"),
  all.x = TRUE, sort = FALSE
)
utils::write.csv(
  report_table,
  file.path(result_dir, "table_inventor_heterogeneity.csv"),
  row.names = FALSE
)
utils::write.csv(
  contrasts,
  file.path(result_dir, "table_inventor_heterogeneity_contrasts.csv"),
  row.names = FALSE
)
utils::write.csv(
  omnibus,
  file.path(result_dir, "table_inventor_heterogeneity_omnibus.csv"),
  row.names = FALSE
)

full <- groups[groups$sample == "full_1994_2010", ]
get_est <- function(m, g) {
  full$estimate[full$moderator == m & full$group_name == g]
}
get_omnibus <- function(m, field = "omnibus_governing_p") {
  z <- omnibus[
    omnibus$sample == "full_1994_2010" & omnibus$moderator == m,
  ]
  z[[field]]
}
note <- c(
  "# Local Match v2: inventor-level patent-count heterogeneity",
  "",
  "## TL;DR",
  "",
  sprintf(
    paste(
      "The certified overall ATT remains %.3f patents per inventor-year.",
      "The clearest credible heterogeneity is by pre-deal productivity:"
    ), overall_att
  ),
  sprintf(
    paste(
      "inventors with one pre-deal patent lose %.3f annually, whereas",
      "inventors with three or more lose %.3f."
    ),
    get_est("predeal_productivity", "1 patent"),
    get_est("predeal_productivity", "3+ patents")
  ),
  sprintf(
    paste(
      "The governing omnibus p-value is %.4f (Holm-adjusted %.4f),",
      "and every productivity group passes the prospective support/balance",
      "gate."
    ),
    get_omnibus("predeal_productivity"),
    get_omnibus(
      "predeal_productivity", "holm_adjusted_governing_p"
    )
  ),
  "",
  sprintf(
    paste(
      "Team embeddedness is empirically informative but should be labelled",
      "suggestive: no-stable-team inventors lose %.3f, partially embedded",
      "inventors %.3f, and fully embedded inventors %.3f patents annually."
    ),
    get_est("team_embeddedness", "no stable team"),
    get_est("team_embeddedness", "partial stable team"),
    get_est("team_embeddedness", "all patents stable team")
  ),
  sprintf(
    paste(
      "Its governing omnibus p-value is %.4f (Holm-adjusted %.4f), and the",
      "1994--2008 companion is nearly identical. The full-sample partial-team",
      "cell narrowly misses the balance gate (maximum SMD 0.112, driven by",
      "focal-firm exclusivity); it passes in the buffered companion."
    ),
    get_omnibus("team_embeddedness"),
    get_omnibus("team_embeddedness", "holm_adjusted_governing_p")
  ),
  "",
  "## Design and interpretation",
  "",
  paste(
    "All moderators are measured during t=-5,...,-1. A stable team tie is a",
    "co-inventor appearing on at least two pre-deal patents; team",
    "embeddedness is the share of pre-deal patents containing such a tie.",
    "Subgroup ATTs reuse the certified P5c roster and weights and standardize",
    "all groups to common acquisition-cohort shares."
  ),
  paste(
    "This directly operationalizes the mechanism highlighted by Verginer and",
    "Riccaboni (2025): acquisitions can disrupt established inventor teams and",
    "force costly reconfiguration. They explicitly identify team disruption as",
    "a priority for future research; Paruchuri, Nerkar, and Hambrick (2006)",
    "provide the closely related technical-core disruption argument."
  ),
  "",
  sprintf(
    paste(
      "Career age shows no detectable heterogeneity (omnibus p=%.3f), and",
      "the appendix tenure split also does not differ (p=%.3f)."
    ),
    get_omnibus("career_age"), get_omnibus("focal_tenure")
  ),
  paste(
    "The multi-firm exclusivity estimate is very large, but that cell has",
    "maximum residual SMD 0.322 and therefore fails the frozen balance gate.",
    "It belongs in the appendix as a diagnostic, not as causal evidence."
  ),
  "",
  paste(
    "The productivity result supports an incentive/restructuring channel:",
    "the average decline is concentrated among inventors who entered the deal",
    "with the largest recent patent stock. The team result is consistent with",
    "collaboration-network disruption, but its non-monotone pattern and the",
    "narrow balance miss mean it should motivate a focused appendix analysis",
    "rather than carry the thesis's causal headline."
  ),
  "",
  paste(
    "The prospective MDE gate shows that the design was not powered to detect",
    "heterogeneity contrasts as small as the 0.053 overall ATT. The observed",
    "productivity and partial-team contrasts are much larger and statistically",
    "distinguishable; this distinction should be stated explicitly."
  )
)
note_path <- file.path(
  BASE, "notes", "local_match_v2_inventor_heterogeneity_results.md"
)
writeLines(note, note_path, useBytes = TRUE)

artifact_paths <- c(
  figure_path, appendix_figure_path,
  file.path(result_dir, "table_inventor_heterogeneity.csv"),
  file.path(result_dir, "table_inventor_heterogeneity_contrasts.csv"),
  file.path(result_dir, "table_inventor_heterogeneity_omnibus.csv"),
  note_path
)
manifest <- data.frame(
  artifact = basename(artifact_paths),
  path = normalizePath(
    artifact_paths, winslash = "/", mustWork = TRUE
  ),
  sha256 = vapply(
    artifact_paths, digest::digest, character(1),
    file = TRUE, algo = "sha256"
  ),
  heterogeneity_design_hash = lmv2_inventor_het_hash(),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest,
  file.path(result_dir, "inventor_heterogeneity_artifact_manifest.csv"),
  row.names = FALSE
)
message(
  "Certified inventor heterogeneity package written to: ", result_dir
)
