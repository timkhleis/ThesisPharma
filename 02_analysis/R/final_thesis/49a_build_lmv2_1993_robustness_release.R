#!/usr/bin/env Rscript

# Consolidate the certified 1993--2010 robustness exercise. Reporting uses
# ordinary (unadjusted) p-values throughout; multiplicity-adjusted values are
# not imported into this release.

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
AUDIT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
ROBUST <- file.path(AUDIT, "ROBUSTNESS_RELEASE_1993")
OUT <- file.path(ROBUST, "FINAL_RELEASE")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

read_csv <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) stop("Missing release input: ", path)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
one <- function(x, where, label) {
  z <- x[where, , drop = FALSE]
  if (nrow(z) != 1L) stop("Expected one row for ", label, "; found ", nrow(z))
  z
}
num <- function(x) if (length(x)) as.numeric(x[[1L]]) else NA_real_
chr <- function(x) if (length(x)) as.character(x[[1L]]) else NA_character_

rows <- list()
add <- function(
    check, estimate = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
    p_value = NA_real_, scale = "annual patents per inventor",
    status = "estimated", interpretation = "", source) {
  rows[[length(rows) + 1L]] <<- data.frame(
    check = check, estimate = estimate, ci_low = ci_low, ci_high = ci_high,
    p_value = p_value, p_value_type = if (is.finite(p_value)) {
      "ordinary_unadjusted"
    } else {
      "not_applicable"
    },
    scale = scale, status = status, interpretation = interpretation,
    source = source, stringsAsFactors = FALSE
  )
}

weight_path <- file.path(
  ROBUST, "WEIGHT_ROBUSTNESS_P5C", "weight_robustness_headline.csv"
)
weight <- read_csv(weight_path)
governing_weight <- weight$inference == "deal_wild_bootstrap_t" &
  weight$summary == "average_annual_t1_to_t5"
weight <- weight[governing_weight, , drop = FALSE]
add_weight <- function(spec, label, interpretation) {
  z <- one(weight, weight$specification == spec, label)
  add(
    label, num(z$estimate), num(z$ci_low), num(z$ci_high), num(z$p_value),
    interpretation = interpretation, source = weight_path
  )
}
add_weight(
  "headline_all18", "Headline inventor-weighted estimate",
  "Primary amended 1993--2010 estimand."
)
add_weight(
  "equal_deal_same16", "Equal-deal weighting",
  paste(
    "No detectable effect for the equally weighted acquisition estimand;",
    "this solve excludes cohorts 2000 and 2005."
  )
)
add_weight(
  "headline_same16", "Inventor weighting on equal-deal cohort set",
  paste(
    "Same 16 cohorts as the equal-deal estimate, so the aggregation",
    "comparison is not confounded by cohort coverage."
  )
)
add_weight(
  "no_deal70", "Exclude deal 70 and re-solve",
  "Deal 70 does not drive the inventor-weighted result."
)
add_weight(
  "omit_henkel", "Exclude Henkel and re-solve",
  "Henkel does not drive the inventor-weighted result."
)

size_dir <- file.path(ROBUST, "DEAL_VALUE_SIZE_SPLIT")
size_design_dir <- file.path(size_dir, "DESIGN_V2")
size_estimation_dir <- file.path(size_dir, "ESTIMATION_PRIMARY_V3")
size_sensitivity_dir <- file.path(size_dir, "ESTIMATION_REBALANCED")
size_headline_path <- file.path(
  size_estimation_dir, "deal_value_size_headline.csv")
size_difference_path <- file.path(
  size_estimation_dir, "deal_value_size_formal_difference.csv")
size_manifest_path <- file.path(
  size_estimation_dir, "deal_value_size_estimation_manifest.csv")
size_counts_path <- file.path(
  size_estimation_dir, "deal_value_size_primary_counts.csv")
size_identity_path <- file.path(
  size_estimation_dir, "deal_value_size_filtered_identity_check.csv")
size_sensitivity_difference_path <- file.path(
  size_sensitivity_dir, "deal_value_size_formal_difference.csv")
