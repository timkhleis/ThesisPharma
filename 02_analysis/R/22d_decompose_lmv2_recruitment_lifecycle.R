# ============================================================================
# 22d_decompose_lmv2_recruitment_lifecycle.R
# Common-deal-support and lifecycle decomposition of inventor recruitment.
#
# Descriptive diagnostic only. The script holds the treated deal support fixed
# to deals represented in the t=-7/-6 landmark cohort, applies the frozen
# placebo clocks, and classifies inventors symmetrically as:
#   continuing incumbent = present in both recruitment windows
#   recent entrant        = present only in t=-5,...,-1
#   legacy-only inventor  = present only in t=-7/-6
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
for (pkg in c("DBI", "duckdb", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

DB_PATH <- normalizePath(
  read_arg("db", file.path(BASE, "output", "thesis_foundation.duckdb")),
  winslash = "/", mustWork = TRUE
)
OUT_DIR <- read_arg(
  "output-dir",
  file.path(BASE, "output", "audit", "local_match_v2",
            "P6_RECRUITMENT_LIFECYCLE")
)
FIG_DIR <- read_arg(
  "figure-dir",
  file.path(BASE, "output", "figures", "local_match_v2",
            "recruitment_lifecycle")
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
  "lmv2_treated_primary", "lmv2_control_inventor_eligibility",
  "lmv2_control_firm_eligibility", "cassi_deal_group_spine_expanded",
  "deal_target_company_expanded", "deal_target_company_strict",
  "patent_company_link", "patent_inventor", "inventor_affiliation_own",
  "inventor_year"
)
available <- DBI::dbGetQuery(con, "
  SELECT table_name FROM information_schema.tables WHERE table_schema='main'
")$table_name
missing_tables <- setdiff(required_tables, available)
if (length(missing_tables)) {
  stop("Missing required tables: ", paste(missing_tables, collapse = ", "))
}

DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_target_exposures AS
  SELECT DISTINCT
    CAST(pi.codinv AS BIGINT) AS codinv,
    CAST(s.deal_year AS INTEGER) AS exposure_year
  FROM cassi_deal_group_spine_expanded s
  JOIN deal_target_company_expanded dtc ON dtc.deal_id = s.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year BETWEEN CAST(s.deal_year AS INTEGER) - 5
                    AND CAST(s.deal_year AS INTEGER) - 1
  JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
  WHERE pi.codinv IS NOT NULL
")

DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_current_treated AS
  SELECT
    CAST(cohort AS INTEGER) AS cohort,
    'treated' AS arm,
    CAST(codinv AS BIGINT) AS codinv,
    CAST(deal_id AS BIGINT) AS cluster_id,
    CAST(target_group AS BIGINT) AS focal_group
  FROM lmv2_treated_primary
  WHERE cohort BETWEEN 1995 AND 2010
")

DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_current_control AS
  SELECT
    CAST(cohort AS INTEGER) AS cohort,
    'control' AS arm,
    CAST(codinv AS BIGINT) AS codinv,
    -CAST(control_group AS BIGINT) AS cluster_id,
    CAST(control_group AS BIGINT) AS focal_group
  FROM lmv2_control_inventor_eligibility
  WHERE cohort BETWEEN 1995 AND 2010
")

DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_landmark_treated AS
  WITH deals AS (
    SELECT DISTINCT cohort, cluster_id AS deal_id, focal_group AS target_group
    FROM lifecycle_current_treated
  ),
  focal_patent AS (
    SELECT DISTINCT
      d.cohort, d.deal_id, d.target_group,
      CAST(pi.codinv AS BIGINT) AS codinv
    FROM deals d
    JOIN deal_target_company_strict dtc USING (deal_id)
    JOIN patent_company_link pcl
      ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
     AND pcl.year BETWEEN d.cohort - 7 AND d.cohort - 6
    JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
    WHERE pi.codinv IS NOT NULL
  ),
  latest AS (
    SELECT
      f.*, ia.year, ia.resolved_group, ia.candidate_group_count,
      ROW_NUMBER() OVER (
        PARTITION BY f.deal_id, f.codinv ORDER BY ia.year DESC
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
    cohort, 'treated' AS arm, codinv,
    deal_id AS cluster_id, target_group AS focal_group
  FROM exposure_ranked
  WHERE exposure_rank = 1
")

DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_landmark_control AS
  WITH cohorts AS (
    SELECT DISTINCT CAST(cohort AS INTEGER) AS cohort
    FROM lmv2_control_firm_eligibility
    WHERE cohort BETWEEN 1995 AND 2010
  ),
  latest AS (
    SELECT
      s.cohort,
      CAST(ia.codinv AS BIGINT) AS codinv,
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
    l.cohort, 'control' AS arm, l.codinv,
    -CAST(cf.control_group AS BIGINT) AS cluster_id,
    CAST(cf.control_group AS BIGINT) AS focal_group
  FROM latest l
  JOIN lmv2_control_firm_eligibility cf
    ON CAST(cf.cohort AS INTEGER) = l.cohort
   AND CAST(cf.control_group AS BIGINT) = l.resolved_group
  WHERE l.affiliation_rank = 1
    AND l.candidate_group_count = 1
    AND l.resolved_group IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM lifecycle_target_exposures te
      WHERE te.codinv = l.codinv
        AND te.exposure_year <= l.cohort + 5
    )
")

# Hold treated deal support fixed to the deals represented in the landmark
# roster. The placebo pool remains the frozen eligible pool for each cohort.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_common_deals AS
  SELECT DISTINCT cohort, cluster_id
  FROM lifecycle_landmark_treated
")
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_current_treated_common AS
  SELECT c.*
  FROM lifecycle_current_treated c
  JOIN lifecycle_common_deals d USING (cohort, cluster_id)
")

# One row per arm/cohort/focal entity/inventor in the union of the two
# recruitment windows. Membership flags yield the three lifecycle categories.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_union_roster AS
  WITH treated AS (
    SELECT
      COALESCE(c.cohort, l.cohort) AS cohort,
      'treated' AS arm,
      COALESCE(c.codinv, l.codinv) AS codinv,
      COALESCE(c.cluster_id, l.cluster_id) AS cluster_id,
      COALESCE(c.focal_group, l.focal_group) AS focal_group,
      c.codinv IS NOT NULL AS current_member,
      l.codinv IS NOT NULL AS landmark_member
    FROM lifecycle_current_treated_common c
    FULL OUTER JOIN lifecycle_landmark_treated l
      USING (cohort, cluster_id, codinv)
  ),
  controls AS (
    SELECT
      COALESCE(c.cohort, l.cohort) AS cohort,
      'control' AS arm,
      COALESCE(c.codinv, l.codinv) AS codinv,
      COALESCE(c.cluster_id, l.cluster_id) AS cluster_id,
      COALESCE(c.focal_group, l.focal_group) AS focal_group,
      c.codinv IS NOT NULL AS current_member,
      l.codinv IS NOT NULL AS landmark_member
    FROM lifecycle_current_control c
    FULL OUTER JOIN lifecycle_landmark_control l
      USING (cohort, cluster_id, codinv)
  )
  SELECT
    *,
    CASE
      WHEN current_member AND landmark_member THEN 'continuing_incumbent'
      WHEN current_member THEN 'recent_entry'
      WHEN landmark_member THEN 'legacy_only'
    END AS lifecycle_category,
    arm || ':' || CAST(cohort AS VARCHAR) || ':' ||
      CAST(cluster_id AS VARCHAR) || ':' || CAST(codinv AS VARCHAR)
      AS unit_id
  FROM (
    SELECT * FROM treated
    UNION ALL
    SELECT * FROM controls
  )
")

roster_checks <- DBI::dbGetQuery(con, "
  SELECT
    arm, lifecycle_category,
    COUNT(*) AS inventor_cohort_rows,
    COUNT(DISTINCT unit_id) AS unique_rows,
    COUNT(DISTINCT codinv) AS distinct_inventors,
    COUNT(DISTINCT cluster_id) AS focal_clusters,
    COUNT(DISTINCT cohort) AS cohorts,
    COUNT(*) FILTER (
      codinv IS NULL OR cluster_id IS NULL OR focal_group IS NULL
      OR lifecycle_category IS NULL
    ) AS bad_keys
  FROM lifecycle_union_roster
  GROUP BY arm, lifecycle_category
  ORDER BY lifecycle_category, arm
")
if (any(roster_checks$inventor_cohort_rows != roster_checks$unique_rows) ||
    any(roster_checks$bad_keys != 0L)) {
  stop("Lifecycle union roster failed its identity checks")
}
write_csv(roster_checks, "lifecycle_roster_counts")

deal_support <- DBI::dbGetQuery(con, "
  SELECT
    (SELECT COUNT(DISTINCT cluster_id)
     FROM lifecycle_current_treated) AS current_deals,
    (SELECT COUNT(DISTINCT cluster_id)
     FROM lifecycle_common_deals) AS common_landmark_deals,
    (SELECT COUNT(*) FROM lifecycle_current_treated) AS current_treated,
    (SELECT COUNT(*) FROM lifecycle_current_treated_common)
      AS current_treated_common_deals,
    (SELECT COUNT(*) FROM lifecycle_landmark_treated) AS landmark_treated
")
write_csv(deal_support, "lifecycle_common_deal_support")

DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE lifecycle_panel AS
  WITH event_grid AS (
    SELECT r.*, e.event_time, r.cohort + e.event_time AS calendar_year
    FROM lifecycle_union_roster r
    CROSS JOIN range(-7, 6) e(event_time)
  )
  SELECT
    g.*,
    COALESCE(y.patent_count, 0.0) AS patent_count
  FROM event_grid g
  LEFT JOIN inventor_year y
    ON CAST(y.codinv AS BIGINT) = g.codinv
   AND y.year = g.calendar_year
")

panel_check <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT unit_id) AS units,
    MIN(event_time) AS min_event_time,
    MAX(event_time) AS max_event_time,
    COUNT(*) FILTER (patent_count IS NULL) AS missing_outcomes
  FROM lifecycle_panel
")
if (panel_check$rows != 13 * panel_check$units ||
    panel_check$min_event_time != -7L ||
    panel_check$max_event_time != 5L ||
    panel_check$missing_outcomes != 0L) {
  stop("Lifecycle panel failed its grain or outcome checks")
}
write_csv(panel_check, "lifecycle_panel_checks")

specifications <- list(
  common_deals_current = "current_member",
  common_deals_landmark = "landmark_member",
  continuing_incumbent =
    "current_member AND landmark_member",
  recent_entry =
    "current_member AND NOT landmark_member",
  legacy_only =
    "landmark_member AND NOT current_member"
)

compute_specification <- function(spec_id, condition_sql) {
  stats_table <- paste0("lifecycle_stats_", spec_id)
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE %1$s AS
    WITH arm_stats AS (
      SELECT
        cohort, event_time, arm,
        COUNT(*) AS n_units,
        AVG(patent_count) AS mean_y
      FROM lifecycle_panel
      WHERE %2$s
      GROUP BY 1, 2, 3
    ),
    valid_cohorts AS (
      SELECT cohort
      FROM arm_stats
      GROUP BY cohort
      HAVING COUNT(DISTINCT arm) = 2 AND MIN(n_units) > 0
    ),
    treated_mass AS (
      SELECT a.cohort, MAX(a.n_units) AS n_treated
      FROM arm_stats a
      JOIN valid_cohorts v USING (cohort)
      WHERE a.arm='treated'
      GROUP BY a.cohort
    ),
    shares AS (
      SELECT
        cohort,
        n_treated / SUM(n_treated) OVER () AS cohort_weight
      FROM treated_mass
    )
    SELECT a.*, s.cohort_weight
    FROM arm_stats a
    JOIN shares s USING (cohort)
  ", stats_table, condition_sql))

  means <- DBI::dbGetQuery(con, sprintf("
    SELECT
      event_time, arm,
      SUM(cohort_weight * mean_y) AS mean_patent_count
    FROM %s
    GROUP BY event_time, arm
    ORDER BY event_time, arm
  ", stats_table))
  means$specification <- spec_id

  did <- DBI::dbGetQuery(con, sprintf("
    WITH gaps AS (
      SELECT
        t.cohort, t.event_time, t.cohort_weight,
        t.mean_y - c.mean_y AS gap
      FROM %1$s t
      JOIN %1$s c USING (cohort, event_time)
      WHERE t.arm='treated' AND c.arm='control'
    ),
    relative AS (
      SELECT
        g.cohort, g.event_time, g.cohort_weight,
        g.gap - r.gap AS estimate
      FROM gaps g
      JOIN gaps r ON r.cohort=g.cohort AND r.event_time=-1
    )
    SELECT event_time, SUM(cohort_weight * estimate) AS estimate
    FROM relative
    GROUP BY event_time
    ORDER BY event_time
  ", stats_table))
  did$specification <- spec_id

  summary <- data.frame(
    specification = spec_id,
    n_cohorts = length(unique(
      DBI::dbGetQuery(con, sprintf(
        "SELECT DISTINCT cohort FROM %s", stats_table
      ))$cohort
    )),
    pre_rms_t5_t2 = sqrt(mean(
      did$estimate[did$event_time %in% -5:-2]^2
    )),
    pre_max_abs_t5_t2 = max(abs(
      did$estimate[did$event_time %in% -5:-2]
    )),
    post_average_t1_t5 = mean(
      did$estimate[did$event_time %in% 1:5]
    ),
    stringsAsFactors = FALSE
  )

  counts <- DBI::dbGetQuery(con, sprintf("
    SELECT
      '%1$s' AS specification, arm,
      COUNT(*) AS inventor_cohort_rows,
      COUNT(DISTINCT codinv) AS distinct_inventors,
      COUNT(DISTINCT cluster_id) AS focal_clusters
    FROM lifecycle_union_roster
    WHERE %2$s
    GROUP BY arm
    ORDER BY arm
  ", spec_id, condition_sql))

  career <- DBI::dbGetQuery(con, sprintf("
    WITH first_year AS (
      SELECT
        CAST(codinv AS BIGINT) AS codinv,
        MIN(career_first_year) AS career_first_year
      FROM inventor_year
      GROUP BY 1
    ),
    unit_career AS (
      SELECT
        p.arm, p.unit_id, p.codinv, p.cohort,
        p.cohort - f.career_first_year AS career_age,
        SUM(p.patent_count) FILTER (
          p.event_time BETWEEN -5 AND -1
        ) AS patents_t5_t1,
        COUNT(*) FILTER (
          p.event_time BETWEEN -5 AND -1 AND p.patent_count > 0
        ) AS active_years_t5_t1,
        p.cohort - MAX(p.calendar_year) FILTER (
          p.event_time BETWEEN -5 AND -1 AND p.patent_count > 0
        ) AS last_pre_patent_gap,
        SUM((p.event_time + 3) * p.patent_count) FILTER (
          p.event_time BETWEEN -5 AND -1
        ) / 10.0 AS pre_patent_slope
      FROM lifecycle_panel p
      LEFT JOIN first_year f USING (codinv)
      WHERE %1$s
      GROUP BY p.arm, p.unit_id, p.codinv, p.cohort, f.career_first_year
    )
    SELECT
      '%2$s' AS specification, arm,
      COUNT(*) AS inventor_cohort_rows,
      AVG(career_age) AS mean_career_age,
      MEDIAN(career_age) AS median_career_age,
      AVG(patents_t5_t1) AS mean_patents_t5_t1,
      AVG(active_years_t5_t1) AS mean_active_years_t5_t1,
      AVG(last_pre_patent_gap) AS mean_last_pre_patent_gap,
      AVG(pre_patent_slope) AS mean_pre_patent_slope,
      AVG(CAST(last_pre_patent_gap IS NULL AS INTEGER))
        AS share_no_patent_t5_t1
    FROM unit_career
    GROUP BY arm
    ORDER BY arm
  ", condition_sql, spec_id))

  DBI::dbExecute(con, sprintf("DROP TABLE %s", stats_table))
  list(means = means, did = did, summary = summary,
       counts = counts, career = career)
}

results <- Map(
  compute_specification,
  names(specifications),
  unname(specifications)
)
means <- do.call(rbind, lapply(results, `[[`, "means"))
did <- do.call(rbind, lapply(results, `[[`, "did"))
summaries <- do.call(rbind, lapply(results, `[[`, "summary"))
counts <- do.call(rbind, lapply(results, `[[`, "counts"))
career <- do.call(rbind, lapply(results, `[[`, "career"))
write_csv(means, "lifecycle_standardized_mean_paths")
write_csv(did, "lifecycle_did_diagnostics")
write_csv(summaries, "lifecycle_path_summary")
write_csv(counts, "lifecycle_sample_counts")
write_csv(career, "lifecycle_career_composition")

spec_labels <- c(
  common_deals_current = "Current recruitment, common deals",
  common_deals_landmark = "Landmark recruitment, common deals",
  continuing_incumbent = "Continuing incumbents",
  recent_entry = "Recent entrants",
  legacy_only = "Legacy-only inventors"
)
arm_labels <- c(
  treated = "Acquisition-treated",
  control = "Placebo-treated controls"
)
theme_lifecycle <- ggplot2::theme_minimal(base_size = 10.5) +
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

path_plot <- function(spec_ids, title, subtitle, nrow = 1L) {
  x <- means[means$specification %in% spec_ids, ]
  x$sample <- factor(
    spec_labels[x$specification], levels = spec_labels[spec_ids]
  )
  x$arm_label <- factor(
    arm_labels[x$arm], levels = unname(arm_labels)
  )
  ggplot2::ggplot(
    x,
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
    ggplot2::geom_point(size = 1.55) +
    ggplot2::facet_wrap(~sample, nrow = nrow, scales = "free_y") +
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
      title = title, subtitle = subtitle,
      x = "Event time relative to acquisition or placebo year",
      y = "Mean patent applications",
      colour = NULL, linetype = NULL, shape = NULL,
      caption = paste(
        "Unmatched means use the treated-cohort distribution within each",
        "sample. The shaded area marks t=-7/-6. Cohorts 1995-2010."
      )
    ) +
    theme_lifecycle
}

common_plot <- path_plot(
  c("common_deals_current", "common_deals_landmark"),
  "Recruitment-window comparison on common treated deals",
  paste(
    "Both panels use the 242 deals represented in the landmark cohort;",
    "the placebo pool remains fixed."
  )
)
lifecycle_plot <- path_plot(
  c("continuing_incumbent", "recent_entry", "legacy_only"),
  "Inventor lifecycle composition on common deal support",
  paste(
    "Continuing inventors appear in both windows; recent and legacy-only",
    "inventors appear in one window."
  )
)

did_plot_data <- did
did_plot_data$sample <- factor(
  spec_labels[did_plot_data$specification],
  levels = unname(spec_labels)
)
did_plot <- ggplot2::ggplot(
  did_plot_data, ggplot2::aes(event_time, estimate)
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
  ggplot2::geom_line(linewidth = 0.68, colour = "#0072B2") +
  ggplot2::geom_point(size = 1.55, colour = "#0072B2") +
  ggplot2::facet_wrap(~sample, ncol = 2, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = -7:5) +
  ggplot2::labs(
    title = "Lifecycle-specific DiD diagnostics on common deal support",
    subtitle = "Descriptive coefficients relative to t=-1; no matching.",
    x = "Event time relative to acquisition or placebo year",
    y = "Difference-in-differences diagnostic",
    caption = paste(
      "These coefficients are descriptive and have no confidence intervals.",
      "The shaded years define landmark recruitment."
    )
  ) +
  theme_lifecycle +
  ggplot2::theme(legend.position = "none")

save_plot <- function(plot, stem, width, height) {
  png <- file.path(FIG_DIR, paste0(stem, ".png"))
  pdf <- file.path(FIG_DIR, paste0(stem, ".pdf"))
  ggplot2::ggsave(
    png, plot, width = width, height = height,
    units = "in", dpi = 220, bg = "white"
  )
  ggplot2::ggsave(
    pdf, plot, width = width, height = height,
    units = "in", device = grDevices::cairo_pdf
  )
  data.frame(
    figure = stem,
    png = normalizePath(png, winslash = "/", mustWork = TRUE),
    pdf = normalizePath(pdf, winslash = "/", mustWork = TRUE),
    stringsAsFactors = FALSE
  )
}

figure_manifest <- rbind(
  save_plot(
    common_plot, "lifecycle_common_deal_recruitment",
    width = 11.0, height = 5.7
  ),
  save_plot(
    lifecycle_plot, "lifecycle_category_paths",
    width = 11.4, height = 5.8
  ),
  save_plot(
    did_plot, "lifecycle_did_diagnostics",
    width = 10.8, height = 9.0
  )
)
write_csv(figure_manifest, "lifecycle_figure_manifest")

manifest <- data.frame(
  item = c(
    "scope", "treated_deal_support", "cohorts", "event_window",
    "current_window", "landmark_window", "control_clock", "matching"
  ),
  value = c(
    "descriptive lifecycle decomposition; not a causal ATT",
    "deals with at least one landmark-treated inventor",
    "1995-2010", "-7 to +5", "-5 to -1", "-7 and -6",
    "frozen P2 placebo cohort", "none"
  ),
  stringsAsFactors = FALSE
)
write_csv(manifest, "lifecycle_manifest")
message(
  "Lifecycle decomposition complete. Outputs: ", OUT_DIR,
  " | figures: ", FIG_DIR
)
