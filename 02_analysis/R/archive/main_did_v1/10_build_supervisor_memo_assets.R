# Build all quantitative assets for the five-page supervisor memo.
#
# The database is opened read-only. Descriptive confidence intervals use a
# nonparametric bootstrap that resamples complete acquisition deals. DiD
# intervals are simultaneous multiplier-bootstrap bands clustered by deal.
#
# Run from the project root:
#   Rscript 02_analysis/R/10_build_supervisor_memo_assets.R

BASE     <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB   <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS  <- file.path(BASE, "output", "results", "supervisor_memo")
FIGURES  <- file.path(BASE, "output", "figures", "supervisor_memo")
CS_DIR   <- file.path(BASE, "output", "results", "cs2021_common_support")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "did", "ggplot2", "cowplot", "scales")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGURES, recursive = TRUE, showWarnings = FALSE)

B <- 999L
SEED <- 20260702L
GREEN <- "#1B4332"
PALE_GREEN <- "#DCEDE4"
ORANGE <- "#D97706"
GREY <- "#6B7280"

write_result <- function(x, filename) {
  utils::write.csv(x, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

save_figure <- function(plot, stem, width, height) {
  ggplot2::ggsave(file.path(FIGURES, paste0(stem, ".pdf")), plot,
                  width = width, height = height, units = "in", device = grDevices::cairo_pdf)
  ggplot2::ggsave(file.path(FIGURES, paste0(stem, ".png")), plot,
                  width = width, height = height, units = "in", dpi = 320, bg = "white")
}

memo_theme <- function(base_size = 10) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold", color = GREEN, size = base_size + 1),
      plot.subtitle = ggplot2::element_text(color = GREY, size = base_size - 1),
      axis.title = ggplot2::element_text(color = "grey25"),
      axis.text = ggplot2::element_text(color = "grey25"),
      legend.title = ggplot2::element_blank(),
      plot.background = ggplot2::element_rect(fill = "white", color = NA)
    )
}

