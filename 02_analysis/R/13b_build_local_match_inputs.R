# ============================================================================
# 13b_build_local_match_inputs.R  -- design version local_match_v1 (v2 spine)
# ----------------------------------------------------------------------------
# Builds outcome-blind matching inputs on the AUTHORITATIVE company-level
# treatment-assignment spine (04c_build_prelim_own_status.R). The old
# deal_map / inventor_status_reference / group-level qualification is NOT used
# for the primary treated path.
#
#   Treated (LM_SAMPLE):
#     strict   -> qualify_sql(0, cassi_deal_group_spine)          [PRIMARY, company-level]
#     expanded -> qualify_sql(0, cassi_deal_group_spine_expanded) [sensitivity]
#     group    -> target_cohort_group_sensitivity                  [OLD group sensitivity]
#   First-exposure retained (earliest acquisition exposure only).
#   Strict treated is verified to AGREE with target_cohort_own.
#
#   Donor "ever-target" screen (same broad screen for every sample mode):
#     company-level identities from deal_target_company_EXPANDED (strict +
#     unambiguous supplementary), propagated across the FULL firm_group
#     (compcod,year,id_group) lineage -- not a single-year snapshot, and
#     including target identities outside the estimation window. target-drop /
#     divestiture / ambiguous / unresolved records are tracked SEPARATELY and
#     reported (not silently treated as untreated). firm_group.merger_status is
#     a diagnostic cross-check only.
#
#   Acquisition year = target_year everywhere. acqui_year never used.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R")); use_project_library()
source(file.path(BASE, "R", "13a_local_match_config.R"))
source(file.path(BASE, "R", "archive", "main_did_v1", "11_main_design_utils.R"))    # functions only (authoritative qualify_sql)
source(file.path(BASE, "R", "13_local_match_utils.R"))
set.seed(SEED)
args <- commandArgs(trailingOnly = TRUE)
COHORTS_ARG <- if (length(args) > 0) as.integer(args) else PILOT_COHORTS
lm_section(sprintf("building inputs for cohorts %s  (sample='%s', tag='%s')",
                   paste(COHORTS_ARG, collapse = "/"), LM_SAMPLE, LM_TAG))

t0  <- Sys.time()
con <- lm_connect()
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

