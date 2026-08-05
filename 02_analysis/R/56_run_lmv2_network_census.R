#!/usr/bin/env Rscript

# N0 outcome-blind collaboration-network census. Persistent ties use only
# event times -5..-3 and require at least two joint applications in at least
# two anchor years. This script never reads event time -2 or later outcomes.

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
OUT <- file.path(ROOT, "NETWORK_N0_CENSUS")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}
sql_path <- function(path, must_work = TRUE) gsub(
  "\\\\", "/", normalizePath(path, winslash = "/", mustWork = must_work)
)

panel_glob <- gsub(
  "\\\\", "/", file.path(ROOT, "P6_BASE", "panel_matched", "*.parquet")
)
ties_file <- file.path(OUT, "network_persistent_ties.parquet")
db <- file.path(BASE, "output", "thesis_foundation.duckdb")
con <- DBI::dbConnect(duckdb::duckdb(), db, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
temp_dir <- file.path(OUT, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory='%s'", gsub("\\\\", "/", temp_dir)
))

message("Constructing anchor-period persistent collaboration ties...")
DBI::dbExecute(con, sprintf("
  COPY (
    WITH roster AS MATERIALIZED (
      SELECT DISTINCT roster_row_id, CAST(deal_id AS INTEGER) AS deal_id,
        CAST(cohort AS INTEGER) AS cohort, arm, CAST(codinv AS BIGINT) AS codinv,
        CAST(weight AS DOUBLE) AS weight
      FROM read_parquet('%s')
      WHERE event_time=-1 AND cohort BETWEEN 1993 AND 2010
    ), app_inv AS MATERIALIZED (
      SELECT DISTINCT CAST(appln_id AS BIGINT) AS appln_id,
        CAST(codinv AS BIGINT) AS codinv
      FROM patent_inventor
    ), focal_apps AS MATERIALIZED (
      SELECT r.roster_row_id, r.deal_id, r.cohort, r.arm, r.codinv,
        r.weight, CAST(pa.appln_id AS BIGINT) AS appln_id,
        CAST(pa.patent_year AS INTEGER) AS patent_year
      FROM roster r
      JOIN app_inv pi ON pi.codinv=r.codinv
      JOIN patent_application pa
        ON CAST(pa.appln_id AS BIGINT)=pi.appln_id
       AND pa.patent_year BETWEEN r.cohort-5 AND r.cohort-3
    ), dyads AS (
      SELECT DISTINCT f.roster_row_id, f.deal_id, f.cohort, f.arm,
        f.codinv AS focal_codinv, f.weight, c.codinv AS collaborator_codinv,
        f.appln_id, f.patent_year
      FROM focal_apps f
      JOIN app_inv c USING (appln_id)
      WHERE c.codinv<>f.codinv
    )
    SELECT roster_row_id, deal_id, cohort, arm, focal_codinv, weight,
      collaborator_codinv,
      COUNT(DISTINCT appln_id) AS joint_applications,
      COUNT(DISTINCT patent_year) AS joint_years,
      MIN(patent_year) AS first_anchor_year,
      MAX(patent_year) AS last_anchor_year
    FROM dyads
    GROUP BY 1,2,3,4,5,6,7
    HAVING COUNT(DISTINCT appln_id)>=2
       AND COUNT(DISTINCT patent_year)>=2
  ) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE TRUE)
", panel_glob, gsub("\\\\", "/", ties_file)))

ties_sql <- sprintf("read_parquet('%s')", sql_path(ties_file))
key_checks <- DBI::dbGetQuery(con, sprintf("
  SELECT COUNT(*) AS ties,
    COUNT(*)-COUNT(DISTINCT (roster_row_id, collaborator_codinv)) AS duplicate_keys,
    SUM(focal_codinv=collaborator_codinv) AS self_links,
    MIN(first_anchor_year-cohort) AS min_event_time,
    MAX(last_anchor_year-cohort) AS max_event_time,
    MIN(joint_applications) AS min_joint_apps,
    MIN(joint_years) AS min_joint_years
  FROM %s
", ties_sql))

census <- DBI::dbGetQuery(con, sprintf("
  WITH focal AS (
    SELECT roster_row_id, deal_id, cohort, arm, focal_codinv, weight,
      COUNT(*) AS persistent_collaborators
    FROM %1$s GROUP BY 1,2,3,4,5,6
  ), deal_mass AS (
    SELECT arm, deal_id, SUM(weight) AS mass,
      COUNT(*) AS focal_inventors
    FROM focal GROUP BY 1,2
  ), shares AS (
    SELECT *, mass/SUM(mass) OVER(PARTITION BY arm) AS share
    FROM deal_mass
  )
  SELECT f.arm, COUNT(*) AS focal_inventors,
    COUNT(DISTINCT f.deal_id) AS nominal_deals,
    SUM(f.weight) AS weighted_focal_mass,
    AVG(f.persistent_collaborators) AS mean_persistent_collaborators,
    MEDIAN(f.persistent_collaborators) AS median_persistent_collaborators,
    (SELECT 1/SUM(share*share) FROM shares s WHERE s.arm=f.arm)
      AS effective_deals,
    (SELECT MAX(share) FROM shares s WHERE s.arm=f.arm)
      AS largest_deal_share
  FROM focal f GROUP BY f.arm ORDER BY f.arm
", ties_sql))
write_csv(key_checks, "network_key_checks.csv")
write_csv(census, "network_support_census.csv")

treated <- census[census$arm == "treated", ]
control <- census[census$arm == "control", ]
if (nrow(treated) != 1L || nrow(control) != 1L) {
  stop("Network census does not contain both arms")
}
support_pass <- treated$focal_inventors >= 3000L &&
  treated$nominal_deals >= 150L && treated$effective_deals >= 20 &&
  treated$largest_deal_share <= 0.10 && control$focal_inventors > 0L
decision <- data.frame(
  selected_path = if (support_pass) "N1" else "Q",
  path_description = if (support_pass) {
    "Outcome-blind support gate passes; negative-event validation may run."
  } else {
    "Outcome-blind network support is insufficient; post effects remain closed."
  },
  meaningful_effect_threshold = 0.05,
  treated_focal_inventors = treated$focal_inventors,
  treated_nominal_deals = treated$nominal_deals,
  treated_effective_deals = treated$effective_deals,
  treated_largest_deal_share = treated$largest_deal_share
)
write_csv(decision, "network_n0_path_decision.csv")

freeze <- c(
  "# Local Match v2 network pre-analysis freeze",
  "",
  "- Population: certified P5c full pre-deal target-inventor cohort and its frozen weighted controls.",
  "- Anchor: event times -5 through -3 only.",
  "- Persistent tie: at least two distinct joint applications in at least two anchor years.",
  "- Validation periods: -2 and -1; no post-treatment outcome is opened by N0.",
  "- Smallest main-text-relevant change: 0.05 on the share scale.",
  paste0("- N0 decision: **", decision$selected_path, "** — ",
         decision$path_description)
)
writeLines(freeze, file.path(OUT, "network_preanalysis_freeze.md"), useBytes = TRUE)

cert <- data.frame(
  check = c(
    "unique_roster_collaborator_key", "no_self_links",
    "anchor_stays_within_minus5_minus3", "persistent_tie_minimums",
    "symmetric_arms_present", "meaningful_effect_frozen",
    "support_gate_decision_written"
  ),
  pass = c(
    key_checks$duplicate_keys == 0L, key_checks$self_links == 0L,
    key_checks$min_event_time >= -5L && key_checks$max_event_time <= -3L,
    key_checks$min_joint_apps >= 2L && key_checks$min_joint_years >= 2L,
    nrow(treated) == 1L && nrow(control) == 1L,
    decision$meaningful_effect_threshold == 0.05,
    decision$selected_path %in% c("N1", "Q")
  ),
  value = c(
    key_checks$duplicate_keys, key_checks$self_links,
    paste(key_checks$min_event_time, key_checks$max_event_time, sep = ":"),
    paste(key_checks$min_joint_apps, key_checks$min_joint_years, sep = ":"),
    paste(census$arm, collapse = ";"), 0.05, decision$selected_path
  ),
  detail = c(
    "one row per roster-specific focal-collaborator tie", "focal differs from collaborator",
    "no validation or post year read", "two applications and two years",
    "same dyad construction for treated and frozen controls",
    "absolute share-scale MDE threshold", decision$path_description
  )
)
write_csv(cert, "network_n0_certification.csv")
manifest <- data.frame(
  artifact = c("network_persistent_ties.parquet", "network_support_census.csv",
               "network_n0_path_decision.csv", "network_preanalysis_freeze.md"),
  sha256 = vapply(
    file.path(OUT, c("network_persistent_ties.parquet", "network_support_census.csv",
                     "network_n0_path_decision.csv", "network_preanalysis_freeze.md")),
    digest::digest, character(1), file = TRUE, algo = "sha256"
  )
)
write_csv(manifest, "network_n0_manifest.csv")
message("Network N0 census written to: ", OUT)
if (!all(cert$pass)) quit(status = 1L)
