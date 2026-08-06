# Outcome-blind IPC4 granularity audit for the frozen primary weights.
#
# This does not change eligibility or weights. It measures how often the
# selected firm-pair technology cosine weakens at IPC main-group resolution.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit)
}

shared_lib <- normalizePath(
  file.path(getwd(), "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (package in c("DBI", "duckdb")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}

db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
production_root <- normalizePath(
  read_arg("production-root"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

comparison <- utils::read.csv(
  file.path(
    production_root, "finalized", "comparison_weight_manifest.csv"),
  stringsAsFactors = FALSE)
primary <- comparison[
  comparison$estimand == "primary_full_supported" &
    comparison$status == "complete",
  , drop = FALSE]
if (nrow(primary) != 17L) {
  stop("Expected 17 primary-full weight files")
}
sql_quote <- function(path) {
  paste0(
    "'", gsub("'", "''", normalizePath(
      path, winslash = "/", mustWork = TRUE)), "'")
}
weight_files <- paste(
  vapply(primary$path, sql_quote, character(1)), collapse = ",")

con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=4")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")

pair_detail <- DBI::dbGetQuery(con, sprintf("
  WITH weights AS (
    SELECT * FROM read_parquet([%s])
    WHERE treated = 0 AND final_weight > 0
  ), pair_weight AS (
    SELECT
      cohort, deal_id,
      CAST(target_group AS BIGINT) AS target_group,
      CAST(control_group AS BIGINT) AS control_group,
      SUM(final_weight) AS pair_weight
    FROM weights
    GROUP BY ALL
  ), similarities AS (
    SELECT
      cohort, deal_id, target_group, control_group,
      MAX(cosine) FILTER (WHERE resolution='ipc4') AS ipc4_cosine,
      MAX(cosine) FILTER (WHERE resolution='ipc_main_group')
        AS main_group_cosine
    FROM lmv2_p3_stage1_similarity
    WHERE resolution IN ('ipc4','ipc_main_group')
    GROUP BY ALL
  )
  SELECT
    p.*, s.ipc4_cosine, s.main_group_cosine,
    s.ipc4_cosine - s.main_group_cosine AS cosine_drop,
    CASE WHEN s.ipc4_cosine > 0
      THEN (s.ipc4_cosine-s.main_group_cosine)/s.ipc4_cosine
      ELSE NULL END AS relative_cosine_drop,
    (s.main_group_cosine < 0.5*s.ipc4_cosine)
      AS main_group_below_half_ipc4,
    ROW_NUMBER() OVER (
      PARTITION BY p.cohort,p.deal_id
      ORDER BY p.pair_weight DESC,p.control_group) AS donor_weight_rank
  FROM pair_weight p
  LEFT JOIN similarities s USING (
    cohort,deal_id,target_group,control_group)
  ORDER BY p.cohort,p.deal_id,donor_weight_rank", weight_files))

if (any(is.na(pair_detail$ipc4_cosine)) ||
    any(is.na(pair_detail$main_group_cosine))) {
  stop("A selected weighted firm pair lacks a frozen similarity value")
}

summarize_pairs <- function(x, label) {
  data.frame(
    diagnostic_sample = label,
    selected_firm_pairs = nrow(x),
    pair_weight = sum(x$pair_weight),
    weighted_mean_ipc4_cosine =
      weighted.mean(x$ipc4_cosine, x$pair_weight),
    weighted_mean_main_group_cosine =
      weighted.mean(x$main_group_cosine, x$pair_weight),
    weighted_mean_cosine_drop =
      weighted.mean(x$cosine_drop, x$pair_weight),
    weight_share_main_group_below_half_ipc4 =
      sum(x$pair_weight[x$main_group_below_half_ipc4]) /
      sum(x$pair_weight),
    median_relative_cosine_drop =
      stats::median(x$relative_cosine_drop, na.rm = TRUE),
    p90_relative_cosine_drop =
      as.numeric(stats::quantile(
        x$relative_cosine_drop, 0.90, na.rm = TRUE)),
    stringsAsFactors = FALSE)
}
summary <- rbind(
  summarize_pairs(pair_detail, "all_selected_weighted_firm_pairs"),
  summarize_pairs(
    pair_detail[pair_detail$donor_weight_rank == 1L, , drop = FALSE],
    "top_weight_donor_firm_per_deal"))

utils::write.csv(
  pair_detail,
  file.path(output_dir, "ipc4_main_group_selected_pair_detail.csv"),
  row.names = FALSE)
utils::write.csv(
  summary,
  file.path(output_dir, "ipc4_main_group_weighted_summary.csv"),
  row.names = FALSE)
utils::write.csv(
  data.frame(
    status = "diagnostic_only_primary_unchanged",
    primary_resolution = "ipc4",
    interpretation = paste(
      "IPC4 is the frozen support resolution. Main-group disaggregation",
      "measures coarseness among selected weighted firm pairs and does not",
      "delete Henkel or alter the primary roster."),
    stringsAsFactors = FALSE),
  file.path(output_dir, "ipc4_granularity_status.csv"),
  row.names = FALSE)
message(
  "IPC4 granularity audit complete | collapse weight share=",
  sprintf(
    "%.4f",
    summary$weight_share_main_group_below_half_ipc4[[1]]))
