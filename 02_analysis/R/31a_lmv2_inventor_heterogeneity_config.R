# ============================================================================
# 31a_lmv2_inventor_heterogeneity_config.R -- frozen inventor heterogeneity
# ============================================================================
# Declarative post-results contract.  The package leaves the certified P5c/P6
# roster, weights, and headline estimates untouched.  All moderators use only
# information dated t=-5,...,-1.  Outcome estimates are opened only by 31c,
# after 31b has built and certified this moderator table.

LMV2_INVENTOR_HET_VERSION <- "lmv2_inventor_heterogeneity_v1"

LMV2_INVENTOR_HET <- list(
  construction = list(
    pre_event_times = -5:-1,
    stable_tie_min_joint_patents = 2L,
    team_measure = paste(
      "share of pre-deal patents involving at least one co-inventor who",
      "appears with the focal inventor on at least two pre-deal patents"
    ),
    moderators = list(
      career_age = list(
        order = c("0-1 years", "2-3 years", "4+ years"),
        designation = "primary",
        mechanism = "career-stage vulnerability"
      ),
      predeal_productivity = list(
        order = c("1 patent", "2 patents", "3+ patents"),
        designation = "primary",
        mechanism = "incentive restructuring and pre-deal productivity"
      ),
      focal_exclusivity = list(
        order = c("exclusive", "multi-firm"),
        designation = "conditional",
        mechanism = "dependence on the focal firm"
      ),
      team_embeddedness = list(
        order = c("no stable team", "partial stable team", "all patents stable team"),
        designation = "primary",
        mechanism = "disruption of established collaboration networks"
      ),
      focal_tenure = list(
        order = c("1-2 years", "3-4 years", "5+ years"),
        designation = "appendix",
        mechanism = "firm-specific embeddedness; alternative to career age"
      )
    )
  ),
  estimand = list(
    outcome = "patent_count",
    reference_event_time = -1L,
    post_event_times = 1:5,
    samples = list(
      full_1994_2010 = 1994:2010,
      buffered_1994_2008 = 1994:2008
    ),
    standardization = paste(
      "group-specific treated-control first-difference ATT standardized to",
      "the same full-treated cohort shares over moderator-common cohorts"
    ),
    meaningful_annual_contrast = 0.053
  ),
  diagnostics = list(
    max_abs_smd = 0.10,
    minimum_treated_inventors = 500L,
    minimum_effective_treated_deals = 15,
    maximum_treated_deal_share = 0.25
  ),
  inference = list(
    primary_cluster = "deal_id",
    companion_cluster = "deal_id + codinv",
    bootstrap_type = "Webb",
    bootstrap_replications = 9999L,
    bootstrap_seed = 20260729L,
    confidence_level = 0.95,
    family_alpha = 0.05,
    target_power = 0.80,
    moderator_omnibus_adjustment = "Holm"
  ),
  execution = list(
    threads = 8L,
    memory_limit = "5GB"
  ),
  inputs = list(
    database = file.path(
      "02_analysis", "output", "thesis_foundation.duckdb"
    ),
    panel_dir = file.path(
      "02_analysis", "output", "audit", "local_match_v2",
      "P6_P5C_PANEL_COUNT_ACTIVE", "panel_matched"
    ),
    panel_manifest = file.path(
      "02_analysis", "output", "audit", "local_match_v2",
      "P6_P5C_PANEL_COUNT_ACTIVE", "p6_manifest.csv"
    )
  ),
  output_dir = file.path(
    "02_analysis", "output", "audit", "local_match_v2",
    "P7_INVENTOR_HETEROGENEITY"
  ),
  result_dir = file.path(
    "02_analysis", "output", "results", "local_match_v2",
    "inventor_heterogeneity"
  )
)

lmv2_inventor_het_hash <- function() {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for the heterogeneity design hash")
  }
  digest::digest(
    list(
      version = LMV2_INVENTOR_HET_VERSION,
      parent_design_hash = LMV2_DESIGN_HASH,
      p6_estimation_hash = lmv2_p6_estimation_hash(),
      config = LMV2_INVENTOR_HET
    ),
    algo = "sha256", serialize = TRUE
  )
}

lmv2_het_group <- function(moderator, x) {
  if (moderator == "career_age") {
    return(ifelse(
      x <= 1, "0-1 years", ifelse(x <= 3, "2-3 years", "4+ years")
    ))
  }
  if (moderator == "predeal_productivity") {
    return(ifelse(
      x <= 1, "1 patent", ifelse(x == 2, "2 patents", "3+ patents")
    ))
  }
  if (moderator == "focal_exclusivity") {
    return(ifelse(x >= 1 - 1e-12, "exclusive", "multi-firm"))
  }
  if (moderator == "team_embeddedness") {
    return(ifelse(
      x <= 1e-12, "no stable team",
      ifelse(x >= 1 - 1e-12, "all patents stable team",
             "partial stable team")
    ))
  }
  if (moderator == "focal_tenure") {
    return(ifelse(
      x <= 2, "1-2 years", ifelse(x <= 4, "3-4 years", "5+ years")
    ))
  }
  stop("Unknown moderator: ", moderator)
}

lmv2_het_assert_checks <- function(checks) {
  if (!is.data.frame(checks) ||
      !all(c("check", "pass") %in% names(checks)) ||
      anyNA(checks$pass) || !all(checks$pass)) {
    failed <- if (is.data.frame(checks)) {
      checks$check[is.na(checks$pass) | !checks$pass]
    } else {
      "malformed_check_table"
    }
    stop("Heterogeneity certification failed: ",
         paste(failed, collapse = ", "))
  }
  invisible(TRUE)
}
