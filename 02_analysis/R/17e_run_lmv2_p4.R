# ============================================================================
# 17e_run_lmv2_p4.R -- twice-run deterministic P4 pilot runner
# ============================================================================
# Requires explicit --db, --p3-manifest, and --audit-dir.  Refuses hash
# drift, audits the P4 sources for outcome references, runs the synthetic
# certification, executes two complete pilot runs in fresh isolated run
# directories, and publishes the frozen design only when both logical
# manifests are identical and every acceptance check passed.  Nothing is ever
# claimed from restart-skipped files: both run directories must be created by
# this invocation.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17a_lmv2_p4_pilot_config.R"))

db_path <- lmv2_p4_read_arg("db")
p3_manifest_path <- lmv2_p4_read_arg("p3-manifest")
audit_dir <- lmv2_p4_read_arg("audit-dir")
if (!file.exists(db_path)) stop("Database not found: ", db_path)
invisible(lmv2_p4_validate_p3_manifest(p3_manifest_path))
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

p4_sources <- file.path(BASE, "R", c(
  "17a_lmv2_p4_pilot_config.R", "17b_run_lmv2_stage1_pilot.R",
  "17c_run_lmv2_stage2_pilot.R", "17d_certify_lmv2_p4_pilot.R",
  "17e_run_lmv2_p4.R"
))
design_records <- c(
  LMV2_P4_PATHS$resolution_lock,
  LMV2_P4_PATHS$small_cohort_amendment,
  LMV2_P4_PATHS$trajectory_fallback_amendment,
  LMV2_P4_PATHS$bisection_amendment,
  file.path(BASE, "notes", "local_match_v2_p4_outcome_blind_pilot.md"),
  file.path(BASE, "R", "15a_lmv2_design_lock.R"),
  file.path(BASE, "R", "16a_lmv2_matching_config.R"),
  file.path(BASE, "R", "16c_lmv2_matching_utils.R")
)

# --- Outcome-blind source audit ---------------------------------------------
# Exact forbidden table/column identifiers only (no broad substrings), with
# the patterns assembled from fragments so this audit never matches its own
# definitions.  Only executable R tokens are scanned: files are parsed and
# comment tokens are excluded, so prose in comments can neither trigger nor
# mask a violation.  String literals (for example SQL) remain in scope.
frag <- function(...) paste0(...)
forbidden <- c(
  frag("pq", "ii"), frag("quality", "_index"), frag("forward", "_citations"),
  frag("oe", "cd"), frag("cit", "ation"), frag("tech", "_drift"),
  frag("tech", "drift"), frag("absorbing", "_left"), frag("left", "_onset"),
  frag("event", "_panel"), frag("lmv2", "_p6"), frag("patent", "_enriched"),
  frag("18", "[a-z]_lmv2")
)
audit_pattern <- paste0("\\b(?:", paste(forbidden, collapse = "|"), ")")
violations <- list()
for (path in p4_sources) {
  pd <- utils::getParseData(parse(path, keep.source = TRUE))
  code <- pd[pd$terminal & pd$token != "COMMENT", , drop = FALSE]
  hits <- grepl(audit_pattern, code$text, ignore.case = TRUE, perl = TRUE)
  if (any(hits)) {
    violations[[basename(path)]] <- data.frame(
      file = basename(path), line = code$line1[hits], token = code$text[hits],
      stringsAsFactors = FALSE
    )
  }
}
if (length(violations)) {
  bad <- do.call(rbind, violations)
  lmv2_p4_write_csv(bad, audit_dir, "p4_source_audit_violations.csv")
  stop("P4 source audit found outcome references in: ",
       paste(unique(bad$file), collapse = ", "))
}

source_hashes <- do.call(rbind, lapply(c(p4_sources, design_records), function(p) {
  data.frame(file = basename(p), sha256 = lmv2_p3_file_hash(p),
             stringsAsFactors = FALSE)
}))
source_hashes$p4_version <- LMV2_P4_VERSION
source_hashes$p4_config_hash <- LMV2_P4_CONFIG_HASH
lmv2_p4_write_csv(source_hashes, audit_dir, "p4_source_hashes.csv")