# ---------------------------------------------------------------------------
# (1) Treated cohort -- authoritative company-level qualification + first-exposure
# ---------------------------------------------------------------------------
lm_banner(sprintf("Treated cohort (sample='%s', company-level)", LM_SAMPLE))
if (LM_SAMPLE == "group") {
  # OLD corporate-group sensitivity definition (kept ONLY as a labelled sensitivity)
  cert <- dbGetQuery(con, sprintf("
    SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id,
           CAST(deal_year AS INTEGER) deal_year,
           CAST(target_group AS DOUBLE) target_group,
           CAST(acquirer_group AS DOUBLE) acquirer_group,
           status_eligible,
           target_assignment_rule AS qualification_route
    FROM %s", TBL_GROUP_SENS))
} else {
  spine <- if (LM_SAMPLE == "expanded") TBL_SPINE_EXPANDED else TBL_SPINE_STRICT
  q0 <- dbGetQuery(con, qualify_sql(0L, spine))            # company-level (target_compcod join)
  q0$deal_year <- as.integer(q0$deal_year)
  cert <- q0[, c("codinv","deal_id","deal_year","target_group","acquirer_group",
                 "status_eligible","qualification_route")]
}
cert <- keep_first_exposure(cert, "deal_year")             # earliest acquisition exposure only
cert$sample_definition <- LM_SAMPLE

# --- verify strict treated AGREES with target_cohort_own at INVENTOR-DEAL level ---
# (codinv, deal_id, deal_year, target_group) both directions -- IDs alone can hide
# a wrong-deal assignment.
if (LM_SAMPLE == "strict") {
  own <- dbGetQuery(con, sprintf("
    SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id,
           CAST(deal_year AS INTEGER) deal_year, CAST(target_group AS DOUBLE) target_group
    FROM %s", TBL_TARGET_COHORT))
  m <- merge(cert[, c("codinv","deal_id","deal_year","target_group")], own,
             by = "codinv", all = TRUE, suffixes = c("_mine","_own"))
  only_mine <- sum(is.na(m$deal_id_own))
  only_own  <- sum(is.na(m$deal_id_mine))
  both <- m[!is.na(m$deal_id_own) & !is.na(m$deal_id_mine), ]
  dis_deal  <- sum(both$deal_id_mine    != both$deal_id_own,    na.rm = TRUE)
  dis_year  <- sum(both$deal_year_mine  != both$deal_year_own,  na.rm = TRUE)
  dis_group <- sum(!is.na(both$target_group_mine) & !is.na(both$target_group_own) &
                   both$target_group_mine != both$target_group_own)
  recon <- data.frame(only_in_construction = only_mine, only_in_authoritative = only_own,
                      deal_id_disagreements = dis_deal, deal_year_disagreements = dis_year,
                      target_group_disagreements = dis_group)
  print(recon)
  lm_write_csv(recon, AUDIT_DIR, "inventor_deal_reconciliation")
  lm_assert(only_mine == 0 && only_own == 0 && dis_deal == 0 && dis_year == 0 && dis_group == 0,
            "strict (codinv,deal_id,deal_year,target_group) AGREES with target_cohort_own")
}

treated_full <- cert[cert$deal_year %in% FULL_COHORTS, ]
treated      <- cert[cert$deal_year %in% COHORTS_ARG, ]
treated$g    <- treated$deal_year
lm_section(sprintf("treated: %d inventors across %d deals in cohorts %s",
                   nrow(treated), length(unique(treated$deal_id)), paste(COHORTS_ARG, collapse="/")))

# ---------------------------------------------------------------------------
# (2) Authoritative M&A history + benchmark reconciliation (deal_assignment)
# ---------------------------------------------------------------------------
lm_banner("M&A history + benchmark reconciliation (deal_assignment)")
da <- dbGetQuery(con, sprintf("
  SELECT CAST(deal_id AS BIGINT) deal_id, match_source,
         strict_eligible, expanded_eligible, status_eligible, manual_review,
         CAST(target_year AS INTEGER) target_year,
         CAST(target_group AS DOUBLE) target_group,
         CAST(acquirer_group AS DOUBLE) acquirer_group,
         todrop_tar, divest, n_target_groups
  FROM %s", TBL_DEAL_ASSIGN))
bench <- data.frame(
  merger_list_deals      = nrow(da),
  direct_TARGET_EVENT_ID = sum(da$match_source == "TARGET_EVENT_ID"),
  supplementary_MERGE_ID = sum(da$match_source == "MERGE_ID_SUPPLEMENT"),
  unresolved             = sum(grepl("^UNRESOLVED", da$match_source)),
  strict_assigned        = sum(da$strict_eligible),
  expanded_assigned      = sum(da$expanded_eligible),
  listed_1993_2010       = sum(da$target_year >= 1993 & da$target_year <= 2010, na.rm = TRUE),
  strict_1993_2010       = sum(da$strict_eligible & da$target_year >= 1993 & da$target_year <= 2010, na.rm = TRUE))
print(bench)
lm_write_csv(bench, AUDIT_DIR, "benchmark_reconciliation")
lm_assert(bench$merger_list_deals == 513 && bench$direct_TARGET_EVENT_ID == 496 &&
          bench$supplementary_MERGE_ID == 13 && bench$unresolved == 4 &&
          bench$strict_assigned == 484 && bench$expanded_assigned == 490,
          "deal_assignment reconciles to full-list benchmarks (513/496/13/4/484/490)")
lm_assert(bench$listed_1993_2010 == 372 && bench$strict_1993_2010 == 350,
          "deal_assignment reconciles to 1993-2010 benchmarks (372 listed / 350 strict)")

# consolidated matching-sample waterfall: every sample restriction, explicit
waterfall <- data.frame(
  step = c("merger_list_deals", "strict_assigned_deals", "expanded_assigned_deals",
           sprintf("%s_qualified_inventors_all_years", LM_SAMPLE),
           sprintf("%s_qualified_deals_all_years", LM_SAMPLE),
           sprintf("cohort_window_%d_%d_inventors", min(FULL_COHORTS), max(FULL_COHORTS)),
           sprintf("cohort_window_%d_%d_deals", min(FULL_COHORTS), max(FULL_COHORTS)),
           "this_run_cohort_inventors", "this_run_cohort_deals"),
  n = c(bench$merger_list_deals, bench$strict_assigned, bench$expanded_assigned,
        length(unique(cert$codinv)), length(unique(cert$deal_id)),
        nrow(treated_full), length(unique(treated_full$deal_id)),
        nrow(treated), length(unique(treated$deal_id))))
print(waterfall)
lm_write_csv(waterfall, AUDIT_DIR, "matching_sample_waterfall")

# acquirer events (for the full-window acquirer-clean donor rule) -- resolved, non-999
acq_ev <- dbGetQuery(con, sprintf("
  SELECT CAST(acquirer_group AS DOUBLE) acquirer_group, CAST(target_year AS INTEGER) target_year
  FROM %s WHERE acquirer_group IS NOT NULL AND CAST(acquirer_group AS VARCHAR) NOT LIKE '999%%'",
  TBL_DEAL_ASSIGN))
lm_write_parquet(con, da, LM_MAHISTORY_PARQUET)

# ---------------------------------------------------------------------------
# (2b) Ever-target donor screen -- EVENT-SPECIFIC PRE-DEAL target group (Fix 1)
# ---------------------------------------------------------------------------
lm_banner("Ever-target donor screen (event-specific pre-deal target group)")
# PRIMARY (predeal): for each expanded-eligible deal, the target company's group
# observed ONLY in the pre-deal window [g-5, g-1]. No post-deal propagation, so a
# target company that later joins the acquirer group does NOT taint that acquirer.
tgt_deals <- dbGetQuery(con, sprintf("
  WITH dtc AS (
    SELECT dtc.deal_id, CAST(dtc.target_compcod AS DOUBLE) compcod, CAST(da.target_year AS INTEGER) g
    FROM %s dtc JOIN %s da ON da.deal_id = dtc.deal_id
    WHERE da.expanded_eligible AND da.target_year IS NOT NULL)
  SELECT DISTINCT CAST(fg.id_group AS DOUBLE) id_group, dtc.deal_id, dtc.g AS target_year
  FROM dtc JOIN firm_group fg ON CAST(fg.compcod AS DOUBLE) = dtc.compcod
   AND fg.year BETWEEN dtc.g - 5 AND dtc.g - 1
  WHERE fg.id_group IS NOT NULL", TBL_DTC_EXPANDED, TBL_DEAL_ASSIGN))
ever_predeal <- sort(unique(tgt_deals$id_group))
# ROBUSTNESS (allyear): target company through firm_group over ALL years (also
# sweeps in acquirer groups via post-deal ownership) -- separately labelled only.
ever_allyear <- sort(unique(dbGetQuery(con, sprintf("
  WITH tc AS (SELECT DISTINCT CAST(target_compcod AS DOUBLE) compcod FROM %s)
  SELECT DISTINCT CAST(fg.id_group AS DOUBLE) id_group FROM tc
  JOIN firm_group fg ON CAST(fg.compcod AS DOUBLE) = tc.compcod
  WHERE fg.id_group IS NOT NULL", TBL_DTC_EXPANDED))$id_group))
ever_target_groups <- if (LM_DONOR_SCREEN == "allyear") ever_allyear else ever_predeal

# observed acquirer groups (resolved, non-999) and target-acquirer overlap
acq_groups <- sort(unique(acq_ev$acquirer_group))
overlap    <- intersect(ever_predeal, acq_groups)
recovered  <- setdiff(ever_allyear, ever_predeal)   # donor groups recovered vs all-year screen

# case-level overlap explanation: for each overlap group, deals where it is a
# pre-deal TARGET vs deals where it is an ACQUIRER (overlap must be a real target event)
acq_deals <- dbGetQuery(con, sprintf("
  SELECT CAST(acquirer_group AS DOUBLE) id_group, CAST(deal_id AS BIGINT) deal_id, target_year
  FROM %s WHERE acquirer_group IS NOT NULL AND CAST(acquirer_group AS VARCHAR) NOT LIKE '999%%'",
  TBL_DEAL_ASSIGN))
paste_deals <- function(df, grp) {
  df <- df[df$id_group %in% grp, ]
  if (!nrow(df)) return(data.frame(id_group = numeric(0), deals = character(0)))
  aggregate(deal_id ~ id_group, df, function(x) paste(sort(unique(x)), collapse = ";"))
}
ov_expl <- if (length(overlap)) {
  a <- paste_deals(tgt_deals, overlap); names(a)[2] <- "deals_as_target"
  b <- paste_deals(acq_deals, overlap); names(b)[2] <- "deals_as_acquirer"
  merge(a, b, by = "id_group", all = TRUE)
} else data.frame(id_group = numeric(0), deals_as_target = character(0), deals_as_acquirer = character(0))
lm_write_csv(ov_expl, AUDIT_DIR, "target_acquirer_overlap_cases")

# drop/divest company lineages (pre-deal window; screen-sensitivity flag only)
dd_groups <- sort(unique(dbGetQuery(con, sprintf("
  WITH dd AS (SELECT DISTINCT TRIM(x) c, CAST(target_year AS INTEGER) g FROM %s,
                UNNEST(string_split(target_compcod_list, ';')) AS t(x)
              WHERE (todrop_tar OR divest) AND target_compcod_list IS NOT NULL AND TRIM(x) <> ''
                AND target_year IS NOT NULL)
  SELECT DISTINCT CAST(fg.id_group AS DOUBLE) id_group
  FROM dd JOIN firm_group fg ON CAST(fg.compcod AS DOUBLE) = CAST(dd.c AS DOUBLE)
   AND fg.year BETWEEN dd.g - 5 AND dd.g - 1
  WHERE fg.id_group IS NOT NULL", TBL_DEAL_ASSIGN))$id_group))
dd_only <- setdiff(dd_groups, ever_target_groups)
fg_target_groups <- dbGetQuery(con,
  "SELECT COUNT(DISTINCT id_group) n FROM firm_group WHERE merger_status = 'target'")$n
donor_hist <- data.frame(
  donor_screen                 = LM_DONOR_SCREEN,
  ever_target_predeal          = length(ever_predeal),
  ever_target_allyear          = length(ever_allyear),
  donors_recovered_vs_allyear  = length(recovered),
  observed_acquirer_groups     = length(acq_groups),
  acquirers_in_predeal_screen  = length(intersect(acq_groups, ever_predeal)),
  acquirers_in_allyear_screen  = length(intersect(acq_groups, ever_allyear)),
  target_acquirer_overlap      = length(overlap),
  dropdivest_lineage_groups    = length(dd_groups),
  dropdivest_only_extra_groups = length(dd_only),
  unresolved_ambiguous_deals   = sum(grepl("^UNRESOLVED", da$match_source)),
  firm_group_merger_status_target_DIAGNOSTIC = fg_target_groups)
print(donor_hist)
lm_write_csv(donor_hist, AUDIT_DIR, "donor_history_audit")

# ---------------------------------------------------------------------------
# (3) Control firm pool (never-target + full-window acquirer-clean) + covariates
# ---------------------------------------------------------------------------
lm_banner("Control firm pool + firm covariates")
firm_covar_sql <- "
  WITH k AS (SELECT CAST(id_group AS DOUBLE) grp, CAST(g AS INTEGER) g FROM fkeys),
  pat AS (SELECT k.grp, k.g, pcl.appln_id, MIN(pcl.year) yr
          FROM k JOIN patent_company_link pcl
            ON pcl.id_group = k.grp AND pcl.year BETWEEN k.g-5 AND k.g-1
          GROUP BY k.grp, k.g, pcl.appln_id),
  pc AS (SELECT grp, g, COUNT(*) stock,
           COUNT(*) FILTER (WHERE yr BETWEEN g-5 AND g-3) early,
           COUNT(*) FILTER (WHERE yr BETWEEN g-2 AND g-1) recent
         FROM pat GROUP BY grp, g),
  ic AS (SELECT k.grp, k.g, COUNT(DISTINCT pi.codinv) n_inv
         FROM k JOIN patent_company_link pcl
           ON pcl.id_group = k.grp AND pcl.year BETWEEN k.g-5 AND k.g-1
                JOIN patent_inventor pi ON pi.appln_id = pcl.appln_id
         GROUP BY k.grp, k.g)
  SELECT k.grp AS id_group, k.g AS g,
         COALESCE(pc.stock,0) AS stock, COALESCE(pc.early,0) AS early,
         COALESCE(pc.recent,0) AS recent, COALESCE(ic.n_inv,0) AS n_inv
  FROM k LEFT JOIN pc ON pc.grp=k.grp AND pc.g=k.g
         LEFT JOIN ic ON ic.grp=k.grp AND ic.g=k.g"
add_firm_covars <- function(df) {
  df$log_patent_stock_5y   <- log1p(df$stock)
  df$log_inventor_count_5y <- log1p(df$n_inv)
  df$patent_trajectory     <- log1p(df$recent / 2) - log1p(df$early / 3)  # annualized
  df
}
firm_pool_list <- list(); treated_firm_list <- list()
for (g in COHORTS_ARG) {
  acq_win <- unique(acq_ev$acquirer_group[acq_ev$target_year >= g + EVENT_LO &
                                          acq_ev$target_year <= g + EVENT_HI])
  duckdb::duckdb_register(con, "ever_t", data.frame(id_group = ever_target_groups))
  duckdb::duckdb_register(con, "acq_w",  data.frame(id_group = if (length(acq_win)) acq_win else -1))
  elig <- dbGetQuery(con, sprintf("
    WITH win AS (SELECT DISTINCT CAST(id_group AS DOUBLE) id_group
                 FROM patent_company_link
                 WHERE year BETWEEN %1$d AND %2$d AND id_group IS NOT NULL)
    SELECT w.id_group, %3$d AS g FROM win w
    WHERE w.id_group NOT IN (SELECT id_group FROM ever_t)
      AND w.id_group NOT IN (SELECT id_group FROM acq_w)", g + QUAL_LO, g + QUAL_HI, g))
  duckdb::duckdb_unregister(con, "ever_t"); duckdb::duckdb_unregister(con, "acq_w")
  duckdb::duckdb_register(con, "fkeys", data.frame(id_group = elig$id_group, g = g))
  fc <- dbGetQuery(con, firm_covar_sql); duckdb::duckdb_unregister(con, "fkeys")
  fc <- add_firm_covars(fc); fc <- fc[fc$stock > 0, ]
  fc$cohort <- g; fc$role <- "control"
  fc$in_dropdivest_lineage <- as.integer(fc$id_group %in% dd_only)   # screen-sensitivity flag
  firm_pool_list[[as.character(g)]] <- fc

  tg <- unique(treated$target_group[treated$g == g & is.finite(treated$target_group)])
  duckdb::duckdb_register(con, "fkeys", data.frame(id_group = tg, g = g))
  tfc <- dbGetQuery(con, firm_covar_sql); duckdb::duckdb_unregister(con, "fkeys")
  tfc <- add_firm_covars(tfc); tfc$cohort <- g; tfc$role <- "treated"
  treated_firm_list[[as.character(g)]] <- tfc
  lm_section(sprintf("cohort %d: %d eligible control firms (%d in drop/divest lineage); %d treated firms; %d acquirer exclusions",
                     g, nrow(fc), sum(fc$in_dropdivest_lineage), nrow(tfc), length(acq_win)))
}
firm_pool    <- do.call(rbind, firm_pool_list)
treated_firm <- do.call(rbind, treated_firm_list)
lm_write_parquet(con, firm_pool,    LM_FIRMPOOL_PARQUET)
lm_write_parquet(con, treated_firm, LM_TREATED_FIRM_PARQUET)

# ---------------------------------------------------------------------------
# (4) Treated inventor covariates (certified helper + trajectory + family)
# ---------------------------------------------------------------------------
lm_banner("Treated inventor covariates")
inv_keys <- data.frame(codinv = treated$codinv, g = treated$g, grp = treated$target_group)
tcov <- compute_inventor_covariates(con, inv_keys)
duckdb::duckdb_register(con, "ik", inv_keys[, c("codinv","g")])
traj <- dbGetQuery(con, "
  WITH u AS (SELECT CAST(codinv AS BIGINT) codinv, CAST(g AS INTEGER) g FROM ik)
  SELECT u.codinv, u.g,
    COALESCE(SUM(iy.patent_count) FILTER (WHERE iy.year BETWEEN u.g-5 AND u.g-3),0) early,
    COALESCE(SUM(iy.patent_count) FILTER (WHERE iy.year BETWEEN u.g-2 AND u.g-1),0) recent
  FROM u LEFT JOIN inventor_year iy ON CAST(iy.codinv AS BIGINT)=u.codinv
     AND iy.year BETWEEN u.g-5 AND u.g-1 GROUP BY u.codinv, u.g")
duckdb::duckdb_unregister(con, "ik")
tcov <- merge(tcov, traj, by = c("codinv","g"), all.x = TRUE)
tcov$early[is.na(tcov$early)] <- 0; tcov$recent[is.na(tcov$recent)] <- 0
tcov$log_patent_count_5y <- tcov$log_inventor_patent_stock
tcov$career_age          <- tcov$observed_inventor_career_age
tcov$tenure              <- tcov$observed_target_patent_tenure
tcov$exclusivity         <- tcov$target_exclusivity
tcov$patent_trajectory   <- log1p(tcov$recent / 2) - log1p(tcov$early / 3)
tcov <- cbind(tcov, family_dummies(tcov$modal_family))
tcov <- merge(tcov, treated[, c("codinv","deal_id","g","target_group",
                                "qualification_route","sample_definition","status_eligible")],
              by.x = c("codinv","g"), by.y = c("codinv","g"), all.x = TRUE)
lm_write_parquet(con, treated, LM_TREATED_PARQUET)
lm_write_parquet(con, tcov,    LM_TREATED_COV_PARQUET)

# ---------------------------------------------------------------------------
# (5) Sample-composition audit (replaces the obsolete transition-route audit)
# ---------------------------------------------------------------------------
lm_banner("Sample-composition audit")
era_of <- function(y) { for (nm in names(BROAD_ERAS)) if (y >= BROAD_ERAS[[nm]][1] && y <= BROAD_ERAS[[nm]][2]) return(nm); NA_character_ }
treated_full$era <- vapply(treated_full$deal_year, era_of, character(1))
comp_year <- aggregate(cbind(n = rep(1, nrow(treated_full)),
                             status_eligible = as.integer(treated_full$status_eligible)) ~ deal_year,
                       data = treated_full, FUN = sum)
comp_year$status_eligible_share <- comp_year$status_eligible / comp_year$n
comp_route <- as.data.frame(table(qualification_route = treated_full$qualification_route))
comp <- list(sample_definition = LM_SAMPLE,
             n_treated = nrow(treated_full),
             n_deals = length(unique(treated_full$deal_id)),
             status_eligible_share = mean(as.integer(treated_full$status_eligible), na.rm = TRUE))
lm_write_csv(comp_year, AUDIT_DIR, "composition_by_year")
lm_write_csv(comp_route, AUDIT_DIR, "composition_by_route")
lm_write_csv(as.data.frame(comp), AUDIT_DIR, "composition_summary")
print(as.data.frame(comp))

# ---------------------------------------------------------------------------
# (6) Cohort support census
# ---------------------------------------------------------------------------
lm_banner("Support census")
big_lookup <- dbGetQuery(con, sprintf(
  "SELECT CAST(deal_id AS BIGINT) deal_id, big_deal AS big FROM %s", TBL_SPINE_EXPANDED))
treated <- merge(treated, big_lookup, by = "deal_id", all.x = TRUE)
census <- list()
for (g in COHORTS_ARG) {
  tsub  <- treated[treated$g == g, ]
  elig  <- firm_pool[firm_pool$cohort == g, ]
  duckdb::duckdb_register(con, "fkeys2", data.frame(id_group = elig$id_group))
  # fast equality-join via exploded candidate list (avoids list_contains cross-join)
  n_ctrl_inv <- dbGetQuery(con, sprintf("
    WITH aff AS (SELECT CAST(ia.codinv AS BIGINT) codinv, ia.year, ia.resolved_group, ia.candidate_group_list
                 FROM inventor_affiliation_own ia WHERE ia.year BETWEEN %1$d AND %2$d),
    latest AS (SELECT codinv, MAX(year) my FROM aff GROUP BY codinv),
    la AS (SELECT a.codinv, a.resolved_group, a.candidate_group_list
           FROM aff a JOIN latest l ON a.codinv=l.codinv AND a.year=l.my),
    cand AS (
      SELECT codinv, resolved_group AS grp FROM la WHERE resolved_group IS NOT NULL
      UNION
      SELECT codinv, TRY_CAST(x AS DOUBLE) AS grp
      FROM la, UNNEST(string_split(candidate_group_list, ';')) AS t(x)
      WHERE x <> '' AND TRY_CAST(x AS DOUBLE) IS NOT NULL)
    SELECT COUNT(DISTINCT c.codinv) n FROM cand c JOIN fkeys2 f ON c.grp = f.id_group",
    g + QUAL_LO, g + QUAL_HI))$n
  duckdb::duckdb_unregister(con, "fkeys2")
  census[[as.character(g)]] <- data.frame(
    cohort = g,
    treated_deals       = length(unique(tsub$deal_id)),
    treated_inventors   = nrow(tsub),
    treated_status_elig  = sum(as.integer(tsub$status_eligible), na.rm = TRUE),
    treated_deals_big   = length(unique(tsub$deal_id[tsub$big == 1])),
    treated_deals_small = length(unique(tsub$deal_id[tsub$big == 0])),
    eligible_ctrl_firms = nrow(elig),
    eligible_ctrl_firms_excl_dropdivest = sum(elig$in_dropdivest_lineage == 0),
    eligible_ctrl_inv   = n_ctrl_inv,
    firm_cand_per_treated_deal = round(nrow(elig) / max(1, length(unique(tsub$deal_id))), 1),
    inv_cand_per_treated_inv   = round(n_ctrl_inv / max(1, nrow(tsub)), 1))
}
census <- do.call(rbind, census)
print(census)
lm_write_csv(census, AUDIT_DIR, LM_SUPPORT_CENSUS_CSV)

# ---------------------------------------------------------------------------
# (7) Construction assertions
# ---------------------------------------------------------------------------
lm_banner("Construction assertions")
lm_assert(!any(duplicated(treated$codinv)), "one treated row per inventor after first-exposure (unique codinv)")
lm_assert(nrow(unique(treated[, c("codinv","deal_id")])) == nrow(treated), "treated unique at (codinv, deal_id)")
lm_assert(length(intersect(firm_pool$id_group, ever_target_groups)) == 0,
          "no control firm is an ever-target group (company-lineage screen)")
acq_viol <- 0L
for (g in COHORTS_ARG) {
  aw <- unique(acq_ev$acquirer_group[acq_ev$target_year >= g + EVENT_LO & acq_ev$target_year <= g + EVENT_HI])
  acq_viol <- acq_viol + length(intersect(firm_pool$id_group[firm_pool$cohort == g], aw))
}
lm_assert(acq_viol == 0, "no control firm has an acquirer event in its g-5..g+5 window")
lm_assert(all(firm_pool$stock > 0), "every control firm has pre-period patent info (stock>0)")
core_inv <- c("log_patent_count_5y","patent_trajectory","career_age","tenure","exclusivity")
lm_section(sprintf("treated inventors with any missing core covariate: %d of %d",
                   sum(!stats::complete.cases(tcov[, core_inv])), nrow(tcov)))
lm_assert(QUAL_HI <= -1L && EARLY_HI <= -1L && RECENT_HI <= -1L, "all matching-variable windows end no later than g-1")
lm_assert(!any(duplicated(firm_pool[, c("id_group","cohort")])), "firm pool unique at (id_group, cohort)")

lm_section(sprintf("elapsed: %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
lm_banner("13b DONE")
