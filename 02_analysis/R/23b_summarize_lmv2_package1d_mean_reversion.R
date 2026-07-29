# ============================================================================
# Package 1D: mean-reversion, raw-path, decomposition, and concentration report
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
required_packages <- c(
  "DBI", "duckdb", "digest", "fixest", "fwildclusterboot",
  "dqrng", "ggplot2")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

AUDIT <- file.path(BASE, "output", "audit", "local_match_v2")
OUT_DIR <- file.path(AUDIT, "P6_PACKAGE1D_MEAN_REVERSION")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_package1d_mean_reversion_freeze.md")
DB_PATH <- file.path(BASE, "output", "thesis_foundation.duckdb")
RAW_DIR <- file.path(AUDIT, "P6_APPENDIX_RAW_DID")

panel_dirs <- c(
  count_active = file.path(AUDIT, "P6_P5C_PANEL_COUNT_ACTIVE", "panel_matched"),
  loyo_m1 = file.path(AUDIT, "P6_PACKAGE1D_PANEL_LOYO_M1", "panel_matched"),
  loyo_m2 = file.path(AUDIT, "P6_PACKAGE1_PANEL_LOYO_M2", "panel_matched"),
  loyo_m3 = file.path(AUDIT, "P6_P5C_PANEL_LOYO_M3", "panel_matched"),
  loyo_m4 = file.path(AUDIT, "P6_P5C_PANEL_LOYO_M4", "panel_matched"),
  loyo_m5 = file.path(AUDIT, "P6_PACKAGE1_PANEL_LOYO_M5", "panel_matched"))
required_files <- c(
  FREEZE_PATH, DB_PATH,
  file.path(RAW_DIR, "raw_did_dynamic_estimates.csv"),
  file.path(RAW_DIR, "raw_did_joint_pretrend.csv"),
  file.path(RAW_DIR, "raw_did_post_att.csv"),
  file.path(RAW_DIR, "raw_did_standardized_mean_paths.csv"),
  file.path(OUT_DIR, "package1d_p6_run_manifest.csv"))
if (!all(dir.exists(panel_dirs)) || !all(file.exists(required_files))) {
  stop("Package 1D diagnostic input is missing")
}
panel_files <- lapply(panel_dirs, function(path) {
  out <- sort(list.files(
    path, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
    full.names = TRUE))
  if (length(out) != 17L) stop("Expected 17 panel shards in ", path)
  out
})

write_csv <- function(x, name) {
  path <- file.path(OUT_DIR, name)
  temp <- paste0(path, ".tmp")
  utils::write.csv(x, temp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temp, path)) stop("Could not publish ", path)
  invisible(path)
}

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = DB_PATH, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'",
  LMV2_P6_ESTIMATION$execution$duckdb_memory_limit))
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", LMV2_P6_ESTIMATION$execution$threads))
temp_dir <- file.path(OUT_DIR, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)))

custom_pair_table <- function(panel_sql, reference, tag, cohorts) {
  table_name <- paste0("package1d_pairs_", tag)
  cohort_sql <- paste(as.integer(cohorts), collapse = ",")
  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", table_name))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE %1$s AS
     SELECT
       e.roster_row_id,
       CAST(e.deal_id AS INTEGER) AS deal_id,
       CAST(e.cohort AS INTEGER) AS cohort,
       e.arm,
       CAST(e.codinv AS BIGINT) AS codinv,
       CAST(e.event_time AS INTEGER) AS event_time,
       CAST(e.weight AS DOUBLE) AS weight,
       CAST(e.patent_count-r.patent_count AS DOUBLE) AS dy
     FROM %2$s e
     JOIN %2$s r USING(roster_row_id)
     WHERE e.cohort IN (%3$s)
       AND r.event_time=%4$d
       AND e.event_time<>%4$d",
    table_name, panel_sql, cohort_sql, as.integer(reference)))
  table_name
}

