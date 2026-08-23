#!/usr/bin/env Rscript

# Outcome-blind design and feasibility audit for the pre-acquisition
# financial-condition robustness check. The script never opens an outcome
# panel. It starts from the certified P5c roster, restricts firms to complete
# g-1 turnover and operating-income records, preserves the locked five-firm
# deal-level support requirement, and solves two weight systems on one common
# roster: the original balance vector and the same vector plus financials.

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
MIN_CONTROL_FIRMS <- as.integer(get_arg("--min-control-firms", "5"))
FINANCIAL_WINDOW <- get_arg("--financial-window", "exact_gm1")

if (any(is.na(c(WEIGHTS_DIR, OUTPUT_DIR)))) {
  stop("48j requires --weights-dir= and --output-dir=")
}
if (!file.exists(DB_PATH)) stop("Database not found: ", DB_PATH)
if (!dir.exists(WEIGHTS_DIR)) stop("Weight directory not found: ", WEIGHTS_DIR)
if (dir.exists(OUTPUT_DIR) && length(list.files(
    OUTPUT_DIR, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", OUTPUT_DIR)
}
if (MIN_CONTROL_FIRMS < 2L) stop("At least two control firms are required")
if (!FINANCIAL_WINDOW %in% c("exact_gm1", "latest_gm3_gm1")) {
  stop("--financial-window must be exact_gm1 or latest_gm3_gm1")
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
    "DBI", "duckdb", "digest", "WeightIt", "nleqslv", "optweight")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

# Import only the certified pure solver functions. These two globals are the
# frozen numerical tolerances used by that solver.
LMV2_P3_DISTANCE_EPSILON <- 1e-10
LMV2_P4_EBAL <- list(tolerances = list(
  exact_tol = 1e-6, residual_tol = 1e-3, maxit = 100000L
))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))
lmv2_install_p5_newton_solver()

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "weights"), showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "balance"), showWarnings = FALSE)

write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = "")
}
sql_quote <- function(x) paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
frame_hash <- function(x) {
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
cohort_from_file <- as.integer(sub("^c([0-9]+)_.*$", "\\1", basename(weight_files)))
if (!identical(cohort_from_file, 1993:2010)) {
  stop("Expected one certified primary P5c weight file for every 1993--2010 cohort")
}

original_vars <- c(
  paste0("patent_count_m", 5:1),
  paste0("active_patenting_m", 5:1),
  "career_age", "focal_group_exclusivity",
  "firm_log_patent_stock_5y", "firm_log_inventor_count_5y",
  "firm_patent_trajectory"
)
financial_vars <- c(
  "log_turnover", "asinh_operating_income", "negative_operating_income"
)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, sprintf(
  "ATTACH %s AS financial_source (READ_ONLY)",
  DBI::dbQuoteString(con, normalizePath(DB_PATH, winslash = "/", mustWork = TRUE))
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
    "base_weight::DOUBLE original_base_weight, ",
    "final_weight::DOUBLE original_final_weight, %s FROM %s"
  ), paste(original_vars, collapse = ", "), weight_sql
))
if (anyDuplicated(roster$roster_row_id) || nrow(roster) == 0L ||
    !identical(sort(unique(roster$cohort)), 1993:2010)) {
  stop("Certified P5c roster has an invalid grain or cohort set")
}

financial_wide <- DBI::dbGetQuery(
  con, "SELECT * FROM financial_source.cassi_financial_all")
if (nrow(financial_wide) != length(unique(financial_wide$id_group))) {
  stop("cassi_financial_all is not unique by id_group")
}
financial_long <- do.call(rbind, lapply(1996:2015, function(year) {
  data.frame(
    group_id = as.integer(financial_wide$id_group),
    financial_year = year,
    turnover = as.numeric(financial_wide[[paste0("turnover_", year)]]),
    operating_income = as.numeric(
      financial_wide[[paste0("operating_income_", year)]]),
    total_assets = as.numeric(financial_wide[[paste0("total_assets_", year)]]),
    employees = as.numeric(financial_wide[[paste0("employees_", year)]]),
    consolidation_code = as.character(financial_wide$consolidation_code),
    country_code = as.character(financial_wide$country_code),
    stringsAsFactors = FALSE
  )
}))
if (anyDuplicated(financial_long[c("group_id", "financial_year")])) {
  stop("Financial long table is not unique by group-year")
}

