# ============================================================================
# 48a_run_lmv2_weight_robustness.R -- post-freeze weighting/dependence checks
# ============================================================================
# This runner estimates only checks whose design weights were solved before
# outcomes were opened. It deliberately leaves the frozen P6 runner untouched.
#
# Implemented specifications:
#   * headline weights on all 18 cohorts (comparison row)
#   * headline weights on the 16 cohorts available to equal-deal weighting
#   * equal-deal weights on those same 16 cohorts
#   * cohort-2000 re-solves excluding deal 70, Henkel, or one deal-70 donor firm
#
# Usage (from the repository root):
# Rscript 02_analysis/R/48a_run_lmv2_weight_robustness.R \
#   --panel-dir=<P6 panel_matched directory> \
#   --p4-root=<P4/P5 local_match_v2 artifact directory> \
#   --output-dir=<new output directory> [--smoke]

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}

PANEL_DIR <- get_arg("--panel-dir")
P4_ROOT <- get_arg("--p4-root")
SENSITIVITY_ROOT <- get_arg("--sensitivity-root")
REFIT_ROOT <- get_arg("--refit-root")
OUTPUT_DIR <- get_arg("--output-dir")
CODE_ROOT <- get_arg("--code-root")
SPEC_ARG <- get_arg("--specs")
SENSITIVITY_PANEL <- get_arg("--sensitivity-panel")
SMOKE <- "--smoke" %in% args

if (any(is.na(c(
    PANEL_DIR, P4_ROOT, SENSITIVITY_ROOT, REFIT_ROOT, OUTPUT_DIR)))) {
  stop(paste0(
    "48a requires --panel-dir=, --p4-root=, --sensitivity-root=, ",
    "--refit-root=, and --output-dir="))
}
if (!dir.exists(PANEL_DIR)) stop("Panel directory not found: ", PANEL_DIR)
if (!dir.exists(P4_ROOT)) stop("P4/P5 artifact root not found: ", P4_ROOT)
if (dir.exists(OUTPUT_DIR) && length(list.files(
  OUTPUT_DIR, all.files = TRUE, no.. = TRUE
))) stop("Output directory must be new or empty: ", OUTPUT_DIR)

BASE <- normalizePath(
  if (is.na(CODE_ROOT)) "02_analysis" else CODE_ROOT,
  mustWork = TRUE
)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
required <- c(
  "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng"
)
for (pkg in required) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
panel_cohorts <- as.integer(sub(
  "^.*_c([0-9]+)\\.parquet$", "\\1", panel_files
))
if (!identical(panel_cohorts, 1993:2010)) {
  stop("The base panel must contain exactly one shard for each cohort 1993:2010")
}
base_panel_sql <- lmv2_panel_sql(panel_files)

one_file <- function(path, label) {
  files <- Sys.glob(path)
  if (length(files) != 1L) {
    stop(label, " requires exactly one file; found ", length(files), ": ", path)
  }
  normalizePath(files, winslash = "/", mustWork = TRUE)
}

equal_deal_files <- vapply(setdiff(1993:2010, c(2000L, 2005L)), function(g) {
  one_file(file.path(
    P4_ROOT, "P5C_ANNUAL_TRAJECTORY", "equal_deal_other_cohorts", "weights",
    sprintf("c%d_equal_deal_count_active_*.parquet", g)
  ), paste0("equal_deal cohort ", g))
}, character(1))

sensitivity_files <- c(
  no_deal70 = one_file(file.path(
    SENSITIVITY_ROOT, "N", "weights", "main",
    "weights_2000_primary_*.parquet"
  ), "no_deal70"),
  omit_henkel = one_file(file.path(
    SENSITIVITY_ROOT, "H", "weights", "main",
    "weights_2000_primary_*.parquet"
  ), "omit_henkel")
)

refit_dirs <- sort(list.dirs(
  REFIT_ROOT, recursive = FALSE,
  full.names = TRUE
))
for (refit_dir in refit_dirs) {
  status_path <- file.path(refit_dir, "deal70_refit_status.csv")
  if (!file.exists(status_path)) next
  status <- utils::read.csv(status_path, stringsAsFactors = FALSE)
  if (nrow(status) != 1L || identical(status$mode[[1]], "infeasible")) next
  firm <- as.character(status$omitted_control_group[[1]])
  sensitivity_files[[paste0("omit_firm_", firm)]] <- one_file(file.path(
    refit_dir, "weights", "main", "weights_2000_primary_*.parquet"
  ), paste0("omit_firm_", firm))
}
if (length(sensitivity_files) != 10L) {
  stop("Expected 10 feasible pre-solved sensitivity weights (deal, Henkel, 8 firms)")
}

