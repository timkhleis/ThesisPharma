#!/usr/bin/env Rscript

# Outcome-stage estimator for the frozen deal-value decile and quartile
# profiles built by 48r. Uses certified P5c relative weights and renormalises
# control mass only within cohort-by-bin cells.

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
OUTPUT_DIR <- get_arg("--output-dir")
BOOTSTRAP_REPS <- as.integer(get_arg("--bootstrap-reps", "9999"))
EXPECTED_DEALS <- as.integer(get_arg("--expected-deals", "343"))
COHORT_START <- as.integer(get_arg("--cohort-start", "1993"))
COHORT_END <- as.integer(get_arg("--cohort-end", "2010"))
DESIGNATION <- get_arg("--designation", "post_hoc_exploratory")
WEIGHT_SCHEME <- get_arg(
  "--weight-scheme", "frozen_certified_p5c_relative_weights"
)
if (any(is.na(c(PANEL_DIR, DESIGN_DIR, OUTPUT_DIR)))) {
  stop("48s requires --panel-dir=, --design-dir=, and --output-dir=")
}
for (path in c(PANEL_DIR, DESIGN_DIR)) {
  if (!dir.exists(path)) stop("Input directory missing: ", path)
}
if (dir.exists(OUTPUT_DIR) && length(list.files(
    OUTPUT_DIR, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", OUTPUT_DIR)
}
if (!is.finite(BOOTSTRAP_REPS) || BOOTSTRAP_REPS < 199L) {
  stop("At least 199 bootstrap replications are required")
}
if (anyNA(c(EXPECTED_DEALS, COHORT_START, COHORT_END)) ||
    EXPECTED_DEALS < 10L || COHORT_START > COHORT_END) {
  stop("Invalid expected-deals or cohort range")
}

BASE <- normalizePath(CODE_ROOT, winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "MASS")) {
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

manifest_path <- file.path(DESIGN_DIR, "deal_value_quantile_design_manifest.csv")
map_path <- file.path(DESIGN_DIR, "deal_value_quantile_map.csv")
counts_path <- file.path(DESIGN_DIR, "deal_value_quantile_counts.csv")
if (!all(file.exists(c(manifest_path, map_path, counts_path)))) {
  stop("Frozen quantile-design inputs are incomplete")
}
manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
if (nrow(manifest) != 1L || !isTRUE(manifest$analysis_authorized[[1]]) ||
    isTRUE(manifest$post_outcomes_opened[[1]])) {
  stop("The outcome-blind design did not authorize estimation")
}
deal_map <- utils::read.csv(map_path, stringsAsFactors = FALSE)
if (nrow(deal_map) != EXPECTED_DEALS ||
    anyDuplicated(deal_map[c("cohort", "deal_id")]) ||
    !identical(sort(unique(deal_map$decile_label)), sprintf("D%02d", 1:10)) ||
    !identical(sort(unique(deal_map$quartile_label)), paste0("Q", 1:4))) {
  stop("Frozen quantile map is invalid")
}

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$", full.names = TRUE
))
panel_cohorts <- as.integer(sub("^.*_c([0-9]+)\\.parquet$", "\\1", panel_files))
if (!identical(panel_cohorts, COHORT_START:COHORT_END)) {
  stop("Panel shards do not match the declared cohort range")
}
base_panel_sql <- lmv2_panel_sql(panel_files)
map_sql <- sql_string(normalizePath(map_path, winslash = "/", mustWork = TRUE))

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")

cfg <- LMV2_VR_HET
cfg$inference$bootstrap_replications <- BOOTSTRAP_REPS
cfg$inference$bootstrap_seed <- 20260814L

build_unit <- function(label_column) {
  sql <- sprintf(paste0(
    "WITH f AS (SELECT p.*, m.%s AS bin, m.target_value, m.n_supported ",
    "FROM %s p INNER JOIN read_csv_auto(%s) m USING(cohort, deal_id)), ",
    "mass AS (SELECT cohort, bin, ",
    "SUM(weight) FILTER(arm='treated' AND event_time=-1) tm, ",
    "SUM(weight) FILTER(arm='control' AND event_time=-1) cm ",
    "FROM f GROUP BY cohort, bin), weighted AS (",
    "SELECT f.* EXCLUDE(weight), CASE WHEN arm='treated' THEN 1.0 ",
    "ELSE f.weight*mass.tm/mass.cm END::DOUBLE analysis_weight ",
    "FROM f JOIN mass USING(cohort, bin)), u AS (",
    "SELECT roster_row_id, cohort::INTEGER cohort, deal_id::INTEGER deal_id, ",
    "codinv::BIGINT codinv, arm, bin, target_value::DOUBLE target_value, ",
    "n_supported::INTEGER n_supported, MAX(analysis_weight)::DOUBLE analysis_weight, ",
    "AVG(patent_count) FILTER(event_time BETWEEN 1 AND 5) - ",
    "MAX(patent_count) FILTER(event_time=-1) AS dy_post, COUNT(*) panel_periods ",
    "FROM weighted GROUP BY ALL) SELECT * FROM u"),
    label_column, base_panel_sql, map_sql
  )
  DBI::dbGetQuery(con, sql)
}

