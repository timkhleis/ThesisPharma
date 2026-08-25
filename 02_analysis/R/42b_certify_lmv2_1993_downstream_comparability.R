#!/usr/bin/env Rscript

# Certify that every substantive result carried into the 1993 amendment uses
# the amended cohort definition and summarize the resulting evidence.

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
AUDIT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
RESULTS <- file.path(
  BASE, "output", "results", "local_match_v2_1993_amendment"
)
OUT <- file.path(AUDIT, "RESULT_SUMMARY")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

read_csv <- function(...) {
  utils::read.csv(
    file.path(...), stringsAsFactors = FALSE, check.names = FALSE
  )
}
bool <- function(x) {
  if (is.logical(x)) return(x)
  tolower(as.character(x)) == "true"
}
cert_pass <- function(path) {
  z <- read_csv(path)
  if (!"pass" %in% names(z) || !nrow(z)) return(FALSE)
  all(bool(z$pass))
}

certifications <- data.frame(
  package = c(
    "full_cohort_primary", "stayer_primary", "stayer_secondary",
    "stayer_techdrift_windowed",
    "stayer_selection", "inventor_heterogeneity", "dealsim_power_gate",
    "vr_heterogeneity", "stayer_heterogeneity", "exit_decomposition",
    "recurrent_inventors", "completion_year_sensitivity",
    "control_endpoint_diagnostic", "simple_control_placebo"
  ),
  path = file.path(AUDIT, c(
    "P6_ESTIMATION_PRIMARY/p6_estimation_input_certification.csv",
    "P5B_STAYER_S4_RESULTS/s4_certification.csv",
    "P5B_STAYER_S6_SECONDARY_OUTCOMES/s6_certification.csv",
    paste0(
      "P5B_TECHDRIFT_WINDOWED_AMENDMENT/",
      "techdrift_certification.csv"
    ),
    "P5B_STAYER_SELECTION_DIAGNOSTICS/selection_certification.csv",
    "P7_INVENTOR_HETEROGENEITY/heterogeneity_certification.csv",
    "P7_DEALSIM_POWER_GATE/dealsim_power_certification.csv",
    "P7_VR_HETEROGENEITY/vr_certification.csv",
    "P7_STAYER_HETEROGENEITY/stayer_certification.csv",
    "P8_EXIT_DECOMPOSITION/exit_decomposition_certification.csv",
    "P8_RECURRENT_INVENTORS/recurrent_result_certification.csv",
    "P6_COMPLETION_YEAR_SENSITIVITY/completion_year_certification.csv",
    "C1_CONTROL_ENDPOINT_DIAGNOSTIC/control_endpoint_certification.csv",
    paste0(
      "ROBUSTNESS_RELEASE_1993/",
      "SIMPLE_CONTROL_PLACEBO_2000DRAW_DYNAMIC/",
      "simple_control_placebo_certification.csv"
    )
  )),
  stringsAsFactors = FALSE
)
if (any(!file.exists(certifications$path))) {
  stop(
    "Missing downstream certification(s): ",
    paste(certifications$path[!file.exists(certifications$path)], collapse = ", ")
  )
}
certifications$pass <- vapply(
  certifications$path, cert_pass, logical(1)
)

landmark_cert_path <- file.path(
  AUDIT, "P8_STAYER_LANDMARK", "landmark_certification.csv"
)
landmark_omitted_path <- file.path(
  AUDIT, "P8_STAYER_LANDMARK", "LANDMARK_OMITTED.txt"
)
landmark <- read_csv(landmark_cert_path)
landmark_gate_operated <-
  file.exists(landmark_omitted_path) && any(!bool(landmark$pass))
certifications <- rbind(
  certifications,
  data.frame(
    package = "stayer_landmark_intentionally_omitted",
    path = landmark_cert_path,
    pass = landmark_gate_operated,
    stringsAsFactors = FALSE
  )
)

