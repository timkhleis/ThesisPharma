# Frozen P6 common-support and stayer-selection sensitivity rules.

LMV2_P6_SELECTION_FREEZE_SHA256 <-
  "67f6bccd3d01318c1b5d71842d39d1dbd038b11b206d2f706832ab4a2c48f856"
LMV2_P6_SELECTION_FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_p6_selection_sensitivity_freeze.md")
observed_selection_freeze_hash <- lmv2_p3_file_hash(
  LMV2_P6_SELECTION_FREEZE_PATH)
if (!identical(
    observed_selection_freeze_hash,
    LMV2_P6_SELECTION_FREEZE_SHA256)) {
  stop(
    "P6 selection-sensitivity freeze drifted: expected ",
    LMV2_P6_SELECTION_FREEZE_SHA256, ", observed ",
    observed_selection_freeze_hash)
}

LMV2_P6_SELECTION <- list(
  common_support_delta_grid = c(
    -3, -2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2, 3),
  pre_outcome_window = -5:-1,
  pre_outcome_winsorization = c(0.01, 0.99),
  cohort_scope_review = 0.80,
  lee_directions = c("trim_upper_tail", "trim_lower_tail"),
  freeze_hash = LMV2_P6_SELECTION_FREEZE_SHA256
)

lmv2_p6_common_support_sensitivity <- function(
    att_supported, coverage, sigma_pre) {
  values <- c(att_supported, coverage, sigma_pre)
  if (any(!is.finite(values)) || coverage <= 0 || coverage > 1 ||
      sigma_pre < 0) {
    stop("Invalid common-support sensitivity inputs")
  }
  delta <- LMV2_P6_SELECTION$common_support_delta_grid
  att_unsupported <- att_supported + delta * sigma_pre
  data.frame(
    coverage = coverage,
    delta = delta,
    att_supported = att_supported,
    sigma_pre = sigma_pre,
    att_unsupported = att_unsupported,
    att_all = coverage * att_supported +
      (1 - coverage) * att_unsupported,
    stringsAsFactors = FALSE)
}

lmv2_p6_common_support_reversal <- function(
    att_supported, coverage, sigma_pre) {
  values <- c(att_supported, coverage, sigma_pre)
  if (any(!is.finite(values)) || coverage <= 0 || coverage > 1 ||
      sigma_pre < 0) {
    stop("Invalid common-support reversal inputs")
  }
  if (coverage == 1) {
    return(data.frame(
      coverage = coverage,
      att_unsupported_reversal = NA_real_,
      delta_reversal = NA_real_,
      reason = "full_support"))
  }
  att_unsupported_reversal <-
    -coverage / (1 - coverage) * att_supported
  delta_reversal <- if (sigma_pre > 0) {
    -att_supported / ((1 - coverage) * sigma_pre)
  } else {
    NA_real_
  }
  data.frame(
    coverage = coverage,
    att_unsupported_reversal = att_unsupported_reversal,
    delta_reversal = delta_reversal,
    reason = if (sigma_pre > 0) "identified" else "zero_pre_sd",
    stringsAsFactors = FALSE)
}

lmv2_p6_validate_lee_cell <- function(
    treated_selection_rate, comparison_selection_rate) {
  rates <- c(treated_selection_rate, comparison_selection_rate)
  if (any(!is.finite(rates)) || any(rates <= 0 | rates > 1)) {
    stop("Lee selection rates must be in (0,1]")
  }
  higher <- max(rates)
  lower <- min(rates)
  data.frame(
    treated_selection_rate = treated_selection_rate,
    comparison_selection_rate = comparison_selection_rate,
    distribution_to_trim = if (
      treated_selection_rate > comparison_selection_rate) {
      "treated"
    } else if (comparison_selection_rate > treated_selection_rate) {
      "comparison"
    } else {
      "none"
    },
    trimming_share = if (higher > lower) 1 - lower / higher else 0,
    stringsAsFactors = FALSE)
}

