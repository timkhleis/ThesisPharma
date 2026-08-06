# Outcome-blind P5 sensitivity refits required before P6.
#
# Supported modes:
#   no_deal70          Re-estimate cohort 2000 after removing deal 70.
#   omit_henkel_exact  Remove Henkel (303292) from deal 70 and accept the
#                      exact-balance solution without an ESS acceptance gate.
#
# These are labeled sensitivity designs. They never overwrite or alter the
# frozen P5 primary weights.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit)
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
lmv2_install_p5_sparse_cache()
source(file.path(BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))
source(file.path(BASE, "R", "19a_lmv2_p5_rescue_config.R"))
source(file.path(BASE, "R", "18n_lmv2_p5_weight_materialization.R"))
source(file.path(BASE, "R", "19f_lmv2_p5_rescue_dependence_diagnostics.R"))
source(file.path(BASE, "R", "19i_lmv2_p5_final_production_config.R"))

db_path <- normalizePath(read_arg("db"), winslash = "/", mustWork = TRUE)
audit_dir <- read_arg("audit-dir")
p3_manifest_path <- normalizePath(
  read_arg("p3-manifest"), winslash = "/", mustWork = TRUE)
sensitivity <- read_arg("sensitivity")
allowed_modes <- c("no_deal70", "omit_henkel_exact")
if (!sensitivity %in% allowed_modes) {
  stop("--sensitivity= must be one of: ", paste(allowed_modes, collapse = ", "))
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

# The frozen design validates both schemes. Each sensitivity estimates only
# the headline primary scheme.
SCHEMES <- "primary"

if (identical(sensitivity, "no_deal70")) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    stop("Packages DBI and duckdb are required")
  }
  con_filter <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con_filter, shutdown = TRUE), add = TRUE)
  LMV2_P5_TREATED_DEAL_FILTER <- DBI::dbGetQuery(con_filter, "
    SELECT DISTINCT CAST(cohort AS INTEGER) AS cohort,
                    CAST(deal_id AS INTEGER) AS deal_id
    FROM lmv2_treated_primary
    WHERE cohort = 2000 AND deal_id <> 70
    ORDER BY deal_id")
  DBI::dbDisconnect(con_filter, shutdown = TRUE)
  on.exit(NULL, add = FALSE)
  if (!nrow(LMV2_P5_TREATED_DEAL_FILTER) ||
      any(LMV2_P5_TREATED_DEAL_FILTER$deal_id == 70L)) {
    stop("Failed to construct the prospective no-deal-70 roster")
  }
}

if (identical(sensitivity, "omit_henkel_exact")) {
  base_stage1_admissible <- lmv2_ebal_stage1_admissible_edges
  assign(
    "lmv2_ebal_stage1_admissible_edges",
    function(edges, caliper) {
      out <- base_stage1_admissible(edges, caliper)
      out[
        !(out$deal_id == 70L & out$control_group == 303292),
        , drop = FALSE]
    },
    envir = .GlobalEnv)

  # This sensitivity has a single, prospectively specified acceptance rule:
  # use the exact-balance solution and report its realized ESS. A zero lower
  # bound disables only the ESS gate; all support, balance, positivity, and
  # finite-weight checks remain active. No alternative tolerance is searched.
  LMV2_COHORT_ESS_RATIO_ACCEPTABLE <- 0
  LMV2_COHORT_ESS_RATIO_PREFERRED <- 0
}

p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
base_execution_hash <- lmv2_p5_production_execution_hash(BASE, p3_hash)
sensitivity_execution_hash <- digest::digest(
  list(
    parent = base_execution_hash,
    runner = lmv2_p3_file_hash(file.path(
      BASE, "R", "20i_run_lmv2_p5_sensitivities.R")),
    cohort = 2000L,
    sensitivity = sensitivity,
    deal_id = 70L,
    omitted_control_group =
      if (sensitivity == "omit_henkel_exact") 303292 else NA_real_,
    acceptance =
      if (sensitivity == "omit_henkel_exact")
        "exact_balance_without_ess_gate"
      else "frozen_primary_hierarchy"),
  algo = "sha256")

assign(
  "lmv2_composite_execution_hash",
  function(base_dir, p3_manifest_hash) sensitivity_execution_hash,
  envir = .GlobalEnv)

dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
lmv2_install_p5_weight_materializer(
  audit_dir = audit_dir,
  execution_hash = sensitivity_execution_hash,
  analysis_scope = "main",
  dealsim_tercile = NA_integer_)
lmv2_install_p5_rescue_dependence_diagnostics(
  audit_dir = audit_dir,
  execution_hash = sensitivity_execution_hash)

manifest <- data.frame(
  timestamp = as.character(Sys.time()),
  version = "local_match_v2_p5_p6_sensitivity_v1",
  sensitivity = sensitivity,
  production_freeze_hash = LMV2_P5_PRODUCTION_FREEZE_SHA256,
  base_execution_hash = base_execution_hash,
  sensitivity_execution_hash = sensitivity_execution_hash,
  cohort = 2000L,
  deal_id = 70L,
  omitted_control_group =
    if (sensitivity == "omit_henkel_exact") 303292 else NA_real_,
  acceptance_rule =
    if (sensitivity == "omit_henkel_exact")
      "exact_balance_without_ess_gate"
    else "frozen_primary_hierarchy",
  scheme = "primary",
  outcome_boundary = LMV2_P5_PRODUCTION$outcome_boundary,
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest, file.path(audit_dir, "sensitivity_manifest.csv"),
  row.names = FALSE)

run_cohort_hybrid_pilot(
  db_path, audit_dir, p3_manifest_path,
  cohorts_to_run = 2000L)

diagnostics_path <- file.path(
  audit_dir, "cohort_hybrid_diagnostics_2000.csv")
diagnostics <- utils::read.csv(
  diagnostics_path, stringsAsFactors = FALSE)
diagnostics$sensitivity_mode <- sensitivity
diagnostics$acceptance_rule <- manifest$acceptance_rule
utils::write.csv(diagnostics, diagnostics_path, row.names = FALSE)

if (sensitivity == "omit_henkel_exact" &&
    !all(diagnostics$mode == "exact_ebal")) {
  stop("Henkel-omitted sensitivity did not materialize the exact-balance rung")
}
message("P5 sensitivity complete: ", sensitivity)
