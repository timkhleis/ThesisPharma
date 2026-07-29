# Package D1: build predetermined status descriptors and annual patent paths.

if (!exists("lmv2_d1_config")) {
  source(file.path(
    "02_analysis", "R", "42a_lmv2_stayer_descriptives_config.R"
  ))
}

lmv2_d1_build_status_paths <- function(config = lmv2_d1_config()) {
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
  for (pkg in c("DBI", "duckdb")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Missing package: ", pkg, call. = FALSE)
    }
  }
  required <- c(
    config$foundation_db,
    config$status_partition,
    config$status_certification,
    config$p8_endpoints,
    config$p8_certification,
    config$retained_weights,
    config$retained_weights_certification,
    config$freeze_file
  )
  if (any(!file.exists(required))) {
    stop(
      "Missing D1 input(s): ",
      paste(required[!file.exists(required)], collapse = ", "),
      call. = FALSE
    )
  }
  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
  output_names <- c(
    "status_predeal_metrics.parquet",
    "d1_global_career_endpoints.parquet",
    "annual_status_paths.parquet",
    "annual_status_transition.csv",
    "persistent_inside.csv",
    "endpoint_activity_rows.parquet",
    "endpoint_activity_summary.csv",
    "status_path_construction_audit.csv"
  )
  output_paths <- file.path(config$output_dir, output_names)
  unlink(output_paths[file.exists(output_paths)], force = TRUE)

  con <- DBI::dbConnect(
    duckdb::duckdb(
      dbdir = config$foundation_db,
      read_only = TRUE
    )
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "PRAGMA threads=8")
  DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")

  status_sql <- lmv2_d1_sql_string(config$status_partition)
  endpoint_sql <- lmv2_d1_sql_string(config$p8_endpoints)
  weights_sql <- lmv2_d1_sql_string(config$retained_weights)
  statuses <- paste(
    vapply(config$status_groups, lmv2_d1_sql_string, character(1)),
    collapse = ","
  )

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE d1_status_base AS
    SELECT
      CAST(cohort AS INTEGER) AS cohort,
      CAST(deal_id AS BIGINT) AS deal_id,
      CAST(codinv AS BIGINT) AS codinv,
      CAST(focal_group_1 AS BIGINT) AS focal_group_1,
      CAST(focal_group_2 AS BIGINT) AS focal_group_2,
      CAST(first_post_year AS INTEGER) AS first_post_year,
      CAST(first_event_time AS INTEGER) AS first_event_time,
      CAST(last_event_time AS INTEGER) AS last_event_time,
      retention_status
    FROM read_parquet(%s)
    WHERE is_primary
      AND retention_status IN (%s)
  ", status_sql, statuses))

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE d1_endpoints AS
    WITH endpoint AS (
      SELECT
        CAST(iy.codinv AS BIGINT) AS codinv,
        MIN(CAST(iy.career_first_year AS INTEGER)) AS career_first_year,
        MAX(CAST(iy.year AS INTEGER)) FILTER (
          WHERE iy.patent_count > 0
            AND iy.year <= %d
        ) AS global_last_patent_year
      FROM inventor_year iy
      JOIN (
        SELECT DISTINCT codinv FROM d1_status_base
      ) b
        ON b.codinv = CAST(iy.codinv AS BIGINT)
      GROUP BY 1
    )
    SELECT
      e.*,
      CAST(p.global_last_patent_year AS INTEGER)
        AS p8_global_last_patent_year,
      (
        p.codinv IS NOT NULL
        AND e.global_last_patent_year = p.global_last_patent_year
      ) AS p8_endpoint_matches
    FROM endpoint e
    LEFT JOIN read_parquet(%s) p USING (codinv)
  ", config$observation_end_year, endpoint_sql))

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE d1_predeal_metrics AS
    WITH patent_stock AS (
      SELECT
        b.codinv,
        SUM(COALESCE(iy.patent_count, 0)) AS patent_stock_5y,
        MAX(CASE
          WHEN iy.patent_count > 0 THEN iy.year
          ELSE NULL
        END) AS latest_patent_year_used
      FROM d1_status_base b
      LEFT JOIN inventor_year iy
        ON CAST(iy.codinv AS BIGINT) = b.codinv
       AND iy.year BETWEEN b.cohort - 5 AND b.cohort - 1
      GROUP BY 1
    )
    SELECT
      b.*,
      e.career_first_year,
      (b.cohort - 1 - e.career_first_year) AS career_age_t_minus_1,
      COALESCE(p.patent_stock_5y, 0) AS patent_stock_5y,
      p.latest_patent_year_used,
      e.global_last_patent_year,
      e.p8_global_last_patent_year,
      e.p8_endpoint_matches
    FROM d1_status_base b
    JOIN d1_endpoints e USING (codinv)
    LEFT JOIN patent_stock p USING (codinv)
  "))

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE d1_event_grid AS
    SELECT
      b.*,
      r.event_time,
      b.cohort + r.event_time AS calendar_year,
      b.first_post_year - b.cohort AS first_post_event_time,
      e.global_last_patent_year
    FROM d1_status_base b
    JOIN d1_endpoints e USING (codinv)
    CROSS JOIN range(1, 6) r(event_time)
    WHERE b.retention_status = 'initially_retained'
  "))

  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_patents AS
    SELECT DISTINCT
      CAST(codinv AS BIGINT) AS codinv,
      CAST(appln_id AS BIGINT) AS appln_id,
      CAST(year AS INTEGER) AS year
    FROM patent_inventor_enriched
  ")

  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_location_evidence AS
    SELECT
      g.deal_id,
      g.codinv,
      g.event_time,
      COUNT(DISTINCT p.appln_id) AS patent_count,
      COALESCE(MAX(CASE
        WHEN CAST(pcl.id_group AS BIGINT) IN (
          g.focal_group_1, g.focal_group_2
        )
          OR dtc.target_compcod IS NOT NULL
        THEN 1 ELSE 0
      END), 0) AS focal_evidence,
      COALESCE(MAX(CASE
        WHEN pcl.id_group IS NOT NULL
          AND CAST(pcl.id_group AS BIGINT) NOT IN (
            g.focal_group_1, g.focal_group_2
          )
          AND dtc.target_compcod IS NULL
        THEN 1 ELSE 0
      END), 0) AS outside_evidence
    FROM d1_event_grid g
    LEFT JOIN d1_patents p
      ON p.codinv = g.codinv
     AND p.year = g.calendar_year
    LEFT JOIN patent_company_link pcl
      ON CAST(pcl.appln_id AS BIGINT) = p.appln_id
    LEFT JOIN deal_target_company_strict dtc
      ON CAST(dtc.deal_id AS BIGINT) = g.deal_id
     AND CAST(dtc.target_compcod AS BIGINT) =
       CAST(pcl.compcod AS BIGINT)
    GROUP BY 1, 2, 3
  ")

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE d1_status_paths AS
    SELECT
      g.*,
      l.patent_count,
      (l.focal_evidence = 1) AS focal_evidence,
      (l.outside_evidence = 1) AS outside_evidence,
      (
        l.patent_count > 0
        AND l.focal_evidence = 0
        AND l.outside_evidence = 0
      ) AS unresolved_patent_location,
      CASE
        WHEN g.calendar_year > %d
          THEN 'right_censored_not_observable'
        WHEN l.patent_count > 0
          AND l.focal_evidence = 1
          AND l.outside_evidence = 1
          THEN 'both_focal_and_outside'
        WHEN l.patent_count > 0
          AND l.focal_evidence = 1
          THEN 'focal_group_only'
        WHEN l.patent_count > 0
          THEN 'outside_group_only'
        WHEN g.global_last_patent_year > g.calendar_year
          THEN 'no_patent_later_patent_exists'
        WHEN g.calendar_year >= %d
          THEN 'right_censored_not_observable'
        ELSE 'end_of_observed_patenting'
      END AS annual_state
    FROM d1_event_grid g
    JOIN d1_location_evidence l
      ON l.deal_id = g.deal_id
     AND l.codinv = g.codinv
     AND l.event_time = g.event_time
  ", config$observation_end_year, config$observation_end_year))

  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_transition_summary AS
    SELECT
      event_time,
      annual_state,
      COUNT(*) AS inventor_rows,
      COUNT(DISTINCT codinv) AS inventors,
      COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (
        PARTITION BY event_time
      ) AS share
    FROM d1_status_paths
    GROUP BY 1, 2
    ORDER BY 1, 2
  ")

  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_persistence AS
    WITH horizons AS (
      SELECT * FROM (VALUES (3), (5)) AS h(horizon)
    ),
    inventor_horizon AS (
      SELECT
        p.deal_id,
        p.codinv,
        h.horizon,
        MIN(p.first_post_event_time) AS first_post_event_time,
        MAX(CASE
          WHEN p.event_time = h.horizon
            AND p.annual_state IN (
              'focal_group_only', 'both_focal_and_outside'
            )
          THEN 1 ELSE 0
        END) AS focal_evidence_at_horizon,
        MAX(CASE
          WHEN p.event_time BETWEEN p.first_post_event_time AND h.horizon
            AND p.annual_state = 'outside_group_only'
          THEN 1 ELSE 0
        END) AS any_outside_only_through_horizon,
        MIN(CASE
          WHEN p.event_time <= h.horizon
            AND p.annual_state IN (
              'focal_group_only', 'both_focal_and_outside'
            )
          THEN 1 ELSE 0
        END) AS focal_evidence_every_year
      FROM d1_status_paths p
      CROSS JOIN horizons h
      WHERE p.event_time <= h.horizon
      GROUP BY 1, 2, 3
    )
    SELECT
      *,
      (
        first_post_event_time <= horizon
        AND focal_evidence_at_horizon = 1
        AND any_outside_only_through_horizon = 0
      ) AS persistent_inside,
      (focal_evidence_every_year = 1) AS uninterrupted_annual_focal
    FROM inventor_horizon
  ")

  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_persistence_summary AS
    SELECT
      horizon,
      COUNT(*) AS initially_retained_inventors,
      SUM((first_post_event_time <= horizon)::INTEGER)
        AS first_post_observed_by_horizon,
      SUM(persistent_inside::INTEGER) AS persistent_inside_inventors,
      AVG(persistent_inside::INTEGER) AS persistent_inside_share_all,
      AVG(persistent_inside::INTEGER) FILTER (
        WHERE first_post_event_time <= horizon
      ) AS persistent_inside_share_first_post_observed,
      SUM(uninterrupted_annual_focal::INTEGER)
        AS uninterrupted_annual_focal_inventors,
      AVG(uninterrupted_annual_focal::INTEGER)
        AS uninterrupted_annual_focal_share
    FROM d1_persistence
    GROUP BY 1
    ORDER BY 1
  ")

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE d1_group_activity AS
    SELECT
      CAST(id_group AS BIGINT) AS id_group,
      CAST(year AS INTEGER) AS year,
      MAX(COALESCE(helper_group_patent, 0)) AS group_patent_count,
      (MAX(COALESCE(helper_group_patent, 0)) > 0)
        AS group_patent_active
    FROM group_year_status
    GROUP BY 1, 2
  "))
  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_group_endpoint AS
    SELECT
      CAST(id_group AS BIGINT) AS id_group,
      MAX(CAST(year AS INTEGER)) FILTER (
        WHERE COALESCE(helper_group_patent, 0) > 0
      ) AS group_last_patent_year
    FROM group_year_status
    GROUP BY 1
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_target_company_activity AS
    SELECT
      CAST(dtc.deal_id AS BIGINT) AS deal_id,
      CAST(pcl.year AS INTEGER) AS year,
      COUNT(DISTINCT CAST(pcl.appln_id AS BIGINT))
        AS target_company_patent_count
    FROM deal_target_company_strict dtc
    JOIN patent_company_link pcl
      ON CAST(pcl.compcod AS BIGINT) =
        CAST(dtc.target_compcod AS BIGINT)
    GROUP BY 1, 2
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_treated_endpoint AS
    SELECT
      b.deal_id,
      GREATEST(
        COALESCE(
          (
            SELECT MAX(g.group_last_patent_year)
            FROM d1_group_endpoint g
            WHERE g.id_group IN (
              b.focal_group_1, b.focal_group_2
            )
          ),
          -9999
        ),
        COALESCE(
          (
            SELECT MAX(t.year)
            FROM d1_target_company_activity t
            WHERE t.deal_id = b.deal_id
          ),
          -9999
        )
      ) AS treated_focal_last_patent_year
    FROM (
      SELECT DISTINCT
        deal_id, focal_group_1, focal_group_2
      FROM d1_status_base
    ) b
  ")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_control_endpoint AS
    SELECT
      CAST(cohort AS INTEGER) AS cohort,
      CAST(codinv AS BIGINT) AS codinv,
      CAST(control_group AS BIGINT) AS control_group,
      MAX(CAST(last_patent_year AS INTEGER))
        AS control_group_last_patent_year
    FROM lmv2_control_inventor_eligibility
    GROUP BY 1, 2, 3
  ")

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE d1_retained_design AS
    WITH weights AS (
      SELECT *
      FROM read_parquet(%s)
      WHERE spec = %s
        AND support_variant = %s
    ),
    treated AS (
      SELECT
        w.cohort,
        w.deal_id,
        w.codinv,
        'treated' AS arm,
        w.final_weight,
        b.focal_group_1,
        b.focal_group_2,
        NULL::BIGINT AS control_group,
        e.treated_focal_last_patent_year,
        NULL::INTEGER AS control_group_last_patent_year
      FROM weights w
      JOIN d1_status_base b
        ON b.deal_id = w.deal_id
       AND b.codinv = w.codinv
       AND b.retention_status = 'initially_retained'
      JOIN d1_treated_endpoint e
        ON e.deal_id = CAST(w.deal_id AS BIGINT)
      WHERE w.treated = 1
    ),
    controls AS (
      SELECT
        CAST(w.cohort AS INTEGER) AS cohort,
        CAST(w.deal_id AS BIGINT) AS deal_id,
        CAST(w.codinv AS BIGINT) AS codinv,
        'control' AS arm,
        w.final_weight,
        NULL::BIGINT AS focal_group_1,
        NULL::BIGINT AS focal_group_2,
        CAST(w.control_group AS BIGINT) AS control_group,
        NULL::INTEGER AS treated_focal_last_patent_year,
        e.control_group_last_patent_year
      FROM weights w
      JOIN d1_control_endpoint e
        ON e.cohort = CAST(w.cohort AS INTEGER)
       AND e.codinv = CAST(w.codinv AS BIGINT)
       AND e.control_group = CAST(w.control_group AS BIGINT)
      WHERE w.treated = 0
    )
    SELECT * FROM treated
    UNION ALL
    SELECT * FROM controls
  ",
  weights_sql,
  lmv2_d1_sql_string(config$primary_retained_spec),
  lmv2_d1_sql_string(config$primary_retained_support)))

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE d1_endpoint_activity AS
    WITH horizons AS (
      SELECT * FROM (VALUES (5), (6)) AS h(event_time)
    )
    SELECT
      d.*,
      h.event_time,
      d.cohort + h.event_time AS calendar_year,
      (d.cohort + h.event_time <= %d) AS observable,
      CASE
        WHEN d.cohort + h.event_time > %d THEN NULL
        WHEN d.arm = 'treated' THEN (
          COALESCE(
            (
              SELECT MAX(a.group_patent_active::INTEGER)
              FROM d1_group_activity a
              WHERE a.year = d.cohort + h.event_time
                AND a.id_group IN (
                  d.focal_group_1, d.focal_group_2
                )
            ),
            0
          ) = 1
          OR EXISTS (
            SELECT 1
            FROM d1_target_company_activity t
            WHERE t.deal_id = d.deal_id
              AND t.year = d.cohort + h.event_time
          )
        )::INTEGER
        ELSE COALESCE(
          (
            SELECT MAX(a.group_patent_active::INTEGER)
            FROM d1_group_activity a
            WHERE a.year = d.cohort + h.event_time
              AND a.id_group = d.control_group
          ),
          0
        )
      END AS focal_group_patent_active,
      CASE
        WHEN d.cohort + h.event_time > %d THEN NULL
        WHEN d.arm = 'treated' THEN (
          d.treated_focal_last_patent_year >=
            d.cohort + h.event_time
        )::INTEGER
        ELSE (
          d.control_group_last_patent_year >=
            d.cohort + h.event_time
        )::INTEGER
      END AS focal_group_exists_through_horizon
    FROM d1_retained_design d
    CROSS JOIN horizons h
  ",
  config$observation_end_year,
  config$observation_end_year,
  config$observation_end_year))

  DBI::dbExecute(con, "
    CREATE TEMP TABLE d1_endpoint_activity_summary AS
    SELECT
      arm,
      event_time,
      COUNT(*) AS design_rows,
      COUNT(*) FILTER (WHERE observable) AS observable_rows,
      COUNT(DISTINCT deal_id) FILTER (WHERE observable)
        AS observable_deals,
      SUM(final_weight) FILTER (WHERE observable)
        AS observable_weight,
      SUM(final_weight * focal_group_patent_active) FILTER (
        WHERE observable
      ) / SUM(final_weight) FILTER (WHERE observable)
        AS weighted_patent_active_share,
      AVG(focal_group_patent_active) FILTER (WHERE observable)
        AS unweighted_patent_active_share,
      SUM(
        final_weight * focal_group_exists_through_horizon
      ) FILTER (WHERE observable) /
        SUM(final_weight) FILTER (WHERE observable)
        AS weighted_exists_through_horizon_share,
      AVG(focal_group_exists_through_horizon) FILTER (
        WHERE observable
      ) AS unweighted_exists_through_horizon_share
    FROM d1_endpoint_activity
    GROUP BY 1, 2
    ORDER BY 1, 2
  ")

  audit <- DBI::dbGetQuery(con, sprintf("
    SELECT
      (SELECT COUNT(*) FROM d1_status_base) AS status_rows,
      (SELECT COUNT(DISTINCT codinv) FROM d1_status_base)
        AS status_inventors,
      (SELECT COUNT(*) FROM d1_status_base
       WHERE first_post_year IS NOT NULL
         AND first_post_year < cohort + 1) AS event_year_status_violations,
      (SELECT COUNT(*) FROM d1_predeal_metrics
       WHERE career_first_year > cohort - 1) AS career_age_lookahead_rows,
      (SELECT COUNT(*) FROM d1_predeal_metrics
       WHERE latest_patent_year_used > cohort - 1)
        AS patent_stock_lookahead_rows,
      (SELECT COUNT(*) FROM d1_endpoints
       WHERE global_last_patent_year IS NULL) AS missing_d1_endpoints,
      (SELECT COUNT(*) FROM d1_endpoints
       WHERE p8_global_last_patent_year IS NOT NULL)
        AS p8_endpoint_overlap,
      (SELECT COUNT(*) FROM d1_endpoints
       WHERE p8_global_last_patent_year IS NOT NULL
         AND NOT p8_endpoint_matches) AS p8_endpoint_mismatches,
      (SELECT COUNT(*) FROM d1_status_paths) AS path_rows,
      (SELECT COUNT(DISTINCT codinv) FROM d1_status_paths)
        AS path_inventors,
      (SELECT COUNT(*) FROM d1_status_paths
       WHERE unresolved_patent_location)
        AS unresolved_patent_location_rows,
      (SELECT COUNT(*) FROM d1_transition_summary
       WHERE ABS(share) > 1) AS invalid_state_shares,
      (SELECT MAX(ABS(total_share - 1)) FROM (
        SELECT event_time, SUM(share) AS total_share
        FROM d1_transition_summary
        GROUP BY 1
      )) AS maximum_state_share_error,
      (SELECT COUNT(*) FROM d1_endpoint_activity
       WHERE event_time = 6 AND NOT observable
         AND focal_group_patent_active IS NOT NULL)
        AS plus_six_unobservable_value_rows,
      (SELECT COUNT(*) FROM d1_retained_design)
        AS retained_design_rows,
      (SELECT COUNT(*) FROM d1_retained_design
       WHERE arm = 'treated') AS retained_design_treated_rows
  "))
  audit$expected_path_rows <- audit$path_inventors *
    length(config$post_window)
  audit$pass <- with(
    audit,
    status_rows == status_inventors &
      event_year_status_violations == 0L &
      career_age_lookahead_rows == 0L &
      patent_stock_lookahead_rows == 0L &
      missing_d1_endpoints == 0L &
      p8_endpoint_mismatches == 0L &
      path_rows == expected_path_rows &
      invalid_state_shares == 0L &
      maximum_state_share_error < 1e-12 &
      plus_six_unobservable_value_rows == 0L &
      retained_design_treated_rows > 0L
  )
  if (!isTRUE(audit$pass[[1L]])) {
    stop("D1 status-path construction audit failed.", call. = FALSE)
  }

  copy_parquet <- function(table, path, order_by = NULL) {
    query <- paste0(
      "COPY (SELECT * FROM ", table,
      if (!is.null(order_by)) paste0(" ORDER BY ", order_by) else "",
      ") TO ", lmv2_d1_sql_string(path),
      " (FORMAT PARQUET, COMPRESSION ZSTD)"
    )
    DBI::dbExecute(con, query)
  }
  copy_csv <- function(table, path, order_by = NULL) {
    query <- paste0(
      "COPY (SELECT * FROM ", table,
      if (!is.null(order_by)) paste0(" ORDER BY ", order_by) else "",
      ") TO ", lmv2_d1_sql_string(path),
      " (HEADER, DELIMITER ',')"
    )
    DBI::dbExecute(con, query)
  }

  copy_parquet(
    "d1_predeal_metrics", output_paths[[1L]],
    "retention_status, cohort, deal_id, codinv"
  )
  copy_parquet(
    "d1_endpoints", output_paths[[2L]], "codinv"
  )
  copy_parquet(
    "d1_status_paths", output_paths[[3L]],
    "event_time, deal_id, codinv"
  )
  copy_csv(
    "d1_transition_summary", output_paths[[4L]],
    "event_time, annual_state"
  )
  copy_csv(
    "d1_persistence_summary", output_paths[[5L]], "horizon"
  )
  copy_parquet(
    "d1_endpoint_activity", output_paths[[6L]],
    "arm, event_time, deal_id, codinv"
  )
  copy_csv(
    "d1_endpoint_activity_summary", output_paths[[7L]],
    "arm, event_time"
  )
  lmv2_d1_write_csv(audit, output_paths[[8L]])

  invisible(list(output_paths = output_paths, audit = audit))
}

if (sys.nframe() == 0L) {
  lmv2_d1_build_status_paths()
  message("D1 status paths built.")
}
