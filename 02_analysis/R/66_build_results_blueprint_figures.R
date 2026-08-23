# Build thesis-styled figures and LaTeX tables for the 1993--2010 results
# section. Inputs are read from the certified amendment release.

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing package: ggplot2")
}

audit_root <- file.path(
  "02_analysis", "output", "audit",
  "local_match_v2_1993_amendment"
)
heterogeneity_root <- file.path(
  "02_analysis", "output", "results",
  "local_match_v2_1993_amendment", "results_section_exhibits"
)
output_dir <- file.path("output", "results_blueprint")
table_dir <- file.path(output_dir, "tables")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

THESIS <- c(
  accent = "#9B1B30",
  accent_dark = "#671522",
  warm_grey = "#756A67",
  tint = "#F7F1F3",
  text = "#2F2A2B",
  grid = "#DAD3D1",
  white = "#FFFFFF",
  rose = "#C98B98"
)

read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

save_figure <- function(plot, stub, width, height, dpi = 420) {
  ggplot2::ggsave(
    paste0(stub, ".png"), plot, width = width, height = height,
    units = "in", dpi = dpi, bg = "white"
  )
  ggplot2::ggsave(
    paste0(stub, ".pdf"), plot, width = width, height = height,
    units = "in", device = grDevices::cairo_pdf, bg = "white"
  )
}

theme_thesis <- function(base_size = 10) {
  ggplot2::theme_minimal(
    base_size = base_size,
    base_family = "Palatino Linotype"
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
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(
        face = "bold", hjust = 0, colour = THESIS[["text"]]
      ),
      plot.margin = ggplot2::margin(6, 8, 4, 6),
      legend.position = "none"
    )
}

event_study_plot <- function(data) {
  d <- data[data$outcome %in% c("patent_count", "active_patenting"), ]
  d$panel <- ifelse(
    d$outcome == "patent_count",
    "A. Change in annual patent count",
    "B. Change in active patenting (percentage points)"
  )
  multiplier <- ifelse(d$outcome == "active_patenting", 100, 1)
  d$estimate_display <- d$estimate * multiplier
  d$ci_low_display <- d$ci_low * multiplier
  d$ci_high_display <- d$ci_high * multiplier

  ggplot2::ggplot(d, ggplot2::aes(event_time, estimate_display)) +
    ggplot2::annotate(
      "rect", xmin = -0.5, xmax = 5.5, ymin = -Inf, ymax = Inf,
      fill = THESIS[["tint"]], alpha = 0.70
    ) +
    ggplot2::geom_hline(
      yintercept = 0, colour = THESIS[["warm_grey"]], linewidth = 0.40
    ) +
    ggplot2::geom_vline(
      xintercept = -0.5, colour = THESIS[["warm_grey"]],
      linewidth = 0.40, linetype = "dashed"
    ) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = ci_low_display, ymax = ci_high_display),
      width = 0.12, linewidth = 0.45, colour = THESIS[["accent_dark"]]
    ) +
    ggplot2::geom_line(
      linewidth = 0.70, colour = THESIS[["accent"]]
    ) +
    ggplot2::geom_point(
      shape = 21, size = 1.90, stroke = 0.55,
      colour = THESIS[["accent_dark"]],
      fill = ifelse(
        d$event_time >= 1, THESIS[["accent"]], THESIS[["white"]]
      )
    ) +
    ggplot2::facet_wrap(~panel, ncol = 2, scales = "free_y") +
    ggplot2::scale_x_continuous(
      breaks = -5:5
    ) +
    ggplot2::labs(
      x = "Years relative to acquisition",
      y = "Estimated acquisition effect"
    ) +
    theme_thesis(9) +
    ggplot2::theme(panel.spacing = grid::unit(1.0, "lines"))
}

full_dynamic <- read_csv(file.path(
  audit_root, "P6_ESTIMATION_PRIMARY", "p6_event_study_dynamic.csv"
))
save_figure(
  event_study_plot(full_dynamic),
  file.path(output_dir, "figure_full_cohort_event_study"),
  7.2, 3.15
)

