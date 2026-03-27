project_path <- function(...) {
  file.path(normalizePath(getwd(), winslash = "/", mustWork = TRUE), ...)
}

local_library_path <- function() {
  project_path(".r_libs")
}

use_project_library <- function() {
  lib <- local_library_path()
  if (!dir.exists(lib)) {
    dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  }
  version_short <- paste(R.version$major, strsplit(R.version$minor, "\\.")[[1]][1], sep = ".")
  default_user_lib <- file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-library", version_short)
  base_paths <- unique(c(lib, default_user_lib, .Library.site, .Library, .libPaths()))
  .libPaths(base_paths)
  invisible(lib)
}

load_packages <- function() {
  use_project_library()
  packages <- c("DBI", "duckdb", "dplyr", "readr", "haven", "stringr", "purrr", "tidyr", "janitor")
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop(
      "Missing required packages: ",
      paste(missing, collapse = ", "),
      ". Install them into the project library before running the pipeline."
    )
  }
  invisible(packages)
}

ensure_output_dirs <- function() {
  dirs <- c(
    project_path("analysis", "output"),
    project_path("analysis", "output", "parquet"),
    project_path("analysis", "output", "parquet", "canonical"),
    project_path("analysis", "output", "parquet", "helper"),
    project_path("analysis", "output", "parquet", "enrichment"),
    project_path("analysis", "output", "parquet", "derived"),
    project_path("analysis", "output", "parquet", "audit"),
    project_path("analysis", "output", "metadata"),
    project_path("analysis", "output", "audit")
  )
  invisible(vapply(dirs, dir.create, logical(1), recursive = TRUE, showWarnings = FALSE))
}

clean_character_columns <- function(df) {
  char_cols <- names(df)[vapply(df, is.character, logical(1))]
  if (length(char_cols) == 0) {
    return(df)
  }
  df[char_cols] <- lapply(df[char_cols], function(x) {
    x <- stringr::str_squish(x)
    x[x == ""] <- NA_character_
    x
  })
  df
}

clean_table <- function(df) {
  df |>
    janitor::clean_names() |>
    tibble::as_tibble() |>
    clean_character_columns()
}

read_dta_table <- function(path) {
  haven::read_dta(path) |>
    clean_table()
}

read_csv_table <- function(path, delim = ",") {
  if (identical(delim, ",")) {
    readr::read_csv(path, show_col_types = FALSE, progress = FALSE) |>
      clean_table()
  } else {
    readr::read_delim(path, delim = delim, show_col_types = FALSE, progress = FALSE) |>
      clean_table()
  }
}

read_bvd_group_id <- function(path) {
  raw <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE, name_repair = "minimal")
  raw <- raw[, seq_len(min(2, ncol(raw)))]
  names(raw) <- c("id_group", "bvd_id")
  clean_table(raw)
}

duckdb_path <- function() {
  project_path("analysis", "output", "thesis_foundation.duckdb")
}

connect_duckdb <- function(read_only = FALSE) {
  duckdb_state$drv <- duckdb::duckdb()
  con <- DBI::dbConnect(duckdb_state$drv, duckdb_path(), read_only = read_only)
  try(DBI::dbExecute(con, "LOAD parquet;"), silent = TRUE)
  con
}

disconnect_duckdb <- function(con) {
  DBI::dbDisconnect(con, shutdown = TRUE)
  if (exists("drv", envir = duckdb_state, inherits = FALSE)) {
    rm("drv", envir = duckdb_state)
  }
}

normalize_path_sql <- function(path) {
  gsub("\\\\", "/", normalizePath(path, winslash = "/", mustWork = FALSE))
}

write_parquet_and_table <- function(con, df, table_name, parquet_subdir) {
  parquet_path <- project_path("analysis", "output", "parquet", parquet_subdir, paste0(table_name, ".parquet"))
  parquet_sql <- normalize_path_sql(parquet_path)
  quoted_table <- as.character(DBI::dbQuoteIdentifier(con, table_name))
  if (DBI::dbExistsTable(con, table_name)) {
    DBI::dbRemoveTable(con, table_name)
  }
  DBI::dbWriteTable(con, table_name, df, overwrite = TRUE)
  DBI::dbExecute(con, sprintf("COPY %s TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", quoted_table, parquet_sql))
  invisible(parquet_path)
}

create_table_inventory <- function(table_specs) {
  tibble::tibble(
    table_name = names(table_specs),
    layer = vapply(table_specs, `[[`, character(1), "layer"),
    source_path = vapply(table_specs, `[[`, character(1), "source_path"),
    grain = vapply(table_specs, `[[`, character(1), "grain"),
    primary_key = vapply(table_specs, function(x) paste(x$primary_key, collapse = ", "), character(1)),
    role = vapply(table_specs, `[[`, character(1), "role")
  )
}

count_duplicate_keys <- function(df, keys) {
  if (length(keys) == 0 || !all(keys %in% names(df))) {
    return(NA_integer_)
  }
  df |>
    dplyr::count(dplyr::across(dplyr::all_of(keys)), name = "n") |>
    dplyr::filter(.data$n > 1) |>
    nrow()
}

write_csv <- function(df, path) {
  readr::write_csv(df, path, na = "")
  invisible(path)
}
duckdb_state <- new.env(parent = emptyenv())
