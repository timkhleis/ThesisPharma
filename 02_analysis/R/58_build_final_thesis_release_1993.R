#!/usr/bin/env Rscript

# Build the single thesis-facing index for the amended 1993--2010 release.
# This script estimates no new treatment effects. It links certified estimates,
# diagnostics, identification gates, and the code that produced each result.

options(stringsAsFactors = FALSE, scipen = 999)

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
audit <- file.path(
  root, "02_analysis", "output", "audit",
  "local_match_v2_1993_amendment")
out_dir <- file.path(audit, "FINAL_THESIS_RELEASE_1993")
notes_dir <- file.path(root, "02_analysis", "notes")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(notes_dir, recursive = TRUE, showWarnings = FALSE)

rel <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (startsWith(path, paste0(root, "/"))) {
    substring(path, nchar(root) + 2L)
  } else path
}
path_a <- function(...) file.path(audit, ...)
path_r <- function(name) file.path(root, "02_analysis", "R", name)
read_csv <- function(path) {
  if (!file.exists(path)) stop("Missing release input: ", rel(path))
  utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}

registry <- list()
add <- function(
    section, result, population, outcome = NA_character_,
    estimate = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
    p_value = NA_real_, status, thesis_use, result_file, code_file,
    cohort_start = 1993L, cohort_end = 2010L) {
  registry[[length(registry) + 1L]] <<- data.frame(
    section = section,
    result = result,
    population = population,
    cohort_start = cohort_start,
    cohort_end = cohort_end,
    outcome = outcome,
    estimate = estimate,
    ci_low = ci_low,
    ci_high = ci_high,
    p_value = p_value,
    status = status,
    thesis_use = thesis_use,
    result_file = rel(result_file),
    code_file = rel(code_file),
    stringsAsFactors = FALSE)
}

# Main Local Match v2 estimates.
main_path <- path_a("P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv")
main <- read_csv(main_path)
main <- main[
  main$sample == "full_1993_2010" &
    main$summary == "average_annual_t1_to_t5" &
    main$inference == "deal_wild_bootstrap_t", ]
for (i in seq_len(nrow(main))) {
  causal <- if (main$outcome[i] == "tech_drift")
    "qualified: joint pretrend rejected" else "primary"
  add(
    "Main results", "Local Match v2 ATT, t=+1,...,+5",
    "Pre-deal target-inventor cohort", main$outcome[i],
    main$estimate[i], main$ci_low[i], main$ci_high[i], main$p_value[i],
    causal,
    if (main$outcome[i] == "tech_drift")
      "Report as a pretrend-qualified matched contrast; do not make a clean causal claim."
    else "Main thesis estimate with deal-cluster wild-bootstrap inference.",
    main_path, path_r("19c_run_lmv2_p6_estimation.R"))
}
main_pre_path <- path_a(
  "P6_ESTIMATION_PRIMARY", "p6_joint_pretrend_tests.csv")
main_pre <- read_csv(main_pre_path)
for (i in seq_len(nrow(main_pre))) {
  add(
    "Identification diagnostic", "Local Match joint pretreatment test",
    "Pre-deal target-inventor cohort", main_pre$outcome[i],
    p_value = main_pre$p_value[i],
    status = if (main_pre$p_value[i] > 0.1) "passes reporting threshold" else
      "pretrend rejected",
    thesis_use = paste0("Joint test over event times ", main_pre$periods[i], "."),
    result_file = main_pre_path,
    code_file = path_r("19c_run_lmv2_p6_estimation.R"))
}

# Initially retained estimates.
stayer_path <- path_a("RESULT_SUMMARY", "stayer_1993_headline.csv")
stayer <- read_csv(stayer_path)
for (i in seq_len(nrow(stayer))) {
  add(
    "Initially retained", "Initially retained matched ATT, t=+1,...,+5",
    "Initially retained inventors", stayer$outcome[i],
    stayer$estimate[i], stayer$ci_low[i], stayer$ci_high[i],
    stayer$p_value[i], "selected-population result",
    "Report with the positive-selection diagnostic and outcome-specific pretrend test.",
    stayer_path,
    if (stayer$outcome[i] %in% c("patent_count", "active_patenting"))
      path_r("28b_run_lmv2_p5b_s4_estimation.R")
    else path_r("30_run_lmv2_p5b_secondary_outcomes.R"))
}

