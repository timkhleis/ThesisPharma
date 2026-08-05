# ============================================================================
# 36c_estimate_lmv2_exit_decomposition.R
# Reference-anchored exit contrasts and exact three-factor decomposition.
# ============================================================================

if (!exists("lmv2_exit_config")) {
  source(file.path(
    "02_analysis", "R", "36a_lmv2_exit_decomposition_config.R"))
}

lmv2_exit_load_runtime <- function(config) {
  assign(
    "BASE",
    normalizePath(
      file.path(config$base, "02_analysis"),
      winslash = "/", mustWork = TRUE),
    envir = .GlobalEnv)
  source(file.path(config$base, "02_analysis", "R", "00_utils.R"))
  use_project_library()
  shared_lib <- file.path(config$project_root, ".r_libs")
  if (dir.exists(shared_lib)) {
    .libPaths(unique(c(shared_lib, .libPaths())))
  }
  required <- c(
    "DBI", "duckdb", "data.table", "digest", "fixest",
    "fwildclusterboot", "dqrng")
  for (pkg in required) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Missing package: ", pkg)
    }
  }
  source(file.path(config$base, "02_analysis", "R",
                   "15a_lmv2_design_lock.R"))
  source(file.path(config$base, "02_analysis", "R",
                   "18a_lmv2_outcome_config.R"))
  source(file.path(config$base, "02_analysis", "R",
                   "19a_lmv2_p6_estimation_config.R"))
  source(file.path(config$base, "02_analysis", "R",
                   "19b_lmv2_p6_estimation_core.R"))
  invisible(TRUE)
}

lmv2_product3_shapley <- function(treated, control) {
  stopifnot(
    length(treated) == 3L, length(control) == 3L,
    identical(names(treated), names(control)),
    all(is.finite(treated)), all(is.finite(control)))
  out <- setNames(numeric(3L), names(treated))
  for (j in seq_len(3L)) {
    other <- setdiff(seq_len(3L), j)
    k <- other[[1L]]
    l <- other[[2L]]
    out[[j]] <- (treated[[j]] - control[[j]]) * (
      control[[k]] * control[[l]] / 3 +
        treated[[k]] * control[[l]] / 6 +
        control[[k]] * treated[[l]] / 6 +
        treated[[k]] * treated[[l]] / 3)
  }
  if (abs(sum(out) - (prod(treated) - prod(control))) > 1e-12) {
    stop("Three-factor Shapley identity failed")
  }
  out
}

lmv2_exit_factors <- function(y, active, survival) {
  if (!all(is.finite(c(y, active, survival))) ||
      survival <= 0 || active <= 0 ||
      active > survival + 1e-12) {
    stop("Invalid patent/activity/survival means")
  }
  out <- c(
    cessation = survival,
    active_given_survival = active / survival,
    patents_per_active_year = y / active)
  if (abs(prod(out) - y) > 1e-12) {
    stop("Patent factorization failed")
  }
  out
}

lmv2_shapley_factor_jacobian <- function(treated, control) {
  p <- length(treated)
  d_t <- d_c <- matrix(0, p, p)
  for (j in seq_len(p)) {
    other <- setdiff(seq_len(p), j)
    k <- other[[1L]]
    l <- other[[2L]]
    bridge <- control[[k]] * control[[l]] / 3 +
      treated[[k]] * control[[l]] / 6 +
      control[[k]] * treated[[l]] / 6 +
      treated[[k]] * treated[[l]] / 3
    d_t[j, j] <- bridge
    d_c[j, j] <- -bridge
    gap <- treated[[j]] - control[[j]]
    d_t[j, k] <- gap * (control[[l]] / 6 + treated[[l]] / 3)
    d_c[j, k] <- gap * (control[[l]] / 3 + treated[[l]] / 6)
    d_t[j, l] <- gap * (control[[k]] / 6 + treated[[k]] / 3)
    d_c[j, l] <- gap * (control[[k]] / 3 + treated[[k]] / 6)
  }
  list(treated = d_t, control = d_c)
}

lmv2_exit_factor_jacobian <- function(y, active, survival) {
  matrix(c(
    0, 0, 1,
    0, 1 / survival, -active / survival^2,
    1 / active, -y / active^2, 0
  ), nrow = 3L, byrow = TRUE)
}

lmv2_exit_reference_jacobian <- function(y, active) {
  matrix(c(
    0, 0,
    0, 1,
    1 / active, -y / active^2
  ), nrow = 3L, byrow = TRUE)
}

lmv2_exit_decomposition <- function(theta) {
  required <- c(
    "yTpre", "aTpre", "yCpre", "aCpre",
    "yTpost", "aTpost", "sTpost",
    "yCpost", "aCpost", "sCpost")
  if (!identical(names(theta), required)) {
    stop("Unexpected primitive-mean vector")
  }
  f_t_pre <- lmv2_exit_factors(
    theta[["yTpre"]], theta[["aTpre"]], 1)
  f_c_pre <- lmv2_exit_factors(
    theta[["yCpre"]], theta[["aCpre"]], 1)
  f_t_post <- lmv2_exit_factors(
    theta[["yTpost"]], theta[["aTpost"]], theta[["sTpost"]])
  f_c_post <- lmv2_exit_factors(
    theta[["yCpost"]], theta[["aCpost"]], theta[["sCpost"]])
  components <- lmv2_product3_shapley(f_t_post, f_c_post) -
    lmv2_product3_shapley(f_t_pre, f_c_pre)
  total <- (theta[["yTpost"]] - theta[["yCpost"]]) -
    (theta[["yTpre"]] - theta[["yCpre"]])
  if (abs(sum(components) - total) > 1e-12) {
    stop("Reference-anchored DiD identity failed")
  }

  g_pre <- lmv2_shapley_factor_jacobian(f_t_pre, f_c_pre)
  g_post <- lmv2_shapley_factor_jacobian(f_t_post, f_c_post)
  gradient <- matrix(
    0, nrow = 3L, ncol = length(theta),
    dimnames = list(names(components), names(theta)))
  gradient[, 1:2] <- -g_pre$treated %*%
    lmv2_exit_reference_jacobian(theta[["yTpre"]], theta[["aTpre"]])
  gradient[, 3:4] <- -g_pre$control %*%
    lmv2_exit_reference_jacobian(theta[["yCpre"]], theta[["aCpre"]])
  gradient[, 5:7] <- g_post$treated %*%
    lmv2_exit_factor_jacobian(
      theta[["yTpost"]], theta[["aTpost"]], theta[["sTpost"]])
  gradient[, 8:10] <- g_post$control %*%
    lmv2_exit_factor_jacobian(
      theta[["yCpost"]], theta[["aCpost"]], theta[["sCpost"]])
  gradient <- rbind(gradient, total = colSums(gradient))
  value <- c(components, total = total)
  list(value = value, gradient = gradient)
}