retained_dynamic <- read_csv(file.path(
  audit_root, "P5B_STAYER_S4_RESULTS", "s4_event_study_dynamic.csv"
))
retained_dynamic <- retained_dynamic[
  retained_dynamic$spec == "primary_count_active_scale" &
    retained_dynamic$support_variant == "primary_resolved_t1", ,
  drop = FALSE
]
save_figure(
  event_study_plot(retained_dynamic),
  file.path(output_dir, "figure_retained_event_study"),
  7.2, 3.15
)

decomp <- read_csv(file.path(
  audit_root, "P8_EXIT_DECOMPOSITION", "exit_decomposition_components.csv"
))
decomp <- decomp[
  decomp$sample == "headline_1993_2010" & decomp$component != "total", ,
  drop = FALSE
]

stars <- function(p) {
  ifelse(p < 0.01, "***", ifelse(p < 0.05, "**", ifelse(p < 0.10, "*", "")))
}
fmt_p <- function(p) {
  ifelse(p < 0.001, "$<.001$", sub("^0", "", sprintf("%.3f", p)))
}
fmt_num <- function(x, digits = 3) sprintf(paste0("%.", digits, "f"), x)
fmt_est <- function(est, p, scale = 1, digits = 3) {
  marker <- stars(p)
  marker <- if (nzchar(marker)) {
    paste0("\\textsuperscript{", marker, "}")
  } else {
    ""
  }
  paste0(
    fmt_num(scale * est, digits),
    "\\makebox[1.15em][l]{", marker, "}"
  )
}
fmt_se <- function(se, scale = 1, digits = 3) {
  paste0("(", fmt_num(scale * se, digits), ")")
}
fmt_ci <- function(lo, hi, scale = 1, digits = 3) {
  paste0("[", fmt_num(scale * lo, digits), ", ",
         fmt_num(scale * hi, digits), "]")
}
fmt_pretrend <- function(p) {
  if (is.finite(p) && p < 0.10) {
    if (p < 0.001) {
      "\\textbf{\\textit{\\textless .001}}"
    } else {
      paste0("\\textbf{\\textit{", sub("^0", "", sprintf("%.3f", p)), "}}")
    }
  } else {
    fmt_p(p)
  }
}

write_table <- function(lines, name) {
  writeLines(lines, file.path(table_dir, name), useBytes = TRUE)
}

support_lines <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Common Support and Entropy-Balancing Diagnostics}",
  "    \\label{tab:results_support_balance}",
  "    \\begin{threeparttable}",
  "        \\small",
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{0.82\\textwidth}{@{\\extracolsep{\\fill}}lr@{}}",
  "            \\toprule",
  "            Diagnostic & Value \\\\",
  "            \\midrule",
  "            \\multicolumn{2}{@{}l}{\\itshape Sample coverage} \\\\",
  "            Eligible treated inventors & 29,694 \\\\",
  "            Supported treated inventors & 27,598 \\\\",
  "            Treated-inventor coverage & 92.94\\% \\\\",
  "            Supported acquisitions & 343 \\\\",
  "            Acquisition cohorts & 18 (every year, 1993--2010) \\\\",
  "            \\addlinespace[0.4em]",
  "            \\multicolumn{2}{@{}l}{\\itshape Prespecified balancing covariates and weights} \\\\",
  "            Maximum absolute SMD before weighting & 1.033 \\\\",
  "            Maximum absolute SMD after weighting & $8.61\\times10^{-8}$ \\\\",
  "            Median control ESS as share of unique controls & 39.0\\% \\\\",
  "            Largest control-weight share & 0.995\\% \\\\",
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} SMD denotes standardised mean ",
    "difference. ESS denotes effective sample size after repeated control rows ",
    "are aggregated to unique inventors within each cohort. Dexter/Invitrogen ",
    "(2000) and James Robinson/Vivimed Labs (2008) are excluded because no ",
    "treated inventor satisfies the donor-support rule."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_table(support_lines, "table_support_balance.tex")

