#!/usr/bin/env Rscript

# Apply the certified P6 influence-function estimator to the retained-sample
# robustness weights solved by 70_run_lmv2_retained_robustness.R. The wild
# bootstrap is not repeated for every sensitivity; its certified baseline
# result is already part of P5b S4. All rows here use two-way deal-inventor
# clustered inference, matching the main tables.

options(stringsAsFactors = FALSE, scipen = 999)
BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c(
    "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
LMV2_P6_ESTIMATION$outcomes <- rbind(
  LMV2_P6_ESTIMATION$outcomes,
  data.frame(
    outcome = "fractional_patent_count",
    designation = "amended_appendix",
    interpretation = "inventor-team fractional patent applications",
    stringsAsFactors = FALSE))

# lmv2_fit_outcome always constructs its three inference rows. For these
# sensitivity specifications, return a placeholder wild interval and retain
# only the certified two-way analytical row. This avoids running an unused
# bootstrap 14 times.
lmv2_wild_post <- function(mod, reps) {
  estimate <- unname(stats::coef(mod)[["treated"]])
  data.frame(
    inference = "deal_wild_bootstrap_t",
    estimate = estimate, se = NA_real_, df = NA_real_,
    ci_low = estimate - 1e6, ci_high = estimate + 1e6,
    p_value = NA_real_, ci_method = "not_run_for_sensitivity",
    stringsAsFactors = FALSE)
}

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
OUT <- file.path(
  ROOT, "ROBUSTNESS_RELEASE_1993", "RETAINED_INVENTORS")
panel_dir <- file.path(OUT, "PANEL_PRIMARY")
panel_files <- sort(list.files(
  panel_dir, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE))
if (length(panel_files) != 18L) stop("Retained primary panel is incomplete")

write_csv <- function(x, name, dir = OUT) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, file.path(dir, name), row.names = FALSE, na = "")
}
sql_paths <- function(paths) {
  paste0("[", paste(vapply(
    normalizePath(paths, winslash = "/", mustWork = TRUE),
    function(x) paste0("'", gsub("'", "''", x), "'"), character(1)),
    collapse = ","), "]")
}
safe_name <- function(x) gsub("[^A-Za-z0-9_]", "_", x)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")
DBI::dbExecute(con, sprintf(
  "CREATE OR REPLACE TEMP VIEW panel_primary AS
   SELECT * FROM read_parquet(%s)", sql_paths(panel_files)))
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP VIEW retained_base_units AS
  SELECT DISTINCT roster_row_id,cohort,deal_id,arm,codinv,focal_group_1
  FROM panel_primary WHERE event_time=-1")

make_panel <- function(id, weight_paths, parquet = FALSE) {
  id <- safe_name(id)
  reader <- if (parquet) "read_parquet" else "read_csv_auto"
  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE TEMP VIEW weights_%1$s AS
     SELECT * FROM %2$s(%3$s, union_by_name=true)",
    id, reader, sql_paths(weight_paths)))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP VIEW map_%1$s AS
    SELECT w.final_weight,b.roster_row_id
    FROM weights_%1$s w JOIN retained_base_units b
      ON CAST(w.cohort AS INTEGER)=b.cohort
     AND CAST(w.deal_id AS BIGINT)=b.deal_id
     AND CAST(w.codinv AS BIGINT)=b.codinv
     AND b.arm='treated'
    WHERE CAST(w.treated AS INTEGER)=1
    UNION ALL
    SELECT w.final_weight,b.roster_row_id
    FROM weights_%1$s w JOIN retained_base_units b
      ON CAST(w.cohort AS INTEGER)=b.cohort
     AND CAST(w.deal_id AS BIGINT)=b.deal_id
     AND CAST(w.codinv AS BIGINT)=b.codinv
     AND CAST(w.control_group AS BIGINT)=b.focal_group_1
     AND b.arm='control'
    WHERE CAST(w.treated AS INTEGER)=0", id))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP VIEW panel_%1$s AS
    SELECT p.* REPLACE(CAST(m.final_weight AS DOUBLE) AS weight)
    FROM panel_primary p JOIN map_%1$s m USING(roster_row_id)", id))
  paste0("panel_", id)
}

