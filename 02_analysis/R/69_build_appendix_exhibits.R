# Build appendix exhibits from the certified 1993--2010 amendment release.
# Outputs are written to output/appendix_exhibits and do not overwrite the
# settled thesis chapters or their main-text exhibits.

source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()
for (pkg in c("ggplot2", "DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

audit_root <- file.path(
  "02_analysis", "output", "audit",
  "local_match_v2_1993_amendment"
)
results_root <- file.path(
  "02_analysis", "output", "results",
  "local_match_v2_1993_amendment"
)
out_root <- file.path("output", "appendix_exhibits")
table_dir <- file.path(out_root, "tables")
figure_dir <- file.path(out_root, "figures")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

THESIS <- c(
  accent = "#9B1B30", accent_dark = "#671522", warm_grey = "#756A67",
  tint = "#F7F1F3", text = "#2F2A2B", grid = "#DAD3D1",
  white = "#FFFFFF", rose = "#C98B98"
)

read_csv <- function(path) {
  if (!file.exists(path)) stop("Missing certified input: ", path)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

sql_path <- function(path) {
  gsub("'", "''", gsub("\\\\", "/", normalizePath(path, winslash = "/", mustWork = TRUE)))
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "--", sprintf(paste0("%.", digits, "f"), x))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "--", ifelse(x < .001, "$<.001$", sub("^0", "", sprintf("%.3f", x))))
}

stars <- function(p) {
  ifelse(is.na(p), "", ifelse(p < .01, "***", ifelse(p < .05, "**", ifelse(p < .10, "*", ""))))
}

fmt_est <- function(est, p, scale = 1, digits = 3) {
  marker <- stars(p)
  marker <- ifelse(nzchar(marker), paste0("\\textsuperscript{", marker, "}"), "")
  paste0(fmt_num(scale * est, digits), "\\makebox[1.1em][l]{", marker, "}")
}

fmt_ci <- function(lo, hi, scale = 1, digits = 3) {
  paste0("[", fmt_num(scale * lo, digits), ", ", fmt_num(scale * hi, digits), "]")
}

write_tex <- function(name, lines) {
  writeLines(lines, file.path(table_dir, name), useBytes = TRUE)
}

save_plot <- function(plot, name, width = 7.2, height = 3.7) {
  ggplot2::ggsave(
    file.path(figure_dir, paste0(name, ".pdf")), plot,
    width = width, height = height, units = "in",
    device = grDevices::cairo_pdf, bg = "white"
  )
  ggplot2::ggsave(
    file.path(figure_dir, paste0(name, ".png")), plot,
    width = width, height = height, units = "in", dpi = 420, bg = "white"
  )
}

theme_thesis <- function(base_size = 10) {
  ggplot2::theme_minimal(base_size = base_size, base_family = "Palatino Linotype") +
    ggplot2::theme(
      text = ggplot2::element_text(colour = THESIS[["text"]]),
      axis.text = ggplot2::element_text(colour = THESIS[["text"]]),
      axis.title = ggplot2::element_text(colour = THESIS[["text"]]),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(colour = THESIS[["grid"]], linewidth = .35),
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(face = "bold", hjust = 0),
      legend.position = "bottom",
      legend.title = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(6, 8, 5, 6)
    )
}

table_wrapper <- function(caption, label, body, notes, size = "\\small") {
  c(
    "\\begin{table}[!htbp]",
    "    \\centering",
    paste0("    \\caption{", caption, "}"),
    paste0("    \\label{", label, "}"),
    "    \\begin{threeparttable}",
    paste0("        ", size),
    body,
    "        \\begin{tablenotes}[flushleft]",
    "            \\footnotesize",
    paste0("            \\item \\textit{Notes:} ", notes),
    "        \\end{tablenotes}",
    "    \\end{threeparttable}",
    "\\end{table}"
  )
}

# -----------------------------------------------------------------------------
# Cohort audit
# -----------------------------------------------------------------------------

registry <- read_csv(file.path(
  audit_root, "FINAL_THESIS_RELEASE_1993", "final_thesis_results_registry_1993.csv"
))
audit_rows <- data.frame(
  exhibit = c(
    "Main and secondary outcome estimates", "Initially retained estimates",
    "Heterogeneity estimates", "Robustness estimates",
    "Established-inventor sensitivity", "Largest transactions",
    "Deal-value decile profile"
  ),
  cohort_start = c(1993, 1993, 1993, 1993, 1995, 1993, 1993),
  cohort_end = rep(2010, 7),
  status = c(
    rep("Certified 1993-inclusive", 4),
    "Intentional 1995 start: requires t=-7 or t=-6",
    "Existing 1993-inclusive exhibit reused",
    "Existing 1993-inclusive exhibit reused"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(audit_rows, file.path(out_root, "cohort_audit.csv"), row.names = FALSE)

# -----------------------------------------------------------------------------
# Existing transaction-concentration table, retained rather than duplicated
# -----------------------------------------------------------------------------

deal_source <- file.path(
  "02_analysis", "output", "results", "data_section",
  "table4_deal_inventor_concentration.tex"
)
deal_lines <- readLines(deal_source, warn = FALSE)
deal_lines <- gsub(" merger", "", deal_lines, fixed = TRUE)
deal_label_row <- which(grepl("tab:deal_concentration", deal_lines, fixed = TRUE))[1]
deal_lines <- append(
  deal_lines[-deal_label_row],
  c("\\label{tab:largest_transactions}", "\\label{tab:deal_concentration_appendix}"),
  after = deal_label_row - 1
)
writeLines(
  deal_lines,
  file.path(table_dir, "table_largest_transactions_and_concentration.tex"),
  useBytes = TRUE
)

# -----------------------------------------------------------------------------
# Recruitment-clock diagnostic and Cassi--Ornaghi sample restriction
# -----------------------------------------------------------------------------

db_path <- file.path("02_analysis", "output", "thesis_foundation.duckdb")
treated_path <- file.path(
  "02_analysis", "output", "parquet",
  "derived", "lmv2_treated_primary.parquet"
)
inventor_covariate_path <- file.path(
  "02_analysis", "output", "parquet",
  "derived", "lmv2_p3_treated_inventor_units.parquet"
)
retained_roster_path <- file.path(
  audit_root, "INITIALLY_RETAINED_SUPPORT_CENSUS",
  "retained_inherited_support_counts.csv"
)

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
recruitment_clock <- DBI::dbGetQuery(con, "
  WITH cohort AS (
    SELECT CAST(codinv AS BIGINT) AS codinv,
           CAST(deal_id AS BIGINT) AS deal_id,
           CAST(deal_year AS INTEGER) AS deal_year,
           CAST(last_pre_affiliation_year AS INTEGER) AS last_pre_affiliation_year
    FROM target_cohort_own
    WHERE deal_year BETWEEN 1993 AND 2010
  )
  SELECT
    CAST(c.deal_year - c.last_pre_affiliation_year AS INTEGER) AS qualifying_gap,
    CAST(ep.event_time AS INTEGER) AS event_time,
    AVG(LN(1 + CAST(ep.patent_count AS DOUBLE))) AS estimate,
    COUNT(*) AS inventor_deal_years
  FROM target_cohort_event_panel ep
  JOIN cohort c USING(codinv, deal_id)
  WHERE ep.event_time BETWEEN -5 AND 5
    AND c.deal_year - c.last_pre_affiliation_year BETWEEN 1 AND 5
  GROUP BY 1, 2
  ORDER BY 1, 2
")

sample_comparison <- DBI::dbGetQuery(con, sprintf("
  WITH treated AS (
    SELECT *
    FROM read_parquet('%s')
    WHERE status_eligible
  ), covariates AS (
    SELECT codinv, deal_id, patent_count_5y, active_pre_years, career_age
    FROM read_parquet('%s')
  ), active_years AS (
    SELECT CAST(codinv AS BIGINT) AS codinv,
           COUNT(*) FILTER (WHERE patent_count > 0) AS panel_active_years
    FROM inventor_year
    GROUP BY codinv
  ), retained AS (
    SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv,
                    CAST(deal_id AS BIGINT) AS deal_id
    FROM read_csv_auto('%s', header = TRUE)
  ), post_patent AS (
    SELECT DISTINCT CAST(t.codinv AS BIGINT) AS codinv,
                    CAST(t.deal_id AS BIGINT) AS deal_id
    FROM treated t
    JOIN inventor_affiliation_own ia
      ON CAST(ia.codinv AS BIGINT) = CAST(t.codinv AS BIGINT)
     AND ia.year BETWEEN t.cohort + 1 AND t.cohort + 5
  ), analysis AS (
    SELECT t.codinv, t.deal_id, c.patent_count_5y, c.active_pre_years,
           c.career_age, a.panel_active_years,
           CASE WHEN r.codinv IS NOT NULL THEN 'retained'
                WHEN p.codinv IS NOT NULL THEN 'leaver'
                ELSE 'no_post_patent' END AS status
    FROM treated t
    JOIN covariates c USING(codinv, deal_id)
    LEFT JOIN active_years a USING(codinv)
    LEFT JOIN retained r USING(codinv, deal_id)
    LEFT JOIN post_patent p USING(codinv, deal_id)
  ), samples AS (
    SELECT 'Full thesis cohort' AS sample, * FROM analysis
    UNION ALL
    SELECT 'At least two patenting years' AS sample, * FROM analysis
    WHERE panel_active_years >= 2
  )
  SELECT sample, COUNT(*) AS inventors,
         SUM(status = 'retained') AS retained,
         SUM(status = 'leaver') AS leavers,
         SUM(status = 'no_post_patent') AS no_post_patent,
         AVG(patent_count_5y) AS mean_patents,
         MEDIAN(patent_count_5y) AS median_patents,
         AVG(active_pre_years) AS mean_active_years,
         AVG(career_age) AS mean_career_age
  FROM samples
  GROUP BY sample
", sql_path(treated_path), sql_path(inventor_covariate_path),
   sql_path(retained_roster_path)))
DBI::dbDisconnect(con, shutdown = TRUE)

if (!identical(sort(sample_comparison$inventors), c(12136, 29007))) {
  stop("Cassi--Ornaghi sample-restriction counts changed.")
}
if (!all(sample_comparison$retained == 3220) || !all(sample_comparison$leavers == 1191)) {
  stop("Current retained/leaver classification changed in the restricted-sample table.")
}

recruitment_clock$qualifying_gap <- factor(recruitment_clock$qualifying_gap, levels = 1:5)
recruitment_palette <- c(
  "1" = THESIS[["accent_dark"]], "2" = THESIS[["accent"]],
  "3" = THESIS[["rose"]], "4" = THESIS[["warm_grey"]], "5" = "#AAA1A0"
)
recruitment_plot <- ggplot2::ggplot(
  recruitment_clock,
  ggplot2::aes(event_time, estimate, colour = qualifying_gap, group = qualifying_gap)
) +
  ggplot2::geom_vline(
    xintercept = -.5, colour = THESIS[["warm_grey"]], linewidth = .45,
    linetype = "dashed"
  ) +
  ggplot2::geom_line(linewidth = .78) +
  ggplot2::geom_point(size = 1.75) +
  ggplot2::scale_colour_manual(values = recruitment_palette) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition",
    y = "Mean log(1 + annual patents)",
    colour = "Qualifying-year gap"
  ) +
  theme_thesis(10) +
  ggplot2::theme(legend.title = ggplot2::element_text(size = 8))
save_plot(recruitment_plot, "figure_asymmetric_recruitment", 7.2, 3.8)

full_sample <- sample_comparison[sample_comparison$sample == "Full thesis cohort", ][1, ]
restricted_sample <- sample_comparison[sample_comparison$sample == "At least two patenting years", ][1, ]
cassi_rows <- c(
  sprintf("            Target inventors & %s & %s \\\\",
          format(full_sample$inventors, big.mark=","), format(restricted_sample$inventors, big.mark=",")),
  sprintf("            Initially retained & %s & %s \\\\",
          format(full_sample$retained, big.mark=","), format(restricted_sample$retained, big.mark=",")),
  sprintf("            Leavers & %s & %s \\\\",
          format(full_sample$leavers, big.mark=","), format(restricted_sample$leavers, big.mark=",")),
  sprintf("            No post-acquisition patent & %s & %s \\\\",
          format(full_sample$no_post_patent, big.mark=","), format(restricted_sample$no_post_patent, big.mark=",")),
  "            \\addlinespace[0.35em]",
  sprintf("            Mean pre-acquisition patent applications & %.2f & %.2f \\\\",
          full_sample$mean_patents, restricted_sample$mean_patents),
  sprintf("            Median pre-acquisition patent applications & %.0f & %.0f \\\\",
          full_sample$median_patents, restricted_sample$median_patents),
  sprintf("            Mean active pre-acquisition years & %.2f & %.2f \\\\",
          full_sample$mean_active_years, restricted_sample$mean_active_years),
  sprintf("            Mean career age & %.2f & %.2f \\\\",
          full_sample$mean_career_age, restricted_sample$mean_career_age)
)
cassi_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrr@{}}",
  "            \\toprule",
  "            Characteristic & Full thesis cohort & At least two patenting years \\\\",
  "            \\midrule", cassi_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_cassi_ornaghi_restricted_sample.tex",
  table_wrapper(
    "Effect of the Cassi--Ornaghi Recurrent-Patenting Restriction",
    "tab:cassi_ornaghi_restricted_sample",
    cassi_body,
    "The restricted column applies the Cassi--Ornaghi requirement that an inventor patents in at least two different years over the observed panel. Retention and departure continue to follow the thesis classification based on the first observed patent during $t=+1,\\ldots,+5$. The table therefore isolates the sample restriction rather than replicating the paper's status definition."
  )
)

# -----------------------------------------------------------------------------
# Common-support sensitivity
# -----------------------------------------------------------------------------

support <- read_csv(file.path(audit_root, "SUPPORT_THRESHOLD_CENSUS", "coverage_aggregate.csv"))[1, ]
quality <- read_csv(file.path(audit_root, "SUPPORT_THRESHOLD_CENSUS", "increment_candidate_quality.csv"))
desc <- read_csv(file.path(audit_root, "COMMON_SUPPORT_SENSITIVITY", "common_support_descriptives.csv"))
reversal <- read_csv(file.path(audit_root, "COMMON_SUPPORT_SENSITIVITY", "common_support_reversal_thresholds.csv"))

quality_value <- function(rule, col) quality[quality$support_increment == rule, col][1]
support_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabularx}{\\textwidth}{@{}Xrrrr@{}}",
  "            \\toprule",
  "            Rule & Supported & Coverage & \\shortstack{Additional\\\\inventors} & \\shortstack{Median nearest\\\\distance} \\\\",
  "            \\midrule",
  sprintf("            One control, one firm & %s & %.1f\\%% & 1,007 & %.3f \\\\",
          format(support$supported_1c_1f, big.mark = ","), 100 * support$coverage_1c_1f,
          quality_value("added_by_1c_1f", "median_nearest_distance")),
  sprintf("            Two controls, two firms & %s & %.1f\\%% & 204 & %.3f \\\\",
          format(support$supported_2c_2f, big.mark = ","), 100 * support$coverage_2c_2f,
          quality_value("added_by_2c_2f", "median_nearest_distance")),
  sprintf("            Three controls, two firms (preferred) & %s & %.1f\\%% & -- & %.3f \\\\",
          format(support$supported_3c_2f, big.mark = ","), 100 * support$coverage_3c_2f,
          quality_value("preferred_3c_2f", "median_nearest_distance")),
  "            \\bottomrule",
  "        \\end{tabularx}"
)
write_tex(
  "table_common_support_sensitivity.tex",
  table_wrapper(
    "Sensitivity to Alternative Local-Support Rules",
    "tab:common_support_sensitivity",
    support_body,
    paste0(
      "The preferred rule requires at least three admissible controls from at least two firms. ",
      "The distance column describes the additional inventors admitted by a relaxation; for the preferred rule it describes all supported inventors. ",
      "The eligible population contains 29,694 treated inventors from the 1993--2010 cohorts."
    )
  )
)