fit_reference <- function(design, reference, sample, cohorts) {
  panel_sql <- lmv2_panel_sql(panel_files[[design]])
  tag <- paste(design, sub("[^0-9]", "", as.character(reference)),
               sample, sep = "_")
  pair <- custom_pair_table(panel_sql, reference, tag, cohorts)
  influence <- lmv2_prepare_influence_table(con, pair, panel_sql, cohorts)
  estimates <- DBI::dbGetQuery(con, sprintf(
    "SELECT event_time, SUM(contribution) AS estimate,
            SUM(influence) AS influence_sum
     FROM %s GROUP BY event_time ORDER BY event_time", influence))
  expected <- as.integer(setdiff(-5:5, reference))
  if (!identical(estimates$event_time, expected) ||
      max(abs(estimates$influence_sum)) > 1e-8) {
    stop("Custom-reference estimate invariant failed: ", tag)
  }
  covariance <- lmv2_two_way_covariance(
    con, influence, estimates$event_time)
  df <- min(covariance$n_deal, covariance$n_inventor) - 1L
  critical <- stats::qt(0.975, df)
  se <- sqrt(diag(covariance$two_way))
  dynamic <- data.frame(
    design = design, sample = sample, reference_event_time = reference,
    event_time = estimates$event_time, estimate = estimates$estimate,
    se = se, df = df,
    ci_low = estimates$estimate - critical * se,
    ci_high = estimates$estimate + critical * se,
    inference = "two_way_deal_inventor",
    stringsAsFactors = FALSE)
  dynamic <- rbind(dynamic, data.frame(
    design = design, sample = sample, reference_event_time = reference,
    event_time = reference, estimate = 0, se = 0, df = df,
    ci_low = 0, ci_high = 0, inference = "reference_period",
    stringsAsFactors = FALSE))
  dynamic <- dynamic[order(dynamic$event_time), ]

  post_index <- match(1:5, estimates$event_time)
  expected_post <- mean(estimates$estimate[post_index])
  compact <- lmv2_compact_post_regression(con, influence, expected_post)
  wild <- lmv2_wild_post(
    compact$model, LMV2_P6_ESTIMATION$inference$replications)
  two_way <- lmv2_cluster_post(
    estimates, covariance, "two_way", "two_way_deal_inventor")
  deal <- lmv2_cluster_post(
    estimates, covariance, "deal", "deal_cluster_robust")
  post <- rbind(wild, two_way, deal)
  post$design <- design
  post$sample <- sample
  post$reference_event_time <- reference
  post$summary <- "average_annual_t1_to_t5"
  post$bootstrap_replications <- c(
    LMV2_P6_ESTIMATION$inference$replications, NA, NA)

  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", pair))
  list(dynamic = dynamic, post = post)
}

reference_specs <- data.frame(
  design = c("loyo_m4", "loyo_m5", "loyo_m1"),
  reference = c(-4L, -5L, -4L),
  stringsAsFactors = FALSE)
samples <- list(full_1994_2010 = 1994:2010, buffered_1994_2008 = 1994:2008)
reference_results <- list()
index <- 0L
for (i in seq_len(nrow(reference_specs))) {
  for (sample in names(samples)) {
    index <- index + 1L
    message(
      "Package 1D reference fit: ", reference_specs$design[[i]],
      " / ", sample, " / ref ", reference_specs$reference[[i]])
    reference_results[[index]] <- fit_reference(
      reference_specs$design[[i]], reference_specs$reference[[i]],
      sample, samples[[sample]])
  }
}
reference_dynamic <- do.call(
  rbind, lapply(reference_results, `[[`, "dynamic"))
reference_post <- do.call(
  rbind, lapply(reference_results, `[[`, "post"))
write_csv(reference_dynamic, "package1d_reference_dynamic.csv")
write_csv(reference_post, "package1d_reference_post_att.csv")

m1_heldout <- reference_dynamic[
  reference_dynamic$design == "loyo_m1" &
    reference_dynamic$event_time == -1 &
    reference_dynamic$inference == "two_way_deal_inventor", ,
  drop = FALSE]
if (nrow(m1_heldout) != 2L) stop("Missing loyo_m1 held-out estimates")
write_csv(m1_heldout, "package1d_loyo_m1_heldout.csv")

matched_mean_path <- function(design) {
  panel_sql <- lmv2_panel_sql(panel_files[[design]])
  out <- DBI::dbGetQuery(con, sprintf(
    "WITH design_mass AS (
       SELECT cohort, SUM(weight) AS treated_mass
       FROM %1$s
       WHERE arm='treated' AND event_time=-1
       GROUP BY cohort
     ), shares AS (
       SELECT cohort, treated_mass/SUM(treated_mass) OVER() AS q_g
       FROM design_mass
     ), arm_means AS (
       SELECT cohort,event_time,arm,
              SUM(weight*patent_count)/SUM(weight) AS mean_y
       FROM %1$s
       GROUP BY cohort,event_time,arm
     )
     SELECT a.event_time,a.arm,SUM(s.q_g*a.mean_y) AS mean_patent_count
     FROM arm_means a JOIN shares s USING(cohort)
     GROUP BY a.event_time,a.arm ORDER BY a.event_time,a.arm",
    panel_sql))
  out$design <- design
  out
}
matched_means <- matched_mean_path("count_active")
raw_means <- utils::read.csv(
  file.path(RAW_DIR, "raw_did_standardized_mean_paths.csv"),
  stringsAsFactors = FALSE)
raw_means <- raw_means[
  raw_means$specification == "full_cohort_unmatched",
  c("event_time", "arm", "mean_patent_count")]
raw_means$design <- "raw_unmatched"
path_comparison <- rbind(raw_means, matched_means)
path_comparison$arm <- factor(
  path_comparison$arm, levels = c("treated", "control"))
write_csv(path_comparison, "package1d_raw_vs_matched_paths.csv")

path_plot <- ggplot2::ggplot(
  path_comparison,
  ggplot2::aes(
    x = event_time, y = mean_patent_count,
    colour = arm, linetype = arm, shape = arm)) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_line(linewidth = 0.7) +
  ggplot2::geom_point(size = 1.6) +
  ggplot2::facet_wrap(
    ~design, ncol = 1,
    labeller = ggplot2::as_labeller(c(
      raw_unmatched = "A. Unmatched eligible cohorts",
      count_active = "B. Frozen P5c count-active weights"))) +
  ggplot2::scale_colour_manual(
    values = c(treated = "#0072B2", control = "#D55E00")) +
  ggplot2::scale_linetype_manual(
    values = c(treated = "solid", control = "longdash")) +
  ggplot2::scale_shape_manual(values = c(treated = 16, control = 17)) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Event time", y = "Mean patent applications",
    colour = NULL, linetype = NULL, shape = NULL,
    title = "Raw and matched patent paths",
    subtitle = paste(
      "Unmatched paths use all eligible placebo controls;",
      "P5c uses the frozen matched roster and count-active weights.")) +
  ggplot2::theme_minimal(base_size = 10.5) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    legend.position = "top")
