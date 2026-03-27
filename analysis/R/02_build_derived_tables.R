source(file.path("analysis", "R", "00_utils.R"))

load_packages()
ensure_output_dirs()

message("Opening DuckDB and loading canonical tables...")
con <- connect_duckdb()
on.exit(disconnect_duckdb(con), add = TRUE)

inventor <- DBI::dbReadTable(con, "inventor")
patent <- DBI::dbReadTable(con, "patent")
patent_inventor <- DBI::dbReadTable(con, "patent_inventor")
ipc <- DBI::dbReadTable(con, "ipc")
group_tbl <- DBI::dbReadTable(con, "group")
firm <- DBI::dbReadTable(con, "firm")
firm_group <- DBI::dbReadTable(con, "firm_group")
bvd_group_id <- DBI::dbReadTable(con, "bvd_group_id")
oecd_quality <- DBI::dbReadTable(con, "oecd_quality")
group_production <- DBI::dbReadTable(con, "group_production")

message("Building patent-level enrichments...")

inventor_counts <- patent_inventor |>
  dplyr::count(.data$appln_id, name = "inventor_count")

ipc_counts <- ipc |>
  dplyr::count(.data$appln_id, name = "ipc_code_count")

group_year_status <- firm_group |>
  dplyr::group_by(.data$id_group, .data$year) |>
  dplyr::summarise(
    firms_in_group = dplyr::n_distinct(.data$compcod),
    merger_status_values = paste(sort(unique(stats::na.omit(.data$merger_status))), collapse = ";"),
    .groups = "drop"
  ) |>
  dplyr::left_join(group_tbl, by = "id_group") |>
  dplyr::left_join(bvd_group_id, by = "id_group") |>
  dplyr::left_join(group_production, by = c("id_group", "year"), suffix = c("", "_helper"))

patent_enriched <- patent |>
  dplyr::left_join(firm, by = "compcod") |>
  dplyr::left_join(firm_group, by = c("compcod", "year")) |>
  dplyr::left_join(group_tbl, by = "id_group") |>
  dplyr::left_join(bvd_group_id, by = "id_group") |>
  dplyr::left_join(oecd_quality, by = "appln_id") |>
  dplyr::left_join(ipc_counts, by = "appln_id") |>
  dplyr::left_join(inventor_counts, by = "appln_id")

patent_inventor_enriched <- patent_inventor |>
  dplyr::left_join(patent_enriched, by = "appln_id") |>
  dplyr::left_join(inventor, by = "codinv")

message("Building inventor-year and IPC inputs...")

inventor_year <- patent_inventor_enriched |>
  dplyr::group_by(.data$codinv, .data$year) |>
  dplyr::summarise(
    patent_count = dplyr::n_distinct(.data$appln_id),
    fractional_patent_count = sum(1 / .data$inventor_count, na.rm = TRUE),
    distinct_firm_count = dplyr::n_distinct(stats::na.omit(.data$compcod)),
    distinct_group_count = dplyr::n_distinct(stats::na.omit(.data$id_group)),
    first_patent_year = min(.data$year, na.rm = TRUE),
    last_patent_year = max(.data$year, na.rm = TRUE),
    inventor_country = dplyr::first(stats::na.omit(.data$incy)),
    inventor_name = dplyr::first(stats::na.omit(.data$inname)),
    .groups = "drop"
  ) |>
  dplyr::arrange(.data$codinv, .data$year) |>
  dplyr::group_by(.data$codinv) |>
  dplyr::mutate(
    career_first_year = min(.data$year, na.rm = TRUE),
    career_last_year = max(.data$year, na.rm = TRUE),
    career_year_index = .data$year - career_first_year + 1L
  ) |>
  dplyr::ungroup()

inventor_group_year <- patent_inventor_enriched |>
  dplyr::filter(!is.na(.data$id_group)) |>
  dplyr::group_by(.data$codinv, .data$year) |>
  dplyr::summarise(
    group_count = dplyr::n_distinct(.data$id_group),
    firm_count = dplyr::n_distinct(.data$compcod),
    group_list = paste(sort(unique(.data$id_group)), collapse = ";"),
    merger_status_values = paste(sort(unique(stats::na.omit(.data$merger_status))), collapse = ";"),
    .groups = "drop"
  )

inventor_ipc_year <- patent_inventor |>
  dplyr::left_join(inventor_counts, by = "appln_id") |>
  dplyr::left_join(patent |> dplyr::select(.data$appln_id, .data$year, .data$compcod), by = "appln_id") |>
  dplyr::left_join(firm_group |> dplyr::select(.data$compcod, .data$year, .data$id_group), by = c("compcod", "year")) |>
  dplyr::left_join(ipc, by = "appln_id") |>
  dplyr::filter(!is.na(.data$ipc_code), !is.na(.data$year)) |>
  dplyr::group_by(.data$codinv, .data$year, .data$ipc_code) |>
  dplyr::summarise(
    patent_count = dplyr::n_distinct(.data$appln_id),
    fractional_patent_count = sum(1 / .data$inventor_count, na.rm = TRUE),
    distinct_group_count = dplyr::n_distinct(stats::na.omit(.data$id_group)),
    .groups = "drop"
  )

group_ipc_year <- patent |>
  dplyr::left_join(firm_group |> dplyr::select(.data$compcod, .data$year, .data$id_group), by = c("compcod", "year")) |>
  dplyr::left_join(ipc, by = "appln_id") |>
  dplyr::filter(!is.na(.data$id_group), !is.na(.data$ipc_code)) |>
  dplyr::group_by(.data$id_group, .data$year, .data$ipc_code) |>
  dplyr::summarise(
    patent_count = dplyr::n_distinct(.data$appln_id),
    .groups = "drop"
  )

derived_tables <- list(
  patent_enriched = patent_enriched,
  patent_inventor_enriched = patent_inventor_enriched,
  group_year_status = group_year_status,
  inventor_year = inventor_year,
  inventor_group_year = inventor_group_year,
  inventor_ipc_year = inventor_ipc_year,
  group_ipc_year = group_ipc_year
)

message("Writing derived tables...")
for (name in names(derived_tables)) {
  write_parquet_and_table(con, derived_tables[[name]], name, "derived")
}

derived_inventory <- tibble::tibble(
  table_name = names(derived_tables),
  n_rows = purrr::map_int(derived_tables, nrow),
  n_cols = purrr::map_int(derived_tables, ncol)
) |>
  dplyr::arrange(.data$table_name)

write_csv(derived_inventory, project_path("analysis", "output", "metadata", "derived_inventory.csv"))

message("Derived table build complete.")
