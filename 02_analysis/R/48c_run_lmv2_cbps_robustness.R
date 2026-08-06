# ============================================================================
# 48c_run_lmv2_cbps_robustness.R -- CBPS alternative to entropy balancing
# ============================================================================
# Uses the identical P5 local-support roster and its pre-treatment base
# weights. CBPS is fit separately by treatment cohort for an ATT estimand.
# Outcome estimation is authorized only after every cohort clears max |SMD|
# <= 0.10. ESS and weight concentration are always written for inspection.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}

P5_WEIGHT_DIR <- get_arg("--p5-weight-dir")
PANEL_DIR <- get_arg("--panel-dir")
CODE_ROOT <- get_arg("--code-root")
OUTPUT_DIR <- get_arg("--output-dir")
SMOKE <- "--smoke" %in% args
if (any(is.na(c(P5_WEIGHT_DIR, PANEL_DIR, CODE_ROOT, OUTPUT_DIR)))) {
  stop("48c requires --p5-weight-dir=, --panel-dir=, --code-root=, --output-dir=")
}
for (path in c(P5_WEIGHT_DIR, PANEL_DIR, CODE_ROOT)) {
  if (!dir.exists(path)) stop("Input directory not found: ", path)
}
if (dir.exists(OUTPUT_DIR) && length(list.files(
  OUTPUT_DIR, all.files = TRUE, no.. = TRUE
))) stop("Output directory must be new or empty: ", OUTPUT_DIR)

BASE <- normalizePath(CODE_ROOT, mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
required <- c(
  "DBI", "duckdb", "digest", "WeightIt", "fixest",
  "fwildclusterboot", "dqrng"
)
for (pkg in required) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

covariates <- c(
  paste0("patent_count_m", 5:1),
  paste0("active_patenting_m", 5:1),
  "career_age", "focal_group_exclusivity",
  "firm_log_patent_stock_5y", "firm_log_inventor_count_5y",
  "firm_patent_trajectory"
)
formula <- stats::reformulate(covariates, response = "treated")
cohorts <- 1993:2010

one_weight_file <- function(g) {
  pattern <- file.path(
    P5_WEIGHT_DIR,
    sprintf("c%d_primary_count_active_*.parquet", g)
  )
  hit <- Sys.glob(pattern)
  if (length(hit) != 1L) stop("Expected one P5 weight file for cohort ", g)
  normalizePath(hit, winslash = "/", mustWork = TRUE)
}
source_weight_files <- vapply(cohorts, one_weight_file, character(1))
panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
panel_cohorts <- as.integer(sub(
  "^.*_c([0-9]+)\\.parquet$", "\\1", panel_files
))
if (!identical(panel_cohorts, cohorts)) stop("P6 panel cohort set is not 1993:2010")

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
weights_dir <- file.path(OUTPUT_DIR, "weights")
dir.create(weights_dir, showWarnings = FALSE)
write_csv <- function(x, name) utils::write.csv(
  x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = ""
)
sql_string <- function(x) paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", LMV2_P6_ESTIMATION$execution$duckdb_memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", LMV2_P6_ESTIMATION$execution$threads
))

weighted_var <- function(x, w) {
  m <- stats::weighted.mean(x, w)
  sum(w * (x - m)^2) / sum(w)
}
smd_one <- function(dat, variable) {
  t <- dat$treated == 1L
  mt <- stats::weighted.mean(dat[[variable]][t], dat$cbps_weight[t])
  mc <- stats::weighted.mean(dat[[variable]][!t], dat$cbps_weight[!t])
  denom <- sqrt(mean(c(
    weighted_var(dat[[variable]][t], dat$cbps_weight[t]),
    weighted_var(dat[[variable]][!t], dat$cbps_weight[!t])
  )))
  if (denom <= 1e-12) return(if (abs(mt - mc) <= 1e-12) 0 else Inf)
  (mt - mc) / denom
}

balance <- list()
diagnostics <- list()
cbps_weight_files <- character(length(cohorts))
warnings_seen <- character()

