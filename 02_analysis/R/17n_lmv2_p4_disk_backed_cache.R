# ============================================================================
# Disk-backed Stage-2 technology cache (memory fix, cohort-2009 OOM, v3 --
# review correction after the v2 smoke test found real deal 346 exposed a
# second memory risk: build_stage2_edges_for_profile_diskbacked() itself
# still collected a deal's full shard content -- 17.7M rows for deal 346 --
# into R before filtering. Additive only: 15*/16*/17a-e and the existing
# IN-MEMORY build_stage2_technology_cache_for_cohort()/
# build_stage2_edges_for_profile() path stay completely untouched and are
# still what runs for 1995/2002.
#
# v3 architecture:
#   1. Technology SHARDS (cosine/shared-IPC4) are built per treated-inventor
#      BLOCK within a deal (v2), never per cohort or even per whole deal --
#      construction never touches more than one block's candidate cross at
#      once, and that cross itself is built and consumed entirely inside one
#      SQL statement, never materialized in R.
#   2. PROFILE-level edge construction (this file's newest fix) is now
#      TWO-PASS, entirely in DuckDB: Pass 1 computes the profile's own
#      scalar-covariate and technology-distance standard deviations (the
#      SAME quantities 16c's lmv2_prepare_stage2_edges() computes, over the
#      SAME populations -- covariate SDs from the full profile treated+donor
#      population, tech-distance SD from the shared-IPC4/recency-admissible
#      candidate set) via SQL aggregates; Pass 2 computes the standardized
#      Stage-2 distance and applies the caliper INSIDE one SQL statement
#      that reads only the relevant shard files, returning ONLY the (much
#      smaller) caliper-admissible edges to R. The formula is a byte-exact
#      SQL port of 16c's algorithm (lmv2_safe_sd/lmv2_scale_gap semantics,
#      including degenerate-dimension handling) -- verified in the fixture
#      suite against the in-memory reference on real and synthetic data.
#   3. Every cache artifact (vectors/norms, each block shard, each deal's
#      generation record, each profile row) is keyed on a single COMPOSITE
#      EXECUTION HASH covering every piece of code and config that
#      determines the cache's output (this file, the cohort runner, the
#      matching/entropy utilities, the P4 config+amendments, and the P3
#      manifest) -- not the P3 manifest alone -- so a change anywhere in
#      that chain invalidates reuse, not just a P3-manifest drift.
#   4. Each deal BUILD is recorded as one atomic "generation": the exact set
#      of active block indices and their individual pair-identity hashes,
#      keyed on a generation hash over the deal's full admissible-firm/
#      treated/donor/recency-gap/block-size-target inputs. Profile-level
#      reads use ONLY the block set listed in a deal's LATEST valid
#      generation record -- if block sizing or donor pools ever change
#      between runs, stale blocks left over from an earlier generation can
#      never leak into a profile.
# ============================================================================

lmv2_diskcache_cohort_dir <- function(cache_dir, g) file.path(cache_dir, sprintf("cohort_%d", g))
lmv2_diskcache_universe_dir <- function(cache_dir, g, universe) {
  file.path(lmv2_diskcache_cohort_dir(cache_dir, g), sprintf("universe_%s", universe))
}
lmv2_diskcache_vectors_path <- function(cache_dir, g) file.path(lmv2_diskcache_cohort_dir(cache_dir, g), "ipc4_vectors.parquet")
lmv2_diskcache_norms_path <- function(cache_dir, g) file.path(lmv2_diskcache_cohort_dir(cache_dir, g), "ipc4_norms.parquet")
lmv2_diskcache_vectors_manifest_path <- function(cache_dir, g) file.path(lmv2_diskcache_cohort_dir(cache_dir, g), "vectors_manifest.csv")
lmv2_diskcache_shard_path <- function(cache_dir, g, universe, deal_id, block_idx) {
  file.path(lmv2_diskcache_universe_dir(cache_dir, g, universe),
           sprintf("tech_shard_deal%d_block%d.parquet", deal_id, block_idx))
}
lmv2_diskcache_shard_manifest_path <- function(cache_dir, g, universe) {
  file.path(lmv2_diskcache_universe_dir(cache_dir, g, universe), "shard_manifest.csv")
}
lmv2_diskcache_deal_generation_manifest_path <- function(cache_dir, g, universe) {
  file.path(lmv2_diskcache_universe_dir(cache_dir, g, universe), "deal_generation_manifest.csv")
}
lmv2_diskcache_profile_row_dir <- function(cache_dir, g) file.path(lmv2_diskcache_cohort_dir(cache_dir, g), "profile_rows")
lmv2_diskcache_profile_row_path <- function(cache_dir, g, caliper, profile, universe, scheme) {
  file.path(lmv2_diskcache_profile_row_dir(cache_dir, g),
           sprintf("row_c%s_%s_%s_%s.csv", format(caliper, trim = TRUE), profile, universe, scheme))
}
lmv2_diskcache_profile_row_manifest_path <- function(cache_dir, g) {
  file.path(lmv2_diskcache_profile_row_dir(cache_dir, g), "manifest.csv")
}

lmv2_roster_hash <- function(codinv_roster) {
  digest::digest(sort(unique(as.numeric(codinv_roster))), algo = "sha256")
}

