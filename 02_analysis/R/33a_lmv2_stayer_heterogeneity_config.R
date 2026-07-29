# ============================================================================
# 33a_lmv2_stayer_heterogeneity_config.R -- frozen stayer heterogeneity design
# ============================================================================

# Reuse the already-certified numerical helpers. The stayer package has its
# own roster, weights, hash, outputs, and reporting family.
source(file.path("02_analysis", "R", "32a_lmv2_vr_heterogeneity_config.R"))

LMV2_STAYER_HET_VERSION <- "lmv2_stayer_heterogeneity_v1"

lmv2_stayer_root <- function() {
  project_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  ok <- dir.exists(file.path(
    project_root, "02_analysis", "output", "audit", "local_match_v2",
    "P5B_STAYER_S3"
  ))
  if (!isTRUE(ok)) {
    stop("Cannot locate the certified local P5b stayer handoff")
  }
  project_root
}

LMV2_STAYER_HET <- local({
  stayer_root <- lmv2_stayer_root()
  stayer_audit <- file.path(
    stayer_root, "02_analysis", "output", "audit", "local_match_v2"
  )
  list(
    construction = list(
      primary_spec = "primary_count_active_scale",
      primary_support = "primary_resolved_t1",
      primary_moderators = c(
        "predeal_productivity", "career_age",
        "team_persistence", "techfit"
      ),
      appendix_moderators = "focal_tenure",
      primary_outcomes = c("patent_count", "active_patenting")
    ),
    estimand = list(
      population = "patent-observed initially retained inventors",
      reference_event_time = -1L,
      pre_event_times = -5:-1,
      post_event_times = 1:5,
      samples = list(
        full_1994_2010 = 1994:2010,
        buffered_1994_2008 = 1994:2008
      ),
      meaningful_contrast = c(
        patent_count = 0.053,
        active_patenting = 0.020
      ),
      focal_contrast = list(
        predeal_productivity = "treated weighted p75 minus p25",
        career_age = "treated weighted p75 minus p25",
        team_persistence = "average positive persistent tie minus no tie",
        techfit = "treated weighted p75 minus p25",
        focal_tenure = "treated weighted p75 minus p25"
      )
    ),
    inference = list(
      bootstrap_type = "Webb",
      bootstrap_replications = 9999L,
      bootstrap_seed = 20260722L,
      confidence_level = 0.95,
      target_power = 0.80,
      primary_reporting = "unadjusted governing p-values",
      multiplicity =
        "Holm across 4 primary moderators x 2 outcomes, appendix only"
    ),
    execution = list(threads = 8L, memory_limit = "5GB"),
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
      ),
      full_moderators = file.path(
        "02_analysis", "output", "audit", "local_match_v2",
        "P7_VR_HETEROGENEITY", "vr_moderators.parquet"
      ),
      full_moderator_manifest = file.path(
        "02_analysis", "output", "audit", "local_match_v2",
        "P7_VR_HETEROGENEITY", "moderator_build_manifest.csv"
      ),
      s3_weights = file.path(
        stayer_audit, "P5B_STAYER_S3", "s3_production_weights.parquet"
      ),
      s3_manifest = file.path(
        stayer_audit, "P5B_STAYER_S3", "s3_manifest.csv"
      ),
      s3_certification = file.path(
        stayer_audit, "P5B_STAYER_S3", "s3_certification.csv"
      ),
      s3_summary = file.path(
        stayer_audit, "P5B_STAYER_S3", "s3_summary.csv"
      ),
      s4_headline = file.path(
        stayer_audit, "P5B_STAYER_S4_RESULTS", "reporting",
        "s4_governing_results.csv"
      ),
      s4_manifest = file.path(
        stayer_audit, "P5B_STAYER_S4_RESULTS", "s4_manifest.csv"
      ),
      s4_certification = file.path(
        stayer_audit, "P5B_STAYER_S4_RESULTS", "s4_certification.csv"
      )
    ),
    freeze_path = file.path(
      "02_analysis", "notes",
      "local_match_v2_stayer_heterogeneity_freeze.md"
    ),
    output_dir = file.path(
      "02_analysis", "output", "audit", "local_match_v2",
      "P7_STAYER_HETEROGENEITY"
    ),
    result_dir = file.path(
      "02_analysis", "output", "results", "local_match_v2",
      "stayer_heterogeneity"
    )
  )
})

lmv2_stayer_het_hash <- function() {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for the stayer heterogeneity hash")
  }
  digest::digest(
    list(
      version = LMV2_STAYER_HET_VERSION,
      config = LMV2_STAYER_HET,
      config_source_sha256 = digest::digest(
        file = file.path(
          "02_analysis", "R", "33a_lmv2_stayer_heterogeneity_config.R"
        ),
        algo = "sha256"
      ),
      freeze_sha256 = digest::digest(
        file = LMV2_STAYER_HET$freeze_path, algo = "sha256"
      ),
      s3_manifest_sha256 = digest::digest(
        file = LMV2_STAYER_HET$inputs$s3_manifest, algo = "sha256"
      ),
      s4_manifest_sha256 = digest::digest(
        file = LMV2_STAYER_HET$inputs$s4_manifest, algo = "sha256"
      )
    ),
    algo = "sha256", serialize = TRUE
  )
}

lmv2_stayer_het_assert <- function(checks) {
  if (!is.data.frame(checks) ||
      !all(c("check", "pass") %in% names(checks)) ||
      anyNA(checks$pass) || !all(checks$pass)) {
    failed <- if (is.data.frame(checks)) {
      checks$check[is.na(checks$pass) | !checks$pass]
    } else {
      "malformed_check_table"
    }
    stop("Stayer heterogeneity certification failed: ",
         paste(failed, collapse = ", "))
  }
  invisible(TRUE)
}

lmv2_stayer_tenure_valid <- function(tenure, career_age) {
  length(tenure) == length(career_age) &&
    !anyNA(tenure) && !anyNA(career_age) &&
    all(tenure >= 0) && all(tenure <= career_age)
}

lmv2_stayer_prepare_data <- function(
    x, cohorts, techfit_variant = NULL) {
  out <- lmv2_vr_prepare_data(x, cohorts, techfit_variant)
  z <- out$data
  treated <- z$treated == 1
  w <- z$analysis_weight
  tenure_raw <- log1p(z$focal_group_tenure)
  tenure_mean <- weighted.mean(tenure_raw[treated], w[treated])
  tenure_sd <- sqrt(weighted.mean(
    (tenure_raw[treated] - tenure_mean)^2, w[treated]
  ))
  if (!is.finite(tenure_sd) || tenure_sd <= 0) {
    stop("Focal tenure has no treated variation")
  }
  z$tenure_z <- (tenure_raw - tenure_mean) / tenure_sd
  z$tx_tenure <- z$treated * z$tenure_z
  q <- lmv2_vr_weighted_quantile(
    z$focal_group_tenure[treated], w[treated], c(.25, .75)
  )
  out$data <- z
  out$contrasts$focal_tenure <- diff(
    (log1p(q) - tenure_mean) / tenure_sd
  )
  out$contrasts$tenure_raw_quantiles <- q
  out
}
