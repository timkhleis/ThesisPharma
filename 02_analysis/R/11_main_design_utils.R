# ============================================================================
# 11_main_design_utils.R  --  shared functions for the Main DiD v1 pipeline
# ----------------------------------------------------------------------------
# Reuses the certified 08t qualification logic (qualify_sql, keep_first_exposure)
# and adds: IPC-family classification, two-stage entropy-balancing diagnostics,
# event-study coefficient extraction, and the Delta-generalized control builder.
# No top-level execution: functions only. Source AFTER 11a_main_design_config.R.
# ============================================================================

# --- Console + IO helpers ---------------------------------------------------
banner  <- function(msg) message("\n", strrep("=", 76), "\n== ", msg, "\n", strrep("=", 76))
section <- function(msg) message("\n-- ", msg)

write_audit  <- function(df, name) {
  df <- cbind(design_version = DESIGN_VERSION, df)
  utils::write.csv(df, file.path(AUDIT_DIR, name), row.names = FALSE, na = "")
  invisible(file.path(AUDIT_DIR, name))
}
write_result <- function(df, name) {
  df <- cbind(design_version = DESIGN_VERSION, df)
  utils::write.csv(df, file.path(RESULTS_DIR, name), row.names = FALSE, na = "")
  invisible(file.path(RESULTS_DIR, name))
}

