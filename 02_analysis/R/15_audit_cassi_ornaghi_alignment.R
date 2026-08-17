# Diagnose differences between the thesis P2/P3 descriptives and the published
# Cassi--Ornaghi separation-sample statistics.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
FOUNDATION <- normalizePath(file.path(".worktrees", "lmv2-foundation", "02_analysis"),
                            mustWork = TRUE)
ROOT_PAR <- file.path(BASE, "output", "parquet")
LMV2_PAR <- file.path(FOUNDATION, "output", "parquet")
OUT <- file.path(BASE, "output", "results", "data_section")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

paths <- list(
  status = file.path(ROOT_PAR, "reference", "inventor_status_reference.parquet"),
  inventor_production = file.path(ROOT_PAR, "helper", "inventor_production.parquet"),
  group_production = file.path(ROOT_PAR, "helper", "group_production.parquet"),
  deal_assignment = file.path(LMV2_PAR, "helper", "deal_assignment.parquet"),
  treated = file.path(LMV2_PAR, "derived", "lmv2_treated_primary.parquet"),
  inventor_covariates = file.path(LMV2_PAR, "derived",
                                  "lmv2_p3_treated_inventor_units.parquet"),
  firm_covariates = file.path(LMV2_PAR, "derived", "lmv2_p3_firm_units.parquet")
)
missing <- names(paths)[!file.exists(unlist(paths))]
if (length(missing)) stop("Missing inputs: ", paste(missing, collapse = ", "))
sql_path <- function(x) gsub("'", "''", gsub("\\\\", "/", normalizePath(x)))
p <- lapply(paths, sql_path)

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=2")
DBI::dbExecute(con, "PRAGMA memory_limit='4GB'")

# Recreate the exact 760,047-observation separation sample and attach deal IDs.
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE cassi_separation AS
  WITH status_ok AS (
    SELECT *,
      COUNT(*) OVER (PARTITION BY codinv) AS n_status,
      COUNT(*) FILTER (WHERE type = 'N_LEAVER')
        OVER (PARTITION BY codinv) AS n_nleave,
      COUNT(DISTINCT COALESCE(CAST(id_group AS VARCHAR), 'MISSING'))
        OVER (PARTITION BY codinv) AS n_groups
    FROM read_parquet('%s')
  ), prod AS (
    SELECT *,
      SUM(patent) OVER (
        PARTITION BY codinv ORDER BY year
        RANGE BETWEEN 4 PRECEDING AND CURRENT ROW
      ) / 5.0 AS productivity5
    FROM read_parquet('%s')
  ), deal_bridge AS (
    SELECT CAST(deal_id AS BIGINT) deal_id, CAST(target_year AS INTEGER) target_year,
           target_value
    FROM read_parquet('%s')
  )
  SELECT s.codinv, CAST(s.year AS INTEGER) status_year, s.id_group, s.type,
         CASE WHEN s.type LIKE 'T_%%' THEN 1 ELSE 0 END AS target,
         p.productivity5, gp.patent AS group_patent,
         d.deal_id, CAST(s.target_year AS INTEGER) target_year
  FROM status_ok s
  JOIN prod p ON s.codinv = p.codinv AND CAST(s.year AS INTEGER) = p.year
  JOIN read_parquet('%s') gp
    ON s.id_group = gp.id_group AND CAST(s.year AS INTEGER) = gp.year
  LEFT JOIN deal_bridge d
    ON CAST(s.target_year AS INTEGER) = d.target_year
   AND s.target_value = d.target_value
  WHERE s.n_status > 1
    AND s.n_nleave * 1.0 / s.n_groups <= 1
    AND s.type <> 'last year'
    AND gp.patent > 0
", p$status, p$inventor_production, p$deal_assignment, p$group_production))

sample_sizes <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) n, SUM(target) target_n,
         AVG(productivity5) productivity5, AVG(group_patent) group_patent
  FROM cassi_separation
