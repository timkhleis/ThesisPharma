# ============================================================================
# Amended 1993--2010 joint holdout (-3,-2) Rambachan--Roth sensitivity
# ============================================================================
# Additive package: reuses the frozen P5c support roster and P6 outcomes,
# re-solves one cohort-level weight vector, and leaves headline artifacts
# unchanged.

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) return(default)
  sub(paste0("^--", name, "="), "", hit[[1L]])
}

THESIS_ROOT <- normalizePath(".", winslash = "/", mustWork = TRUE)
P6_ROOT <- THESIS_ROOT
P4_ROOT <- THESIS_ROOT
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
    "P6_RR_RM_HOLDOUT_M3_M2"))
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
OUT_DIR <- normalizePath(OUT_DIR, winslash = "/", mustWork = TRUE)

FREEZE_PATH <- normalizePath(
  file.path(
    BASE, "notes", "local_match_v2_1993_rr_honestdid_freeze.md"),
  winslash = "/", mustWork = TRUE)
P4_WEIGHT_DIR <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "P5C_ANNUAL_TRAJECTORY", "production", "weights")
P4_BASE_HANDOFF <- normalizePath(
  file.path(
    BASE, "output", "audit", "local_match_v2_1993_amendment",
    "P5C_P6_HANDOFF",
    "p5c_p6_primary_weighted_roster.parquet"),
  winslash = "/", mustWork = TRUE)
PANEL_DIR <- normalizePath(
  file.path(
    BASE, "output", "audit", "local_match_v2_1993_amendment",
    "P6_P5C_COUNT_ACTIVE", "panel_matched"),
  winslash = "/", mustWork = TRUE)
P6_MANIFEST_PATH <- normalizePath(
  file.path(dirname(PANEL_DIR), "p6_manifest.csv"),
  winslash = "/", mustWork = TRUE)
OLD_RR_DIR <- normalizePath(
  file.path(
    BASE, "output", "audit", "local_match_v2",
    "P6_RR_RM_HOLDOUT_M3_M2"),
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
  duckdb::duckdb_register(con, "rr_write_rows", x)
  on.exit(try(
    duckdb::duckdb_unregister(con, "rr_write_rows"), silent = TRUE),
    add = TRUE)
  DBI::dbExecute(con, sprintf(
    "COPY (SELECT * FROM rr_write_rows ORDER BY %s)
     TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    order_by, DBI::dbQuoteString(con, temp)))
  duckdb::duckdb_unregister(con, "rr_write_rows")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temp, path)) stop("Could not publish ", path)
  invisible(path)
}

matrix_csv <- function(x, periods, path) {
  names <- paste0(ifelse(periods < 0, "m", "p"), abs(periods))
  out <- data.frame(event_time_row = periods, x, check.names = FALSE)
  colnames(out)[-1L] <- names
  atomic_csv(out, path)
}

weighted_mean <- function(x, w) sum(x * w) / sum(w)

