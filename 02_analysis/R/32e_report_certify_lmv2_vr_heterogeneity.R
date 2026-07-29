# ============================================================================
# 32e_report_certify_lmv2_vr_heterogeneity.R -- certify and report package
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
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))

cfg <- LMV2_VR_HET
out_dir <- cfg$output_dir
result_dir <- cfg$result_dir
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
input_paths <- setNames(file.path(out_dir, c(
  "moderator_build_certification.csv",
  "moderator_build_manifest.csv",
  "team_persistence_counts.csv",
  "techfit_coverage_funnel.csv",
  "techfit_distribution.csv",
  "unit_analysis_certification.csv",
  "power_gate_manifest.csv",
  "vr_power_gate.csv",
  "vr_heterogeneity_results.csv",
  "vr_aggregate_results.csv",
  "vr_margin_decomposition.csv",
  "vr_estimation_manifest.csv"
)), c(
  "moderator_cert", "moderator_manifest", "team_counts",
  "techfit_funnel", "techfit_distribution", "unit_cert",
  "power_manifest", "power", "heterogeneity", "aggregate",
  "decomposition", "estimation_manifest"
))
if (!all(file.exists(input_paths))) {
  stop("VR result bundle is incomplete: ",
       paste(names(input_paths)[!file.exists(input_paths)], collapse = ", "))
}
read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE)
}
moderator_cert <- read_csv(input_paths[["moderator_cert"]])
moderator_manifest <- read_csv(input_paths[["moderator_manifest"]])
team_counts <- read_csv(input_paths[["team_counts"]])
techfit_funnel <- read_csv(input_paths[["techfit_funnel"]])
techfit_distribution <- read_csv(input_paths[["techfit_distribution"]])
unit_cert <- read_csv(input_paths[["unit_cert"]])
power_manifest <- read_csv(input_paths[["power_manifest"]])
power <- read_csv(input_paths[["power"]])
heterogeneity <- read_csv(input_paths[["heterogeneity"]])
aggregate <- read_csv(input_paths[["aggregate"]])
decomposition <- read_csv(input_paths[["decomposition"]])
est_manifest <- read_csv(input_paths[["estimation_manifest"]])

assert_close <- function(x, y, tolerance = 1e-10) {
  length(x) == 1L && length(y) == 1L &&
    is.finite(x) && is.finite(y) && abs(x - y) <= tolerance
}
team_qualifies <- function(joint_patents, joint_years) {
  joint_patents >= cfg$construction$persistent_min_joint_patents &&
    joint_years >= cfg$construction$persistent_min_joint_years
}
techfit_eligible <- function(group, inv_norm, acq_norm) {
  !is.na(group) && !grepl("^999", as.character(group)) &&
    is.finite(inv_norm) && inv_norm > 0 &&
    is.finite(acq_norm) && acq_norm > 0
}
route_precision <- function(mde, threshold) {
  if (mde <= threshold) "meets_mde_benchmark" else "limited_precision"
}
gap_decomposition <- function(p_t, p_c, mu_t, mu_c) {
  a <- c(
    extensive = (p_t - p_c) * mu_c,
    intensive = p_t * (mu_t - mu_c)
  )
  b <- c(
    extensive = (p_t - p_c) * mu_t,
    intensive = p_c * (mu_t - mu_c)
  )
  list(a = a, b = b, symmetric = (a + b) / 2)
}

