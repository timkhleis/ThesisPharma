# Package N0: construct pre-acquisition application dyads and baseline ties.

if (!exists("lmv2_n0_config")) {
  source(file.path(
    "02_analysis", "R", "43a_lmv2_network_freeze_config.R"
  ))
}

lmv2_n0_build_predeal_dyads <- function(config = lmv2_n0_config()) {
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
  required <- c(
    config$foundation_db,
    config$p5c_roster,
    config$p6_manifest,
    config$p6_certification,
    config$freeze_file
  )
  if (any(!file.exists(required))) {
    stop(
      "Missing N0 construction input(s): ",
      paste(required[!file.exists(required)], collapse = ", "),
      call. = FALSE
    )
  }
  observed_roster_hash <- digest::digest(
    file = config$p5c_roster, algo = "sha256", serialize = FALSE
  )
  if (!identical(observed_roster_hash, config$p5c_roster_sha256)) {
    stop("Certified P5c roster hash mismatch.", call. = FALSE)
  }

  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
  output_names <- c(
    "p5c_network_roster.parquet",
    "predeal_application_dyads.parquet",
    "predeal_focal_partner_links.parquet",
    "persistent_baseline_ties.parquet",
    "network_focal_support.parquet",
    "validation_denominator_support.parquet",
    "network_construction_audit.csv"
  )
  output_paths <- file.path(config$output_dir, output_names)
  unlink(output_paths[file.exists(output_paths)], force = TRUE)

  con <- DBI::dbConnect(
    duckdb::duckdb(dbdir = config$foundation_db, read_only = TRUE)
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "PRAGMA threads=8")
  DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")

  roster_sql <- lmv2_n0_sql_string(config$p5c_roster)
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE n0_roster AS
    SELECT
      CAST(deal_id AS BIGINT) AS deal_id,
      CAST(cohort AS INTEGER) AS cohort,
      arm,
      CAST(codinv AS BIGINT) AS codinv,
      roster_row_id,
      CAST(weight AS DOUBLE) AS weight,
      status_eligible,
      CAST(focal_group_1 AS BIGINT) AS focal_group_1,
      CAST(focal_group_2 AS BIGINT) AS focal_group_2,
      use_target_company_path,
      qualification_route,
      target_to_acquirer_transition_strict,
      latest_pre_candidate_group_count,
      multi_exposure_inventor,
      big_deal
    FROM read_parquet(%s)
  ", roster_sql))

  min_pre_year <- min(1994:2010) + min(config$anchor_window)
  max_pre_year <- max(1994:2010) + max(config$validation_window)
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE n0_application_inventors AS
    SELECT
      CAST(appln_id AS BIGINT) AS appln_id,
      CAST(codinv AS BIGINT) AS codinv,
      CAST(year AS INTEGER) AS year
    FROM patent_inventor_enriched
    WHERE year BETWEEN %d AND %d
  ", min_pre_year, max_pre_year))

  DBI::dbExecute(con, "
    CREATE TEMP TABLE n0_focal_applications AS
    SELECT DISTINCT
      r.roster_row_id,
      r.deal_id,
      r.cohort,
      r.arm,
      r.codinv AS focal_codinv,
      r.weight,
      a.appln_id,
      a.year,
      a.year - r.cohort AS event_time
    FROM n0_roster r
    JOIN n0_application_inventors a
      ON a.codinv = r.codinv
    WHERE a.year - r.cohort BETWEEN -5 AND -1
  ")

  DBI::dbExecute(con, "
    CREATE TEMP TABLE n0_focal_partner_links AS
    SELECT DISTINCT
      f.roster_row_id,
      f.deal_id,
      f.cohort,
      f.arm,
      f.focal_codinv,
      f.weight,
      f.appln_id,
      f.year,
      f.event_time,
      p.codinv AS partner_codinv
    FROM n0_focal_applications f
    JOIN n0_application_inventors p
      ON p.appln_id = f.appln_id
     AND p.codinv <> f.focal_codinv
  ")

  DBI::dbExecute(con, "
    CREATE TEMP TABLE n0_application_dyads AS
    SELECT DISTINCT
      appln_id,
      year,
      LEAST(focal_codinv, partner_codinv) AS codinv_low,
      GREATEST(focal_codinv, partner_codinv) AS codinv_high
    FROM n0_focal_partner_links
  ")

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE n0_baseline_ties AS
    SELECT
      roster_row_id,
      deal_id,
      cohort,
      arm,
      focal_codinv,
      partner_codinv,
      MIN(weight) AS weight,
      COUNT(DISTINCT appln_id) AS anchor_joint_applications,
      COUNT(DISTINCT year) AS anchor_joint_years,
      MIN(year) AS first_anchor_year,
      MAX(year) AS last_anchor_year
    FROM n0_focal_partner_links
    WHERE event_time BETWEEN %d AND %d
    GROUP BY 1, 2, 3, 4, 5, 6
    HAVING COUNT(DISTINCT appln_id) >= %d
       AND COUNT(DISTINCT year) >= %d
  ",
  min(config$anchor_window),
  max(config$anchor_window),
  config$minimum_joint_applications,
  config$minimum_joint_years))

  DBI::dbExecute(con, "
    CREATE TEMP TABLE n0_tie_summary AS
    SELECT
      roster_row_id,
      COUNT(*) AS baseline_collaborator_count,
      SUM(anchor_joint_applications) AS total_anchor_joint_applications,
      MAX(anchor_joint_applications) AS strongest_tie_joint_applications,
      MAX(anchor_joint_applications) * 1.0 /
        SUM(anchor_joint_applications) AS strongest_tie_concentration
    FROM n0_baseline_ties
    GROUP BY 1
  ")

  DBI::dbExecute(con, "
    CREATE TEMP TABLE n0_focal_support AS
    SELECT
      r.*,
      COALESCE(t.baseline_collaborator_count, 0)
        AS baseline_collaborator_count,
      COALESCE(t.total_anchor_joint_applications, 0)
        AS total_anchor_joint_applications,
      COALESCE(t.strongest_tie_joint_applications, 0)
        AS strongest_tie_joint_applications,
      t.strongest_tie_concentration,
      (t.roster_row_id IS NOT NULL) AS has_persistent_baseline_tie
    FROM n0_roster r
    LEFT JOIN n0_tie_summary t USING (roster_row_id)
  ")

  DBI::dbExecute(con, "
    CREATE TEMP TABLE n0_validation_denominators AS
    WITH grid AS (
      SELECT
        s.*,
        v.event_time,
        s.cohort + v.event_time AS calendar_year
      FROM n0_focal_support s
      CROSS JOIN (VALUES (-2), (-1)) AS v(event_time)
      WHERE s.has_persistent_baseline_tie
    ),
    current_links AS (
      SELECT
        roster_row_id,
        event_time,
        COUNT(DISTINCT partner_codinv)
          AS distinct_current_collaborators,
        COUNT(*) AS current_link_instances
      FROM n0_focal_partner_links
      WHERE event_time BETWEEN -2 AND -1
      GROUP BY 1, 2
    )
    SELECT
      g.roster_row_id,
      g.deal_id,
      g.cohort,
      g.arm,
      g.codinv AS focal_codinv,
      g.weight,
      g.baseline_collaborator_count,
      g.event_time,
      g.calendar_year,
      COALESCE(c.distinct_current_collaborators, 0)
        AS distinct_current_collaborators,
      COALESCE(c.current_link_instances, 0)
        AS current_link_instances,
      (COALESCE(c.current_link_instances, 0) > 0)
        AS composition_defined,
      TRUE AS partner_persistence_denominator_defined
    FROM grid g
    LEFT JOIN current_links c
      ON c.roster_row_id = g.roster_row_id
     AND c.event_time = g.event_time
  ")

  audit <- DBI::dbGetQuery(con, "
    SELECT
      (SELECT COUNT(*) FROM n0_roster) AS roster_rows,
      (SELECT COUNT(DISTINCT roster_row_id) FROM n0_roster)
        AS roster_keys,
      (SELECT COUNT(*) FROM n0_roster
       WHERE NOT isfinite(weight) OR weight <= 0)
        AS invalid_weight_rows,
      (SELECT COUNT(DISTINCT arm) FROM n0_roster) AS roster_arms,
      (SELECT COUNT(*) FROM (
        SELECT appln_id, codinv, COUNT(*) AS n
        FROM n0_application_inventors
        GROUP BY 1, 2
        HAVING COUNT(*) > 1
      )) AS duplicate_application_inventor_keys,
      (SELECT COUNT(*) FROM n0_focal_partner_links
       WHERE focal_codinv = partner_codinv) AS self_link_rows,
      (SELECT COUNT(*) FROM (
        SELECT appln_id, codinv_low, codinv_high, COUNT(*) AS n
        FROM n0_application_dyads
        GROUP BY 1, 2, 3
        HAVING COUNT(*) > 1
      )) AS duplicate_application_dyad_keys,
      (SELECT COUNT(*) FROM (
        SELECT roster_row_id, appln_id, partner_codinv, COUNT(*) AS n
        FROM n0_focal_partner_links
        GROUP BY 1, 2, 3
        HAVING COUNT(*) > 1
      )) AS duplicate_focal_partner_link_keys,
      (SELECT MIN(event_time) FROM n0_focal_partner_links)
        AS minimum_input_event_time,
      (SELECT MAX(event_time) FROM n0_focal_partner_links)
        AS maximum_input_event_time,
      (SELECT COUNT(*) FROM n0_baseline_ties
       WHERE anchor_joint_applications < 2
          OR anchor_joint_years < 2) AS invalid_persistent_ties,
      (SELECT COUNT(*) FROM n0_focal_support
       WHERE has_persistent_baseline_tie) AS network_support_rows,
      (SELECT COUNT(DISTINCT arm) FROM n0_focal_support
       WHERE has_persistent_baseline_tie) AS network_support_arms,
      (SELECT COUNT(*) FROM n0_validation_denominators)
        AS validation_rows,
      (SELECT COUNT(*) FROM n0_validation_denominators
       WHERE NOT partner_persistence_denominator_defined)
        AS undefined_partner_denominator_rows
  ")
  audit$expected_validation_rows <- 2L * audit$network_support_rows
  audit$pass <- with(
    audit,
    roster_rows == roster_keys &
      invalid_weight_rows == 0L &
      roster_arms == 2L &
      duplicate_application_inventor_keys == 0L &
      self_link_rows == 0L &
      duplicate_application_dyad_keys == 0L &
      duplicate_focal_partner_link_keys == 0L &
      minimum_input_event_time >= -5L &
      maximum_input_event_time <= -1L &
      invalid_persistent_ties == 0L &
      network_support_rows > 0L &
      network_support_arms == 2L &
      validation_rows == expected_validation_rows &
      undefined_partner_denominator_rows == 0L
  )
  if (!isTRUE(audit$pass[[1L]])) {
    stop("N0 pre-deal network construction audit failed.", call. = FALSE)
  }

  copy_parquet <- function(table, path, order_by) {
    DBI::dbExecute(con, paste0(
      "COPY (SELECT * FROM ", table, " ORDER BY ", order_by, ") TO ",
      lmv2_n0_sql_string(path),
      " (FORMAT PARQUET, COMPRESSION ZSTD)"
    ))
  }
  copy_parquet(
    "n0_roster", output_paths[[1L]], "arm, cohort, deal_id, roster_row_id"
  )
  copy_parquet(
    "n0_application_dyads", output_paths[[2L]],
    "year, appln_id, codinv_low, codinv_high"
  )
  copy_parquet(
    "n0_focal_partner_links", output_paths[[3L]],
    "arm, cohort, deal_id, roster_row_id, event_time, appln_id, partner_codinv"
  )
  copy_parquet(
    "n0_baseline_ties", output_paths[[4L]],
    "arm, cohort, deal_id, roster_row_id, partner_codinv"
  )
  copy_parquet(
    "n0_focal_support", output_paths[[5L]],
    "arm, cohort, deal_id, roster_row_id"
  )
  copy_parquet(
    "n0_validation_denominators", output_paths[[6L]],
    "arm, event_time, cohort, deal_id, roster_row_id"
  )
  lmv2_n0_write_csv(audit, output_paths[[7L]])

  invisible(list(output_paths = output_paths, audit = audit))
}

if (sys.nframe() == 0L) {
  lmv2_n0_build_predeal_dyads()
  message("N0 pre-deal dyads and baseline ties built.")
}
