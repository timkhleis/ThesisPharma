# FN stacked DiD with TRAJECTORY-MATCHED controls (Verginer-style double matching)
#
# The plain FN control pool differs from treated on the pre-period activity path
# (gap distribution: treated skews away from gap-1), producing sloped, significant
# FN pre-trends. This script enforces parallel pre-trends BY CONSTRUCTION: coarsened
# exact matching (CEM) of treated<->control on the full pre-period active_patenting
# trajectory ([-5..-1] 5-bit pattern) x primary IPC section. Within a matched cell
# both arms have the identical pre-period active pattern, so the active_patenting
# pre-trend is flat by construction; counts/citations pre-trends flatten to the
# extent they track the activity path.
#
# Identifying assumption shifts to: conditional on the same 5-year pre-deal
# trajectory + IPC, treated and (placebo-dated) control would have shared the same
# post path absent treatment. (This is the thesis's pre-registered Verginer double-
# matching design, now layered on the FN control clock.)
#
# Run via PowerShell after 08t + 08u:
#   & 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis/R/08w_fn_trajectory_matched.R

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
dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
banner <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
write_result <- function(df, f) utils::write.csv(df, file.path(RESULTS, f), row.names = FALSE, na = "")

DELTAS   <- c(0L, 1L)
DELTA_FN <- 7L
OUTCOMES <- c("active_patenting", "log_patent_count", "log_fwd_cits5")
OUTCOME_LABS <- c(active_patenting = "Active patenting (0/1)",
                  log_patent_count = "log(1+patent count)",
                  log_fwd_cits5    = "log(1+forward cites 5y)")

drv <- duckdb::duckdb(); con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

banner("LOAD PANEL")
pq <- gsub("\\\\", "/", file.path(DERIVED_PAR, "fn_stacked_panel.parquet"))
stacked <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", pq))
stacked$event_time <- as.integer(stacked$event_time)
stacked$stack   <- as.integer(stacked$stack)
stacked$treated <- as.integer(stacked$treated)
stacked$deal_id <- as.integer(stacked$deal_id)
stacked$unit    <- paste(stacked$codinv, stacked$stack, stacked$arm, sep = "_")
stacked$uid_stack <- interaction(stacked$codinv, stacked$stack, drop = TRUE)

# ---------------------------------------------------------------------------
# CEM on pre-period trajectory x IPC
# ---------------------------------------------------------------------------
banner("COARSENED EXACT MATCHING (pre-period trajectory x IPC)")
pre <- stacked[stacked$event_time >= -5 & stacked$event_time <= -1, ]
pre <- pre[order(pre$unit, pre$event_time), ]
traj <- tapply(pre$active_patenting, pre$unit, function(z) paste(as.integer(z), collapse = ""))

unit_info <- unique(stacked[, c("unit", "codinv", "deal_id", "stack", "arm", "treated", "ipc_primary_field")])
unit_info$traj <- traj[unit_info$unit]
# matching cell: full pre-period active pattern x IPC section (pooled across stacks;
# calendar handled by stack^event_time FE in estimation). This balances the gap
# distribution + tech mix that drove the sloped pre-trends.
unit_info$cell <- paste(unit_info$traj, unit_info$ipc_primary_field, sep = "|")

cell_counts <- as.data.frame(table(cell = unit_info$cell, treated = unit_info$treated))
nt <- setNames(cell_counts$Freq[cell_counts$treated == 1], cell_counts$cell[cell_counts$treated == 1])
nc <- setNames(cell_counts$Freq[cell_counts$treated == 0], cell_counts$cell[cell_counts$treated == 0])
common_cells <- intersect(names(nt)[nt > 0], names(nc)[nc > 0])

unit_info$on_support <- unit_info$cell %in% common_cells
# ATT CEM weights: treated = 1; control = (n_treated_cell / n_control_cell)
unit_info$cem_w <- NA_real_
unit_info$cem_w[unit_info$treated == 1L & unit_info$on_support] <- 1
ctl_idx <- which(unit_info$treated == 0L & unit_info$on_support)
unit_info$cem_w[ctl_idx] <- nt[unit_info$cell[ctl_idx]] / nc[unit_info$cell[ctl_idx]]

# support diagnostics
supp <- data.frame(
  arm = c("treated", "control"),
  n_total = c(sum(unit_info$treated == 1L), sum(unit_info$treated == 0L)),
  n_on_support = c(sum(unit_info$treated == 1L & unit_info$on_support),
                   sum(unit_info$treated == 0L & unit_info$on_support)))
supp$share_on_support <- supp$n_on_support / supp$n_total
message("Matching cells: ", length(common_cells), " common (both arms) of ",
        length(unique(unit_info$cell)), " total")
print(supp)
write_result(supp, "trajmatch_support.csv")

