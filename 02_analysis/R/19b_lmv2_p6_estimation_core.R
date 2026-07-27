# ============================================================================
# 19b_lmv2_p6_estimation_core.R -- memory-safe P6 full-cohort estimator
# ============================================================================
# All large joins, first differences, and influence construction stay in
# DuckDB. R receives only small coefficient tables, cluster-level influence
# matrices, and the compact deal-cell regression used by fwildclusterboot.

lmv2_sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

lmv2_panel_sql <- function(panel_files) {
  paste0(
    "read_parquet([",
    paste(vapply(panel_files, lmv2_sql_string, character(1)), collapse = ","),
    "])"
  )
}

lmv2_validate_estimation_inputs <- function(con, panel_files, stamp_files,
                                            p6_manifest_path) {
  expected_cohorts <- LMV2_P6_CONFIG$cohorts
  cohort_from_name <- as.integer(sub(
    "^.*_c([0-9]+)\\.parquet$", "\\1", panel_files
  ))
  if (length(panel_files) != length(expected_cohorts) ||
      !identical(sort(cohort_from_name), expected_cohorts)) {
    stop("Panel shard cohort set is not exactly 1994:2010")
  }
  if (length(stamp_files) != length(expected_cohorts)) {
    stop("Expected one stamp per P6 panel shard")
  }

  stamps <- do.call(rbind, lapply(stamp_files, function(path) {
    utils::read.csv(path, stringsAsFactors = FALSE)
  }))
  required_stamp_cols <- c(
    "cohort", "p6_design_hash", "preanalysis_freeze_sha256",
    "roster_rows", "shard_rows", "shard_parquet_md5"
  )
  if (!all(required_stamp_cols %in% names(stamps))) {
    stop("P6 shard stamps are missing required provenance columns")
  }
  if (!all(stamps$p6_design_hash == lmv2_p6_design_hash()) ||
      !all(stamps$preanalysis_freeze_sha256 ==
             LMV2_P6_PREANALYSIS_FREEZE_SHA256)) {
    stop("P6 shard provenance is stale; rebuild construction before ATT")
  }

  manifest <- utils::read.csv(p6_manifest_path, stringsAsFactors = FALSE)
  if (nrow(manifest) != 1L || manifest$n_failed[[1]] != 0 ||
      manifest$p6_design_hash[[1]] != lmv2_p6_design_hash() ||
      manifest$preanalysis_freeze_sha256[[1]] !=
        LMV2_P6_PREANALYSIS_FREEZE_SHA256) {
    stop("P6 construction manifest is missing, failed, or stale")
  }

  p <- lmv2_panel_sql(panel_files)
  checks <- DBI::dbGetQuery(con, sprintf("
    WITH panel AS (SELECT * FROM %s),
    unit_checks AS (
      SELECT roster_row_id, COUNT(*) AS n,
             COUNT(DISTINCT cohort) AS n_cohort,
             COUNT(DISTINCT deal_id) AS n_deal,
             COUNT(DISTINCT arm) AS n_arm,
             COUNT(DISTINCT codinv) AS n_codinv,
             MIN(event_time) AS min_e, MAX(event_time) AS max_e
      FROM panel GROUP BY roster_row_id
    ),
    masses AS (
      SELECT cohort,
        SUM(weight) FILTER (arm='treated' AND event_time=-1) AS tm,
        SUM(weight) FILTER (arm='control' AND event_time=-1) AS cm
      FROM panel GROUP BY cohort
    )
    SELECT
      (SELECT COUNT(*) FROM panel) AS panel_rows,
      (SELECT COUNT(*) FROM unit_checks) AS units,
      (SELECT COUNT(*) FROM unit_checks
       WHERE n<>11 OR n_cohort<>1 OR n_deal<>1 OR n_arm<>1 OR n_codinv<>1
          OR min_e<>-5 OR max_e<>5) AS bad_units,
      (SELECT COUNT(*) FROM masses WHERE ABS(tm-cm)>1e-7) AS bad_masses,
      (SELECT COUNT(*) FROM panel
       WHERE arm='treated' AND weight<>1) AS bad_treated_weights,
      (SELECT COUNT(*) FROM panel
       WHERE weight IS NULL OR NOT isfinite(weight) OR weight<=0) AS bad_weights,
      (SELECT COUNT(DISTINCT cohort) FROM panel) AS cohorts,
      (SELECT COUNT(DISTINCT deal_id) FROM panel) AS deals
  ", p))
  checks$pass <- checks$panel_rows == sum(stamps$shard_rows) &&
    checks$units == sum(stamps$roster_rows) &&
    checks$bad_units == 0 && checks$bad_masses == 0 &&
    checks$bad_treated_weights == 0 && checks$bad_weights == 0 &&
    checks$cohorts == 17 && checks$deals > 1
  if (!isTRUE(checks$pass[[1]])) {
    stop("P6 estimation input certification failed")
  }
  checks
}

lmv2_outcome_table_name <- function(outcome, sample_id) {
  safe <- gsub("[^A-Za-z0-9_]", "_", paste(outcome, sample_id, sep = "_"))
  paste0("p6_pairs_", safe)
}

lmv2_build_pair_table <- function(con, panel_sql, outcome, cohorts,
                                  sample_id) {
  if (!outcome %in% LMV2_P6_ESTIMATION$outcomes$outcome) {
    stop("Outcome is not frozen: ", outcome)
  }
  table_name <- lmv2_outcome_table_name(outcome, sample_id)
  cohort_sql <- paste(as.integer(cohorts), collapse = ",")
  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", table_name))
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE %1$s AS
    SELECT
      e.roster_row_id,
      CAST(e.deal_id AS INTEGER) AS deal_id,
      CAST(e.cohort AS INTEGER) AS cohort,
      e.arm,
      CAST(e.codinv AS BIGINT) AS codinv,
      CAST(e.event_time AS INTEGER) AS event_time,
      CAST(e.weight AS DOUBLE) AS weight,
      CAST(e.%2$s - r.%2$s AS DOUBLE) AS dy
    FROM %3$s e
    JOIN %3$s r USING (roster_row_id)
    WHERE e.cohort IN (%4$s)
      AND r.event_time = -1
      AND e.event_time <> -1
      AND e.%2$s IS NOT NULL
      AND r.%2$s IS NOT NULL
  ", table_name, outcome, panel_sql, cohort_sql))
  table_name
}

lmv2_design_deal_counts <- function(con, panel_sql, cohorts) {
  cohort_sql <- paste(as.integer(cohorts), collapse = ",")
  DBI::dbGetQuery(con, sprintf("
    WITH d AS (
      SELECT deal_id, SUM(weight) AS treated_mass
      FROM %s
      WHERE cohort IN (%s) AND arm='treated' AND event_time=-1
      GROUP BY deal_id
    ), s AS (
      SELECT deal_id, treated_mass, treated_mass / SUM(treated_mass) OVER () sh
      FROM d
    )
    SELECT COUNT(*) AS nominal_treated_deals,
           1 / SUM(sh * sh) AS effective_treated_deals,
           SUM(treated_mass) AS treated_weight_mass
    FROM s
  ", panel_sql, cohort_sql))
}

lmv2_prepare_influence_table <- function(con, pair_table, panel_sql, cohorts) {
  cohort_sql <- paste(as.integer(cohorts), collapse = ",")
  influence_table <- paste0(pair_table, "_influence")
  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", influence_table))
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE %1$s AS
    WITH design_mass AS (
      SELECT cohort, SUM(weight) AS treated_design_mass
      FROM %2$s
      WHERE cohort IN (%3$s) AND arm='treated' AND event_time=-1
      GROUP BY cohort
    ), design_share AS (
      SELECT cohort,
             treated_design_mass / SUM(treated_design_mass) OVER () AS q_g
      FROM design_mass
    ), arm_stats AS (
      SELECT cohort, event_time, arm,
             SUM(weight) AS observed_mass,
             SUM(weight * dy) / SUM(weight) AS mean_dy
      FROM %4$s
      GROUP BY cohort, event_time, arm
    ), eligible AS (
      SELECT cohort, event_time
      FROM arm_stats
      GROUP BY cohort, event_time
      HAVING COUNT(DISTINCT arm) = 2
         AND MIN(observed_mass) > 0
    ), event_share AS (
      SELECT e.event_time, SUM(q.q_g) AS retained_design_share
      FROM eligible e
      JOIN design_share q USING (cohort)
      GROUP BY e.event_time
    )
    SELECT
      p.roster_row_id, p.deal_id, p.cohort, p.arm, p.codinv,
      p.event_time, p.weight, p.dy,
      s.observed_mass, s.mean_dy, q.q_g,
      q.q_g / es.retained_design_share AS q_event,
      CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END *
        q.q_g / es.retained_design_share *
        p.weight / s.observed_mass * p.dy AS contribution,
      CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END *
        q.q_g / es.retained_design_share *
        p.weight / s.observed_mass *
        (p.dy - s.mean_dy) AS influence
    FROM %4$s p
    JOIN arm_stats s USING (cohort, event_time, arm)
    JOIN design_share q USING (cohort)
    JOIN eligible e USING (cohort, event_time)
    JOIN event_share es USING (event_time)
  ", influence_table, panel_sql, cohort_sql, pair_table))
  influence_table
}

lmv2_pair_coverage <- function(con, pair_table, panel_sql, cohorts,
                               outcome, sample_id) {
  cohort_sql <- paste(as.integer(cohorts), collapse = ",")
  out <- DBI::dbGetQuery(con, sprintf("
    WITH design AS (
      SELECT cohort, arm, SUM(weight) AS design_mass
      FROM %1$s
      WHERE cohort IN (%2$s) AND event_time=-1
      GROUP BY cohort, arm
    ), design_share AS (
      SELECT cohort, design_mass / SUM(design_mass) OVER () AS q_g
      FROM design
      WHERE arm='treated'
    ), observed AS (
      SELECT cohort, event_time, arm,
             COUNT(*) AS observed_rows,
             COUNT(DISTINCT deal_id) AS observed_deals,
             COUNT(DISTINCT codinv) AS observed_inventors,
             SUM(weight) AS observed_mass
      FROM %3$s
      GROUP BY cohort, event_time, arm
    ), event_grid AS (
      SELECT d.cohort, e.event_time, a.arm
      FROM (SELECT DISTINCT cohort FROM design) d
      CROSS JOIN (
        SELECT event_time
        FROM range(-5, 6) r(event_time)
        WHERE event_time <> -1
      ) e
      CROSS JOIN (VALUES ('treated'), ('control')) a(arm)
    ), eligible AS (
      SELECT cohort, event_time,
             COUNT(DISTINCT arm) = 2 AND MIN(observed_mass) > 0
               AS eligible_cohort_event
      FROM observed
      GROUP BY cohort, event_time
    ), event_share AS (
      SELECT e.event_time,
             SUM(q.q_g) FILTER (e.eligible_cohort_event)
               AS retained_design_share
      FROM eligible e
      JOIN design_share q USING (cohort)
      GROUP BY e.event_time
    )
    SELECT g.cohort, g.event_time, g.arm,
           COALESCE(o.observed_rows, 0) AS observed_rows,
           COALESCE(o.observed_deals, 0) AS observed_deals,
           COALESCE(o.observed_inventors, 0) AS observed_inventors,
           COALESCE(o.observed_mass, 0) AS observed_mass,
           d.design_mass,
           COALESCE(o.observed_mass, 0) / d.design_mass
             AS pair_weight_coverage,
           COALESCE(e.eligible_cohort_event, FALSE)
             AS eligible_cohort_event,
           es.retained_design_share
    FROM event_grid g
    JOIN design d USING (cohort, arm)
    LEFT JOIN observed o USING (cohort, event_time, arm)
    LEFT JOIN eligible e USING (cohort, event_time)
    LEFT JOIN event_share es USING (event_time)
    ORDER BY cohort, event_time, arm
  ", panel_sql, cohort_sql, pair_table))
  out$outcome <- outcome
  out$sample <- sample_id
  out
}

lmv2_event_estimates <- function(con, influence_table, outcome, sample_id) {
  out <- DBI::dbGetQuery(con, sprintf("
    SELECT event_time, SUM(contribution) AS estimate,
           SUM(influence) AS influence_sum
    FROM %s
    GROUP BY event_time
    ORDER BY event_time
  ", influence_table))
  expected <- setdiff(
    LMV2_P6_ESTIMATION$event_window,
    LMV2_P6_ESTIMATION$reference_event_time
  )
  if (!identical(out$event_time, as.integer(expected))) {
    stop("At least one cohort-arm-event cell has no pairwise observed outcome")
  }
  if (max(abs(out$influence_sum)) > 1e-8) {
    stop("Influence functions do not sum to zero")
  }
  out$outcome <- outcome
  out$sample <- sample_id
  out
}

lmv2_cluster_influence_wide <- function(con, influence_table, cluster_cols,
                                        periods) {
  cluster_sql <- paste(cluster_cols, collapse = ", ")
  value_cols <- paste0("e", ifelse(periods < 0, "m", "p"), abs(periods))
  expressions <- paste(sprintf(
    "COALESCE(SUM(influence) FILTER (event_time=%d), 0) AS %s",
    periods, value_cols
  ), collapse = ",\n")
  out <- DBI::dbGetQuery(con, sprintf("
    SELECT %s, %s
    FROM %s
    GROUP BY %s
  ", cluster_sql, expressions, influence_table, cluster_sql))
  mat <- as.matrix(out[, value_cols, drop = FALSE])
  storage.mode(mat) <- "double"
  mat <- sweep(mat, 2, colMeans(mat), "-")
  list(matrix = mat, n_clusters = nrow(mat), periods = periods)
}

lmv2_cr1_covariance <- function(cluster_matrix) {
  G <- nrow(cluster_matrix)
  if (G < 2L) stop("Fewer than two clusters")
  G / (G - 1) * crossprod(cluster_matrix)
}

lmv2_two_way_covariance <- function(con, influence_table, periods) {
  deal <- lmv2_cluster_influence_wide(
    con, influence_table, "deal_id", periods
  )
  inventor <- lmv2_cluster_influence_wide(
    con, influence_table, "codinv", periods
  )
  intersection <- lmv2_cluster_influence_wide(
    con, influence_table, c("deal_id", "codinv"), periods
  )
  V_deal <- lmv2_cr1_covariance(deal$matrix)
  V_inventor <- lmv2_cr1_covariance(inventor$matrix)
  V_intersection <- lmv2_cr1_covariance(intersection$matrix)
  V_two_way <- V_deal + V_inventor - V_intersection
  if (any(diag(V_two_way) < -1e-12)) {
    stop("Two-way cluster covariance has a materially negative variance")
  }
  diag(V_two_way) <- pmax(diag(V_two_way), 0)
  list(
    two_way = V_two_way,
    deal = V_deal,
    n_deal = deal$n_clusters,
    n_inventor = inventor$n_clusters,
    n_intersection = intersection$n_clusters
  )
}

lmv2_dynamic_results <- function(event_estimates, covariance) {
  periods <- event_estimates$event_time
  estimate <- event_estimates$estimate
  df <- min(covariance$n_deal, covariance$n_inventor) - 1
  se <- sqrt(diag(covariance$two_way))
  crit <- stats::qt(
    1 - (1 - LMV2_P6_ESTIMATION$inference$confidence_level) / 2, df
  )
  out <- data.frame(
    outcome = event_estimates$outcome,
    sample = event_estimates$sample,
    event_time = periods,
    estimate = estimate,
    se = se,
    df = df,
    ci_low = estimate - crit * se,
    ci_high = estimate + crit * se,
    inference = "two_way_deal_inventor",
    stringsAsFactors = FALSE
  )
  out <- rbind(out, data.frame(
    outcome = event_estimates$outcome[[1]],
    sample = event_estimates$sample[[1]],
    event_time = LMV2_P6_ESTIMATION$reference_event_time,
    estimate = 0, se = 0, df = df, ci_low = 0, ci_high = 0,
    inference = "reference_period", stringsAsFactors = FALSE
  ))
  out[order(out$event_time), ]
}

lmv2_pretrend_test <- function(event_estimates, covariance) {
  periods <- event_estimates$event_time
  keep <- match(LMV2_P6_ESTIMATION$pretrend_window, periods)
  b <- event_estimates$estimate[keep]
  V <- covariance$two_way[keep, keep, drop = FALSE]
  q <- length(keep)
  df2 <- min(covariance$n_deal, covariance$n_inventor) - 1
  f_stat <- as.numeric(t(b) %*% solve(V, b)) / q
  data.frame(
    outcome = event_estimates$outcome[[1]],
    sample = event_estimates$sample[[1]],
    periods = paste(LMV2_P6_ESTIMATION$pretrend_window, collapse = ";"),
    f_stat = f_stat, df1 = q, df2 = df2,
    p_value = stats::pf(f_stat, q, df2, lower.tail = FALSE),
    stringsAsFactors = FALSE
  )
}

lmv2_compact_post_regression <- function(con, influence_table,
                                         expected_estimate) {
  post_sql <- paste(LMV2_P6_ESTIMATION$post_window, collapse = ",")
  dat <- DBI::dbGetQuery(con, sprintf("
    WITH arm_stats AS (
      SELECT cohort, event_time, arm,
             MAX(q_event) AS q_event,
             SUM(weight) AS arm_mass
      FROM %1$s
      WHERE event_time IN (%2$s)
      GROUP BY cohort, event_time, arm
    ), cells AS (
      SELECT deal_id, cohort, event_time, arm,
             SUM(weight) AS cell_mass,
             SUM(weight * dy) / SUM(weight) AS dy_mean
      FROM %1$s
      WHERE event_time IN (%2$s)
      GROUP BY deal_id, cohort, event_time, arm
    )
    SELECT
      c.deal_id,
      CAST(c.arm='treated' AS INTEGER) AS treated,
      CAST(c.cohort * 100 + c.event_time + 10 AS INTEGER)
        AS cohort_event_id,
      c.dy_mean,
      c.cell_mass / s.arm_mass * s.q_event / 5.0 AS analysis_weight
    FROM cells c
    JOIN arm_stats s USING (cohort, event_time, arm)
  ", influence_table, post_sql))
  mod <- fixest::feols(
    dy_mean ~ treated | cohort_event_id,
    data = dat, weights = ~analysis_weight,
    cluster = ~deal_id, fixef.rm = "none", notes = FALSE
  )
  estimate <- unname(stats::coef(mod)[["treated"]])
  if (!is.finite(estimate) || abs(estimate - expected_estimate) > 1e-9) {
    stop(sprintf(
      "Compact-regression tooth-check failed: direct=%.12f regression=%.12f",
      expected_estimate, estimate
    ))
  }
  list(model = mod, rows = nrow(dat))
}

lmv2_extract_wild_ci <- function(boot, mod) {
  ci <- try(as.numeric(stats::confint(boot)), silent = TRUE)
  if (!inherits(ci, "try-error") &&
      length(ci) == 2L &&
      all(is.finite(ci)) &&
      ci[[1]] <= ci[[2]]) {
    return(list(
      ci_low = ci[[1]], ci_high = ci[[2]],
      ci_method = "p_value_inversion"
    ))
  }

  # fwildclusterboot can return no inverted interval when its automatic
  # starting grid is degenerate (notably when the point estimate is near
  # zero). The bootstrap-t draws remain valid. Use their equal-tailed
  # quantiles with the original deal-clustered standard error.
  t_boot <- as.numeric(boot$t_boot)
  t_boot <- t_boot[is.finite(t_boot)]
  model_se <- unname(sqrt(diag(stats::vcov(mod)))[["treated"]])
  if (length(t_boot) < 100L || !is.finite(model_se) || model_se <= 0) {
    stop("Wild-bootstrap CI inversion failed and fallback inputs are invalid")
  }
  alpha <- 1 - LMV2_P6_ESTIMATION$inference$confidence_level
  q <- stats::quantile(
    t_boot, probs = c(1 - alpha / 2, alpha / 2),
    names = FALSE, na.rm = TRUE, type = 7
  )
  estimate <- as.numeric(boot$point_estimate)
  fallback <- estimate - q * model_se
  if (length(fallback) != 2L || !all(is.finite(fallback)) ||
      fallback[[1]] > fallback[[2]]) {
    stop("Wild-bootstrap percentile-t fallback produced an invalid interval")
  }
  list(
    ci_low = fallback[[1]], ci_high = fallback[[2]],
    ci_method = "bootstrap_t_quantile_fallback"
  )
}

lmv2_wild_post <- function(mod, reps) {
  seed <- LMV2_P6_ESTIMATION$inference$seed
  set.seed(seed)
  dqrng::dqset.seed(seed)
  boot <- fwildclusterboot::boottest(
    mod, param = "treated", B = as.integer(reps),
    clustid = ~deal_id,
    type = LMV2_P6_ESTIMATION$inference$bootstrap_type,
    impose_null = LMV2_P6_ESTIMATION$inference$impose_null,
    conf_int = TRUE,
    engine = LMV2_P6_ESTIMATION$inference$engine,
    nthreads = LMV2_P6_ESTIMATION$execution$threads
  )
  ci <- lmv2_extract_wild_ci(boot, mod)
  data.frame(
    inference = "deal_wild_bootstrap_t",
    estimate = as.numeric(boot$point_estimate),
    se = NA_real_, df = NA_real_,
    ci_low = ci$ci_low, ci_high = ci$ci_high,
    p_value = as.numeric(fwildclusterboot::pval(boot)),
    ci_method = ci$ci_method,
    stringsAsFactors = FALSE
  )
}

lmv2_cluster_post <- function(event_estimates, covariance, which_vcov,
                              label) {
  periods <- event_estimates$event_time
  keep <- match(LMV2_P6_ESTIMATION$post_window, periods)
  L <- rep(1 / length(keep), length(keep))
  estimate <- sum(L * event_estimates$estimate[keep])
  V <- covariance[[which_vcov]][keep, keep, drop = FALSE]
  se <- sqrt(as.numeric(t(L) %*% V %*% L))
  df <- covariance$n_deal - 1
  crit <- stats::qt(
    1 - (1 - LMV2_P6_ESTIMATION$inference$confidence_level) / 2, df
  )
  data.frame(
    inference = label, estimate = estimate, se = se, df = df,
    ci_low = estimate - crit * se,
    ci_high = estimate + crit * se,
    p_value = 2 * stats::pt(-abs(estimate / se), df),
    ci_method = "analytic_cluster_t",
    stringsAsFactors = FALSE
  )
}

lmv2_fit_outcome <- function(con, panel_sql, outcome, sample_id, cohorts,
                             bootstrap_reps, design_deal_counts) {
  pair_table <- lmv2_build_pair_table(
    con, panel_sql, outcome, cohorts, sample_id
  )
  influence_table <- lmv2_prepare_influence_table(
    con, pair_table, panel_sql, cohorts
  )
  coverage <- lmv2_pair_coverage(
    con, pair_table, panel_sql, cohorts, outcome, sample_id
  )
  DBI::dbExecute(con, sprintf("DROP TABLE %s", pair_table))
  event_estimates <- lmv2_event_estimates(
    con, influence_table, outcome, sample_id
  )
  covariance <- lmv2_two_way_covariance(
    con, influence_table, event_estimates$event_time
  )
  dynamic <- lmv2_dynamic_results(event_estimates, covariance)
  pretrend <- lmv2_pretrend_test(event_estimates, covariance)

  keep_post <- match(
    LMV2_P6_ESTIMATION$post_window, event_estimates$event_time
  )
  expected_post <- mean(event_estimates$estimate[keep_post])
  compact <- lmv2_compact_post_regression(
    con, influence_table, expected_post
  )
  wild <- lmv2_wild_post(compact$model, bootstrap_reps)
  two_way <- lmv2_cluster_post(
    event_estimates, covariance, "two_way", "two_way_deal_inventor"
  )
  deal_only <- lmv2_cluster_post(
    event_estimates, covariance, "deal", "deal_cluster_robust"
  )

  headline <- rbind(wild, two_way, deal_only)
  headline$outcome <- outcome
  headline$sample <- sample_id
  headline$summary <- "average_annual_t1_to_t5"
  headline$bootstrap_replications <- c(bootstrap_reps, NA, NA)
  headline$nominal_treated_deals <-
    design_deal_counts$nominal_treated_deals[[1]]
  headline$effective_treated_deals <-
    design_deal_counts$effective_treated_deals[[1]]
  headline$treated_weight_mass <-
    design_deal_counts$treated_weight_mass[[1]]
  headline$compact_regression_rows <- compact$rows

  widths <- setNames(
    headline$ci_high - headline$ci_low, headline$inference
  )
  governing <- if (
    widths[["two_way_deal_inventor"]] >
      widths[["deal_wild_bootstrap_t"]]
  ) "two_way_deal_inventor" else "deal_wild_bootstrap_t"
  headline$governing <- headline$inference == governing
  wild_sig_pos <- headline$ci_low[
    headline$inference == "deal_wild_bootstrap_t"
  ] > 0
  two_sig_pos <- headline$ci_low[
    headline$inference == "two_way_deal_inventor"
  ] > 0
  wild_sig_neg <- headline$ci_high[
    headline$inference == "deal_wild_bootstrap_t"
  ] < 0
  two_sig_neg <- headline$ci_high[
    headline$inference == "two_way_deal_inventor"
  ] < 0
  headline$inference_sensitive <-
    (wild_sig_pos != two_sig_pos) || (wild_sig_neg != two_sig_neg)

  cumulative <- headline
  scale_cols <- c("estimate", "se", "ci_low", "ci_high")
  cumulative[scale_cols] <- lapply(
    cumulative[scale_cols],
    function(x) x * length(LMV2_P6_ESTIMATION$post_window)
  )
  cumulative$summary <- "cumulative_t1_to_t5"
  headline <- rbind(headline, cumulative)

  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
  rm(compact, covariance)
  gc()
  list(
    dynamic = dynamic, pretrend = pretrend,
    headline = headline, coverage = coverage
  )
}
