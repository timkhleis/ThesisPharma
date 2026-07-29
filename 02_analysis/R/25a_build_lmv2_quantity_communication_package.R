# ============================================================================
# Supervisor-ready closeout of the full-cohort patent-quantity results
# ============================================================================
#
# This script does not estimate a new matching design. It assembles certified
# P5c/P6 and Package 1 results, adds:
#   1. a LOYO-calibrated sign-breakdown statistic; and
#   2. an exact Shapley decomposition of the patent-count ATT into the
#      active-patenting (extensive) and patents-per-active-year (intensive)
#      margins.
#
# Run from the thesis worktree root:
# Rscript 02_analysis/R/25a_build_lmv2_quantity_communication_package.R

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (pkg in c("DBI", "duckdb", "digest", "ggplot2", "gridExtra")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

AUDIT_ROOT <- file.path(BASE, "output", "audit", "local_match_v2")
OUT_DIR <- file.path(AUDIT_ROOT, "P6_QUANTITY_COMMUNICATION_PACKAGE")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

path <- function(...) file.path(AUDIT_ROOT, ...)
read_csv <- function(...) {
  f <- path(...)
  if (!file.exists(f)) stop("Missing required input: ", f)
  utils::read.csv(f, stringsAsFactors = FALSE)
}

assert_close <- function(actual, expected, tolerance, label) {
  if (length(actual) != 1L || length(expected) != 1L ||
      !is.finite(actual) || !is.finite(expected) ||
      abs(actual - expected) > tolerance) {
    stop(
      label, " mismatch: actual=", format(actual, digits = 16),
      ", expected=", format(expected, digits = 16),
      ", tolerance=", tolerance)
  }
  invisible(TRUE)
}

# Tooth-check the numeric guard before relying on it.
guard_fired <- FALSE
tryCatch(
  assert_close(0, 0.01, 1e-6, "tooth test"),
  error = function(e) guard_fired <<- TRUE)
if (!guard_fired) stop("assert_close tooth test did not fire")

headline <- read_csv(
  "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_headline_post_att.csv")
dynamic <- read_csv(
  "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_event_study_dynamic.csv")
loyo_placebo <- read_csv(
  "P6_PACKAGE1_LOYO_GRID", "package1_loyo_heldout_placebos.csv")
loyo_headlines <- list(
  loyo_m2 = read_csv(
    "P6_PACKAGE1_ESTIMATION_LOYO_M2", "p6_headline_post_att.csv"),
  loyo_m3 = read_csv(
    "P6_P5C_ESTIMATION_LOYO_M3", "p6_headline_post_att.csv"),
  loyo_m4 = read_csv(
    "P6_P5C_ESTIMATION_LOYO_M4", "p6_headline_post_att.csv"),
  loyo_m5 = read_csv(
    "P6_PACKAGE1_ESTIMATION_LOYO_M5", "p6_headline_post_att.csv"))
loyo_m1_placebo <- read_csv(
  "P6_PACKAGE1D_MEAN_REVERSION", "package1d_loyo_m1_heldout.csv")
loyo_m1_headline <- read_csv(
  "P6_PACKAGE1D_ESTIMATION_LOYO_M1", "p6_headline_post_att.csv")
established_strict <- read_csv(
  "P6_VERGINER_EARLY_RECRUITMENT_STRICT_FEASIBLE",
  "verginer_p6_headline.csv")
established_all16 <- read_csv(
  "P6_VERGINER_EARLY_RECRUITMENT", "verginer_p6_headline.csv")

main_wild <- headline[
  headline$outcome == "patent_count" &
    headline$sample == "full_1994_2010" &
    headline$inference == "deal_wild_bootstrap_t", ,
  drop = FALSE]
active_wild <- headline[
  headline$outcome == "active_patenting" &
    headline$sample == "full_1994_2010" &
    headline$inference == "deal_wild_bootstrap_t", ,
  drop = FALSE]
if (nrow(main_wild) != 2L || nrow(active_wild) != 2L) {
  stop("Expected annual and cumulative wild-bootstrap headline rows")
}
main_annual <- main_wild[which.min(abs(main_wild$estimate)), ]
main_cumulative <- main_wild[which.max(abs(main_wild$estimate)), ]
active_annual <- active_wild[which.min(abs(active_wild$estimate)), ]

# Read the matched panel once and compute exact post-period weighted means.
panel_glob <- normalizePath(
  path("P6_P5C_PANEL_COUNT_ACTIVE", "panel_matched"),
  winslash = "/", mustWork = TRUE)
panel_glob <- paste0(panel_glob, "/*.parquet")
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
quoted_glob <- gsub("'", "''", panel_glob, fixed = TRUE)
post_means <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT arm, ",
    "SUM(weight * patent_count) / SUM(weight) AS patent_mean, ",
    "SUM(weight * active_patenting) / SUM(weight) AS active_rate, ",
    "SUM(weight * patent_count) / ",
    "NULLIF(SUM(weight * active_patenting), 0) AS patents_per_active_year ",
    "FROM read_parquet('", quoted_glob, "') ",
    "WHERE event_time BETWEEN 1 AND 5 ",
    "GROUP BY arm ORDER BY arm"))
