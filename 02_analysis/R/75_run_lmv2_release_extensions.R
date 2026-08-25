#!/usr/bin/env Rscript

# Standard-path orchestrator for the final robustness extensions. It starts
# from the completed 1993 P5c/P6 artifacts and writes only new, versioned
# extension directories. Frozen builders intentionally refuse non-empty output
# directories, so this runner is for a fresh extension build.

options(stringsAsFactors = FALSE)
args <- commandArgs(trailingOnly = TRUE)
arg <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  if (length(hit) != 1L) stop("Duplicate argument: ", flag)
  sub(paste0("^", flag, "="), "", hit)
}
bootstrap_reps <- as.integer(arg("--bootstrap-reps", "9999"))
if (!is.finite(bootstrap_reps) || bootstrap_reps < 199L) {
  stop("--bootstrap-reps must be at least 199")
}

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
base <- file.path(root, "02_analysis")
r_dir <- file.path(base, "R")
audit <- file.path(
  base, "output", "audit", "local_match_v2_1993_amendment"
)
robust <- file.path(audit, "ROBUSTNESS_RELEASE_1993")
weights <- file.path(
  audit, "P5C_ANNUAL_TRAJECTORY", "production", "weights"
)
panel <- file.path(audit, "P6_P5C_COUNT_ACTIVE", "panel_matched")
headline <- file.path(audit, "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv")
weight_robustness <- file.path(robust, "WEIGHT_ROBUSTNESS_P5C")

required <- c(weights, panel, headline, weight_robustness)
missing <- required[!file.exists(required) & !dir.exists(required)]
if (length(missing)) {
  stop(
    "Completed P5c/P6 inputs are missing. Build the core 1993 release first: ",
    paste(missing, collapse = ", ")
  )
}

rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")
run <- function(script, extra = character()) {
  message("[release extensions] ", script)
  script_path <- file.path(r_dir, script)
  final_path <- file.path(r_dir, "final_thesis", script)
  if (file.exists(final_path)) script_path <- final_path
  status <- system2(
    rscript, c(script_path, extra), stdout = "", stderr = ""
  )
  if (!identical(status, 0L)) stop(script, " failed with status ", status)
}
reps <- paste0("--bootstrap-reps=", bootstrap_reps)

# Financial-condition robustness: exact g-1 and latest g-3:g-1.
for (window in c("exact_gm1", "latest_gm3_gm1")) {
  suffix <- if (window == "exact_gm1") "" else "_GM3"
  design <- file.path(robust, paste0("FINANCIAL_CONDITIONS_DESIGN", suffix))
  estimation <- file.path(
    robust, paste0("FINANCIAL_CONDITIONS_ESTIMATION", suffix)
  )
  run("48j_build_lmv2_financial_condition_design.R", c(
    paste0("--weights-dir=", weights), paste0("--output-dir=", design),
    paste0("--financial-window=", window)
  ))
  run("48k_run_lmv2_financial_condition_estimation.R", c(
    paste0("--panel-dir=", panel), paste0("--design-dir=", design),
    paste0("--headline-file=", headline),
    paste0("--output-dir=", estimation), reps
  ))
  run("48l_certify_lmv2_financial_condition_robustness.R", c(
    paste0("--design-dir=", design),
    paste0("--estimation-dir=", estimation)
  ))
}

# Supported-inventor and transaction-value size checks.
supported <- file.path(robust, "SUPPORTED_SIZE_SPLIT")
run("48m_build_lmv2_supported_size_split.R", c(
  paste0("--weights-dir=", weights),
  paste0("--output-dir=", file.path(supported, "DESIGN"))
))
run("48n_run_lmv2_supported_size_split.R", c(
  paste0("--panel-dir=", panel),
  paste0("--design-dir=", file.path(supported, "DESIGN")),
  paste0("--weight-robustness-dir=", weight_robustness),
  paste0("--output-dir=", file.path(supported, "ESTIMATION")), reps
))

deal_size <- file.path(robust, "DEAL_VALUE_SIZE_SPLIT")
deal_design <- file.path(deal_size, "DESIGN_V2")
run("48o_build_lmv2_deal_value_size_split.R", c(
  paste0("--weights-dir=", weights), paste0("--output-dir=", deal_design)
))
run("48q_run_lmv2_deal_value_size_split_frozen_weights.R", c(
  paste0("--panel-dir=", panel), paste0("--design-dir=", deal_design),
  paste0("--weight-robustness-dir=", weight_robustness),
  paste0("--output-dir=", file.path(deal_size, "ESTIMATION_PRIMARY_V3")),
  reps
))
run("48p_run_lmv2_deal_value_size_split.R", c(
  paste0("--panel-dir=", panel), paste0("--design-dir=", deal_design),
  paste0("--weight-robustness-dir=", weight_robustness),
  paste0("--output-dir=", file.path(deal_size, "ESTIMATION_REBALANCED")),
  reps
))

# Full-cohort deal-value quantile profile.
quantiles <- file.path(robust, "DEAL_VALUE_QUANTILES")
quantile_design <- file.path(quantiles, "DESIGN_V1")
run("48r_build_lmv2_deal_value_quantiles.R", c(
  paste0("--deal-map=", file.path(
    deal_design, "deal_value_size_deal_map.csv"
  )),
  paste0("--output-dir=", quantile_design)
))
run("48s_run_lmv2_deal_value_quantiles.R", c(
  paste0("--panel-dir=", panel),
  paste0("--design-dir=", quantile_design),
  paste0("--output-dir=", file.path(quantiles, "ESTIMATION_V2")), reps
))

# Selected-population robustness and its deal-value profile.
run("68_run_lmv2_support_threshold_census.R")
run("69_run_lmv2_initially_retained_support_census.R")
run("70_run_lmv2_retained_robustness.R")
run("71_estimate_lmv2_retained_robustness_core.R")
retained <- file.path(robust, "RETAINED_INVENTORS")
run("48f_run_lmv2_ppml_robustness.R", c(
  paste0("--panel-dir=", file.path(retained, "PANEL_PRIMARY")),
  paste0("--code-root=", base),
  paste0("--output-dir=", file.path(retained, "PPML"))
))
run("74_run_lmv2_retained_deal_value_quantiles.R", reps)

run("49a_build_lmv2_1993_robustness_release.R")
message("Final robustness extensions and certification are complete.")
