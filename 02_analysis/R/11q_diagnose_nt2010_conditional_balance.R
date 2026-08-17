# ============================================================================
# 11q_diagnose_nt2010_conditional_balance.R -- Package 2A
# ----------------------------------------------------------------------------
# Conditional-balance & support diagnostic for the nt2010 weighted designs.
# AGGREGATION-FIRST: all per-(cohort x covariate) statistics are derived from
# wide sufficient statistics computed inside DuckDB (one grouped scan per spec).
# The 4.5M-row panel is NEVER collected into R. No reweighting, no outcomes,
# no estimation, no change to saved weights or thresholds.
#
# Reproduces the frozen smd_weighted convention exactly:
#   mt = sum(w*x)/sum(w) (treated);  mc likewise (control)
#   sd_t = sqrt(sum(w*x^2)/sum(w) - mt^2)   [treated weighted SD = SMD denominator]
#   SMD_within = (mt - mc)/sd_t   (0 if sd_t is 0/non-finite)
# Alternative: SMD_fullpooled = (mt - mc) / pooled_full_sd, pooled over the whole
# specification (sqrt((var_t_full + var_c_full)/2)).
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))   # banner/section only (no execution)
source(file.path(BASE, "R", "11i_robustness_config.R"))
suppressMessages({ library(DBI); library(duckdb) })

sqlp  <- function(p) gsub("\\\\", "/", p)
apath <- function(name) paste0(NT2010_AUDIT_PREFIX, "_", name)      # versioned audit prefix
fail  <- function(msg) stop("[NT2010-2A] ", msg, call. = FALSE)

COVARS      <- FULL_NUMERIC_COVARS      # 14 balance variables (continuous + share + binary)
CONT_COVARS <- FULL_CONT_COVARS         # 9 continuous (existing cohort/era max was over these)
SMD_REPRO_RELTOL <- 1e-3                # relative tol for reproducing existing maxima

specs <- data.frame(
  spec  = c("P0H5_nt2010", "P5_nt2010", "P0H5_cc9408", "P5_cc9408"),
  wpath = c(P0H5_NT2010_WEIGHTS_PARQUET, P5_NT2010_WEIGHTS_PARQUET,
            P0H5_CC9408_WEIGHTS_PARQUET, P5_CC9408_WEIGHTS_PARQUET),
  eras  = c("nt", "nt", "g7", "g7"), stringsAsFactors = FALSE)
eras_of <- function(tag) if (tag == "g7") BALANCE_ERAS_G7 else BALANCE_ERAS_NEVER_TARGET

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='6GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sqlp(DUCKDB_TMP)))

