# Primary CS(2021) spec: lean predetermined-only xformla (Phase 2), universal
# base period (Phase "restore PT" decision -- avoids the varying-base t=-5
# boundary artifact found in 08d/08e, and is required for HonestDiD input),
# anticipation = 1 (Phase 1, institutional grounds), full deal-clustered
# bootstrap. This supersedes 08_estimate_cs2021_main.R (uncontrolled,
# anticipation = 0) as the headline spec; that script is retained as the
# uncontrolled/legacy baseline for comparison, not deleted.
#
# Outcomes: active_patenting, log_patent_count (main causal); moved_thirdparty
# (secondary, inventor-mobility outcome, not a joint hypothesis test).
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08f_estimate_cs2021_primary.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_primary")
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

panel <- DBI::dbGetQuery(con, "
SELECT
  CAST(codinv AS DOUBLE) AS codinv,
  CAST(deal_id AS INTEGER) AS deal_id,
  CAST(deal_year AS INTEGER) AS deal_year,
  CAST(calendar_year AS INTEGER) AS calendar_year,
  CAST(active_patenting AS DOUBLE) AS active_patenting,
  CAST(log_patent_count AS DOUBLE) AS log_patent_count,
  CAST(moved_thirdparty AS DOUBLE) AS moved_thirdparty,
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

run_primary <- function(outcome, data = panel, bstrap = TRUE, label = "full_sample") {
  section(paste("PRIMARY |", outcome, "|", label, "| bstrap =", bstrap))
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "deal_year",
    xformla = xformla_lean, data = data, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "notyettreated", anticipation = 1, base_period = "universal",
    est_method = "dr", bstrap = bstrap, biters = if (bstrap) 999 else 1,
    clustervars = if (bstrap) "deal_id" else NULL, cband = bstrap, print_details = FALSE
  )
  dynamic <- did::aggte(
    att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5, na.rm = TRUE,
    bstrap = bstrap, biters = if (bstrap) 999 else 1,
    clustervars = if (bstrap) "deal_id" else NULL, cband = bstrap
  )
  pretrend_p <- if (!is.null(att$Wpval) && length(att$Wpval) == 1) as.numeric(att$Wpval) else NA_real_

  coefs <- data.frame(
    outcome = outcome, label = label,
    n_inventors = length(unique(data$codinv)), n_deals = length(unique(data$deal_id)),
    event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )
  message("Pretrend p (all pre-periods, universal base) = ", round(pretrend_p, 4))
  print(coefs[c("event_time", "att", "se")])

  saveRDS(att, file.path(RESULTS, paste0("att_gt_", outcome, "_", label, ".rds")))
  saveRDS(dynamic, file.path(RESULTS, paste0("aggte_", outcome, "_", label, ".rds")))
  write_result(coefs, paste0("dynamic_att_", outcome, "_", label, ".csv"))
  write_result(
    data.frame(outcome = outcome, label = label, pretrend_p_all_preperiods = pretrend_p),
    paste0("pretrend_", outcome, "_", label, ".csv")
  )
  list(att = att, dynamic = dynamic, coefs = coefs, pretrend_p = pretrend_p)
}

banner("PRIMARY CS(2021): UNIVERSAL BASE, ANTICIPATION=1, DEAL-CLUSTERED BOOTSTRAP")

outcomes <- c("active_patenting", "log_patent_count", "moved_thirdparty")
primary_results <- lapply(outcomes, run_primary)
names(primary_results) <- outcomes

all_coefs <- do.call(rbind, lapply(primary_results, `[[`, "coefs"))
write_result(all_coefs, "primary_all_dynamic_att.csv")

banner("PRIMARY FIGURE")

label_map <- c(active_patenting = "Active patenting (any patent this year)",
               log_patent_count = "Log(1 + patents)",
               moved_thirdparty = "Moved to known outside group")
all_coefs$label_pretty <- label_map[all_coefs$outcome]

p <- ggplot2::ggplot(all_coefs, ggplot2::aes(x = event_time, y = att)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey55") +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = att - 1.96 * se, ymax = att + 1.96 * se),
    fill = "#1b4332", alpha = 0.15
  ) +
  ggplot2::geom_line(colour = "#1b4332", linewidth = 0.9) +
  ggplot2::geom_point(colour = "#1b4332", size = 1.8) +
  ggplot2::facet_wrap(~label_pretty, scales = "free_y", ncol = 3) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition", y = "Group-time average treatment effect",
    subtitle = "Primary CS(2021): lean predetermined xformla, universal base, anticipation = 1",
    caption = "Deal-clustered multiplier bootstrap (999 iters); pointwise 95% CI shown."
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    plot.subtitle = ggplot2::element_text(colour = "#9c4f1c", face = "italic"),
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )

primary_figure <- file.path(FIGS, "figure6_cs2021_primary.png")
ggplot2::ggsave(primary_figure, p, width = 10.5, height = 4.0, dpi = 300)

banner("PRIMARY ESTIMATION COMPLETE")
message("Outputs: ", RESULTS)
message("Figure: ", primary_figure)
