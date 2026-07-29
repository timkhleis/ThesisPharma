# Pre-treatment intensity filter -- "at-risk" ITT, both thresholds.
#
# Motivation: every not-yet-treated control is itself a future acquisition
# target selected near a productivity peak (no never-treated anchor exists in
# this design). 63% of the treated cohort has permanently exited patenting
# before the deal (career_exited share at t=-1). If active composition drifts
# differentially between treated and not-yet-treated across event time, that
# drift could mechanically generate part of the t=-3 pre-trend residual that
# survives deal clustering, common-support restriction, and both base-period
# and anticipation choices. This script restricts to inventors who were
# genuinely "at risk" of measurable pre-deal patenting -- a PRE-TREATMENT
# sample restriction (legitimate; conditions only on event_time <= -2
# information, strictly before the anticipation=1 window), not a bad-control
# problem.
#
# Two thresholds, both reported (see CLAUDE.md discussion / thesis notes):
#   A (looser):   predeal_patent_stock_5y >= 2 (>=2 total patents, event_time -5..-1)
#   B (stricter, primary): >=2 DISTINCT active patenting years, event_time -5..-2
#     (excludes -1, which sits inside the anticipation=1 window)
# Threshold B mirrors Cassi & Ornaghi's own published inclusion criterion
# ("patents in at least two different years") -- supportive precedent, not
# binding validation, since this thesis's design already diverges from theirs
# in other respects (own stayer/leaver classification, CS(2021) instead of
# their LPM/probit, different cohort construction).
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08k_at_risk_intensity_filter.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_at_risk")
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

banner("BUILDING AT-RISK FLAGS (both thresholds)")

at_risk_flags <- DBI::dbGetQuery(con, "
WITH unit AS (
  SELECT DISTINCT codinv, deal_id, deal_year, predeal_patent_stock_5y
  FROM cs2021_estimation_panel
),
predeal_active_years AS (
  SELECT u.codinv, u.deal_id,
    COUNT(DISTINCT iy.year) FILTER (WHERE iy.patent_count > 0) AS n_active_years_pre
  FROM unit u
  LEFT JOIN inventor_year iy
    ON CAST(iy.codinv AS BIGINT) = CAST(u.codinv AS BIGINT)
   AND iy.year BETWEEN u.deal_year - 5 AND u.deal_year - 2
  GROUP BY u.codinv, u.deal_id
)
SELECT
  u.codinv, u.deal_id,
  u.predeal_patent_stock_5y,
  pay.n_active_years_pre,
  CASE WHEN u.predeal_patent_stock_5y >= 2 THEN TRUE ELSE FALSE END AS at_risk_a_ge2_patents,
  CASE WHEN pay.n_active_years_pre >= 2 THEN TRUE ELSE FALSE END AS at_risk_b_ge2_years
FROM unit u
LEFT JOIN predeal_active_years pay ON u.codinv = pay.codinv AND u.deal_id = pay.deal_id
")
at_risk_flags$codinv <- as.double(at_risk_flags$codinv)
write_result(at_risk_flags, "at_risk_unit_flags.csv")

n_total <- nrow(at_risk_flags)
n_a <- sum(at_risk_flags$at_risk_a_ge2_patents)
n_b <- sum(at_risk_flags$at_risk_b_ge2_years)
message(sprintf("Total units: %d", n_total))
message(sprintf("Threshold A (>=2 total patents, -5..-1): %d (%.1f%%)", n_a, 100 * n_a / n_total))
message(sprintf("Threshold B (>=2 distinct active years, -5..-2): %d (%.1f%%)", n_b, 100 * n_b / n_total))

banner("LOADING PANEL AND BUILDING COMMON-SUPPORT MATCHED SAMPLE")

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
full_panel <- merge(full_panel, at_risk_flags[c("codinv", "deal_id", "at_risk_a_ge2_patents", "at_risk_b_ge2_years")],
                     by = c("codinv", "deal_id"))

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
  WITH unit AS (SELECT DISTINCT codinv, deal_id, predeal_patent_stock_5y FROM cs2021_estimation_panel)
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
             ipc_primary_field = allowed_cells$ipc_primary_field, in_common_support = TRUE),
  by = c("patent_stock_quintile", "ipc_primary_field"), all.x = TRUE
)
full_panel$in_common_support[is.na(full_panel$in_common_support)] <- FALSE

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

