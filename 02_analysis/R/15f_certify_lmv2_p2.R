# ============================================================================
# 15f_certify_lmv2_p2.R -- independent certification of P2 interfaces
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))

for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
AUDIT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P2")
dir.create(AUDIT_DIR, recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=4")

scalar <- function(sql) DBI::dbGetQuery(con, sql)[[1]][1]
checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = name,
    observed = as.character(observed),
    expected = as.character(expected),
    pass = isTRUE(pass),
    stringsAsFactors = FALSE
  )
}

interfaces <- c(
  "lmv2_treated_primary", "lmv2_treated_broad",
  "lmv2_treated_unique_affiliation_robustness",
  "lmv2_control_firm_eligibility", "lmv2_control_inventor_eligibility"
)
present <- vapply(interfaces, DBI::dbExistsTable, logical(1), conn = con)
add_check("all_interfaces_exist", paste(present, collapse = ","), "all TRUE", all(present))
if (!all(present)) stop("P2 interfaces missing; run 15e_build_lmv2_p2.R first.")

add_check(
  "treated_primary_unique_inventor",
  scalar("SELECT COUNT(*) - COUNT(DISTINCT codinv) FROM lmv2_treated_primary"),
  0,
  scalar("SELECT COUNT(*) - COUNT(DISTINCT codinv) FROM lmv2_treated_primary") == 0
)
add_check(
  "treated_broad_unique_inventor",
  scalar("SELECT COUNT(*) - COUNT(DISTINCT codinv) FROM lmv2_treated_broad"),
  0,
  scalar("SELECT COUNT(*) - COUNT(DISTINCT codinv) FROM lmv2_treated_broad") == 0
)
add_check(
  "control_firm_unique_key",
  scalar("SELECT COUNT(*) - COUNT(DISTINCT (cohort, control_group)) FROM lmv2_control_firm_eligibility"),
  0,
  scalar("SELECT COUNT(*) - COUNT(DISTINCT (cohort, control_group)) FROM lmv2_control_firm_eligibility") == 0
)
add_check(
  "control_inventor_unique_key",
  scalar("SELECT COUNT(*) - COUNT(DISTINCT (cohort, codinv)) FROM lmv2_control_inventor_eligibility"),
  0,
  scalar("SELECT COUNT(*) - COUNT(DISTINCT (cohort, codinv)) FROM lmv2_control_inventor_eligibility") == 0
)

range_primary <- DBI::dbGetQuery(con, "SELECT MIN(cohort) lo, MAX(cohort) hi FROM lmv2_treated_primary")
range_control <- DBI::dbGetQuery(con, "SELECT MIN(cohort) lo, MAX(cohort) hi FROM lmv2_control_inventor_eligibility")
add_check("treated_cohort_range", paste(range_primary, collapse = ":"), "1993:2010",
          range_primary$lo == 1993 && range_primary$hi == 2010)
add_check("control_cohort_range", paste(range_control, collapse = ":"), "1993:2010",
          range_control$lo == 1993 && range_control$hi == 2010)

