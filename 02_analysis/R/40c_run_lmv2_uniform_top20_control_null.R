# ============================================================================
# Control-only pipeline falsification for the uniform top-20 branch
# ============================================================================
# This stage opens post-period outcomes only for acquisition-clean control
# inventors. It never reads real treated post-period outcomes or a real ATT.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c(
    "DBI", "duckdb", "data.table", "digest", "Matrix")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "40a_lmv2_uniform_top20_config.R"))
config <- lmv2_uniform_top20_config()
freeze_sha256 <- lmv2_uniform_assert_freeze(config)
dir.create(config$control_null_dir, recursive = TRUE, showWarnings = FALSE)

source_path <- file.path(
  BASE, "R", "40c_run_lmv2_uniform_top20_control_null.R")
source_sha256 <- lmv2_uniform_sha256(source_path)
config_path <- file.path(BASE, "R", "40a_lmv2_uniform_top20_config.R")
config_sha256 <- lmv2_uniform_sha256(config_path)
validation_manifest_path <- file.path(
  config$validation_dir, "validation_manifest.csv")
validation_hash_path <- file.path(
  config$validation_dir, "artifact_hashes.csv")
if (!file.exists(validation_manifest_path) ||
    !file.exists(validation_hash_path)) {
  stop("Missing uniform validation certification")
}
validation <- utils::read.csv(
  validation_manifest_path, stringsAsFactors = FALSE)
if (nrow(validation) != 1L ||
    !isTRUE(as.logical(validation$validation_pass)) ||
    !identical(validation$status, "CERTIFIED_TO_CONTROL_NULL") ||
    as.integer(validation$maximum_outcome_event_time) != -1L ||
    isTRUE(as.logical(validation$post_outcomes_queried)) ||
    !identical(
      tolower(validation$freeze_sha256), tolower(freeze_sha256)) ||
    !identical(
      tolower(validation$config_sha256), tolower(config_sha256))) {
  stop("Control-null stage requires current certified validation")
}
validation_artifacts <- utils::read.csv(
  validation_hash_path, stringsAsFactors = FALSE)
for (i in seq_len(nrow(validation_artifacts))) {
  path <- file.path(
    config$validation_dir, validation_artifacts$artifact[[i]])
  if (!file.exists(path) ||
      !identical(
        tolower(lmv2_uniform_sha256(path)),
        tolower(validation_artifacts$sha256[[i]]))) {
    stop("Validation artifact hash mismatch: ", basename(path))
  }
}
validation_manifest_sha256 <- lmv2_uniform_sha256(
  validation_manifest_path)

sql_string <- function(con, x) {
  as.character(DBI::dbQuoteString(con, x))
}

atomic_parquet <- function(con, x, path, order_by) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  table_name <- paste0(
    "uniform_publish_", as.integer(stats::runif(1, 1, 1e9)))
  duckdb::duckdb_register(con, table_name, as.data.frame(x))
  on.exit(duckdb::duckdb_unregister(con, table_name), add = TRUE)
  tmp <- paste0(path, ".tmp.parquet")
  if (file.exists(tmp) && !file.remove(tmp)) {
    stop("Could not clear temporary parquet")
  }
  DBI::dbExecute(con, sprintf(
    "COPY (SELECT * FROM %s ORDER BY %s) TO %s
     (FORMAT PARQUET, COMPRESSION ZSTD)",
    table_name, order_by,
    sql_string(con, normalizePath(
      tmp, winslash = "/", mustWork = FALSE))))
  if (file.exists(path) && !file.remove(path)) {
    stop("Could not replace ", path)
  }
  if (!file.rename(tmp, path)) stop("Could not publish ", path)
  invisible(path)
}

weighted_scalar_inference <- function(x, weights, reps, seed) {
  weights <- weights / sum(weights)
  estimate <- sum(weights * x)
  centered <- x - estimate
  g <- length(x)
  influence <- weights * centered
  se <- sqrt(g / max(g - 1, 1) * sum(influence^2))
  t_observed <- if (se > 0) estimate / se else 0
  set.seed(seed)
  webb <- c(
    -sqrt(1.5), -1, -sqrt(0.5),
    sqrt(0.5), 1, sqrt(1.5))
  multipliers <- matrix(
    sample(webb, g * reps, replace = TRUE),
    nrow = g, ncol = reps)
  pseudo_x <- centered * multipliers
  pseudo_estimate <- colSums(pseudo_x * weights)
  pseudo_centered <- sweep(pseudo_x, 2, pseudo_estimate, "-")
  pseudo_se <- sqrt(
    g / max(g - 1, 1) *
      colSums((pseudo_centered * weights)^2))
  pseudo_t <- ifelse(
    pseudo_se > 0, pseudo_estimate / pseudo_se, 0)
  p_value <- (
    1 + sum(abs(pseudo_t) >= abs(t_observed))) / (reps + 1)
  critical <- as.numeric(stats::quantile(
    abs(pseudo_t), 0.95, names = FALSE, type = 1))
  list(
    estimate = estimate, se = se, t = t_observed,
    p_value = p_value,
    ci_low = estimate - critical * se,
    ci_high = estimate + critical * se)
}