# --- Certification first, then two complete pilot runs ----------------------
rscript <- file.path(R.home("bin"), "Rscript.exe")
run_script_status <- function(path, args) {
  system2(rscript, c(shQuote(path, type = "cmd"),
                     shQuote(args, type = "cmd")))
}
run_script <- function(path, args) {
  status <- run_script_status(path, args)
  if (!identical(status, 0L)) stop("P4 script failed: ", basename(path))
}

run_script(file.path(BASE, "R", "17d_certify_lmv2_p4_pilot.R"),
           paste0("--audit-dir=", audit_dir))
cert <- utils::read.csv(file.path(audit_dir, "p4_package_status.csv"),
                        stringsAsFactors = FALSE)
if (!isTRUE(cert$pass)) stop("P4 certification failed before the pilot runs")

common_outputs <- c(
  "p4_stage1_profiles.csv", "p4_stage1_profile_metrics.csv",
  "p4_stage1_unsupported.csv", "p4_stage1_reuse.csv",
  "p4_stage1_frozen_firms.csv", "p4_stage1_freeze.csv",
  "p4_stage2_support_cohorts.csv", "p4_stage2_support_units.csv",
  "p4_stage2_donor_exclusions.csv", "p4_resolution_decision.csv",
  "p4_stage2_scalers.csv", "p4_stage2_profiles.csv",
  "p4_stage2_profile_metrics.csv", "p4_stage2_funnel.csv",
  "p4_stage2_composition.csv", "p4_stage2_big_retention.csv",
  "p4_stage2_reuse.csv", "p4_stage2_bisection.csv"
)
success_outputs <- c("p4_final_firm_balance.csv",
                     "p4_stage2_matched_sets.csv", "p4_design.csv")

final_gate_failed_in <- function(dir) {
  path <- file.path(dir, "p4_final_firm_balance.csv")
  file.exists(path) && any(!utils::read.csv(path, stringsAsFactors = FALSE)$pass)
}

check_attempt_outputs <- function(dir, frozen_design) {
  files <- list.files(dir)
  missing <- setdiff(common_outputs, files)
  if (frozen_design) missing <- c(missing, setdiff(success_outputs, files))
  if (length(missing)) {
    stop("Pilot attempt incomplete in ", dir, "; missing: ",
         paste(missing, collapse = ", "))
  }
  if (!frozen_design &&
      !file.exists(file.path(dir, "p4_stage2_design_failure.csv")) &&
      !final_gate_failed_in(dir)) {
    stop("Failed pilot attempt lacks a design-failure record in ", dir)
  }
}

pilot_run <- function(run_dir) {
  if (dir.exists(run_dir) && length(list.files(run_dir, recursive = TRUE))) {
    stop("Run directory already populated; refusing restart-skipped results: ",
         run_dir)
  }
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
  base_args <- c(paste0("--db=", db_path),
                 paste0("--p3-manifest=", p3_manifest_path))
  started <- Sys.time()

  # Primary five-firm design.  A Stage-1 failure never activates the
  # extension (pinned ten-firm amendment) and stops the pilot.
  args5 <- c(base_args, paste0("--audit-dir=", run_dir), "--pool-size=5")
  run_script(file.path(BASE, "R", "17b_run_lmv2_stage1_pilot.R"), args5)
  status5 <- run_script_status(file.path(BASE, "R", "17c_run_lmv2_stage2_pilot.R"),
                               args5)
  ten_dir <- file.path(run_dir, "ten_firm")
  if (!identical(status5, 0L)) {
    # Activation only on a five-firm Stage-2 terminal failure: bounded
    # refinement exhausted, or the final firm-trajectory gate failed.
    refinement_exhausted <- file.exists(file.path(run_dir,
                                                  "p4_stage2_design_failure.csv"))
    if (!refinement_exhausted && !final_gate_failed_in(run_dir)) {
      stop("Five-firm Stage 2 failed outside the ten-firm activation conditions")
    }
    message("Five-firm design exhausted its bounded refinement; activating ",
            "the ten-firm extension (final structural attempt)")
    dir.create(ten_dir, recursive = TRUE, showWarnings = FALSE)
    args10 <- c(base_args, paste0("--audit-dir=", ten_dir), "--pool-size=10")
    status10 <- run_script_status(file.path(BASE, "R", "17b_run_lmv2_stage1_pilot.R"),
                                  args10)
    if (identical(status10, 0L)) {
      status10 <- run_script_status(file.path(BASE, "R", "17c_run_lmv2_stage2_pilot.R"),
                                    args10)
    }
    if (!identical(status10, 0L)) {
      stop("P4 permanent stop: the ten-firm design also failed; this matching ",
           "design is infeasible under the locked standards and no further ",
           "tuning follows")
    }
  }

  five_success <- file.exists(file.path(run_dir, "p4_design.csv"))
  ten_success <- file.exists(file.path(ten_dir, "p4_design.csv"))
  if (identical(five_success, ten_success)) {
    stop("Exactly one pilot attempt must freeze a design in ", run_dir)
  }
  check_attempt_outputs(run_dir, frozen_design = five_success)
  if (dir.exists(ten_dir)) check_attempt_outputs(ten_dir, frozen_design = TRUE)
  all_csvs <- list.files(run_dir, pattern = "\\.csv$", recursive = TRUE)
  stale <- all_csvs[file.mtime(file.path(run_dir, all_csvs)) < started]
  if (length(stale)) {
    stop("Pilot outputs predate this invocation in ", run_dir, ": ",
         paste(stale, collapse = ", "))
  }
  as.numeric(difftime(Sys.time(), started, units = "mins"))
}