safe_inverse <- function(x) {
  tryCatch(solve(x), error = function(e) MASS::ginv(x))
}

omnibus_result <- function(fit, covariance, terms, multipliers, partition) {
  q <- length(terms) - 1L
  R <- matrix(0, nrow = q, ncol = length(fit$beta),
              dimnames = list(NULL, names(fit$beta)))
  for (j in seq_len(q)) {
    R[j, terms[[1]]] <- -1
    R[j, terms[[j + 1L]]] <- 1
  }
  delta <- drop(R %*% fit$beta)
  V_deal <- R %*% covariance$deal %*% t(R)
  V_two <- R %*% covariance$two %*% t(R)
  stat_deal <- drop(crossprod(delta, safe_inverse(V_deal) %*% delta)) / q
  stat_two <- drop(crossprod(delta, safe_inverse(V_two) %*% delta)) / q

  model_deals <- rownames(covariance$S_deal)
  beta_draw <- multipliers[, model_deals, drop = FALSE] %*%
    covariance$S_deal
  delta_draw <- beta_draw %*% t(R)
  draw_stat <- rowSums((delta_draw %*% safe_inverse(V_deal)) * delta_draw) / q
  wild_p <- (1 + sum(draw_stat >= stat_deal)) / (nrow(delta_draw) + 1)
  two_p <- stats::pf(
    stat_two, df1 = q, df2 = covariance$df_two, lower.tail = FALSE)
  data.frame(
    partition = partition,
    null_hypothesis = "all_bin_atts_equal",
    restrictions = q,
    deal_wild_statistic = stat_deal,
    deal_wild_p = wild_p,
    two_way_statistic = stat_two,
    two_way_df2 = covariance$df_two,
    two_way_p = two_p,
    governing_p = max(wild_p, two_p),
    governing_rule = "larger_of_deal_wild_and_two_way_p",
    designation = "post_hoc_exploratory",
    stringsAsFactors = FALSE
  )
}

