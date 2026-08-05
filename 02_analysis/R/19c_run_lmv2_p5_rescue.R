# Selected-stage, restartable P5.1 rescue runner.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE, default = NA_character_) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(default)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
if (any(startsWith(args, "--mode=")) ||
    any(startsWith(args, "--selected-mode="))) {
  stop("Use --rescue-mode=production|certify with the P5.1 runner")
}
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
lmv2_install_p5_sparse_cache()
source(file.path(BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))
source(file.path(BASE, "R", "19a_lmv2_p5_rescue_config.R"))
source(file.path(BASE, "R", "18n_lmv2_p5_weight_materialization.R"))
source(file.path(
  BASE, "R", "19f_lmv2_p5_rescue_dependence_diagnostics.R"))

mode <- read_arg("rescue-mode")
if (identical(mode, "certify")) {
  source(
    file.path(BASE, "R", "19d_certify_lmv2_p5_rescue.R"),
    local = new.env(parent = .GlobalEnv))
} else if (identical(mode, "production")) {
  stage <- read_arg("stage")
  db_path <- read_arg("db")
  audit_dir <- read_arg("audit-dir")
  p3_manifest_path <- read_arg("p3-manifest")
  cohorts <- as.integer(strsplit(
    read_arg("cohorts"), ",", fixed = TRUE)[[1]])
  confirm_full <- read_arg(
    "confirm-full", required = FALSE, default = "NO")
  if (!length(cohorts) || anyNA(cohorts) ||
      any(!cohorts %in% LMV2_P5_RESCUE$selected$cohorts)) {
    stop("--cohorts= contains an invalid cohort")
  }
  if (any(!cohorts %in% LMV2_P5_RESCUE$diagnostic_cohorts) &&
      !identical(confirm_full, "YES_P5_RESCUE")) {
    stop(
      "Full production is locked. Use only cohorts 2000,2009 until review, ",
      "or pass --confirm-full=YES_P5_RESCUE after approval.")
  }

  STAGE1_CALIPERS <- LMV2_P5_RESCUE$selected$stage1_caliper
  STAGE1_PROFILES <- LMV2_P5_RESCUE$selected$profile
  STAGE2_CALIPER <- LMV2_P5_RESCUE$selected$stage2_caliper
  UNIVERSES <- LMV2_P5_RESCUE$selected$universe
  SCHEMES <- LMV2_P5_RESCUE$selected$schemes
  COHORTS <- cohorts
  LMV2_DISKBACKED_COHORTS <- cohorts
  LMV2_P5_SOLVER <- LMV2_P5_RESCUE$selected$solver
  MIN_ELIGIBLE_FIRMS <-
    LMV2_P5_RESCUE$inventor_first$minimum_stage1_firms
  lmv2_p5_rescue_apply_stage(stage)
  lmv2_install_p5_selected_acceleration()
  lmv2_install_p5_newton_solver()

  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
  execution_hash <- lmv2_p5_rescue_execution_hash(
    BASE, p3_hash, stage)
  lmv2_install_p5_weight_materializer(
    audit_dir = audit_dir,
    execution_hash = execution_hash,
    analysis_scope = "main",
    dealsim_tercile = NA_integer_)
  lmv2_install_p5_rescue_dependence_diagnostics(
    audit_dir = audit_dir,
    execution_hash = execution_hash)

  manifest <- data.frame(
    timestamp = as.character(Sys.time()),
    version = LMV2_P5_RESCUE_VERSION,
    amendment_hash = LMV2_P5_RESCUE_AMENDMENT_SHA256,
    industry_support_amendment_hash =
      LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256,
    execution_hash = execution_hash,
    rescue_stage = stage,
    cohorts = paste(cohorts, collapse = ";"),
    universe = UNIVERSES,
    profile = STAGE1_PROFILES,
    stage1_caliper = STAGE1_CALIPERS,
    stage2_caliper = STAGE2_CALIPER,
    distance_variables = paste(
      LMV2_P3$stage_2$scalar_variables, collapse = ";"),
    balance_variables = paste(
      LMV2_HYBRID_INV_VARS, collapse = ";"),
    cohort_retention_floor = LMV2_COHORT_RETENTION_MIN,
    schemes = paste(SCHEMES, collapse = ";"),
    solver = LMV2_P5_SOLVER,
    outcome_boundary = LMV2_P5_RESCUE$outcome_boundary,
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    manifest, file.path(audit_dir, "p5_rescue_manifest.csv"),
    row.names = FALSE)
  run_cohort_hybrid_pilot(
    db_path, audit_dir, p3_manifest_path,
    cohorts_to_run = cohorts)
} else {
  stop(
    "Unknown --rescue-mode=", mode,
    "; expected production or certify")
}
