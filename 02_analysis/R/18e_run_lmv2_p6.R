# ============================================================================
# 18e_run_lmv2_p6.R -- P6 runner: provenance gate, double build, certification
# ============================================================================
# Dormant by construction: every data path must be supplied explicitly on the
# command line. The runner never auto-locates or copies data from a sibling
# worktree; the one-time copy of the frozen database and P2 audit directory
# into this worktree is a separate external command executed by the operator
# (documented in local_match_v2_p6_outcomes.md).
#
# Usage (execution stage only, after P3-P5a):
#   Rscript 02_analysis/R/18e_run_lmv2_p6.R \
#     --db=<path to P6 working copy of thesis_foundation.duckdb> \
#     --p2-manifest=<path to p2_interface_manifest.csv> \
#     --audit-dir=<output directory for P6 audit artifacts> \
#     --roster=<certified P5a roster parquet> \
#     --roster-manifest=<P5a certification manifest csv> | --fixture-only \
#     [--allow-restart]
#
# Production runs REQUIRE --roster AND --roster-manifest; --fixture-only is
# the explicit pre-P5 testing mode, labeled as such in the manifest and pass
# message. The P5a manifest contract (columns): roster_sha256, roster_rows,
# p5a_design_hash, certification_pass. The runner verifies the roster file
# hash and row count against it and refuses uncertified rosters.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}

DB_PATH <- get_arg("--db")
P2_MANIFEST <- get_arg("--p2-manifest")
AUDIT_DIR <- get_arg("--audit-dir")
ROSTER_PATH <- get_arg("--roster")
ROSTER_MANIFEST <- get_arg("--roster-manifest")
ALLOW_RESTART <- "--allow-restart" %in% args
FIXTURE_ONLY <- "--fixture-only" %in% args

if (is.na(DB_PATH) || is.na(P2_MANIFEST) || is.na(AUDIT_DIR)) {
  stop("P6 runner requires explicit --db=, --p2-manifest=, and --audit-dir= ",
       "arguments. It never locates or copies data on its own.")
}
if (!FIXTURE_ONLY && (is.na(ROSTER_PATH) || is.na(ROSTER_MANIFEST))) {
  stop("Production runs require --roster=<certified P5a roster parquet> AND ",
       "--roster-manifest=<P5a certification manifest csv>. ",
       "Use --fixture-only for explicit pre-P5 testing.")
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
# A nested git worktree has its own empty .r_libs; reuse the repository-level
# project library without modifying shared utilities (same pattern as 16a).
LMV2_P6_SHARED_R_LIB <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(LMV2_P6_SHARED_R_LIB)) {
  .libPaths(unique(c(LMV2_P6_SHARED_R_LIB, .libPaths())))
}
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "18b_build_lmv2_outcome_ingredients.R"))
source(file.path(BASE, "R", "18c_materialize_lmv2_outcome_panel.R"))
source(file.path(BASE, "R", "18d_certify_lmv2_outcomes.R"))

t_start <- Sys.time()
dir.create(AUDIT_DIR, recursive = TRUE, showWarnings = FALSE)
write_audit <- function(x, name) {
  utils::write.csv(x, file.path(AUDIT_DIR, name), row.names = FALSE, na = "")
}

# ---------------------------------------------------------------------------
# Provenance gate: abort before any build if inputs are missing/inconsistent.
# ---------------------------------------------------------------------------
if (!file.exists(DB_PATH)) stop("Database not found: ", DB_PATH)
if (!file.exists(P2_MANIFEST)) stop("P2 manifest not found: ", P2_MANIFEST)
AMENDMENTS_PATH <- file.path(BASE, "notes", "local_match_v2_amendments.md")
amendments_sha <- lmv2_file_sha256(AMENDMENTS_PATH)

con <- DBI::dbConnect(duckdb::duckdb(), DB_PATH)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA memory_limit='%s'",
                            LMV2_P6_CONFIG$memory_limit))
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", LMV2_P6_CONFIG$threads))

