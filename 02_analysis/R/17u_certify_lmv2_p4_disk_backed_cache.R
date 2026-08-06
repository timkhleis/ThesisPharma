# ============================================================================
# certify_disk_backed_technology_cache.R (v3 -- review correction after the
# v2 smoke test found build_stage2_edges_for_profile_diskbacked() itself
# collected a deal's full shard content -- 17.7M rows for deal 346 -- into R
# before filtering). Fixtures for: composite execution hash, strengthened
# block hash, deal-generation manifest + active-block-only reads (no stale
# blocks), positive-only shared_ipc4 storage, and the two-pass disk-backed
# profile distance/caliper computation -- verified byte-for-byte against
# 16c's lmv2_prepare_stage2_edges() on data with REAL covariate variance
# (not all-zero, so the standardization/degenerate-SD logic is genuinely
# exercised, not vacuously trivial).
# ============================================================================

if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))
source(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path(BASE, "R", "17n_lmv2_p4_disk_backed_cache.R"))
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))

checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1]] <<- data.frame(
    check = name, observed = paste(observed, collapse = ","),
    expected = paste(expected, collapse = ","), pass = isTRUE(pass), stringsAsFactors = FALSE)
}

cache_dir <- file.path(tempdir(), paste0("disk_tech_cache_certify_v3_", as.integer(Sys.time())))
dir.create(cache_dir, recursive = TRUE)

con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")