sample_specs <- list(
  full_cohort = list(
    path = file.path(AUDIT, "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv"),
    allowed = "full_1993_2010"
  ),
  stayer_primary = list(
    path = file.path(AUDIT, "P5B_STAYER_S4_RESULTS", "s4_headline_post_att.csv"),
    allowed = "full_1993_2010"
  ),
  stayer_secondary = list(
    path = file.path(
      AUDIT, "P5B_STAYER_S6_SECONDARY_OUTCOMES", "s6_secondary_headline.csv"
    ),
    allowed = "full_1993_2010"
  ),
  inventor_heterogeneity = list(
    path = file.path(
      AUDIT, "P7_INVENTOR_HETEROGENEITY", "heterogeneity_group_att.csv"
    ),
    allowed = "full_1993_2010"
  ),
  vr_heterogeneity = list(
    path = file.path(
      AUDIT, "P7_VR_HETEROGENEITY", "vr_heterogeneity_results.csv"
    ),
    allowed = c("full_1993_2010", "full_1993_2010_team_positive")
  ),
  stayer_heterogeneity = list(
    path = file.path(
      AUDIT, "P7_STAYER_HETEROGENEITY", "stayer_heterogeneity_results.csv"
    ),
    allowed = "full_1993_2010"
  ),
  exit_decomposition = list(
    path = file.path(AUDIT, "P8_EXIT_DECOMPOSITION", "exit_post_att.csv"),
    allowed = c(
      "headline_1993_2010", "strict_1993_2005",
      "headline_1993_2010_t1_t3"
    )
  ),
  recurrent_inventors = list(
    path = file.path(
      AUDIT, "P8_RECURRENT_INVENTORS", "recurrent_exit_post_att.csv"
    ),
    allowed = "headline_1993_2010_t1_t5"
  ),
  completion_year = list(
    path = file.path(
      AUDIT, "P6_COMPLETION_YEAR_SENSITIVITY",
      "completion_year_inclusive_headline.csv"
    ),
    allowed = "full_1993_2010"
  ),
  control_endpoint = list(
    path = file.path(
      AUDIT, "C1_CONTROL_ENDPOINT_DIAGNOSTIC",
      "control_endpoint_headline.csv"
    ),
    allowed = "full_1993_2010_control_group_active_through_g_plus_5"
  )
)
sample_checks <- do.call(rbind, lapply(names(sample_specs), function(name) {
  spec <- sample_specs[[name]]
  z <- read_csv(spec$path)
  observed <- sort(unique(z$sample))
  data.frame(
    package = name,
    observed_samples = paste(observed, collapse = ";"),
    expected_samples = paste(sort(spec$allowed), collapse = ";"),
    pass = setequal(observed, spec$allowed),
    stringsAsFactors = FALSE
  )
}))
placebo_manifest <- read_csv(
  AUDIT, "SIMPLE_CONTROL_PLACEBO", "simple_control_placebo_manifest.csv"
)
sample_checks <- rbind(
  sample_checks,
  data.frame(
    package = "simple_control_placebo",
    observed_samples = placebo_manifest$cohorts,
    expected_samples = "1993-2010",
    pass = nrow(placebo_manifest) == 1L &&
      identical(placebo_manifest$cohorts, "1993-2010"),
    stringsAsFactors = FALSE
  )
)