# Short window and valid early-timing placebo.
short_path <- path_a("P6_SHORT_WINDOW_T1_T3", "short_window_headline.csv")
short <- read_csv(short_path)
short <- short[short$inference == "deal_wild_bootstrap_t", ]
for (i in seq_len(nrow(short))) {
  add(
    "Robustness", "Alternative post window, t=+1,...,+3",
    "Pre-deal target-inventor cohort", short$outcome[i],
    short$estimate[i], short$ci_low[i], short$ci_high[i], short$p_value[i],
    "completed", "Alternative-window robustness.",
    short_path, path_r("52_run_lmv2_short_window.R"))
}
placebo_path <- path_a("TIMING_PLACEBO_EARLY3", "timing_placebo_headline.csv")
placebo <- read_csv(placebo_path)
placebo <- placebo[placebo$inference == "deal_wild_bootstrap_t", ]
for (i in seq_len(nrow(placebo))) {
  add(
    "Robustness", "Treatment timing shifted three years early",
    "Pre-deal target-inventor cohort", placebo$outcome[i],
    placebo$estimate[i], placebo$ci_low[i], placebo$ci_high[i],
    placebo$p_value[i], "completed",
    "Valid pre-treatment placebo. A three-year late shift is not estimated because it uses truly treated years as pseudo-preperiods.",
    placebo_path, path_r("53_run_lmv2_timing_placebo.R"))
}

# CS(2021) companion and its restrictive never-treated robustness. Both use
# the repaired 1993 cohort and report anticipation 0 and 1 in parallel.
for (cs_dir in c("CS2021_1993_FINAL", "CS2021_1993_NEVER")) {
  cs_path <- path_a(cs_dir, "cs2021_headline.csv")
  cs_pre_path <- path_a(cs_dir, "cs2021_pretrend_tests.csv")
  cs_failure_path <- path_a(cs_dir, "cs2021_failures.csv")
  control_label <- if (cs_dir == "CS2021_1993_FINAL")
    "notyettreated" else "nevertreated"
  cs <- if (file.info(cs_path)$size > 4L) read_csv(cs_path) else data.frame(
    outcome = character(), anticipation = integer(),
    control_group = character(), post_window = character(),
    estimate = numeric(), ci_low = numeric(), ci_high = numeric(),
    p_value = numeric())
  cs_pre <- if (file.info(cs_pre_path)$size > 4L) read_csv(cs_pre_path) else
    data.frame(outcome = character(), anticipation = integer(), p_value = numeric())
  cs <- merge(
    cs, cs_pre[c("outcome", "anticipation", "p_value")],
    by = c("outcome", "anticipation"), suffixes = c("", "_pretrend"),
    all.x = TRUE)
  for (i in seq_len(nrow(cs))) {
    pre_ok <- is.finite(cs$p_value_pretrend[i]) && cs$p_value_pretrend[i] > 0.1
    add(
      "Co-equal identification", paste0(
        "CS(2021), ", cs$control_group[i], ", anticipation=",
        cs$anticipation[i], ", post window ", cs$post_window[i]),
      "Pre-deal target-inventor cohort", cs$outcome[i],
      cs$estimate[i], cs$ci_low[i], cs$ci_high[i], cs$p_value[i],
      if (pre_ok) "completed: pretrend not rejected" else
        "qualified: pretrend rejected or unavailable",
      paste0(
        "Companion estimator; pretreatment Wald p=",
        formatC(cs$p_value_pretrend[i], digits = 4, format = "f"), "."),
      cs_path, path_r("51_run_cs2021_1993.R"))
  }
  cs_failure <- read_csv(cs_failure_path)
  if (nrow(cs_failure)) {
    for (i in seq_len(nrow(cs_failure))) {
      add(
        "Co-equal identification", paste0(
          "CS(2021), ", control_label,
          ", anticipation=", cs_failure$anticipation[i],
          ", failed stage ", cs_failure$stage[i]),
        "Pre-deal target-inventor cohort", cs_failure$outcome[i],
        status = "unavailable after attempted estimation",
        thesis_use = if (control_label == "nevertreated")
          paste0(
            "Do not impute or substitute this cell. The repaired CS spine ",
            "contains zero g=0 never-treated units, so this comparison is ",
            "not identified; the failed aggregation is a downstream symptom.")
        else paste0(
          "Do not impute or substitute this cell. Estimator message: ",
          cs_failure$message[i]),
        result_file = cs_failure_path,
        code_file = path_r("51_run_cs2021_1993.R"))
    }
  }
}