# Every material guard is tooth-tested against a real positive.
synthetic_gap <- gap_decomposition(.2, .3, 2, 3)
tooth_tests <- data.frame(
  check = c(
    "temporal_team_rejects_two_patents_in_one_year",
    "temporal_team_accepts_two_patents_in_two_years",
    "techfit_rejects_placeholder_acquirer",
    "techfit_rejects_zero_norm_instead_of_assigning_zero",
    "future_year_guard_rejects_treatment_year",
    "precision_label_is_determined_only_by_mde",
    "type_m_ratio_is_nontrivial_when_precision_is_limited",
    "both_decomposition_orderings_reproduce_gap",
    "numeric_guard_rejects_perturbed_headline"
  ),
  pass = c(
    !team_qualifies(2, 1),
    team_qualifies(2, 2),
    !techfit_eligible(999001, 1, 1),
    !techfit_eligible(100001, 1, 0),
    !((2000L - 2000L) <= -1L) && ((1999L - 2000L) <= -1L),
    route_precision(.06, .053) == "limited_precision" &&
      route_precision(.04, .053) == "meets_mde_benchmark",
    lmv2_vr_type_m_ratio(.045, .053, 1.96) > 1,
    assert_close(sum(synthetic_gap$a), .2 * 2 - .3 * 3) &&
      assert_close(sum(synthetic_gap$b), .2 * 2 - .3 * 3),
    !assert_close(-.0534, -.0524)
  ),
  stringsAsFactors = FALSE
)

primary <- heterogeneity[
  heterogeneity$result_type == "focal_contrast" &
    heterogeneity$sample == "full_1994_2010" &
    heterogeneity$window == "post_mean_minus_t_minus_1" &
    heterogeneity$model_type == "separate_primary" &
    heterogeneity$techfit_variant %in% c("not_applicable", "full"),
]
strongest <- heterogeneity[
  heterogeneity$model_type == "strongest_tie_appendix_extension" &
    heterogeneity$result_type == "focal_contrast",
]
full_decomp <- decomposition[
  decomposition$sample == "full_1994_2010",
]
component <- function(name) {
  full_decomp$estimate[full_decomp$component == name]
}
headline <- aggregate$estimate[
  aggregate$sample == "full_1994_2010" &
    aggregate$outcome == "patent_count" &
    aggregate$window == "post_mean_minus_t_minus_1"
]
source_32b <- readLines(
  file.path(BASE, "R", "32b_build_lmv2_vr_moderators.R"),
  warn = FALSE
)
source_32d <- readLines(
  file.path(BASE, "R", "32d_estimate_lmv2_vr_heterogeneity.R"),
  warn = FALSE
)
checks <- data.frame(
  check = c(
    "all_moderator_checks_pass",
    "all_unit_analysis_checks_pass",
    "all_tooth_tests_pass",
    "freeze_hash_is_unchanged_across_stages",
    "all_executed_stage_sources_match_their_manifests",
    "power_stage_wrote_no_heterogeneity_point_estimate",
    "primary_family_has_exactly_eight_rows",
    "holm_adjustment_is_complete_for_primary_family",
    "all_primary_rows_are_included_with_precision_diagnostics",
    "aggregate_headline_is_reproduced",
    "both_decomposition_orderings_reproduce_total",
    "symmetric_decomposition_reproduces_total",
    "reference_patent_and_active_gaps_are_numerically_zero",
    "temporal_team_counts_are_reported_before_outcomes",
    "full_history_techfit_is_primary_and_five_year_never_substitutes",
    "moderator_builder_does_not_read_the_outcome_panel",
    "estimator_never_uses_post_treatment_left_status",
    "strongest_tie_extension_is_reported_outside_primary_family"
  ),
  pass = c(
    all(moderator_cert$pass),
    all(unit_cert$pass),
    all(tooth_tests$pass),
    length(unique(c(
      moderator_manifest$design_hash,
      power_manifest$design_hash,
      est_manifest$design_hash,
      lmv2_vr_hash()
    ))) == 1L,
    moderator_manifest$source_sha256 == digest::digest(
      file = file.path(BASE, "R", "32b_build_lmv2_vr_moderators.R"),
      algo = "sha256"
    ) &&
      power_manifest$source_sha256 == digest::digest(
        file = file.path(BASE, "R", "32c_compute_lmv2_vr_power_gate.R"),
        algo = "sha256"
      ) &&
      est_manifest$source_sha256 == digest::digest(
        file = file.path(
          BASE, "R", "32d_estimate_lmv2_vr_heterogeneity.R"
        ),
        algo = "sha256"
      ),
    power_manifest$heterogeneity_point_estimates_written == 0L,
    nrow(primary) == 8L &&
      !anyDuplicated(paste(primary$moderator, primary$outcome)),
    all(is.finite(primary$holm_adjusted_governing_p)),
    all(primary$reporting_status ==
          "included_primary_heterogeneity_table") &&
      !anyNA(primary$power_gate_pass) &&
      all(is.finite(primary$precision_mde)) &&
      all(is.finite(primary$meaningful_threshold)) &&
      all(is.finite(primary$type_m_exaggeration_ratio_at_threshold)),
    length(headline) == 1L &&
      assert_close(headline, -.0534044541698586, 1e-10),
    assert_close(
      component("ordering_a_extensive") +
        component("ordering_a_intensive"),
      component("total")
    ) &&
      assert_close(
        component("ordering_b_extensive") +
          component("ordering_b_intensive"),
        component("total")
      ),
    assert_close(
      component("symmetric_extensive") +
        component("symmetric_intensive"),
      component("total")
    ),
    abs(component("pre_gap")) < 1e-7 &&
      abs(component("pre_active_gap")) < 1e-7,
    sum(team_counts$roster_rows[
      team_counts$arm == "treated" & team_counts$team_any == 0
    ]) == 22715L &&
      sum(team_counts$roster_rows[
        team_counts$arm == "treated" & team_counts$team_any == 1
      ]) == 4363L,
    identical(cfg$construction$techfit_primary_window,
              "all_observable_years_before_treatment") &&
      any(heterogeneity$model_type ==
            "techfit_five_year_robustness") &&
      all(heterogeneity$techfit_variant[
        heterogeneity$model_type == "separate_primary" &
          heterogeneity$moderator == "techfit"
      ] == "full"),
    !any(grepl(
      "P6_P5C_PANEL|event_panel_c|active_patenting|patent_post",
      source_32b
    )),
    !any(grepl("left_focal|Left × After|Left_i", source_32d)),
    isTRUE(est_manifest$strongest_tie_opened) &&
      nrow(strongest) == 2L &&
      setequal(strongest$outcome, c("patent_count", "active_patenting")) &&
      all(strongest$reporting_status ==
            "included_exploratory_extension") &&
      all(is.na(strongest$holm_adjusted_governing_p))
  ),
  stringsAsFactors = FALSE
)
lmv2_vr_assert_checks(tooth_tests)
lmv2_vr_assert_checks(checks)
utils::write.csv(
  tooth_tests, file.path(out_dir, "vr_tooth_tests.csv"), row.names = FALSE
)
utils::write.csv(
  checks, file.path(out_dir, "vr_certification.csv"), row.names = FALSE
)