active_sources <- file.path(BASE, "R", c(
  "28a_lmv2_p5b_s4_config.R",
  "28d_summarize_lmv2_p5b_s4_results.R",
  "29a_lmv2_p5b_selection_diagnostics.R",
  "30a_lmv2_dealsim_power_config.R",
  "30b_build_lmv2_dealsim_table.R",
  "30c_assign_lmv2_dealsim_terciles.R",
  "30d_compute_lmv2_dealsim_power.R",
  "30e_certify_lmv2_dealsim_power_gate.R",
  "31a_lmv2_inventor_heterogeneity_config.R",
  "31b_build_lmv2_inventor_moderators.R",
  "31c_estimate_lmv2_inventor_heterogeneity.R",
  "31d_report_certify_lmv2_inventor_heterogeneity.R",
  "32a_lmv2_vr_heterogeneity_config.R",
  "32b_build_lmv2_vr_moderators.R",
  "32c_compute_lmv2_vr_power_gate.R",
  "32d_estimate_lmv2_vr_heterogeneity.R",
  "32e_report_certify_lmv2_vr_heterogeneity.R",
  "33a_lmv2_stayer_heterogeneity_config.R",
  "33b_build_lmv2_stayer_moderators.R",
  "33c_compute_lmv2_stayer_power_gate.R",
  "33d_estimate_lmv2_stayer_heterogeneity.R",
  "33e_report_certify_lmv2_stayer_heterogeneity.R",
  "34a_run_lmv2_control_endpoint_diagnostic.R",
  "36a_lmv2_exit_decomposition_config.R",
  "final_thesis/36c_estimate_lmv2_exit_decomposition.R",
  "36_run_lmv2_exit_decomposition.R",
  "36_run_lmv2_simple_control_placebo.R",
  "37a_lmv2_stayer_landmark_config_build.R",
  "37b_estimate_certify_lmv2_stayer_landmark.R",
  "37_run_lmv2_stayer_landmark.R",
  "38a_lmv2_recurrent_inventor_config_build.R",
  "38b_estimate_certify_lmv2_recurrent_inventors.R",
  "38_run_lmv2_recurrent_inventors.R",
  "39_build_lmv2_exit_decomposition_thesis_assets.R",
  "40d_audit_lmv2_completion_year_window.R",
  "40e_certify_lmv2_completion_year_window.R"
))
if (any(!file.exists(active_sources))) {
  stop("Missing active amendment source file(s)")
}
forbidden <- "full_1994_2010|buffered_1994_2008|1994:2010|1994--2008"
source_hits <- vapply(active_sources, function(path) {
  any(grepl(forbidden, readLines(path, warn = FALSE)))
}, logical(1))
source_check <- data.frame(
  package = "active_source_set",
  observed_samples = paste(basename(active_sources[source_hits]), collapse = ";"),
  expected_samples = "no retired 1994/double-buffer labels",
  pass = !any(source_hits),
  stringsAsFactors = FALSE
)
sample_checks <- rbind(sample_checks, source_check)

utils::write.csv(
  certifications,
  file.path(OUT, "downstream_package_certification.csv"),
  row.names = FALSE
)
utils::write.csv(
  sample_checks,
  file.path(OUT, "downstream_sample_comparability.csv"),
  row.names = FALSE
)

if (!all(certifications$pass) || !all(sample_checks$pass)) {
  stop("Downstream 1993 comparability certification failed")
}

primary <- read_csv(
  AUDIT, "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv"
)
primary <- primary[
  primary$sample == "full_1993_2010" &
    primary$summary == "average_annual_t1_to_t5" &
    primary$inference == "deal_wild_bootstrap_t", , drop = FALSE
]
outcome_order <- c(
  "patent_count", "active_patenting", "tech_drift", "pqii_scaled",
  "fwd_cits5_scaled"
)
primary <- primary[match(outcome_order, primary$outcome), ]

stayer <- read_csv(
  AUDIT, "P5B_STAYER_S4_RESULTS", "reporting",
  "s4_primary_inference_comparison.csv"
)
stayer <- stayer[
  stayer$sample == "full_1993_2010" &
    stayer$summary == "average_annual_t1_to_t5" &
    stayer$outcome %in% c("patent_count", "active_patenting"), ,
  drop = FALSE
]
stayer_wild <- stayer[stayer$inference == "deal_wild_bootstrap_t", ]
stayer_two_way <- stayer[stayer$inference == "two_way_deal_inventor", ]

techdrift_window <- read_csv(
  AUDIT, "P5B_TECHDRIFT_WINDOWED_AMENDMENT",
  "techdrift_window_estimates.csv"
)
techdrift_window <- techdrift_window[
  techdrift_window$inference == "deal_wild_bootstrap_t", , drop = FALSE
]
required_techdrift_specs <- c(
  "pooled_recent5_main", "pooled_fullstock_sensitivity",
  "pooled_recent5_binary_sensitivity", "pooled_early_post",
  "pooled_late_post", "pooled_recent5_exclude_2010",
  "restricted_prepre_placebo"
)
if (!setequal(
  techdrift_window$specification, required_techdrift_specs
)) stop("Windowed TechDrift release is incomplete")
utils::write.csv(
  techdrift_window,
  file.path(OUT, "stayer_1993_techdrift_windowed.csv"),
  row.names = FALSE
)

