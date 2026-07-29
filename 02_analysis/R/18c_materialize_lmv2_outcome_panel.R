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
# Roster validation: row-level and weighted-pool rules with exact messages.
# mode = "production" additionally requires both arms, equal treated/control
# weight mass by cohort, and at least two control firms per treated deal.
# mode = "treated_fixture" permits the self-matched treated-only fixture.
# ---------------------------------------------------------------------------
validate_lmv2_roster <- function(con, roster_tbl, config = LMV2_P6_CONFIG,
                                 mode = c(
                                   "production", "treated_fixture",
                                   "control_null")) {
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
        OR codinv IS NULL OR roster_row_id IS NULL
        OR use_target_company_path IS NULL", r))$n,
    "Roster key columns (deal_id, cohort, arm, codinv, roster_row_id, use_target_company_path) must be non-missing")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm IS NULL OR arm NOT IN ('treated','control')", r))$n,
    "Roster arm values must be 'treated' or 'control'")
  fail_if(q(sprintf(
    "SELECT COUNT(*) - COUNT(DISTINCT roster_row_id) n
     FROM %s", r))$n,
    "roster_row_id must be unique")
  fail_if(q(sprintf(
    "SELECT COUNT(*) - COUNT(DISTINCT
       (cohort, deal_id, arm, codinv, focal_group_1)) n
     FROM %s", r))$n,
    "Conceptual roster rows must be unique independently of roster_row_id")
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
     WHERE arm = 'treated' AND weight <> 1", r))$n,
    "Treated rows must have weight = 1")
  if (mode != "control_null") {
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM %s
       WHERE arm = 'treated' AND NOT use_target_company_path", r))$n,
      "Treated rows must have use_target_company_path = TRUE")
  }
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm = 'control' AND use_target_company_path", r))$n,
    "Control rows must have use_target_company_path = FALSE")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s WHERE arm = 'control' AND weight < 0", r))$n,
    "Control weights must be nonnegative")
  # Both fields below enter outcome construction directly (stayer status via
  # status_eligible; stayer and absorbing Left via focal groups), so the
  # contract is enforced, not assumed.
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm = 'control' AND NOT status_eligible", r))$n,
    "Control rows must have status_eligible = TRUE")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm = 'control' AND focal_group_2 IS NOT NULL", r))$n,
    "Control rows must have focal_group_2 NULL")
  fail_if(q(sprintf(
    "SELECT COUNT(*) n FROM %s
     WHERE arm = 'treated' AND (
       qualification_route IS NULL
       OR target_to_acquirer_transition_strict IS NULL
       OR latest_pre_candidate_group_count IS NULL
       OR multi_exposure_inventor IS NULL
       OR big_deal IS NULL)", r))$n,
    "Treated assignment-route fields must be non-missing")

  if (mode == "production") {
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT UNNEST(range(%d, %d)) AS cohort
         EXCEPT SELECT DISTINCT cohort FROM %s)",
      min(config$cohorts), max(config$cohorts) + 1L, r))$n,
      "The primary production roster must contain all 17 locked cohorts")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT DISTINCT cohort FROM %s
         EXCEPT SELECT UNNEST(range(%d, %d)) AS cohort)",
      r, min(config$cohorts), max(config$cohorts) + 1L))$n,
      "The primary production roster contains a cohort outside the lock")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort FROM %s GROUP BY cohort
         HAVING COUNT(*) FILTER (WHERE arm='treated') = 0
             OR COUNT(*) FILTER (WHERE arm='control') = 0)", r))$n,
      "Every production cohort must contain treated and control rows")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort FROM %s GROUP BY cohort
         HAVING ABS(SUM(weight) FILTER (WHERE arm='treated') -
                    SUM(weight) FILTER (WHERE arm='control')) > %g)",
      r, config$cohort_weight_mass_tolerance))$n,
      "Treated and control weights must have equal mass within each cohort")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort, deal_id FROM %s
         WHERE arm='control' AND weight > 0
         GROUP BY cohort, deal_id
         HAVING COUNT(DISTINCT focal_group_1) < %d)",
      r, config$min_control_firms_per_deal))$n,
      "Each treated deal must draw positive control weight from at least two firms")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT DISTINCT cohort, deal_id FROM %s WHERE arm='treated'
         EXCEPT
         SELECT DISTINCT cohort, deal_id FROM %s WHERE arm='control')",
      r, r))$n,
      "Every treated deal must have a weighted control pool")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT DISTINCT cohort, deal_id FROM %s WHERE arm='control'
         EXCEPT
         SELECT DISTINCT cohort, deal_id FROM %s WHERE arm='treated')",
      r, r))$n,
      "Every weighted control pool must reference a treated deal")
  }
  if (mode == "control_null") {
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM %s
       WHERE use_target_company_path OR focal_group_2 IS NOT NULL", r))$n,
      "Control-null rows must use one control-firm focal path")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort FROM %s GROUP BY cohort
         HAVING COUNT(*) FILTER (WHERE arm='treated')=0
             OR COUNT(*) FILTER (WHERE arm='control')=0)", r))$n,
      "Every control-null cohort must contain both arms")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort FROM %s GROUP BY cohort
         HAVING ABS(
           SUM(weight) FILTER (WHERE arm='treated')-
           SUM(weight) FILTER (WHERE arm='control'))>%g)", r,
      config$cohort_weight_mass_tolerance))$n,
      "Control-null treated/control weight mass must agree by cohort")
    fail_if(q(sprintf(
      "SELECT COUNT(*) n FROM (
         SELECT cohort,deal_id FROM %s
         WHERE arm='control'
         GROUP BY cohort,deal_id
         HAVING COUNT(DISTINCT focal_group_1)<%d)", r,
      config$min_control_firms_per_deal))$n,
      "Every control-null deal must use at least two control firms")
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
      'T:' || CAST(cohort AS VARCHAR) || ':' ||
        CAST(deal_id AS VARCHAR) || ':' || CAST(codinv AS VARCHAR)
        AS roster_row_id,
      1.0 AS weight,
      status_eligible,
      CAST(target_group AS BIGINT) AS focal_group_1,
      CAST(acquirer_group AS BIGINT) AS focal_group_2,
      TRUE AS use_target_company_path,
      qualification_route,
      target_to_acquirer_transition_strict,
      latest_pre_candidate_group_count,
      multi_exposure_inventor,
      big_deal
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
      CAST(SUM(CAST(hash(deal_id, arm, codinv, roster_row_id, weight,
                         status_eligible, focal_group_1, focal_group_2,
                         use_target_company_path, qualification_route,
                         target_to_acquirer_transition_strict,
                         latest_pre_candidate_group_count,
                         multi_exposure_inventor, big_deal) AS HUGEINT))
        AS VARCHAR)
        AS roster_hash_sum,
      CAST(bit_xor(hash(deal_id, arm, codinv, roster_row_id, weight,
                        status_eligible, focal_group_1, focal_group_2,
                        use_target_company_path, qualification_route,
                        target_to_acquirer_transition_strict,
                        latest_pre_candidate_group_count,
                        multi_exposure_inventor, big_deal))
        AS VARCHAR) AS roster_hash_xor
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
    preanalysis_freeze_sha256 = provenance$preanalysis_freeze_sha256,
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
         OR r.status_eligible IS DISTINCT FROM t.status_eligible
         OR r.qualification_route IS DISTINCT FROM t.qualification_route
         OR r.target_to_acquirer_transition_strict IS DISTINCT FROM
              t.target_to_acquirer_transition_strict
         OR r.latest_pre_candidate_group_count IS DISTINCT FROM
              t.latest_pre_candidate_group_count
         OR r.multi_exposure_inventor IS DISTINCT FROM
              t.multi_exposure_inventor
         OR r.big_deal IS DISTINCT FROM t.big_deal)",
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
                                         roster_mode = "production",
                                         cohorts_to_run = NULL,
                                         profile_dir = NULL) {
  validate_lmv2_roster(con, roster_tbl, config, mode = roster_mode)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (!is.null(profile_dir)) {
    dir.create(profile_dir, recursive = TRUE, showWarnings = FALSE)
  }
  s <- function(tbl) sprintf("%s.%s", schema, tbl)

  has_control_firm_eligibility <- DBI::dbExistsTable(
    con, "lmv2_control_firm_eligibility")
  if (has_control_firm_eligibility) {
    duplicate_control_firms <- DBI::dbGetQuery(con, "
      SELECT COUNT(*) n FROM (
        SELECT cohort, CAST(control_group AS BIGINT) AS control_group
        FROM lmv2_control_firm_eligibility
        GROUP BY 1, 2 HAVING COUNT(*) > 1)")$n
    if (duplicate_control_firms > 0) {
      stop(
        "lmv2_control_firm_eligibility is not unique on ",
        "(cohort, control_group)")
    }
    DBI::dbExecute(con, "
      CREATE OR REPLACE TEMP TABLE
        lmv2_control_firm_eligibility_cast AS
      SELECT
        CAST(cohort AS INTEGER) AS cohort,
        CAST(control_group AS BIGINT) AS control_group,
        control_firm_exits_before_g_plus_5
      FROM lmv2_control_firm_eligibility")
  }

  cohorts <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT cohort FROM %s ORDER BY cohort", roster_tbl))$cohort
  if (!is.null(cohorts_to_run)) {
    cohorts_to_run <- sort(unique(as.integer(cohorts_to_run)))
    unknown <- setdiff(cohorts_to_run, cohorts)
    if (length(unknown)) {
      stop(
        "Requested cohort is absent from the validated roster: ",
        paste(unknown, collapse = ", "))
    }
    cohorts <- intersect(cohorts, cohorts_to_run)
  }

  manifest <- vector("list", length(cohorts))
  for (i in seq_along(cohorts)) {
    g <- as.integer(cohorts[i])
    shard_started <- proc.time()[["elapsed"]]
    shard_path <- file.path(out_dir, sprintf("lmv2_event_panel_c%d.parquet", g))
    stamp_path <- file.path(out_dir, sprintf("lmv2_event_panel_c%d_stamp.csv", g))
    roster_hash <- lmv2_roster_cohort_hash(con, roster_tbl, g)
    stamp <- lmv2_shard_stamp(provenance, g, roster_hash)

    if (check_lmv2_shard_stamp(stamp_path, shard_path, stamp, allow_restart)) {
      manifest[[i]] <- data.frame(cohort = g, shard = shard_path,
                                  status = "restart_skip",
                                  runtime_seconds = 0,
                                  profile_path = NA_character_,
                                  roster_hash_xor = roster_hash$roster_hash_xor)
      next
    }

    sql <- sprintf("
COPY (
WITH r AS MATERIALIZED (
  SELECT * FROM %1$s WHERE cohort = %2$d
),
roster_codinv AS MATERIALIZED (
  SELECT DISTINCT codinv FROM r
),
-- per roster row: first post-event patent year and stayer status,
-- replicating the P2 semantics verbatim (resolved affiliations only)
fp AS (
  SELECT r.deal_id, r.arm, r.codinv, r.roster_row_id,
         MIN(a.year) AS first_post_patent_year
  FROM r
  JOIN %3$s a ON a.codinv = r.codinv
             AND a.year BETWEEN %2$d AND %2$d + 5
  GROUP BY 1, 2, 3, 4
),
stay AS (
  SELECT
    r.deal_id, r.arm, r.codinv, r.roster_row_id,
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
  LEFT JOIN fp USING (deal_id, arm, codinv, roster_row_id)
),
-- Per-roster-row last focal evidence. Each equality branch remains
-- hash-joinable; combining them with OR would force a blockwise nested loop.
last_group_1 AS (
  SELECT r.roster_row_id, MAX(g.year) AS last_group_1_year
  FROM r
  LEFT JOIN %5$s g
    ON g.codinv = r.codinv AND g.id_group = r.focal_group_1
  GROUP BY 1
),
last_group_2 AS (
  SELECT r.roster_row_id, MAX(g.year) AS last_group_2_year
  FROM r
  LEFT JOIN %5$s g
    ON g.codinv = r.codinv AND g.id_group = r.focal_group_2
  GROUP BY 1
),
target_path_rows AS MATERIALIZED (
  SELECT * FROM r WHERE use_target_company_path
),
last_target_company AS (
  SELECT r.roster_row_id, MAX(tc.year) AS last_target_company_year
  FROM target_path_rows r
  LEFT JOIN %4$s tc
    ON tc.codinv = r.codinv AND tc.deal_id = r.deal_id
  GROUP BY 1
),
last_focal AS (
  SELECT r.deal_id, r.arm, r.codinv, r.roster_row_id,
    CASE
      WHEN g1.last_group_1_year IS NULL
       AND g2.last_group_2_year IS NULL
       AND tc.last_target_company_year IS NULL
      THEN NULL
      ELSE GREATEST(
        COALESCE(g1.last_group_1_year, -2147483648),
        COALESCE(g2.last_group_2_year, -2147483648),
        COALESCE(tc.last_target_company_year, -2147483648))
    END AS last_focal_patent_year
  FROM r
  LEFT JOIN last_group_1 g1 USING (roster_row_id)
  LEFT JOIN last_group_2 g2 USING (roster_row_id)
  LEFT JOIN last_target_company tc USING (roster_row_id)
),
-- TechDrift ingredients: baseline over g-5..g-1 and per-year vectors
baseline AS MATERIALIZED (
  SELECT v.codinv, v.ipc4, SUM(v.weight) AS bw
  FROM %6$s v
  JOIN roster_codinv rc USING (codinv)
  WHERE v.year BETWEEN %2$d - 5 AND %2$d - 1
  GROUP BY 1, 2
),
bnorm AS (
  SELECT codinv, SQRT(SUM(bw * bw)) AS bnorm FROM baseline GROUP BY 1
),
cvec AS MATERIALIZED (
  SELECT v.codinv, v.year, v.ipc4, v.weight AS cw
  FROM %6$s v
  JOIN roster_codinv rc USING (codinv)
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
-- Attach every roster/codinv-grain state once before the eleven-row
-- event-time expansion.
roster_state AS (
  SELECT
    r.*,
    lf.last_focal_patent_year,
    st.first_post_patent_year,
    st.stayer_group_first_post_t0_t5,
    st.stayer_target_company_first_post_t0_t5,
    bn.bnorm,
    %12$s AS control_firm_exits_before_g_plus_5
  FROM r
  LEFT JOIN stay st
    ON st.roster_row_id = r.roster_row_id
  LEFT JOIN last_focal lf
    ON lf.roster_row_id = r.roster_row_id
  LEFT JOIN bnorm bn ON bn.codinv = r.codinv
  %13$s
),
events AS (
  SELECT r.*, t.event_time, %2$d + t.event_time AS calendar_year
  FROM roster_state r CROSS JOIN (
    SELECT UNNEST(range(-5, 6)) AS event_time
  ) t
)
SELECT
  e.deal_id, e.cohort, e.arm, e.codinv, e.roster_row_id, e.weight,
  e.status_eligible, e.focal_group_1, e.focal_group_2,
  e.use_target_company_path, e.qualification_route,
  e.target_to_acquirer_transition_strict,
  e.latest_pre_candidate_group_count,
  e.multi_exposure_inventor, e.big_deal,
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
  e.last_focal_patent_year,
  (e.last_focal_patent_year IS NOT NULL) AS left_defined,
  CASE WHEN e.last_focal_patent_year IS NULL THEN NULL
       ELSE (e.calendar_year > e.last_focal_patent_year)::INTEGER
  END AS left_focal,
  CASE WHEN e.last_focal_patent_year IS NULL THEN NULL
       ELSE (e.calendar_year = e.last_focal_patent_year + 1)::INTEGER
  END AS left_onset,
  -- stayer status (constant within the unit-stack)
  e.first_post_patent_year,
  e.stayer_group_first_post_t0_t5,
  e.stayer_target_company_first_post_t0_t5,
  (e.stayer_group_first_post_t0_t5
   OR e.stayer_target_company_first_post_t0_t5)
    AS stayer_focal_entity_first_post_t0_t5,
  (e.status_eligible AND (e.stayer_group_first_post_t0_t5
   OR e.stayer_target_company_first_post_t0_t5))
    AS status_eligible_stayer_first_post_t0_t5,
  -- Matched-control firm-exit diagnostic (NULL for treated rows)
  e.control_firm_exits_before_g_plus_5,
  -- TechDrift: both directions stored to prevent downstream sign mistakes
  CASE
    WHEN e.bnorm IS NULL OR e.bnorm = 0 THEN NULL
    WHEN cn.cnorm IS NULL OR cn.cnorm = 0 THEN NULL
    ELSE COALESCE(d.dot, 0) / (e.bnorm * cn.cnorm)
  END AS tech_similarity,
  CASE
    WHEN e.bnorm IS NULL OR e.bnorm = 0 THEN NULL
    WHEN cn.cnorm IS NULL OR cn.cnorm = 0 THEN NULL
    ELSE 1 - COALESCE(d.dot, 0) / (e.bnorm * cn.cnorm)
  END AS tech_drift
FROM events e
LEFT JOIN %10$s oy
  ON oy.codinv = e.codinv AND oy.year = e.calendar_year
LEFT JOIN cnorm cn ON cn.codinv = e.codinv AND cn.year = e.calendar_year
LEFT JOIN dot d ON d.codinv = e.codinv AND d.year = e.calendar_year
ORDER BY e.deal_id, e.arm, e.codinv, e.roster_row_id, e.event_time
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
      if (has_control_firm_eligibility) {
        "CASE WHEN r.arm = 'control'
              THEN cfe.control_firm_exits_before_g_plus_5
              ELSE NULL END"
      } else "NULL::BOOLEAN",
      if (has_control_firm_eligibility) {
        "LEFT JOIN lmv2_control_firm_eligibility_cast cfe
           ON cfe.cohort = r.cohort
          AND cfe.control_group = r.focal_group_1"
      } else "")

    profile_path <- NA_character_
    if (!is.null(profile_dir)) {
      profile_path <- normalizePath(
        file.path(profile_dir, sprintf("cohort_%d.json", g)),
        winslash = "/", mustWork = FALSE)
      DBI::dbExecute(con, "PRAGMA enable_profiling='json'")
      DBI::dbExecute(con, sprintf(
        "PRAGMA profiling_output='%s'", profile_path))
    }
    DBI::dbExecute(con, sql)
    if (!is.null(profile_dir)) {
      DBI::dbExecute(con, "PRAGMA disable_profiling")
    }

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
                                runtime_seconds =
                                  proc.time()[["elapsed"]] - shard_started,
                                profile_path = profile_path,
                                roster_hash_xor = roster_hash$roster_hash_xor)
  }
  do.call(rbind, manifest)
}

# ---------------------------------------------------------------------------
# Common-support selection artifact. The causal event panel above remains
# supported-only. This separate, pre-treatment-only file supplies outcomes
# and the frozen P3 covariates for every eligible treated inventor, including
# the unsupported tail required by the P6 sensitivity freeze. It never
# materializes post-treatment outcomes for unsupported inventors.
# ---------------------------------------------------------------------------
materialize_lmv2_selection_prepanel <- function(
    con, roster_tbl, schema, out_path) {
  s <- function(tbl) sprintf("%s.%s", schema, tbl)
  q <- function(sql) DBI::dbGetQuery(con, sql)

  treated_duplicate_keys <- q("
    SELECT COUNT(*) n FROM (
      SELECT cohort, deal_id, CAST(codinv AS BIGINT) AS codinv
      FROM lmv2_treated_primary
      GROUP BY 1, 2, 3 HAVING COUNT(*) > 1)")$n
  if (treated_duplicate_keys > 0) {
    stop("lmv2_treated_primary is not unique on (cohort, deal_id, codinv)")
  }
  unit_duplicate_keys <- q("
    SELECT COUNT(*) n FROM (
      SELECT cohort, deal_id, codinv
      FROM lmv2_p3_treated_inventor_units
      GROUP BY 1, 2, 3 HAVING COUNT(*) > 1)")$n
  if (unit_duplicate_keys > 0) {
    stop(
      "lmv2_p3_treated_inventor_units is not unique on ",
      "(cohort, deal_id, codinv)")
  }
  missing_unit_rows <- q("
    SELECT COUNT(*) n
    FROM lmv2_treated_primary t
    WHERE NOT EXISTS (
      SELECT 1 FROM lmv2_p3_treated_inventor_units u
      WHERE u.cohort = t.cohort AND u.deal_id = t.deal_id
        AND u.codinv = CAST(t.codinv AS BIGINT))")$n
  if (missing_unit_rows > 0) {
    stop(
      "Selection pre-panel cannot attach frozen P3 covariates to ",
      missing_unit_rows, " treated inventors")
  }

  out_path <- normalizePath(
    out_path, winslash = "/", mustWork = FALSE)
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  sql <- sprintf("
COPY (
WITH all_treated AS MATERIALIZED (
  SELECT
    t.cohort,
    t.deal_id,
    CAST(t.codinv AS BIGINT) AS codinv,
    t.status_eligible,
    u.patent_count_5y,
    u.log_patent_count_5y,
    u.patent_trajectory,
    u.career_age,
    u.focal_group_tenure,
    u.focal_group_exclusivity
  FROM lmv2_treated_primary t
  JOIN lmv2_p3_treated_inventor_units u
    ON u.cohort = t.cohort AND u.deal_id = t.deal_id
   AND u.codinv = CAST(t.codinv AS BIGINT)
),
supported AS MATERIALIZED (
  SELECT DISTINCT cohort, deal_id, codinv
  FROM %1$s WHERE arm = 'treated'
),
events AS MATERIALIZED (
  SELECT
    a.*,
    (s.codinv IS NOT NULL) AS supported,
    et.event_time,
    a.cohort + et.event_time AS calendar_year
  FROM all_treated a
  LEFT JOIN supported s USING (cohort, deal_id, codinv)
  CROSS JOIN (
    SELECT UNNEST(range(-5, 0)) AS event_time
  ) et
),
baseline AS MATERIALIZED (
  SELECT
    a.cohort, a.deal_id, a.codinv, v.ipc4,
    SUM(v.weight) AS bw
  FROM all_treated a
  JOIN %2$s v
    ON v.codinv = a.codinv
   AND v.year BETWEEN a.cohort - 5 AND a.cohort - 1
  GROUP BY 1, 2, 3, 4
),
bnorm AS (
  SELECT cohort, deal_id, codinv, SQRT(SUM(bw * bw)) AS bnorm
  FROM baseline GROUP BY 1, 2, 3
),
cvec AS MATERIALIZED (
  SELECT
    e.cohort, e.deal_id, e.codinv, e.calendar_year,
    v.ipc4, v.weight AS cw
  FROM events e
  JOIN %2$s v
    ON v.codinv = e.codinv AND v.year = e.calendar_year
),
cnorm AS (
  SELECT cohort, deal_id, codinv, calendar_year,
         SQRT(SUM(cw * cw)) AS cnorm
  FROM cvec GROUP BY 1, 2, 3, 4
),
dot AS (
  SELECT
    c.cohort, c.deal_id, c.codinv, c.calendar_year,
    SUM(b.bw * c.cw) AS dot
  FROM cvec c
  JOIN baseline b
    ON b.cohort = c.cohort AND b.deal_id = c.deal_id
   AND b.codinv = c.codinv AND b.ipc4 = c.ipc4
  GROUP BY 1, 2, 3, 4
)
SELECT
  e.cohort, e.deal_id, e.codinv, e.status_eligible, e.supported,
  e.patent_count_5y, e.log_patent_count_5y, e.patent_trajectory,
  e.career_age, e.focal_group_tenure, e.focal_group_exclusivity,
  e.event_time, e.calendar_year,
  COALESCE(oy.patent_count, 0) AS patent_count,
  COALESCE(oy.fractional_patent_count, 0) AS fractional_patent_count,
  (COALESCE(oy.patent_count, 0) > 0)::INTEGER AS active_patenting,
  COALESCE(oy.n_linked_oecd, 0) AS n_linked_oecd,
  COALESCE(oy.n_fwd_nonmiss, 0) AS n_fwd_nonmiss,
  COALESCE(oy.n_pqii_nonmiss, 0) AS n_pqii_nonmiss,
  %3$s,
  %4$s,
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
LEFT JOIN %5$s oy
  ON oy.codinv = e.codinv AND oy.year = e.calendar_year
LEFT JOIN bnorm bn
  ON bn.cohort = e.cohort AND bn.deal_id = e.deal_id
 AND bn.codinv = e.codinv
LEFT JOIN cnorm cn
  ON cn.cohort = e.cohort AND cn.deal_id = e.deal_id
 AND cn.codinv = e.codinv AND cn.calendar_year = e.calendar_year
LEFT JOIN dot d
  ON d.cohort = e.cohort AND d.deal_id = e.deal_id
 AND d.codinv = e.codinv AND d.calendar_year = e.calendar_year
ORDER BY e.cohort, e.deal_id, e.codinv, e.event_time
) TO '%6$s' (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE TRUE)",
    roster_tbl,
    s("lmv2_inventor_ipc4_year"),
    lmv2_outcome_variant_sql(
      "fwd_cits5",
      "COALESCE(oy.patent_count, 0)",
      "COALESCE(oy.n_fwd_nonmiss, 0)",
      "oy.sum_fwd_cits5_obs"),
    lmv2_outcome_variant_sql(
      "pqii",
      "COALESCE(oy.patent_count, 0)",
      "COALESCE(oy.n_pqii_nonmiss, 0)",
      "oy.sum_pqii_obs"),
    s("lmv2_outcome_inventor_year"),
    out_path)
  DBI::dbExecute(con, sql)

  expected_units <- q("SELECT COUNT(*) n FROM lmv2_treated_primary")$n
  actual <- q(sprintf("
    SELECT
      COUNT(*) AS rows,
      COUNT(DISTINCT (cohort, deal_id, codinv)) AS units,
      COUNT(DISTINCT (cohort, deal_id, codinv))
        FILTER (WHERE supported) AS supported_units,
      COUNT(DISTINCT (cohort, deal_id, codinv))
        FILTER (WHERE NOT supported) AS unsupported_units,
      MIN(event_time) AS min_event_time,
      MAX(event_time) AS max_event_time,
      MAX(calendar_year - cohort) AS max_relative_year
    FROM read_parquet('%s')", out_path))
  expected_supported <- q(sprintf("
    SELECT COUNT(*) n FROM (
      SELECT DISTINCT cohort, deal_id, codinv
      FROM %s WHERE arm = 'treated')", roster_tbl))$n
  support_mismatch <- q(sprintf("
    WITH observed AS (
      SELECT DISTINCT cohort, deal_id, codinv
      FROM read_parquet('%1$s') WHERE supported
    ),
    expected AS (
      SELECT DISTINCT cohort, deal_id, codinv
      FROM %2$s WHERE arm = 'treated'
    )
    SELECT
      (SELECT COUNT(*) FROM (
         SELECT * FROM observed EXCEPT SELECT * FROM expected)) +
      (SELECT COUNT(*) FROM (
         SELECT * FROM expected EXCEPT SELECT * FROM observed)) AS n",
    out_path, roster_tbl))$n

  checks <- data.frame(
    check = c(
      "selection_prepanel_rows_equal_all_treated_x5",
      "selection_prepanel_unit_grain_complete",
      "selection_prepanel_supported_membership_exact",
      "selection_prepanel_strictly_pre_treatment"),
    observed = c(
      actual$rows,
      actual$units,
      support_mismatch,
      paste(actual$min_event_time, actual$max_event_time,
            actual$max_relative_year, sep = ":")),
    expected = c(
      expected_units * 5,
      expected_units,
      0,
      "-5:-1:-1"),
    pass = c(
      actual$rows == expected_units * 5,
      actual$units == expected_units,
      support_mismatch == 0 &&
        actual$supported_units == expected_supported,
      actual$min_event_time == -5 &&
        actual$max_event_time == -1 &&
        actual$max_relative_year == -1),
    stringsAsFactors = FALSE)
  attr(checks, "manifest") <- data.frame(
    artifact = out_path,
    rows = actual$rows,
    eligible_treated_units = actual$units,
    supported_units = actual$supported_units,
    unsupported_units = actual$unsupported_units,
    parquet_md5 = unname(tools::md5sum(out_path)),
    stringsAsFactors = FALSE)
  checks
}
