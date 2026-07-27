# ============================================================================
# 22c_diagnose_lmv2_recruitment_rule.R
# Diagnostic for the inventor recruitment window.
#
# This is not a CS(2021) parallel-trends test. It is an unmatched,
# cohort-standardized pre-treatment path diagnostic using the frozen actual and
# placebo event clocks. It asks:
#   1. Within the current t=-5,...,-1 cohort, do inventors with patents at
#      t=-7 or t=-6 have different career paths from those without them?
#   2. What happens if inventors are recruited at a fixed t=-7/-6 landmark
#      using focal-entity patent evidence, then followed unconditionally?
#
# The landmark exercise holds the accepted treated deals, placebo cohorts, and
# eligible control firms fixed. It changes only inventor recruitment.
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
            "P6_RECRUITMENT_T7_T6")
)
FIG_DIR <- read_arg(
  "figure-dir",
  file.path(BASE, "output", "figures", "local_match_v2",
            "recruitment_t7_t6")
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

required_tables <- c(
  "main.lmv2_treated_primary",
  "main.lmv2_control_inventor_eligibility",
  "main.lmv2_control_firm_eligibility",
  "main.cassi_deal_group_spine_expanded",
  "main.deal_target_company_expanded",
  "main.deal_target_company_strict",
  "main.patent_company_link",
  "main.patent_inventor",
  "main.inventor_affiliation_own",
  "main.inventor_year"
)
available <- DBI::dbGetQuery(con, "
  SELECT table_schema || '.' || table_name AS table_key
  FROM information_schema.tables
")$table_key
missing_tables <- setdiff(required_tables, available)
if (length(missing_tables)) {
  stop("Missing required tables: ", paste(missing_tables, collapse = ", "))
}

# The current control rule excludes inventors with any target exposure whose
# acquisition year is no later than placebo year + 5. Recreate that exclusion
# for landmark-only inventors.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE recruitment_all_target_exposures AS
  SELECT DISTINCT
    CAST(pi.codinv AS BIGINT) AS codinv,
    CAST(s.deal_year AS INTEGER) AS exposure_year
  FROM cassi_deal_group_spine_expanded s
  JOIN deal_target_company_expanded dtc
    ON dtc.deal_id = s.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year BETWEEN CAST(s.deal_year AS INTEGER) - 5
                    AND CAST(s.deal_year AS INTEGER) - 1
  JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
  WHERE pi.codinv IS NOT NULL
")

# Current sample, restricted to cohorts with a complete t=-7,...,+5 window.
# early_patent_t7_t6 is deliberately based on any inventor patent, symmetrically
# across treated and placebo arms.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE recruitment_current_units AS
  WITH treated AS (
    SELECT
      'current' AS design,
      CAST(t.cohort AS INTEGER) AS cohort,
      'treated' AS arm,
      CAST(t.codinv AS BIGINT) AS codinv,
      CAST(t.deal_id AS BIGINT) AS cluster_id,
      CAST(t.target_group AS BIGINT) AS focal_group
    FROM lmv2_treated_primary t
    WHERE t.cohort BETWEEN 1995 AND 2010
  ),
  controls AS (
    SELECT
      'current' AS design,
      CAST(c.cohort AS INTEGER) AS cohort,
      'control' AS arm,
      CAST(c.codinv AS BIGINT) AS codinv,
      -CAST(c.control_group AS BIGINT) AS cluster_id,
      CAST(c.control_group AS BIGINT) AS focal_group
    FROM lmv2_control_inventor_eligibility c
    WHERE c.cohort BETWEEN 1995 AND 2010
  )
  SELECT
    u.*,
    EXISTS (
      SELECT 1
      FROM inventor_year y
      WHERE CAST(y.codinv AS BIGINT) = u.codinv
        AND y.year BETWEEN u.cohort - 7 AND u.cohort - 6
        AND y.patent_count > 0
    ) AS early_patent_t7_t6,
    u.design || ':' || u.arm || ':' || CAST(u.cohort AS VARCHAR) ||
      ':' || CAST(u.cluster_id AS VARCHAR) || ':' ||
      CAST(u.codinv AS VARCHAR) AS unit_id
  FROM (
    SELECT * FROM treated
    UNION ALL
    SELECT * FROM controls
  ) u
")

# Landmark treated inventors: a deal-specific target-company patent at t=-7 or
# t=-6, and a unique latest affiliation in that window resolving to the target.
# Keep the earliest accepted acquisition exposure per inventor, matching the
# current treated-cohort convention.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE recruitment_landmark_treated AS
  WITH accepted_deals AS (
    SELECT DISTINCT
      CAST(deal_id AS BIGINT) AS deal_id,
      CAST(cohort AS INTEGER) AS cohort,
      CAST(target_group AS BIGINT) AS target_group
    FROM lmv2_treated_primary
    WHERE cohort BETWEEN 1995 AND 2010
  ),
  focal_patent AS (
    SELECT DISTINCT
      d.deal_id, d.cohort, d.target_group,
      CAST(pi.codinv AS BIGINT) AS codinv
    FROM accepted_deals d
    JOIN deal_target_company_strict dtc USING (deal_id)
    JOIN patent_company_link pcl
      ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
     AND pcl.year BETWEEN d.cohort - 7 AND d.cohort - 6
    JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
    WHERE pi.codinv IS NOT NULL
  ),
  latest AS (
    SELECT
      f.*,
      ia.year AS latest_landmark_affiliation_year,
      ia.resolved_group,
      ia.candidate_group_count,
      ROW_NUMBER() OVER (
        PARTITION BY f.deal_id, f.codinv
        ORDER BY ia.year DESC
      ) AS affiliation_rank
    FROM focal_patent f
    JOIN inventor_affiliation_own ia
      ON CAST(ia.codinv AS BIGINT) = f.codinv
     AND ia.year BETWEEN f.cohort - 7 AND f.cohort - 6
  ),
  eligible AS (
    SELECT *
    FROM latest
    WHERE affiliation_rank = 1
      AND candidate_group_count = 1
      AND CAST(resolved_group AS BIGINT) = target_group
  ),
  exposure_ranked AS (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY codinv ORDER BY cohort, deal_id
      ) AS exposure_rank
    FROM eligible
  )
  SELECT
    'landmark' AS design,
    cohort,
    'treated' AS arm,
    codinv,
    deal_id AS cluster_id,
    target_group AS focal_group,
    TRUE AS early_patent_t7_t6,
    latest_landmark_affiliation_year,
    design || ':' || arm || ':' || CAST(cohort AS VARCHAR) ||
      ':' || CAST(cluster_id AS VARCHAR) || ':' ||
      CAST(codinv AS VARCHAR) AS unit_id
  FROM exposure_ranked
  WHERE exposure_rank = 1
")

# Landmark controls: use the same accepted placebo cohorts and control firms,
# but choose inventors whose unique latest t=-7/-6 affiliation resolves to that
# focal control group. Apply the frozen target-exposure exclusion.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE recruitment_landmark_control AS
  WITH cohorts AS (
    SELECT DISTINCT CAST(cohort AS INTEGER) AS cohort
    FROM lmv2_control_firm_eligibility
    WHERE cohort BETWEEN 1995 AND 2010
  ),
  latest AS (
    SELECT
      s.cohort,
      CAST(ia.codinv AS BIGINT) AS codinv,
      ia.year AS latest_landmark_affiliation_year,
      CAST(ia.resolved_group AS BIGINT) AS resolved_group,
      ia.candidate_group_count,
      ROW_NUMBER() OVER (
        PARTITION BY s.cohort, CAST(ia.codinv AS BIGINT)
        ORDER BY ia.year DESC
      ) AS affiliation_rank
    FROM cohorts s
    JOIN inventor_affiliation_own ia
      ON ia.year BETWEEN s.cohort - 7 AND s.cohort - 6
  )
  SELECT
    'landmark' AS design,
    l.cohort,
    'control' AS arm,
    l.codinv,
    -CAST(cf.control_group AS BIGINT) AS cluster_id,
    CAST(cf.control_group AS BIGINT) AS focal_group,
    TRUE AS early_patent_t7_t6,
    l.latest_landmark_affiliation_year,
    design || ':' || arm || ':' || CAST(l.cohort AS VARCHAR) ||
      ':' || CAST(cluster_id AS VARCHAR) || ':' ||
      CAST(l.codinv AS VARCHAR) AS unit_id
  FROM latest l
  JOIN lmv2_control_firm_eligibility cf
    ON CAST(cf.cohort AS INTEGER) = l.cohort
   AND CAST(cf.control_group AS BIGINT) = l.resolved_group
  WHERE l.affiliation_rank = 1
    AND l.candidate_group_count = 1
    AND l.resolved_group IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM recruitment_all_target_exposures te
      WHERE te.codinv = l.codinv
        AND te.exposure_year <= l.cohort + 5
    )
