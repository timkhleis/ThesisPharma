#!/usr/bin/env Rscript

# Retained-inventor robustness package.
#
# This additive runner leaves the certified P5b estimates unchanged. It
# reuses their retained roster and separately solved entropy weights to run:
#   * leave-one-pre-year-out checks for t=-5,...,-1;
#   * fractional patent counts and a three-year post window;
#   * an established-inventor sample;
#   * equal-deal aggregation;
#   * removal of the largest retained deal with weights re-solved; and
#   * a frozen-weight leave-one-deal-out influence audit.
# PPML is run by 48f against the retained panel materialized here.

options(stringsAsFactors = FALSE, scipen = 999)
args <- commandArgs(trailingOnly = TRUE)
smoke <- "--smoke" %in% args

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
runner_path <- normalizePath(
  file.path(BASE, "R", "70_run_lmv2_retained_robustness.R"),
  winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "fixest", "data.table")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

source(file.path(BASE, "R", "27a_lmv2_p5b_s3_config.R"))
source(file.path(BASE, "R", "27c_run_lmv2_p5b_s3_weights.R"))

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
OUT <- file.path(
  ROOT, "ROBUSTNESS_RELEASE_1993", "RETAINED_INVENTORS")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

write_output_csv <- function(x, name, dir = OUT) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, file.path(dir, name), row.names = FALSE, na = "")
}

config <- lmv2_p5b_s3_config()
source_dir <- config$source_dir
base_weights <- file.path(config$output_dir, "s3_primary_weights.parquet")
base_results <- file.path(
  ROOT, "P5B_STAYER_S4_RESULTS", "s4_headline_post_att.csv")
base_panel_dir <- file.path(
  ROOT, "P6_P5C_COUNT_ACTIVE", "panel_matched")
required <- c(base_weights, base_results, source_dir, base_panel_dir)
missing <- required[!file.exists(required) & !dir.exists(required)]
if (length(missing)) stop("Missing retained robustness input: ", paste(missing, collapse = ", "))

panel_files <- sort(list.files(
  base_panel_dir, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE))
panel_cohorts <- as.integer(sub(
  "^.*_c([0-9]+)\\.parquet$", "\\1", panel_files))
if (!identical(panel_cohorts, 1993:2010)) {
  stop("Expected one base panel shard for every cohort from 1993 to 2010")
}
cohorts <- if (smoke) 1993:1995 else 1993:2010

sql_paths <- function(paths) {
  paste0("[", paste(vapply(
    normalizePath(paths, winslash = "/", mustWork = TRUE),
    function(x) paste0("'", gsub("'", "''", x), "'"), character(1)),
    collapse = ","), "]")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")
temp_dir <- file.path(OUT, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory='%s'", gsub("'", "''", normalizePath(
    temp_dir, winslash = "/", mustWork = TRUE))))