fin_key <- paste(financial_long$group_id, financial_long$financial_year)
financial_long$complete_joint <- is.finite(financial_long$turnover) &
  financial_long$turnover >= 0 & is.finite(financial_long$operating_income)
offsets <- if (FINANCIAL_WINDOW == "exact_gm1") 1L else 1:3
idx <- rep(NA_integer_, nrow(roster))
for (offset in offsets) {
  candidate <- match(paste(roster$group_id, roster$cohort - offset), fin_key)
  candidate_complete <- rep(FALSE, length(candidate))
  available <- !is.na(candidate)
  candidate_complete[available] <-
    financial_long$complete_joint[candidate[available]]
  use <- is.na(idx) & candidate_complete
  idx[use] <- candidate[use]
}
for (v in setdiff(names(financial_long), c("group_id", "financial_year"))) {
  roster[[v]] <- financial_long[[v]][idx]
}
roster$financial_year <- financial_long$financial_year[idx]
roster$financial_complete <- is.finite(roster$turnover) &
  roster$turnover >= 0 & is.finite(roster$operating_income)
roster$log_turnover <- NA_real_
roster$log_turnover[roster$financial_complete] <-
  log1p(roster$turnover[roster$financial_complete])
roster$asinh_operating_income <- NA_real_
roster$asinh_operating_income[roster$financial_complete] <-
  asinh(roster$operating_income[roster$financial_complete])
roster$negative_operating_income <- ifelse(
  roster$financial_complete,
  as.numeric(roster$operating_income < 0), NA_real_)

# Coverage at the row and distinct-firm levels.
coverage_arm <- do.call(rbind, lapply(split(
  roster, list(roster$cohort, roster$treated), drop = TRUE), function(x) {
  data.frame(
    cohort = x$cohort[[1]], arm = if (x$treated[[1]] == 1L) "treated" else "control",
    rows = nrow(x), complete_rows = sum(x$financial_complete),
    row_coverage = mean(x$financial_complete),
    firms = length(unique(x$group_id)),
    complete_firms = length(unique(x$group_id[x$financial_complete])),
    stringsAsFactors = FALSE
  )
}))
write_csv(coverage_arm[order(coverage_arm$cohort, coverage_arm$arm), ],
          "financial_coverage_by_arm.csv")

# Deal-level support census. A treated deal is retained only when its target
# has complete g-1 financials and at least the locked number of financially
# observed control firms remain in its frozen donor stack.
deal_split <- split(roster, roster$deal_id)
support <- do.call(rbind, lapply(deal_split, function(x) {
  treated <- x$treated == 1L
  control <- !treated
  data.frame(
    cohort = unique(x$cohort), deal_id = unique(x$deal_id),
    n_treated = sum(treated), n_control_rows_original = sum(control),
    n_control_firms_original = length(unique(x$group_id[control])),
    target_financial_complete = all(x$financial_complete[treated]),
    n_control_rows_financial = sum(control & x$financial_complete),
    n_control_firms_financial = length(unique(
      x$group_id[control & x$financial_complete])),
    stringsAsFactors = FALSE
  )
}))
support$eligible_two_firm <- support$target_financial_complete &
  support$n_control_firms_financial >= 2L & support$n_control_rows_financial >= 3L
support$eligible_locked <- support$target_financial_complete &
  support$n_control_firms_financial >= MIN_CONTROL_FIRMS &
  support$n_control_rows_financial >= 3L
write_csv(support[order(support$cohort, support$deal_id), ],
          "financial_support_by_deal.csv")

coverage_summary <- data.frame(
  rule = c("headline", paste0(FINANCIAL_WINDOW, "_two_firms"),
           paste0(FINANCIAL_WINDOW, "_locked_five_firms")),
  deals = c(nrow(support), sum(support$eligible_two_firm),
            sum(support$eligible_locked)),
  treated_inventors = c(sum(support$n_treated),
    sum(support$n_treated[support$eligible_two_firm]),
    sum(support$n_treated[support$eligible_locked])),
  cohorts = c(length(unique(support$cohort)),
    length(unique(support$cohort[support$eligible_two_firm])),
    length(unique(support$cohort[support$eligible_locked]))),
  stringsAsFactors = FALSE
)
coverage_summary$treated_share <-
  coverage_summary$treated_inventors / coverage_summary$treated_inventors[[1]]
