#!/usr/bin/env Rscript

# Outcome-stage runner for the exploratory supported-treated-inventor size
# split frozen by 48m. Estimates pooled and subgroup ATTs, tests their direct
# difference, and produces the exact filtered-weight contribution identity.

options(stringsAsFactors = FALSE, scipen = 999)

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NA_character_) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  if (length(hit) != 1L) stop("Duplicate argument: ", flag)
  sub(paste0("^", flag, "="), "", hit)
}

CODE_ROOT <- get_arg("--code-root", "02_analysis")
PANEL_DIR <- get_arg("--panel-dir")
DESIGN_DIR <- get_arg("--design-dir")
WEIGHT_ROBUSTNESS_DIR <- get_arg("--weight-robustness-dir")
OUTPUT_DIR <- get_arg("--output-dir")
BOOTSTRAP_REPS <- as.integer(get_arg("--bootstrap-reps", "9999"))

if (any(is.na(c(PANEL_DIR, DESIGN_DIR, WEIGHT_ROBUSTNESS_DIR, OUTPUT_DIR)))) {
  stop(paste0("48n requires --panel-dir=, --design-dir=, ",
              "--weight-robustness-dir=, and --output-dir="))
}
for (path in c(PANEL_DIR, DESIGN_DIR, WEIGHT_ROBUSTNESS_DIR)) {
  if (!dir.exists(path)) stop("Input directory missing: ", path)
}
if (dir.exists(OUTPUT_DIR) && length(list.files(
    OUTPUT_DIR, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", OUTPUT_DIR)
}
if (!is.finite(BOOTSTRAP_REPS) || BOOTSTRAP_REPS < 199L) {
  stop("At least 199 bootstrap replications are required")
}

BASE <- normalizePath(CODE_ROOT, winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c(
    "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = "")
}
sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

manifest_path <- file.path(DESIGN_DIR, "supported_size_design_manifest.csv")
cohorts_path <- file.path(DESIGN_DIR, "supported_size_feasible_cohorts.csv")
size_map_path <- file.path(DESIGN_DIR, "supported_size_deal_map.csv")
counts_path <- file.path(DESIGN_DIR, "supported_size_counts.csv")
gates_path <- file.path(DESIGN_DIR, "supported_size_reporting_gates.csv")
weights_path <- file.path(
  DESIGN_DIR, "weights", "supported_size_weights.parquet")
weight_headline_path <- file.path(
  WEIGHT_ROBUSTNESS_DIR, "weight_robustness_headline.csv")
required <- c(manifest_path, cohorts_path, size_map_path, counts_path,
              gates_path, weights_path, weight_headline_path)
if (!all(file.exists(required))) {
  stop("Frozen supported-size inputs are incomplete: ",
       paste(required[!file.exists(required)], collapse = ", "))
}

manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
if (nrow(manifest) != 1L || !isTRUE(manifest$analysis_authorized[[1]]) ||
    isTRUE(manifest$post_outcomes_opened[[1]])) {
  stop("The outcome-blind design did not authorize size-split estimation")
}
cohorts <- sort(as.integer(utils::read.csv(cohorts_path)$cohort))
if (!identical(paste(cohorts, collapse = ";"), manifest$common_cohorts[[1]])) {
  stop("Frozen common-cohort list disagrees with the design manifest")
}
size_map <- utils::read.csv(size_map_path, stringsAsFactors = FALSE)
size_map <- size_map[size_map$cohort %in% cohorts, ]
if (!identical(sort(unique(size_map$size_group)), c("large", "small")) ||
    anyDuplicated(size_map[c("cohort", "deal_id")])) {
  stop("Frozen supported-size deal map is invalid")
}

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$", full.names = TRUE
))
panel_cohorts <- as.integer(sub("^.*_c([0-9]+)\\.parquet$", "\\1", panel_files))
if (!identical(panel_cohorts, 1993:2010)) {
  stop("Base P6 panel must contain exactly the 1993--2010 cohorts")
}
base_panel_sql <- lmv2_panel_sql(panel_files)
cohort_sql <- paste(cohorts, collapse = ",")

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")

pooled_panel_sql <- sprintf(
  "(SELECT * FROM %s WHERE cohort IN (%s))", base_panel_sql, cohort_sql)
subgroup_panel_sql <- sprintf(paste0(
  "(SELECT p.* EXCLUDE(weight), w.final_weight::DOUBLE weight, ",
  "w.size_group, w.n_supported FROM %s p ",
  "INNER JOIN read_parquet(%s) w USING(roster_row_id) ",
  "WHERE p.cohort IN (%s))"),
  base_panel_sql,
  sql_string(normalizePath(weights_path, winslash = "/", mustWork = TRUE)),
  cohort_sql
)

specs <- list(
  pooled_common_cohorts = pooled_panel_sql,
  supported_size_small = sprintf(
    "(SELECT * EXCLUDE(size_group, n_supported) FROM %s WHERE size_group='small')",
    subgroup_panel_sql),
  supported_size_large = sprintf(
    "(SELECT * EXCLUDE(size_group, n_supported) FROM %s WHERE size_group='large')",
    subgroup_panel_sql)
)

expected_deals <- c(
  pooled_common_cohorts = nrow(size_map),
  supported_size_small = sum(size_map$size_group == "small"),
  supported_size_large = sum(size_map$size_group == "large")
)

certify_panel <- function(specification, panel_sql) {
  out <- DBI::dbGetQuery(con, sprintf(paste0(
    "WITH p AS (SELECT * FROM %s), ",
    "u AS (SELECT roster_row_id, COUNT(*) n, COUNT(DISTINCT cohort) nc, ",
    "COUNT(DISTINCT deal_id) nd, COUNT(DISTINCT arm) na, ",
    "COUNT(DISTINCT codinv) ni, MIN(event_time) mine, MAX(event_time) maxe ",
    "FROM p GROUP BY roster_row_id), ",
    "m AS (SELECT cohort, SUM(weight) FILTER(arm='treated' AND event_time=-1) tm, ",
    "SUM(weight) FILTER(arm='control' AND event_time=-1) cm FROM p GROUP BY cohort) ",
    "SELECT COUNT(*) panel_rows, (SELECT COUNT(*) FROM u) units, ",
    "(SELECT COUNT(*) FROM u WHERE n<>11 OR nc<>1 OR nd<>1 OR na<>1 OR ni<>1 ",
    "OR mine<>-5 OR maxe<>5) bad_units, ",
    "(SELECT COUNT(*) FROM m WHERE ABS(tm-cm)>1e-7) bad_masses, ",
    "COUNT(*) FILTER(weight IS NULL OR NOT isfinite(weight) OR weight<=0) bad_weights, ",
    "COUNT(*) FILTER(arm='treated' AND ABS(weight-1)>1e-12) bad_treated_weights, ",
    "COUNT(DISTINCT cohort) cohorts, COUNT(DISTINCT deal_id) deals FROM p"),
    panel_sql))
  out$specification <- specification
  out$pass <- out$bad_units == 0 & out$bad_masses == 0 &
    out$bad_weights == 0 & out$bad_treated_weights == 0 &
    out$cohorts == length(cohorts) &
    out$deals == expected_deals[[specification]]
  out
}

dynamic <- pretrend <- headline <- coverage <- certification <- list()
for (i in seq_along(specs)) {
  specification <- names(specs)[[i]]
  panel_sql <- specs[[i]]
  message(sprintf("[%d/%d] %s", i, length(specs), specification))
  certification[[i]] <- certify_panel(specification, panel_sql)
  if (!isTRUE(certification[[i]]$pass[[1]])) {
    stop("Panel certification failed for ", specification)
  }
  deal_counts <- lmv2_design_deal_counts(con, panel_sql, cohorts)
  fitted <- lmv2_fit_outcome(
    con, panel_sql, "patent_count", specification, cohorts,
    BOOTSTRAP_REPS, deal_counts
  )
  for (object in c("dynamic", "pretrend", "headline", "coverage")) {
    fitted[[object]]$specification <- specification
    fitted[[object]]$designation <- "post_hoc_exploratory"
  }
  dynamic[[i]] <- fitted$dynamic
  pretrend[[i]] <- fitted$pretrend
  headline[[i]] <- fitted$headline
  coverage[[i]] <- fitted$coverage
}

headline_all <- do.call(rbind, headline)
dynamic_all <- do.call(rbind, dynamic)
pretrend_all <- do.call(rbind, pretrend)
coverage_all <- do.call(rbind, coverage)
certification_all <- do.call(rbind, certification)

# Preserve the already-certified same-16-cohort inventor-weighted and
# equal-acquisition rows together so the aggregation comparison is not
# confounded by the two cohorts absent from the equal-acquisition solve.
weight_headline <- utils::read.csv(
  weight_headline_path, stringsAsFactors = FALSE, check.names = FALSE)
aggregation_anchor <- weight_headline[
  weight_headline$outcome == "patent_count" &
    weight_headline$summary == "average_annual_t1_to_t5" &
    weight_headline$specification %in% c("headline_same16", "equal_deal_same16"), ]
if (nrow(aggregation_anchor) != 6L) {
  stop("Certified same-16 aggregation anchors are absent or stale")
}
aggregation_anchor$sample_note <- paste(
  "Both rows use the 16 cohorts in which equal-deal P5c weights were feasible;",
  "cohorts 2000 and 2005 are excluded."
)

# Unit-level five-year changes for the direct subgroup contrast.
unit_sql <- sprintf(paste0(
  "WITH p AS (SELECT * FROM %s), u AS (",
  "SELECT roster_row_id, cohort::INTEGER cohort, deal_id::INTEGER deal_id, ",
  "codinv::BIGINT codinv, arm, size_group, n_supported::INTEGER n_supported, ",
  "MAX(weight)::DOUBLE analysis_weight, ",
  "AVG(patent_count) FILTER(event_time BETWEEN 1 AND 5) - ",
  "MAX(patent_count) FILTER(event_time=-1) AS dy_post ",
  "FROM p GROUP BY ALL) SELECT * FROM u"), subgroup_panel_sql)
unit <- DBI::dbGetQuery(con, unit_sql)
unit$treated <- as.integer(unit$arm == "treated")
unit$cell_id <- interaction(unit$cohort, unit$size_group, drop = TRUE)
unit$tr_small <- unit$treated * as.integer(unit$size_group == "small")
unit$tr_large <- unit$treated * as.integer(unit$size_group == "large")

fit <- lmv2_vr_fit_wls(
  unit, "dy_post", c("factor(cell_id)", "tr_small", "tr_large"))
covariance <- lmv2_vr_model_covariance(fit)
cfg <- LMV2_VR_HET
cfg$inference$bootstrap_replications <- BOOTSTRAP_REPS
cfg$inference$bootstrap_seed <- 20260814L
mult <- lmv2_vr_webb_multipliers(
  sort(unique(fit$deal)), cfg = cfg)

linear_result_frozen <- function(fit, covariance, contrast, multipliers,
                                 label, cfg) {
  L <- numeric(length(fit$beta)); names(L) <- names(fit$beta)
  missing <- setdiff(names(contrast), names(L))
  if (length(missing)) stop("Contrast term absent: ", paste(missing, collapse = ", "))
  L[names(contrast)] <- contrast
  estimate <- sum(L * fit$beta)
  se_deal <- sqrt(drop(t(L) %*% covariance$deal %*% L))
  se_two <- sqrt(drop(t(L) %*% covariance$two %*% L))
  score <- drop(covariance$S_deal %*% L)
  draw_t <- drop(multipliers[, rownames(covariance$S_deal), drop = FALSE] %*% score) / se_deal
  alpha <- 1 - cfg$inference$confidence_level
  crit_wild <- unname(stats::quantile(abs(draw_t), 1 - alpha, type = 7))
  crit_two <- stats::qt(1 - alpha / 2, covariance$df_two)
  width_wild <- crit_wild * se_deal
  width_two <- crit_two * se_two
  wild_p <- (1 + sum(abs(draw_t) >= abs(estimate / se_deal))) /
    (length(draw_t) + 1)
  two_p <- 2 * stats::pt(-abs(estimate / se_two), df = covariance$df_two)
  governing <- if (width_two > width_wild) {
    "two_way_deal_inventor"
  } else {
    "deal_wild_bootstrap_t"
  }
  rows <- data.frame(
    contrast = label,
    inference = c("deal_wild_bootstrap_t", "two_way_deal_inventor"),
    estimate = estimate,
    se = c(se_deal, se_two),
    df = c(NA_real_, covariance$df_two),
    ci_low = estimate - c(width_wild, width_two),
    ci_high = estimate + c(width_wild, width_two),
    p_value = c(wild_p, two_p),
    bootstrap_replications = c(BOOTSTRAP_REPS, NA_integer_),
    governing = c("deal_wild_bootstrap_t", "two_way_deal_inventor") == governing,
    designation = "post_hoc_exploratory",
    stringsAsFactors = FALSE
  )
  rows
}

formal_difference <- linear_result_frozen(
  fit, covariance, c(tr_small = -1, tr_large = 1), mult,
  "large_minus_small", cfg)

# Tooth-check the joint model against independently estimated subgroup ATTs.
subgroup_governing <- headline_all[
  headline_all$summary == "average_annual_t1_to_t5" &
    headline_all$specification %in% c("supported_size_small", "supported_size_large") &
    headline_all$governing, ]
joint_coefs <- c(
  supported_size_small = unname(fit$beta[["tr_small"]]),
  supported_size_large = unname(fit$beta[["tr_large"]])
)
standalone <- setNames(
  subgroup_governing$estimate, subgroup_governing$specification)
tooth_check <- data.frame(
  specification = names(joint_coefs),
  joint_model_estimate = joint_coefs,
  standalone_estimate = standalone[names(joint_coefs)],
  absolute_difference = abs(joint_coefs - standalone[names(joint_coefs)]),
  tolerance = 1e-10,
  stringsAsFactors = FALSE
)
tooth_check$pass <- tooth_check$absolute_difference <= tooth_check$tolerance
if (!all(tooth_check$pass)) stop("Joint subgroup model failed the ATT tooth-check")

# Descriptive full-sample frozen-weight interaction. Both the size measure and
# weights are inherited; no subgroup weights are re-solved for this diagnostic.
full_size_path <- normalizePath(size_map_path, winslash = "/", mustWork = TRUE)
full_unit_sql <- sprintf(paste0(
  "WITH m AS (SELECT cohort::INTEGER cohort, deal_id::INTEGER deal_id, ",
  "n_supported::INTEGER n_supported FROM read_csv_auto(%s) WHERE cohort BETWEEN 1993 AND 2010), ",
  "p AS (SELECT p.*, m.n_supported FROM %s p JOIN m USING(cohort, deal_id)), ",
  "u AS (SELECT roster_row_id, cohort::INTEGER cohort, deal_id::INTEGER deal_id, ",
  "codinv::BIGINT codinv, arm, n_supported, MAX(weight)::DOUBLE analysis_weight, ",
  "AVG(patent_count) FILTER(event_time BETWEEN 1 AND 5) - ",
  "MAX(patent_count) FILTER(event_time=-1) AS dy_post FROM p GROUP BY ALL) ",
  "SELECT * FROM u"), sql_string(full_size_path), base_panel_sql)
full_unit <- DBI::dbGetQuery(con, full_unit_sql)
full_unit$treated <- as.integer(full_unit$arm == "treated")
log_mean <- with(full_unit[full_unit$treated == 1L, ],
                 weighted.mean(log(n_supported), analysis_weight))
full_unit$log_size_centered <- log(full_unit$n_supported) - log_mean
full_unit$treated_log_size <- full_unit$treated * full_unit$log_size_centered
fit_log <- lmv2_vr_fit_wls(
  full_unit, "dy_post",
  c("factor(cohort)", "treated", "log_size_centered", "treated_log_size"))
cov_log <- lmv2_vr_model_covariance(fit_log)
mult_log <- lmv2_vr_webb_multipliers(sort(unique(fit_log$deal)), cfg = cfg)
descriptive_log_interaction <- linear_result_frozen(
  fit_log, cov_log, c(treated_log_size = 1), mult_log,
  "treated_x_log_supported_size", cfg)
descriptive_log_interaction$centered_at_treated_weighted_mean_log_size <- log_mean
descriptive_log_interaction$causal_heterogeneity_test <- FALSE

# Exact filtered-headline contribution decomposition on the retained cohort
# sample. Contributions are tagged by treated acquisition stack and therefore
# sum algebraically to each event ATT and to the pooled post-period ATT.
pair_table <- lmv2_build_pair_table(
  con, pooled_panel_sql, "patent_count", cohorts,
  "supported_size_filtered_identity")
influence_table <- lmv2_prepare_influence_table(
  con, pair_table, pooled_panel_sql, cohorts)
DBI::dbWriteTable(con, "tmp_supported_size_map", size_map[
  c("cohort", "deal_id", "size_group", "n_supported")], overwrite = TRUE)
contribution_event <- DBI::dbGetQuery(con, sprintf(paste0(
  "SELECT m.size_group, i.event_time, SUM(i.contribution) contribution ",
  "FROM %s i JOIN tmp_supported_size_map m USING(cohort, deal_id) ",
  "GROUP BY m.size_group, i.event_time ORDER BY i.event_time, m.size_group"),
  influence_table))
pooled_event <- aggregate(
  contribution ~ event_time, contribution_event, sum)
contribution_post <- aggregate(
  contribution ~ size_group,
  contribution_event[contribution_event$event_time %in% 1:5, ], mean)
pooled_post_identity <- mean(
  pooled_event$contribution[pooled_event$event_time %in% 1:5])
pooled_post_runner <- headline_all$estimate[
  headline_all$specification == "pooled_common_cohorts" &
    headline_all$summary == "average_annual_t1_to_t5" &
    headline_all$inference == "two_way_deal_inventor"]
identity_check <- data.frame(
  identity = "small_plus_large_filtered_contributions_equals_pooled_att",
  small_contribution = contribution_post$contribution[
    contribution_post$size_group == "small"],
  large_contribution = contribution_post$contribution[
    contribution_post$size_group == "large"],
  contribution_sum = sum(contribution_post$contribution),
  pooled_att = pooled_post_runner,
  absolute_difference = abs(sum(contribution_post$contribution) - pooled_post_runner),
  tolerance = 1e-10,
  stringsAsFactors = FALSE
)
identity_check$pass <- identity_check$absolute_difference <= identity_check$tolerance
if (!isTRUE(identity_check$pass[[1]])) stop("Filtered contribution identity failed")
DBI::dbExecute(con, sprintf("DROP TABLE %s", pair_table))
DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
DBI::dbExecute(con, "DROP TABLE tmp_supported_size_map")

# Report, but do not impose, the non-identity for separately re-solved weights.
treated_mass <- aggregate(n_supported ~ size_group, size_map, sum)
treated_mass$share <- treated_mass$n_supported / sum(treated_mass$n_supported)
resolved_est <- standalone[paste0("supported_size_", treated_mass$size_group)]
resolved_weighted_average <- sum(treated_mass$share * resolved_est)
resolved_nonidentity <- data.frame(
  diagnostic = "resolved_subgroup_weighted_average_minus_pooled_original_weight_att",
  resolved_weighted_average = resolved_weighted_average,
  pooled_original_weight_att = pooled_post_runner,
  difference = resolved_weighted_average - pooled_post_runner,
  identity_required = FALSE,
  reason = "Stage-2 counterfactual weights are re-solved separately by subgroup.",
  stringsAsFactors = FALSE
)

write_csv(certification_all, "supported_size_estimation_certification.csv")
write_csv(dynamic_all, "supported_size_dynamic.csv")
write_csv(pretrend_all, "supported_size_pretrend.csv")
write_csv(headline_all, "supported_size_headline.csv")
write_csv(coverage_all, "supported_size_coverage.csv")
write_csv(aggregation_anchor, "supported_size_same16_aggregation_anchor.csv")
write_csv(formal_difference, "supported_size_formal_difference.csv")
write_csv(tooth_check, "supported_size_joint_model_tooth_check.csv")
write_csv(descriptive_log_interaction, "supported_size_descriptive_log_interaction.csv")
write_csv(contribution_event, "supported_size_filtered_contributions_event.csv")
write_csv(contribution_post, "supported_size_filtered_contributions_post.csv")
write_csv(identity_check, "supported_size_filtered_identity_check.csv")
write_csv(resolved_nonidentity, "supported_size_resolved_nonidentity.csv")

estimation_manifest <- data.frame(
  version = "lmv2_supported_size_split_estimation_v1",
  designation = "post_hoc_exploratory",
  bootstrap_replications = BOOTSTRAP_REPS,
  bootstrap_seed = cfg$inference$bootstrap_seed,
  governing_rule = "wider_of_deal_wild_and_two_way_ci_wild_on_exact_tie",
  common_cohorts = paste(cohorts, collapse = ";"),
  specifications = paste(names(specs), collapse = ";"),
  all_panel_certification_pass = all(certification_all$pass),
  joint_model_tooth_check_pass = all(tooth_check$pass),
  filtered_identity_pass = identity_check$pass[[1]],
  direct_difference_governing_inference = formal_difference$inference[
    formal_difference$governing],
  descriptive_log_governing_inference = descriptive_log_interaction$inference[
    descriptive_log_interaction$governing],
  main_text_eligible = manifest$main_text_eligible[[1]],
  placement = manifest$placement[[1]],
  design_manifest_sha256 = digest::digest(
    manifest_path, file = TRUE, algo = "sha256"),
  panel_bundle_sha256 = digest::digest(vapply(
    panel_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
    algo = "sha256"),
  source_sha256 = digest::digest(normalizePath(sub(
    "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]),
    winslash = "/", mustWork = TRUE), file = TRUE, algo = "sha256"),
  stringsAsFactors = FALSE
)
write_csv(estimation_manifest, "supported_size_estimation_manifest.csv")
message(sprintf(
  paste0("Supported-size estimation complete: small %.4f; large %.4f; ",
         "difference %.4f (p=%.4f, %s governs)"),
  standalone[["supported_size_small"]],
  standalone[["supported_size_large"]],
  formal_difference$estimate[formal_difference$governing],
  formal_difference$p_value[formal_difference$governing],
  formal_difference$inference[formal_difference$governing]
))
