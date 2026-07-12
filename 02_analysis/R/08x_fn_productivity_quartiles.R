# FN heterogeneity: pre-deal productivity quartiles (trajectory-matched)
#
# Pre-registered (research_log_pre_commitment_thresholds.md, 9 Jul addendum):
# incentive-restructuring predicts the post-acquisition decline is MONOTONICALLY
# more negative in higher pre-deal productivity quartiles (Q4 most negative). All
# four quartiles reported regardless of outcome; the monotone gradient (not any
# single cell) is the evidential unit.
#
# Method: quartiles on log_predeal_patent_stock (cut on the TREATED distribution,
# same cuts applied to controls). Within each quartile, CEM-match treated<->control
# on the 5-year pre-period active pattern x IPC (as in 08w) to enforce flat pre-
# trends, then estimate the stacked FN TWFE. delta=1 headline.
#
# Run via PowerShell after 08t/08u/08w:
#   & 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis/R/08x_fn_productivity_quartiles.R

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
DELTA    <- 1L                 # headline anticipation (base -2)
OUTCOMES <- c("active_patenting", "log_patent_count", "log_fwd_cits5")
OUTCOME_LABS <- c(active_patenting = "Active patenting (0/1)",
                  log_patent_count = "log(1+patent count)",
                  log_fwd_cits5    = "log(1+forward cites 5y)")

drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

banner("LOAD PANEL + ASSIGN PRODUCTIVITY QUARTILES")
pq <- gsub("\\\\", "/", file.path(DERIVED_PAR, "fn_stacked_panel.parquet"))
stacked <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", pq))
stacked$event_time <- as.integer(stacked$event_time)
stacked$stack   <- as.integer(stacked$stack)
stacked$treated <- as.integer(stacked$treated)
stacked$deal_id <- as.integer(stacked$deal_id)
stacked$unit    <- paste(stacked$codinv, stacked$stack, stacked$arm, sep = "_")
stacked$uid_stack <- interaction(stacked$codinv, stacked$stack, drop = TRUE)

unit_info <- unique(stacked[, c("unit", "treated", "ipc_primary_field", "log_predeal_patent_stock")])
# Pre-deal stock is lumpy (>50% have <=1 patent), so value-based quartile cuts
# collapse. Use RANK-based quartiles WITHIN each arm (equal groups, deterministic
# tie-break by unit) -- standard NTILE approach; guarantees both arms populate
# every quartile so CEM support is preserved. Report stock ranges for transparency.
assign_quartile <- function(df) {
  ord <- order(df$log_predeal_patent_stock, df$unit)
  q <- integer(nrow(df))
  q[ord] <- as.integer(cut(seq_along(ord),
                           breaks = stats::quantile(seq_along(ord), 0:4 / 4),
                           include.lowest = TRUE, labels = 1:4))
  df$quartile <- q
  df
}
unit_info <- rbind(assign_quartile(unit_info[unit_info$treated == 1L, ]),
                   assign_quartile(unit_info[unit_info$treated == 0L, ]))
# stock range per quartile per arm (shows how much productivity actually varies)
qr <- do.call(rbind, lapply(split(unit_info, list(unit_info$quartile, unit_info$treated)), function(s)
  data.frame(quartile = s$quartile[1], treated = s$treated[1], n = nrow(s),
             stock_min = round(min(s$log_predeal_patent_stock), 3),
             stock_med = round(stats::median(s$log_predeal_patent_stock), 3),
             stock_max = round(max(s$log_predeal_patent_stock), 3))))
message("Stock (log) range per quartile x arm:")
print(qr[order(qr$treated, qr$quartile), ], row.names = FALSE)
write_result(qr, "fn_productivity_quartile_stockranges.csv")

# pre-period trajectory (5-bit active pattern) for CEM
pre <- stacked[stacked$event_time >= -5 & stacked$event_time <= -1, ]
pre <- pre[order(pre$unit, pre$event_time), ]
traj <- tapply(pre$active_patenting, pre$unit, function(z) paste(as.integer(z), collapse = ""))
unit_info$traj <- traj[unit_info$unit]
unit_info$cell <- paste(unit_info$traj, unit_info$ipc_primary_field, sep = "|")

# ---------------------------------------------------------------------------
# Per-quartile CEM (trajectory x IPC) + FN stacked TWFE
# ---------------------------------------------------------------------------
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

