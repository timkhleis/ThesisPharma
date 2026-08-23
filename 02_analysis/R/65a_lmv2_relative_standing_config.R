# ============================================================================
# 65a_lmv2_relative_standing_config.R -- frozen relative-standing contract
# ============================================================================

LMV2_RELSTAND_VERSION <- "lmv2_relative_standing_1993_v2"

LMV2_RELSTAND <- list(
  construction = list(
    pre_event_times = -5:-1,
    standing_scale = 100,
    contrast_percentage_points = 10,
    combined_pool_grain = "deal_x_cohort_x_arm_x_focal_group",
    top20_minimum_focal_inventors = 5L,
    productive_threshold = 3L
  ),
  estimand = list(
    sample = "full_1993_2010",
    cohorts = 1993:2010,
    reference_event_time = -1L,
    post_event_times = 1:5,
    pretrend_event_times = -5:-2,
    outcomes = c(
      patent_count = "d_patent_ref",
      active_patenting = "d_active_ref"
    ),
    meaningful_effect = c(
      patent_count = 0.053,
      active_patenting = 0.020
    )
  ),
  diagnostics = list(
    max_abs_smd = 0.10,
    minimum_treated_inventors = 500L,
    minimum_effective_treated_deals = 15,
    maximum_treated_deal_share = 0.25
  ),
  inference = list(
    bootstrap_type = "Webb",
    bootstrap_replications = 9999L,
    bootstrap_seed = 20260807L,
    confidence_level = 0.95,
    target_power = 0.80,
    primary_adjustment = "Holm"
  ),
  execution = list(threads = 8L, memory_limit = "5GB"),
  freeze_path = file.path(
    "02_analysis", "notes", "local_match_v2_relative_standing_freeze.md"
  ),
  inputs = list(
    database = file.path(
      "02_analysis", "output", "thesis_foundation.duckdb"
    ),
    inherited_moderators = file.path(
      "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
      "P7_INVENTOR_HETEROGENEITY", "inventor_moderators.parquet"
    ),
    inherited_moderator_manifest = file.path(
      "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
      "P7_INVENTOR_HETEROGENEITY", "moderator_build_manifest.csv"
    ),
    vr_unit_analysis = file.path(
      "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
      "P7_VR_HETEROGENEITY", "vr_unit_analysis.parquet"
    ),
    vr_moderator_manifest = file.path(
      "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
      "P7_VR_HETEROGENEITY", "moderator_build_manifest.csv"
    ),
    vr_power_manifest = file.path(
      "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
      "P7_VR_HETEROGENEITY", "power_gate_manifest.csv"
    ),
    panel_dir = file.path(
      "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
      "P6_P5C_COUNT_ACTIVE", "panel_matched"
    )
  ),
  output_dir = file.path(
    "02_analysis", "output", "audit", "local_match_v2_1993_amendment",
    "P7_RELATIVE_STANDING"
  )
)

lmv2_relstand_hash <- function() {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for the relative-standing design hash")
  }
  digest::digest(
    list(
      version = LMV2_RELSTAND_VERSION,
      parent_design_hash = LMV2_DESIGN_HASH,
      config = LMV2_RELSTAND
    ),
    algo = "sha256", serialize = TRUE
  )
}

lmv2_relstand_assert <- function(checks) {
  if (!is.data.frame(checks) ||
      !all(c("check", "pass") %in% names(checks)) ||
      anyNA(checks$pass) || !all(checks$pass)) {
    failed <- if (is.data.frame(checks)) {
      checks$check[is.na(checks$pass) | !checks$pass]
    } else {
      "malformed_check_table"
    }
    stop("Relative-standing certification failed: ",
         paste(failed, collapse = ", "))
  }
  invisible(TRUE)
}
