# ============================================================================
# 18c_materialize_lmv2_outcome_panel.R -- deterministic event-panel materializer
# ============================================================================
# Function library only; nothing executes at source time. The materializer
# accepts a validated roster (later: certified P5a output; earlier: the treated
# fixture) and produces cohort-sharded event panels for t = -5..+5. Output rows
# are always roster rows x 11; the unmatched control universe is never
# expanded. Focal groups travel in the roster and are never re-derived, so
# treated and control rows flow through one code path.

# ---------------------------------------------------------------------------
# Roster validation: row-level and matched-set rules with exact messages.
# mode = "production" (default) additionally requires every treated row to
# carry a complete certified control set; mode = "treated_fixture" is for the
# self-matched treated fixture, which has no control arm by construction.
# ---------------------------------------------------------------------------
validate_lmv2_roster <- function(con, roster_tbl, config = LMV2_P6_CONFIG,
                                 mode = c("production", "treated_fixture")) {
  mode <- match.arg(mode)
  q <- function(sql) DBI::dbGetQuery(con, sql)
  r <- roster_tbl
  failures <- character(0)
  fail_if <- function(n, msg) {
    if (n > 0) failures <<- c(failures, sprintf("%s [%d rows]", msg, n))
  }

  have <- q(sprintf("SELECT * FROM %s LIMIT 0", r))
  missing_cols <- setdiff(names(config$roster_columns), names(have))
  if (length(missing_cols)) {
    stop("Roster is missing required columns: ",
         paste(missing_cols, collapse = ", "))
  }

  # NULL keys first: NULLs escape ordinary SQL predicates, so every key
  # column is checked explicitly before the rule checks below.
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE deal_id IS NULL OR cohort IS NULL OR arm IS NULL
        OR codinv IS NULL OR match_id IS NULL
        OR use_target_company_path IS NULL", r))$n,
    "Roster key columns (deal_id, cohort, arm, codinv, match_id, use_target_company_path) must be non-missing")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm IS NULL OR arm NOT IN ('treated','control')", r))$n,
    "Roster arm values must be 'treated' or 'control'")
  fail_if(q(sprintf(
    "SELECT COUNT(*) - COUNT(DISTINCT (deal_id, arm, codinv, match_id)) n
     FROM %s", r))$n,
    "Roster keys (deal_id, arm, codinv, match_id) must be unique")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM (
       SELECT deal_id FROM %s GROUP BY deal_id
       HAVING COUNT(DISTINCT cohort) > 1)", r))$n,
    "Each deal_id must have exactly one cohort")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s WHERE cohort NOT BETWEEN %d AND %d", r,
    min(config$cohorts), max(config$cohorts)))$n,
    "Roster cohorts must lie in 1994-2010")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s WHERE focal_group_1 IS NULL", r))$n,
    "focal_group_1 must be non-missing for every roster row")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE weight IS NULL OR NOT isfinite(weight)", r))$n,
    "Roster weights must be finite")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s WHERE status_eligible IS NULL", r))$n,
    "status_eligible must be non-missing for every roster row")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm = 'treated' AND match_id <> codinv", r))$n,
    "Treated rows must have match_id = codinv")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm = 'treated' AND weight <> 1", r))$n,
    "Treated rows must have weight = 1")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm = 'treated' AND NOT use_target_company_path", r))$n,
    "Treated rows must have use_target_company_path = TRUE")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm = 'control' AND use_target_company_path", r))$n,
    "Control rows must have use_target_company_path = FALSE")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s WHERE arm = 'control' AND weight < 0", r))$n,
    "Control weights must be nonnegative")

  # Matched-set rules at (deal_id, cohort, match_id). Weights arrive
  # entropy-balanced from certified P5 output; P6 never recomputes,
  # rebalances, repairs, or renormalizes them.
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM (
       SELECT deal_id, cohort, match_id FROM %s WHERE arm = 'control'
       GROUP BY 1, 2, 3
       HAVING COUNT(DISTINCT codinv) <> %d)",
    r, config$controls_per_treated))$n,
    "Each matched set must contain exactly three distinct control inventors")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM (
       SELECT deal_id, cohort, match_id FROM %s WHERE arm = 'control'
       GROUP BY 1, 2, 3
       HAVING COUNT(DISTINCT focal_group_1) < %d)",
    r, config$min_control_firms_per_treated))$n,
    "Each matched set must span at least two distinct control firms")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM (
       SELECT deal_id, cohort, match_id FROM %s WHERE arm = 'control'
       GROUP BY 1, 2, 3
       HAVING ABS(SUM(weight) - 1.0) > %g)",
    r, config$control_weight_sum_tolerance))$n,
    "Control weights must sum to one within numerical tolerance per matched set")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s c
     WHERE c.arm = 'control' AND NOT EXISTS (
       SELECT 1 FROM %s t
       WHERE t.arm = 'treated' AND t.deal_id = c.deal_id
         AND t.cohort = c.cohort AND t.codinv = c.match_id)", r, r))$n,
    "Every control match_id must reference a treated row in the same deal and cohort")

  if (mode == "production") {
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM %s t
       WHERE t.arm = 'treated' AND (
         SELECT COUNT(DISTINCT c.codinv) FROM %s c
         WHERE c.arm = 'control' AND c.deal_id = t.deal_id
           AND c.cohort = t.cohort AND c.match_id = t.codinv) <> %d",
      r, r, config$controls_per_treated))$n,
      "Every treated row must have a complete three-control matched set in production mode")
  }

  if (length(failures)) {
    stop("Roster validation failed:\n  - ",
         paste(failures, collapse = "\n  - "))
  }
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# Treated fixture roster: mechanical self-matched derivation from the frozen
# P2 interface. Used to certify that the materializer reproduces the P2
# stayer classification exactly.
# ---------------------------------------------------------------------------
derive_treated_fixture_roster <- function(con, out_tbl) {
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT
      deal_id,
      cohort,
      'treated' AS arm,
      CAST(codinv AS BIGINT) AS codinv,
      CAST(codinv AS BIGINT) AS match_id,
      1.0 AS weight,
      status_eligible,
      CAST(target_group AS BIGINT) AS focal_group_1,
      CAST(acquirer_group AS BIGINT) AS focal_group_2,
      TRUE AS use_target_company_path
    FROM lmv2_treated_primary", out_tbl))
  invisible(out_tbl)
}