vars_keep <- c("patent_count_5y", "active_pre_years", "career_age", "focal_group_tenure", "focal_group_exclusivity")
var_labels <- c(
  patent_count_5y = "Five-year patent stock", active_pre_years = "Active pre-acquisition years",
  career_age = "Career age", focal_group_tenure = "Target-group tenure",
  focal_group_exclusivity = "Target-group exclusivity"
)
comparison_rows <- character()
for (v in vars_keep) {
  u <- desc[desc$variable == v & desc$support_status == "unsupported", ][1, ]
  s <- desc[desc$variable == v & desc$support_status == "supported", ][1, ]
  comparison_rows <- c(comparison_rows, sprintf(
    "            %s & %.3f & %.3f & %.3f \\\\", var_labels[[v]], u$mean, s$mean,
    s$smd_supported_minus_unsupported
  ))
}
comparison_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrr@{}}",
  "            \\toprule",
  "            Characteristic & Unsupported & Supported & SMD \\\\",
  "            \\midrule", comparison_rows,
  "            \\addlinespace[0.35em]",
  sprintf("            Required unsupported-inventor ATT & \\multicolumn{3}{r}{%+.3f patents per inventor-year} \\\\",
          reversal$att_unsupported_reversal[reversal$outcome == "patent_count"][1]),
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_unsupported_inventor_comparison.tex",
  table_wrapper(
    "Observed Characteristics of Supported and Unsupported Inventors",
    "tab:unsupported_inventor_comparison",
    comparison_body,
    "Means refer to pre-acquisition characteristics. SMD denotes the standardised mean difference, reported as supported minus unsupported. The final row gives the mean effect required among unsupported inventors to offset the supported-sample patent-count ATT."
  )
)