lmv2_exit_decomposition_raw <- function(theta) {
  f_t_pre <- lmv2_exit_factors(
    theta[["yTpre"]], theta[["aTpre"]], theta[["sTpre"]])
  f_c_pre <- lmv2_exit_factors(
    theta[["yCpre"]], theta[["aCpre"]], theta[["sCpre"]])
  f_t_post <- lmv2_exit_factors(
    theta[["yTpost"]], theta[["aTpost"]], theta[["sTpost"]])
  f_c_post <- lmv2_exit_factors(
    theta[["yCpost"]], theta[["aCpost"]], theta[["sCpost"]])
  components <- lmv2_product3_shapley(f_t_post, f_c_post) -
    lmv2_product3_shapley(f_t_pre, f_c_pre)
  c(components, total = sum(components))
}

lmv2_product2_shapley <- function(treated, control) {
  c(
    extensive = (treated[[1L]] - control[[1L]]) *
      (treated[[2L]] + control[[2L]]) / 2,
    intensive = (treated[[2L]] - control[[2L]]) *
      (treated[[1L]] + control[[1L]]) / 2)
}

lmv2_exit_decomposition_two_factor <- function(theta) {
  pre <- lmv2_product2_shapley(
    c(theta[["aTpre"]], theta[["yTpre"]] / theta[["aTpre"]]),
    c(theta[["aCpre"]], theta[["yCpre"]] / theta[["aCpre"]]))
  post <- lmv2_product2_shapley(
    c(theta[["aTpost"]], theta[["yTpost"]] / theta[["aTpost"]]),
    c(theta[["aCpost"]], theta[["yCpost"]] / theta[["aCpost"]]))
  out <- post - pre
  c(out, total = sum(out))
}

lmv2_exit_numeric_gradient <- function(fun, theta) {
  value <- fun(theta)
  out <- matrix(
    NA_real_, nrow = length(value), ncol = length(theta),
    dimnames = list(names(value), names(theta)))
  for (j in seq_along(theta)) {
    h <- max(1e-8, abs(theta[[j]]) * 1e-6)
    up <- down <- theta
    up[[j]] <- up[[j]] + h
    down[[j]] <- down[[j]] - h
    out[, j] <- (fun(up) - fun(down)) / (2 * h)
  }
  out
}

lmv2_exit_fixture_checks <- function() {
  names10 <- c(
    "yTpre", "aTpre", "yCpre", "aCpre",
    "yTpost", "aTpost", "sTpost",
    "yCpost", "aCpost", "sCpost")
  theta <- setNames(
    c(.35, .20, .34, .20, .24, .14, .52, .30, .17, .58),
    names10)
  fit <- lmv2_exit_decomposition(theta)
  numeric <- lmv2_exit_numeric_gradient(
    function(x) lmv2_exit_decomposition(x)$value, theta)
  pure <- list(
    cessation = setNames(
      c(.4, .2, .4, .2, .3, .15, .6, .4, .2, .8), names10),
    activity = setNames(
      c(.4, .2, .4, .2, .24, .12, .6, .4, .2, .6), names10),
    intensity = setNames(
      c(.4, .2, .4, .2, .18, .15, .6, .3, .15, .6), names10))
  pure_values <- lapply(pure, function(x) {
    lmv2_exit_decomposition(x)$value[1:3]
  })
  data.frame(
    check = c(
      "analytic_numeric_gradient_agree",
      "mixed_identity",
      "pure_cessation",
      "pure_activity",
      "pure_intensity"),
    pass = c(
      max(abs(fit$gradient - numeric)) < 1e-6,
      abs(sum(fit$value[1:3]) - fit$value[["total"]]) < 1e-12,
      max(abs(pure_values$cessation[2:3])) < 1e-12,
      max(abs(pure_values$activity[c(1, 3)])) < 1e-12,
      max(abs(pure_values$intensity[1:2])) < 1e-12),
    detail = c(
      max(abs(fit$gradient - numeric)),
      abs(sum(fit$value[1:3]) - fit$value[["total"]]),
      max(abs(pure_values$cessation[2:3])),
      max(abs(pure_values$activity[c(1, 3)])),
      max(abs(pure_values$intensity[1:2]))),
    stringsAsFactors = FALSE)
}

lmv2_exit_cr1 <- function(influence, group) {
  sums <- rowsum(influence, group = group, reorder = FALSE)
  sums <- sweep(sums, 2L, colMeans(sums), "-")
  g <- nrow(sums)
  if (g < 2L) stop("Fewer than two clusters")
  list(vcov = g / (g - 1) * crossprod(sums), clusters = g)
}

lmv2_exit_two_way_covariance <- function(influence, deal, inventor) {
  d <- lmv2_exit_cr1(influence, deal)
  i <- lmv2_exit_cr1(influence, inventor)
  x <- lmv2_exit_cr1(influence, interaction(
    deal, inventor, drop = TRUE, lex.order = TRUE))
  two <- d$vcov + i$vcov - x$vcov
  if (any(diag(two) < -1e-10)) {
    stop("Materially negative two-way variance")
  }
  diag(two) <- pmax(diag(two), 0)
  list(
    two_way = two, deal = d$vcov,
    n_deal = d$clusters, n_inventor = i$clusters,
    n_intersection = x$clusters)
}