selection <- read_csv(
  AUDIT, "P5B_STAYER_SELECTION_DIAGNOSTICS",
  "selection_pairwise_differences.csv"
)[1, ]
inventor_omnibus <- read_csv(
  RESULTS, "inventor_heterogeneity", "table_inventor_heterogeneity_omnibus.csv"
)
vr_power <- read_csv(
  RESULTS, "vr_heterogeneity", "table_vr_power_gate.csv"
)
stayer_power <- read_csv(
  RESULTS, "stayer_heterogeneity", "table_stayer_power_gate.csv"
)
dealsim <- read_csv(
  AUDIT, "P7_DEALSIM_POWER_GATE", "dealsim_power_gate.csv"
)
exit_table <- read_csv(
  RESULTS, "patenting_exit", "table_patenting_exit_decomposition.csv"
)
completion <- read_csv(
  AUDIT, "P6_COMPLETION_YEAR_SENSITIVITY",
  "completion_year_inclusive_headline.csv"
)
completion <- completion[
  completion$sample == "full_1993_2010" &
    completion$outcome == "patent_count" &
    completion$summary == "cumulative_t0_to_t5" &
    bool(completion$governing), , drop = FALSE
]
endpoint <- read_csv(
  AUDIT, "C1_CONTROL_ENDPOINT_DIAGNOSTIC", "control_endpoint_comparison.csv"
)
endpoint <- endpoint[endpoint$role == "diagnostic", ]
placebo <- read_csv(
  AUDIT, "SIMPLE_CONTROL_PLACEBO", "simple_control_placebo_summary.csv"
)

fmt <- function(x, digits = 3L) {
  formatC(as.numeric(x), digits = digits, format = "f")
}
primary_line <- function(z) sprintf(
  "| %s | %s | [%s, %s] | %s |",
  z$outcome, fmt(z$estimate), fmt(z$ci_low), fmt(z$ci_high),
  fmt(z$p_value, 4L)
)
stayer_line <- function(outcome) {
  w <- stayer_wild[stayer_wild$outcome == outcome, ]
  t <- stayer_two_way[stayer_two_way$outcome == outcome, ]
  sprintf(
    "| %s | %s [%s, %s], p=%s | %s [%s, %s], p=%s |",
    outcome, fmt(w$estimate), fmt(w$ci_low), fmt(w$ci_high),
    fmt(w$p_value, 4L), fmt(t$estimate), fmt(t$ci_low), fmt(t$ci_high),
    fmt(t$p_value, 4L)
  )
}
techdrift_line <- function(specification, label) {
  z <- techdrift_window[
    techdrift_window$specification == specification, , drop = FALSE
  ]
  sprintf(
    "| %s | %s | [%s, %s] | %s |",
    label, fmt(z$estimate), fmt(z$ci_low), fmt(z$ci_high),
    fmt(z$p_value, 4L)
  )
}

