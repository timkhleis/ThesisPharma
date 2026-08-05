# Full 24-cell P4 pilot grid using the certified P5 acceleration components.
#
# This runner exists only to finish the specification-selection pilot faster.
# P5 production should use 18g/18i with the single frozen specification.

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
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
lmv2_install_p5_sparse_cache()
source(file.path(BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))

db_path <- read_arg("db")
audit_dir <- read_arg("audit-dir")
p3_manifest_path <- read_arg("p3-manifest")
cohorts <- as.integer(
  strsplit(read_arg("cohorts"), ",", fixed = TRUE)[[1]])
solver <- read_arg(
  "solver", required = FALSE, default = "newton")
if (!length(cohorts) || anyNA(cohorts)) {
  stop("--cohorts= must contain integer cohort years")
}
if (!solver %in% c("weightit", "newton")) {
  stop("--solver= must be weightit or newton")
}

COHORTS <- cohorts
LMV2_DISKBACKED_COHORTS <- cohorts
LMV2_P5_SOLVER <- solver
lmv2_install_p5_selected_acceleration()
if (identical(solver, "newton")) {
  lmv2_install_p5_newton_solver()
}

dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
manifest <- data.frame(
  timestamp = as.character(Sys.time()),
  version = "lmv2_p4_fast_grid_v1",
  execution_hash = lmv2_p5_selected_execution_hash(BASE, p3_hash),
  cohorts = paste(cohorts, collapse = ";"),
  calipers = paste(STAGE1_CALIPERS, collapse = ";"),
  profiles = paste(STAGE1_PROFILES, collapse = ";"),
  universes = paste(UNIVERSES, collapse = ";"),
  schemes = paste(SCHEMES, collapse = ";"),
  solver = solver,
  target_pairs_per_block = LMV2_P5_TARGET_PAIRS_PER_BLOCK,
  edge_cover_cache = TRUE,
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest, file.path(audit_dir, "p4_fast_grid_manifest.csv"),
  row.names = FALSE)
run_cohort_hybrid_pilot(
  db_path, audit_dir, p3_manifest_path,
  cohorts_to_run = cohorts)
