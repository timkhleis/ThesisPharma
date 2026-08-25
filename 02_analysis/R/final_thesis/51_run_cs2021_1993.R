#!/usr/bin/env Rscript

# Callaway--Sant'Anna companion analysis for the repaired 1993 cohort.
#
# The full panel retains every eventually treated cohort through 2015 so later
# cohorts can serve as not-yet-treated controls. balance_e=5 restricts the
# reported 1..5 estimand to cohorts 1993--2010 without contaminating their risk
# sets. Anticipation 0 and 1 are reported in parallel because target_year may
# represent announcement or completion. Local Match v2 remains the separate
# never-observed-target comparison. Pass --control-group=nevertreated for the
# required restrictive CS(2021) robustness; future-treated inventors are never
# relabelled as never treated.

options(stringsAsFactors = FALSE, scipen = 999)

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) return(default)
  if (length(hit) != 1L) stop("Expected one --", name, "= argument")
  sub(paste0("^--", name, "="), "", hit)
}
split_arg <- function(name, default) {
  trimws(strsplit(arg_value(name, paste(default, collapse = ",")), ",",
                  fixed = TRUE)[[1L]])
}

SMOKE <- "--smoke" %in% args
OUTCOMES <- split_arg(
  "outcomes",
  c("patent_count", "active_patenting", "pqii_scaled",
    "fwd_cits5_scaled", "tech_drift")
)
ANTICIPATIONS <- as.integer(split_arg("anticipations", c(0L, 1L)))
BITERS <- if (SMOKE) 49L else as.integer(arg_value("biters", "999"))
CONTROL_GROUP <- arg_value("control-group", "notyettreated")
if (any(!ANTICIPATIONS %in% 0:1)) stop("Anticipation must be 0 or 1")
if (!CONTROL_GROUP %in% c("notyettreated", "nevertreated")) {
  stop("--control-group must be notyettreated or nevertreated")
}

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "did", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

allowed_outcomes <- c(
  "patent_count", "active_patenting", "pqii_scaled",
  "fwd_cits5_scaled", "tech_drift"
)
if (!length(OUTCOMES) || !all(OUTCOMES %in% allowed_outcomes)) {
  stop("Unknown or empty outcome list")
}

OUT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  if (SMOKE) {
    paste0("CS2021_1993_SMOKE_", CONTROL_GROUP)
  } else if (CONTROL_GROUP == "notyettreated") {
    "CS2021_1993_FINAL"
  } else {
    "CS2021_1993_NEVER"
  }
)
FIG <- file.path(OUT, "figures")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}

con <- DBI::dbConnect(
  duckdb::duckdb(), file.path(BASE, "output", "thesis_foundation.duckdb"),
  read_only = TRUE
)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=8")