# ---- Composite execution hash (review correction): reuse of ANY cache
# artifact (vectors, technology shards, deal generations, profile rows) is
# gated on this single hash, not the P3 manifest alone -- it covers every
# file whose content can change what the disk-backed pipeline computes.
# Post-repo-migration: every component now lives under `base_dir/R/`
# (`02_analysis`), so a single directory suffices.
lmv2_composite_execution_hash <- function(base_dir, p3_manifest_hash) {
  component_hashes <- c(
    disk_backed_cache = lmv2_p3_file_hash(file.path(base_dir, "R", "17n_lmv2_p4_disk_backed_cache.R")),
    cohort_runner = lmv2_p3_file_hash(file.path(base_dir, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R")),
    hybrid_utils = lmv2_p3_file_hash(file.path(base_dir, "R", "17l_lmv2_p4_hybrid_core.R")),
    cohort_hybrid_utils = lmv2_p3_file_hash(file.path(base_dir, "R", "17m_lmv2_p4_cohort_hybrid_core.R")),
    p4_ebal_config = lmv2_p3_file_hash(file.path(base_dir, "R", "17f_lmv2_p4_ebal_config.R")),
    p4_ebal_utils = lmv2_p3_file_hash(file.path(base_dir, "R", "17g_lmv2_p4_ebal_utils.R")),
    matching_config = lmv2_p3_file_hash(file.path(base_dir, "R", "16a_lmv2_matching_config.R")),
    matching_utils = lmv2_p3_file_hash(file.path(base_dir, "R", "16c_lmv2_matching_utils.R")),
    p3_manifest = p3_manifest_hash)
  digest::digest(component_hashes, algo = "sha256")
}

# ---- Adaptive treated-inventor block size (review correction): a deal with
# ~50 admissible firms can still have over a thousand treated inventors --
# firm count and treated-inventor count are unrelated, and deal-level-only
# blocking let one such deal (2009 real data, deal 346: 1,279 treated
# inventors x 23,364 eligible donors) expand to ~30 million candidate pairs
# before any filtering, which is what drove real worker memory past 9GB.
# Block size targets ~target_pairs total candidate pairs per block:
# n_treated_per_block = max(1, floor(target_pairs / n_eligible_donors)).
lmv2_treated_block_size <- function(n_eligible_donors, target_pairs = 1000000L) {
  max(1L, floor(target_pairs / max(1L, n_eligible_donors)))
}

# ---- Strengthened block-identity hash (review correction): covers the
# sorted (treated_codinv, recency_bin) rows, the sorted (control_codinv,
# control_group, recency_bin) rows, the admissible control-GROUP set, and
# the recency gap -- not just bare ID lists. The pair set a block produces
# is a deterministic function of exactly these inputs (verified in the
# fixture suite against an unsplit reference), so this remains a valid
# fingerprint for restart/reuse gating without ever materializing the
# (potentially enormous) full pair cross to hash it directly.
lmv2_block_pair_hash <- function(treated_block_df, donor_pairs_d, admissible_control_groups, recency_gap) {
  treated_key <- unique(treated_block_df[c("treated_codinv", "recency_bin_treated")])
  treated_key <- treated_key[order(treated_key$treated_codinv), ]
  donor_key <- unique(donor_pairs_d[c("control_codinv", "control_group", "recency_bin_control")])
  donor_key <- donor_key[order(donor_key$control_codinv, donor_key$control_group), ]
  digest::digest(list(treated = treated_key, donors = donor_key,
                      admissible_control_groups = sort(unique(as.numeric(admissible_control_groups))),
                      recency_gap = recency_gap), algo = "sha256")
}

# ---- Deal-generation hash: covers the deal's FULL admissible-firm set,
# treated-inventor set, donor set, recency gap, and block-size target --
# i.e. everything that determines how many blocks a deal produces and what
# they contain. Used to detect "this deal's inputs or block-sizing changed
# since the last build" at the DEAL level, distinct from (and in addition
# to) each individual block's own pair hash.
lmv2_deal_generation_hash <- function(admissible_d, treated_d, donor_cols_d, recency_gap, target_pairs_per_block) {
  digest::digest(list(
    admissible = unique(admissible_d[order(admissible_d$control_group), c("deal_id", "control_group")]),
    treated_ids = sort(unique(as.numeric(treated_d$codinv))),
    donor_ids = sort(unique(as.numeric(donor_cols_d$control_codinv))),
    recency_gap = recency_gap, target_pairs_per_block = target_pairs_per_block), algo = "sha256")
}

# ---- Generic atomic Parquet writer: COPY to a temp file, validate (row
# count + key uniqueness off the temp file itself), checksum, THEN rename.
lmv2_write_atomic_parquet <- function(con, select_sql, final_path, key_cols) {
  dir.create(dirname(final_path), recursive = TRUE, showWarnings = FALSE)
  ts <- gsub("[: ]", "-", format(Sys.time(), "%Y%m%d%H%M%OS3"))
  tmp_path <- paste0(final_path, sprintf(".tmp_%d_%s", Sys.getpid(), ts))
  DBI::dbExecute(con, sprintf("COPY (%s) TO '%s' (FORMAT PARQUET)", select_sql, tmp_path))
  check <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS n_rows, COUNT(*) - COUNT(DISTINCT (%s)) AS n_dupe_keys FROM read_parquet('%s')",
    paste(key_cols, collapse = ", "), tmp_path))
  if (isTRUE(check$n_dupe_keys[1] != 0L)) {
    file.remove(tmp_path)
    stop("lmv2_write_atomic_parquet: duplicate keys in shard before commit (", final_path, ")")
  }
  checksum <- lmv2_p3_file_hash(tmp_path)
  ok <- file.rename(tmp_path, final_path)
  if (!ok) { file.remove(tmp_path); stop("lmv2_write_atomic_parquet: rename failed for ", final_path) }
  list(path = final_path, row_count = check$n_rows[1], checksum = checksum)
}

