# ============================================================================
# 36b_build_lmv2_global_career_endpoints.R
# Build one capped, global patenting endpoint per P6 inventor.
# ============================================================================

if (!exists("lmv2_exit_config")) {
  source(file.path(
    "02_analysis", "R", "36a_lmv2_exit_decomposition_config.R"))
}

lmv2_build_global_career_endpoints <- function(
    config = lmv2_exit_config(), smoke = FALSE) {
  source(file.path(config$base, "02_analysis", "R", "00_utils.R"))
  use_project_library()
  shared_lib <- file.path(config$project_root, ".r_libs")
  if (dir.exists(shared_lib)) {
    .libPaths(unique(c(shared_lib, .libPaths())))
  }
  required_packages <- c("DBI", "duckdb", "digest")
  for (pkg in required_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Missing package: ", pkg)
    }
  }
  required <- c(
    config$inventor_year, config$patent_inventor_enriched,
    config$p6_manifest, config$freeze_file)
  if (any(!file.exists(required))) {
    stop("Missing endpoint input: ", paste(required[!file.exists(required)],
                                            collapse = ", "))
  }
  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
  panel_files <- lmv2_exit_panel_files(config)
  if (smoke) panel_files <- panel_files[1:3]
  panel_sql <- lmv2_exit_panel_sql(panel_files)

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(
    con, sprintf("PRAGMA threads=%d", config$execution$threads))
  DBI::dbExecute(
    con, sprintf("PRAGMA memory_limit=%s",
                 lmv2_exit_sql_string(config$execution$memory_limit)))

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE relevant_inventors AS
    SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv
    FROM %s
  ", panel_sql))
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE endpoint_lookup AS
    WITH source AS (
      SELECT
        CAST(iy.codinv AS BIGINT) AS codinv,
        CAST(iy.year AS INTEGER) AS year,
        CAST(iy.career_last_year AS INTEGER) AS career_last_year
      FROM read_parquet(%s) iy
      JOIN relevant_inventors r
        ON r.codinv = CAST(iy.codinv AS BIGINT)
      WHERE iy.patent_count > 0
        AND iy.year <= %d
    )
    SELECT
      codinv,
      MAX(year) AS global_last_patent_year,
      MAX(career_last_year) AS source_career_last_year,
      COUNT(DISTINCT career_last_year) AS distinct_endpoint_values
    FROM source
    GROUP BY codinv
  ", lmv2_exit_sql_string(config$inventor_year),
     config$observation_end_year))
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE independent_endpoint AS
    SELECT
      CAST(p.codinv AS BIGINT) AS codinv,
      MAX(CAST(p.year AS INTEGER)) AS independent_last_patent_year
    FROM (
      SELECT DISTINCT codinv, appln_id, year
      FROM read_parquet(%s)
      WHERE year <= %d
    ) p
    JOIN relevant_inventors r
      ON r.codinv = CAST(p.codinv AS BIGINT)
    GROUP BY 1
  ", lmv2_exit_sql_string(config$patent_inventor_enriched),
     config$observation_end_year))

  checks <- DBI::dbGetQuery(con, sprintf("
    SELECT
      (SELECT COUNT(*) FROM relevant_inventors) AS relevant_inventors,
      (SELECT COUNT(*) FROM endpoint_lookup) AS endpoint_rows,
      (SELECT COUNT(*) FROM endpoint_lookup
       WHERE global_last_patent_year IS NULL) AS missing_endpoint,
      (SELECT COUNT(*) FROM endpoint_lookup
       WHERE distinct_endpoint_values <> 1) AS inconsistent_source_endpoint,
      (SELECT COUNT(*) FROM endpoint_lookup e
       JOIN independent_endpoint i USING (codinv)
       WHERE e.global_last_patent_year <>
             i.independent_last_patent_year) AS independent_mismatch,
      (SELECT COUNT(*) FROM endpoint_lookup e
       LEFT JOIN independent_endpoint i USING (codinv)
       WHERE i.codinv IS NULL) AS missing_independent_endpoint,
      (SELECT MIN(global_last_patent_year)
       FROM endpoint_lookup) AS min_endpoint_year,
      (SELECT MAX(global_last_patent_year)
       FROM endpoint_lookup) AS max_endpoint_year,
      (SELECT COUNT(*) FROM read_parquet(%s)
       WHERE patent_count > 0 AND year > %d) AS source_rows_after_cap,
      (SELECT COUNT(DISTINCT CAST(codinv AS BIGINT))
       FROM read_parquet(%s)
       WHERE patent_count > 0 AND year > %d) AS source_inventors_after_cap
  ", lmv2_exit_sql_string(config$inventor_year),
     config$observation_end_year,
     lmv2_exit_sql_string(config$inventor_year),
     config$observation_end_year))
  checks$pass <- with(
    checks,
    endpoint_rows == relevant_inventors &&
      missing_endpoint == 0L &&
      inconsistent_source_endpoint == 0L &&
      independent_mismatch == 0L &&
      missing_independent_endpoint == 0L &&
      max_endpoint_year <= config$observation_end_year)
  if (!isTRUE(checks$pass[[1L]])) {
    stop("Global career endpoint construction failed certification")
  }

  endpoint_path <- normalizePath(
    config$output_dir, winslash = "/", mustWork = TRUE)
  endpoint_path <- file.path(endpoint_path, basename(config$endpoint_path))
  DBI::dbExecute(con, sprintf("
    COPY (
      SELECT
        e.codinv,
        e.global_last_patent_year,
        e.source_career_last_year,
        i.independent_last_patent_year
      FROM endpoint_lookup e
      JOIN independent_endpoint i USING (codinv)
      ORDER BY codinv
    ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)
  ", lmv2_exit_sql_string(endpoint_path)))

  lmv2_exit_write_csv(
    checks,
    file.path(config$output_dir, "endpoint_construction_audit.csv"))
  buffer_audit <- data.frame(
    sample = names(config$samples),
    latest_outcome_year = vapply(
      config$samples,
      function(x) max(x$cohorts) + max(x$post_window), numeric(1)),
    future_observation_buffer = vapply(
      config$samples,
      function(x) config$observation_end_year -
        (max(x$cohorts) + max(x$post_window)), numeric(1)),
    censoring_label = vapply(
      config$samples, `[[`, character(1), "censoring_label"),
    stringsAsFactors = FALSE)
  lmv2_exit_write_csv(
    buffer_audit,
    file.path(config$output_dir, "endpoint_buffer_audit.csv"))
  invisible(list(endpoint_path = endpoint_path, checks = checks))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  smoke <- "--smoke" %in% args
  output_arg <- sub(
    "^--output-dir=", "", grep(
      "^--output-dir=", args, value = TRUE))
  config <- lmv2_exit_config(
    output_dir = if (length(output_arg)) output_arg[[1L]] else NULL)
  lmv2_build_global_career_endpoints(config, smoke = smoke)
}
