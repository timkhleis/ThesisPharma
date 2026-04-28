source(file.path("analysis", "R", "00_utils.R"))

load_packages()

args <- commandArgs(trailingOnly = TRUE)

default_tables <- c(
  "inventor_year",
  "inventor_group_year",
  "group_year_status",
  "patent_enriched"
)

preview_tables <- if (length(args) > 0) args else default_tables

preview_n <- 10L

cat_line <- function(...) {
  cat(..., "\n", sep = "")
}

print_section <- function(title) {
  cat_line("")
  cat_line(strrep("=", nchar(title)))
  cat_line(title)
  cat_line(strrep("=", nchar(title)))
}

preview_table <- function(con, table_name, n = 10L) {
  if (!DBI::dbExistsTable(con, table_name)) {
    cat_line("")
    cat_line("Skipping missing table: ", table_name)
    return(invisible(NULL))
  }

  print_section(paste("Table:", table_name))

  row_count <- DBI::dbGetQuery(
    con,
    sprintf("SELECT COUNT(*) AS n_rows FROM %s", DBI::dbQuoteIdentifier(con, table_name))
  )
  print(row_count)

  cat_line("")
  cat_line("Schema")
  schema <- DBI::dbGetQuery(
    con,
    sprintf("DESCRIBE %s", DBI::dbQuoteIdentifier(con, table_name))
  )
  print(schema)

  cat_line("")
  cat_line("Preview")
  preview <- DBI::dbGetQuery(
    con,
    sprintf("SELECT * FROM %s LIMIT %d", DBI::dbQuoteIdentifier(con, table_name), as.integer(n))
  )
  print(preview)
  invisible(NULL)
}

print_section("DuckDB Database")
cat_line("Path: ", duckdb_path())

con <- connect_duckdb(read_only = TRUE)
on.exit(disconnect_duckdb(con), add = TRUE)

tables <- DBI::dbListTables(con)

print_section("Available Tables")
print(data.frame(table_name = tables))

print_section("Metadata Files")
metadata_files <- c(
  project_path("analysis", "output", "metadata", "table_inventory.csv"),
  project_path("analysis", "output", "metadata", "derived_inventory.csv"),
  project_path("analysis", "output", "metadata", "key_checks.csv"),
  project_path("analysis", "output", "metadata", "duckdb_tables.csv")
)
print(data.frame(path = metadata_files, exists = file.exists(metadata_files)))

for (table_name in preview_tables) {
  preview_table(con, table_name, n = preview_n)
}

cat_line("")
cat_line("Inspection complete.")