fit_core <- function(panel, outcome, id, cohort_set = 1993:2010,
                     post_window = 1:5) {
  old_post <- LMV2_P6_ESTIMATION$post_window
  LMV2_P6_ESTIMATION$post_window <<- post_window
  on.exit(LMV2_P6_ESTIMATION$post_window <<- old_post, add = TRUE)
  counts <- lmv2_design_deal_counts(con, panel, cohort_set)
  fit <- lmv2_fit_outcome(
    con, panel, outcome, id, cohort_set, 0L, counts)
  headline <- fit$headline[
    fit$headline$inference == "two_way_deal_inventor" &
      grepl("^average_annual", fit$headline$summary), , drop = FALSE]
  if (nrow(headline) != 1L) stop("Core retained result is not unique: ", id)
  headline$specification <- id
  headline$post_window_used <- paste(post_window, collapse = ";")
  list(headline = headline, dynamic = fit$dynamic,
       pretrend = fit$pretrend, coverage = fit$coverage)
}

# LOYO weights and held-out gaps.
loyo_dir <- file.path(OUT, "LOYO")
loyo_diag <- utils::read.csv(
  file.path(loyo_dir, "weight_diagnostics.csv"), stringsAsFactors = FALSE)
loyo_headline <- list()
loyo_heldout <- list()
loyo_dynamic <- list()
for (m in 1:5) {
  spec <- paste0("retained_loyo_m", m)
  paths <- loyo_diag$weight_path[
    loyo_diag$spec == spec & loyo_diag$feasible]
  panel <- make_panel(spec, paths)
  for (outcome in c("patent_count", "active_patenting")) {
    fit <- fit_core(panel, outcome, paste0(spec, "_", outcome))
    row <- fit$headline
    row$held_out_event_time <- -m
    loyo_headline[[length(loyo_headline) + 1L]] <- row
    dynamic <- fit$dynamic
    dynamic$specification <- spec
    loyo_dynamic[[length(loyo_dynamic) + 1L]] <- dynamic
    event <- if (m == 1L) -4L else -m
    gap <- dynamic[dynamic$event_time == event, , drop = FALSE]
    if (nrow(gap) != 1L) stop("Held-out dynamic row is not unique: ", spec)
    if (m == 1L) {
      gap$estimate <- -gap$estimate
      old_low <- gap$ci_low
      gap$ci_low <- -gap$ci_high
      gap$ci_high <- -old_low
    }
    gap$p_value <- 2 * stats::pt(-abs(gap$estimate / gap$se), gap$df)
    gap$held_out_event_time <- -m
    gap$specification <- spec
    loyo_heldout[[length(loyo_heldout) + 1L]] <- gap
  }
}
loyo_headline <- do.call(rbind, loyo_headline)
loyo_heldout <- do.call(rbind, loyo_heldout)
loyo_dynamic <- do.call(rbind, loyo_dynamic)
write_csv(loyo_headline, "retained_loyo_headline_core.csv", loyo_dir)
write_csv(loyo_heldout, "retained_loyo_heldout_core.csv", loyo_dir)
write_csv(loyo_dynamic, "retained_loyo_dynamic_core.csv", loyo_dir)

# Alternative outcome, window, sample, aggregation, and influence checks.
alternative <- list()
alternative[[1L]] <- fit_core(
  "panel_primary", "fractional_patent_count",
  "fractional_patent_count")$headline
alternative[[2L]] <- fit_core(
  "panel_primary", "patent_count", "three_year_post_window",
  post_window = 1:3)$headline

est_diag <- utils::read.csv(file.path(
  OUT, "ESTABLISHED_INVENTORS", "weight_diagnostics.csv"),
  stringsAsFactors = FALSE)