if (!identical(post_means$arm, c("control", "treated"))) {
  stop("Unexpected arm order in post means")
}

control <- post_means[post_means$arm == "control", ]
treated <- post_means[post_means$arm == "treated", ]
delta_patent <- treated$patent_mean - control$patent_mean
delta_active <- treated$active_rate - control$active_rate
delta_intensity <-
  treated$patents_per_active_year - control$patents_per_active_year
assert_close(
  delta_patent, main_annual$estimate, 1e-8,
  "Direct weighted patent-count ATT")
assert_close(
  delta_active, active_annual$estimate, 1e-8,
  "Direct weighted active-patenting ATT")

# Order-invariant Shapley decomposition of Y = Pr(Y>0) * E[Y | Y>0].
extensive_component <- delta_active *
  mean(c(control$patents_per_active_year, treated$patents_per_active_year))
intensive_component <- delta_intensity *
  mean(c(control$active_rate, treated$active_rate))
assert_close(
  extensive_component + intensive_component,
  delta_patent, 1e-12, "Shapley decomposition")

margin_decomposition <- data.frame(
  margin = c("Extensive: probability of patenting",
             "Intensive: patents per active inventor-year"),
  contribution = c(extensive_component, intensive_component),
  share_of_total_decline = c(
    extensive_component / delta_patent,
    intensive_component / delta_patent),
  stringsAsFactors = FALSE)
utils::write.csv(
  margin_decomposition,
  file.path(OUT_DIR, "quantity_margin_decomposition.csv"),
  row.names = FALSE)
utils::write.csv(
  post_means,
  file.path(OUT_DIR, "quantity_post_weighted_means.csv"),
  row.names = FALSE)

# LOYO-calibrated sensitivity: how many multiples of the largest held-out
# pre-period discrepancy are required to offset the annual headline estimate?
placebo_columns <- c(
  "design", "held_out_event_time", "reference_event_time",
  "estimate", "se", "df", "ci_low", "ci_high",
  "ordinary_ci95_includes_zero", "equivalence_margin")
placebo_m5_m2 <- transform(
  loyo_placebo[loyo_placebo$sample == "full_1994_2010", ],
  reference_event_time = -1L)
placebo_m1 <- transform(
  loyo_m1_placebo[loyo_m1_placebo$sample == "full_1994_2010", ],
  held_out_event_time = event_time,
  ordinary_ci95_includes_zero = ci_low <= 0 & ci_high >= 0,
  equivalence_margin = 0.05)
all_placebos <- rbind(
  placebo_m5_m2[, placebo_columns],
  placebo_m1[, placebo_columns])
all_placebos <- all_placebos[order(all_placebos$held_out_event_time), ]
max_abs_placebo <- max(abs(all_placebos$estimate))
breakdown_multiple <- abs(main_annual$estimate) / max_abs_placebo
breakdown <- data.frame(
  headline_att_per_year = main_annual$estimate,
  maximum_absolute_heldout_gap = max_abs_placebo,
  additive_gap_needed_to_reach_zero = abs(main_annual$estimate),
  breakdown_multiple_of_maximum_heldout_gap = breakdown_multiple,
  interpretation = paste0(
    "The post-period violation would need to be ",
    sprintf("%.2f", breakdown_multiple),
    " times the largest observed held-out pre-period discrepancy ",
    "to offset the point estimate under a simple additive calibration."),
  stringsAsFactors = FALSE)
utils::write.csv(
  all_placebos,
  file.path(OUT_DIR, "quantity_loyo_heldout_placebos.csv"),
  row.names = FALSE)