full_head <- read_csv(file.path(
  audit_root, "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv"
))
full_head <- full_head[
  full_head$inference == "two_way_deal_inventor" &
    full_head$sample == "full_1993_2010" &
    full_head$summary == "average_annual_t1_to_t5", , drop = FALSE
]
full_diagnostic_head <- read_csv(file.path(
  audit_root, "P6_ESTIMATION_CITATIONS_PER_PATENT",
  "p6_headline_post_att.csv"
))
full_diagnostic_head <- full_diagnostic_head[
  full_diagnostic_head$inference == "two_way_deal_inventor" &
    full_diagnostic_head$sample == "full_1993_2010" &
    full_diagnostic_head$summary == "average_annual_t1_to_t5", ,
  drop = FALSE
]
full_head <- rbind(full_head, full_diagnostic_head)
full_pre <- read_csv(file.path(
  audit_root, "P6_ESTIMATION_PRIMARY", "p6_joint_pretrend_tests.csv"
))
full_diagnostic_pre <- read_csv(file.path(
  audit_root, "P6_ESTIMATION_CITATIONS_PER_PATENT",
  "p6_joint_pretrend_tests.csv"
))
full_pre <- rbind(full_pre, full_diagnostic_pre)
pre_map <- setNames(full_pre$p_value, full_pre$outcome)
full_order <- c(
  "patent_count", "active_patenting", "pqii_scaled",
  "fwd_cits5_scaled", "fwd_cits5_conditional_mean", "tech_drift"
)
full_labels <- c(
  patent_count = "Annual patent count",
  active_patenting = "Active patenting (pp)",
  pqii_scaled = "PQII composite score",
  fwd_cits5_scaled = "Five-year forward citations",
  fwd_cits5_conditional_mean = "Forward citations per patent",
  tech_drift = "TechDrift"
)
full_rows <- lapply(full_order, function(outcome) {
  z <- full_head[full_head$outcome == outcome, , drop = FALSE]
  scale <- if (outcome == "active_patenting") 100 else 1
  pt <- if (outcome %in% c("patent_count", "active_patenting")) {
    "Balanced"
  } else {
    fmt_pretrend(pre_map[[outcome]])
  }
  paste0(
    "            ", full_labels[[outcome]], " & ",
    fmt_est(z$estimate, z$p_value, scale), " & ",
    fmt_se(z$se, scale), " & ",
    fmt_ci(z$ci_low, z$ci_high, scale), " & ",
    fmt_p(z$p_value), " & ", pt, " \\\\"
  )
})
full_outcome_lines <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Acquisition Effects for the Full Target-Inventor Cohort}",
  "    \\label{tab:full_cohort_outcomes}",
  "    \\begin{threeparttable}",
  "        \\footnotesize",
  "        \\setlength{\\tabcolsep}{4.5pt}",
  "        \\begin{tabular*}{0.92\\textwidth}{@{\\extracolsep{\\fill}}lrrrrr@{}}",
  "            \\toprule",
  "            Outcome & Estimate & SE & 95\\% CI & $p$-value & \\shortstack{Pre-trend diagnostic\\\\($p$-value)} \\\\",
  "            \\midrule",
  unlist(full_rows),
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} Estimates average $t=+1$ to $+5$ ",
    "relative to $t=-1$; standard errors use two-way acquisition--inventor ",
    "clustering. Outcome coverage (treated/control) is 84.1/84.2\\% for PQII, ",
    "2.7/3.9\\% for TechDrift, and 96.4/94.8\\% for citations. Patent count and ",
    "active patenting are balanced before the deal. Failed diagnostics appear ",
    "in bold italics. $^{*}p<.10$, ",
    "$^{**}p<.05$, $^{***}p<.01$."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_table(full_outcome_lines, "table_full_cohort_outcomes.tex")

