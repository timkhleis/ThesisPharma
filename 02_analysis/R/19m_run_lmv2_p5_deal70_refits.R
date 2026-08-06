# Outcome-blind nine-firm deletion refits for deal 70.

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
source(file.path(
  BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(
  BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
lmv2_install_p5_sparse_cache()
source(file.path(
  BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
source(file.path(
  BASE, "R", "18j_lmv2_p5_newton_solver.R"))
source(file.path(
  BASE, "R", "19a_lmv2_p5_rescue_config.R"))
source(file.path(
  BASE, "R", "18n_lmv2_p5_weight_materialization.R"))
source(file.path(
  BASE, "R", "19f_lmv2_p5_rescue_dependence_diagnostics.R"))
source(file.path(
  BASE, "R", "19i_lmv2_p5_final_production_config.R"))

db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
refit_root <- read_arg("refit-root")
p3_manifest_path <- normalizePath(
  read_arg("p3-manifest"), winslash = "/", mustWork = TRUE)
omitted_control_group <- as.numeric(read_arg("omitted-control-group"))
if (length(omitted_control_group) != 1L ||
    !is.finite(omitted_control_group)) {
  stop("--omitted-control-group= must identify one finite firm")
}

expected_firms <- c(
  100569, 102374, 107670, 108594, 109770,
  200547, 203155, 303292, 307791)
if (!omitted_control_group %in% expected_firms) {
  stop(
    "The omitted firm is not one of the nine preregistered ",
    "deal-70 donor firms")
}

STAGE1_CALIPERS <- LMV2_P5_PRODUCTION$selected$stage1_caliper
STAGE1_PROFILES <- LMV2_P5_PRODUCTION$selected$profile
STAGE2_CALIPER <- LMV2_P5_PRODUCTION$selected$stage2_caliper
UNIVERSES <- LMV2_P5_PRODUCTION$selected$universe
SCHEMES <- LMV2_P5_PRODUCTION$selected$schemes
COHORTS <- 2000L
LMV2_DISKBACKED_COHORTS <- 2000L
LMV2_P5_SOLVER <- LMV2_P5_PRODUCTION$selected$solver
MIN_ELIGIBLE_FIRMS <-
  LMV2_P5_RESCUE$inventor_first$minimum_stage1_firms
lmv2_p5_production_apply()
lmv2_install_p5_selected_acceleration()
lmv2_install_p5_newton_solver()

p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
base_execution_hash <- lmv2_p5_production_execution_hash(
  BASE, p3_hash)
refit_execution_hash <- digest::digest(
  list(
    parent = base_execution_hash,
    refit_runner = lmv2_p3_file_hash(file.path(
      BASE, "R", "19m_run_lmv2_p5_deal70_refits.R")),
    cohort = 2000L,
    deal_id = 70L,
    omitted_control_group = omitted_control_group,
    scheme = "primary"),
  algo = "sha256")

# The frozen design is validated with both schemes above. Each deletion run
# then solves only the preregistered headline primary scheme.
SCHEMES <- "primary"
base_stage1_admissible <- lmv2_ebal_stage1_admissible_edges
assign(
  "lmv2_ebal_stage1_admissible_edges",
  function(edges, caliper) {
    out <- base_stage1_admissible(edges, caliper)
    out[
      !(out$deal_id == 70L &
          out$control_group == omitted_control_group),
      , drop = FALSE]
  },
  envir = .GlobalEnv)
assign(
  "lmv2_composite_execution_hash",
  function(base_dir, p3_manifest_hash) refit_execution_hash,
  envir = .GlobalEnv)

audit_dir <- file.path(
  refit_root,
  sprintf("omit_firm_%s", format(
    omitted_control_group, scientific = FALSE, trim = TRUE)))
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
lmv2_install_p5_weight_materializer(
  audit_dir = audit_dir,
  execution_hash = refit_execution_hash,
  analysis_scope = "main",
  dealsim_tercile = NA_integer_)
lmv2_install_p5_rescue_dependence_diagnostics(
  audit_dir = audit_dir,
  execution_hash = refit_execution_hash)

manifest <- data.frame(
  timestamp = as.character(Sys.time()),
  version = "local_match_v2_p5_deal70_refit_v1",
  production_freeze_hash = LMV2_P5_PRODUCTION_FREEZE_SHA256,
  base_execution_hash = base_execution_hash,
  refit_execution_hash = refit_execution_hash,
  cohort = 2000L,
  deal_id = 70L,
  omitted_control_group = omitted_control_group,
  scheme = "primary",
  outcome_boundary = LMV2_P5_PRODUCTION$outcome_boundary,
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest, file.path(audit_dir, "deal70_refit_manifest.csv"),
  row.names = FALSE)

run_cohort_hybrid_pilot(
  db_path, audit_dir, p3_manifest_path,
  cohorts_to_run = 2000L)
diagnostics <- utils::read.csv(
  file.path(audit_dir, "cohort_hybrid_diagnostics_2000.csv"),
  stringsAsFactors = FALSE)
diagnostics$omitted_control_group <- omitted_control_group
utils::write.csv(
  diagnostics, file.path(audit_dir, "deal70_refit_status.csv"),
  row.names = FALSE)
message(
  "Deal-70 outcome-blind refit complete after omitting firm ",
  omitted_control_group)

