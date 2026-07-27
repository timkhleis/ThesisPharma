# ============================================================================
# 18b_build_lmv2_outcome_ingredients.R -- P6 roster-independent ingredients
# ============================================================================
# Function library only; nothing executes at source time. All tables are
# written into an isolated build schema supplied by the runner (double-build
# isolation). Ingredients are restricted to relevant inventors (union of
# treated and control-eligible codinv) and never expand the control universe
# across event years.

# Build every P6 ingredient table into `schema`. `con` must already hold the
# validated frozen database (18e provenance gate runs first).
build_lmv2_outcome_ingredients <- function(con, schema) {
  DBI::dbExecute(con, sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
  s <- function(tbl) sprintf("%s.%s", schema, tbl)

  # -- relevant inventors ----------------------------------------------------
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT DISTINCT codinv FROM (
      SELECT CAST(codinv AS BIGINT) AS codinv FROM lmv2_treated_primary
      UNION
      SELECT CAST(codinv AS BIGINT) AS codinv
      FROM lmv2_control_inventor_eligibility
    )", s("lmv2_relevant_inventors")))

  # -- inventor-by-calendar-year outcomes (sparse patent years) --------------
  # Base counts come from the certified P1 inventor_year; OECD aggregates are
  # recomputed from the distinct inventor-application spine. Certification
  # test 2 re-derives the counts directly from the spine.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    WITH pairs AS (
      SELECT DISTINCT CAST(pi.codinv AS BIGINT) AS codinv, pi.appln_id
      FROM patent_inventor pi
      JOIN %s r ON r.codinv = CAST(pi.codinv AS BIGINT)
    ),
    oecd AS (
      SELECT
        p.codinv,
        pa.patent_year AS year,
        COUNT(oq.appln_id) AS n_linked_oecd,
        COUNT(oq.fwd_cits5) AS n_fwd_nonmiss,
        SUM(oq.fwd_cits5) AS sum_fwd_cits5_obs,
        COUNT(oq.quality_index_4) AS n_pqii_nonmiss,
        -- Aggregate deterministically: parallel floating-point SUM order can
        -- differ at ~1e-15. Round each source value to 12 decimals, sum exact
        -- integers, then restore the scale.
        CAST(
          SUM(CAST(ROUND(oq.quality_index_4 * 1000000000000) AS HUGEINT))
          AS DOUBLE
        ) / 1000000000000 AS sum_pqii_obs
      FROM pairs p
      JOIN patent_application pa USING (appln_id)
      LEFT JOIN oecd_quality oq USING (appln_id)
      GROUP BY p.codinv, pa.patent_year
    )
    SELECT
      CAST(iy.codinv AS BIGINT) AS codinv,
      iy.year,
      iy.patent_count,
      iy.fractional_patent_count,
      COALESCE(o.n_linked_oecd, 0) AS n_linked_oecd,
      COALESCE(o.n_fwd_nonmiss, 0) AS n_fwd_nonmiss,
      o.sum_fwd_cits5_obs,
      COALESCE(o.n_pqii_nonmiss, 0) AS n_pqii_nonmiss,
      o.sum_pqii_obs
    FROM inventor_year iy
    JOIN %s r ON r.codinv = CAST(iy.codinv AS BIGINT)
    LEFT JOIN oecd o
      ON o.codinv = CAST(iy.codinv AS BIGINT) AND o.year = iy.year",
    s("lmv2_outcome_inventor_year"),
    s("lmv2_relevant_inventors"), s("lmv2_relevant_inventors")))

  # -- resolved affiliations: sole source for stayer group-path status -------
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      CAST(ia.codinv AS BIGINT) AS codinv,
      ia.year,
      CAST(ia.resolved_group AS BIGINT) AS resolved_group,
      ia.candidate_group_count
    FROM inventor_affiliation_own ia
    JOIN %s r ON r.codinv = CAST(ia.codinv AS BIGINT)",
    s("lmv2_outcome_inventor_affiliation_year"), s("lmv2_relevant_inventors")))

  # -- patent-level group links: sole source for absorbing Left --------------
  # pcl.year is used for focal evidence exactly as in the P2 stayer company
  # path; the application clock is untouched.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      CAST(pi.codinv AS BIGINT) AS codinv,
      pcl.year,
      CAST(pcl.id_group AS BIGINT) AS id_group,
      COUNT(DISTINCT pcl.appln_id) AS n_patents
    FROM patent_inventor pi
    JOIN %s r ON r.codinv = CAST(pi.codinv AS BIGINT)
    JOIN patent_company_link pcl ON pcl.appln_id = pi.appln_id
    WHERE pcl.id_group IS NOT NULL
    GROUP BY 1, 2, 3",
    s("lmv2_inventor_group_patent_year"), s("lmv2_relevant_inventors")))

  # -- deal-specific target-company links (treated Left/stayer company path) -
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      CAST(pi.codinv AS BIGINT) AS codinv,
      dtc.deal_id,
      pcl.year,
      COUNT(DISTINCT pcl.appln_id) AS n_patents
    FROM deal_target_company_strict dtc
    JOIN patent_company_link pcl
      ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
    JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
    JOIN %s r ON r.codinv = CAST(pi.codinv AS BIGINT)
    GROUP BY 1, 2, 3",
    s("lmv2_inventor_target_company_patent_year"), s("lmv2_relevant_inventors")))

  # -- sparse IPC4 vectors for TechDrift (integer patent-count weights) ------
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      CAST(iiy.codinv AS BIGINT) AS codinv,
      iiy.year,
      SUBSTR(iiy.ipc_code, 1, 4) AS ipc4,
      SUM(iiy.patent_count) AS weight
    FROM inventor_ipc_year iiy
    JOIN %s r ON r.codinv = CAST(iiy.codinv AS BIGINT)
    WHERE iiy.ipc_code IS NOT NULL
    GROUP BY 1, 2, 3",
    s("lmv2_inventor_ipc4_year"), s("lmv2_relevant_inventors")))

  build_lmv2_oecd_audits(con, schema)
  invisible(schema)
}

