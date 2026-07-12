# Fadlon-Nielsen stacked DiD: estimate corrected event-study + fraction stat
#
# Consumes fn_stacked_panel.parquet (from 08t). Produces:
#   - FN-corrected event study (stacked TWFE via fixest), delta in {0,1},
#     unweighted (headline) + IPW-weighted (co-report)
#   - Raw (naive) CS(2021) path (08h clone, full panel), delta in {0,1}
#   - Overlay figure14_fn_corrected_vs_raw.png
#   - fn_fraction_stat.csv (how much of the naive hump/cliff FN absorbs)
#
# The mechanical hump cancels WITHIN the stacked estimator: stack^event_time FE
# absorb the M(tau) shared by both arms per stack; codinv^stack FE absorb unit
# means; the treated x event_time coefficients are the corrected event study.
#
# Run via PowerShell after 08t:
#   & 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis/R/08u_fn_estimate_stacked.R

BASE        <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB      <- file.path(BASE, "output", "thesis_foundation.duckdb")
DERIVED_PAR <- file.path(BASE, "output", "parquet", "derived")
RESULTS     <- file.path(BASE, "output", "results", "cs2021_fn_stacked")
AUDIT       <- file.path(BASE, "output", "audit", "fn_stacked")
FIGS        <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "did", "fixest", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_result <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

DELTAS   <- c(0L, 1L)   # anticipation grid; base event-time = -(1+delta)
EVENT_HI <- 5L
DELTA_FN <- 7L          # control lag (for truncation: keep control t <= 6-delta)
OUTCOMES <- c("active_patenting", "log_patent_count", "log_fwd_cits5")
OUTCOME_LABS <- c(active_patenting = "Active patenting (0/1)",
                  log_patent_count = "log(1+patent count)",
                  log_fwd_cits5    = "log(1+forward cites 5y)")

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

# ---------------------------------------------------------------------------
# Load the stacked panel
# ---------------------------------------------------------------------------
banner("LOADING FN STACKED PANEL")
pq <- gsub("\\\\", "/", file.path(DERIVED_PAR, "fn_stacked_panel.parquet"))
stacked <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", pq))
stacked$event_time <- as.integer(stacked$event_time)
stacked$stack      <- as.integer(stacked$stack)
stacked$treated    <- as.integer(stacked$treated)
stacked$deal_id    <- as.integer(stacked$deal_id)
stacked$ipc_primary_field <- factor(stacked$ipc_primary_field)
# unit x stack id for FE / dual-role handling. NOTE: an inventor treated at
# stack 2007 and serving as FN control at stack 2000 carries the SAME deal_id in
# both roles, so cluster ~ deal_id correctly groups their appearances; cross-
# stack dual roles are expected and fine (do not "dedupe" them).
stacked$uid_stack <- interaction(stacked$codinv, stacked$stack, drop = TRUE)
message("Rows: ", nrow(stacked), " | treated obs: ", sum(stacked$treated),
        " | control obs: ", sum(1 - stacked$treated))

# ---------------------------------------------------------------------------
# IPW (ATT-weighted): pooled logit of treated on PRE-DEAL covariates + stack.
# BAN outcome-derived regressors (e.g. qualifying_gap is derived from the
# outcome path) -- covariates below are all predetermined.
# ---------------------------------------------------------------------------
banner("IPW WEIGHTS (ATT: treated=1, control=p/(1-p))")
units <- unique(stacked[, c("codinv", "deal_id", "stack", "treated",
                            "career_age_at_deal", "career_age_sq_at_deal",
                            "log_predeal_patent_stock", "log_group_size",
                            "ipc_primary_field")])
units$ipc_primary_field <- factor(units$ipc_primary_field)
units$stack_f <- factor(units$stack)

# guard against IPC x stack separation: log a warning if any (stack, ipc) cell
# is single-arm (perfect prediction risk). Coarsening is deferred unless it bites.
sep_tab <- table(units$stack, units$ipc_primary_field, units$treated)
single_arm_cells <- sum((sep_tab[, , 1] > 0) != (sep_tab[, , 2] > 0))
message("IPC x stack cells that are single-arm (separation risk): ", single_arm_cells)

logit <- stats::glm(
  treated ~ career_age_at_deal + career_age_sq_at_deal +
    log_predeal_patent_stock + log_group_size + ipc_primary_field + stack_f,
  data = units, family = stats::binomial()
)
units$phat <- stats::predict(logit, type = "response")
# ATT weights
units$w_raw <- ifelse(units$treated == 1L, 1, units$phat / pmax(1 - units$phat, 1e-8))
max_untrimmed <- max(units$w_raw[units$treated == 0L])
# trim control weights at 1st/99th pct
qs <- stats::quantile(units$w_raw[units$treated == 0L], c(0.01, 0.99), na.rm = TRUE)
units$w_ipw <- units$w_raw
ctl <- units$treated == 0L
units$w_ipw[ctl] <- pmin(pmax(units$w_ipw[ctl], qs[1]), qs[2])
trimmed_mass <- mean(units$w_raw[ctl] < qs[1] | units$w_raw[ctl] > qs[2])
message("Max UNTRIMMED control weight: ", round(max_untrimmed, 2),
        " | trimmed mass (1st/99th): ", round(trimmed_mass, 4),
        " | phat range: [", round(min(units$phat), 3), ", ", round(max(units$phat), 3), "]")