lmv2_append_manifest_row <- function(manifest_path, row) {
  dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.table(row, manifest_path, sep = ",", row.names = FALSE,
                     col.names = !file.exists(manifest_path), append = file.exists(manifest_path))
}

# ---- TRUE if a manifest has a "complete" row matching ALL match_cols/vals
# AND the referenced file still exists AND its live checksum still matches.
lmv2_manifest_has_valid_row <- function(manifest_path, match_cols, match_vals, path_col, checksum_col = "checksum") {
  if (!file.exists(manifest_path)) return(FALSE)
  m <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  if (!nrow(m) || !"status" %in% names(m)) return(FALSE)
  hit <- m
  for (i in seq_along(match_cols)) {
    if (!match_cols[i] %in% names(hit)) return(FALSE)
    hit <- hit[as.character(hit[[match_cols[i]]]) == as.character(match_vals[i]), , drop = FALSE]
  }
  hit <- hit[hit$status == "complete", , drop = FALSE]
  if (!nrow(hit)) return(FALSE)
  hit <- hit[nrow(hit), ]
  file.exists(hit[[path_col]]) && identical(lmv2_p3_file_hash(hit[[path_col]]), hit[[checksum_col]])
}

# ---- STEP 1: normalized IPC4 vectors + norms, built ONCE per cohort from
# the DIRECT UNION of treated codinv and eligible-donor codinv across BOTH
# universes (never from expanded pairs). Reused across u1/u3/every future
# run (P5 included) only while (cohort, resolution, roster_hash,
# execution_hash) all still match.
lmv2_build_ipc4_vectors_norms <- function(con, g, codinv_roster, cache_dir, execution_hash) {
  vec_path <- lmv2_diskcache_vectors_path(cache_dir, g)
  norm_path <- lmv2_diskcache_norms_path(cache_dir, g)
  manifest_path <- lmv2_diskcache_vectors_manifest_path(cache_dir, g)
  roster_hash <- lmv2_roster_hash(codinv_roster)
  match_cols <- c("cohort", "resolution", "roster_hash", "execution_hash")
  match_vals <- c(g, "ipc4", roster_hash, execution_hash)
  if (lmv2_manifest_has_valid_row(manifest_path, match_cols, match_vals, path_col = "vectors_path", checksum_col = "vectors_checksum") &&
      lmv2_manifest_has_valid_row(manifest_path, match_cols, match_vals, path_col = "norms_path", checksum_col = "norms_checksum")) {
    return(list(vectors_path = vec_path, norms_path = norm_path, roster_hash = roster_hash, reused = TRUE))
  }
  roster_df <- data.frame(cohort = g, codinv = unique(as.numeric(codinv_roster)))
  duckdb::duckdb_register(con, "lmv2_diskcache_roster", roster_df)
  # Speed fix (review correction #5.4): materialize the year-filtered,
  # codinv-precast IPC4 source ONCE (a single scan of inventor_ipc_year for
  # this cohort's 5-year window) instead of letting the join below CAST()
  # every row of that (potentially large) table on the fly.
  DBI::dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE lmv2_diskcache_ipc4_source AS
    SELECT CAST(i.codinv AS BIGINT) AS codinv, m.ipc_feature, i.patent_count
    FROM inventor_ipc_year i
    JOIN lmv2_p3_ipc_code_map m ON m.ipc_code=i.ipc_code AND m.resolution='ipc4'
    WHERE i.year BETWEEN %d AND %d", g - 5, g - 1))
  vectors_sql <- "
    WITH weighted AS (
      SELECT r.cohort,r.codinv,s.ipc_feature,SUM(s.patent_count)::DOUBLE weight
      FROM lmv2_diskcache_roster r
      JOIN lmv2_diskcache_ipc4_source s ON s.codinv=r.codinv
      GROUP BY r.cohort,r.codinv,s.ipc_feature
    )
    SELECT cohort,codinv,ipc_feature,weight/SUM(weight) OVER(PARTITION BY cohort,codinv) AS frequency
    FROM weighted"
  vec_result <- lmv2_write_atomic_parquet(con, vectors_sql, vec_path, c("cohort", "codinv", "ipc_feature"))
  try(duckdb::duckdb_unregister(con, "lmv2_diskcache_roster"), silent = TRUE)
  DBI::dbExecute(con, "DROP TABLE IF EXISTS lmv2_diskcache_ipc4_source")
  norms_sql <- sprintf("SELECT cohort,codinv,SQRT(SUM(frequency*frequency)) AS norm FROM read_parquet('%s') GROUP BY cohort,codinv", vec_path)
  norm_result <- lmv2_write_atomic_parquet(con, norms_sql, norm_path, c("cohort", "codinv"))
  lmv2_append_manifest_row(manifest_path, data.frame(
    cohort = g, resolution = "ipc4", roster_hash = roster_hash, execution_hash = execution_hash,
    vectors_path = vec_path, vectors_row_count = vec_result$row_count, vectors_checksum = vec_result$checksum,
    norms_path = norm_path, norms_row_count = norm_result$row_count, norms_checksum = norm_result$checksum,
    n_codinv_in_roster = length(unique(codinv_roster)),
    status = "complete", timestamp = as.character(Sys.time()), stringsAsFactors = FALSE))
  rm(roster_df); gc(FALSE)
  list(vectors_path = vec_path, norms_path = norm_path, roster_hash = roster_hash, reused = FALSE)
}

