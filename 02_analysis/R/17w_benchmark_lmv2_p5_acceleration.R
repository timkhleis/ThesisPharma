# Outcome-blind benchmark for P5 technology-cache acceleration.
#
# Reconstructs the real 2009/u1/deal-346 inputs and reports the redundant
# control-firm fan-out before running one legacy and one deduplicated SQL
# similarity query. It writes benchmark artifacts only below --out-dir.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(NA_character_)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

db_path <- normalizePath(read_arg("db"), mustWork = TRUE)
out_dir <- read_arg("out-dir")
threads_arg <- read_arg("threads", required = FALSE)
threads <- if (is.na(threads_arg)) 4L else as.integer(threads_arg)
if (is.na(threads) || threads < 1L) stop("--threads= must be a positive integer")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))

con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='4GB'")
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", threads))
DBI::dbExecute(con, "PRAGMA preserve_insertion_order=false")
DBI::dbExecute(con, sprintf("PRAGMA temp_directory='%s'",
                           normalizePath(out_dir, winslash = "/", mustWork = TRUE)))

g <- 2009L
deal_id <- 346L
build_universe_pools_and_scalers_and_edges(con, g)

all_treated_g <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT t.cohort, t.deal_id, CAST(t.target_group AS DOUBLE) AS id_group
  FROM lmv2_treated_primary t WHERE t.cohort=%d", g))
all_treated_g <- lmv2_left_join_checked(
  all_treated_g,
  DBI::dbGetQuery(con, sprintf(
    "SELECT cohort, id_group, log_patent_stock_5y, log_inventor_count_5y, patent_trajectory
     FROM h_firm_covars WHERE cohort=%d", g)),
  by = c("cohort", "id_group"), context = "benchmark treated x firm covariates",
  no_missing_cols = c("log_patent_stock_5y", "log_inventor_count_5y", "patent_trajectory"))

built <- build_universe_edges(con, g, "h_pool_u1", all_treated_g)
admissible <- lmv2_ebal_stage1_admissible_edges(built$edges, 2.0)
eligible <- DBI::dbGetQuery(con, sprintf(
  "SELECT cohort, codinv AS control_codinv, control_group FROM h_inv_latest
   WHERE cohort=%d AND control_group IN (%s)", g,
  paste(unique(admissible$control_group), collapse = ",")))

s2_vars <- LMV2_P3$stage_2$scalar_variables
recency_gap <- LMV2_P3$stage_2$maximum_recency_bin_gap
donor_base <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, codinv, career_first_year, last_pre_patent_year,
    LN(1+patent_count_5y) AS log_patent_count_5y,
    LN(1+patents_recent/2.0)-LN(1+patents_early/3.0) AS patent_trajectory,
    (cohort-1-career_first_year) AS career_age,
    CASE WHEN last_pre_patent_year=cohort-1 THEN 0
         WHEN last_pre_patent_year=cohort-2 THEN 1
         WHEN last_pre_patent_year=cohort-3 THEN 2
         WHEN last_pre_patent_year BETWEEN cohort-5 AND cohort-4 THEN 3
         ELSE NULL END AS recency_bin
  FROM lmv2_p3_inventor_cohort_stats WHERE cohort=%d AND codinv IN (%s)",
  g, paste(unique(eligible$control_codinv), collapse = ",")))
donor_raw <- merge(eligible, donor_base,
                   by.x = c("cohort", "control_codinv"),
                   by.y = c("cohort", "codinv"))
names(donor_raw)[names(donor_raw) == "control_group"] <- "focal_group"
names(donor_raw)[names(donor_raw) == "control_codinv"] <- "codinv"
focal <- lmv2_build_control_focal_covariates(
  con, donor_raw[c("cohort", "codinv", "focal_group")])
donor_raw <- merge(donor_raw, focal,
                   by = c("cohort", "codinv", "focal_group"), sort = FALSE)
donors <- donor_raw[stats::complete.cases(donor_raw[c(s2_vars, "recency_bin")]), ]
donor_cols <- donors
names(donor_cols)[names(donor_cols) == "codinv"] <- "control_codinv"
names(donor_cols)[names(donor_cols) == "focal_group"] <- "control_group"

treated <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, codinv, recency_bin, %s
  FROM lmv2_p3_treated_inventor_units WHERE cohort=%d",
  paste(s2_vars, collapse = ", "), g))
treated <- treated[stats::complete.cases(treated[c(s2_vars, "recency_bin")]), ]

admissible_d <- admissible[admissible$deal_id == deal_id, , drop = FALSE]
treated_d <- treated[treated$deal_id == deal_id, , drop = FALSE]
pool <- unique(admissible_d[c("cohort", "deal_id", "control_group")])
donor_pairs <- merge(
  pool,
  donor_cols[c("cohort", "control_codinv", "control_group", "recency_bin")],
  by = c("cohort", "control_group"))
names(donor_pairs)[names(donor_pairs) == "recency_bin"] <- "recency_bin_control"
donor_pairs <- donor_pairs[
  c("cohort", "deal_id", "control_codinv", "control_group", "recency_bin_control")]
donor_tech <- unique(donor_pairs[
  c("cohort", "deal_id", "control_codinv", "recency_bin_control")])

block_size <- lmv2_treated_block_size(length(unique(donor_pairs$control_codinv)))
block_ids <- sort(unique(treated_d$codinv))[seq_len(block_size)]
treated_block <- treated_d[
  treated_d$codinv %in% block_ids,
  c("cohort", "deal_id", "codinv", "recency_bin")]
