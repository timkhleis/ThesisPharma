# Build thesis-styled exhibits for the robustness section.
# The script reads only certified 1993--2010 robustness outputs.

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing package: ggplot2")
}

audit_root <- file.path(
  ".worktrees", "lmv2-1993-amendment", "02_analysis", "output", "audit",
  "local_match_v2_1993_amendment"
)
robust_root <- file.path(audit_root, "ROBUSTNESS_RELEASE_1993")
output_dir <- file.path("output", "robustness_exhibits")
overleaf_root <- file.path(
  "output", "overleaf", "Tim_4_fixed_project", "Thesis Template"
)
overleaf_figure_dir <- file.path(overleaf_root, "assets", "figures")
overleaf_table_dir <- file.path(overleaf_root, "assets", "tables")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(overleaf_figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(overleaf_table_dir, recursive = TRUE, showWarnings = FALSE)

THESIS <- c(
  accent = "#9B1B30",
  accent_dark = "#671522",
  warm_grey = "#756A67",
  tint = "#F7F1F3",
  text = "#2F2A2B",
  grid = "#E3DEDC",
  white = "#FFFFFF",
  rose = "#DAD3D1"
)

read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "--", sprintf(paste0("%.", digits, "f"), x))
}

fmt_p <- function(x) {
  ifelse(
    is.na(x), "--",
    ifelse(x < 0.001, "$<.001$", sub("^0", "", sprintf("%.3f", x)))
  )
}

stars <- function(p) {
  ifelse(
    is.na(p), "",
    ifelse(p < 0.01, "***", ifelse(p < 0.05, "**", ifelse(p < 0.10, "*", "")))
  )
}

fmt_est <- function(est, p, digits = 3) {
  marker <- stars(p)
  marker <- ifelse(
    nzchar(marker), paste0("\\textsuperscript{", marker, "}"), ""
  )
  paste0(fmt_num(est, digits), "\\makebox[1.15em][l]{", marker, "}")
}

fmt_se <- function(x, digits = 3) {
  ifelse(is.na(x), "--", paste0("(", fmt_num(x, digits), ")"))
}

fmt_ci <- function(lo, hi, digits = 3) {
  ifelse(
    is.na(lo) | is.na(hi), "--",
    paste0("[", fmt_num(lo, digits), ", ", fmt_num(hi, digits), "]")
  )
}

write_both <- function(lines, filename) {
  writeLines(lines, file.path(output_dir, filename), useBytes = TRUE)
  writeLines(lines, file.path(overleaf_table_dir, filename), useBytes = TRUE)
}

select_row <- function(data, ...) {
  conditions <- list(...)
  keep <- rep(TRUE, nrow(data))
  for (nm in names(conditions)) {
    keep <- keep & data[[nm]] == conditions[[nm]]
  }
  data[keep, , drop = FALSE][1, , drop = FALSE]
}

# -----------------------------------------------------------------------------
# Figure: untreated-firm placebo distributions
# -----------------------------------------------------------------------------

