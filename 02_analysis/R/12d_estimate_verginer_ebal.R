# ============================================================================
# 12d_estimate_verginer_ebal.R -- Estimate VR0/VR1/VR2/VR2B with bootstrap
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "12a_verginer_ebal_config.R"))
source(file.path(BASE, "R", "12c_verginer_ebal_utils.R"))
required_packages_12(c("DBI", "duckdb", "did", "WeightIt", "digest"))

args <- commandArgs(trailingOnly = TRUE)
RUN_MODE <- run_mode_12(args)
BITERS <- bootstrap_iters_12(RUN_MODE)

banner_12(sprintf("12d: Estimate Verginer ebal (%s, %d bootstrap draws)", RUN_MODE, BITERS))

if (!file.exists(COVARIATES_PARQUET)) {
  stop("Missing covariates parquet; run 12b first: ", COVARIATES_PARQUET)
}

con <- connect_thesis_readonly()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

panel_sql <- sprintf("
WITH cov AS (
  SELECT *
  FROM read_parquet('%s')
),
cohort AS (
  SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv
  FROM cov
),
patent_inventor_unique AS (
  SELECT DISTINCT p.appln_id, CAST(p.codinv AS BIGINT) AS codinv, p.year
  FROM patent_inventor_enriched p
  JOIN cohort c
    ON c.codinv = CAST(p.codinv AS BIGINT)
),
inventor_year_citations AS (
  SELECT
    codinv,
    CAST(year AS INTEGER) AS calendar_year,
    COUNT(*) AS direct_patent_count,
    SUM(COALESCE(q.fwd_cits5, 0)) AS fwd_citations5
  FROM patent_inventor_unique p
  LEFT JOIN oecd_quality q
    ON q.appln_id = p.appln_id
  GROUP BY codinv, year
)
SELECT
  CAST(x.codinv AS DOUBLE) AS codinv,
  CAST(x.deal_id AS INTEGER) AS deal_id,
  CAST(dm.target_year AS INTEGER) AS treatment_year,
  CAST(x.calendar_year AS INTEGER) AS calendar_year,
  CAST(x.patent_count AS DOUBLE) AS patent_count,
  CAST(COALESCE(c.fwd_citations5, 0) AS DOUBLE) AS fwd_citations5,
  CAST(x.career_end_year AS INTEGER) AS career_end_year,
  CAST(x.last_merged_entity_patent_year AS INTEGER) AS last_merged_entity_patent_year,
  cov.vr_age,
  cov.vr_tenure,
  cov.vr_exclusivity,
  cov.vr_common_ipc,
  cov.vr_common_ipc_cat,
  cov.log_vr_age,
  cov.log_vr_tenure,
  cov.acquirer_resolved,
  cov.acquirer_preportfolio_observed,
  cov.inventor_preipc_observed,
  cov.vr_common_ipc_observed,
  cov.vr_common_ipc_missing_reason
FROM cs2021_estimation_panel x
JOIN deal_map dm
  ON CAST(dm.deal_id AS INTEGER) = x.deal_id
JOIN cov
  ON CAST(cov.codinv AS BIGINT) = CAST(x.codinv AS BIGINT)
 AND CAST(cov.deal_id AS INTEGER) = CAST(x.deal_id AS INTEGER)
LEFT JOIN inventor_year_citations c
  ON c.codinv = CAST(x.codinv AS BIGINT)
 AND c.calendar_year = x.calendar_year
ORDER BY x.deal_id, x.codinv, x.calendar_year
", sql_path_12(COVARIATES_PARQUET))

panel <- DBI::dbGetQuery(con, panel_sql)
panel$log1p_patents <- log1p(panel$patent_count)
panel$log1p_citations <- log1p(panel$fwd_citations5)
panel$vr_rd_activity <- as.numeric(panel$career_end_year >= panel$calendar_year)
panel$vr_left <- as.numeric(panel$last_merged_entity_patent_year < panel$calendar_year)
panel$vr_common_ipc_cat <- factor(panel$vr_common_ipc_cat, levels = c("0", "1-3", "4+"))

unit0 <- panel[!duplicated(panel$codinv), ]
complete_ids <- unit0$codinv[stats::complete.cases(unit0[, VR_RAW_COVARS]) &
                               unit0$vr_common_ipc_observed]
complete_panel <- panel[panel$codinv %in% complete_ids, ]
complete_panel$vr_common_ipc_cat <- factor(complete_panel$vr_common_ipc_cat,
                                           levels = c("0", "1-3", "4+"))

write_parquet_12(complete_panel, PANEL_PARQUET)
units <- complete_panel[!duplicated(complete_panel$codinv), ]
write_parquet_12(units, UNITS_PARQUET)
support_universe <- did_support_universe_12(units, sort(unique(complete_panel$calendar_year)))
write_audit_12(data.frame(
  control_group = CONTROL_GROUP,
  base_period = BASE_PERIOD,
  no_never_treated_units = !any(units$treatment_year == 0L),
  excluded_latest_treated_group = support_universe$excluded_latest_group,
  support_rule = support_universe$support_rule,
  custom_treated_groups = paste(support_universe$treated_groups, collapse = ";"),
  support_year_min = min(support_universe$support_years),
  support_year_max = max(support_universe$support_years)
), "did_support_universe_alignment.csv")

sample_flow <- data.frame(
  stage = c("merged_sample_start", "complete_case_locked"),
  n_inventors = c(length(unique(unit0$codinv)), length(unique(units$codinv))),
  n_deals = c(length(unique(unit0$deal_id)), length(unique(units$deal_id)))
)
sample_flow$excluded_share_from_start <- 1 - sample_flow$n_inventors / sample_flow$n_inventors[1]
write_audit_12(sample_flow, "estimation_sample_flow.csv")

if (sample_flow$n_inventors[1] != EXPECTED_N_INVENTORS ||
    sample_flow$n_deals[1] != EXPECTED_N_DEALS) {
  warning("Starting counts differ from expected diagnostics; continuing with current data.")
}

banner_12("Validating explicit group-time cell engine")
custom_validation <- cell_engine_12(
  complete_panel, "log1p_patents", "cell_engine_unadjusted_validation",
  rhs = ~1, method = "unadjusted", stop_on_failure = FALSE
)
custom_unadj <- custom_validation$cells
did_unadj <- estimate_did_cells_12(
  complete_panel, "log1p_patents", ~1, "did_unadjusted_validation"
)$cells
did_unadj_all <- did_unadj
did_unadj <- did_unadj[is.finite(did_unadj$att), ]
cmp <- merge(
  custom_unadj[, c("group", "time", "event_time", "att")],
  did_unadj[, c("group", "time", "event_time", "att")],
  by = c("group", "time", "event_time"),
  suffixes = c("_custom", "_did")
)
key_cols <- c("group", "time", "event_time")
custom_keys <- unique(custom_unadj[, key_cols])
did_keys <- unique(did_unadj[, key_cols])
custom_only <- custom_keys[
  !interaction(custom_keys, drop = TRUE) %in% interaction(did_keys, drop = TRUE),
  , drop = FALSE
]
did_only <- did_keys[
  !interaction(did_keys, drop = TRUE) %in% interaction(custom_keys, drop = TRUE),
  , drop = FALSE
]
cell_key_audit <- rbind(
  if (nrow(custom_only)) cbind(source = "custom_only", custom_only) else data.frame(),
  if (nrow(did_only)) cbind(source = "did_only", did_only) else data.frame()
)
if (nrow(cell_key_audit) == 0L) {
  cell_key_audit <- data.frame(
    source = character(),
    group = integer(),
    time = integer(),
    event_time = integer()
  )
}
if (nrow(cell_key_audit) > 0L) {
  custom_detail <- custom_unadj[
    match(interaction(cell_key_audit[, key_cols], drop = TRUE),
          interaction(custom_unadj[, key_cols], drop = TRUE)),
    c("group", "time", "event_time", "pre_time", "n_treated", "n_control", "att"),
    drop = FALSE
  ]
  names(custom_detail)[names(custom_detail) == "att"] <- "custom_att"
  did_detail <- did_unadj_all[
    match(interaction(cell_key_audit[, key_cols], drop = TRUE),
          interaction(did_unadj_all[, key_cols], drop = TRUE)),
    c("group", "time", "event_time", "att"),
    drop = FALSE
  ]
  cell_key_audit$custom_pre_time <- custom_detail$pre_time
  cell_key_audit$comparison_period <- paste0(cell_key_audit$time, "_vs_", custom_detail$pre_time)
  cell_key_audit$custom_n_treated <- custom_detail$n_treated
  cell_key_audit$custom_n_control <- custom_detail$n_control
  cell_key_audit$custom_att <- custom_detail$custom_att
  cell_key_audit$did_att <- did_detail$att
  did_group_rows <- lapply(cell_key_audit$group, function(g) {
    did_unadj_all[did_unadj_all$group == g, , drop = FALSE]
  })
  cell_key_audit$did_group_row_count <- vapply(did_group_rows, nrow, integer(1))
  cell_key_audit$did_group_finite_row_count <- vapply(
    did_group_rows,
    function(x) sum(is.finite(x$att)),
    integer(1)
  )
  cell_key_audit$did_group_event_times_returned <- vapply(
    did_group_rows,
    function(x) paste(sort(unique(x$event_time)), collapse = ";"),
    character(1)
  )
  cell_key_audit$did_group_times_returned <- vapply(
    did_group_rows,
    function(x) paste(sort(unique(x$time)), collapse = ";"),
    character(1)
  )
  cell_key_audit$did_nonfinite_reason <- ifelse(
    is.na(did_detail$group),
    "unresolved_validation_mismatch_did_att_gt_returned_no_group_time_row",
    ifelse(is.finite(did_detail$att), "finite_did_counterpart", "did_att_gt_returned_nonfinite_att")
  )
  cell_key_audit$validation_interpretation <- "unresolved_validation_mismatch_pending_specific_did_support_rule"
}
write_audit_12(cell_key_audit, "cell_engine_unmatched_cells.csv")
max_cell_diff <- max(abs(cmp$att_custom - cmp$att_did), na.rm = TRUE)
supported_key_equality <- nrow(custom_only) == 0L && nrow(did_only) == 0L
cell_equiv <- data.frame(
  n_custom_cells = nrow(custom_unadj),
  n_did_cells = nrow(did_unadj),
  n_compared = nrow(cmp),
  n_custom_only_cells = nrow(custom_only),
  n_did_only_cells = nrow(did_only),
  supported_key_equality = supported_key_equality,
  max_abs_difference = max_cell_diff,
  pass_overlap_1e_8 = max_cell_diff <= CELL_EQUIVALENCE_TOL,
  pass_overlap_1e_10_diagnostic = max_cell_diff <= CELL_EQUIVALENCE_STRICT_TOL,
  pass_supported_cell_equivalence = supported_key_equality &&
    max_cell_diff <= CELL_EQUIVALENCE_TOL
)
write_audit_12(cell_equiv, "cell_engine_equivalence.csv")
if (!cell_equiv$pass_supported_cell_equivalence) {
  warning("Cell engine overlap matches did::att_gt only conditionally; inspect cell_engine_unmatched_cells.csv")
}
required_cells <- did_unadj[, c("group", "time", "event_time")]

banner_12("Design-first entropy-balancing feasibility")
design_panel <- complete_panel
design_panel$design_dummy <- 0
raw_design <- cell_engine_12(
  design_panel, "design_dummy", "VR2_entropy_balanced", rhs = VR_RAW_RHS,
  method = "ebal", return_weights = TRUE, stop_on_failure = FALSE
)
logcat_design <- cell_engine_12(
  design_panel, "design_dummy", "VR2B_logged_categorical", rhs = VR_LOGCAT_RHS,
  method = "ebal", return_weights = TRUE, stop_on_failure = FALSE
)
write_audit_12(rbind(raw_design$balance, logcat_design$balance), "group_time_balance.csv")
write_audit_12(rbind(raw_design$weight_diag, logcat_design$weight_diag),
               "group_time_weight_diagnostics.csv")
write_audit_12(rbind(raw_design$covariate_balance, logcat_design$covariate_balance),
               "group_time_covariate_imbalance.csv")
write_audit_12(rbind(raw_design$problem_cells, logcat_design$problem_cells),
               "group_time_problem_cells.csv")
problem_design <- rbind(raw_design$problem_cells, logcat_design$problem_cells)
cov_balance_design <- rbind(raw_design$covariate_balance, logcat_design$covariate_balance)
if (nrow(problem_design) > 0L && nrow(cov_balance_design) > 0L) {
  cov_balance_design$imbalance_column <- paste0("imbalance_", cov_balance_design$covariate)
  cov_wide <- stats::reshape(
    cov_balance_design[, c("specification", "bootstrap_replication", "group",
                           "time", "event_time", "imbalance_column",
                           "abs_difference")],
    idvar = c("specification", "bootstrap_replication", "group", "time", "event_time"),
    timevar = "imbalance_column",
    direction = "wide"
  )
  names(cov_wide) <- sub("^abs_difference\\.", "", names(cov_wide))
  problem_diagnostic <- merge(
    problem_design, cov_wide,
    by = c("specification", "bootstrap_replication", "group", "time", "event_time"),
    all.x = TRUE
  )
} else {
  problem_diagnostic <- problem_design
}
names(problem_diagnostic)[names(problem_diagnostic) == "group"] <- "cohort"
names(problem_diagnostic)[names(problem_diagnostic) == "time"] <- "calendar_year"
write_audit_12(problem_diagnostic, "group_time_problem_cell_diagnostics.csv")
support <- rbind(
  raw_design$cells[, c("specification", "group", "time", "event_time", "n_treated", "n_control")],
  logcat_design$cells[, c("specification", "group", "time", "event_time", "n_treated", "n_control")]
)
write_audit_12(support, "group_time_support.csv")
failures_design <- rbind(raw_design$failures, logcat_design$failures)
write_audit_12(failures_design, "group_time_failures.csv")
balance_design <- rbind(raw_design$balance, logcat_design$balance)
required_balance <- merge(balance_design, required_cells, by = c("group", "time", "event_time"))
required_failures <- if (nrow(failures_design) > 0L) {
  merge(failures_design, required_cells, by = c("group", "time", "event_time"))
} else {
  data.frame()
}
write_audit_12(required_failures, "group_time_required_failures.csv")
required_success_status <- required_balance[, c(
  "specification", "group", "time", "event_time",
  "balance_category", "max_abs_mean_difference"
)]
required_failure_status <- if (nrow(required_failures) > 0L) {
  pf <- merge(
    required_failures[, c("specification", "bootstrap_replication", "group",
                          "time", "event_time", "balance_category", "reason")],
    problem_design[, c("specification", "bootstrap_replication", "group",
                       "time", "event_time", "max_abs_mean_difference")],
    by = c("specification", "bootstrap_replication", "group", "time", "event_time"),
    all.x = TRUE
  )
  pf[, c("specification", "group", "time", "event_time",
         "balance_category", "max_abs_mean_difference")]
} else {
  required_success_status[FALSE, ]
}
required_status <- rbind(required_success_status, required_failure_status)
required_status <- required_status[order(required_status$specification,
                                         required_status$group,
                                         required_status$time), ]
write_audit_12(required_status, "group_time_required_cell_status.csv")
residual_summary <- as.data.frame(table(
  specification = required_status$specification,
  balance_category = required_status$balance_category
))
names(residual_summary)[3] <- "n_required_cells"
write_audit_12(residual_summary, "group_time_residual_summary.csv")
n_cat <- function(category) {
  sum(required_status$balance_category == category, na.rm = TRUE)
}
max_category_residual <- function(category) {
  x <- required_status$max_abs_mean_difference[
    required_status$balance_category == category
  ]
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else max(x)
}
supported_counts <- do.call(rbind, lapply(
  c("VR2_entropy_balanced", "VR2B_logged_categorical"),
  function(spec) {
    ss <- required_status[required_status$specification == spec, , drop = FALSE]
    data.frame(
      specification = spec,
      n_required_cells = nrow(ss),
      n_supported_cells = sum(ss$balance_category != "true_feasibility_failure"),
      n_unsupported_cells = sum(ss$balance_category == "true_feasibility_failure"),
      n_exact_pass = sum(ss$balance_category == "exact_pass"),
      n_accepted_numerical_approximation =
        sum(ss$balance_category == "solver_tolerance_residual"),
      max_accepted_residual = max(ss$max_abs_mean_difference[
        ss$balance_category == "solver_tolerance_residual"
      ], na.rm = TRUE)
    )
  }
))
write_audit_12(supported_counts, "supported_cell_counts_by_specification.csv")

composition_rows <- lapply(unique(required_status$specification), function(spec) {
  ss <- required_status[required_status$specification == spec, , drop = FALSE]
  do.call(rbind, lapply(sort(unique(ss$event_time)), function(e) {
    ee <- ss[ss$event_time == e, , drop = FALSE]
    data.frame(
      specification = spec,
      event_time = e,
      n_required_cells = nrow(ee),
      n_supported_cells = sum(ee$balance_category != "true_feasibility_failure"),
      n_unsupported_cells = sum(ee$balance_category == "true_feasibility_failure"),
      supported_groups = paste(sort(unique(ee$group[
        ee$balance_category != "true_feasibility_failure"
      ])), collapse = ";"),
      unsupported_groups = paste(sort(unique(ee$group[
        ee$balance_category == "true_feasibility_failure"
      ])), collapse = ";")
    )
  }))
})
write_audit_12(do.call(rbind, composition_rows),
               "supported_cell_composition_by_event_time.csv")

design_blocked <- !isTRUE(cell_equiv$pass_supported_cell_equivalence)
write_result_12(data.frame(
  run_mode = RUN_MODE,
  bootstrap_iterations = BITERS,
  stage = "design_feasibility",
  status = if (design_blocked) "failed" else "passed_with_unsupported_ebal_cells",
  numerical_acceptance_tolerance = NUMERICAL_ACCEPTANCE_TOL,
  did_supported_key_equality = cell_equiv$supported_key_equality,
  did_overlap_pass_1e_8 = cell_equiv$pass_overlap_1e_8,
  n_custom_only_cells = cell_equiv$n_custom_only_cells,
  n_did_only_cells = cell_equiv$n_did_only_cells,
  n_required_exact_pass = n_cat("exact_pass"),
  n_required_solver_tolerance_residual = n_cat("solver_tolerance_residual"),
  n_required_review_residual = n_cat("review_residual"),
  max_required_solver_tolerance_residual = max_category_residual("solver_tolerance_residual"),
  max_required_review_residual = max_category_residual("review_residual"),
  n_required_true_feasibility_failures = nrow(required_failures),
  block_true_feasibility_failures = FALSE,
  block_review_residuals_unresolved = FALSE,
  block_unmatched_cell_validation = design_blocked,
  n_required_total = nrow(required_status),
  n_required_expected_total = nrow(required_cells) * 2L,
  required_category_counts_reconcile = nrow(required_status) == nrow(required_cells) * 2L
), "feasibility_status.csv")
write_result_12(data.frame(run_mode = RUN_MODE, bootstrap_iterations = BITERS,
                           seed = SEED), "run_mode.csv")
if (design_blocked) {
  stop("did-cell validation blocked outcome estimation; inspect audit/verginer_ebal")
}

estimate_point <- function(data, id_col = "codinv") {
  dynamic_all <- list()
  cells_all <- list()
  warnings_all <- list()
  vr0_all <- cell_engine_multi_12(
    data, OUTCOMES, "VR0_unadjusted", rhs = ~1, method = "unadjusted",
    id_col = id_col, stop_on_failure = FALSE
  )
  vr2_all <- cell_engine_multi_12(
    data, OUTCOMES, "VR2_entropy_balanced", rhs = VR_RAW_RHS, method = "ebal",
    id_col = id_col, stop_on_failure = FALSE
  )
  vr2b_all <- cell_engine_multi_12(
    data, OUTCOMES, "VR2B_logged_categorical", rhs = VR_LOGCAT_RHS,
    method = "ebal", id_col = id_col, stop_on_failure = FALSE
  )
  for (outcome in OUTCOMES) {
    section_12(paste("Point estimates", outcome))
    vr1 <- estimate_did_cells_12(data, outcome, VR_RAW_RHS, "VR1_DR_four_variables",
                                 id_col = id_col)
    specs <- list(
      VR0_unadjusted = vr0_all$cells[vr0_all$cells$outcome == outcome, ],
      VR1_DR_four_variables = vr1$cells,
      VR2_entropy_balanced = vr2_all$cells[vr2_all$cells$outcome == outcome, ],
      VR2B_logged_categorical = vr2b_all$cells[vr2b_all$cells$outcome == outcome, ]
    )
    for (nm in names(specs)) {
      cells <- specs[[nm]]
      dynamic_all[[length(dynamic_all) + 1L]] <- aggregate_cells_12(cells, outcome, nm)
      if (!"outcome" %in% names(cells)) cells$outcome <- outcome
      if (!"pre_time" %in% names(cells)) cells$pre_time <- NA_integer_
      cells <- cells[, c("outcome", "specification", "bootstrap_replication",
                         "group", "time", "event_time", "pre_time", "att",
                         "n_treated", "n_control")]
      cells_all[[length(cells_all) + 1L]] <- cells
    }
    if (length(vr1$warnings)) {
      warnings_all[[length(warnings_all) + 1L]] <- data.frame(
        outcome = outcome, specification = "VR1_DR_four_variables", warning = vr1$warnings
      )
    }
  }
  dynamic <- do.call(rbind, dynamic_all)
  summaries <- do.call(rbind, lapply(seq_len(nrow(unique(dynamic[, c("outcome", "specification")]))), function(i) {
    keys <- unique(dynamic[, c("outcome", "specification")])
    summary_from_dynamic_12(dynamic, keys$outcome[i], keys$specification[i])
  }))
  list(
    dynamic = dynamic,
    summaries = summaries,
    cells = do.call(rbind, cells_all),
    warnings = if (length(warnings_all)) do.call(rbind, warnings_all) else data.frame()
  )
}

point <- estimate_point(complete_panel)
write_result_12(point$cells, "group_time_point_estimates.csv")
write_result_12(point$warnings, "point_estimation_warnings.csv")

existing_full <- utils::read.csv(
  file.path(BASE, "output", "results", "verginer_reconstruction", "five_year_average_att.csv"),
  stringsAsFactors = FALSE
)
existing_full <- existing_full[
  existing_full$specification == "paper_faithful_clustered" &
    existing_full$outcome %in% OUTCOMES,
  c("outcome", "overall_dynamic_att")
]
names(existing_full)[2] <- "existing_full_sample_vr0"

banner_12("Bootstrap inference")
draws <- make_bootstrap_draws_12(units$deal_id, BITERS, SEED)
write_result_12(draws, sprintf("bootstrap_draws_%s.csv", tolower(RUN_MODE)))

boot_dynamic <- list()
boot_fail <- list()
for (b in seq_len(BITERS)) {
  if (b %% 10L == 0L || b == 1L) message("Bootstrap draw ", b, " / ", BITERS)
  draws_b <- draws[draws$bootstrap_replication == b, ]
  bp <- bootstrap_panel_12(complete_panel, draws_b)
  one <- tryCatch(estimate_point(bp, id_col = "boot_uid"), error = function(e) e)
  if (inherits(one, "error")) {
    boot_fail[[length(boot_fail) + 1L]] <- data.frame(
      bootstrap_replication = b, specification = NA_character_, outcome = NA_character_,
      group = NA_integer_, reason = conditionMessage(one)
    )
    next
  }
  bd <- one$dynamic
  bd$bootstrap_replication <- b
  boot_dynamic[[length(boot_dynamic) + 1L]] <- bd
}
boot_dynamic_df <- if (length(boot_dynamic)) do.call(rbind, boot_dynamic) else data.frame()
boot_fail_df <- if (length(boot_fail)) do.call(rbind, boot_fail) else data.frame()
write_result_12(boot_dynamic_df, sprintf("bootstrap_dynamic_%s.csv", tolower(RUN_MODE)))
write_result_12(boot_fail_df, sprintf("bootstrap_failures_%s.csv", tolower(RUN_MODE)))

specs_all <- c("VR0_unadjusted", "VR1_DR_four_variables",
               "VR2_entropy_balanced", "VR2B_logged_categorical")
success_by_spec <- do.call(rbind, lapply(specs_all, function(s) {
  n_success <- length(unique(boot_dynamic_df$bootstrap_replication[
    boot_dynamic_df$specification == s
  ]))
  data.frame(
    run_mode = RUN_MODE, specification = s, attempted = BITERS,
    successful = n_success, success_share = n_success / BITERS,
    pass = n_success / BITERS >= BOOTSTRAP_SUCCESS_MIN
  )
}))
write_result_12(success_by_spec, "bootstrap_success_by_specification.csv")
failure_by_group <- if (nrow(boot_fail_df)) {
  as.data.frame(table(group = boot_fail_df$group, reason = boot_fail_df$reason,
                      useNA = "ifany"))
} else {
  data.frame(group = integer(), reason = character(), Freq = integer())
}
write_result_12(failure_by_group, "bootstrap_failure_by_group.csv")
if (!all(success_by_spec$pass)) {
  stop("Bootstrap success gate failed; inspect bootstrap_success_by_specification.csv")
}

dynamic_final <- add_bootstrap_intervals_12(point$dynamic, boot_dynamic_df)
summary_final <- point$summaries
summaries_with_intervals <- summary_final
summaries_with_intervals$bootstrap_se <- NA_real_
summaries_with_intervals$ci_low <- NA_real_
summaries_with_intervals$ci_high <- NA_real_
for (i in seq_len(nrow(summaries_with_intervals))) {
  od <- boot_dynamic_df[
    boot_dynamic_df$outcome == summaries_with_intervals$outcome[i] &
      boot_dynamic_df$specification == summaries_with_intervals$specification[i], ]
  vals <- tapply(od$att, list(od$bootstrap_replication, od$event_time), mean)
  if (summaries_with_intervals$summary[i] == "event_t0" && "0" %in% colnames(vals)) {
    v <- vals[, "0"]
  } else {
    keep <- intersect(as.character(1:5), colnames(vals))
    v <- rowMeans(vals[, keep, drop = FALSE], na.rm = TRUE)
  }
  v <- v[is.finite(v)]
  if (length(v) >= 2L) {
    summaries_with_intervals$bootstrap_se[i] <- stats::sd(v)
    qs <- stats::quantile(v, c(.025, .975), na.rm = TRUE, names = FALSE)
    summaries_with_intervals$ci_low[i] <- qs[1]
    summaries_with_intervals$ci_high[i] <- qs[2]
  }
}

comparison <- summaries_with_intervals[summaries_with_intervals$summary == "overall_post_t1_to_t5", ]
comparison <- merge(comparison, existing_full, by = "outcome", all.x = TRUE)
comparison$paper_estimate <- PAPER_BENCHMARKS[comparison$outcome]
comparison$difference_from_paper <- comparison$att - comparison$paper_estimate

write_result_12(dynamic_final, "event_study_dynamic.csv")
write_result_12(summaries_with_intervals, "summary_att.csv")
write_result_12(pretrend_12(dynamic_final), "pretrend_diagnostics.csv")
write_result_12(comparison, "verginer_paper_comparison.csv")
write_result_12(data.frame(run_mode = RUN_MODE, bootstrap_iterations = BITERS,
                           seed = SEED), "run_mode.csv")

banner_12("12d complete")
message("Dynamic results: ", file.path(RESULTS_DIR, "event_study_dynamic.csv"))