# ---- STEP 2: ONE treated-inventor BLOCK of ONE deal's similarity+shared-
# IPC4 shard. The candidate cross (treated_block x donor_pairs_d), its
# recency filter, AND the dot-product/cosine computation all run as ONE SQL
# statement executed via COPY ... TO (lmv2_write_atomic_parquet) -- never
# pulled into R. Only POSITIVE shared_ipc4 rows are stored (speed fix,
# review correction #5.1): everything downstream (both the in-memory
# reference and this file's own profile-level reader) only ever consumes
# shared_ipc4=TRUE rows, so storing the FALSE rows was pure waste -- an
# INNER JOIN on `dots` (rather than the previous LEFT JOIN emitting a
# shared_ipc4 boolean for every candidate pair) keeps only rows that
# actually share an IPC4 feature, verified in the fixture suite to produce
# an identical admissible pair set. Reused only if cohort, universe,
# deal_id, block_idx, resolution, execution_hash, AND the strengthened
# block-identity hash all match a checksummed prior shard.
lmv2_build_treated_block_shard <- function(con, g, universe, deal_id, block_idx, treated_block_df,
                                           donor_pairs_d, admissible_control_groups, recency_gap,
                                           vectors_path, norms_path, cache_dir, execution_hash) {
  block_ids <- unique(treated_block_df$treated_codinv)
  pair_hash <- lmv2_block_pair_hash(treated_block_df, donor_pairs_d, admissible_control_groups, recency_gap)
  treated_id_hash <- digest::digest(sort(as.numeric(block_ids)), algo = "sha256")
  treated_id_range <- sprintf("%d-%d", min(block_ids), max(block_ids))
  shard_path <- lmv2_diskcache_shard_path(cache_dir, g, universe, deal_id, block_idx)
  manifest_path <- lmv2_diskcache_shard_manifest_path(cache_dir, g, universe)
  match_cols <- c("cohort", "universe", "deal_id", "block_idx", "resolution", "execution_hash", "pair_hash")
  match_vals <- c(g, universe, deal_id, block_idx, "ipc4", execution_hash, pair_hash)
  if (lmv2_manifest_has_valid_row(manifest_path, match_cols, match_vals, path_col = "path")) {
    return(invisible(list(path = shard_path, pair_hash = pair_hash, reused = TRUE)))
  }
  duckdb::duckdb_register(con, "lmv2_diskcache_treated_block", treated_block_df)
  duckdb::duckdb_register(con, "lmv2_diskcache_donor_pairs", donor_pairs_d)
  # Speed fix (review correction #5.2): SELECT DISTINCT over the
  # (potentially ~1M-row) candidate cross is expensive but only actually
  # NEEDED when a donor inventor legitimately appears under more than one
  # admissible control_group for this deal (duplicate control_codinv rows in
  # donor_pairs_d would otherwise fan out the same treated-control pair once
  # per firm). treated_block_df is already unique on treated_codinv by
  # construction, so uniqueness is certified per-call by checking JUST
  # donor_pairs_d$control_codinv (cheap, donor_pairs_d is small) -- DISTINCT
  # is only kept in the SQL when that check finds a real duplicate.
  donors_certified_unique <- !anyDuplicated(donor_pairs_d$control_codinv)
  select_clause <- if (donors_certified_unique) "SELECT" else "SELECT DISTINCT"
  sql <- sprintf("
    WITH candidate AS (
      %s t.cohort, t.treated_codinv, d.control_codinv
      FROM lmv2_diskcache_treated_block t
      JOIN lmv2_diskcache_donor_pairs d ON d.cohort=t.cohort AND d.deal_id=t.deal_id
      WHERE t.recency_bin_treated IS NOT NULL AND d.recency_bin_control IS NOT NULL
        AND ABS(t.recency_bin_treated - d.recency_bin_control) <= %d
    ),
    dots AS (
      SELECT p.cohort,p.treated_codinv,p.control_codinv,SUM(t.frequency*c.frequency) dot
      FROM candidate p
      JOIN read_parquet('%s') t ON t.cohort=p.cohort AND t.codinv=p.treated_codinv
      JOIN read_parquet('%s') c ON c.cohort=p.cohort AND c.codinv=p.control_codinv AND c.ipc_feature=t.ipc_feature
      GROUP BY p.cohort,p.treated_codinv,p.control_codinv
    )
    SELECT d.cohort,d.treated_codinv,d.control_codinv, TRUE AS shared_ipc4,
           CASE WHEN tn.norm>0 AND cn.norm>0
                THEN LEAST(1.0,GREATEST(0.0,d.dot/(tn.norm*cn.norm)))
                ELSE NULL END AS cosine
    FROM dots d
    LEFT JOIN read_parquet('%s') tn ON tn.cohort=d.cohort AND tn.codinv=d.treated_codinv
    LEFT JOIN read_parquet('%s') cn ON cn.cohort=d.cohort AND cn.codinv=d.control_codinv",
    select_clause, recency_gap, vectors_path, vectors_path, norms_path, norms_path)
  result <- tryCatch(lmv2_write_atomic_parquet(con, sql, shard_path, c("cohort", "treated_codinv", "control_codinv")),
                     error = function(e) e)
  try(duckdb::duckdb_unregister(con, "lmv2_diskcache_treated_block"), silent = TRUE)
  try(duckdb::duckdb_unregister(con, "lmv2_diskcache_donor_pairs"), silent = TRUE)
  manifest_row_base <- data.frame(
    cohort = g, universe = universe, deal_id = deal_id, block_idx = block_idx, resolution = "ipc4",
    execution_hash = execution_hash, pair_hash = pair_hash,
    treated_id_hash = treated_id_hash, treated_id_range = treated_id_range,
    n_treated_in_block = length(block_ids), path = shard_path,
    timestamp = as.character(Sys.time()), stringsAsFactors = FALSE)
  if (inherits(result, "condition")) {
    lmv2_append_manifest_row(manifest_path, cbind(manifest_row_base,
      data.frame(row_count = NA_integer_, checksum = NA_character_,
                status = paste0("failed: ", conditionMessage(result)), stringsAsFactors = FALSE)))
    stop("lmv2_build_treated_block_shard: deal ", deal_id, " block ", block_idx, " failed: ", conditionMessage(result))
  }
  lmv2_append_manifest_row(manifest_path, cbind(manifest_row_base,
    data.frame(row_count = result$row_count, checksum = result$checksum, status = "complete", stringsAsFactors = FALSE)))
  invisible(list(path = shard_path, pair_hash = pair_hash, reused = FALSE))
}