build_placebo_panel <- function(placebo_dir, panel_title, bin_width) {
  placebo <- read_csv(file.path(
    placebo_dir, "simple_control_placebo_draws.csv"
  ))
  placebo_summary <- read_csv(file.path(
    placebo_dir, "simple_control_placebo_summary.csv"
  ))
  actual_att <- placebo_summary$certified_reference_att[1]
  breaks <- seq(
    floor(min(placebo$estimate) / bin_width) * bin_width,
    ceiling(max(placebo$estimate) / bin_width) * bin_width,
    by = bin_width
  )
  histogram <- hist(placebo$estimate, breaks = breaks, plot = FALSE)
  hist_data <- data.frame(
    xmin = head(histogram$breaks, -1),
    xmax = tail(histogram$breaks, -1),
    share = 100 * histogram$counts / sum(histogram$counts)
  )
  grey_data <- hist_data[hist_data$xmax > actual_att, , drop = FALSE]
  grey_data$xmin <- pmax(grey_data$xmin, actual_att)
  tail_data <- hist_data[hist_data$xmin < actual_att, , drop = FALSE]
  tail_data$xmax <- pmin(tail_data$xmax, actual_att)
  tail_share <- 100 * placebo_summary$descriptive_left_tail_probability[1]
  tail_left <- min(hist_data$xmin)
  bracket_y <- max(hist_data$share) * 0.13
  bracket_tick <- max(hist_data$share) * 0.012

  ggplot2::ggplot() +
    ggplot2::geom_rect(
      data = grey_data,
      ggplot2::aes(xmin = xmin, xmax = xmax, ymin = 0, ymax = share),
      fill = THESIS[["rose"]], colour = THESIS[["white"]], linewidth = 0.25
    ) +
    ggplot2::geom_rect(
      data = tail_data,
      ggplot2::aes(xmin = xmin, xmax = xmax, ymin = 0, ymax = share),
      fill = THESIS[["accent"]], colour = THESIS[["white"]], linewidth = 0.25
    ) +
    ggplot2::geom_vline(
      xintercept = 0, colour = THESIS[["warm_grey"]],
      linewidth = 0.50, linetype = "dashed"
    ) +
    ggplot2::geom_vline(
      xintercept = actual_att, colour = THESIS[["accent_dark"]],
      linewidth = 0.75
    ) +
    ggplot2::annotate(
      "segment", x = tail_left, xend = actual_att,
      y = bracket_y, yend = bracket_y,
      colour = THESIS[["accent_dark"]], linewidth = 0.28, alpha = 0.62
    ) +
    ggplot2::annotate(
      "segment", x = tail_left, xend = tail_left,
      y = bracket_y - bracket_tick, yend = bracket_y + bracket_tick,
      colour = THESIS[["accent_dark"]], linewidth = 0.28, alpha = 0.62
    ) +
    ggplot2::annotate(
      "segment", x = actual_att, xend = actual_att,
      y = bracket_y - bracket_tick, yend = bracket_y + bracket_tick,
      colour = THESIS[["accent_dark"]], linewidth = 0.28, alpha = 0.62
    ) +
    ggplot2::annotate(
      "text", x = (tail_left + actual_att) / 2,
      y = bracket_y + max(hist_data$share) * 0.035,
      label = sprintf("%.1f%%", tail_share),
      colour = THESIS[["accent_dark"]], size = 2.65, alpha = 0.85,
      family = "Palatino Linotype"
    ) +
    ggplot2::annotate(
      "text", x = actual_att + bin_width * 0.45,
      y = max(hist_data$share) * 0.91,
      label = sprintf("Actual ATT\n%.3f", actual_att),
      hjust = 0, vjust = 0.5, colour = THESIS[["accent_dark"]], size = 2.8,
      family = "Palatino Linotype", fontface = "bold", lineheight = 0.95
    ) +
    ggplot2::scale_x_continuous(
      labels = function(x) sprintf("%.2f", x),
      expand = ggplot2::expansion(mult = c(0.02, 0.03))
    ) +
    ggplot2::scale_y_continuous(
      labels = function(x) paste0(sprintf("%.0f", x), "%"),
      expand = ggplot2::expansion(mult = c(0, 0.08))
    ) +
    ggplot2::labs(
      title = panel_title,
      x = "Placebo ATT (annual patents per inventor)",
      y = "Share of placebo draws"
    ) +
    ggplot2::theme_minimal(
      base_size = 9.2, base_family = "Palatino Linotype"
    ) +
    ggplot2::theme(
      text = ggplot2::element_text(colour = THESIS[["text"]]),
      plot.title = ggplot2::element_text(
        face = "italic", size = 9.2, hjust = 0, margin = ggplot2::margin(b = 2)
      ),
      axis.title = ggplot2::element_text(colour = THESIS[["text"]]),
      axis.text = ggplot2::element_text(colour = THESIS[["text"]]),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(
        colour = THESIS[["grid"]], linewidth = 0.35
      ),
      plot.margin = ggplot2::margin(6, 9, 5, 6)
    )
}

placebo_full <- build_placebo_panel(
  file.path(robust_root, "SIMPLE_CONTROL_PLACEBO_2000DRAW_DYNAMIC"),
  NULL, 0.006
)

for (directory in c(output_dir, overleaf_figure_dir)) {
  ggplot2::ggsave(
    file.path(directory, "figure_placebo_distribution.pdf"),
    placebo_full, width = 7.2, height = 3.65,
    units = "in", device = grDevices::cairo_pdf, bg = "white"
  )
  ggplot2::ggsave(
    file.path(directory, "figure_placebo_distribution.png"),
    placebo_full, width = 7.2, height = 3.65,
    units = "in", dpi = 420, bg = "white"
  )
}

# -----------------------------------------------------------------------------
# Table 1: leave-one-year-out and timing checks
# -----------------------------------------------------------------------------

heldout <- read_csv(file.path(
  robust_root, "P6_PACKAGE1_LOYO_GRID", "package1_loyo_heldout_placebos.csv"
))
heldout <- heldout[, c(
  "design", "sample", "held_out_event_time", "estimate", "se", "df",
  "ci_low", "ci_high"
)]
m1_dynamic <- read_csv(file.path(
  robust_root, "P6_PACKAGE1_ESTIMATION_LOYO_M1",
  "p6_event_study_dynamic.csv"
))
m1_reference <- select_row(
  m1_dynamic,
  outcome = "patent_count",
  sample = "full_1993_2010",
  event_time = -4,
  inference = "two_way_deal_inventor"
)
heldout_m1 <- data.frame(
  design = "loyo_m1",
  sample = "full_1993_2010",
  held_out_event_time = -1L,
  estimate = -m1_reference$estimate,
  se = m1_reference$se,
  df = m1_reference$df,
  ci_low = -m1_reference$ci_high,
  ci_high = -m1_reference$ci_low
)
heldout <- rbind(heldout, heldout_m1)
heldout <- heldout[order(heldout$held_out_event_time), , drop = FALSE]
heldout$p_value <- 2 * stats::pt(
  -abs(heldout$estimate / heldout$se), df = heldout$df
)

loyo_rows <- lapply(5:1, function(year) {
  data <- read_csv(file.path(
    robust_root,
    paste0("P6_PACKAGE1_ESTIMATION_LOYO_M", year),
    "p6_headline_post_att.csv"
  ))
  row <- select_row(
    data,
    inference = "two_way_deal_inventor",
    outcome = "patent_count",
    summary = "average_annual_t1_to_t5"
  )
  row$omitted_year <- -year
  row
})
loyo <- do.call(rbind, loyo_rows)