run1_dir <- file.path(audit_dir, "run1")
run2_dir <- file.path(audit_dir, "run2")
minutes1 <- pilot_run(run1_dir)
minutes2 <- pilot_run(run2_dir)

first <- lmv2_p4_logical_manifest(run1_dir)
second <- lmv2_p4_logical_manifest(run2_dir)
deterministic <- identical(first, second)
comparison <- merge(first[c("file", "rows", "logical_sha256")],
                    second[c("file", "rows", "logical_sha256")],
                    by = "file", all = TRUE, suffixes = c("_run1", "_run2"))
comparison$identical <- !is.na(comparison$logical_sha256_run1) &
  !is.na(comparison$logical_sha256_run2) &
  comparison$logical_sha256_run1 == comparison$logical_sha256_run2
lmv2_p4_write_csv(comparison[order(comparison$file), ], audit_dir,
                  "p4_manifest_comparison.csv")

determinism <- data.frame(
  p4_version = LMV2_P4_VERSION, p4_config_hash = LMV2_P4_CONFIG_HASH,
  check = "two_complete_p4_pilot_runs_have_identical_logical_manifests",
  pass = deterministic,
  first_run_minutes = minutes1, second_run_minutes = minutes2,
  stringsAsFactors = FALSE
)
lmv2_p4_write_csv(determinism, audit_dir, "p4_rebuild_determinism.csv")
if (!deterministic) stop("P4 logical manifests differ across complete pilot runs")

# --- Publish / freeze --------------------------------------------------------
published <- list.files(run1_dir, pattern = "\\.csv$", recursive = TRUE)
for (f in published) {
  target <- file.path(audit_dir, f)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  stopifnot(file.copy(file.path(run1_dir, f), target, overwrite = TRUE))
}
manifest <- lmv2_p4_logical_manifest(run1_dir)
manifest$p3_config_hash <- LMV2_P3_CONFIG_HASH
manifest$p3_manifest_hash <- LMV2_P4_P3_MANIFEST_SHA256
manifest$resolution_lock_hash <- LMV2_P4_RESOLUTION_LOCK_SHA256
manifest$small_cohort_amendment_hash <- LMV2_P4_SMALL_COHORT_AMENDMENT_SHA256
manifest$trajectory_fallback_amendment_hash <- LMV2_P4_TRAJECTORY_FALLBACK_AMENDMENT_SHA256
manifest$bisection_amendment_hash <- LMV2_P4_BISECTION_AMENDMENT_SHA256
manifest$p0_design_hash <- LMV2_DESIGN_HASH
lmv2_p4_write_csv(manifest, audit_dir, "p4_interface_manifest.csv")
print(determinism)
message("P4 pilot published to ", audit_dir)