lmv2_exit_prepare_panels <- function(config, con, smoke = FALSE) {
  panel_files <- lmv2_exit_panel_files(config)
  stamp_files <- sort(list.files(
    config$panel_dir,
    pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$",
    full.names = TRUE))
  if (smoke) {
    panel_files <- panel_files[1:3]
    stamp_files <- stamp_files[1:3]
  } else {
    checks <- lmv2_validate_estimation_inputs(
      con, panel_files, stamp_files, config$p6_manifest)
    if (!isTRUE(checks$pass[[1L]])) {
      stop("Certified P6 input validation failed")
    }
  }
  panel_sql <- lmv2_exit_panel_sql(panel_files)
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE p8_base_panel AS
    SELECT
      roster_row_id, CAST(deal_id AS INTEGER) AS deal_id,
      CAST(cohort AS INTEGER) AS cohort, arm,
      CAST(codinv AS BIGINT) AS codinv,
      CAST(focal_group_1 AS BIGINT) AS focal_group_1,
      CAST(event_time AS INTEGER) AS event_time,
      CAST(calendar_year AS INTEGER) AS calendar_year,
      CAST(weight AS DOUBLE) AS weight,
      CAST(patent_count AS DOUBLE) AS patent_count,
      CAST(active_patenting AS DOUBLE) AS active_patenting
    FROM %s
  ", panel_sql))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE p8_k3_continuation AS
    SELECT
      p.roster_row_id, p.event_time,
      CASE
        WHEN p.calendar_year + %1$d > %2$d THEN NULL
        ELSE CAST(COUNT(iy.year) > 0 AS INTEGER)
      END AS survival_k3
    FROM p8_base_panel p
    LEFT JOIN read_parquet(%3$s) iy
      ON CAST(iy.codinv AS BIGINT) = p.codinv
     AND iy.patent_count > 0
     AND iy.year BETWEEN p.calendar_year
                     AND p.calendar_year + %1$d
     AND iy.year <= %2$d
    GROUP BY p.roster_row_id, p.event_time, p.calendar_year
  ", config$fixed_lookahead_years, config$observation_end_year,
     lmv2_exit_sql_string(config$inventor_year)))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE exit_panel AS
    SELECT
      p.*, e.global_last_patent_year,
      CAST(
        p.calendar_year <= e.global_last_patent_year AS INTEGER
      ) AS patenting_survival,
      CAST(
        p.calendar_year > e.global_last_patent_year AS INTEGER
      ) AS patenting_exit,
      CASE WHEN p.event_time < 0 THEN 0 ELSE CAST(
        p.calendar_year > e.global_last_patent_year AS INTEGER
      ) END AS patenting_exit_anchored,
      CAST(
        p.calendar_year = e.global_last_patent_year + 1 AS INTEGER
      ) AS patenting_exit_onset,
      k.survival_k3
    FROM p8_base_panel p
    JOIN read_parquet(%s) e USING (codinv)
    JOIN p8_k3_continuation k USING (roster_row_id, event_time)
  ", lmv2_exit_sql_string(config$endpoint_path)))

  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE p8_s3_weights AS
    SELECT * FROM read_parquet(%s)
    WHERE spec=%s
  ", lmv2_exit_sql_string(config$s3_weights),
     lmv2_exit_sql_string(config$primary_stayer_spec)))
  DBI::dbExecute(con, "
    CREATE OR REPLACE TEMP TABLE p8_stayer_map AS
    WITH base_units AS (
      SELECT roster_row_id, deal_id, cohort, arm, codinv, focal_group_1
      FROM p8_base_panel WHERE event_time=-1
    ), treated_map AS (
      SELECT b.roster_row_id, w.final_weight
      FROM p8_s3_weights w
      JOIN base_units b
        ON w.cohort=b.cohort
       AND w.deal_id=b.deal_id
       AND w.codinv=b.codinv
       AND b.arm='treated'
      WHERE w.treated=1
    ), control_map AS (
      SELECT b.roster_row_id, w.final_weight
      FROM p8_s3_weights w
      JOIN base_units b
        ON w.cohort=b.cohort
       AND w.deal_id=b.deal_id
       AND w.codinv=b.codinv
       AND w.control_group=b.focal_group_1
       AND b.arm='control'
      WHERE w.treated=0
    )
    SELECT * FROM treated_map
    UNION ALL
    SELECT * FROM control_map
  ")
  DBI::dbExecute(con, "
    CREATE OR REPLACE TEMP TABLE stayer_exit_panel AS
    SELECT p.* EXCLUDE(weight), CAST(m.final_weight AS DOUBLE) AS weight
    FROM exit_panel p
    JOIN p8_stayer_map m USING (roster_row_id)
  ")

  checks <- DBI::dbGetQuery(con, "
    WITH full_units AS (
      SELECT roster_row_id, COUNT(*) n, MIN(event_time) min_e,
             MAX(event_time) max_e
      FROM exit_panel GROUP BY roster_row_id
    ), full_mass AS (
      SELECT cohort,
        SUM(weight) FILTER (WHERE arm='treated' AND event_time=-1) tm,
        SUM(weight) FILTER (WHERE arm='control' AND event_time=-1) cm
      FROM exit_panel GROUP BY cohort
    ), stayer_units AS (
      SELECT roster_row_id, COUNT(*) n, MIN(event_time) min_e,
             MAX(event_time) max_e
      FROM stayer_exit_panel GROUP BY roster_row_id
    ), stayer_mass AS (
      SELECT cohort,
        SUM(weight) FILTER (WHERE arm='treated' AND event_time=-1) tm,
        SUM(weight) FILTER (WHERE arm='control' AND event_time=-1) cm
      FROM stayer_exit_panel GROUP BY cohort
    )
    SELECT
      (SELECT COUNT(*) FROM full_units) full_units,
      (SELECT COUNT(*) FROM full_units
       WHERE n<>11 OR min_e<>-5 OR max_e<>5) full_bad_units,
      (SELECT COUNT(*) FROM full_mass WHERE ABS(tm-cm)>1e-7)
        full_bad_masses,
      (SELECT COUNT(*) FROM stayer_units) stayer_units,
      (SELECT COUNT(*) FROM stayer_units
       WHERE n<>11 OR min_e<>-5 OR max_e<>5) stayer_bad_units,
      (SELECT COUNT(*) FROM stayer_mass WHERE ABS(tm-cm)>1e-7)
        stayer_bad_masses,
      (SELECT COUNT(*) FROM exit_panel
       WHERE patent_count>0 AND patenting_survival<>1)
        patent_survival_violations,
      (SELECT COUNT(*) FROM exit_panel
       WHERE patenting_exit + patenting_survival<>1)
        partition_violations,
      (SELECT COUNT(*) FROM exit_panel
       WHERE event_time<0 AND patenting_exit_anchored<>0)
        anchor_violations
  ")
  checks$pass <- with(
    checks,
    full_bad_units == 0L && full_bad_masses == 0L &&
      stayer_bad_units == 0L && stayer_bad_masses == 0L &&
      patent_survival_violations == 0L &&
      partition_violations == 0L && anchor_violations == 0L)
  if (!isTRUE(checks$pass[[1L]])) {
    stop("Joined exit-panel certification failed")
  }
  checks
}

lmv2_exit_extract_panel <- function(con, relation) {
  data.table::as.data.table(DBI::dbGetQuery(con, sprintf("
    SELECT
      roster_row_id, deal_id, cohort, arm,
      CAST(arm='treated' AS INTEGER) AS treated,
      codinv, event_time, calendar_year, weight,
      patent_count AS y, active_patenting AS active,
      patenting_survival AS survival,
      survival_k3
    FROM %s
  ", relation)))
}

lmv2_exit_design_shares <- function(dt, cohorts) {
  out <- dt[
    cohort %in% cohorts & event_time == -1L & treated == 1L,
    .(design_mass = sum(weight)), by = cohort]
  out[, q_g := design_mass / sum(design_mass)]
  out
}

lmv2_exit_cell_means <- function(dt, cohorts, events, survival_col) {
  x <- dt[cohort %in% cohorts & event_time %in% events]
  x[, survival_used := get(survival_col)]
  x[, .(
    mass = sum(weight),
    y = weighted.mean(y, weight),
    active = weighted.mean(active, weight),
    survival = if (all(is.na(survival_used))) NA_real_ else
      weighted.mean(survival_used, weight, na.rm = TRUE),
    survival_raw = weighted.mean(survival, weight),
    active_ess = {
      wa <- weight * active
      if (sum(wa^2) > 0) sum(wa)^2 / sum(wa^2) else 0
    }
  ), by = .(cohort, event_time, treated, arm)]
}

lmv2_exit_event_weights <- function(cells, shares, events) {
  eligible <- cells[event_time %in% events & is.finite(survival),
                    .(arms = data.table::uniqueN(arm), min_mass = min(mass)),
                    by = .(cohort, event_time)]
  eligible <- eligible[arms == 2L & min_mass > 0]
  eligible <- merge(eligible, shares, by = "cohort", all.x = TRUE)
  eligible[, retained_design_share := sum(q_g), by = event_time]
  eligible[, q_event := q_g / retained_design_share]
  eligible
}

lmv2_exit_theta <- function(cells, cohort, event_time) {
  pull_mean <- function(period, treated, variable) {
    cohort_value <- cohort
    treated_value <- treated
    keep <- cells$cohort == cohort_value &
      cells$event_time == period &
      cells$treated == treated_value
    z <- cells[[variable]][keep]
    if (length(z) != 1L) stop("Missing cohort-arm-period primitive")
    z
  }
  c(
    yTpre = pull_mean(-1L, 1L, "y"),
    aTpre = pull_mean(-1L, 1L, "active"),
    yCpre = pull_mean(-1L, 0L, "y"),
    aCpre = pull_mean(-1L, 0L, "active"),
    yTpost = pull_mean(event_time, 1L, "y"),
    aTpost = pull_mean(event_time, 1L, "active"),
    sTpost = pull_mean(event_time, 1L, "survival"),
    yCpost = pull_mean(event_time, 0L, "y"),
    aCpost = pull_mean(event_time, 0L, "active"),
    sCpost = pull_mean(event_time, 0L, "survival"))
}

lmv2_exit_theta_raw <- function(theta, cells, cohort) {
  pull_survival <- function(treated) {
    cohort_value <- cohort
    treated_value <- treated
    keep <- cells$cohort == cohort_value &
      cells$event_time == -1L &
      cells$treated == treated_value
    z <- cells$survival_raw[keep]
    if (length(z) != 1L) stop("Missing raw reference survival")
    z
  }
  c(
    theta[c("yTpre", "aTpre")], sTpre = pull_survival(1L),
    theta[c("yCpre", "aCpre")], sCpre = pull_survival(0L),
    theta[c(
      "yTpost", "aTpost", "sTpost",
      "yCpost", "aCpost", "sCpost")])
}

lmv2_exit_add_mean_if <- function(
    influence, dt, index, variable, mean_value, mass, derivative, scale) {
  primitive <- dt$weight[index] / mass *
    (dt[[variable]][index] - mean_value)
  influence[index, ] <- influence[index, , drop = FALSE] +
    scale * outer(primitive, derivative)
  influence
}

lmv2_estimate_exit_decomposition <- function(
    dt, cohorts, post_window, sample, population,
    survival_col = "survival", endpoint_definition = "global_endpoint",
    active_ess_floor = 20) {
  events <- c(-1L, as.integer(post_window))
  dt <- data.table::copy(
    dt[cohort %in% cohorts & event_time %in% events])
  cells <- lmv2_exit_cell_means(
    dt, cohorts, events, survival_col)
  shares <- lmv2_exit_design_shares(dt, cohorts)
  weights <- lmv2_exit_event_weights(cells, shares, post_window)
  if (!nrow(weights)) stop("No eligible cohort-event cells")
  components <- c(
    "cessation", "active_given_survival",
    "patents_per_active_year", "total")
  estimate <- setNames(numeric(4L), components)
  old_estimate <- setNames(numeric(3L), c(
    "extensive", "intensive", "total"))
  raw_estimate <- setNames(numeric(4L), components)
  influence <- matrix(
    0, nrow = nrow(dt), ncol = 4L,
    dimnames = list(NULL, components))
  dt[, row_index__ := .I]
  n_events <- length(post_window)

  for (r in seq_len(nrow(weights))) {
    g <- weights$cohort[[r]]
    event <- weights$event_time[[r]]
    scale <- weights$q_event[[r]] / n_events
    theta <- lmv2_exit_theta(cells, g, event)
    boundary_cell <- any(theta[c(
      "aTpre", "aCpre", "aTpost", "aCpost",
      "sTpost", "sCpost")] <= 1e-12) ||
      theta[["aTpost"]] > theta[["sTpost"]] + 1e-12 ||
      theta[["aCpost"]] > theta[["sCpost"]] + 1e-12
    theta_eval <- theta
    if (boundary_cell) {
      # A conditional patent rate is unidentified when an arm has no active
      # patenting. The zero-patent product is represented by a zero rate at an
      # epsilon activity level for point accounting. Component inference is
      # suppressed below by the active-ESS gate; only the exactly identified
      # total-ATT gradient is retained for this boundary cell.
      active_names <- c("aTpre", "aCpre", "aTpost", "aCpost")
      theta_eval[active_names] <- pmax(theta_eval[active_names], 1e-12)
      theta_eval[["sTpost"]] <- max(
        theta_eval[["sTpost"]], theta_eval[["aTpost"]], 1e-12)
      theta_eval[["sCpost"]] <- max(
        theta_eval[["sCpost"]], theta_eval[["aCpost"]], 1e-12)
    }
    fit <- lmv2_exit_decomposition(theta_eval)
    if (boundary_cell) {
      fit$gradient[1:3, ] <- 0
    }
    estimate <- estimate + scale * fit$value
    old_estimate <- old_estimate +
      scale * lmv2_exit_decomposition_two_factor(theta_eval)
    raw_estimate <- raw_estimate + scale *
      lmv2_exit_decomposition_raw(
        {
          raw_theta <- lmv2_exit_theta_raw(theta_eval, cells, g)
          active_names <- c("aTpre", "aCpre", "aTpost", "aCpost")
          raw_theta[active_names] <- pmax(raw_theta[active_names], 1e-12)
          raw_theta[["sTpre"]] <- max(
            raw_theta[["sTpre"]], raw_theta[["aTpre"]], 1e-12)
          raw_theta[["sCpre"]] <- max(
            raw_theta[["sCpre"]], raw_theta[["aCpre"]], 1e-12)
          raw_theta[["sTpost"]] <- max(
            raw_theta[["sTpost"]], raw_theta[["aTpost"]], 1e-12)
          raw_theta[["sCpost"]] <- max(
            raw_theta[["sCpost"]], raw_theta[["aCpost"]], 1e-12)
          raw_theta
        })

    map <- list(
      yTpre = list(-1L, 1L, "y"),
      aTpre = list(-1L, 1L, "active"),
      yCpre = list(-1L, 0L, "y"),
      aCpre = list(-1L, 0L, "active"),
      yTpost = list(event, 1L, "y"),
      aTpost = list(event, 1L, "active"),
      sTpost = list(event, 1L, survival_col),
      yCpost = list(event, 0L, "y"),
      aCpost = list(event, 0L, "active"),
      sCpost = list(event, 0L, survival_col))
    for (parameter in names(map)) {
      spec <- map[[parameter]]
      ix <- dt[
        cohort == g & event_time == spec[[1L]] &
          treated == spec[[2L]], row_index__]
      cell <- cells[
        cohort == g & event_time == spec[[1L]] &
          treated == spec[[2L]]]
      mean_name <- if (startsWith(parameter, "s")) "survival" else spec[[3L]]
      influence <- lmv2_exit_add_mean_if(
        influence, dt, ix, spec[[3L]],
        cell[[mean_name]][[1L]], cell$mass[[1L]],
        fit$gradient[, parameter], scale)
    }
  }
  dt[, row_index__ := NULL]
  if (max(abs(colSums(influence))) > 1e-8) {
    stop("Component influence functions do not sum to zero")
  }
  covariance <- lmv2_exit_two_way_covariance(
    influence, dt$deal_id, dt$codinv)
  se <- sqrt(diag(covariance$two_way))
  df <- min(covariance$n_deal, covariance$n_inventor) - 1L
  crit <- stats::qt(.975, df)
  min_active_ess <- min(cells[
    event_time %in% post_window, active_ess], na.rm = TRUE)
  interval_released <- min_active_ess >= active_ess_floor
  out <- data.frame(
    population = population, sample = sample,
    endpoint_definition = endpoint_definition,
    component = components, estimate = estimate,
    se = se, df = df,
    ci_low = estimate - crit * se,
    ci_high = estimate + crit * se,
    post_years = length(post_window),
    cumulative_post_window_patents = estimate * length(post_window),
    share_of_total = estimate / estimate[["total"]],
    min_active_ess = min_active_ess,
    interval_released = interval_released,
    identity_error = abs(sum(estimate[1:3]) - estimate[["total"]]),
    stringsAsFactors = FALSE)
  if (!interval_released) {
    k <- out$component != "total"
    out$se[k] <- out$ci_low[k] <- out$ci_high[k] <- NA_real_
  }
  old <- data.frame(
    population = population, sample = sample,
    decomposition = "certified_two_factor_recalculation",
    component = names(old_estimate), estimate = old_estimate,
    stringsAsFactors = FALSE)
  raw <- data.frame(
    population = population, sample = sample,
    decomposition = "raw_reference_survival_sensitivity",
    endpoint_definition = endpoint_definition,
    component = names(raw_estimate), estimate = raw_estimate,
    stringsAsFactors = FALSE)
  factor_rows <- merge(
    cells, weights[, .(
      cohort, event_time, q_g, retained_design_share, q_event)],
    by = c("cohort", "event_time"), all.x = TRUE)
  factor_rows$population <- population
  factor_rows$sample <- sample
  factor_rows$endpoint_definition <- endpoint_definition
  list(
    components = out, influence = influence,
    covariance = covariance, factor_means = factor_rows,
    weights = weights, two_factor = old, raw = raw)
}

lmv2_exit_dynamic_contrast <- function(
    dt, cohorts, post_window, sample, population,
    bootstrap_reps = 0L, run_wild = FALSE) {
  events <- sort(unique(c(0L, as.integer(post_window))))
  x <- dt[cohort %in% cohorts & event_time %in% c(-1L, events)]
  x[, exit := 1 - survival]
  shares <- lmv2_exit_design_shares(x, cohorts)
  cells <- x[event_time %in% events, .(
    mass = sum(weight),
    mean_exit = weighted.mean(exit, weight)
  ), by = .(cohort, event_time, treated, arm)]
  eligible <- cells[, .(
    arms = data.table::uniqueN(arm), min_mass = min(mass)),
    by = .(cohort, event_time)][arms == 2L & min_mass > 0]
  eligible <- merge(eligible, shares, by = "cohort")
  eligible[, retained_design_share := sum(q_g), by = event_time]
  eligible[, q_event := q_g / retained_design_share]
  influence <- matrix(
    0, nrow = nrow(x), ncol = length(events),
    dimnames = list(NULL, as.character(events)))
  estimate <- setNames(numeric(length(events)), as.character(events))
  x[, row_index__ := .I]
  for (r in seq_len(nrow(eligible))) {
    g <- eligible$cohort[[r]]
    event <- eligible$event_time[[r]]
    q <- eligible$q_event[[r]]
    for (arm in 0:1) {
      arm_value <- arm
      cell <- cells[
        cohort == g & event_time == event & treated == arm_value]
      ix <- x[
        cohort == g & event_time == event &
          treated == arm_value, row_index__]
      sign <- if (arm == 1L) 1 else -1
      estimate[[as.character(event)]] <-
        estimate[[as.character(event)]] +
        sign * q * cell$mean_exit[[1L]]
      influence[ix, as.character(event)] <-
        influence[ix, as.character(event)] +
        sign * q * x$weight[ix] / cell$mass[[1L]] *
        (x$exit[ix] - cell$mean_exit[[1L]])
    }
  }
  x[, row_index__ := NULL]
  covariance <- lmv2_exit_two_way_covariance(
    influence, x$deal_id, x$codinv)
  se <- sqrt(diag(covariance$two_way))
  df <- min(covariance$n_deal, covariance$n_inventor) - 1L
  crit <- stats::qt(.975, df)
  dynamic <- data.frame(
    population = population, sample = sample,
    event_time = events, estimate = estimate,
    se = se, df = df,
    ci_low = estimate - crit * se,
    ci_high = estimate + crit * se,
    inference = "two_way_deal_inventor",
    stringsAsFactors = FALSE)
  dynamic <- rbind(data.frame(
    population = population, sample = sample,
    event_time = -1L, estimate = 0, se = 0, df = df,
    ci_low = 0, ci_high = 0, inference = "reference_anchor",
    stringsAsFactors = FALSE), dynamic)

  keep <- match(as.character(post_window), colnames(influence))
  avg_if <- rowMeans(influence[, keep, drop = FALSE])
  avg_estimate <- mean(estimate[as.character(post_window)])
  avg_cov <- lmv2_exit_two_way_covariance(
    matrix(avg_if, ncol = 1L), x$deal_id, x$codinv)
  analytic <- lapply(
    c("two_way", "deal"), function(which) {
      se0 <- sqrt(avg_cov[[which]][1, 1])
      df0 <- avg_cov$n_deal - 1L
      crit0 <- stats::qt(.975, df0)
      data.frame(
        inference = if (which == "two_way")
          "two_way_deal_inventor" else "deal_cluster_robust",
        estimate = avg_estimate, se = se0, df = df0,
        ci_low = avg_estimate - crit0 * se0,
        ci_high = avg_estimate + crit0 * se0,
        p_value = 2 * stats::pt(-abs(avg_estimate / se0), df0),
        ci_method = "analytic_cluster_t",
        stringsAsFactors = FALSE)
    })
  headline <- do.call(rbind, analytic)

  if (run_wild && bootstrap_reps >= 99L) {
    deal_cells <- x[event_time %in% post_window, .(
      cell_mass = sum(weight),
      exit_mean = weighted.mean(exit, weight)),
      by = .(deal_id, cohort, event_time, treated, arm)]
    arm_mass <- deal_cells[, .(arm_mass = sum(cell_mass)),
                           by = .(cohort, event_time, treated, arm)]
    deal_cells <- merge(
      deal_cells, arm_mass,
      by = c("cohort", "event_time", "treated", "arm"))
    deal_cells <- merge(
      deal_cells, eligible[, .(cohort, event_time, q_event)],
      by = c("cohort", "event_time"))
    deal_cells[, analysis_weight :=
                 cell_mass / arm_mass * q_event / length(post_window)]
    deal_cells[, cohort_event_id := cohort * 100L + event_time + 10L]
    model <- fixest::feols(
      exit_mean ~ treated | cohort_event_id,
      data = deal_cells, weights = ~analysis_weight,
      cluster = ~deal_id, fixef.rm = "none", notes = FALSE)
    if (abs(unname(stats::coef(model)[["treated"]]) - avg_estimate) > 1e-9) {
      stop("Anchored-exit compact regression tooth check failed")
    }
    wild <- lmv2_wild_post(model, bootstrap_reps)
    headline <- rbind(wild, headline)
  }
  headline$population <- population
  headline$sample <- sample
  headline$summary <- paste0(
    "average_annual_t", min(post_window), "_to_t", max(post_window))
  headline$bootstrap_replications <- ifelse(
    headline$inference == "deal_wild_bootstrap_t",
    bootstrap_reps, NA_integer_)
  widths <- headline$ci_high - headline$ci_low
  headline$governing <- widths == max(
    widths[headline$inference %in%
             c("deal_wild_bootstrap_t", "two_way_deal_inventor")])
  list(dynamic = dynamic, headline = headline)
}

lmv2_exit_reference_support <- function(dt, cohorts, sample, population) {
  x <- dt[cohort %in% cohorts & event_time == -1L]
  shares <- lmv2_exit_design_shares(x, cohorts)
  cells <- x[, .(
    mass = sum(weight),
    survival = weighted.mean(survival, weight),
    active_reference = weighted.mean(active, weight),
    later_patent_only = weighted.mean(survival - active, weight)
  ), by = .(cohort, arm)]
  cells <- merge(cells, shares[, .(cohort, q_g)], by = "cohort")
  arm <- cells[, .(
    survival = sum(q_g * survival),
    active_reference = sum(q_g * active_reference),
    later_patent_only = sum(q_g * later_patent_only)
  ), by = arm]
  gap <- data.frame(
    arm = "treated_minus_control",
    survival = arm[arm == "treated", survival] -
      arm[arm == "control", survival],
    active_reference = arm[arm == "treated", active_reference] -
      arm[arm == "control", active_reference],
    later_patent_only = arm[arm == "treated", later_patent_only] -
      arm[arm == "control", later_patent_only])
  out <- rbind(as.data.frame(arm), gap)
  out$population <- population
  out$sample <- sample
  out
}

lmv2_exit_entropy_calibrate <- function(
    x, treated_col, weight_col, variables) {
  d <- as.integer(x[[treated_col]])
  prior <- as.numeric(x[[weight_col]])
  if (any(!is.finite(prior) | prior <= 0)) {
    stop("Invalid calibration prior weights")
  }
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
  objective <- function(lambda) {
    eta <- drop(mat[control, , drop = FALSE] %*% lambda)
    shift <- max(eta)
    tilted <- prior[control] * exp(eta - shift)
    log(sum(tilted)) + shift - sum(lambda * target)
  }
  gradient <- function(lambda) {
    eta <- drop(mat[control, , drop = FALSE] %*% lambda)
    shift <- max(eta)
    tilted <- prior[control] * exp(eta - shift)
    drop(crossprod(
      mat[control, , drop = FALSE], tilted) / sum(tilted)) - target
  }
  fit <- stats::optim(
    rep(0, ncol(mat)), objective, gradient,
    method = "BFGS", control = list(maxit = 5000, reltol = 1e-12))
  if (fit$convergence != 0L || max(abs(gradient(fit$par))) > 1e-7) {
    stop("Entropy calibration did not converge")
  }
  out <- prior
  eta <- drop(mat[control, , drop = FALSE] %*% fit$par)
  out[control] <- prior[control] * exp(eta - max(eta))
  out[control] <- out[control] *
    sum(out[treated]) / sum(out[control])
  list(
    weight = out, max_moment_error = max(abs(gradient(fit$par))),
    rank = ncol(mat), converged = TRUE)
}

lmv2_run_exit_decomposition <- function(
    config = lmv2_exit_config(), smoke = FALSE,
    relations = c(
      full_cohort = "exit_panel",
      initially_retained_broad = "stayer_exit_panel")) {
  lmv2_exit_load_runtime(config)
  set.seed(config$bootstrap$seed)
  dqrng::dqset.seed(config$bootstrap$seed)
  required <- c(
    config$endpoint_path, config$s3_weights,
    config$p6_manifest, config$certified_p6_headline)
  if (any(!file.exists(required))) {
    stop("Missing estimation input: ",
         paste(required[!file.exists(required)], collapse = ", "))
  }
  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(
    con, sprintf("PRAGMA threads=%d", config$execution$threads))
  DBI::dbExecute(
    con, sprintf("PRAGMA memory_limit=%s",
                 lmv2_exit_sql_string(config$execution$memory_limit)))
  panel_checks <- lmv2_exit_prepare_panels(config, con, smoke)
  lmv2_exit_write_csv(
    panel_checks,
    file.path(config$output_dir, "exit_panel_certification.csv"))
  fixture <- lmv2_exit_fixture_checks()
  lmv2_exit_write_csv(
    fixture, file.path(config$output_dir, "exit_decomposition_fixtures.csv"))
  if (!all(fixture$pass)) stop("Exit decomposition fixture failed")

  samples <- config$samples
  if (smoke) {
    samples <- list(smoke_1994_1996 = list(
      cohorts = 1994:1996, post_window = 1:3,
      censoring_label = "smoke_only"))
  }
  bootstrap_reps <- if (smoke) {
    config$bootstrap$smoke
  } else {
    config$bootstrap$production
  }
  output <- list(
    components = list(), factors = list(), weights = list(),
    two_factor = list(), raw = list(), dynamic = list(),
    exit_headline = list(), reference = list())

  for (population in names(relations)) {
    message("Loading ", population)
    panel <- lmv2_exit_extract_panel(con, relations[[population]])
    for (sample in names(samples)) {
      spec <- samples[[sample]]
      message("Estimating ", population, " | ", sample)
      decomposition <- lmv2_estimate_exit_decomposition(
        panel, spec$cohorts, spec$post_window, sample, population,
        survival_col = "survival",
        endpoint_definition = "global_endpoint_capped_2015",
        active_ess_floor = config$active_ess_floor)
      decomposition$components$censoring_label <- spec$censoring_label
      decomposition$factor_means$censoring_label <- spec$censoring_label
      output$components[[length(output$components) + 1L]] <-
        decomposition$components
      output$factors[[length(output$factors) + 1L]] <-
        decomposition$factor_means
      output$weights[[length(output$weights) + 1L]] <-
        cbind(
          population = population, sample = sample,
          decomposition$weights)
      output$two_factor[[length(output$two_factor) + 1L]] <-
        decomposition$two_factor
      output$raw[[length(output$raw) + 1L]] <- decomposition$raw

      direct <- lmv2_exit_dynamic_contrast(
        panel, spec$cohorts, spec$post_window, sample, population,
        bootstrap_reps = bootstrap_reps,
        run_wild = identical(sample, names(samples)[[1L]]))
      output$dynamic[[length(output$dynamic) + 1L]] <- direct$dynamic
      output$exit_headline[[length(output$exit_headline) + 1L]] <-
        direct$headline
      output$reference[[length(output$reference) + 1L]] <-
        lmv2_exit_reference_support(
          panel, spec$cohorts, sample, population)
    }

    if (!smoke) {
      fixed <- lmv2_estimate_exit_decomposition(
        panel, 1993:2010, 1:5,
        "fixed_lookahead_3y", population,
        survival_col = "survival_k3",
        endpoint_definition = "three_year_prospective_continuation",
        active_ess_floor = config$active_ess_floor)
      fixed$components$censoring_label <-
        "homogeneous_three_year_lookahead"
      output$components[[length(output$components) + 1L]] <-
        fixed$components
      output$factors[[length(output$factors) + 1L]] <-
        fixed$factor_means
      output$weights[[length(output$weights) + 1L]] <-
        cbind(
          population = population, sample = "fixed_lookahead_3y",
          fixed$weights)
      output$two_factor[[length(output$two_factor) + 1L]] <-
        fixed$two_factor
      output$raw[[length(output$raw) + 1L]] <- fixed$raw
    }
    rm(panel)
    gc()
  }

  bind <- function(x) data.table::rbindlist(
    x, use.names = TRUE, fill = TRUE)
  components <- bind(output$components)
  factors <- bind(output$factors)
  event_weights <- bind(output$weights)
  two_factor <- bind(output$two_factor)
  raw <- bind(output$raw)
  dynamic <- bind(output$dynamic)
  exit_headline <- bind(output$exit_headline)
  reference <- bind(output$reference)

  reconciliation <- merge(
    components[, .(
      population, sample, three_component = component,
      three_estimate = estimate)],
    two_factor[, .(
      population, sample, two_component = component,
      two_estimate = estimate)],
    by = c("population", "sample"), allow.cartesian = TRUE)
  totals <- components[component == "total",
                       .(population, sample, total_three = estimate)]
  totals <- merge(
    totals,
    two_factor[component == "total",
               .(population, sample, total_two = estimate)],
    by = c("population", "sample"))
  totals[, total_difference := total_three - total_two]

  if (smoke) {
    comparison <- components[
      component == "total",
      .(
        population, sample, recalculated = estimate,
        certified = estimate, difference = 0)]
  } else {
    certified <- utils::read.csv(
      config$certified_p6_headline, stringsAsFactors = FALSE)
    certified <- certified[
      certified$outcome == "patent_count" &
        certified$sample == "full_1993_2010" &
        certified$summary == "average_annual_t1_to_t5", ]
    if ("governing" %in% names(certified) &&
        any(certified$governing %in% TRUE)) {
      certified <- certified[certified$governing %in% TRUE, ]
    }
    certified_point <- unique(certified$estimate)
    if (length(certified_point) != 1L) {
      stop("Could not identify certified full-cohort patent-count ATT")
    }
    comparison <- data.frame(
      population = "full_cohort",
      sample = config$primary_sample,
      recalculated = components[
        population == "full_cohort" &
          sample == config$primary_sample &
          component == "total", estimate],
      certified = certified_point,
      stringsAsFactors = FALSE)
    comparison$difference <- comparison$recalculated - comparison$certified

    s4_path <- lmv2_exit_s4_headline_path(config)
    if (!is.na(s4_path)) {
      s4 <- utils::read.csv(s4_path, stringsAsFactors = FALSE)
      s4 <- s4[
        s4$spec == config$primary_stayer_spec &
          s4$outcome == "patent_count" &
          s4$sample == "full_1993_2010" &
          s4$summary == "average_annual_t1_to_t5", ]
      if ("governing" %in% names(s4) && any(s4$governing %in% TRUE)) {
        s4 <- s4[s4$governing %in% TRUE, ]
      }
      s4_point <- unique(s4$estimate)
      if (length(s4_point) == 1L) {
        comparison <- rbind(comparison, data.frame(
          population = "initially_retained_broad",
          sample = config$primary_sample,
          recalculated = components[
            population == "initially_retained_broad" &
              sample == config$primary_sample &
              component == "total", estimate],
          certified = s4_point,
          difference = components[
            population == "initially_retained_broad" &
              sample == config$primary_sample &
              component == "total", estimate] - s4_point,
          stringsAsFactors = FALSE))
      }
    }
  }
  if (any(abs(comparison$difference) > 1e-10)) {
    stop("Decomposition does not reproduce a certified patent-count ATT")
  }

  lmv2_exit_write_csv(
    components,
    file.path(config$output_dir, "exit_decomposition_components.csv"))
  lmv2_exit_write_csv(
    factors,
    file.path(config$output_dir, "exit_decomposition_factor_means.csv"))
  lmv2_exit_write_csv(
    event_weights,
    file.path(config$output_dir, "exit_decomposition_event_weights.csv"))
  lmv2_exit_write_csv(
    raw,
    file.path(config$output_dir, "exit_raw_reference_sensitivity.csv"))
  lmv2_exit_write_csv(
    reconciliation,
    file.path(
      config$output_dir,
      "exit_two_vs_three_factor_reconciliation_long.csv"))
  lmv2_exit_write_csv(
    totals,
    file.path(config$output_dir, "exit_two_vs_three_factor_totals.csv"))
  lmv2_exit_write_csv(
    dynamic, file.path(config$output_dir, "exit_dynamic_att.csv"))
  lmv2_exit_write_csv(
    exit_headline, file.path(config$output_dir, "exit_post_att.csv"))
  lmv2_exit_write_csv(
    reference,
    file.path(
      config$output_dir, "exit_reference_support_diagnostic.csv"))
  lmv2_exit_write_csv(
    comparison,
    file.path(config$output_dir, "exit_certified_total_reconciliation.csv"))
  invisible(list(
    components = components, dynamic = dynamic,
    exit_headline = exit_headline, comparison = comparison))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  smoke <- "--smoke" %in% args
  output_arg <- sub(
    "^--output-dir=", "", grep(
      "^--output-dir=", args, value = TRUE))
  config <- lmv2_exit_config(
    output_dir = if (length(output_arg)) output_arg[[1L]] else NULL)
  lmv2_run_exit_decomposition(config, smoke = smoke)
}
