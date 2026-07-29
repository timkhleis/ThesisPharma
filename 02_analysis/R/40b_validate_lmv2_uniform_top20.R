# ============================================================================
# Outcome-blind validation for the independent uniform top-20 branch
# ============================================================================
# Reads only the certified -5 through -1 prepanel. It never opens the analysis
# database or any post-period outcome artifact.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "data.table", "digest", "MASS")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "40a_lmv2_uniform_top20_config.R"))
config <- lmv2_uniform_top20_config()
freeze_sha256 <- lmv2_uniform_assert_freeze(config)
dir.create(config$validation_dir, recursive = TRUE, showWarnings = FALSE)

source_path <- file.path(BASE, "R", "40b_validate_lmv2_uniform_top20.R")
source_sha256 <- lmv2_uniform_sha256(source_path)
config_path <- file.path(BASE, "R", "40a_lmv2_uniform_top20_config.R")
config_sha256 <- lmv2_uniform_sha256(config_path)
census_manifest_path <- file.path(
  config$source_census_dir, "census_manifest.csv")
if (!file.exists(census_manifest_path)) stop("Missing source census manifest")
census_manifest_sha256 <- lmv2_uniform_sha256(census_manifest_path)
if (!identical(
    tolower(census_manifest_sha256),
    tolower(config$expected_census_manifest_sha256))) {
  stop("Source census manifest hash mismatch")
}
census <- utils::read.csv(census_manifest_path, stringsAsFactors = FALSE)
if (nrow(census) != 1L ||
    !isTRUE(as.logical(census$census_pass)) ||
    !identical(census$status, "CERTIFIED_TO_VALIDATE") ||
    as.integer(census$maximum_outcome_event_time) != -1L ||
    isTRUE(as.logical(census$post_outcomes_queried)) ||
    isTRUE(as.logical(census$optimized_weights_estimated))) {
  stop("Uniform validation requires the certified pre-period census")
}
required_inputs <- c(
  config$prepanel_path,
  config$units_path,
  config$candidate_pools_path,
  config$screening_features_path)
if (any(!file.exists(required_inputs))) {
  stop("Uniform validation input is missing")
}
if (!identical(
    tolower(lmv2_uniform_sha256(config$prepanel_path)),
    tolower(census$prepanel_sha256)) ||
    !identical(
      tolower(lmv2_uniform_sha256(config$units_path)),
      tolower(census$units_sha256)) ||
    !identical(
      tolower(lmv2_uniform_sha256(config$candidate_pools_path)),
      tolower(census$candidate_pools_sha256))) {
  stop("Uniform validation input hash mismatch")
}

read_parquet <- function(path) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  quoted <- as.character(DBI::dbQuoteString(
    con, normalizePath(path, winslash = "/", mustWork = TRUE)))
  data.table::as.data.table(DBI::dbGetQuery(
    con, paste0("SELECT * FROM read_parquet(", quoted, ")")))
}

safe_inverse <- function(x) {
  tryCatch(solve(x), error = function(e) MASS::ginv(x))
}

weighted_joint <- function(deal, deal_weights) {
  wide <- data.table::dcast(
    deal, deal_id ~ event_time, value.var = "raw_gap")
  ids <- wide$deal_id
  x <- as.matrix(wide[, -1])
  a <- deal_weights[as.character(ids)]
  a <- a / sum(a)
  mu <- colSums(x * a)
  influence <- sweep(x, 2, mu, "-") * a
  g <- nrow(influence)
  covariance <- g / max(g - 1, 1) * crossprod(influence)
  list(
    ids = ids, x = x, a = a, mu = mu, influence = influence,
    covariance = covariance,
    statistic = as.numeric(
      t(mu) %*% safe_inverse(covariance) %*% mu))
}

message("Uniform top-20: load certified preperiod panel")
panel <- read_parquet(config$prepanel_path)
if (!identical(as.integer(range(panel$event_time)), c(-5L, -1L)) ||
    data.table::uniqueN(panel$deal_id) != config$expected_deals ||
    any(!is.finite(panel$treated_outcome)) ||
    any(!is.finite(panel$donor_outcome))) {
  stop("Uniform prepanel invariant failed")
}
donor_counts <- unique(panel[, .(deal_id, donor_group)])[
  , .N, by = deal_id]
if (any(donor_counts$N != config$expected_donors_per_deal)) {
  stop("Uniform donor count invariant failed")
}

deal <- panel[, .(
  cohort = unique(cohort),
  n_treated = unique(n_treated),
  treated_raw = unique(treated_outcome),
  synthetic_raw = mean(donor_outcome),
  treated_log = unique(log1p(treated_outcome)),
  synthetic_log = mean(log1p(donor_outcome))),
  by = .(deal_id, event_time)]
deal[, `:=`(
  raw_gap = treated_raw - synthetic_raw,
  log_gap = treated_log - synthetic_log)]