# Full-cohort three-factor cessation/activity/intensity decomposition.
exit_path <- path_a("P8_EXIT_DECOMPOSITION", "exit_decomposition_components.csv")
exit <- read_csv(exit_path)
exit <- exit[
  exit$population == "full_cohort" &
    exit$sample == "headline_1993_2010", ]
for (i in seq_len(nrow(exit))) {
  add(
    "Decomposition", "Three-factor patent-count accounting decomposition",
    "Pre-deal target-inventor cohort", exit$component[i],
    exit$estimate[i], exit$ci_low[i], exit$ci_high[i], NA_real_,
    if (exit$component[i] == "total") "completed" else "accounting component",
    paste0(
      "Share of total patent-count effect: ",
      formatC(100 * exit$share_of_total[i], digits = 1, format = "f"), "%."),
    exit_path, path_r("36c_estimate_lmv2_exit_decomposition.R"))
}

# Exact two-factor extensive/intensive view of the same amended full-cohort
# effect, using the P8 cohort-event weights and factor means.
factor_path <- path_a(
  "P8_EXIT_DECOMPOSITION", "exit_decomposition_factor_means.csv")
factor <- read_csv(factor_path)
factor <- factor[
  factor$population == "full_cohort" &
    factor$sample == "headline_1993_2010" &
    factor$event_time %in% 1:5, ]
factor$wy <- factor$q_event * factor$y
factor$wa <- factor$q_event * factor$active
by_event <- stats::aggregate(
  cbind(wy, wa) ~ event_time + arm, data = factor, FUN = sum)
full_means <- stats::aggregate(cbind(wy, wa) ~ arm, data = by_event, FUN = mean)
fy_t <- full_means$wy[full_means$arm == "treated"]
fy_c <- full_means$wy[full_means$arm == "control"]
fp_t <- full_means$wa[full_means$arm == "treated"]
fp_c <- full_means$wa[full_means$arm == "control"]
fm_t <- fy_t / fp_t
fm_c <- fy_c / fp_c
full_extensive <- (fp_t - fp_c) * (fm_t + fm_c) / 2
full_intensive <- (fm_t - fm_c) * (fp_t + fp_c) / 2
full_total <- fy_t - fy_c
if (abs(full_extensive + full_intensive - full_total) > 1e-12 ||
    abs(full_total - exit$estimate[exit$component == "total"]) > 1e-8) {
  stop("Full-cohort Shapley decomposition does not reproduce the count ATT.")
}
full_decomp <- data.frame(
  population = "full_cohort", cohort = "1993_2010",
  component = c(
    "extensive_active_patenting", "intensive_patents_per_active_year", "total"),
  estimate = c(full_extensive, full_intensive, full_total),
  share_of_total = c(full_extensive / full_total, full_intensive / full_total, 1),
  treated_post_mean = c(fp_t, fm_t, fy_t),
  counterfactual_post_mean = c(fp_c, fm_c, fy_c),
  interpretation = c(
    "Order-invariant Shapley contribution of the active-patenting margin.",
    "Order-invariant Shapley contribution of patents per active inventor-year; descriptive conditioning on post-treatment activity.",
    "Certified full-cohort patent-count ATT."),
  stringsAsFactors = FALSE)
