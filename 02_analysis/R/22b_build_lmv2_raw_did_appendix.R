# ============================================================================
# 22b_build_lmv2_raw_did_appendix.R
# Unmatched, cohort-standardized DiD diagnostics for the appendix.
#
# The control clock is the frozen P2 placebo cohort. No firm or inventor
# matching, entropy balancing, caliper, common-support restriction, or outcome
# covariate adjustment is applied. The full-cohort diagnostic uses every P2
# treated and control-eligible inventor. The stayer diagnostic applies the
# frozen main-design rule symmetrically: at least one focal-entity patent in
# event time +1 to +5. Event year zero cannot qualify an inventor as a stayer.
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, default) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) > 1L) stop("Argument supplied more than once: --", name)
  if (!length(hit)) return(default)
  sub(paste0("^", prefix), "", hit)
}

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (pkg in c("DBI", "duckdb", "ggplot2", "gridExtra")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

DB_PATH <- normalizePath(
  read_arg("db", file.path(BASE, "output", "thesis_foundation.duckdb")),
  winslash = "/", mustWork = TRUE
)
OUT_DIR <- read_arg(
  "output-dir",
  file.path(BASE, "output", "audit", "local_match_v2",
            "P6_APPENDIX_RAW_DID")
)
FIG_DIR <- read_arg(
  "figure-dir",
  file.path(BASE, "output", "figures", "local_match_v2",
            "appendix_raw_did")
)
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)
OUT_DIR <- normalizePath(OUT_DIR, winslash = "/", mustWork = TRUE)
FIG_DIR <- normalizePath(FIG_DIR, winslash = "/", mustWork = TRUE)
dir.create(file.path(OUT_DIR, "duckdb_tmp"),
           recursive = TRUE, showWarnings = FALSE)

write_csv <- function(x, name) {
  utils::write.csv(
    x, file.path(OUT_DIR, paste0(name, ".csv")),
    row.names = FALSE, na = ""
  )
}

con <- DBI::dbConnect(duckdb::duckdb(), DB_PATH)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(
  con, sprintf("PRAGMA temp_directory='%s'",
               gsub("'", "''", file.path(OUT_DIR, "duckdb_tmp")))
)