estimate_partition <- function(partition, label_column) {
  unit <- build_unit(label_column)
  labels <- sort(unique(unit$bin))
  expected <- if (partition == "decile") sprintf("D%02d", 1:10) else paste0("Q", 1:4)
  if (!identical(labels, expected) || any(unit$panel_periods != 11L) ||
      any(!is.finite(unit$analysis_weight)) || any(unit$analysis_weight <= 0)) {
    stop("Unit-panel certification failed for ", partition)
  }
  unit$treated <- as.integer(unit$arm == "treated")
  unit$cell_id <- interaction(unit$cohort, unit$bin, drop = TRUE)
  terms <- paste0("tr_", labels)
  for (j in seq_along(labels)) {
    unit[[terms[[j]]]] <- unit$treated * as.integer(unit$bin == labels[[j]])
  }

  mass <- aggregate(analysis_weight ~ cohort + bin + arm, unit, sum)
  mass_wide <- reshape(mass, idvar = c("cohort", "bin"),
                       timevar = "arm", direction = "wide")
  mass_wide$gap <- mass_wide$analysis_weight.treated -
    mass_wide$analysis_weight.control
  if (any(!is.finite(mass_wide$gap)) || max(abs(mass_wide$gap)) > 1e-7) {
    stop("Cohort-by-bin treatment/control mass mismatch for ", partition)
  }

  fit <- lmv2_vr_fit_wls(
    unit, "dy_post", c("factor(cell_id)", terms))
  if (fit$rank != length(fit$beta)) stop("Rank-deficient ", partition, " model")
  covariance <- lmv2_vr_model_covariance(fit)
  multipliers <- lmv2_vr_webb_multipliers(
    sort(unique(fit$deal)), cfg = cfg)

  results <- do.call(rbind, lapply(seq_along(labels), function(j) {
    out <- lmv2_vr_linear_result(
      fit, covariance, setNames(1, terms[[j]]), multipliers,
      paste0(partition, "_", labels[[j]]), cfg)
    out$partition <- partition
    out$bin <- labels[[j]]
    out
  }))
  results$holm_p <- stats::p.adjust(results$governing_p, method = "holm")

  extreme <- lmv2_vr_linear_result(
    fit, covariance,
    setNames(c(-1, 1), c(terms[[1]], terms[[length(terms)]])),
    multipliers, paste0(partition, "_extreme"), cfg
  )
  extreme$partition <- partition
  extreme$comparison <- paste0(labels[[length(labels)]], "_minus_", labels[[1]])

  cell_means <- aggregate(
    cbind(wy = analysis_weight * dy_post, w = analysis_weight) ~
      cohort + bin + arm, unit, sum)
  cell_means$mean <- cell_means$wy / cell_means$w
  treated <- cell_means[cell_means$arm == "treated", c("cohort", "bin", "w", "mean")]
  control <- cell_means[cell_means$arm == "control", c("cohort", "bin", "mean")]
  names(treated)[3:4] <- c("treated_mass", "treated_mean")
  names(control)[3] <- "control_mean"
  cells <- merge(treated, control, by = c("cohort", "bin"), all = TRUE)
  cells$cell_att <- cells$treated_mean - cells$control_mean
  manual <- do.call(rbind, lapply(labels, function(label) {
    z <- cells[cells$bin == label, ]
    data.frame(
      bin = label,
      manual_att = stats::weighted.mean(z$cell_att, z$treated_mass),
      stringsAsFactors = FALSE
    )
  }))
  manual$model_att <- unname(fit$beta[terms])
  manual$absolute_difference <- abs(manual$manual_att - manual$model_att)
  manual$pass <- manual$absolute_difference <= 1e-10
  if (!all(manual$pass)) stop("ATT tooth-check failed for ", partition)

  counts <- do.call(rbind, lapply(labels, function(label) {
    z <- unit[unit$bin == label, ]
    data.frame(
      partition = partition,
      bin = label,
      acquisitions = length(unique(z$deal_id)),
      treated_inventors = sum(z$treated),
      control_stacks = sum(1L - z$treated),
      cohorts = length(unique(z$cohort)),
      minimum_target_value = min(z$target_value),
      median_target_value = stats::median(unique(z[c("deal_id", "target_value")])$target_value),
      maximum_target_value = max(z$target_value),
      stringsAsFactors = FALSE
    )
  }))

  list(
    estimates = results,
    extreme = extreme,
    omnibus = omnibus_result(
      fit, covariance, terms, multipliers, partition),
    counts = counts,
    tooth_check = transform(manual, partition = partition),
    certification = data.frame(
      partition = partition,
      units = nrow(unit),
      acquisitions = length(unique(unit$deal_id)),
      treated_inventors = sum(unit$treated),
      bins = length(labels),
      cohort_bin_cells = nrow(mass_wide),
      maximum_mass_gap = max(abs(mass_wide$gap)),
      model_full_rank = fit$rank == length(fit$beta),
      tooth_check_pass = all(manual$pass),
      pass = TRUE,
      stringsAsFactors = FALSE
    )
  )
}

decile <- estimate_partition("decile", "decile_label")
quartile <- estimate_partition("quartile", "quartile_label")
bind_partitions <- function(name) rbind(decile[[name]], quartile[[name]])

# Exact decomposition of the original pooled P5c ATT. These are contributions,
# not separately rebalanced subgroup ATTs, and therefore sum algebraically.
cohorts <- COHORT_START:COHORT_END
pair_table <- lmv2_build_pair_table(
  con, base_panel_sql, "patent_count", cohorts,
  "deal_value_quantile_pooled_identity")
influence_table <- lmv2_prepare_influence_table(
  con, pair_table, base_panel_sql, cohorts)
DBI::dbWriteTable(
  con, "tmp_deal_value_quantile_map",
  deal_map[c("cohort", "deal_id", "decile_label", "quartile_label")],
  overwrite = TRUE
)
contribution_event <- do.call(rbind, lapply(
  c(decile = "decile_label", quartile = "quartile_label"),
  function(column) {
    out <- DBI::dbGetQuery(con, sprintf(paste0(
      "SELECT m.%s AS bin, i.event_time, SUM(i.contribution) contribution ",
      "FROM %s i JOIN tmp_deal_value_quantile_map m USING(cohort, deal_id) ",
      "GROUP BY m.%s, i.event_time ORDER BY i.event_time, m.%s"),
      column, influence_table, column, column))
    out$partition <- if (column == "decile_label") "decile" else "quartile"
    out
  }
))
contribution_post <- aggregate(
  contribution ~ partition + bin,
  contribution_event[contribution_event$event_time %in% 1:5, ], mean)
