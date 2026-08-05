# ============================================================================
# 15a_lmv2_design_lock.R -- prospective lock for local_match_v2
# ============================================================================
# This file is the machine-readable, outcome-blind design record for packages
# P0--P9.  Any substantive change requires a new design version and an explicit
# amendment note; do not edit thresholds after outcome inspection.

LMV2_DESIGN_VERSION <- "local_match_v2_1993_amendment_v1"
LMV2_LOCK_FROZEN <- TRUE

LMV2_1993_AMENDMENT_PATH <- file.path(
  "02_analysis", "notes", "local_match_v2_1993_cohort_amendment.md"
)

LMV2_LOCK <- list(
  package_order = c("P0", "P1", "P2", "P3", "P4", "P5a", "P6", "P5b", "P7", "P8", "P9"),
  timing = list(
    cohorts = 1993:2010,
    buffered_cohorts = 1993:2008,
    frozen_reproduction_cohorts = 1994:2010,
    event_window = -5:5,
    reference_period = -1L,
    aggregate_post = 1:5,
    treatment_year = "target_year",
    anticipation = 0L,
    patent_clock = "application_year",
    earliest_inventor_exposure_only = TRUE,
    later_exposures = "intention_to_treat_with_audit"
  ),
  cohort = list(
    treated_pre_window = -5:-1,
    treated_requires_deal_specific_target_company_patent = TRUE,
    treated_latest_route = "target_resolved_latest",
    treated_transition_route = "target_to_acquirer_transition_strict",
    controls_latest_rule = c(
      "resolved_group_equals_candidate_control_group",
      "candidate_group_count_equals_1"
    ),
    control_firm_rule = c("never_target", "acquirer_clean_g_minus_5_to_g_plus_5"),
    control_inventor_exposure_rule = "no_target_exposure_on_or_before_g_plus_5",
    transition_max_share_overall = 0.05,
    transition_max_share_era = 0.10,
    always_coreport_without_transition = TRUE,
    broad_company_link_is_robustness_only = TRUE
  ),
  estimands = list(
    primary = "average_effect_for_treated_inventor",
    co_report = "equal_deal_weighted_average_inventor_effect_in_average_acquisition",
    common_support_label_below_retention = 0.90,
    primary_model = "linear_levels",
    robustness_models = c("ppml", "log1p")
  ),
  buffered_sample = list(
    absorbing_left_and_stayers = 1993:2008,
    minimum_stayers = 3000L,
    minimum_deals_with_stayers = 150L,
    minimum_raw_deal_ess = 20,
    full_cohort_left_valid_through = 3L,
    full_cohort_left_through_5_label = "right_censored_descriptive"
  ),
  control_firm_exit = list(
    primary = "itt_keep",
    interpretation = "closure_or_patenting_cessation_is_part_of_untreated_counterfactual",
    diagnostic = "drop_control_firms_last_patent_before_g_plus_5_then_rebuild_stage_2",
    diagnostic_label = "post_event_conditioned_not_superior_causal_design"
  ),
  honest_did = list(
    trigger_if_simultaneous_lead_band_excludes_zero = TRUE,
    trigger_if_abs_lead_exceeds_pre_sd = 0.10
  ),
  inference = list(
    headline = "deal_level_wild_cluster_bootstrap_t",
    package = "fwildclusterboot",
    package_version = "0.14.3",
    package_repository = "https://s3alfisc.r-universe.dev",
    weights = "webb",
    replications = 9999L,
    seed = 20260722L,
    impose_null = TRUE,
    confidence_level = 0.95,
    report_nominal_treated_deals = TRUE,
    effective_deal_count = "1/sum(deal_treated_weight_share^2)",
    companions = c("two_way_deal_inventor_cluster", "deal_only_cluster")
  ),
  matching = list(
    standardization = "within_cohort_treated_plus_eligible_candidate_pool_by_stage",
    zero_variance_component = "contributes_zero_and_is_audited",
    stage_1 = list(
      n_control_firms = 5L,
      variables = c("log_patent_stock_5y", "log_inventor_count_5y", "ipc4_firm_cosine"),
      calipers = c(Inf, 2.0, 1.5, 1.0),
      freeze_before_stage_2 = TRUE,
      trajectory_promotion_pooled_smd = 0.05,
      trajectory_promotion_era_smd = 0.075
    ),
    stage_2 = list(
      n_control_inventors = 3L,
      minimum_control_firms = 2L,
      variables = c(
        "log_patent_count_5y", "patent_trajectory", "career_age",
        "focal_firm_tenure", "focal_firm_exclusivity", "inventor_technology_cosine"
      ),
      calipers = c(Inf, 2.0, 1.5, 1.0),
      recency_bins = c("0:g-1", "1:g-2", "2:g-3", "3:g-4_or_g-5"),
      maximum_recency_bin_gap = 1L,
      distinct_controls = TRUE,
      control_weight = 1 / 3,
      deterministic_id_tie_break = TRUE
    ),
    technology = list(
      shared_ipc4_required = TRUE,
      pilot_cohorts = c(1995L, 2002L, 2009L),
      ipc7_primary_if = list(
        share_three_positive_controls_two_firms = 0.90,
        median_distinct_positive_values = 5L,
        median_zero_cosine_share_below = 0.50,
        share_all_nearest_tied_below = 0.20
      ),
      production_gross_failure = list(
        positive_cosine_support_below = 0.80,
        median_zero_cosine_share_at_least = 0.75,
        median_distinct_positive_values_below = 3L
      ),
      global_fallback = "ipc4_and_rerun_all_stage_2"
    )
  ),
  pilot = list(
    cohorts = c(1995L, 2002L, 2009L),
    stage_1_preferred = list(pooled_smd = 0.05, era_smd = 0.075, deal_retention = 0.90),
    stage_1_acceptable = list(max_smd = 0.10, deal_retention = 0.85),
    stage_1_selection_order = c("deal_retention", "balance", "ess", "loosest_caliper"),
    stage_2_preferred = list(
      pooled_smd = 0.05, era_smd = 0.075,
      inventor_retention = 0.90, deal_retention = 0.90
    ),
    stage_2_acceptable = list(
      max_smd = 0.10, inventor_retention_min = 0.80,
      inventor_retention_max = 0.90, deal_retention = 0.85,
      minimum_cohort_retention = 0.50, preserve_target_size_categories = TRUE
    ),
    stop_if_no_acceptable_design = TRUE
  ),
  outcomes = list(
    patent_count = "distinct_inventor_application_pairs_by_application_year",
    active_patenting = "one_if_at_least_one_patent_in_current_year",
    forward_citations = "oecd_five_year_forward_citations",
    left = "absorbing_indicator_last_focal_patent_year_less_than_calendar_year",
    left_onset = "diagnostic_only",
    pqii = "quality_index_4",
    tech_drift = "cosine_to_inventor_predeal_ipc_vector",
    zero_patent_year = 0,
    incomplete_oecd_linkage = "missing_not_zero",
    oecd_specs = c("complete_linked", "observed_linked", "linkage_scaled"),
    stayer_window = 1:5,
    event_year_zero_can_define_stayer = FALSE
  ),
  stayer_design = list(
    cohorts = 1993:2008,
    treated_and_control_definition = "at_least_one_focal_entity_patent_in_event_time_1_to_5",
    event_year_zero_excluded = TRUE,
    preferred = list(
      pooled_smd = 0.05,
      era_smd = 0.075,
      inventor_retention = 0.90,
      deal_retention = 0.90,
      minimum_matched_deal_ess = 20
    ),
    acceptable = list(
      max_smd = 0.10,
      inventor_retention = 0.80,
      deal_retention = 0.85,
      minimum_cohort_retention = 0.50,
      preserve_target_size_categories = TRUE,
      minimum_matched_deal_ess = 20
    ),
    first_pool = "frozen_five_firm_stage_1_pool",
    fallback_pool = "predeclared_ten_firm_stayer_extension",
    if_both_fail = "report_selection_and_descriptive_results_without_matched_stayer_att"
  ),
  production = list(
    restartable_cohort_shards = TRUE,
    required_validations = c(
      "firm_and_inventor_match_counts", "two_firm_diversification",
      "weight_sums", "balance_and_retention", "concentration",
      "design_hashes", "no_stale_shards"
    ),
    stage_1_must_remain_frozen_during_stage_2 = TRUE
  ),
  placebo = list(
    replications = 200L,
    seed = 20260722L,
    gating_outcomes = c("patent_count", "active_patenting", "absorbing_left", "forward_citations"),
    diagnostic_outcomes = c("pqii", "tech_drift"),
    ordinary = list(mean_abs_sd = 0.10, rejection_rate = c(0.02, 0.10), max_lead_sd = 0.10, positive_share = c(0.40, 0.60)),
    gross = list(mean_abs_sd = 0.20, rejection_rate_above = 0.20, max_lead_sd = 0.20, positive_share = c(0.25, 0.75)),
    failure_rule = "one_gross_or_two_ordinary",
    shard = "outcome_by_cohort_by_blocks_of_20",
    memory_limit = "9GB"
  ),
  dealsim = list(
    supported = c(
      "middle_att_better_than_both_extremes",
      "tercile_equality_rejects_at_10_percent",
      "quadratic_concave_and_jointly_significant_at_10_percent",
      "estimated_peak_inside_support"
    ),
    consistent_but_imprecise = "ordering_and_curvature_agree_but_precision_or_peak_localization_insufficient",
    no_pattern = "ordering_or_curvature_contradicts_or_peak_outside_support"
  ),
  interfaces = list(
    inventor_lookup = "inventor_lookup",
    inventor_year = "inventor_year",
    treated_primary = "lmv2_treated_primary",
    treated_broad = "lmv2_treated_broad",
    control_firms = "lmv2_control_firm_eligibility",
    control_inventors = "lmv2_control_inventor_eligibility",
    audit_root = "02_analysis/output/audit/local_match_v2"
  ),
  parallel_ownership = list(
    before_p2 = "codex_writes_claude_read_only_review",
    after_p2_codex = c("P3", "P4", "P5a"),
    after_p2_claude = "P6_separate_files_and_worktree",
    placebo_after_integration = TRUE,
    one_writer_per_shared_file = TRUE
  )
)

lmv2_design_hash <- function() {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required to calculate the prospective-lock hash.")
  }
  if (!file.exists(LMV2_1993_AMENDMENT_PATH)) {
    stop("The prospective 1993 cohort amendment is missing.")
  }
  digest::digest(
    list(
      lock = LMV2_LOCK,
      amendment_sha256 = digest::digest(
        file = LMV2_1993_AMENDMENT_PATH,
        algo = "sha256",
        serialize = FALSE
      )
    ),
    algo = "sha256", serialize = TRUE
  )
}

# The approved design identifier is frozen in the certified 1993 panel stamps.
# Keep narrative implementation updates to the amendment note from changing
# that identifier after estimation.  The separate lock-only hash below still
# fails closed if any substantive field in LMV2_LOCK drifts.
LMV2_LOCK_ONLY_HASH <- digest::digest(
  LMV2_LOCK, algo = "sha256", serialize = TRUE
)
stopifnot(identical(
  LMV2_LOCK_ONLY_HASH,
  "9248146f976ce030121cad1e706d0923708f7b2e1c17fe5cc95f1464606ab4a8"
))
LMV2_DESIGN_HASH <-
  "877fff88c2fa107800800f4983721835e92aab51fdaed9b9b0c5f0dacd161930"