PANEL_CACHE <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "CS2021_1993_PANEL.rds"
)
if (file.exists(PANEL_CACHE)) {
  message("Reading cached repaired CS(2021) analysis panel...")
  panel <- readRDS(PANEL_CACHE)
} else {
  message("Building repaired CS(2021) analysis panel...")
  panel <- DBI::dbGetQuery(con, "
  WITH units AS MATERIALIZED (
    SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv,
      CAST(deal_year AS INTEGER) AS deal_year
    FROM cs2021_estimation_panel
  ),
  ipc4 AS MATERIALIZED (
    SELECT u.codinv, u.deal_year, i.year,
      SUBSTR(i.ipc_code, 1, 4) AS ipc4,
      SUM(i.patent_count) AS w
    FROM units u
    JOIN inventor_ipc_year i
      ON CAST(i.codinv AS BIGINT) = u.codinv
     AND i.year BETWEEN u.deal_year - 5 AND u.deal_year + 5
    WHERE i.ipc_code IS NOT NULL AND LENGTH(i.ipc_code) >= 4
    GROUP BY 1, 2, 3, 4
  ),
  baseline AS MATERIALIZED (
    SELECT codinv, deal_year, ipc4, SUM(w) AS bw
    FROM ipc4
    WHERE year BETWEEN deal_year - 5 AND deal_year - 1
    GROUP BY 1, 2, 3
  ),
  bnorm AS (
    SELECT codinv, deal_year, SQRT(SUM(bw * bw)) AS bnorm
    FROM baseline GROUP BY 1, 2
  ),
  cnorm AS (
    SELECT codinv, deal_year, year, SQRT(SUM(w * w)) AS cnorm
    FROM ipc4 GROUP BY 1, 2, 3
  ),
  dot AS (
    SELECT c.codinv, c.deal_year, c.year, SUM(c.w * b.bw) AS dot
    FROM ipc4 c
    JOIN baseline b USING (codinv, deal_year, ipc4)
    GROUP BY 1, 2, 3
  )
  SELECT
    CAST(ep.codinv AS DOUBLE) AS codinv,
    CAST(ep.deal_id AS INTEGER) AS deal_id,
    CAST(ep.deal_year AS INTEGER) AS deal_year,
    CAST(ep.calendar_year AS INTEGER) AS calendar_year,
    CAST(ep.patent_count AS DOUBLE) AS patent_count,
    CAST(ep.active_patenting AS DOUBLE) AS active_patenting,
    CASE
      WHEN ep.patent_count = 0 THEN 0
      WHEN COALESCE(o.n_pqii_nonmiss, 0) = 0 THEN NULL
      ELSE o.sum_pqii_obs * ep.patent_count / o.n_pqii_nonmiss
    END AS pqii_scaled,
    CASE
      WHEN ep.patent_count = 0 THEN 0
      WHEN COALESCE(o.n_fwd_nonmiss, 0) = 0 THEN NULL
      ELSE o.sum_fwd_cits5_obs * ep.patent_count / o.n_fwd_nonmiss
    END AS fwd_cits5_scaled,
    CASE
      WHEN bn.bnorm IS NULL OR bn.bnorm = 0 THEN NULL
      WHEN cn.cnorm IS NULL OR cn.cnorm = 0 THEN NULL
      ELSE 1 - COALESCE(d.dot, 0) / (bn.bnorm * cn.cnorm)
    END AS tech_drift,
    CAST(ep.career_age_at_deal AS DOUBLE) AS career_age_at_deal,
    CAST(ep.career_age_sq_at_deal AS DOUBLE) AS career_age_sq_at_deal,
    COALESCE(ep.ipc_primary_field, 'UNKNOWN') AS ipc_primary_field,
    CAST(ep.log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
    CAST(ep.log_group_size AS DOUBLE) AS log_group_size,
    CAST(ep.log_deal_value AS DOUBLE) AS log_deal_value,
    CAST(ep.predeal_patent_stock_5y AS DOUBLE) AS predeal_patent_stock_5y
  FROM cs2021_estimation_panel ep
  LEFT JOIN p6.lmv2_outcome_inventor_year o
    ON o.codinv = CAST(ep.codinv AS BIGINT) AND o.year = ep.calendar_year
  LEFT JOIN bnorm bn
    ON bn.codinv = CAST(ep.codinv AS BIGINT)
   AND bn.deal_year = ep.deal_year
  LEFT JOIN cnorm cn
    ON cn.codinv = CAST(ep.codinv AS BIGINT)
   AND cn.deal_year = ep.deal_year AND cn.year = ep.calendar_year
  LEFT JOIN dot d
    ON d.codinv = CAST(ep.codinv AS BIGINT)
   AND d.deal_year = ep.deal_year AND d.year = ep.calendar_year
  ORDER BY ep.codinv, ep.calendar_year
")
  saveRDS(panel, PANEL_CACHE, compress = "xz")
}

# Preserve the common-support rule used in the archived CS implementation.
coverage <- DBI::dbGetQuery(con, "
  WITH unit AS (
    SELECT DISTINCT codinv, deal_id, deal_year,
      predeal_patent_stock_5y, ipc_primary_field
    FROM cs2021_estimation_panel
  ), binned AS (
    SELECT *, NTILE(5) OVER (
      ORDER BY predeal_patent_stock_5y, codinv, deal_id
    ) AS q
    FROM unit
  )
  SELECT q AS patent_stock_quintile, ipc_primary_field,
    COUNT(DISTINCT deal_year) AS n_cohorts,
    MAX(deal_year) - MIN(deal_year) AS span
  FROM binned GROUP BY 1, 2
")
coverage$pass <- coverage$n_cohorts >= 3L & coverage$span >= 5L
allowed <- coverage[coverage$pass,
                    c("patent_stock_quintile", "ipc_primary_field")]
unit_bins <- DBI::dbGetQuery(con, "
  WITH unit AS (
    SELECT DISTINCT codinv, deal_id, predeal_patent_stock_5y
    FROM cs2021_estimation_panel
  )
  SELECT CAST(codinv AS DOUBLE) AS codinv, deal_id,
    NTILE(5) OVER (
      ORDER BY predeal_patent_stock_5y, codinv, deal_id
    ) AS patent_stock_quintile
  FROM unit
")
panel <- merge(panel, unit_bins, by = c("codinv", "deal_id"))
panel <- merge(
  panel, transform(allowed, common_support = TRUE),
  by = c("patent_stock_quintile", "ipc_primary_field"), all.x = TRUE
)
panel$common_support[is.na(panel$common_support)] <- FALSE
panel <- panel[panel$common_support, ]
panel$ipc_primary_field <- factor(panel$ipc_primary_field)
panel <- panel[order(panel$codinv, panel$calendar_year), ]
never_treated_units <- length(unique(panel$codinv[panel$deal_year == 0L]))

sample_audit <- data.frame(
  rows = nrow(panel), inventors = length(unique(panel$codinv)),
  deals = length(unique(panel$deal_id)),
  min_treatment_year = min(panel$deal_year),
  max_treatment_year = max(panel$deal_year),
  cohort_1993_inventors = length(unique(panel$codinv[panel$deal_year == 1993L])),
  cohort_1993_deals = length(unique(panel$deal_id[panel$deal_year == 1993L])),
  bootstrap_replications = BITERS,
  smoke = SMOKE
)
write_csv(sample_audit, "cs2021_sample_audit.csv")
write_csv(coverage, "cs2021_common_support_cells.csv")
message("Panel: ", sample_audit$inventors, " inventors; ",
        sample_audit$deals, " deals; 1993 inventors=",
        sample_audit$cohort_1993_inventors)

xform <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size +
  log_deal_value

dynamic_rows <- list()
headline_rows <- list()
pretrend_rows <- list()
failures <- list()
estimation_outcomes <- OUTCOMES
if (CONTROL_GROUP == "nevertreated" && never_treated_units == 0L) {
  estimation_outcomes <- character()
  for (outcome in OUTCOMES) for (anticipation in ANTICIPATIONS) {
    label <- paste0(outcome, "_a", anticipation, "_never")
    failures[[label]] <- data.frame(
      outcome = outcome, anticipation = anticipation,
      stage = "control_group_support",
      message = paste0(
        "The repaired CS panel contains zero g=0 never-treated units; ",
        "the never-treated CS comparison is not identified in this spine."))
  }
}
run_index <- 0L

for (outcome in estimation_outcomes) {
  for (anticipation in ANTICIPATIONS) {
    run_index <- run_index + 1L
    label <- paste0(
      outcome, "_a", anticipation, "_",
      if (CONTROL_GROUP == "notyettreated") "nyt" else "never")
    message("Estimating ", label, " ...")
    set.seed(20260805L + run_index)
    fit <- tryCatch(
      did::att_gt(
        yname = outcome, tname = "calendar_year", idname = "codinv",
        gname = "deal_year", xformla = xform, data = panel,
        panel = TRUE, allow_unbalanced_panel = TRUE,
        control_group = CONTROL_GROUP, anticipation = anticipation,
        base_period = "universal", est_method = "dr",
        bstrap = FALSE, clustervars = "deal_id", cband = FALSE,
        print_details = FALSE
      ),
      error = function(e) e
    )
    if (inherits(fit, "error")) {
      failures[[label]] <- data.frame(
        outcome = outcome, anticipation = anticipation,
        stage = "att_gt", message = conditionMessage(fit)
      )
      next
    }

    set.seed(20260805L + run_index)
    dyn <- tryCatch(
      did::aggte(
        fit, type = "dynamic", balance_e = 5, min_e = -5, max_e = 5,
        na.rm = TRUE, bstrap = TRUE, biters = BITERS,
        clustervars = "deal_id", cband = TRUE
      ),
      error = function(e) e
    )
    if (inherits(dyn, "error")) {
      failures[[label]] <- data.frame(
        outcome = outcome, anticipation = anticipation,
        stage = "aggte_dynamic", message = conditionMessage(dyn)
      )
      next
    }
    crit <- if (!is.null(dyn$crit.val.egt) && is.finite(dyn$crit.val.egt)) {
      dyn$crit.val.egt
    } else 1.96
    dynamic_rows[[label]] <- data.frame(
      outcome = outcome, anticipation = anticipation,
      control_group = CONTROL_GROUP, event_time = dyn$egt,
      estimate = dyn$att.egt, se = dyn$se.egt,
      ci_low = dyn$att.egt - crit * dyn$se.egt,
      ci_high = dyn$att.egt + crit * dyn$se.egt,
      simultaneous_critical_value = crit
    )

    pretrend_rows[[label]] <- data.frame(
      outcome = outcome, anticipation = anticipation,
      control_group = CONTROL_GROUP,
      test = "att_gt_Wald_all_pretreatment_cells",
      p_value = if (length(fit$Wpval) == 1L) fit$Wpval else NA_real_
    )

    for (window_hi in c(3L, 5L)) {
      set.seed(20260805L + run_index + window_hi)
      post <- tryCatch(
        did::aggte(
          fit, type = "dynamic", balance_e = window_hi,
          min_e = 1, max_e = window_hi, na.rm = TRUE,
          bstrap = TRUE, biters = BITERS, clustervars = "deal_id",
          cband = FALSE
        ),
        error = function(e) e
      )
      if (inherits(post, "error")) {
        failures[[paste0(label, "_post", window_hi)]] <- data.frame(
          outcome = outcome, anticipation = anticipation,
          stage = paste0("aggte_post_1_", window_hi),
          message = conditionMessage(post)
        )
      } else {
        b <- as.numeric(post$overall.att)
        se <- as.numeric(post$overall.se)
        headline_rows[[paste0(label, "_post", window_hi)]] <- data.frame(
          outcome = outcome, anticipation = anticipation,
          control_group = CONTROL_GROUP,
          post_window = paste0("1:", window_hi),
          estimate = b, se = se,
          ci_low = b - 1.96 * se, ci_high = b + 1.96 * se,
          p_value = 2 * stats::pnorm(-abs(b / se)),
          bootstrap_replications = BITERS
        )
      }
    }
    saveRDS(fit, file.path(OUT, paste0("att_gt_", label, ".rds")))
    saveRDS(dyn, file.path(OUT, paste0("aggte_dynamic_", label, ".rds")))
    rm(fit, dyn)
    gc()
  }
}

dynamic <- if (length(dynamic_rows)) do.call(rbind, dynamic_rows) else data.frame(
  outcome = character(), anticipation = integer(), control_group = character(),
  event_time = integer(), estimate = numeric(), se = numeric(),
  ci_low = numeric(), ci_high = numeric(), simultaneous_critical_value = numeric())
headline <- if (length(headline_rows)) do.call(rbind, headline_rows) else data.frame(
  outcome = character(), anticipation = integer(), control_group = character(),
  post_window = character(), estimate = numeric(), se = numeric(),
  ci_low = numeric(), ci_high = numeric(), p_value = numeric(),
  bootstrap_replications = integer())
pretrend <- if (length(pretrend_rows)) do.call(rbind, pretrend_rows) else data.frame(
  outcome = character(), anticipation = integer(), control_group = character(),
  test = character(), p_value = numeric())
failure <- if (length(failures)) do.call(rbind, failures) else data.frame(
  outcome = character(), anticipation = integer(), stage = character(),
  message = character()
)
write_csv(dynamic, "cs2021_dynamic.csv")
write_csv(headline, "cs2021_headline.csv")
write_csv(pretrend, "cs2021_pretrend_tests.csv")
write_csv(failure, "cs2021_failures.csv")

if (nrow(dynamic)) {
  plot_data <- dynamic
  plot_data$anticipation <- factor(
    plot_data$anticipation, levels = c(0, 1),
    labels = c("Anticipation = 0", "Anticipation = 1")
  )
  p <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(event_time, estimate, colour = anticipation,
                 group = anticipation)
  ) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey55") +
    ggplot2::geom_vline(xintercept = 0, linetype = 2, colour = "grey60") +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = ci_low, ymax = ci_high, fill = anticipation),
      alpha = 0.12, colour = NA
    ) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 1.2) +
    ggplot2::facet_wrap(~outcome, scales = "free_y", ncol = 2) +
    ggplot2::scale_x_continuous(breaks = -5:5) +
    ggplot2::labs(
      x = "Event time", y = "Group-time ATT", colour = NULL, fill = NULL,
      title = paste0(
        "Callaway--Sant'Anna estimates with ",
        if (CONTROL_GROUP == "notyettreated") "not-yet-treated" else "never-treated",
        " controls"),
      subtitle = "Repaired cohort panel; balanced post-treatment support"
    ) +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())
  ggplot2::ggsave(
    file.path(FIG, "cs2021_event_study.png"), p,
    width = 8.2, height = 6.2, dpi = 300, bg = "white"
  )
}