est_panel <- make_panel(
  "established_core", est_diag$weight_path[est_diag$feasible])
est_cohorts <- sort(est_diag$cohort[est_diag$feasible])
alternative[[3L]] <- fit_core(
  est_panel, "patent_count", "established_inventors",
  cohort_set = est_cohorts)$headline

equal_diag <- utils::read.csv(file.path(
  OUT, "EQUAL_DEAL", "weight_diagnostics.csv"), stringsAsFactors = FALSE)
equal_panel <- make_panel(
  "equal_deal_core", equal_diag$weight_path[equal_diag$feasible])
equal_cohorts <- sort(equal_diag$cohort[equal_diag$feasible])
alternative[[4L]] <- fit_core(
  "panel_primary", "patent_count", "headline_same_equal_deal_cohorts",
  cohort_set = equal_cohorts)$headline
alternative[[5L]] <- fit_core(
  equal_panel, "patent_count", "equal_deal",
  cohort_set = equal_cohorts)$headline

combined_weights <- file.path(
  OUT, "REMOVE_LARGEST_DEAL", "remove_largest_combined.parquet")
omit_panel <- make_panel(
  "remove_largest_core", combined_weights, parquet = TRUE)
alternative[[6L]] <- fit_core(
  omit_panel, "patent_count", "remove_largest_deal_reweighted")$headline
alternative <- do.call(rbind, alternative)

# Confirm the two specifications already present in certified P5b S4.
base_results <- utils::read.csv(file.path(
  ROOT, "P5B_STAYER_S4_RESULTS", "s4_headline_post_att.csv"),
  stringsAsFactors = FALSE)
for (m in 2:3) {
  spec <- paste0("retained_loyo_m", m, "_patent_count")
  observed <- loyo_headline$estimate[loyo_headline$specification == spec]
  certified <- base_results$estimate[
    base_results$spec == paste0(
      "primary_count_active_scale_loyo_m", m) &
      base_results$sample == "full_1993_2010" &
      base_results$outcome == "patent_count" &
      base_results$summary == "average_annual_t1_to_t5" &
      base_results$inference == "two_way_deal_inventor"]
  if (length(observed) != 1L || length(certified) != 1L ||
      abs(observed - certified) > 1e-10) {
    stop("LOYO core estimator failed certified point check for m", m)
  }
}

classification_specs <- c(
  "route_consistent_count_active_scale",
  "raw_unmixed_count_active_scale",
  "timing_t2_count_active_scale")
classification <- base_results[
  base_results$spec %in% classification_specs &
    base_results$sample == "full_1993_2010" &
    base_results$outcome == "patent_count" &
    base_results$summary == "average_annual_t1_to_t5" &
    base_results$inference == "two_way_deal_inventor", , drop = FALSE]
if (nrow(classification) != length(classification_specs)) {
  stop("Certified retention-classification sensitivities are incomplete")
}
classification$specification <- c(
  route_consistent_count_active_scale = "route_consistent_retention",
  raw_unmixed_count_active_scale = "unambiguous_affiliation_only",
  timing_t2_count_active_scale = "retention_classified_from_t2"
)[classification$spec]
classification$post_window_used <- "1;2;3;4;5"
classification <- classification[names(alternative)]
alternative <- rbind(alternative, classification)
write_csv(alternative, "retained_alternative_specifications_core.csv")

certification <- data.frame(
  check = c(
    "ten_loyo_outcomes_complete", "all_loyo_estimates_finite",
    "nine_alternative_rows_complete", "all_alternative_estimates_finite",
    "certified_m2_m3_points_reproduced"),
  pass = c(
    nrow(loyo_headline) == 10L,
    all(is.finite(loyo_headline$estimate)),
    nrow(alternative) == 9L,
    all(is.finite(alternative$estimate)), TRUE),
  stringsAsFactors = FALSE)
write_csv(certification, "retained_robustness_core_certification.csv")
if (!all(certification$pass)) stop("Retained core robustness failed")
message("Retained robustness core estimation complete")