size_headline <- read_csv(size_headline_path)
size_difference <- read_csv(size_difference_path)
size_manifest <- read_csv(size_manifest_path)
size_counts <- read_csv(size_counts_path)
size_identity <- read_csv(size_identity_path)
size_sensitivity_difference <- read_csv(size_sensitivity_difference_path)
if (!isTRUE(size_manifest$main_text_eligible[[1]]) ||
    !identical(size_manifest$placement[[1]], "main_table_and_appendix")) {
  stop("Deal-value size split is not eligible for the Influence and aggregation panel")
}
size_governing <- size_headline[
  size_headline$summary == "average_annual_t1_to_t5" &
    size_headline$governing, , drop = FALSE]
size_count <- function(group, field) {
  row <- size_counts$size_group == group
  as.integer(size_counts[[field]][row])
}
add_size <- function(spec, label, group = NA_character_) {
  z <- one(size_governing, size_governing$specification == spec, label)
  detail <- if (is.na(group)) {
    paste0(
      "Pooled inventor-weighted anchor on the 16 common financial-size cohorts (",
      sum(size_counts$acquisitions),
      " acquisitions; ",
      sum(size_counts$supported_treated_inventors),
      " supported treated inventors)."
    )
  } else {
    paste0(
      if (group == "small") "Target value at or below EUR 5 billion" else
        "Target value above EUR 5 billion",
      "; ", size_count(group, "acquisitions"),
      " acquisitions and ", size_count(group, "supported_treated_inventors"),
      " treated inventors."
    )
  }
  add(
    label, num(z$estimate), num(z$ci_low), num(z$ci_high), num(z$p_value),
    interpretation = detail, source = size_headline_path
  )
}
add_size(
  "pooled_common_cohorts", "Deal-value split: pooled common-cohort anchor")
add_size("deal_value_size_small", "Deal value at or below EUR 5 billion", "small")
add_size("deal_value_size_large", "Deal value above EUR 5 billion", "large")
size_diff <- one(
  size_difference, size_difference$governing, "deal-value direct difference")
add(
  "Deal-value split: above minus at/below EUR 5 billion", num(size_diff$estimate),
  num(size_diff$ci_low), num(size_diff$ci_high), num(size_diff$p_value),
  interpretation = paste(
    "Formal direct comparison on 16 common cohorts. The subgroup estimates",
    "are not statistically distinguishable."
  ), source = size_difference_path
)
size_sensitivity_diff <- one(
  size_sensitivity_difference, size_sensitivity_difference$governing,
  "rebalanced deal-value difference")
add(
  "Deal-value split: rebalanced subset difference",
  num(size_sensitivity_diff$estimate), num(size_sensitivity_diff$ci_low),
  num(size_sensitivity_diff$ci_high), num(size_sensitivity_diff$p_value),
  status = "appendix_sensitivity",
  interpretation = paste(
    "Stage-2 weights are re-solved within value cells; only nine cohorts and",
    "24 above-threshold acquisitions remain."
  ), source = size_sensitivity_difference_path
)

quantile_dir <- file.path(
  ROBUST, "DEAL_VALUE_QUANTILES", "ESTIMATION_V2"
)
quantile_att_path <- file.path(quantile_dir, "deal_value_quantile_att.csv")
quantile_counts_path <- file.path(
  quantile_dir, "deal_value_quantile_estimation_counts.csv")
quantile_omnibus_path <- file.path(
  quantile_dir, "deal_value_quantile_omnibus.csv")
quantile_extreme_path <- file.path(
  quantile_dir, "deal_value_quantile_extreme_contrasts.csv")
quantile_identity_path <- file.path(
  quantile_dir, "deal_value_quantile_pooled_identity.csv")
quantile_certification_path <- file.path(
  quantile_dir, "deal_value_quantile_certification.csv")
quantile_manifest_path <- file.path(
  quantile_dir, "deal_value_quantile_estimation_manifest.csv")
