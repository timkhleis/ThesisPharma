# ============================================================================
# 30b_build_lmv2_dealsim_table.R -- build outcome-blind deal-level DealSim
# ============================================================================
# Creates IPC4 cosine similarity from target and acquirer patent portfolios in
# event times -5 through -1.  It covers the 341 deals in the frozen P5c panel
# and explicitly records every exclusion.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "30a_lmv2_dealsim_power_config.R"))

cfg <- LMV2_DEALSIM_POWER
out_dir <- cfg$output_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
db_path <- normalizePath(cfg$inputs$database, winslash = "/", mustWork = TRUE)
panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
if (length(panel_files) != 17L) stop("Expected 17 certified P5c panel shards")
panel_glob <- normalizePath(
  file.path(cfg$inputs$panel_dir, "*.parquet"),
  winslash = "/", mustWork = FALSE
)

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")

deal_base <- DBI::dbGetQuery(con, sprintf("
  WITH panel_deals AS (
    SELECT deal_id,
           COUNT(DISTINCT codinv) AS n_treated_inventors,
           SUM(weight) AS treated_weight
    FROM read_parquet('%s')
    WHERE arm='treated' AND event_time=-1
    GROUP BY deal_id
  ), mapping AS (
    SELECT deal_id,
           MIN(cohort) AS cohort,
           MIN(CAST(target_group AS BIGINT)) AS target_group,
           MIN(CAST(acquirer_group AS BIGINT)) AS acquirer_group,
           COUNT(DISTINCT target_group) AS n_target_groups,
           COUNT(DISTINCT acquirer_group) AS n_acquirer_groups
    FROM lmv2_treated_primary
    WHERE deal_id IN (SELECT deal_id FROM panel_deals)
    GROUP BY deal_id
  )
  SELECT p.deal_id, m.cohort, m.target_group, m.acquirer_group,
         p.n_treated_inventors, p.treated_weight,
         m.n_target_groups, m.n_acquirer_groups
  FROM panel_deals p
  LEFT JOIN mapping m USING (deal_id)
  ORDER BY p.deal_id
", gsub("'", "''", panel_glob, fixed = TRUE)))
if (nrow(deal_base) != 341L || anyDuplicated(deal_base$deal_id) ||
    any(deal_base$n_target_groups != 1L) ||
    any(deal_base$n_acquirer_groups > 1L)) {
  stop("Frozen panel-to-deal mapping is incomplete or nonunique")
}

DBI::dbWriteTable(con, "dealsim_deal_base", deal_base, temporary = TRUE)
dealsim <- DBI::dbGetQuery(con, "
  WITH ipc4 AS (
    SELECT CAST(id_group AS BIGINT) AS id_group,
           CAST(year AS INTEGER) AS year,
           SUBSTR(ipc_code, 1, 4) AS ipc4,
           SUM(CAST(patent_count AS DOUBLE)) AS patent_weight
    FROM group_ipc_year
    WHERE ipc_code IS NOT NULL AND LENGTH(ipc_code) >= 4
    GROUP BY id_group, year, ipc4
  ), target_vector AS (
    SELECT d.deal_id, i.ipc4, SUM(i.patent_weight) AS patent_weight,
           MIN(i.year) AS first_ipc_year, MAX(i.year) AS last_ipc_year
    FROM dealsim_deal_base d
    JOIN ipc4 i ON i.id_group=d.target_group
      AND i.year BETWEEN d.cohort-5 AND d.cohort-1
    GROUP BY d.deal_id, i.ipc4
  ), acquirer_vector AS (
    SELECT d.deal_id, i.ipc4, SUM(i.patent_weight) AS patent_weight,
           MIN(i.year) AS first_ipc_year, MAX(i.year) AS last_ipc_year
    FROM dealsim_deal_base d
    JOIN ipc4 i ON i.id_group=d.acquirer_group
      AND i.year BETWEEN d.cohort-5 AND d.cohort-1
    WHERE d.acquirer_group IS NOT NULL
      AND NOT regexp_matches(CAST(d.acquirer_group AS VARCHAR), '^999')
    GROUP BY d.deal_id, i.ipc4
  ), target_stats AS (
    SELECT deal_id, SQRT(SUM(patent_weight*patent_weight)) AS target_norm,
           SUM(patent_weight) AS target_patents,
           MIN(first_ipc_year) AS target_first_ipc_year,
           MAX(last_ipc_year) AS target_last_ipc_year
    FROM target_vector GROUP BY deal_id
  ), acquirer_stats AS (
    SELECT deal_id, SQRT(SUM(patent_weight*patent_weight)) AS acquirer_norm,
           SUM(patent_weight) AS acquirer_patents,
           MIN(first_ipc_year) AS acquirer_first_ipc_year,
           MAX(last_ipc_year) AS acquirer_last_ipc_year
    FROM acquirer_vector GROUP BY deal_id
  ), dot_product AS (
    SELECT t.deal_id, SUM(t.patent_weight*a.patent_weight) AS dot_product
    FROM target_vector t
    JOIN acquirer_vector a USING (deal_id, ipc4)
    GROUP BY t.deal_id
  )
  SELECT d.*,
         ts.target_norm, acs.acquirer_norm,
         ts.target_patents, acs.acquirer_patents,
         ts.target_first_ipc_year, ts.target_last_ipc_year,
         acs.acquirer_first_ipc_year, acs.acquirer_last_ipc_year,
         COALESCE(dp.dot_product, 0) AS dot_product,
         CASE
           WHEN d.acquirer_group IS NULL THEN 'missing_acquirer_group'
           WHEN regexp_matches(CAST(d.acquirer_group AS VARCHAR), '^999')
             THEN 'placeholder_acquirer_group'
           WHEN ts.target_norm IS NULL OR ts.target_norm<=0
             THEN 'missing_target_ipc4_portfolio'
           WHEN acs.acquirer_norm IS NULL OR acs.acquirer_norm<=0
             THEN 'missing_acquirer_ipc4_portfolio'
           ELSE 'eligible'
         END AS eligibility_reason,
         CASE
           WHEN d.acquirer_group IS NOT NULL
            AND NOT regexp_matches(CAST(d.acquirer_group AS VARCHAR), '^999')
            AND ts.target_norm>0 AND acs.acquirer_norm>0
           THEN TRUE ELSE FALSE
         END AS eligible_dealsim,
         CASE
           WHEN d.acquirer_group IS NOT NULL
            AND NOT regexp_matches(CAST(d.acquirer_group AS VARCHAR), '^999')
            AND ts.target_norm>0 AND acs.acquirer_norm>0
           THEN COALESCE(dp.dot_product, 0)/(ts.target_norm*acs.acquirer_norm)
           ELSE NULL
         END AS dealsim
  FROM dealsim_deal_base d
  LEFT JOIN target_stats ts USING (deal_id)
  LEFT JOIN acquirer_stats acs USING (deal_id)
  LEFT JOIN dot_product dp USING (deal_id)
  ORDER BY d.deal_id
")
lmv2_assert_dealsim_rows(dealsim)

funnel <- do.call(rbind, lapply(
  split(dealsim, dealsim$eligibility_reason),
  function(x) data.frame(
    eligibility_reason = x$eligibility_reason[[1]],
    nominal_deals = nrow(x),
    treated_inventors = sum(x$n_treated_inventors),
    treated_weight = sum(x$treated_weight),
    effective_deals = lmv2_effective_count(x$treated_weight),
    stringsAsFactors = FALSE
  )
))
funnel <- funnel[order(funnel$eligibility_reason), ]

utils::write.csv(
  dealsim, file.path(out_dir, "dealsim_by_deal.csv"),
  row.names = FALSE, na = ""
)
utils::write.csv(
  funnel, file.path(out_dir, "dealsim_eligibility_funnel.csv"),
  row.names = FALSE, na = ""
)

source_path <- file.path(BASE, "R", "30b_build_lmv2_dealsim_table.R")
manifest <- data.frame(
  dealsim_power_version = LMV2_DEALSIM_POWER_VERSION,
  dealsim_power_hash = lmv2_dealsim_power_hash(),
  parent_design_hash = LMV2_DESIGN_HASH,
  database_sha256 = digest::digest(file = db_path, algo = "sha256"),
  panel_bundle_sha256 = digest::digest(
    vapply(panel_files, tools::md5sum, character(1)),
    algo = "sha256", serialize = TRUE
  ),
  source_sha256 = digest::digest(file = source_path, algo = "sha256"),
  nominal_deals = nrow(dealsim),
  eligible_deals = sum(dealsim$eligible_dealsim),
  excluded_deals = sum(!dealsim$eligible_dealsim),
  eligible_effective_deals = lmv2_effective_count(
    dealsim$treated_weight[dealsim$eligible_dealsim]
  ),
  outcome_columns_written = 0L,
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "dealsim_build_manifest.csv"),
  row.names = FALSE
)
message(
  "DealSim table built: ", manifest$eligible_deals, "/",
  manifest$nominal_deals, " deals eligible; no subgroup outcomes opened."
)
