# ============================================================================
# Selected-spec P5 acceleration
# ============================================================================
# Additive to the completed/running P4 and P5-v1 paths.
#
# 1. Stage-2 returns an exact bipartite edge cover rather than every
#    caliper-admissible inventor pair. Downstream code uses the edge table only
#    through its treated and control projections, so one representative edge
#    per supported treated inventor plus one per eligible control row preserves
#    the roster exactly while bounding R-side memory.
# 2. The compact cover is persisted atomically and reused by the second
#    weighting scheme.
# 3. Sparse technology blocks target 5 million candidate pairs instead of
#    1 million. The sparse IPC-feature join streams to Parquet, so this reduces
#    file/manifest overhead without recreating the legacy candidate cross.

LMV2_P5_SELECTED_VERSION <- "lmv2_p5_selected_v1"
LMV2_P5_TARGET_PAIRS_PER_BLOCK <- 5000000L

if (!exists("lmv2_p5_v1_execution_hash", envir = .GlobalEnv, inherits = FALSE)) {
  assign("lmv2_p5_v1_execution_hash", lmv2_composite_execution_hash,
         envir = .GlobalEnv)
}

lmv2_p5_selected_execution_hash <- function(base_dir, p3_manifest_hash) {
  selected_settings <- list(
    calipers = get("STAGE1_CALIPERS", envir = .GlobalEnv),
    profiles = get("STAGE1_PROFILES", envir = .GlobalEnv),
    universes = get("UNIVERSES", envir = .GlobalEnv),
    schemes = get("SCHEMES", envir = .GlobalEnv),
    solver = get0(
      "LMV2_P5_SOLVER", envir = .GlobalEnv,
      ifnotfound = "weightit"),
    stage2_caliper = get("STAGE2_CALIPER", envir = .GlobalEnv),
    target_pairs_per_block = LMV2_P5_TARGET_PAIRS_PER_BLOCK)
  digest::digest(c(
    parent = lmv2_p5_v1_execution_hash(base_dir, p3_manifest_hash),
    selected_acceleration = lmv2_p3_file_hash(
      file.path(base_dir, "R", "18f_lmv2_p5_selected_acceleration.R")),
    newton_solver = lmv2_p3_file_hash(
      file.path(base_dir, "R", "18j_lmv2_p5_newton_solver.R")),
    selected_runner = lmv2_p3_file_hash(
      file.path(base_dir, "R", "18g_run_lmv2_p5_selected.R")),
    final_config = lmv2_p3_file_hash(
      file.path(base_dir, "R", "18m_lmv2_p5_final_config.R")),
    weight_materialization = lmv2_p3_file_hash(
      file.path(base_dir, "R", "18n_lmv2_p5_weight_materialization.R")),
    final_amendment = lmv2_p3_file_hash(
      file.path(
        base_dir, "notes",
        "local_match_v2_p5_outcome_blind_amendment.md")),
    fast_grid_runner = lmv2_p3_file_hash(
      file.path(base_dir, "R", "18l_run_lmv2_p4_fast_grid.R")),
    settings = digest::digest(selected_settings, algo = "sha256")),
    algo = "sha256")
}

lmv2_p5_cover_dir <- function(cache_dir, g) {
  file.path(lmv2_diskcache_cohort_dir(cache_dir, g), "profile_edge_covers")
}

lmv2_p5_cover_manifest_path <- function(cache_dir, g) {
  file.path(lmv2_p5_cover_dir(cache_dir, g), "manifest.csv")
}

lmv2_p5_cover_path <- function(cache_dir, g, universe, profile_hash) {
  file.path(
    lmv2_p5_cover_dir(cache_dir, g),
    # Keep the atomic DuckDB temporary path below Windows' legacy MAX_PATH
    # boundary even when the scheduler adds a per-cohort directory.
    sprintf("c_%s_%s.parquet", universe, substr(profile_hash, 1, 12)))
}

