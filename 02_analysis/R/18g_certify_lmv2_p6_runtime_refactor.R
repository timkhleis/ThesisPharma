# ============================================================================
# 18g_certify_lmv2_p6_runtime_refactor.R -- bounded runtime/A-B certification
# ============================================================================
# This is a pre-production harness. It materializes only explicitly requested
# cohorts, checks exact multiset equality against preserved pre-refactor
# shards, and records runtime/memory evidence. It never estimates outcomes.
#
# Usage:
#   Rscript 02_analysis/R/18g_certify_lmv2_p6_runtime_refactor.R \
#     --db=<working duckdb> --roster=<frozen P5 roster parquet> \
#     --old-dir=<preserved panel_matched directory> \
#     --new-dir=<fresh benchmark directory> \
#     --cohorts=1994,1995,1996,1997,1998 --threads=4

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}

DB_PATH <- get_arg("--db")
ROSTER_PATH <- get_arg("--roster")
OLD_DIR <- get_arg("--old-dir")
NEW_DIR <- get_arg("--new-dir")
COHORTS <- as.integer(strsplit(get_arg("--cohorts"), ",", fixed = TRUE)[[1]])
THREADS <- as.integer(get_arg("--threads"))
if (any(is.na(c(DB_PATH, ROSTER_PATH, OLD_DIR, NEW_DIR))) ||
    !length(COHORTS) || any(is.na(COHORTS)) ||
    length(THREADS) != 1 || is.na(THREADS) || THREADS < 1) {
  stop(
    "Required: --db= --roster= --old-dir= --new-dir= ",
    "--cohorts=<comma list> --threads=<positive integer>")
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "jsonlite")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "18c_materialize_lmv2_outcome_panel.R"))
source(file.path(BASE, "R", "18d_certify_lmv2_outcomes.R"))

dir.create(NEW_DIR, recursive = TRUE, showWarnings = FALSE)
con <- DBI::dbConnect(duckdb::duckdb(), DB_PATH)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", THREADS))
DBI::dbExecute(con, sprintf("
  CREATE OR REPLACE TEMP TABLE runtime_refactor_roster AS
  SELECT * FROM read_parquet('%s')",
  gsub("\\\\", "/", ROSTER_PATH)))

provenance <- list(
  p0_design_hash = LMV2_DESIGN_HASH,
  p6_design_hash = lmv2_p6_design_hash(),
  amendments_sha256 = lmv2_file_sha256(
    file.path(BASE, "notes", "local_match_v2_amendments.md")),
  preanalysis_freeze_sha256 = LMV2_P6_PREANALYSIS_FREEZE_SHA256,
  p2_interface_hashes = "runtime_refactor_bounded_harness",
  source_bundle_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "18c_materialize_lmv2_outcome_panel.R"),
    algo = "sha256"),
  ingredient_build_hash = "preserved_p6_published_ingredients")

# The synthetic fixture is deliberately run in the same process so the
# NULL-focal control regression and hand-derived outcome matrix gate every
# benchmark.
build_lmv2_p6_fixture(con, "p6_runtime_fixture")
fixture_dir <- file.path(NEW_DIR, "synthetic_fixture")
materialize_lmv2_event_panel(
  con, "p6_runtime_fixture.lmv2_fixture_roster",
  "p6_runtime_fixture", fixture_dir, provenance,
  roster_mode = "treated_fixture")
fixture_checks <- run_lmv2_fixture_assertions(
  con, file.path(fixture_dir, "lmv2_event_panel_c2000.parquet"))
if (!all(fixture_checks$pass)) {
  stop(
    "Synthetic runtime-refactor fixture failed: ",
    paste(fixture_checks$check[!fixture_checks$pass], collapse = ", "))
}

# Certify the structural-gap fix independently of causal materialization:
# every eligible treated inventor, both supported and unsupported, appears
# exactly five times and only before treatment.
selection_path <- file.path(
  NEW_DIR, "p6_all_eligible_treated_preperiod.parquet")
