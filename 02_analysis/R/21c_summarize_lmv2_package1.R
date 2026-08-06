# ============================================================================
# Package 1: summarize the four-arm LOYO grid and valid timing placebo
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

AMEND_ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
AUDIT_ROOT <- file.path(AMEND_ROOT, "ROBUSTNESS_RELEASE_1993")
OUT_DIR <- file.path(AUDIT_ROOT, "P6_PACKAGE1_LOYO_GRID")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_package1_preperiod_freeze.md")

paths <- c(
  count_active = file.path(AMEND_ROOT, "P6_ESTIMATION_PRIMARY"),
  loyo_m2 = file.path(AUDIT_ROOT, "P6_PACKAGE1_ESTIMATION_LOYO_M2"),
  loyo_m3 = file.path(AUDIT_ROOT, "P6_PACKAGE1_ESTIMATION_LOYO_M3"),
  loyo_m4 = file.path(AUDIT_ROOT, "P6_PACKAGE1_ESTIMATION_LOYO_M4"),
  loyo_m5 = file.path(AUDIT_ROOT, "P6_PACKAGE1_ESTIMATION_LOYO_M5"))
required_files <- c(
  "p6_event_study_dynamic.csv",
  "p6_headline_post_att.csv",
  "p6_estimation_manifest.csv",
  "p6_estimation_certification_manifest.csv")
for (design in names(paths)) {
  missing <- required_files[
    !file.exists(file.path(paths[[design]], required_files))]
  if (length(missing)) {
    stop(
      "Missing Package 1 estimate for ", design, ": ",
      paste(missing, collapse = ", "))
  }
  cert <- utils::read.csv(
    file.path(
      paths[[design]], "p6_estimation_certification_manifest.csv"),
    stringsAsFactors = FALSE)
  if (nrow(cert) != 1L || cert$n_failed != 0) {
    stop("Estimation certification failed for ", design)
  }
}

read_design <- function(file) {
  pieces <- lapply(names(paths), function(design) {
    x <- utils::read.csv(
      file.path(paths[[design]], file),
      stringsAsFactors = FALSE)
    x$design <- design
    x
  })
  all_names <- unique(unlist(lapply(pieces, names), use.names = FALSE))
  pieces <- lapply(pieces, function(x) {
    for (name in setdiff(all_names, names(x))) x[[name]] <- NA
    x[, all_names, drop = FALSE]
  })
  do.call(rbind, pieces)
}

dynamic <- read_design("p6_event_study_dynamic.csv")
headline <- read_design("p6_headline_post_att.csv")

placebo_spec <- data.frame(
  design = c("loyo_m5", "loyo_m4", "loyo_m3", "loyo_m2"),
  held_out_event_time = c(-5L, -4L, -3L, -2L),
  stringsAsFactors = FALSE)
placebo <- do.call(rbind, lapply(seq_len(nrow(placebo_spec)), function(i) {
  spec <- placebo_spec[i, ]
  x <- dynamic[
    dynamic$design == spec$design &
      dynamic$outcome == "patent_count" &
      dynamic$event_time == spec$held_out_event_time &
      dynamic$inference == "two_way_deal_inventor", ,
    drop = FALSE]
  if (nrow(x) != 1L) {
    stop("Expected one amended-primary held-out row for ", spec$design)
  }
  x$held_out_event_time <- spec$held_out_event_time
  x$equivalence_margin <- 0.05
  x$p_lower <- stats::pt(
    (x$estimate + x$equivalence_margin) / x$se,
    df = x$df, lower.tail = FALSE)
  x$p_upper <- stats::pt(
    (x$estimate - x$equivalence_margin) / x$se,
    df = x$df, lower.tail = TRUE)
  x$tost_equivalent_alpha_005 <- x$p_lower < 0.05 & x$p_upper < 0.05
  crit90 <- stats::qt(0.95, df = x$df)
  x$ci90_low <- x$estimate - crit90 * x$se
  x$ci90_high <- x$estimate + crit90 * x$se
  x$ci90_inside_equivalence_margin <-
    x$ci90_low > -x$equivalence_margin &
    x$ci90_high < x$equivalence_margin
  x$ordinary_ci95_includes_zero <- x$ci_low <= 0 & x$ci_high >= 0
  x
}))
placebo <- placebo[
  , c(
    "design", "sample", "held_out_event_time",
    "estimate", "se", "df", "ci_low", "ci_high",
    "ordinary_ci95_includes_zero", "equivalence_margin",
    "ci90_low", "ci90_high", "p_lower", "p_upper",
    "tost_equivalent_alpha_005",
    "ci90_inside_equivalence_margin")]

post <- headline[
  headline$outcome == "patent_count" &
    headline$summary == "average_annual_t1_to_t5" &
    headline$governing, ,
  drop = FALSE]