lmv2_p5_profile_hash <- function(
    g, universe, caliper, admissible_pool, treated_spine, donor_firms,
    execution_hash) {
  digest::digest(list(
    cohort = g,
    universe = universe,
    caliper = caliper,
    admissible_pool = admissible_pool[
      order(admissible_pool$deal_id, admissible_pool$control_group), ],
    treated_spine = treated_spine[
      order(treated_spine$deal_id, treated_spine$treated_codinv), ],
    donor_firms = donor_firms[
      order(donor_firms$control_group, donor_firms$control_codinv), ],
    execution_hash = execution_hash),
    algo = "sha256")
}

build_stage2_edge_cover_for_profile_diskbacked <- function(
    con, cache_dir, g, universe, admissible_firm_edges_profile,
    treated_inv_ok, donors_profile, donor_cols_profile,
    execution_hash, caliper) {
  empty <- data.frame(
    cohort = integer(), deal_id = integer(),
    treated_codinv = numeric(), control_codinv = numeric(),
    control_group = numeric(), distance = numeric())
  deal_ids <- unique(admissible_firm_edges_profile$deal_id)
  if (!length(deal_ids)) return(empty)

  vars <- LMV2_P3$stage_2$scalar_variables
  recency_gap <- LMV2_P3$stage_2$maximum_recency_bin_gap
  eps <- LMV2_P3_DISTANCE_EPSILON
  paths <- lmv2_list_complete_shard_paths_for_deals(
    cache_dir, g, universe, deal_ids, execution_hash)
  if (!length(paths)) return(empty)
  glob <- paste0("[", paste(sprintf("'%s'", paths), collapse = ","), "]")

  admissible_pool <- unique(
    admissible_firm_edges_profile[
      c("cohort", "deal_id", "control_group")])
  treated_spine <- treated_inv_ok[
    treated_inv_ok$deal_id %in% deal_ids,
    c("cohort", "deal_id", "codinv", "recency_bin", vars)]
  names(treated_spine)[names(treated_spine) == "codinv"] <-
    "treated_codinv"
  donor_firms <- unique(
    donor_cols_profile[
      c("cohort", "control_codinv", "control_group", "recency_bin", vars)])

  profile_hash <- lmv2_p5_profile_hash(
    g, universe, caliper, admissible_pool, treated_spine, donor_firms,
    execution_hash)
  dir.create(
    lmv2_p5_cover_dir(cache_dir, g),
    recursive = TRUE,
    showWarnings = FALSE)
  cover_path <- lmv2_p5_cover_path(
    cache_dir, g, universe, profile_hash)
  cover_manifest <- lmv2_p5_cover_manifest_path(cache_dir, g)
  if (lmv2_manifest_has_valid_row(
      cover_manifest,
      c("cohort", "universe", "profile_hash", "execution_hash"),
      c(g, universe, profile_hash, execution_hash),
      path_col = "path")) {
    return(DBI::dbGetQuery(
      con, sprintf("SELECT * FROM read_parquet('%s')", cover_path)))
  }

  duckdb::duckdb_register(
    con, "p5_cover_admissible_pool", admissible_pool)
  duckdb::duckdb_register(
    con, "p5_cover_treated_spine", treated_spine)
  duckdb::duckdb_register(
    con, "p5_cover_donor_firms", donor_firms)
  cleanup <- function() {
    try(duckdb::duckdb_unregister(
      con, "p5_cover_admissible_pool"), silent = TRUE)
    try(duckdb::duckdb_unregister(
      con, "p5_cover_treated_spine"), silent = TRUE)
    try(duckdb::duckdb_unregister(
      con, "p5_cover_donor_firms"), silent = TRUE)
  }

  var_select <- paste(
    sprintf("t.%s AS %s_t, df.%s AS %s_c", vars, vars, vars, vars),
    collapse = ", ")
  candidate_sql <- sprintf("
    SELECT t.cohort,t.deal_id,t.treated_codinv,
           df.control_codinv,df.control_group,
           t.recency_bin AS recency_bin_t,
           df.recency_bin AS recency_bin_c,%s
    FROM p5_cover_treated_spine t
    JOIN p5_cover_admissible_pool a
      ON a.cohort=t.cohort AND a.deal_id=t.deal_id
    JOIN p5_cover_donor_firms df
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
    candidate_sql, glob, recency_gap)

  var_cols <- paste(vars, collapse = ", ")
  scaler_sql <- sprintf("
    WITH combined AS (
      SELECT %s FROM p5_cover_treated_spine
      UNION ALL
      SELECT %s FROM p5_cover_donor_firms)
    SELECT %s FROM combined",
    var_cols, var_cols,
    paste(
      sprintf("STDDEV_SAMP(%s) AS sd_%s", vars, vars),
      collapse = ", "))
  scaler_row <- tryCatch(
    DBI::dbGetQuery(con, scaler_sql), error = function(e) e)
  if (inherits(scaler_row, "condition")) {
    cleanup()
    stop("P5 edge cover scaler: ", conditionMessage(scaler_row))
  }
  tech_sd_row <- tryCatch(
    DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT STDDEV_SAMP(1-cosine) AS tech_sd FROM (%s)",
        matched_sql)),
    error = function(e) e)
  if (inherits(tech_sd_row, "condition")) {
    cleanup()
    stop("P5 edge cover technology scale: ",
         conditionMessage(tech_sd_row))
  }

  safe_scale <- function(sd) {
    if (is.na(sd) || !is.finite(sd) || sd < eps) "NULL"
    else sprintf("%.15g", sd)
  }
  sd_vals <- vapply(
    vars,
    function(v) safe_scale(
      scaler_row[[paste0("sd_", v)]][1]),
    character(1))
  tech_sd <- safe_scale(tech_sd_row$tech_sd[1])
  gap_terms <- vapply(seq_along(vars), function(i) {
    v <- vars[i]
    if (sd_vals[i] == "NULL") "0"
    else sprintf("POWER((%s_c-%s_t)/%s,2)", v, v, sd_vals[i])
  }, character(1))
  tech_term <- if (tech_sd == "NULL") "0" else
    sprintf("POWER((1-cosine)/%s,2)", tech_sd)
  distance_expr <- sprintf(
    "SQRT(%s)", paste(c(gap_terms, tech_term), collapse = " + "))
  minimum_controls <- get0(
    "LMV2_P5_MIN_CONTROLS_PER_TREATED",
    envir = .GlobalEnv, ifnotfound = 1L)
  minimum_firms <- get0(
    "LMV2_P5_MIN_FIRMS_PER_TREATED",
    envir = .GlobalEnv, ifnotfound = 1L)
  if (!is.numeric(minimum_controls) || length(minimum_controls) != 1L ||
      !is.finite(minimum_controls) || minimum_controls < 1 ||
      !is.numeric(minimum_firms) || length(minimum_firms) != 1L ||
      !is.finite(minimum_firms) || minimum_firms < 1) {
    stop("P5 edge-cover support minima are invalid")
  }
  knn_mode <- isTRUE(get0(
    "LMV2_P5_KNN_MODE", envir = .GlobalEnv, ifnotfound = FALSE))

  # Absolute-caliper mode uses an exact projection-preserving cover:
  # - support_counts optionally enforces rescue-only inventor-first minima;
  #   defaults (one control, one firm) reproduce completed P5 behavior.
  # - rt=1 retains every treated inventor that clears those minima.
  # - rc=1 retains every eligible (deal, control inventor, control firm) row.
  # The downstream pipeline uses no other pair-level information.
  absolute_cover_sql <- sprintf("
    WITH admissible_edges AS (
      SELECT cohort,deal_id,treated_codinv,control_codinv,control_group,
             %s AS distance
      FROM (%s)
      WHERE %s IS NOT NULL AND %s <= %.15g
    ),
    support_counts AS (
      SELECT cohort,deal_id,treated_codinv,
             COUNT(DISTINCT control_codinv) AS n_controls,
             COUNT(DISTINCT control_group) AS n_firms
      FROM admissible_edges
      GROUP BY cohort,deal_id,treated_codinv
    ),
    supported_edges AS (
      SELECT a.*
      FROM admissible_edges a
      JOIN support_counts s
        USING (cohort,deal_id,treated_codinv)
      WHERE s.n_controls >= %d AND s.n_firms >= %d
    ),
    ranked AS (
      SELECT *,
        ROW_NUMBER() OVER (
          PARTITION BY cohort,deal_id,treated_codinv
          ORDER BY distance,control_group,control_codinv) AS rt,
        ROW_NUMBER() OVER (
          PARTITION BY cohort,deal_id,control_group,control_codinv
          ORDER BY treated_codinv) AS rc
      FROM supported_edges
    )
    SELECT cohort,deal_id,treated_codinv,control_codinv,control_group,distance
    FROM ranked
    WHERE rt=1 OR rc=1",
    distance_expr, matched_sql, distance_expr, distance_expr, caliper,
    as.integer(minimum_controls), as.integer(minimum_firms))
  cover_sql <- absolute_cover_sql

  if (knn_mode) {
    knn_k <- get0(
      "LMV2_P5_KNN_K", envir = .GlobalEnv, ifnotfound = NA_integer_)
    sanity_quantile <- get0(
      "LMV2_P5_KNN_SANITY_QUANTILE",
      envir = .GlobalEnv, ifnotfound = NA_real_)
    if (!is.numeric(knn_k) || length(knn_k) != 1L ||
        !is.finite(knn_k) || knn_k < 3 ||
        !is.numeric(sanity_quantile) ||
        length(sanity_quantile) != 1L ||
        !is.finite(sanity_quantile) ||
        sanity_quantile <= 0 || sanity_quantile >= 1) {
      cleanup()
      stop("P5 adaptive k-nearest configuration is invalid")
    }

    # One SQL statement computes the fifth-nearest sanity distribution,
    # applies its cohort-specific quantile, and selects k controls while
    # forcing a second-firm anchor. This avoids materializing the unbounded
    # candidate cross in R or in a temporary in-memory table.
    cover_sql <- sprintf("
      WITH candidate_edges AS (
        SELECT cohort,deal_id,treated_codinv,control_codinv,control_group,
               %s AS distance
        FROM (%s)
        WHERE %s IS NOT NULL
      ),
      ranked_unbounded AS (
        SELECT *,
          ROW_NUMBER() OVER (
            PARTITION BY cohort,deal_id,treated_codinv
            ORDER BY distance,control_group,control_codinv) AS distance_rank
        FROM candidate_edges
      ),
      unbounded_counts AS (
        SELECT cohort,deal_id,treated_codinv,
               COUNT(DISTINCT control_codinv) AS n_controls,
               COUNT(DISTINCT control_group) AS n_firms
        FROM candidate_edges
        GROUP BY cohort,deal_id,treated_codinv
      ),
      fifth_distances AS (
        SELECT r.distance
        FROM ranked_unbounded r
        JOIN unbounded_counts c
          USING (cohort,deal_id,treated_codinv)
        WHERE r.distance_rank=%d
          AND c.n_controls >= %d
          AND c.n_firms >= %d
      ),
      sanity AS (
        SELECT QUANTILE_CONT(distance, %.15g) AS bound
        FROM fifth_distances
      ),
      bounded_edges AS (
        SELECT e.*
        FROM candidate_edges e
        CROSS JOIN sanity s
        WHERE e.distance <= s.bound
      ),
      bounded_counts AS (
        SELECT cohort,deal_id,treated_codinv,
               COUNT(DISTINCT control_codinv) AS n_controls,
               COUNT(DISTINCT control_group) AS n_firms
        FROM bounded_edges
        GROUP BY cohort,deal_id,treated_codinv
      ),
      eligible_edges AS (
        SELECT e.*
        FROM bounded_edges e
        JOIN bounded_counts c
          USING (cohort,deal_id,treated_codinv)
        WHERE c.n_controls >= %d AND c.n_firms >= %d
      ),
      first_ranked AS (
        SELECT *,
          ROW_NUMBER() OVER (
            PARTITION BY cohort,deal_id,treated_codinv
            ORDER BY distance,control_group,control_codinv) AS rn
        FROM eligible_edges
      ),
      first_edges AS (
        SELECT cohort,deal_id,treated_codinv,control_codinv,
               control_group,distance
        FROM first_ranked WHERE rn=1
      ),
      other_firm_ranked AS (
        SELECT e.*,
          ROW_NUMBER() OVER (
            PARTITION BY e.cohort,e.deal_id,e.treated_codinv
            ORDER BY e.distance,e.control_group,e.control_codinv) AS rn
        FROM eligible_edges e
        JOIN first_edges f
          USING (cohort,deal_id,treated_codinv)
        WHERE e.control_group <> f.control_group
      ),
      second_edges AS (
        SELECT cohort,deal_id,treated_codinv,control_codinv,
               control_group,distance
        FROM other_firm_ranked WHERE rn=1
      ),
      anchors AS (
        SELECT * FROM first_edges
        UNION ALL
        SELECT * FROM second_edges
      ),
      remaining_ranked AS (
        SELECT e.*,
          ROW_NUMBER() OVER (
            PARTITION BY e.cohort,e.deal_id,e.treated_codinv
            ORDER BY e.distance,e.control_group,e.control_codinv) AS rn
        FROM eligible_edges e
        LEFT JOIN anchors a
          ON a.cohort=e.cohort
         AND a.deal_id=e.deal_id
         AND a.treated_codinv=e.treated_codinv
         AND a.control_codinv=e.control_codinv
         AND a.control_group=e.control_group
        WHERE a.control_codinv IS NULL
      ),
      selected AS (
        SELECT * FROM anchors
        UNION ALL
        SELECT cohort,deal_id,treated_codinv,control_codinv,
               control_group,distance
        FROM remaining_ranked
        WHERE rn <= %d
      )
      SELECT cohort,deal_id,treated_codinv,control_codinv,
             control_group,distance
      FROM selected",
      distance_expr, matched_sql, distance_expr,
      as.integer(knn_k), as.integer(knn_k),
      as.integer(minimum_firms), sanity_quantile,
      as.integer(knn_k), as.integer(minimum_firms),
      as.integer(knn_k - 2L))
  }

  result <- tryCatch(
    lmv2_write_atomic_parquet(
      con, cover_sql, cover_path,
      c("cohort", "deal_id", "treated_codinv",
        "control_codinv", "control_group")),
    error = function(e) e)
  cleanup()
  if (inherits(result, "condition")) {
    stop("P5 edge cover construction: ", conditionMessage(result))
  }
  lmv2_append_manifest_row(
    cover_manifest,
    data.frame(
      cohort = g, universe = universe, profile_hash = profile_hash,
      execution_hash = execution_hash, path = cover_path,
      row_count = result$row_count, checksum = result$checksum,
      status = "complete", timestamp = as.character(Sys.time()),
      stringsAsFactors = FALSE))
  DBI::dbGetQuery(
    con, sprintf("SELECT * FROM read_parquet('%s')", cover_path))
}

