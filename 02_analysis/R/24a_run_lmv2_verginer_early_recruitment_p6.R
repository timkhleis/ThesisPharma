# ============================================================================
# Verginer-style early-recruitment diagnostic: P6 patent-count stage
# ============================================================================
# Uses the certified inventor-only early-recruitment weights. The stronger
# pooled-firm refinements were attempted before outcomes and were infeasible;
# firm imbalance remains a reported limitation of this diagnostic.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (pkg in c(
    "DBI", "duckdb", "digest", "fixest", "fwildclusterboot",
    "dqrng", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

args <- commandArgs(trailingOnly = TRUE)
design_arg <- args[startsWith(args, "--design=")]
if (length(design_arg) > 1L) stop("--design supplied more than once")
DESIGN <- if (length(design_arg)) {
  sub("^--design=", "", design_arg[[1]])
} else {
  "inventor_only"
}
if (!DESIGN %in% c("inventor_only", "strict_feasible")) {
  stop("--design must be inventor_only or strict_feasible")
}
BOOTSTRAP_REPS <- LMV2_P6_ESTIMATION$inference$replications
P4_ROOT <- normalizePath(
  file.path(BASE, "..", "..", "lmv2-p4-ebal", "02_analysis"),
  winslash = "/", mustWork = TRUE)
WEIGHT_DIR <- file.path(
  P4_ROOT, "output", "audit", "local_match_v2",
  if (identical(DESIGN, "inventor_only")) {
    "P5D_VERGINER_EARLY_RECRUITMENT_INVENTOR_ONLY"
  } else {
    "P5D_VERGINER_EARLY_RECRUITMENT"
  })
WEIGHT_MANIFEST <- file.path(
  WEIGHT_DIR, "verginer_weight_manifest.csv")
WEIGHT_CERT <- file.path(
  WEIGHT_DIR, "verginer_certification.csv")
WEIGHT_DIAGNOSTICS <- file.path(
  WEIGHT_DIR, "verginer_cell_diagnostics.csv")
BASE_PANEL_DIR <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "P6_P5C_COUNT_ACTIVE", "panel_matched")
MAIN_RESULT_DIR <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "P6_ESTIMATION_PRIMARY")
OUT_DIR <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "ROBUSTNESS_RELEASE_1993",
  if (identical(DESIGN, "inventor_only")) {
    "P6_VERGINER_EARLY_RECRUITMENT"
  } else {
    "P6_VERGINER_EARLY_RECRUITMENT_STRICT_FEASIBLE"
  })
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
DB_PATH <- file.path(BASE, "output", "thesis_foundation.duckdb")

required <- c(
  if (identical(DESIGN, "inventor_only")) {
    c(WEIGHT_MANIFEST, WEIGHT_CERT)
  } else {
    WEIGHT_DIAGNOSTICS
  },
  DB_PATH,
  file.path(MAIN_RESULT_DIR, "p6_event_study_dynamic.csv"),
  file.path(MAIN_RESULT_DIR, "p6_headline_post_att.csv"))
if (!all(file.exists(required))) {
  stop("Missing certified Verginer or P6 input")
}
if (identical(DESIGN, "inventor_only")) {
  weight_cert <- utils::read.csv(
    WEIGHT_CERT, stringsAsFactors = FALSE)
  if (nrow(weight_cert) != 1L ||
      !isTRUE(weight_cert$all_pass[[1]]) ||
      weight_cert$variant[[1]] != "count_active_inventor_only") {
    stop("Inventor-only Verginer design is not certified")
  }
  weight_manifest <- utils::read.csv(
    WEIGHT_MANIFEST, stringsAsFactors = FALSE)
} else {
  design_diagnostics <- utils::read.csv(
    WEIGHT_DIAGNOSTICS, stringsAsFactors = FALSE)
  design_diagnostics <- design_diagnostics[
    design_diagnostics$feasible &
      design_diagnostics$max_abs_smd_after <= 0.10 + 1e-8,
    , drop = FALSE]
  if (nrow(design_diagnostics) != 13L ||
      !identical(
        as.integer(design_diagnostics$cohort),
        c(1996L, 1997L, 2000:2010)) ||
      !all(file.exists(design_diagnostics$weight_path))) {
    stop("Strict feasible-cohort set is not the expected 13 cohorts")
  }
  weight_cert <- data.frame(
    execution_hash =
      unique(design_diagnostics$execution_hash),
    variant = "strict_feasible",
    all_pass = TRUE,
    stringsAsFactors = FALSE)
  weight_manifest <- data.frame(
    execution_hash = design_diagnostics$execution_hash,
    cohort = design_diagnostics$cohort,
    path = design_diagnostics$weight_path,
    sha256 = design_diagnostics$weight_sha256,
    rows = design_diagnostics$early_recruited_treated +
      design_diagnostics$control_rows,
    stringsAsFactors = FALSE)
}
weight_manifest <- weight_manifest[order(weight_manifest$cohort), ]
COHORTS <- as.integer(weight_manifest$cohort)
if (nrow(weight_manifest) != length(COHORTS) ||
    !identical(as.integer(weight_manifest$cohort), COHORTS) ||
    !all(file.exists(weight_manifest$path))) {
  stop("Expected 16 certified Verginer weight files")
}
observed_weight_hash <- vapply(
  weight_manifest$path, digest::digest, character(1),
  file = TRUE, algo = "sha256")