utils::write.csv(
  breakdown,
  file.path(OUT_DIR, "quantity_loyo_sign_breakdown.csv"),
  row.names = FALSE)

# Appendix result table. The t=-1 LOYO arm is retained but marked as using
# t=-4 as its reference, so it is not folded into the comparable LOYO range.
select_wild_rows <- function(
    x, design_key, design, population, reference) {
  y <- x[
    x$outcome == "patent_count" &
      x$inference == "deal_wild_bootstrap_t", ,
    drop = FALSE]
  y <- y[order(y$sample, abs(y$estimate)), ]
  y$design_key <- design_key
  y$design <- design
  y$population <- population
  y$reference_period <- reference
  y
}

table_rows <- list(
  select_wild_rows(
    headline, "count_active", "P5c headline",
    "Full eligible cohort", "t=-1"),
  select_wild_rows(
    loyo_headlines$loyo_m2, "loyo_m2", "LOYO: hold out t=-2",
    "Full eligible cohort", "t=-1"),
  select_wild_rows(
    loyo_headlines$loyo_m3, "loyo_m3", "LOYO: hold out t=-3",
    "Full eligible cohort", "t=-1"),
  select_wild_rows(
    loyo_headlines$loyo_m4, "loyo_m4", "LOYO: hold out t=-4",
    "Full eligible cohort", "t=-1"),
  select_wild_rows(
    loyo_headlines$loyo_m5, "loyo_m5", "LOYO: hold out t=-5",
    "Full eligible cohort", "t=-1"),
  select_wild_rows(
    loyo_m1_headline, "loyo_m1", "LOYO: hold out t=-1",
    "Full eligible cohort", "t=-4"),
  select_wild_rows(
    established_strict, "established_strict",
    "Established, strict firm-balanced",
    "Early-recruited inventors; 13 feasible cohorts", "t=-1"),
  select_wild_rows(
    established_all16, "established_all16",
    "Established, inventor-balanced",
    "Early-recruited inventors; 16 cohorts", "t=-1"))
all_names <- unique(unlist(lapply(table_rows, names), use.names = FALSE))
table_rows <- lapply(table_rows, function(x) {
  for (name in setdiff(all_names, names(x))) x[[name]] <- NA
  x[, all_names, drop = FALSE]
})
results_appendix <- do.call(rbind, table_rows)
results_appendix$effect_scale <- ifelse(
  abs(results_appendix$estimate) > 0.2,
  "five-year cumulative", "per inventor-year")

panel_dirs <- c(
  count_active = "P6_P5C_PANEL_COUNT_ACTIVE",
  loyo_m2 = "P6_PACKAGE1_PANEL_LOYO_M2",
  loyo_m3 = "P6_P5C_PANEL_LOYO_M3",
  loyo_m4 = "P6_P5C_PANEL_LOYO_M4",
  loyo_m5 = "P6_PACKAGE1_PANEL_LOYO_M5",
  loyo_m1 = "P6_PACKAGE1D_PANEL_LOYO_M1")
