# Build the appendix event-study figure for secondary outcomes among initially
# retained inventors. This script only writes the new figure and LaTeX wrapper.

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing package: ggplot2")
}

input_path <- file.path(
  "02_analysis", "output", "audit",
  "local_match_v2_1993_amendment", "P5B_STAYER_S6_SECONDARY_OUTCOMES",
  "s6_secondary_dynamic.csv"
)
output_dir <- file.path("output", "results_blueprint")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

thesis <- c(
  accent = "#9B1B30",
  accent_dark = "#671522",
  warm_grey = "#756A67",
  tint = "#F7F1F3",
  text = "#2F2A2B",
  grid = "#DAD3D1",
  white = "#FFFFFF"
)

d <- utils::read.csv(
  input_path, stringsAsFactors = FALSE, check.names = FALSE
)
d <- d[d$outcome %in% c(
  "pqii_scaled", "fwcit5w_cassi_total",
  "fwcit5w_cassi_per_patent", "tech_drift"
), , drop = FALSE]

panel_labels <- c(
  pqii_scaled = "A. PQII composite score",
  fwcit5w_cassi_total = "B. Five-year forward citations",
  fwcit5w_cassi_per_patent = "C. Forward citations per patent",
  tech_drift = "D. TechDrift"
)
d$panel <- factor(
  unname(panel_labels[d$outcome]),
  levels = unname(panel_labels)
)

theme_thesis <- function(base_size = 10) {
  ggplot2::theme_minimal(
    base_size = base_size,
    base_family = "Palatino Linotype"
  ) +
    ggplot2::theme(
      text = ggplot2::element_text(colour = thesis[["text"]]),
      axis.title = ggplot2::element_text(colour = thesis[["text"]]),
      axis.text = ggplot2::element_text(colour = thesis[["text"]]),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(
        colour = thesis[["grid"]], linewidth = 0.35
      ),
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(
        face = "bold", hjust = 0, colour = thesis[["text"]]
      ),
      panel.spacing = grid::unit(1.1, "lines"),
      plot.margin = ggplot2::margin(6, 8, 4, 6),
      legend.position = "none"
    )
}

p <- ggplot2::ggplot(d, ggplot2::aes(event_time, estimate)) +
  ggplot2::annotate(
    "rect", xmin = -0.5, xmax = 5.5, ymin = -Inf, ymax = Inf,
    fill = thesis[["tint"]], alpha = 0.72
  ) +
  ggplot2::geom_hline(
    yintercept = 0, colour = thesis[["warm_grey"]], linewidth = 0.45
  ) +
  ggplot2::geom_vline(
    xintercept = -0.5, colour = thesis[["warm_grey"]],
    linewidth = 0.45, linetype = "dashed"
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci_low, ymax = ci_high),
    width = 0.13, linewidth = 0.5, colour = thesis[["accent_dark"]]
  ) +
  ggplot2::geom_line(
    linewidth = 0.75, colour = thesis[["accent"]]
  ) +
  ggplot2::geom_point(
    data = d[d$event_time < 0, ],
    size = 2.05, shape = 21, stroke = 0.6,
    colour = thesis[["accent_dark"]], fill = thesis[["white"]]
  ) +
  ggplot2::geom_point(
    data = d[d$event_time == 0, ],
    size = 2.05, shape = 21, stroke = 0.6,
    colour = thesis[["warm_grey"]], fill = thesis[["white"]]
  ) +
  ggplot2::geom_point(
    data = d[d$event_time >= 1, ],
    size = 2.05, shape = 21, stroke = 0.6,
    colour = thesis[["accent_dark"]], fill = thesis[["accent"]]
  ) +
  ggplot2::facet_wrap(~panel, ncol = 2, scales = "free_y") +
  ggplot2::scale_x_continuous(
    breaks = -5:5, limits = c(-5.35, 5.35)
  ) +
  ggplot2::labs(
    x = "Years relative to acquisition",
    y = "Estimated acquisition effect"
  ) +
  theme_thesis(10)

stub <- file.path(output_dir, "figure_retained_secondary_event_studies")
ggplot2::ggsave(
  paste0(stub, ".png"), p, width = 7.2, height = 5.8,
  units = "in", dpi = 420, bg = "white"
)
ggplot2::ggsave(
  paste0(stub, ".pdf"), p, width = 7.2, height = 5.8,
  units = "in", device = grDevices::cairo_pdf, bg = "white"
)

latex <- c(
  "\\begin{figure}[!htbp]",
  "    \\centering",
  "    \\caption{Event-Study Estimates for Secondary Outcomes among Initially Retained Inventors}",
  "    \\label{fig:retained_secondary_event_studies}",
  "    \\includegraphics[width=\\textwidth]{figure_retained_secondary_event_studies.pdf}",
  "    \\begin{minipage}{0.96\\textwidth}",
  "        \\scriptsize \\textit{Notes:} Points show cohort-aggregated DiD estimates relative to event year $t=-1$; bars report 95\\% confidence intervals based on two-way clustering by acquisition and inventor. The shaded area marks the post-acquisition period. The retained sample is post-treatment selected.",
  "    \\end{minipage}",
  "\\end{figure}"
)
writeLines(
  latex,
  file.path(output_dir, "figure_retained_secondary_event_studies.tex")
)