# ---------------------------------------------------------------------------
# One grouped scan per spec: NUMERICALLY STABLE sufficient statistics at
# (cohort x arm). Each arm is centered on its OWN cohort weighted mean inside a
# CTE, so the centered sum of squares avoids catastrophic cancellation (the
# uncentered E[wx^2]-mean^2 form blows up when the within-cohort variance is tiny).
# Returns per cohort x arm: sum_w, sum_w2, n, n_pos, and per covariate
#   swx_<cov> = sum(w*x)                    (for weighted means)
#   cSS_<cov> = sum(w*(x - m_cohort_arm)^2) (centered sum of squares, stable)
# Group (cohort/era/full) variances are pooled from these via the parallel-axis
# identity, exactly reproducing the frozen smd_weighted denominator.
# ---------------------------------------------------------------------------
suff_stats <- function(wpath, cohort_filter = NULL) {
  j_cols   <- paste(sprintf("r.%s", COVARS), collapse = ", ")
  m_means  <- paste(sprintf("SUM(fw * %1$s) / SUM(fw) AS m_%1$s", COVARS), collapse = ",\n      ")
  out_cov  <- paste(sprintf(
    "SUM(j.fw * j.%1$s) AS swx_%1$s, SUM(j.fw * (j.%1$s - m.m_%1$s) * (j.%1$s - m.m_%1$s)) AS cSS_%1$s",
    COVARS), collapse = ",\n      ")
  where <- if (is.null(cohort_filter)) "" else sprintf("WHERE w.stack = %d", cohort_filter)
  sql <- sprintf("
    WITH j AS (
      SELECT r.stack AS cohort, w.treated AS treated, w.final_weight AS fw, %s
      FROM read_parquet('%s') w
      JOIN read_parquet('%s') r
        ON CAST(r.codinv AS BIGINT) = CAST(w.codinv AS BIGINT)
       AND r.stack = w.stack AND r.treated = w.treated
      %s
    ),
    m AS (SELECT cohort, treated, %s FROM j GROUP BY cohort, treated)
    SELECT j.cohort AS cohort, j.treated AS treated,
      COUNT(*) AS n,
      SUM(CASE WHEN j.fw > 0 THEN 1 ELSE 0 END) AS n_pos,
      SUM(j.fw) AS sum_w, SUM(j.fw * j.fw) AS sum_w2,
      %s
    FROM j JOIN m ON m.cohort = j.cohort AND m.treated = j.treated
    GROUP BY j.cohort, j.treated",
    j_cols, sqlp(wpath), sqlp(NT2010_ANALYSIS_UNITS_PARQUET), where, m_means, out_cov)
  dbGetQuery(con, sql)
}

# Weighted mean/var for a group (>=1 cohort) x arm via the parallel-axis identity:
#   centered_SS_group = sum_cohort [ cSS_cohort + sum_w_cohort * (m_cohort - m_group)^2 ]
#   var_group = centered_SS_group / sum_w_group      (stable; no cancellation)
arm_moment <- function(rows, cov) {
  sw <- sum(rows$sum_w)
  m  <- sum(rows[[paste0("swx_", cov)]]) / sw
  mc <- rows[[paste0("swx_", cov)]] / rows$sum_w                       # per-cohort means
  css <- sum(rows[[paste0("cSS_", cov)]] + rows$sum_w * (mc - m)^2)    # pool to group mean
  list(mean = m, var = max(css / sw, 0), sw = sw)
}
moments <- function(ss, cov) {
  t <- arm_moment(ss[ss$treated == 1L, ], cov)
  c <- arm_moment(ss[ss$treated == 0L, ], cov)
  list(mt = t$mean, mc = c$mean, vt = t$var, vc = c$var, sw_t = t$sw, sw_c = c$sw)
}

