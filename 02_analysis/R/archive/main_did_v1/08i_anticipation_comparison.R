# Anticipation=0 vs anticipation=1, side by side, on the current best spec
# (lean predetermined xformla, universal base, deal-clustered bootstrap,
# common-support matched sample).
#
# Context: target_year's exact meaning (Zephyr announcement vs. closing date)
# is unverified -- Cassi & Ornaghi (2026) Sec 3.2 confirms Zephyr as the
# source and Sec 4.1 uses "announcement date" interchangeably with their
# acquisition-timing variable in an illustrative passage, but this is not a
# crisp methods statement. Per CLAUDE.md's tracked question for Prof. Cassi,
# both anticipation values are reported as equally-motivated specs, not
# selected based on which one shows a cleaner pre-trend (that would be exactly
# the specification-search problem the plan is designed to avoid).
#
# Reuses the already-saved anticipation=1 matched-bootstrap results from
# 08h_primary_matched_bootstrap.R rather than re-running them.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08i_anticipation_comparison.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_common_support")
FIGS    <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "did", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)
banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_result <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

anticip1_rds_exists <- all(file.exists(
  file.path(RESULTS, paste0("aggte_matched_bootstrap_", c("active_patenting", "log_patent_count"), ".rds"))
))
if (!anticip1_rds_exists) {
  stop("Missing saved anticipation=1 results from 08h_primary_matched_bootstrap.R. Run that script first.")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

# --- rebuild the identical common-support matched sample (same deterministic
# NTILE tiebreaker as 08g/08h) ------------------------------------------------
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
  length(unique(matched_panel$deal_id)), " deals"
)

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

run_anticipation0 <- function(outcome) {
  section(paste("ANTICIPATION=0 |", outcome))
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "deal_year",
    xformla = xformla_lean, data = matched_panel, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "notyettreated", anticipation = 0, base_period = "universal",
    est_method = "dr", bstrap = TRUE, biters = 999,
    clustervars = "deal_id", cband = TRUE, print_details = FALSE
  )
  dynamic <- did::aggte(
    att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5, na.rm = TRUE,
    bstrap = TRUE, biters = 999, clustervars = "deal_id", cband = TRUE
  )
  coefs <- data.frame(
    outcome = outcome, anticipation = 0,
    n_inventors = length(unique(matched_panel$codinv)), n_deals = length(unique(matched_panel$deal_id)),
    event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )
  coefs$t_stat <- coefs$att / coefs$se
  saveRDS(att, file.path(RESULTS, paste0("att_gt_matched_bootstrap_anticipation0_", outcome, ".rds")))
  saveRDS(dynamic, file.path(RESULTS, paste0("aggte_matched_bootstrap_anticipation0_", outcome, ".rds")))
  print(coefs[c("event_time", "att", "se", "t_stat")])
  coefs
}

banner("ANTICIPATION=0, MATCHED SAMPLE, DEAL-CLUSTERED BOOTSTRAP")
anticipation0_results <- do.call(rbind, lapply(c("active_patenting", "log_patent_count"), run_anticipation0))

banner("LOADING SAVED ANTICIPATION=1 RESULTS")
anticipation1_results <- do.call(rbind, lapply(c("active_patenting", "log_patent_count"), function(oc) {
  dyn <- readRDS(file.path(RESULTS, paste0("aggte_matched_bootstrap_", oc, ".rds")))
  coefs <- data.frame(
    outcome = oc, anticipation = 1,
    n_inventors = NA_integer_, n_deals = NA_integer_,
    event_time = dyn$egt, att = dyn$att.egt, se = dyn$se.egt
  )
  coefs$t_stat <- coefs$att / coefs$se
  coefs
}))

all_results <- rbind(anticipation0_results, anticipation1_results)
write_result(all_results, "anticipation0_vs_anticipation1.csv")

banner("SIDE-BY-SIDE COMPARISON")
wide <- reshape(
  all_results[c("outcome", "event_time", "anticipation", "att", "se", "t_stat")],
  timevar = "anticipation", idvar = c("outcome", "event_time"), direction = "wide"
)
wide <- wide[order(wide$outcome, wide$event_time), ]
write_result(wide, "anticipation0_vs_anticipation1_wide.csv")
print(wide)

banner("COMPARISON FIGURE")
plot_data <- all_results
plot_data$anticipation_label <- paste0("anticipation = ", plot_data$anticipation)
p <- ggplot2::ggplot(
  plot_data, ggplot2::aes(x = event_time, y = att, colour = anticipation_label, group = anticipation_label)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = att - 1.96 * se, ymax = att + 1.96 * se, fill = anticipation_label),
    alpha = 0.12, colour = NA
  ) +
  ggplot2::geom_line(linewidth = 0.9) +
  ggplot2::geom_point(size = 1.8) +
  ggplot2::facet_wrap(~outcome, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition", y = "Group-time average treatment effect",
    colour = "Timing assumption", fill = "Timing assumption",
    subtitle = "Common-support matched sample, deal-clustered bootstrap, universal base",
    caption = "target_year timing (announcement vs. closing) unverified -- both shown as equally-motivated specs."
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )
fig_path <- file.path(FIGS, "figure7_anticipation_comparison.png")
ggplot2::ggsave(fig_path, p, width = 9, height = 4.5, dpi = 300)

banner("ANTICIPATION COMPARISON COMPLETE")
message("Outputs: ", RESULTS)
message("Figure: ", fig_path)
