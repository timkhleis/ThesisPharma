#!/usr/bin/env Rscript

# Post-gate descriptive collaboration-network package.
#
# The certified annual design selected Path F. This script therefore estimates
# no causal network ATT and reports no inferential p-value. It opens positive
# event times only for transparent pooled levels and accounting decompositions.

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
OUT <- file.path(ROOT, "NETWORK_N4_DESCRIPTIVE")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

ties_file <- file.path(N0, "network_persistent_ties.parquet")
full_glob <- file.path(ROOT, "P6_BASE", "panel_matched", "*.parquet")
retained_file <- file.path(
  ROOT, "P7_STAYER_HETEROGENEITY", "stayer_unit_analysis.parquet"
)
n1_path <- file.path(N1, "network_n1_path_decision.csv")
n1_figure <- file.path(N1, "network_validation_leads.png")
db_file <- file.path(BASE, "output", "thesis_foundation.duckdb")
for (p in c(ties_file, retained_file, n1_path, n1_figure, db_file)) {
  if (!file.exists(p)) stop("Missing descriptive-network input: ", p)
}
n1 <- utils::read.csv(
  n1_path, check.names = FALSE, stringsAsFactors = FALSE,
  colClasses = "character"
)
if (nrow(n1) != 1L || n1$selected_path[[1L]] != "F" ||
    as.logical(n1$post_treatment_outcomes_opened[[1L]])) {
  stop("Descriptive package requires certified N1 Path F with causal N2 closed")
}

write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}
sha <- function(path) digest::digest(path, file = TRUE, algo = "sha256")
sql_path <- function(path, must_work = TRUE) gsub(
  "\\\\", "/", normalizePath(path, winslash = "/", mustWork = must_work)
)

# This scope statement is written before any positive-period query is run.
scope <- c(
  "# Collaboration networks after the failed annual validation",
  "",
  "The certified annual design selected Path F. Positive-event network",
  "outcomes are therefore opened only for post-gate descriptive accounting.",
  "This package estimates no causal network ATT, reports no p-value, and does",
  "not relabel a pooled pre/post contrast as causal.",
  "",
  "The thesis-facing population is initially retained treated inventors.",
  "Extensive-margin collaboration is shown for the full retained population.",
  "Legacy-tie persistence and recomposition use the strict persistent-tie",
  "subset. Full-cohort and control levels are supporting descriptive benchmarks.",
  "",
  "A strict legacy tie is unchanged from N0: at least two joint applications",
  "in at least two anchor years over event times -5 through -3. Post outcomes",
  "use event times +1 through +5. The recorded acquisition year is omitted.",
  "",
  "Legacy partners are assigned to mutually exclusive post-window states:",
  "patented in the post-acquisition focal/acquirer group; patented only outside",
  "that group; or did not patent. New collaborators are assigned by a fixed",
  "priority rule: post focal/acquirer group, old target group, then other.",
  "",
  "All outputs are selected-population descriptions or accounting identities."
)
writeLines(scope, file.path(OUT, "network_descriptive_scope.md"), useBytes = TRUE)

con <- DBI::dbConnect(duckdb::duckdb(), db_file, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
tmp <- file.path(OUT, "duckdb_tmp")
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory='%s'", gsub("\\\\", "/", tmp)
))

qpath <- function(path) DBI::dbQuoteString(con, sql_path(path))
full_dir <- normalizePath(dirname(full_glob), winslash = "/", mustWork = TRUE)
full_q <- DBI::dbQuoteString(
  con, gsub("\\\\", "/", file.path(full_dir, "*.parquet"))
)

