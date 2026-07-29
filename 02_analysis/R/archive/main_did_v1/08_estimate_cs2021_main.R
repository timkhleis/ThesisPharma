# Preliminary unconditional Callaway-Sant'Anna (2021) estimates
#
# Prerequisite (run separately from this script):
#   install.packages("did", lib = ".r_libs", repos = "https://cloud.r-project.org")
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08_estimate_cs2021_main.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021")
FIGURES <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
# The archived runner lives in an authoritative worktree, while the shared
# repository package cache is one level above the worktree collection. Add it
# explicitly so the reproduction works from a clean checkout.
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}

required_packages <- c("DBI", "duckdb", "did", "ggplot2")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop(
    "Missing required package(s): ", paste(missing_packages, collapse = ", "),
    ". Install them separately into .r_libs before estimation."
  )
}

dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGURES, recursive = TRUE, showWarnings = FALSE)

write_csv_base <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

if (!DBI::dbExistsTable(con, "cs2021_estimation_panel")) {
  stop("Missing cs2021_estimation_panel. Run 06_build_event_panel.R first.")
}

panel <- DBI::dbGetQuery(con, "
SELECT
  CAST(codinv AS DOUBLE) AS codinv,
  CAST(deal_id AS INTEGER) AS deal_id,
  CAST(deal_year AS INTEGER) AS deal_year,
  CAST(calendar_year AS INTEGER) AS calendar_year,
  CAST(patent_count AS DOUBLE) AS patent_count,
  CAST(active_patenting AS DOUBLE) AS active_patenting
FROM cs2021_estimation_panel
ORDER BY codinv, calendar_year
")

if (anyDuplicated(panel[c("codinv", "calendar_year")]) > 0) {
  stop("cs2021_estimation_panel is not unique by codinv x calendar_year.")
}
if (anyNA(panel[c("codinv", "deal_id", "deal_year", "calendar_year")])) {
  stop("CS panel contains missing identifiers or treatment timing.")
}

seed <- 20260629L
bootstrap_iterations <- 999L

estimate_outcome <- function(outcome) {
  set.seed(seed)
  att <- did::att_gt(
    yname = outcome,
    tname = "calendar_year",
    idname = "codinv",
    gname = "deal_year",
    xformla = ~1,
    data = panel,
    panel = TRUE,
    allow_unbalanced_panel = FALSE,
    control_group = "notyettreated",
    anticipation = 0,
    est_method = "dr",
    bstrap = TRUE,
    biters = bootstrap_iterations,
    clustervars = "deal_id",
    cband = TRUE,
    print_details = TRUE
  )

  set.seed(seed)
  dynamic <- did::aggte(
    att,
    type = "dynamic",
    balance_e = 5,
    min_e = -5,
    max_e = 5,
    na.rm = TRUE,
    bstrap = TRUE,
    biters = bootstrap_iterations,
    clustervars = "deal_id",
    cband = TRUE
  )

  critical_value <- if (!is.null(dynamic$crit.val.egt)) dynamic$crit.val.egt else 1.96
  coefficients <- data.frame(
    outcome = outcome,
    event_time = dynamic$egt,
    att = dynamic$att.egt,
    std_error = dynamic$se.egt,
    conf_low = dynamic$att.egt - critical_value * dynamic$se.egt,
    conf_high = dynamic$att.egt + critical_value * dynamic$se.egt
  )

  pretrend <- data.frame(
    outcome = outcome,
    # did::att_gt() does not return its analytic Wald pre-test when the
    # bootstrap is clustered above the unit level. Record NA explicitly;
    # the bootstrap confidence bands remain the appropriate diagnostic.
    joint_pretrend_p_value = if (length(att$Wpval)) as.numeric(att$Wpval) else NA_real_,
    bootstrap_iterations = bootstrap_iterations,
    clustered_by = "deal_id",
    covariates = "none",
    pretrend_inference_note = "Analytic Wald p-value unavailable under deal-level clustering; inspect bootstrap event-study intervals."
  )

  saveRDS(att, file.path(RESULTS, paste0("att_gt_", outcome, ".rds")))
  saveRDS(dynamic, file.path(RESULTS, paste0("aggte_dynamic_", outcome, ".rds")))
  write_csv_base(coefficients, paste0("dynamic_att_", outcome, ".csv"))
  write_csv_base(pretrend, paste0("pretrend_", outcome, ".csv"))

  list(att = att, dynamic = dynamic, coefficients = coefficients, pretrend = pretrend)
}

results <- lapply(c("patent_count", "active_patenting"), estimate_outcome)
names(results) <- c("patent_count", "active_patenting")

cohort_years <- sort(unique(panel$deal_year))
support <- do.call(rbind, lapply(-5:5, function(event_time) {
  eligible <- cohort_years[cohort_years <= 2010]
  comparison_year <- eligible + event_time
  supported <- vapply(
    comparison_year,
    function(year) any(cohort_years > year),
    logical(1)
  )
  data.frame(
    event_time = event_time,
    n_contributing_cohorts = sum(supported),
    first_contributing_cohort = if (any(supported)) min(eligible[supported]) else NA,
    last_contributing_cohort = if (any(supported)) max(eligible[supported]) else NA
  )
}))
write_csv_base(support, "dynamic_cohort_support.csv")

plot_data <- rbind(
  transform(results$patent_count$coefficients, outcome_label = "Patent count"),
  transform(results$active_patenting$coefficients, outcome_label = "Active patenting")
)

p <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(x = event_time, y = att, ymin = conf_low, ymax = conf_high)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey45", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey45") +
  ggplot2::geom_errorbar(width = 0.15, colour = "#1b4332") +
  ggplot2::geom_line(colour = "#1b4332", linewidth = 0.8) +
  ggplot2::geom_point(colour = "#1b4332", size = 1.8) +
  ggplot2::facet_wrap(~outcome_label, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition",
    y = "Group-time average treatment effect",
    subtitle = "Preliminary unconditional CS(2021); deal-clustered uniform confidence bands"
  ) +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank())

ggplot2::ggsave(
  file.path(FIGURES, "figure4_cs2021_preliminary.png"),
  p,
  width = 9.0,
  height = 4.2,
  dpi = 300
)

message("CS(2021) estimation complete: ", RESULTS)