# ============================================================================
# Parameterized qualification (faithful port of 08t qualify_sql, generalized)
#   shift  : ref_year = deal_year - shift  (0 = treated; CONTROL_LAG = control)
#   spine  : table/view with deal_id, cassi_deal_group_id, deal_year,
#            target_group, acquirer_group, todrop_acq
#   Adds qualification_route in {target_resolved, target_candidate,
#   acquirer_transition}. One row per (codinv, deal_id).
# ============================================================================
qualify_sql <- function(shift, spine = "cassi_deal_group_spine") {
  sprintf("
WITH usable_deals AS (
  SELECT
    CAST(deal_id AS BIGINT)              AS deal_id,
    CAST(cassi_deal_group_id AS BIGINT)  AS cassi_deal_group_id,
    CAST(deal_year AS INTEGER)           AS deal_year,
    CAST(deal_year AS INTEGER) - %1$d    AS ref_year,
    target_group, acquirer_group, todrop_acq,
    CASE WHEN acquirer_group IS NOT NULL
          AND CAST(acquirer_group AS VARCHAR) NOT LIKE '999%%'
          AND NOT todrop_acq
         THEN TRUE ELSE FALSE END        AS status_eligible
  FROM %2$s
),
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
  (l.ref_year - l.year) AS qualifying_gap,
  CASE
    WHEN l.target_resolved  THEN 'target_resolved'
    WHEN l.target_candidate THEN 'target_candidate'
    ELSE 'acquirer_transition'
  END AS qualification_route
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
", shift, spine)
}

# exposure_rank == 1 per inventor (04c rule), ordered by (order_year, deal_id).
keep_first_exposure <- function(df, order_year_col) {
  df <- df[order(df$codinv, df[[order_year_col]], df$deal_id), ]
  df$exposure_rank <- stats::ave(seq_len(nrow(df)), df$codinv, FUN = seq_along)
  df[df$exposure_rank == 1L, , drop = FALSE]
}

# ============================================================================
# IPC broad-family classifier (zero-padded ipc_code; C07K before C07).
# Returns a SQL CASE expression that yields the family name for column `col`.
# ============================================================================
ipc_family_case_sql <- function(col = "ipc_code") {
  sprintf("
    CASE
      WHEN SUBSTR(%1$s,1,4) = 'C07K'
        OR SUBSTR(%1$s,1,3) = 'C12'
        OR SUBSTR(%1$s,1,7) IN ('A61K038','A61K039') THEN 'biotech'
      WHEN SUBSTR(%1$s,1,7) = 'A61K009'               THEN 'formulation'
      WHEN (SUBSTR(%1$s,1,3) = 'C07' AND SUBSTR(%1$s,1,4) <> 'C07K')
        OR SUBSTR(%1$s,1,7) = 'A61K031'               THEN 'small_molecule'
      ELSE 'other'
    END", col)
}

# ============================================================================
# Balance / weight diagnostics (base-R; cobalt used for official love plots)
# ============================================================================
smd_weighted <- function(x, treated, w = NULL) {
  if (is.null(w)) w <- rep(1, length(x))
  t <- treated == 1L; c <- treated == 0L
  mt <- stats::weighted.mean(x[t], w[t]); mc <- stats::weighted.mean(x[c], w[c])
  vt <- sum(w[t] * (x[t] - mt)^2) / sum(w[t])
  sdt <- sqrt(vt)
  if (!is.finite(sdt) || sdt == 0) return(0)
  (mt - mc) / sdt
}

ess <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (length(w) == 0) return(0)
  (sum(w)^2) / sum(w^2)
}

weight_quantile_diag <- function(w) {
  q <- stats::quantile(w, c(0, .5, .95, .99, 1), na.rm = TRUE)
  data.frame(min = q[1], median = q[2], p95 = q[3], p99 = q[4], max = q[5],
            ess = ess(w), n = length(w), row.names = NULL)
}

# [C5] ebal convergence: max abs WEIGHTED model-matrix column mean diff (raw, not SMD).
# mm = numeric model matrix (no intercept); w = analysis mass (s.weights * ebal weights).
model_matrix_cols <- function(formula, data) {
  mm <- stats::model.matrix(formula, data)
  mm[, colnames(mm) != "(Intercept)", drop = FALSE]
}
ebal_max_meandiff <- function(mm, treated, w) {
  tw <- w[treated == 1L]; cw <- w[treated == 0L]
  d <- vapply(seq_len(ncol(mm)), function(j)
    abs(stats::weighted.mean(mm[treated == 1L, j], tw) -
        stats::weighted.mean(mm[treated == 0L, j], cw)), numeric(1))
  max(d)
}

standardize_continuous <- function(x) {
  s <- stats::sd(x, na.rm = TRUE)
  if (!is.finite(s) || s == 0) return(x - mean(x, na.rm = TRUE))
  (x - mean(x, na.rm = TRUE)) / s
}

# Structural model-matrix inspection: zero-variance and single-arm columns.
inspect_model_matrix <- function(df, covars, treated_col = "treated") {
  out <- lapply(covars, function(v) {
    x <- df[[v]]
    zero_var <- length(unique(x[!is.na(x)])) <= 1L
    single_arm <- FALSE
    if (is.numeric(x) && length(unique(x[!is.na(x)])) == 2L) {
      # binary indicator: is it all-zero in one arm?
      tt <- tapply(x, df[[treated_col]], function(z) sum(z != 0, na.rm = TRUE))
      single_arm <- any(tt == 0)
    }
    data.frame(covariate = v, n_missing = sum(is.na(x)),
               zero_variance = zero_var, single_arm_binary = single_arm)
  })
  do.call(rbind, out)
}

# ============================================================================
# Event-study extraction + inference (fixest); mirrors 08u idiom.
# ============================================================================
extract_es_coefs <- function(mod, base_e) {
  ct <- as.data.frame(fixest::coeftable(mod)); ct$term <- rownames(ct)
  ct <- ct[grepl("^event_time::.*:treated$", ct$term), ]
  ct$event_time <- as.integer(sub("^event_time::(-?\\d+):treated$", "\\1", ct$term))
  ci <- stats::confint(mod); ci$term <- rownames(ci)
  ci <- ci[ci$term %in% ct$term, ]; names(ci)[1:2] <- c("ci_low", "ci_high")
  ct <- merge(ct, ci[, c("term", "ci_low", "ci_high")], by = "term")
  out <- data.frame(event_time = ct$event_time, att = ct$Estimate,
                    se = ct$`Std. Error`, ci_low = ct$ci_low, ci_high = ct$ci_high)
  out <- rbind(out, data.frame(event_time = base_e, att = 0, se = 0, ci_low = 0, ci_high = 0))
  out[order(out$event_time), ]
}

# Equal-weight average of treated:event_time coefs over `periods`, with the full
# clustered covariance (L b, sqrt(L V L')). CIs conditional on estimated weights.
post_average <- function(mod, periods = PRIMARY_POST) {
  b <- stats::coef(mod); V <- stats::vcov(mod); nm <- names(b)
  terms <- sprintf("event_time::%d:treated", periods)
  keep <- terms[terms %in% nm]
  if (length(keep) == 0L)
    return(data.frame(estimate = NA_real_, se = NA_real_, ci_low = NA_real_,
                      ci_high = NA_real_, n_terms = 0L))
  L <- stats::setNames(rep(0, length(b)), nm); L[keep] <- 1 / length(keep)
  est <- sum(L * b); se <- sqrt(as.numeric(t(L) %*% V %*% L))
  data.frame(estimate = est, se = se, ci_low = est - 1.96 * se,
             ci_high = est + 1.96 * se, n_terms = length(keep))
}

# Joint Wald chi-square that all treated:event_time coefs over `periods` are 0.
joint_pretrend <- function(mod, periods) {
  b <- stats::coef(mod); V <- stats::vcov(mod); nm <- names(b)
  terms <- sprintf("event_time::%d:treated", periods)
  keep <- terms[terms %in% nm]
  if (length(keep) < 1L) return(data.frame(stat = NA_real_, df = 0L, p = NA_real_))
  bb <- b[keep]; VV <- V[keep, keep, drop = FALSE]
  stat <- tryCatch(as.numeric(t(bb) %*% solve(VV) %*% bb), error = function(e) NA_real_)
  df <- length(keep)
  data.frame(stat = stat, df = df, p = stats::pchisq(stat, df, lower.tail = FALSE))
}

# ============================================================================
# Delta-generalized future-treated control builder
#   Resolves the placebo-date target group (firm_group @ ref_year-1), qualifies
#   controls against it, applies lineage-aware cleanliness, returns diagnostics.
#   `con` must be an open DuckDB connection; uses duckdb_register (read-only OK).
# ============================================================================
resolve_placebo_spine <- function(con, control_lag) {
  # Per thesis deal: distinct placebo-date group across its target companies,
  # measured at ref_year-1 = (deal_year - control_lag - 1). Also pre-period
  # (g-6..g-1) stability audit and real-vs-placebo comparison.
  sql <- sprintf("
    WITH comps AS (
      SELECT s.deal_id, s.cassi_deal_group_id, s.deal_year, s.acquirer_group, s.todrop_acq,
             s.target_group AS real_target_group_at_deal,
             CAST(s.deal_year AS INTEGER) - %1$d       AS placebo_g,          -- g
             CAST(s.deal_year AS INTEGER) - %1$d - 1   AS placebo_ref_year,   -- g-1
             CAST(TRIM(x.c) AS DOUBLE)                  AS compcod
      FROM cassi_deal_group_spine s,
           UNNEST(string_split(s.target_compcod_list, ';')) AS x(c)
      WHERE TRIM(x.c) <> ''
    ),
    placebo_at_g AS (
      SELECT c.deal_id, c.cassi_deal_group_id, c.deal_year, c.acquirer_group, c.todrop_acq,
             c.real_target_group_at_deal, c.placebo_g,
             fg.id_group AS placebo_group
      FROM comps c
      LEFT JOIN firm_group fg
        ON fg.compcod = c.compcod AND fg.year = c.placebo_ref_year
    ),
    preperiod AS (   -- g-6..g-1 stability across the deal's target companies
      SELECT c.deal_id,
             COUNT(DISTINCT fg.id_group) AS n_distinct_preperiod_group_ids,
             SUM(CASE WHEN fg.id_group IS NULL THEN 1 ELSE 0 END) AS n_missing_group_years
      FROM comps c
      LEFT JOIN firm_group fg
        ON fg.compcod = c.compcod
       AND fg.year BETWEEN c.placebo_g - 6 AND c.placebo_g - 1
      GROUP BY c.deal_id
    ),
    agg AS (
      SELECT deal_id, ANY_VALUE(cassi_deal_group_id) AS cassi_deal_group_id,
             ANY_VALUE(deal_year) AS deal_year, ANY_VALUE(acquirer_group) AS acquirer_group,
             ANY_VALUE(todrop_acq) AS todrop_acq,
             ANY_VALUE(real_target_group_at_deal) AS real_target_group_at_deal,
             ANY_VALUE(placebo_g) AS placebo_g,
             COUNT(DISTINCT placebo_group) AS n_placebo_groups,
             MIN(placebo_group) AS min_placebo_group,
             MAX(placebo_group) AS max_placebo_group
      FROM placebo_at_g GROUP BY deal_id
    )
    SELECT a.deal_id, a.cassi_deal_group_id, a.deal_year, a.acquirer_group, a.todrop_acq,
           a.real_target_group_at_deal, a.placebo_g,
           a.n_placebo_groups,
           CASE WHEN a.n_placebo_groups = 1 THEN a.min_placebo_group ELSE NULL END AS analysis_target_group_id,
           CASE WHEN a.n_placebo_groups = 1 THEN 'unique'
                WHEN a.n_placebo_groups = 0 THEN 'missing'
                ELSE 'ambiguous' END AS placebo_status,
           p.n_distinct_preperiod_group_ids, p.n_missing_group_years,
           CASE WHEN p.n_distinct_preperiod_group_ids <= 1 THEN TRUE ELSE FALSE END AS preperiod_group_stable
    FROM agg a LEFT JOIN preperiod p ON p.deal_id = a.deal_id
  ", control_lag)
  DBI::dbGetQuery(con, sql)
}

build_control_arm <- function(con, control_lag, stack_lo = STACK_LO, stack_hi = 2015L - control_lag) {
  L <- control_lag
  # 1. placebo-group resolution + identity audit
  ident <- resolve_placebo_spine(con, L)
  spine <- ident[ident$placebo_status == "unique" &
                   !is.na(ident$analysis_target_group_id), ]
  # placebo control spine view (columns qualify_sql expects)
  spine_view <- data.frame(
    deal_id = as.integer(spine$deal_id),
    cassi_deal_group_id = as.integer(spine$cassi_deal_group_id),
    deal_year = as.integer(spine$deal_year),
    target_group = as.numeric(spine$analysis_target_group_id),
    acquirer_group = as.numeric(spine$acquirer_group),
    todrop_acq = as.logical(spine$todrop_acq)
  )
  view_nm <- sprintf("control_spine_%d", L)
  duckdb::duckdb_register(con, view_nm, spine_view)
  on.exit(duckdb::duckdb_unregister(con, view_nm), add = TRUE)

  # 2. qualify controls against placebo spine (ref_year = deal_year - L = g)
  q <- DBI::dbGetQuery(con, qualify_sql(L, view_nm))
  q$codinv    <- as.numeric(q$codinv)
  q$deal_id   <- as.integer(q$deal_id)
  q$deal_year <- as.integer(q$deal_year)
  q$ref_year  <- as.integer(q$ref_year)

  # 3. eligible stacks: ref_year (=g) in [stack_lo, stack_hi]; deal_year=g+L
  q <- q[q$ref_year >= stack_lo & q$ref_year <= stack_hi &
           q$deal_year >= (stack_lo + L) & q$deal_year <= (stack_hi + L), ]
  ctrl <- keep_first_exposure(q, "ref_year")
  n_qualified <- nrow(ctrl)
  ctrl$analysis_target_group_id <-
    spine$analysis_target_group_id[match(ctrl$deal_id, spine$deal_id)]

  # 4. lineage-aware cleanliness flags
  #    (a) inventor real exposures (target_cohort_own)
  tco <- DBI::dbGetQuery(con, "
    SELECT DISTINCT CAST(codinv AS DOUBLE) AS codinv, CAST(deal_id AS INTEGER) AS r_deal_id,
           CAST(deal_year AS INTEGER) AS r_deal_year FROM target_cohort_own")
  im <- merge(ctrl[, c("codinv", "deal_id", "ref_year")], tco, by = "codinv")
  im$is_designated <- im$r_deal_id == im$deal_id
  im$prior     <- (!im$is_designated) & (im$r_deal_year <  im$ref_year)
  im$competing <- (!im$is_designated) & (im$r_deal_year >= im$ref_year) &
                  (im$r_deal_year <= im$ref_year + L)
  agg_inv <- aggregate(cbind(prior, competing) ~ codinv + deal_id, data = im, FUN = any)
  ctrl <- merge(ctrl, agg_inv, by = c("codinv", "deal_id"), all.x = TRUE)
  ctrl$prior_inventor_exposure     <- isTRUE_vec(ctrl$prior)
  ctrl$competing_inventor_exposure <- isTRUE_vec(ctrl$competing)
  ctrl$prior <- NULL; ctrl$competing <- NULL

  #    (b) firm target/acquirer roles from cassi_deal_spine (group + compcod lineage)
  firm_roles <- DBI::dbGetQuery(con, "
    SELECT CAST(target_group AS DOUBLE) AS target_group,
           CAST(acquirer_group AS DOUBLE) AS acquirer_group,
           CAST(deal_year AS INTEGER) AS deal_year,
           CAST(cassi_deal_row_id AS BIGINT) AS row_id
    FROM cassi_deal_spine WHERE deal_year IS NOT NULL")
  grp <- ctrl$analysis_target_group_id; g <- ctrl$ref_year
  # prior/competing target roles, acquirer roles for the focal placebo group
  ctrl$prior_firm_target_deal <- vapply(seq_len(nrow(ctrl)), function(i) {
    any(firm_roles$target_group == grp[i] & firm_roles$deal_year < g[i], na.rm = TRUE)
  }, logical(1))
  ctrl$competing_firm_target_deal <- vapply(seq_len(nrow(ctrl)), function(i) {
    any(firm_roles$target_group == grp[i] &
          firm_roles$deal_year >= g[i] & firm_roles$deal_year <= g[i] + EVENT_HI &
          firm_roles$deal_year != (g[i] + L), na.rm = TRUE)
  }, logical(1))
  # [C2] acquirer status is DIAGNOSTIC, never an exclusion (a control may be an acquirer)
  ctrl$acquirer_event_in_window <- vapply(seq_len(nrow(ctrl)), function(i) {
    any(firm_roles$acquirer_group == grp[i] &
          firm_roles$deal_year >= g[i] + EVENT_LO & firm_roles$deal_year <= g[i] + EVENT_HI,
        na.rm = TRUE)
  }, logical(1))
  ctrl$ever_acquirer <- vapply(seq_len(nrow(ctrl)), function(i) {
    any(firm_roles$acquirer_group == grp[i], na.rm = TRUE)
  }, logical(1))

  # 5. exclusion flags (target-side + inventor exposure only) + diagnostic acquirer flags [C2]
  exclusion_cols <- c("prior_inventor_exposure", "competing_inventor_exposure",
                      "prior_firm_target_deal", "competing_firm_target_deal")
  diag_cols <- c("acquirer_event_in_window", "ever_acquirer")
  for (fc in c(exclusion_cols, diag_cols)) ctrl[[fc]] <- isTRUE_vec(ctrl[[fc]])
  ctrl$any_exclusion <- Reduce(`|`, ctrl[exclusion_cols])
  units <- ctrl[!ctrl$any_exclusion, , drop = FALSE]

  list(
    control_lag = L, stack_lo = stack_lo, stack_hi = stack_hi,
    identity = ident, units = units, all_qualified = ctrl,
    n_qualified = n_qualified, flag_cols = c(exclusion_cols, diag_cols),
    exclusion_cols = exclusion_cols, diag_cols = diag_cols
  )
}

# small helper: coerce possibly-NA logical vector to FALSE-filled logical
isTRUE_vec <- function(x) { x <- as.logical(x); x[is.na(x)] <- FALSE; x }

# ============================================================================
# Shared covariate computation (identical definitions for g+7 and never-target)
# ============================================================================
# firm_keys: data.frame(fk_id, id_group, g). Returns fk_id + derived firm covars.
compute_firm_covariates <- function(con, firm_keys) {
  duckdb::duckdb_register(con, "firm_keys", firm_keys[, c("fk_id", "id_group", "g")])
  on.exit(duckdb::duckdb_unregister(con, "firm_keys"), add = TRUE)
  fam_case <- ipc_family_case_sql("ipc.ipc_code")
  fc <- DBI::dbGetQuery(con, sprintf("
    WITH fk AS (SELECT fk_id, CAST(id_group AS DOUBLE) grp, CAST(g AS INTEGER) g FROM firm_keys),
    pat AS (SELECT fk.fk_id, fk.g, pcl.appln_id, MIN(pcl.year) yr
            FROM fk JOIN patent_company_link pcl ON pcl.id_group=fk.grp AND pcl.year<=fk.g-3
            GROUP BY fk.fk_id, fk.g, pcl.appln_id),
    pstat AS (SELECT fk_id, COUNT(*) stock, MIN(yr) first_year,
              COUNT(*) FILTER (WHERE yr BETWEEN g-6 AND g-5) early,
              COUNT(*) FILTER (WHERE yr BETWEEN g-4 AND g-3) recent,
              COUNT(*) FILTER (WHERE yr BETWEEN g-6 AND g-3) win_patents FROM pat GROUP BY fk_id),
    invc AS (SELECT fk.fk_id, COUNT(DISTINCT pi.codinv) n_inv
             FROM fk JOIN patent_company_link pcl ON pcl.id_group=fk.grp AND pcl.year BETWEEN fk.g-6 AND fk.g-3
                     JOIN patent_inventor pi ON pi.appln_id=pcl.appln_id GROUP BY fk.fk_id),
    famrows AS (SELECT DISTINCT fk.fk_id, pcl.appln_id, %s AS fam
                FROM fk JOIN patent_company_link pcl ON pcl.id_group=fk.grp AND pcl.year BETWEEN fk.g-6 AND fk.g-3
                        JOIN ipc ON ipc.appln_id=pcl.appln_id),
    kcnt AS (SELECT fk_id, appln_id, COUNT(*) k FROM famrows GROUP BY fk_id, appln_id),
    alloc AS (SELECT fr.fk_id, fr.fam, SUM(1.0/kc.k) w FROM famrows fr
              JOIN kcnt kc ON kc.fk_id=fr.fk_id AND kc.appln_id=fr.appln_id GROUP BY fr.fk_id, fr.fam),
    tot AS (SELECT fk_id, SUM(w) tot FROM alloc GROUP BY fk_id),
    shares AS (SELECT a.fk_id,
      SUM(CASE WHEN a.fam='small_molecule' THEN a.w ELSE 0 END)/MAX(t.tot) AS share_small_molecule,
      SUM(CASE WHEN a.fam='biotech'        THEN a.w ELSE 0 END)/MAX(t.tot) AS share_biotech,
      SUM(CASE WHEN a.fam='formulation'    THEN a.w ELSE 0 END)/MAX(t.tot) AS share_formulation
      FROM alloc a JOIN tot t ON t.fk_id=a.fk_id GROUP BY a.fk_id)
    SELECT fk.fk_id, fk.g,
      COALESCE(ps.stock,0) AS firm_patent_stock, ps.first_year AS firm_first_year,
      COALESCE(ps.early,0) AS patents_early, COALESCE(ps.recent,0) AS patents_recent,
      COALESCE(ps.win_patents,0) AS win_patents, COALESCE(ic.n_inv,0) AS firm_inventor_count,
      sh.share_small_molecule, sh.share_biotech, sh.share_formulation
    FROM fk LEFT JOIN pstat ps ON ps.fk_id=fk.fk_id
            LEFT JOIN invc ic ON ic.fk_id=fk.fk_id
            LEFT JOIN shares sh ON sh.fk_id=fk.fk_id", fam_case))
  # derived covariates + structural no-history indicators [B2]
  fc$no_firm_patent_by_g3 <- as.integer(fc$firm_patent_stock == 0)
  fc$no_technology_activity_g6_g3 <- as.integer(fc$win_patents == 0 | is.na(fc$share_small_molecule))
  fc$log_firm_patent_stock   <- log1p(fc$firm_patent_stock)
  fc$log_firm_inventor_count <- log1p(fc$firm_inventor_count)
  fc$log_patents_early  <- log1p(fc$patents_early)
  fc$log_patents_recent <- log1p(fc$patents_recent)
  fc$observed_firm_patent_age <- ifelse(fc$no_firm_patent_by_g3 == 1L, 0,
    (fc$g - 3) - fc$firm_first_year)
  for (s in c("share_small_molecule","share_biotech","share_formulation"))
    fc[[s]][is.na(fc[[s]])] <- 0
  fc
}

# inv_keys: data.frame(codinv, g, grp). Returns codinv,g,grp + inventor covars.
compute_inventor_covariates <- function(con, inv_keys) {
  duckdb::duckdb_register(con, "inv_keys", inv_keys[, c("codinv", "g", "grp")])
  on.exit(duckdb::duckdb_unregister(con, "inv_keys"), add = TRUE)
  fam_case <- ipc_family_case_sql("iiy.ipc_code")
  ic <- DBI::dbGetQuery(con, sprintf("
    WITH u AS (SELECT CAST(codinv AS BIGINT) codinv, CAST(g AS INTEGER) g, CAST(grp AS DOUBLE) grp FROM inv_keys),
    career AS (SELECT CAST(codinv AS BIGINT) codinv, MIN(year) FILTER (WHERE patent_count>0) cfy
               FROM inventor_year GROUP BY codinv),
    stock AS (SELECT u.codinv,u.g, COALESCE(SUM(iy.patent_count),0) s
              FROM u LEFT JOIN inventor_year iy ON CAST(iy.codinv AS BIGINT)=u.codinv
               AND iy.year BETWEEN u.g-5 AND u.g-1 GROUP BY u.codinv,u.g),
    tenure AS (SELECT u.codinv,u.g,u.grp, MIN(ia.year) first_aff
               FROM u JOIN inventor_affiliation_own ia ON ia.codinv=u.codinv AND ia.year<=u.g-1
                AND (ia.resolved_group=u.grp OR list_contains(string_split(ia.candidate_group_list,';'),
                     CAST(CAST(u.grp AS BIGINT) AS VARCHAR)))
               GROUP BY u.codinv,u.g,u.grp),
    excl AS (SELECT u.codinv,u.g,u.grp,
        COUNT(DISTINCT CASE WHEN pcl.id_group=u.grp THEN pi.appln_id END) AS n_target,
        COUNT(DISTINCT pi.appln_id) AS n_total
      FROM u JOIN patent_inventor pi ON pi.codinv=u.codinv
             JOIN patent_company_link pcl ON pcl.appln_id=pi.appln_id AND pcl.year BETWEEN u.g-5 AND u.g-1
      GROUP BY u.codinv,u.g,u.grp),
    fam AS (SELECT u.codinv,u.g, %s AS fam, SUM(iiy.patent_count) c
            FROM u JOIN inventor_ipc_year iiy ON CAST(iiy.codinv AS BIGINT)=u.codinv
             AND iiy.year BETWEEN u.g-5 AND u.g-1 GROUP BY u.codinv,u.g, %s),
    modal AS (SELECT codinv,g,fam modal_family FROM
              (SELECT codinv,g,fam, ROW_NUMBER() OVER(PARTITION BY codinv,g
                 ORDER BY c DESC, CASE fam WHEN 'small_molecule' THEN 1 WHEN 'biotech' THEN 2
                            WHEN 'formulation' THEN 3 ELSE 4 END) rn FROM fam) WHERE rn=1)
    SELECT u.codinv, u.g, u.grp,
      (u.g-1) - c.cfy AS observed_inventor_career_age,
      (u.g-1) - te.first_aff AS observed_target_patent_tenure,
      LN(1 + st.s) AS log_inventor_patent_stock,
      CASE WHEN ex.n_total>0 THEN CAST(ex.n_target AS DOUBLE)/ex.n_total ELSE NULL END AS target_exclusivity,
      COALESCE(md.modal_family,'other') AS modal_family
    FROM u LEFT JOIN career c ON c.codinv=u.codinv
           LEFT JOIN stock st ON st.codinv=u.codinv AND st.g=u.g
           LEFT JOIN tenure te ON te.codinv=u.codinv AND te.g=u.g AND te.grp=u.grp
           LEFT JOIN excl ex ON ex.codinv=u.codinv AND ex.g=u.g AND ex.grp=u.grp
           LEFT JOIN modal md ON md.codinv=u.codinv AND md.g=u.g", fam_case, fam_case))
  ic$codinv <- as.numeric(ic$codinv); ic$g <- as.integer(ic$g); ic$grp <- as.numeric(ic$grp)
  ic
}

# ============================================================================
# Never-(observed-)target control arm [rev.5 addendum]
#   Universe: pharma-patenting groups minus ever-target groups (target-side only;
#   acquirers retained; ambiguous target histories conservatively excluded [C4]).
#   Assignment: latest affiliation in [g-5,g-1] resolves to a never-target group.
#   Cleanliness [C3]: drop (codinv,stack) with any prior (deal_year<g) or competing
#   ([g,g+3]) real target acquisition.
# ============================================================================
build_never_target_arm <- function(con, stacks = STACK_LO:STACK_HI) {
  fam_case <- ipc_family_case_sql("ipc.ipc_code")
  # --- universe: never-observed-target, pharma-relevant groups ---
  # ever_target (target-side only; +/-2y compcod->group window = conservative [C4])
  ever_sql <- "
    SELECT DISTINCT id_group FROM (
      SELECT target_group id_group FROM cassi_deal_spine WHERE target_group IS NOT NULL
      UNION ALL SELECT target_group_pre  FROM cassi_deal_spine WHERE target_group_pre IS NOT NULL
      UNION ALL SELECT target_group_post FROM cassi_deal_spine WHERE target_group_post IS NOT NULL
      UNION ALL SELECT fg.id_group FROM cassi_deal_spine s
        JOIN firm_group fg ON fg.compcod=s.target_compcod AND fg.year BETWEEN s.deal_year-2 AND s.deal_year
        WHERE s.target_compcod IS NOT NULL
      UNION ALL SELECT fg.id_group FROM cassi_deal_group_spine gs,
          UNNEST(string_split(gs.target_compcod_list, ';')) AS x(c)
        JOIN firm_group fg ON fg.compcod=CAST(TRIM(x.c) AS DOUBLE) AND fg.year BETWEEN gs.deal_year-2 AND gs.deal_year
        WHERE TRIM(x.c)<>''
    ) WHERE id_group IS NOT NULL"
  nt <- DBI::dbGetQuery(con, sprintf("
    WITH ever_target AS (%s),
    pharma_groups AS (
      SELECT DISTINCT pcl.id_group
      FROM patent_company_link pcl JOIN ipc ON ipc.appln_id=pcl.appln_id
      WHERE pcl.year BETWEEN 1988 AND 2015 AND %s IN ('small_molecule','biotech','formulation'))
    SELECT pg.id_group
    FROM pharma_groups pg
    WHERE pg.id_group IS NOT NULL AND pg.id_group NOT IN (SELECT id_group FROM ever_target)",
    ever_sql, fam_case))
  n_ever    <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) n FROM (%s)", ever_sql))$n
  n_pharma  <- DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT id_group) n FROM patent_company_link pcl JOIN ipc ON ipc.appln_id=pcl.appln_id WHERE pcl.year BETWEEN 1988 AND 2015")$n
  duckdb::duckdb_register(con, "nt_groups", data.frame(id_group = as.numeric(nt$id_group)))
  on.exit(duckdb::duckdb_unregister(con, "nt_groups"), add = TRUE)

  # --- assignment: latest affiliation in [g-5,g-1] to a never-target group ---
  stack_lit <- paste0("[", paste(as.integer(stacks), collapse = ","), "]")
  assigned <- DBI::dbGetQuery(con, sprintf("
    WITH stacks AS (SELECT UNNEST(%s) AS g),
    aff AS (SELECT s.g, CAST(ia.codinv AS BIGINT) codinv, ia.year, ia.resolved_group, ia.candidate_group_list
            FROM stacks s JOIN inventor_affiliation_own ia ON ia.year BETWEEN s.g-5 AND s.g-1),
    ly AS (SELECT g, codinv, MAX(year) mly FROM aff GROUP BY g, codinv),
    latest AS (SELECT a.g, a.codinv, a.year AS last_year, a.resolved_group, a.candidate_group_list
               FROM aff a JOIN ly ON a.g=ly.g AND a.codinv=ly.codinv AND a.year=ly.mly),
    resolved_match AS (SELECT l.g, l.codinv, l.last_year, l.resolved_group AS grp, 'resolved' AS match_source
                       FROM latest l JOIN nt_groups nt ON nt.id_group=l.resolved_group),
    candidate_match AS (SELECT l.g, l.codinv, ANY_VALUE(l.last_year) last_year,
                          MIN(CAST(TRIM(x.c) AS DOUBLE)) grp, 'candidate' AS match_source
                        FROM latest l, UNNEST(string_split(l.candidate_group_list,';')) AS x(c)
                        JOIN nt_groups nt ON nt.id_group=CAST(TRIM(x.c) AS DOUBLE)
                        WHERE TRIM(x.c)<>''
                          AND NOT EXISTS (SELECT 1 FROM nt_groups n2 WHERE n2.id_group=l.resolved_group)
                        GROUP BY l.g, l.codinv),
    assigned AS (SELECT * FROM resolved_match
                 UNION ALL
                 SELECT cm.* FROM candidate_match cm
                 WHERE NOT EXISTS (SELECT 1 FROM resolved_match rm WHERE rm.g=cm.g AND rm.codinv=cm.codinv))
    SELECT g AS stack, CAST(codinv AS DOUBLE) codinv, CAST(grp AS DOUBLE) underlying_group_id,
           match_source AS source, (g - last_year) AS qualifying_gap
    FROM assigned", stack_lit))
  assigned$codinv <- as.numeric(assigned$codinv)
  assigned$stack  <- as.integer(assigned$stack)
  assigned$underlying_group_id <- as.numeric(assigned$underlying_group_id)
  n_assigned <- nrow(assigned)

  # --- [C3] cleanliness: drop prior (<g) or competing ([g,g+3]) real target exposure ---
  tco <- DBI::dbGetQuery(con, "SELECT DISTINCT CAST(codinv AS DOUBLE) codinv,
                               CAST(deal_year AS INTEGER) dy FROM target_cohort_own")
  im <- merge(assigned[, c("codinv", "stack")], tco, by = "codinv")
  im$prior     <- im$dy <  im$stack
  im$competing <- im$dy >= im$stack & im$dy <= im$stack + 3L
  agg <- aggregate(cbind(prior, competing) ~ codinv + stack, data = im, FUN = any)
  assigned <- merge(assigned, agg, by = c("codinv", "stack"), all.x = TRUE)
  assigned$prior_target_exposure     <- isTRUE_vec(assigned$prior)
  assigned$competing_target_exposure <- isTRUE_vec(assigned$competing)
  assigned$prior <- NULL; assigned$competing <- NULL
  assigned$any_exclusion <- assigned$prior_target_exposure | assigned$competing_target_exposure

  # --- diagnostics: acquirer status (never excluding) ---
  acq_groups <- DBI::dbGetQuery(con, "SELECT DISTINCT CAST(acquirer_group AS DOUBLE) g,
                                MIN(deal_year) miny, MAX(deal_year) maxy
                                FROM cassi_deal_spine WHERE acquirer_group IS NOT NULL GROUP BY acquirer_group")
  assigned$ever_acquirer <- assigned$underlying_group_id %in% acq_groups$g
  # acquirer event in [g-5,g+3]
  acq_events <- DBI::dbGetQuery(con, "SELECT CAST(acquirer_group AS DOUBLE) g, CAST(deal_year AS INTEGER) dy
                                FROM cassi_deal_spine WHERE acquirer_group IS NOT NULL")
  ae <- merge(assigned[, c("codinv","stack","underlying_group_id")], acq_events,
              by.x = "underlying_group_id", by.y = "g")
  ae$inwin <- ae$dy >= ae$stack - 5L & ae$dy <= ae$stack + 3L
  ae_agg <- aggregate(inwin ~ codinv + stack + underlying_group_id, data = ae, FUN = any)
  assigned <- merge(assigned, ae_agg, by = c("codinv","stack","underlying_group_id"), all.x = TRUE)
  assigned$acquirer_event_in_window <- isTRUE_vec(assigned$inwin); assigned$inwin <- NULL

  units <- assigned[!assigned$any_exclusion, , drop = FALSE]
  units$control_source <- "never_observed_target"
  units$firm_stack_key <- paste(units$underlying_group_id, units$stack, sep = "|")
  units$group_stack_id <- match(units$firm_stack_key, unique(units$firm_stack_key))

  list(units = units, all_assigned = assigned, never_target_groups = nt$id_group,
       n_pharma_groups = n_pharma, n_ever_target = n_ever, n_never_target = nrow(nt),
       n_assigned = n_assigned)
}