full_decomp_path <- file.path(out_dir, "fullcohort_extensive_intensive_decomposition.csv")
utils::write.csv(full_decomp, full_decomp_path, row.names = FALSE)
for (i in seq_len(nrow(full_decomp))) {
  add(
    "Decomposition", "Full-cohort two-factor Shapley decomposition",
    "Pre-deal target-inventor cohort", full_decomp$component[i],
    full_decomp$estimate[i], status = "accounting decomposition",
    thesis_use = paste0(
      full_decomp$interpretation[i], " Share: ",
      formatC(100 * full_decomp$share_of_total[i], digits = 1, format = "f"), "%."),
    result_file = full_decomp_path,
    code_file = path_r("58_build_final_thesis_release_1993.R"))
}

# Two-factor Shapley decomposition for the amended retained sample. This fills
# the cohort-1993 gap left by the earlier retained-inventor release.
mag_path <- path_a(
  "P5B_STAYER_S4_RESULTS", "reporting", "s4_primary_magnitude.csv")
mag <- read_csv(mag_path)
mag <- mag[mag$sample == "full_1993_2010", ]
count <- mag[mag$outcome == "patent_count", ]
active <- mag[mag$outcome == "active_patenting", ]
if (nrow(count) != 1L || nrow(active) != 1L) {
  stop("Retained-sample magnitude inputs are not unique.")
}
p_t <- active$observed_treated_post_mean
p_c <- active$matched_counterfactual_post_mean
y_t <- count$observed_treated_post_mean
y_c <- count$matched_counterfactual_post_mean
m_t <- y_t / p_t
m_c <- y_c / p_c
extensive <- (p_t - p_c) * (m_t + m_c) / 2
intensive <- (m_t - m_c) * (p_t + p_c) / 2
total <- y_t - y_c
if (abs(extensive + intensive - total) > 1e-12) {
  stop("Retained Shapley decomposition does not reproduce the count ATT.")
}
retained_decomp <- data.frame(
  population = "initially_retained",
  cohort = "1993_2010",
  component = c("extensive_active_patenting", "intensive_patents_per_active_year", "total"),
  estimate = c(extensive, intensive, total),
  share_of_total = c(extensive / total, intensive / total, 1),
  treated_post_mean = c(p_t, m_t, y_t),
  counterfactual_post_mean = c(p_c, m_c, y_c),
  interpretation = c(
    "Order-invariant Shapley contribution of the active-patenting margin.",
    "Order-invariant Shapley contribution of patents per active inventor-year; descriptive conditioning on post-treatment activity.",
    "Certified initially retained patent-count ATT."),
  stringsAsFactors = FALSE)
retained_decomp_path <- file.path(out_dir, "retained_extensive_intensive_decomposition.csv")
utils::write.csv(retained_decomp, retained_decomp_path, row.names = FALSE)
for (i in seq_len(nrow(retained_decomp))) {
  add(
    "Decomposition", "Retained two-factor Shapley decomposition",
    "Initially retained inventors", retained_decomp$component[i],
    retained_decomp$estimate[i], status = "accounting decomposition",
    thesis_use = paste0(
      retained_decomp$interpretation[i], " Share: ",
      formatC(100 * retained_decomp$share_of_total[i], digits = 1, format = "f"), "%."),
    result_file = retained_decomp_path,
    code_file = path_r("58_build_final_thesis_release_1993.R"))
}

# Mechanism, selection, DealSim, and network gates.
assoc_path <- path_a(
  "MECHANISM_SELECTION_DIAGNOSTICS", "techdrift_quality_association.csv")
assoc <- read_csv(assoc_path)
for (i in seq_len(nrow(assoc))) {
  add(
    "Mechanism diagnostic", "TechDrift-quality within-retained association",
    "Initially retained inventor-years", assoc$outcome[i],
    assoc$estimate[i], assoc$ci_low[i], assoc$ci_high[i], assoc$p_value[i],
    "association only", "Deal- and event-time-FE association; not an ATT.",
    assoc_path, path_r("54_run_lmv2_mechanism_selection.R"))
}
age_path <- path_a(
  "MECHANISM_SELECTION_DIAGNOSTICS", "management_transition_summary.csv")