retained_root <- file.path(robust_root, "RETAINED_INVENTORS")
retained_heldout <- read_csv(file.path(
  retained_root, "LOYO", "retained_loyo_heldout_core.csv"
))
retained_heldout <- retained_heldout[
  retained_heldout$outcome == "patent_count",
  c("held_out_event_time", "estimate", "se", "df", "ci_low", "ci_high", "p_value")
]
retained_heldout <- retained_heldout[
  order(retained_heldout$held_out_event_time), , drop = FALSE
]
retained_loyo <- read_csv(file.path(
  retained_root, "LOYO", "retained_loyo_headline_core.csv"
))
retained_loyo <- retained_loyo[
  retained_loyo$outcome == "patent_count", , drop = FALSE
]
retained_loyo$omitted_year <- retained_loyo$held_out_event_time
retained_loyo <- retained_loyo[
  order(retained_loyo$omitted_year), , drop = FALSE
]

format_loyo_rows <- function(data, year_column, prefix) {
  year <- data[[year_column]]
  paste0(
    "            ", prefix, "$t=g", year, "$",
    ifelse(year == -1, "$^{\\dagger}$", ""), " & ",
    fmt_est(data$estimate, data$p_value), " & ",
    fmt_se(data$se), " & ",
    fmt_ci(data$ci_low, data$ci_high), " & ",
    fmt_p(data$p_value), " \\\\"
  )
}

loyo_table <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Leave-One-Year-Out Parallel-Trend Diagnostics}",
  "    \\label{tab:robustness_loyo}",
  "    \\begin{threeparttable}",
  "        \\footnotesize",
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\setlength{\\tabcolsep}{5.0pt}",
  "        \\begin{tabular*}{0.88\\textwidth}{@{\\extracolsep{\\fill}}lrrrr@{}}",
  "            \\toprule",
  "            Check & Estimate & SE & 95\\% CI & $p$-value \\\\",
  "            \\midrule",
  "            \\addlinespace[0.35em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Full target-inventor cohort}} \\\\",
  "            \\addlinespace[0.20em]",
  "            \\multicolumn{5}{@{}l}{Held-out pre-acquisition gap (parallel-trends diagnostic)} \\\\",
  "            \\addlinespace[0.15em]",
  format_loyo_rows(heldout, "held_out_event_time", "Held out "),
  "            \\addlinespace[0.35em]",
  "            \\multicolumn{5}{@{}l}{Five-year ATT using the corresponding leave-one-year-out weights} \\\\",
  "            \\addlinespace[0.15em]",
  format_loyo_rows(loyo, "omitted_year", "Weights omit "),
  "            \\addlinespace[0.70em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Initially retained inventors}} \\\\",
  "            \\addlinespace[0.20em]",
  "            \\multicolumn{5}{@{}l}{Held-out pre-acquisition gap (parallel-trends diagnostic)} \\\\",
  "            \\addlinespace[0.15em]",
  format_loyo_rows(retained_heldout, "held_out_event_time", "Held out "),
  "            \\addlinespace[0.35em]",
  "            \\multicolumn{5}{@{}l}{Five-year ATT using the corresponding leave-one-year-out weights} \\\\",
  "            \\addlinespace[0.15em]",
  format_loyo_rows(retained_loyo, "omitted_year", "Weights omit "),
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} For each year, I omit that year's patent-count and active-patenting measures from ",
    "entropy balancing, recompute the weights, and report the change in the treated--control patent-count gap between the ",
    "reference and held-out years. Values close to zero indicate that the weights reproduce a pre-acquisition outcome not ",
    "used to fit them. The ATT rows use the same leave-one-year-out weights. $^{\\dagger}$~Because $t=g-1$ is normally the ",
    "reference period, its held-out gap is measured relative to $t=g-4$; the corresponding ATT retains $t=g-1$ as its ",
    "reference and is therefore a separate reference-period sensitivity. Standard errors use two-way acquisition--inventor ",
    "clustering. $^{*}p<.10$, $^{**}p<.05$, $^{***}p<.01$."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_both(loyo_table, "table_robustness_loyo.tex")

# -----------------------------------------------------------------------------
# Table 2: alternative specifications and influence checks
# -----------------------------------------------------------------------------

weight_results <- read_csv(file.path(
  robust_root, "WEIGHT_ROBUSTNESS_P5C", "weight_robustness_headline.csv"
))
transformed <- read_csv(file.path(
  robust_root, "TRANSFORMED_OUTCOMES_P5C", "transformed_outcome_headline.csv"
))
ppml <- read_csv(file.path(robust_root, "PPML_P5C", "ppml_post_effect.csv"))
verginer <- read_csv(file.path(
  robust_root, "P6_VERGINER_EARLY_RECRUITMENT_STRICT_FEASIBLE",
  "verginer_p6_headline.csv"
))
short_window <- read_csv(file.path(
  audit_root, "P6_SHORT_WINDOW_T1_T3", "short_window_headline.csv"
))
release <- read_csv(file.path(
  robust_root, "FINAL_RELEASE", "robustness_results_ordinary_p.csv"
))
quantile_dir <- file.path(
  robust_root, "DEAL_VALUE_QUANTILES", "ESTIMATION_V2"
)
quantile_att <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_att.csv"
))
quantile_counts <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_estimation_counts.csv"
))
quantile_omnibus <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_omnibus.csv"
))
quantile_extreme <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_extreme_contrasts.csv"
))
quantile_identity <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_pooled_identity.csv"
))
quantile_manifest <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_estimation_manifest.csv"
))
if (!isTRUE(quantile_manifest$all_certification_pass[1]) ||
    !isTRUE(quantile_manifest$pooled_contribution_identity_pass[1]) ||
    !all(quantile_identity$pass)) {
  stop("Deal-value quantile release did not pass certification")
}

