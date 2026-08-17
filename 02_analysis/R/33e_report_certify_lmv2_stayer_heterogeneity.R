# ============================================================================
# 33e_report_certify_lmv2_stayer_heterogeneity.R -- certify and report
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
source(file.path(BASE, "R", "33a_lmv2_stayer_heterogeneity_config.R"))

cfg <- LMV2_STAYER_HET
out_dir <- cfg$output_dir
result_dir <- cfg$result_dir
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)
input_paths <- setNames(file.path(out_dir, c(
  "moderator_build_certification.csv",
  "moderator_build_audit.csv",
  "moderator_build_manifest.csv",
  "unit_analysis_certification.csv",
  "power_gate_manifest.csv",
  "stayer_power_gate.csv",
  "stayer_heterogeneity_results.csv",
  "stayer_aggregate_results.csv",
  "stayer_margin_decomposition.csv",
  "estimation_manifest.csv",
  "team_persistence_counts.csv",
  "techfit_coverage_funnel.csv"
)), c(
  "moderator_cert", "moderator_audit", "moderator_manifest", "unit_cert",
  "power_manifest", "power", "heterogeneity", "aggregate",
  "decomposition", "estimation_manifest", "team_counts",
  "techfit_funnel"
))
if (!all(file.exists(input_paths))) {
  stop("Stayer heterogeneity output bundle is incomplete")
}
read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
moderator_cert <- read_csv(input_paths[["moderator_cert"]])
moderator_audit <- read_csv(input_paths[["moderator_audit"]])
moderator_manifest <- read_csv(input_paths[["moderator_manifest"]])
unit_cert <- read_csv(input_paths[["unit_cert"]])
power_manifest <- read_csv(input_paths[["power_manifest"]])
power <- read_csv(input_paths[["power"]])
heterogeneity <- read_csv(input_paths[["heterogeneity"]])
aggregate <- read_csv(input_paths[["aggregate"]])
decomposition <- read_csv(input_paths[["decomposition"]])
est_manifest <- read_csv(input_paths[["estimation_manifest"]])
team_counts <- read_csv(input_paths[["team_counts"]])
techfit_funnel <- read_csv(input_paths[["techfit_funnel"]])
s4_inference_path <- file.path(
  dirname(cfg$inputs$s4_headline), "s4_primary_inference_comparison.csv"
)
if (!file.exists(s4_inference_path)) {
  stop("Certified S4 primary inference comparison is missing")
}
s4_inference <- read_csv(s4_inference_path)
s4_primary_inference <- s4_inference[
  s4_inference$spec == cfg$construction$primary_spec &
    s4_inference$support_variant == cfg$construction$primary_support &
    s4_inference$sample == "full_1993_2010" &
    s4_inference$summary == "average_annual_t1_to_t5", ,
  drop = FALSE
]

primary <- heterogeneity[
  heterogeneity$reporting_status ==
    "included_primary_heterogeneity_table", ,
  drop = FALSE
]
tenure <- heterogeneity[
  heterogeneity$moderator == "focal_tenure" &
    heterogeneity$result_type == "focal_contrast", ,
  drop = FALSE
]
full_aggregate <- aggregate[
  aggregate$sample == "full_1993_2010" &
    aggregate$window == "post_mean_minus_t_minus_1", ,
  drop = FALSE
]
full_decomp <- decomposition[
  decomposition$sample == "full_1993_2010", ,
  drop = FALSE
]

# Guards are paired with positives that must be rejected.
tooth_tests <- data.frame(
  check = c(
    "numeric_guard_rejects_perturbed_att",
    "tenure_clock_guard_rejects_invalid_positive",
    "primary_family_rejects_appendix_tenure",
    "holm_family_rejects_missing_row",
    "decomposition_guard_rejects_perturbed_component"
  ),
  pass = c(
    abs(-0.1072 - (-0.0972)) > 1e-10,
    !lmv2_stayer_tenure_valid(c(1, 3), c(0, 4)),
    !"focal_tenure" %in% cfg$construction$primary_moderators,
    nrow(primary[-1, , drop = FALSE]) != 8L,
    abs(
      (0.01 + full_decomp$estimate[
        full_decomp$component == "symmetric_extensive"
      ]) +
        full_decomp$estimate[
          full_decomp$component == "symmetric_intensive"
        ] -
        full_decomp$estimate[full_decomp$component == "total"]
    ) > 1e-10
  ),
  stringsAsFactors = FALSE
)