ret_primary <- read_csv(file.path(
  audit_root, "P5B_STAYER_S4_RESULTS", "reporting",
  "s4_two_way_primary_results.csv"
))
ret_primary <- ret_primary[
  ret_primary$spec == "primary_count_active_scale" &
    ret_primary$support_variant == "primary_resolved_t1" &
    ret_primary$summary == "average_annual_t1_to_t5", , drop = FALSE
]
ret_secondary <- read_csv(file.path(
  audit_root, "P5B_STAYER_S6_SECONDARY_OUTCOMES",
  "s6_secondary_headline.csv"
))
ret_secondary <- ret_secondary[
  ret_secondary$inference == "two_way_deal_inventor" &
    ret_secondary$summary == "average_annual_t1_to_t5", , drop = FALSE
]
ret_pre <- read_csv(file.path(
  audit_root, "P5B_STAYER_S6_SECONDARY_OUTCOMES",
  "s6_secondary_pretrend.csv"
))
ret_pre_map <- setNames(ret_pre$p_value, ret_pre$outcome)
ret_all <- rbind(
  ret_primary[, intersect(names(ret_primary), names(ret_secondary))],
  ret_secondary[, intersect(names(ret_primary), names(ret_secondary))]
)
ret_order <- c(
  "patent_count", "active_patenting", "pqii_scaled",
  "fwcit5w_cassi_total", "fwcit5w_cassi_per_patent", "tech_drift"
)
ret_labels <- c(
  patent_count = "Annual patent count",
  active_patenting = "Active patenting (pp)",
  pqii_scaled = "PQII composite score",
  fwcit5w_cassi_total = "Five-year forward citations",
  fwcit5w_cassi_per_patent = "Forward citations per patent",
  tech_drift = "TechDrift"
)
ret_rows <- lapply(ret_order, function(outcome) {
  z <- ret_all[ret_all$outcome == outcome, , drop = FALSE]
  scale <- if (outcome == "active_patenting") 100 else 1
  pt <- if (outcome %in% c("patent_count", "active_patenting")) {
    "Balanced"
  } else {
    fmt_pretrend(ret_pre_map[[outcome]])
  }
  paste0(
    "            ", ret_labels[[outcome]], " & ",
    fmt_est(z$estimate, z$p_value, scale), " & ",
    fmt_se(z$se, scale), " & ",
    fmt_ci(z$ci_low, z$ci_high, scale), " & ",
    fmt_p(z$p_value), " & ", pt, " \\\\"
  )
})
retained_outcome_lines <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Acquisition Effects among Initially Retained Inventors}",
  "    \\label{tab:retained_outcomes}",
  "    \\begin{threeparttable}",
  "        \\footnotesize",
  "        \\setlength{\\tabcolsep}{4.5pt}",
  "        \\begin{tabular*}{0.92\\textwidth}{@{\\extracolsep{\\fill}}lrrrrr@{}}",
  "            \\toprule",
  "            Outcome & Estimate & SE & 95\\% CI & $p$-value & \\shortstack{Pre-trend diagnostic\\\\($p$-value)} \\\\",
  "            \\midrule",
  unlist(ret_rows),
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} The retained sample is post-treatment ",
    "selected. Treated/control coverage is 82.9/81.8\\% for PQII, 39.2/39.3\\% ",
    "for TechDrift, and 97.2/95.7\\% for citations. Total citations fail the ",
    "pre-trend test; citations per patent condition on post-deal patenting. ",
    "Failed tests appear in bold italics. $^{*}p<.10$, $^{**}p<.05$, ",
    "$^{***}p<.01$."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_table(retained_outcome_lines, "table_retained_outcomes.tex")

