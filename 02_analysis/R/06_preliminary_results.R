# Preliminary zero-filled stayer event panel and patent-output figures
#
# Run from project root after 04c:
#   Rscript 02_analysis/R/06_preliminary_results.R
#
# Outputs:
#   DuckDB table : stayer_event_panel_prelim
#   Parquet      : 02_analysis/output/parquet/derived/stayer_event_panel_prelim.parquet
#   Figures      : 02_analysis/output/figures/preliminary_results/
#   Tables       : 02_analysis/output/audit/preliminary_results/

BASE <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
DERIVED_PARQUET <- file.path(BASE, "output", "parquet", "derived")
FIGURES <- file.path(BASE, "output", "figures", "preliminary_results")
TABLES <- file.path(BASE, "output", "audit", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
load_packages()
library(duckdb)
library(ggplot2)

dir.create(DERIVED_PARQUET, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGURES, recursive = TRUE, showWarnings = FALSE)
dir.create(TABLES, recursive = TRUE, showWarnings = FALSE)

banner <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")

copy_to_parquet <- function(con, table_name, parquet_dir) {
  parquet_file <- file.path(parquet_dir, paste0(table_name, ".parquet"))
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
  utils::write.csv(df, file.path(TABLES, filename), row.names = FALSE, na = "")
}

plot_event_means <- function(df, y_col, y_label, output_file, split_col = NULL) {
  dodge <- if (is.null(split_col)) 0 else 0.25
  p <- ggplot(df, aes(x = event_time, y = .data[[y_col]]))
  if (is.null(split_col)) {
    p <- p +
      geom_ribbon(aes(ymin = .data[[paste0(y_col, "_ci_low")]],
                      ymax = .data[[paste0(y_col, "_ci_high")]]),
                  fill = "#d8e2dc", alpha = 0.9) +
      geom_line(color = "#1b4332", linewidth = 0.9) +
      geom_point(color = "#1b4332", size = 2)
  } else {
    p <- p +
      geom_errorbar(aes(
        ymin = .data[[paste0(y_col, "_ci_low")]],
        ymax = .data[[paste0(y_col, "_ci_high")]],
        color = .data[[split_col]]
      ), width = 0.12, position = position_dodge(width = dodge), alpha = 0.8) +
      geom_line(aes(color = .data[[split_col]]), linewidth = 0.9) +
      geom_point(aes(color = .data[[split_col]]), size = 2)
  }
  p <- p +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "grey40") +
    scale_x_continuous(breaks = -5:5) +
    labs(x = "Years relative to acquisition", y = y_label, color = NULL) +
    theme_minimal(base_size = 12) +
    theme(
      panel.grid.minor = element_blank(),
      legend.position = "bottom",
      plot.background = element_rect(fill = "white", color = NA)
    )
  ggsave(output_file, p, width = 7.2, height = 4.4, dpi = 300)
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB)
on.exit({ DBI::dbDisconnect(con, shutdown = TRUE) }, add = TRUE)

banner("PRELIMINARY RESULTS")

required_tables <- c("inventor_status_own", "inventor_year", "cassi_deal_spine")
missing_tables <- required_tables[!vapply(required_tables, DBI::dbExistsTable, logical(1), conn = con)]
if (length(missing_tables) > 0) {
  stop("Missing required DuckDB tables: ", paste(missing_tables, collapse = ", "),
       ". Run 04c_build_prelim_own_status.R first.")
}

section("Building balanced zero-filled event panel")