required_tables <- data.frame(
  table_schema = c("main", "main", "p6", "p6", "p6"),
  table_name = c(
    "lmv2_treated_primary", "lmv2_control_inventor_eligibility",
    "lmv2_outcome_inventor_year",
    "lmv2_outcome_inventor_affiliation_year",
    "lmv2_inventor_target_company_patent_year"
  ),
  stringsAsFactors = FALSE
)
available_tables <- DBI::dbGetQuery(con, "
  SELECT table_schema, table_name
  FROM information_schema.tables
")
required_keys <- paste(
  required_tables$table_schema, required_tables$table_name, sep = "."
)
available_keys <- paste(
  available_tables$table_schema, available_tables$table_name, sep = "."
)
missing_tables <- required_keys[!required_keys %in% available_keys]
if (length(missing_tables)) {
  stop("Missing required tables: ", paste(missing_tables, collapse = ", "))
}

# One raw observation per inventor and assigned event clock. Control clusters
# are the placebo focal groups; negative IDs keep them distinct from treated
# acquisition deal IDs. The stayer rule is evaluated before any outcome
# contrast is computed.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE raw_did_units AS
  WITH control_units AS (
    SELECT
      CAST(c.cohort AS INTEGER) AS cohort,
      'control' AS arm,
      CAST(c.codinv AS BIGINT) AS codinv,
      -CAST(c.control_group AS BIGINT) AS cluster_id,
      CAST(c.control_group AS BIGINT) AS focal_group,
      COALESCE(
        EXISTS (
          SELECT 1
          FROM p6.lmv2_outcome_inventor_affiliation_year a
          WHERE a.codinv = c.codinv
            AND a.year BETWEEN c.cohort + 1 AND c.cohort + 5
            AND CAST(a.resolved_group AS BIGINT) =
                CAST(c.control_group AS BIGINT)
        ), FALSE
      ) AS stayer,
      EXISTS (
        SELECT 1
        FROM p6.lmv2_outcome_inventor_year y
        WHERE y.codinv = c.codinv
          AND y.year BETWEEN c.cohort AND c.cohort + 5
          AND y.patent_count > 0
      ) AS any_post_patent_t0_t5,
      EXISTS (
        SELECT 1
        FROM p6.lmv2_outcome_inventor_year y
        WHERE y.codinv = c.codinv
          AND y.year BETWEEN c.cohort + 1 AND c.cohort + 5
          AND y.patent_count > 0
      ) AS any_post_patent_t1_t5
    FROM lmv2_control_inventor_eligibility c
  ),
  treated_units AS (
    SELECT
      CAST(cohort AS INTEGER) AS cohort,
      'treated' AS arm,
      CAST(codinv AS BIGINT) AS codinv,
      CAST(deal_id AS BIGINT) AS cluster_id,
      CAST(target_group AS BIGINT) AS focal_group,
      COALESCE(
        t.status_eligible AND (
          EXISTS (
            SELECT 1
            FROM p6.lmv2_outcome_inventor_affiliation_year a
            WHERE a.codinv = t.codinv
              AND a.year BETWEEN t.cohort + 1 AND t.cohort + 5
              AND CAST(a.resolved_group AS BIGINT) IN (
                CAST(t.target_group AS BIGINT),
                CAST(t.acquirer_group AS BIGINT)
              )
          )
          OR EXISTS (
            SELECT 1
            FROM p6.lmv2_inventor_target_company_patent_year tc
            WHERE tc.codinv = t.codinv
              AND tc.deal_id = t.deal_id
              AND tc.year BETWEEN t.cohort + 1 AND t.cohort + 5
          )
        ), FALSE
      ) AS stayer,
      EXISTS (
        SELECT 1
        FROM p6.lmv2_outcome_inventor_year y
        WHERE y.codinv = t.codinv
          AND y.year BETWEEN t.cohort AND t.cohort + 5
          AND y.patent_count > 0
      ) AS any_post_patent_t0_t5,
      EXISTS (
        SELECT 1
        FROM p6.lmv2_outcome_inventor_year y
        WHERE y.codinv = t.codinv
          AND y.year BETWEEN t.cohort + 1 AND t.cohort + 5
          AND y.patent_count > 0
      ) AS any_post_patent_t1_t5
    FROM lmv2_treated_primary t
  )
  SELECT
    cohort, arm, codinv, cluster_id, focal_group, stayer,
    any_post_patent_t0_t5, any_post_patent_t1_t5,
    arm || ':' || CAST(cohort AS VARCHAR) || ':' ||
      CAST(cluster_id AS VARCHAR) || ':' || CAST(codinv AS VARCHAR)
      AS unit_id
  FROM (
    SELECT * FROM treated_units
    UNION ALL
    SELECT * FROM control_units
  )
")

unit_checks <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT unit_id) AS unique_rows,
    COUNT(*) FILTER (arm='treated') AS treated_rows,
    COUNT(*) FILTER (arm='control') AS control_rows,
    COUNT(*) FILTER (arm='treated' AND stayer) AS treated_stayers,
    COUNT(*) FILTER (arm='control' AND stayer) AS control_stayers,
    COUNT(*) FILTER (arm='treated' AND any_post_patent_t0_t5)
      AS treated_any_post_t0_t5,
    COUNT(*) FILTER (arm='control' AND any_post_patent_t0_t5)
      AS control_any_post_t0_t5,
    COUNT(*) FILTER (arm='treated' AND any_post_patent_t1_t5)
      AS treated_any_post_t1_t5,
    COUNT(*) FILTER (arm='control' AND any_post_patent_t1_t5)
      AS control_any_post_t1_t5,
    COUNT(DISTINCT cohort) AS cohorts,
    COUNT(*) FILTER (
      cluster_id IS NULL OR codinv IS NULL OR stayer IS NULL
      OR any_post_patent_t0_t5 IS NULL OR any_post_patent_t1_t5 IS NULL
    )
      AS bad_keys
  FROM raw_did_units