quantile_att <- read_csv(quantile_att_path)
quantile_counts <- read_csv(quantile_counts_path)
quantile_omnibus <- read_csv(quantile_omnibus_path)
quantile_extreme <- read_csv(quantile_extreme_path)
quantile_identity <- read_csv(quantile_identity_path)
quantile_certification <- read_csv(quantile_certification_path)
quantile_manifest <- read_csv(quantile_manifest_path)

quartile_att <- quantile_att[quantile_att$partition == "quartile", ]
quartile_counts <- quantile_counts[quantile_counts$partition == "quartile", ]
for (label in paste0("Q", 1:4)) {
  z <- one(quartile_att, quartile_att$bin == label, paste("deal-value", label))
  count <- one(
    quartile_counts, quartile_counts$bin == label, paste("deal-value count", label))
  add(
    paste("Deal-value quartile", label), num(z$estimate), num(z$ci_low),
    num(z$ci_high), num(z$governing_p), status = "appendix_exploratory",
    interpretation = paste0(
      count$acquisitions[[1]], " acquisitions and ",
      count$treated_inventors[[1]], " treated inventors."
    ), source = quantile_att_path
  )
}
quantile_extreme_q <- one(
  quantile_extreme, quantile_extreme$partition == "quartile",
  "deal-value Q4-minus-Q1 contrast")
add(
  "Deal-value quartiles: Q4 minus Q1", num(quantile_extreme_q$estimate),
  num(quantile_extreme_q$ci_low), num(quantile_extreme_q$ci_high),
  num(quantile_extreme_q$governing_p), status = "appendix_exploratory",
  interpretation = "Formal top-minus-bottom quartile comparison.",
  source = quantile_extreme_path
)
quantile_omnibus_q <- one(
  quantile_omnibus, quantile_omnibus$partition == "quartile",
  "deal-value quartile omnibus")
add(
  "Deal-value quartiles: joint equality test", p_value =
    num(quantile_omnibus_q$governing_p), status = "appendix_exploratory",
  interpretation = "Three-restriction test that all four quartile ATTs are equal.",
  source = quantile_omnibus_path
)

quantile_release <- quantile_att[c(
  "partition", "bin", "estimate", "ci_low", "ci_high", "governing_p")]
names(quantile_release)[names(quantile_release) == "governing_p"] <-
  "ordinary_p_value"
quantile_release$p_value_type <- "ordinary_unadjusted"
utils::write.csv(
  quantile_release,
  file.path(OUT, "deal_value_quantile_profile_ordinary_p.csv"),
  row.names = FALSE
)

donor <- weight[grepl("^omit_firm_", weight$specification), , drop = FALSE]
if (nrow(donor) != 8L) stop("Expected eight feasible donor-firm omissions")
add(
  "Eight feasible donor-firm omissions",
  min(donor$estimate), min(donor$estimate), max(donor$estimate),
  max(donor$p_value), status = "range",
  interpretation = paste0(
    "Estimate range; p_value records the largest ordinary p-value across ",
    "the eight feasible omissions."
  ), source = weight_path
)

cbps_path <- file.path(ROBUST, "CBPS", "cbps_headline.csv")
cbps <- read_csv(cbps_path)
cbps <- one(
  cbps,
  cbps$inference == "deal_wild_bootstrap_t" &
    cbps$summary == "average_annual_t1_to_t5",
  "CBPS"
)
add(
  "CBPS reweighting", num(cbps$estimate), num(cbps$ci_low),
  num(cbps$ci_high), num(cbps$p_value),
  interpretation = "Numerically identical to the entropy-balancing headline.",
  source = cbps_path
)

transform_path <- file.path(
  ROBUST, "TRANSFORMED_OUTCOMES_P5C", "transformed_outcome_headline.csv"
)
transform <- read_csv(transform_path)
for (outcome in c("fractional_patent_count", "log1p_patent_count")) {
  z <- one(
    transform,
    transform$outcome == outcome &
      transform$inference == "deal_wild_bootstrap_t" &
      transform$summary == "average_annual_t1_to_t5",
    outcome
  )
  add(
    if (outcome == "fractional_patent_count") {
      "Fractional patent counts"
    } else {
      "log(1+patents)"
    },
    num(z$estimate), num(z$ci_low), num(z$ci_high), num(z$p_value),
    scale = outcome,
    interpretation = if (outcome == "fractional_patent_count") {
      "Not mechanically driven by inventor-team size."
    } else {
      "Robust to right-tail compression while retaining zeros."
    },
    source = transform_path
  )
}