p2_gate <- lmv2_check_p2_interfaces(con, P2_MANIFEST)
write_audit(p2_gate, "p6_p2_interface_gate.csv")
before_p1 <- lmv2_p1_upstream_checksums(con)
write_audit(before_p1, "p6_p1_upstream_before.csv")

# Source bundle: every file whose code shapes materialized values. 18a hosts
# the outcome-variant SQL generator, so hashing 18c alone would let an 18a
# change leave stale shards looking current.
p6_source_files <- file.path(BASE, "R", c(
  "18a_lmv2_outcome_config.R",
  "18b_build_lmv2_outcome_ingredients.R",
  "18c_materialize_lmv2_outcome_panel.R"
))
p6_source_hashes <- vapply(p6_source_files, lmv2_file_sha256, character(1))
names(p6_source_hashes) <- basename(p6_source_files)

provenance <- list(
  p0_design_hash = LMV2_DESIGN_HASH,
  p6_design_hash = lmv2_p6_design_hash(),
  amendments_sha256 = amendments_sha,
  p2_interface_hashes = setNames(p2_gate$actual_hash, p2_gate$table),
  source_bundle_sha256 = digest::digest(p6_source_hashes, algo = "sha256",
                                        serialize = TRUE),
  ingredient_build_hash = NA_character_ # filled after publish
)

# ---------------------------------------------------------------------------
# True double build: two independent builds into isolated schemas, logical
# hash comparison, publish only on equality. Restart-skipping never
# substitutes for the second build.
# ---------------------------------------------------------------------------
ingredient_checksums <- function(schema) {
  out <- lapply(LMV2_P6_CONFIG$ingredient_tables, function(tbl) {
    lmv2_p1_logical_checksum(con, sprintf("%s.%s", schema, tbl))
  })
  do.call(rbind, out)
}

for (schema in LMV2_P6_CONFIG$build_schemas) {
  build_lmv2_outcome_ingredients(con, schema)
}
hash_a <- ingredient_checksums(LMV2_P6_CONFIG$build_schemas[1])
hash_b <- ingredient_checksums(LMV2_P6_CONFIG$build_schemas[2])
hash_a$table_name <- sub("^[^.]+\\.", "", hash_a$table_name)
hash_b$table_name <- sub("^[^.]+\\.", "", hash_b$table_name)
if (!lmv2_df_equal(hash_a[order(hash_a$table_name), ],
                   hash_b[order(hash_b$table_name), ])) {
  write_audit(hash_a, "p6_build_a_checksums.csv")
  write_audit(hash_b, "p6_build_b_checksums.csv")
  stop("Double-build determinism failed: build_a and build_b differ.")
}

PUBLISH_SCHEMA <- "p6"
DBI::dbExecute(con, sprintf("CREATE SCHEMA IF NOT EXISTS %s", PUBLISH_SCHEMA))
for (tbl in c("lmv2_relevant_inventors", LMV2_P6_CONFIG$ingredient_tables)) {
  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE TABLE %s.%s AS SELECT * FROM %s.%s",
    PUBLISH_SCHEMA, tbl, LMV2_P6_CONFIG$build_schemas[1], tbl))
}
for (schema in LMV2_P6_CONFIG$build_schemas) {
  DBI::dbExecute(con, sprintf("DROP SCHEMA %s CASCADE", schema))
}
provenance$ingredient_build_hash <- digest::digest(hash_a, algo = "sha256",
                                                   serialize = TRUE)
write_audit(hash_a, "p6_ingredient_checksums.csv")

# ---------------------------------------------------------------------------
# Synthetic fixture certification (18d): exact hand-derivable expectations
# plus the roster-validation unit tests.
# ---------------------------------------------------------------------------
build_lmv2_p6_fixture(con, "p6_fixture")
fixture_dir <- file.path(AUDIT_DIR, "panel_synthetic_fixture")
materialize_lmv2_event_panel(con, "p6_fixture.lmv2_fixture_roster",
                             "p6_fixture", fixture_dir, provenance,
                             allow_restart = FALSE,
                             roster_mode = "treated_fixture")
