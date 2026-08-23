# ============================================================================
# 13d_report_local_match_pilot.R  -- design version local_match_v1
# ----------------------------------------------------------------------------
# Outcome-blind diagnostics for the pilot matches. Reads the restartable shards
# and pre-built inputs; writes CSV tables under results/local_match_v1 and
# audit/local_match_v1. NO post-treatment variable is read or estimated.
#
# smd_weighted() returns an ATT-STANDARDIZED mean difference (denominator = the
# standard deviation of the TREATED arm), not a pooled-variance SMD.
# Nearest-neighbour matching does NOT guarantee balance: every quantity below is
# an empirical design diagnostic.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R")); use_project_library()
source(file.path(BASE, "R", "13a_local_match_config.R"))
source(file.path(BASE, "R", "archive", "main_did_v1", "11_main_design_utils.R"))
source(file.path(BASE, "R", "13_local_match_utils.R"))

con <- lm_connect()
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

read_pq <- function(path) if (file.exists(path)) arrow_or_duck(con, path) else NULL

tcov        <- read_pq(LM_TREATED_COV_PARQUET)
treated_frm <- read_pq(LM_TREATED_FIRM_PARQUET)
firm_pool   <- read_pq(LM_FIRMPOOL_PARQUET)
PROF <- names(CALIPER_PROFILES)
# report over whatever cohorts are actually present in the loaded inputs
# (3 pilot cohorts when untagged; all 17 when LM_TAG=full)
REPORT_COHORTS <- sort(unique(as.integer(tcov$g)))
cat("reporting cohorts:", paste(REPORT_COHORTS, collapse = "/"), " (tag='", LM_TAG, "')\n", sep = "")
# guard: inputs must match the requested sample (no cross-sample pooling)
lm_assert(all(tcov$sample_definition == LM_SAMPLE),
          sprintf("loaded inputs match LM_SAMPLE='%s'", LM_SAMPLE))
FIRM_SCALAR <- c("log_patent_stock_5y","log_inventor_count_5y","patent_trajectory")
CORE_INV    <- INV_CONT_VARS

era_of <- function(y) { for (nm in names(BROAD_ERAS)) if (y >= BROAD_ERAS[[nm]][1] && y <= BROAD_ERAS[[nm]][2]) return(nm); NA_character_ }

# ---------------------------------------------------------------------------
# 1. Retention (treated deals & inventors) by cohort x profile
# ---------------------------------------------------------------------------
lm_banner("Retention")
ret <- list()
for (g in REPORT_COHORTS) {
  n_deals_tot <- length(unique(tcov$deal_id[tcov$g == g]))
  n_inv_tot   <- sum(tcov$g == g)
  for (pn in PROF) {
    fm <- read_pq(shard_file(g, "firm", pn)); im <- read_pq(shard_file(g, "inv", pn))
    n_deals_sup <- if (!is.null(fm) && nrow(fm)) length(unique(fm$deal_id)) else 0L
    n_inv_sup   <- if (!is.null(im) && nrow(im)) length(unique(im$treated_codinv)) else 0L
    ret[[paste(g,pn)]] <- data.frame(
      cohort = g, era = era_of(g), profile = pn,
      treated_deals = n_deals_tot, deals_supported = n_deals_sup,
      deal_retention = n_deals_sup / n_deals_tot,
      treated_inventors = n_inv_tot, inventors_supported = n_inv_sup,
      inventor_retention = n_inv_sup / n_inv_tot)
  }
}
ret <- do.call(rbind, ret)
# pooled inventor retention by profile
pooled_ret <- do.call(rbind, lapply(PROF, function(pn) {
  s <- ret[ret$profile == pn, ]
  data.frame(profile = pn,
             inv_retention_pooled = sum(s$inventors_supported) / sum(s$treated_inventors),
             deal_retention_pooled = sum(s$deals_supported) / sum(s$treated_deals),
             min_cohort_inv_retention = min(s$inventor_retention))
}))
print(pooled_ret)
lm_write_csv(ret, RESULTS_DIR, "retention_by_cohort_profile")
lm_write_csv(pooled_ret, RESULTS_DIR, "retention_pooled")