panel_metrics <- do.call(rbind, lapply(names(panel_dirs), function(key) {
  glob <- normalizePath(
    path(panel_dirs[[key]], "panel_matched"),
    winslash = "/", mustWork = TRUE)
  glob <- gsub("'", "''", paste0(glob, "/*.parquet"), fixed = TRUE)
  x <- DBI::dbGetQuery(
    con,
    paste0(
      "WITH panel AS (",
      "SELECT * FROM read_parquet('", glob, "')",
      "), deal_mass AS (",
      "SELECT 'full_1994_2010' AS sample, deal_id, ",
      "SUM(weight) AS mass FROM panel ",
      "WHERE arm='treated' AND event_time=1 GROUP BY deal_id ",
      "UNION ALL ",
      "SELECT 'buffered_1994_2008' AS sample, deal_id, ",
      "SUM(weight) AS mass FROM panel ",
      "WHERE arm='treated' AND event_time=1 AND cohort<=2008 ",
      "GROUP BY deal_id",
      "), deal_summary AS (",
      "SELECT sample, COUNT(*) AS nominal_deals, ",
      "SUM(mass)*SUM(mass)/SUM(mass*mass) AS effective_deals ",
      "FROM deal_mass GROUP BY sample",
      "), control_summary AS (",
      "SELECT CASE WHEN cohort<=2008 THEN 'buffered_1994_2008' ",
      "ELSE 'full_only' END AS cohort_group, ",
      "SUM(weight*patent_count) AS numerator, SUM(weight) AS denominator ",
      "FROM panel WHERE arm='control' AND event_time BETWEEN 1 AND 5 ",
      "GROUP BY cohort_group",
      "), control_means AS (",
      "SELECT 'full_1994_2010' AS sample, ",
      "SUM(numerator)/SUM(denominator) AS control_post_mean ",
      "FROM control_summary ",
      "UNION ALL ",
      "SELECT 'buffered_1994_2008' AS sample, ",
      "SUM(numerator)/SUM(denominator) AS control_post_mean ",
      "FROM control_summary WHERE cohort_group!='full_only'",
      "), pre_summary AS (",
      "SELECT CASE WHEN cohort<=2008 THEN 'buffered_1994_2008' ",
      "ELSE 'full_only' END AS cohort_group, ",
      "SUM(weight*patent_count) AS numerator, SUM(weight) AS denominator ",
      "FROM panel WHERE arm='treated' AND event_time BETWEEN -5 AND -1 ",
      "GROUP BY cohort_group",
      "), pre_means AS (",
      "SELECT 'full_1994_2010' AS sample, ",
      "SUM(numerator)/SUM(denominator) AS treated_pre_mean ",
      "FROM pre_summary ",
      "UNION ALL ",
      "SELECT 'buffered_1994_2008' AS sample, ",
      "SUM(numerator)/SUM(denominator) AS treated_pre_mean ",
      "FROM pre_summary WHERE cohort_group!='full_only'",
      ") SELECT d.sample, d.nominal_deals, d.effective_deals, ",
      "c.control_post_mean, p.treated_pre_mean FROM deal_summary d ",
      "JOIN control_means c USING(sample) ",
      "JOIN pre_means p USING(sample)"))
  x$design_key <- key
  x
}))

p4_root <- normalizePath(
  file.path(
    BASE, "..", "..", "lmv2-p4-ebal", "02_analysis", "output",
    "audit", "local_match_v2"),
  winslash = "/", mustWork = TRUE)
established_weight_dirs <- c(
  established_strict = "P5D_VERGINER_EARLY_RECRUITMENT",
  established_all16 = "P5D_VERGINER_EARLY_RECRUITMENT_INVENTOR_ONLY")
established_metrics <- do.call(
  rbind, lapply(names(established_weight_dirs), function(key) {
    weight_glob <- normalizePath(
      file.path(
        p4_root, established_weight_dirs[[key]], "weights"),
      winslash = "/", mustWork = TRUE)
    weight_glob <- gsub(
      "'", "''", paste0(weight_glob, "/*.parquet"), fixed = TRUE)
    x <- DBI::dbGetQuery(
      con,
      paste0(
        "WITH deal_mass AS (",
        "SELECT 'full' AS sample, deal_id, SUM(final_weight) AS mass ",
        "FROM read_parquet('", weight_glob, "') ",
        "WHERE treated=1 GROUP BY deal_id ",
        "UNION ALL ",
        "SELECT 'buffered' AS sample, deal_id, SUM(final_weight) AS mass ",
        "FROM read_parquet('", weight_glob, "') ",
        "WHERE treated=1 AND cohort<=2008 GROUP BY deal_id",
        ") SELECT sample, COUNT(*) AS nominal_deals, ",
        "SUM(mass)*SUM(mass)/SUM(mass*mass) AS effective_deals ",
        "FROM deal_mass GROUP BY sample"))
    paths <- read_csv(
      if (key == "established_strict") {
        "P6_VERGINER_EARLY_RECRUITMENT_STRICT_FEASIBLE"
      } else {
        "P6_VERGINER_EARLY_RECRUITMENT"
      },
      "verginer_weighted_patent_paths.csv")
    control_mean <- mean(
      paths$weighted_mean[
        paths$arm == "control" &
          paths$event_time >= 1 & paths$event_time <= 5])
    treated_pre_mean <- mean(
      paths$weighted_mean[
        paths$arm == "treated" &
          paths$event_time >= -5 & paths$event_time <= -1])
    x$control_post_mean <- ifelse(
      x$sample == "full", control_mean, NA_real_)
    x$treated_pre_mean <- ifelse(
      x$sample == "full", treated_pre_mean, NA_real_)
    x$design_key <- key
    x
  }))
metrics <- rbind(panel_metrics, established_metrics)
results_appendix <- merge(
  results_appendix, metrics,
  by = c("design_key", "sample"), all.x = TRUE, sort = FALSE)