add(
  "Classification diagnostic", "T_NO_POST_5Y career-age comparison",
  "Retained, leaver, and no-post classifications", status = "completed",
  thesis_use = "No-post inventors are younger on average; the management-transition explanation is not supported.",
  result_file = age_path, code_file = path_r("54_run_lmv2_mechanism_selection.R"))

deal_path <- path_a(
  "DEALSIM_EXPLORATORY_POSTGATE", "dealsim_tercile_exploratory.csv")
deal <- read_csv(deal_path)
for (i in seq_len(nrow(deal))) {
  add(
    "DealSim", paste0("Exploratory DealSim tercile: ", deal$tercile[i]),
    "Deals with non-placeholder acquirer portfolio", deal$outcome[i],
    deal$estimate[i], deal$ci_low[i], deal$ci_high[i], NA_real_,
    "exploratory after failed prospective power gate",
    "Appendix/descriptive only; no confirmatory p-value and no inverted-U claim.",
    deal_path, path_r("55_run_dealsim_exploratory.R"))
}
network_path <- path_a("NETWORK_N0_CENSUS", "network_n0_path_decision.csv")
add(
  "Team disruption", "Persistent pre-deal tie support census",
  "Treated and control focal inventors", status = "support gate failed",
  thesis_use = "Path Q closes after N0: post-treatment network effects are not estimated.",
  result_file = network_path, code_file = path_r("56_run_lmv2_network_census.R"))
bounds_path <- path_a("SELECTION_BOUNDS_DECISION", "selection_bounds_decision.csv")
add(
  "Selection", "Lee-bounds identification decision",
  "Initially retained inventors", status = "not identified under defensible assumptions",
  thesis_use = "Do not report ordinary Lee bounds; report observed selection contrasts and their direction instead.",
  result_file = bounds_path, code_file = path_r("57_certify_selection_bounds_decision.R"))

# Link the broad robustness release rather than duplicate every appendix row.
robust_path <- path_a(
  "ROBUSTNESS_RELEASE_1993", "FINAL_RELEASE", "robustness_results_ordinary_p.csv")
add(
  "Robustness", "Full robustness battery",
  "Pre-deal target-inventor cohort", status = "completed",
  thesis_use = "CBPS, alternative weights, donor/deal omissions, transformed outcomes, PPML, sign-flip, LODO, control placebos, and completion-year checks.",
  result_file = robust_path, code_file = path_r("49a_build_lmv2_1993_robustness_release.R"))
verginer_path <- path_a(
  "ROBUSTNESS_RELEASE_1993", "P6_VERGINER_EARLY_RECRUITMENT",
  "verginer_p6_headline.csv")
add(
  "Co-equal identification", "Verginer-style matched comparison",
  "Pre-deal target-inventor cohort", status = "completed with design-specific qualification",
  thesis_use = "Trajectory/technology matched companion design; report its certified support and pretrend diagnostics alongside the estimate.",
  result_file = verginer_path,
  code_file = path_r("24a_run_lmv2_verginer_early_recruitment_p6.R"))

registry <- do.call(rbind, registry)
registry_path <- file.path(out_dir, "final_thesis_results_registry_1993.csv")
utils::write.csv(registry, registry_path, row.names = FALSE)
utils::write.csv(
  registry,
  file.path(notes_dir, "final_thesis_results_registry_1993.csv"),
  row.names = FALSE)