# Resample whole deals and evaluate event-time ratios in each draw.
cluster_bootstrap <- function(dat, numerator, denominator, group_vars = "event_time") {
  deals <- sort(unique(dat$deal_id))
  dat$deal_index <- match(dat$deal_id, deals)
  key <- interaction(dat[group_vars], drop = TRUE, lex.order = TRUE)
  groups <- split(seq_len(nrow(dat)), key)
  draw_values <- matrix(NA_real_, nrow = B, ncol = length(groups))
  set.seed(SEED)
  for (b in seq_len(B)) {
    deal_weights <- tabulate(sample.int(length(deals), length(deals), replace = TRUE),
                             nbins = length(deals))
    for (j in seq_along(groups)) {
      ii <- groups[[j]]
      w <- deal_weights[dat$deal_index[ii]]
      den <- sum(w * dat[[denominator]][ii])
      draw_values[b, j] <- if (den > 0) sum(w * dat[[numerator]][ii]) / den else NA_real_
    }
  }
  out <- do.call(rbind, lapply(groups, function(ii) dat[ii[1], group_vars, drop = FALSE]))
  out$estimate <- vapply(groups, function(ii) {
    sum(dat[[numerator]][ii]) / sum(dat[[denominator]][ii])
  }, numeric(1))
  out$ci_low <- apply(draw_values, 2, stats::quantile, probs = 0.025, na.rm = TRUE)
  out$ci_high <- apply(draw_values, 2, stats::quantile, probs = 0.975, na.rm = TRUE)
  out
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

message("Building descriptive deal-clustered intervals...")

event_cells <- DBI::dbGetQuery(con, "
  SELECT CAST(deal_id AS INTEGER) AS deal_id,
         CAST(event_time AS INTEGER) AS event_time,
         COUNT(*)::DOUBLE AS n_rows,
         SUM(patent_count)::DOUBLE AS patents,
         SUM(CASE WHEN patent_count > 0 THEN 1 ELSE 0 END)::DOUBLE AS active
  FROM target_cohort_event_panel
  GROUP BY deal_id, event_time
  ORDER BY deal_id, event_time
")

if (anyDuplicated(event_cells[c("deal_id", "event_time")])) {
  stop("Descriptive deal-event cells are not unique.")
}

raw_patents <- cluster_bootstrap(event_cells, "patents", "n_rows")
active_margin <- cluster_bootstrap(event_cells, "active", "n_rows")
intensive_margin <- cluster_bootstrap(event_cells, "patents", "active")
raw_patents$outcome <- "Mean patents per inventor"
active_margin$outcome <- "Probability of any patent"
intensive_margin$outcome <- "Patents per active inventor"
write_result(raw_patents, "descriptive_raw_patents_bootstrap.csv")
write_result(rbind(active_margin, intensive_margin), "descriptive_margins_bootstrap.csv")

selection_cells <- DBI::dbGetQuery(con, "
  WITH inventor_stock AS (
    SELECT codinv, CAST(deal_id AS INTEGER) AS deal_id,
           SUM(patent_count) AS predeal_patent_stock,
           MAX(CASE WHEN status_available THEN 1 ELSE 0 END) AS eligible,
           MAX(CASE WHEN type = 'T_Ever_Stayed' THEN 1 ELSE 0 END) AS stayed
    FROM target_cohort_event_panel
    WHERE event_time BETWEEN -5 AND -1
    GROUP BY codinv, deal_id
  ), binned AS (
    SELECT *, CASE WHEN predeal_patent_stock = 1 THEN '1'
                   WHEN predeal_patent_stock = 2 THEN '2'
                   WHEN predeal_patent_stock >= 3 THEN '3+' ELSE '0' END AS stock_group
    FROM inventor_stock
  )
  SELECT deal_id, stock_group,
         SUM(eligible)::DOUBLE AS eligible,
         SUM(stayed)::DOUBLE AS stayed,
         COUNT(*)::DOUBLE AS cohort_n
  FROM binned
  GROUP BY deal_id, stock_group
")
if (any(selection_cells$stock_group == "0")) stop("Unexpected zero-stock clean-cohort inventor.")
selection_ci <- cluster_bootstrap(selection_cells, "stayed", "eligible", "stock_group")
selection_ci$stock_group <- factor(selection_ci$stock_group, levels = c("1", "2", "3+"))
selection_ci <- selection_ci[order(selection_ci$stock_group), ]
write_result(selection_ci, "selection_stayer_share_bootstrap.csv")

reach_cells <- DBI::dbGetQuery(con, "
  WITH units AS (
    SELECT DISTINCT p.codinv, CAST(p.deal_id AS INTEGER) AS deal_id, p.deal_year,
           s.first_acquirer_year, s.first_other_known_year
    FROM target_cohort_event_panel p
    LEFT JOIN inventor_status_own s
      ON p.codinv = s.codinv AND p.deal_id = s.deal_id
  ), event_grid AS (
    SELECT * FROM range(0, 6) AS t(event_time)
  ), unit_reach AS (
    SELECT g.event_time, u.codinv, u.deal_id,
           MAX(CASE WHEN p.event_time BETWEEN 0 AND g.event_time
                         AND p.patent_count > 0 THEN 1 ELSE 0 END) AS any_patent,
           MAX(CASE WHEN u.first_acquirer_year <= u.deal_year + g.event_time THEN 1 ELSE 0 END) AS acquirer,
           MAX(CASE WHEN u.first_other_known_year <= u.deal_year + g.event_time THEN 1 ELSE 0 END) AS outside
    FROM units u CROSS JOIN event_grid g
    LEFT JOIN target_cohort_event_panel p
      ON u.codinv = p.codinv AND u.deal_id = p.deal_id
    GROUP BY g.event_time, u.codinv, u.deal_id
  )
  SELECT CAST(deal_id AS INTEGER) AS deal_id, CAST(event_time AS INTEGER) AS event_time,
         SUM(any_patent)::DOUBLE AS any_patent,
         SUM(acquirer)::DOUBLE AS acquirer,
         SUM(outside)::DOUBLE AS outside,
         COUNT(*)::DOUBLE AS cohort_n
  FROM unit_reach
  GROUP BY deal_id, event_time
")

reach_list <- lapply(c(any_patent = "Any post-deal patent",
                       acquirer = "Acquirer-affiliated patent",
                       outside = "Outside-group patent"), function(label) NULL)
reach_list <- Map(function(v, label) {
  z <- cluster_bootstrap(reach_cells, v, "cohort_n")
  z$reach_type <- label
  z
}, c("any_patent", "acquirer", "outside"),
   c("Any post-deal patent", "Acquirer-affiliated patent", "Outside-group patent"))
reach_ci <- do.call(rbind, reach_list)
write_result(reach_ci, "selection_cumulative_reach_bootstrap.csv")

sample_audit <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS inventor_years,
         COUNT(DISTINCT codinv || ':' || deal_id) AS inventors,
         COUNT(DISTINCT deal_id) AS deals,
         MIN(event_time) AS min_event, MAX(event_time) AS max_event
  FROM target_cohort_event_panel
")
write_result(sample_audit, "descriptive_sample_audit.csv")

# Descriptive figures.
p_raw <- ggplot2::ggplot(raw_patents, ggplot2::aes(event_time, estimate)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), fill = PALE_GREEN, alpha = 0.9) +
  ggplot2::geom_vline(xintercept = 0, color = ORANGE, linewidth = 0.55, linetype = 2) +
  ggplot2::geom_line(color = GREEN, linewidth = 0.9) +
  ggplot2::geom_point(color = GREEN, size = 1.8) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(x = "Years relative to acquisition", y = "Patents per inventor",
                title = "Raw inventor output peaks before acquisition and then falls",
                subtitle = "Full clean target cohort; shaded area is the 95% deal-cluster bootstrap interval") +
  memo_theme(10)
save_figure(p_raw, "memo_figure1_raw_patents", 7.2, 3.25)

margin_data <- rbind(active_margin, intensive_margin)
margin_data$panel <- factor(margin_data$outcome,
                            levels = c("Probability of any patent", "Patents per active inventor"),
                            labels = c("A. Extensive margin: any patent", "B. Conditional output: patents per active inventor"))
p_margins <- ggplot2::ggplot(margin_data, ggplot2::aes(event_time, estimate)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), fill = PALE_GREEN, alpha = 0.9) +
  ggplot2::geom_vline(xintercept = 0, color = ORANGE, linewidth = 0.5, linetype = 2) +
  ggplot2::geom_line(color = GREEN, linewidth = 0.85) +
  ggplot2::geom_point(color = GREEN, size = 1.55) +
  ggplot2::facet_wrap(~panel, scales = "free_y", nrow = 1) +
  ggplot2::scale_x_continuous(breaks = seq(-4, 4, 2)) +
  ggplot2::labs(x = "Years relative to acquisition", y = NULL,
                title = "The decline is extensive; conditional output reflects a selected survivor pool",
                subtitle = "95% deal-cluster bootstrap intervals; the intensive-margin ratio is recomputed in every draw") +
  memo_theme(9.5)
save_figure(p_margins, "memo_figure2_margins", 7.2, 3.15)

stock_labels <- setNames(c("1 patent", "2 patents", "3+ patents"), c("1", "2", "3+"))
p_sel_a <- ggplot2::ggplot(selection_ci, ggplot2::aes(stock_group, estimate)) +
  ggplot2::geom_col(fill = GREEN, width = 0.58) +
  ggplot2::geom_errorbar(ggplot2::aes(ymin = ci_low, ymax = ci_high), width = 0.13,
                         color = ORANGE, linewidth = 0.7) +
  ggplot2::scale_x_discrete(labels = stock_labels) +
  ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
  ggplot2::labs(x = NULL, y = "Observed stayer share",
               title = "A. Probability of staying rises\nwith pre-deal patent count") +
  memo_theme(9)

reach_ci$reach_type <- factor(reach_ci$reach_type,
  levels = c("Any post-deal patent", "Acquirer-affiliated patent", "Outside-group patent"))
reach_colors <- c("Any post-deal patent" = "#536878", "Acquirer-affiliated patent" = GREEN,
                  "Outside-group patent" = ORANGE)
p_sel_b <- ggplot2::ggplot(reach_ci,
                           ggplot2::aes(event_time, estimate, color = reach_type, fill = reach_type)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), alpha = 0.12, color = NA) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.35) +
  ggplot2::scale_color_manual(values = reach_colors,
    labels = c("Any patent", "Acquirer", "Outside group")) +
  ggplot2::scale_fill_manual(values = reach_colors,
    labels = c("Any patent", "Acquirer", "Outside group")) +
  ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  ggplot2::scale_x_continuous(breaks = 0:5) +
  ggplot2::labs(x = "Years since acquisition", y = "Cumulative share of full cohort",
                title = "B. Most inventors do not reappear after the deal") +
  memo_theme(9) +
  ggplot2::theme(legend.position = "bottom", legend.text = ggplot2::element_text(size = 7.2),
                 legend.key.width = grid::unit(0.55, "cm")) +
  ggplot2::guides(color = ggplot2::guide_legend(nrow = 1),
                  fill = ggplot2::guide_legend(nrow = 1))