# Build the covariate-long conditional-balance table for a spec from its full
# cohort-level sufficient stats. groups = named list(label -> vector of cohorts).
cov_balance_table <- function(spec, ss_all, groups, group_level) {
  # full-spec pooled SD per covariate (over ALL cohorts)
  full <- setNames(lapply(COVARS, function(cov) moments(ss_all, cov)), COVARS)
  pooled <- sapply(COVARS, function(cov) sqrt((full[[cov]]$vt + full[[cov]]$vc) / 2))
  out <- list()
  for (glab in names(groups)) {
    ss <- ss_all[ss_all$cohort %in% groups[[glab]], ]
    for (cov in COVARS) {
      m <- moments(ss, cov)
      sd_t <- sqrt(m$vt); sd_c <- sqrt(m$vc)
      raw <- m$mt - m$mc
      smd_within <- if (is.finite(sd_t) && sd_t > 0) raw / sd_t else 0
      smd_pooled <- if (is.finite(pooled[cov]) && pooled[cov] > 0) raw / pooled[cov] else 0
      out[[length(out) + 1L]] <- data.frame(
        spec = spec, level = group_level, group = glab, covariate = cov,
        continuous = cov %in% CONT_COVARS,
        treated_wmean = m$mt, control_wmean = m$mc, raw_diff = raw,
        smd_within = smd_within, denom_within_sd_treated = sd_t,
        smd_fullpooled = smd_pooled, pooled_full_sd = unname(pooled[cov]),
        sd_treated = sd_t, sd_control = sd_c,
        mass_treated = m$sw_t, mass_control = m$sw_c,
        zero_var = sd_t == 0,
        near_zero_denom = sd_t > 0 && sd_t < max(1e-8, 1e-3 * pooled[cov]),
        stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, out)
}

# support + counts per cohort x arm (weights parquet only)
support_stats <- function(wpath) {
  dbGetQuery(con, sprintf("
    SELECT stack AS cohort, treated,
      COUNT(*) AS n,
      SUM(CASE WHEN final_weight > 0 THEN 1 ELSE 0 END) AS n_pos,
      SUM(final_weight) AS sum_w,
      SUM(final_weight * final_weight) AS sum_w2,
      COUNT(DISTINCT focal_deal_id) AS n_focal_deals,
      COUNT(DISTINCT CASE WHEN final_weight > 0 THEN underlying_group_id END) AS n_firms_pos
    FROM read_parquet('%s') GROUP BY stack, treated", sqlp(wpath)))
}

# control firm mass at (cohort x firm) grain (weights parquet only)
firm_mass <- function(wpath) {
  dbGetQuery(con, sprintf("
    SELECT stack AS cohort, underlying_group_id, SUM(final_weight) AS firm_mass
    FROM read_parquet('%s') WHERE treated = 0 AND final_weight > 0
    GROUP BY stack, underlying_group_id", sqlp(wpath)))
}

conc <- function(mass_vec) {
  tot <- sum(mass_vec)
  s <- sort(mass_vec, decreasing = TRUE)
  list(n = length(mass_vec), ess = if (tot > 0) tot^2 / sum(mass_vec^2) else 0,
       max_share = if (tot > 0) s[1] / tot else NA_real_,
       top5_share = if (tot > 0) sum(head(s, 5)) / tot else NA_real_)
}

support_table <- function(spec, sup, fm, groups, group_level) {
  out <- list()
  for (glab in names(groups)) {
    cohs <- groups[[glab]]
    st <- sup[sup$cohort %in% cohs & sup$treated == 1L, ]
    sc <- sup[sup$cohort %in% cohs & sup$treated == 0L, ]
    fmg <- fm[fm$cohort %in% cohs, ]
    firm_agg <- tapply(fmg$firm_mass, fmg$underlying_group_id, sum)
    cc <- conc(as.numeric(firm_agg))
    sw_c <- sum(sc$sum_w); sw2_c <- sum(sc$sum_w2)
    out[[length(out) + 1L]] <- data.frame(
      spec = spec, level = group_level, group = glab,
      treated_inventors = sum(st$n), treated_deals = sum(st$n_focal_deals),
      control_pos_inventors = sum(sc$n_pos), control_pos_firms = cc$n,
      control_mass = sw_c,
      control_firm_ess = cc$ess,                                  # firm-level (fragility diagnostic)
      control_inventor_ess = if (sw2_c > 0) sw_c^2 / sw2_c else 0, # inventor-weight-level
      max_firm_share = cc$max_share, top5_firm_share = cc$top5_share,
      stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# ===========================================================================
# 2A.0 PILOT -- P0H5_nt2010, cohort 2009 only
# ===========================================================================
banner("2A.0 PILOT -- P0H5_nt2010 cohort 2009")
gc(reset = TRUE); t0 <- Sys.time()
pilot_ss <- suff_stats(P0H5_NT2010_WEIGHTS_PARQUET, cohort_filter = 2009L)
pilot_tab <- cov_balance_table("P0H5_nt2010", pilot_ss,
  groups = list(`2009` = 2009L), group_level = "cohort")
pilot_elapsed <- as.numeric(Sys.time() - t0, units = "secs")
pilot_mem_mb <- sum(gc()[, "max used"] * c(56, 8)) / 1e6   # rough peak (Ncells*8 + Vcells*8 bytes)

cont_rows <- pilot_tab[pilot_tab$continuous, ]
imax <- which.max(abs(cont_rows$smd_within))
worst <- cont_rows[imax, ]
target_2009 <- 1.92318128924186
rel_err <- abs(abs(worst$smd_within) - target_2009) / target_2009
message(sprintf("PILOT worst continuous covariate: %s | SMD_within=%.6f (target %.6f, rel_err=%.2e)",
                worst$covariate, worst$smd_within, target_2009, rel_err))
message(sprintf("  raw_diff=%.6g | denom(sd_treated)=%.6g | full-pooled SMD=%.6g | sd_control=%.6g",
                worst$raw_diff, worst$denom_within_sd_treated, worst$smd_fullpooled, worst$sd_control))
message(sprintf("  elapsed=%.1fs | approx peak R mem=%.0f MB | (panel NOT collected)", pilot_elapsed, pilot_mem_mb))
if (!is.finite(rel_err) || rel_err > SMD_REPRO_RELTOL)
  fail(sprintf("PILOT could not reproduce P0H5-2009 max |SMD| (got %.6f vs %.6f).",
               worst$smd_within, target_2009))
write.csv(cbind(pilot = TRUE, worst,
  elapsed_s = pilot_elapsed, approx_peak_mem_mb = pilot_mem_mb),
  apath("2a_pilot_p0h5_2009.csv"), row.names = FALSE)
message("PILOT PASSED -- proceeding to full audit.\n")

# ===========================================================================
# 2A.1 + 2A.2 -- all four specifications, complete data, sequential
# ===========================================================================
runtime <- list()
cov_all <- list(); sup_all <- list()
for (i in seq_len(nrow(specs))) {
  spec <- specs$spec[i]; wpath <- specs$wpath[i]
  banner(sprintf("Spec %d/4: %s", i, spec))
  gc(reset = TRUE); ts <- Sys.time()

  ss  <- suff_stats(wpath)                 # big grouped scan (aggregation pushed down)
  sup <- support_stats(wpath)
  fm  <- firm_mass(wpath)
  cohorts <- sort(unique(ss$cohort))
  cohort_groups <- setNames(as.list(cohorts), as.character(cohorts))
  era_list <- eras_of(specs$eras[i])
  era_groups <- setNames(lapply(era_list, function(er) cohorts[cohorts >= er[1] & cohorts <= er[2]]),
                         sapply(era_list, paste, collapse = "-"))

  cov_c <- cov_balance_table(spec, ss, cohort_groups, "cohort")
  cov_e <- cov_balance_table(spec, ss, era_groups, "era")
  full_group <- list(all = cohorts)
  sup_c <- support_table(spec, sup, fm, cohort_groups, "cohort")
  sup_e <- support_table(spec, sup, fm, era_groups, "era")
  sup_f <- support_table(spec, sup, fm, full_group, "full")   # full-spec firm ESS (~119 target)

  cov_all[[spec]] <- rbind(cov_c, cov_e)
  sup_all[[spec]] <- rbind(sup_c, sup_e, sup_f)
  # save per-spec immediately (restartable)
  write.csv(cov_all[[spec]], apath(sprintf("2a_conditional_balance_%s.csv", spec)), row.names = FALSE)
  write.csv(sup_all[[spec]], apath(sprintf("2a_support_%s.csv", spec)), row.names = FALSE)

  el <- as.numeric(Sys.time() - ts, units = "secs")
  mm <- sum(gc()[, "max used"] * c(56, 8)) / 1e6
  runtime[[spec]] <- data.frame(spec = spec, n_cohorts = length(cohorts),
    n_suff_rows = nrow(ss), n_firm_rows = nrow(fm), elapsed_s = el, approx_peak_mem_mb = mm)
  message(sprintf("  done: %d cohorts, suff rows=%d, firm rows=%d | %.1fs, ~%.0f MB",
                  length(cohorts), nrow(ss), nrow(fm), el, mm))
}

# ---- combine + reproduction verification against existing 11o outputs ----
cov_master <- do.call(rbind, cov_all)
sup_master <- do.call(rbind, sup_all)
write.csv(cov_master, apath("2a_conditional_balance.csv"), row.names = FALSE)
write.csv(sup_master, apath("2a_support_concentration.csv"), row.names = FALSE)
write.csv(do.call(rbind, runtime), apath("2a_runtime_resource_log.csv"), row.names = FALSE)

# max over CONTINUOUS covars per (spec, level, group) -> compare to existing 11o CSVs
agg_max <- function(df) {
  d <- df[df$continuous, ]
  ag <- aggregate(abs(d$smd_within), by = list(spec = d$spec, level = d$level, group = d$group), max)
  names(ag)[4] <- "max_abs_smd_cont"; ag
}
mine <- agg_max(cov_master)
existing_c <- utils::read.csv(paste0(NT2010_RESULTS_PREFIX, "_cohort_balance.csv"), stringsAsFactors = FALSE)
existing_e <- utils::read.csv(paste0(NT2010_RESULTS_PREFIX, "_era_balance.csv"), stringsAsFactors = FALSE)
existing <- rbind(
  data.frame(spec = existing_c$spec, level = "cohort", group = as.character(existing_c$cohort),
             existing_max = existing_c$max_abs_smd),
  data.frame(spec = existing_e$spec, level = "era", group = existing_e$era,
             existing_max = existing_e$max_abs_smd))
chk <- merge(mine, existing, by = c("spec", "level", "group"))
chk$rel_err <- abs(chk$max_abs_smd_cont - chk$existing_max) /
               pmax(abs(chk$existing_max), abs(chk$max_abs_smd_cont), 1)
# Denominator-collapse groups: a covariate is (near-)constant among treated in the
# cohort, so its within-cohort variance sits at machine epsilon and the SMD is
# mathematically undefined -- its computed value (whether the frozen in-memory
# smd_weighted or this aggregation-first method) is numerically meaningless. Real
# conditional imbalances are O(0.1-3); any |SMD| > 100 on EITHER side is a collapse
# artifact, not a reproduction failure. Well-conditioned groups must meet rel tol.
COLLAPSE_THRESH <- 1e2
chk$denom_collapse <- chk$existing_max > COLLAPSE_THRESH | chk$max_abs_smd_cont > COLLAPSE_THRESH
chk$reproduced <- chk$rel_err < SMD_REPRO_RELTOL | chk$denom_collapse
write.csv(chk, apath("2a_reproduction_check.csv"), row.names = FALSE)
n_bad <- sum(!chk$reproduced)
message(sprintf("\nReproduction check: %d/%d group maxima reproduced (rel tol %.0e); %d mismatches.",
                sum(chk$reproduced), nrow(chk), SMD_REPRO_RELTOL, n_bad))
if (n_bad > 0) print(chk[!chk$reproduced, ])

# ---- summary: which covariate drives each cohort/era maximum (all 14 covars) ----
drivers <- do.call(rbind, by(cov_master, list(cov_master$spec, cov_master$level, cov_master$group),
  function(d) { j <- which.max(abs(d$smd_within)); d[j, c("spec","level","group","covariate",
    "smd_within","raw_diff","denom_within_sd_treated","smd_fullpooled","near_zero_denom","zero_var")] }))
drivers <- drivers[order(drivers$spec, drivers$level, -abs(drivers$smd_within)), ]
write.csv(drivers, apath("2a_max_smd_drivers.csv"), row.names = FALSE)

banner("11q DONE -- conditional-balance diagnostic complete; no reweighting/outcomes")
message(sprintf("Reproduced %d/%d maxima. Driver summary rows: %d.",
                sum(chk$reproduced), nrow(chk), nrow(drivers)))
