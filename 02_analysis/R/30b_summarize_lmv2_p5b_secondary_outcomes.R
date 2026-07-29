# Build thesis-facing tables and figures for the certified S6 secondary
# outcomes. Reporting uses the predeclared two-way deal/inventor inference.

source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
cfg <- lmv2_p5b_s4_config()
source(file.path(cfg$p6_r_dir, "00_lmv2_visual_style.R"))
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing package: ggplot2")
}

audit_root <- file.path(
  cfg$base, "02_analysis", "output", "audit", "local_match_v2")
s4_dir <- file.path(audit_root, "P5B_STAYER_S4_RESULTS")
s6_dir <- file.path(audit_root, "P5B_STAYER_S6_SECONDARY_OUTCOMES")
out_dir <- file.path(s6_dir, "reporting")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

s4 <- utils::read.csv(
  file.path(s4_dir, "s4_headline_post_att.csv"),
  stringsAsFactors = FALSE)
s6 <- utils::read.csv(
  file.path(s6_dir, "s6_secondary_headline.csv"),
  stringsAsFactors = FALSE)
pretrend <- utils::read.csv(
  file.path(s6_dir, "s6_secondary_pretrend.csv"),
  stringsAsFactors = FALSE)
dynamic <- utils::read.csv(
  file.path(s6_dir, "s6_secondary_dynamic.csv"),
  stringsAsFactors = FALSE)

primary <- s4[
  s4$spec == "primary_count_active_scale" &
    s4$sample == "full_1994_2010" &
    s4$summary == "average_annual_t1_to_t5" &
    s4$inference == "two_way_deal_inventor",
  ]
secondary <- s6[
  s6$sample == "full_1994_2010" &
    s6$summary == "average_annual_t1_to_t5" &
    s6$inference == "two_way_deal_inventor",
  ]
keep_secondary <- c(
  "tech_drift", "pqii_scaled", "fwcit5w_cassi_total",
  "fwcit5w_cassi_per_patent")
secondary <- secondary[
  match(keep_secondary, secondary$outcome, nomatch = 0L), ]
results <- rbind(
  primary[, names(secondary), drop = FALSE],
  secondary)

labels <- c(
  patent_count = "Patent count",
  active_patenting = "Probability of patenting",
  tech_drift = "Technology drift",
  pqii_scaled = "OECD PQII total",
  fwcit5w_cassi_total = "Five-year forward citations",
  fwcit5w_cassi_per_patent = "Forward citations per patent")
scales <- c(
  patent_count = 1,
  active_patenting = 100,
  tech_drift = 1,
  pqii_scaled = 1,
  fwcit5w_cassi_total = 1,
  fwcit5w_cassi_per_patent = 1)
units <- c(
  patent_count = "patents per inventor-year",
  active_patenting = "percentage points",
  tech_drift = "cosine-distance units",
  pqii_scaled = "PQII units per inventor-year",
  fwcit5w_cassi_total = "citations per inventor-year",
  fwcit5w_cassi_per_patent = "citations per active patent")

results$outcome_label <- unname(labels[results$outcome])
results$scale <- unname(scales[results$outcome])
results$unit <- unname(units[results$outcome])
results$estimate_report <- results$estimate * results$scale
results$ci_low_report <- results$ci_low * results$scale
results$ci_high_report <- results$ci_high * results$scale
results$joint_pretrend_p <- NA_real_
idx <- match(results$outcome, pretrend$outcome)
results$joint_pretrend_p[!is.na(idx)] <- pretrend$p_value[idx[!is.na(idx)]]

report_table <- results[, c(
  "outcome", "outcome_label", "unit", "estimate_report",
  "ci_low_report", "ci_high_report", "p_value",
  "joint_pretrend_p", "nominal_treated_deals",
  "effective_treated_deals")]
utils::write.csv(
  report_table,
  file.path(out_dir, "table_s6_stayer_outcomes.csv"),
  row.names = FALSE, na = "")