run_arm <- function(outcome, data, arm_label) {
  section(paste(arm_label, "|", outcome, "| n =", length(unique(data$codinv))))
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
    outcome = outcome, arm = arm_label,
    n_inventors = length(unique(data$codinv)), n_deals = length(unique(data$deal_id)),
    event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )
  coefs$t_stat <- coefs$att / coefs$se
  print(coefs[c("event_time", "att", "se", "t_stat")])
  saveRDS(att, file.path(RESULTS, paste0("att_gt_", arm_label, "_", outcome, ".rds")))
  saveRDS(dynamic, file.path(RESULTS, paste0("aggte_", arm_label, "_", outcome, ".rds")))
  write_result(coefs, paste0("dynamic_att_at_risk_", arm_label, "_", outcome, ".csv"))
  coefs
}

banner("RUNNING ARMS: THRESHOLD A (>=2 patents) AND B (>=2 distinct years), FULL + MATCHED")

arms <- list(
  thresholdA_full    = full_panel[full_panel$at_risk_a_ge2_patents, ],
  thresholdA_matched = full_panel[full_panel$at_risk_a_ge2_patents & full_panel$in_common_support, ],
  thresholdB_full    = full_panel[full_panel$at_risk_b_ge2_years, ],
  thresholdB_matched = full_panel[full_panel$at_risk_b_ge2_years & full_panel$in_common_support, ]
)

all_new_results <- list()
for (arm_label in names(arms)) {
  for (outcome in c("active_patenting", "log_patent_count")) {
    key <- paste(arm_label, outcome, sep = "_")
    all_new_results[[key]] <- run_arm(outcome, arms[[arm_label]], arm_label)
  }
}
new_results_df <- do.call(rbind, all_new_results)

banner("LOADING REFERENCE: UNRESTRICTED FULL-COHORT MATCHED RESULT (from 08h)")

reference_results <- do.call(rbind, lapply(c("active_patenting", "log_patent_count"), function(oc) {
  saved <- utils::read.csv(file.path(SUPPORT_RESULTS, paste0("dynamic_att_matched_bootstrap_", oc, ".csv")))
  saved$arm <- "unrestricted_matched_reference"
  saved$t_stat <- saved$att / saved$se
  saved[c("outcome", "arm", "n_inventors", "n_deals", "event_time", "att", "se", "t_stat")]
}))

all_results <- rbind(new_results_df, reference_results)
write_result(all_results, "at_risk_vs_full_cohort_comparison.csv")

banner("SAMPLE SIZE / MONOTONICITY SUMMARY")
sample_sizes <- unique(all_results[c("arm", "n_inventors", "n_deals")])
print(sample_sizes[order(sample_sizes$n_inventors), ])

banner("FIGURE")
plot_data <- all_results
arm_order <- c("unrestricted_matched_reference", "thresholdA_full", "thresholdA_matched",
                "thresholdB_full", "thresholdB_matched")
plot_data$arm <- factor(plot_data$arm, levels = arm_order)
p <- ggplot2::ggplot(
  plot_data, ggplot2::aes(x = event_time, y = att, colour = arm, group = arm)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.5) +
  ggplot2::facet_wrap(~outcome, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition", y = "Group-time average treatment effect",
    colour = "Cohort definition",
    subtitle = "At-risk intensity filter: Threshold A (>=2 patents) vs B (>=2 distinct years) vs unrestricted",
    caption = "Deal-clustered bootstrap; universal base; anticipation=1."
  ) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(), legend.position = "bottom",
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )
fig_path <- file.path(FIGS, "figure8_at_risk_comparison.png")
ggplot2::ggsave(fig_path, p, width = 10, height = 5, dpi = 300)

banner("AT-RISK INTENSITY FILTER COMPLETE")
message("Outputs: ", RESULTS)
message("Figure: ", fig_path)