certification <- data.frame(
  check = c(
    "panel_contains_1993", "reported_long_window_is_1993_2010",
    "both_anticipation_values_requested", "control_group_valid",
    "requested_control_group_supported",
    "all_requested_fits_completed"
  ),
  pass = c(
    sample_audit$cohort_1993_deals > 0,
    max(panel$calendar_year) >= 2015L && min(panel$deal_year) == 1993L,
    all(c(0L, 1L) %in% ANTICIPATIONS),
    CONTROL_GROUP %in% c("notyettreated", "nevertreated"),
    CONTROL_GROUP != "nevertreated" || never_treated_units > 0L,
    nrow(failure) == 0L
  ),
  note = c(
    paste(sample_audit$cohort_1993_inventors, "inventors across",
          sample_audit$cohort_1993_deals, "deals"),
    "balance_e=5 retains 1993--2010 cohorts for the 1:5 summary",
    paste(ANTICIPATIONS, collapse = ";"),
    CONTROL_GROUP,
    paste(never_treated_units, "g=0 inventor units"),
    if (nrow(failure)) paste(unique(failure$stage), collapse = ";") else "none"
  )
)
write_csv(certification, "cs2021_certification.csv")
message("CS(2021) package written to: ", OUT)
if (!SMOKE && !all(certification$pass)) quit(status = 1L)