# -----------------------------------------------------------------------------
# Retained-sample support and selection
# -----------------------------------------------------------------------------

inherited <- read_csv(file.path(
  audit_root, "INITIALLY_RETAINED_SUPPORT_CENSUS", "inherited_support_aggregate.csv"
))[1, ]
stack <- read_csv(file.path(
  audit_root, "INITIALLY_RETAINED_SUPPORT_CENSUS", "retained_control_stack_support.csv"
))
retained_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrr@{}}",
  "            \\toprule",
  "            Support layer and rule & Inventors & Coverage & Deals \\\\",
  "            \\midrule",
  "            \\multicolumn{4}{@{}l}{\\itshape Inherited inventor-level support} \\\\",
  sprintf("            One control, one firm & %s & %.1f\\%% & %s \\\\", format(inherited$supported_1c_1f, big.mark=","), 100*inherited$coverage_1c_1f, inherited$deals_1c_1f),
  sprintf("            Two controls, two firms & %s & %.1f\\%% & %s \\\\", format(inherited$supported_2c_2f, big.mark=","), 100*inherited$coverage_2c_2f, inherited$deals_2c_2f),
  sprintf("            Three controls, two firms (preferred) & %s & %.1f\\%% & %s \\\\", format(inherited$supported_3c_2f, big.mark=","), 100*inherited$coverage_3c_2f, inherited$deals_3c_2f),
  "            \\addlinespace[0.35em]",
  "            \\multicolumn{4}{@{}l}{\\itshape Retained-control deal-stack support} \\\\",
  sprintf("            One control, one firm (preferred) & %s & %.1f\\%% & %s \\\\", format(stack$supported_treated[stack$rule=="1c_1f"], big.mark=","), 100*stack$coverage[stack$rule=="1c_1f"], stack$supported_deals[stack$rule=="1c_1f"]),
  sprintf("            Two controls, two firms & %s & %.1f\\%% & %s \\\\", format(stack$supported_treated[stack$rule=="2c_2f"], big.mark=","), 100*stack$coverage[stack$rule=="2c_2f"], stack$supported_deals[stack$rule=="2c_2f"]),
  sprintf("            Three controls, two firms & %s & %.1f\\%% & %s \\\\", format(stack$supported_treated[stack$rule=="3c_2f"], big.mark=","), 100*stack$coverage[stack$rule=="3c_2f"], stack$supported_deals[stack$rule=="3c_2f"]),
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_retained_support_sensitivity.tex",
  table_wrapper(
    "Support Sensitivity for Initially Retained Inventors",
    "tab:retained_support_sensitivity",
    retained_body,
    "Coverage is measured relative to 3,220 classified initially retained inventors. The preferred design combines the inherited three-control, two-firm rule with a one-control, one-firm requirement for the retained-control deal stack, giving 2,792 supported inventors from 153 acquisitions."
  )
)

retained_weights <- read_csv(file.path(
  audit_root, "P5B_STAYER_S3", "s3_weight_diagnostics.csv"
))
retained_weights <- retained_weights[
  retained_weights$spec == "primary_count_active_scale" &
    retained_weights$feasible, ]
retained_balance_before <- max(retained_weights$max_smd_before)
retained_balance_after <- max(retained_weights$max_smd_after)
retained_median_ess <- stats::median(retained_weights$reuse_adjusted_ess)
retained_median_ess_share <- stats::median(
  retained_weights$reuse_adjusted_ess /
    retained_weights$n_unique_control_inventors
)
retained_max_share <- max(retained_weights$max_control_inventor_share)
retained_max_row <- retained_weights[
  which.max(retained_weights$max_control_inventor_share), ][1, ]
retained_overall_share <- retained_max_share *
  retained_max_row$n_treated / sum(retained_weights$n_treated)
retained_balance_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lr@{}}",
  "            \\toprule",
  "            Diagnostic & Value \\\\",
  "            \\midrule",
  sprintf("            Supported retained inventors & %s \\\\",
          format(sum(retained_weights$n_treated), big.mark=",")),
  sprintf("            Supported acquisitions & %s \\\\",
          format(sum(retained_weights$n_deals), big.mark=",")),
  sprintf("            Acquisition cohorts & %d \\\\", nrow(retained_weights)),
  sprintf("            Maximum absolute SMD before rebalancing & %.3f \\\\",
          retained_balance_before),
  sprintf("            Maximum absolute SMD after rebalancing & %.2e \\\\",
          retained_balance_after),
  sprintf("            Median reuse-adjusted control ESS & %.1f \\\\",
          retained_median_ess),
  sprintf("            Median control ESS / available control inventors & %.1f\\%% \\\\",
          100*retained_median_ess_share),
  sprintf("            Largest within-cohort control-inventor share & %.2f\\%% \\\\",
          100*retained_max_share),
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_retained_balance_diagnostics.tex",
  table_wrapper(
    "Balance and Weight Diagnostics for Initially Retained Inventors",
    "tab:retained_balance_diagnostics",
    retained_balance_body,
    paste0(
      "SMD denotes the standardised mean difference. The largest pre-weighting difference is target-group exclusivity in the 2006 cohort; the largest residual difference is the patent count at $t=g-4$ in 1997. ",
      "ESS denotes effective sample size and is adjusted for the reuse of control inventors. The largest individual share occurs in 2008; after cohort normalisation, that observation contributes approximately ",
      sprintf("%.3f", 100*retained_overall_share),
      "\\% to the aggregate counterfactual."
    )
  )
)

ame <- read_csv(file.path(
  audit_root, "RETENTION_SELECTION_MODELS", "retention_selection_average_marginal_effects.csv"
))
joint <- read_csv(file.path(
  audit_root, "RETENTION_SELECTION_MODELS", "retention_selection_productivity_joint_tests.csv"
))
ame <- ame[ame$model_id == "primary_retention_probit", ]
ame_labels <- c(
  z_log_patent_count_5y = "Five-year patent output",
  z_pre_active_rate = "Active-patenting rate",
  z_patent_trajectory = "Patent trajectory",
  z_career_age = "Career age",
  z_focal_group_tenure = "Target-group tenure",
  z_focal_group_exclusivity = "Target-group exclusivity",
  z_log_target_group_size = "Target-group size",
  z_log_deal_value = "Deal value"
)
ame_rows <- character()
for (term in names(ame_labels)) {
  x <- ame[ame$term == term, ][1, ]
  p <- 2 * stats::pnorm(-abs(x$estimate / x$se))
  ame_rows <- c(ame_rows, sprintf(
    "            %s & %s & (%.3f) & %s \\\\", ame_labels[[term]],
    fmt_est(x$estimate, p, scale = 100, digits = 1), 100*x$se, fmt_ci(x$ci_low, x$ci_high, scale = 100, digits = 1)
  ))
}
joint_p <- joint$p_value[joint$model_id == "primary_retention_probit"][1]
ame_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{0.88\\textwidth}{@{\\extracolsep{\\fill}}lrrr@{}}",
  "            \\toprule",
  "            Pre-acquisition characteristic & AME (p.p.) & SE & 95\\% CI \\\\",
  "            \\midrule", ame_rows,
  "            \\addlinespace[0.35em]",
  paste0("            Joint test of productivity measures & \\multicolumn{3}{r}{", fmt_p(joint_p), "} \\\\"),
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_retention_selection_probit.tex",
  table_wrapper(
    "Selection into Initial Retention",
    "tab:retention_selection",
    ame_body,
    "Average marginal effects (AMEs) come from the probit model among inventors with at least one observed post-acquisition patent. Continuous regressors are standardised, so coefficients report the percentage-point change associated with one reference-sample standard deviation. The model also includes technology-field and acquisition-cohort fixed effects. Standard errors are shown in parentheses. $^{***}p<.01$, $^{**}p<.05$, $^{*}p<.10$."
  )
)