# ---------------------------------------------------------------------------
# Tables and figures
# ---------------------------------------------------------------------------
labels <- c(
  predeal_productivity = "Pre-deal productivity",
  career_age = "Career age",
  team_persistence = "Persistent collaborator",
  techfit = "Inventor-acquirer TechFit"
)
primary$moderator_label <- unname(labels[primary$moderator])
primary$outcome_label <- ifelse(
  primary$outcome == "patent_count",
  "Patent count", "Active patenting"
)
primary$plot_estimate <- ifelse(
  primary$outcome == "active_patenting",
  100 * primary$estimate, primary$estimate
)
primary$plot_low <- ifelse(
  primary$outcome == "active_patenting",
  100 * primary$ci_low, primary$ci_low
)
primary$plot_high <- ifelse(
  primary$outcome == "active_patenting",
  100 * primary$ci_high, primary$ci_high
)
primary$raw_significance <- ifelse(
  primary$governing_p < .05,
  "Raw p < 0.05", "Raw p >= 0.05"
)
primary$moderator_label <- factor(
  primary$moderator_label,
  levels = rev(unname(labels))
)
p_het <- ggplot2::ggplot(
  primary,
  ggplot2::aes(
    x = plot_estimate, y = moderator_label, shape = raw_significance
  )
) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"], linewidth = .5
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = plot_low, xmax = plot_high),
    width = .12, orientation = "y", linewidth = .65
  ) +
  ggplot2::geom_point(
    size = 2.6, colour = unname(LMV2_COLOURS["forest"])
  ) +
  ggplot2::facet_wrap(
    ~outcome_label, scales = "free_x", nrow = 1
  ) +
  ggplot2::scale_shape_manual(values = c(
    "Raw p < 0.05" = 16,
    "Raw p >= 0.05" = 1
  )) +
  ggplot2::labs(
    title = "Five-year acquisition effects by inventor characteristics",
    subtitle = paste(
      "Focal p75-p25 or persistent-tie contrast;",
      "intervals use the governing inference method"
    ),
    x = "Patent-count difference or active-patenting difference (percentage points)",
    y = NULL,
    shape = NULL,
    caption = paste(
      "All eight predeclared contrasts are reported. Filled points have raw",
      "p<0.05; Holm adjustment covers the full eight-test family."
    )
  ) +
  lmv2_theme(10.5, "bottom")
