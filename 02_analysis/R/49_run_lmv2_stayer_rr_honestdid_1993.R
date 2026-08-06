# ============================================================================
# Amended 1993--2010 initially retained joint-holdout HonestDiD sensitivity
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) return(default)
  sub(paste0("^--", name, "="), "", hit[[1L]])
}

P6_ROOT <- normalizePath(".", winslash = "/", mustWork = TRUE)
THESIS_ROOT <- normalizePath(
  file.path(P6_ROOT, "..", ".."), winslash = "/", mustWork = TRUE)
P4_ROOT <- normalizePath(
  file.path(THESIS_ROOT, ".worktrees", "lmv2-p4-ebal"),
  winslash = "/", mustWork = TRUE)
BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
.libPaths(unique(c(file.path(THESIS_ROOT, ".r_libs"), .libPaths())))

required_packages <- c(
  "DBI", "duckdb", "digest", "Matrix", "HonestDiD", "fixest",
  "fwildclusterboot", "dqrng", "ggplot2")
for (package in required_packages) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}
if (!identical(as.character(utils::packageVersion("HonestDiD")), "0.2.8")) {
  stop("This frozen package requires HonestDiD 0.2.8")
}

bootstrap_reps <- as.integer(arg("bootstrap-reps", "9999"))
if (is.na(bootstrap_reps) || bootstrap_reps < 999L) {
  stop("--bootstrap-reps must be at least 999")
}
OUT_DIR <- arg(
  "output-dir",
  file.path(
    BASE, "output", "audit", "local_match_v2_1993_amendment",
    "P5B_STAYER_RR_RM_HOLDOUT_M3_M2"))
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
OUT_DIR <- normalizePath(OUT_DIR, winslash = "/", mustWork = TRUE)

FREEZE_PATH <- normalizePath(
  file.path(
    BASE, "notes", "local_match_v2_1993_stayer_rr_honestdid_freeze.md"),
  winslash = "/", mustWork = TRUE)
S3_DIR <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "P5B_STAYER_S3")
S3_WEIGHTS <- normalizePath(
  file.path(S3_DIR, "s3_production_weights.parquet"),
  winslash = "/", mustWork = TRUE)
S3_MANIFEST <- normalizePath(
  file.path(S3_DIR, "s3_manifest.csv"), winslash = "/", mustWork = TRUE)
S3_CERTIFICATION <- normalizePath(
  file.path(S3_DIR, "s3_certification.csv"),
  winslash = "/", mustWork = TRUE)
PANEL_DIR <- normalizePath(
  file.path(
    BASE, "output", "audit", "local_match_v2_1993_amendment",
    "P6_P5C_COUNT_ACTIVE", "panel_matched"),
  winslash = "/", mustWork = TRUE)
P6_MANIFEST_PATH <- normalizePath(
  file.path(dirname(PANEL_DIR), "p6_manifest.csv"),
  winslash = "/", mustWork = TRUE)
FULL_RR_DIR <- normalizePath(
  file.path(
    BASE, "output", "audit", "local_match_v2_1993_amendment",
    "P6_RR_RM_HOLDOUT_M3_M2"),
  winslash = "/", mustWork = TRUE)
OLD_STAYER_RR_DIR <- normalizePath(
  file.path(
    THESIS_ROOT, ".worktrees", "lmv2-p6-outcomes", "02_analysis",
    "output", "audit", "local_match_v2",
    "P5B_STAYER_RR_RM_HOLDOUT_M3_M2"),
  winslash = "/", mustWork = TRUE)

atomic_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temp <- paste0(path, ".tmp")
  utils::write.csv(x, temp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temp, path)) stop("Could not publish ", path)
  invisible(path)
}

atomic_parquet <- function(con, x, path, order_by) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temp <- paste0(path, ".tmp.parquet")
  if (file.exists(temp)) file.remove(temp)
  duckdb::duckdb_register(con, "stayer_rr_write_rows", x)
  on.exit(try(
    duckdb::duckdb_unregister(con, "stayer_rr_write_rows"), silent = TRUE),
    add = TRUE)
  DBI::dbExecute(con, sprintf(
    "COPY (SELECT * FROM stayer_rr_write_rows ORDER BY %s)
     TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    order_by, DBI::dbQuoteString(con, temp)))
  duckdb::duckdb_unregister(con, "stayer_rr_write_rows")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temp, path)) stop("Could not publish ", path)
  invisible(path)
}