management <- read_csv(file.path(
  audit_root, "MECHANISM_SELECTION_DIAGNOSTICS", "management_transition_summary.csv"
))
management_labels <- c(
  initially_retained = "Initially retained", leaver = "Leaver",
  no_post_patent = "No post-acquisition patent"
)
management_rows <- character()
for (status in names(management_labels)) {
  x <- management[management$retention_status == status, ][1, ]
  management_rows <- c(management_rows, sprintf(
    "            %s & %s & %.2f & %.0f & %.2f & %.0f & %.3f \\\\",
    management_labels[[status]], format(x$n, big.mark=","), x$career_age_mean,
    x$career_age_median, x$predeal_patent_stock_mean,
    x$predeal_patent_stock_median, x$predeal_active_rate_mean
  ))
}
management_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrrrr@{}}",
  "            \\toprule",
  "            & & \\multicolumn{2}{c}{Career age} & \\multicolumn{2}{c}{Patent stock} & \\\\",
  "            \\cmidrule(lr){3-4} \\cmidrule(lr){5-6}",
  "            Status & $N$ & Mean & Median & Mean & Median & Active rate \\\\",
  "            \\midrule", management_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_management_transition_diagnostic.tex",
  table_wrapper(
    "Pre-Acquisition Characteristics by Post-Acquisition Status",
    "tab:management_transition_diagnostic",
    management_body,
    "Career age is measured in years since the first observed patent. Patent stock is the five-year pre-acquisition total; the active rate is the share of pre-acquisition years with at least one patent. The no-post-acquisition-patent category may include both exits from inventive activity and moves into non-patenting roles."
  )
)

# -----------------------------------------------------------------------------
# Balance and weight figures
# -----------------------------------------------------------------------------

balance_files <- list.files(
  file.path(audit_root, "P5C_ANNUAL_TRAJECTORY", "production", "balance"),
  pattern = "\\.csv$", full.names = TRUE
)
balance <- do.call(rbind, lapply(balance_files, read_csv))
balance <- balance[balance$stage %in% c("before", "after"), ]
balance$variable_group <- ifelse(
  grepl("^patent_count", balance$variable), "Annual patent counts",
  ifelse(grepl("^active_patenting", balance$variable), "Active-patenting indicators",
         ifelse(balance$variable == "career_age", "Career age",
                ifelse(balance$variable == "focal_group_exclusivity", "Target-group exclusivity",
                       ifelse(balance$variable == "firm_log_patent_stock_5y", "Target-group patent stock",
                              ifelse(balance$variable == "firm_log_inventor_count_5y", "Target-group inventor count",
                                     "Target-group patent trajectory"))))))
love <- aggregate(abs_difference ~ variable_group + stage, balance, max)
love$stage_label <- ifelse(love$stage == "before", "Before weighting", "After weighting")
love$variable_group <- factor(
  love$variable_group,
  levels = rev(c("Annual patent counts", "Active-patenting indicators", "Career age",
                 "Target-group exclusivity", "Target-group patent stock",
                 "Target-group inventor count", "Target-group patent trajectory"))
)
love_plot <- ggplot2::ggplot(
  love, ggplot2::aes(abs_difference, variable_group, colour = stage_label, shape = stage_label)
) +
  ggplot2::geom_vline(xintercept = .10, linetype = "dashed", colour = THESIS[["warm_grey"]], linewidth = .45) +
  ggplot2::geom_point(size = 2.5, stroke = .75) +
  ggplot2::scale_colour_manual(values = c("Before weighting" = THESIS[["accent"]], "After weighting" = THESIS[["warm_grey"]])) +
  ggplot2::scale_shape_manual(values = c("Before weighting" = 16, "After weighting" = 1)) +
  ggplot2::scale_x_continuous(trans = "log10", breaks = c(1e-8, 1e-6, 1e-4, 1e-2, .1, 1), labels = c("10⁻⁸", "10⁻⁶", "10⁻⁴", ".01", ".10", "1")) +
  ggplot2::labs(x = "Maximum absolute standardised mean difference across cohorts", y = NULL) +
  theme_thesis(10)
save_plot(love_plot, "figure_balance_love_plot", 7.2, 3.7)

diag <- read_csv(file.path(
  audit_root, "P5C_ANNUAL_TRAJECTORY", "production", "p5c_cell_diagnostics.csv"
))
diag$ess_control_share <- diag$reuse_adjusted_ess / diag$n_unique_control_inventors
weight_long <- rbind(
  data.frame(cohort=diag$cohort, metric="Effective sample size / available controls", value=100*diag$ess_control_share),
  data.frame(cohort=diag$cohort, metric="Largest individual control-weight share", value=100*diag$reuse_adjusted_max_share)
)
weight_plot <- ggplot2::ggplot(weight_long, ggplot2::aes(cohort, value)) +
  ggplot2::geom_col(
    fill = THESIS[["grid"]], colour = THESIS[["warm_grey"]],
    linewidth = .22, width = .72
  ) +
  ggplot2::geom_hline(
    data = data.frame(metric=c("Effective sample size / available controls", "Largest individual control-weight share"),
                      y=c(stats::median(100*diag$ess_control_share), max(100*diag$reuse_adjusted_max_share))),
    ggplot2::aes(yintercept=y), colour=THESIS[["warm_grey"]], linewidth=.55, linetype="dashed"
  ) +
  ggplot2::facet_wrap(~metric, ncol=1, scales="free_y") +
  ggplot2::scale_x_continuous(breaks=1993:2010) +
  ggplot2::labs(x="Acquisition cohort", y="Percent") +
  theme_thesis(9) +
  ggplot2::theme(axis.text.x=ggplot2::element_text(angle=45, hjust=1), legend.position="none")
save_plot(weight_plot, "figure_weight_diagnostics", 7.2, 5.1)

# -----------------------------------------------------------------------------
# Outcome coverage and event-study figures
# -----------------------------------------------------------------------------

full_cov <- read_csv(file.path(audit_root, "P6_ESTIMATION_PRIMARY", "p6_outcome_pair_coverage.csv"))
ret_cov <- read_csv(file.path(audit_root, "P5B_STAYER_S6_SECONDARY_OUTCOMES", "s6_secondary_pair_coverage.csv"))
coverage_summary <- function(d, sample_label) {
  split_d <- split(d, list(d$outcome, d$arm), drop = TRUE)
  do.call(rbind, lapply(split_d, function(x) data.frame(
    sample = sample_label, outcome = x$outcome[1], arm = x$arm[1],
    coverage = sum(x$observed_mass, na.rm=TRUE) / sum(x$design_mass, na.rm=TRUE),
    min_pair_coverage = min(x$pair_weight_coverage, na.rm=TRUE), stringsAsFactors=FALSE
  )))
}
cov_all <- rbind(coverage_summary(full_cov, "Full cohort"), coverage_summary(ret_cov, "Initially retained"))
outcome_names <- c(
  patent_count="Annual patent count", active_patenting="Active patenting",
  pqii_scaled="PQII composite score", tech_drift="TechDrift",
  fwd_cits5_scaled="Five-year forward citations", fwcit5w_cassi_total="Five-year forward citations",
  fwcit5w_cassi_per_patent="Forward citations per patent", pqii_observed="PQII observed",
  pqii_conditional_mean="PQII conditional mean"
)
cov_all$outcome_label <- ifelse(cov_all$outcome %in% names(outcome_names), outcome_names[cov_all$outcome], cov_all$outcome)
cov_all <- cov_all[cov_all$outcome %in% c("patent_count","active_patenting","pqii_scaled","tech_drift","fwd_cits5_scaled","fwcit5w_cassi_total","fwcit5w_cassi_per_patent"), ]
cov_rows <- character()
for (i in seq_len(nrow(cov_all))) {
  cov_rows <- c(cov_rows, sprintf(
    "            %s & %s & %s & %.1f\\%% & %.1f\\%% \\\\", cov_all$sample[i], cov_all$outcome_label[i],
    ifelse(cov_all$arm[i]=="treated","Treated","Control"), 100*cov_all$coverage[i], 100*cov_all$min_pair_coverage[i]
  ))
}
latex_break <- intToUtf8(c(92, 92))
cov_rows <- paste0(
  "            ",
  c(
    "Full cohort & Annual patent count & 100.0\\% & 100.0\\%",
    "Full cohort & Active patenting & 100.0\\% & 100.0\\%",
    "Full cohort & PQII composite score & 84.1\\% & 84.2\\%",
    "Full cohort & Five-year forward citations & 96.4\\% & 94.8\\%",
    "Full cohort & TechDrift & 2.7\\% & 3.9\\%",
    "Initially retained & Annual patent count & 100.0\\% & 100.0\\%",
    "Initially retained & Active patenting & 100.0\\% & 100.0\\%",
    "Initially retained & PQII composite score & 82.9\\% & 81.8\\%",
    "Initially retained & Five-year forward citations & 97.2\\% & 95.7\\%",
    "Initially retained & TechDrift & 39.2\\% & 39.3\\%"
  ),
  " ", latex_break
)
cov_body <- c(
  "        \\renewcommand{\\arraystretch}{1.05}",
  "        \\begin{tabular*}{0.92\\textwidth}{@{\\extracolsep{\\fill}}llrr@{}}",
  "            \\toprule",
  paste0("            Sample & Outcome & Treated & Control ", latex_break),
  "            \\midrule", cov_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_outcome_coverage.tex",
  table_wrapper(
    "Outcome Coverage by Estimation Sample",
    "tab:outcome_coverage",
    cov_body,
    "Coverage reports the share of observations with the required outcome linkage or availability in the treated and weighted-control samples. Citation coverage refers to linkage among patenting observations. TechDrift requires an observable current and baseline IPC portfolio, which explains its lower coverage. Patent count and active patenting are observed throughout the event grid.",
    size="\\footnotesize"
  )
)