# Load the certified P4 hierarchy without changing any P4 source.
old_wd <- getwd()
setwd(P4_ROOT)
source(file.path("02_analysis", "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path("02_analysis", "R", "18j_lmv2_p5_newton_solver.R"))
lmv2_install_p5_newton_solver()
setwd(old_wd)
BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)

p6_manifest <- utils::read.csv(
  P6_MANIFEST_PATH, stringsAsFactors = FALSE)
if (nrow(p6_manifest) != 1L ||
    !nzchar(p6_manifest$p5c_execution_hash[[1L]])) {
  stop("Certified P6 P5c manifest is missing or invalid")
}
p5c_hash <- p6_manifest$p5c_execution_hash[[1L]]
p5c_hash_stub <- substr(p5c_hash, 1L, 12L)

count_constrained <- paste0("patent_count_m", c(5, 4, 1))
active_constrained <- paste0("active_patenting_m", c(5, 4, 1))
held_out_vars <- c(
  "patent_count_m3", "active_patenting_m3",
  "patent_count_m2", "active_patenting_m2")
retained_vars <- c("career_age", "focal_group_exclusivity")
firm_vars <- c(
  "firm_log_patent_stock_5y", "firm_log_inventor_count_5y",
  "firm_patent_trajectory")
inv_vars <- c(count_constrained, active_constrained, retained_vars)
balance_vars <- c(inv_vars, firm_vars)
if (length(intersect(balance_vars, held_out_vars))) {
  stop("Held-out annual outcomes leaked into the balance vector")
}

balance_table <- function(x, weight, variables, stage) {
  standardized <- lmv2_ebal_standardize_cohort(variables, x)
  use <- setdiff(variables, standardized$zero_variance)
  out <- if (length(use)) {
    lmv2_ebal_covariate_balance(
      use, standardized$data, x$D, weight)
  } else {
    data.frame(
      variable = character(), treated_mean = numeric(),
      control_mean = numeric(), difference = numeric(),
      abs_difference = numeric())
  }
  out$stage <- stage
  out
}

read_cohort_roster <- function(con, cohort) {
  pattern <- sprintf(
    "^c%d_primary_count_active_%s[.]parquet$", cohort, p5c_hash_stub)
  paths <- list.files(P4_WEIGHT_DIR, pattern = pattern, full.names = TRUE)
  if (length(paths) != 1L) {
    stop("Expected one certified P5c weight file for cohort ", cohort)
  }
  x <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM read_parquet(%s) ORDER BY roster_row_id",
    DBI::dbQuoteString(con, normalizePath(
      paths, winslash = "/", mustWork = TRUE))))
  if (anyDuplicated(x$roster_row_id) || any(!x$treated %in% c(0L, 1L))) {
    stop("Invalid P5c source roster for cohort ", cohort)
  }
  x
}

