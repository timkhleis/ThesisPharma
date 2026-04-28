source(file.path("analysis", "R", "00_utils.R"))

load_packages()

cat("Opening DuckDB...\n")
con <- tryCatch(
  connect_duckdb(read_only = TRUE),
  error = function(e) {
    stop(
      paste(
        "Could not open analysis/output/thesis_foundation.duckdb.",
        "It is probably already open in another R session, DuckDB session, or DB viewer.",
        "Close the other connection and run this script again.",
        "",
        "Original error:",
        conditionMessage(e)
      ),
      call. = FALSE
    )
  }
)
assign("thesis_con", con, envir = .GlobalEnv)

close_thesis_connection <- function() {
  if (exists("thesis_con", envir = .GlobalEnv, inherits = FALSE)) {
    con <- get("thesis_con", envir = .GlobalEnv, inherits = FALSE)
    if (DBI::dbIsValid(con)) {
      disconnect_duckdb(con)
      cat("\nDuckDB connection closed.\n")
    }
    rm("thesis_con", envir = .GlobalEnv)
  }
  invisible(NULL)
}

assign("close_thesis_connection", close_thesis_connection, envir = .GlobalEnv)

tables <- DBI::dbListTables(con)
assign("tables", tables, envir = .GlobalEnv)
cat("\nAvailable tables:\n")
print(tables)

get_thesis_connection <- function() {
  if (!exists("thesis_con", envir = .GlobalEnv, inherits = FALSE)) {
    stop(
      "No DuckDB connection found. Re-run source('analysis/R/zz_tim_working.r') first.",
      call. = FALSE
    )
  }

  con <- get("thesis_con", envir = .GlobalEnv, inherits = FALSE)
  if (!DBI::dbIsValid(con)) {
    stop(
      "The DuckDB connection is closed. Re-run source('analysis/R/zz_tim_working.r') to reopen it.",
      call. = FALSE
    )
  }

  con
}

load_table <- function(table_name, n = NULL) {
  stopifnot(is.character(table_name), length(table_name) == 1)

  con <- get_thesis_connection()

  if (!table_name %in% tables) {
    stop(sprintf("Table '%s' was not found in DuckDB.", table_name), call. = FALSE)
  }

  quoted_table <- as.character(DBI::dbQuoteIdentifier(con, table_name))
  sql <- if (is.null(n)) {
    sprintf("SELECT * FROM %s", quoted_table)
  } else {
    sprintf("SELECT * FROM %s LIMIT %d", quoted_table, as.integer(n))
  }

  DBI::dbGetQuery(con, sql)
}

inspect_table <- function(table_name, n = 1000L, open_viewer = interactive()) {
  df <- load_table(table_name, n = n)
  assign(table_name, df, envir = .GlobalEnv)

  cat(sprintf("\nLoaded '%s' into your Global Environment with %s rows.\n", table_name, nrow(df)))

  if (open_viewer && exists("View", mode = "function")) {
    View(df, title = table_name)
  }

  invisible(df)
}

table_schema <- function(table_name) {
  con <- get_thesis_connection()

  if (!table_name %in% tables) {
    stop(sprintf("Table '%s' was not found in DuckDB.", table_name), call. = FALSE)
  }

  schema <- DBI::dbGetQuery(
    con,
    sprintf("DESCRIBE %s", as.character(DBI::dbQuoteIdentifier(con, table_name)))
  )
  assign(paste0(table_name, "_schema"), schema, envir = .GlobalEnv)
  schema
}

database_overview <- function(open_viewer = interactive()) {
  con <- get_thesis_connection()

  overview <- lapply(tables, function(table_name) {
    n_rows <- DBI::dbGetQuery(
      con,
      sprintf("SELECT COUNT(*) AS n_rows FROM %s", as.character(DBI::dbQuoteIdentifier(con, table_name)))
    )$n_rows[[1]]

    schema <- DBI::dbGetQuery(
      con,
      sprintf("DESCRIBE %s", as.character(DBI::dbQuoteIdentifier(con, table_name)))
    )

    data.frame(
      table_name = table_name,
      n_rows = as.numeric(n_rows),
      n_cols = nrow(schema),
      first_columns = paste(utils::head(schema$column_name, 5), collapse = ", "),
      stringsAsFactors = FALSE
    )
  })

  overview <- do.call(rbind, overview)
  overview <- overview[order(-overview$n_rows, overview$table_name), ]
  row.names(overview) <- NULL

  assign("database_overview_df", overview, envir = .GlobalEnv)

  if (open_viewer && exists("View", mode = "function")) {
    View(overview, title = "database_overview_df")
  }

  overview
}

plot_table_sizes <- function() {
  overview <- database_overview(open_viewer = FALSE)
  op <- par(no.readonly = TRUE)
  on.exit(par(op), add = TRUE)

  par(mar = c(5, 12, 4, 2) + 0.1)
  graphics::barplot(
    rev(overview$n_rows),
    horiz = TRUE,
    las = 1,
    names.arg = rev(overview$table_name),
    col = "steelblue",
    main = "Rows per DuckDB Table",
    xlab = "Number of rows"
  )

  invisible(overview)
}

inventor_year_preview <- inspect_table("inventor_year", n = 20L, open_viewer = FALSE)
cat("\nPreview: inventor_year\n")
print(inventor_year_preview)

inventor_year_by_year <- DBI::dbGetQuery(
  con,
  "SELECT year, COUNT(*) AS n FROM inventor_year GROUP BY year ORDER BY year"
)
assign("inventor_year_by_year", inventor_year_by_year, envir = .GlobalEnv)
cat("\nCounts by year: inventor_year\n")
print(inventor_year_by_year)

patent_enriched_preview <- inspect_table("patent_enriched", n = 20L, open_viewer = FALSE)
cat("\nPreview: patent_enriched\n")
print(patent_enriched_preview)

database_overview_df <- database_overview(open_viewer = FALSE)
cat("\nDatabase overview:\n")
print(database_overview_df)

cat("\nInteractive inspection helpers now available:\n")
cat("- tables\n")
cat("- database_overview()\n")
cat("- plot_table_sizes()\n")
cat("- load_table('inventor_year', n = 100)\n")
cat("- inspect_table('inventor_year')\n")
cat("- table_schema('inventor_year')\n")
cat("- inspect_table('patent_enriched', n = 5000)\n")
cat("- close_thesis_connection()\n")
cat("\nObjects added to your Global Environment:\n")
cat("- thesis_con\n")
cat("- database_overview_df\n")
cat("- inventor_year\n")
cat("- patent_enriched\n")
cat("- inventor_year_by_year\n")
