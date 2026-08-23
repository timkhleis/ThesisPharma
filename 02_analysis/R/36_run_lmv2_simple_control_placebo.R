# ============================================================================
# Simple untreated-firm placebo
# ============================================================================
# Purpose
#   Test whether randomly labelled, never-treated U2-clean firms show a
#   spurious post-period patent-count effect when both placebo arms use the
#   same inventor recruitment rule.
#
# Scope
#   This is a preliminary falsification of the recruitment/event-time setup.
#   It does not reproduce or validate P5 matching or entropy balancing.
#
# Design
#   In every cohort and draw, sample 200 eligible firms without replacement,
#   assign 100 to placebo treatment and 100 to placebo control, recruit all
#   eligible pre-period inventors in both arms, and estimate changes relative
#   to t=-1. Firms cannot appear in two cohorts within the same draw.

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) return(default)
  sub(paste0("^--", name, "="), "", hit[[1L]])
}

db_path <- normalizePath(
  arg("db", "02_analysis/output/thesis_foundation.duckdb"),
  winslash = "/", mustWork = TRUE)
output_dir <- arg(
  "output-dir",
  paste0(
    "02_analysis/output/audit/local_match_v2_1993_amendment/",
    "SIMPLE_CONTROL_PLACEBO"
  ))
draws <- as.integer(arg("draws", "50"))
firms_per_arm <- as.integer(arg("firms-per-arm", "100"))
master_seed <- as.integer(arg("seed", "20260729"))
headline_only <- tolower(arg("headline-only", "false")) %in%
  c("true", "1", "yes")
bootstrap_reps <- as.integer(arg("bootstrap-reps", "0"))
resume <- tolower(arg("resume", "true")) %in% c("true", "1", "yes")
checkpoint_every <- as.integer(arg("checkpoint-every", "50"))
point_only <- tolower(arg("point-only", "false")) %in%
  c("true", "1", "yes")
