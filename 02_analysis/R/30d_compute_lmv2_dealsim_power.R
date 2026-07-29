# ============================================================================
# 30d_compute_lmv2_dealsim_power.R -- joint contrast MDE and path gate
# ============================================================================
# Uses the certified P5c patent-count influence construction.  Subgroup point
# estimates are never written or printed.  The two frozen contrasts are
# calibrated jointly with Webb multiplier draws at the deal level.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "30a_lmv2_dealsim_power_config.R"))

cfg <- LMV2_DEALSIM_POWER
out_dir <- cfg$output_dir
assignment_path <- file.path(out_dir, "dealsim_tercile_assignment.csv")
support_path <- file.path(out_dir, "dealsim_tercile_support.csv")
assignment_manifest_path <- file.path(
  out_dir, "dealsim_assignment_manifest.csv"
)
if (!all(file.exists(c(
  assignment_path, support_path, assignment_manifest_path
)))) {
  stop("Run 30b and 30c before computing DealSim MDEs")
}
assignment_manifest <- utils::read.csv(
  assignment_manifest_path, stringsAsFactors = FALSE
)
if (nrow(assignment_manifest) != 1L ||
    assignment_manifest$dealsim_power_hash != lmv2_dealsim_power_hash()) {
  stop("DealSim assignment manifest is stale")
}

deals <- utils::read.csv(assignment_path, stringsAsFactors = FALSE)
support <- utils::read.csv(support_path, stringsAsFactors = FALSE)
lmv2_assert_dealsim_rows(deals)
common_cohorts <- as.integer(strsplit(
  assignment_manifest$common_cohorts, ";", fixed = TRUE
)[[1]])
if (length(common_cohorts) <
    cfg$power$minimum_common_cohorts) {
  message("Common-cohort count is below the frozen review threshold")
}

panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
stamp_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$",
  full.names = TRUE
))
panel_sql_all <- lmv2_panel_sql(panel_files)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
temp_dir <- file.path(out_dir, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))
input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, cfg$inputs$construction_manifest
)
if (!isTRUE(input_checks$pass[[1]])) {
  stop("Certified P5c panel did not pass the inherited estimator checks")
}

