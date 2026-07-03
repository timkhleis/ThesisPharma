# Universal-base-period cross-check for the pre-trend concentration diagnostic.
#
# 08d found that the joint Wpval rejection is ~52% driven by event_time = -5
# (the boundary of the 5-year pre-deal cohort-defining window) and ~37% by
# deep-lag cells, but a restricted test on exactly the reported -4..-1 window
# ALSO rejects strongly (p ~ 1e-55), despite the aggregated dynamic ATT at
# those event times being small. That combination is consistent with
# base_period = "varying" (each period compared to the PREVIOUS period, not a
# fixed reference) chaining a large t=-5 spike into a large offsetting swing
# at t=-4 for the same cohorts -- i.e. two faces of the same boundary
# artifact, not two independent violations. base_period = "universal" (fixed
# reference period) tests this directly, and is also what HonestDiD requires
# downstream, so this run is reusable for Phase 4.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08e_universal_base_pretrend_check.R

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

cohort_sizes <- aggregate(
  codinv ~ deal_year, data = unique(panel[c("codinv", "deal_year")]), FUN = length
)
names(cohort_sizes) <- c("group", "n_treated_inventors")

fit_universal <- function(outcome) {
  message("--- Universal base | ", outcome, " ---")
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "deal_year",
    xformla = xformla_lean, data = panel, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "notyettreated", anticipation = 1, base_period = "universal",
    est_method = "dr", bstrap = FALSE, cband = FALSE, print_details = FALSE
  )
  cells <- data.frame(outcome = outcome, group = att$group, t = att$t, att = att$att, se = att$se)
  cells$event_time <- cells$t - cells$group
  cells <- cells[is.finite(cells$att) & is.finite(cells$se) & cells$se > 0, ]
  cells$z <- cells$att / cells$se
  cells$z_sq <- cells$z^2
  merge(cells, cohort_sizes, by = "group", all.x = TRUE)

  # dynamic aggregation, matching the primary spec's window
  dynamic <- did::aggte(
    att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5,
    na.rm = TRUE, bstrap = FALSE, cband = FALSE
  )
  list(
    cells = merge(cells, cohort_sizes, by = "group", all.x = TRUE),
    dynamic = data.frame(outcome = outcome, event_time = dynamic$egt, att = dynamic$att.egt,
                          se = dynamic$se.egt),
    pretrend_p = if (!is.null(att$Wpval) && length(att$Wpval) == 1) as.numeric(att$Wpval) else NA_real_
  )
}

banner("UNIVERSAL-BASE PRE-TREND CHECK")

results <- lapply(c("active_patenting", "log_patent_count"), fit_universal)
names(results) <- c("active_patenting", "log_patent_count")

all_cells <- do.call(rbind, lapply(results, `[[`, "cells"))
all_dynamic <- do.call(rbind, lapply(results, `[[`, "dynamic"))
write_result(all_cells, "universal_base_cell_level_diagnostics.csv")
write_result(all_dynamic, "universal_base_dynamic_att.csv")

for (oc in names(results)) {
  message("\n=== ", oc, " (universal base) ===")
  message("Overall Wpval (all pre-periods, universal base): ", round(results[[oc]]$pretrend_p, 4))

  sub <- results[[oc]]$cells
  pre <- sub[sub$event_time <= -2, ]
  restricted <- pre[pre$event_time >= -4, ]
  full_chisq <- sum(pre$z_sq)
  r_chisq <- sum(restricted$z_sq)
  message(sprintf(
    "Manual full-window chisq=%.1f (df=%d, p=%.3g) | restricted -4..-1 chisq=%.1f (df=%d, p=%.3g)",
    full_chisq, nrow(pre), pchisq(full_chisq, nrow(pre), lower.tail = FALSE),
    r_chisq, nrow(restricted), pchisq(r_chisq, nrow(restricted), lower.tail = FALSE)
  ))

  at5 <- pre[pre$event_time == -5, ]
  message(sprintf(
    "event_time == -5 only: n=%d, mean att=%.4f, sum(z^2)=%.1f (%.1f%% of full)",
    nrow(at5), mean(at5$att), sum(at5$z_sq), 100 * sum(at5$z_sq) / full_chisq
  ))

  print(results[[oc]]$dynamic)
}

banner("UNIVERSAL-BASE CHECK COMPLETE")
message("Outputs: ", RESULTS)