sql_weight_join <- function(weight_files) {
  weights_sql <- lmv2_panel_sql(weight_files)
  sprintf(
    paste0(
      "(SELECT p.* EXCLUDE(weight), CAST(w.final_weight AS DOUBLE) AS weight ",
      "FROM %s p INNER JOIN %s w USING (roster_row_id))"
    ), base_panel_sql, weights_sql
  )
}

sql_cohort2000_replacement <- function(weight_file, specification) {
  if (is.na(SENSITIVITY_PANEL) || !file.exists(SENSITIVITY_PANEL)) {
    stop(
      "A materialized --sensitivity-panel= is required for re-solved rosters; ",
      "joining them to the headline panel would omit newly selected donors"
    )
  }
  weights_sql <- lmv2_panel_sql(weight_file)
  sensitivity_sql <- lmv2_panel_sql(normalizePath(
    SENSITIVITY_PANEL, winslash = "/", mustWork = TRUE
  ))
  sprintf(
    paste0(
      "(SELECT * FROM %1$s WHERE cohort <> 2000 UNION ALL ",
      "SELECT p.* REPLACE(",
      "CONCAT(%4$s, '_', p.roster_row_id) AS roster_row_id, ",
      "CAST(w.final_weight AS DOUBLE) AS weight) ",
      "FROM %3$s p INNER JOIN %2$s w ON p.deal_id=w.deal_id ",
      "AND CAST(p.codinv AS DOUBLE)=w.codinv ",
      "AND CAST(p.arm='treated' AS INTEGER)=w.treated ",
      "AND (w.treated=1 OR CAST(p.focal_group_1 AS DOUBLE)=w.control_group) ",
      "WHERE p.cohort = 2000)"
    ), base_panel_sql, weights_sql, sensitivity_sql,
    lmv2_sql_string(specification)
  )
}

cohorts_16 <- setdiff(1993:2010, c(2000L, 2005L))
specs <- list(
  headline_all18 = list(
    panel_sql = base_panel_sql, cohorts = 1993:2010,
    source = "frozen_headline_weights", estimand = "inventor_weighted"
  ),
  headline_same16 = list(
    panel_sql = base_panel_sql, cohorts = cohorts_16,
    source = "frozen_headline_weights", estimand = "inventor_weighted"
  ),
  equal_deal_same16 = list(
    panel_sql = sql_weight_join(equal_deal_files), cohorts = cohorts_16,
    source = paste(equal_deal_files, collapse = ";"), estimand = "equal_deal"
  )
)
for (id in names(sensitivity_files)) {
  specs[[id]] <- list(
    panel_sql = sql_cohort2000_replacement(sensitivity_files[[id]], id),
    cohorts = 1993:2010, source = sensitivity_files[[id]],
    estimand = "inventor_weighted_re_solved_cohort_2000"
  )
}
if (!is.na(SPEC_ARG)) {
  requested <- trimws(strsplit(SPEC_ARG, ",", fixed = TRUE)[[1]])
  if (!length(requested) || any(!requested %in% names(specs))) {
    stop("--specs contains an unknown or empty specification")
  }
  specs <- specs[requested]
}

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) utils::write.csv(
  x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = ""
)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", LMV2_P6_ESTIMATION$execution$duckdb_memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", LMV2_P6_ESTIMATION$execution$threads
))
temp_dir <- file.path(OUTPUT_DIR, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))

certify_panel <- function(spec_id, spec) {
  cohort_sql <- paste(spec$cohorts, collapse = ",")
  out <- DBI::dbGetQuery(con, sprintf(
    paste0(
      "WITH p AS (SELECT * FROM %1$s WHERE cohort IN (%2$s)), ",
      "u AS (SELECT roster_row_id, COUNT(*) n, COUNT(DISTINCT cohort) nc, ",
      "COUNT(DISTINCT deal_id) nd, COUNT(DISTINCT arm) na, ",
      "COUNT(DISTINCT codinv) ni, MIN(event_time) mine, MAX(event_time) maxe ",
      "FROM p GROUP BY roster_row_id), ",
      "m AS (SELECT cohort, SUM(weight) FILTER(arm='treated' AND event_time=-1) tm, ",
      "SUM(weight) FILTER(arm='control' AND event_time=-1) cm FROM p GROUP BY cohort) ",
      "SELECT COUNT(*) panel_rows, (SELECT COUNT(*) FROM u) units, ",
      "(SELECT COUNT(*) FROM u WHERE n<>11 OR nc<>1 OR nd<>1 OR na<>1 OR ni<>1 ",
      "OR mine<>-5 OR maxe<>5) bad_units, ",
      "(SELECT COUNT(*) FROM m WHERE ABS(tm-cm)>1e-7) bad_masses, ",
      "COUNT(*) FILTER(weight IS NULL OR NOT isfinite(weight) OR weight<=0) bad_weights, ",
      "COUNT(DISTINCT cohort) cohorts, COUNT(DISTINCT deal_id) deals ",
      "FROM p"
    ), spec$panel_sql, cohort_sql
  ))
  out$specification <- spec_id
  out$pass <- out$bad_units == 0 & out$bad_masses == 0 &
    out$bad_weights == 0 & out$cohorts == length(spec$cohorts) & out$deals > 1
  out
}