het <- read_csv(file.path(
  heterogeneity_root, "heterogeneity_5x5_two_way_results.csv"
))
het_pre <- read_csv(file.path(
  heterogeneity_root, "heterogeneity_pretrend_tests.csv"
))
utils::write.csv(
  het,
  file.path(output_dir, "heterogeneity_5x5_two_way_results.csv"),
  row.names = FALSE
)
utils::write.csv(
  het_pre,
  file.path(output_dir, "heterogeneity_pretrend_tests.csv"),
  row.names = FALSE
)
moderator_labels <- c(
  predeal_productivity = "Pre-deal productivity (+1 SD)",
  team_persistence = "Persistent team",
  techfit = "TechFit (+1 SD)"
)
sample_labels <- c(
  full_target_inventor_cohort = "Full target-inventor cohort",
  initially_retained = "Initially retained inventors"
)
het_rows <- list()
for (sample in names(sample_labels)) {
  het_rows[[length(het_rows) + 1L]] <- paste0(
    "            \\multicolumn{9}{@{}l}{\\textit{",
    sample_labels[[sample]], "}} \\\\"
  )
  for (moderator in names(moderator_labels)) {
    p <- het[het$sample == sample & het$moderator == moderator &
               het$outcome == "patent_count", , drop = FALSE]
    a <- het[het$sample == sample & het$moderator == moderator &
               het$outcome == "active_patenting", , drop = FALSE]
    pp <- het_pre[het_pre$sample == sample &
                    het_pre$moderator == moderator &
                    het_pre$outcome == "patent_count", "p_value"]
    ap <- het_pre[het_pre$sample == sample &
                    het_pre$moderator == moderator &
                    het_pre$outcome == "active_patenting", "p_value"]
    het_rows[[length(het_rows) + 1L]] <- paste0(
      "            ", moderator_labels[[moderator]], " & ",
      fmt_est(p$estimate, p$two_way_p), " & ",
      fmt_se(p$two_way_se), " & ",
      fmt_ci(p$ci_low, p$ci_high), " & ", fmt_pretrend(pp), " & ",
      fmt_est(a$estimate, a$two_way_p, 100, 2), " & ",
      fmt_se(a$two_way_se, 100, 2), " & ",
      fmt_ci(a$ci_low, a$ci_high, 100, 2), " & ", fmt_pretrend(ap),
      " \\\\"
    )
  }
  if (sample == "full_target_inventor_cohort") {
    het_rows[[length(het_rows) + 1L]] <- "            \\addlinespace[0.45em]"
  }
}
heterogeneity_lines <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Heterogeneous Five-Year Acquisition Effects}",
  "    \\label{tab:heterogeneity_results}",
  "    \\begin{threeparttable}",
  "        \\scriptsize",
  "        \\setlength{\\tabcolsep}{2.4pt}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrrrrrr@{}}",
  "            \\toprule",
  "            & \\multicolumn{4}{c}{Annual patent count} & \\multicolumn{4}{c}{Active patenting (pp)} \\\\",
  "            \\cmidrule(lr){2-5} \\cmidrule(lr){6-9}",
  "            Moderator & Estimate & SE & 95\\% CI & \\shortstack{Pre-trend\\\\diagnostic ($p$)} & Estimate & SE & 95\\% CI & \\shortstack{Pre-trend\\\\diagnostic ($p$)} \\\\",
  "            \\midrule",
  unlist(het_rows),
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} Outcomes are five-post minus five-pre ",
    "annual averages. Continuous moderators are standardised; persistent team ",
    "compares mean positive collaboration intensity with none. Pre-trend tests ",
    "cover $t=-5,\\ldots,-2$ relative to $t=-1$; failed tests appear in bold ",
    "italics. Standard errors use two-way acquisition--inventor clustering. ",
    "$^{*}p<.10$, ",
    "$^{**}p<.05$, $^{***}p<.01$."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_table(heterogeneity_lines, "table_heterogeneity_results.tex")

