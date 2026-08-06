# Disk-backed candidate extraction for the frozen cardinality arm.

lmv2_cardinality_candidate_path <- function(candidate_root, cohort) {
  file.path(
    candidate_root,
    sprintf("cardinality_candidates_%d.parquet", as.integer(cohort)))
}

lmv2_write_cardinality_candidates <- function(
    con, cache_dir, cohort, universe,
    admissible_firm_edges_profile, treated_inv_ok,
    donor_cols_profile, execution_hash, stage2_caliper,
    unsupported_keys, candidate_root) {
  required_unsupported <- c("cohort", "deal_id", "treated_codinv")
  if (!all(required_unsupported %in% names(unsupported_keys)) ||
      anyDuplicated(unsupported_keys[required_unsupported])) {
    stop("Cardinality unsupported keys are invalid")
  }
  unsupported <- unsupported_keys[
    unsupported_keys$cohort == cohort, , drop = FALSE]
  output_path <- lmv2_cardinality_candidate_path(
    candidate_root, cohort)
  if (!nrow(unsupported)) {
    return(invisible(output_path))
  }

  deal_ids <- unique(admissible_firm_edges_profile$deal_id)
  paths <- lmv2_list_complete_shard_paths_for_deals(
    cache_dir, cohort, universe, deal_ids, execution_hash)
  if (!length(paths)) stop("Cardinality technology shards are missing")
  parquet_list <- paste0(
    "[", paste(sprintf("'%s'", paths), collapse = ","), "]")
  vars <- LMV2_P3$stage_2$scalar_variables
  balance_inv <- unique(c(
    vars, "focal_group_exclusivity"))
  recency_gap <- LMV2_P3$stage_2$maximum_recency_bin_gap
  eps <- LMV2_P3_DISTANCE_EPSILON

  admissible_pool <- unique(
    admissible_firm_edges_profile[
      c("cohort", "deal_id", "control_group")])
  treated_spine <- treated_inv_ok[
    treated_inv_ok$deal_id %in% deal_ids,
    c("cohort", "deal_id", "codinv", "recency_bin", balance_inv)]
  names(treated_spine)[names(treated_spine) == "codinv"] <-
    "treated_codinv"
  donor_firms <- unique(
    donor_cols_profile[
      c(
        "cohort", "control_codinv", "control_group",
        "recency_bin", balance_inv)])
  target_map <- DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT cohort,deal_id,
            CAST(target_group AS DOUBLE) target_group
     FROM lmv2_treated_primary
     WHERE cohort=%d", as.integer(cohort)))
  firm_covars <- DBI::dbGetQuery(con, sprintf(
    "SELECT cohort,CAST(id_group AS DOUBLE) id_group,
            log_patent_stock_5y,
            log_inventor_count_5y,
            patent_trajectory
     FROM h_firm_covars
     WHERE cohort=%d", as.integer(cohort)))

  registrations <- list(
    card_admissible_pool = admissible_pool,
    card_treated_spine = treated_spine,
    card_donor_firms = donor_firms,
    card_unsupported = unsupported,
    card_target_map = target_map,
    card_firm_covars = firm_covars)
  for (name in names(registrations)) {
    duckdb::duckdb_register(con, name, registrations[[name]])
  }
  on.exit({
    for (name in names(registrations)) {
      try(duckdb::duckdb_unregister(con, name), silent = TRUE)
    }
  }, add = TRUE)

  distance_select <- paste(
    sprintf(
      "t.%s AS %s_t, df.%s AS %s_c",
      vars, vars, vars, vars),
    collapse = ", ")
  candidate_sql <- sprintf(
    "SELECT t.cohort,t.deal_id,t.treated_codinv,
            df.control_codinv,df.control_group,
            t.recency_bin AS recency_bin_t,
            df.recency_bin AS recency_bin_c,%s
     FROM card_treated_spine t
     JOIN card_unsupported u
       USING (cohort,deal_id,treated_codinv)
     JOIN card_admissible_pool a
       ON a.cohort=t.cohort AND a.deal_id=t.deal_id
     JOIN card_donor_firms df
       ON df.cohort=a.cohort
      AND df.control_group=a.control_group",
    distance_select)
  matched_sql <- sprintf(
    "SELECT c.*,s.cosine
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
  scalar_cols <- paste(vars, collapse = ", ")
  scaler <- DBI::dbGetQuery(con, sprintf(
    "WITH combined AS (
       SELECT %s FROM card_treated_spine
       UNION ALL
       SELECT %s FROM card_donor_firms)
     SELECT %s FROM combined",
    scalar_cols, scalar_cols,
    paste(
      sprintf("STDDEV_SAMP(%s) AS sd_%s", vars, vars),
      collapse = ", ")))
  technology_scale <- DBI::dbGetQuery(con, sprintf(
    "SELECT STDDEV_SAMP(1-cosine) AS tech_sd FROM (%s)",
    matched_sql))$tech_sd[[1]]
  safe_scale <- function(value) {
    if (is.na(value) || !is.finite(value) || value < eps) {
      "NULL"
    } else {
      sprintf("%.15g", value)
    }
  }
  scalar_scales <- vapply(vars, function(variable) {
    safe_scale(scaler[[paste0("sd_", variable)]][[1]])
  }, character(1))
  gap_terms <- vapply(seq_along(vars), function(index) {
    variable <- vars[[index]]
    if (scalar_scales[[index]] == "NULL") {
      "0"
    } else {
      sprintf(
        "POWER((%s_c-%s_t)/%s,2)",
        variable, variable, scalar_scales[[index]])
    }
  }, character(1))
  technology_term <- if (safe_scale(technology_scale) == "NULL") {
    "0"
  } else {
    sprintf(
      "POWER((1-cosine)/%s,2)",
      safe_scale(technology_scale))
  }
  distance_expression <- sprintf(
    "SQRT(%s)",
    paste(c(gap_terms, technology_term), collapse = " + "))

  inventor_select <- paste(c(
    sprintf(
      "t.%s AS %s_treated",
      balance_inv, balance_inv),
    sprintf(
      "df.%s AS %s_control",
      balance_inv, balance_inv)),
    collapse = ", ")
  select_sql <- sprintf(
    "WITH admissible_edges AS (
       SELECT cohort,deal_id,treated_codinv,control_codinv,
              control_group,%s AS distance
       FROM (%s)
       WHERE %s IS NOT NULL AND %s <= %.15g
     ),
     support_counts AS (
       SELECT cohort,deal_id,treated_codinv,
              COUNT(DISTINCT control_codinv) n_controls,
              COUNT(DISTINCT control_group) n_firms
       FROM admissible_edges
       GROUP BY cohort,deal_id,treated_codinv
     ),
     ranked AS (
       SELECT e.*,
              ROW_NUMBER() OVER (
                PARTITION BY cohort,deal_id,treated_codinv
                ORDER BY distance,control_group,control_codinv) candidate_rank
       FROM admissible_edges e
       JOIN support_counts s
         USING (cohort,deal_id,treated_codinv)
       WHERE s.n_controls >= 2 AND s.n_firms >= 2
     )
     SELECT r.cohort,r.deal_id,r.treated_codinv,
            r.control_codinv,r.control_group,r.distance,
            %s,
            tf.log_patent_stock_5y AS firm_log_patent_stock_5y_treated,
            cf.log_patent_stock_5y AS firm_log_patent_stock_5y_control,
            tf.log_inventor_count_5y AS firm_log_inventor_count_5y_treated,
            cf.log_inventor_count_5y AS firm_log_inventor_count_5y_control,
            tf.patent_trajectory AS firm_patent_trajectory_treated,
            cf.patent_trajectory AS firm_patent_trajectory_control
     FROM ranked r
     JOIN card_treated_spine t
       USING (cohort,deal_id,treated_codinv)
     JOIN card_donor_firms df
       USING (cohort,control_codinv,control_group)
     JOIN card_target_map tm
       USING (cohort,deal_id)
     JOIN card_firm_covars tf
       ON tf.cohort=tm.cohort AND tf.id_group=tm.target_group
     JOIN card_firm_covars cf
       ON cf.cohort=r.cohort AND cf.id_group=r.control_group
     WHERE r.candidate_rank <= %d
     ORDER BY r.cohort,r.deal_id,r.treated_codinv,
              r.distance,r.control_group,r.control_codinv",
    distance_expression, matched_sql,
    distance_expression, distance_expression, stage2_caliper,
    inventor_select,
    LMV2_CARDINALITY$maximum_candidates_per_treated)

  dir.create(candidate_root, recursive = TRUE, showWarnings = FALSE)
  result <- lmv2_write_atomic_parquet(
    con, select_sql, output_path,
    c(
      "cohort", "deal_id", "treated_codinv",
      "control_codinv", "control_group"))
  manifest <- data.frame(
    version = "lmv2_cardinality_candidates_v1",
    cohort = as.integer(cohort),
    execution_hash = execution_hash,
    cardinality_freeze_hash = LMV2_CARDINALITY_FREEZE_SHA256,
    path = result$path, row_count = result$row_count,
    checksum = result$checksum,
    timestamp = as.character(Sys.time()),
    stringsAsFactors = FALSE)
  utils::write.csv(
    manifest,
    file.path(
      candidate_root,
      sprintf("cardinality_candidates_%d_manifest.csv", cohort)),
    row.names = FALSE)
  invisible(output_path)
}

