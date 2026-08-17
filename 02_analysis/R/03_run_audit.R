source(file.path("analysis", "R", "00_utils.R"))

load_packages()
ensure_output_dirs()

con <- connect_duckdb()
on.exit(disconnect_duckdb(con), add = TRUE)

message("Loading tables for the disambiguation and data quality audit...")

patent_inventor <- DBI::dbReadTable(con, "patent_inventor")
inventor_year <- DBI::dbReadTable(con, "inventor_year")
inventor_group_year <- DBI::dbReadTable(con, "inventor_group_year")
inventor_ipc_year <- DBI::dbReadTable(con, "inventor_ipc_year")
group_year_status <- DBI::dbReadTable(con, "group_year_status")
patent_company_link <- DBI::dbReadTable(con, "patent_company_link")
inventor_production <- DBI::dbReadTable(con, "inventor_production")
group_production <- DBI::dbReadTable(con, "group_production")

message("Running duplicate bridge checks...")

duplicate_inventor_patent <- patent_inventor |>
  dplyr::count(.data$codinv, .data$appln_id, name = "n") |>
  dplyr::filter(.data$n > 1)

message("Running inventor-year outlier checks...")

patent_threshold <- max(10, stats::quantile(inventor_year$patent_count, probs = 0.995, na.rm = TRUE))
fractional_threshold <- max(5, stats::quantile(inventor_year$fractional_patent_count, probs = 0.995, na.rm = TRUE))

inventor_year_outliers <- inventor_year |>
  dplyr::filter(
    .data$patent_count >= patent_threshold |
      .data$fractional_patent_count >= fractional_threshold
  ) |>
  dplyr::mutate(
    audit_flag = dplyr::case_when(
      .data$patent_count >= patent_threshold & .data$fractional_patent_count >= fractional_threshold ~ "high_patent_and_fractional_output",
      .data$patent_count >= patent_threshold ~ "high_patent_output",
      TRUE ~ "high_fractional_output"
    )
  )

message("Running IPC breadth checks...")

inventor_ipc_breadth <- inventor_ipc_year |>
  dplyr::group_by(.data$codinv, .data$year) |>
  dplyr::summarise(
    ipc_code_count = dplyr::n_distinct(.data$ipc_code),
    ipc_patent_count = sum(.data$patent_count, na.rm = TRUE),
    .groups = "drop"
  )

ipc_breadth_threshold <- max(8, stats::quantile(inventor_ipc_breadth$ipc_code_count, probs = 0.995, na.rm = TRUE))

ipc_breadth_outliers <- inventor_ipc_breadth |>
  dplyr::filter(.data$ipc_code_count >= ipc_breadth_threshold) |>
  dplyr::mutate(audit_flag = "high_ipc_breadth")

message("Running mobility plausibility checks...")

multiple_groups_same_year <- inventor_group_year |>
  dplyr::filter(.data$group_count > 1) |>
  dplyr::mutate(audit_flag = "multiple_groups_same_year")

single_group_path <- inventor_group_year |>
  dplyr::filter(.data$group_count == 1) |>
  dplyr::mutate(primary_group = .data$group_list) |>
  dplyr::arrange(.data$codinv, .data$year) |>
  dplyr::group_by(.data$codinv) |>
  dplyr::mutate(
    previous_group = dplyr::lag(.data$primary_group),
    previous_year = dplyr::lag(.data$year),
    adjacent_switch = dplyr::if_else(
      !is.na(.data$previous_group) &
        (.data$year - .data$previous_year) <= 1 &
        .data$primary_group != .data$previous_group,
      1L,
      0L
    )
  ) |>
  dplyr::ungroup()

switch_counts <- single_group_path |>
  dplyr::group_by(.data$codinv) |>
  dplyr::summarise(adjacent_group_switches = sum(.data$adjacent_switch, na.rm = TRUE), .groups = "drop")

switch_threshold <- max(3, stats::quantile(switch_counts$adjacent_group_switches, probs = 0.995, na.rm = TRUE))

mobility_switch_outliers <- switch_counts |>
  dplyr::filter(.data$adjacent_group_switches >= switch_threshold) |>
  dplyr::mutate(audit_flag = "many_adjacent_group_switches")

message("Building merger-window review sample...")

merger_window_candidates <- inventor_group_year |>
  dplyr::filter(!is.na(.data$merger_status_values), !is.na(.data$year), !is.na(.data$group_list)) |>
  dplyr::rename(id_group_list = .data$group_list, merger_status = .data$merger_status_values)

set.seed(20260327)

merger_window_review_sample <- merger_window_candidates |>
  dplyr::arrange(.data$codinv, .data$year) |>
  dplyr::group_by(.data$codinv) |>
  dplyr::slice_head(n = 1) |>
  dplyr::ungroup() |>
  dplyr::slice_sample(n = min(25, dplyr::n()))

