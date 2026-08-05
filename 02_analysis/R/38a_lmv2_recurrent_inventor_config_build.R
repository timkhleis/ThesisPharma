if (!exists("lmv2_landmark_config")) {
  source(file.path("02_analysis", "R",
                   "37a_lmv2_stayer_landmark_config_build.R"))
}

lmv2_recurrent_config <- function(
    base = getwd(), output_dir = NULL, parent_exit_dir = NULL) {
  x <- lmv2_exit_config(base)
  audit_root <- file.path(
    x$base, "02_analysis", "output", "audit", "local_match_v2_1993_amendment")
  if (is.null(output_dir)) {
    output_dir <- file.path(audit_root, "P8_RECURRENT_INVENTORS")
  }
  if (is.null(parent_exit_dir)) {
    parent_exit_dir <- file.path(audit_root, "P8_EXIT_DECOMPOSITION")
  }
  x$output_dir <- output_dir
  x$parent_exit_dir <- parent_exit_dir
  x$endpoint_path <- file.path(
    parent_exit_dir, "global_career_endpoints.parquet")
  x$recurrent_weights <- file.path(output_dir, "recurrent_weights.parquet")
  x$recurrent_min_pre_active_years <- 2L
  x$recurrent_balance_variables <- c(
    paste0("patent_count_m", 5:1),
    paste0("active_patenting_m", 5:1))
  x$recurrent_gates <- list(
    treated_deal_retention = 0.50,
    max_absolute_smd = 0.10,
    effective_treated_deals = 20)
  x
}

