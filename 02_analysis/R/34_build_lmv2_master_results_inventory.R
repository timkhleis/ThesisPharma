#!/usr/bin/env Rscript

# =============================================================================
# 34_build_lmv2_master_results_inventory.R
#
# Purpose: create one machine-readable and one human-readable index of the
# certified thesis results. This script does not estimate outcomes.
#
# Inputs: certified P6 quantity/secondary outputs, full-cohort heterogeneity,
# P5b/S4 initially retained effects, stayer selection/decomposition, stayer
# heterogeneity, and the DealSim feasibility gate.
#
# Outputs:
# - output/results/local_match_v2/CURRENT_LOCAL_MATCH_V2/results_inventory/
#   master_results_inventory.csv
#   master_results_inventory_certification.csv
#   source_manifest.csv
# - notes/local_match_v2_master_results_inventory.md
# =============================================================================

options(stringsAsFactors = FALSE, scipen = 999)
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Package 'digest' is required for handoff hash verification.")
}

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
audit <- file.path(
  root, "02_analysis", "output", "audit", "local_match_v2"
)
results <- file.path(
  root, "02_analysis", "output", "results", "local_match_v2"
)
appendix <- file.path(root, "02_analysis", "output", "appendix")
out_dir <- file.path(
  results, "CURRENT_LOCAL_MATCH_V2", "results_inventory"
)
note_path <- file.path(
  root, "02_analysis", "notes", "local_match_v2_master_results_inventory.md"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

paths <- c(
  quantity = file.path(
    audit, "P6_QUANTITY_COMMUNICATION_PACKAGE",
    "quantity_results_appendix.csv"
  ),
  p6_cert = file.path(
    audit, "P6_FULLCOHORT_RESULTS_PACKAGE",
    "final_package_certification.csv"
  ),
  secondary = file.path(
    audit, "P6_FULLCOHORT_RESULTS_PACKAGE", "d5_secondary_outcomes.csv"
  ),
  vr_cert = file.path(
    audit, "P7_VR_HETEROGENEITY", "vr_certification.csv"
  ),
  vr_heterogeneity = file.path(
    results, "vr_heterogeneity", "table_vr_heterogeneity.csv"
  ),
  s3_weights = file.path(
    audit, "P5B_STAYER_S3", "s3_production_weights.parquet"
  ),
  s3_manifest = file.path(
    audit, "P5B_STAYER_S3", "s3_manifest.csv"
  ),
  s3_cert = file.path(
    audit, "P5B_STAYER_S3", "s3_certification.csv"
  ),
  s4_cert = file.path(
    audit, "P5B_STAYER_S4_RESULTS", "s4_certification.csv"
  ),
  stayer_aggregate = file.path(
    results, "stayer_heterogeneity", "table_stayer_aggregate_effects.csv"
  ),
  stayer_inference_comparison = file.path(
    audit, "P5B_STAYER_S4_RESULTS", "reporting",
    "s4_primary_inference_comparison.csv"
  ),
  stayer_loyo = file.path(
    audit, "P5B_STAYER_S4_RESULTS", "reporting",
    "s4_loyo_heldout_diagnostics.csv"
  ),
  s5_cert = file.path(
    audit, "P5B_STAYER_S5_SELECTION_DECOMP", "s5_certification.csv"
  ),
  stayer_selection = file.path(
    audit, "P5B_STAYER_S5_SELECTION_DECOMP",
    "s5_selection_pre_characteristics.csv"
  ),
  stayer_secondary_cert = file.path(
    audit, "P5B_STAYER_S6_SECONDARY_OUTCOMES", "s6_certification.csv"
  ),
  stayer_secondary = file.path(
    audit, "P5B_STAYER_S6_SECONDARY_OUTCOMES",
    "s6_secondary_headline.csv"
  ),
  p8_cert = file.path(
    audit, "P8_EXIT_DECOMPOSITION",
    "exit_decomposition_certification.csv"
  ),
  p8_components = file.path(
    audit, "P8_EXIT_DECOMPOSITION",
    "exit_decomposition_components.csv"
  ),
  p8_exit_post = file.path(
    audit, "P8_EXIT_DECOMPOSITION", "exit_post_att.csv"
  ),
  recurrent_cert = file.path(
    audit, "P8_RECURRENT_INVENTORS",
    "recurrent_result_certification.csv"
  ),
  recurrent_components = file.path(
    audit, "P8_RECURRENT_INVENTORS",
    "recurrent_decomposition_components.csv"
  ),
  landmark_cert = file.path(
    audit, "P8_STAYER_LANDMARK", "landmark_certification.csv"
  ),
  landmark_status = file.path(
    audit, "P8_STAYER_LANDMARK", "landmark_estimation_status.csv"
  ),
  placebo_summary = file.path(
    appendix, "simple_control_placebo_2000draw",
    "simple_control_placebo_summary.csv"
  ),
  placebo_manifest = file.path(
    appendix, "simple_control_placebo_2000draw",
    "simple_control_placebo_manifest.csv"
  ),
  control_endpoint_cert = file.path(
    audit, "C1_CONTROL_ENDPOINT_DIAGNOSTIC",
    "control_endpoint_certification.csv"
  ),
  control_endpoint_comparison = file.path(
    audit, "C1_CONTROL_ENDPOINT_DIAGNOSTIC",
    "control_endpoint_comparison.csv"
  ),
  control_endpoint_dynamic_comparison = file.path(
    audit, "C1_CONTROL_ENDPOINT_DIAGNOSTIC",
    "control_endpoint_dynamic_comparison.csv"
  ),
  completion_year_cert = file.path(
    audit, "P6_COMPLETION_YEAR_SENSITIVITY",
    "completion_year_certification.csv"
  ),
  completion_year_results = file.path(
    audit, "P6_COMPLETION_YEAR_SENSITIVITY",
    "completion_year_inclusive_headline.csv"
  ),
  stayer_het_cert = file.path(
    audit, "P7_STAYER_HETEROGENEITY", "stayer_certification.csv"
  ),
  stayer_heterogeneity = file.path(
    results, "stayer_heterogeneity",
    "table_stayer_heterogeneity_primary.csv"
  ),
  dealsim_cert = file.path(
    audit, "P7_DEALSIM_POWER_GATE", "dealsim_power_certification.csv"
  ),
  dealsim_gate = file.path(
    audit, "P7_DEALSIM_POWER_GATE", "dealsim_power_gate.csv"
  )
)
missing <- paths[!file.exists(paths)]
if (length(missing)) {
  stop("Missing inventory input(s): ", paste(missing, collapse = ", "))
}

read_csv <- function(path) {
  utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}
cert_passes <- function(path) {
  x <- read_csv(path)
  all(c("check", "pass") %in% names(x)) &&
    !anyNA(x$pass) &&
    all(tolower(as.character(x$pass)) == "true")
}

record <- function(
    domain, population, outcome, analysis, sample, estimate = NA_real_,
    ci_low = NA_real_, ci_high = NA_real_, p_value = NA_real_,
    five_year_effect = NA_real_, reporting_tier, interpretation,
    source_path, status = NA_character_,
    governing_inference = NA_character_,
    selection_basis = NA_character_,
    main_text_eligible = NA,
    pretrend_qualification = NA_character_,
    component_share = NA_real_,
    gap_type = "not_applicable") {
  data.frame(
    domain = domain,
    population = population,
    outcome = outcome,
    analysis = analysis,
    sample = sample,
    estimate = estimate,
    ci_low = ci_low,
    ci_high = ci_high,
    p_value = p_value,
    five_year_effect = five_year_effect,
    component_share = component_share,
    reporting_tier = reporting_tier,
    status = status,
    governing_inference = governing_inference,
    selection_basis = selection_basis,
    main_text_eligible = main_text_eligible,
    pretrend_qualification = pretrend_qualification,
    gap_type = gap_type,
    interpretation = interpretation,
    source_path = normalizePath(
      source_path, winslash = "/", mustWork = TRUE
    ),
    stringsAsFactors = FALSE
  )
}

inventory <- list()

quantity <- read_csv(paths[["quantity"]])
quantity <- quantity[
  quantity$design == "P5c headline" &
    quantity$effect_scale == "per inventor-year", ,
  drop = FALSE
]
for (i in seq_len(nrow(quantity))) {
  z <- quantity[i, ]
  tier <- if (z$sample == "full_1994_2010") "main" else "robustness"
  inventory[[length(inventory) + 1L]] <- record(
    "aggregate", "full target-inventor cohort", "patent_count",
    "entropy-balanced ATT", z$sample, z$estimate, z$ci_low, z$ci_high,
    z$p_value, 5 * z$estimate, tier,
    if (tier == "main") {
      "Preferred quantity estimate; causal interpretation explicitly qualified by LOYO leads."
    } else {
      "Right-censoring-clean companion."
    },
    paths[["quantity"]]
  )
}

secondary <- read_csv(paths[["secondary"]])
secondary <- secondary[secondary$sample == "full_1994_2010", , drop = FALSE]
secondary_tier <- c(
  active_patenting = "secondary",
  pqii_scaled = "secondary",
  fwcit5w_cassi_total = "secondary",
  tech_drift = "appendix"
)
for (i in seq_len(nrow(secondary))) {
  z <- secondary[i, ]
  inventory[[length(inventory) + 1L]] <- record(
    "aggregate", "full target-inventor cohort", z$outcome,
    "entropy-balanced ATT", z$sample, z$estimate, z$ci_low, z$ci_high,
    z$p_value, NA_real_, secondary_tier[[z$outcome]],
    "Secondary outcome; interpretation follows its coverage and pre-trend diagnostics.",
    paths[["secondary"]]
  )
}

vr <- read_csv(paths[["vr_heterogeneity"]])
for (i in seq_len(nrow(vr))) {
  z <- vr[i, ]
  inventory[[length(inventory) + 1L]] <- record(
    "heterogeneity", "full target-inventor cohort", z$outcome,
    paste0(z$moderator, " high-minus-low contrast"),
    "full_1994_2010", z$estimate, z$ci_low, z$ci_high, z$p_value,
    if (z$outcome == "patent_count") 5 * z$estimate else NA_real_,
    "main heterogeneity",
    "All eight predeclared contrasts are reported with conventional inference.",
    paths[["vr_heterogeneity"]]
  )
}

stayer_agg <- read_csv(paths[["stayer_aggregate"]])
stayer_agg <- stayer_agg[
  stayer_agg$inference == "two_way_deal_inventor" &
    stayer_agg$sample == "full_1994_2010", ,
  drop = FALSE
]
for (i in seq_len(nrow(stayer_agg))) {
  z <- stayer_agg[i, ]
  inventory[[length(inventory) + 1L]] <- record(
    "aggregate", "initially retained inventors", z$outcome,
    "separately balanced selected-group ATT", z$sample,
    z$estimate, z$ci_low, z$ci_high, z$p_value,
    if (z$outcome == "patent_count") 5 * z$estimate else NA_real_,
    "stayer main",
    "Conditional selected-group estimate; retention is determined after treatment.",
    paths[["stayer_aggregate"]]
  )
}

stayer_inference <- read_csv(paths[["stayer_inference_comparison"]])
buffered_retained <- stayer_inference[
  stayer_inference$spec == "primary_count_active_scale" &
    stayer_inference$outcome == "patent_count" &
    stayer_inference$sample == "buffered_1994_2008" &
    stayer_inference$summary == "average_annual_t1_to_t5" &
    stayer_inference$inference == "two_way_deal_inventor", ,
  drop = FALSE
]
if (nrow(buffered_retained) != 1L) {
  stop("Expected one buffered retained two-way patent-count row")
}
z <- buffered_retained[1, ]
inventory[[length(inventory) + 1L]] <- record(
  "aggregate", "initially retained inventors", "patent_count",
  "separately balanced selected-group ATT", z$sample,
  z$estimate, z$ci_low, z$ci_high, z$p_value,
  5 * z$estimate, "stayer main",
  paste(
    "Right-censoring-clean selected-group companion;",
    "not promoted over the frozen full-window retained result."
  ),
  paths[["stayer_inference_comparison"]],
  status = "companion",
  governing_inference = z$inference,
  selection_basis = "post-treatment initially patent-retained",
  main_text_eligible = TRUE,
  pretrend_qualification = paste(
    "Buffered held-out t=-3 gap is 0.0856217;",
    "absolute sign-breakdown ratio 1.407."
  ),
  gap_type = "genuine_LOYO_held_out_gap"
)

stayer_loyo <- read_csv(paths[["stayer_loyo"]])
calibration_specs <- data.frame(
  sample = c("full_1994_2010", "buffered_1994_2008"),
  event_time = c(-3L, -3L),
  att = c(
    stayer_agg$estimate[
      stayer_agg$outcome == "patent_count" &
        stayer_agg$sample == "full_1994_2010"
    ],
    buffered_retained$estimate
  ),
  stringsAsFactors = FALSE
)
for (i in seq_len(nrow(calibration_specs))) {
  z <- calibration_specs[i, ]
  lead <- stayer_loyo[
    stayer_loyo$sample == z$sample &
      stayer_loyo$outcome == "patent_count" &
      stayer_loyo$event_time == z$event_time, ,
    drop = FALSE
  ]
  if (nrow(lead) != 1L) {
    stop("Expected one retained LOYO calibration row for ", z$sample)
  }
  ratio <- abs(z$att) / abs(lead$estimate[[1]])
  inventory[[length(inventory) + 1L]] <- record(
    "sign-stability diagnostic", "initially retained inventors",
    "patent_count", "absolute ATT-to-largest-held-out-gap ratio",
    z$sample, estimate = ratio,
    reporting_tier = "diagnostic",
    interpretation = paste(
      "Descriptive sign-breakdown calibration using held-out t=-3;",
      "values near or below one imply weak separation from the lead gap."
    ),
    source_path = paths[["stayer_loyo"]],
    status = "companion",
    governing_inference = "descriptive_ratio",
    selection_basis = "post-treatment initially patent-retained",
    main_text_eligible = TRUE,
    pretrend_qualification = sprintf(
      "Held-out t=-3 gap %.7f; ATT %.7f.", lead$estimate[[1]], z$att
    ),
    gap_type = "genuine_LOYO_held_out_gap"
  )
}

stayer_secondary <- read_csv(paths[["stayer_secondary"]])
stayer_secondary <- stayer_secondary[
  stayer_secondary$sample == "full_1994_2010" &
    stayer_secondary$summary == "average_annual_t1_to_t5" &
    tolower(as.character(stayer_secondary$governing)) == "true", ,
  drop = FALSE
]
for (i in seq_len(nrow(stayer_secondary))) {
  z <- stayer_secondary[i, ]
  inventory[[length(inventory) + 1L]] <- record(
    "aggregate", "initially retained inventors", z$outcome,
    "separately balanced selected-group ATT", z$sample,
    z$estimate, z$ci_low, z$ci_high, z$p_value,
    if (z$outcome %in% c("pqii_scaled", "pqii_observed",
                         "fwcit5w_cassi_total")) {
      5 * z$estimate
    } else {
      NA_real_
    },
    "stayer secondary",
    "Selected-group secondary outcome; interpret with coverage and pretrend diagnostics.",
    paths[["stayer_secondary"]],
    status = "companion",
    governing_inference = z$inference,
    selection_basis = "post-treatment initially patent-retained",
    main_text_eligible = z$outcome %in% c("pqii_scaled", "tech_drift")
  )
}

p8 <- read_csv(paths[["p8_components"]])
p8 <- p8[
  p8$sample == "headline_1994_2010" &
    p8$population %in% c("full_cohort", "initially_retained_broad"), ,
  drop = FALSE
]
for (i in seq_len(nrow(p8))) {
  z <- p8[i, ]
  pop <- if (z$population == "full_cohort") {
    "full target-inventor cohort"
  } else {
    "initially retained inventors"
  }
  inventory[[length(inventory) + 1L]] <- record(
    "P8 decomposition", pop, "patent_count",
    paste0("P8 Shapley ", z$component), z$sample,
    z$estimate, z$ci_low, z$ci_high,
    five_year_effect = z$cumulative_post_window_patents,
    reporting_tier = if (z$population == "full_cohort") {
      "main decomposition"
    } else {
      "stayer decomposition"
    },
    interpretation = if (
      z$population == "initially_retained_broad" &&
        z$component == "cessation"
    ) {
      "Descriptive and partly mechanical because initial retention requires patenting in +1 through +5."
    } else if (z$component == "total") {
      "Exact P8 reconstruction of the corresponding aggregate patent-count contrast."
    } else {
      "P8 accounting component; component-level inference is not released."
    },
    source_path = paths[["p8_components"]],
    status = "descriptive",
    governing_inference = if (z$component == "total") {
      "two_way_deal_inventor_reconstruction"
    } else {
      "none_component_accounting"
    },
    selection_basis = if (z$population == "full_cohort") {
      "predetermined full cohort"
    } else {
      "post-treatment initially patent-retained"
    },
    main_text_eligible = TRUE,
    component_share = z$share_of_total
  )
}

exit_post <- read_csv(paths[["p8_exit_post"]])
exit_post <- exit_post[
  exit_post$sample == "headline_1994_2010" &
    exit_post$summary == "average_annual_t1_to_t5" &
    tolower(as.character(exit_post$governing)) == "true", ,
  drop = FALSE
]
for (i in seq_len(nrow(exit_post))) {
  z <- exit_post[i, ]
  pop <- if (z$population == "full_cohort") {
    "full target-inventor cohort"
  } else {
    "initially retained inventors"
  }
  inventory[[length(inventory) + 1L]] <- record(
    "patenting exit", pop, "end_of_observed_patenting",
    "global career-endpoint ATT", z$sample,
    z$estimate, z$ci_low, z$ci_high, z$p_value,
    reporting_tier = if (z$population == "full_cohort") {
      "main"
    } else {
      "stayer decomposition"
    },
    interpretation = if (z$population == "full_cohort") {
      "Primary extensive-margin result using the global patenting endpoint; right-edge sensitive."
    } else {
      "Selected-group companion; partly mechanical under the initial-retention definition."
    },
    source_path = paths[["p8_exit_post"]],
    status = if (z$population == "full_cohort") "primary" else "descriptive",
    governing_inference = z$inference,
    selection_basis = if (z$population == "full_cohort") {
      "predetermined full cohort"
    } else {
      "post-treatment initially patent-retained"
    },
    main_text_eligible = z$population == "full_cohort"
  )
}

recurrent <- read_csv(paths[["recurrent_components"]])
for (i in seq_len(nrow(recurrent))) {
  z <- recurrent[i, ]
  inventory[[length(inventory) + 1L]] <- record(
    "P8 decomposition", "recurrent pre-deal inventors", "patent_count",
    paste0("P8 recurrent Shapley ", z$component), z$sample,
    z$estimate, z$ci_low, z$ci_high,
    five_year_effect = z$cumulative_post_window_patents,
    reporting_tier = "appendix",
    interpretation = "Predetermined recurrent-inventor accounting companion.",
    source_path = paths[["recurrent_components"]],
    status = "companion",
    governing_inference = if (z$component == "total") {
      "two_way_deal_inventor_reconstruction"
    } else {
      "none_component_accounting"
    },
    selection_basis = "predetermined recurrent pre-deal patenting",
    main_text_eligible = FALSE,
    component_share = z$share_of_total
  )
}

stayer_het <- read_csv(paths[["stayer_heterogeneity"]])
for (i in seq_len(nrow(stayer_het))) {
  z <- stayer_het[i, ]
  inventory[[length(inventory) + 1L]] <- record(
    "heterogeneity", "initially retained inventors", z$outcome,
    paste0(z$moderator, " high-minus-low contrast"),
    "full_1994_2010", z$estimate, z$ci_low, z$ci_high, z$p_value,
    if (z$outcome == "patent_count") 5 * z$estimate else NA_real_,
    "stayer heterogeneity",
    "All eight predeclared contrasts are reported; population is post-treatment selected.",
    paths[["stayer_heterogeneity"]]
  )
}

selection <- read_csv(paths[["stayer_selection"]])
selection <- selection[
  selection$variable %in%
    c("patent_stock_5y", "active_years_5y", "career_age"), ,
  drop = FALSE
]
for (i in seq_len(nrow(selection))) {
  z <- selection[i, ]
  inventory[[length(inventory) + 1L]] <- record(
    "selection diagnostic", z$retention_status, z$variable,
    "pre-deal descriptive mean", "full_1994_2010", z$mean,
    reporting_tier = "stayer main",
    interpretation = "Descriptive evidence of post-treatment selection.",
    source_path = paths[["stayer_selection"]]
  )
}

gate <- read_csv(paths[["dealsim_gate"]])
inventory[[length(inventory) + 1L]] <- record(
  "feasibility", "DealSim-eligible deals", "DealSim inverted-U",
  "prospective power gate", "common-cohort terciles",
  estimate = gate$minimum_tercile_effective_deals[1],
  reporting_tier = "appendix",
  interpretation = gate$path_description[1],
  source_path = paths[["dealsim_gate"]],
  status = "failed_gate",
  governing_inference = "not_estimated",
  selection_basis = "prospective power gate",
  main_text_eligible = FALSE
)

endpoint_diag <- read_csv(paths[["control_endpoint_comparison"]])
endpoint_diag <- endpoint_diag[
  endpoint_diag$role == "diagnostic", , drop = FALSE
]
if (nrow(endpoint_diag) != 1L) {
  stop("Expected one full-cohort control-endpoint diagnostic row")
}
z <- endpoint_diag[1, ]
inventory[[length(inventory) + 1L]] <- record(
  "sample-definition diagnostic", "full target-inventor cohort",
  "patent_count",
  "P5c controls restricted to focal-group patent activity through +5",
  "full_1994_2010", z$estimate, z$ci_low, z$ci_high, z$p_value,
  5 * z$estimate, "diagnostic",
  paste(
    "Post-window control-support diagnostic. The estimate becomes less",
    "negative, so the endpoint filter explains none of the retained/full",
    "cohort point-estimate gap."
  ),
  paths[["control_endpoint_comparison"]],
  status = "companion",
  governing_inference = z$inference,
  selection_basis = "predetermined treated cohort; post-window-filtered controls",
  main_text_eligible = FALSE,
  pretrend_qualification = paste(
    "No genuine LOYO has been run for this restricted-control diagnostic.",
    "Negative-period differences are residual imbalances after filtering",
    "controls while reusing the frozen P5c weights, not held-out gaps."
  ),
  gap_type = "residual_imbalance_after_control_filter"
)

timing_path <- read_csv(paths[["control_endpoint_dynamic_comparison"]])
timing_zero <- timing_path[timing_path$event_time == 0L, , drop = FALSE]
if (nrow(timing_zero) != 1L) {
  stop("Expected one completion-year dynamic-comparison row")
}
z <- timing_zero[1, ]
frozen_t0_p <- 2 * stats::pt(
  -abs(z$frozen_estimate / z$frozen_se), df = z$frozen_df
)
diagnostic_t0_p <- 2 * stats::pt(
  -abs(z$diagnostic_estimate / z$diagnostic_se),
  df = z$diagnostic_df
)
completion_results <- read_csv(paths[["completion_year_results"]])
completion_results <- completion_results[
  completion_results$sample == "full_1994_2010" &
    completion_results$outcome == "patent_count" &
    tolower(as.character(completion_results$governing)) == "true", ,
  drop = FALSE
]
completion_average <- completion_results[
  completion_results$summary == "average_annual_t0_to_t5", ,
  drop = FALSE
]
completion_cumulative <- completion_results[
  completion_results$summary == "cumulative_t0_to_t5", ,
  drop = FALSE
]
if (nrow(completion_average) != 1L ||
    nrow(completion_cumulative) != 1L) {
  stop("Expected governing completion-year average and cumulative rows")
}
inventory[[length(inventory) + 1L]] <- record(
  "timing", "full target-inventor cohort", "patent_count",
  "completion-year ATT (partially exposed calendar year)",
  "full_1994_2010", z$frozen_estimate, z$frozen_ci_low,
  z$frozen_ci_high, frozen_t0_p, NA_real_, "secondary",
  paste(
    "Merger-completion-year effect. It is included in the event-study",
    "interpretation, while the +1 to +5 average remains the comparable",
    "full-calendar-year flow estimand."
  ),
  paths[["control_endpoint_dynamic_comparison"]],
  status = "companion",
  governing_inference = "two_way_deal_inventor",
  selection_basis = "predetermined treated cohort",
  main_text_eligible = TRUE,
  pretrend_qualification =
    "Interpret with the certified full-cohort LOYO diagnostics."
)
inventory[[length(inventory) + 1L]] <- record(
  "timing", "full target-inventor cohort", "patent_count",
  "completion-through-plus-five average annual ATT",
  "full_1994_2010",
  completion_average$estimate, completion_average$ci_low,
  completion_average$ci_high, completion_average$p_value,
  NA_real_,
  reporting_tier = "secondary",
  interpretation = paste(
    "Average of the partially exposed completion year and five subsequent",
    "fully exposed calendar years."
  ),
  source_path = paths[["completion_year_results"]],
  status = "companion",
  governing_inference = completion_average$inference,
  selection_basis = "predetermined treated cohort",
  main_text_eligible = TRUE,
  pretrend_qualification =
    "Interpret with the certified full-cohort LOYO diagnostics."
)
inventory[[length(inventory) + 1L]] <- record(
  "timing", "full target-inventor cohort", "patent_count",
  "completion-through-plus-five cumulative effect",
  "full_1994_2010",
  completion_cumulative$estimate, completion_cumulative$ci_low,
  completion_cumulative$ci_high, completion_cumulative$p_value,
  NA_real_,
  reporting_tier = "secondary",
  interpretation = paste(
    "Sum of the partially exposed completion-year effect and the five",
    "subsequent annual effects."
  ),
  source_path = paths[["completion_year_results"]],
  status = "companion",
  governing_inference = completion_cumulative$inference,
  selection_basis = "predetermined treated cohort",
  main_text_eligible = TRUE,
  pretrend_qualification =
    "Interpret with the certified full-cohort LOYO diagnostics."
)
inventory[[length(inventory) + 1L]] <- record(
  "timing diagnostic", "full target-inventor cohort", "patent_count",
  "endpoint-restricted completion-year ATT",
  "full_1994_2010", z$diagnostic_estimate, z$diagnostic_ci_low,
  z$diagnostic_ci_high, diagnostic_t0_p, NA_real_, "diagnostic",
  paste(
    "Completion-year effect under the endpoint-restricted control sample;",
    "supporting diagnostic only because frozen weights were reused."
  ),
  paths[["control_endpoint_dynamic_comparison"]],
  status = "companion",
  governing_inference = "two_way_deal_inventor",
  selection_basis = "predetermined treated cohort; post-window-filtered controls",
  main_text_eligible = FALSE,
  pretrend_qualification = paste(
    "No genuine LOYO has been run for this restricted-control diagnostic.",
    "Negative-period differences are residual imbalances, not held-out gaps."
  ),
  gap_type = "residual_imbalance_after_control_filter"
)

placebo <- read_csv(paths[["placebo_summary"]])
if (nrow(placebo) != 1L || placebo$draws[[1]] != 2000L) {
  stop("The required 2,000-draw placebo summary is absent")
}
inventory[[length(inventory) + 1L]] <- record(
  "falsification", "untreated-firm pseudo events", "patent_count",
  "2,000-draw mean placebo ATT", "1994_2010",
  estimate = placebo$mean_placebo_att[[1]],
  reporting_tier = "appendix",
  interpretation = paste(
    "Simple symmetric recruitment/event-time falsification;",
    "not a validation of P5c matching."
  ),
  source_path = paths[["placebo_summary"]],
  status = "appendix",
  governing_inference = "Monte Carlo distribution",
  selection_basis = "untreated-firm pseudo events",
  main_text_eligible = FALSE
)
inventory[[length(inventory) + 1L]] <- record(
  "falsification", "untreated-firm pseudo events", "rejection_share_5pct",
  "2,000-draw calibrated rejection share", "1994_2010",
  estimate = placebo$cohort_wild_rejection_share_5pct[[1]],
  reporting_tier = "appendix",
  interpretation = "Empirical false-positive rate under cohort-wild inference.",
  source_path = paths[["placebo_summary"]],
  status = "appendix",
  governing_inference = "cohort_wild_bootstrap_t_webb",
  selection_basis = "untreated-firm pseudo events",
  main_text_eligible = FALSE
)
inventory[[length(inventory) + 1L]] <- record(
  "falsification", "untreated-firm pseudo events",
  "reference_left_tail_probability",
  "share of placebo ATTs at or below frozen P5c ATT", "1994_2010",
  estimate = placebo$descriptive_left_tail_plus_one[[1]],
  reporting_tier = "appendix",
  interpretation = "Descriptive plus-one Monte Carlo tail probability.",
  source_path = paths[["placebo_summary"]],
  status = "appendix",
  governing_inference = "Monte Carlo plus-one tail",
  selection_basis = "untreated-firm pseudo events",
  main_text_eligible = FALSE
)

landmark <- read_csv(paths[["landmark_status"]])
if (nrow(landmark) != 1L || landmark$estimated[[1]]) {
  stop("The retained-landmark package must remain omitted after its failed gate")
}
inventory[[length(inventory) + 1L]] <- record(
  "failed design", "initially retained at +1",
  "patent_count_t2_to_t5",
  "landmark survivor-population ATT", "full_1994_2010",
  reporting_tier = "appendix",
  interpretation = "Not estimated because prespecified retention, balance, and ESS gates failed.",
  source_path = paths[["landmark_status"]],
  status = "failed_gate",
  governing_inference = "not_estimated",
  selection_basis = "proposed +1 landmark survivor population",
  main_text_eligible = FALSE
)

inventory <- do.call(rbind, inventory)

default_status <- c(
  main = "primary",
  secondary = "companion",
  `main heterogeneity` = "primary",
  robustness = "companion",
  `main decomposition` = "descriptive",
  `stayer main` = "companion",
  `stayer secondary` = "companion",
  `stayer decomposition` = "descriptive",
  `stayer heterogeneity` = "appendix",
  diagnostic = "companion",
  appendix = "appendix"
)
missing_status <- is.na(inventory$status) | !nzchar(inventory$status)
inventory$status[missing_status] <- unname(default_status[
  inventory$reporting_tier[missing_status]
])
inventory$status[is.na(inventory$status)] <- "appendix"

missing_inference <- is.na(inventory$governing_inference) |
  !nzchar(inventory$governing_inference)
inventory$governing_inference[missing_inference] <- "source_selected"

missing_selection <- is.na(inventory$selection_basis) |
  !nzchar(inventory$selection_basis)
selection_default <- ifelse(
  grepl("initially retained", inventory$population, fixed = TRUE),
  "post-treatment initially patent-retained",
  "predetermined or descriptive source population"
)
inventory$selection_basis[missing_selection] <-
  selection_default[missing_selection]

missing_eligibility <- is.na(inventory$main_text_eligible)
inventory$main_text_eligible[missing_eligibility] <-
  inventory$reporting_tier[missing_eligibility] %in% c(
    "main", "secondary", "main heterogeneity", "main decomposition",
    "stayer main", "stayer secondary", "stayer decomposition"
  )

missing_pretrend <- is.na(inventory$pretrend_qualification) |
  !nzchar(inventory$pretrend_qualification)
pretrend_default <- ifelse(
  inventory$population == "initially retained inventors",
  "Selected retained comparison has material held-out LOYO gaps; full-window sign-breakdown ratio 0.946.",
  ifelse(
    inventory$population == "full target-inventor cohort",
    "Interpret with the certified outcome-specific pretrend and LOYO diagnostics.",
    "Not applicable or reported in the source package."
  )
)
inventory$pretrend_qualification[missing_pretrend] <-
  pretrend_default[missing_pretrend]

valid_gap_types <- c(
  "not_applicable",
  "genuine_LOYO_held_out_gap",
  "residual_imbalance_after_control_filter"
)
if (any(!inventory$gap_type %in% valid_gap_types)) {
  stop(
    "Unexpected gap_type value(s): ",
    paste(
      unique(inventory$gap_type[!inventory$gap_type %in% valid_gap_types]),
      collapse = ", "
    )
  )
}

slug <- function(x) {
  x <- tolower(gsub("[^A-Za-z0-9]+", "_", x))
  gsub("^_+|_+$", "", x)
}
inventory$result_id <- vapply(seq_len(nrow(inventory)), function(i) {
  paste(
    slug(inventory$domain[[i]]),
    slug(inventory$population[[i]]),
    slug(inventory$outcome[[i]]),
    slug(inventory$analysis[[i]]),
    slug(inventory$sample[[i]]),
    sep = "__"
  )
}, character(1))
if (anyDuplicated(inventory$result_id)) {
  stop("Generated result_id is not unique")
}

inventory <- inventory[order(
  factor(inventory$reporting_tier, levels = c(
    "main", "secondary", "main heterogeneity", "main decomposition",
    "robustness", "stayer main", "stayer secondary",
    "stayer decomposition", "diagnostic", "stayer heterogeneity",
    "appendix"
  )),
  inventory$domain, inventory$outcome
), ]
row.names(inventory) <- NULL

inventory_path <- file.path(out_dir, "master_results_inventory.csv")
utils::write.csv(inventory, inventory_path, row.names = FALSE, na = "")

fmt <- function(x) {
  ifelse(is.na(x), "", formatC(x, digits = 4, format = "f"))
}
note <- c(
  "# Local Match v2 master results inventory",
  "",
  paste(
    "This is the human-readable index of the certified thesis results.",
    "The CSV in `CURRENT_LOCAL_MATCH_V2/results_inventory` is authoritative."
  ),
  "",
  "| Status | Tier | Population | Outcome / analysis | Estimate | 95% CI | p |",
  "|---|---|---|---|---:|---:|---:|"
)
for (i in seq_len(nrow(inventory))) {
  z <- inventory[i, ]
  ci <- if (is.na(z$ci_low) || is.na(z$ci_high)) {
    ""
  } else {
    sprintf("[%s, %s]", fmt(z$ci_low), fmt(z$ci_high))
  }
  note <- c(note, sprintf(
    "| %s | %s | %s | %s: %s | %s | %s | %s |",
    z$status, z$reporting_tier, z$population, z$outcome, z$analysis,
    fmt(z$estimate), ci, fmt(z$p_value)
  ))
}
writeLines(note, note_path, useBytes = TRUE)

cert_paths <- paths[c(
  "p6_cert", "vr_cert", "s3_cert", "s4_cert", "s5_cert",
  "stayer_secondary_cert", "stayer_het_cert", "dealsim_cert",
  "p8_cert", "recurrent_cert", "control_endpoint_cert",
  "completion_year_cert"
)]
s3_manifest <- read_csv(paths[["s3_manifest"]])
s3_weight_row <- s3_manifest[
  s3_manifest$artifact == basename(paths[["s3_weights"]]), ,
  drop = FALSE
]
analysis_sources <- list.files(
  file.path(root, "02_analysis", "R"),
  pattern = "\\.R$", full.names = TRUE
)
analysis_sources <- analysis_sources[
  basename(analysis_sources) !=
    "34_build_lmv2_master_results_inventory.R"
]
private_worktree_pattern <- "081f|\\.codex[/\\\\]worktrees"
private_worktree_hits <- vapply(analysis_sources, function(path) {
  any(grepl(
    private_worktree_pattern,
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    perl = TRUE
  ))
}, logical(1))
checks <- data.frame(
  check = c(
    "all_source_certifications_pass",
    "local_stayer_handoff_is_complete",
    "s3_weight_hash_matches_certified_manifest",
    "active_code_has_no_private_worktree_dependency",
    "one_full_cohort_main_quantity_row",
    "all_full_cohort_heterogeneity_rows_present",
    "all_stayer_heterogeneity_rows_present",
    "p8_headline_decomposition_is_complete",
    "p8_retained_shares_are_authoritative",
    "old_retained_decomposition_not_in_inventory",
    "control_endpoint_diagnostic_is_recorded",
    "control_endpoint_gap_is_not_mislabeled_as_LOYO",
    "retained_sign_ratios_use_genuine_LOYO_gap_type",
    "completion_year_effect_is_recorded",
    "completion_inclusive_average_is_recorded",
    "completion_inclusive_cumulative_effect_is_recorded",
    "placebo_2000draw_is_recorded",
    "failed_landmark_is_recorded",
    "dealsim_gate_is_recorded",
    "inventory_has_no_missing_source_paths",
    "inventory_result_ids_are_unique",
    "inventory_status_values_are_valid"
  ),
  pass = c(
    all(vapply(cert_paths, cert_passes, logical(1))),
    all(file.exists(paths[c(
      "s3_weights", "s3_manifest", "s3_cert", "s4_cert",
      "stayer_aggregate", "p8_components", "stayer_secondary"
    )])),
    nrow(s3_weight_row) == 1L &&
      identical(
        digest::digest(
          file = paths[["s3_weights"]], algo = "sha256"
        ),
        s3_weight_row$sha256
      ),
    !any(private_worktree_hits),
    sum(
      inventory$reporting_tier == "main" &
        inventory$outcome == "patent_count"
    ) == 1L,
    sum(inventory$reporting_tier == "main heterogeneity") == 8L,
    sum(inventory$reporting_tier == "stayer heterogeneity") == 8L,
    sum(
      inventory$domain == "P8 decomposition" &
        inventory$sample == "headline_1994_2010" &
        inventory$population %in% c(
          "full target-inventor cohort", "initially retained inventors"
        )
    ) == 8L,
    {
      retained_p8 <- p8[p8$population == "initially_retained_broad", ]
      all(abs(
        retained_p8$share_of_total[
          match(
            c("cessation", "active_given_survival",
              "patents_per_active_year"),
            retained_p8$component
          )
        ] - c(
          0.273323384275009,
          0.0535427893842086,
          0.673133826340781
        )
      ) < 1e-12)
    },
    !any(grepl(
      "table_stayer_margin_decomposition.csv",
      inventory$source_path, fixed = TRUE
    )),
    sum(inventory$domain == "sample-definition diagnostic") == 1L,
    sum(
      inventory$domain == "sample-definition diagnostic" &
        inventory$gap_type ==
          "residual_imbalance_after_control_filter" &
        grepl(
          "No genuine LOYO", inventory$pretrend_qualification,
          fixed = TRUE
        )
    ) == 1L,
    all(
      inventory$gap_type[
        inventory$domain == "sign-stability diagnostic"
      ] == "genuine_LOYO_held_out_gap"
    ),
    sum(
      inventory$domain == "timing" &
        inventory$analysis ==
          "completion-year ATT (partially exposed calendar year)" &
        abs(inventory$estimate - (-0.0376802374262842)) < 1e-12
    ) == 1L,
    sum(
      inventory$domain == "timing" &
        inventory$analysis ==
          "completion-through-plus-five average annual ATT" &
        abs(inventory$estimate - (-0.0507837513794978)) < 1e-12 &
        inventory$ci_high < 0
    ) == 1L,
    sum(
      inventory$domain == "timing" &
        inventory$analysis ==
          "completion-through-plus-five cumulative effect" &
        abs(inventory$estimate - (-0.304702508276995)) < 1e-12
        & inventory$ci_high < 0
    ) == 1L,
    sum(
      inventory$population == "untreated-firm pseudo events" &
        inventory$analysis == "2,000-draw mean placebo ATT"
    ) == 1L,
    sum(inventory$status == "failed_gate" &
          inventory$population == "initially retained at +1") == 1L,
    sum(inventory$domain == "feasibility") == 1L,
    all(file.exists(inventory$source_path)),
    !anyDuplicated(inventory$result_id),
    all(inventory$status %in% c(
      "primary", "companion", "appendix", "descriptive",
      "failed_gate", "superseded", "not_run"
    ))
  ),
  stringsAsFactors = FALSE
)
if (!all(checks$pass)) {
  stop(
    "Inventory certification failed: ",
    paste(checks$check[!checks$pass], collapse = ", ")
  )
}
utils::write.csv(
  checks,
  file.path(out_dir, "master_results_inventory_certification.csv"),
  row.names = FALSE
)
source_manifest <- data.frame(
  source = normalizePath(paths, winslash = "/", mustWork = TRUE),
  sha256 = vapply(
    paths, digest::digest, character(1), file = TRUE, algo = "sha256"
  ),
  bytes = unname(file.info(paths)$size),
  stringsAsFactors = FALSE
)
utils::write.csv(
  source_manifest, file.path(out_dir, "source_manifest.csv"),
  row.names = FALSE
)

message("Master results inventory written to: ", out_dir)