# ---- Build ONE deal's shards, split into treated-inventor BLOCKS sized so
# each block's candidate-pair volume targets ~target_pairs_per_block pairs
# (a deal's firm count says nothing about its treated-inventor count; deal-
# level-only blocking let a 53-firm, 1,279-treated-inventor real 2009 deal
# expand to ~30M pairs before any filtering). Treated inventors are assigned
# to blocks deterministically by SORTED treated_codinv. After all blocks are
# built, writes ONE atomic "generation" record listing the exact active
# block set and its per-block pair hashes -- if a REBUILD with a DIFFERENT
# generation hash (e.g. a changed target_pairs_per_block, or a changed
# admissible-firm/treated/donor set) produces FEWER blocks than a prior
# generation, the earlier generation's now-stale extra blocks are recorded
# as superseded and profile reads never see them (see
# lmv2_list_complete_shard_paths_for_deals()). Skips the whole deal if a
# valid generation record for the SAME generation hash + execution hash
# already exists (deal-level restart, in addition to each block's own
# pair-hash-gated restart).
lmv2_build_one_deal_shard <- function(con, g, universe, deal_id, admissible_firm_edges_loosest,
                                      treated_inv_ok, donor_cols_loosest, recency_gap,
                                      vectors_path, norms_path, cache_dir, execution_hash,
                                      target_pairs_per_block = 1000000L) {
  admissible_d <- admissible_firm_edges_loosest[admissible_firm_edges_loosest$deal_id == deal_id, , drop = FALSE]
  treated_d <- treated_inv_ok[treated_inv_ok$deal_id == deal_id, , drop = FALSE]
  if (!nrow(treated_d) || !nrow(admissible_d)) { rm(admissible_d, treated_d); return(invisible(0L)) }
  donor_cols_d <- donor_cols_loosest[donor_cols_loosest$control_group %in% unique(admissible_d$control_group), , drop = FALSE]
  if (!nrow(donor_cols_d)) { rm(admissible_d, treated_d, donor_cols_d); return(invisible(0L)) }

  generation_hash <- lmv2_deal_generation_hash(admissible_d, treated_d, donor_cols_d, recency_gap, target_pairs_per_block)
  gen_manifest_path <- lmv2_diskcache_deal_generation_manifest_path(cache_dir, g, universe)
  gen_match_cols <- c("cohort", "universe", "deal_id", "generation_hash", "execution_hash")
  gen_match_vals <- c(g, universe, deal_id, generation_hash, execution_hash)
  if (lmv2_manifest_has_valid_row(gen_manifest_path, gen_match_cols, gen_match_vals, path_col = "self_path")) {
    prior <- utils::read.csv(gen_manifest_path, stringsAsFactors = FALSE)
    prior <- prior[prior$deal_id == deal_id & prior$status == "complete", ]
    prior <- prior[nrow(prior), ]
    return(invisible(length(strsplit(as.character(prior$active_block_idxs), ";")[[1]])))
  }

  pool <- unique(admissible_d[c("cohort", "deal_id", "control_group")])
  donor_pairs_d <- merge(pool, donor_cols_d[c("cohort", "control_codinv", "control_group", "recency_bin")],
                         by = c("cohort", "control_group"))
  names(donor_pairs_d)[names(donor_pairs_d) == "recency_bin"] <- "recency_bin_control"
  donor_pairs_d <- donor_pairs_d[c("cohort", "deal_id", "control_codinv", "control_group", "recency_bin_control")]
  admissible_control_groups <- unique(admissible_d$control_group)

  n_eligible_donors <- length(unique(donor_pairs_d$control_codinv))
  block_size <- lmv2_treated_block_size(n_eligible_donors, target_pairs_per_block)
  treated_ids_sorted <- sort(unique(treated_d$codinv))
  block_assignment <- ceiling(seq_along(treated_ids_sorted) / block_size)
  n_blocks <- max(block_assignment)

  active_block_idxs <- integer(0)
  active_block_hashes <- character(0)
  for (b in seq_len(n_blocks)) {
    block_ids <- treated_ids_sorted[block_assignment == b]
    treated_block_df <- treated_d[treated_d$codinv %in% block_ids, c("cohort", "deal_id", "codinv", "recency_bin")]
    names(treated_block_df)[names(treated_block_df) == "codinv"] <- "treated_codinv"
    names(treated_block_df)[names(treated_block_df) == "recency_bin"] <- "recency_bin_treated"
    res <- lmv2_build_treated_block_shard(con, g, universe, deal_id, b, treated_block_df, donor_pairs_d,
                                          admissible_control_groups, recency_gap, vectors_path, norms_path,
                                          cache_dir, execution_hash)
    active_block_idxs <- c(active_block_idxs, b)
    active_block_hashes <- c(active_block_hashes, res$pair_hash)
    rm(treated_block_df, res); gc(FALSE)
  }
  gen_path_marker <- sprintf("%s#deal%d#gen%s", gen_manifest_path, deal_id, substr(generation_hash, 1, 12))
  lmv2_append_manifest_row(gen_manifest_path, data.frame(
    cohort = g, universe = universe, deal_id = deal_id, generation_hash = generation_hash,
    execution_hash = execution_hash, n_blocks = n_blocks,
    active_block_idxs = paste(active_block_idxs, collapse = ";"),
    active_block_hashes = paste(active_block_hashes, collapse = ";"),
    self_path = gen_path_marker, checksum = gen_path_marker,
    status = "complete", timestamp = as.character(Sys.time()), stringsAsFactors = FALSE))
  rm(admissible_d, treated_d, donor_cols_d, pool, donor_pairs_d)
  gc(FALSE)
  invisible(n_blocks)
}

