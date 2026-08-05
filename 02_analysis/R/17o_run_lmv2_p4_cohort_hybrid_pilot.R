# ============================================================================
# run_cohort_hybrid_pilot.R -- DB-facing harness, COHORT-LEVEL hybrid design
# ============================================================================
# SECOND PASS after review correction. Two consequential design errors fixed:
#
# (1) Stage-2 distances cannot be cached at the loosest Stage-1 profile and
#     merely subsetted. lmv2_prepare_stage2_edges() (16c_lmv2_matching_utils.R
#     :410-433) recomputes its covariate/tech-distance scalers from whatever
#     `controls` population is passed in (`lmv2_safe_sd()` over the UNIQUE
#     candidate set) -- tightening Stage 1 changes that population, which
#     changes the standardized distance for the SAME raw pair, which can flip
#     whether it clears the Stage-2 caliper. Verified directly and dramatically
#     (certify_stage2_candidate_pool_rescaling.R): an identical pair's distance
#     moved from 2.0 (excluded at caliper 1.5) to 0.136 (included) purely from
#     changing the candidate population, nothing about the pair itself.
#     FIX: cache ONLY the expensive, profile-INDEPENDENT raw cosine
#     similarities and shared-IPC4 indicators (pair-level facts that do not
#     depend on firm admissibility). Recompute the cheap Stage-1-caliper-
#     dependent candidate pairs AND the Stage-2 scalers/composite distance
#     (via lmv2_prepare_stage2_edges) separately for every Stage-1 profile,
#     scoped to that profile's own eligible-control population.
#
# (2) Retention was measured against an artificially narrowed denominator:
#     missing-covariate inventors and Stage-1-lost deals were both removed
#     BEFORE computing the ratio, so a very restrictive caliper that killed
#     most deals could still show a deceptively high retention number.
#     FIX: headline retention is now computed against the COMPLETE primary
#     pilot spine (lmv2_ebal_compute_retention_funnel(), which also reports
#     the full funnel: full treated -> covariate-complete -> Stage-1-
#     supported -> Stage-2-supported) -- and this is the number fed into the
#     hierarchy's retention gate, not the narrowed intermediate count.
#
# Additional corrections: control covariates now join on the full
# (cohort, control_codinv, control_group) key, not (cohort, control_codinv)
# alone; every covariate-attachment join is an explicit LEFT join with
# uniqueness/row-count/no-missing-value assertions (lmv2_left_join_checked())
# so an unexpected missing match errors loudly instead of silently narrowing
# the population; the final treated-weight/mass invariant assertions now run
# in the actual pilot path (both exact and approximate solutions), not only
# in certification fixtures; the file now has an actual --mode=certify|
# production CLI invocation; a manifest records source hashes and package
# versions.
#
# CODE-ONLY, NOT YET EXECUTED. Run the COMPLETE three pilot cohorts (1995,
# 2002, 2009 -- 37 deals total), never a subsample. The frozen 10 hard deals
# are tagged as a nested stress-test diagnostic within that full population.
#
# Grid: Stage-1 caliper {1.0,1.5,2.0} x profile {all_eligible,nearest_50} x
# universe {u1,u3} x scheme {primary,equal_deal} = 24 solves/cohort x 3
# cohorts = 72 rows, solved separately WITHIN each cohort.
#
# Reuses, unedited: the certified 17g/16c functions throughout; the U1/U3
# universe-construction logic already parity-verified against certified P3
# (FIX-3, max|distance diff| = 7.8e-15) and against certified P2 eligibility
# (FIX-4, exact match on 692,548 rows). No 15*/16*/17g file is edited.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))
source(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
`%||%` <- function(a, b) if (is.null(a)) b else a

STAGE1_CALIPERS <- c(1.0, 1.5, 2.0)
STAGE1_PROFILES <- c("all_eligible", "nearest_50")
UNIVERSES <- c("u1", "u3")     # U2 omitted per instruction (added almost no information)
SCHEMES <- c("primary", "equal_deal")
STAGE2_CALIPER <- 1.5          # locked, unchanged from the deal-level pilot
MIN_ELIGIBLE_FIRMS <- 5L       # locked support gate
COHORTS <- c(1995L, 2002L, 2009L)
# Memory fix: cohorts routed through the disk-backed technology cache
# (never holding the full pairwise similarity matrix in RAM) instead of the
# original in-memory build_stage2_technology_cache_for_cohort() path. 1995
# and 2002 already completed cleanly under the in-memory path and are never
# recomputed; only cohort 2009 (which OOM'd DuckDB's 9GB budget) is listed.
LMV2_DISKBACKED_COHORTS <- c(2009L)
FROZEN_10_PATH <- file.path(BASE, "notes", "local_match_v2_p4_pilot_deal_selection_frozen.csv")
source(file.path(BASE, "R", "17n_lmv2_p4_disk_backed_cache.R"))

# =============================================================================
# Left join with mandatory checks (additional correction): uniqueness of the
# lookup key, unchanged row count, and no missing values in the attached
# columns. A plain inner merge() can silently ERASE unsupported observations
# (a row with no match just vanishes); this makes that impossible to miss.
# =============================================================================
lmv2_left_join_checked <- function(left, right, by, context, no_missing_cols = NULL) {
  if (anyDuplicated(right[by])) {
    stop(context, ": right-hand lookup has duplicate keys on (", paste(by, collapse = ", "), ")")
  }
  n_before <- nrow(left)
  out <- merge(left, right, by = by, all.x = TRUE)
  if (nrow(out) != n_before) {
    stop(sprintf("%s: row count changed after left join (%d -> %d) -- unexpected fan-out", context, n_before, nrow(out)))
  }
  for (col in no_missing_cols %||% character(0)) {
    # EXISTENCE first, not merely absence of NA (review correction): a name
    # collision between `left` and `right` on a non-key column gets silently
    # suffixed by merge() to "col.x"/"col.y", so `col` itself no longer
    # exists -- out[[col]] would then be NULL, and anyNA(NULL) is FALSE,
    # which would silently pass the old check. This is exactly the bug that
    # broke firm_patent_trajectory attachment (both the inventor covariate
    # table and the firm covariate table have a raw `patent_trajectory`
    # column). Caller must rename to the final non-colliding name BEFORE
    # calling this function; this check makes that omission a hard, loud
    # failure instead of a silently-dropped covariate.
    if (!col %in% names(out)) {
      stop(context, ": requested output column '", col, "' does not exist after the join -- likely a name ",
          "collision silently suffixed to '", col, ".x'/'", col, ".y' by merge(); rename to a non-colliding ",
          "name in `left`/`right` BEFORE joining, do not rely on a post-join copy")
    }
    if (anyNA(out[[col]])) stop(context, ": missing '", col, "' for some row(s) after left join -- no authoritative match")
  }
  out
}

# =============================================================================
# STEP 1 -- universe firm pools (U1 certified, U3 fresh). Unchanged from the
# first pass (this part was never in question).
# =============================================================================
build_universe_pools_and_scalers_and_edges <- function(con, cohorts) {
  message("Building unfiltered firm covariates for pilot cohorts...")
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE h_activity AS
    WITH stacks AS (SELECT UNNEST([%s]) AS cohort)
    SELECT s.cohort, CAST(pcl.id_group AS DOUBLE) AS id_group,
           COUNT(DISTINCT pcl.appln_id) AS patent_stock_5y,
           COUNT(DISTINCT CAST(pi.codinv AS BIGINT)) AS inventor_count_5y
    FROM stacks s
    JOIN patent_company_link pcl ON pcl.year BETWEEN s.cohort-5 AND s.cohort-1
    JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
    WHERE pcl.id_group IS NOT NULL
    GROUP BY s.cohort, pcl.id_group", paste(cohorts, collapse = ",")))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE h_trajectory AS
    WITH stacks AS (SELECT UNNEST([%s]) AS cohort)
    SELECT s.cohort, g.id_group,
      SUM(CASE WHEN g.year BETWEEN s.cohort-5 AND s.cohort-3 THEN g.patent_count ELSE 0 END) AS patents_early,
      SUM(CASE WHEN g.year BETWEEN s.cohort-2 AND s.cohort-1 THEN g.patent_count ELSE 0 END) AS patents_recent
    FROM stacks s
    JOIN lmv2_p3_group_year_patents g ON g.year BETWEEN s.cohort-5 AND s.cohort-1
    GROUP BY s.cohort, g.id_group", paste(cohorts, collapse = ",")))
  DBI::dbExecute(con, "
    CREATE OR REPLACE TEMP TABLE h_firm_covars AS
    SELECT a.cohort, a.id_group, a.patent_stock_5y, a.inventor_count_5y,
      LN(1+a.patent_stock_5y) AS log_patent_stock_5y,
      LN(1+a.inventor_count_5y) AS log_inventor_count_5y,
      LN(1+COALESCE(t.patents_recent,0)/2.0) - LN(1+COALESCE(t.patents_early,0)/3.0) AS patent_trajectory
    FROM h_activity a LEFT JOIN h_trajectory t USING (cohort, id_group)")
  DBI::dbExecute(con, "
    CREATE OR REPLACE TEMP TABLE h_target_events AS
    SELECT DISTINCT CAST(target_group AS DOUBLE) AS id_group, CAST(target_year AS INTEGER) AS event_year
    FROM deal_assignment WHERE target_group IS NOT NULL
    UNION
    SELECT DISTINCT CAST(fg.id_group AS DOUBLE) AS id_group, CAST(da.target_year AS INTEGER) AS event_year
    FROM deal_assignment da
    JOIN deal_target_company_expanded dtc ON dtc.deal_id = da.deal_id
    JOIN firm_group fg ON CAST(fg.compcod AS BIGINT) = dtc.target_compcod
     AND fg.year = CAST(da.target_year AS INTEGER) - 1
    WHERE fg.id_group IS NOT NULL")
  DBI::dbExecute(con, "CREATE OR REPLACE TEMP TABLE h_ever_target AS SELECT DISTINCT id_group FROM h_target_events")
  DBI::dbExecute(con, "
    CREATE OR REPLACE TEMP TABLE h_acquirer_events AS
    SELECT DISTINCT CAST(acquirer_group AS DOUBLE) AS id_group, CAST(target_year AS INTEGER) AS event_year
    FROM deal_assignment WHERE acquirer_group IS NOT NULL")
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE h_pool_u1 AS
    SELECT f.* FROM h_firm_covars f WHERE f.cohort IN (%s)
    AND NOT EXISTS (SELECT 1 FROM h_ever_target e WHERE e.id_group=f.id_group)
    AND NOT EXISTS (SELECT 1 FROM h_acquirer_events ae WHERE ae.id_group=f.id_group
                    AND ae.event_year BETWEEN f.cohort-5 AND f.cohort+5)", paste(cohorts, collapse = ",")))
  # P5.1 U2: not-yet-treated targets first exposed after the complete
  # five-year outcome window are eligible; acquirer-event cleanliness is
  # unchanged from U1. Existing U1/U3 behavior is untouched.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE h_pool_u2 AS
    SELECT f.* FROM h_firm_covars f WHERE f.cohort IN (%s)
    AND NOT EXISTS (SELECT 1 FROM h_target_events te WHERE te.id_group=f.id_group
                    AND te.event_year<=f.cohort+5)
    AND NOT EXISTS (SELECT 1 FROM h_acquirer_events ae WHERE ae.id_group=f.id_group
                    AND ae.event_year BETWEEN f.cohort-5 AND f.cohort+5)",
    paste(cohorts, collapse = ",")))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE h_pool_u3 AS
    SELECT f.* FROM h_firm_covars f WHERE f.cohort IN (%s)
    AND NOT EXISTS (SELECT 1 FROM h_target_events te WHERE te.id_group=f.id_group AND te.event_year<=f.cohort+5)",
    paste(cohorts, collapse = ",")))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE h_inv_latest AS
    WITH latest AS (
      SELECT s.cohort, CAST(ia.codinv AS BIGINT) AS codinv, ia.resolved_group, ia.candidate_group_count,
             ROW_NUMBER() OVER (PARTITION BY s.cohort, ia.codinv ORDER BY ia.year DESC) AS rn
      FROM (SELECT UNNEST([%s]) AS cohort) s
      JOIN inventor_affiliation_own ia ON ia.year BETWEEN s.cohort-5 AND s.cohort-1
    ), all_target_exposures AS (
      SELECT DISTINCT CAST(pi.codinv AS BIGINT) AS codinv, CAST(sp.deal_year AS INTEGER) AS exposure_year
      FROM cassi_deal_group_spine_expanded sp
      JOIN deal_target_company_expanded dtc ON dtc.deal_id = sp.deal_id
      JOIN patent_company_link pcl ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
       AND pcl.year BETWEEN CAST(sp.deal_year AS INTEGER)-5 AND CAST(sp.deal_year AS INTEGER)-1
      JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id WHERE pi.codinv IS NOT NULL
    )
    SELECT l.cohort, l.codinv, CAST(l.resolved_group AS DOUBLE) AS control_group
    FROM latest l
    WHERE l.rn=1 AND l.candidate_group_count=1 AND l.resolved_group IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM all_target_exposures te
                    WHERE te.codinv=l.codinv AND te.exposure_year<=l.cohort+5)", paste(cohorts, collapse = ",")))
  invisible(TRUE)
}