pooled_identity <- do.call(rbind, lapply(c("decile", "quartile"), function(part) {
  z <- contribution_post[contribution_post$partition == part, ]
  data.frame(
    partition = part,
    contribution_sum = sum(z$contribution),
    pooled_att = mean(aggregate(
      contribution ~ event_time,
      contribution_event[contribution_event$partition == part &
                           contribution_event$event_time %in% 1:5, ], sum
    )$contribution),
    stringsAsFactors = FALSE
  )
}))
pooled_identity$absolute_difference <- abs(
  pooled_identity$contribution_sum - pooled_identity$pooled_att)
pooled_identity$pass <- pooled_identity$absolute_difference <= 1e-10
if (!all(pooled_identity$pass) ||
    abs(diff(pooled_identity$pooled_att)) > 1e-10) {
  stop("Quantile contribution identity failed")
}
DBI::dbExecute(con, sprintf("DROP TABLE %s", pair_table))
DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
DBI::dbExecute(con, "DROP TABLE tmp_deal_value_quantile_map")

resolved_nonidentity <- do.call(rbind, lapply(c("decile", "quartile"), function(part) {
  estimates <- if (part == "decile") decile$estimates else quartile$estimates
  counts <- if (part == "decile") decile$counts else quartile$counts
  joined <- merge(
    estimates[c("bin", "estimate")], counts[c("bin", "treated_inventors")],
    by = "bin", sort = FALSE)
  weighted_average <- stats::weighted.mean(
    joined$estimate, joined$treated_inventors)
  pooled_att <- pooled_identity$pooled_att[pooled_identity$partition == part]
  data.frame(
    partition = part,
    rebalanced_subgroup_weighted_average = weighted_average,
    pooled_original_weight_att = pooled_att,
    difference = weighted_average - pooled_att,
    identity_required = FALSE,
    reason = paste(
      "Separate subgroup ATTs renormalise control mass within cohort-by-bin",
      "cells; only the frozen pooled-weight contributions sum exactly."
    ),
    stringsAsFactors = FALSE
  )
}))

write_csv(bind_partitions("estimates"), "deal_value_quantile_att.csv")
write_csv(bind_partitions("extreme"), "deal_value_quantile_extreme_contrasts.csv")
write_csv(bind_partitions("omnibus"), "deal_value_quantile_omnibus.csv")
write_csv(bind_partitions("counts"), "deal_value_quantile_estimation_counts.csv")
write_csv(bind_partitions("tooth_check"), "deal_value_quantile_tooth_check.csv")
write_csv(bind_partitions("certification"), "deal_value_quantile_certification.csv")
write_csv(contribution_event, "deal_value_quantile_pooled_contributions_event.csv")
write_csv(contribution_post, "deal_value_quantile_pooled_contributions_post.csv")
write_csv(pooled_identity, "deal_value_quantile_pooled_identity.csv")
write_csv(resolved_nonidentity, "deal_value_quantile_resolved_nonidentity.csv")

estimation_manifest <- data.frame(
  version = "lmv2_deal_value_quantile_estimation_v2",
  designation = DESIGNATION,
  outcome = "patent_count",
  estimand = "average_annual_t1_to_t5_relative_to_tminus1",
  weight_scheme = WEIGHT_SCHEME,
  control_rescaling = "within_cohort_by_bin",
  bootstrap_replications = BOOTSTRAP_REPS,
  bootstrap_seed = cfg$inference$bootstrap_seed,
  individual_governing_rule = "wider_of_deal_wild_and_two_way_ci",
  omnibus_governing_rule = "larger_of_deal_wild_and_two_way_p",
  all_certification_pass = all(bind_partitions("certification")$pass),
  pooled_contribution_identity_pass = all(pooled_identity$pass),
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
write_csv(estimation_manifest, "deal_value_quantile_estimation_manifest.csv")
message(sprintf(
  "Quantile estimation complete: decile omnibus p=%.4f; quartile omnibus p=%.4f.",
  decile$omnibus$governing_p, quartile$omnibus$governing_p
))