")

DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE recruitment_units AS
  SELECT
    design, cohort, arm, codinv, cluster_id, focal_group,
    early_patent_t7_t6, NULL::INTEGER AS landmark_affiliation_year,
    unit_id
  FROM recruitment_current_units
  UNION ALL
  SELECT
    design, cohort, arm, codinv, cluster_id, focal_group,
    early_patent_t7_t6,
    latest_landmark_affiliation_year AS landmark_affiliation_year,
    unit_id
  FROM recruitment_landmark_treated
  UNION ALL
  SELECT
    design, cohort, arm, codinv, cluster_id, focal_group,
    early_patent_t7_t6,
    latest_landmark_affiliation_year AS landmark_affiliation_year,
    unit_id
  FROM recruitment_landmark_control
")

unit_checks <- DBI::dbGetQuery(con, "
  SELECT
    design, arm,
    COUNT(*) AS inventor_cohort_rows,
    COUNT(DISTINCT unit_id) AS unique_unit_rows,
    COUNT(DISTINCT codinv) AS distinct_inventors,
    COUNT(DISTINCT cluster_id) AS focal_clusters,
    COUNT(DISTINCT cohort) AS cohorts,
    SUM(CAST(early_patent_t7_t6 AS INTEGER)) AS early_patent_rows,
    COUNT(*) FILTER (
      codinv IS NULL OR cluster_id IS NULL OR focal_group IS NULL
      OR early_patent_t7_t6 IS NULL
    ) AS bad_keys
  FROM recruitment_units
  GROUP BY design, arm
  ORDER BY design, arm
")
if (any(unit_checks$inventor_cohort_rows != unit_checks$unique_unit_rows) ||
    any(unit_checks$bad_keys != 0L) ||
    any(unit_checks$cohorts != 16L)) {
  stop("Recruitment unit construction failed its grain or key checks")
}
write_csv(unit_checks, "recruitment_unit_counts")

DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE recruitment_panel AS
  WITH event_grid AS (
    SELECT u.*, e.event_time, u.cohort + e.event_time AS calendar_year
    FROM recruitment_units u
    CROSS JOIN range(-7, 6) e(event_time)
  )
  SELECT
    g.*,
    COALESCE(y.patent_count, 0.0) AS patent_count,
    COALESCE(r.patent_count, 0.0) AS patent_count_ref,
    COALESCE(y.patent_count, 0.0) -
      COALESCE(r.patent_count, 0.0) AS dy
  FROM event_grid g
  LEFT JOIN inventor_year y
    ON CAST(y.codinv AS BIGINT) = g.codinv
   AND y.year = g.calendar_year
  LEFT JOIN inventor_year r
    ON CAST(r.codinv AS BIGINT) = g.codinv
   AND r.year = g.cohort - 1
")

panel_check <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT unit_id) AS units,
    MIN(event_time) AS min_event_time,
    MAX(event_time) AS max_event_time,
    COUNT(*) FILTER (
      patent_count IS NULL OR patent_count_ref IS NULL OR dy IS NULL
    ) AS missing_outcomes
  FROM recruitment_panel