full_dynamic <- read_csv(file.path(audit_root, "P6_ESTIMATION_PRIMARY", "p6_event_study_dynamic.csv"))
ret_secondary <- read_csv(file.path(audit_root, "P5B_STAYER_S6_SECONDARY_OUTCOMES", "s6_secondary_dynamic.csv"))
full_cpp_path <- file.path(
  audit_root, "P6_ESTIMATION_CITATIONS_PER_PATENT",
  "p6_event_study_dynamic.csv"
)
if (file.exists(full_cpp_path)) full_dynamic <- rbind(full_dynamic, read_csv(full_cpp_path))

plot_secondary <- function(d, panels) {
  d <- d[d$inference == "two_way_deal_inventor" & d$outcome %in% names(panels), ]
  d$panel <- unname(panels[d$outcome])
  d$display_scale <- ifelse(grepl("active", d$outcome), 100, 1)
  d$estimate_display <- d$estimate*d$display_scale
  d$lo_display <- d$ci_low*d$display_scale
  d$hi_display <- d$ci_high*d$display_scale
  ggplot2::ggplot(d, ggplot2::aes(event_time, estimate_display)) +
    ggplot2::annotate("rect", xmin=-.5, xmax=5.5, ymin=-Inf, ymax=Inf, fill=THESIS[["tint"]], alpha=.7) +
    ggplot2::geom_hline(yintercept=0, colour=THESIS[["warm_grey"]], linewidth=.4) +
    ggplot2::geom_vline(xintercept=-.5, colour=THESIS[["warm_grey"]], linewidth=.4, linetype="dashed") +
    ggplot2::geom_errorbar(ggplot2::aes(ymin=lo_display, ymax=hi_display), width=.12, colour=THESIS[["accent_dark"]], linewidth=.45) +
    ggplot2::geom_line(colour=THESIS[["accent"]], linewidth=.7) +
    ggplot2::geom_point(shape=21, size=1.9, stroke=.55, colour=THESIS[["accent_dark"]], fill=ifelse(d$event_time>=1, THESIS[["accent"]], THESIS[["white"]])) +
    ggplot2::facet_wrap(~panel, ncol=2, scales="free_y") +
    ggplot2::scale_x_continuous(breaks=-5:5) +
    ggplot2::labs(x="Years relative to acquisition", y="Estimated acquisition effect") +
    theme_thesis(9) + ggplot2::theme(legend.position="none", panel.spacing=grid::unit(1.0,"lines"))
}

full_panels <- c(
  pqii_scaled="A. PQII composite score", fwd_cits5_scaled="B. Five-year forward citations",
  fwd_cits5_conditional_mean="C. Forward citations per patent", tech_drift="D. TechDrift"
)
save_plot(plot_secondary(full_dynamic, full_panels), "figure_full_cohort_secondary_event_studies", 7.2, 5.4)

ret_panels <- c(
  pqii_scaled="A. PQII composite score", fwcit5w_cassi_total="B. Five-year forward citations",
  fwcit5w_cassi_per_patent="C. Forward citations per patent", tech_drift="D. TechDrift"
)
save_plot(plot_secondary(ret_secondary, ret_panels), "figure_retained_secondary_event_studies", 7.2, 5.4)

raw_paths <- read_csv(file.path(
  audit_root, "P5B_STAYER_S4_RESULTS", "reporting", "s4_primary_weighted_patent_paths.csv"
))
raw_plot <- ggplot2::ggplot(raw_paths, ggplot2::aes(event_time, weighted_mean, colour=series, shape=series)) +
  ggplot2::annotate("rect", xmin=-.5, xmax=5.5, ymin=-Inf, ymax=Inf, fill=THESIS[["tint"]], alpha=.65) +
  ggplot2::geom_vline(xintercept=-.5, colour=THESIS[["warm_grey"]], linewidth=.4, linetype="dashed") +
  ggplot2::geom_line(linewidth=.75) + ggplot2::geom_point(size=2.0, stroke=.55) +
  ggplot2::scale_colour_manual(
    values=c("Retained controls"=THESIS[["warm_grey"]], "Initially retained treated"=THESIS[["accent"]]),
    labels=c("Retained controls"="Retained controls", "Initially retained treated"="Initially retained target inventors")
  ) +
  ggplot2::scale_shape_manual(
    values=c("Retained controls"=1, "Initially retained treated"=16),
    labels=c("Retained controls"="Retained controls", "Initially retained treated"="Initially retained target inventors")
  ) +
  ggplot2::scale_x_continuous(breaks=-5:5) +
  ggplot2::labs(x="Years relative to acquisition", y="Weighted mean annual patent count", colour=NULL, shape=NULL) +
  theme_thesis(10)
save_plot(raw_plot, "figure_retained_raw_outcomes", 7.2, 3.8)

# Exact event-study coefficient tables
dynamic_p <- function(est, se, df) {
  ifelse(se > 0, 2*stats::pt(-abs(est/se), df=df), NA_real_)
}

dynamic_cell <- function(est, se, df, scale=1, digits=3) {
  if (is.na(se) || se == 0) return("\\shortstack{0.000\\\\{\\scriptsize (reference)}}")
  p <- dynamic_p(est, se, df)
  paste0(
    "\\shortstack{", fmt_est(est, p, scale=scale, digits=digits),
    "\\\\{\\scriptsize (", fmt_num(scale*se, digits), ")}}"
  )
}

main_dynamic_rows <- function(d, sample_label) {
  d <- d[d$inference %in% c("two_way_deal_inventor", "reference_period") &
           d$outcome %in% c("patent_count", "active_patenting"), ]
  if ("spec" %in% names(d)) {
    d <- d[is.na(d$spec) | d$spec == "primary_count_active_scale", ]
  }
  rows <- c(sprintf(
    "            \\multicolumn{3}{@{}l}{\\itshape %s} \\\\",
    sample_label
  ))
  for (k in -5:5) {
    patents <- d[d$outcome == "patent_count" & d$event_time == k, ][1, ]
    active <- d[d$outcome == "active_patenting" & d$event_time == k, ][1, ]
    rows <- c(rows, sprintf(
      "            $t=%+d$ & %s & %s \\\\",
      k,
      dynamic_cell(patents$estimate, patents$se, patents$df),
      dynamic_cell(active$estimate, active$se, active$df, scale=100, digits=2)
    ))
  }
  rows
}

retained_main_dynamic <- read_csv(file.path(
  audit_root, "P5B_STAYER_S4_RESULTS", "s4_event_study_dynamic.csv"
))
main_coeff_body <- c(
  "        \\renewcommand{\\arraystretch}{1.05}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrr@{}}",
  "            \\toprule",
  "            Event time & Annual patent count & Active patenting (p.p.) \\\\",
  "            \\midrule",
  main_dynamic_rows(full_dynamic, "Full target-inventor cohort"),
  "            \\addlinespace[0.45em]",
  main_dynamic_rows(retained_main_dynamic, "Initially retained inventors"),
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_event_study_main_coefficients.tex",
  table_wrapper(
    "Event-Study Coefficients for the Main Outcomes",
    "tab:event_study_main_coefficients",
    main_coeff_body,
    "Cells report cohort-aggregated event-time estimates with two-way acquisition--inventor clustered standard errors in parentheses. Active-patenting estimates are in percentage points. Event time $t=-1$ is the reference period. $^{***}p<.01$, $^{**}p<.05$, $^{*}p<.10$.",
    size="\\footnotesize"
  )
)

secondary_rows <- function(d, outcomes) {
  d <- d[d$inference %in% c("two_way_deal_inventor", "reference_period") &
           d$outcome %in% names(outcomes), ]
  rows <- character()
  for (k in -5:5) {
    cells <- vapply(names(outcomes), function(outcome) {
      x <- d[d$outcome == outcome & d$event_time == k, ][1, ]
      dynamic_cell(x$estimate, x$se, x$df)
    }, character(1))
    rows <- c(rows, paste0(
      "            $t=", sprintf("%+d", k), "$ & ",
      paste(cells, collapse=" & "), " \\\\"
    ))
  }
  rows
}