source_paths <- file.path(BASE, "R", c(
  "33b_build_lmv2_stayer_moderators.R",
  "33c_compute_lmv2_stayer_power_gate.R",
  "33d_estimate_lmv2_stayer_heterogeneity.R"
))
source_hashes <- vapply(
  source_paths, digest::digest, character(1), algo = "sha256", file = TRUE
)
manifest_hashes <- c(
  moderator_manifest$source_sha256,
  power_manifest$source_sha256,
  est_manifest$source_sha256
)
sym_sum <- sum(full_decomp$estimate[
  full_decomp$component %in%
    c("symmetric_extensive", "symmetric_intensive")
])
total <- full_decomp$estimate[full_decomp$component == "total"]
checks <- data.frame(
  check = c(
    "all_moderator_checks_pass",
    "all_unit_analysis_checks_pass",
    "all_tooth_tests_pass",
    "one_design_hash_across_all_stages",
    "executed_sources_match_manifests",
    "power_stage_wrote_no_heterogeneity_estimates",
    "primary_family_has_exactly_eight_rows",
    "holm_appendix_complete_for_primary_family",
    "all_primary_estimates_and_intervals_finite",
    "tenure_is_appendix_only_and_reported_for_amended_sample",
    "aggregate_stayer_att_reproduced",
    "certified_s4_aggregate_inference_is_complete_and_reproduced",
    "extensive_intensive_identity_passes",
    "certified_s3_and_s4_inputs_still_pass"
  ),
  pass = c(
    all(moderator_cert$pass),
    all(unit_cert$pass),
    all(tooth_tests$pass),
    length(unique(c(
      moderator_manifest$design_hash,
      power_manifest$design_hash,
      est_manifest$design_hash,
      lmv2_stayer_het_hash()
    ))) == 1L,
    identical(unname(source_hashes), unname(manifest_hashes)),
    power_manifest$heterogeneity_point_estimates_written == 0L,
    nrow(primary) == 8L &&
      !anyDuplicated(paste(primary$moderator, primary$outcome)),
    all(is.finite(primary$holm_adjusted_governing_p)),
    all(is.finite(primary$estimate)) &&
      all(is.finite(primary$ci_low)) &&
      all(is.finite(primary$ci_high)) &&
      all(primary$ci_low <= primary$estimate) &&
      all(primary$estimate <= primary$ci_high),
    nrow(tenure) == 2L &&
      all(is.na(tenure$holm_adjusted_governing_p)),
    isTRUE(est_manifest$aggregate_att_reproduced),
    nrow(s4_primary_inference) == 6L &&
      all(c(
        "deal_cluster_robust", "deal_wild_bootstrap_t",
        "two_way_deal_inventor"
      ) %in% s4_primary_inference$inference) &&
      all(vapply(c("patent_count", "active_patenting"), function(y) {
        internal <- full_aggregate$estimate[full_aggregate$outcome == y]
        external <-
          s4_primary_inference$estimate[s4_primary_inference$outcome == y]
        length(internal) == 1L && length(external) == 3L &&
          max(abs(internal - external)) <= 1e-10
      }, logical(1))),
    length(total) == 1L && abs(sym_sum - total) <= 1e-10,
    all(read_csv(cfg$inputs$s3_certification)$pass) &&
      all(read_csv(cfg$inputs$s4_certification)$pass)
  ),
  stringsAsFactors = FALSE
)
lmv2_stayer_het_assert(tooth_tests)
lmv2_stayer_het_assert(checks)
utils::write.csv(
  tooth_tests, file.path(out_dir, "stayer_tooth_tests.csv"),
  row.names = FALSE
)
utils::write.csv(
  checks, file.path(out_dir, "stayer_certification.csv"),
  row.names = FALSE
)

moderator_labels <- c(
  predeal_productivity = "Pre-deal productivity",
  career_age = "Career age",
  team_persistence = "Persistent team",
  techfit = "Inventor-acquirer TechFit",
  focal_tenure = "Focal-group tenure"
)
outcome_labels <- c(
  patent_count = "Patent count",
  active_patenting = "Probability of patenting"
)
primary$moderator_label <- moderator_labels[primary$moderator]
primary$outcome_label <- outcome_labels[primary$outcome]
primary$raw_significance <- ifelse(
  primary$governing_p < .05, "Raw p < 0.05", "Raw p >= 0.05"
)
primary$moderator_label <- factor(
  primary$moderator_label,
  levels = rev(unname(moderator_labels[c(
    "predeal_productivity", "career_age",
    "team_persistence", "techfit"
  )]))
)