coverage_summary$deal_share <- coverage_summary$deals / coverage_summary$deals[[1]]
write_csv(coverage_summary, "financial_coverage_summary.csv")

# Outcome-blind composition diagnostic among treated inventors.
eligible_deals <- support$deal_id[support$eligible_locked]
treated_all <- roster[roster$treated == 1L, ]
treated_all$financial_design_included <- treated_all$deal_id %in% eligible_deals
smd_binary_split <- function(x, included) {
  s <- stats::sd(x[is.finite(x)])
  if (!is.finite(s) || s < 1e-10) return(NA_real_)
  (mean(x[included], na.rm = TRUE) - mean(x[!included], na.rm = TRUE)) / s
}
observed_missing <- do.call(rbind, lapply(original_vars, function(v) {
  z <- treated_all[[v]]
  inc <- treated_all$financial_design_included
  data.frame(
    variable = v, included_mean = mean(z[inc], na.rm = TRUE),
    excluded_mean = mean(z[!inc], na.rm = TRUE),
    standardized_difference = smd_binary_split(z, inc),
    stringsAsFactors = FALSE
  )
}))
observed_missing$abs_standardized_difference <-
  abs(observed_missing$standardized_difference)
write_csv(observed_missing[order(-observed_missing$abs_standardized_difference), ],
          "financial_included_vs_excluded_treated.csv")

reporting_basis <- do.call(rbind, lapply(split(
  roster[roster$financial_complete, ],
  list(roster$cohort[roster$financial_complete],
       roster$treated[roster$financial_complete]), drop = TRUE), function(x) {
  out <- as.data.frame(table(x$consolidation_code), stringsAsFactors = FALSE)
  names(out) <- c("consolidation_code", "rows")
  out$cohort <- x$cohort[[1]]
  out$arm <- if (x$treated[[1]] == 1L) "treated" else "control"
  out
}))
write_csv(reporting_basis[c("cohort", "arm", "consolidation_code", "rows")],
          "financial_consolidation_code_audit.csv")

# Freeze one restricted roster. Financial completeness is required for both
# arms, and no donor outside the certified P5c stack can enter.
restricted <- roster[roster$deal_id %in% eligible_deals &
                       roster$financial_complete, ]
if (!nrow(restricted) || anyDuplicated(restricted$roster_row_id)) {
  stop("Restricted financial roster is empty or non-unique")
}
recompute_base <- function(x) {
  n_t <- aggregate(treated ~ deal_id, x[x$treated == 1L, ], length)
  n_c <- aggregate(treated ~ deal_id, x[x$treated == 0L, ], length)
  names(n_t)[2] <- "n_treated"
  names(n_c)[2] <- "n_control"
  counts <- merge(n_t, n_c, by = "deal_id", all = TRUE)
  if (anyNA(counts) || any(counts$n_control < 3L)) {
    stop("Restricted roster has an unsupported treated deal")
  }
  j <- match(x$deal_id, counts$deal_id)
  ifelse(x$treated == 1L, 1, counts$n_treated[j] / counts$n_control[j])
}
restricted$base_weight <- recompute_base(restricted)

