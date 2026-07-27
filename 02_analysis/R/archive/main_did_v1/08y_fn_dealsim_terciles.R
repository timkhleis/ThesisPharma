# FN heterogeneity: DealSim terciles (trajectory-matched) -- the inverted-U test
#
# DealSim = cosine similarity of target vs acquirer PRE-DEAL IPC portfolios
# (subclass, 4-char), summed over [deal_year-5, deal_year-1] from group_ipc_year.
# The 15 placeholder acquirers (999xxx) and deals w/o acquirer IPC are excluded
# (per CLAUDE.md). Terciles are a TREATED-DEAL property; each treated inventor
# inherits their deal's tercile. Controls = full FN pool, trajectory-matched
# (CEM on pre-period active pattern x IPC) within each tercile.
#
# Pre-registered prediction (CLAUDE.md + research log): inverted-U in outcomes =>
# U-shape in the ATT: LOW and HIGH DealSim terciles more negative (integration
# friction / portfolio redundancy), MIDDLE tercile least negative (~0). The low-
# tercile ATT also discriminates integration-friction vs autonomy-preservation.
#
# Run via PowerShell after 08t/08w/08x:
#   & 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis/R/08y_fn_dealsim_terciles.R

BASE        <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB      <- file.path(BASE, "output", "thesis_foundation.duckdb")
DERIVED_PAR <- file.path(BASE, "output", "parquet", "derived")
RESULTS     <- file.path(BASE, "output", "results", "cs2021_fn_stacked")
FIGS        <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "fixest", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
banner <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
write_result <- function(df, f) utils::write.csv(df, file.path(RESULTS, f), row.names = FALSE, na = "")

DELTA_FN <- 7L
DELTA    <- 1L
OUTCOMES <- c("active_patenting", "log_patent_count", "log_fwd_cits5")
OUTCOME_LABS <- c(active_patenting = "Active patenting (0/1)",
                  log_patent_count = "log(1+patent count)",
                  log_fwd_cits5    = "log(1+forward cites 5y)")

drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