# ---- Top-level per-(cohort,universe) orchestrator: iterates deal_ids ONE AT
# A TIME (no cohort-wide pairs table ever constructed; each deal itself is
# further split into treated-inventor blocks internally). Vectors/norms are
# NOT built here -- they must already exist (built once, upfront, from the
# U1+U3 roster union) and are passed in as paths.
lmv2_build_disk_backed_technology_shards_for_universe <- function(con, g, universe, admissible_firm_edges_loosest,
                                                                   treated_inv_ok, donor_cols_loosest, recency_gap,
                                                                   vectors_path, norms_path, cache_dir,
                                                                   execution_hash) {
  deal_ids <- unique(admissible_firm_edges_loosest$deal_id)
  for (d in deal_ids) {
    lmv2_build_one_deal_shard(con, g, universe, d, admissible_firm_edges_loosest, treated_inv_ok,
                              donor_cols_loosest, recency_gap, vectors_path, norms_path, cache_dir,
                              execution_hash)
  }
  invisible(deal_ids)
}

# ---- ONLY the block shard paths listed in each deal's LATEST valid
# generation record (for this exact execution_hash), individually
# checksum-verified. A deal's earlier generation's now-superseded blocks
# (e.g. after a target_pairs_per_block change produced a different block
# count) are never returned, even if those old block files/manifest rows
# are still physically present on disk.
lmv2_list_complete_shard_paths_for_deals <- function(cache_dir, g, universe, deal_ids, execution_hash) {
  gen_manifest_path <- lmv2_diskcache_deal_generation_manifest_path(cache_dir, g, universe)
  shard_manifest_path <- lmv2_diskcache_shard_manifest_path(cache_dir, g, universe)
  if (!file.exists(gen_manifest_path) || !file.exists(shard_manifest_path) || !length(deal_ids)) return(character(0))
  gm <- utils::read.csv(gen_manifest_path, stringsAsFactors = FALSE)
  # active_block_idxs/active_block_hashes are semicolon-joined strings, but
  # a single-block deal's value (e.g. "1") contains no semicolon and no
  # non-numeric characters -- read.csv()'s type inference then silently
  # parses that column as integer/logical instead of character, and
  # strsplit() on a non-character column errors. Force character explicitly.
  gm$active_block_idxs <- as.character(gm$active_block_idxs)
  gm$active_block_hashes <- as.character(gm$active_block_hashes)
  gm <- gm[gm$status == "complete" & gm$deal_id %in% deal_ids &
          as.character(gm$execution_hash) == as.character(execution_hash), ]
  if (!nrow(gm)) return(character(0))
  gm <- gm[nrow(gm):1, ]; gm <- gm[!duplicated(gm$deal_id), ]  # latest generation per deal

  sm <- utils::read.csv(shard_manifest_path, stringsAsFactors = FALSE)
  sm <- sm[nrow(sm):1, ]; sm <- sm[!duplicated(paste(sm$deal_id, sm$block_idx)), ]  # latest shard row per (deal,block)

  paths <- character(0)
  for (i in seq_len(nrow(gm))) {
    d <- gm$deal_id[i]
    active_idxs <- as.integer(strsplit(gm$active_block_idxs[i], ";")[[1]])
    active_hashes <- strsplit(gm$active_block_hashes[i], ";")[[1]]
    for (j in seq_along(active_idxs)) {
      row <- sm[sm$deal_id == d & sm$block_idx == active_idxs[j] &
               as.character(sm$execution_hash) == as.character(execution_hash) &
               sm$pair_hash == active_hashes[j] & sm$status == "complete", ]
      if (nrow(row) && file.exists(row$path[1]) && identical(lmv2_p3_file_hash(row$path[1]), row$checksum[1])) {
        paths <- c(paths, row$path[1])
      }
    }
  }
  unique(paths)
}