ppml_path <- file.path(ROBUST, "PPML_P5C", "ppml_post_effect.csv")
ppml <- read_csv(ppml_path)
ppml <- one(ppml, ppml$outcome == "patent_count", "PPML")
add(
  "PPML count model", num(ppml$percent_effect),
  num(ppml$ci_low_percent), num(ppml$ci_high_percent), num(ppml$p_value),
  scale = "percent", interpretation = "Count-data functional-form check.",
  source = ppml_path
)

for (spec in c("P6_VERGINER_EARLY_RECRUITMENT",
               "P6_VERGINER_EARLY_RECRUITMENT_STRICT_FEASIBLE")) {
  path <- file.path(ROBUST, spec, "verginer_p6_headline.csv")
  z <- read_csv(path)
  z <- one(
    z,
    z$inference == "deal_wild_bootstrap_t" &
      z$summary == "average_annual_t1_to_t5",
    spec
  )
  add(
    if (grepl("STRICT", spec)) {
      "Established inventors, firm-balanced"
    } else {
      "Established inventors, inventor-balanced"
    },
    num(z$estimate), num(z$ci_low), num(z$ci_high), num(z$p_value),
    interpretation = paste(
      "Mechanically begins in 1995 because the established-inventor design",
      "requires g-7/g-6 history."
    ), source = path
  )
}

lodo_path <- file.path(
  ROBUST, "FROZEN_WEIGHT_LODO_P5C", "frozen_weight_lodo_summary.csv"
)
lodo <- read_csv(lodo_path)
add(
  "Frozen-weight leave-one-deal-out", num(lodo$headline),
  num(lodo$minimum_lodo), num(lodo$maximum_lodo),
  status = "range", interpretation = paste0(
    lodo$n_feasible_deletions, " feasible deletions; all estimates retain ",
    "the headline sign and lie inside its 95% interval."
  ), source = lodo_path
)

sign_path <- file.path(
  ROBUST, "DEAL_SIGNFLIP_P5C", "deal_signflip_result.csv"
)
sign <- read_csv(sign_path)
add(
  "Deal-stack sign-flip diagnostic", num(sign$observed),
  p_value = num(sign$two_sided_p_value),
  interpretation = chr(sign$interpretation), source = sign_path
)

loyo_path <- file.path(
  ROBUST, "P6_PACKAGE1_LOYO_GRID", "package1_loyo_post_stability.csv"
)
loyo <- read_csv(loyo_path)
loyo <- loyo[loyo$design != "count_active", , drop = FALSE]
add(
  "Hold out t=-5,...,-2", mean(loyo$estimate),
  min(loyo$estimate), max(loyo$estimate), max(loyo$p_value),
  status = "range", interpretation = paste0(
    "Estimate range; p_value records the largest ordinary p-value. ",
    "Held-out t=-3 and t=-2 levels are nonzero, so timing remains a caveat."
  ), source = loyo_path
)

m1_path <- file.path(
  ROBUST, "P6_PACKAGE1_ESTIMATION_LOYO_M1", "p6_headline_post_att.csv"
)
m1 <- read_csv(m1_path)
m1 <- one(
  m1,
  m1$outcome == "patent_count" &
    m1$inference == "deal_wild_bootstrap_t" &
    m1$summary == "average_annual_t1_to_t5",
  "loyo_m1"
)
add(
  "Hold out t=-1", num(m1$estimate), num(m1$ci_low),
  num(m1$ci_high), num(m1$p_value),
  interpretation = paste(
    "Timing/reference-period sensitivity; not part of the early-pre-period",
    "LOYO stability claim."
  ), source = m1_path
)