message("Network descriptive: building network-specific balance audit")
balance <- DBI::dbGetQuery(con, sprintf("
  WITH full_r AS MATERIALIZED (
    SELECT DISTINCT 'full_cohort' AS population, roster_row_id,
      CAST(deal_id AS INTEGER) AS deal_id, CAST(cohort AS INTEGER) AS cohort,
      arm, CAST(codinv AS BIGINT) AS codinv, CAST(weight AS DOUBLE) AS weight,
      CAST(focal_group_1 AS BIGINT) AS focal_pre_group,
      CASE WHEN arm='treated' THEN
        COALESCE(CAST(focal_group_2 AS BIGINT), CAST(focal_group_1 AS BIGINT))
      ELSE CAST(focal_group_1 AS BIGINT) END AS focal_post_group
    FROM read_parquet(%s)
    WHERE event_time=-1 AND cohort BETWEEN 1993 AND 2010
  ), retained_r AS MATERIALIZED (
    SELECT DISTINCT 'initially_retained' AS population, roster_row_id,
      CAST(deal_id AS INTEGER) AS deal_id, CAST(cohort AS INTEGER) AS cohort,
      arm, CAST(codinv AS BIGINT) AS codinv,
      CAST(raw_weight AS DOUBLE) AS weight,
      CAST(focal_group_1 AS BIGINT) AS focal_pre_group,
      CASE WHEN arm='treated' THEN
        COALESCE(CAST(acquirer_group AS BIGINT), CAST(focal_group_1 AS BIGINT))
      ELSE CAST(focal_group_1 AS BIGINT) END AS focal_post_group
    FROM read_parquet(%s)
    WHERE cohort BETWEEN 1993 AND 2010
  ), roster AS MATERIALIZED (
    SELECT * FROM full_r UNION ALL SELECT * FROM retained_r
  ), strict AS MATERIALIZED (
    SELECT r.*, COUNT(DISTINCT t.collaborator_codinv) AS anchor_collaborators
    FROM roster r JOIN read_parquet(%s) t USING(roster_row_id)
    GROUP BY ALL
  ), first_year AS MATERIALIZED (
    SELECT CAST(codinv AS BIGINT) AS codinv, MIN(year) AS first_year
    FROM inventor_year GROUP BY 1
  ), anchor_eval(event_time) AS (VALUES (-5),(-4),(-3)),
  partner_anchor AS (
    SELECT s.population, s.roster_row_id,
      AVG(CASE WHEN iy.codinv IS NULL THEN 0.0 ELSE 1.0 END)
        AS partner_anchor_active_rate,
      AVG(CAST((s.cohort-1)-fy.first_year AS DOUBLE))
        AS mean_partner_career_age
    FROM strict s
    JOIN read_parquet(%s) t USING(roster_row_id)
    CROSS JOIN anchor_eval e
    LEFT JOIN inventor_year iy
      ON CAST(iy.codinv AS BIGINT)=CAST(t.collaborator_codinv AS BIGINT)
     AND iy.year=s.cohort+e.event_time
    LEFT JOIN first_year fy
      ON fy.codinv=CAST(t.collaborator_codinv AS BIGINT)
    GROUP BY 1,2
  ), focal_pre AS (
    SELECT s.population, s.roster_row_id,
      SUM(CASE WHEN iy.year=s.cohort-5 THEN iy.patent_count ELSE 0 END)::DOUBLE
        AS patent_count_m5,
      SUM(CASE WHEN iy.year=s.cohort-4 THEN iy.patent_count ELSE 0 END)::DOUBLE
        AS patent_count_m4,
      SUM(CASE WHEN iy.year=s.cohort-3 THEN iy.patent_count ELSE 0 END)::DOUBLE
        AS patent_count_m3,
      SUM(CASE WHEN iy.year=s.cohort-2 THEN iy.patent_count ELSE 0 END)::DOUBLE
        AS patent_count_m2,
      SUM(CASE WHEN iy.year=s.cohort-1 THEN iy.patent_count ELSE 0 END)::DOUBLE
        AS patent_count_m1,
      MAX(CASE WHEN iy.year=s.cohort-5 AND iy.patent_count>0 THEN 1 ELSE 0 END)
        AS active_patenting_m5,
      MAX(CASE WHEN iy.year=s.cohort-4 AND iy.patent_count>0 THEN 1 ELSE 0 END)
        AS active_patenting_m4,
      MAX(CASE WHEN iy.year=s.cohort-3 AND iy.patent_count>0 THEN 1 ELSE 0 END)
        AS active_patenting_m3,
      MAX(CASE WHEN iy.year=s.cohort-2 AND iy.patent_count>0 THEN 1 ELSE 0 END)
        AS active_patenting_m2,
      MAX(CASE WHEN iy.year=s.cohort-1 AND iy.patent_count>0 THEN 1 ELSE 0 END)
        AS active_patenting_m1
    FROM strict s
    LEFT JOIN inventor_year iy
      ON CAST(iy.codinv AS BIGINT)=s.codinv
     AND iy.year BETWEEN s.cohort-5 AND s.cohort-1
    GROUP BY 1,2
  )
  SELECT s.*, p.partner_anchor_active_rate, p.mean_partner_career_age,
    f.patent_count_m5, f.patent_count_m4, f.patent_count_m3,
    f.patent_count_m2, f.patent_count_m1,
    f.active_patenting_m5, f.active_patenting_m4,
    f.active_patenting_m3, f.active_patenting_m2, f.active_patenting_m1
  FROM strict s
  JOIN partner_anchor p USING(population,roster_row_id)
  JOIN focal_pre f USING(population,roster_row_id)
  ORDER BY population,cohort,deal_id,arm DESC,codinv
", full_q, qpath(retained_file), qpath(ties_file), qpath(ties_file)))

make_weights <- function(x, extra = character()) {
  key <- unique(x[c("population", "roster_row_id", "cohort", "arm", "weight")])
  treated <- key[key$arm == "treated", ]
  mass <- stats::aggregate(weight ~ population + cohort, treated, sum)
  total <- stats::aggregate(weight ~ population, mass, sum)
  names(total)[names(total) == "weight"] <- "total_weight"
  mass <- merge(mass, total, by = "population", all.x = TRUE)
  mass$cohort_share <- mass$weight / mass$total_weight
  mass <- mass[c("population", "cohort", "cohort_share")]
  x <- merge(x, mass, by = c("population", "cohort"), all.x = TRUE,
             sort = FALSE)
  split_vars <- c("population", "arm", "cohort", extra)
  x$analysis_weight <- NA_real_
  for (idx in split(seq_len(nrow(x)), x[split_vars], drop = TRUE)) {
    ok <- is.finite(x$weight[idx]) & x$weight[idx] > 0
    x$analysis_weight[idx[ok]] <- x$cohort_share[idx[ok]] *
      x$weight[idx[ok]] / sum(x$weight[idx[ok]])
  }
  x
}
wmean <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  sum(x[ok] * w[ok]) / sum(w[ok])
}
wvar <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (sum(ok) < 2L) return(NA_real_)
  m <- wmean(x[ok], w[ok])
  sum(w[ok] * (x[ok] - m)^2) / sum(w[ok])
}

