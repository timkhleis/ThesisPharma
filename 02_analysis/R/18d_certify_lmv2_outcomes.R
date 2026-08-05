# ============================================================================
# 18d_certify_lmv2_outcomes.R -- P6 certification suite (dormant)
# ============================================================================
# Function library only; nothing executes at source time. The suite is run by
# 18e after the double build. Test families follow the approved P6 plan.

# ---------------------------------------------------------------------------
# Provenance gates
# ---------------------------------------------------------------------------

# Ignore DuckDB's safe profiling controls, then reject every remaining
# occurrence of "filing".  Keep this broad: identifiers such as
# lmv2_oecd_coverage_filingyear are exactly the leak paths this guard targets.
lmv2_has_forbidden_filing_reference <- function(src_lines) {
  src_scan <- gsub("profiling", "", src_lines, fixed = TRUE)
  any(grepl("filing", src_scan, fixed = TRUE))
}

# All five P2 interfaces must match the P2 manifest (hash + row count),
# using P2's exact serialized-SHA-256 method. Never replaced.
lmv2_check_p2_interfaces <- function(con, p2_manifest_path,
                                     config = LMV2_P6_CONFIG) {
  manifest <- utils::read.csv(p2_manifest_path, stringsAsFactors = FALSE)
  out <- lapply(config$p2_interfaces, function(tbl) {
    expected <- manifest[manifest$table == tbl, , drop = FALSE]
    if (nrow(expected) != 1) {
      stop("P2 manifest is missing interface: ", tbl)
    }
    actual_hash <- lmv2_p2_table_hash(con, tbl)
    actual_rows <- DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM %s", DBI::dbQuoteIdentifier(con, tbl)))$n
    data.frame(
      table = tbl,
      expected_hash = expected$logical_sha256,
      actual_hash = actual_hash,
      expected_rows = expected$rows,
      actual_rows = actual_rows,
      pass = identical(actual_hash, expected$logical_sha256) &&
        actual_rows == expected$rows,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, out)
  if (!all(out$pass)) {
    stop("P2 interface validation failed: ",
         paste(out$table[!out$pass], collapse = ", "))
  }
  out
}

# P1-layer inputs consumed by P6, certified with P1's hash-sum/hash-XOR
# method: inventor_year with the exact 15c column list, the other consumed
# foundation tables over all columns. Recorded before and after the build.
lmv2_p1_upstream_checksums <- function(con, config = LMV2_P6_CONFIG) {
  out <- lapply(config$p6_consumed_foundation_tables, function(tbl) {
    cols <- if (tbl == "inventor_year") config$p1_inventor_year_hash_columns
            else NULL
    lmv2_p1_logical_checksum(con, tbl, cols)
  })
  do.call(rbind, out)
}

# ---------------------------------------------------------------------------
# Synthetic fixture: hand-crafted ingredients with exactly derivable outputs.
# Cohort g = 2000, deal 9001, focal groups 501/502, non-focal groups 777/888.
# ---------------------------------------------------------------------------
build_lmv2_p6_fixture <- function(con, schema = "p6_fixture") {
  DBI::dbExecute(con, sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
  s <- function(tbl) sprintf("%s.%s", schema, tbl)

  # Inventor-year outcomes.
  #  101: full linkage pre and post           -> all variants observed
  #  102: post year with 2 patents, 1 fwd-linked, 0 pqii-linked
  #       -> fwd complete NA / observed 4 / scaled 8 / cond 4; pqii all NA
  #  103: pre year with zero linkage          -> all fwd and pqii variants NA
  #  104: post-only patents (empty baseline)  -> TechDrift NA
  #  105: company-path stayer
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT CAST(codinv AS BIGINT) AS codinv, CAST(year AS INTEGER) AS year,
           CAST(patent_count AS BIGINT) AS patent_count,
           fractional_patent_count,
           CAST(n_linked_oecd AS BIGINT) AS n_linked_oecd,
           CAST(n_fwd_nonmiss AS BIGINT) AS n_fwd_nonmiss,
           CAST(sum_fwd_cits5_obs AS DOUBLE) AS sum_fwd_cits5_obs,
           CAST(n_pqii_nonmiss AS BIGINT) AS n_pqii_nonmiss,
           CAST(sum_pqii_obs AS DOUBLE) AS sum_pqii_obs
    FROM (VALUES
      (101, 1999, 1, 1.0, 1, 1, 3.0, 1, 0.5),
      (101, 2001, 1, 1.0, 1, 1, 2.0, 1, 0.7),
      (102, 1999, 1, 1.0, 1, 1, 1.0, 1, 0.4),
      (102, 2002, 2, 2.0, 1, 1, 4.0, 0, NULL),
      (103, 1999, 1, 1.0, 0, 0, NULL, 0, NULL),
      (104, 2001, 1, 1.0, 1, 1, 5.0, 1, 0.9),
      (105, 1999, 1, 1.0, 1, 1, 1.0, 1, 0.2),
      (105, 2001, 1, 1.0, 1, 1, 1.0, 1, 0.3)
    ) AS t(codinv, year, patent_count, fractional_patent_count, n_linked_oecd,
           n_fwd_nonmiss, sum_fwd_cits5_obs, n_pqii_nonmiss, sum_pqii_obs)",
    s("lmv2_outcome_inventor_year")))

  # Resolved affiliations (stayer group path).
  #  101 first post 2001 resolved 501 -> group stayer
  #  102 first post 2002 resolved 777 -> not a stayer
  #  103 no post affiliation          -> not a stayer
  #  104 first post 2001 resolved 502 -> group stayer via focal_group_2
  #  105 first post 2001 resolved 888 -> group path FALSE, company path TRUE
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT CAST(codinv AS BIGINT) AS codinv, CAST(year AS INTEGER) AS year,
           CAST(resolved_group AS BIGINT) AS resolved_group,
           CAST(candidate_group_count AS INTEGER) AS candidate_group_count
    FROM (VALUES
      (101, 1999, 501, 1), (101, 2001, 501, 1),
      (102, 1999, 501, 1), (102, 2002, 777, 1),
      (103, 1999, 501, 1),
      (104, 2001, 502, 1),
      (105, 1999, 501, 1), (105, 2001, 888, 1)
    ) AS t(codinv, year, resolved_group, candidate_group_count)",
    s("lmv2_outcome_inventor_affiliation_year")))

  # Patent-level group links (absorbing Left evidence).
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT CAST(codinv AS BIGINT) AS codinv, CAST(year AS INTEGER) AS year,
           CAST(id_group AS BIGINT) AS id_group,
           CAST(n_patents AS BIGINT) AS n_patents
    FROM (VALUES
      (101, 1999, 501, 1), (101, 2001, 501, 1),
      (102, 1999, 501, 1), (102, 2002, 777, 2),
      (103, 1999, 501, 1),
      (104, 2001, 502, 1),
      (105, 1999, 501, 1), (105, 2001, 888, 1)
    ) AS t(codinv, year, id_group, n_patents)",
    s("lmv2_inventor_group_patent_year")))

  # Deal-specific target-company links; 105's 2001 patent names the legal
  # target company even though its resolved group is 888.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT CAST(codinv AS BIGINT) AS codinv, CAST(deal_id AS BIGINT) AS deal_id,
           CAST(year AS INTEGER) AS year, CAST(n_patents AS BIGINT) AS n_patents
    FROM (VALUES
      (105, 9001, 1999, 1), (105, 9001, 2001, 1)
    ) AS t(codinv, deal_id, year, n_patents)",
    s("lmv2_inventor_target_company_patent_year")))

  # IPC4 vectors: 101 identical pre/post -> similarity 1; 102 disjoint -> 0;
  # 104 empty baseline -> NA.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT CAST(codinv AS BIGINT) AS codinv, CAST(year AS INTEGER) AS year,
           CAST(ipc4 AS VARCHAR) AS ipc4, CAST(weight AS BIGINT) AS weight
    FROM (VALUES
      (101, 1999, 'A61K', 1), (101, 2001, 'A61K', 1),
      (102, 1999, 'A61K', 1), (102, 2002, 'C07D', 2),
      (103, 1999, 'A61K', 1),
      (104, 2001, 'A61K', 1),
      (105, 1999, 'A61K', 1), (105, 2001, 'A61K', 1)
    ) AS t(codinv, year, ipc4, weight)",
    s("lmv2_inventor_ipc4_year")))

  # Inventor 106: patents but no focal evidence at all (resolved to group
  # 999, no group-501/502 links, no target-company rows) -> Left must be NA
  # and audited via left_defined, never coded 1; not a stayer.
  DBI::dbExecute(con, sprintf(
    "INSERT INTO %s VALUES (106, 2001, 1, 1.0, 1, 1, 1.0, 1, 0.1)",
    s("lmv2_outcome_inventor_year")))
  DBI::dbExecute(con, sprintf(
    "INSERT INTO %s VALUES (106, 2001, 999, 1)",
    s("lmv2_outcome_inventor_affiliation_year")))
  DBI::dbExecute(con, sprintf(
    "INSERT INTO %s VALUES (106, 2001, 999, 1)",
    s("lmv2_inventor_group_patent_year")))
  DBI::dbExecute(con, sprintf(
    "INSERT INTO %s VALUES (106, 2001, 'A61K', 1)",
    s("lmv2_inventor_ipc4_year")))

  # Inventor 107 is the NULL-safety regression fixture for the split
  # last-focal joins: a control with focal_group_2 = NULL, no target-company
  # path, and no focal evidence. The result must remain undefined rather than
  # being converted to a sentinel year or a false Left event.
  DBI::dbExecute(con, sprintf(
    "INSERT INTO %s VALUES (107, 2001, 1, 1.0, 1, 1, 1.0, 1, 0.1)",
    s("lmv2_outcome_inventor_year")))
  DBI::dbExecute(con, sprintf(
    "INSERT INTO %s VALUES (107, 2001, 999, 1)",
    s("lmv2_outcome_inventor_affiliation_year")))
  DBI::dbExecute(con, sprintf(
    "INSERT INTO %s VALUES (107, 2001, 999, 1)",
    s("lmv2_inventor_group_patent_year")))
  DBI::dbExecute(con, sprintf(
    "INSERT INTO %s VALUES (107, 2001, 'A61K', 1)",
    s("lmv2_inventor_ipc4_year")))

  # Fixture roster: six treated units plus the control-path NULL fixture.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT *
    FROM (
      SELECT CAST(9001 AS BIGINT) AS deal_id,
             CAST(2000 AS INTEGER) AS cohort,
             'treated' AS arm, CAST(c AS BIGINT) AS codinv,
             'fixture:' || CAST(c AS VARCHAR) AS roster_row_id,
             1.0 AS weight,
             TRUE AS status_eligible,
             CAST(501 AS BIGINT) AS focal_group_1,
             CAST(502 AS BIGINT) AS focal_group_2,
             TRUE AS use_target_company_path,
             'fixture_route' AS qualification_route,
             TRUE AS target_to_acquirer_transition_strict,
             CAST(1 AS INTEGER) AS latest_pre_candidate_group_count,
             FALSE AS multi_exposure_inventor,
             FALSE AS big_deal
      FROM (SELECT UNNEST([101, 102, 103, 104, 105, 106]) AS c)
      UNION ALL
      SELECT CAST(9001 AS BIGINT), CAST(2000 AS INTEGER),
             'control', CAST(107 AS BIGINT), 'fixture:107',
             1.0, TRUE, CAST(601 AS BIGINT), CAST(NULL AS BIGINT),
             FALSE, CAST(NULL AS VARCHAR), CAST(NULL AS BOOLEAN),
             CAST(NULL AS INTEGER), CAST(NULL AS BOOLEAN),
             CAST(NULL AS BOOLEAN)
    )",
    s("lmv2_fixture_roster")))

  invisible(schema)
}