ggplot2::ggsave(
  file.path(OUT_DIR, "package1d_raw_vs_matched_paths.png"),
  path_plot, width = 7.2, height = 7.2, dpi = 320, bg = "white")
ggplot2::ggsave(
  file.path(OUT_DIR, "package1d_raw_vs_matched_paths.pdf"),
  path_plot, width = 7.2, height = 7.2,
  device = grDevices::cairo_pdf)

build_influence <- function(design, held_out, cohorts, tag) {
  panel_sql <- lmv2_panel_sql(panel_files[[design]])
  pair <- custom_pair_table(panel_sql, -1L, tag, cohorts)
  influence <- lmv2_prepare_influence_table(con, pair, panel_sql, cohorts)
  list(panel_sql = panel_sql, pair = pair, influence = influence)
}

decompose_heldout <- function(design, held_out, sample, cohorts) {
  tag <- paste("decomp", design, sample, sep = "_")
  built <- build_influence(design, held_out, cohorts, tag)
  class_table <- paste0("package1d_class_", tag)
  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", class_table))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE %1$s AS
     WITH first_patent AS (
       SELECT codinv, MIN(year) AS first_patent_year
       FROM p6.lmv2_outcome_inventor_year GROUP BY codinv
     )
     SELECT
       p.roster_row_id,p.cohort,p.arm,p.codinv,p.focal_group_1,
       fp.first_patent_year,g.focal_first_year,
       SUM(p.patent_count) FILTER (
         WHERE p.event_time BETWEEN -5 AND -1) AS patent_count_pre5,
       CASE
         WHEN fp.first_patent_year=p.cohort+%3$d
           THEN 'career_entry_heldout'
         WHEN g.focal_first_year=p.cohort+%3$d
           THEN 'focal_recruit_heldout'
         WHEN g.focal_first_year<p.cohort+%3$d
           THEN 'focal_incumbent'
         ELSE 'focal_entry_later'
       END AS category
     FROM %2$s p
     LEFT JOIN first_patent fp USING(codinv)
     LEFT JOIN lmv2_p3_inventor_group_first_year g
       ON g.codinv=p.codinv AND g.id_group=p.focal_group_1
     GROUP BY 1,2,3,4,5,6,7",
    class_table, built$panel_sql, as.integer(held_out)))
  class_check <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n, COUNT(DISTINCT roster_row_id) AS n_unique
     FROM %s", class_table))
  if (class_check$n != 500906L || class_check$n_unique != 500906L) {
    stop("Package 1D classification grain failed: ", tag)
  }
  joined_check <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n, COUNT(DISTINCT i.roster_row_id) AS n_unique,
            SUM(i.contribution) AS contribution
     FROM %1$s i JOIN %2$s c USING(roster_row_id)
     WHERE i.event_time=%3$d",
    built$influence, class_table, as.integer(held_out)))
  base_check <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n, SUM(contribution) AS contribution
     FROM %s WHERE event_time=%d",
    built$influence, as.integer(held_out)))
  if (joined_check$n != base_check$n ||
      joined_check$n_unique != base_check$n ||
      abs(joined_check$contribution - base_check$contribution) > 1e-10) {
    stop("Package 1D classification join tooth-check failed: ", tag)
  }

  out <- DBI::dbGetQuery(con, sprintf(
    "WITH rows AS (
       SELECT i.*,c.category,c.first_patent_year,c.focal_first_year,
              c.patent_count_pre5
       FROM %1$s i JOIN %2$s c USING(roster_row_id)
       WHERE i.event_time=%3$d
     )
     SELECT
       category,arm,
       COUNT(*) AS roster_rows,
       SUM(q_event*weight/observed_mass) AS weighted_share,
       SUM(contribution) AS signed_estimate_contribution,
       SUM(q_event*weight/observed_mass*
           (cohort-first_patent_year)) AS weighted_career_age,
       SUM(q_event*weight/observed_mass*patent_count_pre5)
         AS weighted_pre5_patents
     FROM rows GROUP BY category,arm ORDER BY category,arm",
    built$influence, class_table, as.integer(held_out)))
  total <- sum(out$signed_estimate_contribution)
  if (abs(total - base_check$contribution) > 1e-10) {
    stop("Package 1D decomposition failed to reproduce held-out ATT: ", tag)
  }
  out$design <- design
  out$sample <- sample
  out$held_out_event_time <- held_out
  out$total_heldout_estimate <- total
  out$contribution_share_of_total <- if (abs(total) > 1e-12) {
    out$signed_estimate_contribution / total
  } else NA_real_
  DBI::dbExecute(con, sprintf("DROP TABLE %s", built$influence))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", built$pair))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", class_table))
  out
}

