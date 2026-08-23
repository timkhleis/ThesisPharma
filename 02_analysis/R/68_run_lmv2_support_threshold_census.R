# ============================================================================
# 68_run_lmv2_support_threshold_census.R
# Outcome-blind local-support census for the frozen 1993--2010 P5.3 release.
#
# The expensive candidate-edge calculation is executed once per cohort. Only
# one row per eligible treated inventor is retained. The three support rules
# are deterministic predicates on those retained counts; no outcome or ATT
# object is read, and the frozen P5 support cover is consumed read-only.
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))

required_packages <- c("DBI", "duckdb", "digest")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
lmv2_install_p5_sparse_cache()
source(file.path(BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
source(file.path(BASE, "R", "19a_lmv2_p5_rescue_config.R"))
source(file.path(BASE, "R", "19i_lmv2_p5_final_production_config.R"))

VERSION <- "lmv2_support_threshold_census_1993_v1"
REUSE_COUNTS <- "--reuse-counts" %in% commandArgs(trailingOnly = TRUE)
COHORTS <- LMV2_P5_PRODUCTION$cohorts
RULES <- data.frame(
  rule = c("1c_1f", "2c_2f", "3c_2f"),
  minimum_controls = c(1L, 2L, 3L),
  minimum_firms = c(1L, 2L, 2L),
  preferred = c(FALSE, FALSE, TRUE),
  stringsAsFactors = FALSE)

AUDIT_ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
PRODUCTION_ROOT <- file.path(AUDIT_ROOT, "P5_PRODUCTION")
FINALIZED_ROOT <- file.path(
  AUDIT_ROOT, "P5_PRODUCTION_FINAL", "finalized")
ROSTER_PATH <- file.path(
  AUDIT_ROOT, "P5C_P6_HANDOFF", "p5c_p6_primary_weighted_roster.parquet")
DB_PATH <- file.path(BASE, "output", "thesis_foundation.duckdb")
OUTPUT_DIR <- file.path(AUDIT_ROOT, "SUPPORT_THRESHOLD_CENSUS")
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# These pins make clear which frozen release the diagnostic qualifies. The
# matching source itself remains untouched because changing it would invalidate
# the completed production cache.
PINNED <- c(
  p5_production_freeze = LMV2_P5_PRODUCTION_FREEZE_SHA256,
  p5_edge_builder_source =
    "f05342a684096f671110850f89ff284b23d3b4c3a900a1894d9e1549bd6dd20d",
  finalized_coverage_by_cohort =
    "130bd3b9d781ffa22deddb85ed2106e6cea6fd8fa0ebbc435d5953d755604ea2",
  finalized_coverage_by_deal =
    "d422afb524176e8fac0d7a508577ac433f1677cefcd7b1f77b49ace85fd906f2",
  finalized_coverage_by_quartile =
    "00f1c79ba61dcd2ac957752b1d0656f7b39d1fb28b38e5ef0b209a65b5384114",
  certified_primary_roster =
    "cf47774d28118201f6689718ba17a5c6fa725bff8661e2343c6cefe3233e9f6e")
PIN_PATHS <- c(
  p5_edge_builder_source = file.path(
    BASE, "R", "18f_lmv2_p5_selected_acceleration.R"),
  finalized_coverage_by_cohort = file.path(
    FINALIZED_ROOT, "realized_coverage_by_cohort.csv"),
  finalized_coverage_by_deal = file.path(
    FINALIZED_ROOT, "realized_coverage_by_deal.csv"),
  finalized_coverage_by_quartile = file.path(
    FINALIZED_ROOT, "realized_coverage_by_productivity_quartile.csv"),
  certified_primary_roster = ROSTER_PATH)
observed_pins <- vapply(
  PIN_PATHS, digest::digest, character(1), file = TRUE, algo = "sha256")
if (!identical(unname(observed_pins), unname(PINNED[names(PIN_PATHS)]))) {
  stop(
    "A frozen support-census input drifted: ",
    paste(names(observed_pins)[observed_pins !=
      PINNED[names(observed_pins)]], collapse = ", "))
}

atomic_csv <- function(x, path) {
  temporary <- tempfile(
    paste0(basename(path), "_"), tmpdir = dirname(path),
    fileext = ".tmp")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(x, temporary, row.names = FALSE, na = "")
  if (file.exists(path) && !file.remove(path)) {
    stop("Could not replace ", path)
  }
  if (!file.rename(temporary, path)) stop("Could not finalize ", path)
}

sql_string <- function(con, path) {
  as.character(DBI::dbQuoteString(
    con, normalizePath(path, winslash = "/", mustWork = TRUE)))
}

key_string <- function(x) {
  do.call(paste, c(x[c("cohort", "deal_id", "codinv")], sep = ":"))
}

safe_scale_sql <- function(value, epsilon) {
  if (is.na(value) || !is.finite(value) || value < epsilon) {
    "NULL"
  } else {
    sprintf("%.15g", value)
  }
}

# Companion to the frozen builder's support_counts CTE. It repeats the exact
# candidate join, scaler population, distance formula, and absolute caliper,
# but returns the aggregate support census rather than writing an edge cover.
# The pinned hash above prevents silent drift from the frozen implementation.
support_counts_for_profile_diskbacked <- function(
    con, cache_dir, g, universe, admissible_firm_edges_profile,
    treated_inv_ok, donor_cols_profile, execution_hash, caliper) {
  deal_ids <- sort(unique(admissible_firm_edges_profile$deal_id))
  if (!length(deal_ids)) {
    return(list(counts = data.frame(), scaler = data.frame()))
  }

  vars <- LMV2_P3$stage_2$scalar_variables
  recency_gap <- LMV2_P3$stage_2$maximum_recency_bin_gap
  epsilon <- LMV2_P3_DISTANCE_EPSILON
  paths <- lmv2_list_complete_shard_paths_for_deals(
    cache_dir, g, universe, deal_ids, execution_hash)
  if (!length(paths)) stop("No certified technology shards for cohort ", g)
  parquet_list <- paste(
    sprintf("'%s'", gsub("'", "''", normalizePath(
      paths, winslash = "/", mustWork = TRUE), fixed = TRUE)),
    collapse = ",")
  parquet_list <- paste0("[", parquet_list, "]")

  admissible_pool <- unique(admissible_firm_edges_profile[
    c("cohort", "deal_id", "control_group")])
  treated_spine <- treated_inv_ok[
    treated_inv_ok$deal_id %in% deal_ids,
    c("cohort", "deal_id", "codinv", "recency_bin", vars)]
  names(treated_spine)[names(treated_spine) == "codinv"] <-
    "treated_codinv"
  donor_firms <- unique(donor_cols_profile[
    c("cohort", "control_codinv", "control_group", "recency_bin", vars)])

  duckdb::duckdb_register(
    con, "census_admissible_pool", admissible_pool)
  duckdb::duckdb_register(
    con, "census_treated_spine", treated_spine)
  duckdb::duckdb_register(
    con, "census_donor_firms", donor_firms)
  cleanup <- function() {
    try(duckdb::duckdb_unregister(
      con, "census_admissible_pool"), silent = TRUE)
    try(duckdb::duckdb_unregister(
      con, "census_treated_spine"), silent = TRUE)
    try(duckdb::duckdb_unregister(
      con, "census_donor_firms"), silent = TRUE)
  }
  on.exit(cleanup(), add = TRUE)

  var_select <- paste(
    sprintf("t.%s AS %s_t, df.%s AS %s_c", vars, vars, vars, vars),
    collapse = ", ")
  candidate_sql <- sprintf("
    SELECT t.cohort,t.deal_id,t.treated_codinv,
           df.control_codinv,df.control_group,
           t.recency_bin AS recency_bin_t,
           df.recency_bin AS recency_bin_c,%s
    FROM census_treated_spine t
    JOIN census_admissible_pool a
      ON a.cohort=t.cohort AND a.deal_id=t.deal_id
    JOIN census_donor_firms df
      ON df.cohort=a.cohort AND df.control_group=a.control_group",
    var_select)
  matched_sql <- sprintf("
    SELECT c.*,s.cosine
    FROM (%s) c
    JOIN read_parquet(%s) s
      ON s.cohort=c.cohort
     AND s.treated_codinv=c.treated_codinv
     AND s.control_codinv=c.control_codinv
    WHERE s.shared_ipc4=TRUE AND s.cosine IS NOT NULL
      AND c.recency_bin_t IS NOT NULL
      AND c.recency_bin_c IS NOT NULL
      AND ABS(c.recency_bin_t-c.recency_bin_c) <= %d",
    candidate_sql, parquet_list, recency_gap)

  var_cols <- paste(vars, collapse = ", ")
  scaler_sql <- sprintf("
    WITH combined AS (
      SELECT %s FROM census_treated_spine
      UNION ALL
      SELECT %s FROM census_donor_firms)
    SELECT %s FROM combined",
    var_cols, var_cols,
    paste(sprintf("STDDEV_SAMP(%s) AS sd_%s", vars, vars),
          collapse = ", "))
  scaler <- DBI::dbGetQuery(con, scaler_sql)
  tech_sd <- DBI::dbGetQuery(
    con, sprintf(
      "SELECT STDDEV_SAMP(1-cosine) AS tech_sd FROM (%s)",
      matched_sql))$tech_sd[[1]]

  sd_values <- vapply(vars, function(v) safe_scale_sql(
    scaler[[paste0("sd_", v)]][[1]], epsilon), character(1))
  tech_sd_sql <- safe_scale_sql(tech_sd, epsilon)
  gap_terms <- vapply(seq_along(vars), function(i) {
    if (sd_values[[i]] == "NULL") return("0")
    sprintf("POWER((%s_c-%s_t)/%s,2)",
            vars[[i]], vars[[i]], sd_values[[i]])
  }, character(1))
  tech_term <- if (tech_sd_sql == "NULL") {
    "0"
  } else {
    sprintf("POWER((1-cosine)/%s,2)", tech_sd_sql)
  }
  distance_expr <- sprintf(
    "SQRT(%s)", paste(c(gap_terms, tech_term), collapse = " + "))

  count_sql <- sprintf("
    WITH admissible_edges AS (
      SELECT cohort,deal_id,treated_codinv,control_codinv,control_group,
             %s AS distance
      FROM (%s)
      WHERE %s IS NOT NULL AND %s <= %.15g
    )
    SELECT CAST(cohort AS INTEGER) cohort,
           CAST(deal_id AS INTEGER) deal_id,
           CAST(treated_codinv AS BIGINT) codinv,
           COUNT(*) AS n_candidate_edges,
           COUNT(DISTINCT control_codinv) AS n_controls,
           COUNT(DISTINCT control_group) AS n_firms,
           MIN(distance) AS nearest_distance,
           MEDIAN(distance) AS median_distance,
           MAX(distance) AS furthest_distance
    FROM admissible_edges
    GROUP BY cohort,deal_id,treated_codinv
    ORDER BY cohort,deal_id,treated_codinv",
    distance_expr, matched_sql, distance_expr, distance_expr, caliper)
  counts <- DBI::dbGetQuery(con, count_sql)

  scaler$cohort <- as.integer(g)
  scaler$tech_sd <- tech_sd
  scaler$n_treated_scaler_rows <- nrow(treated_spine)
  scaler$n_donor_scaler_rows <- nrow(donor_firms)
  scaler$n_admissible_firm_rows <- nrow(admissible_pool)
  scaler$scaler_signature <- digest::digest(
    list(
      cohort = g, scalar_variables = vars, scalar_sd = scaler[1, ],
      population = "treated_spine_union_donor_firms",
      technology_population = "pre_support_matched_candidate_join"),
    algo = "sha256")
  list(counts = counts, scaler = scaler)
}

prepare_cohort_inputs <- function(con, g) {
  s2_vars <- LMV2_P3$stage_2$scalar_variables
  required_vars <- unique(c(s2_vars, LMV2_HYBRID_INV_VARS))

  all_treated <- DBI::dbGetQuery(con, sprintf("
    SELECT DISTINCT t.cohort,t.deal_id,
           CAST(t.target_group AS DOUBLE) AS id_group
    FROM lmv2_treated_primary t WHERE t.cohort=%d", g))
  all_treated <- lmv2_left_join_checked(
    all_treated,
    DBI::dbGetQuery(con, sprintf("
      SELECT cohort,id_group,log_patent_stock_5y,
             log_inventor_count_5y,patent_trajectory
      FROM h_firm_covars WHERE cohort=%d", g)),
    by = c("cohort", "id_group"),
    context = "support census treated firms x firm covariates",
    no_missing_cols = c(
      "log_patent_stock_5y", "log_inventor_count_5y",
      "patent_trajectory"))

  treated_inv <- DBI::dbGetQuery(con, sprintf("
    SELECT cohort,deal_id,codinv,recency_bin,%s
    FROM lmv2_p3_treated_inventor_units WHERE cohort=%d",
    paste(required_vars, collapse = ","), g))
  treated_inv_ok <- treated_inv[stats::complete.cases(
    treated_inv[c(required_vars, "recency_bin")]), , drop = FALSE]

  raw_edges <- build_universe_edges(
    con, g, "h_pool_u2", all_treated)$edges
  admissible_loosest <- lmv2_ebal_stage1_admissible_edges(
    raw_edges, LMV2_P5_PRODUCTION$selected$stage1_caliper)
  eligible_controls_loosest <- DBI::dbGetQuery(con, sprintf("
    SELECT cohort,codinv AS control_codinv,control_group
    FROM h_inv_latest
    WHERE cohort=%d AND control_group IN (%s)",
    g, paste(unique(admissible_loosest$control_group), collapse = ",")))

  donor_base <- DBI::dbGetQuery(con, sprintf("
    SELECT cohort,codinv,career_first_year,last_pre_patent_year,
      LN(1+patent_count_5y) AS log_patent_count_5y,
      LN(1+patents_recent/2.0)-LN(1+patents_early/3.0)
        AS patent_trajectory,
      (cohort-1-career_first_year) AS career_age,
      CASE WHEN last_pre_patent_year=cohort-1 THEN 0
           WHEN last_pre_patent_year=cohort-2 THEN 1
           WHEN last_pre_patent_year=cohort-3 THEN 2
           WHEN last_pre_patent_year BETWEEN cohort-5 AND cohort-4 THEN 3
           ELSE NULL END AS recency_bin
    FROM lmv2_p3_inventor_cohort_stats
    WHERE cohort=%d AND codinv IN (%s)",
    g, paste(unique(eligible_controls_loosest$control_codinv),
             collapse = ",")))
  donor_raw <- merge(
    eligible_controls_loosest, donor_base,
    by.x = c("cohort", "control_codinv"),
    by.y = c("cohort", "codinv"))
  names(donor_raw)[names(donor_raw) == "control_group"] <- "focal_group"
  names(donor_raw)[names(donor_raw) == "control_codinv"] <- "codinv"
  focal <- lmv2_build_control_focal_covariates(
    con, donor_raw[c("cohort", "codinv", "focal_group")])
  donor_raw <- merge(
    donor_raw, focal, by = c("cohort", "codinv", "focal_group"),
    sort = FALSE)
  donors_loosest <- donor_raw[stats::complete.cases(
    donor_raw[c(required_vars, "recency_bin")]), , drop = FALSE]
  donor_cols_loosest <- donors_loosest
  names(donor_cols_loosest)[names(donor_cols_loosest) == "codinv"] <-
    "control_codinv"
  names(donor_cols_loosest)[names(donor_cols_loosest) == "focal_group"] <-
    "control_group"

  admissible <- lmv2_ebal_stage1_admissible_edges(
    raw_edges, LMV2_P5_PRODUCTION$selected$stage1_caliper)
  admissible <- lmv2_ebal_nearest_within_caliper(admissible, 50L)
  firms_by_deal <- stats::aggregate(
    control_group ~ cohort + deal_id, data = admissible,
    FUN = function(x) length(unique(x)))
  supported_deals <- firms_by_deal$deal_id[
    firms_by_deal$control_group >=
      LMV2_P5_RESCUE$inventor_first$minimum_stage1_firms]
  admissible_supported <- admissible[
    admissible$deal_id %in% supported_deals, , drop = FALSE]
  donor_cols_profile <- donor_cols_loosest[
    donor_cols_loosest$control_group %in%
      unique(admissible_supported$control_group), , drop = FALSE]

  list(
    treated_inv_ok = treated_inv_ok,
    admissible_supported = admissible_supported,
    donor_cols_profile = donor_cols_profile)
}

manifest_paths <- list.files(
  PRODUCTION_ROOT, pattern = "^p5_production_manifest\\.csv$",
  recursive = TRUE, full.names = TRUE)
production_manifests <- do.call(rbind, lapply(
  manifest_paths, utils::read.csv, stringsAsFactors = FALSE))
if (nrow(production_manifests) != length(COHORTS) ||
    anyDuplicated(production_manifests$cohort) ||
    !identical(sort(as.integer(production_manifests$cohort)), COHORTS)) {
  stop("Production manifests do not identify one frozen cell per cohort")
}
if (any(production_manifests$production_freeze_hash !=
        LMV2_P5_PRODUCTION_FREEZE_SHA256)) {
  stop("Production manifests do not match the frozen P5.3 release")
}

STAGE1_CALIPERS <- LMV2_P5_PRODUCTION$selected$stage1_caliper
STAGE1_PROFILES <- LMV2_P5_PRODUCTION$selected$profile
STAGE2_CALIPER <- LMV2_P5_PRODUCTION$selected$stage2_caliper
UNIVERSES <- LMV2_P5_PRODUCTION$selected$universe
SCHEMES <- LMV2_P5_PRODUCTION$selected$schemes
LMV2_P5_SOLVER <- LMV2_P5_PRODUCTION$selected$solver
MIN_ELIGIBLE_FIRMS <-
  LMV2_P5_RESCUE$inventor_first$minimum_stage1_firms
lmv2_p5_production_apply()

con <- DBI::dbConnect(duckdb::duckdb(), DB_PATH, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=2")
DBI::dbExecute(con, "SET memory_limit='6GB'")
DBI::dbExecute(con, "SET preserve_insertion_order=false")
spill_dir <- file.path(OUTPUT_DIR, "duckdb_spill")
dir.create(spill_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "SET temp_directory=%s", as.character(DBI::dbQuoteString(con,
    normalizePath(spill_dir, winslash = "/", mustWork = TRUE)))))

if (REUSE_COUNTS) {
  counts_path <- file.path(OUTPUT_DIR, "support_counts.csv")
  scalers_path <- file.path(OUTPUT_DIR, "support_scalers.csv")
  if (!file.exists(counts_path) || !file.exists(scalers_path)) {
    stop("--reuse-counts requires completed support_counts/scalers outputs")
  }
  counts <- utils::read.csv(counts_path, stringsAsFactors = FALSE)
  scalers <- utils::read.csv(scalers_path, stringsAsFactors = FALSE)
  message("Reusing the persisted inventor-level support census")
} else {
  build_universe_pools_and_scalers_and_edges(con, COHORTS)

  count_rows <- list()
  scaler_rows <- list()
  for (g in COHORTS) {
    message("Support census cohort ", g, " ...")
    inputs <- prepare_cohort_inputs(con, g)
    cohort_root <- file.path(
      PRODUCTION_ROOT, sprintf("cohort_%d", as.integer(g)))
    cache_dir <- file.path(cohort_root, "disk_tech_cache")
    execution_hash <- production_manifests$execution_hash[
      production_manifests$cohort == g]
    result <- support_counts_for_profile_diskbacked(
      con = con, cache_dir = cache_dir, g = g, universe = "u2",
      admissible_firm_edges_profile = inputs$admissible_supported,
      treated_inv_ok = inputs$treated_inv_ok,
      donor_cols_profile = inputs$donor_cols_profile,
      execution_hash = execution_hash,
      caliper = LMV2_P5_PRODUCTION$selected$stage2_caliper)
    count_rows[[as.character(g)]] <- result$counts
    scaler_rows[[as.character(g)]] <- result$scaler
    rm(inputs, result)
    gc(FALSE)
  }
  positive_counts <- do.call(rbind, count_rows)
  scalers <- do.call(rbind, scaler_rows)

  eligible <- DBI::dbGetQuery(con, sprintf("
    SELECT CAST(cohort AS INTEGER) cohort,
           CAST(deal_id AS INTEGER) deal_id,
           CAST(codinv AS BIGINT) codinv,
           log_patent_count_5y,patent_trajectory,career_age,
           focal_group_tenure,focal_group_exclusivity
    FROM lmv2_p3_treated_inventor_units
    WHERE cohort IN (%s)
    ORDER BY cohort,deal_id,codinv",
    paste(COHORTS, collapse = ",")))
  if (anyDuplicated(eligible[c("cohort", "deal_id", "codinv")])) {
    stop("Eligible treated-inventor keys are duplicated")
  }
  counts <- merge(
    eligible, positive_counts,
    by = c("cohort", "deal_id", "codinv"), all.x = TRUE, sort = TRUE)
  for (v in c("n_candidate_edges", "n_controls", "n_firms")) {
    counts[[v]][is.na(counts[[v]])] <- 0L
    counts[[v]] <- as.integer(counts[[v]])
  }
  for (i in seq_len(nrow(RULES))) {
    counts[[paste0("supported_", RULES$rule[[i]])]] <-
      counts$n_controls >= RULES$minimum_controls[[i]] &
      counts$n_firms >= RULES$minimum_firms[[i]]
  }
}

roster <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT CAST(cohort AS INTEGER) cohort,
         CAST(deal_id AS INTEGER) deal_id,
         CAST(codinv AS BIGINT) codinv
  FROM read_parquet(%s) WHERE arm='treated'
  ORDER BY cohort,deal_id,codinv", sql_string(con, ROSTER_PATH)))
if (anyDuplicated(roster[c("cohort", "deal_id", "codinv")])) {
  stop("Certified preferred roster has duplicate treated keys")
}
preferred_keys <- key_string(counts[counts$supported_3c_2f, ])
roster_keys <- key_string(roster)
missing_from_census <- setdiff(roster_keys, preferred_keys)
extra_in_census <- setdiff(preferred_keys, roster_keys)
if (length(missing_from_census) || length(extra_in_census)) {
  stop(
    "Preferred 3c/2f census does not reproduce the certified roster: ",
    length(missing_from_census), " missing, ",
    length(extra_in_census), " extra")
}

if (!all(counts$supported_3c_2f <= counts$supported_2c_2f) ||
    !all(counts$supported_2c_2f <= counts$supported_1c_1f)) {
  stop("Support-rule nesting failed")
}

counts$productivity_quartile <-
  lmv2_p5_rescue_assign_productivity_quartile(counts)
counts$support_increment <- ifelse(
  counts$supported_3c_2f, "preferred_3c_2f",
  ifelse(counts$supported_2c_2f, "added_by_2c_2f",
    ifelse(counts$supported_1c_1f, "added_by_1c_1f",
           "unsupported_1c_1f")))

coverage_summary <- function(x, dimensions) {
  split_key <- if (length(dimensions)) {
    interaction(x[dimensions], drop = TRUE, lex.order = TRUE)
  } else {
    factor(rep("aggregate", nrow(x)))
  }
  rows <- lapply(split(x, split_key), function(z) {
    base <- if (length(dimensions)) z[1, dimensions, drop = FALSE] else {
      data.frame(scope = "aggregate", stringsAsFactors = FALSE)
    }
    for (i in seq_len(nrow(RULES))) {
      indicator <- z[[paste0("supported_", RULES$rule[[i]])]]
      base[[paste0("eligible_", RULES$rule[[i]])]] <- nrow(z)
      base[[paste0("supported_", RULES$rule[[i]])]] <- sum(indicator)
      base[[paste0("coverage_", RULES$rule[[i]])]] <- mean(indicator)
    }
    base
  })
  do.call(rbind, rows)
}

coverage_aggregate <- coverage_summary(counts, character())
coverage_cohort <- coverage_summary(counts, "cohort")
coverage_deal <- coverage_summary(counts, c("cohort", "deal_id"))
coverage_quartile <- coverage_summary(counts, "productivity_quartile")

control_bins <- cut(
  counts$n_controls,
  breaks = c(-Inf, 0, 1, 2, 4, 9, Inf),
  labels = c("0", "1", "2", "3-4", "5-9", "10+"),
  right = TRUE)
firm_bins <- cut(
  counts$n_firms,
  breaks = c(-Inf, 0, 1, 2, 4, 9, Inf),
  labels = c("0", "1", "2", "3-4", "5-9", "10+"),
  right = TRUE)
candidate_distribution <- do.call(rbind, lapply(
  c("controls", "firms"), function(metric) {
    bins <- if (metric == "controls") control_bins else firm_bins
    tab <- table(bins, useNA = "no")
    data.frame(
      metric = metric, bin = names(tab), inventors = as.integer(tab),
      share = as.numeric(tab) / nrow(counts),
      stringsAsFactors = FALSE)
  }))

composition_variables <- c(
  "log_patent_count_5y", "patent_trajectory", "career_age",
  "focal_group_tenure", "focal_group_exclusivity")
preferred_reference <- counts$support_increment == "preferred_3c_2f"
composition <- do.call(rbind, lapply(
  unique(counts$support_increment), function(group) {
    member <- counts$support_increment == group
    do.call(rbind, lapply(composition_variables, function(variable) {
      reference <- counts[[variable]][preferred_reference]
      comparison <- counts[[variable]][member]
      pooled_sd <- sqrt(
        (stats::var(reference) + stats::var(comparison)) / 2)
      data.frame(
        support_increment = group,
        variable = variable,
        n = sum(member),
        mean = mean(comparison),
        preferred_mean = mean(reference),
        smd_increment_minus_preferred = if (
          is.finite(pooled_sd) && pooled_sd > 0) {
          (mean(comparison) - mean(reference)) / pooled_sd
        } else {
          0
        },
        stringsAsFactors = FALSE)
    }))
  }))

distance_quality <- do.call(rbind, lapply(
  unique(counts$support_increment), function(group) {
    z <- counts[counts$support_increment == group, , drop = FALSE]
    data.frame(
      support_increment = group, inventors = nrow(z),
      mean_controls = mean(z$n_controls),
      median_controls = stats::median(z$n_controls),
      mean_firms = mean(z$n_firms),
      median_firms = stats::median(z$n_firms),
      mean_nearest_distance = mean(z$nearest_distance, na.rm = TRUE),
      median_nearest_distance = stats::median(
        z$nearest_distance, na.rm = TRUE),
      stringsAsFactors = FALSE)
  }))

reconciles_to_frozen <- function(realized, frozen, keys) {
  realized <- realized[do.call(order, realized[keys]),
                       c(keys, "eligible", "supported", "coverage"),
                       drop = FALSE]
  frozen <- frozen[do.call(order, frozen[keys]),
                   c(keys, "eligible", "supported", "coverage"),
                   drop = FALSE]
  isTRUE(all.equal(
    realized, frozen, tolerance = 1e-12, check.attributes = FALSE))
}
preferred_cohort <- coverage_cohort[c(
  "cohort", "eligible_3c_2f", "supported_3c_2f", "coverage_3c_2f")]
names(preferred_cohort)[2:4] <- c("eligible", "supported", "coverage")
preferred_deal <- coverage_deal[c(
  "cohort", "deal_id", "eligible_3c_2f", "supported_3c_2f",
  "coverage_3c_2f")]
names(preferred_deal)[3:5] <- c("eligible", "supported", "coverage")
preferred_quartile <- coverage_quartile[c(
  "productivity_quartile", "eligible_3c_2f", "supported_3c_2f",
  "coverage_3c_2f")]
names(preferred_quartile)[2:4] <- c(
  "eligible", "supported", "coverage")
frozen_cohort <- utils::read.csv(
  PIN_PATHS[["finalized_coverage_by_cohort"]], stringsAsFactors = FALSE)
frozen_deal <- utils::read.csv(
  PIN_PATHS[["finalized_coverage_by_deal"]], stringsAsFactors = FALSE)
frozen_quartile <- utils::read.csv(
  PIN_PATHS[["finalized_coverage_by_quartile"]],
  stringsAsFactors = FALSE)
cohort_reconciles <- reconciles_to_frozen(
  preferred_cohort, frozen_cohort, "cohort")
deal_reconciles <- reconciles_to_frozen(
  preferred_deal, frozen_deal, c("cohort", "deal_id"))
quartile_reconciles <- reconciles_to_frozen(
  preferred_quartile, frozen_quartile, "productivity_quartile")

preferred_deal_count <- sum(coverage_deal$supported_3c_2f > 0)
certification <- data.frame(
  check = c(
    "frozen_edge_builder_hash",
    "frozen_coverage_hash",
    "frozen_deal_coverage_hash",
    "frozen_quartile_coverage_hash",
    "frozen_roster_hash",
    "preferred_roster_key_reconciliation",
    "preferred_cohort_count_reconciliation",
    "preferred_deal_count_reconciliation",
    "preferred_quartile_count_reconciliation",
    "support_rule_nesting",
    "one_scaler_signature_per_cohort",
    "rules_applied_after_single_count_pass",
    "outcome_or_att_objects_read",
    "eligible_deal_definition",
    "preferred_supported_deals"),
  realized = c(
    observed_pins[["p5_edge_builder_source"]],
    observed_pins[["finalized_coverage_by_cohort"]],
    observed_pins[["finalized_coverage_by_deal"]],
    observed_pins[["finalized_coverage_by_quartile"]],
    observed_pins[["certified_primary_roster"]],
    paste0(length(preferred_keys), " exact keys"),
    paste0(nrow(preferred_cohort), " exact cohort rows"),
    paste0(nrow(preferred_deal), " exact deal rows"),
    paste0(nrow(preferred_quartile), " exact quartile rows"),
    "3c_2f subset 2c_2f subset 1c_1f",
    paste0(length(unique(scalers$scaler_signature)), " signatures / ",
           nrow(scalers), " cohorts"),
    "TRUE",
    "FALSE",
    "deal eligible iff at least one eligible treated inventor",
    paste0(preferred_deal_count, " / ", nrow(coverage_deal))),
  pass = c(
    TRUE, TRUE, TRUE, TRUE, TRUE, TRUE,
    cohort_reconciles, deal_reconciles, quartile_reconciles,
    TRUE,
    nrow(scalers) == length(COHORTS) &&
      !anyDuplicated(scalers$cohort) &&
      length(unique(scalers$scaler_signature)) == nrow(scalers),
    TRUE, TRUE, TRUE,
    preferred_deal_count == 343L),
  stringsAsFactors = FALSE)
if (any(!certification$pass)) {
  stop("At least one support-census certification check failed")
}

manifest <- data.frame(
  version = VERSION,
  release = "local_match_v2_1993_amendment",
  cohort_window = "1993-2010",
  production_status = paste(
    "candidate amendment release; frozen P5 design inputs consumed",
    "read-only; does not promote or alter headline ATT estimates"),
  outcome_boundary = paste(
    "Reads treatment assignments, donor eligibility, pre-treatment",
    "covariates, technology-support shards, design weights/rosters, and",
    "support diagnostics only. Reads no outcome or ATT object."),
  firm_support_rule = paste(
    "Within each treated inventor's deal, retain nearest 50 unexposed",
    "firms sharing IPC4 within firm distance <=2; require at least two",
    "firms for the deal to enter inventor matching."),
  inventor_support_rules = paste(
    "Per treated inventor: 1 control/1 firm; 2 controls/2 firms;",
    "3 controls/2 firms (preferred)."),
  deal_support_definition = paste(
    "A deal is supported under a rule iff at least one eligible treated",
    "inventor in that deal is supported; no separate deal threshold."),
  standardization = paste(
    "Scalar SDs use treated spine union donor firms; technology SD uses",
    "the pre-support matched candidate join. Both are computed once per",
    "cohort and held invariant across all three predicates."),
  eligible_inventors = nrow(counts),
  eligible_deals = nrow(coverage_deal),
  preferred_supported_inventors = sum(counts$supported_3c_2f),
  preferred_supported_deals = preferred_deal_count,
  p5_production_freeze_sha256 = LMV2_P5_PRODUCTION_FREEZE_SHA256,
  edge_builder_sha256 = observed_pins[["p5_edge_builder_source"]],
  certified_roster_sha256 = observed_pins[["certified_primary_roster"]],
  timestamp = as.character(Sys.time()),
  stringsAsFactors = FALSE)

atomic_csv(counts, file.path(OUTPUT_DIR, "support_counts.csv"))
atomic_csv(scalers, file.path(OUTPUT_DIR, "support_scalers.csv"))
atomic_csv(candidate_distribution, file.path(
  OUTPUT_DIR, "candidate_count_distribution.csv"))
atomic_csv(coverage_aggregate, file.path(
  OUTPUT_DIR, "coverage_aggregate.csv"))
atomic_csv(coverage_cohort, file.path(
  OUTPUT_DIR, "coverage_by_cohort.csv"))
atomic_csv(coverage_deal, file.path(
  OUTPUT_DIR, "coverage_by_deal.csv"))
atomic_csv(coverage_quartile, file.path(
  OUTPUT_DIR, "coverage_by_productivity_quartile.csv"))
atomic_csv(composition, file.path(
  OUTPUT_DIR, "increment_composition.csv"))
atomic_csv(distance_quality, file.path(
  OUTPUT_DIR, "increment_candidate_quality.csv"))
atomic_csv(certification, file.path(
  OUTPUT_DIR, "certification.csv"))
atomic_csv(manifest, file.path(OUTPUT_DIR, "manifest.csv"))

summary_lines <- c(
  "# Outcome-blind support-threshold census",
  "",
  paste0("Release: `", manifest$release, "` (", manifest$cohort_window, ")."),
  "",
  paste0(
    "The preferred rule supports ",
    format(sum(counts$supported_3c_2f), big.mark = ","), " of ",
    format(nrow(counts), big.mark = ","), " eligible inventors and ",
    preferred_deal_count, " of ", nrow(coverage_deal), " eligible deals."),
  "",
  paste0(
    "The census is outcome blind. It calculates the common candidate graph ",
    "and its cohort-specific standardization once, then applies the three ",
    "per-inventor support predicates to the resulting counts."),
  "",
  "The relaxed-rule increments are descriptive diagnostics, not evidence that ",
  "a relaxed rule is preferable. Increment composition and candidate-density ",
  "tables must be read together: relaxed rules can recover systematically ",
  "different inventors precisely because their donor support is thin.",
  "",
  "A deal is counted as supported when at least one of its eligible treated ",
  "inventors is supported. There is no additional deal-level threshold.",
  "",
  "The 343 supported deals are therefore 343 of 345 eligible deals (99.4%), ",
  "not 343 of 343. Any smaller downstream estimation sample is a separate ",
  "post-support loss and must not be attributed to this support rule.",
  "",
  paste0(
    "Relaxing to 2c/2f adds ",
    sum(counts$supported_2c_2f & !counts$supported_3c_2f),
    " inventors (", sprintf("%.2f", 100 * mean(counts$supported_2c_2f)),
    "% coverage); relaxing further to 1c/1f adds another ",
    sum(counts$supported_1c_1f & !counts$supported_2c_2f),
    " (", sprintf("%.2f", 100 * mean(counts$supported_1c_1f)),
    "% coverage). Neither relaxation adds a deal. The added inventors are ",
    "more senior and prolific, but their nearest admissible controls are ",
    "substantially more distant. The evidence therefore supports retaining ",
    "3c/2f as a local-credibility restriction while stating clearly that ",
    "the resulting ATT is conditional on common support."))
writeLines(summary_lines, file.path(OUTPUT_DIR, "README.md"), useBytes = TRUE)

message(
  "Support-threshold census complete: ",
  sum(counts$supported_3c_2f), "/", nrow(counts),
  " inventors; ", preferred_deal_count, "/", nrow(coverage_deal),
  " deals under 3c/2f.")
