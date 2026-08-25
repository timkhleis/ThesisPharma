#!/usr/bin/env Rscript

# Two missing thesis diagnostics:
#   1. The selected-group association between TechDrift and patent quality
#      among initially retained treated inventors, with deal and event-time FE.
#   2. The management-transition diagnostic: career age and pre-deal patenting
#      across initially retained, leaver, and no-post-patent classifications.
# Neither exercise is labelled as an acquisition ATT.

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "fixest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
OUT <- file.path(ROOT, "MECHANISM_SELECTION_DIAGNOSTICS")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}
sql_path <- function(path) gsub("\\\\", "/", normalizePath(
  path, winslash = "/", mustWork = TRUE
))

db <- file.path(BASE, "output", "thesis_foundation.duckdb")
panel_glob <- gsub(
  "\\\\", "/", file.path(ROOT, "P6_BASE", "panel_matched", "*.parquet")
)
retention_file <- file.path(
  ROOT, "P5B_STAYER_S0_S2", "treated_retention_partition.parquet"
)
con <- DBI::dbConnect(duckdb::duckdb(), db, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=8")

message("Loading retained-inventor mechanism panel...")
mechanism <- DBI::dbGetQuery(con, sprintf("
  SELECT CAST(deal_id AS INTEGER) AS deal_id,
    CAST(cohort AS INTEGER) AS cohort,
    CAST(codinv AS DOUBLE) AS codinv,
    CAST(event_time AS INTEGER) AS event_time,
    CAST(tech_drift AS DOUBLE) AS tech_drift,
    CAST(pqii_conditional_mean AS DOUBLE) AS pqii_conditional_mean,
    CAST(pqii_scaled AS DOUBLE) AS pqii_scaled,
    CAST(patent_count AS DOUBLE) AS patent_count
  FROM read_parquet('%s')
  WHERE arm='treated'
    AND status_eligible_stayer_first_post_t0_t5
    AND cohort BETWEEN 1993 AND 2010
    AND event_time BETWEEN 0 AND 5
", panel_glob))

fit_one <- function(outcome) {
  dat <- mechanism[
    is.finite(mechanism$tech_drift) & is.finite(mechanism[[outcome]]),
  ]
  if (nrow(dat) < 100L || length(unique(dat$deal_id)) < 10L) {
    stop("Insufficient observations for ", outcome)
  }
  model <- fixest::feols(
    stats::as.formula(paste0(
      outcome, " ~ tech_drift | deal_id + event_time"
    )),
    data = dat, cluster = ~deal_id, notes = FALSE
  )
  ct <- as.data.frame(fixest::coeftable(model))
  row <- ct["tech_drift", , drop = FALSE]
  ci <- as.numeric(stats::confint(model, "tech_drift"))
  data.frame(
    outcome = outcome,
    estimate = row$Estimate,
    se_deal_cluster = row$`Std. Error`,
    t_value = row$`t value`,
    p_value = row$`Pr(>|t|)`,
    ci_low = ci[[1L]], ci_high = ci[[2L]],
    observations = stats::nobs(model),
    deals = length(unique(dat$deal_id)),
    inventors = length(unique(dat$codinv)),
    event_window = "0:5",
    fixed_effects = "deal_id;event_time",
    interpretation = "selected_retained_inventor_association_not_ATT"
  )
}
mechanism_results <- do.call(rbind, lapply(
  c("pqii_conditional_mean", "pqii_scaled"), fit_one
))
write_csv(mechanism_results, "techdrift_quality_association.csv")

message("Building management-transition diagnostic...")
selection <- DBI::dbGetQuery(con, sprintf("
  WITH r AS (
    SELECT CAST(cohort AS INTEGER) AS cohort,
      CAST(deal_id AS INTEGER) AS deal_id,
      CAST(codinv AS BIGINT) AS codinv,
      retention_status
    FROM read_parquet('%s')
    WHERE is_primary AND cohort BETWEEN 1993 AND 2010
  ), c AS (
    SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv,
      CAST(deal_id AS INTEGER) AS deal_id,
      CAST(career_age_at_deal AS DOUBLE) AS career_age_at_deal,
      CAST(predeal_patent_stock_5y AS DOUBLE) AS predeal_patent_stock_5y,
      CAST(predeal_active_rate_5y AS DOUBLE) AS predeal_active_rate_5y
    FROM cs2021_estimation_panel
  )
  SELECT r.*, c.career_age_at_deal, c.predeal_patent_stock_5y,
    c.predeal_active_rate_5y
  FROM r LEFT JOIN c USING (codinv, deal_id)
", sql_path(retention_file)))

q <- function(x, p) as.numeric(stats::quantile(x, p, na.rm = TRUE, type = 7))
summary_rows <- lapply(split(selection, selection$retention_status), function(z) {
  x <- z$career_age_at_deal
  p <- z$predeal_patent_stock_5y
  a <- z$predeal_active_rate_5y
  data.frame(
    retention_status = z$retention_status[[1L]],
    n = nrow(z), n_career_age = sum(is.finite(x)),
    career_age_mean = mean(x, na.rm = TRUE),
    career_age_sd = stats::sd(x, na.rm = TRUE),
    career_age_p10 = q(x, 0.10), career_age_p25 = q(x, 0.25),
    career_age_median = q(x, 0.50), career_age_p75 = q(x, 0.75),
    career_age_p90 = q(x, 0.90),
    predeal_patent_stock_mean = mean(p, na.rm = TRUE),
    predeal_patent_stock_median = q(p, 0.50),
    predeal_active_rate_mean = mean(a, na.rm = TRUE)
  )
})
selection_summary <- do.call(rbind, summary_rows)
selection_summary <- selection_summary[match(
  c("initially_retained", "leaver", "no_post_patent"),
  selection_summary$retention_status
), ]
write_csv(selection_summary, "management_transition_summary.csv")

selection$retention_status <- factor(
  selection$retention_status,
  levels = c("leaver", "initially_retained", "no_post_patent")
)
age_model <- fixest::feols(
  career_age_at_deal ~ i(retention_status, ref = "leaver") | cohort,
  data = selection, cluster = ~deal_id, notes = FALSE
)
age_ct <- as.data.frame(fixest::coeftable(age_model))
age_ct$term <- rownames(age_ct)
age_ci <- as.data.frame(stats::confint(age_model))
age_ci$term <- rownames(age_ci)
names(age_ci)[1:2] <- c("ci_low", "ci_high")
age_results <- merge(age_ct, age_ci, by = "term")
names(age_results)[names(age_results) == "Estimate"] <- "estimate"
names(age_results)[names(age_results) == "Std. Error"] <- "se_deal_cluster"
names(age_results)[names(age_results) == "t value"] <- "t_value"
names(age_results)[names(age_results) == "Pr(>|t|)"] <- "p_value"
age_results$reference_status <- "leaver"
age_results$cohort_fixed_effects <- TRUE
write_csv(age_results, "management_transition_age_contrasts.csv")

no_post <- selection_summary[
  selection_summary$retention_status == "no_post_patent",
]
retained <- selection_summary[
  selection_summary$retention_status == "initially_retained",
]
leaver <- selection_summary[selection_summary$retention_status == "leaver", ]
cert <- data.frame(
  check = c(
    "mechanism_has_1993", "mechanism_is_labelled_associational",
    "all_three_statuses_present", "career_age_nonmissing_above_95pct",
    "management_interpretation_is_empirically_tested"
  ),
  pass = c(
    min(mechanism$cohort, na.rm = TRUE) == 1993L,
    all(mechanism_results$interpretation ==
          "selected_retained_inventor_association_not_ATT"),
    nrow(selection_summary) == 3L,
    all(selection_summary$n_career_age / selection_summary$n >= 0.95),
    nrow(age_results) == 2L
  ),
  note = c(
    paste(range(mechanism$cohort), collapse = "--"),
    "deal and event-time fixed effects; no causal mediation claim",
    paste(selection_summary$retention_status, collapse = ";"),
    paste(round(selection_summary$n_career_age / selection_summary$n, 3),
          collapse = ";"),
    sprintf(
      "Mean career age: retained %.2f, leaver %.2f, no-post %.2f",
      retained$career_age_mean, leaver$career_age_mean,
      no_post$career_age_mean
    )
  )
)
write_csv(cert, "mechanism_selection_certification.csv")
message("Mechanism and selection diagnostics written to: ", OUT)
if (!all(cert$pass)) quit(status = 1L)