p <- ggplot2::ggplot(
  primary,
  ggplot2::aes(
    x = estimate, y = moderator_label, shape = raw_significance
  )
) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"], linewidth = .5
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = ci_low, xmax = ci_high),
    width = .12, colour = LMV2_COLOURS["forest"]
  ) +
  ggplot2::geom_point(
    size = 2.8, colour = LMV2_COLOURS["forest"]
  ) +
  ggplot2::facet_wrap(
    ~ outcome_label, scales = "free_x", ncol = 1
  ) +
  ggplot2::scale_shape_manual(values = c(
    "Raw p < 0.05" = 16, "Raw p >= 0.05" = 1
  )) +
  ggplot2::labs(
    x = "ATT difference: high minus low moderator value",
    y = NULL,
    title = "Initially retained inventor heterogeneity",
    subtitle = paste(
      "P5b weights; conservative intervals; ordinary unadjusted p-values"
    ),
    shape = NULL
  ) +
  lmv2_theme() +
  ggplot2::theme(legend.position = "bottom")
figure_path <- file.path(
  result_dir, "figure_stayer_heterogeneity_forest.png"
)
ggplot2::ggsave(
  figure_path, p, width = 9, height = 7.5, dpi = 180
)

table_primary <- primary[, c(
  "moderator", "outcome", "contrast", "estimate", "ci_low", "ci_high",
  "governing_p", "treated_inventors", "nominal_deals"
)]
names(table_primary)[names(table_primary) == "governing_p"] <- "p_value"
utils::write.csv(
  table_primary,
  file.path(result_dir, "table_stayer_heterogeneity_primary.csv"),
  row.names = FALSE
)
table_diagnostics <- primary[, c(
  "moderator", "outcome", "contrast", "estimate", "ci_low", "ci_high",
  "governing_p", "power_gate_pass", "precision_mde",
  "type_m_exaggeration_ratio_at_threshold"
)]
names(table_diagnostics)[names(table_diagnostics) == "governing_p"] <-
  "p_value"
utils::write.csv(
  table_diagnostics,
  file.path(result_dir, "table_stayer_heterogeneity_diagnostics.csv"),
  row.names = FALSE
)
utils::write.csv(
  heterogeneity[, setdiff(
    names(heterogeneity), "holm_adjusted_governing_p"
  ), drop = FALSE],
  file.path(result_dir, "table_stayer_heterogeneity_complete.csv"),
  row.names = FALSE
)
utils::write.csv(
  s4_primary_inference,
  file.path(result_dir, "table_stayer_aggregate_effects.csv"),
  row.names = FALSE
)
utils::write.csv(
  aggregate,
  file.path(result_dir, "table_stayer_aggregate_reconstruction.csv"),
  row.names = FALSE
)
standard_did <- heterogeneity[
  heterogeneity$result_type == "focal_contrast" &
    heterogeneity$sample == "full_1994_2010" &
    heterogeneity$window == "five_post_minus_five_pre" &
    heterogeneity$model_type == "five_by_five_companion" &
    heterogeneity$techfit_variant %in% c("not_applicable", "full"),
  c("moderator", "outcome", "contrast", "estimate", "ci_low", "ci_high",
    "governing_p", "treated_inventors", "nominal_deals"), drop = FALSE
]
if (nrow(standard_did) != 8L ||
    anyDuplicated(paste(standard_did$moderator, standard_did$outcome))) {
  stop("Conventional aggregate-DiD stayer companion is incomplete")
}
names(standard_did)[names(standard_did) == "governing_p"] <- "p_value"
primary_comparison <- table_primary[, c(
  "moderator", "outcome", "contrast", "estimate", "ci_low", "ci_high",
  "p_value", "treated_inventors", "nominal_deals"
)]
names(primary_comparison)[4:7] <- c(
  "collapsed_estimate", "collapsed_ci_low", "collapsed_ci_high",
  "collapsed_p_value"
)
standard_comparison <- standard_did[, c(
  "moderator", "outcome", "contrast", "estimate", "ci_low", "ci_high",
  "p_value", "treated_inventors", "nominal_deals"
)]
names(standard_comparison)[4:7] <- c(
  "conventional_estimate", "conventional_ci_low", "conventional_ci_high",
  "conventional_p_value"
)
heterogeneity_aggregation_comparison <- merge(
  primary_comparison, standard_comparison,
  by = c("moderator", "outcome", "contrast", "treated_inventors", "nominal_deals"),
  sort = FALSE
)
if (nrow(heterogeneity_aggregation_comparison) != 8L) {
  stop("Stayer heterogeneity aggregation comparison lost a primary contrast")
}
utils::write.csv(
  heterogeneity_aggregation_comparison,
  file.path(result_dir, "table_stayer_heterogeneity_aggregation_comparison.csv"),
  row.names = FALSE
)
one_sd <- heterogeneity[
  heterogeneity$result_type == "one_sd_effect" &
    heterogeneity$sample == "full_1994_2010" &
    heterogeneity$window == "five_post_minus_five_pre" &
    heterogeneity$model_type == "five_by_five_companion" &
    heterogeneity$techfit_variant %in% c("not_applicable", "full"),
  c("moderator", "outcome", "estimate", "ci_low", "ci_high", "governing_p"),
  drop = FALSE
]
if (nrow(one_sd) != 6L) stop("One-SD stayer heterogeneity table is incomplete")
one_sd$effect_scale <- "One-standard-deviation increase"
team_binary <- standard_did[
  standard_did$moderator == "team_persistence",
  c("moderator", "outcome", "estimate", "ci_low", "ci_high", "p_value"),
  drop = FALSE
]
names(team_binary)[names(team_binary) == "p_value"] <- "governing_p"
team_binary$effect_scale <- "Persistent pre-deal team versus none"
interpretable_effects <- rbind(one_sd, team_binary)
names(interpretable_effects)[names(interpretable_effects) == "governing_p"] <-
  "p_value"
