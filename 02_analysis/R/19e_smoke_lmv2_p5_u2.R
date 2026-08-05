# Database-backed, outcome-free smoke test of the P5.1 U2 implementation.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "19a_lmv2_p5_rescue_config.R"))

db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=2")
DBI::dbExecute(con, "SET memory_limit='6GB'")

g <- 2000L
build_universe_pools_and_scalers_and_edges(con, g)
pool_counts <- DBI::dbGetQuery(con, "
  SELECT 'u1' universe, COUNT(*) n_firms FROM h_pool_u1
  UNION ALL
  SELECT 'u2', COUNT(*) FROM h_pool_u2
  UNION ALL
  SELECT 'u3', COUNT(*) FROM h_pool_u3
  ORDER BY universe")
if (pool_counts$n_firms[pool_counts$universe == "u2"] <=
    pool_counts$n_firms[pool_counts$universe == "u1"]) {
  stop("U2 did not expand U1 in cohort 2000")
}

all_treated <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT t.cohort,t.deal_id,
         CAST(t.target_group AS DOUBLE) id_group,
         f.log_patent_stock_5y,f.log_inventor_count_5y,
         f.patent_trajectory
  FROM lmv2_treated_primary t
  JOIN h_firm_covars f
    ON f.cohort=t.cohort
   AND CAST(f.id_group AS BIGINT)=CAST(t.target_group AS BIGINT)
  WHERE t.cohort=%d", g))

stage1_rows <- list()
for (u in c("u1", "u2")) {
  pool_tbl <- paste0("h_pool_", u)
  built <- build_universe_edges(
    con, g, pool_tbl, all_treated)
  admissible <- lmv2_ebal_stage1_admissible_edges(
    built$edges, LMV2_P5_RESCUE$selected$stage1_caliper)
  admissible <- lmv2_ebal_nearest_within_caliper(
    admissible, 50L)
  per_deal <- stats::aggregate(
    control_group ~ cohort + deal_id,
    data = unique(admissible[c(
      "cohort", "deal_id", "control_group")]),
    FUN = length
  )
  names(per_deal)[names(per_deal) == "control_group"] <-
    "n_eligible_firms"
  supported_deals <- per_deal$deal_id[
    per_deal$n_eligible_firms >= MIN_ELIGIBLE_FIRMS]
  stage1_rows[[u]] <- data.frame(
    universe = u,
    n_raw_edges = nrow(built$edges),
    n_admissible_edges = nrow(admissible),
    n_full_deals = length(unique(all_treated$deal_id)),
    n_supported_deals = length(unique(supported_deals)),
    median_eligible_firms = stats::median(
      per_deal$n_eligible_firms),
    max_eligible_firms = max(per_deal$n_eligible_firms),
    stringsAsFactors = FALSE
  )
}
stage1 <- do.call(rbind, stage1_rows)
utils::write.csv(
  pool_counts, file.path(output_dir, "u2_pool_counts.csv"),
  row.names = FALSE)
utils::write.csv(
  stage1, file.path(output_dir, "u2_stage1_smoke.csv"),
  row.names = FALSE)
utils::write.csv(
  data.frame(
    version = LMV2_P5_RESCUE_VERSION,
    amendment_hash = LMV2_P5_RESCUE_AMENDMENT_SHA256,
    database = db_path,
    cohort = g,
    status = "pass",
    timestamp = as.character(Sys.time()),
    stringsAsFactors = FALSE
  ),
  file.path(output_dir, "u2_smoke_manifest.csv"),
  row.names = FALSE
)
message("P5.1 U2 database-backed smoke test PASS")
