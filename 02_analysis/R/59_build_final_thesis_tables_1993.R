#!/usr/bin/env Rscript

# Render compact LaTeX tables from the certified 1993 release registry.

options(stringsAsFactors = FALSE, scipen = 999)
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
base <- file.path(
  root, "02_analysis", "output", "audit",
  "local_match_v2_1993_amendment", "FINAL_THESIS_RELEASE_1993")
table_dir <- file.path(base, "tables")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

read_csv <- function(name) {
  path <- file.path(base, name)
  if (!file.exists(path)) stop("Missing final-release input: ", path)
  utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}
fmt <- function(x, d = 3L) {
  ifelse(is.na(x), "--", formatC(x, digits = d, format = "f"))
}
pstars <- function(p) {
  ifelse(is.na(p), "", ifelse(p < 0.01, "***", ifelse(p < 0.05, "**",
    ifelse(p < 0.1, "*", ""))))
}
label <- function(x) {
  map <- c(
    patent_count = "Patent count",
    active_patenting = "Active patenting",
    pqii_scaled = "PQII (scaled)",
    fwd_cits5_scaled = "Forward citations (scaled)",
    tech_drift = "TechDrift")
  unname(ifelse(x %in% names(map), map[x], gsub("_", " ", x)))
}

registry <- read_csv("final_thesis_results_registry_1993.csv")
main <- registry[registry$section == "Main results", ]
main <- main[match(
  c("patent_count", "active_patenting", "pqii_scaled",
    "fwd_cits5_scaled", "tech_drift"), main$outcome), ]
main_lines <- vapply(seq_len(nrow(main)), function(i) sprintf(
  "%s & %s%s & [%s, %s] & %s \\\\",
  label(main$outcome[i]), fmt(main$estimate[i]), pstars(main$p_value[i]),
  fmt(main$ci_low[i]), fmt(main$ci_high[i]), fmt(main$p_value[i])), character(1))
writeLines(c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Acquisition effects for the 1993--2010 target-inventor cohorts}",
  "\\label{tab:main-results-1993}",
  "\\begin{tabular}{lrrr}", "\\toprule",
  "Outcome & ATT & 95\\% CI & $p$-value \\\\", "\\midrule",
  main_lines, "\\bottomrule", "\\end{tabular}",
  "\\begin{minipage}{0.94\\linewidth}\\footnotesize",
  "\\textit{Notes:} Average annual effects over event times $+1$ through $+5$.",
  "Intervals and $p$-values use the frozen 9,999-draw deal-cluster wild bootstrap.",
  "TechDrift rejects the joint pretreatment test and is reported as a qualified matched contrast, not a clean causal effect.",
  "\\end{minipage}", "\\end{table}"),
  file.path(table_dir, "table_main_results_1993.tex"), useBytes = TRUE)

short <- registry[
  registry$result == "Alternative post window, t=+1,...,+3", ]
timing <- registry[
  registry$result == "Treatment timing shifted three years early", ]
rob_rows <- rbind(
  transform(main[main$outcome %in% c("patent_count", "active_patenting"), ],
            specification = "Main: $+1$ to $+5$"),
  transform(short[short$outcome %in% c("patent_count", "active_patenting"), ],
            specification = "Short window: $+1$ to $+3$"),
  transform(timing[timing$outcome %in% c("patent_count", "active_patenting"), ],
            specification = "Three-year early placebo"))
rob_lines <- vapply(seq_len(nrow(rob_rows)), function(i) sprintf(
  "%s & %s & %s & [%s, %s] & %s \\\\",
  rob_rows$specification[i], label(rob_rows$outcome[i]),
  fmt(rob_rows$estimate[i]), fmt(rob_rows$ci_low[i]),
  fmt(rob_rows$ci_high[i]), fmt(rob_rows$p_value[i])), character(1))
writeLines(c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Window and treatment-timing robustness}",
  "\\label{tab:window-placebo-1993}",
  "\\begin{tabular}{llrrr}", "\\toprule",
  "Specification & Outcome & ATT & 95\\% CI & $p$-value \\\\", "\\midrule",
  rob_lines, "\\bottomrule", "\\end{tabular}",
  "\\begin{minipage}{0.94\\linewidth}\\footnotesize",
  "\\textit{Notes:} Deal-cluster wild-bootstrap inference. The valid early placebo uses true event times $-2$ and $-1$ as its pseudo-post period. A three-year late shift is not estimated because its pseudo-preperiod overlaps actual treatment.",
  "\\end{minipage}", "\\end{table}"),
  file.path(table_dir, "table_window_placebo_1993.tex"), useBytes = TRUE)

full <- read_csv("fullcohort_extensive_intensive_decomposition.csv")
retained <- read_csv("retained_extensive_intensive_decomposition.csv")
decomp <- rbind(
  transform(full, sample = "Full cohort"),
  transform(retained, sample = "Initially retained"))
decomp$component_label <- c(
  "Extensive: active patenting", "Intensive: patents per active year", "Total",
  "Extensive: active patenting", "Intensive: patents per active year", "Total")
decomp_lines <- vapply(seq_len(nrow(decomp)), function(i) sprintf(
  "%s & %s & %s & %s\\%% \\\\",
  decomp$sample[i], decomp$component_label[i], fmt(decomp$estimate[i]),
  fmt(100 * decomp$share_of_total[i], 1L)), character(1))
