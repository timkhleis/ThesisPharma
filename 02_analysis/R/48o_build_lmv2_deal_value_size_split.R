#!/usr/bin/env Rscript

# Outcome-blind design, feasibility, weighting, and power audit for the
# deal-value acquisition-size split. Post-acquisition outcomes
# are never opened here. Stage 1 remains frozen; only P5c inventor balance is
# re-solved within cohort-by-size cells.

options(stringsAsFactors = FALSE, scipen = 999)

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NA_character_) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  if (length(hit) != 1L) stop("Duplicate argument: ", flag)
  sub(paste0("^", flag, "="), "", hit)
}

CODE_ROOT <- get_arg("--code-root", "02_analysis")
DB_PATH <- get_arg("--db", "02_analysis/output/thesis_foundation.duckdb")
WEIGHTS_DIR <- get_arg("--weights-dir")
OUTPUT_DIR <- get_arg("--output-dir")

if (any(is.na(c(WEIGHTS_DIR, OUTPUT_DIR)))) {
  stop("48o requires --weights-dir= and --output-dir=")
}
if (!file.exists(DB_PATH)) stop("Database not found: ", DB_PATH)
if (!dir.exists(WEIGHTS_DIR)) stop("Weight directory not found: ", WEIGHTS_DIR)
if (dir.exists(OUTPUT_DIR) && length(list.files(
    OUTPUT_DIR, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", OUTPUT_DIR)
}

BASE <- normalizePath(CODE_ROOT, winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c(
    "DBI", "duckdb", "digest", "WeightIt", "nleqslv", "optweight",
    "fixest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

# Import only the certified pure balance engine with its pinned tolerances.
LMV2_P3_DISTANCE_EPSILON <- 1e-10
LMV2_P4_EBAL <- list(tolerances = list(
  exact_tol = 1e-6, residual_tol = 1e-3, maxit = 100000L
))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))
lmv2_install_p5_newton_solver()

AMENDMENT <- file.path(
  BASE, "notes", "local_match_v2_deal_value_size_split_amendment.md")
if (!file.exists(AMENDMENT)) stop("Frozen size-split amendment is missing")

VALUE_THRESHOLD_EXPECTED <- 5000000
MIN_DEALS <- 1L
MIN_TREATED <- 50L
MIN_CONTROL_INVENTORS <- 100L
MIN_ESS_RATIO <- 0.50
MAX_CONTROL_INVENTOR_SHARE <- 0.20

balance_vars <- c(
  paste0("patent_count_m", 5:1),
  paste0("active_patenting_m", 5:1),
  "career_age", "focal_group_exclusivity",
  "firm_log_patent_stock_5y", "firm_log_inventor_count_5y",
  "firm_patent_trajectory"
)

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "weights"), showWarnings = FALSE)
write_csv <- function(x, name) utils::write.csv(
  x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = ""
)
sql_quote <- function(x) paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
frame_hash <- function(x) {
  if (!nrow(x)) return(digest::digest(x, algo = "sha256"))
  digest::digest(x[do.call(order, x), , drop = FALSE], algo = "sha256")
}
write_parquet <- function(con, x, path, table_name) {
  DBI::dbWriteTable(con, table_name, x, overwrite = TRUE)
  DBI::dbExecute(con, sprintf(
    "COPY %s TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    table_name, DBI::dbQuoteString(con, normalizePath(
      path, winslash = "/", mustWork = FALSE))
  ))
  DBI::dbExecute(con, paste("DROP TABLE", table_name))
}

weight_files <- sort(list.files(
  WEIGHTS_DIR,
  pattern = "^c[0-9]+_primary_count_active_.*\\.parquet$",
  full.names = TRUE
))
cohort_from_file <- as.integer(sub(
  "^c([0-9]+)_.*$", "\\1", basename(weight_files)))
if (!identical(cohort_from_file, 1993:2010)) {
  stop("Expected one certified primary P5c weight file for every 1993--2010 cohort")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, sprintf(
  "ATTACH %s AS foundation (READ_ONLY)",
  DBI::dbQuoteString(con, normalizePath(
    DB_PATH, winslash = "/", mustWork = TRUE))
))

