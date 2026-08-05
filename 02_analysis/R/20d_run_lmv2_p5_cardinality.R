# Build and solve the frozen recovered-inventor cardinality arm by cohort.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}

cohort <- as.integer(read_arg("cohort"))
if (length(cohort) != 1L || !cohort %in% 1994:2010) {
  stop("--cohort= must be one year from 1994 through 2010")
}
db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
production_root <- normalizePath(
  read_arg("production-root"), winslash = "/", mustWork = TRUE)
cardinality_root <- read_arg("cardinality-root")
p3_manifest_path <- normalizePath(
  read_arg("p3-manifest"), winslash = "/", mustWork = TRUE)

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
  BASE, "R", "19i_lmv2_p5_final_production_config.R"))
source(file.path(
  BASE, "R", "20b_lmv2_cardinality_engine.R"))
source(file.path(
  BASE, "R", "20c_lmv2_cardinality_candidates.R"))

production_cover <- list.files(
  file.path(
    production_root, sprintf("cohort_%d", cohort)),
  pattern = "^c_u2_.*\\.parquet$",
  recursive = TRUE, full.names = TRUE)
if (length(production_cover) != 1L) {
  stop("Expected one realized production support cover for cohort ", cohort)
}

STAGE1_CALIPERS <- LMV2_P5_PRODUCTION$selected$stage1_caliper
STAGE1_PROFILES <- LMV2_P5_PRODUCTION$selected$profile
STAGE2_CALIPER <- LMV2_P5_PRODUCTION$selected$stage2_caliper
UNIVERSES <- LMV2_P5_PRODUCTION$selected$universe
SCHEMES <- LMV2_P5_PRODUCTION$selected$schemes
COHORTS <- cohort
LMV2_DISKBACKED_COHORTS <- cohort
LMV2_P5_SOLVER <- LMV2_P5_PRODUCTION$selected$solver
MIN_ELIGIBLE_FIRMS <-
  LMV2_P5_RESCUE$inventor_first$minimum_stage1_firms
lmv2_p5_production_apply()
lmv2_install_p5_selected_acceleration()
lmv2_install_p5_newton_solver()
SCHEMES <- "primary"

p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
execution_hash <- digest::digest(
  list(
    parent = lmv2_p5_production_execution_hash(BASE, p3_hash),
    cardinality_freeze = LMV2_CARDINALITY_FREEZE_SHA256,
    engine = lmv2_p3_file_hash(file.path(
      BASE, "R", "20b_lmv2_cardinality_engine.R")),
    candidates = lmv2_p3_file_hash(file.path(
      BASE, "R", "20c_lmv2_cardinality_candidates.R")),
    runner = lmv2_p3_file_hash(file.path(
      BASE, "R", "20d_run_lmv2_p5_cardinality.R")),
    cohort = cohort),
  algo = "sha256")
assign(
  "lmv2_composite_execution_hash",
  function(base_dir, p3_manifest_hash) execution_hash,
  envir = .GlobalEnv)

cohort_root <- file.path(
  cardinality_root, sprintf("cohort_%d", cohort))
build_root <- file.path(cohort_root, "candidate_build")
candidate_root <- file.path(cohort_root, "candidates")
dir.create(build_root, recursive = TRUE, showWarnings = FALSE)
dir.create(candidate_root, recursive = TRUE, showWarnings = FALSE)
candidate_path <- lmv2_cardinality_candidate_path(
  candidate_root, cohort)