p_selection <- cowplot::plot_grid(p_sel_a, p_sel_b, nrow = 1, rel_widths = c(0.88, 1.25))
save_figure(p_selection, "memo_figure3_selection", 7.2, 3.0)

message("Building matched citation outcome and DiD figure...")

# Rebuild the exact 08h common-support sample and add a deduplicated citation outcome.
full_panel <- DBI::dbGetQuery(con, "
  WITH patent_citations AS (
    SELECT DISTINCT p.appln_id, p.codinv, p.year,
           COALESCE(q.fwd_cits5, 0)::DOUBLE AS fwd_cits5
    FROM patent_inventor_enriched p
    LEFT JOIN oecd_quality q ON p.appln_id = q.appln_id
  ), inventor_year_citations AS (
    SELECT codinv, year, SUM(fwd_cits5)::DOUBLE AS citations_5y
    FROM patent_citations
    GROUP BY codinv, year
  )
  SELECT CAST(p.codinv AS DOUBLE) AS codinv,
         CAST(p.deal_id AS INTEGER) AS deal_id,
         CAST(p.deal_year AS INTEGER) AS deal_year,
         CAST(p.calendar_year AS INTEGER) AS calendar_year,
         CAST(p.active_patenting AS DOUBLE) AS active_patenting,
         CAST(p.log_patent_count AS DOUBLE) AS log_patent_count,
         LN(1 + COALESCE(c.citations_5y, 0))::DOUBLE AS log_citations_5y,
         CAST(p.career_age_at_deal AS DOUBLE) AS career_age_at_deal,
         CAST(p.career_age_sq_at_deal AS DOUBLE) AS career_age_sq_at_deal,
         p.ipc_primary_field,
         CAST(p.log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
         CAST(p.log_group_size AS DOUBLE) AS log_group_size,
         CAST(p.log_deal_value AS DOUBLE) AS log_deal_value
  FROM cs2021_estimation_panel p
  LEFT JOIN inventor_year_citations c
    ON p.codinv = c.codinv AND p.calendar_year = c.year
  ORDER BY p.codinv, p.calendar_year
")
full_panel$ipc_primary_field <- factor(full_panel$ipc_primary_field)

cell_coverage <- DBI::dbGetQuery(con, "
  WITH unit AS (
    SELECT DISTINCT codinv, deal_id, deal_year, predeal_patent_stock_5y, ipc_primary_field
    FROM cs2021_estimation_panel
  ), binned AS (
    SELECT *, NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
    FROM unit
  )
  SELECT patent_stock_quintile, ipc_primary_field,
         COUNT(DISTINCT deal_year) AS n_cohorts,
         MAX(deal_year) - MIN(deal_year) AS cohort_year_span
  FROM binned GROUP BY patent_stock_quintile, ipc_primary_field
")
allowed_cells <- cell_coverage[cell_coverage$n_cohorts >= 3 & cell_coverage$cohort_year_span >= 5,
                               c("patent_stock_quintile", "ipc_primary_field")]
unit_bins <- DBI::dbGetQuery(con, "
  WITH unit AS (
    SELECT DISTINCT codinv, deal_id, predeal_patent_stock_5y FROM cs2021_estimation_panel
  )
  SELECT codinv, deal_id,
         NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
  FROM unit
")
unit_bins$codinv <- as.double(unit_bins$codinv)
full_panel <- merge(full_panel, unit_bins, by = c("codinv", "deal_id"))
full_panel <- merge(full_panel,
  transform(allowed_cells, in_common_support = TRUE),
  by = c("patent_stock_quintile", "ipc_primary_field"), all.x = TRUE)
matched_panel <- full_panel[!is.na(full_panel$in_common_support), , drop = FALSE]
matched_panel <- matched_panel[order(matched_panel$codinv, matched_panel$calendar_year), ]

if (anyDuplicated(matched_panel[c("codinv", "calendar_year")])) stop("Matched inventor-years are not unique.")
if (length(unique(matched_panel$codinv)) != 32233L || length(unique(matched_panel$deal_id)) != 450L) {
  stop("Common-support sample changed: expected 32,233 inventors and 450 deals.")
}
if (any(!is.finite(matched_panel$log_citations_5y))) stop("Citation outcome contains nonfinite values.")

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal + ipc_primary_field +
  log_predeal_patent_stock + log_group_size + log_deal_value

run_did <- function(outcome, xformla, anticipation = 1) {
  set.seed(SEED)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "deal_year",
    xformla = xformla, data = matched_panel, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "notyettreated", anticipation = anticipation, base_period = "universal",
    est_method = "dr", bstrap = TRUE, biters = B, clustervars = "deal_id",
    cband = TRUE, print_details = FALSE
  )
  dynamic <- did::aggte(att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5,
                        na.rm = TRUE, bstrap = TRUE, biters = B,
                        clustervars = "deal_id", cband = TRUE)
  list(att = att, dynamic = dynamic)
}

active_rds <- file.path(CS_DIR, "aggte_matched_bootstrap_active_patenting.rds")
patent_rds <- file.path(CS_DIR, "aggte_matched_bootstrap_log_patent_count.rds")
if (!file.exists(active_rds) || !file.exists(patent_rds)) stop("Run 08h before building the memo assets.")

controlled_ok <- TRUE
citation_att_cache <- file.path(RESULTS, "att_gt_matched_bootstrap_log_citations_5y.rds")
citation_dynamic_cache <- file.path(RESULTS, "aggte_matched_bootstrap_log_citations_5y.rds")
if (file.exists(citation_att_cache) && file.exists(citation_dynamic_cache)) {
  message("Reusing the completed controlled citation bootstrap.")
  citation_fit <- list(att = readRDS(citation_att_cache), dynamic = readRDS(citation_dynamic_cache))
} else {
  citation_fit <- tryCatch(run_did("log_citations_5y", xformla_lean),
    error = function(e) { message("Controlled citation model failed: ", conditionMessage(e)); NULL })
}
if (is.null(citation_fit) || any(!is.finite(citation_fit$dynamic$att.egt)) ||
    any(!is.finite(citation_fit$dynamic$se.egt[!is.na(citation_fit$dynamic$se.egt)]))) controlled_ok <- FALSE

if (controlled_ok) {
  did_fits <- list(active_patenting = list(dynamic = readRDS(active_rds)),
                   log_patent_count = list(dynamic = readRDS(patent_rds)),
                   log_citations_5y = citation_fit)
  model_label <- "Lean predetermined controls"
  saveRDS(citation_fit$att, citation_att_cache)
  saveRDS(citation_fit$dynamic, citation_dynamic_cache)
} else {
  message("Using one uncontrolled common-support specification for all three panels.")
  did_fits <- lapply(c("active_patenting", "log_patent_count", "log_citations_5y"),
                     function(y) run_did(y, ~1))
  names(did_fits) <- c("active_patenting", "log_patent_count", "log_citations_5y")
  model_label <- "No covariates (common fallback)"
}

extract_dynamic <- function(fit, outcome, panel) {
  d <- fit$dynamic
  crit <- suppressWarnings(as.numeric(d$crit.val.egt))[1]
  if (!is.finite(crit)) stop("Missing simultaneous critical value for ", outcome)
  z <- data.frame(outcome = outcome, panel = panel, event_time = d$egt,
                  att = d$att.egt, se = d$se.egt, critical_value = crit)
  z$ci_low <- z$att - crit * z$se
  z$ci_high <- z$att + crit * z$se
  base <- is.na(z$se) & abs(z$att) < 1e-12
  z$se[base] <- 0; z$ci_low[base] <- 0; z$ci_high[base] <- 0
  z
}

did_dynamic <- rbind(
  extract_dynamic(did_fits$active_patenting, "active_patenting", "A. Probability of filing any patent"),
  extract_dynamic(did_fits$log_patent_count, "log1p_patents", "B. log(1 + patents)"),
  extract_dynamic(did_fits$log_citations_5y, "log1p_citations_5y", "C. log(1 + five-year forward citations)")
)
did_dynamic$model <- model_label
did_dynamic$n_inventors <- length(unique(matched_panel$codinv))
did_dynamic$n_deals <- length(unique(matched_panel$deal_id))
write_result(did_dynamic, "did_dynamic_simultaneous_bands.csv")
write_result(did_dynamic[did_dynamic$event_time %in% c(-4, -3, 0, 5), ], "did_key_event_estimates.csv")

p_did <- ggplot2::ggplot(did_dynamic, ggplot2::aes(event_time, att)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), fill = PALE_GREEN, alpha = 0.9) +
  ggplot2::geom_hline(yintercept = 0, color = "grey55", linewidth = 0.35) +
  ggplot2::geom_vline(xintercept = 0, color = "grey65", linewidth = 0.4, linetype = 2) +
  ggplot2::geom_line(color = GREEN, linewidth = 0.75) +
  ggplot2::geom_point(color = GREEN, size = 1.35) +
  ggplot2::geom_point(data = did_dynamic[did_dynamic$event_time == -3, ], color = ORANGE, size = 2.25) +
  ggplot2::facet_wrap(~panel, nrow = 1, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = c(-4, -2, 0, 2, 4)) +
  ggplot2::labs(x = "Event time", y = "ATT relative to t = -2",
                title = "Provisional DiD estimates show negative post-deal effects—but also a positive lead",
                subtitle = "Callaway–Sant'Anna DR; anticipation = 1; 95% simultaneous bands clustered by deal; orange marks t = -3") +
  memo_theme(8.6) +
  ggplot2::theme(strip.text = ggplot2::element_text(face = "bold", color = GREEN, size = 8.1))
save_figure(p_did, "memo_figure4_did", 7.4, 3.15)

message("Building the no-anticipation (anticipation = 0) DiD figure...")

# Companion figure: the same matched sample and outcomes with anticipation = 0
# (reference t = -1), so the raw pre-deal lead is visible before any anticipation
# adjustment. The two patent outcomes reuse the anticipation=0 objects already
# saved by 08i; the citation outcome is run once here and cached.
active_rds0 <- file.path(CS_DIR, "aggte_matched_bootstrap_anticipation0_active_patenting.rds")
patent_rds0 <- file.path(CS_DIR, "aggte_matched_bootstrap_anticipation0_log_patent_count.rds")
if (!file.exists(active_rds0) || !file.exists(patent_rds0)) {
  stop("Run 08i (anticipation=0 arm) before building the no-anticipation memo figure.")
}

citation_att_cache0 <- file.path(RESULTS, "att_gt_matched_bootstrap_anticipation0_log_citations_5y.rds")
citation_dynamic_cache0 <- file.path(RESULTS, "aggte_matched_bootstrap_anticipation0_log_citations_5y.rds")
if (file.exists(citation_att_cache0) && file.exists(citation_dynamic_cache0)) {
  message("Reusing the completed anticipation=0 citation bootstrap.")
  citation_fit0 <- list(att = readRDS(citation_att_cache0), dynamic = readRDS(citation_dynamic_cache0))
} else if (controlled_ok) {
  citation_fit0 <- run_did("log_citations_5y", xformla_lean, anticipation = 0)
  saveRDS(citation_fit0$att, citation_att_cache0)
  saveRDS(citation_fit0$dynamic, citation_dynamic_cache0)
} else {
  citation_fit0 <- run_did("log_citations_5y", ~1, anticipation = 0)
}

did_fits0 <- list(active_patenting = list(dynamic = readRDS(active_rds0)),
                  log_patent_count = list(dynamic = readRDS(patent_rds0)),
                  log_citations_5y = citation_fit0)

did_dynamic0 <- rbind(
  extract_dynamic(did_fits0$active_patenting, "active_patenting", "A. Probability of filing any patent"),
  extract_dynamic(did_fits0$log_patent_count, "log1p_patents", "B. log(1 + patents)"),
  extract_dynamic(did_fits0$log_citations_5y, "log1p_citations_5y", "C. log(1 + five-year forward citations)")
)
did_dynamic0$model <- model_label
did_dynamic0$anticipation <- 0L
write_result(did_dynamic0, "did_dynamic_noanticipation_bands.csv")

p_did0 <- ggplot2::ggplot(did_dynamic0, ggplot2::aes(event_time, att)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), fill = PALE_GREEN, alpha = 0.9) +
  ggplot2::geom_hline(yintercept = 0, color = "grey55", linewidth = 0.35) +
  ggplot2::geom_vline(xintercept = 0, color = "grey65", linewidth = 0.4, linetype = 2) +
  ggplot2::geom_line(color = GREEN, linewidth = 0.75) +
  ggplot2::geom_point(color = GREEN, size = 1.35) +
  ggplot2::geom_point(data = did_dynamic0[did_dynamic0$event_time %in% c(-4, -3), ],
                      color = ORANGE, size = 2.25) +
  ggplot2::facet_wrap(~panel, nrow = 1, scales = "free_y") +
  ggplot2::scale_x_continuous(breaks = c(-4, -2, 0, 2, 4)) +
  ggplot2::labs(x = "Event time", y = "ATT relative to t = -1",
                title = "Without an anticipation window, the pre-deal lead is even larger",
                subtitle = "Callaway–Sant'Anna DR; anticipation = 0; 95% simultaneous bands clustered by deal; orange marks t = -4 and t = -3") +
  memo_theme(8.6) +
  ggplot2::theme(strip.text = ggplot2::element_text(face = "bold", color = GREEN, size = 8.1))
save_figure(p_did0, "memo_figure_did_noanticipation", 7.4, 3.15)

did_audit <- data.frame(
  check = c("unique_inventor_year", "citation_sample_inventors", "citation_sample_deals",
            "bootstrap_iterations", "cluster_variable", "model"),
  value = c(!anyDuplicated(matched_panel[c("codinv", "calendar_year")]),
            length(unique(matched_panel$codinv)), length(unique(matched_panel$deal_id)),
            B, "deal_id", model_label)
)
write_result(did_audit, "did_sample_and_inference_audit.csv")

message("Memo assets complete: ", FIGURES)
