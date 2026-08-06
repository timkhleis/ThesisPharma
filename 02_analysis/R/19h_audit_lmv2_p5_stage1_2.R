# Outcome-blind clean-U2 Stage-1 support diagnostic at caliper 2.0.

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

con <- DBI::dbConnect(
  duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=2")
DBI::dbExecute(con, "SET memory_limit='6GB'")

g <- 2000L
build_universe_pools_and_scalers_and_edges(con, g)
treated_targets <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT t.cohort,t.deal_id,
         CAST(t.target_group AS DOUBLE) id_group,
         f.log_patent_stock_5y,f.log_inventor_count_5y,
         f.patent_trajectory
  FROM lmv2_treated_primary t
  JOIN h_firm_covars f
    ON f.cohort=t.cohort
   AND CAST(f.id_group AS BIGINT)=CAST(t.target_group AS BIGINT)
  WHERE t.cohort=%d", g))
u2 <- build_universe_edges(
  con, g, "h_pool_u2", treated_targets)

firm_sets <- lapply(c(1.5, 2.0), function(stage1_caliper) {
  admissible <- lmv2_ebal_stage1_admissible_edges(
    u2$edges, stage1_caliper)
  admissible <- lmv2_ebal_nearest_within_caliper(
    admissible, 50L)
  out <- unique(admissible[
    c("cohort", "deal_id", "control_group", "distance")])
  out$stage1_caliper <- stage1_caliper
  out
})
firm_edges <- do.call(rbind, firm_sets)
firm_covariates <- DBI::dbGetQuery(con, "
  SELECT cohort,CAST(id_group AS DOUBLE) control_group,
         log_patent_stock_5y,log_inventor_count_5y,
         patent_trajectory
  FROM h_firm_covars")
firm_edges <- merge(
  firm_edges, firm_covariates,
  by = c("cohort", "control_group"), all.x = TRUE)

per_deal <- stats::aggregate(
  control_group ~ cohort + deal_id + stage1_caliper,
  data = firm_edges, FUN = function(z) length(unique(z)))
names(per_deal)[names(per_deal) == "control_group"] <-
  "n_admissible_firms"
deal_70 <- firm_edges[firm_edges$deal_id == 70L, ]
deal_70$admitted_at_1_5 <- deal_70$control_group %in%
  deal_70$control_group[deal_70$stage1_caliper == 1.5]

utils::write.csv(
  per_deal,
  file.path(output_dir, "u2_stage1_firm_counts_by_deal.csv"),
  row.names = FALSE)
utils::write.csv(
  deal_70[order(
    deal_70$stage1_caliper, deal_70$distance,
    deal_70$control_group), ],
  file.path(output_dir, "deal_70_u2_stage1_firms.csv"),
  row.names = FALSE)
utils::write.csv(
  data.frame(
    version = LMV2_P5_RESCUE_VERSION,
    amendment_hash =
      LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256,
    cohort = g,
    database = db_path,
    status = "complete",
    timestamp = as.character(Sys.time()),
    stringsAsFactors = FALSE),
  file.path(output_dir, "stage1_2_diagnostic_manifest.csv"),
  row.names = FALSE)
message("Clean-U2 Stage-1 caliper-2.0 diagnostic complete")