selection_checks <- materialize_lmv2_selection_prepanel(
  con, "runtime_refactor_roster", "p6", selection_path)
if (!all(selection_checks$pass)) {
  stop(
    "All-eligible treated pre-period fixture failed: ",
    paste(selection_checks$check[!selection_checks$pass], collapse = ", "))
}

panel_dir <- file.path(NEW_DIR, "panel_matched")
profile_dir <- file.path(NEW_DIR, "profiles")
manifest <- materialize_lmv2_event_panel(
  con, "runtime_refactor_roster", "p6", panel_dir, provenance,
  roster_mode = "production", cohorts_to_run = COHORTS,
  profile_dir = profile_dir)

profiles <- lapply(seq_len(nrow(manifest)), function(i) {
  profile_path <- manifest$profile_path[i]
  if (is.na(profile_path) || !file.exists(profile_path)) {
    stop("Missing DuckDB JSON profile for cohort ", manifest$cohort[i])
  }
  profile <- jsonlite::fromJSON(profile_path, simplifyVector = TRUE)
  data.frame(
    cohort = manifest$cohort[i],
    system_peak_buffer_memory = profile$system_peak_buffer_memory,
    system_peak_temp_dir_size = profile$system_peak_temp_dir_size,
    rows_returned = profile$rows_returned,
    stringsAsFactors = FALSE)
})
profiles <- do.call(rbind, profiles)

quote_col <- function(x) {
  paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
}
parquet_checksum <- function(path, columns) {
  hash_expr <- paste(vapply(columns, quote_col, character(1)),
                     collapse = ", ")
  DBI::dbGetQuery(con, sprintf("
    SELECT
      COUNT(*) AS rows,
      CAST(SUM(CAST(hash(%s) AS HUGEINT)) AS VARCHAR) AS hash_sum,
      CAST(bit_xor(hash(%s)) AS VARCHAR) AS hash_xor
    FROM read_parquet('%s')",
    hash_expr, hash_expr, gsub("\\\\", "/", path)))
}

comparisons <- lapply(COHORTS, function(g) {
  old_path <- file.path(
    OLD_DIR, sprintf("lmv2_event_panel_c%d.parquet", g))
  new_path <- file.path(
    panel_dir, sprintf("lmv2_event_panel_c%d.parquet", g))
  if (!file.exists(old_path)) stop("Missing preserved old shard: ", old_path)
  if (!file.exists(new_path)) stop("Missing new shard: ", new_path)
  op <- gsub("\\\\", "/", old_path)
  np <- gsub("\\\\", "/", new_path)
  old_schema <- DBI::dbGetQuery(
    con, sprintf("DESCRIBE SELECT * FROM read_parquet('%s')", op))
  new_schema <- DBI::dbGetQuery(
    con, sprintf("DESCRIBE SELECT * FROM read_parquet('%s')", np))
  columns <- old_schema$column_name
  except_counts <- DBI::dbGetQuery(con, sprintf("
    SELECT
      (SELECT COUNT(*) FROM (
        SELECT * FROM read_parquet('%1$s')
        EXCEPT ALL
        SELECT * FROM read_parquet('%2$s'))) AS old_minus_new,
      (SELECT COUNT(*) FROM (
        SELECT * FROM read_parquet('%2$s')
        EXCEPT ALL
        SELECT * FROM read_parquet('%1$s'))) AS new_minus_old",
    op, np))
  old_hash <- parquet_checksum(old_path, columns)
  new_hash <- parquet_checksum(new_path, columns)
  data.frame(
    cohort = g,
    schema_equal = lmv2_df_equal(old_schema, new_schema),
    rows_old = old_hash$rows,
    rows_new = new_hash$rows,
    old_minus_new = except_counts$old_minus_new,
    new_minus_old = except_counts$new_minus_old,
    hash_sum_equal = identical(old_hash$hash_sum, new_hash$hash_sum),
    hash_xor_equal = identical(old_hash$hash_xor, new_hash$hash_xor),
    pass =
      lmv2_df_equal(old_schema, new_schema) &&
      old_hash$rows == new_hash$rows &&
      except_counts$old_minus_new == 0 &&
      except_counts$new_minus_old == 0 &&
      identical(old_hash$hash_sum, new_hash$hash_sum) &&
      identical(old_hash$hash_xor, new_hash$hash_xor),
    stringsAsFactors = FALSE)
})
comparisons <- do.call(rbind, comparisons)