quartile_rows <- merge(
  quantile_att[quantile_att$partition == "quartile", ],
  quantile_counts[quantile_counts$partition == "quartile", ],
  by = c("partition", "bin"), sort = FALSE
)
quartile_rows$bin_number <- as.integer(sub("Q", "", quartile_rows$bin))
quartile_rows <- quartile_rows[order(quartile_rows$bin_number), ]
quartile_labels <- c(
  "Q1: EUR 10.1--49.2 million",
  "Q2: EUR 49.6--248.6 million",
  "Q3: EUR 252.4 million--1.10 billion",
  "Q4: EUR 1.10--93.4 billion"
)
quartile_joint <- select_row(quantile_omnibus, partition = "quartile")

main <- select_row(
  weight_results,
  inference = "two_way_deal_inventor",
  outcome = "patent_count",
  summary = "average_annual_t1_to_t5",
  specification = "headline_all18"
)
fractional <- select_row(
  transformed,
  inference = "two_way_deal_inventor",
  outcome = "fractional_patent_count",
  summary = "average_annual_t1_to_t5"
)
log_count <- select_row(
  transformed,
  inference = "two_way_deal_inventor",
  outcome = "log1p_patent_count",
  summary = "average_annual_t1_to_t5"
)
window3 <- select_row(
  short_window,
  inference = "two_way_deal_inventor",
  outcome = "patent_count",
  summary = "average_annual_t1_to_t3"
)
verginer_strict <- select_row(
  verginer,
  inference = "two_way_deal_inventor",
  outcome = "patent_count",
  summary = "average_annual_t1_to_t5"
)
no_deal70 <- select_row(
  weight_results,
  inference = "two_way_deal_inventor",
  outcome = "patent_count",
  summary = "average_annual_t1_to_t5",
  specification = "no_deal70"
)
no_henkel <- select_row(
  weight_results,
  inference = "two_way_deal_inventor",
  outcome = "patent_count",
  summary = "average_annual_t1_to_t5",
  specification = "omit_henkel"
)

ppml_row <- data.frame(
  estimate = ppml$percent_effect[1],
  se = 100 * exp(ppml$coefficient_log_rate[1]) * ppml$se_log_rate[1],
  ci_low = ppml$ci_low_percent[1],
  ci_high = ppml$ci_high_percent[1],
  p_value = ppml$p_value[1]
)