")
expected <- DBI::dbGetQuery(con, "
  SELECT
    (SELECT COUNT(*) FROM lmv2_treated_primary) AS treated_rows,
    (SELECT COUNT(*) FROM lmv2_control_inventor_eligibility) AS control_rows
")
if (unit_checks$rows != unit_checks$unique_rows ||
    unit_checks$treated_rows != expected$treated_rows ||
    unit_checks$control_rows != expected$control_rows ||
    unit_checks$cohorts != 17L ||
    unit_checks$bad_keys != 0L) {
  stop("Raw unit construction failed its identity checks")
}
write_csv(unit_checks, "raw_did_unit_counts")

# Structural zero patent years are explicit. First differences use t=-1 as
# the common reference and retain t=0 as the acquisition/placebo year.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE raw_did_panel AS
  WITH event_grid AS (
    SELECT u.*, e.event_time, u.cohort + e.event_time AS calendar_year
    FROM raw_did_units u
    CROSS JOIN range(-5, 6) e(event_time)
  )
  SELECT
    g.cohort, g.arm, g.codinv, g.cluster_id, g.focal_group,
    g.stayer, g.any_post_patent_t0_t5, g.any_post_patent_t1_t5,
    g.unit_id, CAST(g.event_time AS INTEGER) AS event_time,
    COALESCE(y.patent_count, 0.0) AS patent_count,
    COALESCE(r.patent_count, 0.0) AS patent_count_ref,
    COALESCE(y.patent_count, 0.0) -
      COALESCE(r.patent_count, 0.0) AS dy
  FROM event_grid g
  LEFT JOIN p6.lmv2_outcome_inventor_year y
    ON y.codinv = g.codinv AND y.year = g.calendar_year
  LEFT JOIN p6.lmv2_outcome_inventor_year r
    ON r.codinv = g.codinv AND r.year = g.cohort - 1
")

panel_check <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT unit_id) AS units,
    COUNT(*) FILTER (
      patent_count IS NULL OR patent_count_ref IS NULL OR dy IS NULL
    ) AS missing_outcomes,
    MIN(event_time) AS min_event_time,
    MAX(event_time) AS max_event_time
  FROM raw_did_panel
")
if (panel_check$rows != 11 * unit_checks$rows ||
    panel_check$units != unit_checks$rows ||
    panel_check$missing_outcomes != 0L ||
    panel_check$min_event_time != -5L ||
    panel_check$max_event_time != 5L) {
  stop("Raw event panel failed its grain or outcome checks")
}
write_csv(panel_check, "raw_did_panel_checks")

cr1_covariance <- function(cluster_matrix) {
  n_cluster <- nrow(cluster_matrix)
  if (n_cluster < 2L) stop("Fewer than two clusters")
  n_cluster / (n_cluster - 1) * crossprod(cluster_matrix)
}

cluster_influence <- function(influence_table, cluster_cols, periods) {
  cluster_sql <- paste(cluster_cols, collapse = ", ")
  value_names <- paste0("e", ifelse(periods < 0, "m", "p"), abs(periods))
  expressions <- paste(sprintf(
    "COALESCE(SUM(influence) FILTER (event_time=%d), 0) AS %s",
    periods, value_names
  ), collapse = ", ")
  out <- DBI::dbGetQuery(con, sprintf(
    "SELECT %s, %s FROM %s GROUP BY %s",
    cluster_sql, expressions, influence_table, cluster_sql
  ))
  matrix <- as.matrix(out[, value_names, drop = FALSE])
  storage.mode(matrix) <- "double"
  matrix <- sweep(matrix, 2L, colMeans(matrix), "-")
  list(matrix = matrix, n = nrow(matrix))
}

