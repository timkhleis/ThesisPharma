# Build Table 1 and Figures 1-3 for supervisor memo
#
# Run from project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/07_build_figures.R
#
# Outputs:
#   Tables  : 02_analysis/output/audit/preliminary_results/table1_sample_construction.csv
#   Figures : 02_analysis/output/figures/preliminary_results/
#               figure1_full_cohort.png
#               figure2_full_cohort_decomposition.png
#               figure3_selection_and_attrition.png

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
FIGURES <- file.path(BASE, "output", "figures", "preliminary_results")
TABLES  <- file.path(BASE, "output", "audit", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
load_packages()
library(duckdb)
library(ggplot2)
library(scales)
library(cowplot)

dir.create(FIGURES, recursive = TRUE, showWarnings = FALSE)
dir.create(TABLES,  recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")

write_csv_base <- function(df, filename) {
  utils::write.csv(df, file.path(TABLES, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB)
on.exit({ DBI::dbDisconnect(con, shutdown = TRUE) }, add = TRUE)

banner("BUILD FIGURES AND TABLE 1")

required_tables <- c(
  "target_cohort_event_panel",
  "target_cohort_own",
  "inventor_status_own",
  "cassi_deal_group_spine",
  "deal_map"
)
missing_tables <- required_tables[
  !vapply(required_tables, DBI::dbExistsTable, logical(1), conn = con)
]
if (length(missing_tables) > 0) {
  stop(
    "Missing required DuckDB tables: ", paste(missing_tables, collapse = ", "),
    "\n  Run 06_build_event_panel.R first."
  )
}

# ── Helper: event-study aggregation ─────────────────────────────────────────
agg_event_means <- function(con, filter_sql = "TRUE") {
  DBI::dbGetQuery(con, sprintf("
    SELECT
      event_time,
      COUNT(*)               AS n_rows,
      COUNT(DISTINCT codinv) AS n_inventors,
      AVG(patent_count)      AS patent_count_mean,
      AVG(fractional_patent_count) AS frac_patent_count_mean
    FROM target_cohort_event_panel
    WHERE %s
    GROUP BY event_time
    ORDER BY event_time
  ", filter_sql))
}

# ── Helper: event-study line + ribbon plot ───────────────────────────────────
# Adapted from 06_preliminary_results_archive.R (lines 48-79)
plot_event_means <- function(df, y_col, y_label, output_file, subtitle = NULL) {
  p <- ggplot(df, aes(x = event_time, y = .data[[y_col]])) +
    geom_line(color  = "#1b4332", linewidth = 0.9) +
    geom_point(color = "#1b4332", size = 2) +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "grey40") +
    scale_x_continuous(breaks = -5:5) +
    labs(
      x        = "Years relative to acquisition",
      y        = y_label,
      subtitle = subtitle,
      caption  = "Descriptive means — not CS(2021) ATT estimates."
    ) +
    theme_minimal(base_size = 12) +
    theme(
      panel.grid.minor  = element_blank(),
      plot.background   = element_rect(fill = "white", color = NA),
      plot.caption      = element_text(size = 8, color = "grey50")
    )
  ggsave(output_file, p, width = 7.2, height = 4.4, dpi = 300)
  message("Saved: ", output_file)
}

save_two_panel <- function(left_plot, right_plot, output_file,
                           width = 10.4, height = 4.8, dpi = 300) {
  grDevices::png(
    output_file,
    width = width,
    height = height,
    units = "in",
    res = dpi,
    bg = "white"
  )
  grid::grid.newpage()
  layout <- grid::grid.layout(nrow = 1, ncol = 2)
  grid::pushViewport(grid::viewport(layout = layout))
  print(left_plot, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  print(right_plot, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
  grid::popViewport()
  grDevices::dev.off()
  message("Saved: ", output_file)
}

# ── 1. Table 1: Sample Construction ─────────────────────────────────────────
section("Table 1: sample construction")

table1 <- DBI::dbGetQuery(con, "
SELECT 1 AS sort_order, 'Merger-list deals' AS metric,
       (SELECT COUNT(*) FROM deal_map) AS full_sample,
       (SELECT COUNT(*) FROM deal_map WHERE target_year BETWEEN 1993 AND 2010) AS clean_1993_2010
UNION ALL
SELECT 2, 'Unique matched target-spine deals',
       (SELECT COUNT(*) FROM cassi_deal_group_spine),
       (SELECT COUNT(*) FROM cassi_deal_group_spine WHERE deal_year BETWEEN 1993 AND 2010)
UNION ALL
SELECT 3, 'Pre-deal target inventors',
       (SELECT COUNT(*) FROM target_cohort_own),
       (SELECT COUNT(*) FROM target_cohort_own WHERE deal_year BETWEEN 1993 AND 2010)
UNION ALL
SELECT 4, 'Status-eligible target inventors',
       (SELECT COUNT(*) FROM inventor_status_own),
       (SELECT COUNT(*) FROM inventor_status_own WHERE deal_year BETWEEN 1993 AND 2010)
UNION ALL
SELECT 5, 'T_Ever_Stayed',
       (SELECT COUNT(*) FROM inventor_status_own WHERE type = 'T_Ever_Stayed'),
       (SELECT COUNT(*) FROM inventor_status_own WHERE type = 'T_Ever_Stayed' AND deal_year BETWEEN 1993 AND 2010)
UNION ALL
SELECT 6, 'T_LEAVER',
       (SELECT COUNT(*) FROM inventor_status_own WHERE type = 'T_LEAVER'),
       (SELECT COUNT(*) FROM inventor_status_own WHERE type = 'T_LEAVER' AND deal_year BETWEEN 1993 AND 2010)
UNION ALL
SELECT 7, 'T_NO_POST_5Y',
       (SELECT COUNT(*) FROM inventor_status_own WHERE type = 'T_NO_POST_5Y'),
       (SELECT COUNT(*) FROM inventor_status_own WHERE type = 'T_NO_POST_5Y' AND deal_year BETWEEN 1993 AND 2010)
ORDER BY sort_order
")

write_csv_base(table1, "table1_sample_construction.csv")
print(table1)

# ── 2. Figure 1: Full cohort event profile ───────────────────────────────────
section("Figure 1: full cohort")

means_all <- agg_event_means(con, "TRUE")
write_csv_base(means_all, "figure1_event_means_all.csv")

plot_event_means(
  means_all,
  y_col      = "patent_count_mean",
  y_label    = "Mean patent count",
  output_file= file.path(FIGURES, "figure1_full_cohort.png"),
  subtitle   = "All pre-deal target inventors — clean sample (deal years 1993–2010)"
)

# ── 3. Figure 2: Full-cohort patenting decomposition ────────────────────────
section("Figure 2: full-cohort patenting decomposition")

decomposition <- DBI::dbGetQuery(con, "
SELECT
  event_time,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT codinv) AS n_inventors,
  AVG(patent_count) AS unconditional_patent_mean,
  AVG(CASE WHEN patent_count > 0 THEN 1.0 ELSE 0.0 END) AS active_patenting_share,
  AVG(CASE WHEN patent_count > 0 THEN patent_count END) AS patents_per_active_inventor
FROM target_cohort_event_panel
GROUP BY event_time
ORDER BY event_time
")

decomposition$identity_difference <- with(
  decomposition,
  unconditional_patent_mean - active_patenting_share * patents_per_active_inventor
)
if (max(abs(decomposition$identity_difference), na.rm = TRUE) > 1e-10) {
  stop("Full-cohort decomposition identity failed.")
}
if (length(unique(decomposition$n_inventors)) != 1L) {
  stop("The full-cohort event panel does not retain a fixed inventor count.")
}
write_csv_base(decomposition, "figure2_full_cohort_decomposition.csv")

p2a <- ggplot(decomposition, aes(x = event_time, y = active_patenting_share)) +
  geom_line(color = "#1b4332", linewidth = 0.9) +
  geom_point(color = "#1b4332", size = 2) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "grey40") +
  scale_x_continuous(breaks = -5:5) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(
    x = "Years relative to acquisition",
    y = "Inventors with a patent",
    title = "A. Active patenting share"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", color = NA))

p2b <- ggplot(decomposition, aes(x = event_time, y = patents_per_active_inventor)) +
  geom_line(color = "#9c4f1c", linewidth = 0.9) +
  geom_point(color = "#9c4f1c", size = 2) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "grey40") +
  scale_x_continuous(breaks = -5:5) +
  labs(
    x = "Years relative to acquisition",
    y = "Patents per active inventor",
    title = "B. Output among active patentees"
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), plot.background = element_rect(fill = "white", color = NA))

save_two_panel(
  p2a,
  p2b,
  file.path(FIGURES, "figure2_full_cohort_decomposition.png")
)

# ── 4. Figure 3: Pre-deal selection and cumulative post-deal reach ─────────
section("Figure 3: pre-deal selection and cumulative post-deal reach")

predeal_selection <- DBI::dbGetQuery(con, "
WITH inventor_stock AS (
  SELECT
    codinv,
    deal_id,
    SUM(patent_count) AS predeal_patent_stock,
    MAX(CASE WHEN status_available THEN 1 ELSE 0 END) AS status_available,
    MAX(CASE WHEN type = 'T_Ever_Stayed' THEN 1 ELSE 0 END) AS ever_stayed
  FROM target_cohort_event_panel
  WHERE event_time BETWEEN -5 AND -1
  GROUP BY codinv, deal_id
), binned AS (
  SELECT
    *,
    CASE
      WHEN predeal_patent_stock = 1 THEN '1'
      WHEN predeal_patent_stock = 2 THEN '2'
      WHEN predeal_patent_stock >= 3 THEN '3+'
      ELSE '0'
    END AS predeal_patent_group
  FROM inventor_stock
)
SELECT
  predeal_patent_group,
  COUNT(*) AS n_target_inventors,
  SUM(status_available) AS n_status_eligible,
  SUM(ever_stayed) AS n_ever_stayed,
  SUM(ever_stayed) * 1.0 / NULLIF(SUM(status_available), 0) AS stayer_share
FROM binned
GROUP BY predeal_patent_group
ORDER BY CASE predeal_patent_group WHEN '0' THEN 0 WHEN '1' THEN 1 WHEN '2' THEN 2 ELSE 3 END
")

if (any(predeal_selection$predeal_patent_group == "0")) {
  stop("At least one target inventor has zero patents in the pre-deal window.")
}
if (sum(predeal_selection$n_target_inventors) != unique(decomposition$n_inventors)) {
  stop("Pre-deal patent groups do not exhaust the clean target cohort.")
}
write_csv_base(predeal_selection, "figure3_predeal_selection.csv")

cumulative_reach <- DBI::dbGetQuery(con, "
WITH units AS (
  SELECT DISTINCT
    p.codinv,
    p.deal_id,
    p.deal_year,
    s.first_acquirer_year,
    s.first_other_known_year
  FROM target_cohort_event_panel p
  LEFT JOIN inventor_status_own s
    ON p.codinv = s.codinv
   AND p.deal_id = s.deal_id
), event_grid AS (
  SELECT * FROM range(0, 6) AS t(event_time)
), unit_reach AS (
  SELECT
    g.event_time,
    u.codinv,
    u.deal_id,
    MAX(CASE
      WHEN p.event_time BETWEEN 0 AND g.event_time
       AND p.patent_count > 0 THEN 1 ELSE 0 END) AS any_post_patent,
    MAX(CASE
      WHEN u.first_acquirer_year <= u.deal_year + g.event_time THEN 1 ELSE 0 END) AS ever_acquirer,
    MAX(CASE
      WHEN u.first_other_known_year <= u.deal_year + g.event_time THEN 1 ELSE 0 END) AS ever_outside
  FROM units u
  CROSS JOIN event_grid g
  LEFT JOIN target_cohort_event_panel p
    ON u.codinv = p.codinv
   AND u.deal_id = p.deal_id
  GROUP BY g.event_time, u.codinv, u.deal_id
), reach_counts AS (
  SELECT
    event_time,
    COUNT(*) AS denominator,
    SUM(any_post_patent) AS n_any_post_patent,
    SUM(ever_acquirer) AS n_ever_acquirer,
    SUM(ever_outside) AS n_ever_outside
  FROM unit_reach
  GROUP BY event_time
)
SELECT
  event_time,
  'Any post-deal patent' AS reach_type,
  n_any_post_patent AS n_inventors,
  denominator,
  n_any_post_patent * 1.0 / denominator AS share
FROM reach_counts
UNION ALL
SELECT
  event_time,
  'Acquirer-affiliated patent' AS reach_type,
  n_ever_acquirer AS n_inventors,
  denominator,
  n_ever_acquirer * 1.0 / denominator AS share
FROM reach_counts
UNION ALL
SELECT
  event_time,
  'Outside-group patent' AS reach_type,
  n_ever_outside AS n_inventors,
  denominator,
  n_ever_outside * 1.0 / denominator AS share
FROM reach_counts
ORDER BY event_time, reach_type
")

if (length(unique(cumulative_reach$denominator)) != 1L) {
  stop("Cumulative reach does not use a fixed full-cohort denominator.")
}
reach_splits <- split(cumulative_reach, cumulative_reach$reach_type)
if (any(vapply(reach_splits, function(x) any(diff(x$share[order(x$event_time)]) < 0), logical(1)))) {
  stop("At least one cumulative reach series decreases over event time.")
}
write_csv_base(cumulative_reach, "figure3_cumulative_reach.csv")

predeal_selection$predeal_patent_group <- factor(
  predeal_selection$predeal_patent_group,
  levels = c("1", "2", "3+")
)
selection_axis_labels <- setNames(
  paste0(
    predeal_selection$predeal_patent_group,
    "\nN eligible = ",
    format(predeal_selection$n_status_eligible, big.mark = ",", scientific = FALSE)
  ),
  predeal_selection$predeal_patent_group
)

bar_palette <- c("1" = "#a8c9a1", "2" = "#5b9279", "3+" = "#173f31")

p3a <- ggplot(predeal_selection, aes(x = predeal_patent_group, y = stayer_share, fill = predeal_patent_group)) +
  geom_col(width = 0.64, show.legend = FALSE) +
  geom_text(
    aes(label = scales::percent(stayer_share, accuracy = 0.1)),
    vjust = -0.6, size = 3.4, fontface = "bold", color = "#173f31"
  ) +
  scale_fill_manual(values = bar_palette) +
  scale_y_continuous(
    labels = scales::percent_format(accuracy = 1),
    expand = expansion(mult = c(0, 0.16))
  ) +
  scale_x_discrete(labels = selection_axis_labels) +
  labs(
    x = "Pre-deal patents (years −5 to −1)",
    y = "Observed stayer share",
    title = "A. Staying rises sharply with pre-deal output",
    subtitle = "Stayer share among status-eligible target inventors, by pre-deal patent stock"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    plot.title = element_text(size = 11.5, face = "bold", color = "#173f31"),
    plot.subtitle = element_text(size = 8.6, color = "grey40"),
    plot.background = element_rect(fill = "white", color = NA)
  )

cumulative_reach$reach_type <- factor(
  cumulative_reach$reach_type,
  levels = c("Any post-deal patent", "Acquirer-affiliated patent", "Outside-group patent")
)
reach_colors <- c(
  "Any post-deal patent"       = "#536878",
  "Acquirer-affiliated patent" = "#2d6a4f",
  "Outside-group patent"       = "#c65d2e"
)
full_cohort_n  <- unique(decomposition$n_inventors)
last_point     <- cumulative_reach[cumulative_reach$event_time == 5, ]
never_reappear_share <- 1 - max(
  cumulative_reach$share[cumulative_reach$reach_type == "Any post-deal patent"]
)

status_comparison <- DBI::dbGetQuery(con, "
  SELECT
    'Thesis, clean window' AS source,
    SUM(CASE WHEN type = 'T_Ever_Stayed' THEN 1 ELSE 0 END) AS stayers,
    SUM(CASE WHEN type = 'T_LEAVER' THEN 1 ELSE 0 END) AS leavers
  FROM inventor_status_own
  WHERE deal_year BETWEEN 1993 AND 2010
")
status_comparison$stayer_share <- with(
  status_comparison,
  stayers / (stayers + leavers)
)
status_comparison <- rbind(
  status_comparison,
  data.frame(
    source = "Cassi-Ornaghi",
    stayers = 7104,
    leavers = 2675,
    stayer_share = 7104 / (7104 + 2675)
  )
)
write_csv_base(status_comparison, "figure3_status_comparison.csv")

format_count <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
thesis_status <- status_comparison[status_comparison$source == "Thesis, clean window", ]
cassi_status <- status_comparison[status_comparison$source == "Cassi-Ornaghi", ]
comparison_label <- paste0(
  "STAYER SHARE AMONG ACTIVE PATENTERS\n",
  sprintf(
    "Thesis clean: %s  (%s stay / %s leave)\n",
    scales::percent(thesis_status$stayer_share, accuracy = 0.1),
    format_count(thesis_status$stayers),
    format_count(thesis_status$leavers)
  ),
  sprintf(
    "Cassi-Ornaghi: %s  (%s stay / %s leave)",
    scales::percent(cassi_status$stayer_share, accuracy = 0.1),
    format_count(cassi_status$stayers),
    format_count(cassi_status$leavers)
  )
)

p3b <- ggplot(
    cumulative_reach,
    aes(x = event_time, y = share, color = reach_type)
  ) +
  geom_line(linewidth = 1.0) +
  geom_point(size = 2.0) +
  geom_text(
    data = last_point,
    aes(label = paste0(reach_type, "  ", scales::percent(share, accuracy = 0.1))),
    hjust = 0, nudge_x = 0.2, size = 2.95, fontface = "bold", show.legend = FALSE
  ) +
  annotate(
    "label",
    x = 0.15, y = max(cumulative_reach$share) * 0.97,
    label = paste0(
      scales::percent(never_reappear_share, accuracy = 0.1),
      " of the full cohort shows\nno post-deal patent at all\n(not shown above)"
    ),
    hjust = 0, vjust = 1, size = 2.85, color = "grey25",
    fill = "grey96", linewidth = 0.18
  ) +
  annotate(
    "label",
    x = 6.1, y = 0.11,
    label = comparison_label,
    hjust = 0, vjust = 0.5, size = 2.65,
    color = "#173f31", fill = "#edf4f1", linewidth = 0.24
  ) +
  scale_x_continuous(breaks = 0:5, limits = c(0, 12.2)) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = reach_colors) +
  labs(
    x = "Years relative to acquisition",
    y = paste0("Cumulative share of full target cohort (N = ", format(full_cohort_n, big.mark = ","), ")"),
    title = "B. Most of the cohort never reappears",
    subtitle = "Cumulative share with at least one patent observed, by affiliation"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "none",
    panel.grid.minor = element_blank(),
    plot.title = element_text(size = 11.5, face = "bold", color = "#173f31"),
    plot.subtitle = element_text(size = 8.6, color = "grey40"),
    plot.background = element_rect(fill = "white", color = NA),
    plot.margin = margin(5.5, 14, 5.5, 5.5)
  )

figure3_title <- cowplot::ggdraw() +
  cowplot::draw_label(
    "Pre-deal selection and the scale of post-deal disappearance",
    fontface = "bold", size = 13.5, x = 0.02, hjust = 0, colour = "#173f31"
  )

figure3_panels <- cowplot::plot_grid(p3a, p3b, ncol = 2, rel_widths = c(1, 1.22))

figure3_combined <- cowplot::plot_grid(
  figure3_title, figure3_panels,
  ncol = 1, rel_heights = c(0.09, 1)
)

cowplot::save_plot(
  file.path(FIGURES, "figure3_selection_and_attrition.png"),
  figure3_combined,
  base_width = 11.6, base_height = 5.15, dpi = 300, bg = "white"
)
message("Saved: ", file.path(FIGURES, "figure3_selection_and_attrition.png"))

message("\n", strrep("=", 60))
message("Figures and Table 1 complete.")
message("  Tables  : ", TABLES)
message("  Figures : ", FIGURES)
message(strrep("=", 60), "\n")