# ---------------------------------------------------------------------------
# OECD coverage audits (three separate grains) plus the mandatory
# linkage-decline decomposition. Strictly diagnostic: no keys are adopted,
# no records dropped or recovered, no design choice changes here.
# ---------------------------------------------------------------------------
build_lmv2_oecd_audits <- function(con, schema) {
  s <- function(tbl) sprintf("%s.%s", schema, tbl)

  # Coverage at application-year grain (full patent layer).
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      pa.patent_year AS application_year,
      COUNT(*) AS n_patents,
      COUNT(oq.appln_id) AS n_linked,
      COUNT(oq.fwd_cits5) AS n_fwd_nonmiss,
      COUNT(oq.quality_index_4) AS n_pqii_nonmiss
    FROM patent_application pa
    LEFT JOIN oecd_quality oq USING (appln_id)
    GROUP BY 1", s("lmv2_oecd_coverage_appyear")))

  # Coverage at filing-year grain (linked records only; `filing` is OECD-side
  # metadata and never re-times any outcome).
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      oq.filing AS filing_year,
      COUNT(*) AS n_linked,
      COUNT(oq.fwd_cits5) AS n_fwd_nonmiss,
      COUNT(oq.quality_index_4) AS n_pqii_nonmiss
    FROM patent_application pa
    JOIN oecd_quality oq USING (appln_id)
    GROUP BY 1", s("lmv2_oecd_coverage_filingyear")))

  # Filing-minus-application delta histogram.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      pa.patent_year AS application_year,
      oq.filing - pa.patent_year AS filing_minus_application_year,
      COUNT(*) AS n_patents
    FROM patent_application pa
    JOIN oecd_quality oq USING (appln_id)
    GROUP BY 1, 2", s("lmv2_oecd_filing_delta")))

  # Linkage-decline decomposition, application-year grain: patent-layer tail,
  # linkage failure, identifier availability, composition of matched versus
  # unmatched patents from characteristics available in the thesis layer.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    WITH chars AS (
      SELECT
        pa.appln_id,
        pa.patent_year,
        (oq.appln_id IS NOT NULL) AS linked,
        (pa.appln_id IS NULL OR pa.appln_id <= 0) AS bad_identifier,
        COALESCE(pi.n_inventors, 0) AS n_inventors,
        COALESCE(pcl.n_links, 0) AS n_company_links,
        COALESCE(pcl.n_groups, 0) AS n_groups
      FROM patent_application pa
      LEFT JOIN oecd_quality oq USING (appln_id)
      LEFT JOIN (
        SELECT appln_id, COUNT(DISTINCT codinv) AS n_inventors
        FROM patent_inventor GROUP BY appln_id
      ) pi USING (appln_id)
      LEFT JOIN (
        SELECT appln_id, COUNT(*) AS n_links,
               COUNT(DISTINCT id_group) AS n_groups
        FROM patent_company_link GROUP BY appln_id
      ) pcl USING (appln_id)
    )
    SELECT
      patent_year AS application_year,
      linked,
      COUNT(*) AS n_patents,
      SUM(bad_identifier::INT) AS n_bad_identifier,
      AVG(n_inventors) AS mean_inventors,
      AVG((n_company_links > 0)::INT) AS share_with_company_link,
      AVG((n_groups > 0)::INT) AS share_with_id_group
    FROM chars
    GROUP BY 1, 2", s("lmv2_oecd_linkage_decline_appyear")))

  # Linked-side view by filing year: OECD-field missingness among matched
  # records, plus authority composition from the OECD application number
  # prefix (available for linked records only; unlinked-side authority is not
  # available in the thesis patent layer and is documented as such).
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      oq.filing AS filing_year,
      SUBSTR(oq.app_nbr, 1, 2) AS authority_prefix,
      COUNT(*) AS n_linked,
      COUNT(oq.fwd_cits5) AS n_fwd_nonmiss,
      COUNT(oq.quality_index_4) AS n_pqii_nonmiss
    FROM patent_application pa
    JOIN oecd_quality oq USING (appln_id)
    GROUP BY 1, 2", s("lmv2_oecd_linkage_decline_filingyear")))

  invisible(schema)
}
