# ============================================================================
# 30a_lmv2_dealsim_power_config.R -- frozen, outcome-gated DealSim power design
# ============================================================================
# Declarative Stage A contract.  This stage may use the certified full-cohort
# patent-count variance structure, but it must not save or report subgroup ATTs.

LMV2_DEALSIM_POWER_VERSION <- "lmv2_dealsim_power_gate_1993_amendment_v1"

LMV2_DEALSIM_POWER <- list(
  construction = list(
    ipc_level = "IPC4",
    pre_event_times = -5:-1,
    vector_weight = "patent_count",
    placeholder_acquirer_regex = "^999",
    tercile_labels = c("low", "middle", "high"),
    deterministic_tie_break = "dealsim_then_deal_id"
  ),
  estimand = list(
    primary_outcome = "patent_count",
    post_event_times = 1:5,
    contrasts = c("low_minus_middle", "high_minus_middle"),
    meaningful_annual_contrast = 0.053
  ),
  power = list(
    family_alpha = 0.05,
    target = 0.80,
    effective_deal_floor = 15,
    minimum_common_cohorts = 8L,
    maximum_deal_share = 0.25,
    bootstrap_type = "webb",
    bootstrap_replications = 9999L,
    bootstrap_seed = 20260728L,
    continuous_basis = "weighted_standardized_dealsim_quadratic"
  ),
  paths = list(
    T = paste(
      "Tercile confirmatory package: both joint-family MDEs do not exceed",
      "the meaningful contrast and all support gates pass."
    ),
    C = paste(
      "Continuous confirmatory package: terciles are descriptive because their",
      "MDE is above the meaningful contrast, but not above twice that contrast."
    ),
    U = paste(
      "The inverted-U prediction is not testable with credible precision in",
      "the current effective deal sample."
    )
  ),
  inputs = list(
    database = file.path(
      "02_analysis", "output", "thesis_foundation.duckdb"
    ),
    panel_dir = file.path(
      "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
      "P6_P5C_COUNT_ACTIVE", "panel_matched"
    ),
    construction_manifest = file.path(
      "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
      "P6_P5C_COUNT_ACTIVE", "p6_manifest.csv"
    )
  ),
  output_dir = file.path(
    "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
    "P7_DEALSIM_POWER_GATE"
  )
)

lmv2_dealsim_power_hash <- function() {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for the DealSim power-gate hash")
  }
  digest::digest(
    list(
      version = LMV2_DEALSIM_POWER_VERSION,
      parent_design_hash = LMV2_DESIGN_HASH,
      config = LMV2_DEALSIM_POWER
    ),
    algo = "sha256", serialize = TRUE
  )
}

lmv2_dealsim_assign_terciles <- function(deal_id, dealsim) {
  if (length(deal_id) != length(dealsim) || anyNA(deal_id) ||
      anyNA(dealsim) || anyDuplicated(deal_id)) {
    stop("Tercile assignment requires unique, nonmissing deal IDs and scores")
  }
  n <- length(deal_id)
  if (n < 3L) stop("At least three eligible deals are required")
  ord <- order(dealsim, deal_id)
  tercile_number <- integer(n)
  tercile_number[ord] <- pmin(
    3L, floor((seq_len(n) - 1L) * 3L / n) + 1L
  )
  unname(LMV2_DEALSIM_POWER$construction$tercile_labels[tercile_number])
}

lmv2_effective_count <- function(weight) {
  if (!length(weight) || any(!is.finite(weight)) || any(weight <= 0)) {
    stop("Effective count requires finite positive weights")
  }
  sum(weight)^2 / sum(weight^2)
}

lmv2_assert_dealsim_rows <- function(x) {
  required <- c(
    "deal_id", "cohort", "acquirer_group", "eligible_dealsim", "dealsim",
    "target_last_ipc_year", "acquirer_last_ipc_year"
  )
  if (!all(required %in% names(x))) {
    stop("DealSim table is missing required columns")
  }
  if (anyNA(x$deal_id) || anyDuplicated(x$deal_id)) {
    stop("DealSim table must contain one unique row per deal")
  }
  placeholder <- !is.na(x$acquirer_group) & grepl(
    LMV2_DEALSIM_POWER$construction$placeholder_acquirer_regex,
    format(x$acquirer_group, scientific = FALSE)
  )
  if (any(placeholder & x$eligible_dealsim)) {
    stop("Placeholder acquirer passed DealSim eligibility")
  }
  eligible <- x$eligible_dealsim
  if (anyNA(eligible) ||
      any(!is.finite(x$dealsim[eligible])) ||
      any(x$dealsim[eligible] < -1e-12 | x$dealsim[eligible] > 1 + 1e-12) ||
      any(!is.na(x$dealsim[!eligible]))) {
    stop("DealSim values are invalid or inconsistent with eligibility")
  }
  if (any(x$target_last_ipc_year[eligible] > x$cohort[eligible] - 1L,
          na.rm = TRUE) ||
      any(x$acquirer_last_ipc_year[eligible] > x$cohort[eligible] - 1L,
          na.rm = TRUE)) {
    stop("DealSim construction used a treatment or post-treatment patent year")
  }
  invisible(TRUE)
}

lmv2_assert_all_checks <- function(checks) {
  if (!is.data.frame(checks) ||
      !all(c("check", "pass") %in% names(checks)) ||
      anyNA(checks$pass) || !all(checks$pass)) {
    failed <- if (is.data.frame(checks) &&
                  all(c("check", "pass") %in% names(checks))) {
      checks$check[is.na(checks$pass) | !checks$pass]
    } else {
      "malformed_check_table"
    }
    stop(
      "At least one certification check failed: ",
      paste(failed, collapse = ", ")
    )
  }
  invisible(TRUE)
}