balance_for <- function(x, weight, vars, stage, specification) {
  std <- lmv2_ebal_standardize_cohort(vars, x)
  use <- setdiff(vars, std$zero_variance)
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

run_solve <- function(x, vars, specification) {
  before <- balance_for(x, x$base_weight, vars, "before", specification)
  exact <- lmv2_ebal_run_cohort(
    vars, transform(x, D = treated), D_col = "D",
    s_weights = x$base_weight, exact_tol = 1e-6,
    residual_tol = 1e-3, maxit = 100000L
  )
  inventor_ess <- function(weight) {
    w <- aggregate(weight[x$treated == 0L],
                   list(codinv = x$codinv[x$treated == 0L]), sum)$x
    sum(w)^2 / sum(w^2)
  }
  acceptable <- function(weight, maxdiff, tolerance) {
    length(weight) == nrow(x) && all(is.finite(weight)) && all(weight > 0) &&
      length(maxdiff) == 1L && is.finite(maxdiff) &&
      maxdiff <= tolerance + 1e-8 &&
      inventor_ess(weight) / sum(x$treated == 1L) >= 0.50
  }
  solved <- list(
    status = exact$status,
    mode = "exact_ebal",
    tier = if (length(exact$tier)) exact$tier else NA_character_,
    weight = exact$weight,
    maxdiff = if (length(exact$maxdiff)) exact$maxdiff else NA_real_,
    warnings = character()
  )
  passed <- identical(exact$status, "pass") &&
    acceptable(exact$weight, exact$maxdiff, 1e-3)

  if (!passed) {
    std <- lmv2_ebal_standardize_cohort(vars, x)
    use <- setdiff(vars, std$zero_variance)
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
        } else "failed_balance_or_ess",
        mode = paste0("optweight_", sprintf("%.2f", tol)),
        tier = if (passed && maxdiff <= 0.05 + 1e-8) "preferred" else
          if (passed) "acceptable" else NA_character_,
        weight = finalized$weight, maxdiff = maxdiff, warnings = captured
      )
      if (passed) break
    }
  }
  after <- if (passed) {
    balance_for(x, solved$weight, vars, "after", specification)
  } else {
    z <- before
    z$stage <- "after"
    z[c("treated_mean", "control_mean", "difference", "abs_difference")] <- NA_real_
    z
  }
  diagnostics <- data.frame(
    cohort = unique(x$cohort), specification = specification,
    status = solved$status, feasibility_mode = solved$mode,
    tier = solved$tier,
    n_treated = sum(x$treated == 1L), n_control_rows = sum(x$treated == 0L),
    n_control_inventors = length(unique(x$codinv[x$treated == 0L])),
    n_deals = length(unique(x$deal_id[x$treated == 1L])),
    max_abs_smd = if (passed) max(after$abs_difference, na.rm = TRUE) else NA_real_,
    control_ess_stack = if (passed) {
      lmv2_ebal_ess(solved$weight[x$treated == 0L])
    } else NA_real_,
    control_ess_inventor = if (passed) inventor_ess(solved$weight) else NA_real_,
    control_ess_inventor_ratio = if (passed) {
      inventor_ess(solved$weight) / sum(x$treated == 1L)
    } else NA_real_,
    max_control_weight_share = if (passed) {
      max(solved$weight[x$treated == 0L]) /
        sum(solved$weight[x$treated == 0L])
    } else NA_real_,
    solver_warnings = paste(unique(solved$warnings), collapse = " | "),
    passed = passed, stringsAsFactors = FALSE
  )
  list(weight = if (passed) solved$weight else rep(NA_real_, nrow(x)),
       balance = rbind(before, after), diagnostics = diagnostics)
}

cohort_parts <- split(restricted, restricted$cohort)
solves <- lapply(cohort_parts, function(x) {
  list(
    linked = run_solve(x, original_vars, "financial_linked_original_balance"),
    adjusted = run_solve(x, c(original_vars, financial_vars),
                         "financial_adjusted")
  )
})
diagnostics_all <- do.call(rbind, unlist(lapply(solves, function(z) {
  list(z$linked$diagnostics, z$adjusted$diagnostics)
}), recursive = FALSE))
common_cohorts <- sort(unique(diagnostics_all$cohort[
  diagnostics_all$passed &
    diagnostics_all$cohort %in% diagnostics_all$cohort[
      diagnostics_all$specification == "financial_linked_original_balance" &
        diagnostics_all$passed] &
    diagnostics_all$cohort %in% diagnostics_all$cohort[
      diagnostics_all$specification == "financial_adjusted" &
        diagnostics_all$passed]
]))
if (length(common_cohorts) < 2L) {
  write_csv(diagnostics_all, "financial_weight_diagnostics.csv")
  stop("Fewer than two cohorts pass both entropy-balancing specifications")
}

weights_out <- list()
balance_out <- list()
k <- 0L
for (cohort in common_cohorts) {
  x <- cohort_parts[[as.character(cohort)]]
  for (specification in c("linked", "adjusted")) {
    k <- k + 1L
    solved <- solves[[as.character(cohort)]][[specification]]
    out <- x[c(
      "roster_row_id", "cohort", "deal_id", "codinv", "treated",
      "group_id", "target_group", "control_group", "base_weight",
      original_vars, financial_vars, "financial_year",
      "consolidation_code", "country_code"
    )]
    out$specification <- if (specification == "linked") {
      "financial_linked_original_balance"
    } else "financial_adjusted"
    out$final_weight <- solved$weight
    weights_out[[k]] <- out
    b <- solved$balance
    b$cohort <- cohort
    balance_out[[k]] <- b
  }
}
weights_out <- do.call(rbind, weights_out)
balance_out <- do.call(rbind, balance_out)
diagnostics_all$common_feasible_cohort <- diagnostics_all$cohort %in% common_cohorts
write_csv(diagnostics_all, "financial_weight_diagnostics.csv")
write_csv(balance_out, "financial_balance_before_after.csv")