# ---------------------------------------------------------------------------
# 1. Build DealSim (cosine sim of target vs acquirer pre-deal IPC-subclass vectors)
# ---------------------------------------------------------------------------
banner("BUILD DEALSIM (target vs acquirer pre-deal IPC-subclass cosine)")
deals <- DBI::dbGetQuery(con, "
  SELECT DISTINCT CAST(deal_id AS INTEGER) AS deal_id,
         CAST(target_group AS BIGINT) AS target_group,
         CAST(acquirer_group AS BIGINT) AS acquirer_group,
         CAST(deal_year AS INTEGER) AS deal_year
  FROM target_cohort_own WHERE deal_year BETWEEN 1993 AND 2008")
# exclude placeholder acquirers and missing acquirer
deals <- deals[!is.na(deals$acquirer_group) & !grepl("^999", as.character(deals$acquirer_group)), ]
duckdb::duckdb_register(con, "dl", deals)

dealsim <- DBI::dbGetQuery(con, "
  WITH giy AS (
    SELECT CAST(id_group AS BIGINT) AS id_group, year, SUBSTR(ipc_code,1,4) AS sub,
           SUM(patent_count) AS w
    FROM group_ipc_year GROUP BY id_group, year, SUBSTR(ipc_code,1,4)
  ),
  tv AS (
    SELECT d.deal_id, giy.sub, SUM(giy.w) AS w
    FROM dl d JOIN giy ON giy.id_group = d.target_group
              AND giy.year BETWEEN d.deal_year-5 AND d.deal_year-1
    GROUP BY d.deal_id, giy.sub
  ),
  av AS (
    SELECT d.deal_id, giy.sub, SUM(giy.w) AS w
    FROM dl d JOIN giy ON giy.id_group = d.acquirer_group
              AND giy.year BETWEEN d.deal_year-5 AND d.deal_year-1
    GROUP BY d.deal_id, giy.sub
  ),
  dot AS (SELECT tv.deal_id, SUM(tv.w*av.w) AS dp FROM tv JOIN av ON tv.deal_id=av.deal_id AND tv.sub=av.sub GROUP BY tv.deal_id),
  tn  AS (SELECT deal_id, SQRT(SUM(w*w)) AS nrm FROM tv GROUP BY deal_id),
  an  AS (SELECT deal_id, SQRT(SUM(w*w)) AS nrm FROM av GROUP BY deal_id)
  SELECT tn.deal_id, COALESCE(dot.dp,0) / (tn.nrm*an.nrm) AS dealsim
  FROM tn JOIN an ON tn.deal_id=an.deal_id LEFT JOIN dot ON dot.deal_id=tn.deal_id")
duckdb::duckdb_unregister(con, "dl")

message("DealSim computed for ", nrow(dealsim), " deals")
message("DealSim distribution: ", paste(round(stats::quantile(dealsim$dealsim, c(0,.25,.5,.75,1)),3), collapse=" / "))
# terciles
tb <- stats::quantile(dealsim$dealsim, c(1/3, 2/3))
dealsim$tercile <- cut(dealsim$dealsim, breaks = c(-Inf, tb, Inf), labels = 1:3)
message("Tercile breaks: ", paste(round(tb,3), collapse=", "))
print(as.data.frame(table(tercile = dealsim$tercile)))
write_result(dealsim, "dealsim_by_deal.csv")

# ---------------------------------------------------------------------------
# 2. Load FN panel, attach tercile to treated inventors via deal_id
# ---------------------------------------------------------------------------
banner("LOAD PANEL + ASSIGN DEALSIM TERCILE (treated via deal_id)")
pq <- gsub("\\\\", "/", file.path(DERIVED_PAR, "fn_stacked_panel.parquet"))
stacked <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", pq))
stacked$event_time <- as.integer(stacked$event_time)
stacked$stack   <- as.integer(stacked$stack)
stacked$treated <- as.integer(stacked$treated)
stacked$deal_id <- as.integer(stacked$deal_id)
stacked$unit    <- paste(stacked$codinv, stacked$stack, stacked$arm, sep = "_")
stacked$uid_stack <- interaction(stacked$codinv, stacked$stack, drop = TRUE)

# treated deal -> tercile map; controls have NO tercile (full pool reused per tercile)
tmap <- setNames(as.integer(as.character(dealsim$tercile)), dealsim$deal_id)
stacked$tercile <- ifelse(stacked$treated == 1L, tmap[as.character(stacked$deal_id)], NA)

# treated inventors whose deal has no valid DealSim (placeholder/no-IPC) are dropped
n_tr_all <- length(unique(stacked$unit[stacked$treated == 1L]))
n_tr_ds  <- length(unique(stacked$unit[stacked$treated == 1L & !is.na(stacked$tercile)]))
message("Treated units with valid DealSim: ", n_tr_ds, " / ", n_tr_all,
        " (", round(100*n_tr_ds/n_tr_all,1), "%)")

# pre-period trajectory for CEM
pre <- stacked[stacked$event_time >= -5 & stacked$event_time <= -1, ]
pre <- pre[order(pre$unit, pre$event_time), ]
traj <- tapply(pre$active_patenting, pre$unit, function(z) paste(as.integer(z), collapse = ""))
unit_info <- unique(stacked[, c("unit", "treated", "ipc_primary_field", "tercile")])
unit_info$traj <- traj[unit_info$unit]
unit_info$cell <- paste(unit_info$traj, unit_info$ipc_primary_field, sep = "|")

cem_weights <- function(ui_sub) {
  tc <- as.data.frame(table(cell = ui_sub$cell, treated = ui_sub$treated))
  nt <- setNames(tc$Freq[tc$treated == 1], tc$cell[tc$treated == 1])
  nc <- setNames(tc$Freq[tc$treated == 0], tc$cell[tc$treated == 0])
  common <- intersect(names(nt)[nt > 0], names(nc)[nc > 0])
  ui_sub$on_support <- ui_sub$cell %in% common
  ui_sub$cem_w <- NA_real_
  ui_sub$cem_w[ui_sub$treated == 1L & ui_sub$on_support] <- 1
  ci <- which(ui_sub$treated == 0L & ui_sub$on_support)
  ui_sub$cem_w[ci] <- nt[ui_sub$cell[ci]] / nc[ui_sub$cell[ci]]
  ui_sub[ui_sub$on_support, c("unit", "cem_w")]
}
fit_fn <- function(d, outcome, delta) {
  base_e <- -(1L + delta); max_clean <- DELTA_FN - 1L - delta
  dd <- d[d$treated == 1L | d$event_time <= max_clean, ]
  fml <- stats::as.formula(sprintf(
    "%s ~ i(event_time, treated, ref = %d) | stack^event_time + uid_stack", outcome, base_e))
  mod <- fixest::feols(fml, data = dd, weights = ~cem_w, cluster = ~deal_id)
  ct <- as.data.frame(fixest::coeftable(mod)); ct$term <- rownames(ct)
  ct <- ct[grepl("^event_time::.*:treated$", ct$term), ]
  ct$event_time <- as.integer(sub("^event_time::(-?\\d+):treated$", "\\1", ct$term))
  ci <- stats::confint(mod); ci$term <- rownames(ci); names(ci)[1:2] <- c("lo", "hi")
  ct <- merge(ct, ci[, c("term", "lo", "hi")], by = "term")
  out <- data.frame(event_time = ct$event_time, att = ct$Estimate, ci_low = ct$lo, ci_high = ct$hi)
  rbind(out, data.frame(event_time = base_e, att = 0, ci_low = 0, ci_high = 0))
}

# ---------------------------------------------------------------------------
# 3. Estimate within each tercile (treated-in-tercile + full control pool)
# ---------------------------------------------------------------------------
banner("ESTIMATE per DealSim tercile (trajectory-matched, delta=1)")
rows <- list()
for (k in 1:3) {
  # treated in tercile k, plus ALL controls (full FN counterfactual pool)
  ui_k <- unit_info[(unit_info$treated == 1L & !is.na(unit_info$tercile) & unit_info$tercile == k) |
                    (unit_info$treated == 0L), ]
  w <- cem_weights(ui_k)
  d_k <- merge(stacked, w, by = "unit")
  n_t <- length(unique(d_k$unit[d_k$treated == 1L]))
  n_c <- length(unique(d_k$unit[d_k$treated == 0L]))
  message(sprintf("Tercile %d (DealSim %s): %d treated / %d control units on support", k,
                  c("low","mid","high")[k], n_t, n_c))
  for (outcome in OUTCOMES) {
    r <- fit_fn(d_k, outcome, DELTA); r$tercile <- k; r$outcome <- outcome
    rows[[paste(k, outcome)]] <- r
    if (outcome == "log_patent_count")
      message(sprintf("   %-16s pre(-3)=%+.3f | post(+1)=%+.3f (+3)=%+.3f (+5)=%+.3f",
        outcome, r$att[r$event_time==-3], r$att[r$event_time==1], r$att[r$event_time==3], r$att[r$event_time==5]))
  }
}
res <- do.call(rbind, rows)
write_result(res, "fn_dealsim_tercile_event_study.csv")

# post-avg summary (the inverted-U shape lives here)
banner("POST-EFFECT SUMMARY (avg t+1..+5) -- look for U-shape across terciles")
summ <- do.call(rbind, lapply(split(res, list(res$tercile, res$outcome)), function(s) {
  post <- s[s$event_time >= 1 & s$event_time <= 5, ]
  data.frame(tercile = s$tercile[1], outcome = s$outcome[1],
             att_t1 = s$att[s$event_time == 1], att_post_avg = mean(post$att))
}))
summ <- summ[order(summ$outcome, summ$tercile), ]
print(summ, row.names = FALSE)
write_result(summ, "fn_dealsim_tercile_summary.csv")

# ---------------------------------------------------------------------------
# 4. Figure
# ---------------------------------------------------------------------------
banner("FIGURE")
res$outcome_lab <- factor(OUTCOME_LABS[res$outcome], levels = OUTCOME_LABS)
res$Tercile <- factor(res$tercile, levels = 1:3,
                      labels = c("T1 low overlap", "T2 moderate", "T3 high overlap"))
p <- ggplot2::ggplot(res, ggplot2::aes(event_time, att, colour = Tercile, fill = Tercile)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), alpha = 0.10, linetype = 0) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey65", linewidth = 0.4, linetype = 2) +
  ggplot2::geom_line(linewidth = 0.7) + ggplot2::geom_point(size = 1.0) +
  ggplot2::facet_wrap(~outcome_lab, ncol = 3, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = seq(-5, 5, 1)) +
  ggplot2::scale_colour_manual(values = c("#d95f02", "#1b9e77", "#7570b3")) +
  ggplot2::scale_fill_manual(values = c("#d95f02", "#1b9e77", "#7570b3")) +
  ggplot2::labs(x = "Event time (relative to acquisition / placebo date)",
    y = "Trajectory-matched FN ATT (delta=1)", colour = NULL, fill = NULL,
    title = "DealSim terciles (trajectory-matched FN): the inverted-U test",
    subtitle = paste0("Pre-registered: low & high technological-overlap terciles more negative, ",
                      "moderate least negative. 265 deals w/ valid DealSim; placeholders excluded.")) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), legend.position = "bottom",
                 plot.title = ggplot2::element_text(face = "bold", colour = "#1B4332", size = 11),
                 plot.subtitle = ggplot2::element_text(colour = "#6B7280", size = 8),
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
fig_path <- file.path(FIGS, "figure18_fn_dealsim_terciles.png")
ggplot2::ggsave(fig_path, p, width = 10, height = 4.2, dpi = 300, bg = "white")

banner("08y COMPLETE")
message("Figure: ", fig_path)
message("Summary: fn_dealsim_tercile_summary.csv  |  DealSim: dealsim_by_deal.csv")