base_builder <- build_stage2_edges_for_profile_diskbacked
assign(
  "build_stage2_edges_for_profile_diskbacked",
  function(
      con, cache_dir, g, universe,
      admissible_firm_edges_profile, treated_inv_ok,
      donors_profile, donor_cols_profile,
      live_execution_hash, caliper) {
    if (!file.exists(candidate_path)) {
      full <- DBI::dbGetQuery(con, sprintf(
        "SELECT CAST(cohort AS INTEGER) cohort,
                CAST(deal_id AS INTEGER) deal_id,
                CAST(codinv AS DOUBLE) treated_codinv
         FROM lmv2_p3_treated_inventor_units
         WHERE cohort=%d", as.integer(g)))
      supported <- DBI::dbGetQuery(con, sprintf(
        "SELECT DISTINCT CAST(cohort AS INTEGER) cohort,
                CAST(deal_id AS INTEGER) deal_id,
                CAST(treated_codinv AS DOUBLE) treated_codinv
         FROM read_parquet('%s')",
        normalizePath(
          production_cover, winslash = "/", mustWork = TRUE)))
      unsupported <- full[
        !paste(
          full$cohort, full$deal_id,
          full$treated_codinv) %in% paste(
            supported$cohort, supported$deal_id,
            supported$treated_codinv),
        , drop = FALSE]
      lmv2_write_cardinality_candidates(
        con = con, cache_dir = cache_dir,
        cohort = g, universe = universe,
        admissible_firm_edges_profile =
          admissible_firm_edges_profile,
        treated_inv_ok = treated_inv_ok,
        donor_cols_profile = donor_cols_profile,
        execution_hash = live_execution_hash,
        stage2_caliper = caliper,
        unsupported_keys = unsupported,
        candidate_root = candidate_root)
    }
    base_builder(
      con, cache_dir, g, universe,
      admissible_firm_edges_profile, treated_inv_ok,
      donors_profile, donor_cols_profile,
      live_execution_hash, caliper)
  },
  envir = .GlobalEnv)

run_cohort_hybrid_pilot(
  db_path, build_root, p3_manifest_path,
  cohorts_to_run = cohort)
if (!file.exists(candidate_path)) {
  stop("Cardinality candidate extraction did not produce ", candidate_path)
}

con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
write_unrecovered <- function(status, candidate_treated = 0L) {
  full_count <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(DISTINCT (deal_id,codinv)) n
     FROM lmv2_p3_treated_inventor_units
     WHERE cohort=%d", cohort))$n[[1]]
  production_supported <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(DISTINCT (deal_id,treated_codinv)) n
     FROM read_parquet('%s')",
    normalizePath(
      production_cover, winslash = "/", mustWork = TRUE)))$n[[1]]
  coverage <- data.frame(
    cohort = cohort, full_treated = as.integer(full_count),
    entropy_supported = as.integer(production_supported),
    cardinality_candidate_treated = as.integer(candidate_treated),
    cardinality_recovered = 0L,
    still_unsupported =
      as.integer(full_count - production_supported),
    entropy_share = production_supported / full_count,
    recovered_share = 0,
    combined_descriptive_share = production_supported / full_count,
    stringsAsFactors = FALSE)
  utils::write.csv(
    data.frame(
      variable = character(), treated_mean = numeric(),
      control_mean = numeric(), scale = numeric(), smd = numeric()),
    file.path(cohort_root, "cardinality_balance.csv"),
    row.names = FALSE)
  utils::write.csv(
    coverage,
    file.path(cohort_root, "cardinality_coverage.csv"),
    row.names = FALSE)
  utils::write.csv(
    data.frame(
      version = "lmv2_cardinality_v1", cohort = cohort,
      production_freeze_hash = LMV2_P5_PRODUCTION_FREEZE_SHA256,
      cardinality_freeze_hash = LMV2_CARDINALITY_FREEZE_SHA256,
      execution_hash = execution_hash, path = "",
      rows = 0L, checksum = "", status = status,
      timestamp = as.character(Sys.time()),
      stringsAsFactors = FALSE),
    file.path(cohort_root, "cardinality_manifest.csv"),
    row.names = FALSE)
  message(
    "Cardinality cohort ", cohort,
    ": no previously unsupported inventor was recoverable (", status, ")")
  quit(save = "no", status = 0)
}
candidate <- DBI::dbGetQuery(con, sprintf(
  "SELECT * FROM read_parquet('%s')",
  normalizePath(candidate_path, winslash = "/", mustWork = TRUE)))
if (!nrow(candidate)) write_unrecovered("no_candidates")
balance_variables <- LMV2_CARDINALITY$balance_variables
treated <- unique(candidate[c(
  "cohort", "deal_id", "treated_codinv",
  paste0(balance_variables, "_treated"))])
names(treated) <- sub("_treated$", "", names(treated))
controls <- unique(candidate[c(
  "cohort", "deal_id", "control_codinv", "control_group",
  paste0(balance_variables, "_control"))])
names(controls) <- sub("_control$", "", names(controls))
edges <- candidate[c(
  "cohort", "deal_id", "treated_codinv",
  "control_codinv", "control_group", "distance")]

solution <- lmv2_cardinality_match(
  treated = treated, controls = controls, edges = edges)
if (!identical(solution$status, "optimal")) {
  write_unrecovered(
    solution$status,
    if (!is.null(solution$n_candidate_treated)) {
      solution$n_candidate_treated
    } else {
      0L
    })
}