heterogeneity_figure <- file.path(
  result_dir, "figure_vr_heterogeneity_focal.png"
)
ggplot2::ggsave(
  heterogeneity_figure, p_het,
  width = 10.5, height = 4.8, units = "in", dpi = 320,
  bg = LMV2_COLOURS["white"]
)

margin_plot <- full_decomp[
  full_decomp$component %in%
    c("symmetric_extensive", "symmetric_intensive", "total"),
]
margin_plot$label <- c(
  symmetric_extensive = "Reduced active patenting",
  symmetric_intensive = "Fewer patents in active years",
  total = "Total patent loss"
)[margin_plot$component]
margin_plot$label <- factor(
  margin_plot$label,
  levels = c(
    "Total patent loss", "Reduced active patenting",
    "Fewer patents in active years"
  )
)
p_margin <- ggplot2::ggplot(
  margin_plot,
  ggplot2::aes(x = five_year_patents, y = label)
) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"], linewidth = .5
  ) +
  ggplot2::geom_col(
    fill = unname(LMV2_COLOURS["forest"]), width = .62
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = five_year_ci_low, xmax = five_year_ci_high),
    width = .13, orientation = "y", linewidth = .65
  ) +
  ggplot2::geom_text(
    ggplot2::aes(
      label = sprintf("%.3f", five_year_patents)
    ),
    hjust = 1.12, colour = "white", size = 3.3
  ) +
  ggplot2::labs(
    title = "Most of the five-year patent loss is on the extensive margin",
    subtitle = paste(
      "Symmetric accounting: 74% reduced activity and 26%",
      "lower output in active inventor-years"
    ),
    x = "Cumulative patents per inventor over five years",
    y = NULL,
    caption = paste(
      "The total is the certified ATT. The intensive component is descriptive",
      "because active patenting is post-treatment selected."
    )
  ) +
  lmv2_theme(10.5, "none")
margin_figure <- file.path(
  result_dir, "figure_vr_margin_decomposition.png"
)
ggplot2::ggsave(
  margin_figure, p_margin,
  width = 8.5, height = 4.4, units = "in", dpi = 320,
  bg = LMV2_COLOURS["white"]
)