weight_sql <- paste0(
  "read_parquet([", paste(vapply(
    normalizePath(weight_files, winslash = "/", mustWork = TRUE),
    sql_quote, character(1)), collapse = ","), "])"
)
roster <- DBI::dbGetQuery(con, sprintf(
  paste0(
    "SELECT roster_row_id, cohort::INTEGER cohort, deal_id::INTEGER deal_id, ",
    "codinv::BIGINT codinv, treated::INTEGER treated, group_id::BIGINT group_id, ",
    "target_group::BIGINT target_group, control_group::BIGINT control_group, ",
    "base_weight::DOUBLE base_weight, final_weight::DOUBLE original_final_weight, ",
    "%s FROM %s"
  ), paste(balance_vars, collapse = ", "), weight_sql
))
if (!nrow(roster) || anyDuplicated(roster$roster_row_id) ||
    !identical(sort(unique(roster$cohort)), 1993:2010)) {
  stop("Certified P5c roster has an invalid grain or cohort set")
}
if (any(!is.finite(roster$base_weight)) || any(roster$base_weight <= 0) ||
    any(abs(roster$original_final_weight[roster$treated == 1L] - 1) > 1e-12)) {
  stop("Certified P5c base or treated weights are invalid")
}

treated <- roster[roster$treated == 1L, ]
if (anyDuplicated(treated[c("cohort", "deal_id", "codinv")])) {
  stop("Treated P5c roster is not unique by cohort-deal-inventor")
}
size_map <- aggregate(
  treated$roster_row_id,
  treated[c("cohort", "deal_id")],
  function(x) length(unique(x))
)
names(size_map)[3] <- "n_supported"
pre_support <- DBI::dbGetQuery(con, "
  SELECT deal_id::INTEGER deal_id,
         COUNT(*)::INTEGER n_pre_support,
         MAX(deal_value)::DOUBLE target_value
  FROM foundation.lmv2_treated_primary
  GROUP BY deal_id
")
if (anyDuplicated(pre_support$deal_id)) stop("Pre-support deal table is not unique")
size_map <- merge(size_map, pre_support, by = "deal_id", all.x = TRUE, sort = FALSE)
size_map <- size_map[order(size_map$cohort, size_map$deal_id), ]
if (anyNA(size_map$n_pre_support) || any(size_map$n_supported > size_map$n_pre_support)) {
  stop("Supported size does not nest inside the P2 pre-support count")
}
if (any(!is.finite(size_map$target_value)) || any(size_map$target_value < 0)) {
  stop("Target transaction value is missing or invalid")
}
threshold <- VALUE_THRESHOLD_EXPECTED
size_map$size_group <- ifelse(
  size_map$target_value <= threshold, "small", "large")

complete_value <- is.finite(size_map$target_value) & size_map$target_value >= 0
corr_rows <- function(x, label) {
  keep <- is.finite(x) & is.finite(size_map$n_supported)
  data.frame(
    comparison = label,
    method = c("pearson", "spearman"),
    correlation = c(
      stats::cor(size_map$n_supported[keep], x[keep], method = "pearson"),
      stats::cor(size_map$n_supported[keep], x[keep], method = "spearman")
    ),
    complete_deals = sum(keep), stringsAsFactors = FALSE
  )
}
size_correlations <- rbind(
  corr_rows(size_map$n_pre_support, "pre_support_treated_inventor_count"),
  corr_rows(ifelse(complete_value, size_map$target_value, NA_real_), "target_value"),
  corr_rows(ifelse(complete_value, log1p(size_map$target_value), NA_real_),
            "log1p_target_value")
)
write_csv(size_correlations, "deal_value_size_correlations.csv")

size_summary <- data.frame(
  statistic = c(
    "minimum_target_value", "q25_target_value", "median_target_value",
    "q75_target_value", "maximum_target_value", "deals_at_threshold",
    "deals_under_or_equal_5bn", "deals_over_5bn"),
  value = c(
    min(size_map$target_value),
    unname(stats::quantile(size_map$target_value, .25, type = 7)),
    unname(stats::median(size_map$target_value)),
    unname(stats::quantile(size_map$target_value, .75, type = 7)),
    max(size_map$target_value),
    sum(size_map$target_value == threshold),
    sum(size_map$size_group == "small"),
    sum(size_map$size_group == "large")
  ), stringsAsFactors = FALSE
)
write_csv(size_summary, "deal_value_size_threshold.csv")
write_csv(size_map, "deal_value_size_deal_map.csv")

roster_key <- paste(roster$cohort, roster$deal_id, sep = "\r")
size_key <- paste(size_map$cohort, size_map$deal_id, sep = "\r")
j <- match(roster_key, size_key)
if (anyNA(j)) stop("At least one roster row lacks a deal-value-size assignment")
roster$size_group <- size_map$size_group[j]
roster$n_supported <- size_map$n_supported[j]
roster$target_value <- size_map$target_value[j]

cell_parts <- split(
  roster,
  paste(roster$cohort, roster$size_group, sep = "::")
)
cell_census <- do.call(rbind, lapply(cell_parts, function(x) data.frame(
  cohort = x$cohort[[1]], size_group = x$size_group[[1]],
  n_deals = length(unique(x$deal_id[x$treated == 1L])),
  n_treated = sum(x$treated == 1L),
  n_control_rows = sum(x$treated == 0L),
  n_control_inventors = length(unique(x$codinv[x$treated == 0L])),
  stringsAsFactors = FALSE
)))
cell_census$deal_floor_pass <- cell_census$n_deals >= MIN_DEALS
cell_census$treated_floor_pass <- cell_census$n_treated >= MIN_TREATED
cell_census$control_floor_pass <-
  cell_census$n_control_inventors >= MIN_CONTROL_INVENTORS
cell_census$absolute_floors_pass <- with(
  cell_census, deal_floor_pass & treated_floor_pass & control_floor_pass)

floor_cohorts <- sort(unique(cell_census$cohort[
  cell_census$absolute_floors_pass &
    cell_census$cohort %in% cell_census$cohort[
      cell_census$size_group == "small" & cell_census$absolute_floors_pass] &
    cell_census$cohort %in% cell_census$cohort[
      cell_census$size_group == "large" & cell_census$absolute_floors_pass]
]))
if (length(floor_cohorts) < 2L) {
  write_csv(cell_census, "deal_value_size_cell_census.csv")
  stop("Fewer than two cohorts pass both groups' absolute information floors")
}

balance_for <- function(x, weight, stage, specification) {
  std <- lmv2_ebal_standardize_cohort(balance_vars, x)
  use <- setdiff(balance_vars, std$zero_variance)
  out <- lmv2_ebal_covariate_balance(use, std$data, x$treated, weight)
  if (length(std$zero_variance)) {
    out <- rbind(out, data.frame(
      variable = std$zero_variance, treated_mean = 0, control_mean = 0,
      difference = 0, abs_difference = 0, stringsAsFactors = FALSE))
  }
  out$stage <- stage
  out$specification <- specification
  out
}

control_quality <- function(x, weight) {
  agg <- aggregate(
    weight[x$treated == 0L],
    list(codinv = x$codinv[x$treated == 0L]), sum
  )$x
  list(
    ess = sum(agg)^2 / sum(agg^2),
    max_share = max(agg) / sum(agg),
    n = length(agg)
  )
}

run_solve <- function(x) {
  specification <- paste0("deal_value_size_", x$size_group[[1]])
  before <- balance_for(x, x$base_weight, "before", specification)
  acceptable <- function(weight, maxdiff, tolerance) {
    if (length(weight) != nrow(x) || any(!is.finite(weight)) ||
        any(weight <= 0) || !is.finite(maxdiff) ||
        maxdiff > tolerance + 1e-8) return(FALSE)
    quality <- control_quality(x, weight)
    quality$ess / sum(x$treated == 1L) >= MIN_ESS_RATIO &&
      quality$max_share <= MAX_CONTROL_INVENTOR_SHARE + 1e-12
  }
  exact <- lmv2_ebal_run_cohort(
    balance_vars, transform(x, D = treated), D_col = "D",
    s_weights = x$base_weight, exact_tol = 1e-6,
    residual_tol = 1e-3, maxit = 100000L
  )
  solved <- list(
    status = exact$status, mode = "exact_ebal",
    tier = if (length(exact$tier)) exact$tier else NA_character_,
    weight = exact$weight,
    maxdiff = if (length(exact$maxdiff)) exact$maxdiff else NA_real_,
    warnings = character()
  )
  passed <- identical(exact$status, "pass") &&
    acceptable(exact$weight, exact$maxdiff, 1e-3)

  if (!passed) {
    std <- lmv2_ebal_standardize_cohort(balance_vars, x)
    use <- setdiff(balance_vars, std$zero_variance)
    form <- stats::as.formula(paste("treated ~", paste(use, collapse = " + ")))
    for (tol in c(0.05, 0.10)) {
      captured <- character()
      attempt <- tryCatch(withCallingHandlers(
        optweight::optweight(
          form, data = std$data, tols = tol, estimand = "ATT",
          s.weights = x$base_weight
        ), warning = function(w) {
          captured <<- c(captured, conditionMessage(w))
          invokeRestart("muffleWarning")
        }), error = function(e) e)
      if (inherits(attempt, "condition")) {
        solved <- list(
          status = "solver_error", mode = paste0("optweight_", tol),
          tier = NA_character_, weight = rep(NA_real_, nrow(x)),
          maxdiff = NA_real_, warnings = conditionMessage(attempt))
        next
      }
      solver_infeasible <- !is.null(attempt$info$status) &&
        grepl("infeasible", attempt$info$status, fixed = TRUE)
      finalized <- lmv2_ebal_finalize_weights(
        attempt, x$treated, x$base_weight)
      if (!isTRUE(finalized$ok) || !isTRUE(finalized$weights_ok)) {
        solved <- list(
          status = "invalid_weights", mode = paste0("optweight_", tol),
          tier = NA_character_, weight = finalized$weight,
          maxdiff = NA_real_, warnings = captured)
        next
      }
      bal <- lmv2_ebal_covariate_balance(
        use, std$data, x$treated, finalized$weight)
      maxdiff <- max(bal$abs_difference)
      passed <- !solver_infeasible &&
        acceptable(finalized$weight, maxdiff, tol)
      solved <- list(
        status = if (passed) "pass" else if (solver_infeasible) {
          "solver_infeasible"
        } else "failed_balance_or_weight_quality",
        mode = paste0("optweight_", sprintf("%.2f", tol)),
        tier = if (passed && maxdiff <= 0.05 + 1e-8) "preferred" else
          if (passed) "acceptable" else NA_character_,
        weight = finalized$weight, maxdiff = maxdiff, warnings = captured
      )
      if (passed) break
    }
  }
  after <- if (passed) {
    balance_for(x, solved$weight, "after", specification)
  } else {
    z <- before
    z$stage <- "after"
    z[c("treated_mean", "control_mean", "difference", "abs_difference")] <- NA_real_
    z
  }
  quality <- if (passed) control_quality(x, solved$weight) else
    list(ess = NA_real_, max_share = NA_real_, n = NA_integer_)
  diagnostics <- data.frame(
    cohort = x$cohort[[1]], size_group = x$size_group[[1]],
    specification = specification,
    status = solved$status, feasibility_mode = solved$mode, tier = solved$tier,
    n_treated = sum(x$treated == 1L),
    n_control_rows = sum(x$treated == 0L),
    n_control_inventors = length(unique(x$codinv[x$treated == 0L])),
    n_deals = length(unique(x$deal_id[x$treated == 1L])),
    max_abs_smd = if (passed) max(after$abs_difference, na.rm = TRUE) else NA_real_,
    control_ess_inventor = quality$ess,
    control_ess_inventor_ratio = quality$ess / sum(x$treated == 1L),
    max_control_inventor_share = quality$max_share,
    solver_warnings = paste(unique(solved$warnings), collapse = " | "),
    passed = passed, stringsAsFactors = FALSE
  )
  list(
    weight = if (passed) solved$weight else rep(NA_real_, nrow(x)),
    balance = rbind(before, after), diagnostics = diagnostics
  )
}

eligible_cells <- cell_parts[vapply(cell_parts, function(x) {
  x$cohort[[1]] %in% floor_cohorts
}, logical(1))]
solves <- lapply(eligible_cells, run_solve)
solve_diagnostics <- do.call(rbind, lapply(solves, `[[`, "diagnostics"))
solved_cohorts <- sort(unique(solve_diagnostics$cohort[
  solve_diagnostics$passed &
    solve_diagnostics$cohort %in% solve_diagnostics$cohort[
      solve_diagnostics$size_group == "small" & solve_diagnostics$passed] &
    solve_diagnostics$cohort %in% solve_diagnostics$cohort[
      solve_diagnostics$size_group == "large" & solve_diagnostics$passed]
]))
if (length(solved_cohorts) < 2L) {
  write_csv(cell_census, "deal_value_size_cell_census.csv")
  write_csv(solve_diagnostics, "deal_value_size_weight_diagnostics.csv")
  stop("Fewer than two cohorts pass both size-group solves")
}

weights_out <- list()
balance_out <- list()
k <- 0L
for (name in names(solves)) {
  x <- eligible_cells[[name]]
  if (!x$cohort[[1]] %in% solved_cohorts) next
  k <- k + 1L
  solved <- solves[[name]]
  out <- x[c(
    "roster_row_id", "cohort", "deal_id", "codinv", "treated",
    "group_id", "target_group", "control_group", "base_weight",
    "original_final_weight", "size_group", "n_supported", "target_value",
    balance_vars
  )]
  out$specification <- paste0("deal_value_size_", out$size_group)
  out$final_weight <- solved$weight
  weights_out[[k]] <- out
  b <- solved$balance
  b$cohort <- x$cohort[[1]]
  b$size_group <- x$size_group[[1]]
  balance_out[[k]] <- b
}
weights_out <- do.call(rbind, weights_out)
balance_out <- do.call(rbind, balance_out)
solve_diagnostics$common_feasible_cohort <-
  solve_diagnostics$cohort %in% solved_cohorts

cell_census$floor_common_cohort <- cell_census$cohort %in% floor_cohorts
cell_census$final_common_cohort <- cell_census$cohort %in% solved_cohorts
write_csv(cell_census, "deal_value_size_cell_census.csv")
write_csv(solve_diagnostics, "deal_value_size_weight_diagnostics.csv")
write_csv(balance_out, "deal_value_size_balance_before_after.csv")
write_csv(data.frame(cohort = solved_cohorts), "deal_value_size_feasible_cohorts.csv")

weight_path <- file.path(OUTPUT_DIR, "weights", "deal_value_size_weights.parquet")
write_parquet(con, weights_out, weight_path, "tmp_deal_value_size_weights")

count_rows <- do.call(rbind, lapply(c("full_1993_2010", "common_feasible"), function(sample) {
  z <- if (sample == "full_1993_2010") size_map else
    size_map[size_map$cohort %in% solved_cohorts, ]
  do.call(rbind, lapply(c("small", "large"), function(group) {
    y <- z[z$size_group == group, ]
    data.frame(
      sample = sample, size_group = group,
      acquisitions = nrow(y), supported_treated_inventors = sum(y$n_supported),
      pre_support_treated_inventors = sum(y$n_pre_support),
      cohorts = length(unique(y$cohort)), stringsAsFactors = FALSE
    )
  }))
}))
write_csv(count_rows, "deal_value_size_counts.csv")

# Pre-outcome precision calculation. The placebo change uses only variables
# already present in the design file and is computed before any P6 panel opens.
power_data <- weights_out
power_data$pre_placebo <- power_data$patent_count_m1 - rowMeans(
  power_data[paste0("patent_count_m", 5:2)])
power_data$cell_id <- interaction(
  power_data$cohort, power_data$size_group, drop = TRUE)
power_data$tr_small <- power_data$treated * (power_data$size_group == "small")
power_data$tr_large <- power_data$treated * (power_data$size_group == "large")
power_fit <- fixest::feols(
  pre_placebo ~ tr_small + tr_large | cell_id,
  data = power_data, weights = ~final_weight,
  cluster = ~deal_id + codinv, fixef.rm = "none", notes = FALSE
)
power_beta <- stats::coef(power_fit)
power_vcov <- stats::vcov(power_fit)
L <- c(tr_small = -1, tr_large = 1)
placebo_difference <- sum(L * power_beta[names(L)])
power_se <- sqrt(drop(t(L) %*% power_vcov[names(L), names(L)] %*% L))
power_df <- min(
  length(unique(power_data$deal_id)),
  length(unique(power_data$codinv))) - 1L
power_p <- 2 * stats::pt(-abs(placebo_difference / power_se), df = power_df)
mde_80 <- (stats::qt(.975, df = power_df) + stats::qnorm(.80)) * power_se
power <- data.frame(
  contrast = "large_minus_small",
  placebo_definition = "patent_count_m1_minus_mean_m5_to_m2",
  placebo_estimate = placebo_difference, two_way_se = power_se,
  df = power_df, placebo_p_value = power_p,
  alpha = 0.05, target_power = 0.80, mde_80 = mde_80,
  post_outcomes_opened = FALSE, stringsAsFactors = FALSE
)
write_csv(power, "deal_value_size_preoutcome_power.csv")

retained_deals <- size_map[size_map$cohort %in% solved_cohorts, ]
share <- retained_deals$n_supported / sum(retained_deals$n_supported)
effective_deals <- 1 / sum(share^2)
gates <- data.frame(
  gate = c(
    "at_least_ten_common_cohorts",
    "at_least_twenty_five_deals_per_group",
    "at_least_five_hundred_treated_per_group",
    "all_retained_cells_pass_balance_and_weight_quality",
    "finite_preoutcome_mde"
  ),
  value = c(
    length(solved_cohorts),
    min(count_rows$acquisitions[count_rows$sample == "common_feasible"]),
    min(count_rows$supported_treated_inventors[
      count_rows$sample == "common_feasible"]),
    as.numeric(all(solve_diagnostics$passed[
      solve_diagnostics$cohort %in% solved_cohorts])),
    mde_80
  ),
  threshold = c(10, 25, 500, 1, 0),
  pass = c(
    length(solved_cohorts) >= 10L,
    min(count_rows$acquisitions[count_rows$sample == "common_feasible"]) >= 25L,
    min(count_rows$supported_treated_inventors[
      count_rows$sample == "common_feasible"]) >= 500L,
    all(solve_diagnostics$passed[
      solve_diagnostics$cohort %in% solved_cohorts]),
    is.finite(mde_80) && mde_80 > 0
  ), stringsAsFactors = FALSE
)
write_csv(gates, "deal_value_size_reporting_gates.csv")

manifest <- data.frame(
  version = "lmv2_deal_value_size_split_design_v1",
  designation = "post_hoc_exploratory",
  size_definition = "target_transaction_value_in_thousands",
  threshold = threshold,
  threshold_interpretation = "EUR_5_billion",
  tie_rule = "under_5bn_le_5000000_over_5bn_gt_5000000",
  deals_at_threshold = sum(size_map$target_value == threshold),
  minimum_deals_per_cell = MIN_DEALS,
  minimum_treated_per_cell = MIN_TREATED,
  minimum_control_inventors_per_cell = MIN_CONTROL_INVENTORS,
  minimum_reuse_adjusted_ess_ratio = MIN_ESS_RATIO,
  maximum_control_inventor_share = MAX_CONTROL_INVENTOR_SHARE,
  stage1_resolved = FALSE,
  stage2_resolved = TRUE,
  common_cohorts = paste(solved_cohorts, collapse = ";"),
  n_common_cohorts = length(solved_cohorts),
  n_common_deals = nrow(retained_deals),
  n_common_treated = sum(retained_deals$n_supported),
  effective_treated_deals = effective_deals,
  preoutcome_mde_80 = mde_80,
  post_outcomes_opened = FALSE,
  analysis_authorized = length(solved_cohorts) >= 2L &&
    all(solve_diagnostics$passed[solve_diagnostics$cohort %in% solved_cohorts]) &&
    is.finite(mde_80) && mde_80 > 0,
  main_text_eligible = all(gates$pass),
  placement = if (all(gates$pass)) "main_table_and_appendix" else "appendix_only",
  roster_sha256 = frame_hash(weights_out[c(
    "cohort", "deal_id", "roster_row_id", "size_group")]),
  input_weights_bundle_sha256 = digest::digest(vapply(
    weight_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
    algo = "sha256"),
  amendment_sha256 = digest::digest(AMENDMENT, file = TRUE, algo = "sha256"),
  source_sha256 = digest::digest(normalizePath(
    sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]),
    winslash = "/", mustWork = TRUE), file = TRUE, algo = "sha256"),
  stringsAsFactors = FALSE
)
write_csv(manifest, "deal_value_size_design_manifest.csv")

message(sprintf(
  paste0(
    "Deal-value-size design complete: threshold %d; %d common cohorts, ",
    "%d deals, %d treated inventors; MDE %.4f; placement %s"),
  threshold, manifest$n_common_cohorts, manifest$n_common_deals,
  manifest$n_common_treated, manifest$preoutcome_mde_80,
  manifest$placement
))
