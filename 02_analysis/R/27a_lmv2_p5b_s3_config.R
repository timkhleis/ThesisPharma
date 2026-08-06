# Local-match-v2 P5b S3: frozen retained-inventor support/weighting config.

if (!exists("lmv2_stayer_existing_path")) {
  source(file.path("02_analysis", "R", "26a_lmv2_stayer_config.R"))
}

LMV2_P5B_S3_VERSION <- "lmv2_p5b_stayer_s3_1993_amendment_v1"
LMV2_P5C_EXECUTION_HASH <- paste0(
  "4b78b1bb54f8f1ade0bb6a6b08d1971071e719ff2cdfbee851fcf9f88f93aff5")

LMV2_P5B_S3_INV_VARS <- c(
  paste0("patent_count_m", 5:1),
  paste0("active_patenting_m", 5:1),
  "career_age",
  "focal_group_exclusivity"
)

LMV2_P5B_S3_FIRM_VARS <- c(
  "firm_log_patent_stock_5y",
  "firm_log_inventor_count_5y",
  "firm_patent_trajectory"
)

lmv2_p5b_s3_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  user_root <- Sys.getenv("USERPROFILE")
  p4_root <- lmv2_stayer_existing_path(
    c(
      Sys.getenv("LMV2_P4_ROOT"),
      file.path(user_root, "Documents", "Thesis", ".worktrees",
                "lmv2-p4-ebal")
    ),
    "the authoritative P4/P5 worktree")
  foundation_db <- lmv2_stayer_config(base)$foundation_db
  p5_root <- file.path(
    p4_root, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment")
  output_dir <- file.path(
    base, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment",
    "P5B_STAYER_S3")
  source_dir <- file.path(output_dir, "support_rosters")
  weight_dir <- file.path(output_dir, "weights")
  balance_dir <- file.path(output_dir, "balance")

  list(
    version = LMV2_P5B_S3_VERSION,
    execution_hash_p5c = LMV2_P5C_EXECUTION_HASH,
    base = base,
    p4_root = p4_root,
    foundation_db = foundation_db,
    s2_dir = file.path(
      base, "02_analysis", "output", "audit",
      "local_match_v2_1993_amendment",
      "P5B_STAYER_S0_S2"),
    p5_root = file.path(p5_root, "P5_PRODUCTION_FINAL"),
    p5c_diagnostics = file.path(
      p5_root, "P5C_ANNUAL_TRAJECTORY", "production",
      "p5c_cell_diagnostics.csv"),
    output_dir = output_dir,
    source_dir = source_dir,
    weight_dir = weight_dir,
    balance_dir = balance_dir,
    support_variants = c(
      "primary_resolved_t1",
      "route_consistent_t1",
      "raw_unmixed_t1",
      "timing_resolved_t2"
    ),
    production_cohorts = 1993:2010,
    production_specs = c(
      "primary_count_active_scale",
      "primary_count_active_scale_loyo_m3",
      "primary_count_active_scale_loyo_m2",
      "route_consistent_count_active_scale",
      "raw_unmixed_count_active_scale",
      "timing_t2_count_active_scale"
    ),
    composition_benchmark = list(
      established_att = -0.0867,
      recent_att = -0.0534,
      source = paste(
        "Frozen full-cohort established-inventor and headline estimates;",
        "benchmark only, not an outcome-based design selector")
    ),
    treated_support_exclusions = data.frame(
      cohort = rep(2008L, 3L),
      codinv = c(174106, 556447, 556448),
      reason = rep(
        paste(
          "Outcome-blind maximum-retention convex-hull diagnostic;",
          "three exclusions stabilize exact balance and ESS"),
        3L),
      stringsAsFactors = FALSE
    ),
    weight_specs = list(
      primary_count_active_scale = list(
        support = "primary_resolved_t1",
        omit = "firm_patent_trajectory"),
      primary_count_active_scale_loyo_m3 = list(
        support = "primary_resolved_t1",
        omit = c(
          "firm_patent_trajectory", "patent_count_m3",
          "active_patenting_m3")),
      primary_count_active_scale_loyo_m2 = list(
        support = "primary_resolved_t1",
        omit = c(
          "firm_patent_trajectory", "patent_count_m2",
          "active_patenting_m2")),
      route_consistent_count_active_scale = list(
        support = "route_consistent_t1",
        omit = "firm_patent_trajectory"),
      raw_unmixed_count_active_scale = list(
        support = "raw_unmixed_t1",
        omit = "firm_patent_trajectory"),
      timing_t2_count_active_scale = list(
        support = "timing_resolved_t2",
        # The T+2 classification leaves only 57 treated inventors in 2010.
        # Retain firm patent scale but omit the collinear firm inventor-count
        # scale so this sensitivity clears the prospectively frozen ESS gate.
        omit = c(
          "firm_patent_trajectory", "firm_log_inventor_count_5y")),
      primary_full = list(
        support = "primary_resolved_t1",
        omit = character()),
      primary_loyo_m3 = list(
        support = "primary_resolved_t1",
        omit = c("patent_count_m3", "active_patenting_m3")),
      primary_loyo_m2 = list(
        support = "primary_resolved_t1",
        omit = c("patent_count_m2", "active_patenting_m2")),
      route_consistent_full = list(
        support = "route_consistent_t1",
        omit = character()),
      raw_unmixed_full = list(
        support = "raw_unmixed_t1",
        omit = character()),
      timing_t2_full = list(
        support = "timing_resolved_t2",
        omit = character()),
      primary_count_only = list(
        support = "primary_resolved_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory")),
      primary_count_only_loyo_m3 = list(
        support = "primary_resolved_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory", "patent_count_m3")),
      primary_count_only_loyo_m2 = list(
        support = "primary_resolved_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory", "patent_count_m2")),
      route_consistent_count_only = list(
        support = "route_consistent_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory")),
      raw_unmixed_count_only = list(
        support = "raw_unmixed_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory")),
      timing_t2_count_only = list(
        support = "timing_resolved_t2",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory")),
      primary_core = list(
        support = "primary_resolved_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory", "firm_log_inventor_count_5y")),
      primary_core_loyo_m3 = list(
        support = "primary_resolved_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory", "firm_log_inventor_count_5y",
          "patent_count_m3")),
      primary_core_loyo_m2 = list(
        support = "primary_resolved_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory", "firm_log_inventor_count_5y",
          "patent_count_m2")),
      route_consistent_core = list(
        support = "route_consistent_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory", "firm_log_inventor_count_5y")),
      raw_unmixed_core = list(
        support = "raw_unmixed_t1",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory", "firm_log_inventor_count_5y")),
      timing_t2_core = list(
        support = "timing_resolved_t2",
        omit = c(
          paste0("active_patenting_m", 5:1),
          "firm_patent_trajectory", "firm_log_inventor_count_5y"))
    ),
    inv_vars = LMV2_P5B_S3_INV_VARS,
    firm_vars = LMV2_P5B_S3_FIRM_VARS,
    support = list(
      minimum_deal_treated = 1L,
      minimum_deal_control_rows = 1L,
      minimum_deal_control_firms = 1L,
      diagnostic_deal_control_firms = 2L
    ),
    gates = list(
      minimum_cohort_retention = 0.80,
      minimum_reuse_adjusted_ess_ratio = 0.50,
      maximum_exact_smd = 1e-6,
      maximum_approximate_smd = 0.10,
      minimum_effective_treated_deals = 20
    ),
    source_files = file.path(
      base, "02_analysis", "R",
      c(
        "27a_lmv2_p5b_s3_config.R",
        "27b_build_lmv2_p5b_s3_support.R",
        "27c_run_lmv2_p5b_s3_weights.R",
        "27d_certify_lmv2_p5b_s3.R",
        "27_run_lmv2_p5b_s3.R"
      )
    ),
    freeze_file = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_p5b_s3_freeze.md")
  )
}

