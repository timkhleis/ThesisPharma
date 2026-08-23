# ============================================================================
# 13f_extended_diagnostics.R  -- design version local_match_v1 (v2)
# ----------------------------------------------------------------------------
# Diagnostics REQUIRED before a matching profile is selected/frozen. Runs after
# the match shards exist (reads them, tag-aware). Outcome-blind. Adds:
#   1. global cross-cohort control-inventor ESS & reuse
#   2. downstream inventor-weighted control-firm concentration
#   3. equal-deal-weighted concentration (inventor + firm)
#   4. target-minus-mean-matched-control firm gaps
#   5. pooled + broad-era firm balance (ATT-standardized)
#   6. retained-vs-excluded treated composition (cohort/family/size/productivity/
#      age/tenure/exclusivity/status)
# NO post-treatment variable is read.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R")); use_project_library()
source(file.path(BASE, "R", "13a_local_match_config.R"))
source(file.path(BASE, "R", "archive", "main_did_v1", "11_main_design_utils.R"))
source(file.path(BASE, "R", "13_local_match_utils.R"))

con <- lm_connect(); on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
read_pq <- function(p) if (file.exists(p)) arrow_or_duck(con, p) else NULL

tcov        <- read_pq(LM_TREATED_COV_PARQUET)
treated_frm <- read_pq(LM_TREATED_FIRM_PARQUET)
lm_assert(all(tcov$sample_definition == LM_SAMPLE), sprintf("inputs match LM_SAMPLE='%s'", LM_SAMPLE))
PROF <- names(CALIPER_PROFILES)
FSC  <- c("log_patent_stock_5y","log_inventor_count_5y","patent_trajectory")
REPORT_COHORTS <- sort(unique(as.integer(tcov$g)))
era_of <- function(y){for(nm in names(BROAD_ERAS)) if(y>=BROAD_ERAS[[nm]][1]&&y<=BROAD_ERAS[[nm]][2]) return(nm); NA_character_}
top5_share <- function(w){ s<-sum(w); if(s<=0) return(NA_real_); sum(head(sort(w,decreasing=TRUE),5))/s }

read_all_inv <- function(pn) do.call(rbind, lapply(REPORT_COHORTS, function(g){
  im <- read_pq(shard_file(g,"inv",pn)); if(is.null(im)||!nrow(im)) return(NULL)
  im[, c("cohort","deal_id","treated_codinv","control_codinv","control_group","weight",
         INV_MATCH_VARS)]
}))
read_all_firm <- function(pn) do.call(rbind, lapply(REPORT_COHORTS, function(g){
  fm <- read_pq(shard_file(g,"firm",pn)); if(is.null(fm)||!nrow(fm)) return(NULL)
  fm[, c("cohort","deal_id","target_group","control_group",FSC)]
}))

# ---------------------------------------------------------------------------
# 1-3. Concentration: global, downstream-firm, equal-deal-weighted
# ---------------------------------------------------------------------------
lm_banner("Concentration: global / downstream-firm / equal-deal")
inv_rows <- list(); firm_rows <- list()
for (pn in PROF) {
  M <- read_all_inv(pn); if (is.null(M)) next
  # (1) global cross-cohort control-inventor
  gi <- reuse_concentration(data.frame(control_id=M$control_codinv, weight=M$weight), label=pn)
  gi$profile <- pn; gi$metric <- "global_control_inventor"
  # (2) downstream inventor-weighted control-firm
  fw <- aggregate(weight ~ control_group, M, sum)
  gf <- data.frame(profile=pn, metric="inv_weighted_control_firm", n_unique=nrow(fw),
                   ess_weight=ess(fw$weight), max_weight_share=max(fw$weight)/sum(fw$weight),
                   top5_weight_share=top5_share(fw$weight))
  # (3) equal-deal-weighted: each deal contributes equal total mass 1/n_deals
  dmass <- aggregate(weight ~ deal_id, M, sum); names(dmass)[2] <- "deal_mass"
  M2 <- merge(M, dmass, by="deal_id"); nd <- length(unique(M$deal_id))
  M2$eqw <- (1/nd) * (M2$weight / M2$deal_mass)
  ei <- reuse_concentration(data.frame(control_id=M2$control_codinv, weight=M2$eqw), label=pn)
  ei$profile <- pn; ei$metric <- "equal_deal_control_inventor"
  fw2 <- aggregate(eqw ~ control_group, M2, sum)
  ef <- data.frame(profile=pn, metric="equal_deal_control_firm", n_unique=nrow(fw2),
                   ess_weight=ess(fw2$eqw), max_weight_share=max(fw2$eqw)/sum(fw2$eqw),
                   top5_weight_share=top5_share(fw2$eqw))
  inv_rows[[pn]] <- rbind(gi, ei); firm_rows[[pn]] <- rbind(gf, ef)
}
lm_write_csv(do.call(rbind, inv_rows),  RESULTS_DIR, "concentration_inventor_global_equaldeal")
lm_write_csv(do.call(rbind, firm_rows), RESULTS_DIR, "concentration_firm_downstream")