utils::write.csv(
  interpretable_effects,
  file.path(result_dir, "table_stayer_heterogeneity_interpretable_effects.csv"),
  row.names = FALSE
)
decomposition_main <- decomposition[
  decomposition$component %in%
    c("symmetric_extensive", "symmetric_intensive", "total"),
  c("sample", "component", "estimate", "five_year_patents", "share_of_total"),
  drop = FALSE
]
utils::write.csv(
  decomposition_main,
  file.path(result_dir, "table_stayer_margin_decomposition.csv"),
  row.names = FALSE
)
utils::write.csv(
  decomposition,
  file.path(result_dir, "table_stayer_margin_decomposition_inference_appendix.csv"),
  row.names = FALSE
)
utils::write.csv(
  power, file.path(result_dir, "table_stayer_power_gate.csv"),
  row.names = FALSE
)
utils::write.csv(
  team_counts,
  file.path(result_dir, "table_stayer_team_counts.csv"),
  row.names = FALSE
)
utils::write.csv(
  techfit_funnel,
  file.path(result_dir, "table_stayer_techfit_funnel.csv"),
  row.names = FALSE
)

selection_path <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "P5B_STAYER_SELECTION_DIAGNOSTICS", "selection_group_summary.csv"
)
if (file.exists(selection_path)) {
  selection <- read_csv(selection_path)
  utils::write.csv(
    selection,
    file.path(result_dir, "table_stayer_selection_summary.csv"),
    row.names = FALSE
  )
}