write_result(data.frame(
  max_untrimmed_control_weight = max_untrimmed,
  trimmed_mass_frac = trimmed_mass,
  phat_min = min(units$phat), phat_max = max(units$phat),
  single_arm_ipc_stack_cells = single_arm_cells
), "ipw_weight_diagnostics.csv")

stacked <- merge(stacked, units[, c("codinv", "deal_id", "stack", "w_ipw")],
                 by = c("codinv", "deal_id", "stack"), all.x = TRUE)

# ---------------------------------------------------------------------------
# FN-corrected stacked event study (fixest), delta in {0,1}, unw + IPW
# ---------------------------------------------------------------------------
banner("FN-CORRECTED STACKED TWFE (per outcome)")

fn_coefs <- list()
for (outcome in OUTCOMES) {
  for (delta in DELTAS) {
    base_e <- -(1L + delta)
    # truncate control rows to event_time <= DELTA_FN - 1 - delta (no-op for -5..5, DELTA=7, delta<=1)
    max_clean <- DELTA_FN - 1L - delta
    dat <- stacked[stacked$treated == 1L | stacked$event_time <= max_clean, ]

    for (wt in c("unweighted", "ipw")) {
      section(sprintf("FN | %s | delta=%d | %s (base e=%d)", outcome, delta, wt, base_e))
      ww <- if (wt == "ipw") dat$w_ipw else NULL
      fml <- stats::as.formula(sprintf(
        "%s ~ i(event_time, treated, ref = %d) | stack^event_time + uid_stack",
        outcome, base_e))
      mod <- fixest::feols(fml, data = dat, weights = ww, cluster = ~deal_id)
      ct <- as.data.frame(fixest::coeftable(mod))
      ct$term <- rownames(ct)
      ct <- ct[grepl("^event_time::.*:treated$", ct$term), ]
      ct$event_time <- as.integer(sub("^event_time::(-?\\d+):treated$", "\\1", ct$term))
      ci <- stats::confint(mod); ci$term <- rownames(ci)
      ci <- ci[ci$term %in% ct$term, ]; names(ci)[1:2] <- c("ci_low", "ci_high")
      ct <- merge(ct, ci[, c("term", "ci_low", "ci_high")], by = "term")
      out <- data.frame(
        outcome = outcome, spec = paste0("FN_", wt), delta = delta,
        event_time = ct$event_time, att = ct$Estimate, se = ct$`Std. Error`,
        ci_low = ct$ci_low, ci_high = ct$ci_high)
      out <- rbind(out, data.frame(outcome = outcome, spec = paste0("FN_", wt), delta = delta,
                                   event_time = base_e, att = 0, se = 0, ci_low = 0, ci_high = 0))
      out <- out[order(out$event_time), ]
      fn_coefs[[paste(outcome, delta, wt)]] <- out
      message("  t=-3: ", round(out$att[out$event_time == -3], 4),
              " | t=+1: ", round(out$att[out$event_time == 1], 4),
              " | t=+5: ", round(out$att[out$event_time == 5], 4))
    }
  }
}
fn_all <- do.call(rbind, fn_coefs)
write_result(fn_all, "fn_corrected_event_study.csv")

# ---------------------------------------------------------------------------
# Raw (naive) CS(2021) path -- 08h clone on the FULL matched panel (all cohorts
# serve as not-yet-treated controls; DO NOT filter cohorts out of the data).
# ---------------------------------------------------------------------------
banner("RAW (NAIVE) CS(2021) PATH -- 08h clone, full panel")