# Pooled and broad-era inventor balance under the actual Stage-2 ATT weights.
# The treated side contains one row per supported treated inventor; the control
# side retains the three matched rows at weight 1/3 each.
inv_balance_rows <- list()
for (pn in PROF) {
  M <- read_all_inv(pn); if (is.null(M)) next
  supported <- unique(M[, c("cohort","treated_codinv")])
  T <- merge(supported, tcov[, c("g","codinv",INV_MATCH_VARS)],
             by.x=c("cohort","treated_codinv"), by.y=c("g","codinv"),
             all.x=TRUE)
  T$era <- vapply(T$cohort, era_of, character(1))
  M$era <- vapply(M$cohort, era_of, character(1))
  scopes <- c(list(list(lab="pooled", er=NULL)),
              lapply(names(BROAD_ERAS), function(e) list(lab=e, er=e)))
  for (sc in scopes) {
    ts <- if (is.null(sc$er)) T else T[T$era == sc$er, ]
    cs <- if (is.null(sc$er)) M else M[M$era == sc$er, ]
    if (!nrow(ts) || !nrow(cs)) next
    b <- balance_long(ts[, INV_MATCH_VARS, drop=FALSE],
                      cs[, INV_MATCH_VARS, drop=FALSE],
                      INV_MATCH_VARS, control_w=cs$weight,
                      group_label=sc$lab)
    b$profile <- pn; b$scope <- sc$lab
    inv_balance_rows[[paste(pn,sc$lab)]] <-
      b[, c("profile","scope","variable","smd_before","smd_after","abs_smd_after")]
  }
}
lm_write_csv(do.call(rbind, inv_balance_rows), RESULTS_DIR,
             "inventor_balance_pooled_era")