estimate_raw_did <- function(spec_id, sample_condition = "") {
  sample_condition <- trimws(sample_condition)
  filter_sql <- if (nzchar(sample_condition)) {
    paste("WHERE", sample_condition)
  } else ""
  event_filter_sql <- if (nzchar(sample_condition)) {
    paste("AND", sample_condition)
  } else ""
  stats_table <- paste0("raw_stats_", spec_id)
  influence_table <- paste0("raw_influence_", spec_id)

  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE %1$s AS
    WITH sample AS (
      SELECT * FROM raw_did_panel %2$s
    ),
    arm_stats AS (
      SELECT
        cohort, event_time, arm,
        COUNT(*) AS n_units,
        AVG(patent_count) AS mean_y,
        AVG(dy) AS mean_dy
      FROM sample
      GROUP BY 1, 2, 3
    ),
    treated_mass AS (
      SELECT cohort, MAX(n_units) AS n_treated
      FROM arm_stats
      WHERE arm='treated'
      GROUP BY cohort
    ),
    shares AS (
      SELECT cohort, n_treated,
             n_treated / SUM(n_treated) OVER () AS cohort_weight
      FROM treated_mass
    )
    SELECT a.*, s.n_treated, s.cohort_weight
    FROM arm_stats a
    JOIN shares s USING (cohort)
  ", stats_table, filter_sql))

  missing_cells <- DBI::dbGetQuery(con, sprintf("
    SELECT COUNT(*) AS n
    FROM (
      SELECT cohort, event_time
      FROM %s
      GROUP BY 1, 2
      HAVING COUNT(DISTINCT arm) <> 2 OR MIN(n_units) = 0
    )", stats_table))$n
  if (missing_cells != 0L) {
    stop("A raw DiD cohort-event cell lacks one arm: ", spec_id)
  }

  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE %1$s AS
    WITH sample AS (
      SELECT * FROM raw_did_panel
      WHERE event_time <> -1 %2$s
    )
    SELECT
      p.cohort, p.event_time, p.arm, p.codinv, p.cluster_id,
      s.cohort_weight,
      CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END *
        s.cohort_weight / s.n_units * (p.dy - s.mean_dy)
        AS influence
    FROM sample p
    JOIN %3$s s USING (cohort, event_time, arm)
  ", influence_table,
  event_filter_sql,
  stats_table))

  periods <- setdiff(-5:5, -1L)
  point <- DBI::dbGetQuery(con, sprintf("
    WITH contrasts AS (
      SELECT
        t.cohort, t.event_time, t.cohort_weight,
        t.mean_dy - c.mean_dy AS estimate
      FROM %1$s t
      JOIN %1$s c USING (cohort, event_time)
      WHERE t.arm='treated' AND c.arm='control'
    )
    SELECT event_time, SUM(cohort_weight * estimate) AS estimate
    FROM contrasts
    WHERE event_time <> -1
    GROUP BY event_time
    ORDER BY event_time
  ", stats_table))
  if (!identical(point$event_time, as.integer(periods))) {
    stop("Unexpected dynamic event-time set: ", spec_id)
  }

  influence_sum <- DBI::dbGetQuery(con, sprintf(
    "SELECT MAX(ABS(s)) AS max_abs
     FROM (
       SELECT event_time, SUM(influence) AS s
       FROM %s GROUP BY event_time
     )", influence_table
  ))$max_abs
  if (!is.finite(influence_sum) || influence_sum > 1e-8) {
    stop("Influence functions do not sum to zero: ", spec_id)
  }

  by_cluster <- cluster_influence(
    influence_table, "cluster_id", periods
  )
  by_inventor <- cluster_influence(
    influence_table, "codinv", periods
  )
  by_intersection <- cluster_influence(
    influence_table, c("cluster_id", "codinv"), periods
  )
  covariance <- cr1_covariance(by_cluster$matrix) +
    cr1_covariance(by_inventor$matrix) -
    cr1_covariance(by_intersection$matrix)
  if (any(diag(covariance) < -1e-12)) {
    stop("Materially negative two-way variance: ", spec_id)
  }
  diag(covariance) <- pmax(diag(covariance), 0)
  degrees_freedom <- min(by_cluster$n, by_inventor$n) - 1L
  critical <- stats::qt(0.975, degrees_freedom)
  standard_error <- sqrt(diag(covariance))
  dynamic <- data.frame(
    specification = spec_id,
    event_time = periods,
    estimate = point$estimate,
    se = standard_error,
    df = degrees_freedom,
    ci_low = point$estimate - critical * standard_error,
    ci_high = point$estimate + critical * standard_error,
    inference = "two_way_focal_cluster_inventor",
    stringsAsFactors = FALSE
  )
  dynamic <- rbind(
    dynamic,
    data.frame(
      specification = spec_id, event_time = -1L,
      estimate = 0, se = 0, df = degrees_freedom,
      ci_low = 0, ci_high = 0, inference = "reference_period",
      stringsAsFactors = FALSE
    )
  )
  dynamic <- dynamic[order(dynamic$event_time), ]

  post_index <- match(1:5, periods)
  post_loading <- rep(1 / 5, 5)
  post_estimate <- sum(post_loading * point$estimate[post_index])
  post_variance <- as.numeric(
    t(post_loading) %*%
      covariance[post_index, post_index, drop = FALSE] %*%
      post_loading
  )
  post_se <- sqrt(post_variance)
  post <- data.frame(
    specification = spec_id,
    summary = c("average_annual_t1_to_t5", "cumulative_t1_to_t5"),
    estimate = c(post_estimate, 5 * post_estimate),
    se = c(post_se, 5 * post_se),
    df = degrees_freedom,
    ci_low = c(
      post_estimate - critical * post_se,
      5 * (post_estimate - critical * post_se)
    ),
    ci_high = c(
      post_estimate + critical * post_se,
      5 * (post_estimate + critical * post_se)
    ),
    p_value = 2 * stats::pt(
      -abs(c(post_estimate / post_se, post_estimate / post_se)),
      degrees_freedom
    ),
    inference = "two_way_focal_cluster_inventor",
    stringsAsFactors = FALSE
  )

  pre_index <- match(-5:-2, periods)
  pre_beta <- point$estimate[pre_index]
  pre_covariance <- covariance[pre_index, pre_index, drop = FALSE]
  pre_f <- as.numeric(
    t(pre_beta) %*% solve(pre_covariance, pre_beta)
  ) / length(pre_index)
  pretrend <- data.frame(
    specification = spec_id,
    periods = "-5;-4;-3;-2",
    f_stat = pre_f,
    df1 = length(pre_index),
    df2 = degrees_freedom,
    p_value = stats::pf(
      pre_f, length(pre_index), degrees_freedom, lower.tail = FALSE
    ),
    stringsAsFactors = FALSE
  )

  means <- DBI::dbGetQuery(con, sprintf("
    SELECT
      event_time, arm,
      SUM(cohort_weight * mean_y) AS mean_patent_count,
      SUM(cohort_weight * n_units) AS displayed_weighted_units
    FROM %s
    GROUP BY event_time, arm
    ORDER BY event_time, arm
  ", stats_table))
  means$specification <- spec_id

  counts <- DBI::dbGetQuery(con, sprintf("
    SELECT
      '%1$s' AS specification,
      arm,
      COUNT(*) AS inventor_cohort_rows,
      COUNT(DISTINCT codinv) AS distinct_inventors,
      COUNT(DISTINCT cluster_id) AS focal_clusters
    FROM raw_did_units
    %2$s
    GROUP BY arm
    ORDER BY arm
  ", spec_id, filter_sql))

  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", stats_table))
  list(
    dynamic = dynamic, post = post, pretrend = pretrend,
    means = means, counts = counts
  )
}

full_result <- estimate_raw_did(
  "full_cohort_unmatched"
)
stayer_result <- estimate_raw_did(
  "focal_entity_stayer_unmatched", "stayer"
)
any_post_t1_result <- estimate_raw_did(
  "any_post_patent_t1_t5_unmatched", "any_post_patent_t1_t5"
)
any_post_t0_result <- estimate_raw_did(
  "any_post_patent_t0_t5_unmatched", "any_post_patent_t0_t5"
)
all_results <- list(
  full_result, stayer_result, any_post_t1_result, any_post_t0_result
)

dynamic <- do.call(rbind, lapply(all_results, `[[`, "dynamic"))
post <- do.call(rbind, lapply(all_results, `[[`, "post"))
pretrend <- do.call(rbind, lapply(all_results, `[[`, "pretrend"))
means <- do.call(rbind, lapply(all_results, `[[`, "means"))
counts <- do.call(rbind, lapply(all_results, `[[`, "counts"))
write_csv(dynamic, "raw_did_dynamic_estimates")
write_csv(post, "raw_did_post_att")
write_csv(pretrend, "raw_did_joint_pretrend")
write_csv(means, "raw_did_standardized_mean_paths")
write_csv(counts, "raw_did_sample_counts")

spec_labels <- c(
  full_cohort_unmatched = "Full pre-deal target-inventor cohort",
  focal_entity_stayer_unmatched =
    "Focal-entity stayers, qualification in years +1 to +5",
  any_post_patent_t1_t5_unmatched =
    "Any-patent subsample, years +1 to +5",
  any_post_patent_t0_t5_unmatched =
    "Any-patent subsample, years 0 to +5"
)
arm_labels <- c(
  treated = "Acquisition-treated",
  control = "Placebo-treated controls"
)

plot_one <- function(spec_id, file_stem) {
  m <- means[means$specification == spec_id, , drop = FALSE]
  d <- dynamic[dynamic$specification == spec_id, , drop = FALSE]
  m$arm_label <- factor(
    arm_labels[m$arm],
    levels = c("Acquisition-treated", "Placebo-treated controls")
  )

  p_means <- ggplot2::ggplot(
    m, ggplot2::aes(
      x = event_time, y = mean_patent_count,
      colour = arm_label, linetype = arm_label, shape = arm_label
    )
  ) +
    ggplot2::geom_vline(
      xintercept = 0, linewidth = 0.4, colour = "grey55"
    ) +
    ggplot2::geom_line(linewidth = 0.75) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::scale_colour_manual(
      values = c("Acquisition-treated" = "#0072B2",
                 "Placebo-treated controls" = "#D55E00")
    ) +
    ggplot2::scale_linetype_manual(
      values = c("Acquisition-treated" = "solid",
                 "Placebo-treated controls" = "longdash")
    ) +
    ggplot2::scale_shape_manual(
      values = c("Acquisition-treated" = 16,
                 "Placebo-treated controls" = 17)
    ) +
    ggplot2::scale_x_continuous(breaks = -5:5) +
    ggplot2::labs(
      x = NULL, y = "Mean patent applications",
      title = "A. Unmatched outcome paths",
      colour = NULL, linetype = NULL, shape = NULL
    )

  p_did <- ggplot2::ggplot(
    d, ggplot2::aes(x = event_time, y = estimate)
  ) +
    ggplot2::geom_hline(
      yintercept = 0, linewidth = 0.4, colour = "grey45"
    ) +
    ggplot2::geom_vline(
      xintercept = 0, linewidth = 0.4, colour = "grey55"
    ) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = ci_low, ymax = ci_high),
      width = 0.14, linewidth = 0.55, colour = "#0072B2"
    ) +
    ggplot2::geom_line(linewidth = 0.7, colour = "#0072B2") +
    ggplot2::geom_point(size = 1.8, colour = "#0072B2") +
    ggplot2::scale_x_continuous(breaks = -5:5) +
    ggplot2::labs(
      x = "Event time relative to acquisition or placebo year",
      y = "Difference-in-differences estimate",
      title = "B. Unmatched DiD coefficients (95% CI)"
    )

  common_theme <- ggplot2::theme_minimal(base_size = 10.5) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "plain", size = 10.5),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      legend.position = "top",
      legend.justification = "left",
      plot.margin = ggplot2::margin(6, 8, 6, 8)
    )
  p_means <- p_means + common_theme
  p_did <- p_did + common_theme +
    ggplot2::theme(legend.position = "none")

  png_path <- file.path(FIG_DIR, paste0(file_stem, ".png"))
  pdf_path <- file.path(FIG_DIR, paste0(file_stem, ".pdf"))
  spec_counts <- counts[counts$specification == spec_id, , drop = FALSE]
  n_treated <- spec_counts$inventor_cohort_rows[
    spec_counts$arm == "treated"
  ]
  n_control <- spec_counts$inventor_cohort_rows[
    spec_counts$arm == "control"
  ]
  subtitle <- paste(
    sprintf(
      "Raw P2-eligible sample: %s treated and %s placebo-control inventor-cohort rows.",
      format(n_treated, big.mark = ",", scientific = FALSE),
      format(n_control, big.mark = ",", scientific = FALSE)
    ),
    "Controls use the frozen placebo cohort.",
    "No matching, balancing, calipers, support trimming, or covariates."
  )
  caption <- paste(
    "Notes: Cohort-specific means are standardized to the treated-cohort",
    "distribution. DiD coefficients use t = -1 as the reference period.",
    "Confidence intervals use two-way focal-cluster and inventor inference.",
    if (spec_id == "focal_entity_stayer_unmatched") {
      paste(
        "The frozen main-design stayer rule requires at least one",
        "focal-entity patent in years +1 to +5; year 0 cannot qualify.",
        "Because this conditions on a post-treatment outcome, the panel is",
        "descriptive rather than a full-cohort causal ATT."
      )
    } else if (spec_id == "any_post_patent_t1_t5_unmatched") {
      paste(
        "The sample conditions on any patent in years +1 to +5, a",
        "post-treatment outcome. This is a descriptive selected-sample",
        "contrast rather than a full-cohort causal ATT."
      )
    } else if (spec_id == "any_post_patent_t0_t5_unmatched") {
      paste(
        "The sample conditions on any patent in years 0 to +5, including",
        "the acquisition or placebo year. This is a descriptive",
        "selected-sample contrast rather than a full-cohort causal ATT."
      )
    } else ""
  )
  subtitle <- paste(strwrap(subtitle, width = 104), collapse = "\n")
  caption <- paste(strwrap(caption, width = 116), collapse = "\n")
  combined <- gridExtra::arrangeGrob(
    grid::textGrob(
      spec_labels[[spec_id]], x = 0, just = "left",
      gp = grid::gpar(fontsize = 12)
    ),
    grid::textGrob(
      subtitle, x = 0, just = "left",
      gp = grid::gpar(fontsize = 9.5)
    ),
    p_means,
    p_did,
    grid::textGrob(
      caption, x = 0, just = "left",
      gp = grid::gpar(fontsize = 8, col = "grey30")
    ),
    ncol = 1L,
    heights = c(0.5, 1.15, 3, 3, 1.15)
  )
  ggplot2::ggsave(
    png_path, combined, width = 7.2, height = 7.0,
    units = "in", dpi = 320, bg = "white"
  )
  ggplot2::ggsave(
    pdf_path, combined, width = 7.2, height = 7.0,
    units = "in", device = grDevices::cairo_pdf
  )
  c(png = png_path, pdf = pdf_path)
}

full_figures <- plot_one(
  "full_cohort_unmatched", "appendix_raw_did_full_cohort"
)
stayer_figures <- plot_one(
  "focal_entity_stayer_unmatched", "appendix_raw_did_stayers"
)
any_post_t1_figures <- plot_one(
  "any_post_patent_t1_t5_unmatched",
  "appendix_raw_did_any_post_patent_t1_t5"
)
any_post_t0_figures <- plot_one(
  "any_post_patent_t0_t5_unmatched",
  "appendix_raw_did_any_post_patent_t0_t5"
)

figure_manifest <- data.frame(
  specification = rep(names(spec_labels), each = 2L),
  format = rep(c("png", "pdf"), times = length(spec_labels)),
  path = c(
    full_figures, stayer_figures,
    any_post_t1_figures, any_post_t0_figures
  ),
  stringsAsFactors = FALSE
)
write_csv(figure_manifest, "raw_did_figure_manifest")

manifest <- data.frame(
  analysis = "unmatched_raw_did_appendix",
  database = DB_PATH,
  output_directory = OUT_DIR,
  figure_directory = FIG_DIR,
  treatment_clock = "actual acquisition cohort for treated; frozen P2 placebo cohort for controls",
  treated_sample = "all lmv2_treated_primary inventors",
  control_sample = "all lmv2_control_inventor_eligibility inventor-cohort rows",
  matching = "none",
  reference_period = -1L,
  event_window = "-5:5",
  post_summary = "average annual t=1:5",
  inference = "two-way focal-cluster and inventor",
  stringsAsFactors = FALSE
)
write_csv(manifest, "raw_did_manifest")

message(
  "Raw DiD appendix diagnostics complete. Outputs: ", OUT_DIR,
  " | figures: ", FIG_DIR
)
