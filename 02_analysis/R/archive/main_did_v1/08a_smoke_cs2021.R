# Controlled CS(2021) smoke tests and fixed-effects replication.
# Point estimates are diagnostic: CS inference is not deal-clustered in this script.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08a_smoke_cs2021.R

BASE   <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
SMOKE  <- file.path(BASE, "output", "results", "cs2021_smoke_controlled")
FIGS   <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()

for (pkg in c("DBI", "duckdb", "did", "fixest", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

dir.create(SMOKE, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_smoke <- function(df, filename) {
  utils::write.csv(df, file.path(SMOKE, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

if (!DBI::dbExistsTable(con, "cs2021_estimation_panel")) {
  stop("Missing cs2021_estimation_panel. Run 06_build_event_panel.R first.")
}

required_columns <- c(
  "codinv", "deal_id", "deal_year", "calendar_year", "event_time",
  "status_available", "left_this_year", "rd_activity", "log_patent_count",
  "active_patenting", "known_outside_switch",
  "log_predeal_patent_stock", "predeal_active_rate_5y",
  "log_career_age_at_deal", "log_observed_target_patent_tenure",
  "in_narrow_cohort_window"
)
panel_columns <- DBI::dbListFields(con, "cs2021_estimation_panel")
missing_columns <- setdiff(required_columns, panel_columns)
if (length(missing_columns) > 0) {
  stop(
    "CS panel is missing controlled-DiD columns: ",
    paste(missing_columns, collapse = ", "),
    ". Re-run 06_build_event_panel.R."
  )
}

banner("LOADING CONTROLLED CS PANEL")

panel <- DBI::dbGetQuery(con, "
SELECT
  CAST(codinv AS DOUBLE) AS codinv,
  CAST(deal_id AS INTEGER) AS deal_id,
  CAST(deal_year AS INTEGER) AS deal_year,
  CAST(calendar_year AS INTEGER) AS calendar_year,
  CAST(event_time AS INTEGER) AS event_time,
  CAST(status_available AS BOOLEAN) AS status_available,
  CAST(left_this_year AS DOUBLE) AS left_this_year,
  CAST(rd_activity AS DOUBLE) AS rd_activity,
  CAST(log_patent_count AS DOUBLE) AS log_patent_count,
  CAST(active_patenting AS DOUBLE) AS active_patenting,
  CAST(known_outside_switch AS DOUBLE) AS known_outside_switch,
  CAST(log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
  CAST(predeal_active_rate_5y AS DOUBLE) AS predeal_active_rate_5y,
  CAST(log_career_age_at_deal AS DOUBLE) AS log_career_age_at_deal,
  CAST(log_observed_target_patent_tenure AS DOUBLE)
    AS log_observed_target_patent_tenure,
  CAST(in_narrow_cohort_window AS BOOLEAN) AS in_narrow_cohort_window
FROM cs2021_estimation_panel
ORDER BY codinv, calendar_year
")

stopifnot(
  anyDuplicated(panel[c("codinv", "calendar_year")]) == 0,
  !anyNA(panel[c(
    "codinv", "deal_id", "deal_year", "calendar_year",
    "rd_activity", "log_patent_count", "log_predeal_patent_stock",
    "predeal_active_rate_5y", "log_career_age_at_deal",
    "log_observed_target_patent_tenure"
  )])
)
if (any(panel$status_available & is.na(panel$left_this_year))) {
  stop("left_this_year is missing in the acquirer-resolved sample.")
}

message(
  "Panel: ", nrow(panel), " rows | ",
  length(unique(panel$codinv)), " inventors | ",
  length(unique(panel$deal_id)), " deals | ",
  length(unique(panel$calendar_year)), " years"
)

outcome_config <- data.frame(
  outcome = c("left_this_year", "rd_activity", "active_patenting", "log_patent_count"),
  sample  = c("acquirer_resolved", "full_cohort", "full_cohort", "full_cohort"),
  label   = c(
    "Exit year (left this year)",
    "R&D survival (career ongoing)",
    "Active patenting (any patent this year)",
    "Log(1 + patents)"
  ),
  stringsAsFactors = FALSE
)

controlled_formula <- ~ log_predeal_patent_stock +
  predeal_active_rate_5y +
  log_career_age_at_deal +
  log_observed_target_patent_tenure

subset_for_outcome <- function(data, outcome) {
  if (outcome %in% c("left_this_year", "known_outside_switch")) {
    data[data$status_available, , drop = FALSE]
  } else {
    data
  }
}

collect_support <- function(att, outcome, specification) {
  support <- data.frame(
    group = att$group,
    calendar_year = att$t,
    att = att$att
  )
  support$event_time <- support$calendar_year - support$group
  support <- support[
    support$event_time >= -5 & support$event_time <= 5 & is.finite(support$att),
    ,
    drop = FALSE
  ]
  if (nrow(support) == 0) {
    return(data.frame())
  }
  result <- aggregate(
    group ~ event_time,
    data = unique(support[c("event_time", "group")]),
    FUN = length
  )
  names(result)[2] <- "n_contributing_cohorts"
  result$outcome <- outcome
  result$specification <- specification
  result[c("outcome", "specification", "event_time", "n_contributing_cohorts")]
}

warning_log <- list()

run_cs <- function(outcome, specification, xformla, anticipation,
                   base_period_arg = "universal", data_override = NULL) {
  data <- if (!is.null(data_override)) data_override else subset_for_outcome(panel, outcome)
  section(paste("CS", specification, outcome, sep = " | "))
  messages <- character()

  set.seed(20260701L)
  att <- withCallingHandlers(
    did::att_gt(
      yname = outcome,
      tname = "calendar_year",
      idname = "codinv",
      gname = "deal_year",
      xformla = xformla,
      data = data,
      panel = TRUE,
      allow_unbalanced_panel = FALSE,
      control_group = "notyettreated",
      anticipation = anticipation,
      base_period = base_period_arg,
      est_method = "dr",
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
      att,
      type = "dynamic",
      balance_e = 5,
      min_e = -4,
      max_e = 5,
      na.rm = TRUE,
      bstrap = FALSE,
      cband = FALSE
    ),
    warning = function(w) {
      messages <<- c(messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  coefs <- data.frame(
    outcome = outcome,
    specification = specification,
    anticipation = anticipation,
    reference_period = if (anticipation == 0) -1L else -2L,
    sample = if (outcome %in% c("left_this_year", "known_outside_switch")) {
      "acquirer_resolved"
    } else {
      "full_cohort"
    },
    n_inventors = length(unique(data$codinv)),
    n_deals = length(unique(data$deal_id)),
    event_time = dynamic$egt,
    att = dynamic$att.egt,
    analytical_se_unclustered = dynamic$se.egt
  )

  pretrend_p <- if (!is.null(att$Wpval) && length(att$Wpval) == 1) {
    as.numeric(att$Wpval)
  } else {
    NA_real_
  }
  pretrend <- data.frame(
    outcome = outcome,
    specification = specification,
    anticipation = anticipation,
    pretrend_p_unclustered = pretrend_p,
    inference_status = "diagnostic only; no deal clustering"
  )

  warning_log[[length(warning_log) + 1L]] <<- data.frame(
    outcome = outcome,
    specification = specification,
    warning = if (length(messages) == 0) "" else unique(messages),
    stringsAsFactors = FALSE
  )

  saveRDS(att, file.path(SMOKE, paste0("att_gt_", outcome, "_", specification, ".rds")))
  saveRDS(dynamic, file.path(SMOKE, paste0("aggte_", outcome, "_", specification, ".rds")))
  write_smoke(coefs, paste0("dynamic_att_", outcome, "_", specification, ".csv"))
  write_smoke(pretrend, paste0("pretrend_", outcome, "_", specification, ".csv"))

  message(
    "N = ", length(unique(data$codinv)), " | deals = ", length(unique(data$deal_id)),
    " | warnings = ", length(unique(messages))
  )
  print(coefs[c("event_time", "att", "analytical_se_unclustered")])

  list(
    att = att,
    dynamic = dynamic,
    coefs = coefs,
    support = collect_support(att, outcome, specification),
    pretrend = pretrend
  )
}

banner("MAIN CS SMOKE: UNIVERSAL BASE, NO ANTICIPATION")

main_results <- list()
for (outcome in outcome_config$outcome) {
  main_results[[paste0(outcome, "_controlled")]] <- run_cs(
    outcome, "controlled_main", controlled_formula, anticipation = 0
  )
  main_results[[paste0(outcome, "_uncontrolled")]] <- run_cs(
    outcome, "uncontrolled_main", ~1, anticipation = 0
  )
}

banner("ANTICIPATION ROBUSTNESS: ONE YEAR")

anticipation_results <- list()
for (outcome in outcome_config$outcome) {
  anticipation_results[[outcome]] <- run_cs(
    outcome, "controlled_anticipation1", controlled_formula, anticipation = 1
  )
}

banner("KNOWN OUTSIDE SWITCH DIAGNOSTIC")

outside_result <- run_cs(
  "known_outside_switch",
  "controlled_diagnostic",
  controlled_formula,
  anticipation = 0
)

banner("VARYING BASE PERIOD — LOG PATENT COUNT")

varying_result <- run_cs(
  "log_patent_count", "controlled_varying_base",
  controlled_formula, anticipation = 0,
  base_period_arg = "varying"
)

banner("NARROW COHORT WINDOW ROBUSTNESS (-3..-1)")

narrow_results <- list()
for (outcome in outcome_config$outcome) {
  narrow_data <- subset_for_outcome(
    panel[panel$in_narrow_cohort_window, , drop = FALSE],
    outcome
  )
  narrow_results[[outcome]] <- run_cs(
    outcome, "narrow_window_controlled", controlled_formula,
    anticipation = 0, data_override = narrow_data
  )
}
narrow_n_inv   <- length(unique(panel$codinv[panel$in_narrow_cohort_window]))
narrow_n_deals <- length(unique(panel$deal_id[panel$in_narrow_cohort_window]))
message("Narrow window: ", narrow_n_inv, " inventors | ", narrow_n_deals, " deals")

banner("VERGINER BENCHMARK SUBSAMPLE (acquirer R&D-active post-deal)")

verginer_deal_ids <- tryCatch(
  DBI::dbGetQuery(con, "
    SELECT DISTINCT s.deal_id
    FROM cassi_deal_group_spine s
    JOIN group_ipc_year g ON g.id_group = s.acquirer_group AND g.year > s.deal_year
    WHERE CAST(s.acquirer_group AS VARCHAR) NOT LIKE '999%'
  ")$deal_id,
  error = function(e) {
    message("Verginer filter query failed: ", conditionMessage(e))
    integer(0)
  }
)
verginer_results <- list()
if (length(verginer_deal_ids) > 0) {
  for (outcome in c("log_patent_count", "active_patenting")) {
    vdata <- subset_for_outcome(
      panel[panel$deal_id %in% verginer_deal_ids, , drop = FALSE],
      outcome
    )
    verginer_results[[outcome]] <- run_cs(
      outcome, "verginer_subsample", controlled_formula,
      anticipation = 0, data_override = vdata
    )
  }
  message("Verginer subsample: ", sum(panel$deal_id %in% verginer_deal_ids & !duplicated(panel$codinv[panel$deal_id %in% verginer_deal_ids])), " deals matched")
} else {
  message("Verginer filter returned 0 deals — skipping subsample.")
}

all_cs_results <- c(
  main_results, anticipation_results, list(outside_result),
  list(varying_result), narrow_results, verginer_results
)
all_cs_coefs <- do.call(rbind, lapply(all_cs_results, `[[`, "coefs"))
all_support <- do.call(rbind, lapply(all_cs_results, `[[`, "support"))
all_pretrends <- do.call(rbind, lapply(all_cs_results, `[[`, "pretrend"))
all_warnings <- do.call(rbind, warning_log)

write_smoke(all_cs_coefs, "cs_smoke_all_estimates.csv")
write_smoke(all_support, "cs_smoke_cohort_support.csv")
write_smoke(all_pretrends, "cs_smoke_pretrend_diagnostics.csv")
write_smoke(all_warnings, "cs_smoke_warnings.csv")

main_controlled <- all_cs_coefs[all_cs_coefs$specification == "controlled_main", ]
main_uncontrolled <- all_cs_coefs[all_cs_coefs$specification == "uncontrolled_main", ]
controlled_comparison <- merge(
  main_controlled[c("outcome", "event_time", "att")],
  main_uncontrolled[c("outcome", "event_time", "att")],
  by = c("outcome", "event_time"),
  suffixes = c("_controlled", "_uncontrolled")
)
controlled_comparison$difference <-
  controlled_comparison$att_controlled - controlled_comparison$att_uncontrolled
write_smoke(controlled_comparison, "controlled_vs_uncontrolled.csv")

anticipation_coefs <- all_cs_coefs[
  all_cs_coefs$specification == "controlled_anticipation1",
]
anticipation_comparison <- merge(
  main_controlled[c("outcome", "event_time", "att")],
  anticipation_coefs[c("outcome", "event_time", "att")],
  by = c("outcome", "event_time"),
  suffixes = c("_reference_m1", "_anticipation1_reference_m2")
)
write_smoke(anticipation_comparison, "anticipation_robustness.csv")

banner("FIXED-EFFECTS REPLICATION")

run_fe <- function(outcome) {
  fe_outcome <- outcome
  data <- subset_for_outcome(panel, fe_outcome)
  data$event_time_binned <- ifelse(
    data$event_time < -5,
    -6L,
    ifelse(data$event_time > 5, 6L, data$event_time)
  )
  section(paste("FE |", outcome))

  model_formula <- stats::as.formula(
    paste0(fe_outcome, " ~ i(event_time_binned, ref = -1) | codinv + calendar_year")
  )
  model <- fixest::feols(
    model_formula,
    data = data,
    cluster = ~deal_id,
    notes = FALSE
  )
  table <- summary(model)$coeftable
  terms <- rownames(table)
  keep <- grepl("^event_time_binned::", terms)
  terms <- terms[keep]
  table <- table[keep, , drop = FALSE]
  event_time <- as.integer(sub("^event_time_binned::(-?[0-9]+).*$", "\\1", terms))
  report <- event_time >= -5 & event_time <= 5
  event_time <- event_time[report]
  table <- table[report, , drop = FALSE]

  result <- data.frame(
    outcome = outcome,
    specification = "twfe_inventor_year_fe_full_panel",
    sample = if (fe_outcome == "left_this_year") "acquirer_resolved" else "full_cohort",
    n_inventors = length(unique(data$codinv)),
    n_deals = length(unique(data$deal_id)),
    event_time = event_time,
    estimate = table[, "Estimate"],
    deal_clustered_se = table[, "Std. Error"],
    p_value = table[, "Pr(>|t|)"],
    stringsAsFactors = FALSE
  )
  result <- rbind(
    result,
    data.frame(
      outcome = outcome,
      specification = "twfe_inventor_year_fe_full_panel",
      sample = if (fe_outcome == "left_this_year") "acquirer_resolved" else "full_cohort",
      n_inventors = length(unique(data$codinv)),
      n_deals = length(unique(data$deal_id)),
      event_time = -1L,
      estimate = 0,
      deal_clustered_se = NA_real_,
      p_value = NA_real_
    )
  )
  result <- result[order(result$event_time), ]
  saveRDS(model, file.path(SMOKE, paste0("twfe_", outcome, ".rds")))
  print(result[c("event_time", "estimate", "deal_clustered_se")])
  result
}

fe_results <- do.call(rbind, lapply(outcome_config$outcome, run_fe))
write_smoke(fe_results, "twfe_replication_estimates.csv")

cs_fe_comparison <- merge(
  main_controlled[c("outcome", "event_time", "att")],
  fe_results[c("outcome", "event_time", "estimate", "deal_clustered_se")],
  by = c("outcome", "event_time"),
  all = TRUE
)
names(cs_fe_comparison)[names(cs_fe_comparison) == "att"] <- "cs_controlled_att"
names(cs_fe_comparison)[names(cs_fe_comparison) == "estimate"] <- "twfe_estimate"
write_smoke(cs_fe_comparison, "cs_vs_twfe_comparison.csv")

banner("SMOKE FIGURES")

plot_data <- merge(
  main_controlled,
  outcome_config[c("outcome", "label")],
  by = "outcome",
  all.x = TRUE
)

p <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(x = event_time, y = att, group = 1)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey55") +
  ggplot2::geom_line(colour = "#1b4332", linewidth = 0.9) +
  ggplot2::geom_point(colour = "#1b4332", size = 1.8) +
  ggplot2::facet_wrap(~label, scales = "free_y", ncol = 3) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition",
    y = "Group-time average treatment effect",
    subtitle = "Controlled CS(2021) smoke estimates; universal t = -1 reference",
    caption = paste(
      "Diagnostic point estimates only: no deal-clustered CS inference.",
      "Leaving uses the acquirer-resolved sample; other outcomes use the full cohort."
    )
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    plot.subtitle = ggplot2::element_text(colour = "#9c4f1c", face = "italic"),
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )

main_figure <- file.path(FIGS, "figure4_cs2021_controlled_smoke.png")
ggplot2::ggsave(main_figure, p, width = 10.5, height = 4.0, dpi = 300)

outside_plot <- outside_result$coefs
p_outside <- ggplot2::ggplot(
  outside_plot,
  ggplot2::aes(x = event_time, y = att)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey55") +
  ggplot2::geom_line(colour = "#7a3e00", linewidth = 0.9) +
  ggplot2::geom_point(colour = "#7a3e00", size = 1.8) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition",
    y = "ATT",
    title = "Known outside-group switch",
    subtitle = "Controlled CS(2021) diagnostic; no deal-clustered inference"
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank())

outside_figure <- file.path(FIGS, "figure4b_known_outside_switch_smoke.png")
ggplot2::ggsave(outside_figure, p_outside, width = 5.5, height = 4.0, dpi = 300)

key_events <- main_controlled[main_controlled$event_time %in% c(-5, -4, -3, -2, 0, 1, 5), ]
write_smoke(key_events, "controlled_main_key_events.csv")

banner("CONTROLLED SMOKE COMPLETE")
print(key_events[c("outcome", "event_time", "att")])
message("Main figure: ", main_figure)
message("Outside-switch figure: ", outside_figure)
message("Outputs: ", SMOKE)
