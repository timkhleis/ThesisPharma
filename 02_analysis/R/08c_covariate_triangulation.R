# Phase 2 covariate/IPW triangulation: lean, predetermined-only xformla,
# compared across est_method in {dr, reg, ipw} plus an uncontrolled (~1)
# baseline. Point estimates are diagnostic (no deal-clustered bootstrap here,
# matching the convention already used in 08a_smoke_cs2021.R) -- the goal is
# to see whether dr/ipw diverge from reg/uncontrolled, which would signal an
# overlap/positivity problem in the propensity model, per the pre-registered
# decision rule: if they diverge, inspect trimming / fall back to reg.
#
# xformla is deliberately PREDETERMINED-only: no pre-deal outcome slope term.
# A slope conditions on (and can mechanically flatten) the very pre-trend
# this thesis is trying to test, which is circular. Trajectory MATCHING
# (a separate script) is the transparent alternative to a slope covariate.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08c_covariate_triangulation.R

BASE   <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_triangulation")
FIGS   <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()

for (pkg in c("DBI", "duckdb", "did", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS,    recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_result <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

if (!DBI::dbExistsTable(con, "cs2021_estimation_panel")) {
  stop("Missing cs2021_estimation_panel. Run 06_build_event_panel.R first.")
}

required_columns <- c(
  "codinv", "deal_id", "deal_year", "calendar_year", "event_time",
  "active_patenting", "log_patent_count", "moved_thirdparty",
  "career_age_at_deal", "career_age_sq_at_deal", "ipc_primary_field",
  "log_predeal_patent_stock", "log_group_size", "log_deal_value"
)
panel_columns <- DBI::dbListFields(con, "cs2021_estimation_panel")
missing_columns <- setdiff(required_columns, panel_columns)
if (length(missing_columns) > 0) {
  stop(
    "CS panel is missing triangulation columns: ",
    paste(missing_columns, collapse = ", "),
    ". Re-run 06_build_event_panel.R."
  )
}

banner("LOADING PANEL FOR COVARIATE TRIANGULATION")

panel <- DBI::dbGetQuery(con, "
SELECT
  CAST(codinv AS DOUBLE) AS codinv,
  CAST(deal_id AS INTEGER) AS deal_id,
  CAST(deal_year AS INTEGER) AS deal_year,
  CAST(calendar_year AS INTEGER) AS calendar_year,
  CAST(event_time AS INTEGER) AS event_time,
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

stopifnot(
  anyDuplicated(panel[c("codinv", "calendar_year")]) == 0,
  !anyNA(panel[c(
    "codinv", "deal_id", "deal_year", "calendar_year",
    "career_age_at_deal", "career_age_sq_at_deal",
    "log_predeal_patent_stock", "log_group_size", "log_deal_value"
  )])
)

message(
  "Panel: ", nrow(panel), " rows | ",
  length(unique(panel$codinv)), " inventors | ",
  length(unique(panel$deal_id)), " deals | ",
  "IPC levels: ", paste(levels(panel$ipc_primary_field), collapse = ", ")
)

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

outcomes <- c("active_patenting", "log_patent_count", "moved_thirdparty")

run_triangulation <- function(outcome, specification, xformla, est_method) {
  section(paste(specification, "|", outcome, "| est_method =", est_method))
  set.seed(20260701L)
  messages <- character()

  att <- withCallingHandlers(
    did::att_gt(
      yname = outcome,
      tname = "calendar_year",
      idname = "codinv",
      gname = "deal_year",
      xformla = xformla,
      data = panel,
      panel = TRUE,
      allow_unbalanced_panel = FALSE,
      control_group = "notyettreated",
      anticipation = 1,
      base_period = "varying",
      est_method = est_method,
      bstrap = FALSE,
      cband = FALSE,
      print_details = FALSE
    ),
    warning = function(w) {
      messages <<- c(messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  dynamic <- withCallingHandlers(
    did::aggte(
      att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5,
      na.rm = TRUE, bstrap = FALSE, cband = FALSE
    ),
    warning = function(w) {
      messages <<- c(messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  pretrend_p <- if (!is.null(att$Wpval) && length(att$Wpval) == 1) {
    as.numeric(att$Wpval)
  } else {
    NA_real_
  }

  message("  warnings: ", length(unique(messages)), " | pretrend p = ", round(pretrend_p, 4))

  data.frame(
    outcome = outcome,
    specification = specification,
    est_method = est_method,
    event_time = dynamic$egt,
    att = dynamic$att.egt,
    analytical_se_unclustered = dynamic$se.egt,
    pretrend_p_unclustered = pretrend_p,
    n_warnings = length(unique(messages))
  )
}

banner("TRIANGULATION: DR / REG / IPW / UNCONTROLLED")

all_results <- list()
for (outcome in outcomes) {
  for (method in c("dr", "reg", "ipw")) {
    key <- paste(outcome, method, sep = "_")
    all_results[[key]] <- run_triangulation(outcome, "lean_controlled", xformla_lean, method)
  }
  all_results[[paste0(outcome, "_uncontrolled")]] <-
    run_triangulation(outcome, "uncontrolled", ~1, "reg")
}

triangulation_estimates <- do.call(rbind, all_results)
rownames(triangulation_estimates) <- NULL
write_result(triangulation_estimates, "triangulation_dr_reg_ipw_uncontrolled.csv")

banner("DIVERGENCE DIAGNOSTIC")

wide <- reshape(
  triangulation_estimates[c("outcome", "event_time", "specification", "est_method", "att")],
  timevar = "est_method",
  idvar = c("outcome", "event_time", "specification"),
  direction = "wide"
)
wide_uncontrolled <- triangulation_estimates[
  triangulation_estimates$specification == "uncontrolled",
  c("outcome", "event_time", "att")
]
names(wide_uncontrolled)[3] <- "att.uncontrolled"
wide_controlled <- wide[wide$specification == "lean_controlled", ]
divergence <- merge(wide_controlled, wide_uncontrolled, by = c("outcome", "event_time"))
att_cols <- c("att.dr", "att.reg", "att.ipw", "att.uncontrolled")
divergence$max_abs_divergence <- apply(
  divergence[att_cols], 1, function(x) max(x, na.rm = TRUE) - min(x, na.rm = TRUE)
)
divergence <- divergence[order(divergence$outcome, divergence$event_time), ]
write_result(divergence, "triangulation_divergence_by_event_time.csv")
print(divergence[c("outcome", "event_time", att_cols, "max_abs_divergence")])

banner("TRIANGULATION FIGURE")

plot_data <- triangulation_estimates
plot_data$spec_label <- ifelse(
  plot_data$specification == "uncontrolled", "uncontrolled",
  paste0("controlled (", plot_data$est_method, ")")
)

p <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(x = event_time, y = att, colour = spec_label, group = spec_label)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey55") +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.5) +
  ggplot2::facet_wrap(~outcome, scales = "free_y", ncol = 3) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition",
    y = "Group-time average treatment effect",
    colour = "Specification",
    subtitle = "Lean predetermined-only xformla; anticipation = 1, varying base period",
    caption = "Diagnostic point estimates only: no deal-clustered CS inference."
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )

triangulation_figure <- file.path(FIGS, "figure5_covariate_triangulation.png")
ggplot2::ggsave(triangulation_figure, p, width = 10.5, height = 4.2, dpi = 300)

banner("COVARIATE TRIANGULATION COMPLETE")
message("Outputs: ", RESULTS)
message("Figure: ", triangulation_figure)