ipc_path <- file.path(
  ROBUST, "IPC_MAIN_GROUP_GATE", "ipc_main_group_feasibility_manifest.csv"
)
ipc <- read_csv(ipc_path)
add(
  "IPC main-group refinement", status = chr(ipc$status),
  interpretation = paste0(
    "No ATT authorized; retention was ", ipc$minimum_observed_retention,
    "--", ipc$maximum_observed_retention, " versus the 0.80 gate."
  ), source = ipc_path
)

ppscm_path <- file.path(
  ROBUST, "P6_PPSCM_V2_SYMMETRIC", "stage_d_validation",
  "validation_summary.csv"
)
ppscm <- read_csv(ppscm_path)
add(
  "PPSCM reweighting", status = chr(ppscm$status),
  interpretation = paste0(
    "No ATT authorized; validation RMSE=", signif(ppscm$primary_validation_rmse, 4),
    " versus uniform RMSE=", signif(ppscm$uniform_validation_rmse, 4), "."
  ), source = ppscm_path
)

uniform_path <- file.path(
  ROBUST, "P6_UNIFORM_TOP20_SYMMETRIC", "stage_c_control_null",
  "control_null_summary.csv"
)
uniform <- read_csv(uniform_path)
add(
  "Uniform-top-20 weighting", estimate = num(uniform$placebo_mean),
  ci_low = num(uniform$placebo_mean_ci_low),
  ci_high = num(uniform$placebo_mean_ci_high),
  scale = "control-null placebo mean",
  status = chr(uniform$status),
  interpretation = paste0(
    uniform$inference_comparable_draws, "/", uniform$completed_draws,
    " inference-comparable control-null draws; false-rejection share=",
    signif(uniform$false_rejection_share, 4), "."
  ), source = uniform_path
)

placebo_path <- file.path(
  ROBUST, "SIMPLE_CONTROL_PLACEBO_2000DRAW_DYNAMIC",
  "simple_control_placebo_summary.csv"
)
placebo <- read_csv(placebo_path)
add(
  "Untreated-firm placebo", num(placebo$mean_placebo_att),
  num(placebo$p025), num(placebo$p975),
  num(placebo$mean_placebo_p_value),
  scale = "mean across placebo draws",
  interpretation = paste0(
    placebo$draws, " draws; descriptive left-tail probability at or below ",
    "the certified ATT=", signif(placebo$descriptive_left_tail_probability, 4), "."
  ), source = placebo_path
)

results <- do.call(rbind, rows)
utils::write.csv(
  results, file.path(OUT, "robustness_results_ordinary_p.csv"), row.names = FALSE
)

vr_path <- file.path(AUDIT, "P7_VR_HETEROGENEITY", "vr_heterogeneity_results.csv")
vr <- read_csv(vr_path)
vr <- vr[
  vr$result_type == "focal_contrast" &
    vr$reporting_status == "included_primary_heterogeneity_table",
  c("moderator", "outcome", "estimate", "ci_low", "ci_high", "governing_p")
]
names(vr)[names(vr) == "governing_p"] <- "ordinary_p_value"
vr$population <- "full_cohort"
vr$p_value_type <- "ordinary_unadjusted"
stayer_het_path <- file.path(
  AUDIT, "P7_STAYER_HETEROGENEITY", "stayer_heterogeneity_results.csv"
)
stayer_het <- read_csv(stayer_het_path)
stayer_het <- stayer_het[
  stayer_het$result_type == "focal_contrast" &
    stayer_het$reporting_status == "included_primary_heterogeneity_table",
  c("moderator", "outcome", "estimate", "ci_low", "ci_high", "governing_p")
]
names(stayer_het)[names(stayer_het) == "governing_p"] <-
  "ordinary_p_value"
stayer_het$population <- "initially_retained"
stayer_het$p_value_type <- "ordinary_unadjusted"
het_release <- rbind(vr, stayer_het)
utils::write.csv(
  het_release,
  file.path(OUT, "heterogeneity_ordinary_p_values.csv"), row.names = FALSE
)

