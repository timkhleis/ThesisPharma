# ============================================================================
# 13e_full_cohort_census.R  -- design version local_match_v1
# ----------------------------------------------------------------------------
# Full 1994-2010 support census (all 17 cohorts). Counts only -- does NOT build
# or overwrite any matching parquet. Outcome-blind. Writes:
#   audit/local_match_v1/full_cohort_support_census.csv
# Used to decide readiness of the full-cohort matched build.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R")); use_project_library()
source(file.path(BASE, "R", "13a_local_match_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
source(file.path(BASE, "R", "13_local_match_utils.R"))
set.seed(SEED)

t0  <- Sys.time()
con <- lm_connect()
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

lm_banner("Full-cohort support census 1994-2010")

# treated (authoritative company-level strict qualify; first-exposure BEFORE cohort restriction)
spine <- if (LM_SAMPLE == "expanded") TBL_SPINE_EXPANDED else TBL_SPINE_STRICT
if (LM_SAMPLE == "group") {
  cert <- dbGetQuery(con, sprintf("SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id,
    CAST(deal_year AS INTEGER) deal_year FROM %s", TBL_GROUP_SENS))
} else {
  q0 <- dbGetQuery(con, qualify_sql(0L, spine)); q0$deal_year <- as.integer(q0$deal_year)
  cert <- q0[, c("codinv","deal_id","deal_year")]
}
cert <- keep_first_exposure(cert, "deal_year")
big_lookup <- dbGetQuery(con, sprintf("SELECT CAST(deal_id AS BIGINT) deal_id, big_deal AS big FROM %s",
                                      TBL_SPINE_EXPANDED))
cert <- merge(cert, big_lookup, by = "deal_id", all.x = TRUE)

# authoritative ever-target donor screen (company identity -> full firm_group lineage)
ever_target <- dbGetQuery(con, sprintf("
  WITH tc AS (SELECT DISTINCT CAST(target_compcod AS DOUBLE) compcod FROM %s)
  SELECT DISTINCT CAST(fg.id_group AS DOUBLE) id_group FROM tc
  JOIN firm_group fg ON CAST(fg.compcod AS DOUBLE)=tc.compcod WHERE fg.id_group IS NOT NULL",
  TBL_DTC_EXPANDED))$id_group
acq_ev <- dbGetQuery(con, sprintf("SELECT CAST(acquirer_group AS DOUBLE) acquirer_group,
  CAST(target_year AS INTEGER) target_year FROM %s
  WHERE acquirer_group IS NOT NULL AND CAST(acquirer_group AS VARCHAR) NOT LIKE '999%%'",
  TBL_DEAL_ASSIGN))

era_of <- function(y){for(nm in names(BROAD_ERAS)) if(y>=BROAD_ERAS[[nm]][1] && y<=BROAD_ERAS[[nm]][2]) return(nm); NA}

rows <- list()
for (g in FULL_COHORTS) {
  tsub <- cert[cert$deal_year == g, ]
  acq_win <- unique(acq_ev$acquirer_group[acq_ev$target_year >= g+EVENT_LO & acq_ev$target_year <= g+EVENT_HI])
  duckdb::duckdb_register(con, "ever_t", data.frame(id_group = ever_target))
  duckdb::duckdb_register(con, "acq_w",  data.frame(id_group = if(length(acq_win)) acq_win else -1))
  elig <- dbGetQuery(con, sprintf("
    WITH win AS (SELECT DISTINCT CAST(id_group AS DOUBLE) id_group FROM patent_company_link
                 WHERE year BETWEEN %1$d AND %2$d AND id_group IS NOT NULL)
    SELECT w.id_group FROM win w
    WHERE w.id_group NOT IN (SELECT id_group FROM ever_t)
      AND w.id_group NOT IN (SELECT id_group FROM acq_w)", g+QUAL_LO, g+QUAL_HI))
  duckdb::duckdb_unregister(con, "ever_t"); duckdb::duckdb_unregister(con, "acq_w")
  duckdb::duckdb_register(con, "fkeys2", data.frame(id_group = elig$id_group))
  # equality-join (hash) via exploded candidate list -- avoids list_contains cross-join
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
    g+QUAL_LO, g+QUAL_HI))$n
  duckdb::duckdb_unregister(con, "fkeys2")
  rows[[as.character(g)]] <- data.frame(
    cohort=g, era=era_of(g),
    treated_deals=length(unique(tsub$deal_id)), treated_inventors=nrow(tsub),
    treated_deals_big=length(unique(tsub$deal_id[tsub$big==1])),
    treated_deals_small=length(unique(tsub$deal_id[tsub$big==0])),
    eligible_ctrl_firms=nrow(elig), eligible_ctrl_inv=n_ctrl_inv,
    firm_cand_per_deal=round(nrow(elig)/max(1,length(unique(tsub$deal_id))),1),
    inv_cand_per_treated=round(n_ctrl_inv/max(1,nrow(tsub)),1))
  cat(sprintf("  %d: %d deals, %d inv, %d elig firms, %d elig ctrl inv\n",
              g, rows[[as.character(g)]]$treated_deals, nrow(tsub), nrow(elig), n_ctrl_inv))
}
census <- do.call(rbind, rows)
census_tot <- data.frame(cohort=9999, era="ALL",
  treated_deals=sum(census$treated_deals), treated_inventors=sum(census$treated_inventors),
  treated_deals_big=sum(census$treated_deals_big), treated_deals_small=sum(census$treated_deals_small),
  eligible_ctrl_firms=NA, eligible_ctrl_inv=NA,
  firm_cand_per_deal=NA, inv_cand_per_treated=NA)
census <- rbind(census, census_tot)
print(census)
lm_write_csv(census, AUDIT_DIR, "full_cohort_support_census")
lm_section(sprintf("elapsed: %.1f min", as.numeric(difftime(Sys.time(), t0, units="mins"))))
lm_banner("13e DONE")