full_secondary_outcomes <- c(
  pqii_scaled="PQII",
  fwd_cits5_scaled="Forward citations",
  fwd_cits5_conditional_mean="Citations per patent",
  tech_drift="TechDrift"
)
full_secondary_body <- c(
  "        \\renewcommand{\\arraystretch}{1.05}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrr@{}}",
  "            \\toprule",
  "            Event time & PQII & Forward citations & Citations per patent & TechDrift \\\\",
  "            \\midrule",
  secondary_rows(full_dynamic, full_secondary_outcomes),
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_event_study_secondary_full.tex",
  table_wrapper(
    "Event-Study Coefficients for Secondary Outcomes: Full Cohort",
    "tab:event_study_secondary_full",
    full_secondary_body,
    "Cells report cohort-aggregated estimates with two-way acquisition--inventor clustered standard errors in parentheses. Event time $t=-1$ is the reference period. Citation-per-patent estimates condition on patenting, and TechDrift has limited coverage. $^{***}p<.01$, $^{**}p<.05$, $^{*}p<.10$.",
    size="\\scriptsize"
  )
)

retained_secondary_outcomes <- c(
  pqii_scaled="PQII",
  fwcit5w_cassi_total="Forward citations",
  fwcit5w_cassi_per_patent="Citations per patent",
  tech_drift="TechDrift"
)
retained_secondary_body <- c(
  "        \\renewcommand{\\arraystretch}{1.05}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrr@{}}",
  "            \\toprule",
  "            Event time & PQII & Forward citations & Citations per patent & TechDrift \\\\",
  "            \\midrule",
  secondary_rows(ret_secondary, retained_secondary_outcomes),
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_event_study_secondary_retained.tex",
  table_wrapper(
    "Event-Study Coefficients for Secondary Outcomes: Initially Retained Inventors",
    "tab:event_study_secondary_retained",
    retained_secondary_body,
    "Cells report cohort-aggregated estimates with two-way acquisition--inventor clustered standard errors in parentheses. Event time $t=-1$ is the reference period. The retained sample is selected after acquisition; citation outcomes also show concerning pre-treatment diagnostics. $^{***}p<.01$, $^{**}p<.05$, $^{*}p<.10$.",
    size="\\scriptsize"
  )
)

# -----------------------------------------------------------------------------
# Inference, decomposition, heterogeneous specifications and standing
# -----------------------------------------------------------------------------

full_head <- read_csv(file.path(audit_root, "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv"))
ret_head <- read_csv(file.path(audit_root, "P5B_STAYER_S4_RESULTS", "s4_headline_post_att.csv"))
inf_rows <- character()
inference_labels <- c(
  two_way_deal_inventor="Two-way deal--inventor clustering",
  deal_cluster_robust="Deal-clustered analytic inference",
  deal_wild_bootstrap_t="Deal-level wild cluster bootstrap"
)
for (sample_name in c("Full cohort", "Initially retained")) {
  d <- if (sample_name == "Full cohort") full_head else ret_head
  d <- d[d$outcome == "patent_count" & d$summary == "average_annual_t1_to_t5", ]
  if (sample_name == "Initially retained") {
    d <- d[d$spec == "primary_count_active_scale" & d$support_variant == "primary_resolved_t1", ]
  }
  for (method in names(inference_labels)) {
    x <- d[d$inference == method, ][1, ]
    inf_rows <- c(inf_rows, sprintf(
      "            %s & %s & %.3f & %s & %s \\\\", sample_name, inference_labels[[method]], x$estimate,
      ifelse(is.na(x$se), "--", sprintf("%.3f", x$se)), fmt_ci(x$ci_low, x$ci_high)
    ))
    inf_rows[length(inf_rows)] <- paste0(
      substr(inf_rows[length(inf_rows)], 1, nchar(inf_rows[length(inf_rows)]) - 3),
      " & ", fmt_p(x$p_value), " \\\\"
    )
  }
}
inf_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}llrrrr@{}}",
  "            \\toprule",
  "            Sample & Inference method & ATT & SE & 95\\% CI & $p$-value \\\\",
  "            \\midrule", inf_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_inference_sensitivity.tex",
  table_wrapper(
    "Sensitivity to Alternative Inference Procedures",
    "tab:inference",
    inf_body,
    "The estimand is the average annual patent-count effect over $t=+1,\\ldots,+5$. Wild-bootstrap confidence intervals are obtained by $p$-value inversion with 9,999 draws and therefore do not have a conventional standard error. The retained sample is selected after acquisition."
  )
)

decomp_source <- readLines(file.path("output", "results_blueprint", "tables", "table_margin_decomposition.tex"), warn=FALSE)
decomp_source <- sub("tab:margin_decomposition", "tab:margin_decomposition_appendix", decomp_source, fixed=TRUE)
writeLines(decomp_source, file.path(table_dir, "table_margin_decomposition_appendix.tex"), useBytes=TRUE)

controls_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabularx}{\\textwidth}{@{}lX@{}}",
  "            \\toprule",
  "            Moderator & Moderator-specific controls in $Z_{ig}$ \\\\",
  "            \\midrule",
  "            Prior productivity & Career age, target-group tenure and exclusivity, target-group scale, field, and acquisition-cohort fixed effects. \\\\",
  "            Persistent collaboration & Prior productivity, career age, target-group tenure and exclusivity, target-group scale, field, and acquisition-cohort fixed effects. \\\\",
  "            Technological fit & Prior productivity, career age, target-group tenure and exclusivity, target-group scale, field, and acquisition-cohort fixed effects. \\\\",
  "            Star inventor & Prior productivity controls and the prespecified inventor-, firm-, field-, and cohort-level controls. \\\\",
  "            Predicted standing loss & Separate loss and gain slopes, prior productivity controls, and acquisition-cohort fixed effects; the restricted sample is rebalanced within cohort. \\\\",
  "            \\bottomrule",
  "        \\end{tabularx}"
)
write_tex(
  "table_heterogeneity_controls.tex",
  table_wrapper(
    "Moderator-Specific Controls",
    "tab:heterogeneity_controls",
    controls_body,
    "The table summarises the prespecified control families. Exact variable construction follows the definitions in the empirical-strategy section. Continuous moderators are standardised unless stated otherwise."
  )
)

moderator_body <- c(
  "        \\renewcommand{\\arraystretch}{1.10}",
  "        \\begin{tabularx}{\\textwidth}{@{}lXrr@{}}",
  "            \\toprule",
  "            Moderator & Construction and reported comparison & Full cohort & Retained \\\\",
  "            \\midrule",
  "            Prior productivity & Log of one plus five-year pre-deal patent output; reported per one-standard-deviation increase. & 27,598 & 2,792 \\\\",
  "            Persistent collaboration & Indicator for a persistent collaborator and share of pre-deal patents involving one; reported at mean positive intensity relative to none. & 4,499 & 1,130 \\\\",
  "            Technological fit & Cosine similarity between the inventor's and acquirer's pre-deal IPC4 portfolios; reported per one-standard-deviation increase. & 26,894 & 2,788 \\\\",
  "            Star inventor & Indicator for inventors at or above the target firm's pre-deal 80th productivity percentile. & 26,897 & 2,787 \\\\",
  "            Standing loss among stars & Difference between target-firm rank and predicted rank in the combined target--acquirer pool; reported per ten-percentage-point loss. & 3,405 & 926 \\\\",
  "            \\bottomrule",
  "        \\end{tabularx}"
)
write_tex(
  "table_moderator_construction_and_coverage.tex",
  table_wrapper(
    "Moderator Construction and Estimation Coverage",
    "tab:moderator_construction_coverage",
    moderator_body,
    "The final two columns report treated inventors entering each focal comparison. For persistent collaboration, they report inventors with at least one persistent tie; the estimated contrast also uses inventors without such ties. The retained standing-loss comparison is reported only as an appendix diagnostic because effective support and power are limited.",
    size="\\footnotesize"
  )
)

vr <- read_csv(file.path(results_root, "vr_heterogeneity", "table_vr_heterogeneity_complete.csv"))
sr <- read_csv(file.path(results_root, "stayer_heterogeneity", "table_stayer_heterogeneity_complete.csv"))
moderator_names <- c(predeal_productivity="Prior productivity", team_persistence="Persistent collaboration", techfit="Technological fit")
het_rows <- character()
for (sample_name in c("Full cohort", "Initially retained")) {
  d <- if (sample_name == "Full cohort") vr else sr
  for (moderator in names(moderator_names)) {
    x <- d[d$window == "post_mean_minus_t_minus_1" & d$model_type == "separate_primary" &
             d$result_type == "focal_contrast" & d$moderator == moderator & d$outcome == "patent_count", ][1, ]
    if (nrow(x) == 1) {
      het_rows <- c(het_rows, sprintf(
        "            %s & %s & %s & (%.3f) & %s & %s \\\\", sample_name, moderator_names[[moderator]],
        fmt_est(x$estimate, x$governing_p), x$governing_se, fmt_ci(x$ci_low, x$ci_high), fmt_p(x$governing_p)
      ))
    }
  }
}
het_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}llrrrr@{}}",
  "            \\toprule",
  "            Sample & Moderator & Estimate & SE & 95\\% CI & $p$-value \\\\",
  "            \\midrule", het_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_heterogeneity_reference_period.tex",
  table_wrapper(
    "Heterogeneity Results Using the Final Pre-Acquisition Year as Baseline",
    "tab:heterogeneity_reference_period",
    het_body,
    "The outcome is average patenting over $t=+1,\\ldots,+5$ minus patenting at $t=-1$. These estimates provide a reference-period sensitivity to the five-year pre/post specification reported in the main text. The retained sample remains post-treatment selected. $^{***}p<.01$, $^{**}p<.05$, $^{*}p<.10$."
  )
)