primary_not_broad <- scalar("
SELECT COUNT(*) FROM lmv2_treated_primary p
LEFT JOIN lmv2_treated_broad b USING (codinv, deal_id)
WHERE b.codinv IS NULL
")
add_check("primary_is_subset_of_broad", primary_not_broad, 0, primary_not_broad == 0)

unique_not_primary <- scalar("
SELECT COUNT(*)
FROM lmv2_treated_unique_affiliation_robustness u
LEFT JOIN lmv2_treated_primary p USING (codinv, deal_id)
WHERE p.codinv IS NULL
")
add_check("unique_affiliation_is_subset_of_primary", unique_not_primary, 0,
          unique_not_primary == 0)
unique_bad <- scalar("
SELECT COUNT(*) FROM lmv2_treated_unique_affiliation_robustness
WHERE latest_pre_candidate_group_count <> 1
")
add_check("unique_affiliation_robustness_is_unique", unique_bad, 0,
          unique_bad == 0)

invalid_routes <- scalar("
SELECT COUNT(*) FROM lmv2_treated_primary
WHERE qualification_route IS NULL
   OR (qualification_route = 'latest_target_affiliation' AND NOT target_resolved_latest)
   OR (qualification_route = 'strict_target_to_acquirer_transition'
       AND NOT target_to_acquirer_transition_strict)
   OR last_pre_affiliation_group IS NULL
   OR (qualification_route = 'latest_target_affiliation'
       AND last_pre_affiliation_group <> target_group)
   OR (qualification_route = 'strict_target_to_acquirer_transition'
       AND last_pre_affiliation_group <> acquirer_group)
")
add_check("treated_affiliation_routes_valid", invalid_routes, 0, invalid_routes == 0)

transition <- DBI::dbGetQuery(con, "
SELECT
  AVG((qualification_route = 'strict_target_to_acquirer_transition')::INTEGER) overall,
  (SELECT MAX(route_share) FROM (
     SELECT broad_era,
            AVG((qualification_route = 'strict_target_to_acquirer_transition')::INTEGER) route_share
     FROM lmv2_treated_primary GROUP BY broad_era
   )) max_era
FROM lmv2_treated_primary
")
add_check("transition_share_overall", transition$overall, "<=0.05", transition$overall <= 0.05)
add_check("transition_share_max_era", transition$max_era, "<=0.10", transition$max_era <= 0.10)

promoted <- DBI::dbGetQuery(con, "
SELECT
  string_agg(CAST(deal_id AS VARCHAR), ',' ORDER BY deal_id) AS all_ids,
  string_agg(
    CASE WHEN target_year BETWEEN 1993 AND 2010
         THEN CAST(deal_id AS VARCHAR) END,
    ',' ORDER BY deal_id
  ) AS analysis_ids
FROM deal_assignment
WHERE strict_eligible AND match_source = 'MERGE_ID_SUPPLEMENT'
")
add_check("supplementary_promotions_all_years", promoted$all_ids,
          "62,97,98,374,451", identical(promoted$all_ids, "62,97,98,374,451"))
add_check("supplementary_promotions_analysis_window", promoted$analysis_ids,
          "62,97,98,374", identical(promoted$analysis_ids, "62,97,98,374"))

invalid_promotion <- scalar("
SELECT COUNT(*)
FROM deal_assignment
WHERE strict_eligible
  AND match_source = 'MERGE_ID_SUPPLEMENT'
  AND NOT (
    n_target_nmb = 1
    AND matched_year = target_year
    AND matched_value = target_value
    AND n_target_groups = 1 AND target_group IS NOT NULL
    AND n_acquirer_groups = 1 AND acquirer_group IS NOT NULL
    AND acquirer_group_history_consistent
    AND NOT todrop_tar AND NOT todrop_acq AND NOT divest
  )
")
add_check("supplementary_promotions_satisfy_locked_rule", invalid_promotion, 0,
          invalid_promotion == 0)

firm_contamination <- scalar("
WITH target_groups AS (
  SELECT DISTINCT CAST(target_group AS DOUBLE) id_group
  FROM deal_assignment WHERE target_group IS NOT NULL
  UNION
  SELECT DISTINCT CAST(fg.id_group AS DOUBLE)
  FROM deal_assignment da
  JOIN deal_target_company_expanded dtc ON dtc.deal_id = da.deal_id
  JOIN firm_group fg
    ON CAST(fg.compcod AS BIGINT) = dtc.target_compcod
   AND fg.year = CAST(da.target_year AS INTEGER) - 1
), acquirer_events AS (
  SELECT DISTINCT CAST(acquirer_group AS DOUBLE) id_group,
                  CAST(target_year AS INTEGER) event_year
  FROM deal_assignment WHERE acquirer_group IS NOT NULL
)
SELECT COUNT(*)
FROM lmv2_control_firm_eligibility c
WHERE EXISTS (SELECT 1 FROM target_groups t WHERE t.id_group = c.control_group)
   OR EXISTS (
     SELECT 1 FROM acquirer_events a
     WHERE a.id_group = c.control_group
       AND a.event_year BETWEEN c.cohort - 5 AND c.cohort + 5
   )
")
add_check("control_firms_role_clean", firm_contamination, 0, firm_contamination == 0)

control_bad_affiliation <- scalar("
SELECT COUNT(*) FROM lmv2_control_inventor_eligibility
WHERE candidate_group_count <> 1 OR control_group IS NULL
")
add_check("control_inventor_affiliation_unique", control_bad_affiliation, 0,
          control_bad_affiliation == 0)

control_without_firm <- scalar("
SELECT COUNT(*) FROM lmv2_control_inventor_eligibility i
LEFT JOIN lmv2_control_firm_eligibility f USING (cohort, control_group)
WHERE f.control_group IS NULL
")
add_check("control_inventor_has_eligible_firm", control_without_firm, 0,
          control_without_firm == 0)

control_exposure <- scalar("
WITH exposures AS (
  SELECT DISTINCT CAST(pi.codinv AS BIGINT) codinv,
                  CAST(s.deal_year AS INTEGER) exposure_year
  FROM cassi_deal_group_spine_expanded s
  JOIN deal_target_company_expanded dtc ON dtc.deal_id = s.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year BETWEEN CAST(s.deal_year AS INTEGER) - 5
                    AND CAST(s.deal_year AS INTEGER) - 1
  JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
)
SELECT COUNT(*) FROM lmv2_control_inventor_eligibility c
WHERE EXISTS (
  SELECT 1 FROM exposures e
  WHERE e.codinv = c.codinv AND e.exposure_year <= c.cohort + 5
)
")
add_check("control_inventors_have_no_target_exposure_through_g5", control_exposure, 0,
          control_exposure == 0)

exit_rows <- scalar("
SELECT SUM(control_firm_exits_before_g_plus_5::INTEGER)
FROM lmv2_control_firm_eligibility
")
add_check("control_firm_exit_diagnostic_populated", exit_rows, ">0", exit_rows > 0)

stayer_mismatch <- scalar("
WITH first_post AS (
  SELECT
    p.codinv,
    p.deal_id,
    MIN(CAST(ia.year AS INTEGER)) AS first_post_patent_year
  FROM lmv2_treated_primary p
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = p.codinv
   AND ia.year BETWEEN p.cohort AND p.cohort + 5
  GROUP BY p.codinv, p.deal_id
), group_stayer AS (
  SELECT DISTINCT p.codinv, p.deal_id
  FROM lmv2_treated_primary p
  JOIN first_post fp USING (codinv, deal_id)
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = p.codinv
   AND ia.year = fp.first_post_patent_year
   AND ia.resolved_group IN (p.target_group, p.acquirer_group)
), target_company_stayer AS (
  SELECT DISTINCT p.codinv, p.deal_id
  FROM lmv2_treated_primary p
  JOIN first_post fp USING (codinv, deal_id)
  JOIN deal_target_company_strict dtc ON dtc.deal_id = p.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year = fp.first_post_patent_year
  JOIN patent_inventor pi
    ON pi.appln_id = pcl.appln_id
   AND CAST(pi.codinv AS BIGINT) = p.codinv
), truth AS (
  SELECT
    p.codinv,
    p.deal_id,
    fp.first_post_patent_year,
    (g.codinv IS NOT NULL OR t.codinv IS NOT NULL) expected
  FROM lmv2_treated_primary p
  LEFT JOIN first_post fp USING (codinv, deal_id)
  LEFT JOIN group_stayer g USING (codinv, deal_id)
  LEFT JOIN target_company_stayer t USING (codinv, deal_id)
)
SELECT COUNT(*)
FROM lmv2_treated_primary p JOIN truth t USING (codinv, deal_id)
WHERE p.first_post_patent_year IS DISTINCT FROM t.first_post_patent_year
   OR p.stayer_focal_entity_first_post_t0_t5 <> t.expected
   OR p.status_eligible_stayer_first_post_t0_t5
      <> (p.status_eligible AND t.expected)
")
add_check("stayer_first_post_recomputed_exactly", stayer_mismatch, 0,
          stayer_mismatch == 0)

co <- utils::read.csv(file.path(AUDIT_DIR, "cassi_ornaghi_exact_reproduction.csv"),
                      stringsAsFactors = FALSE)
co_expected <- c(311358, 1071405, 760047, 7104, 2675, 643267, 107001)
co_cols <- c(
  "reproduced_inventors", "reproduced_status_rows",
  "reproduced_separation_observations", "reproduced_target_stayers",
  "reproduced_target_leavers", "reproduced_nontarget_stayers",
  "reproduced_nontarget_leavers"
)
co_observed <- unlist(co[1, co_cols], use.names = FALSE)
add_check("cassi_ornaghi_sample_counts_reproduced",
          paste(co_observed, collapse = ","), paste(co_expected, collapse = ","),
          identical(as.numeric(co_observed), as.numeric(co_expected)))

power <- utils::read.csv(file.path(AUDIT_DIR, "buffered_stayer_power_gates.csv"),
                         stringsAsFactors = FALSE)
buffered <- power[power$sample == "1993-2008", ]
power_pass <- nrow(buffered) == 1L && isTRUE(buffered$pass_all_power_gates)
add_check("buffered_stayer_power_gate", power_pass, TRUE, power_pass)

result <- do.call(rbind, checks)
result$design_version <- LMV2_DESIGN_VERSION
result$design_hash <- LMV2_DESIGN_HASH
result <- result[, c("design_version", "design_hash", "check", "observed", "expected", "pass")]
utils::write.csv(result, file.path(AUDIT_DIR, "p2_certification_checks.csv"),
                 row.names = FALSE, na = "")

structural <- result$check != "buffered_stayer_power_gate"
structural_pass <- all(result$pass[structural])
status <- data.frame(
  design_version = LMV2_DESIGN_VERSION,
  design_hash = LMV2_DESIGN_HASH,
  structural_certification_pass = structural_pass,
  buffered_stayer_power_gate_pass = power_pass,
  package_status = if (structural_pass && power_pass) "PASS"
                   else if (structural_pass) "DESIGN_REVIEW_REQUIRED"
                   else "STRUCTURAL_FAILURE",
  stringsAsFactors = FALSE
)
utils::write.csv(status, file.path(AUDIT_DIR, "p2_package_status.csv"),
                 row.names = FALSE, na = "")

print(result)
print(status)
if (!structural_pass) stop("P2 structural certification failed.")
if (!power_pass) message("P2 interfaces pass, but the locked buffered-stayer power gate fails.")