if (!identical(
    unname(observed_weight_hash), weight_manifest$sha256)) {
  stop("Verginer weight checksum mismatch")
}
panel_files <- sort(list.files(
  BASE_PANEL_DIR,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE))
if (length(panel_files) != 18L) {
  stop("Expected the 18 certified count-active panel shards")
}

atomic_csv <- function(x, name) {
  path <- file.path(OUT_DIR, name)
  temp <- paste0(path, ".tmp")
  utils::write.csv(x, temp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temp, path)) stop("Could not publish ", path)
  invisible(path)
}

con <- DBI::dbConnect(
  duckdb::duckdb(), dbdir = DB_PATH, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'",
  LMV2_P6_ESTIMATION$execution$duckdb_memory_limit))
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d",
  LMV2_P6_ESTIMATION$execution$threads))
temp_dir <- file.path(OUT_DIR, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)))

base_panel_sql <- lmv2_panel_sql(panel_files)
weight_sql <- paste0(
  "read_parquet([",
  paste(
    vapply(
      weight_manifest$path,
      function(path) lmv2_sql_string(normalizePath(
        path, winslash = "/", mustWork = TRUE)),
      character(1)),
    collapse = ","),
  "])")
DBI::dbExecute(con, sprintf(
  "CREATE TEMP TABLE verginer_weights AS
   SELECT roster_row_id, cohort, treated,
          firm_log_patent_stock_5y,
          firm_log_inventor_count_5y,
          firm_patent_trajectory,
          CAST(final_weight AS DOUBLE) AS final_weight
   FROM %s",
  weight_sql))
DBI::dbExecute(con, sprintf(
  "CREATE TEMP VIEW verginer_panel AS
   SELECT p.* REPLACE (
     CAST(w.final_weight AS DOUBLE) AS weight
   )
   FROM %s p
   JOIN verginer_weights w USING(roster_row_id,cohort)",
  base_panel_sql))