inventor_omnibus_path <- file.path(
  BASE, "output", "results", "local_match_v2_1993_amendment",
  "inventor_heterogeneity", "table_inventor_heterogeneity_omnibus.csv"
)
inventor_omnibus <- read_csv(inventor_omnibus_path)
inventor_omnibus <- inventor_omnibus[
  inventor_omnibus$sample == "full_1993_2010",
  c("moderator", "designation", "sample", "omnibus_governing_p",
    "support_balance_gate_pass", "main_text_status")
]
names(inventor_omnibus)[
  names(inventor_omnibus) == "omnibus_governing_p"
] <- "ordinary_p_value"
inventor_omnibus$p_value_type <- "ordinary_unadjusted"
utils::write.csv(
  inventor_omnibus,
  file.path(OUT, "inventor_omnibus_ordinary_p_values.csv"),
  row.names = FALSE
)

exit_path <- file.path(
  AUDIT, "P8_EXIT_DECOMPOSITION", "exit_decomposition_components.csv"
)
exit <- read_csv(exit_path)
exit <- exit[
  exit$population == "full_cohort" &
    exit$sample == "headline_1993_2010" &
    exit$component != "total",
  c("component", "estimate", "cumulative_post_window_patents", "share_of_total")
]
utils::write.csv(
  exit, file.path(OUT, "headline_margin_decomposition.csv"), row.names = FALSE
)

