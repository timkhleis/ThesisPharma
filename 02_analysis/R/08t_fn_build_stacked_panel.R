# Fadlon-Nielsen stacked panel builder (Diagnostic follow-up -> corrected design)
#
# Builds a stacked treated + FN-control panel to remove the mechanical pre-trend
# hump. For each real treated cohort g (deal_year = g), the control arm is drawn
# from inventors at targets acquired at g+DELTA, RE-QUALIFIED relative to a
# placebo date g (window [g-5, g-1]) using the IDENTICAL 04c latest-affiliation
# rule. Both arms then carry the mechanical bump M(tau) at the same event-times,
# so it cancels inside a single stacked estimator (see 08u).
#
# Design (approved plan): DELTA=7 fixed; active_patenting only; cohorts
# g in [1993, 2008]; deterministic placebo dates; no double-qualification;
# controls must be not-yet-treated across the observation window.
#
# Read-only DuckDB connection: NO writes to the .duckdb file. Outputs go to
# parquet (fn_stacked_panel) + audit CSVs. Run via PowerShell:
#   & 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis/R/08t_fn_build_stacked_panel.R

BASE        <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB      <- file.path(BASE, "output", "thesis_foundation.duckdb")
DERIVED_PAR <- file.path(BASE, "output", "parquet", "derived")
AUDIT       <- file.path(BASE, "output", "audit", "fn_stacked")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

dir.create(DERIVED_PAR, recursive = TRUE, showWarnings = FALSE)
dir.create(AUDIT, recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_csv_base <- function(df, filename) {
  utils::write.csv(df, file.path(AUDIT, filename), row.names = FALSE, na = "")
}

# --- Parameters (approved plan) --------------------------------------------
DELTA       <- 7L                 # control lag: control deal at event-time +DELTA
REF_LO      <- 1993L              # earliest stack (g-5 >= 1988)
REF_HI      <- 2008L              # latest stack (g+DELTA <= 2015)
EVENT_LO    <- -5L
EVENT_HI    <-  5L
COV_TOL     <- 1e-6               # 4b numeric covariate tolerance
IPC_MATCH_MIN <- 0.99             # 4b ipc_primary_field match-rate floor

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")
DBI::dbExecute(con, "PRAGMA threads=4")
tmp_dir <- file.path(BASE, "output", "duckdb_tmp")
dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf("PRAGMA temp_directory='%s'", gsub("\\\\", "/", tmp_dir)))

banner("FN STACKED PANEL BUILD (Delta = 7)")