")
expected_units <- sum(unit_checks$inventor_cohort_rows)
if (panel_check$rows != 13 * expected_units ||
    panel_check$units != expected_units ||
    panel_check$min_event_time != -7L ||
    panel_check$max_event_time != 5L ||
    panel_check$missing_outcomes != 0L) {
  stop("Recruitment event panel failed its checks")
}
write_csv(panel_check, "recruitment_panel_checks")

cr1_covariance <- function(cluster_matrix) {
  n_cluster <- nrow(cluster_matrix)
  if (n_cluster < 2L) stop("Fewer than two clusters")
  n_cluster / (n_cluster - 1) * crossprod(cluster_matrix)
}

cluster_influence <- function(table_name, cluster_cols, periods) {
  cluster_sql <- paste(cluster_cols, collapse = ", ")
  value_names <- paste0("e", ifelse(periods < 0, "m", "p"), abs(periods))
  expressions <- paste(sprintf(
    "COALESCE(SUM(influence) FILTER (event_time=%d), 0) AS %s",
    periods, value_names
  ), collapse = ", ")
  out <- DBI::dbGetQuery(con, sprintf(
    "SELECT %s, %s FROM %s GROUP BY %s",
    cluster_sql, expressions, table_name, cluster_sql
  ))
  matrix <- as.matrix(out[, value_names, drop = FALSE])
  storage.mode(matrix) <- "double"
  matrix <- sweep(matrix, 2L, colMeans(matrix), "-")
  list(matrix = matrix, n = nrow(matrix))
}

