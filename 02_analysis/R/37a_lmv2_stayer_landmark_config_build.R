if (!exists("lmv2_exit_config")) {
  source(file.path("02_analysis", "R",
                   "36a_lmv2_exit_decomposition_config.R"))
}
if (!exists("lmv2_exit_entropy_calibrate")) {
  source(file.path("02_analysis", "R",
                   "36c_estimate_lmv2_exit_decomposition.R"))
}

lmv2_landmark_config <- function(
    base = getwd(), output_dir = NULL, parent_exit_dir = NULL) {
  x <- lmv2_exit_config(base)
  audit_root <- file.path(
    x$base, "02_analysis", "output", "audit", "local_match_v2")
  if (is.null(output_dir)) {
    output_dir <- file.path(audit_root, "P8_STAYER_LANDMARK")
  }
  if (is.null(parent_exit_dir)) {
    parent_exit_dir <- file.path(audit_root, "P8_EXIT_DECOMPOSITION")
  }
  x$output_dir <- output_dir
  x$parent_exit_dir <- parent_exit_dir
  x$endpoint_path <- file.path(
    parent_exit_dir, "global_career_endpoints.parquet")
  x$landmark_weights <- file.path(output_dir, "landmark_weights.parquet")
  x$landmark_post_window <- 2:5
  x$landmark_gates <- list(
    treated_inventor_retention = 0.80,
    treated_deal_retention = 0.85,
    minimum_cohort_retention = 0.50,
    max_absolute_smd = 0.10,
    effective_treated_deals = 20)
  x$landmark_balance_variables <- c(
    paste0("patent_count_m", 5:1),
    paste0("active_patenting_m", 5:1),
    "career_age", "focal_group_exclusivity",
    "firm_log_patent_stock_5y", "firm_log_inventor_count_5y")
  x
}

lmv2_landmark_smd <- function(
    x, treated_col, weight_col, variables) {
  d <- as.integer(x[[treated_col]])
  w <- as.numeric(x[[weight_col]])
  rows <- lapply(variables, function(v) {
    z <- as.numeric(x[[v]])
    mt <- stats::weighted.mean(z[d == 1L], w[d == 1L])
    mc <- stats::weighted.mean(z[d == 0L], w[d == 0L])
    vt <- sum(w[d == 1L] * (z[d == 1L] - mt)^2) /
      sum(w[d == 1L])
    vc <- sum(w[d == 0L] * (z[d == 0L] - mc)^2) /
      sum(w[d == 0L])
    scale <- sqrt((vt + vc) / 2)
    data.frame(
      variable = v, treated_mean = mt, control_mean = mc,
      standardized_mean_difference =
        if (is.finite(scale) && scale > 1e-12) (mt - mc) / scale else 0)
  })
  data.table::rbindlist(rows)
}

lmv2_landmark_calibrate <- function(x, variables) {
  exact <- tryCatch(
    lmv2_exit_entropy_calibrate(
      x, "treated", "final_weight", variables),
    error = function(e) e)
  if (!inherits(exact, "error")) {
    exact$mode <- "exact_entropy"
    return(exact)
  }
  d <- as.integer(x$treated)
  prior <- as.numeric(x$final_weight)
  mat <- as.matrix(x[, variables, drop = FALSE])
  center <- colMeans(mat[d == 0L, , drop = FALSE])
  scale <- apply(mat[d == 0L, , drop = FALSE], 2L, stats::sd)
  keep <- is.finite(scale) & scale > 1e-10
  mat <- sweep(mat[, keep, drop = FALSE], 2L, center[keep], "-")
  mat <- sweep(mat, 2L, scale[keep], "/")
  control <- which(d == 0L)
  treated <- which(d == 1L)
  qr_x <- qr(mat[control, , drop = FALSE])
  use <- qr_x$pivot[seq_len(qr_x$rank)]
  mat <- mat[, use, drop = FALSE]
  target <- drop(crossprod(
    mat[treated, , drop = FALSE], prior[treated]) / sum(prior[treated]))
  candidates <- lapply(c(1e-8, 1e-6, 1e-4, 1e-3, 1e-2, 1e-1),
                       function(ridge) {
    objective <- function(lambda) {
      eta <- drop(mat[control, , drop = FALSE] %*% lambda)
      shift <- max(eta)
      log(sum(prior[control] * exp(eta - shift))) + shift -
        sum(lambda * target) + ridge * sum(lambda^2) / 2
    }
    gradient <- function(lambda) {
      eta <- drop(mat[control, , drop = FALSE] %*% lambda)
      shift <- max(eta)
      tilted <- prior[control] * exp(eta - shift)
      drop(crossprod(
        mat[control, , drop = FALSE], tilted) / sum(tilted)) -
        target + ridge * lambda
    }
    fit <- stats::optim(
      rep(0, ncol(mat)), objective, gradient, method = "BFGS",
      control = list(maxit = 5000, reltol = 1e-12))
    out <- prior
    eta <- drop(mat[control, , drop = FALSE] %*% fit$par)
    out[control] <- prior[control] * exp(eta - max(eta))
    out[control] <- out[control] *
      sum(out[treated]) / sum(out[control])
    moment <- drop(crossprod(
      mat[control, , drop = FALSE], out[control]) /
        sum(out[control])) - target
    list(
      weight = out, max_moment_error = max(abs(moment)),
      rank = ncol(mat), converged = all(is.finite(out)) && all(out > 0),
      mode = paste0("ridge_entropy_", format(ridge, scientific = TRUE)))
  })
  score <- vapply(candidates, `[[`, numeric(1), "max_moment_error")
  candidates[[which.min(score)]]
}