")
if (sample_sizes$n != 760047L ||
    abs(sample_sizes$productivity5 - 1.0701259264) > 1e-8 ||
    abs(sample_sizes$group_patent - 202.1) > 0.1) {
  stop("Cassi--Ornaghi separation sample does not reproduce Table 3.")
}

# Compare like with like. Rows remain separation observations, so large groups
# and frequently observed inventors receive greater weight, as in Table 3.
cassi_decomposition <- DBI::dbGetQuery(con, sprintf("
  WITH p2_deals AS (
    SELECT DISTINCT CAST(deal_id AS BIGINT) deal_id
    FROM read_parquet('%s')
  ), p2_units AS (
    SELECT DISTINCT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id
    FROM read_parquet('%s')
  ), tagged AS (
    SELECT c.*,
      c.deal_id IN (SELECT deal_id FROM p2_deals) AS p2_deal,
      EXISTS (
        SELECT 1 FROM p2_units u
        WHERE u.codinv = c.codinv AND u.deal_id = c.deal_id
      ) AS exact_p2_unit
    FROM cassi_separation c
  ), samples AS (
    SELECT '1. Published separation sample: all observations' AS sample_label,
           * FROM tagged
    UNION ALL
    SELECT '2. Published separation sample: non-target observations',
           * FROM tagged WHERE target = 0
    UNION ALL
    SELECT '3. Published separation sample: target observations',
           * FROM tagged WHERE target = 1
    UNION ALL
    SELECT '4. Target observations: 1994--2010 cohorts',
           * FROM tagged WHERE target = 1 AND target_year BETWEEN 1994 AND 2010
    UNION ALL
    SELECT '5. Target observations: deals retained in P2',
           * FROM tagged WHERE target = 1 AND p2_deal
    UNION ALL
    SELECT '6. Target observations: exact P2 inventor--deal overlap',
           * FROM tagged WHERE target = 1 AND exact_p2_unit
  )
  SELECT sample_label AS sample,
         COUNT(*)::INTEGER observations,
         COUNT(DISTINCT codinv)::INTEGER distinct_inventors,
         COUNT(DISTINCT deal_id)::INTEGER deals,
         AVG(productivity5) mean_annual_patents_pre5,
         AVG(group_patent) mean_group_patent,
         MEDIAN(group_patent) median_group_patent
  FROM samples
  GROUP BY sample_label ORDER BY sample_label
", p$treated, p$treated))
utils::write.csv(cassi_decomposition,
                 file.path(OUT, "audit_cassi_deviation_decomposition.csv"),
                 row.names = FALSE)

cassi_by_status <- DBI::dbGetQuery(con, "
  SELECT
    CASE
      WHEN type = 'T_STAYER' THEN 'Cassi target stayers'
      WHEN type = 'T_LEAVER' THEN 'Cassi target leavers'
    END sample_label,
    COUNT(*)::INTEGER observations,
    COUNT(DISTINCT codinv)::INTEGER distinct_inventors,
    AVG(productivity5) mean_annual_patents_pre5,
    AVG(group_patent) mean_group_patent
  FROM cassi_separation
  WHERE type IN ('T_STAYER', 'T_LEAVER')
  GROUP BY type ORDER BY type
")
names(cassi_by_status)[names(cassi_by_status) == "sample_label"] <- "sample"

thesis_by_status <- DBI::dbGetQuery(con, sprintf("
  WITH t AS (
    SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id,
           status_eligible, first_post_patent_year,
           status_eligible_stayer_first_post_t0_t5
    FROM read_parquet('%s')
  ), x AS (
    SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id,
           patent_count_5y / 5.0 AS productivity5
    FROM read_parquet('%s')
  ), u AS (
    SELECT t.*, x.productivity5,
      CASE
        WHEN status_eligible_stayer_first_post_t0_t5 THEN 'Thesis P2 stayers'
        WHEN status_eligible AND first_post_patent_year IS NOT NULL
          THEN 'Thesis P2 leavers'
        WHEN status_eligible AND first_post_patent_year IS NULL
          THEN 'Thesis P2 no post-deal patent'
        ELSE 'Thesis P2 not status-eligible'
      END sample_label
    FROM t JOIN x USING(codinv, deal_id)
  )
  SELECT sample_label, COUNT(*)::INTEGER observations,
         COUNT(DISTINCT codinv)::INTEGER distinct_inventors,
         AVG(productivity5) mean_annual_patents_pre5,
         NULL::DOUBLE mean_group_patent
  FROM u GROUP BY sample_label ORDER BY sample_label
", p$treated, p$inventor_covariates))
names(thesis_by_status)[names(thesis_by_status) == "sample_label"] <- "sample"
status_alignment <- rbind(cassi_by_status, thesis_by_status)
utils::write.csv(status_alignment,
                 file.path(OUT, "audit_cassi_status_productivity_alignment.csv"),
                 row.names = FALSE, na = "")

# Hold the inventor--deal sample fixed and change only the productivity clock.
# Cassi productivity is a rolling five-year measure ending at the status year;
# P3 productivity is fixed at the five years immediately preceding the deal.
same_unit_productivity <- DBI::dbGetQuery(con, sprintf("
  WITH x AS (
    SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id,
           patent_count_5y / 5.0 AS thesis_predeal_productivity
    FROM read_parquet('%s')
  ), exact AS (
    SELECT c.*, x.thesis_predeal_productivity
    FROM cassi_separation c
    JOIN x USING(codinv, deal_id)
    WHERE c.target = 1
  )
  SELECT
    CASE
      WHEN type = 'T_STAYER' THEN 'Same units: Cassi target stayers'
      WHEN type = 'T_LEAVER' THEN 'Same units: Cassi target leavers'
      ELSE 'Same units: all Cassi target statuses'
    END AS comparison,
    COUNT(*)::INTEGER n,
    AVG(productivity5) cassi_rolling_productivity,
    AVG(thesis_predeal_productivity) thesis_fixed_predeal_productivity,
    AVG(thesis_predeal_productivity) - AVG(productivity5) difference
  FROM exact
  GROUP BY GROUPING SETS ((type), ())
  HAVING type IN ('T_STAYER', 'T_LEAVER') OR type IS NULL
  ORDER BY comparison
", p$inventor_covariates))
utils::write.csv(same_unit_productivity,
                 file.path(OUT, "audit_same_unit_productivity_clock.csv"),
                 row.names = FALSE)

# Contrast observation-weighted Cassi group size with the deal-weighted P3
# target-group stock used in the thesis descriptive table.
firm_comparison <- DBI::dbGetQuery(con, sprintf("
  WITH f AS (
    SELECT patent_stock_5y
    FROM read_parquet('%s')
    WHERE role = 'treated'
  )
  SELECT 'Thesis P3: target deals, equal deal weight' AS sample_label,
         COUNT(*)::INTEGER n, AVG(patent_stock_5y) mean_group_patent,
         MEDIAN(patent_stock_5y) median_group_patent
  FROM f
", p$firm_covariates))
names(firm_comparison)[names(firm_comparison) == "sample_label"] <- "sample"
utils::write.csv(firm_comparison,
                 file.path(OUT, "audit_group_patent_definition_alignment.csv"),
                 row.names = FALSE)

# Show how much of the group-patent gap is caused by inventor-observation
# weighting rather than by a different patent count.
group_weighting <- DBI::dbGetQuery(con, sprintf("
  WITH p2_deals AS (
    SELECT DISTINCT CAST(deal_id AS BIGINT) deal_id
    FROM read_parquet('%s')
  ), target_rows AS (
    SELECT * FROM cassi_separation
    WHERE target = 1 AND deal_id IS NOT NULL
  ), deal_means AS (
    SELECT deal_id, AVG(group_patent) group_patent
    FROM target_rows GROUP BY deal_id
  ), p2_deal_means AS (
    SELECT d.deal_id, d.group_patent
    FROM deal_means d JOIN p2_deals p USING(deal_id)
  ), p3 AS (
    SELECT CAST(deal_id AS BIGINT) deal_id, patent_stock_5y
    FROM read_parquet('%s') WHERE role = 'treated'
  )
  SELECT 'Cassi target rows: inventor-observation weighted' AS weighting,
         COUNT(*)::INTEGER n, AVG(group_patent) mean_group_patent,
         MEDIAN(group_patent) median_group_patent
  FROM target_rows
  UNION ALL
  SELECT 'Cassi target rows: equal deal weight',
         COUNT(*)::INTEGER, AVG(group_patent), MEDIAN(group_patent)
  FROM deal_means
  UNION ALL
  SELECT 'Cassi rows on P2 deals: equal deal weight',
         COUNT(*)::INTEGER, AVG(group_patent), MEDIAN(group_patent)
  FROM p2_deal_means
  UNION ALL
  SELECT 'Thesis P3 target stock: same deals as Cassi overlap',
         COUNT(*)::INTEGER, AVG(p3.patent_stock_5y), MEDIAN(p3.patent_stock_5y)
  FROM p3 JOIN p2_deal_means d USING(deal_id)
  UNION ALL
  SELECT 'Thesis P3 target stock annualized: same overlap deals',
         COUNT(*)::INTEGER, AVG(p3.patent_stock_5y / 5.0),
         MEDIAN(p3.patent_stock_5y / 5.0)
  FROM p3 JOIN p2_deal_means d USING(deal_id)
  UNION ALL
  SELECT 'Thesis P3 target stock: all P2 deals',
         COUNT(*)::INTEGER, AVG(patent_stock_5y), MEDIAN(patent_stock_5y)
  FROM p3
", p$treated, p$firm_covariates))
utils::write.csv(group_weighting,
                 file.path(OUT, "audit_group_patent_weighting_decomposition.csv"),
                 row.names = FALSE)

# Hold deals, groups, and the g-5,...,g-1 window fixed. This isolates the
# supplied Cassi helper count from the repaired canonical distinct-application
# count used by P3.
group_count_convention <- DBI::dbGetQuery(con, sprintf("
  WITH p3 AS (
    SELECT cohort, CAST(deal_id AS BIGINT) deal_id, CAST(id_group AS BIGINT) id_group,
           patent_stock_5y AS thesis_distinct_applications_5y
    FROM read_parquet('%s') WHERE role = 'treated'
  ), helper AS (
    SELECT p3.deal_id,
           p3.thesis_distinct_applications_5y,
           SUM(gp.patent) AS cassi_helper_patents_5y
    FROM p3
    JOIN read_parquet('%s') gp
      ON CAST(gp.id_group AS BIGINT) = p3.id_group
     AND CAST(gp.year AS INTEGER) BETWEEN p3.cohort - 5 AND p3.cohort - 1
    GROUP BY p3.deal_id, p3.thesis_distinct_applications_5y
  )
  SELECT COUNT(*)::INTEGER deals,
         AVG(cassi_helper_patents_5y) mean_cassi_helper_5y,
         AVG(thesis_distinct_applications_5y) mean_thesis_distinct_apps_5y,
         AVG(thesis_distinct_applications_5y - cassi_helper_patents_5y)
           mean_difference,
         CORR(cassi_helper_patents_5y, thesis_distinct_applications_5y)
           deal_level_correlation
  FROM helper
", p$firm_covariates, p$group_production))
utils::write.csv(group_count_convention,
                 file.path(OUT, "audit_group_patent_count_convention.csv"),
                 row.names = FALSE)

message("Cassi--Ornaghi alignment audit complete.")