balance <- make_weights(balance)
balance_vars <- c(
  "anchor_collaborators", "partner_anchor_active_rate",
  "mean_partner_career_age", paste0("patent_count_m", 5:1),
  paste0("active_patenting_m", 5:1)
)
balance_rows <- list()
for (pop in unique(balance$population)) {
  z <- balance[balance$population == pop, ]
  for (v in balance_vars) {
    t <- z[z$arm == "treated", ]
    c <- z[z$arm == "control", ]
    mt <- wmean(t[[v]], t$analysis_weight)
    mc <- wmean(c[[v]], c$analysis_weight)
    vt <- wvar(t[[v]], t$analysis_weight)
    vc <- wvar(c[[v]], c$analysis_weight)
    scale <- sqrt((vt + vc) / 2)
    smd <- if (is.finite(scale) && scale > 0) (mt - mc) / scale else
      if (isTRUE(all.equal(mt, mc))) 0 else NA_real_
    balance_rows[[length(balance_rows) + 1L]] <- data.frame(
      population = pop, variable = v,
      treated_mean = mt, weighted_control_mean = mc,
      difference = mt - mc, standardized_mean_difference = smd,
      absolute_smd = abs(smd),
      treated_units = nrow(t), control_units = nrow(c),
      interpretation = "diagnostic_only_no_rematching",
      stringsAsFactors = FALSE
    )
  }
}
balance_summary <- do.call(rbind, balance_rows)
write_csv(balance_summary, "network_specific_balance_audit.csv")

