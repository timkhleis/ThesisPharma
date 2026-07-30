# Package N4: construct exploratory retained-inventor team measures.

if (!exists("lmv2_n4_config")) {
  source(file.path(
    "02_analysis", "R", "47a_lmv2_n4_team_config.R"
  ))
}

lmv2_n4_build <- function(config = lmv2_n4_config()) {
  source(file.path(config$base, "02_analysis", "R", "00_utils.R"))
  use_project_library()
  shared_lib <- file.path(
    normalizePath(
      file.path(config$base, "..", ".."),
      winslash = "/", mustWork = TRUE
    ),
    ".r_libs"
  )
  if (dir.exists(shared_lib)) {
    .libPaths(unique(c(shared_lib, .libPaths())))
  }
  for (pkg in c("DBI", "duckdb", "digest")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Missing package: ", pkg, call. = FALSE)
    }
  }
  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(config$results_dir, recursive = TRUE, showWarnings = FALSE)

  build_started <- Sys.time()
  freeze_info <- file.info(config$freeze_file)
  freeze_hash <- digest::digest(
    file = config$freeze_file, algo = "sha256", serialize = FALSE
  )
  if (is.na(freeze_info$mtime) || freeze_info$mtime >= build_started) {
    stop("N4 freeze must predate outcome construction.", call. = FALSE)
  }
  attestation <- data.frame(
    package = "N4_TEAM_RECOMPOSITION",
    freeze_sha256 = freeze_hash,
    freeze_modified_utc = format(
      freeze_info$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    ),
    construction_started_utc = format(
      build_started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    ),
    post_outcomes_opened_only_after_freeze = TRUE,
    stringsAsFactors = FALSE
  )
  lmv2_n4_write_csv(
    attestation,
    file.path(config$output_dir, "n4_freeze_attestation.csv")
  )

  con <- DBI::dbConnect(
    duckdb::duckdb(config$foundation_db, read_only = TRUE)
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "PRAGMA threads=8")
  DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")

  weights_sql <- lmv2_n4_sql_string(config$retained_weights)
  status_sql <- lmv2_n4_sql_string(config$status_partition)
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE n4_roster AS
    SELECT
      CAST(w.cohort AS INTEGER) AS cohort,
      CAST(w.deal_id AS BIGINT) AS deal_id,
      CAST(w.codinv AS BIGINT) AS focal_codinv,
      CAST(w.final_weight AS DOUBLE) AS weight,
      CAST(s.focal_group_1 AS BIGINT) AS focal_group_1,
      CAST(s.focal_group_2 AS BIGINT) AS focal_group_2
    FROM read_parquet(%s) w
    JOIN read_parquet(%s) s
      ON CAST(w.cohort AS INTEGER) = CAST(s.cohort AS INTEGER)
     AND CAST(w.deal_id AS BIGINT) = CAST(s.deal_id AS BIGINT)
     AND CAST(w.codinv AS BIGINT) = CAST(s.codinv AS BIGINT)
    WHERE w.treated = 1
      AND w.spec = 'primary_count_active_scale'
      AND w.support_variant = 'primary_resolved_t1'
      AND s.is_primary
      AND s.retention_status = 'initially_retained'
  ", weights_sql, status_sql))

  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_focal_apps AS
    SELECT DISTINCT
      r.cohort, r.deal_id, r.focal_codinv, r.weight,
      r.focal_group_1, r.focal_group_2,
      CAST(p.appln_id AS BIGINT) AS appln_id,
      CAST(p.year AS INTEGER) AS year,
      CAST(p.year AS INTEGER) - r.cohort AS event_time
    FROM n4_roster r
    JOIN patent_inventor_enriched p
      ON CAST(p.codinv AS BIGINT) = r.focal_codinv
     AND CAST(p.year AS INTEGER) BETWEEN r.cohort - 5 AND r.cohort + 5
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_dyad_apps AS
    SELECT DISTINCT
      f.cohort, f.deal_id, f.focal_codinv, f.weight,
      f.focal_group_1, f.focal_group_2,
      f.appln_id, f.year, f.event_time,
      CAST(p.codinv AS BIGINT) AS partner_codinv
    FROM n4_focal_apps f
    JOIN patent_inventor_enriched p
      ON CAST(p.appln_id AS BIGINT) = f.appln_id
     AND CAST(p.year AS INTEGER) = f.year
     AND CAST(p.codinv AS BIGINT) <> f.focal_codinv
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_dyad_app_flags AS
    SELECT
      d.*,
      COUNT(pcl.id_group) > 0 AS has_resolved_group,
      COALESCE(
        BOOL_OR(
          CAST(pcl.id_group AS BIGINT) IN (
            d.focal_group_1, d.focal_group_2
          )
        ) FILTER (WHERE pcl.id_group IS NOT NULL),
        FALSE
      ) AS has_focal_group,
      COALESCE(
        BOOL_OR(
          CAST(pcl.id_group AS BIGINT) NOT IN (
            d.focal_group_1, d.focal_group_2
          )
        ) FILTER (WHERE pcl.id_group IS NOT NULL),
        FALSE
      ) AS has_outside_group
    FROM n4_dyad_apps d
    LEFT JOIN patent_company_link pcl
      ON CAST(pcl.appln_id AS BIGINT) = d.appln_id
     AND CAST(pcl.year AS INTEGER) = d.year
    GROUP BY ALL
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_partners AS
    SELECT DISTINCT
      cohort, deal_id, focal_codinv, focal_group_1, focal_group_2,
      partner_codinv
    FROM n4_dyad_apps
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_partner_pre_flags AS
    SELECT
      x.cohort, x.deal_id, x.focal_codinv, x.partner_codinv,
      COALESCE(
        BOOL_OR(
          CAST(pcl.id_group AS BIGINT) = x.focal_group_1
        ) FILTER (WHERE pcl.id_group IS NOT NULL),
        FALSE
      ) AS legacy_target,
      COALESCE(
        BOOL_OR(
          CAST(pcl.id_group AS BIGINT) = x.focal_group_2
        ) FILTER (WHERE pcl.id_group IS NOT NULL),
        FALSE
      ) AS legacy_acquirer
    FROM n4_partners x
    LEFT JOIN patent_inventor_enriched p
      ON CAST(p.codinv AS BIGINT) = x.partner_codinv
     AND CAST(p.year AS INTEGER) BETWEEN x.cohort - 5 AND x.cohort - 1
    LEFT JOIN patent_company_link pcl
      ON CAST(pcl.appln_id AS BIGINT) = CAST(p.appln_id AS BIGINT)
     AND CAST(pcl.year AS INTEGER) = CAST(p.year AS INTEGER)
    GROUP BY ALL
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_post_appearances AS
    WITH annual AS (
      SELECT
        d.cohort, d.deal_id, d.focal_codinv, d.weight,
        d.partner_codinv, d.event_time,
        BOOL_OR(d.has_resolved_group) AS composition_defined,
        BOOL_OR(d.has_focal_group) AS has_focal_joint_patent,
        BOOL_OR(d.has_outside_group) AS has_outside_joint_patent,
        COUNT(DISTINCT d.appln_id) AS joint_applications,
        MAX(CAST(p.legacy_target AS INTEGER)) = 1 AS legacy_target,
        MAX(CAST(p.legacy_acquirer AS INTEGER)) = 1 AS legacy_acquirer
      FROM n4_dyad_app_flags d
      LEFT JOIN n4_partner_pre_flags p
        USING (cohort, deal_id, focal_codinv, partner_codinv)
      WHERE d.event_time BETWEEN 1 AND 5
      GROUP BY ALL
    )
    SELECT
      *,
      has_focal_joint_patent AND has_outside_joint_patent
        AS mixed_focal_outside,
      CASE
        WHEN NOT composition_defined THEN NULL
        WHEN NOT has_focal_joint_patent THEN 'outside_group'
        WHEN legacy_target THEN 'legacy_target'
        WHEN legacy_acquirer THEN 'legacy_acquirer'
        ELSE 'new_to_both'
      END AS collaborator_category
    FROM annual
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_anchor_ties AS
    SELECT
      cohort, deal_id, focal_codinv, weight, partner_codinv,
      COUNT(DISTINCT appln_id) AS anchor_joint_applications,
      COUNT(DISTINCT year) AS anchor_joint_years,
      COUNT(DISTINCT appln_id) >= 1 AS weak_tie,
      COUNT(DISTINCT appln_id) >= 2
        AND COUNT(DISTINCT year) >= 2 AS strict_tie
    FROM n4_dyad_apps
    WHERE event_time BETWEEN -5 AND -3
    GROUP BY ALL
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_tie_recurrence AS
    SELECT
      a.cohort, a.deal_id, a.focal_codinv, a.weight,
      a.partner_codinv, a.weak_tie, a.strict_tie,
      h.horizon,
      EXISTS (
        SELECT 1
        FROM n4_post_appearances p
        WHERE p.cohort = a.cohort
          AND p.deal_id = a.deal_id
          AND p.focal_codinv = a.focal_codinv
          AND p.partner_codinv = a.partner_codinv
          AND p.event_time BETWEEN 1 AND h.horizon
      ) AS recurred_by_horizon
    FROM n4_anchor_ties a
    CROSS JOIN range(1, 6) h(horizon)
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE n4_focal_years AS
    WITH patenting AS (
      SELECT
        cohort, deal_id, focal_codinv, weight, event_time,
        COUNT(DISTINCT appln_id) AS patent_applications
      FROM n4_focal_apps
      WHERE event_time BETWEEN 1 AND 5
      GROUP BY ALL
    ),
    teams AS (
      SELECT
        cohort, deal_id, focal_codinv, event_time,
        COUNT(*) AS collaborators,
        COUNT(*) FILTER (WHERE composition_defined)
          AS defined_collaborators
      FROM n4_post_appearances
      GROUP BY ALL
    )
    SELECT
      r.cohort, r.deal_id, r.focal_codinv, r.weight,
      h.event_time,
      COALESCE(p.patent_applications, 0) AS patent_applications,
      COALESCE(t.collaborators, 0) AS collaborators,
      COALESCE(t.defined_collaborators, 0) AS defined_collaborators,
      COALESCE(p.patent_applications, 0) > 0 AS patent_active,
      COALESCE(t.collaborators, 0) > 0 AS has_collaborator,
      COALESCE(p.patent_applications, 0) > 0
        AND COALESCE(t.collaborators, 0) = 0 AS solo_only
    FROM n4_roster r
    CROSS JOIN range(1, 6) h(event_time)
    LEFT JOIN patenting p
      USING (cohort, deal_id, focal_codinv, weight, event_time)
    LEFT JOIN teams t
      USING (cohort, deal_id, focal_codinv, event_time)
  ")

  parquet_tables <- c(
    n4_roster = "n4_roster",
    post_collaborator_appearances = "n4_post_appearances",
    baseline_ties = "n4_anchor_ties",
    tie_recurrence = "n4_tie_recurrence",
    focal_year_team_denominators = "n4_focal_years"
  )
  for (nm in names(parquet_tables)) {
    out <- file.path(config$output_dir, paste0(nm, ".parquet"))
    DBI::dbExecute(con, sprintf(
      "COPY (SELECT * FROM %s) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
      parquet_tables[[nm]], lmv2_n4_sql_string(out)
    ))
  }

  construction <- DBI::dbGetQuery(con, "
    SELECT
      (SELECT COUNT(*) FROM n4_roster) AS roster_rows,
      (SELECT COUNT(DISTINCT focal_codinv) FROM n4_roster)
        AS roster_inventors,
      (SELECT COUNT(DISTINCT deal_id) FROM n4_roster) AS roster_deals,
      (SELECT COUNT(*) FROM n4_dyad_apps) AS dyad_application_rows,
      (SELECT COUNT(*) FROM n4_post_appearances)
        AS post_appearance_rows,
      (SELECT COUNT(*) FROM n4_post_appearances
       WHERE NOT composition_defined) AS unresolved_post_appearances,
      (SELECT COUNT(*) FROM n4_post_appearances
       WHERE composition_defined AND collaborator_category IS NULL)
        AS defined_rows_without_category,
      (SELECT COUNT(*) FROM n4_post_appearances
       WHERE mixed_focal_outside) AS mixed_post_appearances,
      (SELECT COUNT(*) FROM n4_anchor_ties WHERE weak_tie)
        AS weak_anchor_dyads,
      (SELECT COUNT(*) FROM n4_anchor_ties WHERE strict_tie)
        AS strict_anchor_dyads,
      (SELECT COUNT(*) FROM n4_focal_years) AS focal_year_rows,
      (SELECT COUNT(*) FROM n4_roster) * 5 AS expected_focal_year_rows
  ")
  construction$pass <- with(
    construction,
    roster_rows == roster_inventors &
      roster_inventors == 2663L &
      roster_deals == 151L &
      defined_rows_without_category == 0L &
      weak_anchor_dyads >= strict_anchor_dyads &
      focal_year_rows == expected_focal_year_rows
  )
  lmv2_n4_write_csv(
    construction,
    file.path(config$output_dir, "n4_construction_audit.csv")
  )
  if (!isTRUE(construction$pass[[1L]])) {
    stop("N4 construction audit failed.", call. = FALSE)
  }
  invisible(construction)
}

if (sys.nframe() == 0L) {
  lmv2_n4_build()
  message("N4 team-recomposition construction complete.")
}
