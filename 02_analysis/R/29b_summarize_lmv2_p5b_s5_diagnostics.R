# Thesis-facing figures for the certified P5b S5 diagnostics.

source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
cfg <- lmv2_p5b_s4_config()
source(file.path(cfg$p6_r_dir, "00_lmv2_visual_style.R"))
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing package: ggplot2")
}

in_dir <- file.path(
  cfg$base, "02_analysis", "output", "audit", "local_match_v2",
  "P5B_STAYER_S5_SELECTION_DECOMP")
out_dir <- file.path(in_dir, "reporting")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

decomp <- utils::read.csv(
  file.path(in_dir, "s5_extensive_intensive_decomposition.csv"),
  stringsAsFactors = FALSE)
decomp <- decomp[decomp$component %in%
                   c("total", "extensive", "intensive"), ]
decomp$label <- factor(
  c(total = "Total", extensive = "Extensive margin",
    intensive = "Intensive margin")[decomp$component],
  levels = c("Total", "Extensive margin", "Intensive margin"))

component <- setNames(decomp$estimate, decomp$component)
wf <- data.frame(
  x = 1:3,
  label = c("Extensive margin", "Intensive margin", "Total"),
  start = c(0, component[["extensive"]], 0),
  end = c(component[["extensive"]], component[["total"]],
          component[["total"]]),
  fill = c("Extensive margin", "Intensive margin", "Total"),
  text = c(
    sprintf("%.3f\n(%.1f%%)", component[["extensive"]],
            100 * decomp$share_of_total[decomp$component == "extensive"]),
    sprintf("%.3f\n(%.1f%%)", component[["intensive"]],
            100 * decomp$share_of_total[decomp$component == "intensive"]),
    sprintf("%.3f", component[["total"]])),
  stringsAsFactors = FALSE)
wf$ymin <- pmin(wf$start, wf$end)
wf$ymax <- pmax(wf$start, wf$end)
total_row <- decomp[decomp$component == "total", ]
connectors <- data.frame(
  x = c(1.32, 2.32), xend = c(1.68, 2.68),
  y = c(component[["extensive"]], component[["total"]]))

p_decomp <- ggplot2::ggplot() +
  ggplot2::geom_hline(
    yintercept = 0, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.45) +
  ggplot2::geom_rect(
    data = wf,
    ggplot2::aes(
      xmin = x - 0.32, xmax = x + 0.32,
      ymin = ymin, ymax = ymax, fill = fill)) +
  ggplot2::geom_segment(
    data = connectors,
    ggplot2::aes(x = x, xend = xend, y = y, yend = y),
    colour = LMV2_COLOURS["mid_grey"], linewidth = 0.5) +
  ggplot2::geom_errorbar(
    data = total_row,
    ggplot2::aes(x = 3, ymin = ci_low, ymax = ci_high),
    width = 0.14, colour = LMV2_COLOURS["forest"], linewidth = 0.8) +
  ggplot2::geom_text(
    data = wf,
    ggplot2::aes(x = x, y = (start + end) / 2, label = text),
    colour = LMV2_COLOURS["white"], fontface = "bold", size = 3.6) +
  ggplot2::scale_x_continuous(
    breaks = 1:3, labels = wf$label, expand = c(0.08, 0.08)) +
  ggplot2::scale_fill_manual(values = c(
    "Extensive margin" = unname(LMV2_COLOURS["slate_blue"]),
    "Intensive margin" = unname(LMV2_COLOURS["brick"]),
    "Total" = unname(LMV2_COLOURS["forest"]))) +
  ggplot2::labs(
    title = "The intensive margin accounts for 70% of the patent decline",
    subtitle = paste0(
      "Waterfall decomposition of the average annual patent-count contrast.\n",
      "The whisker shows the two-way 95% interval for the total."),
    x = NULL, y = "Patents per inventor-year",
    caption = paste0(
      "Extensive margin: change in the probability of patenting. ",
      "Intensive margin: change conditional on an active year.\n",
      "Percentages are shares of the total decline.")
  ) +
  lmv2_theme(base_size = 10.5, legend_position = "none")
lmv2_save_figure(
  p_decomp,
  file.path(out_dir, "figure_s5_margin_decomposition"),
  width = 7.4, height = 4.7)

t0 <- utils::read.csv(
  file.path(in_dir, "s5_t0_selection_diagnostic.csv"),
  stringsAsFactors = FALSE)
t0$status <- c(
  initially_retained = "Initially retained",
  leaver = "Leaver",
  no_post_patent = "No post-deal patent",
  not_status_eligible = "Status-ineligible",
  not_initially_retained = "Not initially retained"
)[t0$retention_status]
t0$arm_label <- ifelse(t0$arm == "treated", "Treated", "Control")
t0_table <- t0[
  order(match(t0$arm, c("treated", "control")),
        match(t0$retention_status, c(
          "initially_retained", "leaver", "no_post_patent",
          "not_initially_retained", "not_status_eligible"))),
  c(
    "arm_label", "status", "patent_count_m1", "patent_count_0",
    "patent_count_change", "active_patenting_m1_pp",
    "active_patenting_0_pp", "active_patenting_change_pp")]
names(t0_table) <- c(
  "Arm", "Subsequent status", "Patent count: t=-1",
  "Patent count: t=0", "Patent-count change",
  "Active patenting: t=-1 (%)", "Active patenting: t=0 (%)",
  "Active-patenting change (pp)")
utils::write.csv(
  t0_table,
  file.path(out_dir, "table_s5_t0_selection.csv"),
  row.names = FALSE)

fmt <- function(x, digits) formatC(x, format = "f", digits = digits)
tex_rows <- apply(t0_table, 1L, function(row) {
  paste(
    row[["Arm"]], row[["Subsequent status"]],
    fmt(as.numeric(row[["Patent count: t=-1"]]), 3),
    fmt(as.numeric(row[["Patent count: t=0"]]), 3),
    fmt(as.numeric(row[["Patent-count change"]]), 3),
    fmt(as.numeric(row[["Active patenting: t=-1 (%)"]]), 2),
    fmt(as.numeric(row[["Active patenting: t=0 (%)"]]), 2),
    fmt(as.numeric(row[["Active-patenting change (pp)"]]), 2),
    sep = " & ")
})
tex <- c(
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\caption{Acquisition-year patenting by subsequent retention status}",
  "\\label{tab:stayer_t0_selection}",
  "\\begin{tabular}{llrrrrrr}",
  "\\toprule",
  "Arm & Subsequent status & \\multicolumn{3}{c}{Patent count} & \\multicolumn{3}{c}{Active patenting (\\%)} \\\\",
  "\\cmidrule(lr){3-5}\\cmidrule(lr){6-8}",
  " & & $t=-1$ & $t=0$ & Change & $t=-1$ & $t=0$ & Change (pp) \\\\",
  "\\midrule",
  paste0(tex_rows, " \\\\"),
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{minipage}{0.96\\linewidth}\\footnotesize",
  "\\textit{Notes:} Initial retention is defined from the first observed patent in",
  "$t=+1,\\ldots,+5$. The table is a post-treatment selection diagnostic, not",
  "an estimate of a causal acquisition effect. Values use the frozen P5c weights",
  "and common cohort aggregation.",
  "\\end{minipage}",
  "\\end{table}")
writeLines(tex, file.path(out_dir, "table_s5_t0_selection.tex"))

message("S5 reporting figures and tables written to ", out_dir)
