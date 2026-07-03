# Pre-trend concentration diagnostic: is the joint Wald-test rejection
# (Wpval ~ 0 in the Phase 2 triangulation) broad-based across cohorts, or
# driven by a handful of thin/small deal_year cohorts with noisy group-time
# ATT(g,t) estimates? The aggregated dynamic event-study coefficients hide
# this -- they average over many (g,t) cells. This script inspects the
# un-aggregated att_gt() output directly.
#
# Uses the same primary candidate spec as the Phase 2 triangulation
# ("lean_controlled", est_method = "dr", anticipation = 1, base_period =
# "varying") for active_patenting and log_patent_count.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08d_pretrend_concentration_check.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_triangulation")

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

panel <- DBI::dbGetQuery(con, "
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
panel$ipc_primary_field <- factor(panel$ipc_primary_field)

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

# Cohort sizes: number of treated inventors first exposed in each deal_year
cohort_sizes <- aggregate(
  codinv ~ deal_year,
  data = unique(panel[c("codinv", "deal_year")]),
  FUN = length
)
names(cohort_sizes) <- c("group", "n_treated_inventors")
n_deals_by_group <- DBI::dbGetQuery(con, "
SELECT deal_year AS \"group\", COUNT(DISTINCT deal_id) AS n_deals
FROM cs2021_estimation_panel
GROUP BY deal_year
")
cohort_sizes <- merge(cohort_sizes, n_deals_by_group, by = "group", all.x = TRUE)

inspect_pretrends <- function(outcome) {
  section(paste("Refitting att_gt for concentration check:", outcome))
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome,
    tname = "calendar_year",
    idname = "codinv",
    gname = "deal_year",
    xformla = xformla_lean,
    data = panel,
    panel = TRUE,
    allow_unbalanced_panel = FALSE,
    control_group = "notyettreated",
    anticipation = 1,
    base_period = "varying",
    est_method = "dr",
    bstrap = FALSE,
    cband = FALSE,
    print_details = FALSE
  )

  cells <- data.frame(
    outcome = outcome,
    group = att$group,
    t = att$t,
    att = att$att,
    se = att$se
  )
  cells$event_time <- cells$t - cells$group
  # anticipation = 1 shifts the usable pre-period boundary to event_time <= -2
  cells <- cells[cells$event_time <= -2 & is.finite(cells$att) & is.finite(cells$se) & cells$se > 0, ]
  cells$z <- cells$att / cells$se
  cells$z_sq <- cells$z^2
  cells <- merge(cells, cohort_sizes, by = "group", all.x = TRUE)
  cells <- cells[order(-cells$z_sq), ]

  # Varying-base dynamic event-study table (the headline reporting diagnostic,
  # per the dual-base reporting plan -- t=-5 is the documented window-boundary
  # artifact, see cs_state_by_calendar_year.csv / this script's own findings).
  # No bootstrap needed here (matches this script's existing diagnostic style).
  dynamic <- did::aggte(
    att, type = "dynamic", balance_e = 5, min_e = -5, max_e = 5, na.rm = TRUE,
    bstrap = FALSE, cband = FALSE
  )
  dynamic_table <- data.frame(
    outcome = outcome, event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )

  list(cells = cells, dynamic = dynamic_table)
}

banner("PRE-TREND CONCENTRATION CHECK")

pretrend_results <- lapply(c("active_patenting", "log_patent_count"), inspect_pretrends)
all_cells <- do.call(rbind, lapply(pretrend_results, `[[`, "cells"))
write_result(all_cells, "pretrend_cell_level_diagnostics.csv")

varying_base_dynamic <- do.call(rbind, lapply(pretrend_results, `[[`, "dynamic"))
write_result(varying_base_dynamic, "pretrend_dynamic_att_varying_base.csv")
message("\nVarying-base dynamic event-study table (headline t=-5 artifact visible here):")
print(varying_base_dynamic)

for (oc in unique(all_cells$outcome)) {
  section(paste("Outcome:", oc))
  sub <- all_cells[all_cells$outcome == oc, ]
  total_zsq <- sum(sub$z_sq, na.rm = TRUE)

  by_cohort <- aggregate(
    cbind(z_sq, n_cells = 1) ~ group + n_treated_inventors + n_deals,
    data = sub,
    FUN = sum
  )
  by_cohort$share_of_total_zsq <- by_cohort$z_sq / total_zsq
  by_cohort <- by_cohort[order(-by_cohort$share_of_total_zsq), ]
  by_cohort$cumulative_share <- cumsum(by_cohort$share_of_total_zsq)

  message("Total pre-period cells: ", nrow(sub), " | sum(z^2) = ", round(total_zsq, 1))
  message("Top contributing cohorts (deal_year), by share of sum(z^2):")
  print(head(by_cohort, 10))

  top5_share <- sum(head(by_cohort$share_of_total_zsq, 5))
  message(
    "Top 5 cohorts account for ", round(100 * top5_share, 1),
    "% of the total pre-period z^2 mass (", nrow(by_cohort), " cohorts total)."
  )
  write_result(by_cohort, paste0("pretrend_cohort_concentration_", oc, ".csv"))

  # correlation between cohort size and |z|: are the biggest violations in small cohorts?
  cor_size_z <- suppressWarnings(cor(
    by_cohort$n_treated_inventors, by_cohort$z_sq / by_cohort$n_cells, use = "complete.obs"
  ))
  message("Correlation(cohort size, mean z^2 per cell): ", round(cor_size_z, 3))
}

banner("CONCENTRATION CHECK COMPLETE")
message("Outputs: ", RESULTS)