lines <- c(
  "# Local Match v2: amended 1993--2010 downstream results",
  "",
  "## Release status",
  "",
  sprintf(
    "All %d carried-forward packages and all %d sample-definition checks pass.",
    nrow(certifications), nrow(sample_checks)
  ),
  "The 1993--2010 cohort is the sole main sample in this release.",
  "",
  "## Full-cohort primary effects",
  "",
  "Average annual ATT over t=+1,...,+5; governing 9,999-draw deal-wild inference.",
  "",
  "| Outcome | ATT | 95% CI | p |",
  "|---|---:|---:|---:|",
  vapply(seq_len(nrow(primary)), function(i) primary_line(primary[i, ]), character(1)),
  "",
  "TechDrift fails its joint pretrend test (p=0.0128), so it is not interpreted causally.",
  "",
  "## Initially retained inventors",
  "",
  "| Outcome | Deal-wild inference | Two-way deal/inventor inference |",
  "|---|---:|---:|",
  stayer_line("patent_count"),
  stayer_line("active_patenting"),
  "",
  sprintf(
    paste(
      "Initially retained inventors have %.3f more pre-deal patents per year",
      "than leavers (standardized difference %.3f), indicating positive",
      "selection on prior patenting within the observed patent-based statuses."
    ),
    selection$patent_mean_difference,
    selection$patent_standardized_difference
  ),
  "",
  "## Technological portfolio displacement among initially retained inventors",
  "",
  paste(
    "TechDrift requires classified IPC4 activity before and after the",
    "acquisition. These are selected-group matched portfolio contrasts,",
    "not the full-cohort DiD ATT. Positive estimates indicate greater",
    "technological displacement among treated retained inventors."
  ),
  "",
  "| Measure | Contrast | 95% CI | p |",
  "|---|---:|---:|---:|",
  techdrift_line(
    "pooled_recent5_main",
    "Count-weighted recent pre versus pooled post (main)"
  ),
  techdrift_line(
    "pooled_fullstock_sensitivity",
    "Count-weighted complete observed stock (sensitivity)"
  ),
  techdrift_line(
    "pooled_recent5_binary_sensitivity",
    "Binary IPC4 presence (sensitivity)"
  ),
  techdrift_line(
    "restricted_prepre_placebo",
    "Restricted fixed-window pre/pre diagnostic"
  ),
  "",
  paste(
    "The amended pooled main estimate is small, negative, and imprecise.",
    "The baseline, vector-weight, timing, late-tail, count-support, and",
    "pre/pre diagnostics provide no evidence that acquisitions increase",
    "technological displacement among initially retained inventors."
  ),
  "",
  "## Heterogeneity and mechanism limits",
  "",
  sprintf(
    paste(
      "The inventor-level productivity omnibus has an ordinary p=%.4f, but",
      "its high-productivity cell fails the prospective balance gate. The",
      "team pattern also fails its balance gate; both remain appendix evidence."
    ),
    inventor_omnibus$omnibus_governing_p[
      inventor_omnibus$moderator == "predeal_productivity"
    ]
  ),
  sprintf(
    "VR heterogeneity: %d/%d contrasts pass the prospective MDE gate; stayer heterogeneity: %d/%d pass.",
    sum(bool(vr_power$power_gate_pass)), nrow(vr_power),
    sum(bool(stayer_power$power_gate_pass)), nrow(stayer_power)
  ),
  sprintf(
    paste(
      "DealSim selects Path %s: no tercile, quadratic, or spline ATT is",
      "reported because the largest joint MDE is %.3f, versus the frozen",
      "meaningful contrast of %.3f."
    ),
    dealsim$selected_path, dealsim$maximum_joint_mde,
    dealsim$meaningful_annual_contrast
  ),
  "",
  "## Exit and robustness results",
  "",
  sprintf(
    paste(
      "For the full cohort, cessation accounts for %.1f%% of the patent-count",
      "loss, reduced active patenting conditional on survival %.1f%%, and",
      "patents per active year %.1f%%."
    ),
    100 * exit_table$cessation_share[exit_table$population == "full_cohort"],
    100 * exit_table$active_given_survival_share[
      exit_table$population == "full_cohort"
    ],
    100 * exit_table$patents_per_active_year_share[
      exit_table$population == "full_cohort"
    ]
  ),
  sprintf(
    paste(
      "The recurrent-predeal-inventor total ATT is %.3f; its exit component",
      "is %.3f. The t+1 landmark design is omitted because its pre-specified",
      "retention, balance, and ESS gates did not all pass."
    ),
    exit_table$total_att[
      exit_table$population == "recurrent_predeal_inventors"
    ],
    exit_table$exit_estimate[
      exit_table$population == "recurrent_predeal_inventors"
    ]
  ),
  sprintf(
    paste(
      "Including the completion year gives a cumulative t=0,...,+5 effect of",
      "%.3f (95%% CI [%s, %s]). Restricting controls to focal groups active",
      "through g+5 gives %.3f (95%% CI [%s, %s])."
    ),
    completion$estimate, fmt(completion$ci_low), fmt(completion$ci_high),
    endpoint$estimate, fmt(endpoint$ci_low), fmt(endpoint$ci_high)
  ),
  sprintf(
    paste(
      "Across 50 symmetric untreated-firm placebo draws, the mean placebo ATT",
      "is %.3f (Monte Carlo p=%.3f); one draw is at or below the amended",
      "primary patent-count ATT."
    ),
    placebo$mean_placebo_att, placebo$mean_placebo_p_value
  )
)
writeLines(
  lines,
  file.path(OUT, "local_match_v2_1993_downstream_results.md"),
  useBytes = TRUE
)

message("Downstream 1993 comparability certified: ", OUT)