# Thesis requirement matrix: this distinguishes genuinely missing work from
# analyses that were deliberately closed by a prospective identification gate.
requirements <- data.frame(
  requirement = c(
    "Full-cohort patent count and active-patenting ATT",
    "Full-cohort PQII, forward-citation, and TechDrift outcomes",
    "Initially retained quantity, quality, citations, and TechDrift",
    "Full-cohort cessation/activity/intensity decomposition",
    "Full-cohort extensive/intensive Shapley decomposition",
    "Initially retained extensive/intensive Shapley decomposition",
    "Local Match formal pretreatment tests",
    "Short post window (+1 through +3)",
    "Treatment timing shifted three years early",
    "Treatment timing shifted three years late",
    "CS(2021) not-yet-treated, anticipation 0 and 1",
    "CS(2021) never-treated robustness, anticipation 0 and 1",
    "Verginer-style matched companion design",
    "Broader weight/outcome/inference/placebo robustness battery",
    "Stayer-versus-leaver pre-deal selection comparison",
    "Lee bounds for post-treatment retention selection",
    "TechDrift-quality mechanism diagnostic",
    "T_NO_POST_5Y management-transition diagnostic",
    "DealSim tercile, quadratic, and spline patterns",
    "DealSim by deal-size regime",
    "Persistent-team-tie post-acquisition effect",
    "Inventor productivity and team heterogeneity",
    "VR and retained-inventor heterogeneity"),
  status = c(
    "built and primary",
    "built; TechDrift is pretrend-qualified",
    "built; selected-population interpretation",
    "built as accounting decomposition",
    "built as accounting decomposition",
    "built as accounting decomposition",
    "built",
    "built",
    "built and null for count/activity",
    "not identified: pseudo-preperiod overlaps true treatment",
    "attempted; available cells fail pretrend gate and one did aggregation cell is unavailable",
    "not identified: repaired CS spine contains zero g=0 never-treated units",
    "built with design-specific support qualification",
    "built",
    "built; retained inventors are positively selected on pre-deal patenting",
    "not identified under defensible maintained assumptions",
    "built as association, not ATT",
    "built; management-transition interpretation not supported",
    "built as exploratory only after failed power gate",
    "not estimated after failed DealSim power gate",
    "not estimated after failed persistent-tie support gate",
    "built for feasible cells; failed prospective cells remain appendix-only",
    "built for cells passing prospective power/balance gates"),
  thesis_action = c(
    "Main table and event study.",
    "Main/secondary table; qualify TechDrift.",
    "Retained-inventor section with selection caveat.",
    "Mechanism accounting table.",
    "Extensive/intensive table; intensive part is descriptive.",
    "Retained extensive/intensive table; intensive part is descriptive.",
    "Report p-values with outcome tables.",
    "Robustness table.",
    "Robustness table.",
    "State why it is not a valid placebo; do not estimate it.",
    "Use as failed-diagnostic evidence, not as a causal main result.",
    "State that this robustness is infeasible in the repaired CS spine; Local Match supplies the separate never-observed-target comparison.",
    "Co-equal design with its own qualification.",
    "Appendix and compact robustness table.",
    "Discuss direction of selection bias.",
    "Remove the promised numerical bounds and state the identification reason.",
    "Mechanism diagnostic only.",
    "Classification caveat: evidence points away from senior management exit.",
    "Appendix/descriptive figure; no confirmatory inverted-U claim.",
    "List as power-gated future work, not a missing regression to fill post hoc.",
    "List as support-gated future work.",
    "Report only pre-specified feasible cells and omnibus qualification.",
    "Report gate outcomes and feasible contrasts."),
  code_file = c(
    "19c_run_lmv2_p6_estimation.R", "19c_run_lmv2_p6_estimation.R",
    "30_run_lmv2_p5b_secondary_outcomes.R", "36c_estimate_lmv2_exit_decomposition.R",
    "58_build_final_thesis_release_1993.R", "58_build_final_thesis_release_1993.R",
    "19c_run_lmv2_p6_estimation.R", "52_run_lmv2_short_window.R",
    "53_run_lmv2_timing_placebo.R", "53_run_lmv2_timing_placebo.R",
    "51_run_cs2021_1993.R", "51_run_cs2021_1993.R",
    "24a_run_lmv2_verginer_early_recruitment_p6.R",
    "49a_build_lmv2_1993_robustness_release.R",
    "29a_lmv2_p5b_selection_diagnostics.R", "57_certify_selection_bounds_decision.R",
    "54_run_lmv2_mechanism_selection.R", "54_run_lmv2_mechanism_selection.R",
    "55_run_dealsim_exploratory.R", "55_run_dealsim_exploratory.R",
    "56_run_lmv2_network_census.R", "31c_estimate_lmv2_inventor_heterogeneity.R",
    "32_run_lmv2_vr_heterogeneity.R"),
  stringsAsFactors = FALSE)
