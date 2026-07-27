# Anticipation-window extension: test anticipation = 2 (and 3 as a boundary
# case) against the anticipation = 1 primary, on the common-support matched
# sample, deal-clustered bootstrap, universal base.
#
# Motivation (grounded in read-only diagnostics run this session):
#   Raw mean active_patenting by event time in the treated cohort:
#     -5:0.263  -4:0.271  -3:0.301(peak)  -2:0.277  -1:0.264  0:0.108(cliff)
#   -> a MILD decline from the -3 peak to -1 (~12%), then a sharp cliff at 0.
#   Not-yet-treated control pool mean active by distance to own deal:
#     within 1yr:0.264  2-3yr:0.289  4-5yr:0.267  6+yr:0.042
#   -> controls close to their OWN deal are near-peak (~0.28), those far away
#   are near-inactive (0.042); 18.7% of control rows are within 3yr of own deal.
#
# Increasing the anticipation window does TWO legitimate things at once:
#   (a) reclassifies the mild pre-cliff softening at t=-1/-2 as (anticipated)
#       treatment rather than a pre-trend -- valid IF deal_year tracks the
#       ANNOUNCEMENT date (which Cassi-Ornaghi Sec 3.2/4.1 suggests; pending
#       confirmation from Prof. Cassi, logged in CLAUDE.md); and
#   (b) buffers the control pool -- with anticipation=k a not-yet-treated unit
#       stops being an eligible control k periods before its OWN deal, removing
#       exactly the near-own-deal near-peak controls measured above.
#
# Discipline: anticipation=2 keeps a genuine 2-point pre-test (-5,-4, which the
# raw means show as nearly flat). anticipation=3 leaves only t=-5 as a pre-test
# -- reported as a BOUNDARY case (flattens largely by construction; do not treat
# as the primary evidence of parallel trends). This is NOT a licence to pick
# whichever anticipation flattens the pre-trend: report the full ladder
# (anticipation 1/2/3) side by side and let the announcement-vs-close question
# (Cassi) discipline which is primary.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08o_anticipation_window_extension.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_anticipation_ladder")
SUPPORT_RESULTS <- file.path(BASE, "output", "results", "cs2021_common_support")
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

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