names(treated_block) <- c("cohort", "deal_id", "treated_codinv", "recency_bin_treated")

stats <- data.frame(
  cohort = g,
  universe = "u1",
  deal_id = deal_id,
  n_treated_block = nrow(treated_block),
  donor_firm_rows = nrow(donor_pairs),
  unique_donor_rows = nrow(donor_tech),
  fanout_ratio = nrow(donor_pairs) / nrow(donor_tech),
  candidate_rows_legacy = nrow(treated_block) * nrow(donor_pairs),
  candidate_rows_deduplicated = nrow(treated_block) * nrow(donor_tech))
utils::write.csv(stats, file.path(out_dir, "deal346_fanout.csv"), row.names = FALSE)
print(stats)

vectors_path <- normalizePath(file.path(
  BASE, "output", "audit", "local_match_v2", "P4", "run2009",
  "disk_tech_cache", "cohort_2009", "ipc4_vectors.parquet"),
  winslash = "/", mustWork = TRUE)
norms_path <- normalizePath(file.path(
  BASE, "output", "audit", "local_match_v2", "P4", "run2009",
  "disk_tech_cache", "cohort_2009", "ipc4_norms.parquet"),
  winslash = "/", mustWork = TRUE)
expected_path <- normalizePath(file.path(
  BASE, "output", "audit", "local_match_v2", "P4", "run2009",
  "disk_tech_cache", "cohort_2009", "universe_u1",
  "tech_shard_deal346_block1.parquet"),
  winslash = "/", mustWork = TRUE)
optimized_path <- normalizePath(
  file.path(out_dir, "deal346_block1_sparse_join.parquet"),
  winslash = "/", mustWork = FALSE)
if (file.exists(optimized_path)) file.remove(optimized_path)

duckdb::duckdb_register(con, "bench_treated_block", treated_block)
duckdb::duckdb_register(con, "bench_donor_tech", donor_tech)
optimized_sql <- sprintf("
  WITH treated_vectors AS (
    SELECT t.cohort,t.treated_codinv,t.recency_bin_treated,
           v.ipc_feature,v.frequency
    FROM bench_treated_block t
    JOIN read_parquet('%s') v
      ON v.cohort=t.cohort AND v.codinv=t.treated_codinv
  ),
  control_vectors AS (
    SELECT d.cohort,d.control_codinv,d.recency_bin_control,
           v.ipc_feature,v.frequency
    FROM bench_donor_tech d
    JOIN read_parquet('%s') v
      ON v.cohort=d.cohort AND v.codinv=d.control_codinv
  ),
  dots AS (
    SELECT t.cohort,t.treated_codinv,c.control_codinv,
           SUM(t.frequency*c.frequency) AS dot
    FROM treated_vectors t
    JOIN control_vectors c
      ON c.cohort=t.cohort AND c.ipc_feature=t.ipc_feature
    WHERE t.recency_bin_treated IS NOT NULL
      AND c.recency_bin_control IS NOT NULL
      AND ABS(t.recency_bin_treated-c.recency_bin_control) <= %d
    GROUP BY t.cohort,t.treated_codinv,c.control_codinv
  )
  SELECT d.cohort,d.treated_codinv,d.control_codinv,TRUE AS shared_ipc4,
         CASE WHEN tn.norm>0 AND cn.norm>0
              THEN LEAST(1.0,GREATEST(0.0,d.dot/(tn.norm*cn.norm)))
              ELSE NULL END AS cosine
  FROM dots d
  LEFT JOIN read_parquet('%s') tn
    ON tn.cohort=d.cohort AND tn.codinv=d.treated_codinv
  LEFT JOIN read_parquet('%s') cn
    ON cn.cohort=d.cohort AND cn.codinv=d.control_codinv",
  vectors_path, vectors_path, recency_gap, norms_path, norms_path)

elapsed <- system.time(DBI::dbExecute(con, sprintf(
  "COPY (%s) TO '%s' (FORMAT PARQUET)", optimized_sql, optimized_path)))[["elapsed"]]
comparison <- DBI::dbGetQuery(con, sprintf("
  WITH expected AS (SELECT * FROM read_parquet('%s')),
       observed AS (SELECT * FROM read_parquet('%s'))
  SELECT
    (SELECT COUNT(*) FROM expected) AS expected_rows,
    (SELECT COUNT(*) FROM observed) AS observed_rows,
    (SELECT COUNT(*) FROM (
       SELECT e.cohort,e.treated_codinv,e.control_codinv
       FROM expected e ANTI JOIN observed o
         USING (cohort,treated_codinv,control_codinv))) AS missing_keys,
    (SELECT COUNT(*) FROM (
       SELECT o.cohort,o.treated_codinv,o.control_codinv
       FROM observed o ANTI JOIN expected e
         USING (cohort,treated_codinv,control_codinv))) AS extra_keys,
    (SELECT MAX(ABS(e.cosine-o.cosine))
       FROM expected e JOIN observed o
         USING (cohort,treated_codinv,control_codinv)) AS max_abs_cosine_diff",
  expected_path, optimized_path))
comparison$elapsed_seconds <- elapsed
comparison$duckdb_threads <- threads
utils::write.csv(comparison, file.path(out_dir, "deal346_sparse_join_benchmark.csv"),
                 row.names = FALSE)
print(comparison)