# ---------------------------------------------------------------------------
# 4. Target-minus-mean-matched-control firm gaps (unstandardized, robust to thin n)
# 5. Pooled + broad-era firm balance (ATT-standardized)
# ---------------------------------------------------------------------------
lm_banner("Firm gaps + pooled/era firm balance")
gap_rows <- list(); fbal_rows <- list()
for (pn in PROF) {
  FM <- read_all_firm(pn); if (is.null(FM)) next
  # target-minus-mean-control per (deal): target firm value - mean of its matched controls
  mc <- aggregate(FM[,FSC], list(deal_id=FM$deal_id, target_group=FM$target_group), mean)
  tm <- merge(mc, treated_frm[,c("cohort","id_group",FSC)],
              by.x="target_group", by.y="id_group", suffixes=c("_ctrl","_tgt"))
  for (v in FSC) tm[[paste0("gap_",v)]] <- tm[[paste0(v,"_tgt")]] - tm[[paste0(v,"_ctrl")]]
  for (v in FSC) gap_rows[[paste(pn,v)]] <- data.frame(
    profile=pn, variable=v,
    mean_gap=mean(tm[[paste0("gap_",v)]], na.rm=TRUE),
    median_gap=median(tm[[paste0("gap_",v)]], na.rm=TRUE),
    p10=quantile(tm[[paste0("gap_",v)]],.1,na.rm=TRUE),
    p90=quantile(tm[[paste0("gap_",v)]],.9,na.rm=TRUE),
    max_abs_gap=max(abs(tm[[paste0("gap_",v)]]), na.rm=TRUE))
  # pooled + era firm balance: treated firms vs matched controls (multiplicity-weighted)
  uc <- FM[!duplicated(FM[,c("cohort","control_group")]), c("cohort","control_group",FSC)]
  mult <- aggregate(list(mult=rep(1,nrow(FM))), FM[,c("cohort","control_group")], sum)
  uc <- merge(uc, mult, by=c("cohort","control_group"))
  uc$era <- vapply(uc$cohort, era_of, character(1)); tfr <- treated_frm; tfr$era <- vapply(tfr$cohort, era_of, character(1))
  scopes <- c(list(list(lab="pooled", er=NULL)), lapply(names(BROAD_ERAS), function(e) list(lab=e, er=e)))
  for (sc in scopes) {
    tsub <- if (is.null(sc$er)) tfr else tfr[tfr$era==sc$er,]
    csub <- if (is.null(sc$er)) uc  else uc[uc$era==sc$er,]
    if (!nrow(tsub) || !nrow(csub)) next
    b <- balance_long(tsub[,FSC,drop=FALSE], csub[,FSC,drop=FALSE], FSC, control_w=csub$mult, group_label=sc$lab)
    b$profile <- pn; b$scope <- sc$lab; fbal_rows[[paste(pn,sc$lab)]] <- b[,c("profile","scope","variable","smd_after")]
  }
}
lm_write_csv(do.call(rbind, gap_rows),  RESULTS_DIR, "firm_target_minus_control_gaps")
lm_write_csv(do.call(rbind, fbal_rows), RESULTS_DIR, "firm_balance_pooled_era")

# Firm balance under the two estimands used downstream. The inventor-weighted
# version gives each supported treated inventor unit mass; the equal-deal
# version gives each deal unit mass. Control-firm weights are inherited from the
# Stage-2 inventor matches, so these diagnostics measure the balance of firms
# that actually contribute to each ATT rather than Stage-1 match multiplicity.
weighted_firm_balance <- function(tdat, cdat, tw, cw, profile, scope, estimand) {
  do.call(rbind, lapply(FSC, function(v) {
    x <- c(tdat[[v]], cdat[[v]])
    tr <- c(rep(1L, nrow(tdat)), rep(0L, nrow(cdat)))
    w <- c(tw, cw)
    ok <- is.finite(x) & is.finite(w) & w > 0
    data.frame(profile=profile, scope=scope, estimand=estimand,
               variable=v, smd_after=smd_weighted(x[ok], tr[ok], w[ok]))
  }))
}

