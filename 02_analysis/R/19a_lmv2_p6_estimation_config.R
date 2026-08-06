# ============================================================================
# 19a_lmv2_p6_estimation_config.R -- frozen P6 full-cohort estimation contract
# ============================================================================
# Requires 18a_lmv2_outcome_config.R to have been sourced first. This file is
# declarative only and performs no data access or estimation.

stopifnot(
  identical(
    LMV2_P6_PREANALYSIS_FREEZE_SHA256,
    "a37d0d953845a549f4011ec13ad2e52a46768c3ff8a7aa7f12898a255fac1645"
  )
)

LMV2_P6_ESTIMATION_VERSION <-
  "local_match_v2_p6_estimation_1993_amendment_v1"

LMV2_P6_ESTIMATION <- list(
  samples = list(
    full_1993_2010 = 1993:2010
  ),
  event_window = -5:5,
  reference_event_time = -1L,
  pretrend_window = -5:-2,
  post_window = 1:5,
  model = list(
    formula =
      "dy_mean ~ treated | cohort_event_id",
    fixed_effects = "cohort_by_event_time_on_first_differences",
    weight = "certified_p5_final_weight",
    point_estimand = "direct_standardized_cohort_pooled_supported_inventor_ATT"
  ),
  outcomes = data.frame(
    outcome = c(
      "patent_count", "active_patenting", "tech_drift",
      "pqii_scaled", "fwd_cits5_scaled",
      "pqii_complete", "pqii_observed", "pqii_conditional_mean",
      "fwd_cits5_complete", "fwd_cits5_observed",
      "fwd_cits5_conditional_mean"
    ),
    designation = c(
      "primary", "primary", "primary",
      "secondary_leading", "secondary_leading",
      rep("secondary_diagnostic", 6)
    ),
    interpretation = c(
      "integer patent applications",
      "probability of any patent application",
      "one minus IPC4 cosine, conditional on defined technology",
      "OECD PQII linkage-scaled total",
      "five-year forward citations linkage-scaled total",
      "OECD PQII complete-linkage total",
      "OECD PQII observed linked total",
      "OECD PQII conditional mean among linked patents",
      "forward citations complete-linkage total",
      "forward citations observed linked total",
      "forward citations conditional mean among linked patents"
    ),
    stringsAsFactors = FALSE
  ),
  core_outcomes = c(
    "patent_count", "active_patenting", "tech_drift",
    "pqii_scaled", "fwd_cits5_scaled"
  ),
  inference = list(
    package = "fwildclusterboot",
    package_version = "0.14.3",
    bootstrap_type = "webb",
    replications = 9999L,
    seed = 20260722L,
    impose_null = TRUE,
    confidence_level = 0.95,
    engine = "R",
    dynamic_vcov = "deal_id + codinv",
    companions = c("deal_id + codinv", "deal_id"),
    governing_rule = "wider_of_wild_and_two_way_wild_on_exact_width_tie"
  ),
  execution = list(
    threads = 8L,
    duckdb_memory_limit = "5GB"
  )
)

lmv2_p6_estimation_hash <- function() {
  digest::digest(
    list(
      version = LMV2_P6_ESTIMATION_VERSION,
      construction_design_hash = lmv2_p6_design_hash(),
      freeze_sha256 = LMV2_P6_PREANALYSIS_FREEZE_SHA256,
      config = LMV2_P6_ESTIMATION
    ),
    algo = "sha256", serialize = TRUE
  )
}