fixture_checks <- run_lmv2_fixture_assertions(
  con, file.path(fixture_dir, "lmv2_event_panel_c2000.parquet"))
roster_checks <- run_lmv2_roster_validation_tests(con, "p6_fixture")

# ---------------------------------------------------------------------------
# Treated fixture: mechanical self-matched roster from the frozen P2
# interface; the materializer must reproduce P2's stayer classification
# exactly (certification test 7).
# ---------------------------------------------------------------------------
derive_treated_fixture_roster(con, "p6.lmv2_treated_fixture_roster")
treated_dir <- file.path(AUDIT_DIR, "panel_treated_fixture")
treated_manifest <- materialize_lmv2_event_panel(
  con, "p6.lmv2_treated_fixture_roster", PUBLISH_SCHEMA, treated_dir,
  provenance, allow_restart = ALLOW_RESTART,
  roster_mode = "treated_fixture")
write_audit(treated_manifest, "p6_treated_fixture_shards.csv")
panel_dirs <- c(treated_fixture = treated_dir)

# ---------------------------------------------------------------------------
# Production stage: certified P5a roster, validated in production mode and
# certified through the same shard families as the fixtures.
# ---------------------------------------------------------------------------
p5a_design_hash <- NA_character_
roster_sha <- NA_character_
if (!FIXTURE_ONLY) {
  if (!file.exists(ROSTER_PATH)) stop("P5a roster not found: ", ROSTER_PATH)
  if (!file.exists(ROSTER_MANIFEST)) {
    stop("P5a roster manifest not found: ", ROSTER_MANIFEST)
  }

  # P5a certification gate: the roster file must match its manifest hash and
  # row count, and the manifest must attest a passing certification.
  p5a <- utils::read.csv(ROSTER_MANIFEST, stringsAsFactors = FALSE)
  required_cols <- c("roster_sha256", "roster_rows", "p5a_design_hash",
                     "certification_pass")
  if (!all(required_cols %in% names(p5a)) || nrow(p5a) != 1) {
    stop("P5a manifest must have exactly one row with columns: ",
         paste(required_cols, collapse = ", "))
  }
  roster_sha <- lmv2_file_sha256(ROSTER_PATH)
  if (!identical(roster_sha, p5a$roster_sha256)) {
    stop("P5a roster file hash does not match its certification manifest.")
  }
  if (!isTRUE(as.logical(p5a$certification_pass))) {
    stop("P5a manifest does not attest a passing certification; refusing ",
         "to materialize an uncertified roster.")
  }
  if (is.na(p5a$p5a_design_hash) || !nzchar(p5a$p5a_design_hash)) {
    stop("P5a manifest must carry a nonempty p5a_design_hash.")
  }
  p5a_design_hash <- p5a$p5a_design_hash

  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE TABLE p6.lmv2_p5a_roster AS
     SELECT * FROM read_parquet('%s')", gsub("\\\\", "/", ROSTER_PATH)))
  n_roster_rows <- DBI::dbGetQuery(
    con, "SELECT COUNT(*) n FROM p6.lmv2_p5a_roster")$n
  if (n_roster_rows != as.integer(p5a$roster_rows)) {
    stop("P5a roster row count (", n_roster_rows,
         ") does not match its certification manifest (", p5a$roster_rows, ").")
  }

  # Membership certification against the frozen P2 interfaces: every treated
  # row must exist in lmv2_treated_primary with identical focal groups and
  # status_eligible; every control must be an eligible control-inventor row.
  membership <- certify_lmv2_roster_membership(con, "p6.lmv2_p5a_roster")
  write_audit(membership, "p6_roster_membership_certification.csv")
  if (!all(membership$pass)) {
    stop("P5a roster membership certification failed: ",
         paste(membership$check[!membership$pass], collapse = ", "))
  }

  matched_dir <- file.path(AUDIT_DIR, "panel_matched")
  matched_manifest <- materialize_lmv2_event_panel(
    con, "p6.lmv2_p5a_roster", PUBLISH_SCHEMA, matched_dir,
    provenance, allow_restart = ALLOW_RESTART,
    roster_mode = "production")
  write_audit(matched_manifest, "p6_matched_panel_shards.csv")
  panel_dirs <- c(panel_dirs, matched = matched_dir)
}