estimate_diagnostic <- function(spec_id, condition_sql) {
  stats_table <- paste0("recruitment_stats_", spec_id)
  influence_table <- paste0("recruitment_if_", spec_id)

  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE %1$s AS
    WITH sample AS (
      SELECT * FROM recruitment_panel WHERE %2$s
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
      SELECT
        cohort, n_treated,
        n_treated / SUM(n_treated) OVER () AS cohort_weight
      FROM treated_mass
    )
    SELECT a.*, s.n_treated, s.cohort_weight
    FROM arm_stats a
    JOIN shares s USING (cohort)
  ", stats_table, condition_sql))

  missing_cells <- DBI::dbGetQuery(con, sprintf("
    SELECT COUNT(*) AS n
    FROM (
      SELECT cohort, event_time
      FROM %s
      GROUP BY 1, 2
      HAVING COUNT(DISTINCT arm) <> 2 OR MIN(n_units) = 0
    )
  ", stats_table))$n
  if (missing_cells != 0L) {
    stop("A cohort-event cell lacks one arm: ", spec_id)
  }

  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE %1$s AS
    WITH sample AS (
      SELECT *
      FROM recruitment_panel
      WHERE (%2$s) AND event_time <> -1
    )
    SELECT
      p.cohort, p.event_time, p.arm, p.codinv, p.cluster_id,
      s.cohort_weight,
      CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END *
        s.cohort_weight / s.n_units * (p.dy - s.mean_dy) AS influence
    FROM sample p
    JOIN %3$s s USING (cohort, event_time, arm)
  ", influence_table, condition_sql, stats_table))

  periods <- setdiff(-7:5, -1L)
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
  if (!identical(as.integer(point$event_time), as.integer(periods))) {
    stop("Unexpected event-time set: ", spec_id)
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
    p_value = 2 * stats::pt(
      -abs(point$estimate / standard_error), degrees_freedom
    ),
    inference = "two_way_focal_cluster_inventor",
    stringsAsFactors = FALSE
  )
  dynamic <- rbind(
    dynamic,
    data.frame(
      specification = spec_id, event_time = -1L,
      estimate = 0, se = 0, df = degrees_freedom,
      ci_low = 0, ci_high = 0, p_value = NA_real_,
      inference = "reference_period", stringsAsFactors = FALSE
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
    summary = "average_annual_t1_to_t5",
    estimate = post_estimate,
    se = post_se,
    df = degrees_freedom,
    ci_low = post_estimate - critical * post_se,
    ci_high = post_estimate + critical * post_se,
    p_value = 2 * stats::pt(
      -abs(post_estimate / post_se), degrees_freedom
    ),
    stringsAsFactors = FALSE
  )

  heldout_index <- match(-5:-2, periods)
  heldout_beta <- point$estimate[heldout_index]
  heldout_cov <- covariance[heldout_index, heldout_index, drop = FALSE]
  heldout_f <- as.numeric(
    t(heldout_beta) %*% solve(heldout_cov, heldout_beta)
  ) / length(heldout_index)
  path_test <- data.frame(
    specification = spec_id,
    periods = "-5;-4;-3;-2",
    test_description =
      "joint pre-treatment path diagnostic relative to t=-1",
    f_stat = heldout_f,
    df1 = length(heldout_index),
    df2 = degrees_freedom,
    p_value = stats::pf(
      heldout_f, length(heldout_index), degrees_freedom,
      lower.tail = FALSE
    ),
    stringsAsFactors = FALSE
  )

  means <- DBI::dbGetQuery(con, sprintf("
    SELECT
      event_time, arm,
      SUM(cohort_weight * mean_y) AS mean_patent_count
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
    FROM recruitment_units
    WHERE %2$s
    GROUP BY arm
    ORDER BY arm
  ", spec_id, condition_sql))

  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", stats_table))
  list(
    dynamic = dynamic, post = post, path_test = path_test,
    means = means, counts = counts
  )
}

specifications <- list(
  current_all_1995_2010 =
    "design='current'",
  current_early_patent_t7_t6 =
    "design='current' AND early_patent_t7_t6",
  current_no_patent_t7_t6 =
    "design='current' AND NOT early_patent_t7_t6",
  landmark_focal_patent_t7_t6 =
    "design='landmark'"
)
results <- Map(
  estimate_diagnostic,
  names(specifications),
  unname(specifications)
)
names(results) <- names(specifications)

dynamic <- do.call(rbind, lapply(results, `[[`, "dynamic"))
post <- do.call(rbind, lapply(results, `[[`, "post"))
path_test <- do.call(rbind, lapply(results, `[[`, "path_test"))
means <- do.call(rbind, lapply(results, `[[`, "means"))
counts <- do.call(rbind, lapply(results, `[[`, "counts"))
write_csv(dynamic, "recruitment_dynamic_did_diagnostics")
write_csv(post, "recruitment_post_did_diagnostics")
write_csv(path_test, "recruitment_prepath_joint_tests")
write_csv(means, "recruitment_standardized_mean_paths")
write_csv(counts, "recruitment_sample_counts")

spec_labels <- c(
  current_all_1995_2010 = "Current cohort: all inventors",
  current_early_patent_t7_t6 =
    "Current cohort: patent at t=-7 or t=-6",
  current_no_patent_t7_t6 =
    "Current cohort: no patent at t=-7 or t=-6",
  landmark_focal_patent_t7_t6 =
    "Landmark cohort: focal patent at t=-7 or t=-6"
)
arm_labels <- c(
  treated = "Acquisition-treated",
  control = "Placebo-treated controls"
)
theme_diagnostic <- ggplot2::theme_minimal(base_size = 10.5) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    legend.position = "top",
    legend.justification = "left",
    strip.text = ggplot2::element_text(face = "plain"),
    plot.title = ggplot2::element_text(face = "plain"),
    plot.caption = ggplot2::element_text(hjust = 0, colour = "grey35"),
    plot.margin = ggplot2::margin(8, 10, 8, 10)
  )

save_plot <- function(plot, stem, width, height) {
  png_path <- file.path(FIG_DIR, paste0(stem, ".png"))
  pdf_path <- file.path(FIG_DIR, paste0(stem, ".pdf"))
  ggplot2::ggsave(
    png_path, plot, width = width, height = height,
    units = "in", dpi = 220, bg = "white"
  )
  ggplot2::ggsave(
    pdf_path, plot, width = width, height = height,
    units = "in", device = grDevices::cairo_pdf
  )
  data.frame(
    figure = stem,
    png = normalizePath(png_path, winslash = "/", mustWork = TRUE),
    pdf = normalizePath(pdf_path, winslash = "/", mustWork = TRUE),
    stringsAsFactors = FALSE
  )
}

current_specs <- c(
  "current_early_patent_t7_t6", "current_no_patent_t7_t6"
)
current_means <- means[means$specification %in% current_specs, ]
current_means$sample <- factor(
  spec_labels[current_means$specification],
  levels = spec_labels[current_specs]
)
current_means$arm_label <- factor(
  arm_labels[current_means$arm],
  levels = unname(arm_labels)
)
current_plot <- ggplot2::ggplot(
  current_means,
  ggplot2::aes(
    event_time, mean_patent_count,
    colour = arm_label, linetype = arm_label, shape = arm_label
  )
) +
  ggplot2::annotate(
    "rect", xmin = -7.45, xmax = -5.55,
    ymin = -Inf, ymax = Inf, fill = "grey70", alpha = 0.16
  ) +
  ggplot2::geom_vline(
    xintercept = 0, linewidth = 0.4, colour = "grey55"
  ) +
  ggplot2::geom_line(linewidth = 0.72) +
  ggplot2::geom_point(size = 1.6) +
  ggplot2::facet_wrap(~sample, nrow = 1, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = -7:5) +
  ggplot2::scale_colour_manual(
    values = c(
      "Acquisition-treated" = "#0072B2",
      "Placebo-treated controls" = "#D55E00"
    )
  ) +
  ggplot2::scale_linetype_manual(
    values = c(
      "Acquisition-treated" = "solid",
      "Placebo-treated controls" = "longdash"
    )
  ) +
  ggplot2::scale_shape_manual(
    values = c(
      "Acquisition-treated" = 16,
      "Placebo-treated controls" = 17
    )
  ) +
  ggplot2::labs(
    title = "Career paths within the current recruitment rule",
    subtitle = paste(
      "Inventors are split by any patent at t=-7 or t=-6;",
      "the shaded area marks those classification years."
    ),
    x = "Event time relative to acquisition or placebo year",
    y = "Mean patent applications",
    colour = NULL, linetype = NULL, shape = NULL,
    caption = paste(
      "Notes: Unmatched means are standardized to the treated-cohort",
      "distribution within each sample. The split uses any inventor patent,",
      "not only focal-entity patents. Cohorts 1995-2010."
    )
  ) +
  theme_diagnostic

landmark_means <- means[
  means$specification == "landmark_focal_patent_t7_t6", ]
landmark_dynamic <- dynamic[
  dynamic$specification == "landmark_focal_patent_t7_t6", ]
landmark_means$arm_label <- factor(
  arm_labels[landmark_means$arm],
  levels = unname(arm_labels)
)
p_landmark_mean <- ggplot2::ggplot(
  landmark_means,
  ggplot2::aes(
    event_time, mean_patent_count,
    colour = arm_label, linetype = arm_label, shape = arm_label
  )
) +
  ggplot2::annotate(
    "rect", xmin = -7.45, xmax = -5.55,
    ymin = -Inf, ymax = Inf, fill = "grey70", alpha = 0.16
  ) +
  ggplot2::geom_vline(
    xintercept = 0, linewidth = 0.4, colour = "grey55"
  ) +
  ggplot2::geom_line(linewidth = 0.72) +
  ggplot2::geom_point(size = 1.6) +
  ggplot2::scale_x_continuous(breaks = -7:5) +
  ggplot2::scale_colour_manual(
    values = c(
      "Acquisition-treated" = "#0072B2",
      "Placebo-treated controls" = "#D55E00"
    )
  ) +
  ggplot2::scale_linetype_manual(
    values = c(
      "Acquisition-treated" = "solid",
      "Placebo-treated controls" = "longdash"
    )
  ) +
  ggplot2::scale_shape_manual(
    values = c(
      "Acquisition-treated" = 16,
      "Placebo-treated controls" = 17
    )
  ) +
  ggplot2::labs(
    title = "A. Unmatched landmark-cohort paths",
    x = NULL, y = "Mean patent applications",
    colour = NULL, linetype = NULL, shape = NULL
  ) +
  theme_diagnostic

p_landmark_did <- ggplot2::ggplot(
  landmark_dynamic,
  ggplot2::aes(event_time, estimate)
) +
  ggplot2::annotate(
    "rect", xmin = -7.45, xmax = -5.55,
    ymin = -Inf, ymax = Inf, fill = "grey70", alpha = 0.16
  ) +
  ggplot2::geom_hline(
    yintercept = 0, linewidth = 0.4, colour = "grey45"
  ) +
  ggplot2::geom_vline(
    xintercept = 0, linewidth = 0.4, colour = "grey55"
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci_low, ymax = ci_high),
    width = 0.13, linewidth = 0.52, colour = "#0072B2"
  ) +
  ggplot2::geom_line(linewidth = 0.68, colour = "#0072B2") +
  ggplot2::geom_point(size = 1.6, colour = "#0072B2") +
  ggplot2::scale_x_continuous(breaks = -7:5) +
  ggplot2::labs(
    title = "B. Landmark DiD diagnostics (95% CI)",
    x = "Event time relative to acquisition or placebo year",
    y = "Difference-in-differences diagnostic"
  ) +
  theme_diagnostic +
  ggplot2::theme(legend.position = "none")

landmark_counts <- counts[
  counts$specification == "landmark_focal_patent_t7_t6", ]
landmark_subtitle <- sprintf(
  paste(
    "Recruitment uses focal-entity patent evidence at t=-7/-6:",
    "%s treated and %s placebo-control inventor-cohort rows."
  ),
  format(
    landmark_counts$inventor_cohort_rows[
      landmark_counts$arm == "treated"],
    big.mark = ",", scientific = FALSE
  ),
  format(
    landmark_counts$inventor_cohort_rows[
      landmark_counts$arm == "control"],
    big.mark = ",", scientific = FALSE
  )
)
landmark_caption <- paste(
  "Notes: The shaded years define landmark recruitment and should not be",
  "read as standard pre-trend evidence. The joint diagnostic tests t=-5",
  "through t=-2 relative to t=-1. Means use the treated-cohort distribution;",
  "confidence intervals use two-way focal-cluster and inventor inference.",
  "No matching, balancing, calipers, trimming, or covariates."
)
landmark_grob <- gridExtra::arrangeGrob(
  grid::textGrob(
    "Fixed t=-7/-6 landmark recruitment",
    x = 0, just = "left",
    gp = grid::gpar(fontsize = 15, fontface = "plain")
  ),
  grid::textGrob(
    paste(strwrap(landmark_subtitle, width = 110), collapse = "\n"),
    x = 0, just = "left",
    gp = grid::gpar(fontsize = 9.5)
  ),
  p_landmark_mean,
  p_landmark_did,
  grid::textGrob(
    paste(strwrap(landmark_caption, width = 118), collapse = "\n"),
    x = 0, just = "left",
    gp = grid::gpar(fontsize = 8, col = "grey35")
  ),
  ncol = 1,
  heights = grid::unit(c(0.35, 0.55, 3.2, 3.2, 0.75), "null")
)

comparison_dynamic <- dynamic
comparison_dynamic$sample <- factor(
  spec_labels[comparison_dynamic$specification],
  levels = unname(spec_labels)
)
comparison_plot <- ggplot2::ggplot(
  comparison_dynamic,
  ggplot2::aes(event_time, estimate)
) +
  ggplot2::annotate(
    "rect", xmin = -7.45, xmax = -5.55,
    ymin = -Inf, ymax = Inf, fill = "grey70", alpha = 0.16
  ) +
  ggplot2::geom_hline(
    yintercept = 0, linewidth = 0.4, colour = "grey45"
  ) +
  ggplot2::geom_vline(
    xintercept = 0, linewidth = 0.4, colour = "grey55"
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci_low, ymax = ci_high),
    width = 0.13, linewidth = 0.48, colour = "#0072B2"
  ) +
  ggplot2::geom_line(linewidth = 0.65, colour = "#0072B2") +
  ggplot2::geom_point(size = 1.5, colour = "#0072B2") +
  ggplot2::facet_wrap(~sample, ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -7:5) +
  ggplot2::labs(
    title = "How the recruitment rule changes the DiD diagnostic",
    subtitle = paste(
      "All panels use the same accepted acquisition and placebo clocks;",
      "t=-1 is the reference year."
    ),
    x = "Event time relative to acquisition or placebo year",
    y = "Difference-in-differences diagnostic",
    caption = paste(
      "The shaded t=-7/-6 years define the split or landmark sample.",
      "The joint pre-treatment path test therefore uses t=-5,...,-2.",
      "These are unmatched diagnostics, not CS(2021) group-time estimates."
    )
  ) +
  theme_diagnostic +
  ggplot2::theme(legend.position = "none")

figure_manifest <- rbind(
  save_plot(
    current_plot, "recruitment_current_cohort_t7_t6_strata",
    width = 11.2, height = 5.7
  ),
  save_plot(
    landmark_grob, "recruitment_landmark_t7_t6",
    width = 9.4, height = 9.0
  ),
  save_plot(
    comparison_plot, "recruitment_did_comparison",
    width = 10.8, height = 7.8
  )
)
write_csv(figure_manifest, "recruitment_figure_manifest")

manifest <- data.frame(
  item = c(
    "diagnostic_scope", "cohorts", "event_window",
    "classification_window", "reference_period",
    "heldout_prepath_test", "control_clock", "matching",
    "outcome", "inference"
  ),
  value = c(
    "unmatched pre-treatment path diagnostic; not CS(2021) pretrend test",
    "1995-2010", "-7 to +5", "-7 and -6", "-1",
    "-5 through -2 relative to -1",
    "frozen P2 placebo cohort", "none",
    "annual distinct inventor-application patent count",
    "two-way focal cluster and inventor"
  ),
  stringsAsFactors = FALSE
)
write_csv(manifest, "recruitment_manifest")

message(
  "Recruitment diagnostic complete. Outputs: ", OUT_DIR,
  " | figures: ", FIG_DIR
)