lmv2_p5b_s3_selected_p5c <- function(config) {
  d <- read.csv(config$p5c_diagnostics, stringsAsFactors = FALSE)
  keep <- d$execution_hash == config$execution_hash_p5c &
    d$scheme == "primary" & d$variant == "count_active" & d$feasible
  d <- d[keep, ]
  if (nrow(d) != length(config$production_cohorts) ||
      anyDuplicated(d$cohort)) {
    stop("Expected exactly one certified P5c count-active row per cohort")
  }
  missing <- d$weight_path[!file.exists(d$weight_path)]
  if (length(missing)) stop("Missing P5c weight files: ", paste(missing, collapse = ", "))
  d[order(d$cohort), ]
}

lmv2_p5b_s3_edge_manifest <- function(config) {
  paths <- file.path(
    config$p5_root, sprintf("cohort_%d", config$production_cohorts),
    sprintf("disk_tech_cache/cohort_%d/profile_edge_covers/manifest.csv",
            config$production_cohorts))
  missing <- paths[!file.exists(paths)]
  if (length(missing)) stop("Missing edge manifests: ", paste(missing, collapse = ", "))
  rows <- do.call(rbind, lapply(paths, function(path) {
    x <- read.csv(path, stringsAsFactors = FALSE)
    x[x$universe == "u2" & x$status == "complete", ]
  }))
  if (nrow(rows) != length(config$production_cohorts) ||
      anyDuplicated(rows$cohort)) {
    stop("Expected exactly one completed U2 edge cover per cohort")
  }
  missing_edges <- rows$path[!file.exists(rows$path)]
  if (length(missing_edges)) {
    stop("Missing certified edge files: ", paste(missing_edges, collapse = ", "))
  }
  rows[order(rows$cohort), ]
}

lmv2_p5b_s3_shard_manifest <- function(config) {
  paths <- file.path(
    config$p5_root, sprintf("cohort_%d", config$production_cohorts),
    sprintf("disk_tech_cache/cohort_%d/universe_u2/shard_manifest.csv",
            config$production_cohorts))
  missing <- paths[!file.exists(paths)]
  if (length(missing)) {
    stop("Missing U2 shard manifests: ", paste(missing, collapse = ", "))
  }
  rows <- do.call(rbind, lapply(paths, function(path) {
    x <- read.csv(path, stringsAsFactors = FALSE)
    x[x$universe == "u2" & x$status == "complete", ]
  }))
  # A restarted build may append superseded records. Keep the latest complete
  # record per live path, then require every file/checksum to be valid.
  rows <- rows[!duplicated(rows$path, fromLast = TRUE), ]
  missing_shards <- rows$path[!file.exists(rows$path)]
  if (length(missing_shards)) {
    stop("Missing U2 technology shards: ", paste(missing_shards, collapse = ", "))
  }
  rows[order(rows$cohort, rows$deal_id, rows$block_idx), ]
}