requirements$code_file <- file.path("02_analysis", "R", requirements$code_file)
if (!all(file.exists(file.path(root, requirements$code_file)))) {
  stop("A thesis-requirement code link is missing.")
}
requirements_path <- file.path(out_dir, "thesis_requirements_matrix_1993.csv")
utils::write.csv(requirements, requirements_path, row.names = FALSE)
utils::write.csv(
  requirements,
  file.path(notes_dir, "thesis_requirements_matrix_1993.csv"),
  row.names = FALSE)

# Machine-readable certification. Failed empirical identification gates are
# valid completed outcomes; certification checks that they are labelled as such.
required_code <- unique(file.path(root, registry$code_file))
required_results <- unique(file.path(root, registry$result_file))
cert <- data.frame(
  check = c(
    "registry_nonempty", "all_rows_start_1993", "all_rows_end_2010",
    "all_code_files_exist", "all_result_files_exist",
    "techdrift_main_is_qualified", "dealsim_is_exploratory",
    "network_gate_failure_is_preserved", "lee_bounds_not_claimed",
    "full_decomposition_reconciles", "retained_decomposition_reconciles"),
  pass = c(
    nrow(registry) > 0L,
    all(registry$cohort_start == 1993L),
    all(registry$cohort_end == 2010L),
    all(file.exists(required_code)),
    all(file.exists(required_results)),
    all(grepl("qualified", registry$status[registry$outcome == "tech_drift" & registry$section == "Main results"])),
    all(grepl("exploratory", registry$status[registry$section == "DealSim"])),
    all(grepl("failed", registry$status[registry$section == "Team disruption"])),
    all(grepl("not identified", registry$status[registry$result == "Lee-bounds identification decision"])),
    abs(sum(full_decomp$estimate[1:2]) - full_decomp$estimate[3]) <= 1e-12,
    abs(sum(retained_decomp$estimate[1:2]) - retained_decomp$estimate[3]) <= 1e-12),
  detail = c(
    paste(nrow(registry), "linked rows"), "1993", "2010",
    paste(length(required_code), "code files"),
    paste(length(required_results), "result files"),
    "No clean causal TechDrift claim", "Prospective Path U gate retained",
    "N0 support gate retained", "No unsupported Lee bounds",
    format(abs(sum(full_decomp$estimate[1:2]) - full_decomp$estimate[3]), scientific = TRUE),
    format(abs(sum(retained_decomp$estimate[1:2]) - retained_decomp$estimate[3]), scientific = TRUE)),
  stringsAsFactors = FALSE)
cert_path <- file.path(out_dir, "final_thesis_release_certification.csv")
utils::write.csv(cert, cert_path, row.names = FALSE)
if (!all(cert$pass)) stop("Final 1993 release certification failed.")

# Concise, tracked handoff for GitHub. Paths are repository-relative links.
fmt <- function(x) ifelse(is.na(x), "", formatC(x, digits = 4, format = "f"))
main_rows <- registry[registry$section == "Main results", ]
main_lines <- vapply(seq_len(nrow(main_rows)), function(i) sprintf(
  "| %s | %s | [%s, %s] | %s | %s | [`%s`](../R/%s) |",
  main_rows$outcome[i], fmt(main_rows$estimate[i]), fmt(main_rows$ci_low[i]),
  fmt(main_rows$ci_high[i]), fmt(main_rows$p_value[i]), main_rows$status[i],
  basename(main_rows$code_file[i]), basename(main_rows$code_file[i])), character(1))
key_robust <- registry[registry$result %in% c(
  "Alternative post window, t=+1,...,+3",
  "Treatment timing shifted three years early"), ]
