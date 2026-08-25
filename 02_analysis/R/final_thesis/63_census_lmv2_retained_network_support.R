#!/usr/bin/env Rscript

# Outcome-blind retained-network support companion. This intersects the strict
# anchor ties with the certified P5b selected population. It does not read a
# validation-period or post-treatment network outcome.

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
N0 <- file.path(ROOT, "NETWORK_N0_CENSUS")
N1 <- file.path(ROOT, "NETWORK_N1_VALIDATION")
STAYER <- file.path(ROOT, "P7_STAYER_HETEROGENEITY")
OUT <- file.path(ROOT, "NETWORK_N3_RETAINED_SUPPORT")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

ties <- file.path(N0, "network_persistent_ties.parquet")
roster <- file.path(STAYER, "stayer_unit_analysis.parquet")
n1_path <- file.path(N1, "network_n1_path_decision.csv")
for (p in c(ties, roster, n1_path)) if (!file.exists(p)) stop("Missing: ", p)
n1 <- utils::read.csv(
  n1_path, check.names = FALSE, colClasses = "character"
)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
q <- function(path) DBI::dbQuoteString(
  con, gsub("\\\\", "/", normalizePath(path, winslash = "/", mustWork = TRUE))
)

support <- DBI::dbGetQuery(con, sprintf("
  WITH r AS (
    SELECT DISTINCT roster_row_id, CAST(deal_id AS INTEGER) AS deal_id,
      CAST(cohort AS INTEGER) AS cohort, arm, CAST(codinv AS BIGINT) AS codinv,
      CAST(raw_weight AS DOUBLE) AS weight
    FROM read_parquet(%s)
  ), focal AS (
    SELECT r.*, COUNT(*) AS persistent_collaborators
    FROM r JOIN read_parquet(%s) t USING(roster_row_id)
    GROUP BY 1,2,3,4,5,6
  ), dm AS (
    SELECT arm, deal_id, SUM(weight) AS mass
    FROM focal GROUP BY 1,2
  ), ds AS (
    SELECT *, mass/SUM(mass) OVER(PARTITION BY arm) AS mass_share
    FROM dm
  )
  SELECT f.arm, COUNT(*) AS focal_inventors,
    COUNT(DISTINCT f.deal_id) AS nominal_deals,
    SUM(f.weight) AS weighted_focal_mass,
    AVG(f.persistent_collaborators) AS mean_persistent_collaborators,
    MEDIAN(f.persistent_collaborators) AS median_persistent_collaborators,
    (SELECT 1/SUM(s.mass_share*s.mass_share) FROM ds s WHERE s.arm=f.arm)
      AS effective_deals,
    (SELECT MAX(s.mass_share) FROM ds s WHERE s.arm=f.arm)
      AS largest_deal_share
  FROM focal f GROUP BY f.arm ORDER BY f.arm
", q(roster), q(ties)))
utils::write.csv(
  support, file.path(OUT, "retained_network_support_census.csv"),
  row.names = FALSE
)

treated <- support[support$arm == "treated", , drop = FALSE]
control <- support[support$arm == "control", , drop = FALSE]
if (nrow(treated) != 1L || nrow(control) != 1L) {
  stop("Retained support does not contain both arms")
}
upstream_release <- n1$selected_path[[1L]] == "N"
support_pass <- treated$nominal_deals[[1L]] >= 150L &&
  treated$effective_deals[[1L]] >= 20 &&
  treated$largest_deal_share[[1L]] <= 0.10
decision <- data.frame(
  n1_path = n1$selected_path[[1L]],
  retained_treated_inventors = treated$focal_inventors[[1L]],
  retained_nominal_deals = treated$nominal_deals[[1L]],
  retained_effective_deals = treated$effective_deals[[1L]],
  retained_largest_deal_share = treated$largest_deal_share[[1L]],
  retained_support_pass = support_pass,
  retained_effect_released = upstream_release && support_pass,
  release_reason = if (!upstream_release) {
    "blocked_by_full_cohort_N1_Path_F"
  } else if (!support_pass) {
    "retained_deal_support_below_frozen_threshold"
  } else {
    "eligible_for_separate_validation_and_precision_gate"
  },
  validation_or_post_network_outcomes_read = FALSE,
  stringsAsFactors = FALSE
)
utils::write.csv(
  decision, file.path(OUT, "retained_network_release_decision.csv"),
  row.names = FALSE
)

cert <- data.frame(
  check = c(
    "strict_ties_reused", "p5b_roster_reused_without_rematching",
    "both_arms_present", "support_metrics_finite",
    "upstream_gate_enforced", "network_outcomes_remain_closed"
  ),
  pass = c(
    file.exists(ties), file.exists(roster), nrow(support) == 2L,
    all(is.finite(support$effective_deals)) &&
      all(is.finite(support$largest_deal_share)),
    !decision$retained_effect_released[[1L]] || upstream_release,
    !decision$validation_or_post_network_outcomes_read[[1L]]
  ),
  value = c(
    digest::digest(ties, file = TRUE, algo = "sha256"),
    digest::digest(roster, file = TRUE, algo = "sha256"),
    paste(support$arm, collapse = ";"),
    paste(round(support$effective_deals, 3), collapse = ";"),
    decision$release_reason[[1L]],
    decision$validation_or_post_network_outcomes_read[[1L]]
  ),
  detail = c(
    "same two-application/two-year anchor definition",
    "certified P5b weights are used as stored",
    "treated and symmetric controls are counted",
    "effective deals and concentration computed",
    "retained analysis cannot bypass the full-cohort gate",
    "support census opens no network outcome"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  cert, file.path(OUT, "retained_network_support_certification.csv"),
  row.names = FALSE
)
if (!all(cert$pass)) stop("Retained network support certification failed")

note <- c(
  "# Initially retained network support",
  "",
  sprintf(
    "The strict anchor contains %d initially retained treated inventors across %d deals (%.1f effective deals).",
    treated$focal_inventors[[1L]], treated$nominal_deals[[1L]],
    treated$effective_deals[[1L]]
  ),
  "",
  paste0("Release decision: **", decision$release_reason[[1L]], "**."),
  "",
  "The retained population is post-treatment selected and cannot override the",
  "full-cohort Path-F result. No retained validation or post-treatment network",
  "outcome is estimated."
)
writeLines(note, file.path(OUT, "retained_network_support_results.md"),
           useBytes = TRUE)

artifacts <- c(
  "retained_network_support_census.csv",
  "retained_network_release_decision.csv",
  "retained_network_support_certification.csv",
  "retained_network_support_results.md"
)
manifest <- data.frame(
  artifact = artifacts,
  sha256 = vapply(
    file.path(OUT, artifacts), digest::digest, character(1),
    file = TRUE, algo = "sha256"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(OUT, "retained_network_support_manifest.csv"),
  row.names = FALSE
)
message("Retained network support certified; effect released=",
        decision$retained_effect_released[[1L]])
