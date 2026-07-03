# Deal-year clustering robustness check.
#
# did::att_gt's own help text: "clustervars: A vector of variable names to
# cluster on. At most, there can be two variables (otherwise will throw an
# error) and one of these must be the same as idname" (idname = codinv here).
# Two-way deal_id x deal_year clustering is therefore NOT supported -- this
# script runs deal_id-clustered (reproducing 08h, as a sanity check on the
# rebuilt matched sample) and deal_year-clustered (new, ~21-23 clusters, a
# small-cluster regime) as two SEPARATE parallel robustness specs, not a
# combined two-way estimator.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08j_deal_year_clustering_check.R

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

# --- rebuild the identical common-support matched sample (same deterministic
# NTILE tiebreaker as 08g/08h/08i) ------------------------------------------
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
  length(unique(matched_panel$deal_id)), " deals | ",
  length(unique(matched_panel$deal_year)), " distinct deal_year values"
)

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

run_clustered <- function(outcome, cluster_var) {
  section(paste("clustervars =", cluster_var, "|", outcome))
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "deal_year",
    xformla = xformla_lean, data = matched_panel, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "notyettreated", anticipation = 1, base_period = "universal",
    est_method = "dr", bstrap = TRUE, biters = 999,
    clustervars = cluster_var, cband = TRUE, print_details = FALSE
  )
  dynamic <- did::aggte(
    att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5, na.rm = TRUE,
    bstrap = TRUE, biters = 999, clustervars = cluster_var, cband = TRUE
  )
  coefs <- data.frame(
    outcome = outcome, cluster_var = cluster_var,
    n_clusters = length(unique(matched_panel[[cluster_var]])),
    event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )
  coefs$t_stat <- coefs$att / coefs$se
  print(coefs[c("event_time", "att", "se", "t_stat")])
  write_result(coefs, paste0("dynamic_att_", cluster_var, "_clustered_", outcome, ".csv"))
  coefs
}

banner("CLUSTERING ROBUSTNESS: deal_id (sanity check) vs deal_year (new)")

results <- list()
for (outcome in c("active_patenting", "log_patent_count")) {
  results[[paste0(outcome, "_dealid")]]   <- run_clustered(outcome, "deal_id")
  results[[paste0(outcome, "_dealyear")]] <- run_clustered(outcome, "deal_year")
}
all_results <- do.call(rbind, results)

banner("SANITY CHECK: deal_id arm vs existing saved 08h results")
for (oc in c("active_patenting", "log_patent_count")) {
  saved <- utils::read.csv(file.path(RESULTS, paste0("dynamic_att_matched_bootstrap_", oc, ".csv")))
  new_dealid <- all_results[all_results$outcome == oc & all_results$cluster_var == "deal_id", ]
  cmp <- merge(saved[c("event_time", "att")], new_dealid[c("event_time", "att")],
               by = "event_time", suffixes = c("_saved_08h", "_rebuilt_08j"))
  cmp$diff <- cmp$att_rebuilt_08j - cmp$att_saved_08h
  message(oc, ": max abs diff vs saved 08h = ", round(max(abs(cmp$diff)), 8))
  print(cmp)
}

banner("SIDE-BY-SIDE COMPARISON")
wide <- reshape(
  all_results[c("outcome", "event_time", "cluster_var", "att", "se", "t_stat")],
  timevar = "cluster_var", idvar = c("outcome", "event_time"), direction = "wide"
)
wide <- wide[order(wide$outcome, wide$event_time), ]
write_result(wide, "clustering_comparison_dealid_vs_dealyear.csv")
print(wide)

banner("CLUSTERING CHECK COMPLETE")
message("Outputs: ", RESULTS)
