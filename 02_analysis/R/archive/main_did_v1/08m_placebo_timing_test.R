# Placebo timing test: deal_year - 3.
#
# Does NOT rebuild the panel from target_cohort_own with a shifted deal_year
# -- that would risk contaminating pre-deal covariates with real post-deal
# information. Instead: take the existing cs2021_estimation_panel unmodified
# (so predeal_patent_stock_5y etc. stay computed relative to the TRUE
# deal_year), add a placebo group column (deal_year - 3), and restrict to
# calendar_year < deal_year before fitting -- this guarantees the placebo
# test only uses genuinely pre-deal outcome observations with zero possible
# true-treatment content, which is what makes it a valid placebo rather than
# a mislabeled real effect.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08m_placebo_timing_test.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_placebo")
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

banner("BUILDING PLACEBO PANEL")

# Guard against left-edge truncation: deals with deal_year too close to 1993
# lose placebo pre-periods once shifted back another 3 years and filtered to
# calendar_year < deal_year (panel starts 1988). Require deal_year >= 1998 so
# the placebo cohort (deal_year - 3) still has a full -5..-1 pre-window
# available (>= 1993..1997), matching the real design's earliest usable window.
placebo_panel <- DBI::dbGetQuery(con, "
SELECT
  CAST(codinv AS DOUBLE) AS codinv,
  CAST(deal_id AS INTEGER) AS deal_id,
  CAST(deal_year AS INTEGER) AS deal_year,
  CAST(deal_year AS INTEGER) - 3 AS placebo_deal_year,
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
WHERE deal_year >= 1998
  AND calendar_year < deal_year
")
placebo_panel$ipc_primary_field <- factor(placebo_panel$ipc_primary_field)

message(
  "Placebo panel: ", nrow(placebo_panel), " rows | ",
  length(unique(placebo_panel$codinv)), " inventors | ",
  length(unique(placebo_panel$deal_id)), " deals | ",
  "placebo_deal_year range: ", paste(range(placebo_panel$placebo_deal_year), collapse = "-"), " | ",
  "calendar_year range: ", paste(range(placebo_panel$calendar_year), collapse = "-")
)
stopifnot(nrow(placebo_panel) > 0, all(placebo_panel$calendar_year < placebo_panel$deal_year))

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

run_placebo <- function(outcome) {
  section(paste("PLACEBO |", outcome))
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "placebo_deal_year",
    xformla = xformla_lean, data = placebo_panel, panel = TRUE, allow_unbalanced_panel = TRUE,
    control_group = "notyettreated", anticipation = 1, base_period = "universal",
    est_method = "dr", bstrap = TRUE, biters = 999,
    clustervars = "deal_id", cband = TRUE, print_details = FALSE
  )
  # Placebo panel is truncated at calendar_year < deal_year, so the only
  # available "post-placebo" event times are 0..+2 (placebo_deal_year =
  # deal_year - 3). No balance_e (would require unattainable +5 balance).
  dynamic <- did::aggte(
    att, type = "dynamic", min_e = -4, max_e = 2, na.rm = TRUE,
    bstrap = TRUE, biters = 999, clustervars = "deal_id", cband = TRUE
  )
  coefs <- data.frame(
    outcome = outcome,
    n_inventors = length(unique(placebo_panel$codinv)), n_deals = length(unique(placebo_panel$deal_id)),
    event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )
  coefs$t_stat <- coefs$att / coefs$se
  message("Placebo dynamic ATT (all should be near zero -- placebo panel has NO real post-treatment data):")
  print(coefs[c("event_time", "att", "se", "t_stat")])
  saveRDS(att, file.path(RESULTS, paste0("att_gt_placebo_", outcome, ".rds")))
  saveRDS(dynamic, file.path(RESULTS, paste0("aggte_placebo_", outcome, ".rds")))
  write_result(coefs, paste0("dynamic_att_placebo_", outcome, ".csv"))
  coefs
}

banner("PLACEBO TIMING TEST: deal_year - 3, restricted to calendar_year < true deal_year")

placebo_results <- do.call(rbind, lapply(c("active_patenting", "log_patent_count"), run_placebo))
write_result(placebo_results, "placebo_all_dynamic_att.csv")

banner("COMPARISON TO REAL EVENT STUDY")
real_results <- do.call(rbind, lapply(c("active_patenting", "log_patent_count"), function(oc) {
  saved <- utils::read.csv(file.path(BASE, "output", "results", "cs2021_common_support",
                                      paste0("dynamic_att_matched_bootstrap_", oc, ".csv")))
  saved$spec <- "real"
  saved
}))
placebo_results$spec <- "placebo"
combined <- rbind(
  real_results[c("outcome", "spec", "event_time", "att", "se")],
  placebo_results[c("outcome", "spec", "event_time", "att", "se")]
)
write_result(combined, "placebo_vs_real_comparison.csv")

banner("FIGURE")
p <- ggplot2::ggplot(combined, ggplot2::aes(x = event_time, y = att, colour = spec, group = spec)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.5) +
  ggplot2::facet_wrap(~outcome, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to (real or placebo) deal", y = "Group-time average treatment effect",
    colour = "Specification",
    subtitle = "Placebo: deal_year - 3, restricted to calendar_year < true deal_year (no real treatment content)",
    caption = "Deal-clustered bootstrap; universal base; anticipation=1."
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(), legend.position = "bottom",
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )
fig_path <- file.path(FIGS, "figure10_placebo_timing.png")
ggplot2::ggsave(fig_path, p, width = 9, height = 4.5, dpi = 300)

banner("PLACEBO TIMING TEST COMPLETE")
message("Outputs: ", RESULTS)
message("Figure: ", fig_path)
