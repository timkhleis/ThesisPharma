# Verginer--Riccaboni design reconstruction.
#
# This script emulates the closest published design one component at a time.
# It is deliberately standalone: it reads the existing DuckDB in read-only mode,
# does not modify the database, and writes only reconstruction results/figures.
#
# Run from the project root after 06_build_event_panel.R:
#   & 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis/R/08p_verginer_reconstruction.R
# Add --resume to reuse completed per-specification CSVs after an interrupted run.

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "verginer_reconstruction")
FIGS    <- file.path(BASE, "output", "figures", "preliminary_results")
RESUME  <- "--resume" %in% commandArgs(trailingOnly = TRUE)
DESIGN_VERSION <- "vr_reconstruction_v2"

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()

for (pkg in c("DBI", "duckdb", "did", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

banner <- function(x) message("\n", strrep("=", 72), "\n  ", x, "\n", strrep("=", 72))
section <- function(x) message("\n--- ", x, " ---")
write_result <- function(x, filename) {
  utils::write.csv(x, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

required_tables <- c(
  "cs2021_estimation_panel", "deal_map", "cassi_deal_group_spine",
  "group_ipc_year", "patent_inventor_enriched", "oecd_quality"
)
missing_tables <- required_tables[
  !vapply(required_tables, DBI::dbExistsTable, logical(1), conn = con)
]
if (length(missing_tables) > 0L) {
  stop("Missing required tables: ", paste(missing_tables, collapse = ", "))
}

banner("LOAD PANEL AND CONSTRUCT VERGINER--RICCABONI OUTCOMES")

# patent_inventor_enriched contains repeated patent--inventor rows because it
# retains patent-level group/IPC links. Deduplicate before summing citations.
panel <- DBI::dbGetQuery(con, "
WITH cohort AS (
  SELECT DISTINCT codinv FROM cs2021_estimation_panel
),
patent_inventor_unique AS (
  SELECT DISTINCT p.appln_id, p.codinv, p.year
  FROM patent_inventor_enriched p
  JOIN cohort c ON c.codinv = CAST(p.codinv AS BIGINT)
),
inventor_year_citations AS (
  SELECT
    CAST(p.codinv AS BIGINT) AS codinv,
    CAST(p.year AS INTEGER) AS calendar_year,
    COUNT(*) AS direct_patent_count,
    SUM(COALESCE(q.fwd_cits5, 0)) AS fwd_citations5
  FROM patent_inventor_unique p
  LEFT JOIN oecd_quality q ON q.appln_id = p.appln_id
  GROUP BY p.codinv, p.year
)
SELECT
  CAST(x.codinv AS DOUBLE) AS codinv,
  CAST(x.deal_id AS INTEGER) AS deal_id,
  CAST(x.deal_year AS INTEGER) AS integration_year,
  CAST(dm.target_year AS INTEGER) AS announcement_year,
  CAST(x.calendar_year AS INTEGER) AS calendar_year,
  CAST(x.patent_count AS DOUBLE) AS patent_count,
  CAST(COALESCE(c.direct_patent_count, 0) AS DOUBLE) AS direct_patent_count,
  CAST(COALESCE(c.fwd_citations5, 0) AS DOUBLE) AS fwd_citations5,
  CAST(x.career_end_year AS INTEGER) AS career_end_year,
  CAST(x.last_merged_entity_patent_year AS INTEGER) AS last_merged_entity_patent_year,
  CAST(x.career_age_at_deal AS DOUBLE) AS career_age_at_deal,
  CAST(x.career_age_sq_at_deal AS DOUBLE) AS career_age_sq_at_deal,
  x.ipc_primary_field,
  CAST(x.log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
  CAST(x.log_group_size AS DOUBLE) AS log_group_size,
  CAST(x.log_deal_value AS DOUBLE) AS log_deal_value
FROM cs2021_estimation_panel x
JOIN deal_map dm ON CAST(dm.deal_id AS INTEGER) = x.deal_id
LEFT JOIN inventor_year_citations c
  ON c.codinv = x.codinv AND c.calendar_year = x.calendar_year
ORDER BY x.codinv, x.calendar_year
")

panel$log1p_patents   <- log1p(panel$patent_count)
panel$log1p_citations <- log1p(panel$fwd_citations5)
panel$vr_rd_activity  <- as.numeric(panel$career_end_year >= panel$calendar_year)
panel$vr_left <- as.numeric(panel$last_merged_entity_patent_year < panel$calendar_year)
panel$ipc_primary_field <- factor(panel$ipc_primary_field)

stopifnot(
  nrow(panel) > 0L,
  anyDuplicated(panel[c("codinv", "calendar_year")]) == 0L,
  !anyNA(panel[c(
    "codinv", "deal_id", "integration_year", "announcement_year", "calendar_year",
    "log1p_patents", "log1p_citations", "vr_rd_activity", "vr_left"
  )]),
  all(panel$fwd_citations5 >= 0)
)

# Deal-level post-patent flags. The operational filters require a resolved
# acquirer and any strictly post-deal target/acquirer patent. The literal
# five-year target-group flag is a mapping diagnostic only: old target group
# identifiers normally disappear when the target is re-parented to the buyer.
deal_flags <- DBI::dbGetQuery(con, "
SELECT
  CAST(s.deal_id AS INTEGER) AS deal_id,
  CAST(s.deal_year AS INTEGER) AS spine_year,
  CAST(dm.target_year AS INTEGER) AS announcement_year,
  COALESCE(CAST(s.acquirer_group AS VARCHAR) NOT LIKE '999%', FALSE)
    AS acquirer_resolved,
  EXISTS(
    SELECT 1 FROM group_ipc_year g
    WHERE g.id_group = s.target_group
      AND g.year BETWEEN s.deal_year - 5 AND s.deal_year - 1
  ) AS target_patents_pre5,
  EXISTS(
    SELECT 1 FROM group_ipc_year g
    WHERE g.id_group = s.target_group
      AND g.year > s.deal_year
      AND g.year <= s.deal_year + 5
  ) AS literal_target_survival,
  COALESCE(CAST(s.acquirer_group AS VARCHAR) NOT LIKE '999%', FALSE) AND EXISTS(
    SELECT 1 FROM group_ipc_year g
    WHERE g.id_group = s.acquirer_group
      AND g.year > s.deal_year
  ) AS acquirer_survival,
  COALESCE(CAST(s.acquirer_group AS VARCHAR) NOT LIKE '999%', FALSE) AND EXISTS(
    SELECT 1 FROM group_ipc_year g
    WHERE g.id_group IN (s.target_group, s.acquirer_group)
      AND g.year > s.deal_year
  ) AS merged_entity_survival
FROM cassi_deal_group_spine s
JOIN deal_map dm ON CAST(dm.deal_id AS INTEGER) = CAST(s.deal_id AS INTEGER)
")

deal_flags <- deal_flags[!duplicated(deal_flags$deal_id), ]
panel <- merge(panel, deal_flags, by = c("deal_id", "announcement_year"), all.x = TRUE)
panel <- panel[order(panel$codinv, panel$calendar_year), ]

if (anyNA(panel[c(
  "target_patents_pre5", "literal_target_survival",
  "acquirer_survival", "merged_entity_survival"
)])) {
  stop("Deal survival flags are missing after joining to the estimation panel.")
}

unit_panel <- panel[!duplicated(panel$codinv), ]
audit_samples <- c(
  "full_cohort", "target_patents_pre5", "literal_target_survival_5y",
  "acquirer_survival_any_post", "merged_entity_survival_any_post"
)
sample_audit <- rbind(
  data.frame(
    scope = "478_deal_spine",
    sample = audit_samples,
    n_inventors = NA_integer_,
    n_deals = c(
      nrow(deal_flags),
      sum(deal_flags$target_patents_pre5),
      sum(deal_flags$literal_target_survival),
      sum(deal_flags$acquirer_survival),
      sum(deal_flags$merged_entity_survival)
    )
  ),
  data.frame(
    scope = "estimation_panel",
    sample = audit_samples,
    n_inventors = c(
      nrow(unit_panel),
      sum(unit_panel$target_patents_pre5),
      sum(unit_panel$literal_target_survival),
      sum(unit_panel$acquirer_survival),
      sum(unit_panel$merged_entity_survival)
    ),
    n_deals = c(
      length(unique(unit_panel$deal_id)),
      length(unique(unit_panel$deal_id[unit_panel$target_patents_pre5])),
      length(unique(unit_panel$deal_id[unit_panel$literal_target_survival])),
      length(unique(unit_panel$deal_id[unit_panel$acquirer_survival])),
      length(unique(unit_panel$deal_id[unit_panel$merged_entity_survival]))
    )
  )
)
stopifnot(
  sample_audit$n_deals[
    sample_audit$scope == "478_deal_spine" &
      sample_audit$sample == "literal_target_survival_5y"
  ] == 6L
)
write_result(sample_audit, "sample_and_survival_audit.csv")
print(sample_audit)

timing_audit <- data.frame(
  n_deals = length(unique(unit_panel$deal_id)),
  n_year_disagreements = length(unique(
    unit_panel$deal_id[unit_panel$integration_year != unit_panel$announcement_year]
  )),
  min_year_difference = min(unit_panel$announcement_year - unit_panel$integration_year),
  max_year_difference = max(unit_panel$announcement_year - unit_panel$integration_year)
)
write_result(timing_audit, "timing_audit.csv")
print(timing_audit)

# Monotonicity audits for the two forward-looking paper outcomes.
left_violations <- sum(unlist(tapply(
  panel$vr_left, panel$codinv, function(x) any(diff(x) < 0)
)))
rd_violations <- sum(unlist(tapply(
  panel$vr_rd_activity, panel$codinv, function(x) any(diff(x) > 0)
)))
outcome_audit <- data.frame(
  check = c(
    "unique_inventor_year",
    "annual_patent_count_matches_distinct_patent_inventor_links",
    "vr_left_matches_entity_patent_endpoint",
    "vr_rd_activity_matches_career_endpoint",
    "vr_left_weakly_increasing",
    "vr_rd_activity_weakly_decreasing",
    "nonnegative_five_year_citations"
  ),
  violations = c(
    anyDuplicated(panel[c("codinv", "calendar_year")]),
    sum(panel$patent_count != panel$direct_patent_count),
    sum(panel$vr_left != as.numeric(
      panel$last_merged_entity_patent_year < panel$calendar_year
    )),
    sum(panel$vr_rd_activity != as.numeric(
      panel$career_end_year >= panel$calendar_year
    )),
    left_violations,
    rd_violations,
    sum(panel$fwd_citations5 < 0)
  )
)
write_result(outcome_audit, "outcome_definition_audit.csv")
print(outcome_audit)
stopifnot(all(outcome_audit$violations == 0))

outcome_labels <- c(
  log1p_patents = "Log(1 + patents)",
  log1p_citations = "Log(1 + five-year forward citations)",
  vr_rd_activity = "R&D activity (forward-looking)",
  vr_left = "Left merged entity (forward-looking)"
)

controlled_formula <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

all_dynamic <- list()
all_overall <- list()
all_pretrend <- list()
all_warnings <- list()

is_controlled_formula <- function(xformla) length(all.vars(xformla)) > 0L

make_pretrend_diagnostic <- function(coefs, att_gt_omnibus_p = NA_real_) {
  pre <- coefs[coefs$event_time >= -5 & coefs$event_time <= -2, ]
  finite <- is.finite(pre$att) & is.finite(pre$se) & pre$se > 0
  jointly_excludes_zero <- finite &
    (pre$ci_lower > 0 | pre$ci_upper < 0)
  data.frame(
    outcome = coefs$outcome[1],
    specification = coefs$specification[1],
    n_pre_points = sum(finite),
    max_abs_pre_att = if (any(finite)) max(abs(pre$att[finite])) else NA_real_,
    max_abs_pre_t = if (any(finite)) {
      max(abs(pre$att[finite] / pre$se[finite]))
    } else {
      NA_real_
    },
    n_pre_reported_intervals_exclude_zero = sum(jointly_excludes_zero),
    all_pre_reported_intervals_cover_zero = !any(jointly_excludes_zero),
    att_gt_omnibus_p = att_gt_omnibus_p,
    inference_note = if (isTRUE(coefs$bootstrap[1])) {
      "deal-clustered multiplier bootstrap; dynamic intervals simultaneous"
    } else {
      "analytical unclustered diagnostic"
    }
  )
}

run_spec <- function(outcome, specification, data, treatment_year,
                     base_period, balance_e, xformla, bootstrap) {
  section(paste(specification, outcome, sep = " | "))
  d <- data
  d$est_deal_year <- d[[treatment_year]]
  d$event_time_est <- d$calendar_year - d$est_deal_year
  messages <- character()

  set.seed(20260702L)
  att <- withCallingHandlers(
    did::att_gt(
      yname = outcome,
      tname = "calendar_year",
      idname = "codinv",
      gname = "est_deal_year",
      xformla = xformla,
      data = d,
      panel = TRUE,
      allow_unbalanced_panel = FALSE,
      control_group = "notyettreated",
      anticipation = 0,
      base_period = base_period,
      est_method = "dr",
      # Group-time effects are analytical. The requested 999-draw
      # deal-clustered multiplier bootstrap is applied to the reported
      # event-study aggregation below, avoiding redundant first-stage draws.
      bstrap = FALSE,
      biters = NULL,
      clustervars = if (bootstrap) "deal_id" else NULL,
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
      balance_e = balance_e,
      min_e = -5,
      max_e = 5,
      na.rm = TRUE,
      bstrap = bootstrap,
      biters = if (bootstrap) 999L else NULL,
      clustervars = if (bootstrap) "deal_id" else NULL,
      cband = bootstrap
    ),
    warning = function(w) {
      messages <<- c(messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  crit <- if (bootstrap && is.finite(dynamic$crit.val.egt)) {
    as.numeric(dynamic$crit.val.egt)
  } else {
    stats::qnorm(0.975)
  }
  coefs <- data.frame(
    design_version = DESIGN_VERSION,
    outcome = outcome,
    outcome_label = as.character(unname(outcome_labels[outcome])),
    specification = specification,
    treatment_year = treatment_year,
    base_period = base_period,
    balance_e = if (is.null(balance_e)) NA_integer_ else balance_e,
    controlled = is_controlled_formula(xformla),
    bootstrap = bootstrap,
    n_inventors = length(unique(d$codinv)),
    n_deals = length(unique(d$deal_id)),
    event_time = dynamic$egt,
    att = dynamic$att.egt,
    se = dynamic$se.egt,
    critical_value = crit,
    ci_lower = dynamic$att.egt - crit * dynamic$se.egt,
    ci_upper = dynamic$att.egt + crit * dynamic$se.egt
  )

  att_gt_p <- if (!is.null(att$Wpval) && length(att$Wpval) == 1L) {
    as.numeric(att$Wpval)
  } else {
    NA_real_
  }
  if (bootstrap && !is.na(att_gt_p)) {
    att_gt_p <- NA_real_
  }
  pre_diag <- make_pretrend_diagnostic(
    coefs,
    att_gt_omnibus_p = att_gt_p
  )

  overall <- data.frame(
    outcome = outcome,
    specification = specification,
    n_inventors = length(unique(d$codinv)),
    n_deals = length(unique(d$deal_id)),
    overall_dynamic_att = dynamic$overall.att,
    overall_dynamic_se = dynamic$overall.se,
    bootstrap = bootstrap
  )

  warning_df <- if (length(messages) == 0L) {
    data.frame(
      outcome = character(), specification = character(), warning = character()
    )
  } else {
    data.frame(
      outcome = outcome,
      specification = specification,
      warning = unique(messages),
      stringsAsFactors = FALSE
    )
  }

  write_result(coefs, paste0("dynamic_", specification, "_", outcome, ".csv"))
  write_result(overall, paste0("overall_", specification, "_", outcome, ".csv"))
  write_result(pre_diag, paste0("pretrend_", specification, "_", outcome, ".csv"))
  write_result(warning_df, paste0("warnings_", specification, "_", outcome, ".csv"))

  message(
    "N inventors = ", length(unique(d$codinv)),
    " | deals = ", length(unique(d$deal_id)),
    " | overall ATT = ", round(dynamic$overall.att, 4),
    " | warnings = ", length(unique(messages))
  )
  print(coefs[coefs$event_time %in% c(-4, -3, -2, 0, 5), c(
    "event_time", "att", "se", "ci_lower", "ci_upper"
  )])

  rm(att, dynamic)
  gc(verbose = FALSE)
  list(dynamic = coefs, overall = overall, pretrend = pre_diag, warnings = warning_df)
}

load_fit <- function(outcome, specification, treatment_year, base_period,
                     balance_e, xformla, bootstrap) {
  dynamic <- utils::read.csv(file.path(
    RESULTS, paste0("dynamic_", specification, "_", outcome, ".csv")
  ), stringsAsFactors = FALSE)
  overall <- utils::read.csv(file.path(
    RESULTS, paste0("overall_", specification, "_", outcome, ".csv")
  ), stringsAsFactors = FALSE)
  old_pretrend <- utils::read.csv(file.path(
    RESULTS, paste0("pretrend_", specification, "_", outcome, ".csv")
  ), stringsAsFactors = FALSE)

  dynamic$design_version <- DESIGN_VERSION
  dynamic$outcome_label <- as.character(unname(outcome_labels[outcome]))
  dynamic$treatment_year <- treatment_year
  dynamic$base_period <- base_period
  dynamic$balance_e <- if (is.null(balance_e)) NA_integer_ else balance_e
  dynamic$controlled <- is_controlled_formula(xformla)
  dynamic$bootstrap <- bootstrap
  overall$bootstrap <- bootstrap

  old_p <- if ("att_gt_omnibus_p" %in% names(old_pretrend)) {
    suppressWarnings(as.numeric(old_pretrend$att_gt_omnibus_p[1]))
  } else {
    NA_real_
  }
  pretrend <- make_pretrend_diagnostic(dynamic, old_p)

  warning_path <- file.path(
    RESULTS, paste0("warnings_", specification, "_", outcome, ".csv")
  )
  if (file.exists(warning_path)) {
    warnings <- utils::read.csv(warning_path, stringsAsFactors = FALSE)
  } else {
    aggregate_warning_path <- file.path(RESULTS, "estimation_warnings.csv")
    if (file.exists(aggregate_warning_path)) {
      warnings <- utils::read.csv(aggregate_warning_path, stringsAsFactors = FALSE)
      warnings <- warnings[
        warnings$outcome == outcome &
          warnings$specification == specification &
          !is.na(warnings$warning) & nzchar(warnings$warning),
      ]
    } else {
      warnings <- data.frame(
        outcome = character(), specification = character(), warning = character()
      )
    }
  }

  write_result(dynamic, paste0("dynamic_", specification, "_", outcome, ".csv"))
  write_result(overall, paste0("overall_", specification, "_", outcome, ".csv"))
  write_result(pretrend, paste0("pretrend_", specification, "_", outcome, ".csv"))
  write_result(warnings, paste0("warnings_", specification, "_", outcome, ".csv"))
  message("Resumed cached fit: ", specification, " | ", outcome)
  list(dynamic = dynamic, overall = overall, pretrend = pretrend, warnings = warnings)
}

run_or_load_spec <- function(outcome, specification, data, treatment_year,
                             base_period, balance_e, xformla, bootstrap,
                             require_current_version = FALSE) {
  paths <- file.path(RESULTS, c(
    paste0("dynamic_", specification, "_", outcome, ".csv"),
    paste0("overall_", specification, "_", outcome, ".csv"),
    paste0("pretrend_", specification, "_", outcome, ".csv")
  ))
  version_ok <- TRUE
  if (RESUME && all(file.exists(paths)) && require_current_version) {
    header <- names(utils::read.csv(paths[1], nrows = 1, stringsAsFactors = FALSE))
    version_ok <- "design_version" %in% header
  }
  if (RESUME && all(file.exists(paths)) && version_ok) {
    return(load_fit(
      outcome, specification, treatment_year, base_period,
      balance_e, xformla, bootstrap
    ))
  }
  run_spec(
    outcome, specification, data, treatment_year,
    base_period, balance_e, xformla, bootstrap
  )
}

collect_fit <- function(fit) {
  all_dynamic[[length(all_dynamic) + 1L]] <<- fit$dynamic
  all_overall[[length(all_overall) + 1L]] <<- fit$overall
  all_pretrend[[length(all_pretrend) + 1L]] <<- fit$pretrend
  all_warnings[[length(all_warnings) + 1L]] <<- fit$warnings
}

banner("ANALYTICAL ONE-CHANGE-AT-A-TIME LADDER")

full_sample <- panel
acquirer_sample <- panel[panel$acquirer_survival, ]
merged_sample <- panel[panel$merged_entity_survival, ]

for (outcome in c("log1p_patents", "log1p_citations")) {
  fit <- run_or_load_spec(
    outcome, "full_integration_varying", full_sample,
    "integration_year", "varying", NULL, ~1, FALSE
  )
  collect_fit(fit)

  # announcement_year equals integration_year for every estimation deal.
  # Preserve the specification-ladder row without rerunning an identical fit.
  timing_clone <- fit
  timing_clone$dynamic$specification <- "full_announcement_varying"
  timing_clone$dynamic$treatment_year <- "announcement_year"
  timing_clone$overall$specification <- "full_announcement_varying"
  timing_clone$pretrend$specification <- "full_announcement_varying"
  if (nrow(timing_clone$warnings) > 0L) {
    timing_clone$warnings$specification <- "full_announcement_varying"
  }
  collect_fit(timing_clone)
  write_result(
    timing_clone$dynamic,
    paste0("dynamic_full_announcement_varying_", outcome, ".csv")
  )
  write_result(
    timing_clone$overall,
    paste0("overall_full_announcement_varying_", outcome, ".csv")
  )
  write_result(
    timing_clone$pretrend,
    paste0("pretrend_full_announcement_varying_", outcome, ".csv")
  )
  write_result(
    timing_clone$warnings,
    paste0("warnings_full_announcement_varying_", outcome, ".csv")
  )

  collect_fit(run_or_load_spec(
    outcome, "acquirer_survival_varying", acquirer_sample,
    "announcement_year", "varying", NULL, ~1, FALSE,
    require_current_version = TRUE
  ))
  collect_fit(run_or_load_spec(
    outcome, "merged_survival_varying", merged_sample,
    "announcement_year", "varying", NULL, ~1, FALSE,
    require_current_version = TRUE
  ))
}

banner("PAPER-FAITHFUL, CORRECTED, AND CONTROLLED COMPARISON")

for (outcome in names(outcome_labels)) {
  collect_fit(run_or_load_spec(
    outcome, "paper_faithful_clustered", merged_sample,
    "announcement_year", "varying", NULL, ~1, TRUE,
    require_current_version = TRUE
  ))
  collect_fit(run_or_load_spec(
    outcome, "corrected_clustered", merged_sample,
    "announcement_year", "universal", 5L, ~1, TRUE,
    require_current_version = TRUE
  ))
  collect_fit(run_or_load_spec(
    outcome, "controlled_comparison_analytical", merged_sample,
    "announcement_year", "universal", 5L, controlled_formula, FALSE,
    require_current_version = TRUE
  ))
}

dynamic_all <- do.call(rbind, all_dynamic)
overall_all <- do.call(rbind, all_overall)
pretrend_all <- do.call(rbind, all_pretrend)
warnings_all <- do.call(rbind, all_warnings)

write_result(dynamic_all, "dynamic_all_specifications.csv")
write_result(overall_all, "five_year_average_att.csv")
write_result(pretrend_all, "joint_preperiod_diagnostics.csv")
write_result(warnings_all, "estimation_warnings.csv")

if (nrow(warnings_all) > 0L) {
  warnings_all$warning_category <- ifelse(
    grepl("^overlap condition", warnings_all$warning), "overlap",
    ifelse(
      grepl("^Covariate matrix", warnings_all$warning),
      "ill_conditioned_covariates",
      ifelse(
        grepl("^fit_glm", warnings_all$warning),
        "extreme_fitted_probabilities",
        ifelse(
          grepl("singular covariance matrix", warnings_all$warning),
          "singular_pretrend_covariance",
          ifelse(
            grepl("Simultaneous critical value", warnings_all$warning),
            "large_simultaneous_critical_value",
            "other"
          )
        )
      )
    )
  )
  warning_summary <- aggregate(
    warning ~ outcome + specification + warning_category,
    data = warnings_all,
    FUN = length
  )
  names(warning_summary)[names(warning_summary) == "warning"] <- "n_warnings"
} else {
  warning_summary <- data.frame(
    outcome = character(), specification = character(),
    warning_category = character(), n_warnings = integer()
  )
}
write_result(warning_summary, "estimation_warning_summary.csv")

inference_audit <- data.frame(
  specification = c("paper_faithful_clustered", "corrected_clustered"),
  att_gt_estimation = "analytical influence functions",
  dynamic_multiplier_bootstrap = TRUE,
  bootstrap_iterations = 999L,
  bootstrap_cluster = "deal_id",
  simultaneous_dynamic_bands = TRUE
)
write_result(inference_audit, "bootstrap_inference_audit.csv")

key_events <- dynamic_all[dynamic_all$event_time %in% c(-4, -3, -2, 0, 5), ]
write_result(key_events, "specification_ladder_key_events.csv")

comparison_events <- dynamic_all[
  dynamic_all$event_time %in% c(-3, 0, 5),
  c("outcome", "specification", "n_inventors", "n_deals", "event_time", "att")
]
comparison_events$event_label <- c(
  `-3` = "att_t_minus3", `0` = "att_t0", `5` = "att_t5"
)[as.character(comparison_events$event_time)]
comparison_wide <- stats::reshape(
  comparison_events[c(
    "outcome", "specification", "n_inventors", "n_deals", "event_label", "att"
  )],
  idvar = c("outcome", "specification", "n_inventors", "n_deals"),
  timevar = "event_label",
  direction = "wide"
)
names(comparison_wide) <- sub("^att\\.", "", names(comparison_wide))
comparison_wide <- merge(
  comparison_wide,
  overall_all[c("outcome", "specification", "overall_dynamic_att")],
  by = c("outcome", "specification"),
  all.x = TRUE
)
ladder_order <- c(
  "full_integration_varying", "full_announcement_varying",
  "acquirer_survival_varying", "merged_survival_varying",
  "paper_faithful_clustered", "corrected_clustered",
  "controlled_comparison_analytical"
)
comparison_wide$ladder_order <- match(comparison_wide$specification, ladder_order)
comparison_wide <- comparison_wide[order(
  comparison_wide$outcome, comparison_wide$ladder_order
), ]
comparison_wide$delta_t_minus3_from_previous <- NA_real_
for (outcome in unique(comparison_wide$outcome)) {
  rows <- which(comparison_wide$outcome == outcome)
  if (length(rows) > 1L) {
    comparison_wide$delta_t_minus3_from_previous[rows[-1]] <- diff(
      comparison_wide$att_t_minus3[rows]
    )
  }
}
write_result(comparison_wide, "specification_ladder_comparison.csv")

paper_benchmarks <- data.frame(
  outcome = c("log1p_patents", "log1p_citations"),
  paper_reported_att = c(-0.136, -0.350),
  paper_measure = c(
    "Log(patents), transformation not fully documented",
    "Log(citations received through 2022)"
  ),
  reconstruction_measure = c(
    "Log(1 + annual patents)",
    "Log(1 + OECD five-year forward citations)"
  )
)
paper_comparison <- merge(
  paper_benchmarks,
  overall_all[overall_all$specification %in% c(
    "paper_faithful_clustered", "corrected_clustered"
  ), c("outcome", "specification", "overall_dynamic_att", "overall_dynamic_se")],
  by = "outcome",
  all.x = TRUE
)
paper_comparison$difference_from_paper <-
  paper_comparison$overall_dynamic_att - paper_comparison$paper_reported_att
write_result(paper_comparison, "comparison_to_published_att.csv")

banner("FIGURE")

plot_specs <- c(
  "full_announcement_varying", "paper_faithful_clustered", "corrected_clustered"
)
plot_data <- dynamic_all[
  dynamic_all$specification %in% plot_specs &
    dynamic_all$outcome %in% c("log1p_patents", "log1p_citations"),
]
plot_data$specification_label <- factor(
  plot_data$specification,
  levels = plot_specs,
  labels = c(
    "Paper conventions, full cohort",
    "Add merged-entity survival",
    "Corrected inference"
  )
)

p <- ggplot2::ggplot(
  plot_data,
  ggplot2::aes(
    x = event_time, y = att, colour = specification_label,
    group = specification_label
  )
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey55") +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.5) +
  ggplot2::geom_errorbar(
    data = plot_data[plot_data$bootstrap, ],
    ggplot2::aes(ymin = ci_lower, ymax = ci_upper),
    width = 0.12, linewidth = 0.4, alpha = 0.65
  ) +
  ggplot2::facet_wrap(~outcome_label, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition announcement",
    y = "Group-time average treatment effect",
    colour = "Specification",
    title = "Verginer--Riccaboni design reconstruction",
    subtitle = "Forward-citation outcome uses the OECD five-year citation window",
    caption = "Error bars for clustered specifications are simultaneous 95% bands."
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    legend.position = "bottom",
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )

figure_path <- file.path(FIGS, "figure13_verginer_reconstruction.png")
ggplot2::ggsave(figure_path, p, width = 10, height = 5.5, dpi = 300)

banner("RECONSTRUCTION COMPLETE")
message("Results: ", RESULTS)
message("Figure:  ", figure_path)
message("Next: summarize these outputs in 00_Discussion_Docs/009_verginer_reconstruction.md")
