# FN stacked DiD restricted to "stayers" (post-active survivors), SYMMETRICALLY.
#
# WHY THIS IS DELICATE: "stayer" is a POST-acquisition outcome. Conditioning the
# treated arm on it is selection on a post-treatment variable (the stayer-
# selection bias the thesis flags), and it has no clean analogue in the placebo
# control arm (controls never get acquired in-window). To keep the FN comparison
# valid we apply the SAME post-survival restriction to BOTH arms: a unit is kept
# iff it patents at least once in event-time [+1,+5]. This is still conditioning
# on a post-outcome (Lee-bounds territory), but symmetric, so the mechanical /
# mean-reversion component still differences out. It estimates an INTENSIVE-
# margin effect among survivors, NOT a clean ATT. Read with that caveat.
#
# Run via PowerShell after 08t:
#   & 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis/R/08v_fn_stayer_restricted.R

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
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)
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

banner("LOAD PANEL + DEFINE SYMMETRIC SURVIVOR (stayer proxy)")
pq <- gsub("\\\\", "/", file.path(DERIVED_PAR, "fn_stacked_panel.parquet"))
stacked <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", pq))
stacked$event_time <- as.integer(stacked$event_time)
stacked$stack   <- as.integer(stacked$stack)
stacked$treated <- as.integer(stacked$treated)
stacked$deal_id <- as.integer(stacked$deal_id)
stacked$unit    <- paste(stacked$codinv, stacked$stack, stacked$arm, sep = "_")
stacked$uid_stack <- interaction(stacked$codinv, stacked$stack, drop = TRUE)

# survivor = patents at least once in event-time [+1,+5] (same rule, both arms)
post <- stacked[stacked$event_time >= 1 & stacked$event_time <= 5, ]
surv <- tapply(post$active_patenting, post$unit, function(z) as.integer(any(z > 0)))
stacked$survivor <- surv[stacked$unit]

# survivor shares by arm (this composition difference IS the selection story)
share_tab <- aggregate(survivor ~ arm, data = unique(stacked[, c("unit", "arm", "survivor")]), FUN = mean)
n_tab <- aggregate(survivor ~ arm, data = unique(stacked[, c("unit", "arm", "survivor")]), FUN = length)
message("Survivor share by arm (fraction patenting in t+1..+5):")
print(merge(share_tab, setNames(n_tab, c("arm", "n_units")), by = "arm"))
write_result(merge(share_tab, setNames(n_tab, c("arm", "n_units")), by = "arm"),
             "stayer_survivor_shares.csv")

fit_fn <- function(dat, outcome, delta) {
  base_e <- -(1L + delta)
  max_clean <- DELTA_FN - 1L - delta
  d <- dat[dat$treated == 1L | dat$event_time <= max_clean, ]
  fml <- stats::as.formula(sprintf(
    "%s ~ i(event_time, treated, ref = %d) | stack^event_time + uid_stack", outcome, base_e))
  mod <- fixest::feols(fml, data = d, cluster = ~deal_id)
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

banner("ESTIMATE: full cohort vs survivor-restricted (both arms)")
rows <- list()
for (samp in c("full_cohort", "survivors_only")) {
  dat <- if (samp == "survivors_only") stacked[stacked$survivor == 1L, ] else stacked
  for (outcome in OUTCOMES) for (delta in DELTAS) {
    r <- fit_fn(dat, outcome, delta); r$sample <- samp
    rows[[paste(samp, outcome, delta)]] <- r
    if (delta == 1L) message(sprintf("%-14s | %-16s d1 | t+1=%.3f t+3=%.3f t+5=%.3f",
        samp, outcome, r$att[r$event_time == 1], r$att[r$event_time == 3], r$att[r$event_time == 5]))
  }
}
res <- do.call(rbind, rows)
res <- res[order(res$sample, res$outcome, res$delta, res$event_time), ]
write_result(res, "fn_stayer_restricted_event_study.csv")

banner("FIGURE")
res$outcome_lab <- factor(OUTCOME_LABS[res$outcome], levels = OUTCOME_LABS)
res$sample_lab <- factor(res$sample, levels = c("full_cohort", "survivors_only"),
                         labels = c("Full pre-deal cohort", "Survivors only (stayer proxy)"))
res_d1 <- res[res$delta == 1L, ]
p <- ggplot2::ggplot(res_d1, ggplot2::aes(event_time, att, colour = sample_lab, fill = sample_lab)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), alpha = 0.13, linetype = 0) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey65", linewidth = 0.4, linetype = 2) +
  ggplot2::geom_line(linewidth = 0.8) + ggplot2::geom_point(size = 1.3) +
  ggplot2::facet_wrap(~outcome_lab, ncol = 3, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = seq(-5, 5, 1)) +
  ggplot2::scale_colour_manual(values = c("#1f77b4", "#8B0000")) +
  ggplot2::scale_fill_manual(values = c("#1f77b4", "#8B0000")) +
  ggplot2::labs(x = "Event time (relative to acquisition / placebo date)", y = "FN-corrected ATT (delta=1)",
    colour = NULL, fill = NULL,
    title = "FN-corrected effect: full cohort vs. survivors-only (stayer proxy)",
    subtitle = paste0("Survivor = patents in t+1..+5, applied identically to BOTH arms. ",
                      "Conditions on a post-outcome (Lee-bounds territory) -- intensive margin among survivors.")) +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), legend.position = "bottom",
                 plot.title = ggplot2::element_text(face = "bold", colour = "#1B4332", size = 11),
                 plot.subtitle = ggplot2::element_text(colour = "#6B7280", size = 8),
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
fig_path <- file.path(FIGS, "figure15_fn_stayer_restricted.png")
ggplot2::ggsave(fig_path, p, width = 10, height = 4.2, dpi = 300, bg = "white")

banner("08v COMPLETE")
message("Figure: ", fig_path)
message("Table:  ", file.path(RESULTS, "fn_stayer_restricted_event_study.csv"))