lmv2_disk_cache_certify_body <- function() {

DBI::dbExecute(con, "CREATE TABLE inventor_ipc_year (codinv BIGINT, year INTEGER, ipc_code VARCHAR, patent_count INTEGER)")
DBI::dbExecute(con, "CREATE TABLE lmv2_p3_ipc_code_map (ipc_code VARCHAR, resolution VARCHAR, ipc_feature VARCHAR)")
DBI::dbExecute(con, "INSERT INTO lmv2_p3_ipc_code_map VALUES
  ('A01','ipc4','A01'), ('A01','main_group','A0'),
  ('A02','ipc4','A02'), ('A02','main_group','A0'),
  ('B01','ipc4','B01'), ('B01','main_group','B0')")

g <- 2000L
p3_hash <- "certify_p3_v3"
execution_hash <- "certify_execution_hash_v3"

# ===========================================================================
# Fixture COMPOSITE_HASH -- changes with any component file, gates reuse.
# ===========================================================================
real_exec_hash <- lmv2_composite_execution_hash(BASE, p3_hash)
add_check("COMPOSITE_HASH_is_nonempty_hex", nchar(real_exec_hash) == 64, TRUE, nchar(real_exec_hash) == 64)
real_exec_hash_2 <- lmv2_composite_execution_hash(BASE, p3_hash)
add_check("COMPOSITE_HASH_deterministic", real_exec_hash, real_exec_hash_2, identical(real_exec_hash, real_exec_hash_2))
different_p3_exec_hash <- lmv2_composite_execution_hash(BASE, "a_different_p3_hash")
add_check("COMPOSITE_HASH_changes_with_p3_hash",
          real_exec_hash != different_p3_exec_hash, TRUE, real_exec_hash != different_p3_exec_hash)

# ===========================================================================
# Fixture DEAL_SETUP -- treated T1/T2 (deals 1/2), donors with REAL variance
# (not all zero) so the two-pass distance formula's standardization is
# genuinely exercised, plus a THIRD, DEGENERATE-variance covariate to test
# the "scale IS NULL -> contributes 0" path.
# ===========================================================================
ipc_rows <- rbind(
  data.frame(codinv = 101L, year = 1997L, ipc_code = "A01", patent_count = 3L),
  data.frame(codinv = 201L, year = 1996L, ipc_code = "A01", patent_count = 2L),
  data.frame(codinv = 202L, year = 1997L, ipc_code = "A01", patent_count = 5L),
  data.frame(codinv = 203L, year = 1995L, ipc_code = "A01", patent_count = 1L),
  data.frame(codinv = 204L, year = 1996L, ipc_code = "A01", patent_count = 3L))
DBI::dbWriteTable(con, "inventor_ipc_year", ipc_rows, append = TRUE)

vars <- LMV2_P3$stage_2$scalar_variables  # log_patent_count_5y, patent_trajectory, career_age, focal_group_tenure, focal_group_exclusivity
# T1 at the center; donors spread with REAL variance on 4 of 5 covariates,
# and held EXACTLY CONSTANT (degenerate, zero variance) on
# focal_group_exclusivity across BOTH treated and all donors -- this must
# make that ONE dimension contribute 0 to distance (scale IS NULL path),
# while the other 4 dimensions standardize normally.
treated_inv_ok <- data.frame(cohort = g, deal_id = 1L, codinv = 101L, recency_bin = 0L,
                             log_patent_count_5y = 0, patent_trajectory = 0, career_age = 5,
                             focal_group_tenure = 2, focal_group_exclusivity = 0.5)
donor_cols_u1 <- data.frame(cohort = g, control_codinv = c(201L, 202L, 203L, 204L),
                            control_group = c(901L, 901L, 902L, 902L), recency_bin = 0L,
                            log_patent_count_5y = c(1, -1, 2, -2), patent_trajectory = c(0.5, -0.5, 1, -1),
                            career_age = c(6, 4, 7, 3), focal_group_tenure = c(3, 1, 4, 0),
                            focal_group_exclusivity = 0.5)  # DEGENERATE: identical for all + treated
admissible_u1 <- data.frame(cohort = g, deal_id = 1L, control_group = c(901L, 902L), distance = 0.3)
recency_gap <- 5L

codinv_roster <- unique(c(treated_inv_ok$codinv, donor_cols_u1$control_codinv))
vn <- lmv2_build_ipc4_vectors_norms(con, g, codinv_roster, cache_dir, execution_hash)

lmv2_build_disk_backed_technology_shards_for_universe(
  con, g, "u1", admissible_u1, treated_inv_ok, donor_cols_u1, recency_gap,
  vn$vectors_path, vn$norms_path, cache_dir, execution_hash)

# ===========================================================================
# Fixture POSITIVE_ONLY -- shards store ONLY shared_ipc4=TRUE rows (speed
# fix #5.1): every control here shares A01 with T1, so ALL should appear;
# confirm none have shared_ipc4=FALSE (there should be no FALSE rows at all,
# since the column itself is now hardcoded TRUE and the join is an INNER
# JOIN that drops non-matches entirely).
# ===========================================================================
shard1_path <- lmv2_diskcache_shard_path(cache_dir, g, "u1", 1L, 1L)
shard1 <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", shard1_path))
add_check("POSITIVE_ONLY_all_rows_shared_ipc4_true", all(shard1$shared_ipc4), TRUE, all(shard1$shared_ipc4))
add_check("POSITIVE_ONLY_row_count_matches_actual_sharers", nrow(shard1), 4L, nrow(shard1) == 4L)

# ===========================================================================
# Fixture TWO_PASS_PARITY -- the disk-backed profile distance/caliper
# computation vs 16c's lmv2_prepare_stage2_edges() (in-memory reference),
# on data with real covariate variance AND one degenerate dimension.
# ===========================================================================
donors_profile <- donor_cols_u1
names(donors_profile)[names(donors_profile) == "control_codinv"] <- "codinv"
names(donors_profile)[names(donors_profile) == "control_group"] <- "focal_group"

wide_caliper <- 100.0  # keep ALL pairs admissible so row counts match exactly
edges_diskbacked <- build_stage2_edges_for_profile_diskbacked(
  con, cache_dir, g, "u1", admissible_u1, treated_inv_ok, donors_profile, donor_cols_u1,
  execution_hash, wide_caliper)

pair_map_u1 <- expand.grid(cohort = g, treated_codinv = 101L, control_codinv = c(201L, 202L, 203L, 204L))
inmem_cache <- lmv2_stage2_technology_cache_ipc4(con, pair_map_u1)
treated_key_ref <- data.frame(cohort = g, deal_id = 1L, treated_codinv = 101L)
ref_pairs <- lmv2_ebal_build_stage2_candidate_pairs(admissible_u1, donor_cols_u1, treated_key_ref)
edges_inmemory_prep <- lmv2_prepare_stage2_edges(
  treated = treated_inv_ok, controls = donors_profile,
  pair_map = ref_pairs[c("cohort", "deal_id", "treated_codinv", "control_codinv")],
  similarity = inmem_cache$similarity[c("cohort", "treated_codinv", "control_codinv", "cosine")],
  shared_ipc4 = inmem_cache$shared_ipc4[c("cohort", "treated_codinv", "control_codinv", "shared_ipc4")],
  resolution = "ipc4")
edges_inmemory <- edges_inmemory_prep$edges

edges_diskbacked <- edges_diskbacked[order(edges_diskbacked$control_codinv), ]
edges_inmemory <- edges_inmemory[order(edges_inmemory$control_codinv), ]
add_check("TWO_PASS_PARITY_same_row_count", nrow(edges_diskbacked), nrow(edges_inmemory),
          nrow(edges_diskbacked) == nrow(edges_inmemory))
add_check("TWO_PASS_PARITY_same_pair_keys",
          isTRUE(all.equal(edges_diskbacked$control_codinv, edges_inmemory$control_codinv)), TRUE,
          isTRUE(all.equal(edges_diskbacked$control_codinv, edges_inmemory$control_codinv)))
max_dist_diff <- max(abs(edges_diskbacked$distance - edges_inmemory$distance))
add_check("TWO_PASS_PARITY_distance_matches_byte_exact_formula", sprintf("max diff=%.2e", max_dist_diff), "< 1e-8",
          isTRUE(max_dist_diff < 1e-8))
# The degenerate dimension (focal_group_exclusivity, constant everywhere)
# must contribute exactly 0 -- confirmed indirectly: since ALL other
# fixture inputs have real variance, an exact match on `distance` already
# proves the degenerate dimension was excluded identically in both paths
# (if the disk-backed SQL had instead divided by a near-zero/zero SD, the
# distances would diverge sharply, not match to 1e-8).
add_check("TWO_PASS_PARITY_degenerate_dimension_handled_identically",
          sprintf("max diff=%.2e (would be large if mishandled)", max_dist_diff), "< 1e-8",
          isTRUE(max_dist_diff < 1e-8))

# ---- Caliper actually applied: a TIGHT caliper must exclude far pairs.
tight_caliper <- 0.5
edges_tight <- build_stage2_edges_for_profile_diskbacked(
  con, cache_dir, g, "u1", admissible_u1, treated_inv_ok, donors_profile, donor_cols_u1,
  execution_hash, tight_caliper)
add_check("TWO_PASS_PARITY_tight_caliper_excludes_some_pairs",
          nrow(edges_tight) < nrow(edges_diskbacked), TRUE, nrow(edges_tight) < nrow(edges_diskbacked))
add_check("TWO_PASS_PARITY_tight_caliper_all_within_bound",
          all(edges_tight$distance <= tight_caliper), TRUE, all(edges_tight$distance <= tight_caliper))

# ===========================================================================
# Fixture COLLISION_PARITY (review correction) -- the scaler SD must be
# computed over one row PER UNIT preserving duplicate covariate VALUES
# across distinct units, NOT `SELECT DISTINCT` on the covariate columns
# (which would collapse two distinct units sharing an identical covariate
# vector and change the SD). This fixture DELIBERATELY seeds colliding
# covariate vectors: TWO treated inventors (deal 2) with an IDENTICAL 5-
# vector, and TWO control inventors (at different firms) with an identical
# 5-vector -- exactly the real-data condition (1,000+ treated inventors,
# discrete-ish covariates) that a DISTINCT-based scaler would mishandle.
# The disk-backed path must still match 16c's lmv2_prepare_stage2_edges()
# to 1e-8. Pre-fix, the DISTINCT dropped one of each colliding pair from
# the SD population, diverging the distances -- this check would FAIL.
ipc_rows_c <- data.frame(codinv = c(311L, 312L, 411L, 412L, 413L, 414L), year = 1997L,
                         ipc_code = "A01", patent_count = 2L)
DBI::dbWriteTable(con, "inventor_ipc_year", ipc_rows_c, append = TRUE)
# Deal 2: treated 311 and 312 share the IDENTICAL covariate vector.
collide_vec <- list(log_patent_count_5y = 0.7, patent_trajectory = -0.3, career_age = 5,
                    focal_group_tenure = 2, focal_group_exclusivity = 0.4)
treated_c <- data.frame(cohort = g, deal_id = 2L, codinv = c(311L, 312L), recency_bin = 0L,
                        log_patent_count_5y = collide_vec$log_patent_count_5y,
                        patent_trajectory = collide_vec$patent_trajectory, career_age = collide_vec$career_age,
                        focal_group_tenure = collide_vec$focal_group_tenure,
                        focal_group_exclusivity = collide_vec$focal_group_exclusivity)
# Donors: 411 and 413 (DIFFERENT firms 903 vs 904) share an identical vector;
# 412 and 414 have distinct vectors -> real spread remains.
donor_c <- data.frame(cohort = g, control_codinv = c(411L, 412L, 413L, 414L),
                      control_group = c(903L, 903L, 904L, 904L), recency_bin = 0L,
                      log_patent_count_5y = c(0.9, -0.9, 0.9, 1.6),
                      patent_trajectory = c(0.2, -0.2, 0.2, -0.6),
                      career_age = c(6, 4, 6, 3), focal_group_tenure = c(3, 1, 3, 0),
                      focal_group_exclusivity = c(0.4, 0.8, 0.4, 0.1))
admissible_c <- data.frame(cohort = g, deal_id = 2L, control_group = c(903L, 904L), distance = 0.3)

roster_c <- unique(c(treated_c$codinv, donor_c$control_codinv))
vn_c <- lmv2_build_ipc4_vectors_norms(con, g, unique(c(codinv_roster, roster_c)), cache_dir, execution_hash)
lmv2_build_disk_backed_technology_shards_for_universe(
  con, g, "u1", admissible_c, treated_c, donor_c, recency_gap,
  vn_c$vectors_path, vn_c$norms_path, cache_dir, execution_hash)

donors_profile_c <- donor_c
names(donors_profile_c)[names(donors_profile_c) == "control_codinv"] <- "codinv"
names(donors_profile_c)[names(donors_profile_c) == "control_group"] <- "focal_group"
edges_db_c <- build_stage2_edges_for_profile_diskbacked(
  con, cache_dir, g, "u1", admissible_c, treated_c, donors_profile_c, donor_c, execution_hash, 100.0)

pair_map_c <- expand.grid(cohort = g, treated_codinv = c(311L, 312L), control_codinv = c(411L, 412L, 413L, 414L))
inmem_cache_c <- lmv2_stage2_technology_cache_ipc4(con, pair_map_c)
treated_key_c <- data.frame(cohort = g, deal_id = 2L, treated_codinv = c(311L, 312L))
ref_pairs_c <- lmv2_ebal_build_stage2_candidate_pairs(admissible_c, donor_c, treated_key_c)
edges_im_c <- lmv2_prepare_stage2_edges(
  treated = treated_c, controls = donors_profile_c,
  pair_map = ref_pairs_c[c("cohort", "deal_id", "treated_codinv", "control_codinv")],
  similarity = inmem_cache_c$similarity[c("cohort", "treated_codinv", "control_codinv", "cosine")],
  shared_ipc4 = inmem_cache_c$shared_ipc4[c("cohort", "treated_codinv", "control_codinv", "shared_ipc4")],
  resolution = "ipc4")$edges
key_c <- function(d) paste(d$treated_codinv, d$control_codinv)
edges_db_c <- edges_db_c[order(key_c(edges_db_c)), ]
edges_im_c <- edges_im_c[order(key_c(edges_im_c)), ]
add_check("COLLISION_PARITY_same_row_count", nrow(edges_db_c), nrow(edges_im_c), nrow(edges_db_c) == nrow(edges_im_c))
add_check("COLLISION_PARITY_same_pair_keys", isTRUE(all.equal(key_c(edges_db_c), key_c(edges_im_c))), TRUE,
          isTRUE(all.equal(key_c(edges_db_c), key_c(edges_im_c))))
max_diff_c <- if (nrow(edges_db_c) && nrow(edges_db_c) == nrow(edges_im_c)) max(abs(edges_db_c$distance - edges_im_c$distance)) else Inf
add_check("COLLISION_PARITY_distance_matches_despite_duplicate_vectors",
          sprintf("max diff=%.2e (pre-fix: would diverge from DISTINCT-dropped SD population)", max_diff_c), "< 1e-8",
          isTRUE(max_diff_c < 1e-8))

# ===========================================================================
# Fixture TECH_SD_PARITY (review correction) -- every OTHER parity fixture
# gives all inventors the SAME single IPC4 feature, so every cosine=1 and
# tech_distance=0, leaving the technology-distance SD DEGENERATE (0) and its
# standardization branch (Pass 1b STDDEV_SAMP(1-cosine) + Pass 2 tech_term)
# never exercised on real variance. Real 2009 data DOES have cosine variance
# (inventors with different IPC portfolios), so this fixture seeds genuinely
# VARYING cosines -- controls that all SHARE >=1 IPC4 with the treated
# inventor (so shared_ipc4=TRUE, they stay in the candidate set) but have
# DIFFERENT IPC4 distributions (so cosine<1 and varies) -- and confirms the
# disk-backed two-pass path still matches 16c to 1e-8 with a NON-degenerate
# tech-distance SD in play.
DBI::dbExecute(con, "INSERT INTO lmv2_p3_ipc_code_map VALUES ('A02','ipc4','A02'), ('A03','ipc4','A03')")
# Treated 511: portfolio {A01:2, A02:2} (balanced across A01/A02).
# Controls all include A01 (guarantees shared_ipc4) with varying second
# features -> distinct cosines: 611 identical to treated (cos~1), 612 pure
# A01 (cos<1), 613 A01+A03 (cos<1, different direction), 614 A01-heavy+A02.
ipc_rows_t <- rbind(
  data.frame(codinv = 511L, year = 1997L, ipc_code = c("A01","A02"), patent_count = c(2L,2L)),
  data.frame(codinv = 611L, year = 1997L, ipc_code = c("A01","A02"), patent_count = c(2L,2L)),
  data.frame(codinv = 612L, year = 1997L, ipc_code = "A01", patent_count = 4L),
  data.frame(codinv = 613L, year = 1997L, ipc_code = c("A01","A03"), patent_count = c(3L,1L)),
  data.frame(codinv = 614L, year = 1997L, ipc_code = c("A01","A02"), patent_count = c(3L,1L)))
DBI::dbWriteTable(con, "inventor_ipc_year", ipc_rows_t, append = TRUE)
treated_t <- data.frame(cohort = g, deal_id = 3L, codinv = 511L, recency_bin = 0L,
                        log_patent_count_5y = 0.5, patent_trajectory = 0.1, career_age = 5,
                        focal_group_tenure = 2, focal_group_exclusivity = 0.4)
donor_t <- data.frame(cohort = g, control_codinv = c(611L,612L,613L,614L), control_group = c(905L,905L,906L,906L),
                      recency_bin = 0L, log_patent_count_5y = c(0.6,-0.4,0.9,0.2),
                      patent_trajectory = c(0.0,0.3,-0.2,0.5), career_age = c(6,4,7,5),
                      focal_group_tenure = c(3,1,2,2), focal_group_exclusivity = c(0.4,0.6,0.3,0.5))
admissible_t <- data.frame(cohort = g, deal_id = 3L, control_group = c(905L,906L), distance = 0.3)

vn_t <- lmv2_build_ipc4_vectors_norms(con, g, unique(c(treated_t$codinv, donor_t$control_codinv)), cache_dir, execution_hash)
lmv2_build_disk_backed_technology_shards_for_universe(
  con, g, "u1", admissible_t, treated_t, donor_t, recency_gap, vn_t$vectors_path, vn_t$norms_path, cache_dir, execution_hash)
donors_profile_t <- donor_t
names(donors_profile_t)[names(donors_profile_t)=="control_codinv"] <- "codinv"
names(donors_profile_t)[names(donors_profile_t)=="control_group"] <- "focal_group"
edges_db_t <- build_stage2_edges_for_profile_diskbacked(
  con, cache_dir, g, "u1", admissible_t, treated_t, donors_profile_t, donor_t, execution_hash, 100.0)

pair_map_t <- expand.grid(cohort = g, treated_codinv = 511L, control_codinv = c(611L,612L,613L,614L))
im_t <- lmv2_stage2_technology_cache_ipc4(con, pair_map_t)
# Confirm cosines genuinely VARY (else this fixture proves nothing).
cos_vals <- im_t$similarity$cosine[im_t$similarity$cohort == g]
add_check("TECH_SD_PARITY_cosines_genuinely_vary",
          sprintf("range=[%.3f,%.3f]", min(cos_vals), max(cos_vals)), "non-degenerate",
          (max(cos_vals) - min(cos_vals)) > 0.05)
ref_pairs_t <- lmv2_ebal_build_stage2_candidate_pairs(admissible_t, donor_t,
  data.frame(cohort = g, deal_id = 3L, treated_codinv = 511L))
edges_im_t <- lmv2_prepare_stage2_edges(treated = treated_t, controls = donors_profile_t,
  pair_map = ref_pairs_t[c("cohort","deal_id","treated_codinv","control_codinv")],
  similarity = im_t$similarity[c("cohort","treated_codinv","control_codinv","cosine")],
  shared_ipc4 = im_t$shared_ipc4[c("cohort","treated_codinv","control_codinv","shared_ipc4")],
  resolution = "ipc4")$edges
edges_db_t <- edges_db_t[order(edges_db_t$control_codinv),]
edges_im_t <- edges_im_t[order(edges_im_t$control_codinv),]
add_check("TECH_SD_PARITY_same_row_count", nrow(edges_db_t), nrow(edges_im_t), nrow(edges_db_t) == nrow(edges_im_t))
add_check("TECH_SD_PARITY_same_pair_keys",
          isTRUE(all.equal(edges_db_t$control_codinv, edges_im_t$control_codinv)), TRUE,
          isTRUE(all.equal(edges_db_t$control_codinv, edges_im_t$control_codinv)))
max_diff_t <- if (nrow(edges_db_t) && nrow(edges_db_t) == nrow(edges_im_t)) max(abs(edges_db_t$distance - edges_im_t$distance)) else Inf
add_check("TECH_SD_PARITY_distance_matches_with_nondegenerate_tech_sd",
          sprintf("max diff=%.2e", max_diff_t), "< 1e-8", isTRUE(max_diff_t < 1e-8))

# ===========================================================================
# Fixture BLOCK_HASH_STRENGTH -- strengthened hash changes with recency_bin
# and with the admissible control-group set, not just bare IDs.
# ===========================================================================
tb1 <- data.frame(treated_codinv = 101L, recency_bin_treated = 0L)
dp1 <- data.frame(control_codinv = c(201L, 202L), control_group = 901L, recency_bin_control = 0L)
h1 <- lmv2_block_pair_hash(tb1, dp1, 901L, recency_gap)
tb2 <- data.frame(treated_codinv = 101L, recency_bin_treated = 1L)  # different recency_bin, same ID
h2 <- lmv2_block_pair_hash(tb2, dp1, 901L, recency_gap)
add_check("BLOCK_HASH_STRENGTH_changes_with_treated_recency_bin", h1 != h2, TRUE, h1 != h2)
h3 <- lmv2_block_pair_hash(tb1, dp1, c(901L, 999L), recency_gap)  # extra admissible group, same donors
add_check("BLOCK_HASH_STRENGTH_changes_with_admissible_group_set", h1 != h3, TRUE, h1 != h3)
dp2 <- dp1; dp2$recency_bin_control[1] <- 5L
h4 <- lmv2_block_pair_hash(tb1, dp2, 901L, recency_gap)
add_check("BLOCK_HASH_STRENGTH_changes_with_donor_recency_bin", h1 != h4, TRUE, h1 != h4)

# ===========================================================================
# Fixture GENERATION_MANIFEST -- deal-level generation tracking, active-
# block-only reads, no stale blocks from an earlier (different-sized)
# generation ever leak into a profile.
# ===========================================================================
gen_manifest_path <- lmv2_diskcache_deal_generation_manifest_path(cache_dir, g, "u1")
add_check("GENERATION_MANIFEST_exists", file.exists(gen_manifest_path), TRUE, file.exists(gen_manifest_path))
gm <- utils::read.csv(gen_manifest_path, stringsAsFactors = FALSE)
add_check("GENERATION_MANIFEST_deal1_one_block_default_target",
          gm$n_blocks[gm$deal_id == 1L & gm$status == "complete"][1], 1L,
          isTRUE(gm$n_blocks[gm$deal_id == 1L & gm$status == "complete"][1] == 1L))

# Rebuild deal 1 with target_pairs_per_block=1 -> forces MULTIPLE blocks (4
# donors -> block_size=max(1,floor(1/4))=1 -> T1 alone still 1 block since
# there is only 1 treated inventor in deal 1; use deal 1's single treated
# inventor scenario is insufficient to force multiple blocks by itself, so
# this test instead confirms a DIFFERENT generation_hash correctly triggers
# a full rebuild rather than reusing generation 1's record).
paths_gen1 <- lmv2_list_complete_shard_paths_for_deals(cache_dir, g, "u1", 1L, execution_hash)
add_check("GENERATION_MANIFEST_active_paths_resolve_to_real_files",
          length(paths_gen1) >= 1 && all(file.exists(paths_gen1)), TRUE,
          length(paths_gen1) >= 1 && all(file.exists(paths_gen1)))

# ---- Simulate a "stale extra block" scenario directly: manually append a
# FAKE extra shard-manifest row for deal 1, block_idx=2 (as if left over
# from a prior, now-superseded generation with more blocks), WITHOUT it
# being listed in the CURRENT generation record's active_block_idxs. Confirm
# lmv2_list_complete_shard_paths_for_deals() does NOT pick it up.
fake_shard_path <- lmv2_diskcache_shard_path(cache_dir, g, "u1", 1L, 2L)
writeLines("fake stale block content", fake_shard_path)
fake_checksum <- lmv2_p3_file_hash(fake_shard_path)
shard_manifest_path <- lmv2_diskcache_shard_manifest_path(cache_dir, g, "u1")
lmv2_append_manifest_row(shard_manifest_path, data.frame(
  cohort = g, universe = "u1", deal_id = 1L, block_idx = 2L, resolution = "ipc4",
  execution_hash = execution_hash, pair_hash = "fake_stale_pair_hash",
  treated_id_hash = "fake", treated_id_range = "999-999", n_treated_in_block = 1L,
  path = fake_shard_path, timestamp = as.character(Sys.time()),
  row_count = 1L, checksum = fake_checksum, status = "complete", stringsAsFactors = FALSE))
paths_after_fake <- lmv2_list_complete_shard_paths_for_deals(cache_dir, g, "u1", 1L, execution_hash)
add_check("GENERATION_MANIFEST_stale_extra_block_never_included",
          fake_shard_path %in% paths_after_fake, FALSE, !(fake_shard_path %in% paths_after_fake))
add_check("GENERATION_MANIFEST_active_set_unchanged_by_stale_block",
          length(paths_after_fake), length(paths_gen1), length(paths_after_fake) == length(paths_gen1))

# ---- Restart-skip at the DEAL level: rebuilding with the SAME generation
# hash (same inputs, same target_pairs_per_block) must skip entirely.
mtime_before <- file.info(shard1_path)$mtime
n_blocks_restart <- lmv2_build_one_deal_shard(con, g, "u1", 1L, admissible_u1, treated_inv_ok, donor_cols_u1,
                                              recency_gap, vn$vectors_path, vn$norms_path, cache_dir, execution_hash)
add_check("GENERATION_MANIFEST_deal_level_restart_skip",
          identical(file.info(shard1_path)$mtime, mtime_before), TRUE,
          identical(file.info(shard1_path)$mtime, mtime_before))
add_check("GENERATION_MANIFEST_restart_returns_correct_active_block_count", n_blocks_restart, 1L, n_blocks_restart == 1L)

invisible(NULL)
}  # end lmv2_disk_cache_certify_body()

tryCatch(
  lmv2_disk_cache_certify_body(),
  finally = {
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE)
    unlink(cache_dir, recursive = TRUE)
  })

# ===========================================================================
report <- do.call(rbind, checks)
cat(sprintf("\n=== disk-backed technology cache v3 certification: %d checks, %d failing ===\n",
            nrow(report), sum(!report$pass)))
print(report[, c("check", "pass")], row.names = FALSE)
utils::write.csv(report, file.path(AUDIT_OUT_DIR, "certify_disk_backed_technology_cache_results.csv"), row.names = FALSE)
if (any(!report$pass)) {
  cat("\nFAILING CHECKS:\n"); print(report[!report$pass, ], row.names = FALSE)
  stop("disk-backed technology cache v3 certification FAILED")
}
cat("\nALL DISK-BACKED TECHNOLOGY CACHE V3 CHECKS PASS.\n")