extract_deal_scores <- function(ids, cohorts, sample_id) {
  panel_sql <- sprintf(
    "(SELECT * FROM %s WHERE deal_id IN (%s) AND cohort IN (%s))",
    panel_sql_all,
    paste(as.integer(ids), collapse = ","),
    paste(as.integer(cohorts), collapse = ",")
  )
  pair_table <- lmv2_build_pair_table(
    con, panel_sql, cfg$estimand$primary_outcome, cohorts, sample_id
  )
  influence_table <- lmv2_prepare_influence_table(
    con, pair_table, panel_sql, cohorts
  )
  DBI::dbExecute(con, sprintf("DROP TABLE %s", pair_table))
  post_sql <- paste(cfg$estimand$post_event_times, collapse = ",")
  out <- DBI::dbGetQuery(con, sprintf("
    SELECT deal_id,
           SUM(influence)/%d AS score
    FROM %s
    WHERE event_time IN (%s)
    GROUP BY deal_id
    ORDER BY deal_id
  ", length(cfg$estimand$post_event_times), influence_table, post_sql))
  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
  if (!nrow(out) || abs(sum(out$score)) > 1e-8) {
    stop("Deal-level post influence scores are invalid")
  }
  out
}

calibrate_joint_mde <- function(score_matrix, seed) {
  score_matrix <- as.matrix(score_matrix)
  score_matrix <- sweep(score_matrix, 2L, colMeans(score_matrix), "-")
  G <- nrow(score_matrix)
  covariance <- G / (G - 1) * crossprod(score_matrix)
  standard_error <- sqrt(diag(covariance))
  if (any(!is.finite(standard_error)) || any(standard_error <= 0)) {
    stop("Contrast standard errors are invalid")
  }
  set.seed(seed)
  webb_support <- c(
    -sqrt(3 / 2), -1, -sqrt(1 / 2),
    sqrt(1 / 2), 1, sqrt(3 / 2)
  )
  B <- cfg$power$bootstrap_replications
  max_t <- numeric(B)
  block_size <- 500L
  for (start in seq.int(1L, B, by = block_size)) {
    stop_at <- min(B, start + block_size - 1L)
    mult <- matrix(
      sample(
        webb_support, (stop_at - start + 1L) * G,
        replace = TRUE
      ),
      nrow = stop_at - start + 1L, ncol = G
    )
    draws <- mult %*% score_matrix
    draws <- sweep(draws, 2L, standard_error, "/")
    max_t[start:stop_at] <- apply(abs(draws), 1L, max)
  }
  critical_value <- unname(stats::quantile(
    max_t, 1 - cfg$power$family_alpha, type = 7
  ))
  mde <- (
    critical_value + stats::qnorm(cfg$power$target)
  ) * standard_error
  list(
    standard_error = standard_error,
    critical_value = critical_value,
    mde = mde,
    nominal_deals = G
  )
}

score_tables <- list()
labels <- cfg$construction$tercile_labels
for (label in labels) {
  ids <- deals$deal_id[
    deals$eligible_dealsim & deals$tercile == label &
      deals$cohort %in% common_cohorts
  ]
  if (!length(ids)) stop("No common-cohort deals in tercile ", label)
  deal_scores <- extract_deal_scores(
    ids, common_cohorts, paste0("dealsim_power_", label)
  )
  deal_scores$tercile <- label
  score_tables[[label]] <- deal_scores
}

scores_long <- do.call(rbind, score_tables)
all_deals <- sort(unique(scores_long$deal_id))
score_matrix <- matrix(
  0, nrow = length(all_deals), ncol = length(labels),
  dimnames = list(as.character(all_deals), labels)
)
for (label in labels) {
  z <- scores_long[scores_long$tercile == label, ]
  score_matrix[as.character(z$deal_id), label] <- z$score
}
contrast_scores <- cbind(
  low_minus_middle =
    score_matrix[, "low"] - score_matrix[, "middle"],
  high_minus_middle =
    score_matrix[, "high"] - score_matrix[, "middle"]
)
tercile_calibration <- calibrate_joint_mde(
  contrast_scores, cfg$power$bootstrap_seed
)
contrast_se <- tercile_calibration$standard_error
critical_value <- tercile_calibration$critical_value
mde <- tercile_calibration$mde
power_table <- data.frame(
  contrast = names(contrast_se),
  standard_error = unname(contrast_se),
  joint_max_t_critical_value = critical_value,
  target_power = cfg$power$target,
  family_alpha = cfg$power$family_alpha,
  mde_annual_patents = unname(mde),
  meaningful_annual_contrast =
    cfg$estimand$meaningful_annual_contrast,
  mde_to_meaningful_ratio =
    unname(mde) / cfg$estimand$meaningful_annual_contrast,
  tercile_power_pass =
    unname(mde) <= cfg$estimand$meaningful_annual_contrast,
  stringsAsFactors = FALSE
)

# Continuous quadratic screen.  Recover a deal-level residual scale from the
# full eligible-sample influence score and project that scale through a
# weighted quadratic DealSim design.  Only contrast precision is retained.
eligible_for_continuous <- deals[
  deals$eligible_dealsim, c(
    "deal_id", "cohort", "dealsim", "tercile", "treated_weight"
  )
]
continuous_deal_scores <- extract_deal_scores(
  eligible_for_continuous$deal_id,
  sort(unique(eligible_for_continuous$cohort)),
  "dealsim_power_continuous"
)
continuous_design <- merge(
  eligible_for_continuous, continuous_deal_scores,
  by = "deal_id", all.x = TRUE, sort = TRUE
)
if (anyNA(continuous_design$score) ||
    nrow(continuous_design) != nrow(eligible_for_continuous)) {
  stop("Continuous power screen lost an eligible deal")
}
w <- continuous_design$treated_weight /
  sum(continuous_design$treated_weight)
x_mean <- sum(w * continuous_design$dealsim)
x_sd <- sqrt(sum(w * (continuous_design$dealsim - x_mean)^2))
if (!is.finite(x_sd) || x_sd <= 0) stop("DealSim has no usable variation")
z <- (continuous_design$dealsim - x_mean) / x_sd
X <- cbind(intercept = 1, dealsim_z = z, dealsim_z2 = z^2)
u <- continuous_design$score / w
A_inv <- solve(crossprod(X, w * X))
coefficient_influence <- sweep(X, 1L, w * u, "*") %*% t(A_inv)
tercile_centers <- vapply(labels, function(label) {
  keep <- continuous_design$tercile == label
  stats::weighted.mean(z[keep], w[keep])
}, numeric(1))
continuous_contrast_matrix <- rbind(
  low_minus_middle = c(
    0,
    tercile_centers[["low"]] - tercile_centers[["middle"]],
    tercile_centers[["low"]]^2 - tercile_centers[["middle"]]^2
  ),
  high_minus_middle = c(
    0,
    tercile_centers[["high"]] - tercile_centers[["middle"]],
    tercile_centers[["high"]]^2 - tercile_centers[["middle"]]^2
  )
)
continuous_contrast_scores <- coefficient_influence %*%
  t(continuous_contrast_matrix)
continuous_calibration <- calibrate_joint_mde(
  continuous_contrast_scores, cfg$power$bootstrap_seed + 1L
)
continuous_power <- data.frame(
  contrast = names(continuous_calibration$standard_error),
  model = cfg$power$continuous_basis,
  standard_error = unname(continuous_calibration$standard_error),
  joint_max_t_critical_value = continuous_calibration$critical_value,
  target_power = cfg$power$target,
  family_alpha = cfg$power$family_alpha,
  mde_annual_patents = unname(continuous_calibration$mde),
  meaningful_annual_contrast =
    cfg$estimand$meaningful_annual_contrast,
  mde_to_meaningful_ratio =
    unname(continuous_calibration$mde) /
      cfg$estimand$meaningful_annual_contrast,
  continuous_power_pass =
    unname(continuous_calibration$mde) <=
      cfg$estimand$meaningful_annual_contrast,
  stringsAsFactors = FALSE
)

common_support <- support[support$sample == "common_cohort_set", ]
support_pass <- nrow(common_support) == 3L &&
  all(common_support$effective_deals >= cfg$power$effective_deal_floor) &&
  all(common_support$largest_deal_share <= cfg$power$maximum_deal_share) &&
  length(common_cohorts) >= cfg$power$minimum_common_cohorts
tercile_power_pass <- all(power_table$tercile_power_pass)
continuous_effective_deals <- lmv2_effective_count(
  continuous_design$treated_weight
)
continuous_largest_deal_share <- max(w)
continuous_support_pass <-
  nrow(continuous_design) >= 30L &&
  continuous_effective_deals >= cfg$power$effective_deal_floor &&
  continuous_largest_deal_share <= cfg$power$maximum_deal_share
continuous_screen_pass <- continuous_support_pass &&
  all(continuous_power$continuous_power_pass)
selected_path <- if (support_pass && tercile_power_pass) {
  "T"
} else if (continuous_screen_pass) {
  "C"
} else {
  "U"
}

gate <- data.frame(
  selected_path = selected_path,
  path_description = cfg$paths[[selected_path]],
  common_cohort_count = length(common_cohorts),
  common_cohorts = paste(common_cohorts, collapse = ";"),
  minimum_tercile_effective_deals =
    min(common_support$effective_deals),
  maximum_tercile_deal_share =
    max(common_support$largest_deal_share),
  support_gate_pass = support_pass,
  maximum_joint_mde = max(power_table$mde_annual_patents),
  continuous_effective_deals = continuous_effective_deals,
  continuous_largest_deal_share = continuous_largest_deal_share,
  continuous_support_gate_pass = continuous_support_pass,
  maximum_continuous_joint_mde =
    max(continuous_power$mde_annual_patents),
  meaningful_annual_contrast =
    cfg$estimand$meaningful_annual_contrast,
  tercile_power_gate_pass = tercile_power_pass,
  continuous_screen_pass = continuous_screen_pass,
  subgroup_att_saved = FALSE,
  subgroup_att_printed = FALSE,
  stringsAsFactors = FALSE
)
utils::write.csv(
  power_table, file.path(out_dir, "dealsim_contrast_mde.csv"),
  row.names = FALSE
)
utils::write.csv(
  continuous_power, file.path(out_dir, "dealsim_continuous_mde.csv"),
  row.names = FALSE
)
utils::write.csv(
  gate, file.path(out_dir, "dealsim_power_gate.csv"),
  row.names = FALSE
)
utils::write.csv(
  data.frame(
    bootstrap_type = cfg$power$bootstrap_type,
    bootstrap_replications = cfg$power$bootstrap_replications,
    bootstrap_seed = cfg$power$bootstrap_seed,
    family_alpha = cfg$power$family_alpha,
    joint_max_t_critical_value = critical_value,
    nominal_common_deals = tercile_calibration$nominal_deals,
    continuous_bootstrap_seed = cfg$power$bootstrap_seed + 1L,
    continuous_joint_max_t_critical_value =
      continuous_calibration$critical_value,
    continuous_nominal_deals = continuous_calibration$nominal_deals,
    stringsAsFactors = FALSE
  ),
  file.path(out_dir, "dealsim_mde_calibration.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  dealsim_power_hash = lmv2_dealsim_power_hash(),
  assignment_sha256 = digest::digest(
    file = assignment_path, algo = "sha256"
  ),
  support_sha256 = digest::digest(file = support_path, algo = "sha256"),
  source_sha256 = digest::digest(
    file = file.path(BASE, "R", "30d_compute_lmv2_dealsim_power.R"),
    algo = "sha256"
  ),
  primary_outcome_used_for_variance = cfg$estimand$primary_outcome,
  subgroup_att_computed = FALSE,
  subgroup_att_saved = FALSE,
  selected_path = selected_path,
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "dealsim_power_manifest.csv"),
  row.names = FALSE
)
message(
  "DealSim Stage A power gate selected Path ", selected_path,
  ". No subgroup ATT was saved or printed."
)