# rebuild identical common-support matched sample (same deterministic NTILE)
full_panel <- DBI::dbGetQuery(con, "
SELECT
  CAST(codinv AS DOUBLE) AS codinv, CAST(deal_id AS INTEGER) AS deal_id,
  CAST(deal_year AS INTEGER) AS deal_year, CAST(calendar_year AS INTEGER) AS calendar_year,
  CAST(active_patenting AS DOUBLE) AS active_patenting,
  CAST(log_patent_count AS DOUBLE) AS log_patent_count,
  CAST(career_age_at_deal AS DOUBLE) AS career_age_at_deal,
  CAST(career_age_sq_at_deal AS DOUBLE) AS career_age_sq_at_deal, ipc_primary_field,
  CAST(log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
  CAST(log_group_size AS DOUBLE) AS log_group_size, CAST(log_deal_value AS DOUBLE) AS log_deal_value
FROM cs2021_estimation_panel ORDER BY codinv, calendar_year
")
full_panel$ipc_primary_field <- factor(full_panel$ipc_primary_field)
cell_coverage <- DBI::dbGetQuery(con, "
WITH unit AS (SELECT DISTINCT codinv, deal_id, deal_year, predeal_patent_stock_5y, ipc_primary_field FROM cs2021_estimation_panel),
binned AS (SELECT *, NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile FROM unit)
SELECT patent_stock_quintile, ipc_primary_field, COUNT(DISTINCT deal_year) AS n_cohorts,
  MAX(deal_year) - MIN(deal_year) AS cohort_year_span
FROM binned GROUP BY patent_stock_quintile, ipc_primary_field
")
cell_coverage$cell_passes <- cell_coverage$n_cohorts >= 3 & cell_coverage$cohort_year_span >= 5
allowed_cells <- cell_coverage[cell_coverage$cell_passes, c("patent_stock_quintile", "ipc_primary_field")]
unit_bins <- DBI::dbGetQuery(con, "
  WITH unit AS (SELECT DISTINCT codinv, deal_id, predeal_patent_stock_5y FROM cs2021_estimation_panel)
  SELECT codinv, deal_id, NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile FROM unit
")
unit_bins$codinv <- as.double(unit_bins$codinv)
full_panel <- merge(full_panel, unit_bins[c("codinv", "deal_id", "patent_stock_quintile")], by = c("codinv", "deal_id"))
full_panel <- merge(full_panel,
  data.frame(patent_stock_quintile = allowed_cells$patent_stock_quintile,
             ipc_primary_field = allowed_cells$ipc_primary_field, in_common_support = TRUE),
  by = c("patent_stock_quintile", "ipc_primary_field"), all.x = TRUE)
full_panel$in_common_support[is.na(full_panel$in_common_support)] <- FALSE
matched_panel <- full_panel[full_panel$in_common_support, , drop = FALSE]
message("Matched sample: ", length(unique(matched_panel$codinv)), " inventors | ",
        length(unique(matched_panel$deal_id)), " deals")

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

run_anticip <- function(outcome, anticip) {
  section(paste("anticipation =", anticip, "|", outcome))
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "deal_year",
    xformla = xformla_lean, data = matched_panel, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "notyettreated", anticipation = anticip, base_period = "universal",
    est_method = "dr", bstrap = TRUE, biters = 999,
    clustervars = "deal_id", cband = TRUE, print_details = FALSE
  )
  dynamic <- did::aggte(
    att, type = "dynamic", min_e = -5, max_e = 5, na.rm = TRUE,
    bstrap = TRUE, biters = 999, clustervars = "deal_id", cband = TRUE
  )
  coefs <- data.frame(
    outcome = outcome, anticipation = anticip,
    reference_period = -1 - anticip,
    event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )
  coefs$t_stat <- coefs$att / coefs$se
  print(coefs[c("event_time", "att", "se", "t_stat")])
  saveRDS(dynamic, file.path(RESULTS, paste0("aggte_anticip", anticip, "_", outcome, ".rds")))
  coefs
}

banner("ANTICIPATION LADDER: 1 (current primary), 2 (sweet spot), 3 (boundary)")

all_results <- list()
for (outcome in c("active_patenting", "log_patent_count")) {
  for (anticip in c(1, 2, 3)) {
    all_results[[paste(outcome, anticip, sep = "_")]] <- run_anticip(outcome, anticip)
  }
}
ladder <- do.call(rbind, all_results)
write_result(ladder, "anticipation_ladder_all.csv")

banner("PRE-PERIOD FLATNESS SUMMARY (are the remaining pre-test points insignificant?)")
pre <- ladder[ladder$event_time < ladder$reference_period, ]
pre_summary <- aggregate(cbind(max_abs_t = abs(t_stat)) ~ outcome + anticipation,
                          data = pre[is.finite(pre$t_stat), ], FUN = max)
pre_summary$n_pretest_points <- aggregate(t_stat ~ outcome + anticipation,
                          data = pre[is.finite(pre$t_stat), ], FUN = length)$t_stat
print(pre_summary)
write_result(pre_summary, "anticipation_ladder_pretest_summary.csv")

banner("FIGURE")
ladder$anticipation_label <- paste0("anticipation = ", ladder$anticipation)
p <- ggplot2::ggplot(ladder, ggplot2::aes(x = event_time, y = att, colour = anticipation_label, group = anticipation_label)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_line(linewidth = 0.8) + ggplot2::geom_point(size = 1.4) +
  ggplot2::facet_wrap(~outcome, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(x = "Years relative to acquisition", y = "Group-time ATT",
    colour = "Timing assumption",
    subtitle = "Anticipation ladder on the common-support matched sample (deal-clustered bootstrap, universal base)",
    caption = "anticipation=2 keeps a 2-point (-5,-4) pre-test; anticipation=3 leaves only t=-5 (boundary, largely mechanical).") +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), legend.position = "bottom",
    plot.background = ggplot2::element_rect(fill = "white", colour = NA))
fig_path <- file.path(FIGS, "figure12_anticipation_ladder.png")
ggplot2::ggsave(fig_path, p, width = 9, height = 4.5, dpi = 300)

banner("ANTICIPATION LADDER COMPLETE")
message("Outputs: ", RESULTS, " | Figure: ", fig_path)