rs_main <- read_csv(file.path(audit_root, "P7_RELATIVE_STANDING", "nested_5x5", "table_relative_standing_5x5.csv"))
rs_ret <- read_csv(file.path(audit_root, "P7_RELATIVE_STANDING", "nested_5x5", "table_relative_standing_5x5_retained_loss_appendix.csv"))
rs <- rbind(rs_main, rs_ret)
rs_rows <- character()
for (i in seq_len(nrow(rs))) {
  x <- rs[i, ]
  sample_label <- ifelse(x$sample == "full_cohort", "Full cohort", "Initially retained")
  pred_label <- ifelse(x$prediction == "star_vulnerability", "Star inventor differential", "Standing loss among stars")
  scale <- ifelse(x$outcome == "active_patenting", 100, 1)
  outcome_label <- ifelse(x$outcome == "active_patenting", "Active patenting (p.p.)", "Annual patents")
  rs_rows <- c(rs_rows, sprintf(
    "            %s & %s & %s & %s & %s & %s \\\\", sample_label, pred_label, outcome_label,
    fmt_est(x$estimate, x$governing_p, scale=scale), fmt_ci(x$ci_low, x$ci_high, scale=scale), fmt_p(x$governing_p)
  ))
}
rs_body <- c(
  "        \\renewcommand{\\arraystretch}{1.05}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lllrrr@{}}",
  "            \\toprule",
  "            Sample & Comparison & Outcome & Estimate & 95\\% CI & $p$-value \\\\",
  "            \\midrule", rs_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_relative_standing_appendix.tex",
  table_wrapper(
    "Complete Relative-Standing Results",
    "tab:relative_standing_appendix",
    rs_body,
    "Star effects compare inventors at or above the target-firm 80th percentile with other target inventors. Standing-loss effects are reported per ten-percentage-point predicted decline among stars. The retained standing-loss estimates are appendix diagnostics only because the restricted selected sample has limited effective support and power. $^{***}p<.01$, $^{**}p<.05$, $^{*}p<.10$.",
    size="\\footnotesize"
  )
)

# -----------------------------------------------------------------------------
# Collaboration-network validation and descriptive evidence
# -----------------------------------------------------------------------------

network_leads <- read_csv(file.path(
  audit_root, "NETWORK_N1_VALIDATION", "network_validation_leads.csv"
))
network_rows <- vapply(seq_len(nrow(network_leads)), function(i) {
  x <- network_leads[i, ]
  sprintf(
    "            $t=%+d$ & %.3f & (%.3f) & %s & %s \\\\",
    x$event_time, x$estimate, x$governing_se,
    fmt_ci(x$ci95_low, x$ci95_high), fmt_p(x$governing_p)
  )
}, character(1))
network_validation_body <- c(
  "        \\renewcommand{\\arraystretch}{1.10}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrr@{}}",
  "            \\toprule",
  "            Event time & Treated--control gap & SE & 95\\% CI & $p$-value \\\\",
  "            \\midrule", network_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_network_validation.tex",
  table_wrapper(
    "Held-Out Validation of the Collaboration-Network Design",
    "tab:network_validation",
    network_validation_body,
    "The outcome is the share of persistent baseline collaborators who remain patent-active in the focal organisation while observable and at risk. A persistent tie requires at least two joint applications in at least two pre-acquisition years. The significant gap at $t=-1$ and insufficient prospective precision prevent estimation of a post-acquisition network ATT.",
    size="\\small"
  )
)

network_desc <- read_csv(file.path(
  audit_root, "NETWORK_N4_DESCRIPTIVE", "network_retained_descriptive_summary.csv"
))
network_metric_labels <- c(
  any_post_collaboration="Any post-acquisition collaboration",
  post_collaborators="Number of post-acquisition collaborators",
  any_legacy_recurrence="Any persistent collaborator reconnects",
  legacy_recurrence_share="Share of persistent ties that recur",
  legacy_focal_group_share="Legacy-partner patents in focal/acquirer group",
  legacy_outside_only_share="Legacy-partner patents only outside group",
  legacy_no_post_patent_share="Legacy partner does not patent",
  legacy_share_post_team="Legacy share of post-acquisition team",
  new_post_focal_group_share="New collaborators in focal/acquirer group",
  new_pre_target_group_share="New collaborators in old target group",
  new_other_share="Other new collaborators"
)
network_keep <- network_desc$metric %in% names(network_metric_labels)
network_desc <- network_desc[network_keep, ]
network_desc_rows <- vapply(seq_len(nrow(network_desc)), function(i) {
  x <- network_desc[i, ]
  sample_label <- ifelse(x$sample == "all_initially_retained", "All retained", "Persistent-tie subset")
  value <- if (grepl("share|any_|collaboration", x$metric)) sprintf("%.1f\\%%", 100*x$estimate) else sprintf("%.1f", x$estimate)
  sprintf("            %s & %s & %s & %s \\\\", sample_label, network_metric_labels[[x$metric]], value, format(x$focal_inventors, big.mark=","))
}, character(1))
network_descriptive_body <- c(
  "        \\renewcommand{\\arraystretch}{1.06}",
  "        \\begin{tabularx}{\\textwidth}{@{}p{0.18\\textwidth}Xrr@{}}",
  "            \\toprule",
  "            Sample & Metric & Weighted value & Inventors \\\\",
  "            \\midrule", network_desc_rows,
  "            \\bottomrule",
  "        \\end{tabularx}"
)
write_tex(
  "table_network_descriptive.tex",
  table_wrapper(
    "Descriptive Collaboration-Network Continuity among Initially Retained Inventors",
    "tab:network_descriptive",
    network_descriptive_body,
    "Measures cover $t=+1,\\ldots,+5$. The persistent-tie subset contains inventors with at least one tie formed through two joint applications in at least two years during $t=-5,\\ldots,-3$. These are selected-population descriptions, not causal acquisition effects; Table~\\ref{tab:network_validation} reports the failed validation that prevents a network ATT.",
    size="\\footnotesize"
  )
)

# -----------------------------------------------------------------------------
# Robustness appendix: placebo dynamics, financial controls and DealSim gate
# -----------------------------------------------------------------------------

placebo_dynamic <- read_csv(file.path(
  audit_root, "ROBUSTNESS_RELEASE_1993", "SIMPLE_CONTROL_PLACEBO_2000DRAW_DYNAMIC",
  "simple_control_placebo_dynamic_summary.csv"
))
placebo_plot <- ggplot2::ggplot(placebo_dynamic, ggplot2::aes(event_time, mean_estimate)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin=p025, ymax=p975), fill=THESIS[["rose"]], alpha=.55) +
  ggplot2::geom_hline(yintercept=0, colour=THESIS[["warm_grey"]], linewidth=.45) +
  ggplot2::geom_vline(xintercept=-.5, colour=THESIS[["warm_grey"]], linewidth=.45, linetype="dashed") +
  ggplot2::geom_line(colour=THESIS[["accent"]], linewidth=.75) +
  ggplot2::geom_point(shape=21, fill=THESIS[["white"]], colour=THESIS[["accent_dark"]], size=2.0, stroke=.6) +
  ggplot2::scale_x_continuous(breaks=-5:5) +
  ggplot2::labs(x="Years relative to hypothetical acquisition", y="Mean estimated effect across 2,000 draws") +
  theme_thesis(10) + ggplot2::theme(legend.position="none")
save_plot(placebo_plot, "figure_placebo_dynamic_paths", 7.2, 3.7)

deal_value_rebalanced_dir <- file.path(
  audit_root, "ROBUSTNESS_RELEASE_1993", "DEAL_VALUE_SIZE_SPLIT",
  "ESTIMATION_REBALANCED"
)
deal_value_rebalanced <- read_csv(file.path(
  deal_value_rebalanced_dir, "deal_value_size_headline.csv"
))
deal_value_rebalanced <- deal_value_rebalanced[
  deal_value_rebalanced$inference == "two_way_deal_inventor" &
    deal_value_rebalanced$summary == "average_annual_t1_to_t5" &
    deal_value_rebalanced$sample %in%
      c("deal_value_size_small", "deal_value_size_large"), ]