relative <- read_csv(file.path(
  audit_root, "P7_RELATIVE_STANDING", "nested_5x5",
  "relative_standing_5x5_results.csv"
))
relative <- relative[relative$preferred & relative$report_in_main, ]
relative_rows <- list()
for (sample in c("full_cohort", "initially_retained")) {
  label <- if (sample == "full_cohort") {
    "Full target-inventor cohort"
  } else {
    "Initially retained inventors"
  }
  relative_rows[[length(relative_rows) + 1L]] <- paste0(
    "            \\multicolumn{9}{@{}l}{\\textit{", label, "}} \\\\"
  )
  predictions <- if (sample == "full_cohort") {
    c("star_vulnerability", "standing_loss_among_stars")
  } else {
    "star_vulnerability"
  }
  for (prediction in predictions) {
    p <- relative[relative$sample == sample &
                    relative$prediction == prediction &
                    relative$outcome == "patent_count", ]
    a <- relative[relative$sample == sample &
                    relative$prediction == prediction &
                    relative$outcome == "active_patenting", ]
    row_label <- if (prediction == "star_vulnerability") {
      "Stars vs. other target inventors"
    } else {
      "Standing loss among stars (+10 pp)"
    }
    relative_rows[[length(relative_rows) + 1L]] <- paste0(
      "            ", row_label, " & ",
      fmt_est(p$estimate, p$two_way_p), " & ",
      fmt_se(p$two_way_se), " & ",
      fmt_ci(p$ci_low, p$ci_high), " & ", fmt_p(p$two_way_p), " & ",
      fmt_est(a$estimate, a$two_way_p, 100, 2), " & ",
      fmt_se(a$two_way_se, 100, 2), " & ",
      fmt_ci(a$ci_low, a$ci_high, 100, 2), " & ",
      fmt_p(a$two_way_p), " \\\\"
    )
  }
  if (sample == "full_cohort") {
    relative_rows[[length(relative_rows) + 1L]] <- "            \\addlinespace[0.45em]"
  }
}
relative_lines <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Relative Standing and Acquisition Effects}",
  "    \\label{tab:relative_standing_results}",
  "    \\begin{threeparttable}",
  "        \\scriptsize",
  "        \\setlength{\\tabcolsep}{2.4pt}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrrrrrr@{}}",
  "            \\toprule",
  "            & \\multicolumn{4}{c}{Annual patent count} & \\multicolumn{4}{c}{Active patenting (pp)} \\\\",
  "            \\cmidrule(lr){2-5} \\cmidrule(lr){6-9}",
  "            Comparison & Estimate & SE & 95\\% CI & $p$-value & Estimate & SE & 95\\% CI & $p$-value \\\\",
  "            \\midrule",
  unlist(relative_rows),
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\scriptsize",
  paste0(
    "            \\item \\textit{Notes:} Stars are inventors at or above the ",
    "80th target-firm productivity percentile. The standing-loss gradient uses ",
    "separately rebalanced star samples. It is not reported for retained ",
    "inventors because the retained-star sample provides too little effective ",
    "support and statistical power. Retained estimates are descriptive. ",
    "$^{*}p<.10$, $^{**}p<.05$, $^{***}p<.01$."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_table(relative_lines, "table_relative_standing_results.tex")

decomposition_labels <- c(
  cessation = "Patent cessation",
  active_given_survival = "Reduced activity conditional on survival",
  patents_per_active_year = "Fewer patents per active year"
)
full_decomp <- decomp[decomp$population == "full_cohort", ]
retained_decomp <- decomp[
  decomp$population == "initially_retained_broad", ,
  drop = FALSE
]
decomposition_rows <- lapply(names(decomposition_labels), function(component) {
  f <- full_decomp[full_decomp$component == component, ]
  r <- retained_decomp[retained_decomp$component == component, ]
  paste0(
    "            ", decomposition_labels[[component]], " & ",
    fmt_num(f$estimate), " & ", fmt_num(100 * f$share_of_total, 1), "\\% & ",
    fmt_num(r$estimate), " & ", fmt_num(100 * r$share_of_total, 1), "\\% \\\\"
  )
})
decomposition_rows <- c(
  decomposition_rows,
  "            \\addlinespace[0.25em]",
  paste0(
    "            Total & ", fmt_num(sum(full_decomp$estimate)),
    " & 100.0\\% & ", fmt_num(sum(retained_decomp$estimate)),
    " & 100.0\\% \\\\"
  )
)
decomposition_lines <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Decomposition of the Annual Patent-Count Effect}",
  "    \\label{tab:margin_decomposition}",
  "    \\begin{threeparttable}",
  "        \\small",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrr@{}}",
  "            \\toprule",
  "            & \\multicolumn{2}{c}{Full cohort} & \\multicolumn{2}{c}{Initially retained} \\\\",
  "            \\cmidrule(lr){2-3} \\cmidrule(lr){4-5}",
  "            Component & Contribution & Share & Contribution & Share \\\\",
  "            \\midrule",
  unlist(decomposition_rows),
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\footnotesize",
  paste0(
    "            \\item \\textit{Notes:} Contributions sum to the annual ",
    "patent-count estimate in each sample. Patent cessation refers to the final ",
    "observed patent year and is not equivalent to leaving the firm. The ",
    "initially retained sample is selected after acquisition."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
write_table(decomposition_lines, "table_margin_decomposition.tex")

decomp_export <- decomp[, c(
  "population", "component", "estimate", "share_of_total"
)]
utils::write.csv(
  decomp_export,
  file.path(output_dir, "margin_decomposition_source.csv"),
  row.names = FALSE
)

message("Wrote thesis-ready results exhibits to: ", normalizePath(output_dir))