# ---------------------------------------------------------------------------
# 2. Firm-level balance (before = full eligible pool; after = matched, weighted)
# ---------------------------------------------------------------------------
lm_banner("Firm-level balance")
firm_bal <- list(); firm_conc <- list()
for (g in REPORT_COHORTS) {
  tfr <- treated_frm[treated_frm$cohort == g, ]
  fp  <- firm_pool[firm_pool$cohort == g, ]
  for (pn in PROF) {
    fm <- read_pq(shard_file(g, "firm", pn)); if (is.null(fm) || !nrow(fm)) next
    # aggregate matched firms to unique control with multiplicity weight
    agg <- aggregate(list(mult = rep(1, nrow(fm))), by = list(control_group = fm$control_group), sum)
    uc  <- fm[!duplicated(fm$control_group), c("control_group", FIRM_SCALAR)]
    uc  <- merge(uc, agg, by = "control_group")
    # before: treated vs full eligible pool (w=1); after: treated vs matched (mult)
    bef <- balance_long(tfr[, FIRM_SCALAR, drop=FALSE], fp[, FIRM_SCALAR, drop=FALSE],
                        FIRM_SCALAR, control_w = rep(1, nrow(fp)), group_label = paste0(g,"|",pn))
    aft <- balance_long(tfr[, FIRM_SCALAR, drop=FALSE], uc[, FIRM_SCALAR, drop=FALSE],
                        FIRM_SCALAR, control_w = uc$mult, group_label = paste0(g,"|",pn))
    b <- data.frame(cohort = g, era = era_of(g), profile = pn, variable = FIRM_SCALAR,
                    smd_before = bef$smd_after, smd_after = aft$smd_after)  # bef$smd_after uses w=1 pool
    firm_bal[[paste(g,pn)]] <- b
    fc <- reuse_concentration(data.frame(control_id = fm$control_group, weight = 1),
                              label = paste0(g,"|",pn))
    fc$cohort <- g; fc$profile <- pn; fc$level <- "firm"
    fc$mean_tech_distance <- mean(fm$tech_distance)
    firm_conc[[paste(g,pn)]] <- fc
  }
}
firm_bal  <- do.call(rbind, firm_bal)
firm_conc <- do.call(rbind, firm_conc)
firm_bal$abs_smd_after <- abs(firm_bal$smd_after)
lm_write_csv(firm_bal, RESULTS_DIR, "firm_balance")
lm_write_csv(firm_conc, RESULTS_DIR, "firm_concentration")

# ---------------------------------------------------------------------------
# 3. Inventor-level balance (before = donor pool; after = matched, weighted) +
#    match-distance quantiles + inventor concentration + by-family support
# ---------------------------------------------------------------------------
lm_banner("Inventor-level balance / distance / concentration / family support")
inv_bal <- list(); inv_conc <- list(); inv_dist <- list(); fam_sup <- list()
inv_bal_fam <- list()
for (g in REPORT_COHORTS) {
  dp  <- read_pq(shard_file(g, "donorpool"))
  tg  <- tcov[tcov$g == g, ]
  for (pn in PROF) {
    im <- read_pq(shard_file(g, "inv", pn)); if (is.null(im) || !nrow(im)) next
    sup_ids <- unique(im$treated_codinv)
    tg_sup  <- tg[tg$codinv %in% sup_ids, ]
    # after: aggregate matched controls to unique person with analysis weight
    aggw <- aggregate(list(w = im$weight), by = list(control_codinv = im$control_codinv), sum)
    ucov <- im[!duplicated(im$control_codinv), c("control_codinv", INV_MATCH_VARS)]
    ucov <- merge(ucov, aggw, by = "control_codinv")
    if (!is.null(dp) && nrow(dp)) {
      bef <- balance_long(tg[, INV_MATCH_VARS], dp[, INV_MATCH_VARS], INV_MATCH_VARS,
                          control_w = rep(1, nrow(dp)), group_label = paste0(g,"|",pn))
    } else bef <- data.frame(variable = INV_MATCH_VARS, smd_after = NA_real_)
    aft <- balance_long(tg_sup[, INV_MATCH_VARS], ucov[, INV_MATCH_VARS], INV_MATCH_VARS,
                        control_w = ucov$w, group_label = paste0(g,"|",pn))
    b <- data.frame(cohort = g, era = era_of(g), profile = pn, variable = INV_MATCH_VARS,
                    smd_before = bef$smd_after, smd_after = aft$smd_after,
                    abs_smd_after = abs(aft$smd_after))
    inv_bal[[paste(g,pn)]] <- b
    # distance quantiles (inventor)
    qd <- stats::quantile(im$dist, c(.1,.25,.5,.75,.9,.99,1), na.rm = TRUE)
    inv_dist[[paste(g,pn)]] <- data.frame(cohort = g, profile = pn, level = "inventor",
      p10=qd[1],p25=qd[2],p50=qd[3],p75=qd[4],p90=qd[5],p99=qd[6],max=qd[7])
    # concentration (inventor, analysis weights)
    ic <- reuse_concentration(data.frame(control_id = im$control_codinv, weight = im$weight),
                              label = paste0(g,"|",pn))
    ic$cohort <- g; ic$profile <- pn; ic$level <- "inventor"; ic$mean_tech_distance <- NA
    inv_conc[[paste(g,pn)]] <- ic
    # support + balance by family (treated inventor's family)
    fam <- ifelse(tg_sup$fam_small_molecule==1,"small_molecule",
            ifelse(tg_sup$fam_biotech==1,"biotech",
             ifelse(tg_sup$fam_formulation==1,"formulation","other")))
    tg_all_fam <- ifelse(tg$fam_small_molecule==1,"small_molecule",
            ifelse(tg$fam_biotech==1,"biotech",
             ifelse(tg$fam_formulation==1,"formulation","other")))
    for (fnm in FAMILIES) {
      n_all <- sum(tg_all_fam == fnm); n_sup <- sum(fam == fnm)
      fam_sup[[paste(g,pn,fnm)]] <- data.frame(cohort=g, profile=pn, family=fnm,
        treated_in_family = n_all, supported_in_family = n_sup,
        family_retention = ifelse(n_all>0, n_sup/n_all, NA))
    }
  }
}
inv_bal  <- do.call(rbind, inv_bal)
inv_conc <- do.call(rbind, inv_conc)
inv_dist <- do.call(rbind, inv_dist)
fam_sup  <- do.call(rbind, fam_sup)
lm_write_csv(inv_bal,  RESULTS_DIR, "inventor_balance")
lm_write_csv(inv_dist, RESULTS_DIR, "inventor_distance_quantiles")
lm_write_csv(rbind(firm_conc[, intersect(names(firm_conc),names(inv_conc))],
                   inv_conc[, intersect(names(firm_conc),names(inv_conc))]),
             RESULTS_DIR, "concentration_all")
