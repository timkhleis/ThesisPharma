# ============================================================================
# 16a_lmv2_matching_config.R -- effective P3 matching configuration
# ============================================================================
# P3 is outcome blind.  This file pins matching semantics without selecting a
# preferred caliper or IPC resolution; those choices belong to P4.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
# A nested git worktree has its own empty .r_libs directory.  Reuse the
# repository-level project library without modifying shared utilities.
LMV2_SHARED_R_LIB <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(LMV2_SHARED_R_LIB)) .libPaths(unique(c(LMV2_SHARED_R_LIB, .libPaths())))
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))

for (pkg in c("digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

LMV2_P3_VERSION <- "local_match_v2_p3_1993_amendment_v1"
LMV2_P2_COMMIT <- "local_match_v2_1993_amendment_v1"
LMV2_P2_MANIFEST_SHA256 <- "3c6c74670107c64fe6f07471061dbb12bfb6efda79f982c81aaed01081bd7591"
LMV2_P3_DISTANCE_EPSILON <- 1e-10

LMV2_P3_PATHS <- list(
  p2_manifest = file.path(BASE, "output", "audit", "local_match_v2", "P2",
                          "p2_interface_manifest.csv"),
  amendment = file.path(BASE, "notes", "local_match_v2_amendments.md"),
  audit = file.path(BASE, "output", "audit", "local_match_v2", "P3"),
  parquet = file.path(BASE, "output", "parquet", "derived")
)

LMV2_P3 <- list(
  information_rule = "matching may use information dated g-1 or earlier; never g or later",
  cohort_standardization = list(
    scalar_population = "treated units plus eligible candidate units within cohort and stage",
    cosine_population = "all admissible treated-by-candidate pairs within cohort and stage",
    epsilon = LMV2_P3_DISTANCE_EPSILON,
    degenerate_component = "contributes_zero_and_is_audited",
    cosine_is_not_centered = TRUE
  ),
  trajectory = list(
    formula = "log1p(patents_g_minus_2_to_g_minus_1/2)-log1p(patents_g_minus_5_to_g_minus_3/3)",
    early_years = -5:-3,
    recent_years = -2:-1,
    early_divisor = 3,
    recent_divisor = 2
  ),
  technology = list(
    resolutions = c("ipc4", "ipc_main_group", "ipc7"),
    labels = c(
      ipc4 = "IPC subclass (for example A61K)",
      ipc_main_group = "IPC main group (for example A61K31)",
      ipc7 = "normalized full IPC subgroup (for example A61K31/00)"
    ),
    default_for_infrastructure_tests = "ipc_main_group",
    vector_weight = "normalized patent-frequency share",
    inventor_portfolio = "entire inventor pre-period portfolio",
    inventor_portfolio_rationale = paste(
      "technology matching targets accumulated scientific expertise, including expertise",
      "formed at earlier employers; applying the same rule to both arms is symmetric"
    ),
    resolution_roles = c(
      ipc4 = "broad subclass candidate and locked Stage-1 firm resolution",
      ipc_main_group = "intermediate inventor resolution added prospectively before P3",
      ipc7 = "normalized full-subgroup inventor resolution added prospectively before P3"
    ),
    stage_1_matching_resolution = "ipc4",
    stage_1_other_resolutions = "diagnostic_similarity_matrices_only",
    shared_ipc4_required = TRUE,
    selection_deferred_to = "P4_after_stage_1_is_frozen",
    p4_inventor_resolution_choice = paste(
      "compare ipc4, ipc_main_group, and ipc7 on positive support, zero share,",
      "distinct-value gradation, ties, balance, and three-controls-two-firms feasibility"
    ),
    missing_firm_vector = "unsupported_and_reported_by_deal"
  ),
  stage_1 = list(
    n_controls = 5L,
    scalar_variables = c("log_patent_stock_5y", "log_inventor_count_5y"),
    diagnostic_variable = "patent_trajectory",
    technology_component = "one_minus_cosine",
    distance = "euclidean_over_standardized_scalar_gaps_and_scaled_uncentered_cosine_distance",
    calipers = c(Inf, 2, 1.5, 1),
    caliper_binds = "total_composite_distance",
    freeze_before_stage_2 = TRUE,
    deterministic_tie_break = c("distance", "control_group")
  ),
  stage_2 = list(
    n_controls = 3L,
    minimum_control_firms = 2L,
    scalar_variables = c(
      "log_patent_count_5y", "patent_trajectory", "career_age",
      "focal_group_tenure", "focal_group_exclusivity"
    ),
    technology_component = "one_minus_cosine",
    distance = "euclidean_over_standardized_scalar_gaps_and_scaled_uncentered_cosine_distance",
    calipers = c(Inf, 2, 1.5, 1),
    caliper_binds = "total_composite_distance",
    recency_bins = c(`0` = "g-1", `1` = "g-2", `2` = "g-3", `3` = "g-4_or_g-5"),
    maximum_recency_bin_gap = 1L,
    shared_ipc4_required = TRUE,
    replacement_across_treated = TRUE,
    distinct_within_treated = TRUE,
    weight = 1 / 3,
    no_second_firm = "unsupported_no_silent_relaxation",
    deterministic_tie_break = c("distance", "control_codinv", "control_group")
  ),
  p2_assignment = list(
    high_confidence_promoted_deals = c(62L, 97L, 98L, 374L),
    treated_focal_evidence = "target_group_link_union_deal_specific_target_company_link"
  )
)

lmv2_p3_file_hash <- function(path) {
  if (!file.exists(path)) stop("Required design record missing: ", path)
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

lmv2_p3_effective_config <- function() {
  if (!file.exists(LMV2_P3_PATHS$p2_manifest)) {
    stop("Frozen P2 interface manifest missing: ", LMV2_P3_PATHS$p2_manifest)
  }
  observed_p2_hash <- lmv2_p3_file_hash(LMV2_P3_PATHS$p2_manifest)
  if (!identical(observed_p2_hash, LMV2_P2_MANIFEST_SHA256)) {
    stop("Frozen P2 interface manifest drifted: expected ",
         LMV2_P2_MANIFEST_SHA256, ", observed ", observed_p2_hash)
  }
  list(
    p3_version = LMV2_P3_VERSION,
    p2_commit = LMV2_P2_COMMIT,
    p0_design_version = LMV2_DESIGN_VERSION,
    p0_design_hash = LMV2_DESIGN_HASH,
    p2_manifest_hash = observed_p2_hash,
    amendment_hash = lmv2_p3_file_hash(LMV2_P3_PATHS$amendment),
    matching = LMV2_P3
  )
}

LMV2_P3_EFFECTIVE_CONFIG <- lmv2_p3_effective_config()
LMV2_P3_CONFIG_HASH <- digest::digest(
  LMV2_P3_EFFECTIVE_CONFIG, algo = "sha256", serialize = TRUE
)