matched_units <- unit_info[unit_info$on_support, c("unit", "cem_w")]
dat <- merge(stacked, matched_units, by = "unit")
message("Matched panel: ", nrow(dat), " rows, ",
        length(unique(dat$unit)), " units (", length(unique(dat$codinv[dat$treated==1])), " treated inv)")

# ---------------------------------------------------------------------------
# Pre-period balance check on the matched sample (should be ~flat for active)
# ---------------------------------------------------------------------------
bal <- aggregate(active_patenting ~ event_time + arm, data = dat[dat$event_time <= -1, ],
                 FUN = function(z) mean(z))  # unweighted means for transparency
balw <- do.call(rbind, lapply(sort(unique(dat$event_time[dat$event_time <= -1])), function(e) {
  s <- dat[dat$event_time == e, ]
  wm <- function(a) sum(s$active_patenting[s$arm == a] * s$cem_w[s$arm == a]) /
                    sum(s$cem_w[s$arm == a])
  data.frame(event_time = e, treated = wm("treated"), control = wm("control"),
             abs_diff = abs(wm("treated") - wm("control")))
}))
message("Weighted pre-period active_patenting balance (matched):")
print(balw)
write_result(balw, "trajmatch_preperiod_balance.csv")

# ---------------------------------------------------------------------------
# Estimate FN stacked TWFE on matched sample (CEM-weighted)
# ---------------------------------------------------------------------------
banner("ESTIMATE trajectory-matched FN")
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
  out <- data.frame(outcome = outcome, delta = delta, event_time = ct$event_time,
                    att = ct$Estimate, ci_low = ct$lo, ci_high = ct$hi)
  rbind(out, data.frame(outcome = outcome, delta = delta, event_time = base_e,
                        att = 0, ci_low = 0, ci_high = 0))
}
rows <- list()
for (outcome in OUTCOMES) for (delta in DELTAS) {
  r <- fit_fn(dat, outcome, delta); rows[[paste(outcome, delta)]] <- r
  if (delta == 1L) message(sprintf("%-16s d1 | pre(-3)=%+.3f (-5)=%+.3f | post(+1)=%+.3f (+5)=%+.3f",
      outcome, r$att[r$event_time == -3], r$att[r$event_time == -5],
      r$att[r$event_time == 1], r$att[r$event_time == 5]))
}
matched_res <- do.call(rbind, rows); matched_res$spec <- "FN_trajmatched"
write_result(matched_res, "fn_trajectory_matched_event_study.csv")

# ---------------------------------------------------------------------------
# Overlay figure: unmatched FN vs trajectory-matched FN (delta=1)
# ---------------------------------------------------------------------------
banner("FIGURE: unmatched vs trajectory-matched (delta=1)")
unm <- utils::read.csv(file.path(RESULTS, "fn_corrected_event_study.csv"))
unm <- unm[unm$spec == "FN_unweighted" & unm$delta == 1, c("outcome","event_time","att","ci_low","ci_high")]
unm$spec <- "FN (unmatched)"
mm <- matched_res[matched_res$delta == 1, c("outcome","event_time","att","ci_low","ci_high")]
mm$spec <- "FN (trajectory-matched)"
comb <- rbind(unm, mm)
comb$outcome_lab <- factor(OUTCOME_LABS[comb$outcome], levels = OUTCOME_LABS)

p <- ggplot2::ggplot(comb, ggplot2::aes(event_time, att, colour = spec, fill = spec)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), alpha = 0.13, linetype = 0) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey65", linewidth = 0.4, linetype = 2) +
  ggplot2::geom_line(linewidth = 0.8) + ggplot2::geom_point(size = 1.3) +
  ggplot2::facet_wrap(~outcome_lab, ncol = 3, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = seq(-5, 5, 1)) +
  ggplot2::scale_colour_manual(values = c("#ff7f0e", "#1B5E20")) +
  ggplot2::scale_fill_manual(values = c("#ff7f0e", "#1B5E20")) +
  ggplot2::labs(x = "Event time (relative to acquisition / placebo date)", y = "FN-corrected ATT (delta=1)",
    colour = NULL, fill = NULL,
    title = "Trajectory-matched FN: do the pre-trends flatten?",
    subtitle = paste0("CEM on 5-year pre-period active pattern x IPC (both arms). ",
                      "Flat pre-period => parallel trends by construction; read the post path against it.")) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), legend.position = "bottom",
                 plot.title = ggplot2::element_text(face = "bold", colour = "#1B4332", size = 11),
                 plot.subtitle = ggplot2::element_text(colour = "#6B7280", size = 8),
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
fig_path <- file.path(FIGS, "figure16_fn_trajectory_matched.png")
ggplot2::ggsave(fig_path, p, width = 10, height = 4.2, dpi = 300, bg = "white")

banner("08w COMPLETE")
message("Figure: ", fig_path)
message("Pre-period balance -> trajmatch_preperiod_balance.csv (active should be ~0)")