if (nrow(post) != 5L) {
  stop("Expected five designs in the amended-primary post-treatment comparison")
}
baseline <- post[post$design == "count_active", c(
  "sample", "estimate", "ci_low", "ci_high")]
names(baseline)[-1] <- paste0(
  "headline_", names(baseline)[-1])
post <- merge(post, baseline, by = "sample", all.x = TRUE, sort = FALSE)
post$same_sign_as_headline <-
  sign(post$estimate) == sign(post$headline_estimate)
post$inside_headline_ci95 <-
  post$estimate >= post$headline_ci_low &
  post$estimate <= post$headline_ci_high
post$absolute_deviation_from_headline <-
  abs(post$estimate - post$headline_estimate)
post <- post[
  , c(
    "design", "sample", "estimate", "ci_low", "ci_high",
    "p_value", "inference", "same_sign_as_headline",
    "inside_headline_ci95", "absolute_deviation_from_headline",
    "headline_estimate", "headline_ci_low", "headline_ci_high")]

loyo_post <- post[post$design != "count_active", , drop = FALSE]
post_stability <- do.call(rbind, lapply(
  unique(loyo_post$sample), function(sample) {
    x <- loyo_post[loyo_post$sample == sample, ]
    data.frame(
      sample = sample,
      headline_estimate = unique(x$headline_estimate),
      minimum_loyo_estimate = min(x$estimate),
      maximum_loyo_estimate = max(x$estimate),
      loyo_range = max(x$estimate) - min(x$estimate),
      maximum_absolute_deviation =
        max(x$absolute_deviation_from_headline),
      all_same_sign = all(x$same_sign_as_headline),
      all_inside_headline_ci95 = all(x$inside_headline_ci95),
      stringsAsFactors = FALSE)
  }))

# Valid three-years-earlier pseudo-event diagnostic. The loyo_m2 arm holds out
# actual t=-2; pseudo t=+1 is therefore non-mechanical. Pseudo t=+2 maps to
# balanced actual t=-1 and is reported as a mechanical comparison.
timing_panel_dir <- file.path(
  AUDIT_ROOT, "P6_PACKAGE1_PANEL_LOYO_M2", "panel_matched")
panel_files <- sort(list.files(
  timing_panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE))
if (length(panel_files) != 18L) {
  stop("Timing-placebo panel does not contain 18 shards")
}
panel_sql <- lmv2_panel_sql(panel_files)
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=4")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")

timing_samples <- list(full_1993_2010 = 1993:2010)
timing_results <- lapply(names(timing_samples), function(sample) {
  cohorts <- timing_samples[[sample]]
  cohort_sql <- paste(cohorts, collapse = ",")
  pair_table <- paste0("package1_timing_pairs_", sample)
  influence_table <- paste0(pair_table, "_influence")
  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", pair_table))
  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", influence_table))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE %1$s AS
     SELECT
       e.roster_row_id,
       CAST(e.deal_id AS INTEGER) AS deal_id,
       CAST(e.cohort AS INTEGER) AS cohort,
       e.arm,
       CAST(e.codinv AS BIGINT) AS codinv,
       CAST(e.event_time + 3 AS INTEGER) AS event_time,
       CAST(e.event_time AS INTEGER) AS actual_event_time,
       CAST(e.weight AS DOUBLE) AS weight,
       CAST(e.patent_count-r.patent_count AS DOUBLE) AS dy
     FROM %2$s e
     JOIN %2$s r USING(roster_row_id)
     WHERE e.cohort IN (%3$s)
       AND r.event_time=-4
       AND e.event_time IN (-2,-1)",
    pair_table, panel_sql, cohort_sql))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE %1$s AS
     WITH design_mass AS (
       SELECT cohort,SUM(weight) AS treated_design_mass
       FROM %2$s
       WHERE cohort IN (%3$s) AND arm='treated' AND event_time=-4
       GROUP BY cohort
     ), design_share AS (
       SELECT cohort,
         treated_design_mass/SUM(treated_design_mass) OVER () AS q_g
       FROM design_mass
     ), arm_stats AS (
       SELECT cohort,event_time,arm,
         SUM(weight) AS observed_mass,
         SUM(weight*dy)/SUM(weight) AS mean_dy
       FROM %4$s
       GROUP BY cohort,event_time,arm
     ), eligible AS (
       SELECT cohort,event_time
       FROM arm_stats
       GROUP BY cohort,event_time
       HAVING COUNT(DISTINCT arm)=2 AND MIN(observed_mass)>0
     ), event_share AS (
       SELECT e.event_time,SUM(q.q_g) AS retained_design_share
       FROM eligible e JOIN design_share q USING(cohort)
       GROUP BY e.event_time
     )
     SELECT
       p.roster_row_id,p.deal_id,p.cohort,p.arm,p.codinv,
       p.event_time,p.actual_event_time,p.weight,p.dy,
       CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END *
         q.q_g/es.retained_design_share *
         p.weight/s.observed_mass*p.dy AS contribution,
       CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END *
         q.q_g/es.retained_design_share *
         p.weight/s.observed_mass*(p.dy-s.mean_dy) AS influence
     FROM %4$s p
     JOIN arm_stats s USING(cohort,event_time,arm)
     JOIN design_share q USING(cohort)
     JOIN eligible e USING(cohort,event_time)
     JOIN event_share es USING(event_time)",
    influence_table, panel_sql, cohort_sql, pair_table))
  estimates <- DBI::dbGetQuery(con, sprintf(
    "SELECT event_time,SUM(contribution) AS estimate,
       SUM(influence) AS influence_sum
     FROM %s GROUP BY event_time ORDER BY event_time",
    influence_table))
  if (!identical(estimates$event_time, c(1L, 2L)) ||
      max(abs(estimates$influence_sum)) > 1e-8) {
    stop("Timing-placebo influence invariant failed for ", sample)
  }
  covariance <- lmv2_two_way_covariance(
    con, influence_table, estimates$event_time)
  df <- min(covariance$n_deal, covariance$n_inventor) - 1L
  se <- sqrt(diag(covariance$two_way))
  crit <- stats::qt(0.975, df)
  out <- data.frame(
    sample = sample,
    pseudo_shift_years = -3L,
    pseudo_event_time = estimates$event_time,
    actual_event_time = estimates$event_time - 3L,
    actual_reference_event_time = -4L,
    estimate = estimates$estimate,
    se = se,
    df = df,
    ci_low = estimates$estimate - crit * se,
    ci_high = estimates$estimate + crit * se,
    p_value = 2 * stats::pt(
      -abs(estimates$estimate / se), df),
    mechanically_balanced =
      estimates$event_time - 3L == -1L,
    inference = "two_way_deal_inventor",
    stringsAsFactors = FALSE)
  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", pair_table))
  out
})
timing_placebo <- do.call(rbind, timing_results)
timing_validity <- data.frame(
  pseudo_shift_years = c(-3L, 3L),
  valid_no_effect_placebo = c(TRUE, FALSE),
  reported_role = c(
    "two uncontaminated pseudo-post contrasts",
    "construction failure; descriptive persistence only"),
  reason = c(
    "pseudo t=1,2 map to actual t=-2,-1 with actual t=-4 reference",
    "pseudo pre-period contains actual post-acquisition outcomes"),
  stringsAsFactors = FALSE)