matrix_csv <- function(x, periods, path) {
  labels <- paste0(ifelse(periods < 0, "m", "p"), abs(periods))
  out <- data.frame(event_time_row = periods, x, check.names = FALSE)
  colnames(out)[-1L] <- labels
  atomic_csv(out, path)
}

# Certified input gates.
s3_certification <- utils::read.csv(
  S3_CERTIFICATION, stringsAsFactors = FALSE)
if (!nrow(s3_certification) || !all(s3_certification$pass)) {
  stop("S3 certification is missing or contains a failed check")
}
s3_manifest <- utils::read.csv(S3_MANIFEST, stringsAsFactors = FALSE)
s3_manifest_row <- s3_manifest[
  s3_manifest$artifact == basename(S3_WEIGHTS), , drop = FALSE]
s3_hash <- digest::digest(file = S3_WEIGHTS, algo = "sha256")
if (nrow(s3_manifest_row) != 1L ||
    !identical(s3_hash, s3_manifest_row$sha256[[1L]])) {
  stop("S3 production weights do not match the certified manifest")
}

# Load the certified P4 hierarchy without altering its source.
old_wd <- getwd()
setwd(P4_ROOT)
source(file.path("02_analysis", "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path("02_analysis", "R", "18j_lmv2_p5_newton_solver.R"))
lmv2_install_p5_newton_solver()
setwd(old_wd)
BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)

count_constrained <- paste0("patent_count_m", c(5, 4, 1))
active_constrained <- paste0("active_patenting_m", c(5, 4, 1))
held_out_vars <- c(
  "patent_count_m3", "active_patenting_m3",
  "patent_count_m2", "active_patenting_m2")
retained_vars <- c("career_age", "focal_group_exclusivity")
firm_vars <- c(
  "firm_log_patent_stock_5y", "firm_log_inventor_count_5y")
inv_vars <- c(count_constrained, active_constrained, retained_vars)
balance_vars <- c(inv_vars, firm_vars)
if (length(intersect(balance_vars, held_out_vars))) {
  stop("Held-out annual outcomes leaked into the balance vector")
}

balance_table <- function(x, weight, variables, stage) {
  standardized <- lmv2_ebal_standardize_cohort(variables, x)
  use <- setdiff(variables, standardized$zero_variance)
  out <- if (length(use)) {
    lmv2_ebal_covariate_balance(use, standardized$data, x$D, weight)
  } else {
    data.frame(
      variable = character(), treated_mean = numeric(),
      control_mean = numeric(), difference = numeric(),
      abs_difference = numeric())
  }
  out$stage <- stage
  out
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")

source_roster <- DBI::dbGetQuery(con, sprintf(
  "SELECT * FROM read_parquet(%s)
   WHERE spec='primary_count_active_scale'
   ORDER BY cohort,deal_id,treated DESC,codinv,control_group",
  DBI::dbQuoteString(con, S3_WEIGHTS)))
source_checks <- data.frame(
  rows = nrow(source_roster),
  treated_rows = sum(source_roster$treated == 1L),
  treated_deals = length(unique(
    source_roster$deal_id[source_roster$treated == 1L])),
  cohorts = length(unique(source_roster$cohort)),
  stringsAsFactors = FALSE)
if (source_checks$rows != 45270L || source_checks$treated_rows != 2792L ||
    source_checks$treated_deals != 153L || source_checks$cohorts != 18L) {
  stop("Frozen selected-stayer source identity failed")
}

solve_cohort <- function(cohort) {
  x <- source_roster[source_roster$cohort == cohort, , drop = FALSE]
  all_vars <- c(balance_vars, held_out_vars)
  if (any(vapply(x[all_vars], function(z) any(!is.finite(z)), logical(1)))) {
    stop("Non-finite balance input in cohort ", cohort)
  }
  roster <- data.frame(
    D = as.integer(x$treated),
    cohort = as.integer(x$cohort),
    deal_id = as.integer(x$deal_id),
    treated_codinv = ifelse(x$treated == 1L, x$codinv, NA_real_),
    control_codinv = ifelse(x$treated == 0L, x$codinv, NA_real_),
    control_group = ifelse(x$treated == 0L, x$control_group, NA_real_),
    base_weight = x$base_weight,
    x[all_vars],
    check.names = FALSE)
  hierarchy <- lmv2_ebal_cohort_feasibility_hierarchy(
    roster = roster,
    n_eligible_treated = sum(roster$D == 1L),
    inv_vars = inv_vars,
    firm_vars = firm_vars)
  feasible <- hierarchy$mode %in% c(
    "exact_ebal", "optweight_0.05", "optweight_0.10") &&
    !is.null(hierarchy$result)
  if (!feasible) {
    stop("Selected-stayer joint holdout infeasible in cohort ", cohort,
         " (", hierarchy$mode, ")")
  }
  final_weight <- as.numeric(hierarchy$result$weight)
  treated <- roster$D == 1L
  lmv2_ebal_assert_final_treated_weights_equal_base(
    final_weight[treated], roster$base_weight[treated])
  lmv2_ebal_assert_masses_agree(
    final_weight[treated], final_weight[!treated],
    scheme = "primary",
    n_retained_deals = length(unique(roster$deal_id[treated])))

  before <- balance_table(
    roster, roster$base_weight, balance_vars, "constrained_before")
  after <- balance_table(
    roster, final_weight, balance_vars, "constrained_after")
  held <- balance_table(
    roster, final_weight, held_out_vars, "held_out_after")
  balance <- rbind(before, after, held)
  balance$cohort <- cohort
  tolerance <- switch(
    hierarchy$mode,
    exact_ebal = 2e-5,
    optweight_0.05 = 0.05 + 1e-8,
    optweight_0.10 = 0.10 + 1e-8)
  if (length(after$abs_difference) &&
      max(after$abs_difference, na.rm = TRUE) > tolerance) {
    stop("Realized balance exceeds solver rung in cohort ", cohort)
  }

  weights <- data.frame(
    cohort = as.integer(x$cohort),
    deal_id = as.integer(x$deal_id),
    codinv = as.numeric(x$codinv),
    treated = as.integer(x$treated),
    control_group = as.numeric(x$control_group),
    base_weight = as.numeric(x$base_weight),
    source_final_weight = as.numeric(x$final_weight),
    weight = final_weight,
    stringsAsFactors = FALSE)
  concentration <- hierarchy$ess_info$reuse_adjusted_concentration
  diagnostics <- data.frame(
    cohort = cohort,
    mode = hierarchy$mode,
    tier = hierarchy$tier,
    n_treated = sum(treated),
    n_control_rows = sum(!treated),
    reuse_adjusted_ess = hierarchy$ess_info$reuse_adjusted_ess,
    reuse_adjusted_ess_ratio = hierarchy$ess_gate$ess_ratio,
    maximum_control_inventor_share = concentration$max_share,
    top5_control_inventor_share = concentration$top5_share,
    max_constrained_smd = max(after$abs_difference, na.rm = TRUE),
    patent_count_m3_gap = held$difference[
      held$variable == "patent_count_m3"],
    patent_count_m2_gap = held$difference[
      held$variable == "patent_count_m2"],
    stringsAsFactors = FALSE)
  list(weights = weights, balance = balance, diagnostics = diagnostics)
}

message("Selected-stayer RR: solving 18 joint holdout cohorts")
solves <- lapply(1993:2010, function(cohort) {
  message("  cohort ", cohort)
  solve_cohort(cohort)
})
weights <- do.call(rbind, lapply(solves, `[[`, "weights"))
balance <- do.call(rbind, lapply(solves, `[[`, "balance"))
diagnostics <- do.call(rbind, lapply(solves, `[[`, "diagnostics"))
if (nrow(weights) != 45270L || sum(weights$treated == 1L) != 2792L ||
    length(unique(weights$deal_id[weights$treated == 1L])) != 153L ||
    !identical(sort(unique(weights$cohort)), 1993:2010)) {
  stop("Selected-stayer joint holdout roster identity failed")
}

weights_path <- file.path(OUT_DIR, "stayer_rr_holdout_m3_m2_weights.parquet")
atomic_parquet(
  con, weights, weights_path,
  "cohort,deal_id,treated DESC,codinv,control_group")
atomic_csv(balance, file.path(OUT_DIR, "stayer_rr_holdout_balance.csv"))
atomic_csv(
  diagnostics, file.path(OUT_DIR, "stayer_rr_holdout_diagnostics.csv"))

# Map the selected-stayer weights into the unchanged P6 panel.
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
panel_files <- file.path(
  PANEL_DIR, sprintf("lmv2_event_panel_c%d.parquet", 1993:2010))
if (any(!file.exists(panel_files))) stop("Certified P6 shards are missing")
panel_source <- lmv2_panel_sql(panel_files)
DBI::dbExecute(con, sprintf(
  "CREATE OR REPLACE TEMP TABLE stayer_rr_base_outcomes AS
   SELECT roster_row_id,CAST(deal_id AS INTEGER) deal_id,
          CAST(cohort AS INTEGER) cohort,arm,CAST(codinv AS BIGINT) codinv,
          CAST(focal_group_1 AS BIGINT) focal_group_1,
          CAST(event_time AS INTEGER) event_time,
          CAST(patent_count AS DOUBLE) patent_count
   FROM %s", panel_source))
DBI::dbExecute(con, sprintf(
  "CREATE OR REPLACE TEMP TABLE stayer_rr_weights AS
   SELECT * FROM read_parquet(%s)", DBI::dbQuoteString(con, weights_path)))
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE stayer_rr_unit_map AS
  WITH base_units AS (
    SELECT roster_row_id,deal_id,cohort,arm,codinv,focal_group_1
    FROM stayer_rr_base_outcomes WHERE event_time=-1
  ), treated_map AS (
    SELECT b.roster_row_id,w.weight
    FROM stayer_rr_weights w JOIN base_units b
      ON w.cohort=b.cohort AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv AND b.arm='treated'
    WHERE w.treated=1
  ), control_map AS (
    SELECT b.roster_row_id,w.weight
    FROM stayer_rr_weights w JOIN base_units b
      ON w.cohort=b.cohort AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv AND w.control_group=b.focal_group_1
     AND b.arm='control'
    WHERE w.treated=0
  )
  SELECT * FROM treated_map UNION ALL SELECT * FROM control_map")
mapping_checks <- DBI::dbGetQuery(con, "
  SELECT
    (SELECT COUNT(*) FROM stayer_rr_weights) weight_rows,
    (SELECT COUNT(*) FROM stayer_rr_unit_map) mapped_rows,
    (SELECT COUNT(*)-COUNT(DISTINCT roster_row_id)
       FROM stayer_rr_unit_map) duplicate_maps,
    (SELECT COUNT(*) FROM stayer_rr_unit_map m
       JOIN stayer_rr_base_outcomes p USING(roster_row_id)) panel_rows")
mapping_checks$pass <-
  mapping_checks$weight_rows == 45270L &&
  mapping_checks$mapped_rows == 45270L &&
  mapping_checks$duplicate_maps == 0L &&
  mapping_checks$panel_rows == 11L * 45270L
if (!isTRUE(mapping_checks$pass[[1L]])) {
  stop("Selected-stayer weights failed the P6 panel mapping contract")
}
atomic_csv(mapping_checks, file.path(OUT_DIR, "stayer_rr_panel_mapping.csv"))
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE stayer_rr_panel AS
  SELECT p.roster_row_id,p.deal_id,p.cohort,p.arm,p.codinv,p.event_time,
         m.weight,p.patent_count
  FROM stayer_rr_base_outcomes p
  JOIN stayer_rr_unit_map m USING(roster_row_id)")

estimate_sample <- function(sample_id, cohorts) {
  message("Selected-stayer RR: estimating ", sample_id)
  pair_table <- lmv2_build_pair_table(
    con, "stayer_rr_panel", "patent_count", cohorts, sample_id)
  influence_table <- lmv2_prepare_influence_table(
    con, pair_table, "stayer_rr_panel", cohorts)
  coverage <- lmv2_pair_coverage(
    con, pair_table, "stayer_rr_panel", cohorts,
    "patent_count", sample_id)
  DBI::dbExecute(con, sprintf("DROP TABLE %s", pair_table))
  event <- lmv2_event_estimates(
    con, influence_table, "patent_count", sample_id)
  covariance <- lmv2_two_way_covariance(
    con, influence_table, event$event_time)
  dynamic <- lmv2_dynamic_results(event, covariance)

  pre_keep <- match(c(-3L, -2L), event$event_time)
  b_pre <- event$estimate[pre_keep]
  v_pre <- covariance$two_way[pre_keep, pre_keep, drop = FALSE]
  pre_wald <- as.numeric(t(b_pre) %*% solve(v_pre, b_pre))
  pretest <- data.frame(
    sample = sample_id, periods = "-3;-2", statistic = pre_wald,
    df = 2L, p_value = stats::pchisq(pre_wald, 2L, lower.tail = FALSE))

  post_keep <- match(1:5, event$event_time)
  post_estimate <- mean(event$estimate[post_keep])
  compact <- lmv2_compact_post_regression(con, influence_table, post_estimate)
  wild <- lmv2_wild_post(compact$model, bootstrap_reps)
  two_way <- lmv2_cluster_post(
    event, covariance, "two_way", "two_way_deal_inventor")
  deal <- lmv2_cluster_post(
    event, covariance, "deal", "deal_cluster_robust")
  headline <- rbind(wild, two_way, deal)
  headline$sample <- sample_id
  headline$outcome <- "patent_count"
  headline$summary <- "average_annual_t1_to_t5"

  atomic_csv(
    dynamic, file.path(OUT_DIR, paste0("stayer_rr_dynamic_", sample_id, ".csv")))
  atomic_csv(
    headline, file.path(OUT_DIR, paste0("stayer_rr_headline_", sample_id, ".csv")))
  atomic_csv(
    pretest, file.path(OUT_DIR, paste0("stayer_rr_pretrend_", sample_id, ".csv")))
  atomic_csv(
    coverage, file.path(OUT_DIR, paste0("stayer_rr_coverage_", sample_id, ".csv")))
  matrix_csv(
    covariance$two_way, event$event_time,
    file.path(OUT_DIR, paste0(
      "stayer_rr_covariance_two_way_", sample_id, ".csv")))
  matrix_csv(
    covariance$deal, event$event_time,
    file.path(OUT_DIR, paste0(
      "stayer_rr_covariance_deal_", sample_id, ".csv")))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
  list(
    event = event, covariance = covariance, headline = headline,
    pretest = pretest, post_estimate = post_estimate)
}

fits <- list(
  full_1993_2010 = estimate_sample("full_1993_2010", 1993:2010),
  reproduction_1994_2010 = estimate_sample(
    "reproduction_1994_2010", 1994:2010))
DBI::dbDisconnect(con, shutdown = TRUE)
on.exit(NULL, add = FALSE)

prepare_sigma <- function(sigma, sample_id, covariance_id) {
  sigma <- (sigma + t(sigma)) / 2
  min_before <- min(eigen(sigma, symmetric = TRUE, only.values = TRUE)$values)
  repaired <- min_before < -1e-10
  used <- if (repaired) {
    as.matrix(Matrix::nearPD(
      sigma, corr = FALSE, keepDiag = TRUE)$mat)
  } else sigma
  min_after <- min(eigen(used, symmetric = TRUE, only.values = TRUE)$values)
  diagnostics <- data.frame(
    sample = sample_id, covariance = covariance_id,
    minimum_eigenvalue_before = min_before,
    repaired = repaired,
    maximum_absolute_entry_change = max(abs(used - sigma)),
    minimum_eigenvalue_after = min_after,
    stringsAsFactors = FALSE)
  list(sigma = used, diagnostics = diagnostics)
}

rr_grid <- function(beta, sigma, mbar, grid_points) {
  HonestDiD::createSensitivityResults_relativeMagnitudes(
    betahat = beta,
    sigma = sigma,
    numPrePeriods = 2L,
    numPostPeriods = 6L,
    bound = "deviation from parallel trends",
    method = "C-LF",
    Mbarvec = mbar,
    l_vec = c(0, rep(0.2, 5)),
    alpha = 0.05,
    gridPoints = grid_points,
    parallel = FALSE,
    seed = 20260803L)
}

first_crossing <- function(x) {
  hit <- x$Mbar[x$ub >= 0]
  if (length(hit)) min(hit) else NA_real_
}

run_rr <- function(fit, sample_id, covariance_id) {
  select_periods <- c(-3L, -2L, 0:5)
  keep <- match(select_periods, fit$event$event_time)
  if (anyNA(keep)) stop("Selected-stayer RR coefficient periods are incomplete")
  beta <- fit$event$estimate[keep]
  covariance_raw <- fit$covariance[[covariance_id]][keep, keep, drop = FALSE]
  prepared <- prepare_sigma(covariance_raw, sample_id, covariance_id)
  sigma <- prepared$sigma
  l_vec <- c(0, rep(0.2, 5))
  extracted_post <- sum(l_vec * beta[3:8])
  if (abs(extracted_post - fit$post_estimate) > 1e-10) {
    stop("Selected-stayer RR extractor does not reproduce the post aggregate")
  }
  original <- as.data.frame(HonestDiD::constructOriginalCS(
    betahat = beta, sigma = sigma,
    numPrePeriods = 2L, numPostPeriods = 6L,
    l_vec = l_vec, alpha = 0.05))
  original$sample <- sample_id
  original$covariance <- covariance_id

  message("Selected-stayer RR: coarse grid ", sample_id, " / ", covariance_id)
  coarse <- as.data.frame(rr_grid(beta, sigma, seq(0, 0.50, 0.05), 200L))
  coarse$stage <- "coarse_200"
  crossing <- first_crossing(coarse)
  if (is.na(crossing)) {
    extension <- as.data.frame(rr_grid(
      beta, sigma, seq(0.55, 1.00, 0.05), 200L))
    extension$stage <- "extension_200"
    coarse <- rbind(coarse, extension)
    crossing <- first_crossing(coarse)
  }
  if (is.na(crossing)) stop("No selected-stayer sign crossing through Mbar=1")
  previous <- max(coarse$Mbar[coarse$Mbar < crossing], 0)
  fine_m <- seq(previous, crossing, by = 0.005)
  if (tail(fine_m, 1L) < crossing - 1e-12) fine_m <- c(fine_m, crossing)
  fine500 <- as.data.frame(rr_grid(beta, sigma, fine_m, 500L))
  fine500$stage <- "refined_500"
  fine1000 <- as.data.frame(rr_grid(beta, sigma, fine_m, 1000L))
  fine1000$stage <- "stability_1000"
  breakdown500 <- first_crossing(fine500)
  breakdown1000 <- first_crossing(fine1000)
  stable <- is.finite(breakdown500) && is.finite(breakdown1000) &&
    abs(breakdown500 - breakdown1000) <= 0.01 + 1e-12
  if (!stable) stop("Selected-stayer breakdown failed grid stability gate")

  pre_scale <- max(abs(beta[[2L]] - beta[[1L]]), abs(beta[[2L]]))
  summary <- data.frame(
    sample = sample_id,
    covariance = covariance_id,
    beta_m3 = beta[[1L]],
    beta_m2 = beta[[2L]],
    maximum_pre_first_difference = pre_scale,
    post_average = fit$post_estimate,
    cumulative_five_year = 5 * fit$post_estimate,
    original_lb = original$lb[[1L]],
    original_ub = original$ub[[1L]],
    breakdown_mbar_500 = breakdown500,
    breakdown_mbar_1000 = breakdown1000,
    breakdown_grid_stable_within_0_01 = stable,
    worst_case_average_bias_at_breakdown =
      4 * pre_scale * breakdown1000,
    covariance_repaired = prepared$diagnostics$repaired,
    stringsAsFactors = FALSE)
  results <- rbind(coarse, fine500, fine1000)
  results$sample <- sample_id
  results$covariance <- covariance_id
  list(
    results = results,
    original = original,
    summary = summary,
    covariance_diagnostics = prepared$diagnostics,
    beta = data.frame(
      sample = sample_id, covariance = covariance_id,
      event_time = select_periods, estimate = beta))
}

rr <- list()
for (sample_id in names(fits)) {
  for (covariance_id in c("two_way", "deal")) {
    key <- paste(sample_id, covariance_id, sep = "__")
    rr[[key]] <- run_rr(fits[[sample_id]], sample_id, covariance_id)
  }
}
rr_results <- do.call(rbind, lapply(rr, `[[`, "results"))
rr_original <- do.call(rbind, lapply(rr, `[[`, "original"))
rr_summary <- do.call(rbind, lapply(rr, `[[`, "summary"))
rr_covariance_diagnostics <- do.call(
  rbind, lapply(rr, `[[`, "covariance_diagnostics"))
rr_beta <- do.call(rbind, lapply(rr, `[[`, "beta"))
atomic_csv(
  rr_results, file.path(OUT_DIR, "stayer_rr_sensitivity_grid.csv"))
atomic_csv(
  rr_original, file.path(OUT_DIR, "stayer_rr_original_confidence_sets.csv"))
atomic_csv(
  rr_summary, file.path(OUT_DIR, "stayer_rr_breakdown_summary.csv"))
atomic_csv(
  rr_covariance_diagnostics,
  file.path(OUT_DIR, "stayer_rr_covariance_diagnostics.csv"))
atomic_csv(
  rr_beta, file.path(OUT_DIR, "stayer_rr_coefficient_vector.csv"))

# Primary selected-stayer sensitivity figure.
source(file.path(BASE, "R", "00_lmv2_visual_style.R"))
primary <- rr_results[
  rr_results$sample == "full_1993_2010" &
    rr_results$covariance == "two_way" &
    (rr_results$stage == "stability_1000" |
       (rr_results$stage == "coarse_200" & rr_results$Mbar == 0)),
  , drop = FALSE]
if (length(unique(primary$Mbar)) == 1L) {
  primary <- rr_results[
    rr_results$sample == "full_1993_2010" &
      rr_results$covariance == "two_way" &
      rr_results$stage == "coarse_200" & rr_results$Mbar <= 0.10,
    , drop = FALSE]
}
primary <- primary[order(primary$Mbar), , drop = FALSE]
primary_original <- rr_original[
  rr_original$sample == "full_1993_2010" &
    rr_original$covariance == "two_way", , drop = FALSE]
plot <- ggplot2::ggplot(primary, ggplot2::aes(x = Mbar)) +
  ggplot2::geom_hline(yintercept = 0, colour = "#6E6E6E", linewidth = 0.4) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = lb, ymax = ub),
    fill = "#8FB9AD", alpha = 0.35) +
  ggplot2::geom_line(
    ggplot2::aes(y = lb), colour = "#285D55", linewidth = 0.8) +
  ggplot2::geom_line(
    ggplot2::aes(y = ub), colour = "#285D55", linewidth = 0.8) +
  ggplot2::geom_segment(
    data = primary_original,
    ggplot2::aes(x = 0, xend = 0, y = lb, yend = ub),
    inherit.aes = FALSE, colour = "#B05A47", linewidth = 1.0) +
  ggplot2::labs(
    title = "Initially retained inventor sensitivity",
    subtitle = "Rambachan--Roth relative magnitudes; analytic two-way covariance",
    x = expression(bar(M)),
    y = "95% robust confidence set for average ATT, years +1 to +5") +
  lmv2_theme()
lmv2_save_figure(
  plot, file.path(OUT_DIR, "figure_stayer_rr_relative_magnitudes"),
  width = 7.1, height = 4.6, dpi = 320)

# Internal reproduction check; the former sample is not co-reported.
old_dynamic <- utils::read.csv(
  file.path(OLD_STAYER_RR_DIR, "stayer_rr_dynamic_full_1994_2010.csv"),
  stringsAsFactors = FALSE)
new_dynamic <- utils::read.csv(
  file.path(OUT_DIR, "stayer_rr_dynamic_reproduction_1994_2010.csv"),
  stringsAsFactors = FALSE)
dynamic_compare <- merge(
  old_dynamic[c("event_time", "estimate")],
  new_dynamic[c("event_time", "estimate")],
  by = "event_time", suffixes = c("_frozen", "_amended"), all = TRUE)
if (nrow(dynamic_compare) != 11L || anyNA(dynamic_compare)) {
  stop("Incumbent stayer RR dynamic reproduction is incomplete")
}
dynamic_compare$absolute_difference <- abs(
  dynamic_compare$estimate_amended - dynamic_compare$estimate_frozen)
old_summary <- utils::read.csv(
  file.path(OLD_STAYER_RR_DIR, "stayer_rr_breakdown_summary.csv"),
  stringsAsFactors = FALSE)
old_summary <- old_summary[
  old_summary$sample == "full_1994_2010", , drop = FALSE]
new_summary <- rr_summary[
  rr_summary$sample == "reproduction_1994_2010", , drop = FALSE]
summary_compare <- merge(
  old_summary, new_summary, by = "covariance",
  suffixes = c("_frozen", "_amended"), all = TRUE)
if (nrow(summary_compare) != 2L || anyNA(summary_compare$covariance)) {
  stop("Incumbent stayer RR summary reproduction is incomplete")
}
summary_compare$maximum_event_estimate_difference <-
  max(dynamic_compare$absolute_difference)
summary_compare$post_average_difference <- abs(
  summary_compare$post_average_amended - summary_compare$post_average_frozen)
summary_compare$breakdown_difference <- abs(
  summary_compare$breakdown_mbar_1000_amended -
    summary_compare$breakdown_mbar_1000_frozen)
summary_compare$pass <-
  summary_compare$maximum_event_estimate_difference <= 0.001 &
  summary_compare$post_average_difference <= 0.001 &
  summary_compare$breakdown_difference <= 0.01 + 1e-12
atomic_csv(
  dynamic_compare, file.path(OUT_DIR, "stayer_rr_reproduction_dynamic.csv"))
atomic_csv(
  summary_compare, file.path(OUT_DIR, "stayer_rr_reproduction_summary.csv"))

# Terminal certification and provenance.
certification <- data.frame(
  check = c(
    "s3_source_hash_matches", "source_rows_45270",
    "treated_rows_2792", "treated_deals_153", "eighteen_cohorts",
    "all_weight_cells_feasible", "held_out_not_constrained",
    "panel_mapping_pass", "four_rr_specifications",
    "all_breakdowns_grid_stable", "all_coefficient_vectors_have_8_rows",
    "incumbent_reproduction_within_tolerance",
    "honestdid_version_0_2_8"),
  pass = c(
    identical(s3_hash, s3_manifest_row$sha256[[1L]]),
    nrow(weights) == 45270L,
    sum(weights$treated == 1L) == 2792L,
    length(unique(weights$deal_id[weights$treated == 1L])) == 153L,
    identical(sort(unique(weights$cohort)), 1993:2010),
    all(diagnostics$mode %in% c(
      "exact_ebal", "optweight_0.05", "optweight_0.10")),
    !length(intersect(balance_vars, held_out_vars)),
    isTRUE(mapping_checks$pass[[1L]]),
    nrow(rr_summary) == 4L,
    all(rr_summary$breakdown_grid_stable_within_0_01),
    all(table(rr_beta$sample, rr_beta$covariance) == 8L),
    all(summary_compare$pass),
    identical(as.character(utils::packageVersion("HonestDiD")), "0.2.8")),
  stringsAsFactors = FALSE)
atomic_csv(
  certification, file.path(OUT_DIR, "stayer_rr_certification.csv"))
if (!all(certification$pass)) {
  stop("Selected-stayer RR certification failed: ",
       paste(certification$check[!certification$pass], collapse = ", "))
}

source_files <- c(
  runner = file.path(
    BASE, "R", "49_run_lmv2_stayer_rr_honestdid_1993.R"),
  freeze = FREEZE_PATH,
  p4_cohort_core = file.path(
    P4_ROOT, "02_analysis", "R", "17m_lmv2_p4_cohort_hybrid_core.R"),
  p4_newton = file.path(
    P4_ROOT, "02_analysis", "R", "18j_lmv2_p5_newton_solver.R"),
  p6_estimation_core = file.path(
    BASE, "R", "19b_lmv2_p6_estimation_core.R"),
  s3_weights = S3_WEIGHTS,
  s3_manifest = S3_MANIFEST,
  p6_manifest = P6_MANIFEST_PATH,
  full_rr = file.path(FULL_RR_DIR, "rr_breakdown_summary.csv"),
  frozen_stayer_rr_summary = file.path(
    OLD_STAYER_RR_DIR, "stayer_rr_breakdown_summary.csv"),
  frozen_stayer_rr_dynamic = file.path(
    OLD_STAYER_RR_DIR, "stayer_rr_dynamic_full_1994_2010.csv"))
manifest <- data.frame(
  package = "lmv2_stayer_rr_rm_holdout_m3_m2_1993_amendment_v1",
  completed_at = as.character(Sys.time()),
  bootstrap_replications = bootstrap_reps,
  honestdid_version = as.character(utils::packageVersion("HonestDiD")),
  freeze_sha256 = digest::digest(file = FREEZE_PATH, algo = "sha256"),
  runner_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "49_run_lmv2_stayer_rr_honestdid_1993.R"),
    algo = "sha256"),
  source_s3_weights_sha256 = s3_hash,
  weights_sha256 = digest::digest(file = weights_path, algo = "sha256"),
  breakdown_sha256 = digest::digest(
    file = file.path(OUT_DIR, "stayer_rr_breakdown_summary.csv"),
    algo = "sha256"),
  reproduction_sha256 = digest::digest(
    file = file.path(OUT_DIR, "stayer_rr_reproduction_summary.csv"),
    algo = "sha256"),
  source_bundle_sha256 = digest::digest(
    vapply(source_files, digest::digest, character(1),
           file = TRUE, algo = "sha256"), algo = "sha256"),
  certification_pass = TRUE,
  stringsAsFactors = FALSE)
atomic_csv(manifest, file.path(OUT_DIR, "stayer_rr_manifest.csv"))

print(rr_summary)
message("Selected-stayer RR package certified: ", OUT_DIR)