required <- c(
  weight_path, cbps_path, transform_path, ppml_path, lodo_path, sign_path,
  loyo_path, m1_path, ipc_path, ppscm_path, uniform_path, placebo_path,
  vr_path, stayer_het_path, inventor_omnibus_path, exit_path,
  size_headline_path, size_difference_path, size_manifest_path,
  size_counts_path, size_identity_path, size_sensitivity_difference_path,
  quantile_att_path, quantile_counts_path, quantile_omnibus_path,
  quantile_extreme_path, quantile_identity_path,
  quantile_certification_path, quantile_manifest_path
)
cert <- data.frame(
  check = c(
    "all_required_inputs_exist", "no_adjusted_p_values_in_release",
    "headline_is_1993_2010", "untreated_placebo_has_2000_draws",
    "untreated_placebo_has_both_plots", "loyo_m1_certified",
    "untreated_placebo_certified", "uniform_completed_499_draws",
    "uniform_failed_gate_without_real_post_att",
    "deal_value_size_estimation_certified",
    "deal_value_size_filtered_identity_passes",
    "deal_value_size_formal_difference_reported",
    "deal_value_quantile_estimation_certified",
    "deal_value_quantile_pooled_identity_passes",
    "deal_value_quantile_formal_tests_reported",
    "all_numeric_reported_p_values_are_valid"
  ),
  pass = c(
    all(file.exists(required)),
    !any(grepl("holm|adjust", names(results), ignore.case = TRUE)) &&
      !any(grepl("holm|adjust", names(het_release), ignore.case = TRUE)),
    abs(results$estimate[results$check == "Headline inventor-weighted estimate"] -
          (-0.0520603086129782)) < 1e-12,
    placebo$draws == 2000L,
    all(file.exists(file.path(
      dirname(placebo_path),
      c("simple_control_placebo_distribution.png",
        "simple_control_placebo_event_study.png")
    ))),
    all(read_csv(
      ROBUST, "P6_PACKAGE1_ESTIMATION_LOYO_M1",
      "p6_estimation_certification.csv"
    )$pass),
    all(read_csv(
      ROBUST, "SIMPLE_CONTROL_PLACEBO_2000DRAW_DYNAMIC",
      "simple_control_placebo_certification.csv"
    )$pass),
    uniform$completed_draws == 499L,
    identical(uniform$status, "CONTROL_NULL_FAILED") &&
      !isTRUE(uniform$real_post_outcomes_queried),
    all(read_csv(
      size_estimation_dir, "deal_value_size_estimation_certification.csv"
    )$pass) && isTRUE(size_manifest$all_panel_certification_pass[[1]]) &&
      isTRUE(size_manifest$joint_model_tooth_check_pass[[1]]),
    isTRUE(size_manifest$filtered_identity_pass[[1]]) &&
      isTRUE(size_identity$pass[[1]]) &&
      size_identity$absolute_difference[[1]] <= size_identity$tolerance[[1]],
    nrow(size_difference[size_difference$governing, , drop = FALSE]) == 1L &&
      abs(size_diff$estimate[[1]] - (-0.0149654064648304)) < 1e-10,
    all(quantile_certification$pass) &&
      isTRUE(quantile_manifest$all_certification_pass[[1]]) &&
      nrow(quantile_att) == 14L &&
      sum(quantile_counts$partition == "decile") == 10L &&
      sum(quantile_counts$partition == "quartile") == 4L,
    all(quantile_identity$pass) &&
      isTRUE(quantile_manifest$pooled_contribution_identity_pass[[1]]) &&
      max(abs(quantile_identity$pooled_att - (-0.0520603086129782))) < 1e-10,
    nrow(quantile_omnibus) == 2L && nrow(quantile_extreme) == 2L &&
      abs(quantile_omnibus_q$governing_p[[1]] - 0.5088) < 1e-10 &&
      abs(quantile_extreme_q$estimate[[1]] - (-0.0136348555616051)) < 1e-10,
    all(results$p_value[is.finite(results$p_value)] >= 0 &
          results$p_value[is.finite(results$p_value)] <= 1) &&
      all(quantile_release$ordinary_p_value >= 0 &
          quantile_release$ordinary_p_value <= 1)
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  cert, file.path(OUT, "robustness_release_certification.csv"), row.names = FALSE
)
if (!all(cert$pass)) {
  stop("Robustness release certification failed: ",
       paste(cert$check[!cert$pass], collapse = ", "))
}

fmt <- function(x, d = 4L) {
  if (!is.finite(x)) return("")
  formatC(x, digits = d, format = "f")
}
line <- function(z) {
  interval <- if (is.finite(z$ci_low) && is.finite(z$ci_high)) {
    paste0("[", fmt(z$ci_low), ", ", fmt(z$ci_high), "]")
  } else ""
  paste0(
    "| ", z$check, " | ", fmt(z$estimate), " | ", interval, " | ",
    " ", fmt(z$p_value), " | ", z$status, " |"
  )
}
md <- c(
  "# Local Match v2 robustness release: 1993--2010",
  "",
  paste(
    "All reported p-values are ordinary, unadjusted values. The",
    "1993--2010 cohort is the sole main sample."
  ),
  "",
  "| Check | Estimate | 95% CI or range | p | Status |",
  "|---|---:|---:|---:|---|",
  vapply(seq_len(nrow(results)), function(i) line(results[i, ]), character(1)),
  "",
  "The established-inventor designs still begin in 1995 because their",
  "g-7/g-6 history requirement mechanically excludes 1993--1994.",
  "",
  sprintf(
    paste0(
      "The full-cohort patent decline decomposes into %.1f%% cessation, ",
      "%.1f%% reduced active patenting conditional on survival, and %.1f%% ",
      "fewer patents per active year."
    ),
    100 * exit$share_of_total[exit$component == "cessation"],
    100 * exit$share_of_total[exit$component == "active_given_survival"],
    100 * exit$share_of_total[exit$component == "patents_per_active_year"]
  ),
  "",
  paste(
    "IPC refinement, PPSCM, and uniform-top-20 are governed by their frozen",
    "feasibility/comparability gates; a failed gate means no ATT is estimated."
  )
)
writeLines(md, file.path(OUT, "robustness_results_1993.md"), useBytes = TRUE)
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Package 'digest' is required for the release artifact manifest")
}
artifact_paths <- list.files(OUT, full.names = TRUE)
artifact_paths <- artifact_paths[
  basename(artifact_paths) != "robustness_release_artifact_manifest.csv"
]
artifact_manifest <- data.frame(
  artifact = basename(artifact_paths),
  bytes = file.info(artifact_paths)$size,
  sha256 = vapply(
    artifact_paths, digest::digest, character(1), file = TRUE, algo = "sha256"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  artifact_manifest,
  file.path(OUT, "robustness_release_artifact_manifest.csv"),
  row.names = FALSE
)
message("Certified robustness release written to: ", OUT)