input_check <- DBI::dbGetQuery(con, "
  WITH units AS (
    SELECT roster_row_id, COUNT(*) n,
           MIN(event_time) min_e, MAX(event_time) max_e,
           COUNT(DISTINCT cohort) n_cohort,
           COUNT(DISTINCT deal_id) n_deal,
           COUNT(DISTINCT arm) n_arm,
           COUNT(DISTINCT codinv) n_codinv
    FROM verginer_panel
    GROUP BY roster_row_id
  ), masses AS (
    SELECT cohort,
      SUM(weight) FILTER(arm='treated' AND event_time=-1) tm,
      SUM(weight) FILTER(arm='control' AND event_time=-1) cm
    FROM verginer_panel GROUP BY cohort
  )
  SELECT
    (SELECT COUNT(*) FROM verginer_panel) panel_rows,
    (SELECT COUNT(*) FROM units) units,
    (SELECT COUNT(*) FROM units
      WHERE n<>11 OR min_e<>-5 OR max_e<>5 OR n_cohort<>1
         OR n_deal<>1 OR n_arm<>1 OR n_codinv<>1) bad_units,
    (SELECT COUNT(*) FROM masses WHERE ABS(tm-cm)>1e-7) bad_masses,
    (SELECT COUNT(*) FROM verginer_panel
      WHERE weight IS NULL OR NOT isfinite(weight) OR weight<=0) bad_weights,
    (SELECT COUNT(*) FROM verginer_panel
      WHERE arm='treated' AND weight<>1) bad_treated_weights,
    (SELECT COUNT(DISTINCT cohort) FROM verginer_panel) cohorts,
    (SELECT COUNT(DISTINCT deal_id) FROM verginer_panel
      WHERE arm='treated') treated_deals")
expected_units <- sum(weight_manifest$rows)
input_check$pass <-
  input_check$panel_rows == expected_units * 11L &&
  input_check$units == expected_units &&
  input_check$bad_units == 0 &&
  input_check$bad_masses == 0 &&
  input_check$bad_weights == 0 &&
  input_check$bad_treated_weights == 0 &&
  input_check$cohorts == length(COHORTS) &&
  input_check$treated_deals > 1
atomic_csv(
  input_check, "verginer_p6_input_certification.csv")
if (!isTRUE(input_check$pass[[1]])) {
  stop("Verginer P6 input certification failed")
}

firm_balance <- DBI::dbGetQuery(con, "
  WITH long AS (
    SELECT treated, final_weight, variable, value
    FROM verginer_weights
    UNPIVOT (
      value FOR variable IN (
        firm_log_patent_stock_5y,
        firm_log_inventor_count_5y,
        firm_patent_trajectory
      )
    )
  ), stats AS (
    SELECT variable, STDDEV_SAMP(value) sd
    FROM long GROUP BY variable
  ), means AS (
    SELECT variable, treated,
           SUM(final_weight*value)/SUM(final_weight) weighted_mean
    FROM long GROUP BY variable,treated
  )
  SELECT
    s.variable,
    MAX(m.weighted_mean) FILTER(m.treated=1) treated_mean,
    MAX(m.weighted_mean) FILTER(m.treated=0) control_mean,
    (
      MAX(m.weighted_mean) FILTER(m.treated=1) -
      MAX(m.weighted_mean) FILTER(m.treated=0)
    ) / s.sd AS standardized_difference,
    ABS((
      MAX(m.weighted_mean) FILTER(m.treated=1) -
      MAX(m.weighted_mean) FILTER(m.treated=0)
    ) / s.sd) AS absolute_standardized_difference
  FROM stats s
  JOIN means m USING(variable)
  GROUP BY s.variable,s.sd
  ORDER BY s.variable")
atomic_csv(
  firm_balance, "verginer_pooled_firm_diagnostic.csv")

paths <- DBI::dbGetQuery(con, "
  SELECT event_time, arm,
         SUM(weight*patent_count)/SUM(weight) AS weighted_mean,
         SUM(weight) AS weight_mass,
         COUNT(*) AS rows,
         COUNT(DISTINCT codinv) AS inventors
  FROM verginer_panel
  GROUP BY event_time,arm
  ORDER BY event_time,arm")
atomic_csv(paths, "verginer_weighted_patent_paths.csv")

sample_definitions <- list(full = COHORTS)
fit_rows <- list()
for (sample_id in names(sample_definitions)) {
  cohorts <- sample_definitions[[sample_id]]
  deal_counts <- lmv2_design_deal_counts(
    con, "verginer_panel", cohorts)
  fit <- lmv2_fit_outcome(
    con = con,
    panel_sql = "verginer_panel",
    outcome = "patent_count",
    sample_id = sample_id,
    cohorts = cohorts,
    bootstrap_reps = BOOTSTRAP_REPS,
    design_deal_counts = deal_counts)
  fit_rows[[sample_id]] <- fit
  message(
    "Completed Verginer P6 patent_count: ", sample_id)
}
dynamic <- do.call(rbind, lapply(fit_rows, `[[`, "dynamic"))
pretrend <- do.call(rbind, lapply(fit_rows, `[[`, "pretrend"))
headline <- do.call(rbind, lapply(fit_rows, `[[`, "headline"))
coverage <- do.call(rbind, lapply(fit_rows, `[[`, "coverage"))
atomic_csv(dynamic, "verginer_p6_dynamic.csv")
atomic_csv(pretrend, "verginer_p6_pretrend.csv")
atomic_csv(headline, "verginer_p6_headline.csv")
atomic_csv(coverage, "verginer_p6_coverage.csv")

main_dynamic <- utils::read.csv(
  file.path(MAIN_RESULT_DIR, "p6_event_study_dynamic.csv"),
  stringsAsFactors = FALSE)
main_dynamic <- main_dynamic[
    main_dynamic$outcome == "patent_count" &
    main_dynamic$sample == "full_1993_2010",
  , drop = FALSE]
plot_dynamic <- rbind(
  transform(
    main_dynamic[c(
      "event_time", "estimate", "ci_low", "ci_high")],
    design = "P5c full cohort"),
  transform(
    dynamic[
      dynamic$sample == "full",
      c("event_time", "estimate", "ci_low", "ci_high")],
    design = if (identical(DESIGN, "inventor_only")) {
      "Early-recruited inventors"
    } else {
      "Early-recruited, strict feasible cohorts"
    }))
p_dynamic <- ggplot2::ggplot(
  plot_dynamic,
  ggplot2::aes(
    x = event_time, y = estimate,
    colour = design, fill = design)) +
  ggplot2::geom_hline(
    yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(
    xintercept = 0, colour = "grey55",
    linewidth = 0.4, linetype = 2) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = ci_low, ymax = ci_high),
    alpha = 0.12, colour = NA) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.5) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::scale_colour_manual(
    values = c(
      "P5c full cohort" = "#0072B2",
      "Early-recruited inventors" = "#D55E00",
      "Early-recruited, strict feasible cohorts" = "#009E73")) +
  ggplot2::scale_fill_manual(
    values = c(
      "P5c full cohort" = "#0072B2",
      "Early-recruited inventors" = "#D55E00",
      "Early-recruited, strict feasible cohorts" = "#009E73")) +
  ggplot2::labs(
    x = "Event time", y = "Patent-count ATT",
    colour = NULL, fill = NULL,
    title = "Patent-count ATT: full versus early-recruited cohort",
    subtitle = "Reference period t=-1; two-way deal/inventor intervals") +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank())