retained_candidates_path <- arg("retained-candidates", NA_character_)
reference_results_override <- arg("reference-results", NA_character_)
retained_mode <- !is.na(retained_candidates_path)
if (retained_mode) {
  retained_candidates_path <- normalizePath(
    retained_candidates_path, winslash = "/", mustWork = TRUE)
}
if (anyNA(c(draws, firms_per_arm, master_seed)) ||
    anyNA(c(bootstrap_reps, checkpoint_every)) || draws < 1L ||
    firms_per_arm < 2L || bootstrap_reps < 0L || checkpoint_every < 1L) {
  stop(
    "draws, firms-per-arm, seed, and bootstrap-reps must be ",
    "nonnegative integers (with positive draws and firms)")
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
required_packages <- c(
  "DBI", "duckdb", "fixest", "sandwich", "digest")
if (bootstrap_reps > 0L) {
  required_packages <- c(
    required_packages, "fwildclusterboot", "dqrng")
}
for (package in required_packages) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(
  output_dir, winslash = "/", mustWork = TRUE)
con <- DBI::dbConnect(
  duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=4")
DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")

# Build the eligibility table in stages. A previous one-shot query combined
# window functions and correlated filters; a smoke test showed that DuckDB
# could silently project the inventor and firm identifiers in the wrong order.
# These small materialized stages make each identifier mapping tooth-testable.
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE simple_control_units_base AS
  SELECT DISTINCT
    CAST(cohort AS INTEGER) AS cohort,
    CAST(codinv AS BIGINT) AS codinv,
    CAST(focal_group AS BIGINT) AS id_group
  FROM lmv2_p3_inventor_general_units
  WHERE role='control'
    AND cohort BETWEEN 1993 AND 2010
    AND codinv IS NOT NULL
    AND focal_group IS NOT NULL")
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE simple_target_events AS
  SELECT DISTINCT
    CAST(target_group AS BIGINT) AS id_group,
    CAST(target_year AS INTEGER) AS event_year
  FROM deal_assignment
  WHERE target_group IS NOT NULL
  UNION
  SELECT DISTINCT
    CAST(fg.id_group AS BIGINT) AS id_group,
    CAST(da.target_year AS INTEGER) AS event_year
  FROM deal_assignment da
  JOIN deal_target_company_expanded dtc USING(deal_id)
  JOIN firm_group fg
    ON CAST(fg.compcod AS BIGINT)=dtc.target_compcod
   AND fg.year=CAST(da.target_year AS INTEGER)-1
  WHERE fg.id_group IS NOT NULL")
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE simple_acquirer_events AS
  SELECT DISTINCT
    CAST(acquirer_group AS BIGINT) AS id_group,
    CAST(target_year AS INTEGER) AS event_year
  FROM deal_assignment
  WHERE acquirer_group IS NOT NULL")
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE simple_first_treatment AS
  SELECT
    CAST(codinv AS BIGINT) AS codinv,
    MIN(CAST(cohort AS INTEGER)) AS first_treated_cohort
  FROM lmv2_treated_primary
  GROUP BY 1")
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE simple_eligible_firms AS
  SELECT DISTINCT b.cohort,b.id_group
  FROM simple_control_units_base b
  WHERE NOT EXISTS (
      SELECT 1
      FROM simple_target_events t
      WHERE t.id_group=b.id_group
        AND t.event_year<=b.cohort+5)
    AND NOT EXISTS (
      SELECT 1
      FROM simple_acquirer_events a
      WHERE a.id_group=b.id_group
        AND a.event_year BETWEEN b.cohort-5 AND b.cohort+5)")
DBI::dbExecute(con, "
  CREATE OR REPLACE TEMP TABLE simple_u2_units AS
  SELECT b.cohort,b.codinv,b.id_group
  FROM simple_control_units_base b
  JOIN simple_eligible_firms f USING(cohort,id_group)
  LEFT JOIN simple_first_treatment t
    ON t.codinv=b.codinv
   AND t.first_treated_cohort<=b.cohort+5
  WHERE t.codinv IS NULL")
if (retained_mode) {
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE simple_retained_candidates AS
    SELECT DISTINCT
      CAST(cohort AS INTEGER) cohort,
      CAST(codinv AS BIGINT) codinv,
      CAST(control_group AS BIGINT) id_group
    FROM read_parquet('%s')
    WHERE retention_window='t1_t5_primary'
      AND retention_status='initially_retained'",
    gsub("'", "''", retained_candidates_path)))
  DBI::dbExecute(con, "
    CREATE OR REPLACE TEMP TABLE simple_u2_units AS
    SELECT u.*
    FROM simple_u2_units u
    JOIN simple_retained_candidates r USING(cohort,codinv,id_group)")
}

candidate_firms <- DBI::dbGetQuery(con, "
  SELECT
    cohort,id_group,COUNT(*) AS recruited_inventors
  FROM simple_u2_units
  GROUP BY 1,2
  ORDER BY cohort,id_group")
candidate_firms$cohort <- as.integer(candidate_firms$cohort)
candidate_firms$id_group <- as.numeric(candidate_firms$id_group)
candidate_firms$recruited_inventors <-
  as.integer(candidate_firms$recruited_inventors)
candidate_size_summary <- data.frame(
  firms = nrow(candidate_firms),
  min = min(candidate_firms$recruited_inventors),
  median = stats::median(candidate_firms$recruited_inventors),
  mean = mean(candidate_firms$recruited_inventors),
  p90 = stats::quantile(
    candidate_firms$recruited_inventors, 0.90, names = FALSE),
  max = max(candidate_firms$recruited_inventors),
  stringsAsFactors = FALSE)
utils::write.csv(
  candidate_size_summary,
  file.path(output_dir, "simple_control_placebo_candidate_sizes.csv"),
  row.names = FALSE)
message(
  "Candidate firm sizes: median=",
  candidate_size_summary$median,
  ", mean=", round(candidate_size_summary$mean, 1),
  ", max=", candidate_size_summary$max)
if (candidate_size_summary$max <= 1L ||
    candidate_size_summary$mean <= 1) {
  stop(
    "Eligibility construction failed: no firm has multiple recruited ",
    "inventors")
}
identifier_audit <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) AS units,
    COUNT(DISTINCT u.codinv) AS inventors,
    COUNT(DISTINCT u.id_group) AS firms,
    COUNT(*) FILTER (WHERE b.codinv IS NULL) AS invalid_source_mappings
  FROM simple_u2_units u
  LEFT JOIN simple_control_units_base b
    USING(cohort,codinv,id_group)")
utils::write.csv(
  identifier_audit,
  file.path(output_dir, "simple_control_placebo_identifier_audit.csv"),
  row.names = FALSE)
if (identifier_audit$invalid_source_mappings > 0 ||
    identifier_audit$firms >= identifier_audit$inventors) {
  stop(
    "Identifier audit failed: inventor-to-firm mapping is inconsistent")
}
cohorts <- 1993:2010
available <- table(candidate_firms$cohort)
required <- 2L * firms_per_arm
if (any(available[as.character(cohorts)] < required)) {
  stop("At least one cohort has fewer than ", required, " eligible firms")
}

draw_assignment <- function(draw_id) {
  set.seed(master_seed + draw_id, kind = "L'Ecuyer-CMRG")
  used <- numeric()
  rows <- vector("list", length(cohorts))
  cohort_order <- sample(cohorts)
  for (g in cohort_order) {
    pool <- candidate_firms[
      candidate_firms$cohort == g &
        !candidate_firms$id_group %in% used, ,
      drop = FALSE]
    selected <- pool[sample.int(nrow(pool), required), , drop = FALSE]
    selected <- selected[sample.int(nrow(selected)), , drop = FALSE]
    selected$treated <- as.integer(seq_len(required) <= firms_per_arm)
    selected$draw_id <- draw_id
    rows[[match(g, cohorts)]] <- selected
    used <- c(used, selected$id_group)
  }
  out <- do.call(rbind, rows)
  if (length(unique(out$recruited_inventors)) == 1L &&
      length(unique(candidate_firms$recruited_inventors)) > 1L) {
    stop("Selected firms collapsed to one inventor-size value")
  }
  out[order(out$cohort, out$treated, out$id_group), ]
}

fit_delta <- function(data, bootstrap_seed = NULL) {
  firm_crv1 <- fixest::feols(
    delta ~ treated | cohort,
    data = data,
    weights = ~inventors,
    cluster = ~id_group,
    warn = FALSE, notes = FALSE)
  cohort_crv1 <- fixest::feols(
    delta ~ treated | cohort,
    data = data,
    weights = ~inventors,
    cluster = ~cohort,
    warn = FALSE, notes = FALSE)
  two_way_crv1 <- fixest::feols(
    delta ~ treated | cohort,
    data = data,
    weights = ~inventors,
    cluster = ~id_group + cohort,
    warn = FALSE, notes = FALSE)
  hc3_fit <- stats::lm(
    delta ~ treated + factor(cohort),
    data = data,
    weights = inventors)
  hc3_vcov <- sandwich::vcovHC(hc3_fit, type = "HC3")

  estimate <- unname(stats::coef(firm_crv1)[["treated"]])
  hc3_estimate <- unname(stats::coef(hc3_fit)[["treated"]])
  point_gap <- abs(estimate - hc3_estimate)
  point_tolerance <- 1e-8 * max(1, abs(estimate), abs(hc3_estimate))
  if (!is.finite(point_gap) || point_gap > point_tolerance) {
    stop(sprintf(
      paste0(
        "fixest and weighted-lm point estimates disagree: ",
        "fixest=%.17g lm=%.17g gap=%.3g tolerance=%.3g"
      ),
      estimate, hc3_estimate, point_gap, point_tolerance
    ))
  }
  firm_se <- unname(fixest::se(firm_crv1)[["treated"]])
  cohort_se <- unname(fixest::se(cohort_crv1)[["treated"]])
  two_way_se <- unname(fixest::se(two_way_crv1)[["treated"]])
  hc3_se <- sqrt(unname(hc3_vcov["treated", "treated"]))
  hc3_df <- stats::df.residual(hc3_fit)
  hc3_p <- 2 * stats::pt(-abs(estimate / hc3_se), df = hc3_df)
  wild_p <- NA_real_
  if (!is.null(bootstrap_seed) && bootstrap_reps > 0L) {
    set.seed(bootstrap_seed)
    dqrng::dqset.seed(bootstrap_seed)
    wild <- fwildclusterboot::boottest(
      firm_crv1,
      param = "treated",
      B = bootstrap_reps,
      clustid = ~cohort,
      type = "webb",
      impose_null = TRUE,
      conf_int = FALSE,
      engine = "R")
    wild_p <- as.numeric(fwildclusterboot::pval(wild))
  }
  # Conservative confirmation rule: call a draw significant only when both
  # the leverage-adjusted firm-level test and the small-cluster cohort
  # bootstrap reject. The maximum p-value implements that intersection rule.
  primary_p <- if (is.finite(wild_p)) {
    max(hc3_p, wild_p)
  } else {
    hc3_p
  }
  primary_label <- if (is.finite(wild_p)) {
    "max_p_firm_HC3_and_cohort_wild"
  } else {
    "firm_level_HC3"
  }

  data.frame(
    estimate = estimate,
    standard_error = hc3_se,
    p_value = primary_p,
    ci_low = estimate - stats::qt(0.975, hc3_df) * hc3_se,
    ci_high = estimate + stats::qt(0.975, hc3_df) * hc3_se,
    primary_inference = primary_label,
    hc3_p_value = hc3_p,
    cohort_wild_p_value = wild_p,
    firm_crv1_se = firm_se,
    firm_crv1_p_value =
      unname(fixest::pvalue(firm_crv1)[["treated"]]),
    cohort_crv1_se = cohort_se,
    cohort_crv1_p_value =
      unname(fixest::pvalue(cohort_crv1)[["treated"]]),
    two_way_crv1_se = two_way_se,
    two_way_crv1_p_value =
      unname(fixest::pvalue(two_way_crv1)[["treated"]]),
    stringsAsFactors = FALSE)
}

headline_rows <- vector("list", draws)
dynamic_rows <- vector("list", draws)
assignment_rows <- vector("list", draws)
checkpoint_dir <- file.path(output_dir, "checkpoints")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)

checkpoint_files <- function(stem) sort(list.files(
  checkpoint_dir,
  pattern = paste0("^", stem, "_[0-9]{4}_[0-9]{4}\\.csv$"),
  full.names = TRUE
))
restore_rows <- function(files, target, label) {
  if (!length(files)) return(target)
  restored <- do.call(rbind, lapply(files, utils::read.csv,
                                    stringsAsFactors = FALSE))
  if (!"draw_id" %in% names(restored) || anyDuplicated(restored$draw_id) &&
      identical(label, "headline")) {
    stop("Invalid ", label, " checkpoint shards")
  }
  for (draw_id in sort(unique(restored$draw_id))) {
    if (draw_id < 1L || draw_id > draws) next
    target[[draw_id]] <- restored[restored$draw_id == draw_id, , drop = FALSE]
  }
  target
}

fit_delta_point_only <- function(data) {
  model <- fixest::feols(
    delta ~ treated | cohort,
    data = data,
    weights = ~inventors,
    warn = FALSE, notes = FALSE)
  estimate <- unname(stats::coef(model)[["treated"]])
  data.frame(
    estimate = estimate,
    standard_error = NA_real_, p_value = NA_real_,
    ci_low = NA_real_, ci_high = NA_real_,
    primary_inference = "point_estimate_only",
    hc3_p_value = NA_real_, cohort_wild_p_value = NA_real_,
    firm_crv1_se = NA_real_, firm_crv1_p_value = NA_real_,
    cohort_crv1_se = NA_real_, cohort_crv1_p_value = NA_real_,
    two_way_crv1_se = NA_real_, two_way_crv1_p_value = NA_real_,
    stringsAsFactors = FALSE)
}

firm_headline <- NULL
if (headline_only) {
  firm_headline <- DBI::dbGetQuery(con, "
    WITH event_times AS (
      SELECT UNNEST([-1,1,2,3,4,5])::INTEGER AS event_time
    ), firm_event AS (
      SELECT u.cohort,u.id_group,e.event_time,
        COUNT(*) AS inventors,
        AVG(COALESCE(y.patent_count,0))::DOUBLE AS mean_patent_count
      FROM simple_u2_units u
      CROSS JOIN event_times e
      LEFT JOIN lmv2_p3_inventor_year_typed y
        ON y.codinv=u.codinv AND y.year=u.cohort+e.event_time
      GROUP BY 1,2,3
    ), baseline AS (
      SELECT cohort,id_group,inventors,mean_patent_count baseline
      FROM firm_event WHERE event_time=-1
    ), post AS (
      SELECT cohort,id_group,inventors,AVG(mean_patent_count) post
      FROM firm_event WHERE event_time BETWEEN 1 AND 5
      GROUP BY 1,2,3)
    SELECT p.cohort,p.id_group,p.inventors,p.post-b.baseline delta
    FROM post p JOIN baseline b USING(cohort,id_group,inventors)")
}
if (resume) {
  headline_rows <- restore_rows(
    checkpoint_files("headline"), headline_rows, "headline")
  if (!headline_only) {
    dynamic_rows <- restore_rows(
      checkpoint_files("dynamic"), dynamic_rows, "dynamic")
  }
  assignment_rows <- restore_rows(
    checkpoint_files("assignments"), assignment_rows, "assignments")
}
completed_draws <- which(!vapply(headline_rows, is.null, logical(1)))
if (length(completed_draws) &&
    !identical(completed_draws, seq_len(max(completed_draws)))) {
  stop("Headline checkpoints are not a contiguous prefix of draws")
}
if (length(completed_draws)) {
  missing_companions <- completed_draws[
    vapply(assignment_rows[completed_draws], is.null, logical(1)) |
      (!headline_only & vapply(dynamic_rows[completed_draws], is.null, logical(1)))
  ]
  if (length(missing_companions)) {
    stop("Checkpoint companion shards are missing for completed draws")
  }
  message("Resuming after placebo draw ", max(completed_draws))
}
draw_ids <- setdiff(seq_len(draws), completed_draws)
started <- Sys.time()
for (draw_id in draw_ids) {
  draw_started <- Sys.time()
  assignment <- draw_assignment(draw_id)
  if (headline_only) {
    headline_data <- merge(
      assignment[c("cohort", "id_group", "treated")],
      firm_headline,
      by = c("cohort", "id_group"), sort = FALSE)
    if (nrow(headline_data) != nrow(assignment)) {
      stop("Precomputed placebo firm outcomes failed to map")
    }
    headline <- if (point_only) {
      fit_delta_point_only(headline_data)
    } else {
      fit_delta(
        headline_data,
        bootstrap_seed = master_seed + 100000L + draw_id)
    }
  } else {
    duckdb::duckdb_register(con, "simple_assignment", assignment)
    firm_event <- DBI::dbGetQuery(con, sprintf("
    WITH event_times AS (
      SELECT UNNEST(range(-5,6))::INTEGER AS event_time
    ),
    recruited AS (
      SELECT
        a.cohort,a.id_group,a.treated,u.codinv
      FROM simple_assignment a
      JOIN simple_u2_units u USING(cohort,id_group)
    )
    SELECT
      r.cohort,r.id_group,r.treated,e.event_time,
      COUNT(*) AS inventors,
      AVG(COALESCE(y.patent_count,0))::DOUBLE AS mean_patent_count
    FROM recruited r
    CROSS JOIN event_times e
    LEFT JOIN lmv2_p3_inventor_year_typed y
      ON y.codinv=r.codinv
     AND y.year=r.cohort+e.event_time
    GROUP BY 1,2,3,4
    ORDER BY 1,2,4"))
    duckdb::duckdb_unregister(con, "simple_assignment")

    baseline <- firm_event[
      firm_event$event_time == -1L,
      c("cohort", "id_group", "treated", "inventors",
        "mean_patent_count")]
    names(baseline)[5L] <- "baseline"
    post <- stats::aggregate(
      mean_patent_count ~ cohort + id_group + treated + inventors,
      data = firm_event[firm_event$event_time %in% 1:5, ],
      FUN = mean)
    headline_data <- merge(
      post, baseline,
      by = c("cohort", "id_group", "treated", "inventors"),
      sort = FALSE)
    headline_data$delta <-
      headline_data$mean_patent_count - headline_data$baseline
    headline <- fit_delta(
      headline_data,
      bootstrap_seed = master_seed + 100000L + draw_id)
  }
  headline$draw_id <- draw_id
  headline$treated_firms <- sum(assignment$treated == 1L)
  headline$control_firms <- sum(assignment$treated == 0L)
  headline$treated_inventors <- sum(
    assignment$recruited_inventors[assignment$treated == 1L])
  headline$control_inventors <- sum(
    assignment$recruited_inventors[assignment$treated == 0L])
  headline$elapsed_seconds <- as.numeric(
    difftime(Sys.time(), draw_started, units = "secs"))
  headline_rows[[draw_id]] <- headline

  if (!headline_only) {
    dynamic <- merge(
      firm_event[firm_event$event_time != -1L, ],
      baseline,
      by = c("cohort", "id_group", "treated", "inventors"),
      sort = FALSE)
    dynamic$delta <- dynamic$mean_patent_count - dynamic$baseline
    event_rows <- lapply(
      sort(unique(dynamic$event_time)),
      function(event_time) {
        row <- fit_delta(dynamic[dynamic$event_time == event_time, ])
        row$draw_id <- draw_id
        row$event_time <- event_time
        row
      })
    dynamic_rows[[draw_id]] <- do.call(rbind, event_rows)
  }
  assignment_rows[[draw_id]] <- assignment
  if (draw_id <= 5L || draw_id %% 25L == 0L ||
      draw_id == draws) {
    message(
      "Simple placebo draw ", draw_id, "/", draws,
      ": ATT=", sprintf("%.4f", headline$estimate),
      ", p=", sprintf("%.3f", headline$p_value))
  }
  if (draw_id %% checkpoint_every == 0L || draw_id == draws) {
    block_start <- max(1L, draw_id - checkpoint_every + 1L)
    block_ids <- block_start:draw_id
    suffix <- sprintf("%04d_%04d.csv", block_start, draw_id)
    utils::write.csv(
      do.call(rbind, headline_rows[block_ids]),
      file.path(checkpoint_dir, paste0("headline_", suffix)),
      row.names = FALSE)
    utils::write.csv(
      do.call(rbind, assignment_rows[block_ids]),
      file.path(checkpoint_dir, paste0("assignments_", suffix)),
      row.names = FALSE)
    if (!headline_only) {
      utils::write.csv(
        do.call(rbind, dynamic_rows[block_ids]),
        file.path(checkpoint_dir, paste0("dynamic_", suffix)),
        row.names = FALSE)
    }
  }
}

headline <- do.call(rbind, headline_rows)
assignments <- do.call(rbind, assignment_rows)
summary <- data.frame(
  draws = nrow(headline),
  mean_placebo_att = mean(headline$estimate),
  monte_carlo_se =
    stats::sd(headline$estimate) / sqrt(nrow(headline)),
  placebo_att_sd = stats::sd(headline$estimate),
  p025 = stats::quantile(
    headline$estimate, 0.025, names = FALSE),
  p975 = stats::quantile(
    headline$estimate, 0.975, names = FALSE),
  negative_share = mean(headline$estimate < 0),
  rejection_share_5pct = mean(headline$p_value < 0.05),
  mean_treated_inventors = mean(headline$treated_inventors),
  mean_control_inventors = mean(headline$control_inventors),
  elapsed_minutes = as.numeric(
    difftime(Sys.time(), started, units = "mins")),
  stringsAsFactors = FALSE)
summary$mean_placebo_p_value <- 2 * stats::pt(
  -abs(summary$mean_placebo_att / summary$monte_carlo_se),
  df = summary$draws - 1L)
summary$hc3_rejection_share_5pct <- mean(
  headline$hc3_p_value < 0.05)
summary$cohort_wild_rejection_share_5pct <- if (
    all(is.na(headline$cohort_wild_p_value))) {
  NA_real_
} else {
  mean(headline$cohort_wild_p_value < 0.05, na.rm = TRUE)
}
reference_path <- if (!is.na(reference_results_override)) {
  normalizePath(reference_results_override, winslash = "/", mustWork = TRUE)
} else if (retained_mode) {
  file.path(
    BASE, "output", "audit", "local_match_v2_1993_amendment",
    "P5B_STAYER_S4_RESULTS", "s4_headline_post_att.csv")
} else {
  file.path(
    BASE, "output", "audit", "local_match_v2_1993_amendment",
    "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv")
}
if (!file.exists(reference_path)) {
  stop("Certified main-result inventory not found: ", reference_path)
}
reference_inventory <- utils::read.csv(
  reference_path, stringsAsFactors = FALSE)
reference_keep <-
  reference_inventory$sample == "full_1993_2010" &
  reference_inventory$outcome == "patent_count" &
  reference_inventory$summary == "average_annual_t1_to_t5" &
  reference_inventory$inference == "deal_wild_bootstrap_t"
if (retained_mode && "spec" %in% names(reference_inventory)) {
  reference_keep <- reference_keep &
    reference_inventory$spec == "primary_count_active_scale"
}
reference_row <- reference_inventory[reference_keep, , drop = FALSE]
if (nrow(reference_row) != 1L ||
    !is.finite(reference_row$estimate)) {
  stop("Certified patent-count ATT is not uniquely identified")
}
reference_att <- reference_row$estimate[[1L]]
tail_count <- sum(headline$estimate <= reference_att)
summary$certified_reference_att <- reference_att
summary$placebo_draws_at_or_below_reference <- tail_count
summary$descriptive_left_tail_probability <- tail_count / nrow(headline)
summary$descriptive_left_tail_plus_one <- (tail_count + 1) /
  (nrow(headline) + 1)

utils::write.csv(
  headline,
  file.path(output_dir, "simple_control_placebo_draws.csv"),
  row.names = FALSE)
utils::write.csv(
  summary,
  file.path(output_dir, "simple_control_placebo_summary.csv"),
  row.names = FALSE)
utils::write.csv(
  assignments,
  file.path(output_dir, "simple_control_placebo_assignments.csv"),
  row.names = FALSE)

{
  grDevices::png(
    file.path(output_dir, "simple_control_placebo_distribution.png"),
    width = 1800, height = 1100, res = 180)
  histogram <- graphics::hist(
    headline$estimate, breaks = "FD", plot = FALSE)
  bin_probability <- histogram$counts / sum(histogram$counts)
  y_ticks <- pretty(c(0, max(bin_probability)))
  graphics::plot(
    NA_real_, NA_real_,
    xlim = range(histogram$breaks),
    ylim = c(0, max(y_ticks)),
    xlab = "Average post-period placebo ATT: patents",
    ylab = "", yaxt = "n",
    main = "Random untreated-firm placebo distribution",
    sub = paste0(
      draws, " draws; bars report probability mass per bin"))
  graphics::rect(
    histogram$breaks[-length(histogram$breaks)],
    0,
    histogram$breaks[-1L],
    bin_probability,
    col = "#A9C4B4", border = "white")
  graphics::axis(
    2, at = y_ticks,
    labels = paste0(round(100 * y_ticks), "%"),
    las = 1)
  graphics::mtext(
    "Probability", side = 2, line = 3)
  graphics::abline(v = 0, col = "#777777", lty = 2, lwd = 2)
  graphics::abline(
    v = summary$mean_placebo_att, col = "#315C53", lwd = 3)
  graphics::abline(
    v = reference_att, col = "#B45F4A", lwd = 3, lty = 3)
  graphics::legend(
    "topright",
    legend = c(
      "Zero", "Mean placebo ATT",
      sprintf(
        "Certified ATT = %.4f; left-tail probability = %.2f%%",
        reference_att,
        100 * summary$descriptive_left_tail_probability)),
    col = c("#777777", "#315C53", "#B45F4A"),
    lty = c(2, 1, 3), lwd = c(2, 3, 3),
    bty = "n")
  grDevices::dev.off()
}

if (!headline_only) {
  dynamic <- do.call(rbind, dynamic_rows)
  dynamic_summary <- do.call(rbind, lapply(
    sort(unique(dynamic$event_time)),
    function(event_time) {
      x <- dynamic[dynamic$event_time == event_time, ]
      data.frame(
        event_time = event_time,
        mean_estimate = mean(x$estimate),
        p025 = stats::quantile(x$estimate, 0.025, names = FALSE),
        p975 = stats::quantile(x$estimate, 0.975, names = FALSE),
        rejection_share_5pct = mean(x$p_value < 0.05))
    }))
  dynamic_summary <- rbind(
    dynamic_summary,
    data.frame(
      event_time = -1L, mean_estimate = 0,
      p025 = 0, p975 = 0, rejection_share_5pct = NA_real_))
  dynamic_summary <- dynamic_summary[
    order(dynamic_summary$event_time), ]
  utils::write.csv(
    dynamic,
    file.path(output_dir, "simple_control_placebo_dynamic_draws.csv"),
    row.names = FALSE)
  utils::write.csv(
    dynamic_summary,
    file.path(output_dir, "simple_control_placebo_dynamic_summary.csv"),
    row.names = FALSE)
  grDevices::png(
    file.path(output_dir, "simple_control_placebo_event_study.png"),
    width = 1800, height = 1100, res = 180)
  graphics::plot(
    dynamic_summary$event_time,
    dynamic_summary$mean_estimate,
    type = "n", xlab = "Event time", ylab = "Placebo ATT: patents",
    xaxt = "n",
    main = "Random untreated-firm placebo",
    sub = paste0(
      "Mean across ", draws,
      " draws; shaded range is the 2.5th--97.5th percentile across draws"),
    ylim = range(c(dynamic_summary$p025, dynamic_summary$p975)))
  graphics::axis(
    1, at = seq.int(-5L, 5L), labels = seq.int(-5L, 5L),
    cex.axis = 0.9)
  graphics::polygon(
    c(dynamic_summary$event_time, rev(dynamic_summary$event_time)),
    c(dynamic_summary$p025, rev(dynamic_summary$p975)),
    border = NA,
    col = grDevices::adjustcolor("#A9C4B4", alpha.f = 0.45))
  graphics::lines(
    dynamic_summary$event_time,
    dynamic_summary$mean_estimate,
    type = "b", pch = 16, lwd = 2.5, col = "#315C53")
  graphics::abline(h = 0, col = "#777777", lty = 2)
  graphics::abline(v = 0, col = "#C98B45", lty = 3)
  grDevices::dev.off()
}

manifest <- data.frame(
  design = if (retained_mode) {
    "simple_symmetric_random_u2_firm_placebo_initially_retained"
  } else {
    "simple_symmetric_random_u2_firm_placebo"
  },
  cohorts = "1993-2010",
  draws = draws,
  firms_per_arm_per_cohort = firms_per_arm,
  outcome = "patent_count",
  baseline_event_time = -1L,
  post_window = "1:5",
  inference = "max_p_firm_HC3_and_cohort_wild",
  analytic_inference = "firm_level_HC3",
  conservative_inference = if (bootstrap_reps > 0L) {
    "cohort_wild_bootstrap_t_webb"
  } else {
    "not_run"
  },
  bootstrap_replications = bootstrap_reps,
  headline_only = headline_only,
  point_estimate_only = point_only,
  resume_enabled = resume,
  checkpoint_every = checkpoint_every,
  interpretation = if (retained_mode) {
    paste(
      "retained-inventor recruitment/event-time falsification;",
      "retention applied symmetrically relative to placebo cohort;",
      "not P5 validation")
  } else {
    "preliminary recruitment/event-time falsification; not P5 validation"
  },
  retained_candidates = if (retained_mode) {
    retained_candidates_path
  } else {
    NA_character_
  },
  script_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "36_run_lmv2_simple_control_placebo.R"),
    algo = "sha256"),
  database_sha256 = digest::digest(
    file = db_path, algo = "sha256"),
  reference_results_sha256 = digest::digest(
    file = reference_path, algo = "sha256"),
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest,
  file.path(output_dir, "simple_control_placebo_manifest.csv"),
  row.names = FALSE)

certification <- data.frame(
  check = c(
    "amended_cohort_grid",
    "all_draws_completed",
    "all_headline_estimates_finite",
    "amended_primary_reference_unique",
    "symmetric_arm_sizes_positive"
  ),
  pass = c(
    identical(sort(unique(assignments$cohort)), cohorts),
    nrow(headline) == draws && setequal(headline$draw_id, seq_len(draws)),
    all(is.finite(headline$estimate)),
    nrow(reference_row) == 1L && is.finite(reference_att),
    all(headline$treated_inventors > 0 & headline$control_inventors > 0)
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  certification,
  file.path(output_dir, "simple_control_placebo_certification.csv"),
  row.names = FALSE
)
if (!all(certification$pass)) {
  stop(
    "Simple control placebo certification failed: ",
    paste(certification$check[!certification$pass], collapse = ", ")
  )
}
