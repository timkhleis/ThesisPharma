# Diagnostic 1: Qualifying-year split
# Tests whether pre-trend hump fingerprint tracks individual inventors' own
# qualification timing (mechanical artifact signature) or is synchronized across
# inventors (genuine timing-selection signature).
#
# Run from project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08r_qualifying_year_split.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
AUDIT   <- file.path(BASE, "output", "audit", "qualifying_year_split")
FIGS    <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

dir.create(AUDIT, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_csv_base <- function(df, filename) {
  utils::write.csv(df, file.path(AUDIT, filename), row.names = FALSE, na = "")
}

# Cluster bootstrap reusing the pattern from 10_build_supervisor_memo_assets.R:57-81
cluster_bootstrap <- function(dat, numerator, denominator, group_vars = "event_time", B = 999, seed_val = 20260701L) {
  deals <- sort(unique(dat$deal_id))
  dat$deal_index <- match(dat$deal_id, deals)
  key <- interaction(dat[group_vars], drop = TRUE, lex.order = TRUE)
  groups <- split(seq_len(nrow(dat)), key)
  draw_values <- matrix(NA_real_, nrow = B, ncol = length(groups))
  set.seed(seed_val)
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

banner("QUALIFYING-YEAR SPLIT DIAGNOSTIC")
section("Loading data")

# Get target_cohort_own with last_pre_affiliation_year
cohort_base <- DBI::dbGetQuery(con, "
  SELECT CAST(codinv AS DOUBLE) AS codinv,
         CAST(deal_id AS INTEGER) AS deal_id,
         CAST(deal_year AS INTEGER) AS deal_year,
         CAST(last_pre_affiliation_year AS INTEGER) AS last_pre_affiliation_year
  FROM target_cohort_own
")

# Get event panel
event_panel <- DBI::dbGetQuery(con, "
  SELECT CAST(codinv AS DOUBLE) AS codinv,
         CAST(deal_id AS INTEGER) AS deal_id,
         CAST(event_time AS INTEGER) AS event_time,
         CAST(patent_count AS DOUBLE) AS patent_count,
         CAST(CASE WHEN patent_count > 0 THEN 1 ELSE 0 END AS DOUBLE) AS active_patenting
  FROM target_cohort_event_panel
  WHERE event_time BETWEEN -5 AND 5
")

section("Computing qualifying gap")

# Merge cohort base with event panel
merged <- merge(event_panel, cohort_base, by = c("codinv", "deal_id"), all.x = TRUE)

# Compute qualifying_gap = deal_year - last_pre_affiliation_year (ranges 1-5 by construction)
merged$qualifying_gap <- merged$deal_year - merged$last_pre_affiliation_year

# Verify gap is in expected range
gap_range <- range(merged$qualifying_gap, na.rm = TRUE)
message("Qualifying gap range: ", gap_range[1], " to ", gap_range[2])
if (any(is.na(merged$qualifying_gap))) {
  stop("NAs in qualifying_gap -- join or data integrity issue")
}

section("Computing bootstrap CIs by qualifying gap and event time")

# For each qualifying_gap × event_time cell
gap_cells <- DBI::dbGetQuery(con, "
  SELECT CAST(event_time AS INTEGER) AS event_time,
         CAST(patent_count AS DOUBLE) AS patent_count,
         CAST(CASE WHEN patent_count > 0 THEN 1 ELSE 0 END AS DOUBLE) AS active_patenting,
         CAST(deal_id AS INTEGER) AS deal_id,
         CAST(codinv AS DOUBLE) AS codinv,
         CAST(deal_year AS INTEGER) AS deal_year,
         CAST(last_pre_affiliation_year AS INTEGER) AS last_pre_affiliation_year,
         CAST(deal_year - last_pre_affiliation_year AS INTEGER) AS qualifying_gap,
         COUNT(*)::DOUBLE AS n_rows,
         SUM(CASE WHEN patent_count > 0 THEN 1 ELSE 0 END)::DOUBLE AS n_active
  FROM (
    SELECT ep.codinv, ep.deal_id, ep.event_time, ep.patent_count,
           tco.deal_year, tco.last_pre_affiliation_year
    FROM target_cohort_event_panel ep
    JOIN target_cohort_own tco USING (codinv, deal_id)
    WHERE ep.event_time BETWEEN -5 AND 5
  ) joined
  GROUP BY event_time, patent_count, CASE WHEN patent_count > 0 THEN 1 ELSE 0 END,
           deal_id, codinv, deal_year, last_pre_affiliation_year,
           CAST(deal_year - last_pre_affiliation_year AS INTEGER)
")

# Simplify to per-deal-event-gap level for bootstrap
summary_cells <- DBI::dbGetQuery(con, "
  WITH gap_data AS (
    SELECT CAST(event_time AS INTEGER) AS event_time,
           CAST(deal_id AS INTEGER) AS deal_id,
           CAST(deal_year - last_pre_affiliation_year AS INTEGER) AS qualifying_gap,
           CAST(patent_count AS DOUBLE) AS patent_count,
           CAST(CASE WHEN patent_count > 0 THEN 1 ELSE 0 END AS DOUBLE) AS active_patenting
    FROM (
      SELECT ep.codinv, ep.deal_id, ep.event_time, ep.patent_count,
             tco.deal_year, tco.last_pre_affiliation_year
      FROM target_cohort_event_panel ep
      JOIN target_cohort_own tco USING (codinv, deal_id)
      WHERE ep.event_time BETWEEN -5 AND 5
    ) joined
  )
  SELECT event_time, deal_id, qualifying_gap,
         SUM(patent_count)::DOUBLE AS patents,
         SUM(active_patenting)::DOUBLE AS active,
         COUNT(*)::DOUBLE AS n_rows
  FROM gap_data
  GROUP BY event_time, deal_id, qualifying_gap
  ORDER BY event_time, deal_id, qualifying_gap
")

summary_cells$event_time <- as.integer(summary_cells$event_time)
summary_cells$deal_id <- as.integer(summary_cells$deal_id)
summary_cells$qualifying_gap <- as.integer(summary_cells$qualifying_gap)

# Bootstrap CIs for each outcome, grouped by (qualifying_gap, event_time)
message("Computing active_patenting bootstrap CIs...")
active_bootstrap <- cluster_bootstrap(summary_cells, "active", "n_rows",
                                      group_vars = c("qualifying_gap", "event_time"))
active_bootstrap$outcome <- "active_patenting"

message("Computing log_patent_count bootstrap CIs...")
# For log outcome, use the patent counts
patents_bootstrap <- cluster_bootstrap(summary_cells, "patents", "n_rows",
                                       group_vars = c("qualifying_gap", "event_time"))
patents_bootstrap$log_patent_estimate <- log(1 + patents_bootstrap$estimate)
patents_bootstrap$log_patent_ci_low <- log(1 + patents_bootstrap$ci_low)
patents_bootstrap$log_patent_ci_high <- log(1 + patents_bootstrap$ci_high)
patents_bootstrap$outcome <- "log_patent_count"
patents_bootstrap$estimate <- patents_bootstrap$log_patent_estimate
patents_bootstrap$ci_low <- patents_bootstrap$log_patent_ci_low
patents_bootstrap$ci_high <- patents_bootstrap$log_patent_ci_high
patents_bootstrap <- patents_bootstrap[, c("qualifying_gap", "event_time", "estimate", "ci_low", "ci_high", "outcome")]

section("Writing audit outputs")

# Full grid
full_grid <- rbind(active_bootstrap, patents_bootstrap)
write_csv_base(full_grid, "qualifying_gap_by_event_time.csv")

# Summary table: peak event_time per gap per outcome
summary_table <- do.call(rbind, lapply(split(full_grid, list(full_grid$qualifying_gap, full_grid$outcome)), function(subset) {
  if (nrow(subset) == 0) return(NULL)
  peak_idx <- which.max(subset$estimate)
  data.frame(
    qualifying_gap = subset$qualifying_gap[1],
    outcome = subset$outcome[1],
    n_inventors = NA_integer_,  # placeholder
    n_deals = NA_integer_,
    peak_event_time = subset$event_time[peak_idx],
    peak_estimate = subset$estimate[peak_idx],
    peak_ci_low = subset$ci_low[peak_idx],
    peak_ci_high = subset$ci_high[peak_idx]
  )
}))

if (!is.null(summary_table)) {
  # Enrich with counts
  gap_counts <- DBI::dbGetQuery(con, "
    WITH gap_data AS (
      SELECT CAST(deal_year - last_pre_affiliation_year AS INTEGER) AS qualifying_gap,
             CAST(codinv AS DOUBLE) AS codinv,
             CAST(deal_id AS INTEGER) AS deal_id
      FROM (
        SELECT ep.codinv, ep.deal_id, tco.deal_year, tco.last_pre_affiliation_year
        FROM target_cohort_event_panel ep
        JOIN target_cohort_own tco USING (codinv, deal_id)
        WHERE ep.event_time BETWEEN -5 AND 5
      ) joined
    )
    SELECT qualifying_gap,
           COUNT(DISTINCT codinv) AS n_inventors,
           COUNT(DISTINCT deal_id) AS n_deals
    FROM gap_data
    GROUP BY qualifying_gap
  ")

  summary_table <- merge(summary_table, gap_counts, by = "qualifying_gap", all.x = TRUE)
  write_csv_base(summary_table, "qualifying_gap_summary.csv")
}

section("Generating figure")

p <- ggplot2::ggplot(full_grid, ggplot2::aes(x = event_time, y = estimate,
                                               colour = factor(qualifying_gap),
                                               fill = factor(qualifying_gap),
                                               group = factor(qualifying_gap))) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high), alpha = 0.15, linetype = 0) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.5) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4, linetype = 2) +
  ggplot2::facet_wrap(~outcome, scales = "free_y", ncol = 1) +
  ggplot2::scale_x_continuous(breaks = seq(-5, 5, 1)) +
  ggplot2::scale_colour_brewer(palette = "Set1", name = "Qualifying gap\n(deal_year -\nlast_pre_year)") +
  ggplot2::scale_fill_brewer(palette = "Set1", guide = "none") +
  ggplot2::labs(
    x = "Event time (years relative to acquisition)",
    y = "Mean outcome",
    title = "Pre-trend hump fingerprint by inventor qualifying-year gap",
    subtitle = "Each line shows a different gap cohort; shading is 95% deal-cluster bootstrap CI.\nMechanical artifact: peaks track each gap's own event time. Genuine selection: all peak together."
  ) +
  ggplot2::theme_minimal(base_size = 9.5) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold", color = "#1B4332", size = 11),
    plot.subtitle = ggplot2::element_text(color = "#6B7280", size = 8),
    legend.position = "bottom",
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )

fig_path <- file.path(FIGS, "figure12_qualifying_gap_split.png")
ggplot2::ggsave(fig_path, p, width = 7.5, height = 5.5, dpi = 300, bg = "white")
message("Figure saved: ", fig_path)

banner("DIAGNOSTIC 1 COMPLETE")
message("Audit outputs: ", AUDIT)
message("Figure: ", fig_path)
message("\nPre-committed read:")
message("  Mechanical fingerprint: each gap bucket's peak event-time differs")
message("  Genuine selection: all gaps peak at same absolute event-time")
