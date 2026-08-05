# ============================================================================
# P5 sparse technology-cache acceleration
# ============================================================================
# Additive implementation: P4's running 17n/17o pilot is left untouched so
# its execution hash and restartable checkpoints remain valid.
#
# The legacy block query starts from the complete treated x control candidate
# cross and only then joins both sparse IPC vectors. On the real
# 2009/u1/deal-346 benchmark, one block contains about 1 million candidates
# but only 282,641 pairs share an IPC4 feature. Starting from the sparse IPC
# feature join avoids carrying the full candidate cross through both vector
# joins. The output contract is unchanged:
#   (cohort, treated_codinv, control_codinv, shared_ipc4=TRUE, cosine)
#
# This file must be sourced after 17n. The P5 runner explicitly installs the
# accelerated function under the production function name.

LMV2_P5_SPARSE_CACHE_VERSION <- "lmv2_p5_sparse_cache_v1"

if (!exists(
    "lmv2_build_treated_block_shard_legacy",
    envir = .GlobalEnv, inherits = FALSE)) {
  assign(
    "lmv2_build_treated_block_shard_legacy",
    lmv2_build_treated_block_shard,
    envir = .GlobalEnv)
}

lmv2_p5_sparse_execution_hash <- function(base_dir, p3_manifest_hash) {
  component_hashes <- c(
    sparse_technology_cache = lmv2_p3_file_hash(
      file.path(base_dir, "R", "17x_lmv2_p5_sparse_technology_cache.R")),
    p5_runner = lmv2_p3_file_hash(
      file.path(base_dir, "R", "17y_run_lmv2_p5_fast_balancing.R")),
    disk_backed_cache = lmv2_p3_file_hash(
      file.path(base_dir, "R", "17n_lmv2_p4_disk_backed_cache.R")),
    cohort_runner = lmv2_p3_file_hash(
      file.path(base_dir, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R")),
    hybrid_utils = lmv2_p3_file_hash(
      file.path(base_dir, "R", "17l_lmv2_p4_hybrid_core.R")),
    cohort_hybrid_utils = lmv2_p3_file_hash(
      file.path(base_dir, "R", "17m_lmv2_p4_cohort_hybrid_core.R")),
    p4_ebal_config = lmv2_p3_file_hash(
      file.path(base_dir, "R", "17f_lmv2_p4_ebal_config.R")),
    p4_ebal_utils = lmv2_p3_file_hash(
      file.path(base_dir, "R", "17g_lmv2_p4_ebal_utils.R")),
    matching_config = lmv2_p3_file_hash(
      file.path(base_dir, "R", "16a_lmv2_matching_config.R")),
    matching_utils = lmv2_p3_file_hash(
      file.path(base_dir, "R", "16c_lmv2_matching_utils.R")),
    p3_manifest = p3_manifest_hash)
  digest::digest(component_hashes, algo = "sha256")
}

lmv2_build_treated_block_shard_sparse <- function(
    con, g, universe, deal_id, block_idx, treated_block_df,
    donor_pairs_d, admissible_control_groups, recency_gap,
    vectors_path, norms_path, cache_dir, execution_hash) {
  block_ids <- unique(treated_block_df$treated_codinv)
  pair_hash <- lmv2_block_pair_hash(
    treated_block_df, donor_pairs_d, admissible_control_groups, recency_gap)
  treated_id_hash <- digest::digest(
    sort(as.numeric(block_ids)), algo = "sha256")
  treated_id_range <- sprintf("%d-%d", min(block_ids), max(block_ids))
  shard_path <- lmv2_diskcache_shard_path(
    cache_dir, g, universe, deal_id, block_idx)
  manifest_path <- lmv2_diskcache_shard_manifest_path(
    cache_dir, g, universe)
  match_cols <- c(
    "cohort", "universe", "deal_id", "block_idx", "resolution",
    "execution_hash", "pair_hash")
  match_vals <- c(
    g, universe, deal_id, block_idx, "ipc4", execution_hash, pair_hash)
  if (lmv2_manifest_has_valid_row(
      manifest_path, match_cols, match_vals, path_col = "path")) {
    return(invisible(list(
      path = shard_path, pair_hash = pair_hash, reused = TRUE)))
  }

  # Technology similarity is a property of the inventor pair. A control
  # inventor can legitimately appear under multiple admissible firm rows,
  # but those rows must not duplicate its sparse-vector join.
  donor_tech <- unique(donor_pairs_d[
    c("cohort", "deal_id", "control_codinv", "recency_bin_control")])
  if (anyDuplicated(donor_tech[
      c("cohort", "deal_id", "control_codinv")])) {
    stop("lmv2_build_treated_block_shard_sparse: inconsistent recency bins ",
         "for a control inventor within deal ", deal_id)
  }

  duckdb::duckdb_register(
    con, "lmv2_sparse_treated_block", treated_block_df)
  duckdb::duckdb_register(con, "lmv2_sparse_donor_tech", donor_tech)
  on_exit_cleanup <- function() {
    try(duckdb::duckdb_unregister(
      con, "lmv2_sparse_treated_block"), silent = TRUE)
    try(duckdb::duckdb_unregister(
      con, "lmv2_sparse_donor_tech"), silent = TRUE)
  }

  sql <- sprintf("
    WITH treated_vectors AS (
      SELECT t.cohort,t.treated_codinv,t.recency_bin_treated,
             v.ipc_feature,v.frequency
      FROM lmv2_sparse_treated_block t
      JOIN read_parquet('%s') v
        ON v.cohort=t.cohort AND v.codinv=t.treated_codinv
    ),
    control_vectors AS (
      SELECT d.cohort,d.control_codinv,d.recency_bin_control,
             v.ipc_feature,v.frequency
      FROM lmv2_sparse_donor_tech d
      JOIN read_parquet('%s') v
        ON v.cohort=d.cohort AND v.codinv=d.control_codinv
    ),
    dots AS (
      SELECT t.cohort,t.treated_codinv,c.control_codinv,
             SUM(t.frequency*c.frequency) AS dot
      FROM treated_vectors t
      JOIN control_vectors c
        ON c.cohort=t.cohort AND c.ipc_feature=t.ipc_feature
      WHERE t.recency_bin_treated IS NOT NULL
        AND c.recency_bin_control IS NOT NULL
        AND ABS(t.recency_bin_treated-c.recency_bin_control) <= %d
      GROUP BY t.cohort,t.treated_codinv,c.control_codinv
    )
    SELECT d.cohort,d.treated_codinv,d.control_codinv,
           TRUE AS shared_ipc4,
           CASE WHEN tn.norm>0 AND cn.norm>0
                THEN LEAST(1.0,GREATEST(0.0,d.dot/(tn.norm*cn.norm)))
                ELSE NULL END AS cosine
    FROM dots d
    LEFT JOIN read_parquet('%s') tn
      ON tn.cohort=d.cohort AND tn.codinv=d.treated_codinv
    LEFT JOIN read_parquet('%s') cn
      ON cn.cohort=d.cohort AND cn.codinv=d.control_codinv",
    vectors_path, vectors_path, recency_gap, norms_path, norms_path)

  result <- tryCatch(
    lmv2_write_atomic_parquet(
      con, sql, shard_path,
      c("cohort", "treated_codinv", "control_codinv")),
    error = function(e) e)
  on_exit_cleanup()

  manifest_row_base <- data.frame(
    cohort = g, universe = universe, deal_id = deal_id,
    block_idx = block_idx, resolution = "ipc4",
    execution_hash = execution_hash, pair_hash = pair_hash,
    treated_id_hash = treated_id_hash,
    treated_id_range = treated_id_range,
    n_treated_in_block = length(block_ids), path = shard_path,
    timestamp = as.character(Sys.time()), stringsAsFactors = FALSE)
  if (inherits(result, "condition")) {
    lmv2_append_manifest_row(
      manifest_path,
      cbind(
        manifest_row_base,
        data.frame(
          row_count = NA_integer_, checksum = NA_character_,
          status = paste0("failed: ", conditionMessage(result)),
          stringsAsFactors = FALSE)))
    stop(
      "lmv2_build_treated_block_shard_sparse: deal ", deal_id,
      " block ", block_idx, " failed: ", conditionMessage(result))
  }
  lmv2_append_manifest_row(
    manifest_path,
    cbind(
      manifest_row_base,
      data.frame(
        row_count = result$row_count, checksum = result$checksum,
        status = "complete", stringsAsFactors = FALSE)))
  invisible(list(
    path = shard_path, pair_hash = pair_hash, reused = FALSE))
}

lmv2_install_p5_sparse_cache <- function() {
  assign(
    "lmv2_build_treated_block_shard",
    lmv2_build_treated_block_shard_sparse,
    envir = .GlobalEnv)
  assign(
    "lmv2_composite_execution_hash",
    lmv2_p5_sparse_execution_hash,
    envir = .GlobalEnv)
  invisible(TRUE)
}