alt_rows <- rbind(
  data.frame(label = "Main entropy-balancing specification", main[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(label = "Fractional patent-count outcome", fractional[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Fractional patents / inventor"),
  data.frame(label = "Poisson model (PPML): patent count", ppml_row,
             scale = "Patent-count change (\\%)")
)
alt_rows$percent_format <- c(FALSE, FALSE, TRUE)

sample_rows <- rbind(
  data.frame(label = "Shorter post-period: $t=g+1$ to $g+3$", window3[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(label = "Early-recruited established-inventor sample", verginer_strict[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / established inventor")
)
sample_rows$percent_format <- FALSE

influence_rows <- rbind(
  data.frame(label = "Remove largest deal", no_deal70[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(label = "Remove influential control firm", no_henkel[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(
    label = "Remove each acquisition in turn (weights fixed)",
    estimate = NA_real_, se = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
    p_value = NA_real_, scale = "ATT range: $-0.061$ to $-0.046$"
  )
)
influence_rows$percent_format <- FALSE

deal_size_rows <- data.frame(
  label = quartile_labels,
  estimate = quartile_rows$estimate,
  se = quartile_rows$two_way_se,
  ci_low = quartile_rows$ci_low,
  ci_high = quartile_rows$ci_high,
  p_value = quartile_rows$governing_p,
  scale = "Annual patents / inventor",
  percent_format = FALSE
)

format_spec_rows <- function(data) {
  output <- character(nrow(data))
  for (i in seq_len(nrow(data))) {
    if (is.na(data$estimate[i])) {
      output[i] <- paste0(
        "            ", data$label[i],
        " & \\multicolumn{4}{c}{\\textit{", data$scale[i], "}} \\\\"
      )
      next
    } else if (isTRUE(data$percent_format[i])) {
      marker <- stars(data$p_value[i])
      marker <- ifelse(
        nzchar(marker), paste0("\\textsuperscript{", marker, "}"), ""
      )
      estimate <- paste0(
        fmt_num(data$estimate[i], 1), "\\%",
        "\\makebox[1.15em][l]{", marker, "}"
      )
      ci <- paste0(
        "[", fmt_num(data$ci_low[i], 1), "\\%, ",
        fmt_num(data$ci_high[i], 1), "\\%]"
      )
    } else {
      estimate <- fmt_est(data$estimate[i], data$p_value[i])
      ci <- fmt_ci(data$ci_low[i], data$ci_high[i])
    }
    output[i] <- paste0(
      "            ", data$label[i], " & ", estimate, " & ",
      if (isTRUE(data$percent_format[i])) {
        paste0("(", fmt_num(data$se[i], 2), " p.p.)")
      } else {
        fmt_se(data$se[i])
      }, " & ", ci,
      " & ", fmt_p(data$p_value[i]), " \\\\"
    )
  }
  output
}

spec_table <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Robustness Checks and Deal-Size Heterogeneity}",
  "    \\label{tab:robustness_specifications}",
  "    \\begin{threeparttable}",
  "        \\scriptsize",
  "        \\renewcommand{\\arraystretch}{1.18}",
  "        \\setlength{\\tabcolsep}{5.0pt}",
  "        \\begin{tabularx}{0.92\\textwidth}{@{}>{\\raggedright\\arraybackslash}Xrrrr@{}}",
  "            \\toprule",
  "            Specification & Estimate & SE & 95\\% CI & $p$-value \\\\",
  "            \\midrule",
  "            \\addlinespace[0.30em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Alternative estimators and outcome definitions}} \\\\",
  "            \\addlinespace[0.15em]",
  format_spec_rows(alt_rows),
  "            \\addlinespace[0.70em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Alternative sample and post-acquisition window}} \\\\",
  "            \\addlinespace[0.15em]",
  format_spec_rows(sample_rows),
  "            \\addlinespace[0.70em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Influence checks}} \\\\",
  "            \\addlinespace[0.15em]",
  format_spec_rows(influence_rows),
  "            \\addlinespace[0.70em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Heterogeneous effects across deal sizes}} \\\\",
  "            \\addlinespace[0.15em]",
  format_spec_rows(deal_size_rows),
  paste0(
    "            Equality of all quartile ATTs & -- & -- & -- & ",
    fmt_p(quartile_joint$governing_p), " \\\\"
  ),
  "            \\bottomrule",
  "        \\end{tabularx}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} Unless stated otherwise, estimates are average changes in annual patents per inventor ",
    "over the indicated post-acquisition years relative to $t=g-1$. Standard errors use two-way acquisition--inventor clustering. ",
    "The fractional row uses fractional patent counts, while PPML reports the percentage change in patent counts; its standard error is transformed using the delta method. The established-inventor sample uses patents observed at $t=g-7$ or $t=g-6$ ",
    "and begins in 1995. The largest-deal check removes ",
    "SmithKline Beecham--Glaxo (2000). Henkel is removed because it is an influential donor for this deal despite specialising ",
    "in different IPC main groups; the refit achieves balance but falls below the prespecified effective-sample-size threshold. ",
    "The acquisition-deletion range removes each acquisition once while holding the weights fixed. Deal-size quartiles give each acquisition equal weight when defining the cutpoints and contain 85, 86, 86, and 86 acquisitions from Q1 to Q4. The corresponding treated-inventor counts are 1,157, 2,155, 2,740, and 21,546. Relative P5c weights remain frozen, with control mass renormalised within cohort-by-quartile cells. For these rows, the SE column reports the two-way acquisition--inventor clustered SE, while the confidence interval and $p$-value follow the wider-interval rule across that inference and the deal-level Webb wild bootstrap. The joint equality test yields $p=.509$; after Holm adjustment, Q2 and Q4 remain significant at the 5\\% level. ",
    "$^{*}p<.10$, $^{**}p<.05$, $^{***}p<.01$."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_both(spec_table, "table_robustness_specifications.tex")

# -----------------------------------------------------------------------------
# Appendix table: initially retained inventor robustness checks
# -----------------------------------------------------------------------------

retained_alt <- read_csv(file.path(
  retained_root, "retained_alternative_specifications_core.csv"
))
retained_baseline <- read_csv(file.path(
  retained_root, "retained_baseline_inference.csv"
))
retained_ppml <- read_csv(file.path(
  retained_root, "PPML", "ppml_post_effect.csv"
))
retained_lodo <- read_csv(file.path(
  retained_root, "retained_frozen_weight_lodo_summary.csv"
))

retained_main <- select_row(
  retained_baseline, inference = "two_way_deal_inventor"
)
retained_wild <- select_row(
  retained_baseline, inference = "deal_wild_bootstrap_t"
)
retained_fractional <- select_row(
  retained_alt, specification = "fractional_patent_count"
)
retained_window3 <- select_row(
  retained_alt, specification = "three_year_post_window"
)
retained_established <- select_row(
  retained_alt, specification = "established_inventors"
)
retained_same_cohorts <- select_row(
  retained_alt, specification = "headline_same_equal_deal_cohorts"
)
retained_equal_deal <- select_row(
  retained_alt, specification = "equal_deal"
)
retained_remove_largest <- select_row(
  retained_alt, specification = "remove_largest_deal_reweighted"
)
retained_route <- select_row(
  retained_alt, specification = "route_consistent_retention"
)
retained_unambiguous <- select_row(
  retained_alt, specification = "unambiguous_affiliation_only"
)
retained_t2 <- select_row(
  retained_alt, specification = "retention_classified_from_t2"
)

retained_ppml_row <- data.frame(
  estimate = retained_ppml$percent_effect[1],
  se = 100 * exp(retained_ppml$coefficient_log_rate[1]) *
    retained_ppml$se_log_rate[1],
  ci_low = retained_ppml$ci_low_percent[1],
  ci_high = retained_ppml$ci_high_percent[1],
  p_value = retained_ppml$p_value[1]
)

retained_outcome_rows <- rbind(
  data.frame(label = "Main retained-inventor ATT", retained_main[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(label = "Fractional patent-count outcome", retained_fractional[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Fractional patents / inventor"),
  data.frame(label = "Poisson model (PPML): patent count", retained_ppml_row,
             scale = "Patent-count change (\\%)"),
  data.frame(label = "Shorter post-period: $t=g+1$ to $g+3$", retained_window3[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(label = "Established-inventor sample", retained_established[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor")
)
retained_outcome_rows$percent_format <- c(FALSE, FALSE, TRUE, FALSE, FALSE)

retained_classification_rows <- rbind(
  data.frame(label = "Route-consistent retention", retained_route[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(label = "Unambiguous affiliation only", retained_unambiguous[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(label = "Retention classified from $t=g+2$", retained_t2[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor")
)
retained_classification_rows$percent_format <- FALSE

retained_influence_rows <- rbind(
  data.frame(label = "Remove largest retained deal", retained_remove_largest[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(
    label = "Remove each acquisition in turn (weights fixed)",
    estimate = NA_real_, se = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
    p_value = NA_real_,
    scale = sprintf(
      "ATT range: $%.3f$ to $%.3f$",
      retained_lodo$minimum_lodo[1], retained_lodo$maximum_lodo[1]
    )
  )
)
retained_influence_rows$percent_format <- FALSE

retained_aggregation_rows <- rbind(
  data.frame(label = "Inventor-weighted ATT on feasible cohorts", retained_same_cohorts[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor"),
  data.frame(label = "Equal acquisition weights on the same cohorts", retained_equal_deal[, c(
    "estimate", "se", "ci_low", "ci_high", "p_value"
  )], scale = "Annual patents / inventor")
)
retained_aggregation_rows$percent_format <- FALSE

retained_wild_marker <- stars(retained_wild$p_value[1])
retained_wild_marker <- ifelse(
  nzchar(retained_wild_marker),
  paste0("\\textsuperscript{", retained_wild_marker, "}"), ""
)
retained_wild_line <- paste0(
  "            Deal-level wild-bootstrap inference & ",
  fmt_num(retained_wild$estimate[1]), "\\makebox[1.15em][l]{",
  retained_wild_marker, "} & -- & ",
  fmt_ci(retained_wild$ci_low[1], retained_wild$ci_high[1]), " & ",
  fmt_p(retained_wild$p_value[1]), " \\\\"
)

retained_table <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Robustness Checks for Initially Retained Inventors}",
  "    \\label{tab:robustness_retained}",
  "    \\begin{threeparttable}",
  "        \\scriptsize",
  "        \\renewcommand{\\arraystretch}{1.16}",
  "        \\setlength{\\tabcolsep}{5.0pt}",
  "        \\begin{tabularx}{0.92\\textwidth}{@{}>{\\raggedright\\arraybackslash}Xrrrr@{}}",
  "            \\toprule",
  "            Specification & Estimate & SE & 95\\% CI & $p$-value \\\\",
  "            \\midrule",
  "            \\addlinespace[0.30em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Outcome, estimator, and window}} \\\\",
  "            \\addlinespace[0.15em]",
  format_spec_rows(retained_outcome_rows),
  "            \\addlinespace[0.65em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Alternative retained-inventor classifications}} \\\\",
  "            \\addlinespace[0.15em]",
  format_spec_rows(retained_classification_rows),
  "            \\addlinespace[0.65em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Influence and aggregation}} \\\\",
  "            \\addlinespace[0.15em]",
  format_spec_rows(retained_influence_rows),
  format_spec_rows(retained_aggregation_rows),
  "            \\addlinespace[0.65em]",
  "            \\multicolumn{5}{@{}l}{\\textit{Alternative inference for the main ATT}} \\\\",
  "            \\addlinespace[0.15em]",
  retained_wild_line,
  "            \\bottomrule",
  "        \\end{tabularx}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} Unless stated otherwise, estimates are average changes in annual patents per ",
    "initially retained inventor over $t=g+1,\\ldots,g+5$ relative to $t=g-1$, with two-way acquisition--inventor clustered ",
    "standard errors. PPML reports the percentage change in patent counts and its delta-method standard error in percentage ",
    "points. The established-inventor row is based on 471 treated inventors from 49 acquisitions and should be interpreted ",
    "as a narrower-support comparison. The largest-deal check removes SmithKline Beecham--Glaxo (2000). The equal-weight ",
    "comparison uses the same 15 feasible cohorts in both rows; three cohorts fail the equal-deal balance gate. The final ",
    "row reports a 9,999-draw deal-level Webb wild-bootstrap confidence interval. ",
    "$^{*}p<.10$, $^{**}p<.05$, $^{***}p<.01$."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_both(retained_table, "table_robustness_retained.tex")

# -----------------------------------------------------------------------------
# Main-text compact table: common checks by analysis sample
# -----------------------------------------------------------------------------

format_compact_cell <- function(row, percent = FALSE) {
  marker <- stars(row$p_value[1])
  marker <- ifelse(
    nzchar(marker), paste0("\\textsuperscript{", marker, "}"), ""
  )
  if (percent) {
    paste0(
      fmt_num(row$estimate[1], 1), "\\%", marker,
      "\\;{\\footnotesize(", fmt_num(row$se[1], 2), " p.p.)}"
    )
  } else {
    paste0(
      fmt_num(row$estimate[1], 3), marker,
      "\\;{\\footnotesize(", fmt_num(row$se[1], 3), ")}"
    )
  }
}

compact_rows <- data.frame(
  label = c(
    "Main specification",
    "Fractional patent-count outcome",
    "Poisson model (PPML): patent count",
    "Shorter post-period: $t=g+1$ to $g+3$",
    "Established-inventor sample",
    "Remove largest acquisition",
    "Remove each acquisition in turn"
  ),
  full = c(
    format_compact_cell(main),
    format_compact_cell(fractional),
    format_compact_cell(ppml_row, percent = TRUE),
    format_compact_cell(window3),
    format_compact_cell(verginer_strict),
    format_compact_cell(no_deal70),
    "\\textit{$-0.061$ to $-0.046$}"
  ),
  retained = c(
    format_compact_cell(retained_main),
    format_compact_cell(retained_fractional),
    format_compact_cell(retained_ppml_row, percent = TRUE),
    format_compact_cell(retained_window3),
    format_compact_cell(retained_established),
    format_compact_cell(retained_remove_largest),
    sprintf(
      "\\textit{$%.3f$ to $%.3f$}",
      retained_lodo$minimum_lodo[1], retained_lodo$maximum_lodo[1]
    )
  ),
  stringsAsFactors = FALSE
)

compact_table <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Core Robustness Checks across Analysis Samples}",
  "    \\label{tab:robustness_core_by_sample}",
  "    \\begin{threeparttable}",
  "        \\footnotesize",
  "        \\renewcommand{\\arraystretch}{1.16}",
  "        \\setlength{\\tabcolsep}{6.0pt}",
  "        \\begin{tabularx}{0.94\\textwidth}{@{}>{\\raggedright\\arraybackslash}Xcc@{}}",
  "            \\toprule",
  "            Specification & Full target-inventor cohort & Initially retained inventors \\\\",
  "            \\midrule",
  paste0(
    "            ", compact_rows$label, " & ",
    compact_rows$full, " & ", compact_rows$retained, " \\\\"
  ),
  "            \\bottomrule",
  "        \\end{tabularx}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} Cells report estimates with two-way acquisition--inventor clustered standard errors ",
    "in parentheses. Except for the fractional and PPML rows, estimates are changes in annual patents per inventor. PPML ",
    "reports percentage changes and delta-method standard errors in percentage points. The final row reports the range from ",
    "holding the weights fixed and removing each acquisition once. The established-inventor retained estimate is based on ",
    "471 treated inventors from 49 acquisitions and therefore has substantially narrower support. Complete confidence ",
    "intervals, classification sensitivities, and aggregation checks are reported in the appendix tables. ",
    "$^{*}p<.10$, $^{**}p<.05$, $^{***}p<.01$."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_both(compact_table, "table_robustness_core_by_sample.tex")

# -----------------------------------------------------------------------------
# Appendix: deal-value quantile profile
# -----------------------------------------------------------------------------

quantile_dir <- file.path(
  robust_root, "DEAL_VALUE_QUANTILES", "ESTIMATION_V2"
)
quantile_att <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_att.csv"
))
quantile_counts <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_estimation_counts.csv"
))
quantile_omnibus <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_omnibus.csv"
))
quantile_extreme <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_extreme_contrasts.csv"
))
quantile_identity <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_pooled_identity.csv"
))
quantile_manifest <- read_csv(file.path(
  quantile_dir, "deal_value_quantile_estimation_manifest.csv"
))
if (!isTRUE(quantile_manifest$all_certification_pass[1]) ||
    !isTRUE(quantile_manifest$pooled_contribution_identity_pass[1]) ||
    !all(quantile_identity$pass)) {
  stop("Deal-value quantile profile did not pass certification")
}

decile_plot_data <- merge(
  quantile_att[quantile_att$partition == "decile", ],
  quantile_counts[quantile_counts$partition == "decile", ],
  by = c("partition", "bin"), sort = FALSE
)
decile_plot_data$bin_number <- as.integer(sub("D", "", decile_plot_data$bin))
decile_plot_data <- decile_plot_data[order(decile_plot_data$bin_number), ]
decile_plot_data$count_label <- paste0("n=", decile_plot_data$acquisitions)

quantile_plot <- ggplot2::ggplot(
  decile_plot_data,
  ggplot2::aes(x = bin_number, y = estimate)
) +
  ggplot2::geom_hline(
    yintercept = 0, colour = THESIS[["warm_grey"]], linewidth = 0.45
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci_low, ymax = ci_high),
    width = 0.16, colour = THESIS[["accent_dark"]], linewidth = 0.48
  ) +
  ggplot2::geom_point(
    shape = 21, size = 2.65, stroke = 0.55,
    fill = THESIS[["accent"]], colour = THESIS[["accent_dark"]]
  ) +
  ggplot2::scale_x_continuous(
    breaks = 1:10, labels = paste0("D", 1:10),
    expand = ggplot2::expansion(mult = c(0.025, 0.025))
  ) +
  ggplot2::scale_y_continuous(
    labels = function(x) sprintf("%.2f", x),
    expand = ggplot2::expansion(mult = c(0.05, 0.08))
  ) +
  ggplot2::labs(
    x = "Target transaction-value decile (acquisition-weighted cutpoints)",
    y = "ATT: annual patents per inventor"
  ) +
  ggplot2::theme_minimal(
    base_size = 10, base_family = "Palatino Linotype"
  ) +
  ggplot2::theme(
    text = ggplot2::element_text(colour = THESIS[["text"]]),
    axis.title = ggplot2::element_text(colour = THESIS[["text"]]),
    axis.text = ggplot2::element_text(colour = THESIS[["text"]]),
    panel.grid.major.x = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_line(
      colour = THESIS[["grid"]], linewidth = 0.35
    ),
    plot.margin = ggplot2::margin(8, 12, 6, 8)
  )

for (directory in c(output_dir, overleaf_figure_dir)) {
  ggplot2::ggsave(
    file.path(directory, "figure_deal_value_decile_att.pdf"),
    quantile_plot, width = 7.2, height = 3.75,
    units = "in", device = grDevices::cairo_pdf, bg = "white"
  )
  ggplot2::ggsave(
    file.path(directory, "figure_deal_value_decile_att.png"),
    quantile_plot, width = 7.2, height = 3.75,
    units = "in", dpi = 420, bg = "white"
  )
}

quartile_rows <- merge(
  quantile_att[quantile_att$partition == "quartile", ],
  quantile_counts[quantile_counts$partition == "quartile", ],
  by = c("partition", "bin"), sort = FALSE
)
quartile_rows$bin_number <- as.integer(sub("Q", "", quartile_rows$bin))
quartile_rows <- quartile_rows[order(quartile_rows$bin_number), ]
quartile_labels <- c(
  "Q1: EUR 10.1--49.2 million",
  "Q2: EUR 49.6--248.6 million",
  "Q3: EUR 252.4 million--1.10 billion",
  "Q4: EUR 1.10--93.4 billion"
)
quartile_lines <- vapply(seq_len(nrow(quartile_rows)), function(i) {
  paste0(
    "            ", quartile_labels[i], " & ",
    fmt_est(quartile_rows$estimate[i], quartile_rows$governing_p[i]), " & ",
    fmt_ci(quartile_rows$ci_low[i], quartile_rows$ci_high[i]), " & ",
    fmt_p(quartile_rows$governing_p[i]), " & ",
    format(quartile_rows$acquisitions[i], big.mark = ","), " & ",
    format(quartile_rows$treated_inventors[i], big.mark = ","), " \\\\"
  )
}, character(1))
quartile_joint <- select_row(quantile_omnibus, partition = "quartile")
quartile_extreme_row <- select_row(quantile_extreme, partition = "quartile")

quantile_table <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Patent-Count Effects by Target Transaction-Value Quartile}",
  "    \\label{tab:deal_value_quartile_att}",
  "    \\begin{threeparttable}",
  "        \\scriptsize",
  "        \\renewcommand{\\arraystretch}{1.16}",
  "        \\setlength{\\tabcolsep}{4.2pt}",
  "        \\begin{tabularx}{0.96\\textwidth}{@{}>{\\raggedright\\arraybackslash}Xrrrrr@{}}",
  "            \\toprule",
  "            Target-value group & ATT & 95\\% CI & $p$-value & Deals & Inventors \\\\",
  "            \\midrule",
  quartile_lines,
  "            \\addlinespace[0.35em]",
  paste0(
    "            Q4 minus Q1 & ",
    fmt_num(quartile_extreme_row$estimate), " & ",
    fmt_ci(quartile_extreme_row$ci_low, quartile_extreme_row$ci_high), " & ",
    fmt_p(quartile_extreme_row$governing_p), " & -- & -- \\\\"
  ),
  paste0(
    "            Equality of all quartile ATTs & -- & -- & ",
    fmt_p(quartile_joint$governing_p), " & -- & -- \\\\"
  ),
  "            \\bottomrule",
  "        \\end{tabularx}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} Quartiles give each acquisition equal weight when defining cutpoints, then estimate inventor-level ATTs using the frozen P5c relative weights. Control mass is renormalised within cohort-by-quartile cells. Estimates compare average annual patent output in $t=1,\\ldots,5$ with $t=-1$. Confidence intervals and individual $p$-values follow the wider-interval rule across two-way acquisition--inventor clustering and a 9,999-draw deal-level Webb wild bootstrap. The equality test imposes three restrictions; its reported $p$-value is the larger of the two-way and wild-bootstrap values. Individual quartile tests use Holm correction as a family: Q2 and Q4 remain below .05, but the joint equality test does not reject. Target values are converted from thousands to EUR millions or billions for display."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_both(quantile_table, "table_deal_value_quartile_att.tex")

message("Robustness exhibits written to: ", normalizePath(output_dir))