decomposition <- do.call(rbind, list(
  decompose_heldout("loyo_m3", -3L, "full_1994_2010", 1994:2010),
  decompose_heldout("loyo_m3", -3L, "buffered_1994_2008", 1994:2008),
  decompose_heldout("loyo_m2", -2L, "full_1994_2010", 1994:2010),
  decompose_heldout("loyo_m2", -2L, "buffered_1994_2008", 1994:2008)))
write_csv(decomposition, "package1d_heldout_source_decomposition.csv")

deal_concentration <- function(design, held_out, sample, cohorts) {
  tag <- paste("deal", design, sample, sep = "_")
  built <- build_influence(design, held_out, cohorts, tag)
  detail <- DBI::dbGetQuery(con, sprintf(
    "SELECT deal_id,cohort,SUM(contribution) AS contribution
     FROM %s WHERE event_time=%d
     GROUP BY deal_id,cohort ORDER BY ABS(SUM(contribution)) DESC",
    built$influence, as.integer(held_out)))
  detail$absolute_contribution <- abs(detail$contribution)
  absolute_total <- sum(detail$absolute_contribution)
  detail$absolute_share <- detail$absolute_contribution / absolute_total
  detail$absolute_rank <- seq_len(nrow(detail))
  detail$cumulative_absolute_share <- cumsum(detail$absolute_share)
  detail$design <- design
  detail$sample <- sample
  detail$held_out_event_time <- held_out
  total <- sum(detail$contribution)
  summary <- data.frame(
    design = design, sample = sample, held_out_event_time = held_out,
    n_deals = nrow(detail), total_estimate = total,
    top1_absolute_share = sum(detail$absolute_share[detail$absolute_rank <= 1]),
    top5_absolute_share = sum(detail$absolute_share[detail$absolute_rank <= 5]),
    top10_absolute_share = sum(detail$absolute_share[detail$absolute_rank <= 10]),
    absolute_contribution_hhi = sum(detail$absolute_share^2),
    stringsAsFactors = FALSE)
  DBI::dbExecute(con, sprintf("DROP TABLE %s", built$influence))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", built$pair))
  list(detail = detail, summary = summary)
}
deal_runs <- list(
  deal_concentration("loyo_m3", -3L, "full_1994_2010", 1994:2010),
  deal_concentration("loyo_m3", -3L, "buffered_1994_2008", 1994:2008),
  deal_concentration("loyo_m2", -2L, "full_1994_2010", 1994:2010),
  deal_concentration("loyo_m2", -2L, "buffered_1994_2008", 1994:2008))
