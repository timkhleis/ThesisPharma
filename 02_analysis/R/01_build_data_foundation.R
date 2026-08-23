source(file.path("02_analysis", "R", "00_utils.R"))

load_packages()
ensure_output_dirs()

table_specs <- list(
  inventor = list(
    layer = "canonical",
    source_path = project_path("01_Data", "inventor.dta"),
    grain = "one row per published inventor identifier",
    primary_key = c("codinv"),
    role = "canonical baseline inventor identities"
  ),
  patent = list(
    layer = "canonical",
    source_path = project_path("01_Data", "patent.dta"),
    grain = "one row per patent application and company-year link",
    primary_key = c("appln_id"),
    role = "canonical patent application table"
  ),
  patent_inventor = list(
    layer = "canonical",
    source_path = project_path("01_Data", "patent_inventor.dta"),
    grain = "many-to-many bridge between patent applications and inventors",
    primary_key = c("appln_id", "codinv"),
    role = "canonical inventor-patent bridge"
  ),
  ipc = list(
    layer = "canonical",
    source_path = project_path("01_Data", "ipc.dta"),
    grain = "many-to-many bridge between patent applications and IPC codes",
    primary_key = c("appln_id", "clmn"),
    role = "canonical patent classification table"
  ),
  group = list(
    layer = "canonical",
    source_path = project_path("01_Data", "group.dta"),
    grain = "one row per group identifier",
    primary_key = c("id_group"),
    role = "canonical group dimension"
  ),
  firm = list(
    layer = "canonical",
    source_path = project_path("01_Data", "firm.dta"),
    grain = "one row per company code",
    primary_key = c("compcod"),
    role = "canonical firm dimension"
  ),
  firm_group = list(
    layer = "canonical",
    source_path = project_path("01_Data", "firm_group.dta"),
    grain = "one row per company-year group assignment",
    primary_key = c("compcod", "year", "id_group"),
    role = "canonical firm-group-year bridge"
  ),
  inventor_production = list(
    layer = "helper",
    source_path = project_path("01_Data", "CassiOrnaghiPaperData", "inventor_production.csv"),
    grain = "one row per inventor-year helper observation",
    primary_key = c("codinv", "year"),
    role = "validation benchmark only"
  ),
  group_production = list(
    layer = "helper",
    source_path = project_path("01_Data", "CassiOrnaghiPaperData", "group_production.csv"),
    grain = "one row per group-year helper observation",
    primary_key = c("id_group", "year"),
    role = "validation benchmark only"
  ),
  merger_list = list(
    layer = "helper",
    source_path = project_path("01_Data", "CassiOrnaghiPaperData", "merger_list.csv"),
    grain = "summary rows by merger year and value bucket",
    primary_key = c("target_year", "target_value", "big"),
    role = "year-level merger summary helper"
  ),
  bvd_group_id = list(
    layer = "helper",
    source_path = project_path("01_Data", "CassiOrnaghiPaperData", "BvD_group_id.csv"),
    grain = "one row per group to BvD identifier mapping",
    primary_key = c("id_group"),
    role = "linkage helper"
  ),
  oecd_quality = list(
    layer = "enrichment",
    source_path = project_path("01_Data", "OECD_QualitaData", "OECD_Quality_data.txt"),
    grain = "one row per patent application quality record",
    primary_key = c("appln_id"),
    role = "patent quality enrichment"
  )
)

message("Reading source tables...")

tables <- list(
  inventor = read_dta_table(table_specs$inventor$source_path),
  patent = read_dta_table(table_specs$patent$source_path),
  patent_inventor = read_dta_table(table_specs$patent_inventor$source_path),
  ipc = read_dta_table(table_specs$ipc$source_path),
  group = read_dta_table(table_specs$group$source_path),
  firm = read_dta_table(table_specs$firm$source_path),
  firm_group = read_dta_table(table_specs$firm_group$source_path),
  inventor_production = read_csv_table(table_specs$inventor_production$source_path),
  group_production = read_csv_table(table_specs$group_production$source_path),
  merger_list = read_csv_table(table_specs$merger_list$source_path),
  bvd_group_id = read_bvd_group_id(table_specs$bvd_group_id$source_path),
  oecd_quality = read_csv_table(table_specs$oecd_quality$source_path, delim = "|")
)

tables$ipc <- tables$ipc |>
  dplyr::rename(ipc_code = "clmn")

tables$group <- tables$group |>
  dplyr::rename(group_type = "type")

tables$merger_list <- tables$merger_list |>
  dplyr::rename(merger_count = "count")

tables$patent <- tables$patent |>
  dplyr::mutate(year = as.integer(.data$year))

tables$firm_group <- tables$firm_group |>
  dplyr::mutate(year = as.integer(.data$year))

tables$inventor_production <- tables$inventor_production |>
  dplyr::mutate(year = as.integer(.data$year))

tables$group_production <- tables$group_production |>
  dplyr::mutate(year = as.integer(.data$year))

tables$oecd_quality <- tables$oecd_quality |>
  dplyr::mutate(
    appln_id = as.numeric(.data$appln_id),
    filing = as.integer(.data$filing)
  )

inventory <- create_table_inventory(table_specs) |>
  dplyr::mutate(
    n_rows = purrr::map_int(table_name, ~ nrow(tables[[.x]])),
    n_cols = purrr::map_int(table_name, ~ ncol(tables[[.x]])),
    duplicate_key_rows = purrr::map2_int(table_name, primary_key, ~ {
      keys <- stringr::str_split(.y, ",\\s*", simplify = TRUE)
      keys <- keys[keys != ""]
      count_duplicate_keys(tables[[.x]], keys)
    })
  )

write_csv(inventory, project_path("02_analysis", "output", "metadata", "table_inventory.csv"))

key_checks <- inventory |>
  dplyr::select("table_name", "layer", "primary_key", "duplicate_key_rows")

write_csv(key_checks, project_path("02_analysis", "output", "metadata", "key_checks.csv"))

message("Writing canonical, helper, and enrichment outputs to DuckDB and Parquet...")
con <- connect_duckdb()
on.exit(disconnect_duckdb(con), add = TRUE)

for (name in names(table_specs)) {
  spec <- table_specs[[name]]
  write_parquet_and_table(con, tables[[name]], name, spec$layer)
}

db_tables <- DBI::dbGetQuery(con, "SHOW TABLES")
write_csv(db_tables, project_path("02_analysis", "output", "metadata", "duckdb_tables.csv"))

message("Data foundation build complete.")