ggplot2::ggsave(
  file.path(OUT_DIR, "verginer_p6_att_comparison.png"),
  p_dynamic, width = 8.5, height = 5.2, dpi = 220, bg = "white")

p_paths <- ggplot2::ggplot(
  paths,
  ggplot2::aes(
    x = event_time, y = weighted_mean,
    colour = arm, linetype = arm)) +
  ggplot2::geom_vline(
    xintercept = 0, colour = "grey55",
    linewidth = 0.4, linetype = 2) +
  ggplot2::geom_line(linewidth = 0.9) +
  ggplot2::geom_point(size = 1.6) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::scale_colour_manual(
    values = c(treated = "#0072B2", control = "#D55E00")) +
  ggplot2::labs(
    x = "Event time", y = "Weighted mean patent applications",
    colour = NULL, linetype = NULL,
    title = "Early-recruited inventor patent paths",
    subtitle = "Inventors fixed by focal patent evidence at t=-7 or t=-6") +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    legend.position = "bottom",
    panel.grid.minor = ggplot2::element_blank())
ggplot2::ggsave(
  file.path(OUT_DIR, "verginer_weighted_patent_paths.png"),
  p_paths, width = 8.5, height = 5.2, dpi = 220, bg = "white")

output_paths <- c(
  "verginer_p6_input_certification.csv",
  "verginer_pooled_firm_diagnostic.csv",
  "verginer_weighted_patent_paths.csv",
  "verginer_p6_dynamic.csv",
  "verginer_p6_pretrend.csv",
  "verginer_p6_headline.csv",
  "verginer_p6_coverage.csv",
  "verginer_p6_att_comparison.png",
  "verginer_weighted_patent_paths.png")
output_paths <- file.path(OUT_DIR, output_paths)
execution_hash <- digest::digest(list(
  version = "lmv2_verginer_early_recruitment_p6_v1",
  design = DESIGN,
  p5_execution_hash = weight_cert$execution_hash[[1]],
  p5_weight_sha256 = observed_weight_hash,
  base_panel_sha256 = vapply(
    panel_files, digest::digest, character(1),
    file = TRUE, algo = "sha256"),
  estimator_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "19b_lmv2_p6_estimation_core.R"),
    algo = "sha256"),
  source_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "24a_run_lmv2_verginer_early_recruitment_p6.R"),
    algo = "sha256"),
  bootstrap_reps = BOOTSTRAP_REPS
), algo = "sha256")
certification <- data.frame(
  version = "lmv2_verginer_early_recruitment_p6_v1",
  design = DESIGN,
  execution_hash = execution_hash,
  input_pass = input_check$pass[[1]],
  output_count = length(output_paths),
  outputs_exist = all(file.exists(output_paths)),
  outputs_nonempty = all(file.info(output_paths)$size > 0),
  finite_headline = all(is.finite(
    headline$estimate[headline$summary == "average_annual_t1_to_t5"])),
  all_pass =
    input_check$pass[[1]] &&
    all(file.exists(output_paths)) &&
    all(file.info(output_paths)$size > 0) &&
    all(is.finite(
      headline$estimate[
        headline$summary == "average_annual_t1_to_t5"])),
  certified_at = as.character(Sys.time()),
  stringsAsFactors = FALSE)
atomic_csv(
  certification, "verginer_p6_certification.csv")
if (!certification$all_pass) {
  stop("Verginer P6 certification failed")
}
message(
  "Verginer early-recruitment P6 certified | hash=",
  execution_hash)