fbal_estimand_rows <- list()
for (pn in PROF) {
  M <- read_all_inv(pn); FM <- read_all_firm(pn)
  if (is.null(M) || is.null(FM)) next

  treated_pairs <- unique(M[, c("cohort","deal_id","treated_codinv")])
  tw <- aggregate(list(treated_weight=rep(1, nrow(treated_pairs))),
                  treated_pairs[, c("cohort","deal_id")], sum)
  cw <- aggregate(weight ~ cohort + deal_id + control_group, M, sum)

  deal_targets <- unique(FM[, c("cohort","deal_id","target_group")])
  tvals <- merge(deal_targets, treated_frm[, c("cohort","id_group",FSC)],
                 by.x=c("cohort","target_group"), by.y=c("cohort","id_group"),
                 all.x=TRUE)
  tvals <- merge(tvals, tw, by=c("cohort","deal_id"), all=FALSE)

  control_vals <- unique(FM[, c("cohort","deal_id","control_group",FSC)])
  cvals <- merge(control_vals, cw, by=c("cohort","deal_id","control_group"),
                 all=FALSE)
  cvals <- merge(cvals, tw, by=c("cohort","deal_id"), all.x=TRUE)
  cvals$equal_deal_weight <- cvals$weight / cvals$treated_weight

  tvals$era <- vapply(tvals$cohort, era_of, character(1))
  cvals$era <- vapply(cvals$cohort, era_of, character(1))
  scopes <- c(list(list(lab="pooled", er=NULL)),
              lapply(names(BROAD_ERAS), function(e) list(lab=e, er=e)))
  for (sc in scopes) {
    ts <- if (is.null(sc$er)) tvals else tvals[tvals$era == sc$er, ]
    cs <- if (is.null(sc$er)) cvals else cvals[cvals$era == sc$er, ]
    if (!nrow(ts) || !nrow(cs)) next
    fbal_estimand_rows[[paste(pn,sc$lab,"inventor")]] <-
      weighted_firm_balance(ts, cs, ts$treated_weight, cs$weight,
                            pn, sc$lab, "treated_inventor_weighted")
    fbal_estimand_rows[[paste(pn,sc$lab,"deal")]] <-
      weighted_firm_balance(ts, cs, rep(1, nrow(ts)), cs$equal_deal_weight,
                            pn, sc$lab, "equal_deal_weighted")
  }
}
lm_write_csv(do.call(rbind, fbal_estimand_rows), RESULTS_DIR,
             "firm_balance_estimand_weighted")

# ---------------------------------------------------------------------------
# 6. Retained vs excluded treated composition
# ---------------------------------------------------------------------------
lm_banner("Retained vs excluded treated composition")
big <- dbGetQuery(con, sprintf("SELECT CAST(deal_id AS BIGINT) deal_id, big_deal AS big FROM %s", TBL_SPINE_EXPANDED))
tc <- merge(tcov, big, by="deal_id", all.x=TRUE)
tc$family <- ifelse(tc$fam_small_molecule==1,"small_molecule",
             ifelse(tc$fam_biotech==1,"biotech",ifelse(tc$fam_formulation==1,"formulation","other")))
metrics <- c("log_patent_count_5y","career_age","tenure","exclusivity")
comp_rows <- list()
for (pn in PROF) {
  sup <- unique(do.call(c, lapply(REPORT_COHORTS, function(g){
    im <- read_pq(shard_file(g,"inv",pn)); if(is.null(im)||!nrow(im)) return(numeric(0)); unique(im$treated_codinv)})))
  tc$retained <- as.integer(tc$codinv %in% sup)
  for (scope in c("pooled", as.character(REPORT_COHORTS))) {
    d <- if (scope=="pooled") tc else tc[tc$g==as.integer(scope),]
    for (r in c(1L,0L)) {
      dr <- d[d$retained==r,]; if(!nrow(dr)) next
      comp_rows[[paste(pn,scope,r)]] <- data.frame(
        profile=pn, scope=scope, group=ifelse(r==1,"retained","excluded"), n=nrow(dr),
        mean_log_patents=mean(dr$log_patent_count_5y,na.rm=TRUE),
        mean_career_age=mean(dr$career_age,na.rm=TRUE),
        mean_tenure=mean(dr$tenure,na.rm=TRUE),
        mean_exclusivity=mean(dr$exclusivity,na.rm=TRUE),
        share_status_eligible=mean(as.integer(dr$status_eligible),na.rm=TRUE),
        share_big=mean(dr$big==1,na.rm=TRUE),
        share_small_molecule=mean(dr$family=="small_molecule"),
        share_biotech=mean(dr$family=="biotech"),
        share_formulation=mean(dr$family=="formulation"),
        share_other=mean(dr$family=="other"))
    }
  }
}
lm_write_csv(do.call(rbind, comp_rows), RESULTS_DIR, "retained_vs_excluded_composition")
lm_banner("13f DONE")