message("Comparing self-built aggregates to helper benchmark tables...")

inventor_compare <- inventor_year |>
  dplyr::select(.data$codinv, .data$year, self_patent = .data$patent_count, self_fract = .data$fractional_patent_count) |>
  dplyr::left_join(
    inventor_production |>
      dplyr::select(.data$codinv, .data$year, helper_patent = .data$patent, helper_fract = .data$fract),
    by = c("codinv", "year")
  ) |>
  dplyr::mutate(
    patent_diff = .data$self_patent - .data$helper_patent,
    fract_diff = .data$self_fract - .data$helper_fract
  )

group_year_rebuilt <- patent_company_link |>
  dplyr::filter(!is.na(.data$id_group), !is.na(.data$year)) |>
  dplyr::group_by(.data$id_group, .data$year) |>
  dplyr::summarise(self_patent = dplyr::n_distinct(.data$appln_id), .groups = "drop")

group_compare <- group_year_rebuilt |>
  dplyr::left_join(
    group_production |>
      dplyr::rename(helper_patent = .data$patent),
    by = c("id_group", "year")
  ) |>
  dplyr::mutate(patent_diff = .data$self_patent - .data$helper_patent)

audit_summary <- tibble::tibble(
  metric = c(
    "duplicate_inventor_patent_pairs",
    "inventor_year_output_outliers",
    "inventor_year_ipc_breadth_outliers",
    "inventor_year_multiple_groups_same_year",
    "inventor_many_adjacent_group_switches",
    "merger_window_review_sample_size",
    "inventor_helper_rows_compared",
    "inventor_helper_exact_patent_matches",
    "group_helper_rows_compared",
    "group_helper_exact_patent_matches",
    "group_year_status_rows"
  ),
  value = c(
    nrow(duplicate_inventor_patent),
    nrow(inventor_year_outliers),
    nrow(ipc_breadth_outliers),
    nrow(multiple_groups_same_year),
    nrow(mobility_switch_outliers),
    nrow(merger_window_review_sample),
    sum(!is.na(inventor_compare$helper_patent)),
    sum(inventor_compare$patent_diff == 0, na.rm = TRUE),
    sum(!is.na(group_compare$helper_patent)),
    sum(group_compare$patent_diff == 0, na.rm = TRUE),
    nrow(group_year_status)
  )
)

benchmark_summary <- tibble::tibble(
  table_name = c("inventor_compare", "group_compare"),
  mean_abs_patent_diff = c(
    mean(abs(inventor_compare$patent_diff), na.rm = TRUE),
    mean(abs(group_compare$patent_diff), na.rm = TRUE)
  ),
  max_abs_patent_diff = c(
    max(abs(inventor_compare$patent_diff), na.rm = TRUE),
    max(abs(group_compare$patent_diff), na.rm = TRUE)
  ),
  mean_abs_fractional_diff = c(
    mean(abs(inventor_compare$fract_diff), na.rm = TRUE),
    NA_real_
  )
)

write_parquet_and_table(con, duplicate_inventor_patent, "audit_duplicate_inventor_patent", "audit")
write_parquet_and_table(con, inventor_year_outliers, "audit_inventor_year_outliers", "audit")
write_parquet_and_table(con, ipc_breadth_outliers, "audit_ipc_breadth_outliers", "audit")
write_parquet_and_table(con, multiple_groups_same_year, "audit_multiple_groups_same_year", "audit")
write_parquet_and_table(con, mobility_switch_outliers, "audit_mobility_switch_outliers", "audit")
write_parquet_and_table(con, merger_window_review_sample, "audit_merger_window_review_sample", "audit")
write_parquet_and_table(con, inventor_compare, "audit_inventor_benchmark_compare", "audit")
write_parquet_and_table(con, group_compare, "audit_group_benchmark_compare", "audit")

write_csv(audit_summary, project_path("analysis", "output", "audit", "audit_summary.csv"))
write_csv(benchmark_summary, project_path("analysis", "output", "audit", "benchmark_summary.csv"))

summary_md <- c(
  "# Audit Summary",
  "",
  "The published inventor disambiguation is retained as the thesis baseline.",
  "These checks flag potential issues for manual review before treatment and mobility design.",
  "",
  "## Headline Metrics",
  ""
)

summary_md <- c(
  summary_md,
  paste0("- ", audit_summary$metric, ": ", audit_summary$value),
  "",
  "## Benchmark Comparison",
  "",
  paste0(
    "- ", benchmark_summary$table_name,
    " mean abs patent diff: ", round(benchmark_summary$mean_abs_patent_diff, 4),
    ", max abs patent diff: ", round(benchmark_summary$max_abs_patent_diff, 4)
  )
)

writeLines(summary_md, project_path("analysis", "output", "audit", "audit_summary.md"))

message("Audit build complete.")