key_robust_lines <- vapply(seq_len(nrow(key_robust)), function(i) sprintf(
  "| %s | %s | %s | [%s, %s] | %s | [`%s`](../R/%s) |",
  key_robust$result[i], key_robust$outcome[i], fmt(key_robust$estimate[i]),
  fmt(key_robust$ci_low[i]), fmt(key_robust$ci_high[i]),
  fmt(key_robust$p_value[i]), basename(key_robust$code_file[i]),
  basename(key_robust$code_file[i])), character(1))
decomp_note <- registry[
  registry$result %in% c(
    "Full-cohort two-factor Shapley decomposition",
    "Retained two-factor Shapley decomposition") &
    registry$outcome != "total", ]
decomp_note_lines <- vapply(seq_len(nrow(decomp_note)), function(i) sprintf(
  "| %s | %s | %s | %s | [`%s`](../R/%s) |",
  decomp_note$population[i], decomp_note$outcome[i],
  fmt(decomp_note$estimate[i]), decomp_note$thesis_use[i],
  basename(decomp_note$code_file[i]), basename(decomp_note$code_file[i])),
  character(1))
coverage <- unique(registry[c("section", "result", "status", "code_file")])
coverage_lines <- vapply(seq_len(nrow(coverage)), function(i) sprintf(
  "| %s | %s | %s | [`%s`](../R/%s) |",
  coverage$section[i], coverage$result[i], coverage$status[i],
  basename(coverage$code_file[i]), basename(coverage$code_file[i])), character(1))
requirement_lines <- vapply(seq_len(nrow(requirements)), function(i) sprintf(
  "| %s | %s | %s | [`%s`](../R/%s) |",
  requirements$requirement[i], requirements$status[i],
  requirements$thesis_action[i], basename(requirements$code_file[i]),
  basename(requirements$code_file[i])), character(1))
note <- c(
  "# Final thesis results inventory: 1993--2010 cohort release",
  "", "This is the authoritative map from thesis claims to result artifacts and code.",
  "Every estimation sample starts in 1993. The complete machine-readable index is",
  "`FINAL_THESIS_RELEASE_1993/final_thesis_results_registry_1993.csv` in the audit output.",
  "", "## Main full-cohort results", "",
  "Average annual t=+1,...,+5 Local Match v2 estimates; 9,999-draw deal-wild inference.",
  "", "| Outcome | ATT | 95% CI | p | Status | Code |",
  "|---|---:|---:|---:|---|---|", main_lines,
  "", "## Key newly built robustness results", "",
  "| Specification | Outcome | ATT | 95% CI | p | Code |",
  "|---|---|---:|---:|---:|---|", key_robust_lines,
  "", "## Extensive/intensive decomposition", "",
  "| Population | Component | Contribution | Interpretation | Code |",
  "|---|---|---:|---|---|", decomp_note_lines,
  "", "## Coverage and identification status", "",
  "| Section | Result | Status | Code |", "|---|---|---|---|", coverage_lines,
  "", "## Thesis requirement matrix", "",
  "| Requirement | Build status | Thesis action | Code |",
  "|---|---|---|---|", requirement_lines,
  "", "## Required thesis qualifications", "",
  "- TechDrift rejects its Local Match joint pretrend test and is not a clean causal result.",
  "- CS(2021) is a co-equal not-yet-treated companion, but each outcome must be read with its own pretrend result.",
  "- DealSim estimates are exploratory because the prospective power gate selected Path U; they do not confirm the inverted-U hypothesis.",
  "- The persistent-team-tie census fails its frozen support threshold, so no post-treatment network effect is estimated.",
  "- Ordinary Lee bounds are not reported because defensible monotonicity/exchangeability and bounded-support conditions are not established.",
  "- The retained-inventor decomposition is an exact Shapley accounting identity; its intensive component conditions descriptively on post-treatment activity.",
  "", "## One-command refresh", "",
  "Run `Rscript 02_analysis/R/60_run_final_thesis_results_1993.R` from the thesis root after the expensive estimator artifacts exist, or add `--rebuild-new` to rerun all new packages.")
note_path <- file.path(notes_dir, "final_thesis_results_inventory_1993.md")
writeLines(note, note_path, useBytes = TRUE)

message("Final thesis release built and certified: ", out_dir)
message("Tracked inventory: ", note_path)