# Isolate the deterministic-sort change from all join changes. The largest
# preserved shard is copied twice from the same source with identical Parquet
# settings; only the ordering key differs.
sort_cohort <- comparisons$cohort[which.max(comparisons$rows_old)]
sort_source <- gsub("\\\\", "/", file.path(
  OLD_DIR, sprintf("lmv2_event_panel_c%d.parquet", sort_cohort)))
sort_variants <- list(
  order_by_all = "ORDER BY ALL",
  order_by_narrow_key =
    "ORDER BY deal_id, arm, codinv, roster_row_id, event_time")
sort_benchmark <- lapply(names(sort_variants), function(label) {
  sort_output <- gsub("\\\\", "/", file.path(
    NEW_DIR, paste0("sort_benchmark_", label, ".parquet")))
  started <- proc.time()[["elapsed"]]
  DBI::dbExecute(con, sprintf("
    COPY (
      SELECT * FROM read_parquet('%s') %s
    ) TO '%s' (
      FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE TRUE)",
    sort_source, sort_variants[[label]], sort_output))
  data.frame(
    cohort = sort_cohort,
    variant = label,
    rows = DBI::dbGetQuery(con, sprintf(
      "SELECT COUNT(*) n FROM read_parquet('%s')", sort_output))$n,
    runtime_seconds = proc.time()[["elapsed"]] - started,
    stringsAsFactors = FALSE)
})
sort_benchmark <- do.call(rbind, sort_benchmark)

utils::write.csv(
  fixture_checks,
  file.path(NEW_DIR, "runtime_refactor_fixture_checks.csv"),
  row.names = FALSE)
utils::write.csv(
  selection_checks,
  file.path(NEW_DIR, "runtime_refactor_selection_checks.csv"),
  row.names = FALSE)
utils::write.csv(
  attr(selection_checks, "manifest"),
  file.path(NEW_DIR, "runtime_refactor_selection_manifest.csv"),
  row.names = FALSE)
utils::write.csv(
  manifest,
  file.path(NEW_DIR, "runtime_refactor_manifest.csv"),
  row.names = FALSE)
utils::write.csv(
  profiles,
  file.path(NEW_DIR, "runtime_refactor_profiles.csv"),
  row.names = FALSE)
utils::write.csv(
  comparisons,
  file.path(NEW_DIR, "runtime_refactor_exact_ab.csv"),
  row.names = FALSE)
utils::write.csv(
  sort_benchmark,
  file.path(NEW_DIR, "runtime_refactor_sort_benchmark.csv"),
  row.names = FALSE)
memory <- tryCatch(
  DBI::dbGetQuery(con, "SELECT * FROM duckdb_memory()"),
  error = function(e) data.frame(note = conditionMessage(e)))
utils::write.csv(
  memory,
  file.path(NEW_DIR, "runtime_refactor_memory.csv"),
  row.names = FALSE)
utils::write.csv(
  data.frame(
    threads = THREADS,
    cohorts = paste(COHORTS, collapse = ","),
    runtime_seconds = sum(manifest$runtime_seconds),
    exact_ab_pass = all(comparisons$pass),
    stringsAsFactors = FALSE),
  file.path(NEW_DIR, "runtime_refactor_summary.csv"),
  row.names = FALSE)

if (!all(comparisons$pass)) {
  stop(
    "Runtime refactor changed preserved shard content for cohort(s): ",
    paste(comparisons$cohort[!comparisons$pass], collapse = ", "))
}
message(
  "RUNTIME REFACTOR PASS | threads=", THREADS,
  " | cohorts=", paste(COHORTS, collapse = ","),
  " | seconds=", round(sum(manifest$runtime_seconds), 2))