selected <- solution$selected_edges
matched <- solution$matched_treated
treated_rows <- data.frame(
  analysis_scope = "cardinality_recovered",
  cohort = as.integer(matched$cohort),
  deal_id = as.integer(matched$deal_id),
  matched_treated_codinv = as.numeric(matched$treated_codinv),
  codinv = as.numeric(matched$treated_codinv),
  treated = 1L,
  control_group = NA_real_,
  final_weight = 1,
  distance = NA_real_,
  stringsAsFactors = FALSE)
control_rows <- data.frame(
  analysis_scope = "cardinality_recovered",
  cohort = as.integer(selected$cohort),
  deal_id = as.integer(selected$deal_id),
  matched_treated_codinv = as.numeric(selected$treated_codinv),
  codinv = as.numeric(selected$control_codinv),
  treated = 0L,
  control_group = as.numeric(selected$control_group),
  final_weight = 1 / LMV2_CARDINALITY$controls_per_treated,
  distance = as.numeric(selected$distance),
  stringsAsFactors = FALSE)
weights <- rbind(treated_rows, control_rows)
weights$scheme <- "cardinality"
weights$estimand <- "att_cardinality_recovered"
weights$execution_hash <- execution_hash
weights$cardinality_freeze_hash <- LMV2_CARDINALITY_FREEZE_SHA256
weights$row_id <- ifelse(
  weights$treated == 1L,
  sprintf(
    "T:%d:%d:%s",
    weights$cohort, weights$deal_id,
    format(
      weights$matched_treated_codinv,
      scientific = FALSE, trim = TRUE)),
  sprintf(
    "C:%d:%d:%s:%s:%s",
    weights$cohort, weights$deal_id,
    format(
      weights$matched_treated_codinv,
      scientific = FALSE, trim = TRUE),
    format(weights$codinv, scientific = FALSE, trim = TRUE),
    format(
      weights$control_group, scientific = FALSE, trim = TRUE)))
if (anyDuplicated(weights$row_id)) {
  stop("Cardinality weight rows are not unique")
}

duckdb::duckdb_register(con, "cardinality_weights", weights)
on.exit(
  try(duckdb::duckdb_unregister(
    con, "cardinality_weights"), silent = TRUE),
  add = TRUE)
weight_path <- file.path(
  cohort_root, sprintf("cardinality_weights_%d.parquet", cohort))
write_result <- lmv2_write_atomic_parquet(
  con,
  "SELECT * FROM cardinality_weights ORDER BY row_id",
  weight_path, "row_id")
duckdb::duckdb_unregister(con, "cardinality_weights")

full_count <- DBI::dbGetQuery(con, sprintf(
  "SELECT COUNT(DISTINCT (deal_id,codinv)) n
   FROM lmv2_p3_treated_inventor_units
   WHERE cohort=%d", cohort))$n[[1]]
production_supported <- DBI::dbGetQuery(con, sprintf(
  "SELECT COUNT(DISTINCT (deal_id,treated_codinv)) n
   FROM read_parquet('%s')",
  normalizePath(
    production_cover, winslash = "/", mustWork = TRUE)))$n[[1]]
coverage <- data.frame(
  cohort = cohort,
  full_treated = as.integer(full_count),
  entropy_supported = as.integer(production_supported),
  cardinality_candidate_treated =
    as.integer(solution$n_candidate_treated),
  cardinality_recovered =
    as.integer(solution$n_matched_treated),
  still_unsupported = as.integer(
    full_count - production_supported -
      solution$n_matched_treated),
  entropy_share = production_supported / full_count,
  recovered_share = solution$n_matched_treated / full_count,
  combined_descriptive_share =
    (production_supported + solution$n_matched_treated) / full_count,
  stringsAsFactors = FALSE)
utils::write.csv(
  solution$diagnostics,
  file.path(cohort_root, "cardinality_balance.csv"),
  row.names = FALSE)
utils::write.csv(
  coverage,
  file.path(cohort_root, "cardinality_coverage.csv"),
  row.names = FALSE)
utils::write.csv(
  data.frame(
    version = "lmv2_cardinality_v1",
    cohort = cohort,
    production_freeze_hash = LMV2_P5_PRODUCTION_FREEZE_SHA256,
    cardinality_freeze_hash = LMV2_CARDINALITY_FREEZE_SHA256,
    execution_hash = execution_hash,
    path = write_result$path,
    rows = write_result$row_count,
    checksum = write_result$checksum,
    status = solution$status,
    timestamp = as.character(Sys.time()),
    stringsAsFactors = FALSE),
  file.path(cohort_root, "cardinality_manifest.csv"),
  row.names = FALSE)
message(
  "Cardinality cohort ", cohort, ": recovered ",
  solution$n_matched_treated, " of ",
  full_count - production_supported, " unsupported treated inventors")