# Certification runs over every materialized panel directory, so a supplied
# production roster is always inside the certified scope, never after it.
cert <- run_lmv2_p6_certification(
  con, PUBLISH_SCHEMA, panel_dirs,
  before_p1, P2_MANIFEST, r_dir = file.path(BASE, "R"))
all_checks <- rbind(
  cert[, c("check", "pass")],
  fixture_checks,
  roster_checks
)
write_audit(cert, "p6_certification.csv")
write_audit(fixture_checks, "p6_synthetic_fixture_checks.csv")
write_audit(roster_checks, "p6_roster_validation_checks.csv")
write_audit(attr(cert, "oecd_field_availability"),
            "p6_oecd_field_availability_by_filing_year.csv")

# ---------------------------------------------------------------------------
# Manifest. Memory: the configured cap is recorded as a setting, never as an
# observed peak; DuckDB memory statistics are included when the installed
# version exposes them; process peak is NA unless a reliable method exists.
# ---------------------------------------------------------------------------
duckdb_mem <- tryCatch(
  DBI::dbGetQuery(con, "SELECT * FROM duckdb_memory()"),
  error = function(e) data.frame(note = "duckdb_memory() unavailable"))
write_audit(duckdb_mem, "p6_duckdb_memory_stats.csv")

manifest <- data.frame(
  p6_version = LMV2_P6_VERSION,
  run_mode = ifelse(FIXTURE_ONLY, "fixture_only_pre_p5", "production"),
  p6_design_hash = provenance$p6_design_hash,
  p0_design_hash = provenance$p0_design_hash,
  amendments_sha256 = provenance$amendments_sha256,
  source_18a_sha256 = p6_source_hashes[["18a_lmv2_outcome_config.R"]],
  source_18b_sha256 = p6_source_hashes[["18b_build_lmv2_outcome_ingredients.R"]],
  source_18c_sha256 = p6_source_hashes[["18c_materialize_lmv2_outcome_panel.R"]],
  source_bundle_sha256 = provenance$source_bundle_sha256,
  ingredient_build_hash = provenance$ingredient_build_hash,
  db_path = DB_PATH,
  p2_manifest_path = P2_MANIFEST,
  roster_path = ifelse(is.na(ROSTER_PATH), "", ROSTER_PATH),
  roster_sha256 = ifelse(is.na(roster_sha), "", roster_sha),
  roster_manifest_path = ifelse(is.na(ROSTER_MANIFEST), "", ROSTER_MANIFEST),
  roster_manifest_sha256 = ifelse(
    is.na(ROSTER_MANIFEST), "", lmv2_file_sha256(ROSTER_MANIFEST)),
  p5a_design_hash = ifelse(is.na(p5a_design_hash), "", p5a_design_hash),
  n_checks = nrow(all_checks),
  n_failed = sum(!all_checks$pass),
  configured_memory_limit = LMV2_P6_CONFIG$memory_limit,
  configured_threads = LMV2_P6_CONFIG$threads,
  observed_process_peak_memory = NA_character_,
  runtime_minutes = round(as.numeric(difftime(Sys.time(), t_start,
                                              units = "mins")), 2),
  stringsAsFactors = FALSE
)
write_audit(manifest, "p6_manifest.csv")

failed <- all_checks$check[!all_checks$pass]
if (length(failed)) {
  stop("P6 certification failed: ", paste(failed, collapse = ", "))
}
message(ifelse(FIXTURE_ONLY,
               "P6 FIXTURE PASS (pre-P5 testing mode; NOT a production run)",
               "P6 PASS (production)"),
        " | design_hash=", provenance$p6_design_hash,
        " | checks=", nrow(all_checks))
