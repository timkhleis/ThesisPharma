# ============================================================================
# 13c_run_local_match_pilot.R  -- design version local_match_v1
# ----------------------------------------------------------------------------
# Two-stage local nearest-neighbour matching for the pilot cohorts.
#
# Per cohort, per caliper profile (uncalipered / loose 2.0 / medium 1.5 / tight 1.0):
#   Stage 1: standardized-Euclidean caliper applied to the COMPLETE eligible firm
#            pool, then select the 5 nearest surviving control firms per target.
#   Stage 2: build the inventor pool from those 5 firms, apply the caliper, then
#            select the 3 nearest surviving control inventors per treated inventor.
#   Both stages are re-run for every profile (the 5 firms may change).
#   EXACTLY 5 firms / EXACTLY 3 inventors required; otherwise unsupported (no
#   partial matches). Each inventor match receives weight 1/3.
#
# Restartable: one firm-shard and one inventor-shard per (cohort, profile).
# Completed cohorts are preserved if a later cohort fails.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R")); use_project_library()
source(file.path(BASE, "R", "13a_local_match_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
source(file.path(BASE, "R", "13_local_match_utils.R"))
set.seed(SEED)
args <- commandArgs(trailingOnly = TRUE)
COHORTS_ARG <- if (length(args) > 0) as.integer(args) else PILOT_COHORTS

t0  <- Sys.time()
con <- lm_connect()
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

# load pre-built inputs
treated_cov <- as.data.frame(arrow_or_duck(con, LM_TREATED_COV_PARQUET))
firm_pool   <- as.data.frame(arrow_or_duck(con, LM_FIRMPOOL_PARQUET))
treated_frm <- as.data.frame(arrow_or_duck(con, LM_TREATED_FIRM_PARQUET))
profiles    <- CALIPER_PROFILES
# guard: inputs must match the requested sample (no cross-sample pooling)
lm_assert(all(treated_cov$sample_definition == LM_SAMPLE),
          sprintf("loaded inputs match LM_SAMPLE='%s'", LM_SAMPLE))
lm_assert(all(treated_cov$design_hash == LM_DESIGN_HASH),
          "loaded inputs carry the current design_hash")
# caliper acts on continuous inventor vars only (family dummies penalise distance)
INV_CALIPER_COLS <- which(INV_MATCH_VARS %in% INV_CONT_VARS)

# ---- control-inventor covariate retrieval for a set of firms (one cohort) ----
control_inv_covariates <- function(con, firms, g) {
  duckdb::duckdb_register(con, "ufirms", data.frame(id_group = unique(firms)))
  # generic latest-focal-affiliation qualification (resolved OR candidate), restricted to firms
  qual <- dbGetQuery(con, sprintf("
    WITH aff AS (SELECT CAST(ia.codinv AS BIGINT) codinv, ia.year, ia.resolved_group, ia.candidate_group_list
                 FROM inventor_affiliation_own ia WHERE ia.year BETWEEN %1$d AND %2$d),
    latest AS (SELECT codinv, MAX(year) my FROM aff GROUP BY codinv),
    la AS (SELECT a.* FROM aff a JOIN latest l ON a.codinv=l.codinv AND a.year=l.my)
    SELECT DISTINCT la.codinv, f.id_group AS grp
    FROM la JOIN ufirms f
      ON (la.resolved_group = f.id_group
          OR list_contains(string_split(la.candidate_group_list,';'),
                           CAST(CAST(f.id_group AS BIGINT) AS VARCHAR)))",
    g + QUAL_LO, g + QUAL_HI))
  duckdb::duckdb_unregister(con, "ufirms")
  if (nrow(qual) == 0) return(NULL)
  qual$g <- g
  cov <- compute_inventor_covariates(con, qual[, c("codinv","g","grp")])
  # trajectory (codinv,g) -- grp-independent
  duckdb::duckdb_register(con, "ik", unique(qual[, c("codinv","g")]))
  traj <- dbGetQuery(con, "
    WITH u AS (SELECT CAST(codinv AS BIGINT) codinv, CAST(g AS INTEGER) g FROM ik)
    SELECT u.codinv, u.g,
      COALESCE(SUM(iy.patent_count) FILTER (WHERE iy.year BETWEEN u.g-5 AND u.g-3),0) early,
      COALESCE(SUM(iy.patent_count) FILTER (WHERE iy.year BETWEEN u.g-2 AND u.g-1),0) recent
    FROM u LEFT JOIN inventor_year iy ON CAST(iy.codinv AS BIGINT)=u.codinv
       AND iy.year BETWEEN u.g-5 AND u.g-1 GROUP BY u.codinv,u.g")
  duckdb::duckdb_unregister(con, "ik")
  cov <- merge(cov, traj, by = c("codinv","g"), all.x = TRUE)
  cov$early[is.na(cov$early)] <- 0; cov$recent[is.na(cov$recent)] <- 0
  cov$log_patent_count_5y <- cov$log_inventor_patent_stock
  cov$career_age          <- cov$observed_inventor_career_age
  cov$tenure              <- cov$observed_target_patent_tenure
  cov$exclusivity         <- cov$target_exclusivity
  cov$patent_trajectory   <- log1p(cov$recent / 2) - log1p(cov$early / 3)
  cov <- cbind(cov, family_dummies(cov$modal_family))
  cov
}

# ---- tech distance (1 - cosine) for target x control firm pairs (one cohort) -
tech_distance_pairs <- function(con, target_groups, control_groups, g) {
  duckdb::duckdb_register(con, "tg", data.frame(id_group = unique(target_groups)))
  duckdb::duckdb_register(con, "cg", data.frame(id_group = unique(control_groups)))
  d <- dbGetQuery(con, sprintf("
    WITH giy AS (SELECT CAST(id_group AS DOUBLE) id_group, SUBSTR(ipc_code,1,4) sub, SUM(patent_count) w
                 FROM group_ipc_year WHERE year BETWEEN %1$d AND %2$d
                 GROUP BY 1,2),
    tv AS (SELECT g.id_group tgt, g.sub, g.w FROM giy g JOIN tg ON g.id_group=tg.id_group),
    cv AS (SELECT g.id_group ctl, g.sub, g.w FROM giy g JOIN cg ON g.id_group=cg.id_group),
    dot AS (SELECT tv.tgt, cv.ctl, SUM(tv.w*cv.w) dp FROM tv JOIN cv ON tv.sub=cv.sub GROUP BY 1,2),
    tn AS (SELECT tgt, SQRT(SUM(w*w)) n FROM tv GROUP BY tgt),
    cn AS (SELECT ctl, SQRT(SUM(w*w)) n FROM cv GROUP BY ctl)
    SELECT d.tgt AS target_group, d.ctl AS control_group,
           d.dp/(tn.n*cn.n) AS cosine
    FROM dot d JOIN tn ON tn.tgt=d.tgt JOIN cn ON cn.ctl=d.ctl",
    g + QUAL_LO, g + QUAL_HI))
  duckdb::duckdb_unregister(con, "tg"); duckdb::duckdb_unregister(con, "cg")
  d
}

FIRM_GAP_COLS <- paste0("gap_", FIRM_MATCH_VARS)
INV_GAP_COLS  <- paste0("gap_", INV_MATCH_VARS)

process_cohort <- function(g) {
  lm_banner(sprintf("COHORT %d", g))
  # restart guard: skip ONLY if every expected shard validates (sample, design_hash,
  # manifest completion, unique keys, row count, weight sums). Stale/partial/mismatched
  # shards are rejected and the cohort is rebuilt.
  want <- c(shard_file(g, "donorpool"),
            unlist(lapply(names(profiles), function(p) c(shard_file(g,"firm",p), shard_file(g,"inv",p)))))
  if (all(file.exists(want))) {
    v <- verify_cohort_shards(con, g, names(profiles))
    if (isTRUE(v$ok)) { lm_section(sprintf("cohort %d: all shards valid -> skip (restart)", g)); return(invisible(TRUE)) }
    lm_section(sprintf("cohort %d: shards present but INVALID (%s) -> rebuilding", g, v$reason))
  }

  tcv <- treated_cov[treated_cov$g == g, ]
  tfr <- treated_frm[treated_frm$cohort == g, ]
  fp  <- firm_pool[firm_pool$cohort == g, ]
  deals <- unique(tcv[, c("deal_id","target_group")])
  lm_section(sprintf("%d treated inventors, %d deals, %d eligible control firms",
                     nrow(tcv), nrow(deals), nrow(fp)))

  # --- firm-stage pooled SDs (treated targets + eligible controls) ---
  firm_scalar <- c("log_patent_stock_5y","log_inventor_count_5y","patent_trajectory")
  pool_firm <- rbind(tfr[, firm_scalar], fp[, firm_scalar])
  sd_firm3  <- pooled_sds(pool_firm, firm_scalar)

  # --- tech distance for all deal x eligible-control pairs ---
  td <- tech_distance_pairs(con, deals$target_group, fp$id_group, g)
  # build full firm candidate table (deal x control) with tech_distance
  fcand <- merge(deals, data.frame(control_group = fp$id_group), by = NULL)  # cross join
  fcand <- merge(fcand, fp[, c("id_group", firm_scalar)],
                 by.x = "control_group", by.y = "id_group", all.x = TRUE)
  fcand <- merge(fcand, td, by = c("target_group","control_group"), all.x = TRUE)
  fcand$cosine[is.na(fcand$cosine)] <- 0
  fcand$tech_distance <- 1 - fcand$cosine
  sd_tech <- pooled_sd(fcand$tech_distance)
  sd_firm <- c(sd_firm3, tech_distance = sd_tech)[FIRM_MATCH_VARS]

  fcand_dt <- data.table::as.data.table(fcand)
  data.table::setkey(fcand_dt, deal_id)

  # ================= STAGE 1 per profile =================
  firm_matches <- list()   # profile -> data.frame of matched firms
  union_firms  <- numeric(0)
  for (pn in names(profiles)) {
    cal <- profiles[[pn]]
    rows <- list()
    for (i in seq_len(nrow(deals))) {
      d_id <- deals$deal_id[i]; tg <- deals$target_group[i]
      trow <- tfr[tfr$id_group == tg, ]
      if (nrow(trow) == 0 || any(!is.finite(unlist(trow[1, firm_scalar])))) next
      cd <- fcand_dt[.(d_id)]
      Cm <- as.matrix(cd[, ..FIRM_MATCH_VARS])
      tvec <- c(trow$log_patent_stock_5y, trow$log_inventor_count_5y,
                trow$patent_trajectory, 0)                      # tech distance to self = 0
      names(tvec) <- FIRM_MATCH_VARS
      res <- knn_one(tvec, Cm, sd_firm, N_FIRM_MATCH, cal)
      if (is.null(res)) next                                    # deal unsupported this profile
      sel <- cd[res$idx]
      gapdf <- as.data.frame(res$gaps); names(gapdf) <- FIRM_GAP_COLS
      rows[[length(rows) + 1L]] <- cbind(
        data.frame(cohort = g, profile = pn, deal_id = d_id, target_group = tg,
                   control_group = sel$control_group, rank = seq_len(N_FIRM_MATCH),
                   dist = res$dist, max_abs_gap = res$maxabs,
                   log_patent_stock_5y = sel$log_patent_stock_5y,
                   log_inventor_count_5y = sel$log_inventor_count_5y,
                   patent_trajectory = sel$patent_trajectory,
                   tech_distance = sel$tech_distance),
        gapdf)
    }
    fm <- if (length(rows)) do.call(rbind, rows) else
      data.frame()[, character(0)]
    firm_matches[[pn]] <- fm
    if (nrow(fm)) union_firms <- union(union_firms, fm$control_group)
    p <- shard_file(g, "firm", pn)
    lm_write_parquet(con, if (nrow(fm)) fm else data.frame(cohort=integer(0)), p)
    v <- validate_shard_keys(fm, c("deal_id","control_group"))
    manifest_append(g, "firm", pn, p, v$n_rows, v$n_unique_keys, v$key_ok, "complete")
  }

  # ============ control inventor covariates for union of matched firms ============
  lm_section(sprintf("union matched control firms: %d -> retrieving control inventor covariates", length(union_firms)))
  cinv <- if (length(union_firms)) control_inv_covariates(con, union_firms, g) else NULL
  # persist donor candidate pool (pre-match inventor reference for balance/concentration)
  dp_file <- shard_file(g, "donorpool")
  dp_out <- if (!is.null(cinv)) cbind(cohort = g, cinv) else data.frame(cohort = integer(0))
  lm_write_parquet(con, dp_out, dp_file)
  vdp <- validate_shard_keys(if (!is.null(cinv)) cinv else data.frame(codinv=integer(0), grp=integer(0)),
                             c("codinv","grp"))
  manifest_append(g, "donorpool", NA, dp_file, vdp$n_rows, vdp$n_unique_keys, vdp$key_ok, "complete")
  # inventor-stage pooled SDs (treated + control candidate pool)
  if (!is.null(cinv)) {
    pool_inv <- rbind(tcv[, INV_MATCH_VARS], cinv[, INV_MATCH_VARS])
  } else pool_inv <- tcv[, INV_MATCH_VARS]
  sd_inv <- pooled_sds(pool_inv, INV_MATCH_VARS)
  # family indicators: RAW 0/1 mismatch scaled by FAMILY_PENALTY_WEIGHT (dividing a
  # gap by 1/w == multiplying by w), NOT by their pooled binary SD (which would let
  # a rare-family mismatch dominate). Continuous vars keep standardized gaps.
  sd_inv[INV_FAMILY_VARS] <- 1 / FAMILY_PENALTY_WEIGHT
  cinv_dt <- if (!is.null(cinv)) data.table::as.data.table(cinv) else NULL
  if (!is.null(cinv_dt)) data.table::setkey(cinv_dt, grp)

  # ================= STAGE 2 per profile =================
  core_inv <- c("log_patent_count_5y","patent_trajectory","career_age","tenure","exclusivity")
  for (pn in names(profiles)) {
    cal <- profiles[[pn]]; fm <- firm_matches[[pn]]
    rows <- list()
    if (nrow(fm) > 0 && !is.null(cinv_dt)) {
      firms_by_deal <- split(fm$control_group, fm$deal_id)
      for (i in seq_len(nrow(tcv))) {
        d_id <- tcv$deal_id[i]
        fnms <- firms_by_deal[[as.character(d_id)]]
        if (is.null(fnms)) next                         # deal firm-unsupported this profile
        tvec <- unlist(tcv[i, INV_MATCH_VARS]); names(tvec) <- INV_MATCH_VARS
        if (any(!is.finite(tvec[core_inv]))) next        # treated missing core var
        cand <- cinv_dt[.(fnms)]
        cand <- cand[stats::complete.cases(cand[, ..core_inv])]  # no missing core var enters distance
        if (nrow(cand) < N_INV_MATCH) next
        Cm <- as.matrix(cand[, ..INV_MATCH_VARS])
        # caliper on continuous vars only; family indicators penalise distance, not a block
        res <- knn_rank(tvec, Cm, sd_inv, caliper = cal, caliper_cols = INV_CALIPER_COLS)
        if (length(res$idx) < N_INV_MATCH) next
        # dedup by person (codinv): keep min-distance instance, then take 3 nearest distinct
        ord <- data.table::data.table(cand_row = res$idx,
                                       codinv = cand$codinv[res$idx],
                                       dist = res$dist, maxabs = res$maxabs,
                                       res_pos = seq_along(res$idx))
        ord <- ord[!duplicated(codinv)]                          # already ordered by dist
        if (nrow(ord) < N_INV_MATCH) next                        # not enough distinct persons
        take <- ord[seq_len(N_INV_MATCH)]
        selc <- cand[take$cand_row]
        gapdf <- as.data.frame(res$gaps[take$res_pos, , drop = FALSE]); names(gapdf) <- INV_GAP_COLS
        rows[[length(rows) + 1L]] <- cbind(
          data.frame(cohort = g, profile = pn, deal_id = d_id,
                     treated_codinv = tcv$codinv[i], target_group = tcv$target_group[i],
                     control_codinv = selc$codinv, control_group = selc$grp,
                     rank = seq_len(N_INV_MATCH), dist = take$dist, max_abs_gap = take$maxabs,
                     weight = INV_WEIGHT,
                     log_patent_count_5y = selc$log_patent_count_5y,
                     patent_trajectory = selc$patent_trajectory,
                     career_age = selc$career_age, tenure = selc$tenure,
                     exclusivity = selc$exclusivity,
                     fam_small_molecule = selc$fam_small_molecule,
                     fam_biotech = selc$fam_biotech, fam_formulation = selc$fam_formulation),
          gapdf)
      }
    }
    im <- if (length(rows)) do.call(rbind, rows) else data.frame(cohort = integer(0))
    p <- shard_file(g, "inv", pn)
    lm_write_parquet(con, im, p)
    v <- validate_shard_keys(if (nrow(im)) im else data.frame(a=integer(0),b=integer(0)),
                             if (nrow(im)) c("treated_codinv","control_codinv") else c("a","b"))
    # weight-sum-to-1 check per treated inventor
    wok <- TRUE
    if (nrow(im)) {
      ws <- tapply(im$weight, im$treated_codinv, sum)
      wok <- all(abs(ws - 1) < 1e-9)
    }
    manifest_append(g, "inv", pn, p, v$n_rows, v$n_unique_keys, v$key_ok && wok, "complete")
    n_supp <- if (nrow(im)) length(unique(im$treated_codinv)) else 0L
    lm_section(sprintf("profile %-11s: %d treated inventors supported (%d matches); weights_ok=%s",
                       pn, n_supp, nrow(im), wok))
  }
  invisible(TRUE)
}

# helper: read parquet via duckdb (arrow may be absent)
# (defined after use; hoisted by R at parse for function calls above)

for (g in COHORTS_ARG) {
  ok <- tryCatch(process_cohort(g), error = function(e) {
    lm_section(sprintf("COHORT %d FAILED: %s", g, conditionMessage(e))); FALSE })
  if (!ok) { lm_section("stopping; completed cohort shards preserved"); break }
}
lm_section(sprintf("elapsed: %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
lm_banner("13c DONE")
