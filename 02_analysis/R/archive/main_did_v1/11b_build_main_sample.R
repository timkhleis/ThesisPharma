# ============================================================================
# 11b_build_main_sample.R -- Main DiD v1: certify treated cohort, build g+7
# future-treated controls, feasibility census, firm + inventor covariates.
# Output: parquet/derived/main_did_v1_units.parquet + audit CSVs.
# Read-only DuckDB connection; writes only parquet + audit.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
for (pkg in c("DBI", "duckdb"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({library(DBI); library(duckdb)})
set.seed(SEED)

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='8GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", gsub("\\\\", "/", DUCKDB_TMP)))

banner("MAIN DiD v1 -- SAMPLE BUILD")

# ---------------------------------------------------------------------------
# Legacy covariate path (for 4b certification only): reproduces the cs2021
# covariates keyed on ref_year, exactly as 08t compute_covariates().
# ---------------------------------------------------------------------------
compute_legacy_covariates <- function(units_df) {
  duckdb::duckdb_register(con, "leg_units", units_df[, c("codinv", "deal_id", "ref_year")])
  on.exit(duckdb::duckdb_unregister(con, "leg_units"), add = TRUE)
  DBI::dbGetQuery(con, "
    WITH u AS (SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS INTEGER) deal_id,
                      CAST(ref_year AS INTEGER) ref_year FROM leg_units),
    career AS (SELECT CAST(codinv AS BIGINT) codinv,
                 MIN(year) FILTER (WHERE patent_count>0) AS cfy FROM inventor_year GROUP BY codinv),
    stock AS (SELECT u.codinv,u.deal_id, COALESCE(SUM(iy.patent_count),0) s
                FROM u LEFT JOIN inventor_year iy ON CAST(iy.codinv AS BIGINT)=u.codinv
                 AND iy.year BETWEEN u.ref_year-5 AND u.ref_year-1 GROUP BY u.codinv,u.deal_id),
    grp AS (SELECT deal_id, COUNT(DISTINCT codinv) n FROM u GROUP BY deal_id),
    ipc_sec AS (SELECT u.codinv,u.deal_id, SUBSTR(iy.ipc_code,1,1) sec, SUM(iy.patent_count) c
                FROM u LEFT JOIN inventor_ipc_year iy ON CAST(iy.codinv AS BIGINT)=u.codinv
                 AND iy.year BETWEEN u.ref_year-5 AND u.ref_year-1
                WHERE iy.ipc_code IS NOT NULL GROUP BY u.codinv,u.deal_id,SUBSTR(iy.ipc_code,1,1)),
    ipc_primary AS (SELECT codinv,deal_id,sec ipc_primary_field FROM
                 (SELECT codinv,deal_id,sec, ROW_NUMBER() OVER(PARTITION BY codinv,deal_id
                    ORDER BY c DESC, sec ASC) rn FROM ipc_sec) WHERE rn=1)
    SELECT u.codinv,u.deal_id,
           u.ref_year - c.cfy AS career_age_at_deal,
           LN(1+st.s) AS log_predeal_patent_stock,
           LN(1+g.n)  AS log_group_size,
           COALESCE(ip.ipc_primary_field,'UNKNOWN') AS ipc_primary_field
    FROM u LEFT JOIN career c ON c.codinv=u.codinv
           LEFT JOIN stock st ON st.codinv=u.codinv AND st.deal_id=u.deal_id
           LEFT JOIN grp g ON g.deal_id=u.deal_id
           LEFT JOIN ipc_primary ip ON ip.codinv=u.codinv AND ip.deal_id=u.deal_id")
}

# ===========================================================================
# STEP 1: TREATED COHORT + 4a MEMBERSHIP CERTIFICATION (gate)
# ===========================================================================
banner("STEP 1: treated cohort + 4a membership certification")
q0 <- dbGetQuery(con, qualify_sql(0L))
q0$codinv <- as.numeric(q0$codinv); q0$deal_id <- as.integer(q0$deal_id)
q0$deal_year <- as.integer(q0$deal_year); q0$ref_year <- as.integer(q0$ref_year)
cert_full <- keep_first_exposure(q0, "deal_year")
treated <- cert_full[cert_full$deal_year >= STACK_LO & cert_full$deal_year <= STACK_HI, ]
treated$analysis_target_group_id <- as.numeric(treated$target_group)

cs_mem <- dbGetQuery(con, sprintf("
  SELECT DISTINCT CAST(codinv AS DOUBLE) codinv, CAST(deal_id AS INTEGER) deal_id
  FROM cs2021_estimation_panel WHERE deal_year BETWEEN %d AND %d", STACK_LO, STACK_HI))
key_new <- paste(treated$codinv, treated$deal_id)
key_cs  <- paste(cs_mem$codinv, cs_mem$deal_id)
only_new <- setdiff(key_new, key_cs); only_cs <- setdiff(key_cs, key_new)
pass_4a <- length(only_new) == 0 && length(only_cs) == 0
write_audit(data.frame(check = "4a_membership_row_for_row", n_new = length(key_new),
  n_cs2021 = length(key_cs), only_in_new = length(only_new), only_in_cs = length(only_cs),
  pass = pass_4a), "cohort_equivalence.csv")
message("4a membership: new=", length(key_new), " cs=", length(key_cs),
        " only_new=", length(only_new), " only_cs=", length(only_cs), " PASS=", pass_4a)
if (!pass_4a) stop("4a FAILED: treated cohort does not reproduce cs2021 membership row-for-row.")

# 4b covariate equivalence (locks the qualification+covariate port)
tu <- unique(treated[, c("codinv", "deal_id", "deal_year")]); tu$ref_year <- tu$deal_year
leg <- compute_legacy_covariates(tu)
cs_cov <- dbGetQuery(con, sprintf("
  SELECT DISTINCT CAST(codinv AS DOUBLE) codinv, CAST(deal_id AS INTEGER) deal_id,
    CAST(career_age_at_deal AS DOUBLE) career_age_at_deal,
    CAST(log_predeal_patent_stock AS DOUBLE) log_predeal_patent_stock,
    CAST(log_group_size AS DOUBLE) log_group_size, ipc_primary_field
  FROM cs2021_estimation_panel WHERE deal_year BETWEEN %d AND %d", STACK_LO, STACK_HI))
leg$codinv <- as.numeric(leg$codinv); leg$deal_id <- as.integer(leg$deal_id)
cmp <- merge(leg, cs_cov, by = c("codinv", "deal_id"), suffixes = c("_new", "_cs"))
d_age <- max(abs(cmp$career_age_at_deal_new - cmp$career_age_at_deal_cs), na.rm = TRUE)
d_stk <- max(abs(cmp$log_predeal_patent_stock_new - cmp$log_predeal_patent_stock_cs), na.rm = TRUE)
d_grp <- max(abs(cmp$log_group_size_new - cmp$log_group_size_cs), na.rm = TRUE)
ipc_match <- mean(cmp$ipc_primary_field_new == cmp$ipc_primary_field_cs)
pass_4b <- max(d_age, d_stk, d_grp) < COV_TOL && ipc_match >= IPC_MATCH_MIN
write_audit(data.frame(check = "4b_covariates", n = nrow(cmp), max_d_age = d_age,
  max_d_stock = d_stk, max_d_group = d_grp, ipc_match = ipc_match, pass = pass_4b),
  "cohort_covariate_equivalence.csv")
message("4b covariates: max|dage|=", signif(d_age,3), " max|dstock|=", signif(d_stk,3),
        " max|dgroup|=", signif(d_grp,3), " ipc_match=", round(ipc_match,4), " PASS=", pass_4b)
if (!pass_4b) stop("4b FAILED: covariate port does not match cs2021 within tolerance.")

# ===========================================================================
# STEP 2-4: CONTROL ARM (L=7) via build_control_arm (placebo group + cleanliness)
# ===========================================================================
banner("STEP 2-4: future-treated controls (L=7)")
ctl_res <- build_control_arm(con, CONTROL_LAG)
controls <- ctl_res$units
message("Controls: qualified=", ctl_res$n_qualified, " retained=", nrow(controls))

# placebo identity audit + pre-period stability
write_audit(ctl_res$identity[, c("deal_id","deal_year","placebo_g","n_placebo_groups",
  "analysis_target_group_id","placebo_status","real_target_group_at_deal")],
  "placebo_group_identity.csv")
write_audit(ctl_res$identity[, c("deal_id","placebo_g","n_distinct_preperiod_group_ids",
  "n_missing_group_years","preperiod_group_stable")], "preperiod_group_stability.csv")

# exclusion flags (non-exclusive) + priority waterfall
aq <- ctl_res$all_qualified
write_audit(aq[, c("codinv","deal_id","ref_year", ctl_res$flag_cols)], "exclusion_flags.csv")
prio <- ctl_res$exclusion_cols   # [C2] acquirer flags are diagnostic, not in the exclusion waterfall
wf_reason <- rep("retained", nrow(aq)); assigned <- rep(FALSE, nrow(aq))
for (r in prio) { hit <- aq[[r]] & !assigned; wf_reason[hit] <- r; assigned[hit] <- TRUE }
waterfall <- as.data.frame(table(reason = wf_reason))
write_audit(waterfall, "sample_waterfall.csv")

# route audit (report-first)
route_tab <- rbind(
  data.frame(arm = "treated", as.data.frame(table(route = treated$qualification_route))),
  data.frame(arm = "control", as.data.frame(table(route = controls$qualification_route))))
write_audit(route_tab, "qualification_route_audit.csv")
acq_ctrl <- sum(controls$qualification_route == "acquirer_transition")
message("Route audit: control acquirer_transition qualifiers = ", acq_ctrl,
        if (acq_ctrl > 0) "  (requires_review=TRUE, reported not gated)" else "")

# ===========================================================================
# STEP 6: FEASIBILITY CENSUS (L in {7,9}) + treated counts
# ===========================================================================
banner("STEP 6: feasibility census")
census <- list()
n_treated_by_stack <- as.data.frame(table(stack = treated$deal_year))
for (L in CENSUS_LAGS) {
  cr <- if (L == CONTROL_LAG) ctl_res else build_control_arm(con, L)
  cu <- cr$units
  cen <- data.frame(control_lag = L,
    n_treated_inventors = nrow(treated),
    n_treated_deals = length(unique(treated$deal_id)),
    n_control_qualified = cr$n_qualified,
    n_control_retained = nrow(cu),
    n_control_deals = length(unique(cu$deal_id)),
    n_excluded = cr$n_qualified - nrow(cu),
    ratio_ctrl_to_treated = round(nrow(cu) / nrow(treated), 3),
    stack_lo = cr$stack_lo, stack_hi = cr$stack_hi)
  census[[as.character(L)]] <- cen
  rs <- merge(as.data.frame(table(stack = cu$ref_year)),
              n_treated_by_stack, by = "stack", all = TRUE, suffixes = c("_control","_treated"))
  names(rs) <- c("stack","n_control","n_treated"); rs$control_lag <- L
  write_audit(rs, sprintf("risk_set_by_stack_L%d.csv", L))
}
census_df <- do.call(rbind, census)
write_audit(census_df, "delta_feasibility_census.csv")
print(census_df)
if (all(census_df$n_control_retained[census_df$control_lag == CONTROL_LAG] == 0))
  stop("L=7 has no retained controls in any stack -- stop for design decision.")

# funnel
funnel <- data.frame(
  stage = c("treated_qualified", "control_qualified_L7", "control_retained_L7"),
  n_inventors = c(nrow(treated), ctl_res$n_qualified, nrow(controls)))
write_audit(funnel, "sample_funnel.csv")

# ===========================================================================
# STEP 7-8: FIRM + INVENTOR COVARIATES (both arms) on the analysis entity
# ===========================================================================
banner("STEP 7-8: covariates")

# assemble unit table (one row per codinv x deal x arm)
mk_units <- function(df, arm) {
  data.frame(codinv = as.numeric(df$codinv), focal_deal_id = as.integer(df$deal_id),
    analysis_target_group_id = as.numeric(df$analysis_target_group_id),
    stack = as.integer(df$ref_year), real_deal_year = as.integer(df$deal_year),
    placebo_year = as.integer(df$ref_year), arm = arm,
    treated = as.integer(arm == "treated"),
    qualifying_gap = as.integer(df$qualifying_gap),
    qualification_route = df$qualification_route,
    last_pre_affiliation_year = as.integer(df$last_pre_affiliation_year))
}
units <- rbind(mk_units(treated, "treated"), mk_units(controls, "control"))
units$future_control_deal_id <- ifelse(units$arm == "control", units$focal_deal_id, NA_integer_)
message("Units assembled: ", nrow(units), " (treated=", sum(units$treated),
        ", control=", sum(1 - units$treated), ")")

# ---- FIRM covariates keyed on (focal_deal_id, analysis_target_group_id, stack, arm) ----
firm_keys <- unique(units[, c("focal_deal_id", "analysis_target_group_id", "stack", "arm")])
firm_keys$fk_id <- seq_len(nrow(firm_keys))
duckdb::duckdb_register(con, "firm_keys", firm_keys[, c("fk_id","focal_deal_id",
  "analysis_target_group_id","stack")])
fam_case <- ipc_family_case_sql("ipc.ipc_code")
firm_cov <- dbGetQuery(con, sprintf("
  WITH fk AS (SELECT fk_id, CAST(focal_deal_id AS INTEGER) deal_id,
                     CAST(analysis_target_group_id AS DOUBLE) grp, CAST(stack AS INTEGER) g FROM firm_keys),
  pat AS (   -- distinct firm patents through g-3
    SELECT fk.fk_id, fk.g, pcl.appln_id, MIN(pcl.year) AS yr
    FROM fk JOIN patent_company_link pcl ON pcl.id_group = fk.grp AND pcl.year <= fk.g - 3
    GROUP BY fk.fk_id, fk.g, pcl.appln_id),
  pstat AS (
    SELECT fk_id,
      COUNT(*) AS stock,
      MIN(yr) AS first_year,
      COUNT(*) FILTER (WHERE yr BETWEEN g-6 AND g-5) AS early,
      COUNT(*) FILTER (WHERE yr BETWEEN g-4 AND g-3) AS recent,
      COUNT(*) FILTER (WHERE yr BETWEEN g-6 AND g-3) AS win_patents
    FROM pat GROUP BY fk_id),
  invc AS (   -- unique inventors at firm over [g-6,g-3]
    SELECT fk.fk_id, COUNT(DISTINCT pi.codinv) AS n_inv
    FROM fk JOIN patent_company_link pcl ON pcl.id_group=fk.grp AND pcl.year BETWEEN fk.g-6 AND fk.g-3
            JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
    GROUP BY fk.fk_id),
  famrows AS (   -- distinct (appln, family) over [g-6,g-3]
    SELECT DISTINCT fk.fk_id, pcl.appln_id, %s AS fam
    FROM fk JOIN patent_company_link pcl ON pcl.id_group=fk.grp AND pcl.year BETWEEN fk.g-6 AND fk.g-3
            JOIN ipc ON ipc.appln_id = pcl.appln_id),
  kcnt AS (SELECT fk_id, appln_id, COUNT(*) AS k FROM famrows GROUP BY fk_id, appln_id),
  alloc AS (SELECT fr.fk_id, fr.fam, SUM(1.0/kc.k) AS w
            FROM famrows fr JOIN kcnt kc ON kc.fk_id=fr.fk_id AND kc.appln_id=fr.appln_id
            GROUP BY fr.fk_id, fr.fam),
  tot AS (SELECT fk_id, SUM(w) tot FROM alloc GROUP BY fk_id),
  shares AS (
    SELECT a.fk_id,
      SUM(CASE WHEN a.fam='small_molecule' THEN a.w ELSE 0 END)/MAX(t.tot) AS share_small_molecule,
      SUM(CASE WHEN a.fam='biotech'        THEN a.w ELSE 0 END)/MAX(t.tot) AS share_biotech,
      SUM(CASE WHEN a.fam='formulation'    THEN a.w ELSE 0 END)/MAX(t.tot) AS share_formulation
    FROM alloc a JOIN tot t ON t.fk_id=a.fk_id GROUP BY a.fk_id)
  SELECT fk.fk_id, fk.g,
    COALESCE(ps.stock,0) AS firm_patent_stock,
    COALESCE(ps.first_year, NULL) AS firm_first_year,
    COALESCE(ps.early,0) AS patents_early, COALESCE(ps.recent,0) AS patents_recent,
    COALESCE(ps.win_patents,0) AS win_patents,
    COALESCE(ic.n_inv,0) AS firm_inventor_count,
    sh.share_small_molecule, sh.share_biotech, sh.share_formulation
  FROM fk LEFT JOIN pstat ps ON ps.fk_id=fk.fk_id
          LEFT JOIN invc ic ON ic.fk_id=fk.fk_id
          LEFT JOIN shares sh ON sh.fk_id=fk.fk_id", fam_case))
duckdb::duckdb_unregister(con, "firm_keys")

# derive firm covariates + structural no-history indicators [B2]
firm_cov$no_firm_patent_by_g3 <- as.integer(firm_cov$firm_patent_stock == 0)
firm_cov$no_technology_activity_g6_g3 <- as.integer(firm_cov$win_patents == 0 |
  is.na(firm_cov$share_small_molecule))
firm_cov$log_firm_patent_stock  <- log1p(firm_cov$firm_patent_stock)
firm_cov$log_firm_inventor_count <- log1p(firm_cov$firm_inventor_count)
firm_cov$log_patents_early  <- log1p(firm_cov$patents_early)
firm_cov$log_patents_recent <- log1p(firm_cov$patents_recent)
firm_cov$observed_firm_patent_age <- ifelse(firm_cov$no_firm_patent_by_g3 == 1L, 0,
  (firm_cov$g - 3) - firm_cov$firm_first_year)
for (s in TECH_SHARE_COLS) firm_cov[[s]][is.na(firm_cov[[s]])] <- 0   # no-tech -> 0 (flagged)
firm_cov <- merge(firm_keys, firm_cov, by = "fk_id")

# ---- INVENTOR covariates over [g-5,g-1] (B1: full pre-window) ----
duckdb::duckdb_register(con, "inv_units", unique(units[, c("codinv","focal_deal_id","stack",
  "analysis_target_group_id")]))
inv_fam_case <- ipc_family_case_sql("iiy.ipc_code")
inv_cov <- dbGetQuery(con, sprintf("
  WITH u AS (SELECT CAST(codinv AS BIGINT) codinv, CAST(focal_deal_id AS INTEGER) deal_id,
                    CAST(stack AS INTEGER) g, CAST(analysis_target_group_id AS DOUBLE) grp FROM inv_units),
  career AS (SELECT CAST(codinv AS BIGINT) codinv, MIN(year) FILTER (WHERE patent_count>0) cfy
             FROM inventor_year GROUP BY codinv),
  stock AS (SELECT u.codinv,u.deal_id,u.g, COALESCE(SUM(iy.patent_count),0) s
            FROM u LEFT JOIN inventor_year iy ON CAST(iy.codinv AS BIGINT)=u.codinv
             AND iy.year BETWEEN u.g-5 AND u.g-1 GROUP BY u.codinv,u.deal_id,u.g),
  tenure AS (SELECT u.codinv,u.deal_id,u.g, MIN(ia.year) first_aff
             FROM u JOIN inventor_affiliation_own ia ON ia.codinv=u.codinv AND ia.year<=u.g-1
              AND (ia.resolved_group=u.grp OR list_contains(string_split(ia.candidate_group_list,';'),
                   CAST(CAST(u.grp AS BIGINT) AS VARCHAR)))
             GROUP BY u.codinv,u.deal_id,u.g),
  excl AS (   -- target exclusivity over [g-5,g-1]: distinct target-linked / distinct total
    SELECT u.codinv,u.deal_id,u.g,
      COUNT(DISTINCT CASE WHEN pcl.id_group=u.grp THEN pi.appln_id END) AS n_target,
      COUNT(DISTINCT pi.appln_id) AS n_total
    FROM u JOIN patent_inventor pi ON pi.codinv=u.codinv
           JOIN patent_company_link pcl ON pcl.appln_id=pi.appln_id
            AND pcl.year BETWEEN u.g-5 AND u.g-1
    GROUP BY u.codinv,u.deal_id,u.g),
  fam AS (SELECT u.codinv,u.deal_id,u.g, %s AS fam, SUM(iiy.patent_count) c
          FROM u JOIN inventor_ipc_year iiy ON CAST(iiy.codinv AS BIGINT)=u.codinv
           AND iiy.year BETWEEN u.g-5 AND u.g-1
          GROUP BY u.codinv,u.deal_id,u.g, %s),
  modal AS (SELECT codinv,deal_id,g,fam modal_family FROM
            (SELECT codinv,deal_id,g,fam, ROW_NUMBER() OVER(PARTITION BY codinv,deal_id,g
               ORDER BY c DESC,
                 CASE fam WHEN 'small_molecule' THEN 1 WHEN 'biotech' THEN 2
                          WHEN 'formulation' THEN 3 ELSE 4 END) rn FROM fam) WHERE rn=1)
  SELECT u.codinv, u.deal_id, u.g AS stack,
    (u.g-1) - c.cfy AS observed_inventor_career_age,
    (u.g-1) - te.first_aff AS observed_target_patent_tenure,
    LN(1 + st.s) AS log_inventor_patent_stock,
    CASE WHEN ex.n_total>0 THEN CAST(ex.n_target AS DOUBLE)/ex.n_total ELSE NULL END AS target_exclusivity,
    COALESCE(md.modal_family,'other') AS modal_family
  FROM u LEFT JOIN career c ON c.codinv=u.codinv
         LEFT JOIN stock st ON st.codinv=u.codinv AND st.deal_id=u.deal_id AND st.g=u.g
         LEFT JOIN tenure te ON te.codinv=u.codinv AND te.deal_id=u.deal_id AND te.g=u.g
         LEFT JOIN excl ex ON ex.codinv=u.codinv AND ex.deal_id=u.deal_id AND ex.g=u.g
         LEFT JOIN modal md ON md.codinv=u.codinv AND md.deal_id=u.deal_id AND md.g=u.g",
  inv_fam_case, inv_fam_case))
duckdb::duckdb_unregister(con, "inv_units")
inv_cov$codinv <- as.numeric(inv_cov$codinv); inv_cov$deal_id <- as.integer(inv_cov$deal_id)
inv_cov$stack <- as.integer(inv_cov$stack)

# ---- attach covariates to units ----
units <- merge(units, firm_cov[, c("focal_deal_id","analysis_target_group_id","stack","arm",
  FIRM_COVARS)], by = c("focal_deal_id","analysis_target_group_id","stack","arm"), all.x = TRUE)
units <- merge(units, inv_cov, by.x = c("codinv","focal_deal_id","stack"),
  by.y = c("codinv","deal_id","stack"), all.x = TRUE)

# qualifying-gap categorical [0,1,2,3+]
units$qualifying_gap_cat <- factor(pmin(units$qualifying_gap, 3L),
  levels = 0:3, labels = c("gap0","gap1","gap2","gap3plus"))
units$modal_family <- factor(units$modal_family, levels = TECH_FAMILIES)

# firm-stage sampling weight = number of qualifying inventors in the firm-stage cell
fk_n <- aggregate(codinv ~ focal_deal_id + analysis_target_group_id + stack + arm,
  data = units, FUN = length)
names(fk_n)[5] <- "n_qualifying_inventors"
units <- merge(units, fk_n, by = c("focal_deal_id","analysis_target_group_id","stack","arm"))

# ---- covariate missingness audit [A6] ----
cov_all <- c(FIRM_COVARS, INV_COVARS)
miss <- do.call(rbind, lapply(cov_all, function(v) {
  data.frame(covariate = v, level = if (v %in% FIRM_COVARS) "firm" else "inventor",
    n_missing_treated = sum(is.na(units[[v]][units$treated==1])),
    n_missing_control = sum(is.na(units[[v]][units$treated==0])))
}))
write_audit(miss, "covariate_missingness.csv")
print(miss)

# ---- technology-profile-by-year audit ----
tech_year <- dbGetQuery(con, sprintf("
  WITH fr AS (SELECT DISTINCT pcl.year, pcl.appln_id, %s AS fam
              FROM patent_company_link pcl JOIN ipc ON ipc.appln_id=pcl.appln_id
              WHERE pcl.year BETWEEN 1988 AND 2015),
  kc AS (SELECT year,appln_id,COUNT(*) k FROM fr GROUP BY year,appln_id),
  al AS (SELECT fr.year,fr.fam,SUM(1.0/kc.k) w FROM fr JOIN kc ON kc.year=fr.year AND kc.appln_id=fr.appln_id GROUP BY fr.year,fr.fam)
  SELECT year, fam, w, SUM(w) OVER (PARTITION BY year) AS tot FROM al ORDER BY year, fam", fam_case))
tech_year$share <- tech_year$w / tech_year$tot
write_audit(tech_year[, c("year","fam","share")], "technology_profile_by_year.csv")

# ---- design invariants manifest [A9] ----
write_audit(data.frame(
  invariant = c("no_stayer_restriction","no_post_treatment_status_in_selection",
                "no_outcome_based_drop","no_legacy_dealyear_clipping",
                "inventor_covariates_full_g5_g1_window","control_only_designated_gplus7"),
  implementation_location = c("11b qualify_sql/build_control_arm","11b (no status join)",
    "11b (no outcome filter)","11b (fresh event grid in 11d)","11b inv_cov [g-5,g-1]",
    "11b build_control_arm cleanliness"),
  verification_method = rep("code_review", 6),
  status = rep("verified", 6)), "design_invariants.csv")

# ===========================================================================
# WRITE UNIT TABLE
# ===========================================================================
banner("Writing units parquet")
duckdb::duckdb_register(con, "units_out", units)
dbExecute(con, sprintf("COPY (SELECT * FROM units_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  gsub("\\\\", "/", UNITS_PARQUET)))
duckdb::duckdb_unregister(con, "units_out")
message("Wrote ", UNITS_PARQUET, " (", nrow(units), " rows)")
banner("11b DONE")