utils::write.csv(
  placebo,
  file.path(OUT_DIR, "package1_loyo_heldout_placebos.csv"),
  row.names = FALSE, na = "")
utils::write.csv(
  post,
  file.path(OUT_DIR, "package1_loyo_post_stability.csv"),
  row.names = FALSE, na = "")
utils::write.csv(
  post_stability,
  file.path(OUT_DIR, "package1_loyo_post_stability_summary.csv"),
  row.names = FALSE, na = "")
utils::write.csv(
  timing_placebo,
  file.path(OUT_DIR, "package1_timing_placebo_minus3.csv"),
  row.names = FALSE, na = "")
utils::write.csv(
  timing_validity,
  file.path(OUT_DIR, "package1_timing_placebo_validity.csv"),
  row.names = FALSE, na = "")

source_paths <- c(
  summary = file.path(BASE, "R", "21c_summarize_lmv2_package1.R"),
  freeze = FREEZE_PATH,
  estimation_core = file.path(
    BASE, "R", "19b_lmv2_p6_estimation_core.R"))
manifest <- data.frame(
  package = "P6_PACKAGE1_LOYO_GRID",
  designs = paste(names(paths), collapse = ";"),
  placebo_rows = nrow(placebo),
  post_rows = nrow(post),
  timing_rows = nrow(timing_placebo),
  all_four_placebos_reported =
    identical(sort(unique(placebo$design)), sort(placebo_spec$design)),
  all_post_designs_reported =
    identical(sort(unique(post$design)), sort(names(paths))),
  timing_minus3_valid = timing_validity$valid_no_effect_placebo[
    timing_validity$pseudo_shift_years == -3L],
  timing_plus3_rejected = !timing_validity$valid_no_effect_placebo[
    timing_validity$pseudo_shift_years == 3L],
  freeze_sha256 = digest::digest(
    file = FREEZE_PATH, algo = "sha256"),
  source_bundle_sha256 = digest::digest(
    vapply(
      source_paths, digest::digest, character(1),
      file = TRUE, algo = "sha256"),
    algo = "sha256", serialize = TRUE),
  all_pass = nrow(placebo) == 4L && nrow(post) == 5L &&
    nrow(timing_placebo) == 2L,
  completed_at = as.character(Sys.time()),
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest,
  file.path(OUT_DIR, "package1_summary_manifest.csv"),
  row.names = FALSE, na = "")
print(manifest)
if (!manifest$all_pass) stop("Package 1 summary certification failed")