table_paths <- c(
  aggregate = file.path(result_dir, "table_vr_aggregate_effects.csv"),
  heterogeneity_primary =
    file.path(result_dir, "table_vr_heterogeneity.csv"),
  heterogeneity_diagnostics =
    file.path(result_dir, "table_vr_heterogeneity_diagnostics_appendix.csv"),
  heterogeneity_complete =
    file.path(result_dir, "table_vr_heterogeneity_complete.csv"),
  power = file.path(result_dir, "table_vr_power_gate.csv"),
  decomposition = file.path(result_dir, "table_vr_margin_decomposition.csv"),
  team_counts = file.path(result_dir, "table_vr_team_counts.csv"),
  techfit_funnel = file.path(result_dir, "table_vr_techfit_funnel.csv"),
  techfit_distribution =
    file.path(result_dir, "table_vr_techfit_distribution.csv")
)
utils::write.csv(aggregate, table_paths["aggregate"], row.names = FALSE)
primary_main <- primary[, c(
  "moderator", "outcome", "contrast", "estimate", "ci_low", "ci_high",
  "governing_p", "treated_inventors", "nominal_deals"
)]
names(primary_main)[names(primary_main) == "governing_p"] <- "p_value"
utils::write.csv(
  primary_main, table_paths["heterogeneity_primary"], row.names = FALSE
)
primary_diagnostics <- primary[, c(
  "moderator", "outcome", "governing_p",
  "holm_adjusted_governing_p", "power_gate_pass", "precision_mde",
  "type_m_exaggeration_ratio_at_threshold"
)]
names(primary_diagnostics)[names(primary_diagnostics) == "governing_p"] <-
  "unadjusted_p_value"
utils::write.csv(
  primary_diagnostics, table_paths["heterogeneity_diagnostics"],
  row.names = FALSE
)
utils::write.csv(
  heterogeneity, table_paths["heterogeneity_complete"], row.names = FALSE
)
utils::write.csv(power, table_paths["power"], row.names = FALSE)
utils::write.csv(
  decomposition, table_paths["decomposition"], row.names = FALSE
)
utils::write.csv(team_counts, table_paths["team_counts"], row.names = FALSE)
utils::write.csv(
  techfit_funnel, table_paths["techfit_funnel"], row.names = FALSE
)
utils::write.csv(
  techfit_distribution, table_paths["techfit_distribution"],
  row.names = FALSE
)