# Strong order-invariant logical hash of one roster cohort: row count plus
# hash-sum plus hash-XOR (a single 64-bit XOR is too weak to identify a
# roster on its own).
lmv2_roster_cohort_hash <- function(con, roster_tbl, cohort) {
  DBI::dbGetQuery(con, sprintf("
    SELECT
      COUNT(*) AS roster_rows,
      CAST(SUM(CAST(hash(deal_id, arm, codinv, match_id, weight,
                         status_eligible, focal_group_1, focal_group_2,
                         use_target_company_path) AS HUGEINT)) AS VARCHAR)
        AS roster_hash_sum,
      CAST(bit_xor(hash(deal_id, arm, codinv, match_id, weight,
                        status_eligible, focal_group_1, focal_group_2,
                        use_target_company_path)) AS VARCHAR) AS roster_hash_xor
    FROM %s WHERE cohort = %d", roster_tbl, cohort))
}

# ---------------------------------------------------------------------------
# Shard provenance stamps. A shard is identified by the full stamp: design
# hashes, amendments hash, interface hashes, ingredient hash, materializer
# source hash, the strong roster hash, and the output's own row count and
# parquet checksum. A shard matching on design but differing on any field is
# refused with an explicit error, never skipped as valid; a stamped shard
# whose parquet no longer matches its recorded checksum is likewise refused.
# ---------------------------------------------------------------------------
lmv2_shard_stamp <- function(provenance, cohort, roster_hash,
                             shard_rows = NA_integer_,
                             shard_parquet_md5 = NA_character_) {
  data.frame(
    cohort = cohort,
    p0_design_hash = provenance$p0_design_hash,
    p6_design_hash = provenance$p6_design_hash,
    amendments_sha256 = provenance$amendments_sha256,
    interface_hashes = paste(provenance$p2_interface_hashes, collapse = ";"),
    ingredient_build_hash = provenance$ingredient_build_hash,
    source_bundle_sha256 = provenance$source_bundle_sha256,
    roster_rows = roster_hash$roster_rows,
    roster_hash_sum = roster_hash$roster_hash_sum,
    roster_hash_xor = roster_hash$roster_hash_xor,
    shard_rows = shard_rows,
    shard_parquet_md5 = shard_parquet_md5,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Production-only membership certification against the frozen P2 interfaces.
# Separate from structural validation so fixture harnesses (which carry no
# P2 tables) remain runnable; the runner calls this on every production
# roster and fails the run on any nonzero count.
# ---------------------------------------------------------------------------
certify_lmv2_roster_membership <- function(con, roster_tbl) {
  q <- function(sql) DBI::dbGetQuery(con, sql)
  checks <- list(
    treated_rows_missing_from_p2 = q(sprintf(
      "SELECT COUNT(*) n FROM %s r
       WHERE r.arm = 'treated' AND NOT EXISTS (
         SELECT 1 FROM lmv2_treated_primary t
         WHERE t.deal_id = r.deal_id
           AND CAST(t.codinv AS BIGINT) = r.codinv)", roster_tbl))$n,
    treated_fields_differ_from_p2 = q(sprintf(
      "SELECT COUNT(*) n FROM %s r
       JOIN lmv2_treated_primary t
         ON t.deal_id = r.deal_id AND CAST(t.codinv AS BIGINT) = r.codinv
       WHERE r.arm = 'treated' AND (
         r.cohort <> t.cohort
         OR r.focal_group_1 IS DISTINCT FROM CAST(t.target_group AS BIGINT)
         OR r.focal_group_2 IS DISTINCT FROM CAST(t.acquirer_group AS BIGINT)
         OR r.status_eligible IS DISTINCT FROM t.status_eligible)",
      roster_tbl))$n,
    control_rows_missing_from_eligibility = q(sprintf(
      "SELECT COUNT(*) n FROM %s r
       WHERE r.arm = 'control' AND NOT EXISTS (
         SELECT 1 FROM lmv2_control_inventor_eligibility c
         WHERE c.cohort = r.cohort
           AND CAST(c.codinv AS BIGINT) = r.codinv
           AND CAST(c.control_group AS BIGINT) = r.focal_group_1)",
      roster_tbl))$n
  )
  out <- data.frame(
    check = paste0("roster_membership_", names(checks)),
    observed = unlist(checks),
    pass = unlist(checks) == 0,
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  out
}

check_lmv2_shard_stamp <- function(stamp_path, shard_path, expected_stamp,
                                   allow_restart) {
  if (!file.exists(stamp_path)) return(FALSE)
  existing <- utils::read.csv(stamp_path, colClasses = "character")
  # Provenance and roster identity must match exactly (output fields are
  # recorded by the prior run and validated against the file below).
  identity_cols <- setdiff(names(expected_stamp),
                           c("shard_rows", "shard_parquet_md5"))
  if (!lmv2_df_equal(existing[identity_cols], expected_stamp[identity_cols])) {
    stop("Shard stamp mismatch for cohort ", expected_stamp$cohort,
         ": an existing shard was built under different provenance ",
         "(design, amendments, interfaces, ingredients, materializer, or ",
         "roster). Refusing to overwrite or skip; remove the stale shard ",
         "explicitly.")
  }
  if (!file.exists(shard_path)) return(FALSE)
  actual_md5 <- unname(tools::md5sum(shard_path))
  if (!identical(actual_md5, existing$shard_parquet_md5)) {
    stop("Shard parquet for cohort ", expected_stamp$cohort,
         " does not match its stamped checksum; the file is stale or ",
         "corrupted. Refusing to skip; remove the shard and its stamp ",
         "explicitly.")
  }
  isTRUE(allow_restart)
}

# ---------------------------------------------------------------------------
# Materializer. `schema` is the published ingredient schema; `provenance` is
# the named list assembled by the runner after its provenance gate.
# ---------------------------------------------------------------------------
materialize_lmv2_event_panel <- function(con, roster_tbl, schema, out_dir,
                                         provenance,
                                         config = LMV2_P6_CONFIG,
                                         allow_restart = FALSE,
                                         roster_mode = "production") {
  validate_lmv2_roster(con, roster_tbl, config, mode = roster_mode)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  s <- function(tbl) sprintf("%s.%s", schema, tbl)
  cohorts <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT cohort FROM %s ORDER BY cohort", roster_tbl))$cohort

  manifest <- vector("list", length(cohorts))
  for (i in seq_along(cohorts)) {
    g <- as.integer(cohorts[i])
    shard_path <- file.path(out_dir, sprintf("lmv2_event_panel_c%d.parquet", g))
    stamp_path <- file.path(out_dir, sprintf("lmv2_event_panel_c%d_stamp.csv", g))
    roster_hash <- lmv2_roster_cohort_hash(con, roster_tbl, g)
    stamp <- lmv2_shard_stamp(provenance, g, roster_hash)

    if (check_lmv2_shard_stamp(stamp_path, shard_path, stamp, allow_restart)) {
      manifest[[i]] <- data.frame(cohort = g, shard = shard_path,
                                  status = "restart_skip",
                                  roster_hash_xor = roster_hash$roster_hash_xor)
      next
    }

    sql <- sprintf("
COPY (
WITH r AS (
  SELECT * FROM %1$s WHERE cohort = %2$d
),
-- per roster row: first post-event patent year and stayer status,
-- replicating the P2 semantics verbatim (resolved affiliations only)
fp AS (
  SELECT r.deal_id, r.arm, r.codinv, r.match_id,
         MIN(a.year) AS first_post_patent_year
  FROM r
  JOIN %3$s a ON a.codinv = r.codinv
             AND a.year BETWEEN %2$d AND %2$d + 5
  GROUP BY 1, 2, 3, 4
),
stay AS (
  SELECT
    r.deal_id, r.arm, r.codinv, r.match_id,
    fp.first_post_patent_year,
    COALESCE(EXISTS (
      SELECT 1 FROM %3$s a
      WHERE a.codinv = r.codinv
        AND a.year = fp.first_post_patent_year
        AND a.resolved_group IN (r.focal_group_1, r.focal_group_2)
    ), FALSE) AS stayer_group_first_post_t0_t5,
    COALESCE(r.use_target_company_path AND EXISTS (
      SELECT 1 FROM %4$s tc
      WHERE tc.codinv = r.codinv
        AND tc.deal_id = r.deal_id
        AND tc.year = fp.first_post_patent_year
    ), FALSE) AS stayer_target_company_first_post_t0_t5
  FROM r
  LEFT JOIN fp USING (deal_id, arm, codinv, match_id)
),
-- per roster row: last focal-entity patent year (patent-level links),
-- the locked absorbing-Left evidence
last_focal AS (
  SELECT r.deal_id, r.arm, r.codinv, r.match_id,
         MAX(y.year) AS last_focal_patent_year
  FROM r
  LEFT JOIN (
    SELECT gp.codinv, gp.year, gp.id_group, NULL::BIGINT AS deal_id
    FROM %5$s gp
    UNION ALL
    SELECT tc.codinv, tc.year, NULL::BIGINT AS id_group, tc.deal_id
    FROM %4$s tc
  ) y ON y.codinv = r.codinv
     AND (y.id_group IN (r.focal_group_1, r.focal_group_2)
          OR (r.use_target_company_path AND y.deal_id = r.deal_id))
  GROUP BY 1, 2, 3, 4
),
-- TechDrift ingredients: baseline over g-5..g-1 and per-year vectors
baseline AS (
  SELECT v.codinv, v.ipc4, SUM(v.weight) AS bw
  FROM %6$s v
  JOIN (SELECT DISTINCT codinv FROM r) rc USING (codinv)
  WHERE v.year BETWEEN %2$d - 5 AND %2$d - 1
  GROUP BY 1, 2
),
bnorm AS (
  SELECT codinv, SQRT(SUM(bw * bw)) AS bnorm FROM baseline GROUP BY 1
),
cvec AS (
  SELECT v.codinv, v.year, v.ipc4, v.weight AS cw
  FROM %6$s v
  JOIN (SELECT DISTINCT codinv FROM r) rc USING (codinv)
  WHERE v.year BETWEEN %2$d - 5 AND %2$d + 5
),
cnorm AS (
  SELECT codinv, year, SQRT(SUM(cw * cw)) AS cnorm FROM cvec GROUP BY 1, 2
),
dot AS (
  SELECT c.codinv, c.year, SUM(b.bw * c.cw) AS dot
  FROM cvec c JOIN baseline b ON b.codinv = c.codinv AND b.ipc4 = c.ipc4
  GROUP BY 1, 2
),
events AS (
  SELECT r.*, t.event_time, %2$d + t.event_time AS calendar_year
  FROM r CROSS JOIN (
    SELECT UNNEST(range(-5, 6)) AS event_time
  ) t
)
SELECT
  e.deal_id, e.cohort, e.arm, e.codinv, e.match_id, e.weight,
  e.status_eligible, e.focal_group_1, e.focal_group_2,
  e.use_target_company_path,
  e.event_time, e.calendar_year,
  (e.calendar_year >= %7$d) AS late_tail_flag,
  -- structural zeros for absent (genuine zero-patent) years
  COALESCE(oy.patent_count, 0) AS patent_count,
  COALESCE(oy.fractional_patent_count, 0) AS fractional_patent_count,
  (COALESCE(oy.patent_count, 0) > 0)::INTEGER AS active_patenting,
  COALESCE(oy.n_linked_oecd, 0) AS n_linked_oecd,
  COALESCE(oy.n_fwd_nonmiss, 0) AS n_fwd_nonmiss,
  COALESCE(oy.n_pqii_nonmiss, 0) AS n_pqii_nonmiss,
  %8$s,
  %9$s,
  -- absorbing Left from patent-level focal evidence. Units with no focal
  -- evidence are NA (missing, audited via left_defined), never coded 1.
  lf.last_focal_patent_year,
  (lf.last_focal_patent_year IS NOT NULL) AS left_defined,
  CASE WHEN lf.last_focal_patent_year IS NULL THEN NULL
       ELSE (e.calendar_year > lf.last_focal_patent_year)::INTEGER
  END AS left_focal,
  CASE WHEN lf.last_focal_patent_year IS NULL THEN NULL
       ELSE (e.calendar_year = lf.last_focal_patent_year + 1)::INTEGER
  END AS left_onset,
  -- stayer status (constant within the unit-stack)
  st.first_post_patent_year,
  st.stayer_group_first_post_t0_t5,
  st.stayer_target_company_first_post_t0_t5,
  (st.stayer_group_first_post_t0_t5
   OR st.stayer_target_company_first_post_t0_t5)
    AS stayer_focal_entity_first_post_t0_t5,
  (e.status_eligible AND (st.stayer_group_first_post_t0_t5
   OR st.stayer_target_company_first_post_t0_t5))
    AS status_eligible_stayer_first_post_t0_t5,
  -- Matched-control firm-exit diagnostic (NULL for treated rows)
  %12$s AS control_firm_exits_before_g_plus_5,
  -- TechDrift: both directions stored to prevent downstream sign mistakes
  CASE
    WHEN bn.bnorm IS NULL OR bn.bnorm = 0 THEN NULL
    WHEN cn.cnorm IS NULL OR cn.cnorm = 0 THEN NULL
    ELSE COALESCE(d.dot, 0) / (bn.bnorm * cn.cnorm)
  END AS tech_similarity,
  CASE
    WHEN bn.bnorm IS NULL OR bn.bnorm = 0 THEN NULL
    WHEN cn.cnorm IS NULL OR cn.cnorm = 0 THEN NULL
    ELSE 1 - COALESCE(d.dot, 0) / (bn.bnorm * cn.cnorm)
  END AS tech_drift
FROM events e
LEFT JOIN %10$s oy
  ON oy.codinv = e.codinv AND oy.year = e.calendar_year
LEFT JOIN stay st
  ON st.deal_id = e.deal_id AND st.arm = e.arm
 AND st.codinv = e.codinv AND st.match_id = e.match_id
LEFT JOIN last_focal lf
  ON lf.deal_id = e.deal_id AND lf.arm = e.arm
 AND lf.codinv = e.codinv AND lf.match_id = e.match_id
LEFT JOIN bnorm bn ON bn.codinv = e.codinv
LEFT JOIN cnorm cn ON cn.codinv = e.codinv AND cn.year = e.calendar_year
LEFT JOIN dot d ON d.codinv = e.codinv AND d.year = e.calendar_year
%13$s
ORDER BY ALL
) TO '%11$s' (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE TRUE)",
      roster_tbl, g,
      s("lmv2_outcome_inventor_affiliation_year"),
      s("lmv2_inventor_target_company_patent_year"),
      s("lmv2_inventor_group_patent_year"),
      s("lmv2_inventor_ipc4_year"),
      config$late_tail_calendar_year,
      lmv2_outcome_variant_sql("fwd_cits5",
                               "COALESCE(oy.patent_count, 0)",
                               "COALESCE(oy.n_fwd_nonmiss, 0)",
                               "oy.sum_fwd_cits5_obs"),
      lmv2_outcome_variant_sql("pqii",
                               "COALESCE(oy.patent_count, 0)",
                               "COALESCE(oy.n_pqii_nonmiss, 0)",
                               "oy.sum_pqii_obs"),
      s("lmv2_outcome_inventor_year"),
      gsub("\\\\", "/", shard_path),
      if (DBI::dbExistsTable(con, "lmv2_control_firm_eligibility")) {
        "cfe.control_firm_exits_before_g_plus_5"
      } else "NULL::BOOLEAN",
      if (DBI::dbExistsTable(con, "lmv2_control_firm_eligibility")) {
        "LEFT JOIN lmv2_control_firm_eligibility cfe
           ON e.arm = 'control' AND cfe.cohort = e.cohort
          AND CAST(cfe.control_group AS BIGINT) = e.focal_group_1"
      } else "")

    DBI::dbExecute(con, sql)

    n_roster <- roster_hash$roster_rows
    n_panel <- DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM read_parquet('%s')",
      gsub("\\\\", "/", shard_path)))$n
    if (n_panel != n_roster * 11L) {
      stop("Shard cohort ", g, ": panel rows (", n_panel,
           ") do not equal roster rows x 11 (", n_roster * 11L, ").")
    }
    stamp <- lmv2_shard_stamp(provenance, g, roster_hash,
                              shard_rows = n_panel,
                              shard_parquet_md5 = unname(tools::md5sum(shard_path)))
    utils::write.csv(stamp, stamp_path, row.names = FALSE, na = "")
    manifest[[i]] <- data.frame(cohort = g, shard = shard_path,
                                status = "built",
                                roster_hash_xor = roster_hash$roster_hash_xor)
  }
  do.call(rbind, manifest)
}
