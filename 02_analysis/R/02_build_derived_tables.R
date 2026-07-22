source(file.path("02_analysis", "R", "00_utils.R"))

load_packages()
ensure_output_dirs()

message("Opening DuckDB and loading canonical tables...")
con <- connect_duckdb()
on.exit(disconnect_duckdb(con), add = TRUE)

sql_statements <- c(
  inventor_lookup = "
    CREATE OR REPLACE TABLE inventor_lookup AS
    SELECT
      codinv,
      MIN(codinv2) FILTER (WHERE codinv2 IS NOT NULL) AS codinv2,
      MIN(inname) FILTER (WHERE inname IS NOT NULL) AS inventor_name,
      MIN(incy) FILTER (WHERE incy IS NOT NULL) AS inventor_country,
      COUNT(*) AS source_row_count,
      COUNT(DISTINCT codinv2) AS codinv2_value_count,
      COUNT(DISTINCT inname) AS inventor_name_value_count,
      COUNT(DISTINCT incy) AS inventor_country_value_count
    FROM inventor
    GROUP BY codinv
  ",
  patent_application = "
    CREATE OR REPLACE TABLE patent_application AS
    SELECT
      appln_id,
      MIN(year) AS patent_year,
      COUNT(*) AS patent_row_count,
      COUNT(DISTINCT compcod) AS compcod_count,
      string_agg(DISTINCT CAST(compcod AS VARCHAR), ';' ORDER BY CAST(compcod AS VARCHAR)) AS compcod_list
    FROM patent
    GROUP BY appln_id
  ",
  patent_company_link = "
    CREATE OR REPLACE TABLE patent_company_link AS
    SELECT DISTINCT
      p.appln_id,
      p.compcod,
      p.year,
      fg.id_group,
      fg.merger_status
    FROM patent AS p
    LEFT JOIN firm_group AS fg
      ON p.compcod = fg.compcod
     AND p.year = fg.year
  ",
  group_year_status = "
    CREATE OR REPLACE TABLE group_year_status AS
    SELECT
      fg.id_group,
      fg.year,
      COUNT(DISTINCT fg.compcod) AS firms_in_group,
      string_agg(DISTINCT fg.merger_status, ';' ORDER BY fg.merger_status) FILTER (WHERE fg.merger_status IS NOT NULL) AS merger_status_values,
      g.group_type,
      g.group_name,
      b.bvd_id,
      gp.patent AS helper_group_patent
    FROM firm_group AS fg
    LEFT JOIN \"group\" AS g
      ON fg.id_group = g.id_group
    LEFT JOIN bvd_group_id AS b
      ON fg.id_group = b.id_group
    LEFT JOIN group_production AS gp
      ON fg.id_group = gp.id_group
     AND fg.year = gp.year
    GROUP BY fg.id_group, fg.year, g.group_type, g.group_name, b.bvd_id, gp.patent
  ",
  patent_enriched = "
    CREATE OR REPLACE TABLE patent_enriched AS
    WITH inventor_counts AS (
      SELECT appln_id, COUNT(DISTINCT codinv) AS inventor_count
      FROM patent_inventor
      GROUP BY appln_id
    ),
    ipc_counts AS (
      SELECT appln_id, COUNT(DISTINCT ipc_code) AS ipc_code_count
      FROM ipc
      GROUP BY appln_id
    ),
    company_group_summary AS (
      SELECT
        appln_id,
        COUNT(DISTINCT compcod) AS company_link_count,
        COUNT(DISTINCT id_group) AS group_count,
        string_agg(DISTINCT CAST(compcod AS VARCHAR), ';' ORDER BY CAST(compcod AS VARCHAR)) AS compcod_list,
        string_agg(DISTINCT CAST(id_group AS VARCHAR), ';' ORDER BY CAST(id_group AS VARCHAR)) FILTER (WHERE id_group IS NOT NULL) AS id_group_list,
        string_agg(DISTINCT merger_status, ';' ORDER BY merger_status) FILTER (WHERE merger_status IS NOT NULL) AS merger_status_values
      FROM patent_company_link
      GROUP BY appln_id
    )
    SELECT
      pa.appln_id,
      pa.patent_year,
      pa.patent_row_count,
      pa.compcod_count,
      pa.compcod_list,
      cgs.company_link_count,
      cgs.group_count,
      cgs.id_group_list,
      cgs.merger_status_values,
      ic.inventor_count,
      ipcc.ipc_code_count,
      oq.app_nbr,
      oq.filing,
      oq.tech_field,
      oq.many_field,
      oq.patent_scope,
      oq.family_size,
      oq.grant_lag,
      oq.bwd_cits,
      oq.npl_cits,
      oq.claims,
      oq.claims_bwd,
      oq.fwd_cits5,
      oq.fwd_cits5_xy,
      oq.fwd_cits7,
      oq.fwd_cits7_xy,
      oq.breakthrough,
      oq.breakthrough_xy,
      oq.generality,
      oq.originality,
      oq.radicalness,
      oq.renewal,
      oq.quality_index_4,
      oq.quality_index_6
    FROM patent_application AS pa
    LEFT JOIN company_group_summary AS cgs
      ON pa.appln_id = cgs.appln_id
    LEFT JOIN inventor_counts AS ic
      ON pa.appln_id = ic.appln_id
    LEFT JOIN ipc_counts AS ipcc
      ON pa.appln_id = ipcc.appln_id
    LEFT JOIN oecd_quality AS oq
      ON pa.appln_id = oq.appln_id
  ",
  patent_inventor_enriched = "
    CREATE OR REPLACE TABLE patent_inventor_enriched AS
    WITH inventor_application AS (
      SELECT DISTINCT appln_id, codinv
      FROM patent_inventor
    )
    SELECT
      pi.appln_id,
      pi.codinv,
      pe.patent_year AS year,
      pe.inventor_count,
      pe.ipc_code_count,
      pe.group_count,
      pe.compcod_count,
      pe.id_group_list,
      pe.merger_status_values,
      i.codinv2,
      i.inventor_name AS inname,
      i.inventor_country AS incy
    FROM inventor_application AS pi
    LEFT JOIN patent_enriched AS pe
      ON pi.appln_id = pe.appln_id
    LEFT JOIN inventor_lookup AS i
      ON pi.codinv = i.codinv
  ",
  inventor_group_year = "
    CREATE OR REPLACE TABLE inventor_group_year AS
    WITH inventor_application AS (
      SELECT DISTINCT appln_id, codinv
      FROM patent_inventor
    )
    SELECT
      pi.codinv,
      pa.patent_year AS year,
      COUNT(DISTINCT pcl.id_group) AS group_count,
      COUNT(DISTINCT pcl.compcod) AS firm_count,
      string_agg(DISTINCT CAST(pcl.id_group AS VARCHAR), ';' ORDER BY CAST(pcl.id_group AS VARCHAR)) FILTER (WHERE pcl.id_group IS NOT NULL) AS group_list,
      string_agg(DISTINCT pcl.merger_status, ';' ORDER BY pcl.merger_status) FILTER (WHERE pcl.merger_status IS NOT NULL) AS merger_status_values
    FROM inventor_application AS pi
    INNER JOIN patent_application AS pa
      ON pi.appln_id = pa.appln_id
    LEFT JOIN patent_company_link AS pcl
      ON pi.appln_id = pcl.appln_id
    GROUP BY pi.codinv, pa.patent_year
  ",
  inventor_year = "
    CREATE OR REPLACE TABLE inventor_year AS
    WITH inventor_application AS (
      SELECT DISTINCT appln_id, codinv
      FROM patent_inventor
    ),
    inventor_patent_counts AS (
      SELECT appln_id, COUNT(DISTINCT codinv) AS inventor_count
      FROM inventor_application
      GROUP BY appln_id
    ),
    inventor_year_base AS (
      SELECT
        pi.codinv,
        pa.patent_year AS year,
        COUNT(DISTINCT pi.appln_id) AS patent_count,
        CAST(
          SUM(CAST(1.0 / ipc.inventor_count AS DECIMAL(38, 18)))
          AS DOUBLE
        ) AS fractional_patent_count
      FROM inventor_application AS pi
      INNER JOIN patent_application AS pa
        ON pi.appln_id = pa.appln_id
      INNER JOIN inventor_patent_counts AS ipc
        ON pi.appln_id = ipc.appln_id
      GROUP BY pi.codinv, pa.patent_year
    )
    SELECT
      iyb.codinv,
      iyb.year,
      iyb.patent_count,
      iyb.fractional_patent_count,
      igy.firm_count AS distinct_firm_count,
      igy.group_count AS distinct_group_count,
      MIN(iyb.year) OVER (PARTITION BY iyb.codinv) AS career_first_year,
      MAX(iyb.year) OVER (PARTITION BY iyb.codinv) AS career_last_year,
      iyb.year - MIN(iyb.year) OVER (PARTITION BY iyb.codinv) + 1 AS career_year_index
    FROM inventor_year_base AS iyb
    LEFT JOIN inventor_group_year AS igy
      ON iyb.codinv = igy.codinv
     AND iyb.year = igy.year
  ",
  inventor_ipc_year = "
    CREATE OR REPLACE TABLE inventor_ipc_year AS
    WITH inventor_application AS (
      SELECT DISTINCT appln_id, codinv
      FROM patent_inventor
    ),
    ipc_application AS (
      SELECT DISTINCT appln_id, ipc_code
      FROM ipc
    ),
    inventor_patent_counts AS (
      SELECT appln_id, COUNT(DISTINCT codinv) AS inventor_count
      FROM inventor_application
      GROUP BY appln_id
    )
    SELECT
      pi.codinv,
      pa.patent_year AS year,
      ipc.ipc_code,
      COUNT(DISTINCT pi.appln_id) AS patent_count,
      CAST(
        SUM(CAST(1.0 / ic.inventor_count AS DECIMAL(38, 18)))
        AS DOUBLE
      ) AS fractional_patent_count
    FROM inventor_application AS pi
    INNER JOIN patent_application AS pa
      ON pi.appln_id = pa.appln_id
    INNER JOIN inventor_patent_counts AS ic
      ON pi.appln_id = ic.appln_id
    INNER JOIN ipc_application AS ipc
      ON pi.appln_id = ipc.appln_id
    GROUP BY pi.codinv, pa.patent_year, ipc.ipc_code
  ",
  group_ipc_year = "
    CREATE OR REPLACE TABLE group_ipc_year AS
    SELECT
      pcl.id_group,
      pcl.year,
      ipc.ipc_code,
      COUNT(DISTINCT pcl.appln_id) AS patent_count
    FROM patent_company_link AS pcl
    INNER JOIN ipc
      ON pcl.appln_id = ipc.appln_id
    WHERE pcl.id_group IS NOT NULL
    GROUP BY pcl.id_group, pcl.year, ipc.ipc_code
  "
)

message("Building derived tables in DuckDB...")
for (statement_name in names(sql_statements)) {
  message("  - ", statement_name)
  DBI::dbExecute(con, sql_statements[[statement_name]])
}

derived_tables <- names(sql_statements)
for (table_name in derived_tables) {
  copy_db_table_to_parquet(con, table_name, "derived")
}

derived_inventory <- purrr::map_dfr(derived_tables, function(table_name) {
  counts <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) AS n_rows FROM %s", as.character(DBI::dbQuoteIdentifier(con, table_name))))
  columns <- DBI::dbListFields(con, table_name)
  tibble::tibble(
    table_name = table_name,
    n_rows = counts$n_rows[[1]],
    n_cols = length(columns)
  )
}) |>
  dplyr::arrange(table_name)

write_csv(derived_inventory, project_path("02_analysis", "output", "metadata", "derived_inventory.csv"))

message("Derived table build complete.")