for (i in seq_along(cohorts)) {
  g <- cohorts[[i]]
  message(sprintf("CBPS weights [%d/%d]: cohort %d", i, length(cohorts), g))
  dat <- DBI::dbGetQuery(
    con, "SELECT * FROM read_parquet(?)", params = list(source_weight_files[[i]])
  )
  if (anyDuplicated(dat$roster_row_id) ||
      any(!stats::complete.cases(dat[c("treated", "base_weight", covariates)])) ||
      any(!is.finite(dat$base_weight) | dat$base_weight <= 0)) {
    stop("Invalid P5 local-support roster for cohort ", g)
  }
  cohort_warnings <- character()
  fit <- withCallingHandlers(
    WeightIt::weightit(
      formula, data = dat, method = "cbps", estimand = "ATT",
      s.weights = dat$base_weight, solver = "optim", over = FALSE,
      maxit = 20000L, reltol = 1e-11, include.obj = TRUE
    ),
    warning = function(w) {
      cohort_warnings <<- c(cohort_warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  raw <- as.numeric(fit$weights) * dat$base_weight
  if (length(raw) != nrow(dat) || any(!is.finite(raw) | raw <= 0)) {
    stop("CBPS produced invalid weights for cohort ", g)
  }
  treated_mass <- sum(dat$base_weight[dat$treated == 1L])
  raw[dat$treated == 0L] <- raw[dat$treated == 0L] *
    treated_mass / sum(raw[dat$treated == 0L])
  raw[dat$treated == 1L] <- dat$base_weight[dat$treated == 1L]
  dat$cbps_weight <- raw

  smd <- vapply(covariates, function(v) smd_one(dat, v), numeric(1))
  balance[[i]] <- data.frame(
    cohort = g, variable = covariates, smd = smd, abs_smd = abs(smd),
    stringsAsFactors = FALSE
  )
  t <- dat$treated == 1L
  control_weights <- raw[!t]
  diagnostics[[i]] <- data.frame(
    cohort = g,
    n_treated = sum(t), n_control_rows = sum(!t),
    treated_mass = sum(raw[t]), control_mass = sum(control_weights),
    treated_ess = sum(raw[t])^2 / sum(raw[t]^2),
    control_ess = sum(control_weights)^2 / sum(control_weights^2),
    control_ess_ratio =
      (sum(control_weights)^2 / sum(control_weights^2)) / sum(t),
    max_control_weight_share = max(control_weights) / sum(control_weights),
    max_abs_smd = max(abs(smd)),
    solver_warning = paste(unique(cohort_warnings), collapse = " | "),
    stringsAsFactors = FALSE
  )
  warnings_seen <- c(warnings_seen, cohort_warnings)

  out <- dat[c("roster_row_id", "cohort", "deal_id", "codinv", "treated")]
  out$final_weight <- raw
  table_name <- paste0("cbps_weights_", g)
  duckdb::duckdb_register(con, table_name, out)
  out_path <- normalizePath(weights_dir, winslash = "/", mustWork = TRUE)
  out_path <- file.path(out_path, sprintf("cbps_weights_c%d.parquet", g))
  DBI::dbExecute(con, sprintf(
    "COPY %s TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    table_name, sql_string(out_path)
  ))
  duckdb::duckdb_unregister(con, table_name)
  cbps_weight_files[[i]] <- out_path
  rm(dat, fit, out)
  gc()
}

balance <- do.call(rbind, balance)
diagnostics <- do.call(rbind, diagnostics)
diagnostics$balance_gate_pass <- diagnostics$max_abs_smd <= 0.10
diagnostics$finite_ess <- is.finite(diagnostics$control_ess) &
  diagnostics$control_ess > 0
att_authorized <- all(diagnostics$balance_gate_pass & diagnostics$finite_ess)
write_csv(balance, "cbps_balance_by_cohort.csv")
write_csv(diagnostics, "cbps_weight_diagnostics.csv")

manifest_base <- data.frame(
  version = "lmv2_cbps_robustness_v1",
  amendment_date = "2026-08-03",
  method = "WeightIt_cbps_ATT_by_cohort",
  weightit_version = as.character(utils::packageVersion("WeightIt")),
  covariates = paste(covariates, collapse = ";"),
  local_support_sample = "identical_frozen_p5_roster",
  sampling_weight = "p5_base_weight",
  balance_gate = "max_abs_smd_le_0.10_in_every_cohort",
  att_authorized = att_authorized,
  failed_cohorts = paste(
    diagnostics$cohort[!diagnostics$balance_gate_pass], collapse = ";"
  ),
  outcome_accessed = att_authorized,
  stringsAsFactors = FALSE
)
if (!att_authorized) {
  manifest_base$status <- "balance_failure_no_att"
  write_csv(manifest_base, "cbps_manifest.csv")
  message("CBPS failed the pre-estimation balance gate; no ATT was estimated")
  quit(status = 0L, save = "no")
}

base_panel_sql <- lmv2_panel_sql(panel_files)
cbps_weights_sql <- lmv2_panel_sql(cbps_weight_files)
panel_sql <- sprintf(
  paste0(
    "(SELECT p.* EXCLUDE(weight), CAST(w.final_weight AS DOUBLE) AS weight ",
    "FROM %s p INNER JOIN %s w USING(roster_row_id))"
  ), base_panel_sql, cbps_weights_sql
)
cert <- DBI::dbGetQuery(con, sprintf(
  paste0(
    "WITH p AS (SELECT * FROM %s), ",
    "u AS (SELECT roster_row_id, COUNT(*) n FROM p GROUP BY roster_row_id), ",
    "m AS (SELECT cohort, SUM(weight) FILTER(arm='treated' AND event_time=-1) tm, ",
    "SUM(weight) FILTER(arm='control' AND event_time=-1) cm FROM p GROUP BY cohort) ",
    "SELECT COUNT(*) panel_rows, (SELECT COUNT(*) FROM u WHERE n<>11) bad_units, ",
    "(SELECT COUNT(*) FROM m WHERE ABS(tm-cm)>1e-7) bad_masses, ",
    "COUNT(*) FILTER(weight IS NULL OR NOT isfinite(weight) OR weight<=0) bad_weights ",
    "FROM p"
  ), panel_sql
))
cert$pass <- cert$bad_units == 0 & cert$bad_masses == 0 & cert$bad_weights == 0
if (!isTRUE(cert$pass[[1]])) stop("CBPS panel certification failed")
write_csv(cert, "cbps_panel_certification.csv")

bootstrap_reps <- if (SMOKE) 199L else LMV2_P6_ESTIMATION$inference$replications
counts <- lmv2_design_deal_counts(con, panel_sql, cohorts)
fitted <- lmv2_fit_outcome(
  con, panel_sql, "patent_count", "cbps_all18", cohorts,
  bootstrap_reps, counts
)
for (object in c("dynamic", "pretrend", "headline", "coverage")) {
  fitted[[object]]$specification <- "cbps_all18"
}
write_csv(fitted$dynamic, "cbps_dynamic.csv")
write_csv(fitted$pretrend, "cbps_pretrend.csv")
write_csv(fitted$headline, "cbps_headline.csv")
write_csv(fitted$coverage, "cbps_coverage.csv")

manifest_base$status <- if (SMOKE) "smoke_nonproduction" else "production"
manifest_base$bootstrap_replications <- bootstrap_reps
manifest_base$source_weight_bundle_sha256 <- digest::digest(
  vapply(source_weight_files, tools::md5sum, character(1)),
  algo = "sha256", serialize = TRUE
)
manifest_base$cbps_weight_bundle_sha256 <- digest::digest(
  vapply(cbps_weight_files, tools::md5sum, character(1)),
  algo = "sha256", serialize = TRUE
)
write_csv(manifest_base, "cbps_manifest.csv")
message("CBPS robustness estimation complete: ", manifest_base$status)