for (specification in unique(weights_out$specification)) {
  z <- weights_out[weights_out$specification == specification, ]
  path <- file.path(OUTPUT_DIR, "weights", paste0(specification, ".parquet"))
  write_parquet(con, z, path, paste0("tmp_financial_", gsub("[^a-z]", "_", specification)))
}

common <- restricted[restricted$cohort %in% common_cohorts, ]
common_deals <- unique(common$deal_id[common$treated == 1L])
treated_counts <- aggregate(treated ~ deal_id, common[common$treated == 1L, ], length)
share <- treated_counts$treated / sum(treated_counts$treated)
effective_deals <- 1 / sum(share^2)
treated_coverage <- sum(treated_counts$treated) / sum(support$n_treated)
deal_coverage <- length(common_deals) / nrow(support)
cohort_coverage <- length(common_cohorts) / length(unique(support$cohort))
max_composition_smd <- max(observed_missing$abs_standardized_difference, na.rm = TRUE)

# These are reporting gates, not post-outcome specification choices. A failed
# gate authorizes estimation for an appendix diagnostic but rules out using
# the exercise as a broad-coverage main-text robustness claim.
gates <- data.frame(
  gate = c(
    "minimum_treated_coverage_80pct",
    "minimum_deal_coverage_50pct",
    "all_cohorts_retained",
    "minimum_effective_deals_20",
    "included_excluded_max_smd_0_10",
    "all_common_balance_smd_below_0_10"
  ),
  value = c(treated_coverage, deal_coverage, cohort_coverage,
            effective_deals, max_composition_smd,
            max(balance_out$abs_difference[balance_out$stage == "after"],
                na.rm = TRUE)),
  threshold = c(0.80, 0.50, 1, 20, 0.10, 0.10),
  pass = c(treated_coverage >= 0.80, deal_coverage >= 0.50,
           cohort_coverage == 1, effective_deals >= 20,
           max_composition_smd <= 0.10,
           max(balance_out$abs_difference[balance_out$stage == "after"],
               na.rm = TRUE) <= 0.10),
  stringsAsFactors = FALSE
)
write_csv(gates, "financial_reporting_gates.csv")

manifest <- data.frame(
  version = "lmv2_financial_condition_design_v1",
  financial_reference = FINANCIAL_WINDOW,
  minimum_control_firms = MIN_CONTROL_FIRMS,
  primary_financial_variables = paste(financial_vars, collapse = ";"),
  currency_metadata_available = FALSE,
  consolidation_code_audited = TRUE,
  headline_deals = nrow(support), restricted_deals = length(common_deals),
  headline_treated = sum(support$n_treated),
  restricted_treated = sum(treated_counts$treated),
  headline_cohorts = length(unique(support$cohort)),
  restricted_cohorts = length(common_cohorts),
  effective_treated_deals = effective_deals,
  analysis_authorized = length(common_cohorts) >= 2L &&
    all(diagnostics_all$passed[diagnostics_all$cohort %in% common_cohorts]),
  main_text_eligible = all(gates$pass),
  placement = if (all(gates$pass)) "main_table_and_appendix" else "appendix_only",
  roster_sha256 = frame_hash(common[c("cohort", "deal_id", "roster_row_id")]),
  input_weights_bundle_sha256 = digest::digest(vapply(
    weight_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
    algo = "sha256"),
  source_sha256 = digest::digest(normalizePath(
    sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]),
    winslash = "/", mustWork = TRUE), file = TRUE, algo = "sha256"),
  stringsAsFactors = FALSE
)
write_csv(manifest, "financial_design_manifest.csv")
write_csv(data.frame(cohort = common_cohorts), "financial_feasible_cohorts.csv")
write_csv(data.frame(deal_id = sort(common_deals)), "financial_feasible_deals.csv")

message(sprintf(
  paste0("Financial design complete: %d treated inventors, %d deals, %d cohorts; ",
         "effective deals %.2f; placement %s"),
  manifest$restricted_treated, manifest$restricted_deals,
  manifest$restricted_cohorts, manifest$effective_treated_deals,
  manifest$placement
))
