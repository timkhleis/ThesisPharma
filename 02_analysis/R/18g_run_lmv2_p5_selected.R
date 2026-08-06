# Selected-spec, restartable P5 balancing runner.

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
    any(startsWith(args, "--p5-mode="))) {
  stop("Use --selected-mode=production|certify with the selected P5 runner")
}
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
lmv2_install_p5_sparse_cache()
source(file.path(BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))
source(file.path(BASE, "R", "18m_lmv2_p5_final_config.R"))
source(file.path(BASE, "R", "18n_lmv2_p5_weight_materialization.R"))

mode <- read_arg("selected-mode")
if (identical(mode, "certify")) {
  source(
    file.path(BASE, "R", "18h_certify_lmv2_p5_selected_acceleration.R"),
    local = new.env(parent = .GlobalEnv))
  source(
    file.path(BASE, "R", "18q_certify_lmv2_p5_final.R"),
    local = new.env(parent = .GlobalEnv))
} else if (identical(mode, "production")) {
  db_path <- read_arg("db")
  audit_dir <- read_arg("audit-dir")
  p3_manifest_path <- read_arg("p3-manifest")
  cohorts <- as.integer(strsplit(read_arg("cohorts"), ",", fixed = TRUE)[[1]])
  caliper <- as.numeric(read_arg("caliper"))
  profile <- read_arg("profile")
  universe <- read_arg("universe")
  schemes <- strsplit(
    read_arg("schemes", required = FALSE, default = "primary,equal_deal"),
    ",", fixed = TRUE)[[1]]
  solver <- read_arg(
    "solver", required = FALSE, default = "newton")
  analysis_scope <- read_arg(
    "analysis-scope", required = FALSE, default = "main")
  dealsim_tercile <- as.integer(read_arg(
    "dealsim-tercile", required = FALSE, default = NA_character_))
  dealsim_map_path <- read_arg(
    "dealsim-map", required = FALSE, default = NA_character_)

  if (!length(cohorts) || anyNA(cohorts)) {
    stop("--cohorts= must contain integer cohort years")
  }
  if (!is.finite(caliper) || !caliper %in% c(1, 1.5, 2)) {
    stop("--caliper= must be one of 1, 1.5, 2")
  }
  if (!profile %in% c("all_eligible", "nearest_50")) {
    stop("--profile= must be all_eligible or nearest_50")
  }
  if (!universe %in% c("u1", "u3")) {
    stop("--universe= must be u1 or u3")
  }
  if (!length(schemes) ||
      !all(schemes %in% c("primary", "equal_deal"))) {
    stop("--schemes= may contain primary and/or equal_deal")
  }
  if (!solver %in% c("weightit", "newton")) {
    stop("--solver= must be weightit or newton")
  }
  if (!analysis_scope %in% c("main", "dealsim_tercile")) {
    stop("--analysis-scope= must be main or dealsim_tercile")
  }
  if (identical(analysis_scope, "main")) {
    if (!is.na(dealsim_tercile) || !is.na(dealsim_map_path)) {
      stop("Main scope cannot receive DealSim tercile arguments")
    }
  } else {
    if (is.na(dealsim_tercile) || !dealsim_tercile %in% 1:3 ||
        is.na(dealsim_map_path)) {
      stop(
        "DealSim scope requires --dealsim-tercile=1|2|3 and ",
        "--dealsim-map=...")
    }
    dealsim_map_path <- normalizePath(
      dealsim_map_path, winslash = "/", mustWork = TRUE)
    dealsim_map <- utils::read.csv(
      dealsim_map_path, stringsAsFactors = FALSE)
    required_map <- c(
      "cohort", "deal_id", "dealsim_tercile", "definition_hash")
    if (!all(required_map %in% names(dealsim_map)) ||
        anyDuplicated(dealsim_map[c("cohort", "deal_id")]) ||
        length(unique(dealsim_map$definition_hash)) != 1L) {
      stop("DealSim map schema, key, or definition hash is invalid")
    }
    deal_filter <- dealsim_map[
      !is.na(dealsim_map$dealsim_tercile) &
        dealsim_map$dealsim_tercile == dealsim_tercile &
        dealsim_map$cohort %in% cohorts,
      c("cohort", "deal_id")]
    if (!nrow(deal_filter)) {
      stop("Requested cohorts contain no deals in DealSim tercile")
    }
    assign(
      "LMV2_P5_TREATED_DEAL_FILTER",
      deal_filter,
      envir = .GlobalEnv)
  }
  lmv2_p5_assert_selected_settings(
    caliper, profile, universe, schemes, solver, cohorts)

  STAGE1_CALIPERS <- caliper
  STAGE1_PROFILES <- profile
  UNIVERSES <- universe
  SCHEMES <- schemes
  COHORTS <- cohorts
  LMV2_DISKBACKED_COHORTS <- cohorts
  LMV2_P5_SOLVER <- solver
  lmv2_install_p5_selected_acceleration()
  if (identical(solver, "newton")) {
    lmv2_install_p5_newton_solver()
  }

  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
  execution_hash <- lmv2_p5_selected_execution_hash(BASE, p3_hash)
  lmv2_install_p5_weight_materializer(
    audit_dir = audit_dir,
    execution_hash = execution_hash,
    analysis_scope = analysis_scope,
    dealsim_tercile = dealsim_tercile)
  manifest <- data.frame(
    timestamp = as.character(Sys.time()),
    version = LMV2_P5_FINAL_VERSION,
    selected_acceleration_version = LMV2_P5_SELECTED_VERSION,
    amendment_hash = LMV2_P5_FINAL_AMENDMENT_SHA256,
    execution_hash = execution_hash,
    analysis_scope = analysis_scope,
    dealsim_tercile = dealsim_tercile,
    dealsim_map_path = dealsim_map_path,
    dealsim_map_checksum = if (is.na(dealsim_map_path)) {
      NA_character_
    } else {
      lmv2_p3_file_hash(dealsim_map_path)
    },
    cohorts = paste(cohorts, collapse = ";"),
    caliper = caliper, profile = profile, universe = universe,
    schemes = paste(schemes, collapse = ";"),
    solver = solver,
    target_pairs_per_block = LMV2_P5_TARGET_PAIRS_PER_BLOCK,
    edge_cover_cache = TRUE,
    row_level_weights = TRUE,
    outcome_boundary = LMV2_P5_FINAL$outcome_boundary,
    stringsAsFactors = FALSE)
  utils::write.csv(
    manifest, file.path(audit_dir, "p5_selected_manifest.csv"),
    row.names = FALSE)
  run_cohort_hybrid_pilot(
    db_path, audit_dir, p3_manifest_path, cohorts_to_run = cohorts)
} else {
  stop("Unknown --selected-mode=", mode,
       "; expected production or certify")
}