fmt <- function(x, digits = 3L) {
  ifelse(is.na(x), "--", formatC(x, format = "f", digits = digits))
}
fmt_p <- function(x) {
  ifelse(is.na(x), "--",
         ifelse(x < 0.001, "$<0.001$", formatC(x, format = "f", digits = 3L)))
}
tex_rows <- vapply(seq_len(nrow(report_table)), function(i) {
  r <- report_table[i, ]
  paste(
    r$outcome_label,
    fmt(r$estimate_report),
    paste0("[", fmt(r$ci_low_report), ", ", fmt(r$ci_high_report), "]"),
    fmt_p(r$p_value),
    fmt_p(r$joint_pretrend_p),
    sep = " & ")
}, character(1))
tex <- c(
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\caption{Outcomes for initially retained inventors}",
  "\\label{tab:stayer_outcomes}",
  "\\begin{tabular}{lrrrr}",
  "\\toprule",
  "Outcome & Estimate & 95\\% CI & $p$-value & Pretrend $p$ \\\\",
  "\\midrule",
  paste0(tex_rows, " \\\\"),
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{minipage}{0.94\\linewidth}\\footnotesize",
  "\\textit{Notes:} Estimates average event times $t=+1,\\ldots,+5$ under",
  "the frozen initially retained-inventor weights. Confidence intervals and",
  "$p$-values use two-way deal/inventor clustering. The patenting-probability",
  "estimate is reported in percentage points. PQII is linkage-scaled.",
  "Cassi--Ornaghi forward citations replace the OECD citation outcome.",
  "Pretrend tests are diagnostic because the stayer design balances patent",
  "counts and active patenting, not the secondary outcomes.",
  "\\end{minipage}",
  "\\end{table}")
writeLines(tex, file.path(out_dir, "table_s6_stayer_outcomes.tex"))

forest <- report_table[
  report_table$outcome %in% keep_secondary, ]
p_forest <- ggplot2::ggplot(
  forest,
  ggplot2::aes(
    x = estimate_report, y = 1,
    xmin = ci_low_report, xmax = ci_high_report)) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.5) +
  ggplot2::geom_errorbar(
    width = 0.10, colour = LMV2_COLOURS["slate_blue"],
    linewidth = 0.7, orientation = "y") +
  ggplot2::geom_point(
    colour = LMV2_COLOURS["forest"], size = 2.5) +
  ggplot2::facet_wrap(~outcome_label, scales = "free_x", ncol = 2) +
  ggplot2::scale_y_continuous(NULL, breaks = NULL) +
  ggplot2::labs(
    title = "Secondary outcomes for initially retained inventors",
    subtitle = "Average annual contrasts in t = +1,...,+5; two-way 95% intervals",
    x = "Treated minus matched retained controls",
    caption = paste0(
      "Each panel uses its outcome's natural units. Citation estimates use ",
      "the original Cassi--Ornaghi five-year forward-citation field.")) +
  lmv2_theme(base_size = 10.2, legend_position = "none")
lmv2_save_figure(
  p_forest,
  file.path(out_dir, "figure_s6_secondary_forest"),
  width = 7.4, height = 5.1)

plot_outcomes <- c(
  "tech_drift", "pqii_scaled", "fwcit5w_cassi_total",
  "fwcit5w_cassi_per_patent")
dyn <- dynamic[
  dynamic$sample == "full_1994_2010" &
    dynamic$outcome %in% plot_outcomes, ]
dyn$outcome_label <- unname(labels[dyn$outcome])
dyn$outcome_label <- factor(
  dyn$outcome_label, levels = unname(labels[plot_outcomes]))
p_dynamic <- ggplot2::ggplot(
  dyn,
  ggplot2::aes(
    x = event_time, y = estimate,
    ymin = ci_low, ymax = ci_high)) +
  ggplot2::geom_hline(
    yintercept = 0, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.45) +
  ggplot2::geom_vline(
    xintercept = -0.5, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.45) +
  ggplot2::geom_ribbon(
    fill = LMV2_COLOURS["pale_blue"], alpha = 0.75,
    colour = NA) +
  ggplot2::geom_line(
    colour = LMV2_COLOURS["slate_blue"], linewidth = 0.7) +
  ggplot2::geom_point(
    colour = LMV2_COLOURS["forest"], size = 1.7) +
  ggplot2::facet_wrap(~outcome_label, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    title = "Dynamic secondary outcomes for initially retained inventors",
    subtitle = "Two-way deal/inventor-clustered 95% intervals",
    x = "Event time", y = "Treated minus matched retained controls",
    caption = paste0(
      "Secondary-outcome pretrends are not balanced by construction. ",
      "Interpret panels with rejected joint pretrend tests descriptively.")) +
  lmv2_theme(base_size = 9.5, legend_position = "none")
lmv2_save_figure(
  p_dynamic,
  file.path(out_dir, "figure_s6_secondary_event_studies"),
  width = 7.4, height = 6.0)

message("S6 reporting package written to ", out_dir)