lmv2_build_stayer_landmark <- function(
    config = lmv2_landmark_config(), smoke = FALSE) {
  lmv2_exit_load_runtime(config)
  required <- c(
    config$s3_weights, config$inventor_affiliation,
    config$deal_target_company, config$patent_company_link,
    config$patent_inventor)
  if (any(!file.exists(required))) {
    stop("Missing landmark input: ",
         paste(required[!file.exists(required)], collapse = ", "))
  }
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
    CREATE TEMP TABLE landmark_p6_units AS
    SELECT DISTINCT
      roster_row_id, CAST(deal_id AS INTEGER) AS deal_id,
      CAST(cohort AS INTEGER) AS cohort, arm,
      CAST(codinv AS BIGINT) AS codinv,
      CAST(focal_group_1 AS BIGINT) AS focal_group_1,
      CAST(focal_group_2 AS BIGINT) AS focal_group_2,
      CAST(use_target_company_path AS BOOLEAN) AS use_target_company_path
    FROM %s
    WHERE event_time=-1
  ", lmv2_exit_panel_sql(panel_files)))
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE landmark_s3 AS
    SELECT *
    FROM read_parquet(%s)
    WHERE spec=%s AND support_variant=%s
  ", lmv2_exit_sql_string(config$s3_weights),
     lmv2_exit_sql_string(config$primary_stayer_spec),
     lmv2_exit_sql_string(config$primary_stayer_support)))
  DBI::dbExecute(con, "
    CREATE TEMP TABLE landmark_base AS
    SELECT
      w.*, b.roster_row_id, b.arm, b.focal_group_1, b.focal_group_2,
      b.use_target_company_path
    FROM landmark_s3 w
    JOIN landmark_p6_units b
      ON w.cohort=b.cohort
     AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv
     AND (
       (w.treated=1 AND b.arm='treated') OR
       (w.treated=0 AND b.arm='control'
        AND w.control_group=b.focal_group_1)
     )
  ")
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE landmark_target_patent_t1 AS
    SELECT DISTINCT b.deal_id, b.codinv
    FROM landmark_base b
    JOIN read_parquet(%1$s) pi
      ON CAST(pi.codinv AS BIGINT)=b.codinv
    JOIN read_parquet(%2$s) pcl
      ON CAST(pcl.appln_id AS BIGINT)=CAST(pi.appln_id AS BIGINT)
     AND pcl.year=b.cohort+1
    JOIN read_parquet(%3$s) dtc
      ON dtc.deal_id=b.deal_id
     AND CAST(dtc.target_compcod AS BIGINT)=CAST(pcl.compcod AS BIGINT)
    WHERE b.treated=1 AND b.use_target_company_path
  ", lmv2_exit_sql_string(config$patent_inventor),
     lmv2_exit_sql_string(config$patent_company_link),
     lmv2_exit_sql_string(config$deal_target_company)))
  landmark <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf("
    SELECT b.*,
      CAST(a.resolved_group AS BIGINT) AS resolved_group_t1,
      CAST(
        CASE WHEN b.treated=1 THEN
          (
            CAST(a.resolved_group AS BIGINT)=b.focal_group_1 OR
            CAST(a.resolved_group AS BIGINT)=b.focal_group_2 OR
            tp.codinv IS NOT NULL
          )
        ELSE CAST(a.resolved_group AS BIGINT)=b.control_group
        END AS INTEGER
      ) AS retained_at_t1
    FROM landmark_base b
    LEFT JOIN read_parquet(%s) a
      ON CAST(a.codinv AS BIGINT)=b.codinv
     AND a.year=b.cohort+1
    LEFT JOIN landmark_target_patent_t1 tp
      ON tp.deal_id=b.deal_id AND tp.codinv=b.codinv
  ", lmv2_exit_sql_string(config$inventor_affiliation))))
  if (!nrow(landmark) || anyDuplicated(landmark$roster_row_id)) {
    stop("Landmark roster mapping is empty or non-unique")
  }
  landmark[is.na(retained_at_t1), retained_at_t1 := 0L]
  baseline <- landmark[, .(
    baseline_inventors = data.table::uniqueN(codinv),
    retained_inventors =
      data.table::uniqueN(codinv[retained_at_t1 == 1L]),
    retention =
      data.table::uniqueN(codinv[retained_at_t1 == 1L]) /
      data.table::uniqueN(codinv)
  ), by = .(cohort, treated)]
  eligible <- landmark[retained_at_t1 == 1L]
  if (!nrow(eligible[treated == 1L]) || !nrow(eligible[treated == 0L])) {
    stop("Landmark restriction eliminates a treatment arm")
  }
  calibrated <- list()
  solver <- list()
  for (g in sort(unique(eligible$cohort))) {
    z <- eligible[cohort == g]
    if (data.table::uniqueN(z$treated) != 2L) next
    fit <- tryCatch(
      lmv2_landmark_calibrate(
        as.data.frame(z), config$landmark_balance_variables),
      error = function(e) e)
    if (inherits(fit, "error")) {
      solver[[length(solver) + 1L]] <- data.frame(
        cohort = g, converged = FALSE, rank = NA_integer_,
        max_moment_error = NA_real_, mode = NA_character_,
        message = conditionMessage(fit))
      next
    }
    z[, final_weight_landmark := fit$weight]
    calibrated[[length(calibrated) + 1L]] <- z
    solver[[length(solver) + 1L]] <- data.frame(
      cohort = g, converged = fit$converged, rank = fit$rank,
      max_moment_error = fit$max_moment_error, mode = fit$mode,
      message = "")
  }
  weights <- data.table::rbindlist(calibrated, fill = TRUE)
  solver <- data.table::rbindlist(solver, fill = TRUE)
  expected_cohorts <- sort(unique(eligible$cohort))
  if (!nrow(weights) ||
      !setequal(unique(weights$cohort), expected_cohorts)) {
    lmv2_exit_write_csv(
      solver, file.path(config$output_dir, "landmark_solver_audit.csv"))
    stop("Landmark calibration failed in one or more cohorts")
  }
  balance <- data.table::rbindlist(lapply(
    sort(unique(weights$cohort)), function(g) {
      out <- lmv2_landmark_smd(
        as.data.frame(weights[cohort == g]), "treated",
        "final_weight_landmark", config$landmark_balance_variables)
      out$cohort <- g
      out
    }))
  treated_base <- landmark[treated == 1L]
  treated_keep <- weights[treated == 1L]
  deal_mass <- treated_keep[, .(weight = sum(final_weight_landmark)), by = deal_id]
  overall <- data.frame(
    treated_inventor_retention =
      data.table::uniqueN(treated_keep$codinv) /
      data.table::uniqueN(treated_base$codinv),
    treated_deal_retention =
      data.table::uniqueN(treated_keep$deal_id) /
      data.table::uniqueN(treated_base$deal_id),
    minimum_cohort_retention =
      min(baseline[treated == 1L]$retention),
    max_absolute_smd =
      max(abs(balance$standardized_mean_difference)),
    effective_treated_deals =
      sum(deal_mass$weight)^2 / sum(deal_mass$weight^2))
  gates <- data.frame(
    gate = names(config$landmark_gates),
    value = unlist(overall[1, names(config$landmark_gates)]),
    threshold = unlist(config$landmark_gates),
    direction = c(">=", ">=", ">=", "<=", ">="),
    stringsAsFactors = FALSE)
  gates$pass <- c(
    gates$value[1:3] >= gates$threshold[1:3],
    gates$value[4] <= gates$threshold[4],
    gates$value[5] >= gates$threshold[5])
  weights_out <- weights[, .(
    roster_row_id, deal_id, cohort, arm, codinv, treated,
    control_group, base_weight, final_weight = final_weight_landmark,
    retained_at_t1, resolved_group_t1)]
  DBI::dbWriteTable(
    con, "landmark_weights_out", as.data.frame(weights_out),
    temporary = TRUE, overwrite = TRUE)
  DBI::dbExecute(con, sprintf("
    COPY landmark_weights_out TO %s
    (FORMAT PARQUET, COMPRESSION ZSTD)
  ", lmv2_exit_sql_string(config$landmark_weights)))
  lmv2_exit_write_csv(
    baseline, file.path(config$output_dir, "landmark_retention_by_cohort.csv"))
  lmv2_exit_write_csv(
    solver, file.path(config$output_dir, "landmark_solver_audit.csv"))
  lmv2_exit_write_csv(
    balance, file.path(config$output_dir, "landmark_balance.csv"))
  lmv2_exit_write_csv(
    gates, file.path(config$output_dir, "landmark_certification.csv"))
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
  config <- lmv2_landmark_config(
    output_dir = if (length(output_arg)) output_arg[[1L]] else NULL,
    parent_exit_dir = if (length(parent_arg)) parent_arg[[1L]] else NULL)
  lmv2_build_stayer_landmark(config, smoke = smoke)
}
