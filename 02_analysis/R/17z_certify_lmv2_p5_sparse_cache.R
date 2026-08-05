# Database-free certification of the P5 sparse technology-cache join.

if (!exists("lmv2_build_treated_block_shard_sparse", mode = "function")) {
  BASE <- normalizePath("02_analysis", mustWork = TRUE)
  source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
  source(file.path(BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
}

checks <- 0L
check <- function(ok, message) {
  if (!isTRUE(ok)) stop("P5 sparse-cache certification failed: ", message)
  checks <<- checks + 1L
}

fixture_dir <- tempfile("lmv2_p5_sparse_fixture_")
dir.create(fixture_dir, recursive = TRUE)

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
DBI::dbExecute(con, "PRAGMA threads=2")
DBI::dbExecute(con, "PRAGMA preserve_insertion_order=false")

vectors <- data.frame(
  cohort = 2009L,
  codinv = c(1, 1, 2, 2, 100, 100, 101, 101, 102),
  ipc_feature = c("A01B", "C07D", "A01B", "G01N",
                  "A01B", "C07D", "A01B", "G01N", "H01L"),
  frequency = c(0.6, 0.4, 0.5, 0.5, 0.3, 0.7, 0.8, 0.2, 1.0),
  stringsAsFactors = FALSE)
norms <- aggregate(
  frequency ~ cohort + codinv, vectors,
  function(x) sqrt(sum(x * x)))
names(norms)[names(norms) == "frequency"] <- "norm"

vectors_path <- normalizePath(
  file.path(fixture_dir, "vectors.parquet"),
  winslash = "/", mustWork = FALSE)
norms_path <- normalizePath(
  file.path(fixture_dir, "norms.parquet"),
  winslash = "/", mustWork = FALSE)
duckdb::duckdb_register(con, "fixture_vectors", vectors)
duckdb::duckdb_register(con, "fixture_norms", norms)
DBI::dbExecute(con, sprintf(
  "COPY fixture_vectors TO '%s' (FORMAT PARQUET)", vectors_path))
DBI::dbExecute(con, sprintf(
  "COPY fixture_norms TO '%s' (FORMAT PARQUET)", norms_path))
duckdb::duckdb_unregister(con, "fixture_vectors")
duckdb::duckdb_unregister(con, "fixture_norms")

treated <- data.frame(
  cohort = 2009L, deal_id = 9L,
  treated_codinv = c(1, 2),
  recency_bin_treated = c(0L, 1L))
donors <- data.frame(
  cohort = 2009L, deal_id = 9L,
  control_codinv = c(100, 100, 101, 102),
  control_group = c(10, 11, 10, 12),
  recency_bin_control = c(0L, 0L, 1L, 1L))
admissible_groups <- c(10, 11, 12)
execution_hash <- paste(rep("a", 64), collapse = "")
legacy_dir <- file.path(fixture_dir, "legacy")
sparse_dir <- file.path(fixture_dir, "sparse")

legacy_result <- lmv2_build_treated_block_shard_legacy(
  con, 2009L, "u1", 9L, 1L, treated, donors,
  admissible_groups, 1L, vectors_path, norms_path,
  legacy_dir, execution_hash)
sparse_result <- lmv2_build_treated_block_shard_sparse(
  con, 2009L, "u1", 9L, 1L, treated, donors,
  admissible_groups, 1L, vectors_path, norms_path,
  sparse_dir, execution_hash)

legacy <- DBI::dbGetQuery(
  con, sprintf("SELECT * FROM read_parquet('%s')", legacy_result$path))
sparse <- DBI::dbGetQuery(
  con, sprintf("SELECT * FROM read_parquet('%s')", sparse_result$path))
key <- c("cohort", "treated_codinv", "control_codinv")
legacy <- legacy[do.call(order, legacy[key]), ]
sparse <- sparse[do.call(order, sparse[key]), ]

check(nrow(legacy) == nrow(sparse), "row counts differ")
check(isTRUE(all.equal(
  legacy[key], sparse[key], check.attributes = FALSE)),
  "inventor-pair keys differ")
check(all(legacy$shared_ipc4) && all(sparse$shared_ipc4),
      "shared_ipc4 contract differs")
check(max(abs(legacy$cosine - sparse$cosine)) < 1e-14,
      "cosines differ beyond floating-point tolerance")
check(!anyDuplicated(sparse[key]),
      "duplicate control-firm memberships leaked into sparse output")
check(file.exists(sparse_result$path), "sparse Parquet shard was not committed")

mtime_before <- file.info(sparse_result$path)$mtime
reuse_result <- lmv2_build_treated_block_shard_sparse(
  con, 2009L, "u1", 9L, 1L, treated, donors,
  admissible_groups, 1L, vectors_path, norms_path,
  sparse_dir, execution_hash)
check(isTRUE(reuse_result$reused), "valid shard was not reused")
check(identical(mtime_before, file.info(sparse_result$path)$mtime),
      "checkpoint reuse rewrote the completed shard")

hash_a <- lmv2_p5_sparse_execution_hash(
  BASE, paste(rep("1", 64), collapse = ""))
hash_b <- lmv2_p5_sparse_execution_hash(
  BASE, paste(rep("2", 64), collapse = ""))
check(nchar(hash_a) == 64L, "execution hash is not SHA-256 length")
check(!identical(hash_a, hash_b),
      "execution hash does not respond to P3-manifest drift")

DBI::dbDisconnect(con, shutdown = TRUE)
unlink(fixture_dir, recursive = TRUE, force = TRUE)
message("P5 sparse-cache certification passed ", checks, "/", checks,
        " checks.")