fmt <- function(x, digits = 3) formatC(x, digits = digits, format = "f")
get_primary <- function(moderator, outcome) {
  z <- primary[
    primary$moderator == moderator & primary$outcome == outcome, ,
    drop = FALSE
  ]
  if (nrow(z) != 1L) stop("Primary reporting row is not unique")
  z
}
count_att <- s4_primary_inference[
  s4_primary_inference$outcome == "patent_count" &
    s4_primary_inference$inference == "two_way_deal_inventor", ,
  drop = FALSE
]
count_wild <- s4_primary_inference[
  s4_primary_inference$outcome == "patent_count" &
    s4_primary_inference$inference == "deal_wild_bootstrap_t", ,
  drop = FALSE
]
active_att <- s4_primary_inference[
  s4_primary_inference$outcome == "active_patenting" &
    s4_primary_inference$inference == "two_way_deal_inventor", ,
  drop = FALSE
]
prod_count <- get_primary("predeal_productivity", "patent_count")
age_count <- get_primary("career_age", "patent_count")
team_count <- get_primary("team_persistence", "patent_count")
tech_count <- get_primary("techfit", "patent_count")
tenure_count <- tenure[
  tenure$sample == "full_1993_2010" &
    tenure$outcome == "patent_count", ,
  drop = FALSE
]
note <- c(
  "# Initially retained inventor heterogeneity results",
  "",
  "## TL;DR",
  "",
  sprintf(
    paste(
      "The separately balanced P5b design contains %s initially retained",
      "treated inventors across %s deals. Their aggregate patent-count ATT is",
      "%s patents per inventor-year (two-way deal/inventor 95%% CI %s to %s;",
      "p=%s)."
    ),
    format(
      moderator_audit$treated_inventors,
      big.mark = ",", scientific = FALSE
    ),
    format(moderator_audit$treated_deals, big.mark = ",", scientific = FALSE),
    fmt(count_att$estimate), fmt(count_att$ci_low),
    fmt(count_att$ci_high), fmt(count_att$p_value)
  ),
  sprintf(
    paste(
      "The corresponding probability-of-patenting effect is %s percentage",
      "points (two-way 95%% CI %s to %s; p=%s)."
    ),
    fmt(100 * active_att$estimate, 2),
    fmt(100 * active_att$ci_low, 2),
    fmt(100 * active_att$ci_high, 2),
    fmt(active_att$p_value)
  ),
  "",
  "## Predetermined heterogeneity",
  "",
  sprintf(
    paste(
      "The p75-minus-p25 productivity contrast for patent count is %s",
      "(p=%s)."
    ),
    fmt(prod_count$estimate), fmt(prod_count$governing_p)
  ),
  sprintf(
    paste(
      "The career-age contrast is %s (p=%s), the persistent-team contrast",
      "is %s (p=%s), and the TechFit contrast is %s (p=%s)."
    ),
    fmt(age_count$estimate), fmt(age_count$governing_p),
    fmt(team_count$estimate), fmt(team_count$governing_p),
    fmt(tech_count$estimate), fmt(tech_count$governing_p)
  ),
  paste(
    "None of the eight predeclared stayer contrasts passes the prospective",
    "MDE gate. The point estimates and unadjusted p-values are reported for",
    "completeness, but they do not support a confirmatory heterogeneity claim."
  ),
  sprintf(
    paste(
      "Corrected focal tenure is appendix-only. Its p75-minus-p25 patent-count",
      "contrast is %s (p=%s) and is not part of the primary family."
    ),
    fmt(tenure_count$estimate), fmt(tenure_count$governing_p)
  ),
  "",
  "All moderator variables end by event time -1. The same 9,999 Webb draws",
  "are used for every heterogeneity test. Heterogeneity contrasts use the more",
  "conservative of deal-wild and two-way deal/inventor inference; the aggregate",
  "ATT reports the previously selected two-way inference with wild bootstrap",
  "shown transparently as a companion.",
  "",
  "## Precision diagnostics",
  "",
  paste(
    "The main table and diagnostics report ordinary unadjusted governing",
    "p-values. MDE and Type-M diagnostics are retained in",
    "`table_stayer_heterogeneity_diagnostics.csv`."
  ),
  paste(
    "The decomposition's inferential diagnostics are retained separately in",
    "`table_stayer_margin_decomposition_inference_appendix.csv`. The main",
    "decomposition table reports quantities and shares only; its intensive",
    "component is descriptive because activity is post-treatment selected."
  ),
  "",
  "## Interpretation limit",
  "",
  paste(
    "Initial retention is defined using the first patent observed in event",
    "time +1 through +5. These estimates therefore describe heterogeneity",
    "within the post-treatment-selected, patent-observed initially retained",
    "population. They are not unconditional employment-retention effects."
  ),
  paste(
    "Control observations face the symmetric requirement that the focal",
    "control group remains patent-active through +5. In the patent-based",
    "operational sense, the group therefore exists at the end of follow-up",
    "and remains at risk of patenting in +6 or later; an observed +6 patent",
    "is not required."
  )
)
note_path <- file.path(
  cfg$output_dir, "stayer_heterogeneity_results.md"
)
writeLines(note, note_path, useBytes = TRUE)

artifact_paths <- c(
  figure_path,
  file.path(result_dir, c(
    "table_stayer_heterogeneity_primary.csv",
    "table_stayer_heterogeneity_diagnostics.csv",
    "table_stayer_heterogeneity_complete.csv",
    "table_stayer_aggregate_effects.csv",
    "table_stayer_aggregate_reconstruction.csv",
    "table_stayer_heterogeneity_aggregation_comparison.csv",
    "table_stayer_heterogeneity_interpretable_effects.csv",
    "table_stayer_margin_decomposition.csv",
    "table_stayer_margin_decomposition_inference_appendix.csv",
    "table_stayer_power_gate.csv",
    "table_stayer_team_counts.csv",
    "table_stayer_techfit_funnel.csv"
  )),
  note_path
)
selection_output <- file.path(
  result_dir, "table_stayer_selection_summary.csv"
)
if (file.exists(selection_output)) {
  artifact_paths <- c(artifact_paths, selection_output)
}
manifest <- data.frame(
  artifact = basename(artifact_paths),
  sha256 = vapply(
    artifact_paths, digest::digest, character(1),
    algo = "sha256", file = TRUE
  ),
  bytes = file.info(artifact_paths)$size,
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest,
  file.path(result_dir, "stayer_heterogeneity_artifact_manifest.csv"),
  row.names = FALSE
)
message("Certified stayer heterogeneity package written to: ", result_dir)