lmv2_build_recurrent_inventors <- function(
    config = lmv2_recurrent_config(), smoke = FALSE) {
  lmv2_exit_load_runtime(config)
  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
  panel_files <- lmv2_exit_panel_files(config)
  if (smoke) panel_files <- panel_files[1:3]
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(
    con, sprintf("PRAGMA threads=%d", config$execution$threads))
  DBI::dbExecute(
    con, sprintf("PRAGMA memory_limit=%s",
                 lmv2_exit_sql_string(config$execution$memory_limit)))
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE recurrent_base AS
    SELECT
      roster_row_id, CAST(deal_id AS INTEGER) AS deal_id,
      CAST(cohort AS INTEGER) AS cohort, arm,
      CAST(arm='treated' AS INTEGER) AS treated,
      CAST(codinv AS BIGINT) AS codinv,
      CAST(focal_group_1 AS BIGINT) AS control_group,
      MAX(CAST(weight AS DOUBLE)) AS final_weight,
      MAX(CASE WHEN event_time=-5 THEN patent_count END) AS patent_count_m5,
      MAX(CASE WHEN event_time=-4 THEN patent_count END) AS patent_count_m4,
      MAX(CASE WHEN event_time=-3 THEN patent_count END) AS patent_count_m3,
      MAX(CASE WHEN event_time=-2 THEN patent_count END) AS patent_count_m2,
      MAX(CASE WHEN event_time=-1 THEN patent_count END) AS patent_count_m1,
      MAX(CASE WHEN event_time=-5 THEN active_patenting END)
        AS active_patenting_m5,
      MAX(CASE WHEN event_time=-4 THEN active_patenting END)
        AS active_patenting_m4,
      MAX(CASE WHEN event_time=-3 THEN active_patenting END)
        AS active_patenting_m3,
      MAX(CASE WHEN event_time=-2 THEN active_patenting END)
        AS active_patenting_m2,
      MAX(CASE WHEN event_time=-1 THEN active_patenting END)
        AS active_patenting_m1
    FROM %s
    GROUP BY roster_row_id, deal_id, cohort, arm, codinv, focal_group_1
  ", lmv2_exit_panel_sql(panel_files)))
  roster <- data.table::as.data.table(DBI::dbGetQuery(con, "
    SELECT *,
      active_patenting_m5 + active_patenting_m4 +
      active_patenting_m3 + active_patenting_m2 +
      active_patenting_m1 AS pre_active_years
    FROM recurrent_base
  "))
  if (!nrow(roster) || anyDuplicated(roster$roster_row_id)) {
    stop("Recurrent roster is empty or non-unique")
  }
  eligible <- roster[
    pre_active_years >= config$recurrent_min_pre_active_years]
  retention <- roster[, .(
    baseline_inventors = data.table::uniqueN(codinv),
    recurrent_inventors =
      data.table::uniqueN(codinv[
        pre_active_years >= config$recurrent_min_pre_active_years]),
    retention =
      data.table::uniqueN(codinv[
        pre_active_years >= config$recurrent_min_pre_active_years]) /
      data.table::uniqueN(codinv)
  ), by = .(cohort, treated)]
  calibrated <- list()
  solver <- list()
  for (g in sort(unique(eligible$cohort))) {
    z <- eligible[cohort == g]
    if (data.table::uniqueN(z$treated) != 2L) next
    fit <- tryCatch(
      lmv2_landmark_calibrate(
        as.data.frame(z), config$recurrent_balance_variables),
      error = function(e) e)
    if (inherits(fit, "error")) {
      solver[[length(solver) + 1L]] <- data.frame(
        cohort = g, converged = FALSE, rank = NA_integer_,
        max_moment_error = NA_real_, mode = NA_character_,
        message = conditionMessage(fit))
      next
    }
    z[, final_weight_recurrent := fit$weight]
    calibrated[[length(calibrated) + 1L]] <- z
    solver[[length(solver) + 1L]] <- data.frame(
      cohort = g, converged = fit$converged, rank = fit$rank,
      max_moment_error = fit$max_moment_error, mode = fit$mode,
      message = "")
  }
  weights <- data.table::rbindlist(calibrated, fill = TRUE)
  solver <- data.table::rbindlist(solver, fill = TRUE)
  if (!nrow(weights) ||
      !setequal(unique(weights$cohort), unique(eligible$cohort))) {
    lmv2_exit_write_csv(
      solver, file.path(config$output_dir, "recurrent_solver_audit.csv"))
    stop("Recurrent calibration failed in one or more cohorts")
  }
  balance <- data.table::rbindlist(lapply(
    sort(unique(weights$cohort)), function(g) {
      out <- lmv2_landmark_smd(
        as.data.frame(weights[cohort == g]), "treated",
        "final_weight_recurrent", config$recurrent_balance_variables)
      out$cohort <- g
      out
    }))
  treated_base <- roster[treated == 1L]
  treated_keep <- weights[treated == 1L]
  deal_mass <- treated_keep[
    , .(weight = sum(final_weight_recurrent)), by = deal_id]
  overall <- data.frame(
    treated_deal_retention =
      data.table::uniqueN(treated_keep$deal_id) /
      data.table::uniqueN(treated_base$deal_id),
    max_absolute_smd =
      max(abs(balance$standardized_mean_difference)),
    effective_treated_deals =
      sum(deal_mass$weight)^2 / sum(deal_mass$weight^2))
  gates <- data.frame(
    gate = names(config$recurrent_gates),
    value = unlist(overall[1, names(config$recurrent_gates)]),
    threshold = unlist(config$recurrent_gates),
    direction = c(">=", "<=", ">="),
    stringsAsFactors = FALSE)
  gates$pass <- c(
    gates$value[1] >= gates$threshold[1],
    gates$value[2] <= gates$threshold[2],
    gates$value[3] >= gates$threshold[3])
  weights_out <- weights[, .(
    roster_row_id, deal_id, cohort, arm, codinv, treated,
    control_group, pre_active_years,
    final_weight = final_weight_recurrent)]
  DBI::dbWriteTable(
    con, "recurrent_weights_out", as.data.frame(weights_out),
    temporary = TRUE, overwrite = TRUE)
  DBI::dbExecute(con, sprintf("
    COPY recurrent_weights_out TO %s
    (FORMAT PARQUET, COMPRESSION ZSTD)
  ", lmv2_exit_sql_string(config$recurrent_weights)))
  lmv2_exit_write_csv(
    retention,
    file.path(config$output_dir, "recurrent_retention_by_cohort.csv"))
  lmv2_exit_write_csv(
    solver, file.path(config$output_dir, "recurrent_solver_audit.csv"))
  lmv2_exit_write_csv(
    balance, file.path(config$output_dir, "recurrent_balance.csv"))
  lmv2_exit_write_csv(
    gates, file.path(config$output_dir, "recurrent_certification.csv"))
  invisible(list(weights = weights_out, gates = gates))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  smoke <- "--smoke" %in% args
  output_arg <- sub(
    "^--output-dir=", "",
    grep("^--output-dir=", args, value = TRUE))
  parent_arg <- sub(
    "^--parent-exit-dir=", "",
    grep("^--parent-exit-dir=", args, value = TRUE))
  config <- lmv2_recurrent_config(
    output_dir = if (length(output_arg)) output_arg[[1L]] else NULL,
    parent_exit_dir = if (length(parent_arg)) parent_arg[[1L]] else NULL)
  lmv2_build_recurrent_inventors(config, smoke = smoke)
}