# Expected values on the materialized fixture shard; every row is an exact
# hand-derivable assertion.
run_lmv2_fixture_assertions <- function(con, fixture_shard_path) {
  p <- gsub("\\\\", "/", fixture_shard_path)
  q <- function(sql) DBI::dbGetQuery(con, sprintf(sql, p))
  checks <- list()
  add <- function(name, pass) {
    checks[[length(checks) + 1L]] <<- data.frame(
      check = name, pass = isTRUE(pass), stringsAsFactors = FALSE)
  }

  panel <- q("SELECT * FROM read_parquet('%s')")
  row_of <- function(codinv, t) panel[panel$codinv == codinv &
                                        panel$event_time == t, , drop = FALSE]

  r101 <- row_of(101, 1)
  add("fixture_101_active_and_full_linkage",
      r101$active_patenting == 1 && r101$fwd_cits5_complete == 2 &&
        r101$pqii_complete == 0.7 && r101$tech_similarity == 1)
  add("fixture_101_group_stayer",
      r101$stayer_group_first_post_t0_t5 &&
        r101$status_eligible_stayer_first_post_t0_t5)

  r101_0 <- row_of(101, 0) # genuine zero-patent year
  add("fixture_zero_patent_year_structural_zeros",
      r101_0$patent_count == 0 && r101_0$active_patenting == 0 &&
        r101_0$fwd_cits5_complete == 0 && r101_0$fwd_cits5_observed == 0 &&
        r101_0$fwd_cits5_scaled == 0 &&
        is.na(r101_0$fwd_cits5_conditional_mean))

  r102 <- row_of(102, 2) # partial fwd linkage, zero pqii linkage
  add("fixture_102_partial_linkage_matrix",
      is.na(r102$fwd_cits5_complete) && r102$fwd_cits5_observed == 4 &&
        r102$fwd_cits5_scaled == 8 && r102$fwd_cits5_conditional_mean == 4 &&
        is.na(r102$pqii_complete) && is.na(r102$pqii_observed) &&
        is.na(r102$pqii_scaled) && is.na(r102$pqii_conditional_mean))
  add("fixture_102_disjoint_techdrift_zero", r102$tech_similarity == 0)
  add("fixture_102_not_stayer",
      !r102$stayer_focal_entity_first_post_t0_t5)
  r102_0 <- row_of(102, 0)
  add("fixture_102_left_onset_at_t0",
      r102_0$left_focal == 1 && r102_0$left_onset == 1)

  r103 <- row_of(103, -1) # patent year with zero linkage
  add("fixture_103_zero_linkage_all_na",
      r103$patent_count == 1 && is.na(r103$fwd_cits5_complete) &&
        is.na(r103$fwd_cits5_observed) && is.na(r103$fwd_cits5_scaled) &&
        is.na(r103$fwd_cits5_conditional_mean))
  add("fixture_103_no_post_not_stayer",
      !row_of(103, 0)$stayer_focal_entity_first_post_t0_t5)

  r104 <- row_of(104, 1)
  add("fixture_104_empty_baseline_techdrift_na", is.na(r104$tech_similarity))
  add("fixture_104_stayer_via_focal_group_2",
      r104$stayer_group_first_post_t0_t5)

  r105 <- row_of(105, 1)
  add("fixture_105_company_path_stayer",
      !r105$stayer_group_first_post_t0_t5 &&
        r105$stayer_target_company_first_post_t0_t5 &&
        r105$stayer_focal_entity_first_post_t0_t5)

  p106 <- panel[panel$codinv == 106, , drop = FALSE]
  add("fixture_106_undefined_left_is_na_and_audited",
      all(is.na(p106$left_focal)) && all(is.na(p106$left_onset)) &&
        all(!p106$left_defined))
  add("fixture_106_no_focal_evidence_not_stayer",
      all(!p106$stayer_focal_entity_first_post_t0_t5))
  p107 <- panel[panel$codinv == 107, , drop = FALSE]
  add("fixture_107_control_null_focal2_false_target_path_is_null_safe",
      all(p107$arm == "control") &&
        all(is.na(p107$focal_group_2)) &&
        all(!p107$use_target_company_path) &&
        all(is.na(p107$last_focal_patent_year)) &&
        all(!p107$left_defined) &&
        all(is.na(p107$left_focal)) &&
        all(is.na(p107$left_onset)))
  add("fixture_101_tech_drift_is_one_minus_similarity",
      abs((1 - row_of(101, 1)$tech_similarity) -
            row_of(101, 1)$tech_drift) < 1e-12)

  # Active Patenting refers strictly to the current year: 103 patents only in
  # 1999, so every other event year must be inactive despite later panel rows.
  add("fixture_active_current_year_only",
      all(panel$active_patenting[panel$codinv == 103 &
                                   panel$event_time != -1] == 0))

  do.call(rbind, checks)
}

