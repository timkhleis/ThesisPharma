# Import new Cassi deal/group-history files
#
# Run from project root:
#   Rscript 02_analysis/R/04b_import_cassi_deal_files.R
#
# Outputs:
#   DuckDB tables : cassi_group_history_target, cassi_merge, cassi_financial_all
#   Parquet       : 02_analysis/output/parquet/helper/
#   Audit CSVs    : 02_analysis/output/audit/cassi_new_files/

BASE <- normalizePath("02_analysis", mustWork = TRUE)
DATA <- normalizePath("01_Data", mustWork = TRUE)
DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
PARQUET <- file.path(BASE, "output", "parquet", "helper")
AUDIT <- file.path(BASE, "output", "audit", "cassi_new_files")

source(file.path(BASE, "R", "00_utils.R"))
load_packages()
library(duckdb)

dir.create(PARQUET, recursive = TRUE, showWarnings = FALSE)
dir.create(AUDIT, recursive = TRUE, showWarnings = FALSE)

banner <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")

write_table_parquet <- function(con, df, table_name) {
  DBI::dbWriteTable(con, table_name, df, overwrite = TRUE)
  parquet_file <- file.path(PARQUET, paste0(table_name, ".parquet"))
  parquet_sql <- gsub("\\\\", "/", parquet_file)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY %s TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
      DBI::dbQuoteIdentifier(con, table_name),
      parquet_sql
    )
  )
  parquet_file
}

write_csv_base <- function(df, filename) {
  utils::write.csv(df, file.path(AUDIT, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB)
on.exit({ DBI::dbDisconnect(con, shutdown = TRUE) }, add = TRUE)

banner("IMPORT NEW CASSI DEAL FILES")

files <- list(
  cassi_group_history_target = file.path(DATA, "L_group_history_target.dta"),
  cassi_merge = file.path(DATA, "L_merge.dta"),
  cassi_financial_all = file.path(DATA, "BvD_financial_all.dta")
)

tables <- lapply(files, read_dta_table)

section("Writing DuckDB tables and helper Parquet")
for (nm in names(tables)) {
  message(nm, ": ", format(nrow(tables[[nm]]), big.mark = ","), " rows, ",
          ncol(tables[[nm]]), " columns")
  path <- write_table_parquet(con, tables[[nm]], nm)
  message("  wrote ", path)
}

section("Writing audit summaries")

group_history <- tables$cassi_group_history_target
merge <- tables$cassi_merge
financial <- tables$cassi_financial_all

group_history_summary <- dplyr::summarise(
  group_history,
  n_rows = dplyr::n(),
  n_compcod = dplyr::n_distinct(.data$compcod),
  n_groups = dplyr::n_distinct(.data$id_group),
  min_year = min(.data$year, na.rm = TRUE),
  max_year = max(.data$year, na.rm = TRUE),
  n_target_rows = sum(.data$merger_status == "target", na.rm = TRUE),
  n_divestment_rows = sum(.data$merger_status == "divestment", na.rm = TRUE),
  n_nonempty_merger_nmb = sum(!is.na(.data$merger_nmb) & .data$merger_nmb != ""),
  n_distinct_merger_nmb = dplyr::n_distinct(.data$merger_nmb[!is.na(.data$merger_nmb) & .data$merger_nmb != ""])
)

merge_summary <- dplyr::summarise(
  merge,
  n_rows = dplyr::n(),
  n_dealnumber = dplyr::n_distinct(.data$dealnumber),
  n_target_compcod = dplyr::n_distinct(.data$compcod_target, na.rm = TRUE),
  n_acquirer_compcod = dplyr::n_distinct(.data$compcod_acquirer, na.rm = TRUE),
  min_year_merge = min(.data$year_merge, na.rm = TRUE),
  max_year_merge = max(.data$year_merge, na.rm = TRUE),
  n_value_nonmissing = sum(!is.na(.data$value)),
  n_keep_rows = sum(is.na(.data$todrop_acq) & is.na(.data$todrop_tar) & is.na(.data$divest))
)

financial_summary <- dplyr::summarise(
  financial,
  n_rows = dplyr::n(),
  n_groups = dplyr::n_distinct(.data$id_group, na.rm = TRUE),
  n_dealnumber = dplyr::n_distinct(.data$dealnumber),
  n_company = dplyr::n_distinct(.data$company)
)

merge_link_summary <- dplyr::summarise(
  dplyr::filter(group_history, .data$merger_status == "target"),
  n_target_rows = dplyr::n(),
  n_target_merger_nmb = dplyr::n_distinct(.data$merger_nmb),
  n_target_merger_nmb_in_l_merge = sum(unique(.data$merger_nmb) %in% merge$dealnumber)
)

write_csv_base(group_history_summary, "group_history_summary.csv")
write_csv_base(merge_summary, "merge_summary.csv")
write_csv_base(financial_summary, "financial_summary.csv")
write_csv_base(merge_link_summary, "merge_link_summary.csv")
write_csv_base(dplyr::count(group_history, .data$merger_status, sort = TRUE),
               "group_history_merger_status_counts.csv")
write_csv_base(dplyr::count(merge, .data$divest, .data$todrop_acq, .data$todrop_tar, sort = TRUE),
               "merge_drop_flag_counts.csv")

print(group_history_summary)
print(merge_summary)
print(financial_summary)
print(merge_link_summary)

message("\n", strrep("=", 60))
message("New Cassi files imported. Financial file is available but not used in preliminary results.")
message(strrep("=", 60), "\n")