message("Uniform control null: open control-only outcome universe")
con <- DBI::dbConnect(
  duckdb::duckdb(), dbdir = config$database, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(
  con, paste0("SET threads=", config$execution$threads))
DBI::dbExecute(
  con, paste0(
    "SET memory_limit=",
    sql_string(con, config$execution$memory_limit)))
units_sql <- sql_string(
  con, normalizePath(config$units_path, winslash = "/", mustWork = TRUE))
features_sql <- sql_string(
  con, normalizePath(
    config$screening_features_path, winslash = "/", mustWork = TRUE))
DBI::dbExecute(con, paste0(
  "CREATE OR REPLACE TEMP VIEW uniform_units AS
   SELECT * FROM read_parquet(", units_sql, ")"))
DBI::dbExecute(con, paste0(
  "CREATE OR REPLACE TEMP VIEW uniform_features AS
   SELECT * FROM read_parquet(", features_sql, ")"))

control_paths <- data.table::as.data.table(DBI::dbGetQuery(con, "
WITH times AS (
  SELECT UNNEST(range(-5,6))::INTEGER event_time
), control_units AS (
  SELECT cohort,focal_group,codinv
  FROM uniform_units
  WHERE arm='control'
)
SELECT u.cohort,CAST(u.focal_group AS BIGINT) focal_group,t.event_time,
       COUNT(DISTINCT u.codinv)::INTEGER cohort_size,
       AVG(COALESCE(y.patent_count,0))::DOUBLE outcome
FROM control_units u
CROSS JOIN times t
LEFT JOIN inventor_year y
  ON CAST(y.codinv AS BIGINT)=u.codinv
 AND y.year=u.cohort+t.event_time
GROUP BY u.cohort,u.focal_group,t.event_time
ORDER BY u.cohort,u.focal_group,t.event_time
"))
if (!identical(
    as.integer(range(control_paths$event_time)), c(-5L, 5L)) ||
    any(!is.finite(control_paths$outcome))) {
  stop("Control-only outcome materialization failed")
}

features <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT CAST(cohort AS INTEGER) cohort,
       CAST(focal_group AS BIGINT) focal_group,
       z_log1p_mean_patent_m5,z_log1p_mean_patent_m4,
       z_active_share_m5,z_active_share_m4,
       z_log_firm_patent_m5,z_log_firm_patent_m4,
       z_log_firm_inventors_m5,z_log_firm_inventors_m4,
       z_mean_career_age_m4,z_median_career_age_m4
FROM uniform_features
WHERE arm='control'
ORDER BY cohort,focal_group
"))
zvars <- setdiff(names(features), c("cohort", "focal_group"))
if (any(!is.finite(as.matrix(features[, ..zvars])))) {
  stop("Control screening feature contains a non-finite value")
}

ipc <- data.table::as.data.table(DBI::dbGetQuery(con, "
WITH roster AS (
  SELECT DISTINCT cohort,CAST(focal_group AS BIGINT) focal_group
  FROM uniform_units WHERE arm='control'
), weighted AS (
  SELECT r.cohort,r.focal_group,SUBSTR(g.ipc_code,1,4) ipc4,
         SUM(g.patent_count)::DOUBLE weight
  FROM roster r
  JOIN group_ipc_year g
    ON CAST(g.id_group AS BIGINT)=r.focal_group
   AND g.year BETWEEN r.cohort-7 AND r.cohort-4
  WHERE g.ipc_code IS NOT NULL AND LENGTH(g.ipc_code)>=4
  GROUP BY r.cohort,r.focal_group,SUBSTR(g.ipc_code,1,4)
)
SELECT cohort,focal_group,ipc4,
       weight/SUM(weight) OVER
         (PARTITION BY cohort,focal_group) frequency
FROM weighted
ORDER BY cohort,focal_group,ipc4
"))

valid_firms <- unique(ipc[, .(cohort, focal_group)])
features <- merge(
  features, valid_firms, by = c("cohort", "focal_group"))
valid_feature_firms <- unique(features[, .(cohort, focal_group)])
control_info <- unique(control_paths[, .(
  cohort, focal_group, cohort_size)])
control_info <- merge(
  control_info, valid_feature_firms,
  by = c("cohort", "focal_group"))

message("Uniform control null: build exact cached donor rankings")
rank_blocks <- vector("list", data.table::uniqueN(features$cohort))
rank_index <- 0L
for (cohort_value in sort(unique(features$cohort))) {
  rank_index <- rank_index + 1L
  f <- features[cohort == cohort_value][order(focal_group)]
  groups <- f$focal_group
  z <- as.matrix(f[, ..zvars])
  scalar_distance2 <- outer(
    rowSums(z^2), rowSums(z^2), "+") -
    2 * tcrossprod(z)
  scalar_distance2[scalar_distance2 < 0] <- 0
  iv <- ipc[
    cohort == cohort_value & focal_group %in% groups]
  ipc_codes <- sort(unique(iv$ipc4))
  sparse <- Matrix::sparseMatrix(
    i = match(iv$focal_group, groups),
    j = match(iv$ipc4, ipc_codes),
    x = iv$frequency,
    dims = c(length(groups), length(ipc_codes)))
  norms <- sqrt(Matrix::rowSums(sparse^2))
  sparse <- Matrix::Diagonal(x = 1 / norms) %*% sparse
  cosine <- as.matrix(Matrix::tcrossprod(sparse))
  cosine <- pmin(1, pmax(0, cosine))
  distance2 <- scalar_distance2 + (1 - cosine)^2
  diag(distance2) <- Inf
  keep_n <- min(256L, length(groups) - 1L)
  rows <- vector("list", length(groups))
  for (i in seq_along(groups)) {
    ord <- order(distance2[i, ], groups)
    ord <- head(ord[is.finite(distance2[i, ord])], keep_n)
    rows[[i]] <- data.table::data.table(
      cohort = cohort_value,
      focal_group = groups[[i]],
      donor_group = groups[ord],
      donor_rank_full = seq_along(ord),
      distance = sqrt(distance2[i, ord]))
  }
  rank_blocks[[rank_index]] <- data.table::rbindlist(rows)
  message(
    "  donor rankings cohort ", cohort_value,
    " | firms=", length(groups))
  rm(
    f, z, scalar_distance2, iv, sparse, cosine,
    distance2, rows)
  invisible(gc())
}
donor_rankings <- data.table::rbindlist(rank_blocks)
rm(rank_blocks, ipc, features)
invisible(gc())

real_deal <- data.table::fread(file.path(
  config$validation_dir, "uniform_deal_paths.csv"))
real_deal <- unique(real_deal[, .(deal_id, cohort, n_treated)])
data.table::setorder(real_deal, -n_treated, deal_id)
real_effective_deals <- as.numeric(validation$effective_deals)
real_max_share <- as.numeric(validation$maximum_deal_weight_share)

assign_draw <- function(draw_id) {
  set.seed(config$control_null_seed + draw_id)
  used_groups <- numeric()
  rows <- vector("list", nrow(real_deal))
  for (i in seq_len(nrow(real_deal))) {
    target <- real_deal[i]
    candidates <- control_info[
      cohort == target$cohort &
        !focal_group %in% used_groups]
    if (!nrow(candidates)) stop("Pseudo-assignment pool exhausted")
    candidates[, size_distance := abs(
      log1p(cohort_size) - log1p(target$n_treated))]
    data.table::setorder(
      candidates, size_distance, focal_group)
    shortlist <- head(candidates, 50L)
    chosen <- shortlist[sample.int(nrow(shortlist), 1L)]
    used_groups <- c(used_groups, chosen$focal_group)
    rows[[i]] <- data.table::data.table(
      draw_id = draw_id,
      pseudo_deal_id = target$deal_id,
      cohort = target$cohort,
      real_n_treated = target$n_treated,
      pseudo_group = chosen$focal_group,
      pseudo_n_treated = chosen$cohort_size,
      size_distance = chosen$size_distance,
      assignment_seed = config$control_null_seed + draw_id)
  }
  data.table::rbindlist(rows)
}

draw_rows <- vector("list", config$control_null_draws)
event_rows <- vector("list", config$control_null_draws)
assignment_rows <- vector("list", config$control_null_draws)
pool_rows <- vector("list", config$control_null_draws)

message(
  "Uniform control null: run ", config$control_null_draws,
  " frozen pseudo-treatment draws")
for (draw_id in seq_len(config$control_null_draws)) {
  assignment <- assign_draw(draw_id)
  pseudo_groups <- unique(assignment$pseudo_group)
  selected <- merge(
    assignment[, .(
      draw_id, pseudo_deal_id, cohort, pseudo_group,
      pseudo_n_treated)],
    donor_rankings,
    by.x = c("cohort", "pseudo_group"),
    by.y = c("cohort", "focal_group"),
    allow.cartesian = TRUE,
    sort = FALSE)
  selected <- selected[!donor_group %in% pseudo_groups]
  data.table::setorder(
    selected, pseudo_deal_id, donor_rank_full, donor_group)
  selected <- selected[, head(.SD, 20L), by = pseudo_deal_id]
  selected[, donor_rank_draw := seq_len(.N), by = pseudo_deal_id]
  if (any(selected[, .N, by = pseudo_deal_id]$N != 20L) ||
      max(selected$donor_rank_full) > 256L) {
    stop("Cached donor ranking truncation became binding")
  }

  treated_path <- merge(
    assignment[, .(
      pseudo_deal_id, cohort, pseudo_group,
      pseudo_n_treated)],
    control_paths,
    by.x = c("cohort", "pseudo_group"),
    by.y = c("cohort", "focal_group"),
    sort = FALSE)
  data.table::setnames(treated_path, "outcome", "treated_outcome")
  donor_path <- merge(
    selected[, .(
      pseudo_deal_id, cohort, donor_group)],
    control_paths,
    by.x = c("cohort", "donor_group"),
    by.y = c("cohort", "focal_group"),
    allow.cartesian = TRUE,
    sort = FALSE)
  donor_mean <- donor_path[, .(
    donor_outcome = mean(outcome)),
    by = .(pseudo_deal_id, cohort, event_time)]
  paths <- merge(
    treated_path[, .(
      pseudo_deal_id, cohort, event_time,
      pseudo_n_treated, treated_outcome)],
    donor_mean,
    by = c("pseudo_deal_id", "cohort", "event_time"))
  paths[, raw_gap := treated_outcome - donor_outcome]
  hull <- paths[event_time %in% config$screening_times, .(
    inside = treated_outcome >=
      min(donor_path[
        pseudo_deal_id == .BY$pseudo_deal_id &
          event_time == .BY$event_time]$outcome) - 1e-12 &
      treated_outcome <=
      max(donor_path[
        pseudo_deal_id == .BY$pseudo_deal_id &
          event_time == .BY$event_time]$outcome) + 1e-12),
    by = .(pseudo_deal_id, event_time)]
  support <- hull[, .(
    hull_supported = .N == length(config$screening_times) &&
      all(inside)),
    by = pseudo_deal_id]
  supported_ids <- support[hull_supported == TRUE]$pseudo_deal_id
  paths <- paths[pseudo_deal_id %in% supported_ids]
  assignment <- merge(
    assignment, support, by = "pseudo_deal_id", all.x = TRUE)
  assignment[is.na(hull_supported), hull_supported := FALSE]
  selected[, hull_supported :=
    pseudo_deal_id %in% supported_ids]

  supported_info <- unique(paths[, .(
    pseudo_deal_id, pseudo_n_treated)])
  supported_info[, weight :=
    pseudo_n_treated / sum(pseudo_n_treated)]
  weights <- setNames(
    supported_info$weight,
    as.character(supported_info$pseudo_deal_id))
  post_deal <- paths[
    event_time %in% config$primary_post_times,
    .(post_gap = mean(raw_gap),
      post_treated = mean(treated_outcome),
      post_control = mean(donor_outcome)),
    by = pseudo_deal_id]
  post_deal[, weight :=
    weights[as.character(pseudo_deal_id)]]
  inference <- weighted_scalar_inference(
    post_deal$post_gap,
    post_deal$weight,
    config$control_null_bootstrap_replications,
    config$control_null_seed + 100000L + draw_id)
  event <- paths[event_time %in% config$primary_post_times]
  event[, weight :=
    weights[as.character(pseudo_deal_id)]]
  event <- event[, .(
    pseudo_att = sum(weight * raw_gap)),
    by = event_time]
  event[, draw_id := draw_id]

  nominal_deals <- nrow(supported_info)
  effective_deals <- 1 / sum(supported_info$weight^2)
  max_share <- max(supported_info$weight)
  supported_volume <- sum(supported_info$pseudo_n_treated)
  draw_rows[[draw_id]] <- data.table::data.table(
    draw_id = draw_id,
    estimate = inference$estimate,
    se = inference$se,
    ci_low = inference$ci_low,
    ci_high = inference$ci_high,
    p_value = inference$p_value,
    false_rejection_5pct = inference$p_value < 0.05,
    assigned_deals = nrow(assignment),
    supported_deals = nominal_deals,
    supported_treated_inventors = supported_volume,
    volume_ratio =
      supported_volume / config$expected_treated_inventors,
    nominal_deal_ratio =
      nominal_deals / config$expected_deals,
    effective_deals = effective_deals,
    effective_deal_ratio =
      effective_deals / real_effective_deals,
    maximum_deal_weight_share = max_share,
    maximum_share_ratio = max_share / real_max_share,
    maximum_cached_rank_used = max(selected$donor_rank_full),
    assignment_seed = config$control_null_seed + draw_id,
    bootstrap_seed =
      config$control_null_seed + 100000L + draw_id)
  event_rows[[draw_id]] <- event
  assignment_rows[[draw_id]] <- assignment
  selected[, draw_id := draw_id]
  pool_rows[[draw_id]] <- selected[, .(
    draw_id, pseudo_deal_id, cohort, pseudo_group,
    donor_group, donor_rank_full, donor_rank_draw,
    distance, hull_supported)]
  if (draw_id %% 25L == 0L || draw_id == 1L) {
    message(
      "  control-null draw ", draw_id, "/",
      config$control_null_draws)
  }
}

draws <- data.table::rbindlist(draw_rows)
events <- data.table::rbindlist(event_rows)
assignments <- data.table::rbindlist(assignment_rows)
pools <- data.table::rbindlist(pool_rows)
draws[, volume_comparable :=
  volume_ratio >= config$control_null_volume_bounds[[1]] &
    volume_ratio <= config$control_null_volume_bounds[[2]]]
draws[, nominal_deals_comparable :=
  nominal_deal_ratio >=
    config$control_null_nominal_deal_bounds[[1]] &
    nominal_deal_ratio <=
    config$control_null_nominal_deal_bounds[[2]]]
draws[, effective_deals_comparable :=
  effective_deal_ratio >=
    config$control_null_effective_deal_bounds[[1]] &
    effective_deal_ratio <=
    config$control_null_effective_deal_bounds[[2]]]
draws[, maximum_share_comparable :=
  maximum_share_ratio <=
    config$control_null_max_share_multiplier]
draws[, inference_comparable :=
  volume_comparable &
    nominal_deals_comparable &
    effective_deals_comparable &
    maximum_share_comparable]
comparable_ids <- draws[inference_comparable == TRUE]$draw_id
comparable <- draws[draw_id %in% comparable_ids]
if (!nrow(comparable)) stop("No inference-comparable control-null draw")

mean_att <- mean(comparable$estimate)
mean_att_se <- stats::sd(comparable$estimate) / sqrt(nrow(comparable))
mean_att_ci <- mean_att + c(-1, 1) * 1.96 * mean_att_se
rejections <- sum(comparable$false_rejection_5pct)
binomial <- stats::binom.test(
  rejections, nrow(comparable), p = 0.05)
event_summary <- events[draw_id %in% comparable_ids, .(
  mean_pseudo_att = mean(pseudo_att),
  monte_carlo_se = stats::sd(pseudo_att) / sqrt(.N)),
  by = event_time][order(event_time)]
event_summary[, `:=`(
  ci_low = mean_pseudo_att - 1.96 * monte_carlo_se,
  ci_high = mean_pseudo_att + 1.96 * monte_carlo_se)]

disjoint_check <- merge(
  unique(pools[, .(draw_id, donor_group)]),
  unique(assignments[, .(draw_id, pseudo_group)]),
  by = "draw_id", allow.cartesian = TRUE)
assignment_disjoint <- !any(
  disjoint_check$donor_group == disjoint_check$pseudo_group)
gate <- data.frame(
  gate = c(
    "at_least_400_inference_comparable_draws",
    "mean_pseudo_att_mc_ci_inside_equivalence_band",
    "false_rejection_exact_ci_contains_0_05",
    "false_rejection_exact_ci_upper_at_most_0_10",
    "each_mean_post_event_inside_equivalence_band",
    "assignment_and_donor_disjointness",
    "no_real_att_or_recentering_fields",
    "exact_draw_count"),
  value = c(
    nrow(comparable),
    max(abs(mean_att_ci)),
    as.numeric(
      binomial$conf.int[[1]] <= 0.05 &&
        binomial$conf.int[[2]] >= 0.05),
    binomial$conf.int[[2]],
    max(abs(event_summary$mean_pseudo_att)),
    assignment_disjoint,
    !any(c(
      "real_att", "empirical_p", "bias_ratio",
      "recentered_estimate") %in% names(draws)),
    nrow(draws)),
  threshold = c(
    ">=400", "<=0.05", "TRUE", "<=0.10",
    "<=0.05", "TRUE", "TRUE", "499"),
  pass = c(
    nrow(comparable) >=
      config$control_null_minimum_comparable_draws,
    mean_att_ci[[1]] >= -config$equivalence_band &&
      mean_att_ci[[2]] <= config$equivalence_band,
    binomial$conf.int[[1]] <= 0.05 &&
      binomial$conf.int[[2]] >= 0.05,
    binomial$conf.int[[2]] <= 0.10,
    all(abs(event_summary$mean_pseudo_att) <=
      config$equivalence_band),
    assignment_disjoint,
    !any(c(
      "real_att", "empirical_p", "bias_ratio",
      "recentered_estimate") %in% names(draws)),
    nrow(draws) == config$control_null_draws),
  governing = TRUE,
  stringsAsFactors = FALSE)
control_null_pass <- all(gate$pass)

summary <- data.frame(
  version = config$version,
  source_sha256 = source_sha256,
  config_sha256 = config_sha256,
  freeze_sha256 = freeze_sha256,
  validation_manifest_sha256 = validation_manifest_sha256,
  requested_draws = config$control_null_draws,
  completed_draws = nrow(draws),
  inference_comparable_draws = nrow(comparable),
  placebo_mean = mean_att,
  placebo_mean_monte_carlo_se = mean_att_se,
  placebo_mean_ci_low = mean_att_ci[[1]],
  placebo_mean_ci_high = mean_att_ci[[2]],
  false_rejections = rejections,
  false_rejection_share = mean(
    comparable$false_rejection_5pct),
  false_rejection_exact_ci_low = binomial$conf.int[[1]],
  false_rejection_exact_ci_high = binomial$conf.int[[2]],
  mean_supported_volume_ratio = mean(draws$volume_ratio),
  mean_effective_deal_ratio = mean(draws$effective_deal_ratio),
  maximum_cached_rank_used = max(draws$maximum_cached_rank_used),
  control_post_outcomes_queried = TRUE,
  real_post_outcomes_queried = FALSE,
  control_null_pass = control_null_pass,
  status = if (control_null_pass) {
    "CERTIFIED_TO_REAL_POST"
  } else {
    "CONTROL_NULL_FAILED"
  },
  stringsAsFactors = FALSE)

lmv2_uniform_atomic_csv(
  draws[order(draw_id)],
  file.path(config$control_null_dir, "control_null_draws.csv"))
lmv2_uniform_atomic_csv(
  events[order(draw_id, event_time)],
  file.path(config$control_null_dir, "control_null_event_paths.csv"))
lmv2_uniform_atomic_csv(
  event_summary,
  file.path(config$control_null_dir, "control_null_event_summary.csv"))
lmv2_uniform_atomic_csv(
  summary,
  file.path(config$control_null_dir, "control_null_summary.csv"))
lmv2_uniform_atomic_csv(
  gate,
  file.path(config$control_null_dir, "control_null_gate.csv"))
assignments_path <- file.path(
  config$control_null_dir, "pseudo_assignments.parquet")
pools_path <- file.path(
  config$control_null_dir, "selected_donor_pools.parquet")
atomic_parquet(
  con, assignments, assignments_path,
  "draw_id,pseudo_deal_id")
atomic_parquet(
  con, pools, pools_path,
  "draw_id,pseudo_deal_id,donor_rank_draw")

artifact_paths <- list.files(config$control_null_dir, full.names = TRUE)
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
  file.path(config$control_null_dir, "artifact_hashes.csv"))

message(
  "Uniform control null ", summary$status,
  " | comparable=", nrow(comparable), "/",
  nrow(draws),
  " | mean=", sprintf("%.4f", mean_att),
  " | false rejection=",
  sprintf("%.3f", mean(comparable$false_rejection_5pct)),
  " | real post queried=FALSE")