deal_info <- unique(deal[, .(deal_id, cohort, n_treated)])
if (sum(deal_info$n_treated) != config$expected_treated_inventors) {
  stop("Uniform treated count invariant failed")
}
deal_info[, inventor_weight := n_treated / sum(n_treated)]
deal_info[, equal_deal_weight := 1 / .N]
deal_weights <- setNames(
  deal_info$inventor_weight, as.character(deal_info$deal_id))
deal <- merge(
  deal, deal_info[, .(
    deal_id, inventor_weight, equal_deal_weight)],
  by = "deal_id", sort = FALSE)

pooled <- deal[, .(
  treated_raw = sum(inventor_weight * treated_raw),
  synthetic_raw = sum(inventor_weight * synthetic_raw),
  raw_gap = sum(inventor_weight * raw_gap),
  treated_log = sum(inventor_weight * treated_log),
  synthetic_log = sum(inventor_weight * synthetic_log),
  log_gap = sum(inventor_weight * log_gap)),
  by = event_time][order(event_time)]
equal_deal <- deal[, .(
  treated_raw = sum(equal_deal_weight * treated_raw),
  synthetic_raw = sum(equal_deal_weight * synthetic_raw),
  raw_gap = sum(equal_deal_weight * raw_gap),
  treated_log = sum(equal_deal_weight * treated_log),
  synthetic_log = sum(equal_deal_weight * synthetic_log),
  log_gap = sum(equal_deal_weight * log_gap)),
  by = event_time][order(event_time)]

validation_deal <- deal[event_time %in% config$validation_times]
validation_pooled <- pooled[event_time %in% config$validation_times]
validation_rmse <- sqrt(mean(validation_pooled$raw_gap^2))
validation_max_gap <- max(abs(validation_pooled$raw_gap))
joint <- weighted_joint(validation_deal, deal_weights)

message("Uniform top-20: run fixed-weight Webb joint validation")
set.seed(config$validation_bootstrap_seed)
webb <- c(
  -sqrt(1.5), -1, -sqrt(0.5),
  sqrt(0.5), 1, sqrt(1.5))
b <- config$validation_bootstrap_replications
bootstrap <- vector("list", b)
for (r in seq_len(b)) {
  multiplier <- sample(webb, nrow(joint$x), replace = TRUE)
  pseudo_x <- sweep(
    sweep(joint$x, 2, joint$mu, "-"),
    1, multiplier, "*")
  pseudo_mu <- colSums(pseudo_x * joint$a)
  pseudo_influence <- sweep(
    pseudo_x, 2, pseudo_mu, "-") * joint$a
  pseudo_v <- nrow(pseudo_influence) /
    max(nrow(pseudo_influence) - 1, 1) *
    crossprod(pseudo_influence)
  bootstrap[[r]] <- data.frame(
    replication = r,
    statistic = as.numeric(
      t(pseudo_mu) %*% safe_inverse(pseudo_v) %*% pseudo_mu),
    gap_m3 = pseudo_mu[[1]],
    gap_m2 = pseudo_mu[[2]],
    gap_m1 = pseudo_mu[[3]])
}
bootstrap <- data.table::rbindlist(bootstrap)
joint_webb_p <- (
  1 + sum(bootstrap$statistic >= joint$statistic)) / (b + 1)
joint_chisq_p <- stats::pchisq(
  joint$statistic, df = length(config$validation_times),
  lower.tail = FALSE)

loco <- data.table::rbindlist(lapply(
  sort(unique(validation_deal$cohort)), function(drop_cohort) {
    z <- validation_deal[cohort != drop_cohort]
    z[, weight := n_treated / sum(n_treated), by = event_time]
    z[, .(
      dropped_cohort = drop_cohort,
      raw_gap = sum(weight * raw_gap)),
      by = event_time]
  }))

contribution <- validation_deal[
  , .(absolute_contribution = max(abs(inventor_weight * raw_gap))),
  by = deal_id][order(-absolute_contribution)]
top10 <- head(contribution$deal_id, 10L)
influence_delete <- data.table::rbindlist(lapply(top10, function(drop_deal) {
  z <- validation_deal[deal_id != drop_deal]
  z[, weight := n_treated / sum(n_treated), by = event_time]
  z[, .(
    deleted_deal = drop_deal,
    raw_gap = sum(weight * raw_gap)),
    by = event_time]
}))

effective_deals <- 1 / sum(deal_info$inventor_weight^2)
maximum_deal_share <- max(deal_info$inventor_weight)
equal_validation <- equal_deal[
  event_time %in% config$validation_times]
equal_rmse <- sqrt(mean(equal_validation$raw_gap^2))
equal_max_gap <- max(abs(equal_validation$raw_gap))