results_appendix$relative_to_matched_post_counterfactual <-
  results_appendix$estimate /
  ifelse(
    results_appendix$effect_scale == "five-year cumulative",
    5 * results_appendix$control_post_mean,
    results_appendix$control_post_mean)
results_appendix$relative_to_pre_treatment_output <-
  results_appendix$estimate /
  ifelse(
    results_appendix$effect_scale == "five-year cumulative",
    5 * results_appendix$treated_pre_mean,
    results_appendix$treated_pre_mean)
results_appendix <- results_appendix[
  , c(
    "design", "population", "sample", "reference_period",
    "effect_scale", "estimate", "ci_low", "ci_high", "p_value",
    "relative_to_pre_treatment_output",
    "relative_to_matched_post_counterfactual",
    "nominal_deals", "effective_deals", "inference")]
utils::write.csv(
  results_appendix,
  file.path(OUT_DIR, "quantity_results_appendix.csv"),
  row.names = FALSE)

# Supervisor figure: dynamic headline, held-out-year diagnostics, and the
# point-estimate decomposition. The mechanically constrained pre-periods in
# panel A are explicitly labelled as such; panel B supplies the falsification.
dyn <- dynamic[
  dynamic$outcome == "patent_count" &
    dynamic$sample == "full_1994_2010" &
    dynamic$inference == "two_way_deal_inventor",
  c("event_time", "estimate", "ci_low", "ci_high")]
dyn <- rbind(
  dyn,
  data.frame(
    event_time = -1L, estimate = 0, ci_low = 0, ci_high = 0))
dyn <- dyn[order(dyn$event_time), ]

message("Building dynamic panel")
p_dynamic <- ggplot2::ggplot(
  dyn, ggplot2::aes(x = event_time, y = estimate)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey45") +
  ggplot2::geom_vline(
    xintercept = -0.5, linetype = "dashed", colour = "grey55") +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = ci_low, ymax = ci_high),
    fill = "#56B4E9", alpha = 0.20) +
  ggplot2::geom_line(colour = "#0072B2", linewidth = 0.9) +
  ggplot2::geom_point(colour = "#0072B2", size = 2.1) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    title = "A. Preferred matched event study",
    subtitle = "Pre-period means are constrained; t=-1 is the reference",
    x = "Event time", y = "Patent-count ATT") +
  ggplot2::theme_minimal(base_size = 12)

message("Building held-out panel")
p_placebo <- ggplot2::ggplot(
  all_placebos,
  ggplot2::aes(x = held_out_event_time, y = estimate)) +
  ggplot2::annotate(
    "rect", xmin = -Inf, xmax = Inf, ymin = -0.05, ymax = 0.05,
    fill = "#009E73", alpha = 0.10) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey45") +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci_low, ymax = ci_high),
    width = 0.12, colour = "#D55E00") +
  ggplot2::geom_point(colour = "#D55E00", size = 2.5) +
  ggplot2::scale_x_continuous(breaks = -5:-1) +
  ggplot2::labs(
    title = "B. Genuinely held-out pre-periods",
    subtitle = "95% intervals; green band is the predeclared +/-0.05 margin",
    x = "Held-out event year", y = "Treated-control gap") +
  ggplot2::theme_minimal(base_size = 12)

message("Building margin panel")
margin_decomposition$margin <- factor(
  margin_decomposition$margin,
  levels = rev(margin_decomposition$margin))
p_margin <- ggplot2::ggplot(
  margin_decomposition,
  ggplot2::aes(x = margin, y = contribution, fill = margin)) +
  ggplot2::geom_col(width = 0.65, show.legend = FALSE) +
  ggplot2::coord_flip() +
  ggplot2::geom_text(
    ggplot2::aes(
      y = contribution / 2,
      label = paste0(
        sprintf("%.3f", contribution), " (",
        sprintf("%.0f%%", 100 * share_of_total_decline), ")")),
    hjust = 0.5, colour = "white", fontface = "bold", size = 3.7) +
  ggplot2::scale_fill_manual(values = c("#0072B2", "#E69F00")) +
  ggplot2::labs(
    title = "C. Why patent output falls",
    subtitle = "Exact Shapley decomposition of the -0.053 annual point estimate",
    x = NULL, y = "Contribution to patents per inventor-year") +
  ggplot2::theme_minimal(base_size = 12)