bootstrap_reps <- if (SMOKE) 199L else LMV2_P6_ESTIMATION$inference$replications
t0 <- Sys.time()
certification <- list()
dynamic <- list()
pretrend <- list()
headline <- list()
coverage <- list()
progress <- list()

for (i in seq_along(specs)) {
  id <- names(specs)[[i]]
  spec <- specs[[i]]
  message(sprintf("[%d/%d] %s", i, length(specs), id))
  step_start <- Sys.time()
  certification[[i]] <- certify_panel(id, spec)
  write_csv(
    do.call(rbind, certification), "weight_robustness_certification.csv"
  )
  if (!isTRUE(certification[[i]]$pass[[1]])) {
    detail <- paste(
      paste(names(certification[[i]]), certification[[i]][1, ], sep = "="),
      collapse = ", "
    )
    stop("Panel certification failed: ", id, " [", detail, "]")
  }
  counts <- lmv2_design_deal_counts(con, spec$panel_sql, spec$cohorts)
  fitted <- lmv2_fit_outcome(
    con, spec$panel_sql, "patent_count", id, spec$cohorts,
    bootstrap_reps, counts
  )
  for (object in c("dynamic", "pretrend", "headline", "coverage")) {
    fitted[[object]]$specification <- id
    fitted[[object]]$estimand <- spec$estimand
  }
  dynamic[[i]] <- fitted$dynamic
  pretrend[[i]] <- fitted$pretrend
  headline[[i]] <- fitted$headline
  coverage[[i]] <- fitted$coverage
  progress[[i]] <- data.frame(
    specification = id,
    runtime_minutes = as.numeric(difftime(Sys.time(), step_start, units = "mins")),
    stringsAsFactors = FALSE
  )
  write_csv(do.call(rbind, progress), "weight_robustness_progress.csv")
  rm(fitted)
  gc()
}

write_csv(do.call(rbind, certification), "weight_robustness_certification.csv")
write_csv(do.call(rbind, dynamic), "weight_robustness_dynamic.csv")
write_csv(do.call(rbind, pretrend), "weight_robustness_pretrends.csv")
write_csv(do.call(rbind, headline), "weight_robustness_headline.csv")
write_csv(do.call(rbind, coverage), "weight_robustness_coverage.csv")

source_files <- c(file.path(BASE, "R", c(
  "18a_lmv2_outcome_config.R", "19a_lmv2_p6_estimation_config.R",
  "19b_lmv2_p6_estimation_core.R"
)), normalizePath(
  "02_analysis/R/48a_run_lmv2_weight_robustness.R",
  winslash = "/", mustWork = TRUE
))
source_hashes <- vapply(source_files, digest::digest, character(1),
                        file = TRUE, algo = "sha256")
source_artifacts <- unique(c(
  panel_files, equal_deal_files, sensitivity_files,
  if (!is.na(SENSITIVITY_PANEL)) SENSITIVITY_PANEL else character()
))
source_artifacts <- source_artifacts[file.exists(source_artifacts)]
manifest <- data.frame(
  version = "lmv2_postfreeze_weight_robustness_v1",
  run_mode = if (SMOKE) "smoke_nonproduction" else "production",
  outcome = "patent_count",
  specifications = paste(names(specs), collapse = ";"),
  bootstrap_replications = bootstrap_reps,
  source_bundle_sha256 = digest::digest(
    source_hashes, algo = "sha256", serialize = TRUE
  ),
  artifact_bundle_sha256 = digest::digest(
    vapply(source_artifacts, tools::md5sum, character(1)),
    algo = "sha256", serialize = TRUE
  ),
  all_certification_pass = all(do.call(rbind, certification)$pass),
  runtime_minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")),
  stringsAsFactors = FALSE
)
write_csv(manifest, "weight_robustness_manifest.csv")
message(sprintf(
  "Weight robustness %s run complete: %d specifications in %.2f minutes",
  manifest$run_mode, length(specs), manifest$runtime_minutes
))