build_universe_edges <- function(con, g, pool_tbl, all_treated_g) {
  pool <- DBI::dbGetQuery(con, sprintf("SELECT * FROM %s WHERE cohort=%d", pool_tbl, g))
  if (pool_tbl == "h_pool_u1") {
    edges <- DBI::dbGetQuery(con, sprintf("
      SELECT cohort, deal_id, control_group, distance_base AS distance
      FROM lmv2_p3_stage1_edges WHERE resolution='ipc4' AND cohort=%d", g))
    # The authoritative U1 edge table is cohort-wide. P5's DealSim branch
    # deliberately restricts the treated estimand to one tercile, so retain
    # only edges belonging to the supplied treated-deal roster. For the main
    # P4/P5 branch `all_treated_g` contains the full cohort and this is a
    # no-op.
    edges <- edges[
      edges$deal_id %in% unique(as.integer(all_treated_g$deal_id)),
      ,
      drop = FALSE]
    return(list(edges = edges, missing_log = data.frame()))
  }
  ids_needed <- unique(c(all_treated_g$id_group, pool$id_group))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE h_vecs AS
    WITH roster AS (SELECT UNNEST([%s]) AS id_group),
    weighted AS (
      SELECT r.id_group, m.ipc_feature, SUM(gy.patent_count)::DOUBLE AS weight
      FROM roster r
      JOIN group_ipc_year gy ON CAST(gy.id_group AS BIGINT)=r.id_group AND gy.year BETWEEN %d AND %d
      JOIN lmv2_p3_ipc_code_map m USING (ipc_code)
      WHERE m.resolution='ipc4'
      GROUP BY r.id_group, m.ipc_feature
    )
    SELECT *, weight/SUM(weight) OVER (PARTITION BY id_group) AS frequency FROM weighted",
    paste(ids_needed, collapse = ","), g - 5, g - 1))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE h_sim AS
    WITH norms AS (SELECT id_group, SQRT(SUM(frequency*frequency)) AS norm FROM h_vecs GROUP BY id_group),
    tgrid AS (SELECT UNNEST([%s]) AS target_group), pgrid AS (SELECT UNNEST([%s]) AS control_group),
    full_grid AS (SELECT target_group, control_group FROM tgrid CROSS JOIN pgrid),
    dots AS (
      SELECT t.id_group AS target_group, c.id_group AS control_group, SUM(t.frequency*c.frequency) AS dot
      FROM h_vecs t JOIN h_vecs c ON c.ipc_feature=t.ipc_feature
      WHERE t.id_group IN (%s) AND c.id_group IN (%s) GROUP BY t.id_group, c.id_group
    )
    SELECT g.target_group, g.control_group,
      CASE WHEN tn.norm>0 AND cn.norm>0
           THEN LEAST(1.0,GREATEST(0.0,COALESCE(d.dot,0)/(tn.norm*cn.norm))) ELSE NULL END AS cosine,
      (tn.norm IS NULL OR tn.norm=0) AS target_missing_vector,
      (cn.norm IS NULL OR cn.norm=0) AS control_missing_vector
    FROM full_grid g LEFT JOIN dots d USING (target_group, control_group)
    LEFT JOIN norms tn ON tn.id_group=g.target_group LEFT JOIN norms cn ON cn.id_group=g.control_group",
    paste(all_treated_g$id_group, collapse = ","), paste(pool$id_group, collapse = ","),
    paste(all_treated_g$id_group, collapse = ","), paste(pool$id_group, collapse = ",")))
  sims <- DBI::dbGetQuery(con, "SELECT * FROM h_sim")
  missing_log <- sims[is.na(sims$cosine), c("target_group", "control_group",
                                            "target_missing_vector", "control_missing_vector")]
  sims_ok <- sims[!is.na(sims$cosine), ]
  sims_ok$tech_distance <- 1 - sims_ok$cosine

  joint_stock <- c(all_treated_g$log_patent_stock_5y, pool$log_patent_stock_5y)
  joint_invc <- c(all_treated_g$log_inventor_count_5y, pool$log_inventor_count_5y)
  sd_stock <- lmv2_safe_sd(joint_stock)$sd; sd_invc <- lmv2_safe_sd(joint_invc)$sd
  sd_tech <- lmv2_safe_sd(sims_ok$tech_distance)$sd

  target_to_deal <- all_treated_g[c("id_group", "deal_id")]; names(target_to_deal) <- c("target_group", "deal_id")
  sims_all <- merge(sims_ok, target_to_deal, by = "target_group")
  base_pool <- merge(sims_all, pool[c("id_group", "log_patent_stock_5y", "log_inventor_count_5y")],
                     by.x = "control_group", by.y = "id_group")
  base_target <- all_treated_g[c("deal_id", "log_patent_stock_5y", "log_inventor_count_5y")]
  names(base_target)[-1] <- paste0(names(base_target)[-1], "_t")
  base <- merge(base_pool, base_target, by = "deal_id")
  base$gap_stock <- base$log_patent_stock_5y - base$log_patent_stock_5y_t
  base$gap_invc <- base$log_inventor_count_5y - base$log_inventor_count_5y_t
  base$distance <- sqrt(lmv2_scale_gap(base$gap_stock, sd_stock)^2 +
                        lmv2_scale_gap(base$gap_invc, sd_invc)^2 +
                        lmv2_scale_gap(base$tech_distance, sd_tech)^2)
  list(edges = data.frame(cohort = g, deal_id = base$deal_id, control_group = base$control_group,
                          distance = base$distance),
      missing_log = missing_log)
}