lmv2_build_one_deal_shard_selected <- function(
    con, g, universe, deal_id, admissible_firm_edges_loosest,
    treated_inv_ok, donor_cols_loosest, recency_gap,
    vectors_path, norms_path, cache_dir, execution_hash,
    target_pairs_per_block = LMV2_P5_TARGET_PAIRS_PER_BLOCK) {
  admissible_d <- admissible_firm_edges_loosest[
    admissible_firm_edges_loosest$deal_id == deal_id, , drop = FALSE]
  treated_d <- treated_inv_ok[
    treated_inv_ok$deal_id == deal_id, , drop = FALSE]
  if (!nrow(treated_d) || !nrow(admissible_d)) {
    return(invisible(0L))
  }
  donor_cols_d <- donor_cols_loosest[
    donor_cols_loosest$control_group %in%
      unique(admissible_d$control_group), , drop = FALSE]
  if (!nrow(donor_cols_d)) return(invisible(0L))

  generation_hash <- lmv2_deal_generation_hash(
    admissible_d, treated_d, donor_cols_d, recency_gap,
    target_pairs_per_block)
  gen_manifest_path <- lmv2_diskcache_deal_generation_manifest_path(
    cache_dir, g, universe)
  gen_cols <- c(
    "cohort", "universe", "deal_id", "generation_hash",
    "execution_hash")
  gen_vals <- c(
    g, universe, deal_id, generation_hash, execution_hash)
  if (lmv2_manifest_has_valid_row(
      gen_manifest_path, gen_cols, gen_vals, path_col = "self_path")) {
    prior <- utils::read.csv(
      gen_manifest_path, stringsAsFactors = FALSE)
    prior <- prior[
      prior$deal_id == deal_id & prior$status == "complete", ]
    prior <- prior[nrow(prior), ]
    return(invisible(length(
      strsplit(as.character(prior$active_block_idxs), ";")[[1]])))
  }

  pool <- unique(
    admissible_d[c("cohort", "deal_id", "control_group")])
  donor_pairs_d <- merge(
    pool,
    donor_cols_d[
      c("cohort", "control_codinv", "control_group", "recency_bin")],
    by = c("cohort", "control_group"))
  names(donor_pairs_d)[names(donor_pairs_d) == "recency_bin"] <-
    "recency_bin_control"
  donor_pairs_d <- donor_pairs_d[
    c("cohort", "deal_id", "control_codinv",
      "control_group", "recency_bin_control")]
  admissible_control_groups <- unique(admissible_d$control_group)

  block_size <- lmv2_treated_block_size(
    length(unique(donor_pairs_d$control_codinv)),
    target_pairs_per_block)
  treated_ids <- sort(unique(treated_d$codinv))
  assignment <- ceiling(seq_along(treated_ids) / block_size)
  n_blocks <- max(assignment)
  block_idxs <- integer(0)
  block_hashes <- character(0)
  for (b in seq_len(n_blocks)) {
    ids <- treated_ids[assignment == b]
    treated_block <- treated_d[
      treated_d$codinv %in% ids,
      c("cohort", "deal_id", "codinv", "recency_bin")]
    names(treated_block) <- c(
      "cohort", "deal_id", "treated_codinv", "recency_bin_treated")
    built <- lmv2_build_treated_block_shard(
      con, g, universe, deal_id, b, treated_block, donor_pairs_d,
      admissible_control_groups, recency_gap, vectors_path, norms_path,
      cache_dir, execution_hash)
    block_idxs <- c(block_idxs, b)
    block_hashes <- c(block_hashes, built$pair_hash)
    rm(treated_block, built)
    gc(FALSE)
  }

  marker <- sprintf(
    "%s#deal%d#gen%s", gen_manifest_path, deal_id,
    substr(generation_hash, 1, 12))
  lmv2_append_manifest_row(
    gen_manifest_path,
    data.frame(
      cohort = g, universe = universe, deal_id = deal_id,
      generation_hash = generation_hash,
      execution_hash = execution_hash, n_blocks = n_blocks,
      active_block_idxs = paste(block_idxs, collapse = ";"),
      active_block_hashes = paste(block_hashes, collapse = ";"),
      self_path = marker, checksum = marker, status = "complete",
      timestamp = as.character(Sys.time()), stringsAsFactors = FALSE))
  invisible(n_blocks)
}

lmv2_install_p5_selected_acceleration <- function() {
  assign(
    "build_stage2_edges_for_profile_diskbacked",
    build_stage2_edge_cover_for_profile_diskbacked,
    envir = .GlobalEnv)
  assign(
    "lmv2_build_one_deal_shard",
    lmv2_build_one_deal_shard_selected,
    envir = .GlobalEnv)
  assign(
    "lmv2_composite_execution_hash",
    lmv2_p5_selected_execution_hash,
    envir = .GlobalEnv)
  invisible(TRUE)
}