png_path <- file.path(OUT_DIR, "quantity_supervisor_summary.png")
message("Rendering PNG")
grDevices::png(png_path, width = 1800, height = 2100, res = 180)
gridExtra::grid.arrange(
  p_dynamic, p_placebo, p_margin, ncol = 1,
  top = grid::textGrob(
    "Acquisitions and inventor patenting: main quantity result",
    gp = grid::gpar(fontsize = 18, fontface = "bold")))
grDevices::dev.off()

pdf_path <- file.path(OUT_DIR, "quantity_supervisor_summary.pdf")
message("Rendering PDF")
grDevices::pdf(pdf_path, width = 10, height = 12)
gridExtra::grid.arrange(
  p_dynamic, p_placebo, p_margin, ncol = 1,
  top = grid::textGrob(
    "Acquisitions and inventor patenting: main quantity result",
    gp = grid::gpar(fontsize = 18, fontface = "bold")))
grDevices::dev.off()

source_files <- c(
  file.path(BASE, "R", "25a_build_lmv2_quantity_communication_package.R"),
  file.path(
    BASE, "notes", "local_match_v2_quantity_closeout_amendment.md"),
  path(
    "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_headline_post_att.csv"),
  path(
    "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_event_study_dynamic.csv"),
  path(
    "P6_PACKAGE1_LOYO_GRID", "package1_loyo_heldout_placebos.csv"),
  path(
    "P6_PACKAGE1_ESTIMATION_LOYO_M2", "p6_headline_post_att.csv"),
  path(
    "P6_P5C_ESTIMATION_LOYO_M3", "p6_headline_post_att.csv"),
  path(
    "P6_P5C_ESTIMATION_LOYO_M4", "p6_headline_post_att.csv"),
  path(
    "P6_PACKAGE1_ESTIMATION_LOYO_M5", "p6_headline_post_att.csv"),
  path(
    "P6_PACKAGE1D_MEAN_REVERSION", "package1d_loyo_m1_heldout.csv"),
  path(
    "P6_PACKAGE1D_ESTIMATION_LOYO_M1", "p6_headline_post_att.csv"),
  path(
    "P6_VERGINER_EARLY_RECRUITMENT_STRICT_FEASIBLE",
    "verginer_p6_headline.csv"),
  path(
    "P6_VERGINER_EARLY_RECRUITMENT", "verginer_p6_headline.csv"))
source_manifest <- data.frame(
  path = normalizePath(source_files, winslash = "/", mustWork = TRUE),
  sha256 = vapply(
    source_files, digest::digest, character(1),
    algo = "sha256", file = TRUE),
  stringsAsFactors = FALSE)
utils::write.csv(
  source_manifest,
  file.path(OUT_DIR, "quantity_source_manifest.csv"),
  row.names = FALSE)

certification <- data.frame(
  check = c(
    "numeric_guard_tooth_test_fired",
    "direct_patent_att_matches_certified_estimate",
    "direct_active_att_matches_certified_estimate",
    "margin_decomposition_sums_to_patent_att",
    "five_heldout_years_present",
    "appendix_rows_are_unique",
    "supervisor_png_exists",
    "supervisor_pdf_exists"),
  pass = c(
    guard_fired,
    abs(delta_patent - main_annual$estimate) <= 1e-8,
    abs(delta_active - active_annual$estimate) <= 1e-8,
    abs(extensive_component + intensive_component - delta_patent) <= 1e-12,
    identical(all_placebos$held_out_event_time, -5:-1),
    !anyDuplicated(
      results_appendix[
        , c("design", "sample", "effect_scale")]),
    file.exists(png_path),
    file.exists(pdf_path)),
  stringsAsFactors = FALSE)
utils::write.csv(
  certification,
  file.path(OUT_DIR, "quantity_package_certification.csv"),
  row.names = FALSE)
if (!all(certification$pass)) {
  stop(
    "Quantity communication package failed: ",
    paste(certification$check[!certification$pass], collapse = ", "))
}

message(
  "Quantity communication package complete: ",
  normalizePath(OUT_DIR, winslash = "/", mustWork = TRUE))
message(
  "Headline ATT = ", sprintf("%.4f", main_annual$estimate),
  "; LOYO sign breakdown = ", sprintf("%.2f", breakdown_multiple),
  "x; extensive share = ",
  sprintf("%.1f%%", 100 * margin_decomposition$share_of_total_decline[1]))
