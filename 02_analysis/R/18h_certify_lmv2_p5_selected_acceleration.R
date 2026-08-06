# Database-free/source-database-independent certification for selected P5.

if (!exists("build_stage2_edge_cover_for_profile_diskbacked",
            mode = "function")) {
  BASE <- normalizePath("02_analysis", mustWork = TRUE)
  source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
  source(file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
  lmv2_install_p5_sparse_cache()
  source(file.path(BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
}

checks <- 0L
check <- function(ok, message) {
  if (!isTRUE(ok)) {
    stop("Selected-P5 certification failed: ", message)
  }
  checks <<- checks + 1L
}

fixture_dir <- tempfile("lmv2_p5_selected_")
dir.create(fixture_dir, recursive = TRUE)
con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
DBI::dbExecute(con, "PRAGMA threads=2")
DBI::dbExecute(
  con,
  "CREATE TABLE inventor_ipc_year
   (codinv BIGINT, year INTEGER, ipc_code VARCHAR, patent_count INTEGER)")
DBI::dbExecute(
  con,
  "CREATE TABLE lmv2_p3_ipc_code_map
   (ipc_code VARCHAR, resolution VARCHAR, ipc_feature VARCHAR)")
DBI::dbExecute(
  con,
  "INSERT INTO lmv2_p3_ipc_code_map VALUES ('A01','ipc4','A01')")

g <- 2000L
treated_ids <- 101:103
firm_groups <- 901:905
control_ids <- unlist(lapply(
  firm_groups, function(f) f * 100 + seq_len(6)))
ipc <- data.frame(
  codinv = c(treated_ids, control_ids),
  year = 1999L, ipc_code = "A01", patent_count = 1L)
DBI::dbWriteTable(con, "inventor_ipc_year", ipc, append = TRUE)

vars <- LMV2_P3$stage_2$scalar_variables
treated <- data.frame(
  cohort = g, deal_id = 1L, codinv = treated_ids, recency_bin = 0L)
donor_cols <- do.call(rbind, lapply(firm_groups, function(f) {
  data.frame(
    cohort = g, control_codinv = f * 100 + seq_len(6),
    control_group = f, recency_bin = 0L)
}))
for (v in vars) {
  treated[[v]] <- 0
  donor_cols[[v]] <- 0
}
donors <- donor_cols
names(donors)[names(donors) == "control_codinv"] <- "codinv"
names(donors)[names(donors) == "control_group"] <- "focal_group"
admissible <- data.frame(
  cohort = g, deal_id = 1L, control_group = firm_groups,
  distance = 0.3)

execution_hash <- paste(rep("b", 64), collapse = "")
roster <- c(treated_ids, control_ids)
vn <- lmv2_build_ipc4_vectors_norms(
  con, g, roster, fixture_dir, execution_hash)
lmv2_build_disk_backed_technology_shards_for_universe(
  con, g, "u1", admissible, treated, donor_cols, 5L,
  vn$vectors_path, vn$norms_path, fixture_dir, execution_hash)

full <- build_stage2_edges_for_profile_diskbacked(
  con, fixture_dir, g, "u1", admissible, treated, donors,
  donor_cols, execution_hash, 1.5)
cover <- build_stage2_edge_cover_for_profile_diskbacked(
  con, fixture_dir, g, "u1", admissible, treated, donors,
  donor_cols, execution_hash, 1.5)

treated_projection <- function(x) {
  out <- unique(x[c("cohort", "deal_id", "treated_codinv")])
  out[do.call(order, out), ]
}
control_projection <- function(x) {
  out <- unique(
    x[c("cohort", "deal_id", "control_codinv", "control_group")])
  out[do.call(order, out), ]
}
check(nrow(full) == length(treated_ids) * length(control_ids),
      "full fixture did not contain the intended complete pair cross")
check(nrow(cover) < nrow(full),
      "edge cover did not reduce the pair table")
check(isTRUE(all.equal(
  treated_projection(full), treated_projection(cover),
  check.attributes = FALSE)),
  "treated support projection changed")
check(isTRUE(all.equal(
  control_projection(full), control_projection(cover),
  check.attributes = FALSE)),
  "control support projection changed")
check(all(cover$distance <= 1.5),
      "cover contains an edge outside the Stage-2 caliper")

# Rescue-only support minima are applied to the full admissible edge set
# before compression. Requiring more controls than exist removes every
# treated inventor; the default path above remains projection-identical.
strict_dir <- file.path(fixture_dir, "strict_support")
strict_hash <- paste(rep("c", 64), collapse = "")
strict_vn <- lmv2_build_ipc4_vectors_norms(
  con, g, roster, strict_dir, strict_hash)
lmv2_build_disk_backed_technology_shards_for_universe(
  con, g, "u1", admissible, treated, donor_cols, 5L,
  strict_vn$vectors_path, strict_vn$norms_path,
  strict_dir, strict_hash)
assign(
  "LMV2_P5_MIN_CONTROLS_PER_TREATED", 31L,
  envir = .GlobalEnv)
assign(
  "LMV2_P5_MIN_FIRMS_PER_TREATED", 1L,
  envir = .GlobalEnv)
strict_cover <- build_stage2_edge_cover_for_profile_diskbacked(
  con, strict_dir, g, "u1", admissible, treated, donors,
  donor_cols, strict_hash, 1.5)
check(
  nrow(strict_cover) == 0L,
  "rescue minimum-control support filter was not applied before cover")
rm(
  "LMV2_P5_MIN_CONTROLS_PER_TREATED",
  "LMV2_P5_MIN_FIRMS_PER_TREATED",
  envir = .GlobalEnv)

# Adaptive k-nearest mode keeps exactly five local controls for every
# supported treated inventor and forces those controls to span two firms.
knn_dir <- file.path(fixture_dir, "adaptive_knn")
knn_hash <- paste(rep("d", 64), collapse = "")
knn_vn <- lmv2_build_ipc4_vectors_norms(
  con, g, roster, knn_dir, knn_hash)
lmv2_build_disk_backed_technology_shards_for_universe(
  con, g, "u1", admissible, treated, donor_cols, 5L,
  knn_vn$vectors_path, knn_vn$norms_path,
  knn_dir, knn_hash)
assign("LMV2_P5_KNN_MODE", TRUE, envir = .GlobalEnv)
assign("LMV2_P5_KNN_K", 5L, envir = .GlobalEnv)
assign(
  "LMV2_P5_KNN_SANITY_QUANTILE", 0.99,
  envir = .GlobalEnv)
assign(
  "LMV2_P5_MIN_CONTROLS_PER_TREATED", 3L,
  envir = .GlobalEnv)
assign(
  "LMV2_P5_MIN_FIRMS_PER_TREATED", 2L,
  envir = .GlobalEnv)
knn_cover <- build_stage2_edge_cover_for_profile_diskbacked(
  con, knn_dir, g, "u1", admissible, treated, donors,
  donor_cols, knn_hash, Inf)
check(
  all(table(knn_cover$treated_codinv) == 5L),
  "adaptive k-nearest did not keep exactly five controls per treated")
check(
  all(tapply(
    knn_cover$control_group, knn_cover$treated_codinv,
    function(z) length(unique(z))) >= 2L),
  "adaptive k-nearest did not force a second-firm anchor")
rm(
  "LMV2_P5_KNN_MODE", "LMV2_P5_KNN_K",
  "LMV2_P5_KNN_SANITY_QUANTILE",
  "LMV2_P5_MIN_CONTROLS_PER_TREATED",
  "LMV2_P5_MIN_FIRMS_PER_TREATED",
  envir = .GlobalEnv)

cover_file <- lmv2_p5_cover_path(
  fixture_dir, g, "u1",
  lmv2_p5_profile_hash(
    g, "u1", 1.5,
    unique(admissible[c("cohort", "deal_id", "control_group")]),
    {
      z <- treated[c("cohort", "deal_id", "codinv", "recency_bin", vars)]
      names(z)[names(z) == "codinv"] <- "treated_codinv"
      z
    },
    unique(donor_cols[
      c("cohort", "control_codinv", "control_group", "recency_bin", vars)]),
    execution_hash))
mtime_before <- file.info(cover_file)$mtime
cover_again <- build_stage2_edge_cover_for_profile_diskbacked(
  con, fixture_dir, g, "u1", admissible, treated, donors,
  donor_cols, execution_hash, 1.5)
check(identical(mtime_before, file.info(cover_file)$mtime),
      "second weighting scheme rewrote the cached cover")
check(isTRUE(all.equal(
  cover, cover_again, check.attributes = FALSE)),
  "cached cover differs from the committed first result")

firm_dev <- c(-2, -1, 0, 1, 2)
firm_covars <- data.frame(
  cohort = g, control_group = firm_groups,
  log_patent_stock_5y = 2 + 0.3 * firm_dev,
  log_inventor_count_5y = 2 - 0.3 * firm_dev,
  patent_trajectory = 0.1 + 0.05 * firm_dev)
treated_target <- data.frame(
  cohort = g, deal_id = 1L, target_group = 999,
  log_patent_stock_5y = 2, log_inventor_count_5y = 2,
  patent_trajectory = 0.1)
retention <- list(
  n_treated = length(treated_ids), n_deals = 1L,
  n_treated_covariate_complete = length(treated_ids))

run_with <- function(edges, scheme) {
  run_one_cohort_profile(
    con = NULL, g = g, caliper = 1.0, profile = "all_eligible",
    universe = "u1", scheme = scheme, raw_edges = admissible,
    treated_inv_ok = treated, donors_loosest = donors,
    donor_cols_loosest = donor_cols, cached_tech = NULL,
    authoritative_firm_covars = firm_covars,
    authoritative_treated_target = treated_target,
    frozen10_deal_ids = integer(0),
    retention_full_spine = retention,
    stage2_edge_builder = function(...) edges)
}
for (scheme in c("primary", "equal_deal")) {
  row_full <- run_with(full, scheme)
  row_cover <- run_with(cover, scheme)
  compare_cols <- setdiff(
    names(row_full), c("n_solver_warnings"))
  check(isTRUE(all.equal(
    row_full[compare_cols], row_cover[compare_cols],
    tolerance = 1e-12, check.attributes = FALSE)),
    paste("final diagnostics/weights changed for", scheme))
}

old_block <- lmv2_treated_block_size(23364L, 1000000L)
new_block <- lmv2_treated_block_size(
  23364L, LMV2_P5_TARGET_PAIRS_PER_BLOCK)
check(new_block > old_block,
      "selected P5 did not increase the sparse block size")
check(new_block == 214L,
      "five-million-pair block sizing changed unexpectedly")

hash_a <- lmv2_p5_selected_execution_hash(
  BASE, paste(rep("1", 64), collapse = ""))
old_calipers <- get("STAGE1_CALIPERS", envir = .GlobalEnv)
assign("STAGE1_CALIPERS", rev(old_calipers), envir = .GlobalEnv)
hash_b <- lmv2_p5_selected_execution_hash(
  BASE, paste(rep("1", 64), collapse = ""))
assign("STAGE1_CALIPERS", old_calipers, envir = .GlobalEnv)
check(nchar(hash_a) == 64L,
      "selected execution hash is not SHA-256 length")
check(!identical(hash_a, hash_b) || length(old_calipers) == 1L,
      "selected execution hash ignored selected settings")

DBI::dbDisconnect(con, shutdown = TRUE)
unlink(fixture_dir, recursive = TRUE, force = TRUE)
message("Selected-P5 certification passed ", checks, "/", checks,
        " checks.")