# ---------------------------------------------------------------------------
# Parameterized qualification: faithful port of 04c pre_target_side ->
# latest_pre_affiliation -> pre_target_side_current WHERE-clause, with the
# reference year shifted by `shift` (ref_year = deal_year - shift). For shift=0
# this reproduces target_cohort_own's qualification exactly (before exposure
# ranking, which is applied in R below). Returns one row per (codinv, deal_id).
# ---------------------------------------------------------------------------
qualify_sql <- function(shift) {
  sprintf("
WITH usable_deals AS (
  SELECT
    CAST(deal_id AS BIGINT)              AS deal_id,
    CAST(cassi_deal_group_id AS BIGINT)  AS cassi_deal_group_id,
    CAST(deal_year AS INTEGER)           AS deal_year,
    CAST(deal_year AS INTEGER) - %1$d    AS ref_year,
    target_group,
    acquirer_group,
    todrop_acq,
    CASE WHEN acquirer_group IS NOT NULL
          AND CAST(acquirer_group AS VARCHAR) NOT LIKE '999%%'
          AND NOT todrop_acq
         THEN TRUE ELSE FALSE END        AS status_eligible
  FROM cassi_deal_group_spine
),
-- Stage 1: (inventor, deal) pairs with >= 1 matching affiliation in the window.
target_candidate_pairs AS (
  SELECT DISTINCT
    ud.deal_id, ud.cassi_deal_group_id, ud.deal_year, ud.ref_year,
    ud.target_group, ud.acquirer_group, ud.status_eligible,
    CAST(ia.codinv AS BIGINT) AS codinv
  FROM usable_deals ud
  JOIN inventor_affiliation_own ia
    ON ia.year BETWEEN ud.ref_year - 5 AND ud.ref_year - 1
  WHERE COALESCE(ia.resolved_group = ud.target_group, FALSE)
     OR COALESCE(list_contains(string_split(ia.candidate_group_list, ';'),
                 CAST(CAST(ud.target_group AS BIGINT) AS VARCHAR)), FALSE)
     OR COALESCE(ia.resolved_group = ud.acquirer_group, FALSE)
),
-- Stage 2: re-join ALL of the inventor's window rows (matching or not), so the
-- 'latest' row below is the genuinely most-recent affiliation (04c's rule).
pts AS (
  SELECT
    tcp.deal_id, tcp.cassi_deal_group_id, tcp.deal_year, tcp.ref_year,
    tcp.target_group, tcp.acquirer_group, tcp.status_eligible, tcp.codinv,
    ia.year,
    COALESCE(ia.resolved_group = tcp.target_group, FALSE) AS target_resolved,
    COALESCE(list_contains(string_split(ia.candidate_group_list, ';'),
             CAST(CAST(tcp.target_group AS BIGINT) AS VARCHAR)), FALSE) AS target_candidate,
    COALESCE(ia.resolved_group = tcp.acquirer_group, FALSE) AS acquirer_resolved
  FROM target_candidate_pairs tcp
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = tcp.codinv
   AND ia.year BETWEEN tcp.ref_year - 5 AND tcp.ref_year - 1
),
summ AS (
  SELECT codinv, deal_id,
    MAX(CASE WHEN target_resolved OR target_candidate THEN year END) AS last_target_evidence_pre_year,
    MIN(CASE WHEN acquirer_resolved THEN year END)                    AS first_acquirer_resolved_pre_year
  FROM pts GROUP BY codinv, deal_id
),
last_year AS (
  SELECT codinv, deal_id, MAX(year) AS last_pre_affiliation_year
  FROM pts GROUP BY codinv, deal_id
),
latest AS (
  SELECT p.*
  FROM pts p
  JOIN last_year ly
    ON p.codinv = ly.codinv AND p.deal_id = ly.deal_id
   AND p.year   = ly.last_pre_affiliation_year
)
SELECT
  l.codinv, l.deal_id, l.cassi_deal_group_id,
  l.deal_year, l.ref_year, l.target_group, l.acquirer_group, l.status_eligible,
  l.year AS last_pre_affiliation_year,
  (l.ref_year - l.year) AS qualifying_gap   -- placebo/real-relative: event-time of last affiliation = -gap in BOTH arms
FROM latest l
JOIN summ s ON l.codinv = s.codinv AND l.deal_id = s.deal_id
WHERE (
  l.target_resolved
  OR l.target_candidate
  OR (
    l.acquirer_resolved
    AND l.year = l.ref_year - 1
    AND s.first_acquirer_resolved_pre_year = l.ref_year - 1
    AND s.last_target_evidence_pre_year IS NOT NULL
    AND s.last_target_evidence_pre_year < s.first_acquirer_resolved_pre_year
    AND l.ref_year - 1 - s.last_target_evidence_pre_year <= 2
  )
)
", shift)
}

# exposure_rank == 1 per inventor (04c's rule), ordered by (order_year, deal_id).
keep_first_exposure <- function(df, order_year_col) {
  df <- df[order(df$codinv, df[[order_year_col]], df$deal_id), ]
  df$exposure_rank <- stats::ave(seq_len(nrow(df)), df$codinv, FUN = seq_along)
  df[df$exposure_rank == 1L, , drop = FALSE]
}

# ===========================================================================
# STEP 4a: EQUIVALENCE CERTIFICATION -- membership (run first, it is the gate)
# ===========================================================================
banner("STEP 4a: MEMBERSHIP EQUIVALENCE CERTIFICATION (shift = 0)")

q0 <- DBI::dbGetQuery(con, qualify_sql(0L))
q0$codinv    <- as.numeric(q0$codinv)
q0$deal_id   <- as.integer(q0$deal_id)
q0$deal_year <- as.integer(q0$deal_year)
cert_full <- keep_first_exposure(q0, "deal_year")   # == target_cohort_own membership

# cs2021 cohort membership on the FN-eligible treated cohorts
cs_membership <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT CAST(codinv AS DOUBLE) AS codinv, CAST(deal_id AS INTEGER) AS deal_id
  FROM cs2021_estimation_panel
  WHERE deal_year BETWEEN %d AND %d", REF_LO, REF_HI))

cert_treated <- cert_full[cert_full$deal_year >= REF_LO & cert_full$deal_year <= REF_HI,
                          c("codinv", "deal_id")]

key_cert <- paste(cert_treated$codinv, cert_treated$deal_id)
key_cs   <- paste(cs_membership$codinv, cs_membership$deal_id)
only_in_new <- setdiff(key_cert, key_cs)
only_in_cs  <- setdiff(key_cs, key_cert)

cert_4a_pass <- length(only_in_new) == 0 && length(only_in_cs) == 0
cert_4a <- data.frame(
  check = "4a_membership_row_for_row",
  n_new_code = length(key_cert), n_cs2021 = length(key_cs),
  n_only_in_new_code = length(only_in_new), n_only_in_cs2021 = length(only_in_cs),
  pass = cert_4a_pass
)
write_csv_base(cert_4a, "equivalence_certification_4a_membership.csv")
message("4a membership: new-code = ", length(key_cert), " | cs2021 = ", length(key_cs),
        " | only_new = ", length(only_in_new), " | only_cs = ", length(only_in_cs),
        " | PASS = ", cert_4a_pass)
if (!cert_4a_pass) {
  stop("4a FAILED: new qualification code does not reproduce cs2021 cohort membership ",
       "row-for-row. Fix the port of 04c before proceeding (this is the gate).")
}

# ===========================================================================
# Covariate computation (shared new-code path, used for BOTH arms' IPW)
# career_first_year, predeal patent stock, group size, modal IPC section --
# mirrors 06_build_event_panel.R cohort_enriched, keyed on ref_year.
# ===========================================================================
compute_covariates <- function(units_df, label) {
  # units_df: codinv (num), deal_id (int), ref_year (int)
  duckdb::duckdb_register(con, "fn_units", units_df[, c("codinv", "deal_id", "ref_year")])
  on.exit(duckdb::duckdb_unregister(con, "fn_units"), add = TRUE)
  out <- DBI::dbGetQuery(con, "
    WITH u AS (
      SELECT CAST(codinv AS BIGINT) AS codinv, CAST(deal_id AS INTEGER) AS deal_id,
             CAST(ref_year AS INTEGER) AS ref_year
      FROM fn_units
    ),
    career AS (
      SELECT CAST(codinv AS BIGINT) AS codinv,
             MIN(year) FILTER (WHERE patent_count > 0) AS career_first_year
      FROM inventor_year GROUP BY codinv
    ),
    stock AS (
      SELECT u.codinv, u.deal_id,
             COALESCE(SUM(iy.patent_count), 0) AS predeal_patent_stock_5y
      FROM u
      LEFT JOIN inventor_year iy
        ON CAST(iy.codinv AS BIGINT) = u.codinv
       AND iy.year BETWEEN u.ref_year - 5 AND u.ref_year - 1
      GROUP BY u.codinv, u.deal_id
    ),
    grp AS (
      SELECT deal_id, COUNT(DISTINCT codinv) AS n_predeal_inventors
      FROM u GROUP BY deal_id
    ),
    ipc_sec AS (
      SELECT u.codinv, u.deal_id, SUBSTR(iy.ipc_code, 1, 1) AS ipc_section,
             SUM(iy.patent_count) AS section_patent_count
      FROM u
      LEFT JOIN inventor_ipc_year iy
        ON CAST(iy.codinv AS BIGINT) = u.codinv
       AND iy.year BETWEEN u.ref_year - 5 AND u.ref_year - 1
      WHERE iy.ipc_code IS NOT NULL
      GROUP BY u.codinv, u.deal_id, SUBSTR(iy.ipc_code, 1, 1)
    ),
    ipc_primary AS (
      SELECT codinv, deal_id, ipc_section AS ipc_primary_field
      FROM (
        SELECT codinv, deal_id, ipc_section,
               ROW_NUMBER() OVER (PARTITION BY codinv, deal_id
                                  ORDER BY section_patent_count DESC, ipc_section ASC) AS rn
        FROM ipc_sec
      ) WHERE rn = 1
    )
    SELECT u.codinv, u.deal_id, u.ref_year,
           c.career_first_year,
           u.ref_year - c.career_first_year AS career_age_at_deal,
           POWER(u.ref_year - c.career_first_year, 2) AS career_age_sq_at_deal,
           LN(1 + st.predeal_patent_stock_5y) AS log_predeal_patent_stock,
           LN(1 + g.n_predeal_inventors) AS log_group_size,
           COALESCE(ip.ipc_primary_field, 'UNKNOWN') AS ipc_primary_field
    FROM u
    LEFT JOIN career c      ON c.codinv = u.codinv
    LEFT JOIN stock st      ON st.codinv = u.codinv AND st.deal_id = u.deal_id
    LEFT JOIN grp g         ON g.deal_id = u.deal_id
    LEFT JOIN ipc_primary ip ON ip.codinv = u.codinv AND ip.deal_id = u.deal_id
  ")
  out$codinv <- as.numeric(out$codinv)
  out$deal_id <- as.integer(out$deal_id)
  message(label, ": covariates computed for ", nrow(out), " units")
  out
}

# ===========================================================================
# STEP 4b: EQUIVALENCE CERTIFICATION -- covariates (treated new-code vs cs2021)
# ===========================================================================
banner("STEP 4b: COVARIATE EQUIVALENCE CERTIFICATION")

treated_units <- unique(cert_full[cert_full$deal_year >= REF_LO & cert_full$deal_year <= REF_HI,
                                   c("codinv", "deal_id", "deal_year")])
treated_units$ref_year <- treated_units$deal_year
cov_new_treated <- compute_covariates(treated_units, "treated (new-code)")

cs_cov <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT CAST(codinv AS DOUBLE) AS codinv, CAST(deal_id AS INTEGER) AS deal_id,
         CAST(career_age_at_deal AS DOUBLE) AS career_age_at_deal,
         CAST(log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
         CAST(log_group_size AS DOUBLE) AS log_group_size,
         ipc_primary_field
  FROM cs2021_estimation_panel
  WHERE deal_year BETWEEN %d AND %d", REF_LO, REF_HI))

cmp <- merge(cov_new_treated, cs_cov, by = c("codinv", "deal_id"),
             suffixes = c("_new", "_cs"))
d_age   <- abs(cmp$career_age_at_deal_new - cmp$career_age_at_deal_cs)
d_stock <- abs(cmp$log_predeal_patent_stock_new - cmp$log_predeal_patent_stock_cs)
d_grp   <- abs(cmp$log_group_size_new - cmp$log_group_size_cs)
ipc_match_rate <- mean(cmp$ipc_primary_field_new == cmp$ipc_primary_field_cs)

cert_4b <- data.frame(
  check = "4b_covariates_within_tolerance",
  n_compared = nrow(cmp),
  max_abs_diff_career_age = max(d_age, na.rm = TRUE),
  max_abs_diff_log_stock  = max(d_stock, na.rm = TRUE),
  max_abs_diff_log_group  = max(d_grp, na.rm = TRUE),
  ipc_match_rate = ipc_match_rate,
  numeric_pass = max(c(d_age, d_stock, d_grp), na.rm = TRUE) < COV_TOL,
  ipc_pass = ipc_match_rate >= IPC_MATCH_MIN
)
cert_4b$pass <- cert_4b$numeric_pass & cert_4b$ipc_pass
write_csv_base(cert_4b, "equivalence_certification_4b_covariates.csv")
message("4b covariates: max|dcareer_age|=", signif(cert_4b$max_abs_diff_career_age, 3),
        " max|dlog_stock|=", signif(cert_4b$max_abs_diff_log_stock, 3),
        " max|dlog_group|=", signif(cert_4b$max_abs_diff_log_group, 3),
        " ipc_match=", round(ipc_match_rate, 4), " | PASS = ", cert_4b$pass)
if (!cert_4b$pass) {
  stop("4b FAILED: new-code covariates do not match cs2021 within tolerance. ",
       "The IPW propensity would read code asymmetry as imbalance. Fix before proceeding.")
}

# ===========================================================================
# CONTROL ARM: qualify at placebo date g (shift = DELTA), then filter
# ===========================================================================
banner("CONTROL ARM CONSTRUCTION (shift = DELTA = 7)")

q7 <- DBI::dbGetQuery(con, qualify_sql(DELTA))
q7$codinv    <- as.numeric(q7$codinv)
q7$deal_id   <- as.integer(q7$deal_id)
q7$deal_year <- as.integer(q7$deal_year)
q7$ref_year  <- as.integer(q7$ref_year)

# Eligible control stacks: ref_year (= placebo g) in [1993,2008]; control deal
# year Y = g+DELTA in [2000,2015]. Rank WITHIN eligible controls (the
# not-yet-treated filter below is the real cleanliness guard).
q7_elig <- q7[q7$ref_year >= REF_LO & q7$ref_year <= REF_HI &
              q7$deal_year >= (REF_LO + DELTA) & q7$deal_year <= (REF_HI + DELTA), ]
ctrl <- keep_first_exposure(q7_elig, "ref_year")
n_ctrl_prefilter <- nrow(ctrl)
message("Control candidates (post exposure-rank): ", n_ctrl_prefilter,
        " inventors across ", length(unique(ctrl$ref_year)), " stacks")

# Not-yet-treated filter: a control for stack g must have NO real acquisition
# (target_cohort_own) with deal_year in [g-5, g+6] -- i.e. untreated across the
# full observation window; their g+DELTA control deal (event-time +7) is fine.
tco <- DBI::dbGetQuery(con, "
  SELECT DISTINCT CAST(codinv AS DOUBLE) AS codinv, CAST(deal_year AS INTEGER) AS deal_year
  FROM target_cohort_own")
tco$codinv <- as.numeric(tco$codinv)

ctrl_tco <- merge(ctrl[, c("codinv", "deal_id", "ref_year")], tco, by = "codinv")
# flag any real deal inside [g-5, g+6]
ctrl_tco$in_window <- ctrl_tco$deal_year >= (ctrl_tco$ref_year - 5) &
                      ctrl_tco$deal_year <= (ctrl_tco$ref_year + DELTA - 1)
contaminated <- unique(ctrl_tco[ctrl_tco$in_window, c("codinv", "deal_id")])
# also: count controls with a real deal strictly before the window (logged only)
ctrl_tco$pre_window <- ctrl_tco$deal_year >= (ctrl_tco$ref_year - 10) &
                       ctrl_tco$deal_year <  (ctrl_tco$ref_year - 5)
n_pre_window_flag <- length(unique(paste(
  ctrl_tco$codinv[ctrl_tco$pre_window], ctrl_tco$deal_id[ctrl_tco$pre_window])))

ctrl_key <- paste(ctrl$codinv, ctrl$deal_id)
cont_key <- paste(contaminated$codinv, contaminated$deal_id)
ctrl <- ctrl[!(ctrl_key %in% cont_key), , drop = FALSE]
message("Not-yet-treated filter: dropped ", length(cont_key),
        " contaminated control units (real deal in [g-5, g+6]); ",
        n_pre_window_flag, " retained controls have a real deal in [g-10, g-6) (logged)")
message("Control units after not-yet-treated filter: ", nrow(ctrl))

nyt_filter_log <- data.frame(
  n_control_candidates = n_ctrl_prefilter,
  n_dropped_contaminated = length(cont_key),
  n_retained = nrow(ctrl),
  n_retained_with_pre_window_real_deal = n_pre_window_flag
)
write_csv_base(nyt_filter_log, "not_yet_treated_filter.csv")

# ===========================================================================
# BUILD EVENT PANELS
# ===========================================================================
banner("BUILDING STACKED EVENT PANEL")

# Inventor-year forward-citation table (patent_year aligns 1:1 with inventor_year;
# verified corr=1). fwd_cits5 = forward citations within 5y of filing, summed over
# the inventor's patents filed that year; null->0.
CITE_CTE <- "
  cite AS (
    SELECT CAST(pi.codinv AS BIGINT) AS codinv, pe.patent_year AS year,
           SUM(COALESCE(pe.fwd_cits5, 0)) AS fwd_cits5
    FROM patent_inventor pi
    JOIN patent_enriched pe ON pe.appln_id = pi.appln_id
    GROUP BY pi.codinv, pe.patent_year
  )"

# Treated arm: outcomes straight from cs2021 (membership certified) + citations.
treated_panel <- DBI::dbGetQuery(con, sprintf("
  WITH %s
  SELECT CAST(ep.codinv AS DOUBLE) AS codinv,
         CAST(ep.deal_id AS INTEGER) AS deal_id,
         CAST(ep.deal_year AS INTEGER) AS stack,
         CAST(ep.deal_year AS INTEGER) AS ref_year,
         CAST(ep.event_time AS INTEGER) AS event_time,
         CAST(ep.active_patenting AS DOUBLE) AS active_patenting,
         CAST(ep.patent_count AS DOUBLE) AS patent_count,
         CAST(ep.log_patent_count AS DOUBLE) AS log_patent_count,
         COALESCE(c.fwd_cits5, 0) AS fwd_cits5,
         LN(1 + COALESCE(c.fwd_cits5, 0)) AS log_fwd_cits5
  FROM cs2021_estimation_panel ep
  LEFT JOIN cite c ON c.codinv = CAST(ep.codinv AS BIGINT) AND c.year = ep.calendar_year
  WHERE ep.deal_year BETWEEN %d AND %d
    AND ep.event_time BETWEEN %d AND %d", CITE_CTE, REF_LO, REF_HI, EVENT_LO, EVENT_HI))
treated_panel$arm <- "treated"
treated_panel$codinv <- as.numeric(treated_panel$codinv)

# Control arm: expand to event-time grid relative to placebo g, zero-filled.
duckdb::duckdb_register(con, "ctrl_units", ctrl[, c("codinv", "deal_id", "ref_year")])
control_panel <- DBI::dbGetQuery(con, sprintf("
  WITH grid AS (SELECT * FROM range(%d, %d) t(event_time)),
  iy AS (
    SELECT CAST(codinv AS BIGINT) AS codinv, year, MAX(patent_count) AS pc
    FROM inventor_year GROUP BY codinv, year
  ),
  %s
  SELECT CAST(c.codinv AS DOUBLE) AS codinv,
         CAST(c.deal_id AS INTEGER) AS deal_id,
         CAST(c.ref_year AS INTEGER) AS stack,
         CAST(c.ref_year AS INTEGER) AS ref_year,
         CAST(g.event_time AS INTEGER) AS event_time,
         CASE WHEN COALESCE(iy.pc, 0) > 0 THEN 1.0 ELSE 0.0 END AS active_patenting,
         CAST(COALESCE(iy.pc, 0) AS DOUBLE) AS patent_count,
         LN(1 + COALESCE(iy.pc, 0)) AS log_patent_count,
         COALESCE(ct.fwd_cits5, 0) AS fwd_cits5,
         LN(1 + COALESCE(ct.fwd_cits5, 0)) AS log_fwd_cits5
  FROM ctrl_units c
  CROSS JOIN grid g
  LEFT JOIN iy ON iy.codinv = CAST(c.codinv AS BIGINT)
              AND iy.year = c.ref_year + g.event_time
  LEFT JOIN cite ct ON ct.codinv = CAST(c.codinv AS BIGINT)
              AND ct.year = c.ref_year + g.event_time",
  EVENT_LO, EVENT_HI + 1L, CITE_CTE))
duckdb::duckdb_unregister(con, "ctrl_units")
control_panel$arm <- "control"
control_panel$codinv <- as.numeric(control_panel$codinv)

# ---------------------------------------------------------------------------
# GUARDRAIL: disjoint arms within a stack. Drop any (codinv, stack) present in
# BOTH arms of the same stack -- from BOTH arms.
# ---------------------------------------------------------------------------
treated_units_key <- unique(treated_panel[, c("codinv", "stack")])
control_units_key  <- unique(control_panel[, c("codinv", "stack")])
tk <- paste(treated_units_key$codinv, treated_units_key$stack)
ck <- paste(control_units_key$codinv, control_units_key$stack)
dual_same_stack <- intersect(tk, ck)
n_dual <- length(dual_same_stack)
if (n_dual > 0) {
  tp_key <- paste(treated_panel$codinv, treated_panel$stack)
  cp_key <- paste(control_panel$codinv, control_panel$stack)
  treated_panel <- treated_panel[!(tp_key %in% dual_same_stack), , drop = FALSE]
  control_panel <- control_panel[!(cp_key %in% dual_same_stack), , drop = FALSE]
}
message("Disjoint-arms guardrail: dropped ", n_dual,
        " (codinv, stack) present in both arms of the same stack (from both arms)")
write_csv_base(data.frame(n_dual_same_stack_dropped_from_both = n_dual),
               "disjoint_arms_dropped.csv")

# ---------------------------------------------------------------------------
# NO-DOUBLE-QUALIFICATION assertion (structural): controls are qualified ONLY
# at placebo g. The qualification (qualify_sql(DELTA)) references ref_year only;
# it never conditions on the control deal's own real qualification window. This
# assertion documents that invariant: control ref_year must equal deal_year-DELTA.
ctrl_deal_map <- unique(q7[, c("deal_id", "deal_year")])
cp_check <- merge(unique(control_panel[, c("deal_id", "ref_year")]),
                  ctrl_deal_map, by = "deal_id", all.x = TRUE)
stopifnot(all(cp_check$ref_year == cp_check$deal_year - DELTA))
message("No-double-qualification: control ref_year == control_deal_year - DELTA (verified)")

# ---------------------------------------------------------------------------
# PARAMETRIC truncation assert: control rows kept only where
# event_time <= DELTA - 1 - delta. Assert parametrically for delta in {0,1}
# (no-op for -5..5 at DELTA=7); must fail loudly if a future delta drops a cell.
for (delta in c(0L, 1L)) {
  max_clean <- DELTA - 1L - delta
  if (EVENT_HI > max_clean) {
    stop(sprintf("Truncation invariant: at delta=%d, DELTA=%d controls are clean only to t<=%d, ",
                 delta, DELTA, max_clean),
         sprintf("but EVENT_HI=%d. A cell would be silently contaminated -- widen DELTA.", EVENT_HI))
  }
}
message("Parametric truncation assert: DELTA=", DELTA,
        " keeps controls clean through t=+", EVENT_HI, " for delta in {0,1} (OK)")

# ---------------------------------------------------------------------------
# Attach shared-path covariates (for IPW in 08u) to both arms
# ---------------------------------------------------------------------------
section("Attaching shared-path covariates (both arms)")
control_units_df <- unique(control_panel[, c("codinv", "deal_id", "ref_year")])
cov_control <- compute_covariates(control_units_df, "control (new-code)")
# treated covariates recomputed above (cov_new_treated); restrict to retained units
cov_treated <- cov_new_treated

covariate_cols <- c("career_age_at_deal", "career_age_sq_at_deal",
                    "log_predeal_patent_stock", "log_group_size", "ipc_primary_field")
cov_all <- rbind(
  cov_treated[, c("codinv", "deal_id", covariate_cols)],
  cov_control[, c("codinv", "deal_id", covariate_cols)]
)

# ---------------------------------------------------------------------------
# Assemble stacked panel
# ---------------------------------------------------------------------------
OUTCOME_COLS <- c("active_patenting", "patent_count", "log_patent_count",
                  "fwd_cits5", "log_fwd_cits5")
panel_cols <- c("codinv", "deal_id", "stack", "ref_year", "event_time", OUTCOME_COLS, "arm")
stacked <- rbind(treated_panel[, panel_cols], control_panel[, panel_cols])
stacked$treated <- as.integer(stacked$arm == "treated")
stacked <- merge(stacked, cov_all, by = c("codinv", "deal_id"), all.x = TRUE)
stacked <- stacked[order(stacked$stack, stacked$arm, stacked$codinv, stacked$event_time), ]

# ---------------------------------------------------------------------------
# AUDIT: cohort coverage + inventor share, gap distribution, pre-symmetry
# ---------------------------------------------------------------------------
banner("AUDIT OUTPUTS")

# Cohort coverage + inventor share of full sample
tco_all_n <- DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT codinv) AS n FROM target_cohort_own")$n
covered_treated_n <- length(unique(treated_panel$codinv))
coverage <- aggregate(
  cbind(codinv) ~ stack + arm,
  data = unique(stacked[, c("codinv", "stack", "arm")]),
  FUN = length)
names(coverage)[names(coverage) == "codinv"] <- "n_inventors"
coverage_wide <- reshape(coverage, idvar = "stack", timevar = "arm", direction = "wide")
write_csv_base(coverage_wide, "cohort_coverage.csv")

inv_share <- data.frame(
  n_treated_inventors_covered = covered_treated_n,
  n_target_cohort_own_total = tco_all_n,
  inventor_share_covered = covered_treated_n / tco_all_n,
  cohorts_covered = paste0(REF_LO, "-", REF_HI),
  cohorts_lost = paste0(REF_HI + 1L, "-2015 (no g+", DELTA, " control deal)")
)
write_csv_base(inv_share, "inventor_share_scope_condition.csv")
message("Scope: FN covers ", covered_treated_n, " / ", tco_all_n,
        " target-cohort inventors (", round(100 * covered_treated_n / tco_all_n, 1),
        "%); cohorts ", REF_LO, "-", REF_HI, ".")

# Gap distribution by arm (the non-tautological version of Diagnostic 1)
gap_treated <- merge(unique(treated_panel[, c("codinv", "deal_id")]),
                     cert_full[, c("codinv", "deal_id", "qualifying_gap")],
                     by = c("codinv", "deal_id"), all.x = TRUE)
gap_treated$arm <- "treated"
gap_control <- merge(unique(control_panel[, c("codinv", "deal_id")]),
                     q7[, c("codinv", "deal_id", "qualifying_gap")],
                     by = c("codinv", "deal_id"), all.x = TRUE)
gap_control$arm <- "control"
gap_all <- rbind(gap_treated[, c("arm", "qualifying_gap")],
                 gap_control[, c("arm", "qualifying_gap")])
gap_dist <- as.data.frame(table(arm = gap_all$arm, qualifying_gap = gap_all$qualifying_gap))
gap_dist <- reshape(gap_dist, idvar = "qualifying_gap", timevar = "arm", direction = "wide")
# add within-arm shares
gap_dist$share_treated <- gap_dist$Freq.treated / sum(gap_dist$Freq.treated, na.rm = TRUE)
gap_dist$share_control <- gap_dist$Freq.control / sum(gap_dist$Freq.control, na.rm = TRUE)
write_csv_base(gap_dist, "gap_dist_by_arm.csv")
message("Gap distribution by arm written (compare share_treated vs share_control).")
print(gap_dist)

# Pre-flight symmetry: treated vs control mean active_patenting at each tau in [-5,-1]
pre <- stacked[stacked$event_time >= -5 & stacked$event_time <= -1, ]
presym <- aggregate(active_patenting ~ event_time + arm, data = pre, FUN = mean)
presym_wide <- reshape(presym, idvar = "event_time", timevar = "arm", direction = "wide")
presym_wide$abs_diff <- abs(presym_wide$active_patenting.treated - presym_wide$active_patenting.control)
presym_wide$flag_gt_0.025 <- presym_wide$abs_diff > 0.025
write_csv_base(presym_wide, "fn_presymmetry_check.csv")
message("Pre-symmetry check (treated vs control mean active_patenting, tau in [-5,-1]):")
print(presym_wide)
if (any(presym_wide$flag_gt_0.025)) {
  message("\n*** PRE-SYMMETRY WARNING: abs_diff > 0.025 at some pre-period tau. ***")
  message("*** Classify per decision rule 1: BROAD/level-shaped divergence or a ***")
  message("*** mismatched gap distribution => bug (diagnose). A hump-shaped gap  ***")
  message("*** at tau=-3/-4 WITH matched gap distributions => this is the        ***")
  message("*** genuine-timing-selection FINDING, recorded not diagnosed away.    ***")
}

# ---------------------------------------------------------------------------
# WRITE stacked panel to parquet (register + COPY to a parquet file; no DB write)
# ---------------------------------------------------------------------------
banner("WRITING STACKED PANEL")
out_parquet <- file.path(DERIVED_PAR, "fn_stacked_panel.parquet")
duckdb::duckdb_register(con, "fn_stacked_out", stacked)
DBI::dbExecute(con, sprintf(
  "COPY (SELECT * FROM fn_stacked_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  gsub("\\\\", "/", out_parquet)))
duckdb::duckdb_unregister(con, "fn_stacked_out")
message("Written: ", out_parquet, " (", nrow(stacked), " rows, ",
        length(unique(paste(stacked$codinv, stacked$stack, stacked$arm))), " unit-stack-arms)")

banner("08t COMPLETE")
message("Certification 4a (membership): PASS")
message("Certification 4b (covariates): PASS")
message("Inspect audit CSVs in: ", AUDIT)
message("  -> equivalence_certification_4a_membership.csv / _4b_covariates.csv")
message("  -> cohort_coverage.csv, inventor_share_scope_condition.csv")
message("  -> gap_dist_by_arm.csv, fn_presymmetry_check.csv, not_yet_treated_filter.csv")
message("Then run 08u_fn_estimate_stacked.R")