message("Network descriptive: building pooled partner-persistence levels")
pooled <- DBI::dbGetQuery(con, sprintf("
  WITH full_r AS MATERIALIZED (
    SELECT DISTINCT 'full_cohort' AS population, roster_row_id,
      CAST(deal_id AS INTEGER) AS deal_id, CAST(cohort AS INTEGER) AS cohort,
      arm, CAST(codinv AS BIGINT) AS codinv, CAST(weight AS DOUBLE) AS weight,
      CAST(focal_group_1 AS BIGINT) AS focal_pre_group,
      CASE WHEN arm='treated' THEN
        COALESCE(CAST(focal_group_2 AS BIGINT), CAST(focal_group_1 AS BIGINT))
      ELSE CAST(focal_group_1 AS BIGINT) END AS focal_post_group
    FROM read_parquet(%s)
    WHERE event_time=-1 AND cohort BETWEEN 1993 AND 2010
  ), retained_r AS MATERIALIZED (
    SELECT DISTINCT 'initially_retained' AS population, roster_row_id,
      CAST(deal_id AS INTEGER) AS deal_id, CAST(cohort AS INTEGER) AS cohort,
      arm, CAST(codinv AS BIGINT) AS codinv,
      CAST(raw_weight AS DOUBLE) AS weight,
      CAST(focal_group_1 AS BIGINT) AS focal_pre_group,
      CASE WHEN arm='treated' THEN
        COALESCE(CAST(acquirer_group AS BIGINT), CAST(focal_group_1 AS BIGINT))
      ELSE CAST(focal_group_1 AS BIGINT) END AS focal_post_group
    FROM read_parquet(%s)
    WHERE cohort BETWEEN 1993 AND 2010
  ), roster AS MATERIALIZED (
    SELECT * FROM full_r UNION ALL SELECT * FROM retained_r
  ), strict AS MATERIALIZED (
    SELECT r.* FROM roster r
    WHERE EXISTS (SELECT 1 FROM read_parquet(%s) t
                  WHERE t.roster_row_id=r.roster_row_id)
  ), eval(analysis_window,event_time) AS (
    VALUES ('pre_m2_m1',-2),('pre_m2_m1',-1),
           ('post_p1_p2',1),('post_p1_p2',2),
           ('post_p1_p5',1),('post_p1_p5',2),('post_p1_p5',3),
           ('post_p1_p5',4),('post_p1_p5',5)
  ), partner_group_year AS MATERIALIZED (
    SELECT DISTINCT CAST(pi.codinv AS BIGINT) AS codinv,
      CAST(pcl.year AS INTEGER) AS patent_year,
      CAST(pcl.id_group AS BIGINT) AS id_group
    FROM patent_inventor pi JOIN patent_company_link pcl
      ON CAST(pcl.appln_id AS BIGINT)=CAST(pi.appln_id AS BIGINT)
    WHERE pcl.id_group IS NOT NULL
  ), expanded AS (
    SELECT s.population,s.roster_row_id,s.deal_id,s.cohort,s.arm,s.codinv,
      s.weight,e.analysis_window,e.event_time,t.collaborator_codinv,
      CASE WHEN e.event_time<0 THEN s.focal_pre_group
           ELSE s.focal_post_group END AS focal_group,
      p.codinv IS NOT NULL AS partner_in_focal_group
    FROM strict s JOIN read_parquet(%s) t USING(roster_row_id)
    CROSS JOIN eval e
    LEFT JOIN partner_group_year p
      ON p.codinv=CAST(t.collaborator_codinv AS BIGINT)
     AND p.patent_year=s.cohort+e.event_time
     AND p.id_group=CASE WHEN e.event_time<0 THEN s.focal_pre_group
                         ELSE s.focal_post_group END
  )
  SELECT population,roster_row_id,deal_id,cohort,arm,codinv,weight,
    analysis_window,
    AVG(CASE WHEN partner_in_focal_group THEN 1.0 ELSE 0.0 END)
      AS partner_focal_persistence_rate
  FROM expanded GROUP BY 1,2,3,4,5,6,7,8
  ORDER BY population,analysis_window,cohort,deal_id,arm DESC,codinv
", full_q, qpath(retained_file), qpath(ties_file), qpath(ties_file)))
pooled <- make_weights(pooled, "analysis_window")
pooled_summary <- do.call(rbind, lapply(
  split(pooled, list(
    pooled$population, pooled$arm, pooled$analysis_window
  ), drop = TRUE),
  function(z) data.frame(
    population = z$population[[1L]], arm = z$arm[[1L]],
    analysis_window = z$analysis_window[[1L]],
    weighted_mean = wmean(z$partner_focal_persistence_rate,
                          z$analysis_weight),
    focal_inventors = nrow(z), distinct_deals = length(unique(z$deal_id)),
    status = "descriptive_level_not_a_causal_effect",
    stringsAsFactors = FALSE
  )
))
rownames(pooled_summary) <- NULL
write_csv(pooled_summary, "network_pooled_descriptive_levels.csv")

message("Network descriptive: building retained-inventor recomposition")
post <- DBI::dbGetQuery(con, sprintf("
  WITH r AS MATERIALIZED (
    SELECT DISTINCT roster_row_id, CAST(deal_id AS INTEGER) AS deal_id,
      CAST(cohort AS INTEGER) AS cohort, CAST(codinv AS BIGINT) AS codinv,
      CAST(raw_weight AS DOUBLE) AS weight,
      CAST(focal_group_1 AS BIGINT) AS focal_pre_group,
      COALESCE(CAST(acquirer_group AS BIGINT),
               CAST(focal_group_1 AS BIGINT)) AS focal_post_group
    FROM read_parquet(%s)
    WHERE arm='treated' AND cohort BETWEEN 1993 AND 2010
  ), legacy AS MATERIALIZED (
    SELECT r.roster_row_id, CAST(t.collaborator_codinv AS BIGINT) collaborator
    FROM r JOIN read_parquet(%s) t USING(roster_row_id)
  ), legacy_count AS (
    SELECT roster_row_id, COUNT(DISTINCT collaborator) AS legacy_count
    FROM legacy GROUP BY 1
  ), focal_apps AS MATERIALIZED (
    SELECT DISTINCT r.roster_row_id,r.deal_id,r.cohort,r.codinv,r.weight,
      r.focal_pre_group,r.focal_post_group,CAST(pa.appln_id AS BIGINT) appln_id
    FROM r JOIN patent_inventor pi
      ON CAST(pi.codinv AS BIGINT)=r.codinv
    JOIN patent_application pa
      ON CAST(pa.appln_id AS BIGINT)=CAST(pi.appln_id AS BIGINT)
     AND pa.patent_year BETWEEN r.cohort+1 AND r.cohort+5
  ), app_flags AS MATERIALIZED (
    SELECT f.*,
      MAX(CASE WHEN CAST(pcl.id_group AS BIGINT)=f.focal_post_group
               THEN 1 ELSE 0 END) AS in_post_focal_group,
      MAX(CASE WHEN CAST(pcl.id_group AS BIGINT)=f.focal_pre_group
               THEN 1 ELSE 0 END) AS in_pre_target_group
    FROM focal_apps f LEFT JOIN patent_company_link pcl
      ON CAST(pcl.appln_id AS BIGINT)=f.appln_id
    GROUP BY ALL
  ), post_partner AS MATERIALIZED (
    SELECT a.roster_row_id, CAST(pi.codinv AS BIGINT) collaborator,
      MAX(a.in_post_focal_group) AS in_post_focal_group,
      MAX(a.in_pre_target_group) AS in_pre_target_group
    FROM app_flags a JOIN patent_inventor pi
      ON CAST(pi.appln_id AS BIGINT)=a.appln_id
     AND CAST(pi.codinv AS BIGINT)<>a.codinv
    GROUP BY 1,2
  ), post_collab AS (
    SELECT p.roster_row_id, COUNT(*) AS post_collaborators,
      SUM(CASE WHEN l.collaborator IS NOT NULL THEN 1 ELSE 0 END)
        AS recurrent_legacy_collaborators,
      SUM(CASE WHEN l.collaborator IS NULL THEN 1 ELSE 0 END)
        AS new_collaborators,
      SUM(CASE WHEN l.collaborator IS NULL AND p.in_post_focal_group=1
               THEN 1 ELSE 0 END) AS new_post_focal_group,
      SUM(CASE WHEN l.collaborator IS NULL AND p.in_post_focal_group=0
                AND p.in_pre_target_group=1 THEN 1 ELSE 0 END)
        AS new_pre_target_group,
      SUM(CASE WHEN l.collaborator IS NULL AND p.in_post_focal_group=0
                AND p.in_pre_target_group=0 THEN 1 ELSE 0 END)
        AS new_other
    FROM post_partner p LEFT JOIN legacy l
      ON l.roster_row_id=p.roster_row_id AND l.collaborator=p.collaborator
    GROUP BY 1
  ), partner_any AS MATERIALIZED (
    SELECT l.roster_row_id,l.collaborator,
      MAX(CASE WHEN iy.codinv IS NOT NULL THEN 1 ELSE 0 END) AS any_post_patent
    FROM legacy l JOIN r USING(roster_row_id)
    LEFT JOIN inventor_year iy
      ON CAST(iy.codinv AS BIGINT)=l.collaborator
     AND iy.year BETWEEN r.cohort+1 AND r.cohort+5
    GROUP BY 1,2
  ), partner_focal AS MATERIALIZED (
    SELECT DISTINCT l.roster_row_id,l.collaborator
    FROM legacy l JOIN r USING(roster_row_id)
    JOIN patent_inventor pi ON CAST(pi.codinv AS BIGINT)=l.collaborator
    JOIN patent_application pa
      ON CAST(pa.appln_id AS BIGINT)=CAST(pi.appln_id AS BIGINT)
     AND pa.patent_year BETWEEN r.cohort+1 AND r.cohort+5
    JOIN patent_company_link pcl
      ON CAST(pcl.appln_id AS BIGINT)=CAST(pi.appln_id AS BIGINT)
     AND CAST(pcl.id_group AS BIGINT)=r.focal_post_group
  ), legacy_state AS (
    SELECT a.roster_row_id,
      AVG(CASE WHEN f.collaborator IS NOT NULL THEN 1.0 ELSE 0.0 END)
        AS legacy_focal_group_share,
      AVG(CASE WHEN f.collaborator IS NULL AND a.any_post_patent=1
               THEN 1.0 ELSE 0.0 END) AS legacy_outside_only_share,
      AVG(CASE WHEN a.any_post_patent=0 THEN 1.0 ELSE 0.0 END)
        AS legacy_no_post_patent_share
    FROM partner_any a LEFT JOIN partner_focal f
      ON f.roster_row_id=a.roster_row_id AND f.collaborator=a.collaborator
    GROUP BY 1
  )
  SELECT r.roster_row_id,r.deal_id,r.cohort,r.codinv,r.weight,
    CASE WHEN lc.legacy_count IS NULL THEN 0 ELSE 1 END AS strict_tie_sample,
    COALESCE(lc.legacy_count,0) AS legacy_count,
    CASE WHEN fa.roster_row_id IS NULL THEN 0 ELSE 1 END AS any_post_patent,
    CASE WHEN pc.roster_row_id IS NULL THEN 0 ELSE 1 END
      AS any_post_collaboration,
    COALESCE(pc.post_collaborators,0) AS post_collaborators,
    COALESCE(pc.recurrent_legacy_collaborators,0)
      AS recurrent_legacy_collaborators,
    COALESCE(pc.new_collaborators,0) AS new_collaborators,
    COALESCE(pc.new_post_focal_group,0) AS new_post_focal_group,
    COALESCE(pc.new_pre_target_group,0) AS new_pre_target_group,
    COALESCE(pc.new_other,0) AS new_other,
    CASE WHEN lc.legacy_count>0 THEN
      COALESCE(pc.recurrent_legacy_collaborators,0)::DOUBLE/lc.legacy_count
      ELSE NULL END AS legacy_recurrence_share,
    CASE WHEN pc.post_collaborators>0 THEN
      COALESCE(pc.recurrent_legacy_collaborators,0)::DOUBLE/
        pc.post_collaborators ELSE NULL END AS legacy_share_post_team,
    CASE WHEN pc.new_collaborators>0 THEN
      pc.new_post_focal_group::DOUBLE/pc.new_collaborators ELSE NULL END
      AS new_post_focal_group_share,
    CASE WHEN pc.new_collaborators>0 THEN
      pc.new_pre_target_group::DOUBLE/pc.new_collaborators ELSE NULL END
      AS new_pre_target_group_share,
    CASE WHEN pc.new_collaborators>0 THEN
      pc.new_other::DOUBLE/pc.new_collaborators ELSE NULL END
      AS new_other_share,
    ls.legacy_focal_group_share,ls.legacy_outside_only_share,
    ls.legacy_no_post_patent_share
  FROM r LEFT JOIN legacy_count lc USING(roster_row_id)
  LEFT JOIN (SELECT DISTINCT roster_row_id FROM focal_apps) fa USING(roster_row_id)
  LEFT JOIN post_collab pc USING(roster_row_id)
  LEFT JOIN legacy_state ls USING(roster_row_id)
  ORDER BY cohort,deal_id,codinv
", qpath(retained_file), qpath(ties_file)))

post$population <- "initially_retained"
post$arm <- "treated"
post <- make_weights(post)
spec <- data.frame(
  sample = c(
    "all_initially_retained", "all_initially_retained",
    "all_initially_retained", rep("strict_persistent_tie_subset", 9)
  ),
  metric = c(
    "any_post_patent", "any_post_collaboration", "post_collaborators",
    "any_legacy_recurrence", "legacy_recurrence_share",
    "legacy_focal_group_share", "legacy_outside_only_share",
    "legacy_no_post_patent_share", "post_collaborators",
    "legacy_share_post_team", "new_post_focal_group_share",
    "new_pre_target_group_share"
  ),
  condition = c(
    "all", "all", "any_post_collaboration",
    "strict", "strict", "strict", "strict", "strict",
    "strict_and_any_post_collaboration", "strict_and_any_post_collaboration",
    "strict_and_any_new_collaborator", "strict_and_any_new_collaborator"
  ), stringsAsFactors = FALSE
)
spec <- rbind(spec, data.frame(
  sample = "strict_persistent_tie_subset", metric = "new_other_share",
  condition = "strict_and_any_new_collaborator", stringsAsFactors = FALSE
))
desc_rows <- list()
for (i in seq_len(nrow(spec))) {
  z <- post
  cond <- spec$condition[i]
  if (grepl("strict", cond)) z <- z[z$strict_tie_sample == 1L, ]
  if (cond %in% c("any_post_collaboration",
                  "strict_and_any_post_collaboration")) {
    z <- z[z$any_post_collaboration == 1L, ]
  }
  if (cond == "strict_and_any_new_collaborator") {
    z <- z[z$new_collaborators > 0, ]
  }
  metric <- spec$metric[i]
  value <- if (metric == "any_legacy_recurrence")
    as.numeric(z$recurrent_legacy_collaborators > 0) else z[[metric]]
  desc_rows[[i]] <- data.frame(
    sample = spec$sample[i], metric = metric,
    estimate = wmean(value, z$analysis_weight),
    focal_inventors = nrow(z), distinct_deals = length(unique(z$deal_id)),
    denominator = cond,
    status = "descriptive_selected_population_no_causal_ATT",
    stringsAsFactors = FALSE
  )
}
retained_summary <- do.call(rbind, desc_rows)
write_csv(retained_summary, "network_retained_descriptive_summary.csv")

# Exact category identities are checked at the focal-inventor level.
strict_post <- post[post$strict_tie_sample == 1L, ]
legacy_identity <- with(strict_post, legacy_focal_group_share +
  legacy_outside_only_share + legacy_no_post_patent_share)
new_ok <- strict_post$new_collaborators > 0
new_identity <- with(strict_post[new_ok, ], new_post_focal_group_share +
  new_pre_target_group_share + new_other_share)

balance_max <- stats::aggregate(
  absolute_smd ~ population, balance_summary, max, na.rm = TRUE
)
write_csv(balance_max, "network_specific_balance_maximum.csv")

cert <- data.frame(
  check = c(
    "upstream_path_f_preserved", "causal_post_gate_remains_closed",
    "descriptive_scope_written", "cohorts_start_in_1993",
    "legacy_states_sum_to_one", "new_partner_states_sum_to_one",
    "pooled_levels_have_no_inference", "retained_rows_have_no_inference",
    "network_balance_is_reported", "annual_validation_figure_preserved"
  ),
  pass = c(
    n1$selected_path[[1L]] == "F",
    !as.logical(n1$post_treatment_outcomes_opened[[1L]]),
    file.exists(file.path(OUT, "network_descriptive_scope.md")),
    min(c(balance$cohort, pooled$cohort, post$cohort)) == 1993L,
    all(abs(legacy_identity - 1) < 1e-10),
    all(abs(new_identity - 1) < 1e-10),
    !any(c("p_value", "ci_low", "ci_high") %in% names(pooled_summary)),
    !any(c("p_value", "ci_low", "ci_high") %in% names(retained_summary)),
    nrow(balance_summary) == 2L * length(balance_vars),
    file.exists(n1_figure)
  ),
  value = c(
    n1$selected_path[[1L]], n1$post_treatment_outcomes_opened[[1L]],
    sha(file.path(OUT, "network_descriptive_scope.md")),
    min(c(balance$cohort, pooled$cohort, post$cohort)),
    max(abs(legacy_identity - 1)), max(abs(new_identity - 1)),
    nrow(pooled_summary), nrow(retained_summary),
    nrow(balance_summary), sha(n1_figure)
  ),
  detail = c(
    "failed annual validation remains the governing causal result",
    "N2 causal treatment effects are not estimated",
    "post-gate descriptive amendment is explicit",
    "all descriptive samples use the amended 1993--2010 cohorts",
    "focal/acquirer, outside-only, and no-patent shares are exhaustive",
    "new focal/acquirer, old target, and other shares are exhaustive",
    "arm-window levels only; no pooled DiD or p-value",
    "selected-population accounting only; no p-value",
    "strict-tie baseline composition and patent trajectories audited",
    "failed annual event study remains available for the appendix"
  ), stringsAsFactors = FALSE
)
write_csv(cert, "network_descriptive_certification.csv")
if (!all(cert$pass)) stop("Network descriptive certification failed")

find_metric <- function(name) retained_summary$estimate[
  retained_summary$metric == name][1L]
results <- c(
  "# Descriptive collaboration-network results",
  "",
  "The annual causal design remains on Path F. The following results describe",
  "network continuity and recomposition among initially retained inventors;",
  "they are not acquisition treatment effects.",
  "",
  sprintf(
    "Among all initially retained inventors, %.1f%% collaborate with at least one co-inventor during event times +1 through +5.",
    100 * find_metric("any_post_collaboration")
  ),
  sprintf(
    "Within the strict legacy-tie subset, %.1f%% reconnect with at least one persistent pre-deal collaborator.",
    100 * find_metric("any_legacy_recurrence")
  ),
  sprintf(
    "Across strict legacy partners, %.1f%% patent in the post-acquisition focal/acquirer organization, %.1f%% patent only outside it, and %.1f%% do not patent in the five-year post window.",
    100 * find_metric("legacy_focal_group_share"),
    100 * find_metric("legacy_outside_only_share"),
    100 * find_metric("legacy_no_post_patent_share")
  ),
  "",
  paste0(
    "The largest absolute network-specific baseline SMD is ",
    paste(sprintf("%s %.3f", balance_max$population,
                  balance_max$absolute_smd), collapse = "; "), "."
  ),
  "",
  "The accompanying pooled treated and control levels are descriptive",
  "benchmarks only. No difference-in-differences estimate is reported."
)
writeLines(results, file.path(OUT, "network_descriptive_results.md"),
           useBytes = TRUE)

artifacts <- c(
  "network_descriptive_scope.md", "network_specific_balance_audit.csv",
  "network_specific_balance_maximum.csv",
  "network_pooled_descriptive_levels.csv",
  "network_retained_descriptive_summary.csv",
  "network_descriptive_certification.csv", "network_descriptive_results.md"
)
manifest <- data.frame(
  artifact = artifacts,
  sha256 = vapply(file.path(OUT, artifacts), sha, character(1)),
  bytes = file.info(file.path(OUT, artifacts))$size,
  stringsAsFactors = FALSE
)
write_csv(manifest, "network_descriptive_manifest.csv")
message("Certified descriptive network package written to: ", OUT)