DBI::dbExecute(con, sprintf(
  "CREATE OR REPLACE TEMP VIEW retained_base_panel AS
   SELECT * FROM read_parquet(%s)", sql_paths(panel_files)))
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP VIEW retained_base_units AS
  SELECT DISTINCT roster_row_id,cohort,deal_id,arm,codinv,focal_group_1
  FROM retained_base_panel WHERE event_time=-1")

safe_name <- function(x) gsub("[^A-Za-z0-9_]", "_", x)
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
    FROM weights_%1$s w
    JOIN retained_base_units b
      ON CAST(w.cohort AS INTEGER)=b.cohort
     AND CAST(w.deal_id AS BIGINT)=b.deal_id
     AND CAST(w.codinv AS BIGINT)=b.codinv
     AND b.arm='treated'
    WHERE CAST(w.treated AS INTEGER)=1
    UNION ALL
    SELECT w.final_weight,b.roster_row_id
    FROM weights_%1$s w
    JOIN retained_base_units b
      ON CAST(w.cohort AS INTEGER)=b.cohort
     AND CAST(w.deal_id AS BIGINT)=b.deal_id
     AND CAST(w.codinv AS BIGINT)=b.codinv
     AND CAST(w.control_group AS BIGINT)=b.focal_group_1
     AND b.arm='control'
    WHERE CAST(w.treated AS INTEGER)=0", id))
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP VIEW panel_%1$s AS
    SELECT p.* REPLACE(CAST(m.final_weight AS DOUBLE) AS weight)
    FROM retained_base_panel p JOIN map_%1$s m USING(roster_row_id)", id))
  check <- DBI::dbGetQuery(con, sprintf("
    WITH u AS (
      SELECT roster_row_id,COUNT(*) n,MIN(event_time) lo,MAX(event_time) hi
      FROM panel_%1$s GROUP BY roster_row_id),
    m AS (
      SELECT cohort,
        SUM(weight) FILTER(WHERE arm='treated' AND event_time=-1) tm,
        SUM(weight) FILTER(WHERE arm='control' AND event_time=-1) cm
      FROM panel_%1$s GROUP BY cohort)
    SELECT COUNT(*) units,
      COUNT(*) FILTER(WHERE n<>11 OR lo<>-5 OR hi<>5) bad_units,
      (SELECT COUNT(*) FROM m WHERE ABS(tm-cm)>1e-6) bad_masses
    FROM u", id))
  if (check$bad_units != 0L || check$bad_masses != 0L) {
    stop("Retained panel certification failed for ", id)
  }
  paste0("panel_", id)
}

primary_panel <- make_panel("primary", base_weights, parquet = TRUE)

# Materialize the certified retained panel once for the generic fractional and
# PPML runners. The conceptual roster and weights are unchanged.
materialized_dir <- file.path(OUT, "PANEL_PRIMARY")
dir.create(materialized_dir, recursive = TRUE, showWarnings = FALSE)
for (g in 1993:2010) {
  path <- file.path(materialized_dir, sprintf("lmv2_event_panel_c%d.parquet", g))
  if (!file.exists(path)) {
    DBI::dbExecute(con, sprintf(
      "COPY (SELECT * FROM %s WHERE cohort=%d ORDER BY roster_row_id,event_time)
       TO '%s' (FORMAT PARQUET,COMPRESSION ZSTD)",
      primary_panel, g, gsub("'", "''", normalizePath(
        path, winslash = "/", mustWork = FALSE))))
  }
}

fit_change <- function(panel, outcome = "patent_count", post = 1:5,
                       reference = -1L, label = "",
                       cohort_subset = cohorts) {
  if (!outcome %in% c(
      "patent_count", "active_patenting", "fractional_patent_count")) {
    stop("Unknown retained robustness outcome: ", outcome)
  }
  data <- DBI::dbGetQuery(con, sprintf("
    SELECT roster_row_id,deal_id,cohort,codinv,arm,
      MAX(weight) weight,
      AVG(CAST(%1$s AS DOUBLE)) FILTER(WHERE event_time IN (%2$s)) -
      MAX(CAST(%1$s AS DOUBLE)) FILTER(WHERE event_time=%3$d) AS delta
    FROM %4$s
    WHERE cohort IN (%5$s)
    GROUP BY roster_row_id,deal_id,cohort,codinv,arm",
    outcome, paste(post, collapse = ","), reference, panel,
    paste(cohort_subset, collapse = ",")))
  if (any(!is.finite(data$delta)) || any(!is.finite(data$weight)) ||
      any(data$weight <= 0)) stop("Invalid change data for ", label)
  data$treated <- as.integer(data$arm == "treated")
  model <- fixest::feols(
    delta ~ treated | cohort, data = data, weights = ~weight,
    cluster = ~deal_id + codinv, notes = FALSE, warn = FALSE)
  estimate <- unname(stats::coef(model)[["treated"]])
  se <- unname(fixest::se(model)[["treated"]])
  p <- unname(fixest::pvalue(model)[["treated"]])
  ci <- unname(stats::confint(model, "treated", level = 0.95))
  data.frame(
    specification = label, outcome = outcome,
    post_window = paste0(min(post), ":", max(post)),
    reference_event_time = reference, estimate = estimate,
    se = se, ci_low = ci[[1L]], ci_high = ci[[2L]], p_value = p,
    n_rows = nrow(data), n_treated = sum(data$treated),
    n_control_rows = sum(data$treated == 0L),
    n_deals = length(unique(data$deal_id[data$treated == 1L])),
    n_cohorts = length(unique(data$cohort)),
    stringsAsFactors = FALSE)
}

fit_heldout <- function(panel, held_out, outcome, label) {
  reference <- if (held_out == -1L) -4L else -1L
  row <- fit_change(
    panel, outcome = outcome, post = held_out,
    reference = reference, label = label)
  if (held_out == -1L) {
    row$estimate <- -row$estimate
    old_low <- row$ci_low
    row$ci_low <- -row$ci_high
    row$ci_high <- -old_low
  }
  row$held_out_event_time <- held_out
  row
}

baseline <- fit_change(primary_panel, label = "retained_headline")
certified <- utils::read.csv(base_results, stringsAsFactors = FALSE)
certified <- certified[
  certified$spec == "primary_count_active_scale" &
    certified$sample == "full_1993_2010" &
    certified$outcome == "patent_count" &
    certified$summary == "average_annual_t1_to_t5" &
    certified$inference == "two_way_deal_inventor", , drop = FALSE]
if (!smoke && (nrow(certified) != 1L ||
    abs(baseline$estimate - certified$estimate) > 1e-10)) {
  stop(sprintf(
    "Retained regression reconstruction %.12f does not match certified %.12f",
    baseline$estimate, certified$estimate))
}
write_output_csv(baseline, "retained_baseline_reconstruction.csv")

run_weight_package <- function(package_dir, specs, source, run_cohorts,
                               equal_deal = FALSE, require_all = TRUE) {
  cfg <- lmv2_p5b_s3_config()
  cfg$output_dir <- package_dir
  cfg$source_dir <- source
  cfg$weight_dir <- file.path(package_dir, "weights")
  cfg$balance_dir <- file.path(package_dir, "balance")
  cfg$weight_specs <- specs
  dir.create(cfg$weight_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(cfg$balance_dir, recursive = TRUE, showWarnings = FALSE)
  lmv2_p5b_load_solver(cfg)
  original_allocate <- get(
    "lmv2_ebal_allocate_deal_base_weights", envir = .GlobalEnv)
  if (equal_deal) {
    force_equal <- function(treated_rows, control_rows, scheme = "primary") {
      original_allocate(treated_rows, control_rows, scheme = "equal_deal")
    }
    assign("lmv2_ebal_allocate_deal_base_weights", force_equal,
           envir = .GlobalEnv)
  }
  on.exit(assign(
    "lmv2_ebal_allocate_deal_base_weights", original_allocate,
    envir = .GlobalEnv), add = TRUE)
  rows <- list()
  k <- 0L
  for (spec in names(specs)) {
    for (g in run_cohorts) {
      k <- k + 1L
      message("Retained robustness weights: ", spec, " cohort ", g)
      rows[[k]] <- lmv2_p5b_run_cell(cfg, spec, g)
    }
  }
  diagnostics <- do.call(rbind, rows)
  write_output_csv(diagnostics, "weight_diagnostics.csv", package_dir)
  if (require_all && any(!diagnostics$feasible)) {
    stop("At least one retained robustness weighting cell is infeasible in ",
         package_dir)
  }
  diagnostics
}

# Leave one pre-acquisition year out of the retained balancing vector.
loyo_dir <- file.path(OUT, "LOYO")
loyo_specs <- setNames(lapply(1:5, function(m) list(
  support = "primary_resolved_t1",
  omit = c(
    "firm_patent_trajectory", paste0("patent_count_m", m),
    paste0("active_patenting_m", m)))), paste0("retained_loyo_m", 1:5))
loyo_diag <- run_weight_package(
  loyo_dir, loyo_specs, source_dir, cohorts)
loyo_results <- list()
for (m in 1:5) {
  spec <- paste0("retained_loyo_m", m)
  paths <- loyo_diag$weight_path[loyo_diag$spec == spec]
  panel <- make_panel(spec, paths)
  for (outcome in c("patent_count", "active_patenting")) {
    att <- fit_change(panel, outcome, label = spec)
    att$result_type <- "five_year_att"
    att$held_out_event_time <- -m
    gap <- fit_heldout(
      panel, -m, outcome, paste0(spec, "_heldout"))
    gap$result_type <- "held_out_pre_gap"
    loyo_results[[length(loyo_results) + 1L]] <- att
    loyo_results[[length(loyo_results) + 1L]] <- gap
  }
}
loyo_results <- as.data.frame(data.table::rbindlist(
  loyo_results, fill = TRUE, use.names = TRUE))
write_output_csv(loyo_results, "retained_loyo_results.csv", loyo_dir)

# Outcome and window changes on the unchanged retained roster and weights.
alternative <- rbind(
  fit_change(
    primary_panel, "fractional_patent_count", 1:5, -1L,
    "fractional_patent_count"),
  fit_change(
    primary_panel, "patent_count", 1:3, -1L,
    "three_year_post_window"))

# Established inventors: require the early-recruitment flag in both arms,
# remove deal stacks that lose either arm, and re-solve cohort weights.
est_dir <- file.path(OUT, "ESTABLISHED_INVENTORS")
est_source <- file.path(est_dir, "support_rosters")
dir.create(est_source, recursive = TRUE, showWarnings = FALSE)
est_counts <- list()
for (g in cohorts) {
  x <- utils::read.csv(file.path(
    source_dir, sprintf("primary_resolved_t1_c%d.csv", g)),
    stringsAsFactors = FALSE, check.names = FALSE)
  x <- x[as.logical(x$established_early_recruitment), , drop = FALSE]
  t_deals <- unique(x$deal_id[x$treated == 1L])
  c_deals <- unique(x$deal_id[x$treated == 0L])
  keep_deals <- intersect(t_deals, c_deals)
  x <- x[x$deal_id %in% keep_deals, , drop = FALSE]
  utils::write.csv(x, file.path(
    est_source, sprintf("primary_resolved_t1_c%d.csv", g)),
    row.names = FALSE, na = "")
  est_counts[[length(est_counts) + 1L]] <- data.frame(
    cohort = g, treated = sum(x$treated == 1L),
    control_rows = sum(x$treated == 0L),
    deals = length(unique(x$deal_id[x$treated == 1L])))
}
write_output_csv(
  do.call(rbind, est_counts), "established_sample_counts.csv", est_dir)
est_specs <- list(established_inventors = list(
  support = "primary_resolved_t1", omit = "firm_patent_trajectory"))
est_diag <- run_weight_package(
  est_dir, est_specs, est_source, cohorts, require_all = FALSE)
est_gate <- sum(est_diag$feasible) >= if (smoke) 1L else 9L &&
  sum(est_diag$n_treated[est_diag$feasible]) >= if (smoke) 20L else 300L
if (!est_gate) {
  stop("Established-inventor retained sample failed its coverage gate")
}
est_panel <- make_panel(
  "established", est_diag$weight_path[est_diag$feasible])
alternative <- rbind(
  alternative,
  fit_change(est_panel, "patent_count", 1:5, -1L,
             "established_inventors"))

# Equal-deal estimand: each retained acquisition receives unit treated mass.
equal_dir <- file.path(OUT, "EQUAL_DEAL")
equal_specs <- list(equal_deal = list(
  support = "primary_resolved_t1", omit = "firm_patent_trajectory"))
equal_diag <- run_weight_package(
  equal_dir, equal_specs, source_dir, cohorts, equal_deal = TRUE,
  require_all = FALSE)
equal_cohorts <- equal_diag$cohort[equal_diag$feasible]
equal_gate <- length(equal_cohorts) >= if (smoke) 1L else 12L
if (!equal_gate) stop("Equal-deal retained sample failed its coverage gate")
equal_panel <- make_panel(
  "equal_deal", equal_diag$weight_path[equal_diag$feasible])
alternative <- rbind(
  alternative,
  fit_change(
    primary_panel, "patent_count", 1:5, -1L,
    "headline_same_equal_deal_cohorts", equal_cohorts),
  fit_change(
    equal_panel, "patent_count", 1:5, -1L,
    "equal_deal", equal_cohorts))

# Remove the largest retained deal and re-solve the affected cohort.
primary_support <- DBI::dbGetQuery(con, sprintf(
  "SELECT cohort,CAST(deal_id AS BIGINT) deal_id,COUNT(*) n_treated
   FROM read_csv_auto(%s, union_by_name=true)
   WHERE CAST(treated AS INTEGER)=1 GROUP BY cohort,deal_id
   ORDER BY n_treated DESC,deal_id",
  sql_paths(file.path(
    source_dir, sprintf("primary_resolved_t1_c%d.csv", cohorts)))))
largest <- primary_support[1L, , drop = FALSE]
omit_dir <- file.path(OUT, "REMOVE_LARGEST_DEAL")
omit_source <- file.path(omit_dir, "support_rosters")
dir.create(omit_source, recursive = TRUE, showWarnings = FALSE)
g <- largest$cohort[[1L]]
x <- utils::read.csv(file.path(
  source_dir, sprintf("primary_resolved_t1_c%d.csv", g)),
  stringsAsFactors = FALSE, check.names = FALSE)
x <- x[x$deal_id != largest$deal_id[[1L]], , drop = FALSE]
utils::write.csv(x, file.path(
  omit_source, sprintf("primary_resolved_t1_c%d.csv", g)),
  row.names = FALSE, na = "")
omit_specs <- list(remove_largest_deal = list(
  support = "primary_resolved_t1", omit = "firm_patent_trajectory"))
omit_diag <- run_weight_package(
  omit_dir, omit_specs, omit_source, g)

# Combine the re-solved cohort with unchanged certified weights elsewhere.
DBI::dbExecute(con, sprintf(
  "CREATE OR REPLACE TEMP VIEW weights_remove_largest_combined AS
   SELECT * FROM read_parquet('%s') WHERE CAST(cohort AS INTEGER)<>%d
   UNION ALL BY NAME
   SELECT * FROM read_csv_auto('%s')",
  gsub("'", "''", normalizePath(base_weights, winslash = "/")), g,
  gsub("'", "''", normalizePath(
    omit_diag$weight_path[[1L]], winslash = "/"))))
combined_path <- file.path(omit_dir, "remove_largest_combined.parquet")
DBI::dbExecute(con, sprintf(
  "COPY weights_remove_largest_combined TO '%s'
   (FORMAT PARQUET,COMPRESSION ZSTD)",
  gsub("'", "''", normalizePath(
    combined_path, winslash = "/", mustWork = FALSE))))
omit_panel <- make_panel(
  "remove_largest_combined", combined_path, parquet = TRUE)
alternative <- rbind(
  alternative,
  fit_change(omit_panel, "patent_count", 1:5, -1L,
             "remove_largest_deal_reweighted"))
write_output_csv(largest, "largest_retained_deal.csv", omit_dir)
write_output_csv(alternative, "retained_alternative_specifications.csv")

# Frozen-weight leave-one-deal-out audit. This deliberately does not re-solve
# entropy weights; the preceding largest-deal exercise provides that stronger
# check for the most influential retained acquisition.
delta <- DBI::dbGetQuery(con, sprintf("
  SELECT roster_row_id,deal_id,cohort,codinv,arm,MAX(weight) weight,
    AVG(CAST(patent_count AS DOUBLE)) FILTER(WHERE event_time BETWEEN 1 AND 5)-
    MAX(CAST(patent_count AS DOUBLE)) FILTER(WHERE event_time=-1) delta
  FROM %s WHERE cohort IN (%s)
  GROUP BY roster_row_id,deal_id,cohort,codinv,arm",
  primary_panel, paste(cohorts, collapse = ",")))
delta$treated <- as.integer(delta$arm == "treated")
treated_deals <- sort(unique(delta$deal_id[delta$treated == 1L]))
lodo <- lapply(treated_deals, function(deal) {
  d <- delta[delta$deal_id != deal, , drop = FALSE]
  mod <- fixest::feols(
    delta ~ treated | cohort, data = d, weights = ~weight,
    notes = FALSE, warn = FALSE)
  est <- unname(stats::coef(mod)[["treated"]])
  data.frame(
    omitted_deal_id = deal, estimate = est,
    deviation_from_headline = est - baseline$estimate,
    absolute_deviation = abs(est - baseline$estimate),
    same_sign = sign(est) == sign(baseline$estimate))
})
lodo <- do.call(rbind, lodo)
lodo <- lodo[order(-lodo$absolute_deviation), ]
lodo_summary <- data.frame(
  headline = baseline$estimate,
  minimum_lodo = min(lodo$estimate), maximum_lodo = max(lodo$estimate),
  maximum_absolute_deviation = max(lodo$absolute_deviation),
  largest_deletion_deal = lodo$omitted_deal_id[[1L]],
  all_same_sign = all(lodo$same_sign), n_deals = nrow(lodo))
write_output_csv(lodo, "retained_frozen_weight_lodo.csv")
write_output_csv(lodo_summary, "retained_frozen_weight_lodo_summary.csv")

# Bring the already-certified inference and support diagnostics into the
# retained robustness release without re-estimating or altering them.
baseline_inference <- utils::read.csv(base_results, stringsAsFactors = FALSE)
baseline_inference <- baseline_inference[
  baseline_inference$spec == "primary_count_active_scale" &
    baseline_inference$sample == "full_1993_2010" &
    baseline_inference$outcome == "patent_count" &
    baseline_inference$summary == "average_annual_t1_to_t5", ]
write_output_csv(baseline_inference, "retained_baseline_inference.csv")
support_files <- c(
  inherited_support_aggregate = "retained_inherited_support_aggregate.csv",
  retained_control_stack_support = "retained_control_stack_support.csv"
)
for (source_name in names(support_files)) {
  support_source <- file.path(
    ROOT, "INITIALLY_RETAINED_SUPPORT_CENSUS",
    paste0(source_name, ".csv")
  )
  if (file.exists(support_source)) {
    file.copy(
      support_source,
      file.path(OUT, unname(support_files[[source_name]])),
      overwrite = TRUE
    )
  }
}

certification <- data.frame(
  check = c(
    "baseline_reproduced", "all_loyo_cells_feasible",
    "loyo_balanced_covariates_within_gate", "established_cells_feasible",
    "equal_deal_cells_feasible", "largest_deal_resolve_feasible",
    "all_lodo_estimates_same_sign"),
  pass = c(
    smoke || abs(baseline$estimate - certified$estimate) <= 1e-10,
    all(loyo_diag$feasible),
    all(loyo_diag$max_smd_after <= 0.10 + 1e-8),
    est_gate, equal_gate,
    all(omit_diag$feasible), smoke || all(lodo$same_sign)),
  stringsAsFactors = FALSE)
write_output_csv(certification, "retained_robustness_certification.csv")

manifest <- data.frame(
  version = "lmv2_retained_robustness_v1",
  run_mode = if (smoke) "smoke_nonproduction" else "production",
  cohorts = paste(range(cohorts), collapse = "--"),
  baseline_att = baseline$estimate,
  retained_panel_sha256 = digest::digest(
    vapply(list.files(materialized_dir, full.names = TRUE), tools::md5sum,
           character(1)), algo = "sha256", serialize = TRUE),
  runner_sha256 = digest::digest(
    runner_path, algo = "sha256", file = TRUE),
  all_certification_pass = all(certification$pass),
  stringsAsFactors = FALSE)
write_output_csv(manifest, "retained_robustness_manifest.csv")
if (!all(certification$pass)) {
  stop("Retained robustness certification failed: ", paste(
    certification$check[!certification$pass], collapse = ", "))
}
message("Retained robustness package complete: ", OUT)