# ---------------------------------------------------------------------------
# Roster-validation unit tests: every rule must fail with its exact message.
# ---------------------------------------------------------------------------
run_lmv2_roster_validation_tests <- function(con, fixture_schema = "p6_fixture",
                                             config = LMV2_P6_CONFIG) {
  s <- function(tbl) sprintf("%s.%s", fixture_schema, tbl)
  base <- s("lmv2_valid_control_roster")
  work <- s("lmv2_corrupt_roster")
  test_config <- config
  test_config$cohorts <- 2000L

  # A valid weighted two-arm roster: treated and control mass are equal and
  # the deal-level control pool spans two firms.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE %s AS
    SELECT CAST(deal_id AS BIGINT) AS deal_id,
           CAST(cohort AS INTEGER) AS cohort, arm,
           CAST(codinv AS BIGINT) AS codinv,
           CAST(roster_row_id AS VARCHAR) AS roster_row_id,
           CAST(weight AS DOUBLE) AS weight,
           status_eligible,
           CAST(focal_group_1 AS BIGINT) AS focal_group_1,
           CAST(focal_group_2 AS BIGINT) AS focal_group_2,
           use_target_company_path, qualification_route,
           target_to_acquirer_transition_strict,
           CAST(latest_pre_candidate_group_count AS INTEGER)
             AS latest_pre_candidate_group_count,
           multi_exposure_inventor, big_deal
    FROM (VALUES
      (9001, 2000, 'treated', 201, 't201', 1.0, TRUE, 501, 502, TRUE,
       'fixture_route', TRUE, 1, FALSE, FALSE),
      (9001, 2000, 'control', 202, 'c202', 0.5, TRUE, 601, NULL, FALSE,
       NULL, NULL, NULL, NULL, NULL),
      (9001, 2000, 'control', 203, 'c203', 0.3, TRUE, 601, NULL, FALSE,
       NULL, NULL, NULL, NULL, NULL),
      (9001, 2000, 'control', 204, 'c204', 0.2, TRUE, 602, NULL, FALSE,
       NULL, NULL, NULL, NULL, NULL)
    ) AS t(deal_id, cohort, arm, codinv, roster_row_id, weight,
           status_eligible, focal_group_1, focal_group_2,
           use_target_company_path, qualification_route,
           target_to_acquirer_transition_strict,
           latest_pre_candidate_group_count, multi_exposure_inventor,
           big_deal)",
    base))
  validate_lmv2_roster(con, base, test_config) # must pass

  cases <- list(
    list(name = "invalid_arm",
         sql = sprintf("UPDATE %s SET arm = 'x' WHERE codinv = 202", work),
         msg = "arm values must be"),
    list(name = "duplicate_key",
         sql = sprintf("INSERT INTO %s SELECT * FROM %s WHERE codinv = 202",
                       work, work),
         msg = "must be unique"),
    list(name = "duplicate_conceptual_row",
         sql = sprintf(
           "INSERT INTO %s SELECT * REPLACE ('different-row-id' AS roster_row_id)
            FROM %s WHERE codinv = 202", work, work),
         msg = "Conceptual roster rows must be unique"),
    list(name = "two_cohorts_per_deal",
         sql = sprintf("UPDATE %s SET cohort = 2001 WHERE codinv = 204", work),
         msg = "exactly one cohort"),
    list(name = "cohort_out_of_range",
         sql = sprintf("UPDATE %s SET cohort = 1980", work),
         msg = "Roster cohorts must lie in"),
    list(name = "missing_focal_group",
         sql = sprintf("UPDATE %s SET focal_group_1 = NULL
                        WHERE codinv = 202", work),
         msg = "focal_group_1 must be non-missing"),
    list(name = "missing_status_eligible",
         sql = sprintf("UPDATE %s SET status_eligible = NULL
                        WHERE codinv = 201", work),
         msg = "status_eligible must be non-missing"),
    list(name = "treated_weight",
         sql = sprintf("UPDATE %s SET weight = 2 WHERE codinv = 201", work),
         msg = "weight = 1"),
    list(name = "treated_company_path",
         sql = sprintf("UPDATE %s SET use_target_company_path = FALSE
                        WHERE codinv = 201", work),
         msg = "use_target_company_path = TRUE"),
    list(name = "control_company_path",
         sql = sprintf("UPDATE %s SET use_target_company_path = TRUE
                        WHERE codinv = 202", work),
         msg = "use_target_company_path = FALSE"),
    list(name = "negative_control_weight",
         sql = sprintf("UPDATE %s SET weight = -0.1 WHERE codinv = 202", work),
         msg = "nonnegative"),
    list(name = "two_controls_only",
         sql = sprintf("DELETE FROM %s WHERE codinv = 204", work),
         msg = "equal mass within each cohort"),
    list(name = "single_control_firm",
         sql = sprintf("UPDATE %s SET focal_group_1 = 601
                        WHERE codinv = 204", work),
         msg = "at least two firms"),
    list(name = "weights_do_not_sum_to_one",
         sql = sprintf("UPDATE %s SET weight = 0.4 WHERE codinv = 204", work),
         msg = "equal mass within each cohort"),
    list(name = "null_arm_caught",
         sql = sprintf("UPDATE %s SET arm = NULL WHERE codinv = 202", work),
         msg = "must be non-missing"),
    list(name = "null_roster_row_id_caught",
         sql = sprintf("UPDATE %s SET roster_row_id = NULL
                        WHERE codinv = 203", work),
         msg = "must be non-missing"),
    list(name = "treated_without_control_set",
         sql = sprintf("INSERT INTO %s VALUES
                        (9001, 2000, 'treated', 205, 't205', 1.0, TRUE,
                         501, 502, TRUE, 'fixture_route', TRUE, 1,
                         FALSE, FALSE)", work),
         msg = "equal mass within each cohort"),
    list(name = "missing_control_arm",
         sql = sprintf("DELETE FROM %s WHERE arm = 'control'", work),
         msg = "must contain treated and control rows"),
    list(name = "control_status_eligible_false",
         sql = sprintf("UPDATE %s SET status_eligible = FALSE
                        WHERE codinv = 202", work),
         msg = "Control rows must have status_eligible = TRUE"),
    list(name = "control_focal_group_2_set",
         sql = sprintf("UPDATE %s SET focal_group_2 = 999
                        WHERE codinv = 202", work),
         msg = "Control rows must have focal_group_2 NULL")
  )

  out <- lapply(cases, function(cs) {
    DBI::dbExecute(con, sprintf(
      "CREATE OR REPLACE TABLE %s AS SELECT * FROM %s", work, base))
    DBI::dbExecute(con, cs$sql)
    err <- tryCatch({
      validate_lmv2_roster(
        con, work, test_config, mode = "production"); ""
    }, error = function(e) conditionMessage(e))
    data.frame(check = paste0("roster_validation_", cs$name),
               pass = grepl(cs$msg, err, fixed = TRUE),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, out)

  # Fixture mode must accept a treated-only roster (no control arm at all).
  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE TABLE %s AS SELECT * FROM %s WHERE arm = 'treated'",
    work, base))
  fixture_ok <- tryCatch({
    validate_lmv2_roster(con, work, config, mode = "treated_fixture"); TRUE
  }, error = function(e) FALSE)
  rbind(out, data.frame(check = "roster_validation_fixture_mode_treated_only",
                        pass = fixture_ok, stringsAsFactors = FALSE))
}

# ---------------------------------------------------------------------------
# Frozen reporting metadata and coverage diagnostics. These describe outcome
# availability; they do not estimate an ATT or choose among designs.
# ---------------------------------------------------------------------------
write_lmv2_p6_reporting_diagnostics <- function(
    con, panel_dirs, audit_dir, config = LMV2_P6_CONFIG) {
  utils::write.csv(
    data.frame(
      outcome = c(
        config$outcome_status$primary,
        config$outcome_status$secondary),
      designation = c(
        rep("primary", length(config$outcome_status$primary)),
        rep("secondary", length(config$outcome_status$secondary))),
      leading_variant = c(
        rep("as_materialized", length(config$outcome_status$primary)),
        rep(config$outcome_status$oecd_leading_variant,
            length(config$outcome_status$secondary))),
      stringsAsFactors = FALSE),
    file.path(audit_dir, "p6_outcome_designations.csv"),
    row.names = FALSE)

  panel_label <- if ("matched" %in% names(panel_dirs)) {
    "matched"
  } else {
    "treated_fixture"
  }
  shards <- list.files(
    panel_dirs[[panel_label]],
    pattern = "^lmv2_event_panel_c\\d+\\.parquet$",
    full.names = TRUE)
  if (length(shards)) {
    quoted <- paste0(
      "'", gsub("'", "''", gsub("\\\\", "/", shards)), "'",
      collapse = ",")
    coverage <- DBI::dbGetQuery(con, sprintf("
      WITH p AS (SELECT * FROM read_parquet([%s]))
      SELECT
        cohort, event_time, calendar_year, arm, late_tail_flag,
        (cohort <= 2008) AS censoring_clean_cohort,
        COUNT(*) AS roster_rows,
        SUM(weight) AS weight_mass,
        SUM(weight * patent_count) AS weighted_patents,
        SUM(weight * n_linked_oecd) AS weighted_oecd_links,
        SUM(weight * n_fwd_nonmiss) AS weighted_fwd_nonmissing,
        SUM(weight * n_pqii_nonmiss) AS weighted_pqii_nonmissing,
        CASE WHEN SUM(weight * patent_count) > 0
          THEN SUM(weight * n_linked_oecd) /
               SUM(weight * patent_count) ELSE NULL END
          AS oecd_linkage_rate,
        CASE WHEN SUM(weight * patent_count) > 0
          THEN SUM(weight * n_fwd_nonmiss) /
               SUM(weight * patent_count) ELSE NULL END
          AS fwd_cits5_availability_rate,
        CASE WHEN SUM(weight * patent_count) > 0
          THEN SUM(weight * n_pqii_nonmiss) /
               SUM(weight * patent_count) ELSE NULL END
          AS pqii_availability_rate
      FROM p
      GROUP BY ALL
      ORDER BY cohort, event_time, arm", quoted))
    utils::write.csv(
      coverage, file.path(audit_dir, "p6_event_time_coverage.csv"),
      row.names = FALSE, na = "")
  }

  # Only characteristics observed before the OECD join can compare linked
  # and unlinked applications. OECD family size and forward citations are
  # missing by construction for unlinked applications.
  linkage <- DBI::dbGetQuery(con, "
    WITH inv AS (
      SELECT appln_id, COUNT(DISTINCT codinv) AS inventor_count
      FROM patent_inventor GROUP BY appln_id
    ), app AS (
      SELECT
        pa.appln_id, pa.patent_year, pa.patent_row_count,
        pa.compcod_count, COALESCE(inv.inventor_count, 0) AS inventor_count,
        (oq.appln_id IS NOT NULL) AS oecd_linked
      FROM patent_application pa
      LEFT JOIN inv USING (appln_id)
      LEFT JOIN oecd_quality oq USING (appln_id)
    )
    SELECT
      patent_year, oecd_linked, COUNT(*) AS applications,
      AVG(patent_row_count) AS mean_patent_rows,
      AVG(compcod_count) AS mean_linked_companies,
      AVG(inventor_count) AS mean_inventors
    FROM app
    GROUP BY patent_year, oecd_linked
    ORDER BY patent_year, oecd_linked")
  utils::write.csv(
    linkage,
    file.path(audit_dir, "p6_oecd_linkage_nonrandomness.csv"),
    row.names = FALSE, na = "")
  utils::write.csv(
    data.frame(
      requested_characteristic = c(
        "family_size", "forward_citations", "applicant_type"),
      available_for_linked_and_unlinked = c(FALSE, FALSE, FALSE),
      reason = c(
        "family_size exists only in oecd_quality",
        "forward-citation fields exist only in oecd_quality",
        "no applicant-type field exists in the certified patent spine"),
      stringsAsFactors = FALSE),
    file.path(
      audit_dir, "p6_oecd_linkage_diagnostic_field_limits.csv"),
    row.names = FALSE)
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# Full-data certification against the published ingredient schema and the
# treated fixture panel. `before_p1` / `before_p2` are the pre-build hashes.
# ---------------------------------------------------------------------------
# `panel_dirs` is a NAMED character vector of materialized panel directories
# (e.g. c(treated_fixture = ..., matched = ...)); every directory passes the
# full shard-level families, and treated rows in every directory must match
# the certified P2 stayer classification exactly.
run_lmv2_p6_certification <- function(con, schema, panel_dirs,
                                      before_p1, before_p2_manifest_path,
                                      r_dir, config = LMV2_P6_CONFIG) {
  s <- function(tbl) sprintf("%s.%s", schema, tbl)
  q <- function(sql) DBI::dbGetQuery(con, sql)
  checks <- list()
  add <- function(name, pass, detail = "") {
    checks[[length(checks) + 1L]] <<- data.frame(
      check = name, pass = isTRUE(pass), detail = detail,
      stringsAsFactors = FALSE)
  }

  # 1. Grain uniqueness.
  grains <- list(
    lmv2_outcome_inventor_year = "codinv, year",
    lmv2_outcome_inventor_affiliation_year = "codinv, year",
    lmv2_inventor_group_patent_year = "codinv, year, id_group",
    lmv2_inventor_target_company_patent_year = "codinv, deal_id, year",
    lmv2_inventor_ipc4_year = "codinv, year, ipc4"
  )
  for (tbl in names(grains)) {
    n <- q(sprintf(
      "SELECT COUNT(*) - COUNT(DISTINCT (%s)) n FROM %s",
      grains[[tbl]], s(tbl)))$n
    add(paste0("grain_", tbl), n == 0)
  }

  # 2. Patent counts equal direct distinct-pair computation from the spine.
  mism <- q(sprintf("
    WITH direct AS (
      SELECT CAST(pi.codinv AS BIGINT) AS codinv, pa.patent_year AS year,
             COUNT(DISTINCT pi.appln_id) AS pc
      FROM patent_inventor pi
      JOIN patent_application pa USING (appln_id)
      JOIN %s r ON r.codinv = CAST(pi.codinv AS BIGINT)
      GROUP BY 1, 2
    )
    SELECT COUNT(*) n
    FROM direct d
    FULL OUTER JOIN %s o USING (codinv, year)
    WHERE d.codinv IS NULL OR o.codinv IS NULL OR d.pc <> o.patent_count",
    s("lmv2_relevant_inventors"), s("lmv2_outcome_inventor_year")))$n
  add("patent_count_matches_spine", mism == 0,
      sprintf("mismatch_rows=%d", mism))

  # 5. Application-year timing: outcome code never reads OECD `filing`
  # (audit tables in 18b are the sole permitted consumers).
  src_18c <- readLines(file.path(r_dir, "18c_materialize_lmv2_outcome_panel.R"),
                       warn = FALSE)
  add("no_filing_reference_in_materializer",
      !lmv2_has_forbidden_filing_reference(src_18c))

  # 4 + 6 + 7 + 8. Shard-level families over EVERY materialized panel
  # directory: grain, stamped row counts, Left monotonicity/onset,
  # zero-vs-missing, and exact P2 stayer equality for treated rows.
  if (is.null(names(panel_dirs)) || any(names(panel_dirs) == "")) {
    stop("panel_dirs must be a named character vector")
  }
  for (dir_label in names(panel_dirs)) {
    pd <- panel_dirs[[dir_label]]
    shards <- list.files(pd, pattern = "^lmv2_event_panel_c\\d+\\.parquet$",
                         full.names = TRUE)
    add(paste0("shards_present_", dir_label), length(shards) > 0)
    left_violations <- onset_violations <- grain_violations <- 0
    stamp_row_mismatch <- stayer_mism <- silent_zero <- 0
    treated_not_in_p2 <- 0
    for (sh in shards) {
      p <- gsub("\\\\", "/", sh)
      stamp_file <- sub("\\.parquet$", "_stamp.csv", sh)
      n_shard <- q(sprintf("SELECT COUNT(*) n FROM read_parquet('%s')", p))$n
      if (!file.exists(stamp_file)) {
        stamp_row_mismatch <- stamp_row_mismatch + 1L
      } else {
        st <- utils::read.csv(stamp_file, colClasses = "character")
        if (n_shard != as.integer(st$shard_rows)) {
          stamp_row_mismatch <- stamp_row_mismatch + 1L
        }
      }
      left_violations <- left_violations + q(sprintf("
        SELECT COUNT(*) n FROM (
          SELECT left_focal - LAG(left_focal) OVER (
            PARTITION BY deal_id, arm, codinv, roster_row_id
            ORDER BY event_time) AS d
          FROM read_parquet('%s')) WHERE d < 0", p))$n
      onset_violations <- onset_violations + q(sprintf("
        SELECT COUNT(*) n FROM (
          SELECT deal_id, arm, codinv, roster_row_id, SUM(left_onset) so
          FROM read_parquet('%s')
          GROUP BY 1, 2, 3, 4 HAVING so > 1)", p))$n
      grain_violations <- grain_violations + q(sprintf("
        SELECT COUNT(*) - COUNT(DISTINCT
          (deal_id, arm, codinv, roster_row_id, event_time)) n
        FROM read_parquet('%s')", p))$n
      for (v in c("fwd_cits5", "pqii")) {
        ncol_ <- if (v == "fwd_cits5") "n_fwd_nonmiss" else "n_pqii_nonmiss"
        silent_zero <- silent_zero + q(sprintf("
          SELECT COUNT(*) n FROM read_parquet('%s')
          WHERE (patent_count > %s AND %s_complete IS NOT NULL)
             OR (patent_count > 0 AND %s = 0 AND (
                  %s_observed IS NOT NULL OR %s_scaled IS NOT NULL
                  OR %s_conditional_mean IS NOT NULL))",
          p, ncol_, v, ncol_, v, v, v))$n
      }
      # Anti-join membership: the stayer-equality inner join below would let
      # treated rows absent from P2 vanish silently, so their absence is a
      # separate, explicit failure.
      treated_not_in_p2 <- treated_not_in_p2 + q(sprintf("
        SELECT COUNT(*) n
        FROM (SELECT DISTINCT deal_id, codinv
              FROM read_parquet('%s') WHERE arm = 'treated') f
        WHERE NOT EXISTS (
          SELECT 1 FROM lmv2_treated_primary t
          WHERE t.deal_id = f.deal_id
            AND CAST(t.codinv AS BIGINT) = f.codinv)", p))$n
      stayer_mism <- stayer_mism + q(sprintf("
        SELECT COUNT(*) n
        FROM (SELECT DISTINCT deal_id, codinv, first_post_patent_year,
                     stayer_group_first_post_t0_t5,
                     stayer_target_company_first_post_t0_t5,
                     stayer_focal_entity_first_post_t0_t5,
                     status_eligible_stayer_first_post_t0_t5
              FROM read_parquet('%s') WHERE arm = 'treated') f
        JOIN lmv2_treated_primary t
          ON t.deal_id = f.deal_id AND CAST(t.codinv AS BIGINT) = f.codinv
        WHERE f.first_post_patent_year IS DISTINCT FROM t.first_post_patent_year
           OR f.stayer_group_first_post_t0_t5
              IS DISTINCT FROM t.stayer_group_first_post_t0_t5
           OR f.stayer_target_company_first_post_t0_t5
              IS DISTINCT FROM t.stayer_target_company_first_post_t0_t5
           OR f.stayer_focal_entity_first_post_t0_t5
              IS DISTINCT FROM t.stayer_focal_entity_first_post_t0_t5
           OR f.status_eligible_stayer_first_post_t0_t5
              IS DISTINCT FROM t.status_eligible_stayer_first_post_t0_t5",
        p))$n
    }
    add(paste0("shard_rows_match_stamps_", dir_label), stamp_row_mismatch == 0)
    add(paste0("left_weakly_increasing_", dir_label), left_violations == 0)
    add(paste0("left_onset_at_most_once_", dir_label), onset_violations == 0)
    add(paste0("shard_grain_unique_", dir_label), grain_violations == 0)
    add(paste0("no_silent_zero_", dir_label), silent_zero == 0)
    add(paste0("treated_rows_all_in_p2_", dir_label), treated_not_in_p2 == 0,
        sprintf("missing_rows=%d", treated_not_in_p2))
    add(paste0("treated_stayers_match_p2_", dir_label), stayer_mism == 0,
        sprintf("mismatch_rows=%d", stayer_mism))
  }

  # 11. OECD field availability among linked patents by filing year. This is
  # availability, NOT citation-window completeness: a non-missing fwd_cits5
  # does not prove a fully elapsed five-year window for late applications.
  avail <- q(sprintf(
    "SELECT filing_year, n_linked, n_fwd_nonmiss, n_pqii_nonmiss
     FROM %s ORDER BY filing_year", s("lmv2_oecd_coverage_filingyear")))
  add("oecd_field_availability_reported", nrow(avail) > 0)

  # 13. Upstream integrity, dual-method, before vs after.
  after_p1 <- lmv2_p1_upstream_checksums(con, config)
  add("p1_upstream_unchanged",
      lmv2_df_equal(before_p1[order(before_p1$table_name), ],
                    after_p1[order(after_p1$table_name), ]))
  after_p2 <- lmv2_check_p2_interfaces(con, before_p2_manifest_path, config)
  add("p2_interfaces_unchanged_after_build", all(after_p2$pass))

  checks_df <- do.call(rbind, checks)
  attr(checks_df, "oecd_field_availability") <- avail
  checks_df
}