gate <- data.frame(
  gate = c(
    "input_integrity",
    "exact_sample_and_donor_counts",
    "validation_rmse_at_most_0_05",
    "each_validation_gap_within_0_05",
    "joint_webb_p_above_0_10",
    "effective_deals_at_least_20",
    "leave_one_cohort_out_within_0_075",
    "largest_contribution_deletions_within_0_075"),
  value = c(
    1, 1, validation_rmse, validation_max_gap,
    joint_webb_p, effective_deals,
    max(abs(loco$raw_gap)),
    max(abs(influence_delete$raw_gap))),
  threshold = c(
    "TRUE", "235 deals; 10818 inventors; 20 donors",
    "<=0.05", "<=0.05", ">0.10", ">=20",
    "<=0.075", "<=0.075"),
  pass = c(
    TRUE,
    data.table::uniqueN(deal$deal_id) == config$expected_deals &&
      sum(deal_info$n_treated) == config$expected_treated_inventors &&
      all(donor_counts$N == config$expected_donors_per_deal),
    validation_rmse <= config$validation_rmse_limit,
    validation_max_gap <= config$validation_gap_limit,
    joint_webb_p > 0.10,
    effective_deals >= config$minimum_effective_deals,
    max(abs(loco$raw_gap)) <= config$deletion_gap_limit,
    max(abs(influence_delete$raw_gap)) <=
      config$deletion_gap_limit),
  governing = TRUE,
  stringsAsFactors = FALSE)
validation_pass <- all(gate$pass)

lmv2_uniform_atomic_csv(
  deal[order(deal_id, event_time)],
  file.path(config$validation_dir, "uniform_deal_paths.csv"))
lmv2_uniform_atomic_csv(
  pooled,
  file.path(config$validation_dir, "uniform_inventor_weighted_paths.csv"))
lmv2_uniform_atomic_csv(
  equal_deal,
  file.path(config$validation_dir, "uniform_equal_deal_paths.csv"))
lmv2_uniform_atomic_csv(
  data.frame(
    event_time = config$validation_times,
    gap = joint$mu,
    stringsAsFactors = FALSE),
  file.path(config$validation_dir, "joint_validation_gap_vector.csv"))
lmv2_uniform_atomic_csv(
  data.frame(
    event_time_row = config$validation_times,
    joint$covariance,
    check.names = FALSE),
  file.path(config$validation_dir, "joint_validation_covariance.csv"))
lmv2_uniform_atomic_csv(
  bootstrap,
  file.path(config$validation_dir, "joint_webb_bootstrap_draws.csv"))
lmv2_uniform_atomic_csv(
  loco,
  file.path(config$validation_dir, "leave_one_cohort_out.csv"))
lmv2_uniform_atomic_csv(
  influence_delete,
  file.path(config$validation_dir, "influence_deletions.csv"))
lmv2_uniform_atomic_csv(
  gate,
  file.path(config$validation_dir, "validation_gate.csv"))

summary <- data.frame(
  version = config$version,
  source_sha256 = source_sha256,
  config_sha256 = config_sha256,
  freeze_sha256 = freeze_sha256,
  census_manifest_sha256 = census_manifest_sha256,
  prepanel_sha256 = lmv2_uniform_sha256(config$prepanel_path),
  retained_deals = data.table::uniqueN(deal$deal_id),
  retained_treated_inventors = sum(deal_info$n_treated),
  donors_per_deal = unique(donor_counts$N),
  effective_deals = effective_deals,
  maximum_deal_weight_share = maximum_deal_share,
  validation_rmse = validation_rmse,
  validation_max_abs_gap = validation_max_gap,
  joint_wald_statistic = joint$statistic,
  joint_webb_p_value = joint_webb_p,
  joint_chisq_p_value = joint_chisq_p,
  equal_deal_validation_rmse = equal_rmse,
  equal_deal_validation_max_abs_gap = equal_max_gap,
  bootstrap_replications = b,
  maximum_outcome_event_time = -1L,
  post_outcomes_queried = FALSE,
  validation_pass = validation_pass,
  status = if (validation_pass) {
    "CERTIFIED_TO_CONTROL_NULL"
  } else {
    "VALIDATION_FAILED"
  },
  stringsAsFactors = FALSE)
lmv2_uniform_atomic_csv(
  summary,
  file.path(config$validation_dir, "validation_manifest.csv"))

artifact_paths <- list.files(config$validation_dir, full.names = TRUE)
artifact_paths <- artifact_paths[
  basename(artifact_paths) != "artifact_hashes.csv" &
    !file.info(artifact_paths)$isdir]
artifact_hashes <- data.frame(
  artifact = basename(artifact_paths),
  sha256 = vapply(
    artifact_paths, lmv2_uniform_sha256, character(1)),
  stringsAsFactors = FALSE)
lmv2_uniform_atomic_csv(
  artifact_hashes,
  file.path(config$validation_dir, "artifact_hashes.csv"))

message(
  "Uniform top-20 validation ", summary$status,
  " | RMSE=", sprintf("%.5f", validation_rmse),
  " | joint Webb p=", sprintf("%.4f", joint_webb_p),
  " | post queried=FALSE")