# =============================================================================
# IPC4-only specialization of 16c's lmv2_stage2_technology_cache() (memory
# fix, review correction). NOT an edit to 16c -- 15*/16*/17a-e stay certified
# and untouched; this is a new, additive function living alongside the pilot
# harness that happens to reuse 16c's unmodified lmv2_shared_ipc4_matrix()
# (already IPC4-only by construction: both its treated_features and
# control_features CTEs hardcode `m.resolution='ipc4'`) for the shared-IPC4
# half, and replaces only the SIMILARITY half.
#
# 16c's general lmv2_stage2_technology_cache() computes cosine similarity for
# EVERY resolution in lmv2_p3_ipc_code_map (this pilot only ever uses
# 'ipc4' -- see build_stage2_technology_cache_for_cohort()'s
# `cache$similarity[cache$similarity$resolution == "ipc4", ...]` filter
# immediately after calling it) via a `matrix` CTE that CROSS JOINs every
# candidate pair against every distinct resolution, multiplying row count by
# the resolution count before anything is ever filtered down -- and its
# `weighted`/`vectors`/`norms` CTEs are GROUPed BY resolution too, so an
# inventor's IPC-feature rows are duplicated once per resolution even before
# the cross join. This is exactly what exhausted DuckDB's memory building
# cohort 2009's cache (a much larger candidate-pair pool than 1995/2002).
# Restricting `m.resolution='ipc4'` at the FIRST join (not after) removes
# the resolution dimension from every CTE and eliminates the cross join
# entirely -- for a typical multi-resolution ipc_code_map, this is a
# multiplicative memory reduction, not just a constant-factor cleanup.
# No final ORDER BY (large-result-set memory/perf fix; the pilot only reads
# these rows to build an in-memory join afterward, so this matches an
# unordered SELECT downstream).
# =============================================================================
lmv2_stage2_technology_cache_ipc4 <- function(con, pair_map) {
  keys <- c("cohort", "treated_codinv", "control_codinv")
  if (!all(keys %in% names(pair_map))) stop("Pair map lacks technology-cache identifiers")
  pairs <- unique(pair_map[keys])
  duckdb::duckdb_register(con, "lmv2_p3_runtime_cache_pairs_ipc4", pairs)
  on.exit(try(duckdb::duckdb_unregister(con, "lmv2_p3_runtime_cache_pairs_ipc4"), silent = TRUE), add = TRUE)
  similarity <- DBI::dbGetQuery(con, "
    WITH roster AS (
      SELECT cohort,treated_codinv AS codinv FROM lmv2_p3_runtime_cache_pairs_ipc4
      UNION SELECT cohort,control_codinv AS codinv FROM lmv2_p3_runtime_cache_pairs_ipc4
    ), weighted AS (
      SELECT r.cohort,CAST(r.codinv AS BIGINT) codinv,m.ipc_feature,
             SUM(i.patent_count)::DOUBLE weight
      FROM roster r
      JOIN inventor_ipc_year i ON CAST(i.codinv AS BIGINT)=r.codinv
       AND i.year BETWEEN r.cohort-5 AND r.cohort-1
      JOIN lmv2_p3_ipc_code_map m USING(ipc_code)
      WHERE m.resolution='ipc4'
      GROUP BY r.cohort,r.codinv,m.ipc_feature
    ), vectors AS (
      SELECT *,weight/SUM(weight) OVER(PARTITION BY cohort,codinv) frequency
      FROM weighted
    ), norms AS (
      SELECT cohort,codinv,SQRT(SUM(frequency*frequency)) norm
      FROM vectors GROUP BY cohort,codinv
    ), dots AS (
      SELECT p.cohort,p.treated_codinv,p.control_codinv,
             SUM(t.frequency*c.frequency) dot
      FROM lmv2_p3_runtime_cache_pairs_ipc4 p
      JOIN vectors t ON t.cohort=p.cohort AND t.codinv=p.treated_codinv
      JOIN vectors c ON c.cohort=p.cohort AND c.codinv=p.control_codinv
                    AND c.ipc_feature=t.ipc_feature
      GROUP BY p.cohort,p.treated_codinv,p.control_codinv
    )
    SELECT p.cohort,p.treated_codinv,p.control_codinv,'ipc4' AS resolution,
           CASE WHEN tn.norm>0 AND cn.norm>0
                THEN LEAST(1.0,GREATEST(0.0,COALESCE(d.dot,0)/(tn.norm*cn.norm)))
                ELSE NULL END cosine
    FROM lmv2_p3_runtime_cache_pairs_ipc4 p
    LEFT JOIN dots d USING(cohort,treated_codinv,control_codinv)
    LEFT JOIN norms tn ON tn.cohort=p.cohort AND tn.codinv=p.treated_codinv
    LEFT JOIN norms cn ON cn.cohort=p.cohort AND cn.codinv=p.control_codinv
  ")
  list(similarity = similarity, shared_ipc4 = lmv2_shared_ipc4_matrix(con, pairs))
}

# =============================================================================
# STEP 2a -- CACHE ONLY the expensive, profile-INDEPENDENT pair-level facts
# (raw cosine similarity, shared-IPC4 indicator) at the loosest Stage-1
# setting. These depend only on the (treated_codinv, control_codinv) pair's
# own technology vectors -- never on firm admissibility or Stage-1 caliper --
# so they are the only thing safe to compute once and reuse.
# =============================================================================
build_stage2_technology_cache_for_cohort <- function(con, g, admissible_firm_edges_loosest, treated_inv_ok,
                                                      donor_cols_loosest, recency_gap) {
  treated_key <- treated_inv_ok[c("cohort", "deal_id", "codinv")]
  names(treated_key)[3] <- "treated_codinv"
  pairs <- lmv2_ebal_build_stage2_candidate_pairs(admissible_firm_edges_loosest, donor_cols_loosest, treated_key)
  if (!nrow(pairs)) return(list(shared_ipc4 = data.frame(), similarity = data.frame()))
  # Manual recency pre-filter here is a COST-REDUCTION step only (fewer pairs
  # -> cheaper cosine computation); lmv2_prepare_stage2_edges() applies its
  # own authoritative recency filter later regardless, per profile.
  bins_t <- treated_inv_ok[c("deal_id", "codinv", "recency_bin")]
  names(bins_t) <- c("deal_id", "treated_codinv", "recency_bin_treated"); bins_t$cohort <- g
  bins_c <- donor_cols_loosest[c("cohort", "control_codinv", "recency_bin")]
  names(bins_c)[3] <- "recency_bin_control"
  pairs <- merge(merge(pairs, bins_t, by = c("cohort", "deal_id", "treated_codinv")),
                 bins_c, by = c("cohort", "control_codinv"))
  pairs <- pairs[!is.na(pairs$recency_bin_treated) & !is.na(pairs$recency_bin_control) &
                  abs(pairs$recency_bin_treated - pairs$recency_bin_control) <= recency_gap, , drop = FALSE]
  if (!nrow(pairs)) return(list(shared_ipc4 = data.frame(), similarity = data.frame()))
  pair_key_cols <- c("cohort", "deal_id", "treated_codinv", "control_codinv")
  cache <- lmv2_stage2_technology_cache_ipc4(con, pairs[pair_key_cols])
  list(shared_ipc4 = cache$shared_ipc4[c("cohort", "treated_codinv", "control_codinv", "shared_ipc4")],
      similarity = cache$similarity[cache$similarity$resolution == "ipc4",
                                    c("cohort", "treated_codinv", "control_codinv", "cosine")])
}

# =============================================================================
# STEP 2b -- for ONE SPECIFIC Stage-1 profile: build this profile's OWN
# candidate pairs (deal-specific, through THIS profile's admissible firms
# only), look up (never recompute) the cached cosine/shared-IPC4 for exactly
# those pairs, and call lmv2_prepare_stage2_edges() FRESH -- its internal
# scaler is scoped to `donors_profile`, which is THIS profile's own eligible-
# control population. This is the fix: the composite Stage-2 distance is
# recomputed, never cached and subsetted, for every profile.
# =============================================================================
build_stage2_edges_for_profile <- function(g, admissible_firm_edges_profile, treated_inv_ok,
                                           donors_profile, donor_cols_profile,
                                           cached_shared_ipc4, cached_similarity) {
  treated_key <- treated_inv_ok[c("cohort", "deal_id", "codinv")]
  names(treated_key)[3] <- "treated_codinv"
  pairs <- lmv2_ebal_build_stage2_candidate_pairs(admissible_firm_edges_profile, donor_cols_profile, treated_key)
  if (!nrow(pairs) || !nrow(cached_shared_ipc4)) {
    return(data.frame(cohort = integer(), deal_id = integer(), treated_codinv = numeric(),
                      control_codinv = numeric(), control_group = numeric(), distance = numeric()))
  }
  pair_key_cols <- c("cohort", "deal_id", "treated_codinv", "control_codinv")
  shared_true <- cached_shared_ipc4[cached_shared_ipc4$shared_ipc4, , drop = FALSE]
  pairs <- merge(pairs, shared_true[c("cohort", "treated_codinv", "control_codinv")],
                by = c("cohort", "treated_codinv", "control_codinv"))
  if (!nrow(pairs)) {
    return(data.frame(cohort = integer(), deal_id = integer(), treated_codinv = numeric(),
                      control_codinv = numeric(), control_group = numeric(), distance = numeric()))
  }
  sim_sel <- cached_similarity[!is.na(cached_similarity$cosine), ]
  pairs <- merge(pairs, sim_sel[pair_key_cols[-2]], by = c("cohort", "treated_codinv", "control_codinv"))
  if (!nrow(pairs)) {
    return(data.frame(cohort = integer(), deal_id = integer(), treated_codinv = numeric(),
                      control_codinv = numeric(), control_group = numeric(), distance = numeric()))
  }
  shared_flags <- unique(pairs[pair_key_cols[-2]]); shared_flags$shared_ipc4 <- TRUE
  prep <- lmv2_prepare_stage2_edges(treated = treated_inv_ok, controls = donors_profile,
                                    pair_map = pairs[pair_key_cols], similarity = sim_sel,
                                    shared_ipc4 = shared_flags, resolution = "ipc4")
  prep$edges
}

# =============================================================================
# STEP 3 -- attach firm_ covariates via checked left joins (never a plain
# inner merge -- see lmv2_left_join_checked()).
#
# CRITICAL (review correction): `firm_covars`'s raw column names
# (log_patent_stock_5y, log_inventor_count_5y, patent_trajectory) are renamed
# to their final firm_*-prefixed names BEFORE the join, not after. `rows`
# already carries the INVENTOR's own patent_trajectory (one of the 5 inventor
# covariates) under the raw name -- if `firm_covars` entered the merge still
# under that same raw name, merge() would silently suffix BOTH to
# "patent_trajectory.x"/".y", after which a post-join `m[[raw]]` copy finds
# nothing (m[[raw]] is NULL), and firm_patent_trajectory would either never
# be created or would be silently overwritten with NA -- and because
# is.finite(NULL) is logical(0), lmv2_ebal_assert_no_missing_covariates()
# would NOT catch it either (all(logical(0)) is vacuously TRUE): the
# covariate would just silently vanish from the balance vector. Renaming
# before the join makes the collision structurally impossible.
# =============================================================================
attach_firm_covariates <- function(rows, group_col, firm_covars) {
  # `firm_covars` must already carry a column literally named `group_col`
  # (this is what the real call site actually passes: authoritative_firm_
  # covars is built via `SELECT ... id_group AS control_group ...`, i.e. the
  # SQL itself already renames -- there is no separate "id_group" column to
  # find). A prior version assumed a hardcoded "id_group" column existed and
  # would have failed with "undefined columns selected" against real data;
  # caught by the end-to-end fixture, not the earlier isolated unit test,
  # which had (wrongly) matched its synthetic input to that assumption
  # instead of to what the real harness actually produces.
  raw_names <- names(LMV2_HYBRID_FIRM_ATTACH_MAP)
  attached_names <- unname(unlist(LMV2_HYBRID_FIRM_ATTACH_MAP))
  fc <- firm_covars[c("cohort", group_col, raw_names)]
  for (raw in raw_names) names(fc)[names(fc) == raw] <- LMV2_HYBRID_FIRM_ATTACH_MAP[[raw]]
  lmv2_left_join_checked(rows, fc, by = c("cohort", group_col),
                         context = paste0("attach_firm_covariates(", group_col, ")"),
                         no_missing_cols = attached_names)
}

# =============================================================================
# STEP 4 -- one cohort-level solve per (caliper, profile, universe, scheme).
# =============================================================================
run_one_cohort_profile <- function(con, g, caliper, profile, universe, scheme,
                                   raw_edges, treated_inv_ok, donors_loosest, donor_cols_loosest,
                                   cached_tech, authoritative_firm_covars, authoritative_treated_target,
                                   frozen10_deal_ids, retention_full_spine,
                                   stage2_edge_builder = NULL) {
  # stage2_edge_builder (memory fix, disk-backed cohort-2009 path): when NULL
  # (every 1995/2002 call site, unchanged), behavior is byte-for-byte
  # identical to before -- the in-memory `cached_tech` lookup below runs
  # exactly as it always has. Cohort 2009 passes a closure that reads its
  # technology facts from the disk-backed Parquet shard cache instead
  # (build_stage2_edges_for_profile_diskbacked()), so this single function
  # stays the shared, unduplicated entry point for both paths -- no risk of
  # the certified 1995/2002 logic and a "2009 copy" silently drifting apart.
  admissible <- lmv2_ebal_stage1_admissible_edges(raw_edges, caliper)
  if (profile == "nearest_50") admissible <- lmv2_ebal_nearest_within_caliper(admissible, 50L)

  n_firms_by_deal <- stats::aggregate(control_group ~ cohort + deal_id, data = admissible,
                                      FUN = function(x) length(unique(x)))
  names(n_firms_by_deal)[3] <- "n_eligible_firms"
  supported_deals <- n_firms_by_deal$deal_id[
    vapply(n_firms_by_deal$n_eligible_firms, lmv2_ebal_deal_supported, logical(1), min_firms = MIN_ELIGIBLE_FIRMS)]
  # Unsupported-deal leak fix: a deal with <5 admissible Stage-1 firms
  # correctly fails `supported_deals` above, but everything downstream used
  # to be built from the FULL `admissible` pool regardless -- so that deal's
  # lone admissible firm still produced Stage-2 control edges. The treated
  # side gets filtered to `supported_deals` later (via `treated_key` at
  # `lmv2_ebal_stage2_supported_treated()`), but `control_rows` was built
  # straight off `admissible_stage2` with no equivalent filter, leaving a
  # control-only deal that fails `allocate_deal_base_weights()`'s treated/
  # control deal-set-agreement check. `admissible_supported` is the single
  # restriction point: everything derived from it downstream (donor
  # population, Stage-2 candidate pairs, Stage-2 edges, and therefore the
  # control roster, since control_rows is itself derived from
  # admissible_stage2) never sees an unsupported deal in the first place.
  # `admissible` itself is left untouched -- it is still the correct input
  # for computing `supported_deals`/`n_deals_stage1_supported`, and the
  # full-spine retention denominator is a separate, unrelated quantity.
  admissible_supported <- admissible[admissible$deal_id %in% supported_deals, , drop = FALSE]

  base_row <- data.frame(cohort = g, caliper = caliper, profile = profile, universe = universe, scheme = scheme,
                         n_treated_full_spine = retention_full_spine$n_treated,
                         n_deals_full_spine = retention_full_spine$n_deals,
                         n_treated_covariate_complete = retention_full_spine$n_treated_covariate_complete,
                         n_deals_stage1_supported = length(supported_deals),
                         n_deals_frozen10_in_cohort = length(intersect(unique(treated_inv_ok$deal_id), frozen10_deal_ids)),
                         n_deals_frozen10_retained = NA_integer_,
                         mode = NA_character_, tier = NA_character_,
                         n_supported_treated = NA_integer_, n_treated_stage1_deal_supported = NA_integer_,
                         headline_inventor_retention = NA_real_, headline_deal_retention = NA_real_,
                         narrow_stage1_denominator_retention = NA_real_,
                         max_smd = NA_real_, smd_log_patent_count_5y = NA_real_, smd_patent_trajectory = NA_real_,
                         smd_career_age = NA_real_, smd_focal_group_tenure = NA_real_,
                         smd_focal_group_exclusivity = NA_real_, smd_firm_log_patent_stock_5y = NA_real_,
                         smd_firm_log_inventor_count_5y = NA_real_, smd_firm_patent_trajectory = NA_real_,
                         inventor_ess_stack_row = NA_real_, inventor_ess_reuse_adjusted = NA_real_,
                         effective_firm_count = NA_real_,
                         max_weight_share_stack_row_WARNING_ONLY = NA_real_,
                         max_weight_share_reuse_adjusted_WARNING_ONLY = NA_real_,
                         deal_smd_median = NA_real_, deal_smd_p90 = NA_real_, deal_smd_max = NA_real_,
                         deal_smd_share_above_010 = NA_real_, deal_smd_share_above_025 = NA_real_,
                         n_solver_warnings = 0L, failure_reason = NA_character_, stringsAsFactors = FALSE)

  finish <- function(n_supported = 0L, deals_supported = integer(0)) {
    funnel <- lmv2_ebal_compute_retention_funnel(
      n_full = retention_full_spine$n_treated, n_covariate_complete = retention_full_spine$n_treated_covariate_complete,
      n_stage1_supported = base_row$n_treated_stage1_deal_supported %||% 0L, n_stage2_supported = n_supported,
      n_deals_full = retention_full_spine$n_deals, n_deals_stage1_supported = length(supported_deals),
      n_deals_stage2_supported = length(deals_supported))
    base_row$headline_inventor_retention <<- funnel$headline_inventor_retention
    base_row$headline_deal_retention <<- funnel$headline_deal_retention
    base_row$narrow_stage1_denominator_retention <<- funnel$narrow_inventor_retention_stage1_denominator
    base_row$n_deals_frozen10_retained <<- length(intersect(deals_supported, frozen10_deal_ids))
  }

  if (!length(supported_deals)) {
    base_row$n_treated_stage1_deal_supported <- 0L
    finish(0L, integer(0))
    base_row$failure_reason <- "no_deals_cleared_stage1_support"
    return(base_row)
  }

  # ---- profile-scoped donor population (cheap R-side subset of the ONE
  # DB-fetched loosest-setting covariate table -- no new query per profile).
  # Restricted to admissible_supported (not admissible) so an unsupported
  # deal's control firm never enters the donor population in the first place.
  donor_cols_profile <- donor_cols_loosest[donor_cols_loosest$control_group %in% unique(admissible_supported$control_group), ]
  donors_profile <- donors_loosest[donors_loosest$focal_group %in% unique(admissible_supported$control_group), ]

  stage2_edges <- if (is.null(stage2_edge_builder)) {
    build_stage2_edges_for_profile(g, admissible_supported, treated_inv_ok, donors_profile, donor_cols_profile,
                                   cached_tech$shared_ipc4, cached_tech$similarity)
  } else {
    stage2_edge_builder(g, admissible_supported, treated_inv_ok, donors_profile, donor_cols_profile)
  }
  admissible_stage2 <- lmv2_ebal_stage2_admissible_edges(stage2_edges, STAGE2_CALIPER)
  eligible_controls <- lmv2_ebal_stage2_eligible_controls(admissible_stage2)
  treated_key <- treated_inv_ok[treated_inv_ok$deal_id %in% supported_deals, c("cohort", "deal_id", "codinv")]
  names(treated_key)[3] <- "treated_codinv"
  supp <- lmv2_ebal_stage2_supported_treated(admissible_stage2, treated_key)
  n_supported <- nrow(supp$supported)

  base_row$n_treated_stage1_deal_supported <- nrow(treated_key)
  base_row$n_supported_treated <- n_supported
  finish(n_supported, unique(supp$supported$deal_id))

  if (!n_supported) { base_row$failure_reason <- "zero_supported_treated_inventors"; return(base_row) }

  # ---- attach covariates to treated rows (their OWN target firm) ----
  # CRITICAL (review correction, bug 1): supp$supported carries
  # `treated_codinv`, treated_inv_ok carries `codinv` -- these are the SAME
  # identifier under different names at this point in the pipeline.
  # intersect(names(...)) silently drops to (cohort, deal_id) ONLY when the
  # names differ, and the checked join's own row-count assertion then
  # correctly (but unhelpfully) stops on ANY deal with more than one treated
  # inventor -- i.e. on almost every real deal. Rename explicitly and join on
  # all three identifying keys.
  treated_inv_ok_keyed <- treated_inv_ok
  names(treated_inv_ok_keyed)[names(treated_inv_ok_keyed) == "codinv"] <- "treated_codinv"
  treated_rows <- lmv2_left_join_checked(supp$supported, treated_inv_ok_keyed,
                                         by = c("cohort", "deal_id", "treated_codinv"),
                                         context = "treated_rows x treated_inv_ok")
  # CRITICAL (review correction, bug 2): authoritative_treated_target's raw
  # firm covariate names (including patent_trajectory) collide with
  # treated_rows' own inventor patent_trajectory -- same failure mode as
  # attach_firm_covariates() above. Rename to firm_* BEFORE joining.
  target_fc <- authoritative_treated_target[c("cohort", "deal_id", "target_group",
                                              names(LMV2_HYBRID_FIRM_ATTACH_MAP))]
  for (raw in names(LMV2_HYBRID_FIRM_ATTACH_MAP)) {
    names(target_fc)[names(target_fc) == raw] <- LMV2_HYBRID_FIRM_ATTACH_MAP[[raw]]
  }
  treated_rows <- lmv2_left_join_checked(
    treated_rows, target_fc, by = c("cohort", "deal_id"),
    context = "treated_rows x authoritative_treated_target",
    no_missing_cols = c("target_group", unname(unlist(LMV2_HYBRID_FIRM_ATTACH_MAP))))

  # ---- control rows: join covariates on the FULL (cohort, control_codinv,
  # control_group) key (additional correction -- not (cohort,control_codinv)
  # alone). Re-attach deal_id from admissible_stage2 (point 3: the same
  # control inventor legitimately appears in multiple deal stacks).
  control_rows <- lmv2_left_join_checked(
    unique(admissible_stage2[c("cohort", "deal_id", "control_codinv", "control_group")]),
    donor_cols_profile, by = c("cohort", "control_codinv", "control_group"),
    context = "control_rows x donor_cols_profile", no_missing_cols = LMV2_HYBRID_INV_VARS)
  control_rows <- attach_firm_covariates(control_rows, "control_group", authoritative_firm_covars)

  bw <- tryCatch(lmv2_ebal_allocate_deal_base_weights(treated_rows, control_rows, scheme),
                 error = function(e) e)
  if (inherits(bw, "condition")) { base_row$failure_reason <- paste0("base_weight_error: ", conditionMessage(bw)); return(base_row) }

  roster <- tryCatch(
    lmv2_ebal_build_cohort_roster(treated_rows, control_rows, bw,
                                  authoritative_firm_covars = authoritative_firm_covars,
                                  authoritative_treated_target = authoritative_treated_target),
    error = function(e) e)
  if (inherits(roster, "condition")) { base_row$failure_reason <- paste0("roster_validation_error: ", conditionMessage(roster)); return(base_row) }

  # HEADLINE retention (full spine) is what gates, not the narrowed count.
  hier <- lmv2_ebal_cohort_feasibility_hierarchy(roster, n_eligible_treated = retention_full_spine$n_treated)
  base_row$mode <- hier$mode
  base_row$tier <- hier$tier %||% NA_character_
  if (identical(hier$mode, "retention_failed")) {
    base_row$failure_reason <- "retention_below_locked_floor_full_spine"
    return(base_row)
  }
  if (identical(hier$mode, "infeasible")) {
    base_row$failure_reason <- sprintf("infeasible: exact=%s, ow0.05=%s, ow0.10=%s",
                                       hier$exact_status, hier[["optweight_0.05_status"]], hier[["optweight_0.10_status"]])
    return(base_row)
  }

  res <- hier$result
  # ---- final-weight/mass invariants asserted in the ACTUAL pilot path
  # (additional correction), for BOTH exact and approximate solutions --
  # res$weight/treated_weight/control_weight/balance/maxdiff/ess/concentration
  # are identically named for either mode.
  prescribed_treated_base <- roster$base_weight[roster$D == 1L]
  lmv2_ebal_assert_final_treated_weights_equal_base(res$treated_weight, prescribed_treated_base)
  lmv2_ebal_assert_masses_agree(res$treated_weight, res$control_weight, scheme, n_retained_deals = bw$n_retained_deals)

  weight <- res$weight
  control_weight <- res$control_weight
  balance_tbl <- res$balance
  base_row$max_smd <- res$maxdiff
  for (v in c(LMV2_HYBRID_INV_VARS, LMV2_HYBRID_FIRM_VARS)) {
    col <- paste0("smd_", v)
    if (col %in% names(base_row) && v %in% balance_tbl$variable) {
      base_row[[col]] <- balance_tbl$abs_difference[balance_tbl$variable == v]
    }
  }
  # Report BOTH stack-row ESS (the raw optimization problem, from hier$ess_info
  # -- already computed once inside the hierarchy, not recomputed here) and
  # REUSE-ADJUSTED ESS (the one that actually gated acceptance, per review
  # correction #3: a control inventor can appear in several deal stacks, and
  # a naive row-level ESS overstates effective independent support).
  base_row$inventor_ess_stack_row <- hier$ess_info$stack_row_ess
  base_row$inventor_ess_reuse_adjusted <- hier$ess_info$reuse_adjusted_ess
  base_row$effective_firm_count <- lmv2_ebal_effective_firm_count(
    control_weight, roster$control_group[roster$D == 0L])
  # WARNING ONLY (never a gate) -- see LMV2_COHORT_PATHOLOGICAL_* comments in
  # the core file: these thresholds catch numerical corruption, not overlap.
  # Concentration is likewise reported both ways; reuse-adjusted is the
  # meaningful one (stack-row understates true concentration on a small
  # number of distinct inventors).
  base_row$max_weight_share_stack_row_WARNING_ONLY <- hier$ess_info$stack_row_concentration$max_share
  base_row$max_weight_share_reuse_adjusted_WARNING_ONLY <- hier$ess_info$reuse_adjusted_concentration$max_share
  base_row$n_solver_warnings <- length(res$warnings %||% character(0))

  dsmd <- lmv2_ebal_deal_level_smd_summary(roster, weight)
  base_row$deal_smd_median <- dsmd$median; base_row$deal_smd_p90 <- dsmd$p90; base_row$deal_smd_max <- dsmd$max
  base_row$deal_smd_share_above_010 <- dsmd$share_above_0.10
  base_row$deal_smd_share_above_025 <- dsmd$share_above_0.25

  # Optional P5-only persistence hook. P4 does not define this callback and
  # therefore remains behaviorally unchanged. A callback failure is terminal
  # and occurs before the profile diagnostic is committed, so a restart can
  # safely repeat the solve without leaving a diagnostics-only "success".
  if (exists(
      "LMV2_P5_WEIGHT_CALLBACK",
      envir = .GlobalEnv,
      inherits = FALSE)) {
    callback <- get(
      "LMV2_P5_WEIGHT_CALLBACK",
      envir = .GlobalEnv,
      inherits = FALSE)
    if (!is.function(callback)) {
      stop("LMV2_P5_WEIGHT_CALLBACK exists but is not a function")
    }
    callback(list(
      con = con,
      roster = roster,
      result = res,
      hierarchy = hier,
      diagnostic = base_row,
      deal_balance = dsmd$per_deal,
      cohort = g,
      caliper = caliper,
      profile = profile,
      universe = universe,
      scheme = scheme,
      target_group_by_deal = unique(
        treated_rows[c("cohort", "deal_id", "target_group")])
    ))
  }

  base_row
}

# =============================================================================
# Manifest (additional correction): source/config hashes and package
# versions, so any downstream review can confirm exactly what code and
# package state produced a given diagnostics table.
# =============================================================================
write_pilot_manifest <- function(audit_dir, observed_p3_hash) {
  manifest <- data.frame(
    timestamp = as.character(Sys.time()),
    p4_ebal_version = LMV2_P4_EBAL_VERSION, p4_ebal_config_hash = LMV2_P4_EBAL_CONFIG_HASH,
    p3_manifest_hash = observed_p3_hash,
    hybrid_utils_hash = lmv2_p3_file_hash(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R")),
    cohort_hybrid_utils_hash = lmv2_p3_file_hash(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R")),
    harness_hash = lmv2_p3_file_hash(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R")),
    disk_backed_cache_hash = lmv2_p3_file_hash(file.path(BASE, "R", "17n_lmv2_p4_disk_backed_cache.R")),
    execution_hash = lmv2_composite_execution_hash(BASE, observed_p3_hash),
    r_version = as.character(getRversion()),
    weightit_version = as.character(utils::packageVersion("WeightIt")),
    optweight_version = as.character(utils::packageVersion("optweight")),
    stringsAsFactors = FALSE)
  utils::write.csv(manifest, file.path(audit_dir, "cohort_hybrid_manifest.csv"), row.names = FALSE)
  manifest
}

# =============================================================================
# Top-level orchestration -- loops cohort x caliper x profile x universe x
# scheme = 72 rows, ALL deals in the 3 pilot cohorts, frozen-10 tagged.
# Incremental per-row CSV append from the start.
# =============================================================================
run_cohort_hybrid_pilot <- function(
    db_path, audit_dir, p3_manifest_path, cohorts_to_run = COHORTS,
    input_adapter = NULL) {
  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  # Restartability (review correction): PER-COHORT output shards, not one
  # shared CSV deleted at startup. Only the shard(s) for cohorts actually
  # being (re)run THIS invocation are reset -- a shard for a cohort NOT in
  # `cohorts_to_run` (e.g. the certified 1995/2002 outputs during a
  # `--cohorts=2009` run) is never touched, let alone deleted.
  cohort_shard_path <- function(g) file.path(audit_dir, sprintf("cohort_hybrid_diagnostics_%d.csv", g))
  for (g in cohorts_to_run) {
    p <- cohort_shard_path(g)
    if (file.exists(p)) file.remove(p)
  }
  append_row_csv <- function(row, path) {
    utils::write.table(row, path, sep = ",", row.names = FALSE,
                       col.names = !file.exists(path), append = file.exists(path))
  }

  observed_p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
  if (!identical(observed_p3_hash, LMV2_P4_EBAL_P3_MANIFEST_SHA256)) {
    stop("P3 interface manifest drifted: expected ", LMV2_P4_EBAL_P3_MANIFEST_SHA256,
        ", observed ", observed_p3_hash)
  }
  write_pilot_manifest(audit_dir, observed_p3_hash)
  # Composite execution hash (review correction): gates disk-backed cache
  # reuse on every file that can change the cache's output, not the P3
  # manifest alone.
  execution_hash <- lmv2_composite_execution_hash(BASE, observed_p3_hash)

  con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  # DuckDB resource tuning (memory fix, review correction -- v1's 8GB budget
  # still let the real R worker process reach ~17.3GB total, since the
  # DuckDB memory_limit only bounds DuckDB's own buffer manager, not R-side
  # object allocation from large query results). Tightened further to 6GB
  # for DuckDB's own budget; the ARCHITECTURAL fix (per-deal-only
  # construction, never a cohort-wide pairs table) is what actually bounds
  # R-side memory now. preserve_insertion_order=false and a persistent spill
  # directory let DuckDB reorder/stream large intermediate results and spill
  # to disk instead of holding them all in memory.
  DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
  DBI::dbExecute(con, "PRAGMA threads=2")
  DBI::dbExecute(con, "PRAGMA preserve_insertion_order=false")
  spill_dir <- file.path(audit_dir, "duckdb_spill")
  dir.create(spill_dir, recursive = TRUE, showWarnings = FALSE)
  DBI::dbExecute(con, sprintf("PRAGMA temp_directory='%s'", spill_dir))

  tech_cache_dir <- file.path(audit_dir, "disk_tech_cache")
  treated_primary_table <- "lmv2_treated_primary"
  treated_units_table <- "lmv2_p3_treated_inventor_units"
  if (!is.null(input_adapter)) {
    required <- c(
      "treated_primary_path", "treated_units_path",
      "excluded_groups_path", "excluded_inventors_path")
    missing <- setdiff(required, names(input_adapter))
    if (length(missing)) {
      stop(
        "input_adapter is missing: ",
        paste(missing, collapse = ", "))
    }
    for (nm in required) {
      input_adapter[[nm]] <- normalizePath(
        input_adapter[[nm]], winslash = "/", mustWork = TRUE)
    }
    if (!is.null(input_adapter$tech_cache_dir)) {
      tech_cache_dir <- normalizePath(
        input_adapter$tech_cache_dir,
        winslash = "/", mustWork = FALSE)
      dir.create(
        tech_cache_dir, recursive = TRUE, showWarnings = FALSE)
    }
    create_view <- function(name, path) {
      DBI::dbExecute(con, sprintf(
        "CREATE OR REPLACE TEMP VIEW %s AS
         SELECT * FROM read_parquet(%s)",
        name, as.character(DBI::dbQuoteString(con, path))))
    }
    DBI::dbExecute(con, sprintf(
      "CREATE OR REPLACE TEMP VIEW lmv2_adapter_treated_primary AS
       SELECT * REPLACE (
         CAST(deal_id AS INTEGER) AS deal_id,
         CAST(cohort AS INTEGER) AS cohort)
       FROM read_parquet(%s)",
      as.character(DBI::dbQuoteString(
        con, input_adapter$treated_primary_path))))
    DBI::dbExecute(con, sprintf(
      "CREATE OR REPLACE TEMP VIEW lmv2_adapter_treated_units AS
       SELECT * REPLACE (
         CAST(deal_id AS INTEGER) AS deal_id,
         CAST(cohort AS INTEGER) AS cohort)
       FROM read_parquet(%s)",
      as.character(DBI::dbQuoteString(
        con, input_adapter$treated_units_path))))
    create_view(
      "lmv2_adapter_excluded_groups",
      input_adapter$excluded_groups_path)
    create_view(
      "lmv2_adapter_excluded_inventors",
      input_adapter$excluded_inventors_path)
    treated_primary_table <- "lmv2_adapter_treated_primary"
    treated_units_table <- "lmv2_adapter_treated_units"
  }

  frozen10 <- utils::read.csv(FROZEN_10_PATH, stringsAsFactors = FALSE)
  build_universe_pools_and_scalers_and_edges(con, cohorts_to_run)
  if (!is.null(input_adapter)) {
    for (pool_name in c("h_pool_u1", "h_pool_u2", "h_pool_u3")) {
      DBI::dbExecute(con, sprintf(
        "DELETE FROM %s p
         WHERE EXISTS (
           SELECT 1 FROM lmv2_adapter_excluded_groups x
           WHERE CAST(x.cohort AS INTEGER)=p.cohort
             AND CAST(x.control_group AS DOUBLE)=p.id_group)",
        pool_name))
    }
    DBI::dbExecute(con, "
      DELETE FROM h_inv_latest i
      WHERE EXISTS (
        SELECT 1 FROM lmv2_adapter_excluded_groups x
        WHERE CAST(x.cohort AS INTEGER)=i.cohort
          AND CAST(x.control_group AS DOUBLE)=i.control_group)
         OR EXISTS (
        SELECT 1 FROM lmv2_adapter_excluded_inventors x
        WHERE CAST(x.codinv AS BIGINT)=i.codinv)")
  }
  pool_tbl_all <- c(u1 = "h_pool_u1", u2 = "h_pool_u2", u3 = "h_pool_u3")
  if (!length(UNIVERSES) || any(!UNIVERSES %in% names(pool_tbl_all))) {
    stop("UNIVERSES contains an unknown or empty universe selection")
  }
  # P4 defines both universes and therefore remains unchanged. Selected P5
  # sets UNIVERSES='u1'; honoring that setting avoids an accidental U3 run.
  pool_tbl <- pool_tbl_all[UNIVERSES]
  s2_vars <- LMV2_P3$stage_2$scalar_variables
  recency_gap <- LMV2_P3$stage_2$maximum_recency_bin_gap

  for (g in cohorts_to_run) {
    out_path <- cohort_shard_path(g)
    use_disk_backed <- g %in% LMV2_DISKBACKED_COHORTS
    frozen10_deal_ids_g <- frozen10$deal_id[frozen10$cohort == g]
    # Optional P5 DealSim-only treated-deal restriction. P4 never defines
    # this object and therefore continues to use every deal in the cohort.
    # The filter changes only the treated estimand branch; U1 eligibility and
    # every matching rule remain unchanged.
    deal_filter <- get0(
      "LMV2_P5_TREATED_DEAL_FILTER",
      envir = .GlobalEnv,
      inherits = FALSE,
      ifnotfound = NULL)
    allowed_deals_g <- NULL
    if (!is.null(deal_filter)) {
      if (!all(c("cohort", "deal_id") %in% names(deal_filter)) ||
          anyDuplicated(deal_filter[c("cohort", "deal_id")])) {
        stop(
          "LMV2_P5_TREATED_DEAL_FILTER must be unique on ",
          "(cohort, deal_id)")
      }
      allowed_deals_g <- unique(
        as.integer(deal_filter$deal_id[deal_filter$cohort == g]))
      if (!length(allowed_deals_g)) {
        message("Skipping cohort ", g, ": no deals in P5 treated-deal filter")
        next
      }
    }
    all_treated_g <- DBI::dbGetQuery(con, sprintf("
      SELECT DISTINCT t.cohort, t.deal_id, CAST(t.target_group AS DOUBLE) AS id_group
      FROM %s t WHERE t.cohort=%d", treated_primary_table, g))
    if (!is.null(allowed_deals_g)) {
      all_treated_g <- all_treated_g[
        all_treated_g$deal_id %in% allowed_deals_g, , drop = FALSE]
    }
    all_treated_g <- lmv2_left_join_checked(
      all_treated_g,
      DBI::dbGetQuery(con, sprintf(
        "SELECT cohort, id_group, log_patent_stock_5y, log_inventor_count_5y, patent_trajectory
         FROM h_firm_covars WHERE cohort=%d", g)),
      by = c("cohort", "id_group"), context = "all_treated_g x h_firm_covars",
      no_missing_cols = c("log_patent_stock_5y", "log_inventor_count_5y", "patent_trajectory"))

    # ---- FULL PRIMARY PILOT SPINE (retention funnel stage 1): raw,
    # unfiltered treated roster for this cohort -- the headline denominator.
    treated_full_raw <- DBI::dbGetQuery(con, sprintf(
      "SELECT DISTINCT cohort, deal_id, codinv FROM %s WHERE cohort=%d",
      treated_primary_table, g))
    if (!is.null(allowed_deals_g)) {
      treated_full_raw <- treated_full_raw[
        treated_full_raw$deal_id %in% allowed_deals_g, , drop = FALSE]
    }

    # Distance and balance variables normally coincide. P5.1's reduced
    # distance deliberately keeps exclusivity as an exact balance moment, so
    # fetch and completeness-check the union. This is a no-op for P4/P5.
    treated_required_vars <- unique(c(s2_vars, LMV2_HYBRID_INV_VARS))
    treated_inv <- DBI::dbGetQuery(con, sprintf("
      SELECT cohort, deal_id, codinv, recency_bin, %s
      FROM %s WHERE cohort=%d",
      paste(treated_required_vars, collapse = ", "),
      treated_units_table, g))
    if (!is.null(allowed_deals_g)) {
      treated_inv <- treated_inv[
        treated_inv$deal_id %in% allowed_deals_g, , drop = FALSE]
    }
    treated_inv_ok <- treated_inv[
      stats::complete.cases(
        treated_inv[c(treated_required_vars, "recency_bin")]), ]

    retention_full_spine <- list(
      n_treated = nrow(treated_full_raw), n_deals = length(unique(treated_full_raw$deal_id)),
      n_treated_covariate_complete = nrow(treated_inv_ok))

    # ---- Disk-backed cohorts ONLY: build the IPC4 vector/norm cache ONCE,
    # from the DIRECT UNION of treated codinv and eligible-donor codinv
    # across BOTH u1 and u3 (never from expanded pairs -- review correction).
    # A lightweight pre-pass fetches each universe's admissible-firm edges
    # and eligible-donor codinv (control_group/control_codinv only, no
    # covariates yet) so the union can be computed BEFORE any per-universe
    # processing starts; those same pre-fetched objects are reused (not
    # re-queried) inside the per-universe loop below.
    vn <- NULL
    universe_prefetch <- list()
    if (use_disk_backed) {
      for (u in names(pool_tbl)) {
        built_u <- build_universe_edges(con, g, pool_tbl[[u]], all_treated_g)
        admissible_loosest_u <- lmv2_ebal_stage1_admissible_edges(built_u$edges, 2.0)
        eligible_controls_loosest_u <- DBI::dbGetQuery(con, sprintf(
          "SELECT cohort, codinv AS control_codinv, control_group FROM h_inv_latest
           WHERE cohort=%d AND control_group IN (%s)", g,
          paste(unique(admissible_loosest_u$control_group), collapse = ",")))
        universe_prefetch[[u]] <- list(raw_edges = built_u$edges, admissible_loosest = admissible_loosest_u,
                                       eligible_controls_loosest = eligible_controls_loosest_u)
      }
      codinv_roster <- unique(c(treated_inv_ok$codinv,
                                unlist(lapply(universe_prefetch, function(x) x$eligible_controls_loosest$control_codinv))))
      vn <- lmv2_build_ipc4_vectors_norms(con, g, codinv_roster, tech_cache_dir, execution_hash)
      rm(codinv_roster); gc(FALSE)
    }

    for (u in names(pool_tbl)) {
      if (use_disk_backed) {
        raw_edges <- universe_prefetch[[u]]$raw_edges
        admissible_loosest <- universe_prefetch[[u]]$admissible_loosest
        eligible_controls_loosest <- universe_prefetch[[u]]$eligible_controls_loosest
      } else {
        built <- build_universe_edges(con, g, pool_tbl[[u]], all_treated_g)
        raw_edges <- built$edges
        # ---- Loosest-setting eligible-control population, fetched ONCE
        # from the DB per (cohort, universe) -- reused (subsetted, never
        # re-queried) for every tighter profile.
        admissible_loosest <- lmv2_ebal_stage1_admissible_edges(raw_edges, 2.0)
        eligible_controls_loosest <- DBI::dbGetQuery(con, sprintf(
          "SELECT cohort, codinv AS control_codinv, control_group FROM h_inv_latest
           WHERE cohort=%d AND control_group IN (%s)", g,
          paste(unique(admissible_loosest$control_group), collapse = ",")))
      }
      donor_base <- DBI::dbGetQuery(con, sprintf("
        SELECT cohort, codinv, career_first_year, last_pre_patent_year,
          LN(1+patent_count_5y) AS log_patent_count_5y,
          LN(1+patents_recent/2.0)-LN(1+patents_early/3.0) AS patent_trajectory,
          (cohort-1-career_first_year) AS career_age,
          CASE WHEN last_pre_patent_year=cohort-1 THEN 0
               WHEN last_pre_patent_year=cohort-2 THEN 1
               WHEN last_pre_patent_year=cohort-3 THEN 2
               WHEN last_pre_patent_year BETWEEN cohort-5 AND cohort-4 THEN 3
               ELSE NULL END AS recency_bin
        FROM lmv2_p3_inventor_cohort_stats WHERE cohort=%d AND codinv IN (%s)",
        g, paste(unique(eligible_controls_loosest$control_codinv), collapse = ",")))
      donor_raw <- merge(eligible_controls_loosest, donor_base,
                         by.x = c("cohort", "control_codinv"), by.y = c("cohort", "codinv"))
      names(donor_raw)[names(donor_raw) == "control_group"] <- "focal_group"
      names(donor_raw)[names(donor_raw) == "control_codinv"] <- "codinv"
      focal <- lmv2_build_control_focal_covariates(con, donor_raw[c("cohort", "codinv", "focal_group")])
      donor_raw <- merge(donor_raw, focal, by = c("cohort", "codinv", "focal_group"), sort = FALSE)
      donor_required_vars <- unique(c(s2_vars, LMV2_HYBRID_INV_VARS))
      donors_loosest <- donor_raw[
        stats::complete.cases(
          donor_raw[c(donor_required_vars, "recency_bin")]), ]
      donor_cols_loosest <- donors_loosest
      names(donor_cols_loosest)[names(donor_cols_loosest) == "codinv"] <- "control_codinv"
      names(donor_cols_loosest)[names(donor_cols_loosest) == "focal_group"] <- "control_group"

      # ---- CACHE ONLY cosine/shared-IPC4 (the fix). Everything downstream
      # of firm admissibility is recomputed per profile. For disk-backed
      # cohorts, the same facts are computed and persisted to Parquet shards
      # instead (never held in R memory as one big table); `cached_tech`
      # stays NULL and unused for those cohorts -- `stage2_edge_builder`
      # (below) is what actually supplies technology facts per profile.
      cached_tech <- NULL
      stage2_edge_builder <- NULL
      if (use_disk_backed) {
        # Per-deal-only construction (review correction): iterates deal_ids
        # one at a time, never building a cohort-wide pairs table.
        lmv2_build_disk_backed_technology_shards_for_universe(
          con, g, u, admissible_loosest, treated_inv_ok, donor_cols_loosest, recency_gap,
          vn$vectors_path, vn$norms_path, tech_cache_dir, execution_hash)
        stage2_edge_builder <- local({
          con_ <- con; cache_dir_ <- tech_cache_dir; universe_ <- u; execution_hash_ <- execution_hash
          caliper_ <- STAGE2_CALIPER
          function(g, admissible_supported, treated_inv_ok, donors_profile, donor_cols_profile) {
            build_stage2_edges_for_profile_diskbacked(
              con_, cache_dir_, g, universe_, admissible_supported, treated_inv_ok, donors_profile, donor_cols_profile,
              execution_hash_, caliper_)
          }
        })
      } else {
        cached_tech <- build_stage2_technology_cache_for_cohort(con, g, admissible_loosest, treated_inv_ok,
                                                                 donor_cols_loosest, recency_gap)
      }

      authoritative_firm_covars <- DBI::dbGetQuery(con, sprintf(
        "SELECT cohort, id_group AS control_group, log_patent_stock_5y, log_inventor_count_5y, patent_trajectory
         FROM h_firm_covars WHERE cohort=%d", g))
      authoritative_treated_target <- all_treated_g
      names(authoritative_treated_target)[names(authoritative_treated_target) == "id_group"] <- "target_group"

      for (caliper in STAGE1_CALIPERS) {
        for (profile in STAGE1_PROFILES) {
          for (scheme in SCHEMES) {
            profile_ready <- FALSE
            if (use_disk_backed) {
              # Restartable-by-profile (review correction): skip
              # recomputation for any (caliper,profile,universe,scheme) row
              # already persisted and provenance/checksum-validated.
              profile_ready <- lmv2_profile_row_provenance_matches(
                tech_cache_dir, g, caliper, profile, u, scheme,
                execution_hash)
              weight_ready <- TRUE
              if (exists(
                  "LMV2_P5_WEIGHT_READY",
                  envir = .GlobalEnv,
                  inherits = FALSE)) {
                weight_ready <- get(
                  "LMV2_P5_WEIGHT_READY",
                  envir = .GlobalEnv,
                  inherits = FALSE)(
                    g, caliper, profile, u, scheme, execution_hash)
              }
              if (profile_ready && weight_ready) next
            }
            row <- run_one_cohort_profile(con, g, caliper, profile, u, scheme, raw_edges, treated_inv_ok,
                                          donors_loosest, donor_cols_loosest, cached_tech,
                                          authoritative_firm_covars, authoritative_treated_target,
                                          frozen10_deal_ids_g, retention_full_spine,
                                          stage2_edge_builder = stage2_edge_builder)
            if (use_disk_backed && !profile_ready) {
              lmv2_write_profile_row_atomic(tech_cache_dir, g, caliper, profile, u, scheme, row, execution_hash)
            } else {
              if (!use_disk_backed) append_row_csv(row, out_path)
            }
          }
        }
      }
      if (use_disk_backed) { rm(donors_loosest, donor_cols_loosest); gc(FALSE) }
    }
    # Disk-backed cohorts: the final per-cohort diagnostics CSV is always
    # ASSEMBLED from validated, checksummed profile-row shards -- never from
    # anything accumulated in R across the whole cohort run -- so it is
    # fully reconstructible after any restart.
    if (use_disk_backed) {
      lmv2_assemble_cohort_diagnostics_from_shards(tech_cache_dir, g, out_path)
    }
  }
  message("Cohort-level hybrid pilot complete for cohorts: ", paste(cohorts_to_run, collapse = ", "))
}

# =============================================================================
# CLI invocation (additional correction -- the file previously defined
# run_cohort_hybrid_pilot() but never called it). Guarded on the actual
# presence of --mode= in this process's own commandArgs(), so sourcing this
# file from a certification/fixture script (which has its own, unrelated
# commandArgs, typically empty) never triggers it.
# =============================================================================
# --mode=certify actually RUNS the full database-free certification suite
# (review correction -- it previously only printed a message). No database
# work occurs either way; certify runs every fixture file covering this
# design and stops with a nonzero exit if any fail.
run_certify_suite <- function() {
  fixture_files <- c("17p_certify_lmv2_p4_hybrid_core.R", "17q_certify_lmv2_p4_cohort_hybrid_core.R",
                     "17r_certify_lmv2_p4_stage2_rescaling.R",
                     "17s_certify_lmv2_p4_pilot_helpers.R",
                     "17t_certify_lmv2_p4_pilot_e2e.R",
                     "17u_certify_lmv2_p4_disk_backed_cache.R",
                     "17v_certify_lmv2_p4_weight_invariance.R")
  results <- character(0)
  for (f in fixture_files) {
    path <- file.path(BASE, "R", f)
    message("--mode=certify: running ", f, " ...")
    status <- tryCatch({ source(path, local = new.env()); "PASS" },
                       error = function(e) paste0("FAIL: ", conditionMessage(e)))
    results[f] <- status
  }
  message("\n--mode=certify summary:")
  for (f in names(results)) message("  ", f, ": ", results[f])
  if (any(startsWith(results, "FAIL"))) stop("--mode=certify: one or more fixture suites FAILED")
  message("\n--mode=certify: ALL FIXTURE SUITES PASS. No database work performed.")
}

.cli_args <- commandArgs(trailingOnly = TRUE)
# Re-entrancy guard: certify_run_cohort_hybrid_pilot_helpers.R and
# certify_run_cohort_hybrid_pilot_e2e.R each independently source() this file
# at their own top (so they can be run standalone). When they are instead
# invoked FROM WITHIN run_certify_suite() below, that source() call re-runs
# this entire file, including this CLI block -- and since commandArgs() is a
# process-level value that does not change with source() nesting, the
# --mode=certify guard would fire again, calling run_certify_suite() again,
# re-sourcing those same two files again, recursing without bound (this was
# an actual bug: 721 recursive re-entries before an R C-stack crash). The
# flag below ensures the CLI block's body executes at most once per process.
if (any(startsWith(.cli_args, "--mode=")) &&
      !exists(".LMV2_CLI_BLOCK_ENTERED", envir = .GlobalEnv, inherits = FALSE)) {
  assign(".LMV2_CLI_BLOCK_ENTERED", TRUE, envir = .GlobalEnv)
  mode <- lmv2_ebal_mode()
  audit_dir <- lmv2_ebal_read_arg("audit-dir")
  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  if (mode == "certify") {
    run_certify_suite()
  } else {
    db_path <- lmv2_ebal_read_arg("db")
    p3_manifest_path <- lmv2_ebal_read_arg("p3-manifest")
    # --cohorts= (restartability, review correction): optional, comma-
    # separated subset of COHORTS to (re)run this invocation -- e.g.
    # --cohorts=2009 to resume only cohort 2009 without touching the
    # already-certified 1995/2002 shards. Defaults to all of COHORTS when
    # omitted (unchanged behavior).
    cohorts_arg <- lmv2_ebal_read_arg("cohorts", required = FALSE)
    cohorts_to_run <- if (is.na(cohorts_arg)) COHORTS else as.integer(strsplit(cohorts_arg, ",")[[1]])
    if (!all(cohorts_to_run %in% COHORTS)) {
      stop("--cohorts= contains a value outside COHORTS (", paste(COHORTS, collapse = ","),
          "): ", paste(cohorts_to_run, collapse = ","))
    }
    run_cohort_hybrid_pilot(db_path, audit_dir, p3_manifest_path, cohorts_to_run = cohorts_to_run)
  }
}