solve_cohort <- function(con, cohort) {
  x <- read_cohort_roster(con, cohort)
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
    control_group = ifelse(x$treated == 0L, x$group_id, NA_real_),
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
    stop("Joint holdout solve infeasible in cohort ", cohort,
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
  constrained_after <- after$abs_difference
  if (length(constrained_after) &&
      max(constrained_after, na.rm = TRUE) > tolerance) {
    stop("Realized balance exceeds solver rung in cohort ", cohort)
  }

  weights <- data.frame(
    roster_row_id = x$roster_row_id,
    cohort = cohort,
    deal_id = x$deal_id,
    arm = ifelse(treated, "treated", "control"),
    codinv = x$codinv,
    base_weight = x$base_weight,
    weight = final_weight,
    stringsAsFactors = FALSE)
  conc <- hierarchy$ess_info$reuse_adjusted_concentration
  diagnostics <- data.frame(
    cohort = cohort,
    mode = hierarchy$mode,
    tier = hierarchy$tier,
    n_treated = sum(treated),
    n_control_rows = sum(!treated),
    reuse_adjusted_ess = hierarchy$ess_info$reuse_adjusted_ess,
    reuse_adjusted_ess_ratio = hierarchy$ess_gate$ess_ratio,
    maximum_control_inventor_share = conc$max_share,
    top5_control_inventor_share = conc$top5_share,
    max_constrained_smd = max(constrained_after, na.rm = TRUE),
    patent_count_m3_gap = held$difference[
      held$variable == "patent_count_m3"],
    patent_count_m2_gap = held$difference[
      held$variable == "patent_count_m2"],
    stringsAsFactors = FALSE)
  list(weights = weights, balance = balance, diagnostics = diagnostics)
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")

message("RR package: solving 18 joint holdout cohorts")
solves <- lapply(1993:2010, function(cohort) {
  message("  cohort ", cohort)
  solve_cohort(con, cohort)
})
weights <- do.call(rbind, lapply(solves, `[[`, "weights"))
balance <- do.call(rbind, lapply(solves, `[[`, "balance"))
diagnostics <- do.call(rbind, lapply(solves, `[[`, "diagnostics"))
if (nrow(weights) != 512625L || anyDuplicated(weights$roster_row_id) ||
    !identical(sort(unique(weights$cohort)), 1993:2010)) {
  stop("Joint holdout roster identity failed")
}

weights_path <- file.path(OUT_DIR, "rr_holdout_m3_m2_weights.parquet")
atomic_parquet(con, weights, weights_path, "cohort,roster_row_id")
atomic_csv(balance, file.path(OUT_DIR, "rr_holdout_m3_m2_balance.csv"))
atomic_csv(
  diagnostics, file.path(OUT_DIR, "rr_holdout_m3_m2_diagnostics.csv"))

# Emit the established P5c/P6 handoff contract.
handoff_path <- file.path(
  OUT_DIR, "p5c_p6_primary_weighted_roster.parquet")
temp_handoff <- paste0(handoff_path, ".tmp.parquet")
if (file.exists(temp_handoff)) file.remove(temp_handoff)
DBI::dbExecute(con, sprintf(
  "COPY (
     SELECT b.* REPLACE (CAST(w.weight AS DOUBLE) AS weight)
     FROM read_parquet(%s) b
     JOIN read_parquet(%s) w USING(roster_row_id)
     ORDER BY b.cohort,b.deal_id,b.arm DESC,b.codinv,b.roster_row_id
   ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
  DBI::dbQuoteString(con, P4_BASE_HANDOFF),
  DBI::dbQuoteString(con, weights_path),
  DBI::dbQuoteString(con, temp_handoff)))
if (file.exists(handoff_path)) file.remove(handoff_path)
if (!file.rename(temp_handoff, handoff_path)) {
  stop("Could not publish RR P5c/P6 handoff")
}
handoff_checks <- DBI::dbGetQuery(con, sprintf(
  "SELECT COUNT(*) n,
          COUNT(*)-COUNT(DISTINCT roster_row_id) duplicate_ids,
          COUNT(*) FILTER(WHERE weight IS NULL OR NOT isfinite(weight)
                            OR weight<=0) bad_weights,
          COUNT(*) FILTER(WHERE arm='treated' AND weight<>1) bad_treated,
          COUNT(DISTINCT cohort) cohorts
   FROM read_parquet(%s)", DBI::dbQuoteString(con, handoff_path)))
if (handoff_checks$n != 512625L || handoff_checks$duplicate_ids != 0L ||
    handoff_checks$bad_weights != 0L || handoff_checks$bad_treated != 0L ||
    handoff_checks$cohorts != 18L) {
  stop("RR P5c/P6 handoff certification failed")
}
handoff_manifest <- data.frame(
  roster_sha256 = digest::digest(file = handoff_path, algo = "sha256"),
  roster_rows = 512625L,
  p5a_design_hash = digest::digest(
    list(source_p5c_execution_hash = p5c_hash,
         constrained_variables = balance_vars,
         held_out_variables = held_out_vars), algo = "sha256"),
  certification_pass = TRUE,
  production_freeze_hash = digest::digest(
    file = FREEZE_PATH, algo = "sha256"),
  handoff_source_sha256 = digest::digest(
    file = file.path(BASE, "R", "48_run_lmv2_rr_honestdid_1993.R"),
    algo = "sha256"),
  p5c_execution_hash = digest::digest(
    list(source = p5c_hash, balance = balance_vars), algo = "sha256"),
  p5c_variant = "holdout_m3_m2",
  source_p5a_roster_sha256 = digest::digest(
    file = P4_BASE_HANDOFF, algo = "sha256"),
  stringsAsFactors = FALSE)
atomic_csv(
  handoff_manifest, file.path(OUT_DIR, "p5c_p6_roster_manifest.csv"))

# Load the frozen P6 estimator and estimate the new weighted design directly
# through a row-identity join. No outcome panel is rebuilt.
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
panel_files <- file.path(
  PANEL_DIR, sprintf("lmv2_event_panel_c%d.parquet", 1993:2010))
if (any(!file.exists(panel_files))) stop("Certified P6 shards are missing")
panel_sql <- sprintf(
  "(SELECT p.* REPLACE (w.weight AS weight)
    FROM %s p JOIN read_parquet(%s) w USING(roster_row_id))",
  lmv2_panel_sql(panel_files), DBI::dbQuoteString(con, weights_path))

estimate_sample <- function(sample_id, cohorts) {
  message("RR package: estimating ", sample_id)
  pair_table <- lmv2_build_pair_table(
    con, panel_sql, "patent_count", cohorts, sample_id)
  influence_table <- lmv2_prepare_influence_table(
    con, pair_table, panel_sql, cohorts)
  coverage <- lmv2_pair_coverage(
    con, pair_table, panel_sql, cohorts, "patent_count", sample_id)
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
  compact <- lmv2_compact_post_regression(
    con, influence_table, post_estimate)
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
    dynamic, file.path(OUT_DIR, paste0("rr_dynamic_", sample_id, ".csv")))
  atomic_csv(
    headline, file.path(OUT_DIR, paste0("rr_headline_", sample_id, ".csv")))
  atomic_csv(
    pretest, file.path(OUT_DIR, paste0("rr_pretrend_", sample_id, ".csv")))
  atomic_csv(
    coverage, file.path(OUT_DIR, paste0("rr_coverage_", sample_id, ".csv")))
  matrix_csv(
    covariance$two_way, event$event_time,
    file.path(OUT_DIR, paste0("rr_covariance_two_way_", sample_id, ".csv")))
  matrix_csv(
    covariance$deal, event$event_time,
    file.path(OUT_DIR, paste0("rr_covariance_deal_", sample_id, ".csv")))
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
  periods <- fit$event$event_time
  select_periods <- c(-3L, -2L, 0:5)
  keep <- match(select_periods, periods)
  if (anyNA(keep)) stop("RR coefficient periods are incomplete")
  beta <- fit$event$estimate[keep]
  covariance_raw <- fit$covariance[[covariance_id]][keep, keep, drop = FALSE]
  prepared <- prepare_sigma(covariance_raw, sample_id, covariance_id)
  sigma <- prepared$sigma

  l_vec <- c(0, rep(0.2, 5))
  extracted_post <- sum(l_vec * beta[3:8])
  if (abs(extracted_post - fit$post_estimate) > 1e-10) {
    stop("RR extractor does not reproduce certified post aggregate")
  }
  original <- HonestDiD::constructOriginalCS(
    betahat = beta, sigma = sigma,
    numPrePeriods = 2L, numPostPeriods = 6L,
    l_vec = l_vec, alpha = 0.05)
  original <- as.data.frame(original)
  original$sample <- sample_id
  original$covariance <- covariance_id

  message("RR package: HonestDiD coarse grid ", sample_id, " / ", covariance_id)
  coarse_m <- seq(0, 0.50, by = 0.05)
  coarse <- as.data.frame(rr_grid(beta, sigma, coarse_m, 200L))
  coarse$stage <- "coarse_200"
  crossing <- first_crossing(coarse)
  if (is.na(crossing)) {
    extension <- as.data.frame(rr_grid(
      beta, sigma, seq(0.55, 1.00, by = 0.05), 200L))
    extension$stage <- "extension_200"
    coarse <- rbind(coarse, extension)
    crossing <- first_crossing(coarse)
  }
  if (is.na(crossing)) {
    stop("No HonestDiD sign crossing through Mbar=1")
  }
  previous <- max(coarse$Mbar[coarse$Mbar < crossing], 0)
  fine_m <- seq(previous, crossing, by = 0.005)
  if (tail(fine_m, 1L) < crossing - 1e-12) {
    fine_m <- c(fine_m, crossing)
  }
  message("RR package: HonestDiD refinement ", sample_id, " / ", covariance_id)
  fine500 <- as.data.frame(rr_grid(beta, sigma, fine_m, 500L))
  fine500$stage <- "refined_500"
  fine1000 <- as.data.frame(rr_grid(beta, sigma, fine_m, 1000L))
  fine1000$stage <- "stability_1000"
  breakdown500 <- first_crossing(fine500)
  breakdown1000 <- first_crossing(fine1000)
  stable <- is.finite(breakdown500) && is.finite(breakdown1000) &&
    abs(breakdown500 - breakdown1000) <= 0.01 + 1e-12
  if (!stable) stop("HonestDiD breakdown failed grid stability gate")

  pre_scale <- max(abs(beta[[2L]] - beta[[1L]]), abs(beta[[2L]]))
  summary <- data.frame(
    sample = sample_id,
    covariance = covariance_id,
    beta_m3 = beta[[1L]], beta_m2 = beta[[2L]],
    maximum_pre_first_difference = pre_scale,
    post_average = fit$post_estimate,
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
    results = results, original = original, summary = summary,
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

# The former 1994--2010 result is an internal numerical-reproduction check,
# not a routinely co-reported specification.
old_dynamic <- utils::read.csv(
  file.path(OLD_RR_DIR, "rr_dynamic_full_1994_2010.csv"),
  stringsAsFactors = FALSE)
new_dynamic <- utils::read.csv(
  file.path(OUT_DIR, "rr_dynamic_reproduction_1994_2010.csv"),
  stringsAsFactors = FALSE)
dynamic_compare <- merge(
  old_dynamic[c("event_time", "estimate")],
  new_dynamic[c("event_time", "estimate")],
  by = "event_time", suffixes = c("_frozen", "_amended"), all = TRUE)
if (nrow(dynamic_compare) != 11L || anyNA(dynamic_compare)) {
  stop("Incumbent RR dynamic reproduction has incomplete event times")
}
dynamic_compare$absolute_difference <- abs(
  dynamic_compare$estimate_amended - dynamic_compare$estimate_frozen)

old_summary <- utils::read.csv(
  file.path(OLD_RR_DIR, "rr_breakdown_summary.csv"),
  stringsAsFactors = FALSE)
old_summary <- old_summary[
  old_summary$sample == "full_1994_2010", , drop = FALSE]
new_summary <- rr_summary[
  rr_summary$sample == "reproduction_1994_2010", , drop = FALSE]
summary_compare <- merge(
  old_summary, new_summary, by = "covariance",
  suffixes = c("_frozen", "_amended"), all = TRUE)
if (nrow(summary_compare) != 2L || anyNA(summary_compare$covariance)) {
  stop("Incumbent RR summary reproduction is incomplete")
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
atomic_csv(dynamic_compare, file.path(OUT_DIR, "rr_reproduction_dynamic.csv"))
atomic_csv(summary_compare, file.path(OUT_DIR, "rr_reproduction_summary.csv"))

atomic_csv(rr_results, file.path(OUT_DIR, "rr_sensitivity_grid.csv"))
atomic_csv(rr_original, file.path(OUT_DIR, "rr_original_confidence_sets.csv"))
atomic_csv(rr_summary, file.path(OUT_DIR, "rr_breakdown_summary.csv"))
atomic_csv(
  rr_covariance_diagnostics,
  file.path(OUT_DIR, "rr_covariance_diagnostics.csv"))
atomic_csv(rr_beta, file.path(OUT_DIR, "rr_coefficient_vector.csv"))

# Primary sensitivity figure.
source(file.path(BASE, "R", "00_lmv2_visual_style.R"))
primary <- rr_results[
  rr_results$sample == "full_1993_2010" &
    rr_results$covariance == "two_way" &
    (rr_results$stage == "stability_1000" |
       (rr_results$stage == "coarse_200" & rr_results$Mbar == 0)),
  , drop = FALSE]
primary <- primary[order(primary$Mbar), , drop = FALSE]
primary_original <- rr_original[
  rr_original$sample == "full_1993_2010" &
    rr_original$covariance == "two_way", , drop = FALSE]
plot <- ggplot2::ggplot(
  primary, ggplot2::aes(x = Mbar)) +
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
    title = "Sensitivity to violations of parallel trends",
    subtitle = "Rambachan--Roth relative magnitudes; analytic two-way covariance",
    x = expression(bar(M)),
    y = "95% robust confidence set for average ATT, years +1 to +5") +
  lmv2_theme()
lmv2_save_figure(
  plot, file.path(OUT_DIR, "figure_rr_relative_magnitudes"),
  width = 7.1, height = 4.6, dpi = 320)

# Terminal certification and provenance.
certification <- data.frame(
  check = c(
    "eighteen_cohorts", "roster_rows_512625", "unique_roster_ids",
    "all_weight_cells_feasible", "held_out_not_constrained",
    "handoff_contract_pass", "four_rr_specifications",
    "all_breakdowns_grid_stable", "all_coefficient_vectors_have_8_rows",
    "incumbent_reproduction_within_tolerance",
    "honestdid_version_0_2_8"),
  pass = c(
    nrow(diagnostics) == 18L,
    nrow(weights) == 512625L,
    !anyDuplicated(weights$roster_row_id),
    all(diagnostics$mode %in% c(
      "exact_ebal", "optweight_0.05", "optweight_0.10")),
    !length(intersect(balance_vars, held_out_vars)),
    isTRUE(handoff_manifest$certification_pass[[1L]]),
    nrow(rr_summary) == 4L,
    all(rr_summary$breakdown_grid_stable_within_0_01),
    all(table(rr_beta$sample, rr_beta$covariance) == 8L),
    all(summary_compare$pass),
    identical(as.character(utils::packageVersion("HonestDiD")), "0.2.8")),
  stringsAsFactors = FALSE)
atomic_csv(certification, file.path(OUT_DIR, "rr_certification.csv"))
if (!all(certification$pass)) {
  stop("RR terminal certification failed: ",
       paste(certification$check[!certification$pass], collapse = ", "))
}

source_files <- c(
  runner = file.path(BASE, "R", "48_run_lmv2_rr_honestdid_1993.R"),
  freeze = FREEZE_PATH,
  p4_cohort_core = file.path(
    P4_ROOT, "02_analysis", "R", "17m_lmv2_p4_cohort_hybrid_core.R"),
  p4_newton = file.path(
    P4_ROOT, "02_analysis", "R", "18j_lmv2_p5_newton_solver.R"),
  p6_estimation_core = file.path(
    BASE, "R", "19b_lmv2_p6_estimation_core.R"),
  p6_manifest = P6_MANIFEST_PATH,
  source_handoff = P4_BASE_HANDOFF,
  frozen_rr_summary = file.path(OLD_RR_DIR, "rr_breakdown_summary.csv"),
  frozen_rr_dynamic = file.path(
    OLD_RR_DIR, "rr_dynamic_full_1994_2010.csv"))
manifest <- data.frame(
  package = "lmv2_rr_rm_holdout_m3_m2_1993_amendment_v1",
  completed_at = as.character(Sys.time()),
  bootstrap_replications = bootstrap_reps,
  honestdid_version = as.character(utils::packageVersion("HonestDiD")),
  freeze_sha256 = digest::digest(file = FREEZE_PATH, algo = "sha256"),
  runner_sha256 = digest::digest(
    file = file.path(BASE, "R", "48_run_lmv2_rr_honestdid_1993.R"),
    algo = "sha256"),
  weights_sha256 = digest::digest(file = weights_path, algo = "sha256"),
  handoff_sha256 = digest::digest(file = handoff_path, algo = "sha256"),
  breakdown_sha256 = digest::digest(
    file = file.path(OUT_DIR, "rr_breakdown_summary.csv"), algo = "sha256"),
  source_bundle_sha256 = digest::digest(
    vapply(source_files, digest::digest, character(1),
           file = TRUE, algo = "sha256"), algo = "sha256"),
  certification_pass = TRUE,
  stringsAsFactors = FALSE)
atomic_csv(manifest, file.path(OUT_DIR, "rr_manifest.csv"))

print(rr_summary)
message("RR HonestDiD package certified: ", OUT_DIR)