# ---- Two-pass disk-backed profile edge construction (v3 fix): Pass 1
# computes this profile's own scalar-covariate and technology-distance
# standard deviations via SQL aggregates (a byte-exact port of 16c's
# lmv2_prepare_stage2_edges() scaling algorithm -- covariate SDs over the
# FULL profile treated+donor population, tech-distance SD over the shared-
# IPC4/recency-admissible candidate set); Pass 2 computes the standardized
# distance and applies the Stage-2 caliper inside ONE SQL statement that
# reads only the relevant active block shards, returning ONLY the (far
# smaller) caliper-admissible edges to R. Deal 346 alone has ~17.7M shard
# rows; after the Stage-2 caliper this collapses to a small admissible set,
# which is now the ONLY thing that ever reaches R.
build_stage2_edges_for_profile_diskbacked <- function(con, cache_dir, g, universe,
                                                       admissible_firm_edges_profile, treated_inv_ok,
                                                       donors_profile, donor_cols_profile,
                                                       execution_hash, caliper) {
  empty <- data.frame(cohort = integer(), deal_id = integer(), treated_codinv = numeric(),
                      control_codinv = numeric(), control_group = numeric(), distance = numeric())
  deal_ids <- unique(admissible_firm_edges_profile$deal_id)
  if (!length(deal_ids)) return(empty)
  vars <- LMV2_P3$stage_2$scalar_variables
  recency_gap <- LMV2_P3$stage_2$maximum_recency_bin_gap
  eps <- LMV2_P3_DISTANCE_EPSILON

  paths <- lmv2_list_complete_shard_paths_for_deals(cache_dir, g, universe, deal_ids, execution_hash)
  if (!length(paths)) return(empty)
  glob <- paste0("[", paste(sprintf("'%s'", paths), collapse = ","), "]")

  admissible_pool <- unique(admissible_firm_edges_profile[c("cohort", "deal_id", "control_group")])
  treated_spine <- treated_inv_ok[treated_inv_ok$deal_id %in% deal_ids,
                                  c("cohort", "deal_id", "codinv", "recency_bin", vars)]
  names(treated_spine)[names(treated_spine) == "codinv"] <- "treated_codinv"
  donor_firms <- unique(donor_cols_profile[c("cohort", "control_codinv", "control_group", "recency_bin", vars)])

  duckdb::duckdb_register(con, "diskbacked_admissible_pool", admissible_pool)
  duckdb::duckdb_register(con, "diskbacked_treated_spine", treated_spine)
  duckdb::duckdb_register(con, "diskbacked_donor_firms", donor_firms)
  on_exit_cleanup <- function() {
    try(duckdb::duckdb_unregister(con, "diskbacked_admissible_pool"), silent = TRUE)
    try(duckdb::duckdb_unregister(con, "diskbacked_treated_spine"), silent = TRUE)
    try(duckdb::duckdb_unregister(con, "diskbacked_donor_firms"), silent = TRUE)
  }

  # `candidate`: treated x admissible-firm x donor, carrying BOTH sides'
  # covariate values (needed for per-pair gaps in Pass 2) -- built once as a
  # SQL view definition, reused unmodified by both passes.
  var_select <- paste(sprintf("t.%s AS %s_t, df.%s AS %s_c", vars, vars, vars, vars), collapse = ", ")
  candidate_sql <- sprintf("
    SELECT t.cohort, t.deal_id, t.treated_codinv, df.control_codinv, df.control_group,
           t.recency_bin AS recency_bin_t, df.recency_bin AS recency_bin_c, %s
    FROM diskbacked_treated_spine t
    JOIN diskbacked_admissible_pool a ON a.cohort=t.cohort AND a.deal_id=t.deal_id
    JOIN diskbacked_donor_firms df ON df.cohort=a.cohort AND df.control_group=a.control_group", var_select)
  matched_sql <- sprintf("
    SELECT c.*, s.cosine
    FROM (%s) c
    JOIN read_parquet(%s) s
      ON s.cohort=c.cohort AND s.treated_codinv=c.treated_codinv AND s.control_codinv=c.control_codinv
    WHERE s.shared_ipc4 = TRUE AND s.cosine IS NOT NULL
      AND c.recency_bin_t IS NOT NULL AND c.recency_bin_c IS NOT NULL
      AND ABS(c.recency_bin_t - c.recency_bin_c) <= %d", candidate_sql, glob, recency_gap)

  # ---- PASS 1a: scalar-covariate SDs over the FULL profile treated+donor
  # population (NOT the filtered candidate pairs -- matches 16c's
  # treated_scale_units/control_scale_units, computed from the raw inputs).
  # CRITICAL (review correction): NO `SELECT DISTINCT` on the covariate
  # columns. 16c computes the SD over `unique(treated[c("cohort","deal_id",
  # "codinv",vars)])` and `unique(controls[c("cohort","codinv","focal_group",
  # vars)])` -- i.e. one row PER UNIT (per treated inventor; per (control
  # inventor, firm) pairing), PRESERVING duplicate covariate VALUES across
  # distinct units. diskbacked_treated_spine is already exactly one row per
  # treated inventor, and diskbacked_donor_firms exactly one row per (control
  # _codinv, control_group), so no DISTINCT is needed for uniqueness -- and a
  # DISTINCT on the covariate columns alone would WRONGLY collapse two
  # distinct units that happen to share an identical 5-covariate vector into
  # one, changing the SD (hence the standardized distances, the caliper
  # decisions, support, and weights). Real data with 1,000+ treated
  # inventors and discrete-ish covariates (career_age, recency-derived) makes
  # such collisions likely; the earlier fixture missed this because its
  # treated set had no colliding vectors. Aggregate directly over the
  # already-unit-unique registered tables.
  var_cols <- paste(vars, collapse = ", ")
  scaler_sql <- sprintf("
    WITH combined AS (
      SELECT %s FROM diskbacked_treated_spine
      UNION ALL
      SELECT %s FROM diskbacked_donor_firms)
    SELECT %s FROM combined",
    var_cols, var_cols,
    paste(sprintf("STDDEV_SAMP(%s) AS sd_%s", vars, vars), collapse = ", "))
  scaler_row <- tryCatch(DBI::dbGetQuery(con, scaler_sql), error = function(e) e)
  if (inherits(scaler_row, "condition")) { on_exit_cleanup(); stop("build_stage2_edges_for_profile_diskbacked (Pass 1a): ", conditionMessage(scaler_row)) }

  # ---- PASS 1b: technology-distance SD over the shared-IPC4/recency-
  # admissible candidate set (matches 16c's `lmv2_safe_sd(eg$tech_distance)`).
  tech_sd_row <- tryCatch(
    DBI::dbGetQuery(con, sprintf("SELECT STDDEV_SAMP(1-cosine) AS tech_sd FROM (%s)", matched_sql)),
    error = function(e) e)
  if (inherits(tech_sd_row, "condition")) { on_exit_cleanup(); stop("build_stage2_edges_for_profile_diskbacked (Pass 1b): ", conditionMessage(tech_sd_row)) }

  safe_scale_sql <- function(sd) if (is.na(sd) || !is.finite(sd) || sd < eps) "NULL" else sprintf("%.15g", sd)
  sd_vals <- vapply(vars, function(v) safe_scale_sql(scaler_row[[paste0("sd_", v)]][1]), character(1))
  tech_sd_sql <- safe_scale_sql(tech_sd_row$tech_sd[1])

  # ---- PASS 2: standardized distance + Stage-2 caliper, entirely in SQL --
  # only the caliper-admissible edges are ever pulled into R. `scale IS NULL`
  # (degenerate dimension, matches lmv2_scale_gap()'s zero-scale contract)
  # contributes 0 to the sum of squares for that dimension.
  gap_terms <- vapply(seq_along(vars), function(i) {
    v <- vars[i]
    if (sd_vals[i] == "NULL") "0" else sprintf("POWER((%s_c-%s_t)/%s, 2)", v, v, sd_vals[i])
  }, character(1))
  tech_term <- if (tech_sd_sql == "NULL") "0" else sprintf("POWER((1-cosine)/%s, 2)", tech_sd_sql)
  distance_expr <- sprintf("SQRT(%s)", paste(c(gap_terms, tech_term), collapse = " + "))
  final_sql <- sprintf("
    SELECT cohort, deal_id, treated_codinv, control_codinv, control_group, distance FROM (
      SELECT cohort, deal_id, treated_codinv, control_codinv, control_group, %s AS distance
      FROM (%s)
    ) WHERE distance IS NOT NULL AND distance <= %.15g", distance_expr, matched_sql, caliper)

  edges <- tryCatch(DBI::dbGetQuery(con, final_sql), error = function(e) e)
  on_exit_cleanup()
  if (inherits(edges, "condition")) stop("build_stage2_edges_for_profile_diskbacked (Pass 2): ", conditionMessage(edges))
  if (!nrow(edges)) return(empty)
  edges
}

# ---- Restartable-by-profile diagnostic rows (disk-backed cohorts only):
# each (caliper, profile, universe, scheme) row is written atomically to its
# own shard and recorded in a manifest keyed on the exact profile identity
# plus the composite execution hash. A restart validates the manifest+
# checksum and skips recomputation for any already-complete row.
lmv2_profile_row_provenance_matches <- function(cache_dir, g, caliper, profile, universe, scheme, execution_hash) {
  manifest_path <- lmv2_diskcache_profile_row_manifest_path(cache_dir, g)
  match_cols <- c("caliper", "profile", "universe", "scheme", "execution_hash")
  match_vals <- c(format(caliper, trim = TRUE), profile, universe, scheme, execution_hash)
  lmv2_manifest_has_valid_row(manifest_path, match_cols, match_vals, path_col = "path")
}
lmv2_write_profile_row_atomic <- function(cache_dir, g, caliper, profile, universe, scheme, row, execution_hash) {
  path <- lmv2_diskcache_profile_row_path(cache_dir, g, caliper, profile, universe, scheme)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ts <- gsub("[: ]", "-", format(Sys.time(), "%Y%m%d%H%M%OS3"))
  tmp_path <- paste0(path, sprintf(".tmp_%d_%s", Sys.getpid(), ts))
  utils::write.csv(row, tmp_path, row.names = FALSE)
  checksum <- lmv2_p3_file_hash(tmp_path)
  ok <- file.rename(tmp_path, path)
  if (!ok) { file.remove(tmp_path); stop("lmv2_write_profile_row_atomic: rename failed for ", path) }
  lmv2_append_manifest_row(lmv2_diskcache_profile_row_manifest_path(cache_dir, g), data.frame(
    caliper = format(caliper, trim = TRUE), profile = profile, universe = universe, scheme = scheme,
    execution_hash = execution_hash, path = path, checksum = checksum, status = "complete",
    timestamp = as.character(Sys.time()), stringsAsFactors = FALSE))
  invisible(path)
}
lmv2_read_profile_row <- function(cache_dir, g, caliper, profile, universe, scheme) {
  path <- lmv2_diskcache_profile_row_path(cache_dir, g, caliper, profile, universe, scheme)
  utils::read.csv(path, stringsAsFactors = FALSE)
}
# ---- Assemble a cohort's full diagnostics CSV from validated row shards
# only (never from anything held in R across the whole cohort run) -- always
# reconstructible after any restart.
lmv2_assemble_cohort_diagnostics_from_shards <- function(cache_dir, g, out_path) {
  manifest_path <- lmv2_diskcache_profile_row_manifest_path(cache_dir, g)
  if (!file.exists(manifest_path)) stop("lmv2_assemble_cohort_diagnostics_from_shards: no manifest at ", manifest_path)
  m <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  m <- m[m$status == "complete", ]
  rows <- lapply(unique(m$path), function(p) utils::read.csv(p, stringsAsFactors = FALSE))
  out <- do.call(rbind, rows)
  utils::write.csv(out, out_path, row.names = FALSE)
  invisible(out_path)
}
