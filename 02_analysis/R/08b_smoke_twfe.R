# Fixed-effects replication for the controlled CS(2021) smoke analysis.
# Uses the full calendar panel and tail bins to keep t = -1 as the sole reference.
#
# Run after 06_build_event_panel.R and 08a_smoke_cs2021.R.

BASE   <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
SMOKE  <- file.path(BASE, "output", "results", "cs2021_smoke_controlled")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()

for (pkg in c("DBI", "duckdb", "fixest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

dir.create(SMOKE, recursive = TRUE, showWarnings = FALSE)
write_smoke <- function(df, filename) {
  utils::write.csv(df, file.path(SMOKE, filename), row.names = FALSE, na = "")
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
  CAST(event_time AS INTEGER) AS event_time,
  CAST(status_available AS BOOLEAN) AS status_available,
  CAST(left_this_year AS DOUBLE) AS left_this_year,
  CAST(rd_activity AS DOUBLE) AS rd_activity,
  CAST(log_patent_count AS DOUBLE) AS log_patent_count
FROM cs2021_estimation_panel
ORDER BY codinv, calendar_year
")

run_fe <- function(outcome) {
  data <- if (outcome == "left_this_year") {
    panel[panel$status_available, , drop = FALSE]
  } else {
    panel
  }
  data$event_time_binned <- ifelse(
    data$event_time < -5,
    -6L,
    ifelse(data$event_time > 5, 6L, data$event_time)
  )

  model <- fixest::feols(
    stats::as.formula(
      paste0(outcome, " ~ i(event_time_binned, ref = -1) | codinv + calendar_year")
    ),
    data = data,
    cluster = ~deal_id,
    notes = FALSE
  )

  table <- summary(model)$coeftable
  terms <- rownames(table)
  keep <- grepl("^event_time_binned::", terms)
  terms <- terms[keep]
  table <- table[keep, , drop = FALSE]
  event_time <- as.integer(
    sub("^event_time_binned::(-?[0-9]+).*$", "\\1", terms)
  )
  report <- event_time >= -5 & event_time <= 5

  result <- data.frame(
    outcome = outcome,
    specification = "twfe_inventor_dealyear_fe",
    sample = if (outcome == "left_this_year") "acquirer_resolved" else "full_cohort",
    n_inventors = length(unique(data$codinv)),
    n_deals = length(unique(data$deal_id)),
    event_time = event_time[report],
    estimate = table[report, "Estimate"],
    deal_clustered_se = table[report, "Std. Error"],
    p_value = table[report, "Pr(>|t|)"],
    stringsAsFactors = FALSE
  )
  result <- rbind(
    result,
    data.frame(
      outcome = outcome,
      specification = "twfe_inventor_dealyear_fe",
      sample = if (outcome == "left_this_year") "acquirer_resolved" else "full_cohort",
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
  result
}

outcomes <- c("left_this_year", "rd_activity", "log_patent_count")
fe_results <- do.call(rbind, lapply(outcomes, run_fe))

if (any(fe_results$deal_clustered_se > 10, na.rm = TRUE)) {
  stop("Implausibly large FE standard errors remain; inspect the fixed-effects design.")
}

write_smoke(fe_results, "twfe_replication_estimates.csv")

cs_file <- file.path(SMOKE, "cs_smoke_all_estimates.csv")
if (file.exists(cs_file)) {
  cs <- utils::read.csv(cs_file)
  cs <- cs[cs$specification == "controlled_main", c("outcome", "event_time", "att")]
  comparison <- merge(
    cs,
    fe_results[c("outcome", "event_time", "estimate", "deal_clustered_se")],
    by = c("outcome", "event_time"),
    all = TRUE
  )
  names(comparison)[names(comparison) == "att"] <- "cs_controlled_att"
  names(comparison)[names(comparison) == "estimate"] <- "twfe_estimate"
  write_smoke(comparison, "cs_vs_twfe_comparison.csv")
}

print(fe_results[c("outcome", "event_time", "estimate", "deal_clustered_se")])
message("Fixed-effects smoke replication complete: ", SMOKE)