deal_detail <- do.call(rbind, lapply(deal_runs, `[[`, "detail"))
deal_summary <- do.call(rbind, lapply(deal_runs, `[[`, "summary"))
write_csv(deal_detail, "package1d_heldout_deal_contributions.csv")
write_csv(deal_summary, "package1d_heldout_deal_concentration.csv")

count_active_sql <- lmv2_panel_sql(panel_files$count_active)
deal_paths <- DBI::dbGetQuery(con, sprintf(
  "SELECT deal_id,cohort,event_time,
          COUNT(*) AS treated_inventors,
          AVG(patent_count) AS mean_patent_count,
          SUM(patent_count) AS total_patent_count
   FROM %s
   WHERE arm='treated' AND event_time BETWEEN -5 AND -1
   GROUP BY deal_id,cohort,event_time
   ORDER BY deal_id,event_time", count_active_sql))
deal_ids <- unique(deal_paths$deal_id)
peak_rows <- lapply(deal_ids, function(deal_id) {
  x <- deal_paths[deal_paths$deal_id == deal_id, ]
  x <- x[match(-5:-1, x$event_time), ]
  if (anyNA(x$event_time)) stop("Incomplete treated deal pre-path")
  peak_index <- which.max(x$mean_patent_count)
  data.frame(
    deal_id = deal_id,
    cohort = x$cohort[[1]],
    treated_inventors = x$treated_inventors[[1]],
    peak_event_time = x$event_time[[peak_index]],
    peak_mean_patent_count = x$mean_patent_count[[peak_index]],
    surge_m3m2_vs_edges =
      mean(x$mean_patent_count[x$event_time %in% c(-3, -2)]) -
      mean(x$mean_patent_count[x$event_time %in% c(-5, -4, -1)]),
    change_m5_to_m3 =
      x$mean_patent_count[x$event_time == -3] -
      x$mean_patent_count[x$event_time == -5],
    change_m3_to_m1 =
      x$mean_patent_count[x$event_time == -1] -
      x$mean_patent_count[x$event_time == -3],
    stringsAsFactors = FALSE)
})
deal_peaks <- do.call(rbind, peak_rows)
peak_summary <- do.call(rbind, lapply(-5:-1, function(event_time) {
  keep <- deal_peaks$peak_event_time == event_time
  data.frame(
    peak_event_time = event_time,
    n_deals = sum(keep),
    share_deals = mean(keep),
    treated_inventors = sum(deal_peaks$treated_inventors[keep]),
    share_treated_inventors =
      sum(deal_peaks$treated_inventors[keep]) /
      sum(deal_peaks$treated_inventors),
    stringsAsFactors = FALSE)
}))
write_csv(deal_paths, "package1d_treated_deal_prepaths.csv")
write_csv(deal_peaks, "package1d_treated_deal_peak_metrics.csv")
write_csv(peak_summary, "package1d_treated_deal_peak_summary.csv")

raw_dynamic <- utils::read.csv(
  file.path(RAW_DIR, "raw_did_dynamic_estimates.csv"),
  stringsAsFactors = FALSE)
raw_pretrend <- utils::read.csv(
  file.path(RAW_DIR, "raw_did_joint_pretrend.csv"),
  stringsAsFactors = FALSE)
raw_post <- utils::read.csv(
  file.path(RAW_DIR, "raw_did_post_att.csv"),
  stringsAsFactors = FALSE)
write_csv(raw_dynamic, "package1d_raw_did_dynamic_snapshot.csv")
write_csv(raw_pretrend, "package1d_raw_did_pretrend_snapshot.csv")
write_csv(raw_post, "package1d_raw_did_post_snapshot.csv")

source_paths <- c(
  runner = file.path(BASE, "R", "23b_summarize_lmv2_package1d_mean_reversion.R"),
  freeze = FREEZE_PATH,
  estimation_core = file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"),
  raw_dynamic = file.path(RAW_DIR, "raw_did_dynamic_estimates.csv"),
  raw_pretrend = file.path(RAW_DIR, "raw_did_joint_pretrend.csv"),
  raw_post = file.path(RAW_DIR, "raw_did_post_att.csv"),
  raw_means = file.path(RAW_DIR, "raw_did_standardized_mean_paths.csv"))
manifest <- data.frame(
  source = names(source_paths),
  path = unname(normalizePath(
    source_paths, winslash = "/", mustWork = TRUE)),
  sha256 = unname(vapply(
    source_paths, digest::digest, character(1),
    file = TRUE, algo = "sha256")),
  stringsAsFactors = FALSE)
write_csv(manifest, "package1d_source_manifest.csv")
message("Package 1D diagnostic summaries written to ", OUT_DIR)