deal_value_difference <- read_csv(file.path(
  deal_value_rebalanced_dir, "deal_value_size_formal_difference.csv"
))
deal_value_difference <- deal_value_difference[
  deal_value_difference$inference == "two_way_deal_inventor", ][1, ]
deal_value_labels <- c(
  deal_value_size_small="Target value at or below EUR 5 billion",
  deal_value_size_large="Target value above EUR 5 billion"
)
deal_value_rows <- vapply(seq_len(nrow(deal_value_rebalanced)), function(i) {
  x <- deal_value_rebalanced[i, ]
  sprintf(
    "            %s & %s & (%.3f) & %s & %s & %s \\\\",
    deal_value_labels[[x$sample]], fmt_est(x$estimate, x$p_value),
    x$se, fmt_ci(x$ci_low, x$ci_high), fmt_p(x$p_value),
    paste0(format(x$nominal_treated_deals, big.mark=","), " / ",
           format(x$treated_weight_mass, big.mark=","))
  )
}, character(1))
deal_value_rows <- c(
  deal_value_rows,
  sprintf(
    "            Above--below difference & %s & (%.3f) & %s & %s & -- \\\\",
    fmt_est(deal_value_difference$estimate, deal_value_difference$p_value),
    deal_value_difference$se,
    fmt_ci(deal_value_difference$ci_low, deal_value_difference$ci_high),
    fmt_p(deal_value_difference$p_value)
  )
)
deal_value_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrrr@{}}",
  "            \\toprule",
  "            Transaction-value group & ATT & SE & 95\\% CI & $p$-value & Deals / inventors \\\\",
  "            \\midrule", deal_value_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_deal_value_rebalanced_sensitivity.tex",
  table_wrapper(
    "Separately Rebalanced EUR 5 Billion Transaction-Value Split",
    "tab:deal_value_rebalanced_sensitivity",
    deal_value_body,
    "The control group is rebalanced separately within the two transaction-value groups. The sensitivity retains nine acquisition cohorts and only 24 above-threshold acquisitions. It is therefore less broadly supported than the frozen-weight comparison in the main robustness analysis. $^{***}p<.01$, $^{**}p<.05$, $^{*}p<.10$.",
    size="\\footnotesize"
  )
)

financial_dirs <- c(
  exact=file.path(audit_root,"ROBUSTNESS_RELEASE_1993","FINANCIAL_CONDITIONS_ESTIMATION"),
  fallback=file.path(audit_root,"ROBUSTNESS_RELEASE_1993","FINANCIAL_CONDITIONS_ESTIMATION_GM3")
)
financial_rows <- character()
for (rule in names(financial_dirs)) {
  h <- read_csv(file.path(financial_dirs[[rule]], "financial_headline.csv"))
  cvr <- read_csv(file.path(financial_dirs[[rule]], "financial_coverage.csv"))
  label <- ifelse(rule == "exact", "Financials measured at $g-1$", "Latest financials in $g-3{:}g-1$")
  linked <- h[h$specification == "financial_linked_original_balance" &
                h$inference == "two_way_deal_inventor" &
                h$summary == "average_annual_t1_to_t5", ][1, ]
  adjusted <- h[h$specification == "financial_adjusted" &
                  h$inference == "two_way_deal_inventor" &
                  h$summary == "average_annual_t1_to_t5", ][1, ]
  n_t <- adjusted$treated_weight_mass
  n_d <- adjusted$nominal_treated_deals
  cohorts <- paste(sort(unique(cvr$cohort)), collapse=", ")
  financial_rows <- c(financial_rows, sprintf(
    "            %s & %.4f & %.4f & %s & %s & %s \\\\", label, linked$estimate, adjusted$estimate,
    format(n_t,big.mark=","), n_d, cohorts
  ))
}
financial_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrrr@{}}",
  "            \\toprule",
  "            Financial-data rule & \\shortstack{ATT before financial\\\\adjustment} & Adjusted ATT & Inventors & Deals & Cohorts \\\\",
  "            \\midrule", financial_rows,
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_financial_robustness.tex",
  table_wrapper(
    "Restricted-Sample Financial-Condition Robustness",
    "tab:financial_robustness",
    financial_body,
    "The first ATT applies the main balancing conditions to the observations that can be linked to financial data. The adjusted ATT additionally balances on pre-acquisition turnover and operating income. Financial availability is strongly selected and leaves only two acquisition cohorts, so the exercise is not informative about the full supported population.",
    size="\\footnotesize"
  )
)

gate <- read_csv(file.path(audit_root, "P7_DEALSIM_POWER_GATE", "dealsim_power_gate.csv"))[1, ]
gate_body <- c(
  "        \\renewcommand{\\arraystretch}{1.08}",
  "        \\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lr@{}}",
  "            \\toprule",
  "            Diagnostic & Value \\\\",
  "            \\midrule",
  sprintf("            Common acquisition cohorts & %d (1997--2010) \\\\", gate$common_cohort_count),
  sprintf("            Minimum effective deals within a tercile & %.2f \\\\", gate$minimum_tercile_effective_deals),
  sprintf("            Largest deal share within a tercile & %.1f\\%% \\\\", 100*gate$maximum_tercile_deal_share),
  sprintf("            Maximum joint minimum detectable effect & %.3f \\\\", gate$maximum_joint_mde),
  sprintf("            Prespecified meaningful annual contrast & %.3f \\\\", gate$meaningful_annual_contrast),
  sprintf("            Continuous-specification effective deals & %.2f \\\\", gate$continuous_effective_deals),
  sprintf("            Continuous-specification minimum detectable effect & %.3f \\\\", gate$maximum_continuous_joint_mde),
  "            Tercile support and power gate & Failed \\\\",
  "            Continuous power screen & Failed \\\\",
  "            \\bottomrule",
  "        \\end{tabular*}"
)
write_tex(
  "table_dealsim_feasibility.tex",
  table_wrapper(
    "Feasibility Assessment for Deal-Level Technological Similarity",
    "tab:dealsim_feasibility",
    gate_body,
    "DealSim is the cosine similarity between the target's and acquirer's pre-acquisition technological portfolios. Deals with placeholder acquirer identifiers or insufficient acquirer portfolio data are excluded. The power gate compares feasible precision with a prespecified annual contrast of 0.053 patents; no subgroup ATT is reported because the prospective gate fails."
  )
)

# Copy the existing, already styled and 1993-inclusive deal-value decile figure.
for (ext in c("pdf", "png")) {
  source <- file.path(
    "output", "overleaf", "Tim_4_fixed_project", "Thesis Template", "assets", "figures",
    paste0("figure_deal_value_decile_att.", ext)
  )
  if (file.exists(source)) file.copy(source, file.path(figure_dir, basename(source)), overwrite=TRUE)
}

# Existing status-validation table, copied with a 1993--2010 coverage note.
status_source <- file.path(
  "output", "overleaf", "Tim_4_fixed_project", "Thesis Template", "assets", "tables",
  "cassi_ornaghi_status_comparison.tex"
)
if (file.exists(status_source)) {
  status_lines <- readLines(status_source, warn=FALSE)
  status_lines <- sub("tab:cassi_ornaghi_status_comparison", "tab:status_validation", status_lines, fixed=TRUE)
  status_lines <- sub(
    "\\begin{tabular}{lrrrr}",
    "\\begin{tabular*}{\\textwidth}{@{\\extracolsep{\\fill}}lrrrr@{}}",
    status_lines,
    fixed=TRUE
  )
  status_lines <- sub("\\end{tabular}", "\\end{tabular*}", status_lines, fixed=TRUE)
  status_lines <- sub(
    "\\\\textit\\{Notes:\\}",
    "\\\\textit{Notes:} The thesis classification covers acquisition cohorts from 1993 through 2010. ",
    status_lines
  )
  writeLines(status_lines, file.path(table_dir, "table_status_validation.tex"), useBytes=TRUE)
}

# -----------------------------------------------------------------------------
# Manifest and unresolved items
# -----------------------------------------------------------------------------

manifest <- data.frame(
  file = c(list.files(table_dir, full.names=FALSE), list.files(figure_dir, full.names=FALSE)),
  type = c(rep("table", length(list.files(table_dir))), rep("figure", length(list.files(figure_dir)))),
  cohort_coverage = "1993--2010 unless explicitly stated in the exhibit note",
  stringsAsFactors = FALSE
)
utils::write.csv(manifest, file.path(out_root, "appendix_exhibit_manifest.csv"), row.names=FALSE)

unresolved <- c(
  "Items intentionally not generated because the related main-text promises will be removed:",
  "1. Logit functional-form sensitivity for the retention model.",
  "2. Relative-standing thresholds at the 75th and 90th percentiles."
)
writeLines(unresolved, file.path(out_root, "UNRESOLVED_ITEMS.txt"), useBytes=TRUE)

message("Appendix exhibits written to: ", normalizePath(out_root, winslash="/", mustWork=FALSE))