banner("ESTIMATE per quartile (trajectory-matched, delta=1)")
rows <- list(); supp_rows <- list()
for (q in 1:4) {
  ui_q <- unit_info[unit_info$quartile == q, ]
  w <- cem_weights(ui_q)
  d_q <- merge(stacked, w, by = "unit")
  n_t <- length(unique(d_q$unit[d_q$treated == 1L]))
  n_c <- length(unique(d_q$unit[d_q$treated == 0L]))
  supp_rows[[q]] <- data.frame(quartile = q, n_treated = n_t, n_control = n_c,
                               n_treated_pre_match = sum(ui_q$treated == 1L))
  message(sprintf("Q%d: %d treated / %d control units on support", q, n_t, n_c))
  for (outcome in OUTCOMES) {
    r <- fit_fn(d_q, outcome, DELTA); r$quartile <- q; r$outcome <- outcome
    rows[[paste(q, outcome)]] <- r
    if (outcome == "log_patent_count")
      message(sprintf("   %-16s pre(-3)=%+.3f | post(+1)=%+.3f (+3)=%+.3f (+5)=%+.3f",
        outcome, r$att[r$event_time == -3], r$att[r$event_time == 1],
        r$att[r$event_time == 3], r$att[r$event_time == 5]))
  }
}
res <- do.call(rbind, rows)
supp <- do.call(rbind, supp_rows)
write_result(res, "fn_productivity_quartile_event_study.csv")
write_result(supp, "fn_productivity_quartile_support.csv")

# ---------------------------------------------------------------------------
# Summary: average post effect (t+1..+5) per quartile x outcome
# ---------------------------------------------------------------------------
banner("POST-EFFECT SUMMARY (avg t+1..+5) + t+1")
summ <- do.call(rbind, lapply(split(res, list(res$quartile, res$outcome)), function(s) {
  post <- s[s$event_time >= 1 & s$event_time <= 5, ]
  data.frame(quartile = s$quartile[1], outcome = s$outcome[1],
             att_t1 = s$att[s$event_time == 1],
             att_post_avg = mean(post$att))
}))
summ <- summ[order(summ$outcome, summ$quartile), ]
write_result(summ, "fn_productivity_quartile_summary.csv")
print(summ, row.names = FALSE)

# ---------------------------------------------------------------------------
# Figure: event study by quartile (colour), outcome facets, delta=1
# ---------------------------------------------------------------------------
banner("FIGURE")
res$outcome_lab <- factor(OUTCOME_LABS[res$outcome], levels = OUTCOME_LABS)
res$Quartile <- factor(res$quartile, levels = 1:4,
                       labels = c("Q1 (low)", "Q2", "Q3", "Q4 (high)"))
p <- ggplot2::ggplot(res, ggplot2::aes(event_time, att, colour = Quartile, fill = Quartile)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), alpha = 0.08, linetype = 0) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey65", linewidth = 0.4, linetype = 2) +
  ggplot2::geom_line(linewidth = 0.7) + ggplot2::geom_point(size = 1.0) +
  ggplot2::facet_wrap(~outcome_lab, ncol = 3, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = seq(-5, 5, 1)) +
  ggplot2::scale_colour_manual(values = c("#9ecae1", "#4292c6", "#2171b5", "#08306b")) +
  ggplot2::scale_fill_manual(values = c("#9ecae1", "#4292c6", "#2171b5", "#08306b")) +
  ggplot2::labs(x = "Event time (relative to acquisition / placebo date)",
    y = "Trajectory-matched FN ATT (delta=1)", colour = NULL, fill = NULL,
    title = "Pre-deal productivity quartiles (trajectory-matched FN)",
    subtitle = paste0("Pre-registered: incentive-restructuring predicts a monotone gradient, ",
                      "Q4 (high productivity) most negative. All quartiles shown.")) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), legend.position = "bottom",
                 plot.title = ggplot2::element_text(face = "bold", colour = "#1B4332", size = 11),
                 plot.subtitle = ggplot2::element_text(colour = "#6B7280", size = 8),
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
fig_path <- file.path(FIGS, "figure17_fn_productivity_quartiles.png")
ggplot2::ggsave(fig_path, p, width = 10, height = 4.2, dpi = 300, bg = "white")

banner("08x COMPLETE")
message("Figure: ", fig_path)
message("Summary: fn_productivity_quartile_summary.csv")