DBI::dbExecute(con, "
CREATE OR REPLACE TABLE stayer_event_panel_prelim AS
WITH event_grid AS (
  SELECT -5 AS event_time UNION ALL
  SELECT -4 UNION ALL
  SELECT -3 UNION ALL
  SELECT -2 UNION ALL
  SELECT -1 UNION ALL
  SELECT 0 UNION ALL
  SELECT 1 UNION ALL
  SELECT 2 UNION ALL
  SELECT 3 UNION ALL
  SELECT 4 UNION ALL
  SELECT 5
),
stayers AS (
  SELECT *
  FROM inventor_status_own
  WHERE type = 'T_STAYER'
    AND deal_year BETWEEN 1981 AND 2011
),
inventor_year_one AS (
  SELECT
    codinv,
    year,
    MAX(patent_count) AS patent_count,
    MAX(fractional_patent_count) AS fractional_patent_count
  FROM inventor_year
  GROUP BY codinv, year
),
panel AS (
  SELECT
    s.codinv,
    s.cassi_deal_row_id,
    s.dealnumber,
    s.deal_year,
    s.deal_value,
    s.target_group,
    s.acquirer_group,
    s.big_deal,
    CASE WHEN s.big_deal THEN 'Big deals' ELSE 'Small deals' END AS deal_size_group,
    eg.event_time,
    s.deal_year + eg.event_time AS year
  FROM stayers s
  CROSS JOIN event_grid eg
)
SELECT
  p.codinv,
  p.cassi_deal_row_id,
  p.dealnumber,
  p.deal_year,
  p.deal_value,
  p.target_group,
  p.acquirer_group,
  p.big_deal,
  p.deal_size_group,
  p.event_time,
  p.year,
  COALESCE(iy.patent_count, 0) AS patent_count,
  COALESCE(iy.fractional_patent_count, 0) AS fractional_patent_count,
  CASE WHEN iy.codinv IS NULL THEN TRUE ELSE FALSE END AS zero_filled_row
FROM panel p
LEFT JOIN inventor_year_one iy
  ON p.codinv = iy.codinv
 AND p.year = iy.year
")

panel_path <- copy_to_parquet(con, "stayer_event_panel_prelim", DERIVED_PARQUET)
message("Written: ", panel_path)

section("Computing sample and event-time tables")

sample_table <- DBI::dbGetQuery(con, "
WITH target_side AS (
  SELECT COUNT(*) AS n_target_side_inventors
  FROM inventor_status_own
),
status_counts AS (
  SELECT
    SUM(CASE WHEN type = 'T_STAYER' THEN 1 ELSE 0 END) AS n_t_stayer,
    SUM(CASE WHEN type = 'T_LEAVER' THEN 1 ELSE 0 END) AS n_t_leaver
  FROM inventor_status_own
),
panel_counts AS (
  SELECT
    COUNT(DISTINCT cassi_deal_row_id) AS n_deals_in_event_panel,
    COUNT(DISTINCT codinv) AS n_stayer_inventors,
    COUNT(*) AS n_event_panel_rows,
    AVG(CASE WHEN zero_filled_row THEN 1.0 ELSE 0.0 END) AS share_zero_filled_rows
  FROM stayer_event_panel_prelim
)
SELECT
  (SELECT COUNT(DISTINCT cassi_deal_row_id) FROM cassi_deal_spine) AS n_deal_rows_in_spine,
  pc.n_deals_in_event_panel,
  ts.n_target_side_inventors,
  sc.n_t_stayer,
  sc.n_t_leaver,
  pc.n_event_panel_rows,
  pc.share_zero_filled_rows
FROM target_side ts
CROSS JOIN status_counts sc
CROSS JOIN panel_counts pc
")

event_counts <- DBI::dbGetQuery(con, "
SELECT
  event_time,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT codinv) AS n_inventors,
  COUNT(DISTINCT cassi_deal_row_id) AS n_deals,
  AVG(CASE WHEN zero_filled_row THEN 1.0 ELSE 0.0 END) AS share_zero_filled
FROM stayer_event_panel_prelim
GROUP BY event_time
ORDER BY event_time
")

event_means <- DBI::dbGetQuery(con, "
SELECT
  event_time,
  COUNT(*) AS n_rows,
  AVG(patent_count) AS patent_count_mean,
  STDDEV_SAMP(patent_count) / SQRT(COUNT(*)) AS patent_count_se,
  AVG(patent_count) - 1.96 * STDDEV_SAMP(patent_count) / SQRT(COUNT(*)) AS patent_count_mean_ci_low,
  AVG(patent_count) + 1.96 * STDDEV_SAMP(patent_count) / SQRT(COUNT(*)) AS patent_count_mean_ci_high,
  AVG(fractional_patent_count) AS fractional_patent_count_mean,
  STDDEV_SAMP(fractional_patent_count) / SQRT(COUNT(*)) AS fractional_patent_count_se,
  AVG(fractional_patent_count) - 1.96 * STDDEV_SAMP(fractional_patent_count) / SQRT(COUNT(*)) AS fractional_patent_count_mean_ci_low,
  AVG(fractional_patent_count) + 1.96 * STDDEV_SAMP(fractional_patent_count) / SQRT(COUNT(*)) AS fractional_patent_count_mean_ci_high
FROM stayer_event_panel_prelim
GROUP BY event_time
ORDER BY event_time
")

big_small_means <- DBI::dbGetQuery(con, "
SELECT
  deal_size_group,
  event_time,
  COUNT(*) AS n_rows,
  AVG(patent_count) AS patent_count_mean,
  AVG(patent_count) - 1.96 * STDDEV_SAMP(patent_count) / SQRT(COUNT(*)) AS patent_count_mean_ci_low,
  AVG(patent_count) + 1.96 * STDDEV_SAMP(patent_count) / SQRT(COUNT(*)) AS patent_count_mean_ci_high
FROM stayer_event_panel_prelim
GROUP BY deal_size_group, event_time
ORDER BY deal_size_group, event_time
")

write_csv_base(sample_table, "sample_construction_table.csv")
write_csv_base(event_counts, "event_time_counts.csv")
write_csv_base(event_means, "event_time_means.csv")
write_csv_base(big_small_means, "event_time_means_big_small.csv")

section("Writing figures")

plot_event_means(
  event_means,
  "patent_count_mean",
  "Mean patent count",
  file.path(FIGURES, "event_mean_patent_count.png")
)

plot_event_means(
  event_means,
  "fractional_patent_count_mean",
  "Mean fractional patent count",
  file.path(FIGURES, "event_mean_fractional_patent_count.png")
)

plot_event_means(
  big_small_means,
  "patent_count_mean",
  "Mean patent count",
  file.path(FIGURES, "event_mean_patent_count_big_small.png"),
  split_col = "deal_size_group"
)

section("Sanity checks")

sanity <- DBI::dbGetQuery(con, "
WITH counts AS (
  SELECT event_time, COUNT(*) AS n_rows
  FROM stayer_event_panel_prelim
  GROUP BY event_time
)
SELECT
  (SELECT n_rows FROM counts WHERE event_time = -1) AS n_event_minus_1,
  (SELECT n_rows FROM counts WHERE event_time = 0) AS n_event_0,
  CAST((SELECT n_rows FROM counts WHERE event_time = 0) AS DOUBLE)
    / NULLIF((SELECT n_rows FROM counts WHERE event_time = -1), 0) AS event_0_to_minus_1_ratio,
  (SELECT AVG(CASE WHEN zero_filled_row THEN 1.0 ELSE 0.0 END)
   FROM stayer_event_panel_prelim) AS share_zero_filled_rows,
  (SELECT MAX(n_by_deal) FROM (
     SELECT cassi_deal_row_id, COUNT(DISTINCT codinv) AS n_by_deal
     FROM stayer_event_panel_prelim
     GROUP BY cassi_deal_row_id
   )) AS largest_deal_stayer_count
")

validation_note <- data.frame(
  note = c(
    "Preliminary results use first reconstruction from Cassi's new deal/group-history files.",
    "Classification is restricted to target-side T_STAYER/T_LEAVER; full CS(2021), TechDrift, DealSim, financial controls, and robustness are deferred.",
    "Event panel is balanced over event times -5 to +5 and fills missing inventor_year rows with zero patent output."
  )
)

write_csv_base(sanity, "sanity_checks.csv")
write_csv_base(validation_note, "validation_note.csv")

slide_outline <- c(
  "# Preliminary Results Slide Outline",
  "",
  "## Slide 1: Data and Classification Spine",
  "- New Cassi files used: `L_merge.dta` and `L_group_history_target.dta`.",
  "- First own reconstruction classifies target-side inventors as `T_STAYER` if they appear with the acquirer group within five post-deal years; otherwise `T_LEAVER`.",
  "- Validation against Cassi-Ornaghi reference remains imperfect and is a next-step priority.",
  "",
  "## Slide 2: Preliminary Event-Study Patterns",
  "- Show `event_mean_patent_count.png` and `event_mean_fractional_patent_count.png`.",
  "- The panel is balanced over event times -5 to +5 for cohorts with a fully observable window.",
  "- Missing inventor-year patent observations are filled as zero patent output.",
  "",
  "## Slide 3: Caveats and Next Steps",
  "- Caveat: Preliminary results use my first reconstruction from Cassi's new deal/group-history files; final thesis estimates will refine classification and use CS(2021).",
  "- Next: diagnose classification mismatches, add quality outcomes, build TechDrift and DealSim, then move to the not-yet-treated CS(2021) design."
)
writeLines(slide_outline, file.path(TABLES, "preliminary_slide_outline.md"), useBytes = TRUE)

print(sample_table)
print(event_counts)
print(sanity)

message("\n", strrep("=", 60))
message("Preliminary results complete.")
message("Figures: ", FIGURES)
message("Tables : ", TABLES)
message(strrep("=", 60), "\n")