lm_write_csv(fam_sup, RESULTS_DIR, "family_support")

# max abs core inventor SMD (after) by cohort x profile + pooled
core_smd <- do.call(rbind, lapply(split(inv_bal, list(inv_bal$cohort, inv_bal$profile), drop=TRUE),
  function(d) {
    dc <- d[d$variable %in% CORE_INV, ]
    data.frame(cohort = d$cohort[1], profile = d$profile[1],
               max_abs_core_smd_after = max(dc$abs_smd_after, na.rm = TRUE),
               max_abs_all_smd_after  = max(d$abs_smd_after, na.rm = TRUE))
  }))
lm_write_csv(core_smd, RESULTS_DIR, "inventor_core_max_smd")
print(core_smd)

# ---------------------------------------------------------------------------
# 4. Caliper recommendation (ordered rule; NOT frozen -- pending full census)
# ---------------------------------------------------------------------------
lm_banner("Caliper recommendation")
rec <- merge(pooled_ret, core_smd_pooled <- do.call(rbind, lapply(PROF, function(pn) {
  s <- core_smd[core_smd$profile == pn, ]
  data.frame(profile = pn, max_core_smd_worst_cohort = max(s$max_abs_core_smd_after))
})), by = "profile")
# pooled inventor concentration (ESS, max share) by profile
conc_pooled <- do.call(rbind, lapply(PROF, function(pn) {
  s <- inv_conc[inv_conc$profile == pn, ]
  data.frame(profile = pn, mean_inv_ess = mean(s$ess_weight),
             max_inv_weight_share = max(s$max_weight_share))
}))
rec <- merge(rec, conc_pooled, by = "profile")
rec$reject_lt80  <- rec$inv_retention_pooled < RETAIN_REJECT | rec$min_cohort_inv_retention <= 0
rec$prefer_ge90  <- rec$inv_retention_pooled >= RETAIN_PREFER
rec$smd_pass     <- rec$max_core_smd_worst_cohort < SMD_WITHIN_PREF
rec <- rec[order(-rec$prefer_ge90, -rec$smd_pass, -rec$mean_inv_ess), ]
print(rec)
lm_write_csv(rec, RESULTS_DIR, "caliper_recommendation")
cand <- rec[!rec$reject_lt80, ]
cand <- cand[order(-cand$smd_pass, -cand$mean_inv_ess, -cand$inv_retention_pooled), ]
recommended <- if (nrow(cand)) cand$profile[1] else NA_character_
cat("PROVISIONAL RECOMMENDED PROFILE (pilot, not frozen):", recommended, "\n")

# ---------------------------------------------------------------------------
# 5. Implementation vs support failures (separated)
# ---------------------------------------------------------------------------
lm_banner("Failure separation")
man <- read.csv(manifest_path(), stringsAsFactors = FALSE)
impl_fail <- man[man$key_ok == FALSE | tolower(man$status) != "complete", ]
support_tab <- ret[, c("cohort","profile","deal_retention","inventor_retention")]
support_tab$support_failure_deals <- 1 - support_tab$deal_retention
support_tab$support_failure_inv   <- 1 - support_tab$inventor_retention
lm_write_csv(if (nrow(impl_fail)) impl_fail else
             data.frame(note = "no implementation failures: all shards key_ok & complete"),
             AUDIT_DIR, "implementation_failures")
lm_write_csv(support_tab, AUDIT_DIR, "support_failures")
cat("implementation failures:", nrow(impl_fail), "\n")

writeLines(recommended, file.path(RESULTS_DIR, "recommended_profile.txt"))
lm_banner("13d DONE")