writeLines(c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Extensive- and intensive-margin accounting decomposition}",
  "\\label{tab:margin-decomposition-1993}",
  "\\begin{tabular}{llrr}", "\\toprule",
  "Sample & Component & Contribution & Share \\\\", "\\midrule",
  decomp_lines, "\\bottomrule", "\\end{tabular}",
  "\\begin{minipage}{0.94\\linewidth}\\footnotesize",
  "\\textit{Notes:} Exact order-invariant Shapley decompositions of the average annual patent-count contrast. The intensive component is descriptive because it conditions on post-treatment patenting activity.",
  "\\end{minipage}", "\\end{table}"),
  file.path(table_dir, "table_margin_decomposition_1993.tex"), useBytes = TRUE)

network <- registry[
  registry$section == "Team disruption" &
    !is.na(registry$outcome) &
    registry$outcome == "partner_focal_persistence_share", ]
network_event <- as.numeric(sub(".*t=", "", network$result))
network <- network[order(network_event), ]
network_lines <- vapply(seq_len(nrow(network)), function(i) sprintf(
  "%s & %s & [%s, %s] & %s \\\\",
  sub("Partner focal-organization persistence, ", "", network$result[i]),
  fmt(network$estimate[i]), fmt(network$ci_low[i]),
  fmt(network$ci_high[i]), fmt(network$p_value[i])), character(1))
writeLines(c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Held-out validation of the collaboration-network design}",
  "\\label{tab:network-validation-1993}",
  "\\begin{tabular}{lrrr}", "\\toprule",
  "Event time & Treated-control gap & 95\\% CI & $p$-value \\\\",
  "\\midrule", network_lines, "\\bottomrule", "\\end{tabular}",
  "\\begin{minipage}{0.94\\linewidth}\\footnotesize",
  "\\textit{Notes:} The outcome is the share of strict persistent baseline collaborators who remain patent-active in the focal organization while observable and at risk. The governing interval is the wider of deal-wild and two-way deal/inventor inference. The $t=-1$ gap and the precision gate select Path F, so no post-treatment network effect is estimated. No Holm-adjusted $p$-value is reported because the design has one governing outcome.",
  "\\end{minipage}", "\\end{table}"),
  file.path(table_dir, "table_network_validation_1993.tex"),
  useBytes = TRUE)

network_desc <- read_csv("../NETWORK_N4_DESCRIPTIVE/network_retained_descriptive_summary.csv")
network_desc <- network_desc[network_desc$metric %in% c(
  "any_post_collaboration", "post_collaborators",
  "any_legacy_recurrence", "legacy_recurrence_share",
  "legacy_focal_group_share", "legacy_outside_only_share",
  "legacy_no_post_patent_share", "legacy_share_post_team",
  "new_post_focal_group_share", "new_pre_target_group_share",
  "new_other_share"), ]
metric_labels <- c(
  any_post_collaboration = "Any post-acquisition collaboration",
  post_collaborators = "Number of post-acquisition collaborators",
  any_legacy_recurrence = "Any strict legacy collaborator reconnects",
  legacy_recurrence_share = "Share of strict legacy ties that recur",
  legacy_focal_group_share = "Legacy partner patents in focal/acquirer group",
  legacy_outside_only_share = "Legacy partner patents only outside group",
  legacy_no_post_patent_share = "Legacy partner does not patent",
  legacy_share_post_team = "Legacy share of post-acquisition team",
  new_post_focal_group_share = "New collaborators in focal/acquirer group",
  new_pre_target_group_share = "New collaborators in old target group",
  new_other_share = "Other new collaborators")
is_share <- network_desc$metric != "post_collaborators"
network_desc$display <- ifelse(
  is_share, paste0(fmt(100 * network_desc$estimate, 1L), "\\%"),
  fmt(network_desc$estimate, 1L))
network_desc$sample_label <- ifelse(
  network_desc$sample == "all_initially_retained",
  "All retained", "Strict legacy-tie subset")
network_desc_lines <- vapply(seq_len(nrow(network_desc)), function(i) sprintf(
  "%s & %s & %s & %d \\\\",
  network_desc$sample_label[i], metric_labels[network_desc$metric[i]],
  network_desc$display[i], network_desc$focal_inventors[i]), character(1))
writeLines(c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Descriptive collaboration-network continuity among initially retained inventors}",
  "\\label{tab:network-descriptive-1993}",
  "\\small", "\\begin{tabular}{p{0.18\\linewidth}p{0.44\\linewidth}rr}",
  "\\toprule",
  paste0("Sample & Metric & Weighted value & Inventors ", "\\\\"),
  "\\midrule", network_desc_lines, "\\bottomrule", "\\end{tabular}",
  "\\begin{minipage}{0.96\\linewidth}\\footnotesize",
  "\\textit{Notes:} Event times $+1$ through $+5$. A strict legacy tie requires at least two joint applications in at least two years during event times $-5$ through $-3$. Legacy-partner states are mutually exclusive: focal/acquirer group, outside only, or no post-window patent. New-collaborator states use the fixed priority focal/acquirer group, old target group, then other. These are selected-population descriptions, not causal acquisition effects. Table~\\ref{tab:network-validation-1993} reports the failed annual validation that prevents a causal network ATT.",
  "\\end{minipage}", "\\end{table}"),
  file.path(table_dir, "table_network_descriptive_1993.tex"),
  useBytes = TRUE)

message("Final 1993 LaTeX tables written to: ", table_dir)