full_panel <- DBI::dbGetQuery(con, "
  WITH cite AS (
    SELECT CAST(pi.codinv AS BIGINT) AS codinv, pe.patent_year AS year,
           SUM(COALESCE(pe.fwd_cits5, 0)) AS fwd_cits5
    FROM patent_inventor pi JOIN patent_enriched pe ON pe.appln_id = pi.appln_id
    GROUP BY pi.codinv, pe.patent_year
  )
  SELECT CAST(ep.codinv AS DOUBLE) AS codinv, CAST(ep.deal_id AS INTEGER) AS deal_id,
         CAST(ep.deal_year AS INTEGER) AS deal_year, CAST(ep.calendar_year AS INTEGER) AS calendar_year,
         CAST(ep.active_patenting AS DOUBLE) AS active_patenting,
         CAST(ep.log_patent_count AS DOUBLE) AS log_patent_count,
         LN(1 + COALESCE(c.fwd_cits5, 0)) AS log_fwd_cits5,
         CAST(ep.career_age_at_deal AS DOUBLE) AS career_age_at_deal,
         CAST(ep.career_age_sq_at_deal AS DOUBLE) AS career_age_sq_at_deal,
         ep.ipc_primary_field,
         CAST(ep.log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
         CAST(ep.log_group_size AS DOUBLE) AS log_group_size,
         CAST(ep.log_deal_value AS DOUBLE) AS log_deal_value
  FROM cs2021_estimation_panel ep
  LEFT JOIN cite c ON c.codinv = CAST(ep.codinv AS BIGINT) AND c.year = ep.calendar_year
  ORDER BY ep.codinv, ep.calendar_year")
full_panel$ipc_primary_field <- factor(full_panel$ipc_primary_field)

# common-support matched cells (identical rule to 08g/08h)
cell_coverage <- DBI::dbGetQuery(con, "
  WITH unit AS (SELECT DISTINCT codinv, deal_id, deal_year, predeal_patent_stock_5y, ipc_primary_field
                FROM cs2021_estimation_panel),
  binned AS (SELECT *, NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS q FROM unit)
  SELECT q AS patent_stock_quintile, ipc_primary_field, COUNT(DISTINCT deal_year) AS n_cohorts,
         MAX(deal_year)-MIN(deal_year) AS span FROM binned GROUP BY q, ipc_primary_field")
cell_coverage$pass <- cell_coverage$n_cohorts >= 3 & cell_coverage$span >= 5
allowed <- cell_coverage[cell_coverage$pass, c("patent_stock_quintile", "ipc_primary_field")]
unit_bins <- DBI::dbGetQuery(con, "
  WITH unit AS (SELECT DISTINCT codinv, deal_id, predeal_patent_stock_5y FROM cs2021_estimation_panel)
  SELECT codinv, deal_id, NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
  FROM unit")
unit_bins$codinv <- as.double(unit_bins$codinv)
full_panel <- merge(full_panel, unit_bins, by = c("codinv", "deal_id"))
full_panel <- merge(full_panel, transform(allowed, in_cs = TRUE),
                    by = c("patent_stock_quintile", "ipc_primary_field"), all.x = TRUE)
full_panel$in_cs[is.na(full_panel$in_cs)] <- FALSE
matched <- full_panel[full_panel$in_cs, ]
message("Matched sample: ", length(unique(matched$codinv)), " inventors, ",
        length(unique(matched$deal_id)), " deals (ALL cohorts retained as controls)")

xf <- ~ career_age_at_deal + career_age_sq_at_deal + ipc_primary_field +
  log_predeal_patent_stock + log_group_size + log_deal_value

raw_coefs <- list()
for (outcome in OUTCOMES) {
  for (delta in DELTAS) {
    section(sprintf("RAW | %s | delta=%d", outcome, delta))
    set.seed(20260701L)
    att <- did::att_gt(yname = outcome, tname = "calendar_year", idname = "codinv",
                       gname = "deal_year", xformla = xf, data = matched, panel = TRUE,
                       allow_unbalanced_panel = FALSE, control_group = "notyettreated",
                       anticipation = delta, base_period = "universal", est_method = "dr",
                       bstrap = TRUE, biters = 999, clustervars = "deal_id", cband = TRUE,
                       print_details = FALSE)
    dyn <- did::aggte(att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5, na.rm = TRUE,
                      bstrap = TRUE, biters = 999, clustervars = "deal_id", cband = TRUE)
    cval <- if (!is.null(dyn$crit.val.egt)) dyn$crit.val.egt else 1.96
    raw_coefs[[paste(outcome, delta)]] <- data.frame(
      outcome = outcome, spec = "raw_CS", delta = delta, event_time = dyn$egt,
      att = dyn$att.egt, se = dyn$se.egt,
      ci_low = dyn$att.egt - cval * dyn$se.egt, ci_high = dyn$att.egt + cval * dyn$se.egt)
    message("  t=-3: ", round(dyn$att.egt[dyn$egt == -3], 4),
            " | t=+1: ", round(dyn$att.egt[dyn$egt == 1], 4),
            " | t=+5: ", round(dyn$att.egt[dyn$egt == 5], 4))
  }
}
raw_all <- do.call(rbind, raw_coefs)
write_result(raw_all, "raw_cs_event_study.csv")

# ---------------------------------------------------------------------------
# Overlay figure
# ---------------------------------------------------------------------------
banner("OVERLAY FIGURE (outcome x delta grid)")
combined <- rbind(
  raw_all[, c("outcome", "spec", "delta", "event_time", "att", "ci_low", "ci_high")],
  fn_all[, c("outcome", "spec", "delta", "event_time", "att", "ci_low", "ci_high")])
combined$spec <- factor(combined$spec,
  levels = c("raw_CS", "FN_unweighted", "FN_ipw"),
  labels = c("Raw CS(2021) (naive)", "FN corrected (unweighted)", "FN corrected (IPW)"))
combined$outcome_lab <- factor(OUTCOME_LABS[combined$outcome], levels = OUTCOME_LABS)
combined$delta_lab <- paste0("delta = ", combined$delta)

p <- ggplot2::ggplot(combined, ggplot2::aes(event_time, att, colour = spec, fill = spec)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), alpha = 0.12, linetype = 0) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey65", linewidth = 0.4, linetype = 2) +
  ggplot2::geom_line(linewidth = 0.7) + ggplot2::geom_point(size = 1.1) +
  ggplot2::facet_grid(outcome_lab ~ delta_lab, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = seq(-5, 5, 1)) +
  ggplot2::scale_colour_manual(values = c("#B00020", "#1f77b4", "#ff7f0e")) +
  ggplot2::scale_fill_manual(values = c("#B00020", "#1f77b4", "#ff7f0e")) +
  ggplot2::labs(
    x = "Event time (years relative to acquisition / placebo date)",
    y = "ATT", colour = NULL, fill = NULL,
    title = "Fadlon-Nielsen correction across output dimensions",
    subtitle = paste0("Rows: extensive margin, patent counts, forward citations. ",
                      "Red = naive CS(2021); blue/orange = FN corrected (mechanical M(tau) cancels within-estimator).")) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                 legend.position = "bottom",
                 strip.text = ggplot2::element_text(size = 8),
                 plot.title = ggplot2::element_text(face = "bold", colour = "#1B4332", size = 11),
                 plot.subtitle = ggplot2::element_text(colour = "#6B7280", size = 8),
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
fig_path <- file.path(FIGS, "figure14_fn_corrected_vs_raw.png")
ggplot2::ggsave(fig_path, p, width = 9.5, height = 8, dpi = 300, bg = "white")
message("Figure: ", fig_path)

# ---------------------------------------------------------------------------
# Fraction statistic: 1 - beta_FN / ATT_raw at hump (t=-3) and cliff (+1,+3,+5)
# Ratio hygiene: point ratio + component CIs only (no joint precision); flag
# small-denominator cells; quote t=-3 alongside absolute levels (denom ~0.05).
# ---------------------------------------------------------------------------
banner("FRACTION STATISTIC")
tau_report <- c(-3L, 1L, 3L, 5L)
frac_rows <- list()
for (outcome in OUTCOMES) {
  for (delta in DELTAS) {
    rraw <- raw_all[raw_all$outcome == outcome & raw_all$delta == delta, ]
    for (wt in c("FN_unweighted", "FN_ipw")) {
      rfn <- fn_all[fn_all$outcome == outcome & fn_all$delta == delta & fn_all$spec == wt, ]
      for (tau in tau_report) {
        a_raw <- rraw$att[rraw$event_time == tau]
        b_fn  <- rfn$att[rfn$event_time == tau]
        if (length(a_raw) == 0 || length(b_fn) == 0) next
        # small-denominator threshold scaled to outcome magnitude
        denom_floor <- if (outcome == "active_patenting") 0.05 else 0.03
        frac_rows[[length(frac_rows) + 1]] <- data.frame(
          outcome = outcome, delta = delta, fn_spec = wt, event_time = tau,
          att_raw = a_raw,
          att_raw_lo = rraw$ci_low[rraw$event_time == tau],
          att_raw_hi = rraw$ci_high[rraw$event_time == tau],
          beta_fn = b_fn,
          beta_fn_lo = rfn$ci_low[rfn$event_time == tau],
          beta_fn_hi = rfn$ci_high[rfn$event_time == tau],
          fraction_absorbed = 1 - b_fn / a_raw,
          small_denominator_flag = abs(a_raw) < denom_floor)
      }
    }
  }
}
frac <- do.call(rbind, frac_rows)
write_result(frac, "fn_fraction_stat.csv")
message("Fraction absorbed = 1 - beta_FN/ATT_raw (point; read with component CIs):")
print(frac[frac$fn_spec == "FN_unweighted",
           c("outcome", "delta", "event_time", "att_raw", "beta_fn",
             "fraction_absorbed", "small_denominator_flag")], row.names = FALSE)

banner("08u COMPLETE")
message("Results: ", RESULTS)
message("Figure:  ", fig_path)
message("Read fn_fraction_stat.csv with the ratio-hygiene caveats; apply decision rules 3-4.")