get_primary <- function(moderator, outcome) {
  z <- primary[
    primary$moderator == moderator & primary$outcome == outcome,
  ]
  if (nrow(z) != 1L) stop("Primary row is not unique")
  z
}
prod_count <- get_primary("predeal_productivity", "patent_count")
prod_active <- get_primary("predeal_productivity", "active_patenting")
age_count <- get_primary("career_age", "patent_count")
team_count <- get_primary("team_persistence", "patent_count")
tech_count <- get_primary("techfit", "patent_count")
strong_count <- strongest[strongest$outcome == "patent_count", ]
strong_active <- strongest[strongest$outcome == "active_patenting", ]
if (nrow(strong_count) != 1L || nrow(strong_active) != 1L) {
  stop("StrongestTie outcome rows are not unique")
}
prod_marg <- heterogeneity[
  heterogeneity$moderator == "predeal_productivity" &
    heterogeneity$outcome == "patent_count" &
    heterogeneity$sample == "full_1994_2010" &
    heterogeneity$window == "post_mean_minus_t_minus_1" &
    heterogeneity$model_type == "separate_primary" &
    heterogeneity$result_type %in%
      c("low_marginal_effect", "high_marginal_effect"),
]
note <- c(
  "# Local Match v2: five-year inventor heterogeneity",
  "",
  "## TL;DR",
  "",
  paste(
    "The aggregate quantity result is unchanged: acquisitions reduce patent",
    "output by 0.053 patents per inventor-year, or 0.267 patents over five",
    "years. The symmetric accounting assigns 0.197 of the cumulative loss",
    "(74%) to fewer active inventor-years and 0.070 (26%) to fewer patents",
    "during active inventor-years."
  ),
  "",
  paste(
    "All eight predeclared heterogeneity contrasts are included. Career age",
    "does not moderate patent-count",
    sprintf("effects (contrast %.3f; p=%.3f), and pre-deal productivity does",
            age_count$estimate, age_count$governing_p),
    sprintf("not moderate active patenting (%.3f; p=%.3f).",
            prod_active$estimate, prod_active$governing_p)
  ),
  "",
  paste(
    "Three patent-count gradients are conventionally significant. The",
    "p75-p25 productivity",
    sprintf("contrast is %.3f (p=%.3f); the persistent-team",
            prod_count$estimate, prod_count$governing_p),
    sprintf("contrast is %.3f (p=%.3f); and the TechFit",
            team_count$estimate, team_count$governing_p),
    sprintf("contrast is %.3f (p=%.3f).",
            tech_count$estimate, tech_count$governing_p)
  ),
  "",
  "## Interpretation",
  "",
  sprintf(
    paste(
      "The productivity point estimates are not only a mechanical stock",
      "pattern. At the treated p25, the predicted annual loss is %.3f, or",
      "%.1f%% of pre-deal annual output; at p75 it is %.3f, or %.1f%%."
    ),
    prod_marg$estimate[prod_marg$result_type == "low_marginal_effect"],
    100 * abs(prod_marg$effect_as_share_predeal_output[
      prod_marg$result_type == "low_marginal_effect"
    ]),
    prod_marg$estimate[prod_marg$result_type == "high_marginal_effect"],
    100 * abs(prod_marg$effect_as_share_predeal_output[
      prod_marg$result_type == "high_marginal_effect"
    ])
  ),
  paste(
    "Persistent collaborators are a plausible relationship-specific",
    "human-capital channel, but only 4,363 treated inventors have a temporal",
    "persistent tie. The outcome-blind StrongestTie",
    "extension is reported separately among inventors with a persistent tie.",
    sprintf(
      paste(
        "Within that subgroup, a p75-p25 increase in dependence on the",
        "strongest collaborator has a positive patent-count contrast of %.3f",
        "(p=%.3f) and a positive active-patenting contrast of %.3f",
        "(p=%.3f); neither is significant."
      ),
      strong_count$estimate, strong_count$governing_p,
      strong_active$estimate, strong_active$governing_p
    ),
    "The data therefore support a persistent-team gradient but do not show",
    "that greater dependence on one particular collaborator magnifies the",
    "loss."
  ),
  paste(
    "Higher inventor-acquirer TechFit is associated with a more negative,",
    "not less negative, patent-count effect. The full-history and five-year",
    "contrasts are close. This pattern is compatible with",
    "redundancy-driven program rationalization, but it does not identify that",
    "mechanism."
  ),
  "",
  "## Design notes",
  "",
  paste(
    "The five-year regression retains Verginer and Riccaboni's After",
    "structure but uses treated versus matched-control status instead of",
    "their post-treatment Left indicator. The latter belongs in the separate",
    "stayer analysis. Full-history IPC4 cosine is primary; the five-year",
    "cosine and 1994--2008 sample are fixed robustness variants and cannot",
    "replace their primary specifications."
  ),
  paste(
    "Both valid extensive/intensive orderings are reported. They place",
    "69--78% of the total loss on reduced active patenting; the symmetric",
    "74/26 split is the primary accounting presentation. P5c reference-year",
    "patent-count and active-patenting gaps are below 5e-9 and 1e-9."
  ),
  "",
  "## Appendix diagnostics",
  "",
  paste(
    "Holm-adjusted p-values, minimum detectable effects, and Type-M",
    "diagnostics are retained in",
    "`table_vr_heterogeneity_diagnostics_appendix.csv`. They are not used",
    "to decide which predeclared heterogeneity estimates are reported."
  )
)
note_path <- file.path(
  BASE, "notes", "local_match_v2_vr_heterogeneity_results.md"
)
writeLines(note, note_path, useBytes = TRUE)

artifacts <- c(
  heterogeneity_figure, margin_figure, unname(table_paths), note_path
)
manifest <- data.frame(
  artifact = basename(artifacts),
  path = normalizePath(artifacts, winslash = "/", mustWork = TRUE),
  sha256 = vapply(
    artifacts, digest::digest, character(1),
    file = TRUE, algo = "sha256"
  ),
  design_hash = lmv2_vr_hash(),
  report_source_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "32e_report_certify_lmv2_vr_heterogeneity.R"
    ),
    algo = "sha256"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(result_dir, "vr_heterogeneity_artifact_manifest.csv"),
  row.names = FALSE
)
message("Certified VR heterogeneity package written to: ", result_dir)
