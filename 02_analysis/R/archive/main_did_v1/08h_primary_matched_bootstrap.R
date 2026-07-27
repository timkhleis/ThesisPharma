# Combined check: primary CS(2021) spec (universal base, anticipation = 1,
# lean xformla, deal-clustered multiplier bootstrap) run on the common-support
# MATCHED sample from 08g, rather than the full sample used in 08f. This
# stacks both "restore PT" corrections together (deal clustering + dropping
# the sparse/unstable IPC cells) to give the definitive pre-trend read, not
# just two separate checks pointing the same direction.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08h_primary_matched_bootstrap.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_common_support")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "did")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_result <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

full_panel <- DBI::dbGetQuery(con, "
SELECT
  CAST(codinv AS DOUBLE) AS codinv,
  CAST(deal_id AS INTEGER) AS deal_id,
  CAST(deal_year AS INTEGER) AS deal_year,
  CAST(calendar_year AS INTEGER) AS calendar_year,
  CAST(active_patenting AS DOUBLE) AS active_patenting,
  CAST(log_patent_count AS DOUBLE) AS log_patent_count,
  CAST(career_age_at_deal AS DOUBLE) AS career_age_at_deal,
  CAST(career_age_sq_at_deal AS DOUBLE) AS career_age_sq_at_deal,
  ipc_primary_field,
  CAST(log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
  CAST(log_group_size AS DOUBLE) AS log_group_size,
  CAST(log_deal_value AS DOUBLE) AS log_deal_value
FROM cs2021_estimation_panel
ORDER BY codinv, calendar_year
")
full_panel$ipc_primary_field <- factor(full_panel$ipc_primary_field)

# Rebuild the same common-support cell coverage rule as 08g (>= 3 cohorts,
# >= 5-year span) to get the matched-sample allowlist.
cell_coverage <- DBI::dbGetQuery(con, "
WITH unit AS (
  SELECT DISTINCT codinv, deal_id, deal_year, predeal_patent_stock_5y, ipc_primary_field
  FROM cs2021_estimation_panel
),
binned AS (
  SELECT *, NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
  FROM unit
)
SELECT patent_stock_quintile, ipc_primary_field,
  COUNT(DISTINCT deal_year) AS n_cohorts,
  MAX(deal_year) - MIN(deal_year) AS cohort_year_span
FROM binned
GROUP BY patent_stock_quintile, ipc_primary_field
")
cell_coverage$cell_passes <- cell_coverage$n_cohorts >= 3 & cell_coverage$cohort_year_span >= 5
allowed_cells <- cell_coverage[cell_coverage$cell_passes, c("patent_stock_quintile", "ipc_primary_field")]

unit_bins <- DBI::dbGetQuery(con, "
  WITH unit AS (
    SELECT DISTINCT codinv, deal_id, predeal_patent_stock_5y
    FROM cs2021_estimation_panel
  )
  SELECT codinv, deal_id,
    NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
  FROM unit
")
unit_bins$codinv <- as.double(unit_bins$codinv)
full_panel <- merge(full_panel, unit_bins[c("codinv", "deal_id", "patent_stock_quintile")],
                     by = c("codinv", "deal_id"))
full_panel <- merge(
  full_panel,
  data.frame(patent_stock_quintile = allowed_cells$patent_stock_quintile,
             ipc_primary_field = allowed_cells$ipc_primary_field,
             in_common_support = TRUE),
  by = c("patent_stock_quintile", "ipc_primary_field"), all.x = TRUE
)
full_panel$in_common_support[is.na(full_panel$in_common_support)] <- FALSE
matched_panel <- full_panel[full_panel$in_common_support, , drop = FALSE]
message(
  "Matched sample: ", length(unique(matched_panel$codinv)), " inventors | ",
  length(unique(matched_panel$deal_id)), " deals"
)

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

run_primary_bootstrap <- function(outcome, data) {
  section(paste("MATCHED + BOOTSTRAP |", outcome))
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "deal_year",
    xformla = xformla_lean, data = data, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "notyettreated", anticipation = 1, base_period = "universal",
    est_method = "dr", bstrap = TRUE, biters = 999,
    clustervars = "deal_id", cband = TRUE, print_details = FALSE
  )
  dynamic <- did::aggte(
    att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5, na.rm = TRUE,
    bstrap = TRUE, biters = 999, clustervars = "deal_id", cband = TRUE
  )
  coefs <- data.frame(
    outcome = outcome, label = "matched_common_support_clustered",
    n_inventors = length(unique(data$codinv)), n_deals = length(unique(data$deal_id)),
    event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )
  coefs$t_stat <- coefs$att / coefs$se
  message("Deal-clustered bootstrap SEs (matched common-support sample):")
  print(coefs[c("event_time", "att", "se", "t_stat")])

  saveRDS(att, file.path(RESULTS, paste0("att_gt_matched_bootstrap_", outcome, ".rds")))
  saveRDS(dynamic, file.path(RESULTS, paste0("aggte_matched_bootstrap_", outcome, ".rds")))
  write_result(coefs, paste0("dynamic_att_matched_bootstrap_", outcome, ".csv"))
  coefs
}

banner("PRIMARY SPEC ON COMMON-SUPPORT MATCHED SAMPLE, DEAL-CLUSTERED BOOTSTRAP")

results <- lapply(c("active_patenting", "log_patent_count"), run_primary_bootstrap, data = matched_panel)
all_coefs <- do.call(rbind, results)
write_result(all_coefs, "matched_bootstrap_all_dynamic_att.csv")

banner("COMBINED CHECK COMPLETE")
message("Outputs: ", RESULTS)
