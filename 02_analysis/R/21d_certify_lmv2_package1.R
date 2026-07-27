# ============================================================================
# Package 1 terminal certification and real-positive tooth tests
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Missing package: digest")
}

P6_ROOT <- normalizePath(file.path(BASE, ".."), winslash = "/", mustWork = TRUE)
WORKTREES <- normalizePath(
  file.path(P6_ROOT, ".."), winslash = "/", mustWork = TRUE)
P4_ROOT <- normalizePath(
  file.path(WORKTREES, "lmv2-p4-ebal"), winslash = "/", mustWork = TRUE)
P4_AUDIT <- file.path(
  P4_ROOT, "02_analysis", "output", "audit", "local_match_v2")
AUDIT <- file.path(BASE, "output", "audit", "local_match_v2")
OUT_DIR <- file.path(AUDIT, "P6_PACKAGE1_LOYO_GRID")

paths <- c(
  certifier = file.path(BASE, "R", "21d_certify_lmv2_package1.R"),
  freeze = file.path(
    BASE, "notes", "local_match_v2_package1_preperiod_freeze.md"),
  weight_runner = file.path(
    P4_ROOT, "02_analysis", "R", "22a_run_lmv2_package1_loyo_grid.R"),
  p6_runner = file.path(BASE, "R", "21b_run_lmv2_package1_p6.R"),
  summarizer = file.path(BASE, "R", "21c_summarize_lmv2_package1.R"),
  p4_grid_certification = file.path(
    P4_AUDIT, "P5C_PACKAGE1_LOYO_GRID",
    "package1_loyo_grid_certification.csv"),
  p6_run_manifest = file.path(
    OUT_DIR, "package1_p6_run_manifest.csv"),
  summary_manifest = file.path(
    OUT_DIR, "package1_summary_manifest.csv"),
  placebos = file.path(
    OUT_DIR, "package1_loyo_heldout_placebos.csv"),
  post_stability = file.path(
    OUT_DIR, "package1_loyo_post_stability.csv"),
  timing_minus3 = file.path(
    OUT_DIR, "package1_timing_placebo_minus3.csv"),
  timing_validity = file.path(
    OUT_DIR, "package1_timing_placebo_validity.csv"))
missing <- paths[!file.exists(paths)]
if (length(missing)) {
  stop("Package 1 certification input missing: ",
       paste(names(missing), collapse = ", "))
}

source_manifest <- data.frame(
  source = names(paths),
  path = unname(normalizePath(
    paths, winslash = "/", mustWork = TRUE)),
  sha256 = unname(vapply(
    paths, digest::digest, character(1),
    file = TRUE, algo = "sha256")),
  stringsAsFactors = FALSE)
source_manifest <- source_manifest[order(source_manifest$source), ]
package_hash <- digest::digest(
  source_manifest[, c("source", "sha256")],
  algo = "sha256", serialize = TRUE)

checks <- list()
add <- function(check, observed, expected, pass) {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = check,
    observed = as.character(observed),
    expected = as.character(expected),
    pass = isTRUE(pass),
    stringsAsFactors = FALSE)
}

p4_cert <- utils::read.csv(
  paths[["p4_grid_certification"]], stringsAsFactors = FALSE)
add(
  "new_loyo_weight_grid_certified",
  paste(p4_cert$observed_new_cells, p4_cert$all_pass, sep = "/"),
  "34/TRUE",
  nrow(p4_cert) == 1L &&
    p4_cert$observed_new_cells == 34L &&
    isTRUE(p4_cert$all_pass))

p6_runs <- utils::read.csv(
  paths[["p6_run_manifest"]], stringsAsFactors = FALSE)
add(
  "new_loyo_p6_runs_certified",
  paste(p6_runs$variant, collapse = ","),
  "loyo_m2,loyo_m5",
  identical(sort(p6_runs$variant), c("loyo_m2", "loyo_m5")) &&
    all(p6_runs$pass))

summary_manifest <- utils::read.csv(
  paths[["summary_manifest"]], stringsAsFactors = FALSE)
add(
  "package1_summary_certified",
  summary_manifest$all_pass, TRUE,
  nrow(summary_manifest) == 1L &&
    isTRUE(summary_manifest$all_pass))

placebo <- utils::read.csv(
  paths[["placebos"]], stringsAsFactors = FALSE)
expected_designs <- c("loyo_m2", "loyo_m3", "loyo_m4", "loyo_m5")
grid_valid <- function(x) {
  nrow(x) == 8L &&
    identical(sort(unique(x$design)), expected_designs) &&
    identical(sort(unique(x$sample)),
              c("buffered_1994_2008", "full_1994_2010")) &&
    !anyNA(x[c(
      "estimate", "se", "ci_low", "ci_high",
      "tost_equivalent_alpha_005")])
}
add(
  "four_arm_placebo_grid_complete",
  paste(sort(unique(placebo$design)), collapse = ","),
  paste(expected_designs, collapse = ","),
  grid_valid(placebo))
add(
  "terminal_preperiod_not_held_out",
  any(placebo$design == "loyo_m1"), FALSE,
  !any(placebo$design == "loyo_m1"))

# A real missing-arm positive must make the grid guard fail.
missing_arm_fixture <- placebo[placebo$design != "loyo_m2", ]
add(
  "placebo_grid_missing_arm_tooth_test",
  grid_valid(missing_arm_fixture), FALSE,
  !grid_valid(missing_arm_fixture))

tost <- function(estimate, se, df, margin = 0.05) {
  p_lower <- stats::pt(
    (estimate + margin) / se, df = df, lower.tail = FALSE)
  p_upper <- stats::pt(
    (estimate - margin) / se, df = df, lower.tail = TRUE)
  p_lower < 0.05 && p_upper < 0.05
}
tost_fixture <- c(
  precise_zero = tost(0, 0.01, 300),
  imprecise_zero = tost(0, 0.10, 300),
  outside_margin = tost(0.06, 0.01, 300))
tost_expected <- c(TRUE, FALSE, FALSE)
add(
  "tost_real_positive_and_negative_fixtures",
  paste(tost_fixture, collapse = ","),
  paste(tost_expected, collapse = ","),
  identical(unname(tost_fixture), unname(tost_expected)))

post <- utils::read.csv(
  paths[["post_stability"]], stringsAsFactors = FALSE)
add(
  "all_post_designs_reported",
  paste(sort(unique(post$design)), collapse = ","),
  "count_active,loyo_m2,loyo_m3,loyo_m4,loyo_m5",
  nrow(post) == 10L &&
    identical(
      sort(unique(post$design)),
      c("count_active", expected_designs)))

timing <- utils::read.csv(
  paths[["timing_minus3"]], stringsAsFactors = FALSE)
validity <- utils::read.csv(
  paths[["timing_validity"]], stringsAsFactors = FALSE)
add(
  "minus3_timing_placebo_reported",
  nrow(timing), 4,
  nrow(timing) == 4L &&
    identical(sort(unique(timing$pseudo_event_time)), c(1L, 2L)) &&
    all(timing$pseudo_shift_years == -3L))
add(
  "plus3_timing_shift_rejected_as_contaminated",
  validity$valid_no_effect_placebo[
    validity$pseudo_shift_years == 3L],
  FALSE,
  nrow(validity) == 2L &&
    !validity$valid_no_effect_placebo[
      validity$pseudo_shift_years == 3L])

# Tooth-test the package hash against a real mutation of the freeze.
temp_freeze <- tempfile("package1_freeze_", fileext = ".md")
if (!file.copy(paths[["freeze"]], temp_freeze, overwrite = TRUE)) {
  stop("Could not create Package 1 mutation fixture")
}
cat("\nPACKAGE1_REAL_MUTATION\n", file = temp_freeze, append = TRUE)
mutated_manifest <- source_manifest
mutated_manifest$sha256[
  mutated_manifest$source == "freeze"] <- digest::digest(
    file = temp_freeze, algo = "sha256")
mutated_hash <- digest::digest(
  mutated_manifest[, c("source", "sha256")],
  algo = "sha256", serialize = TRUE)
unlink(temp_freeze)
add(
  "package_hash_mutation_tooth_test",
  identical(package_hash, mutated_hash), FALSE,
  !identical(package_hash, mutated_hash))

certification <- do.call(rbind, checks)
certification$package_hash <- package_hash
certification <- certification[
  , c("package_hash", "check", "observed", "expected", "pass")]
utils::write.csv(
  certification,
  file.path(OUT_DIR, "package1_certification.csv"),
  row.names = FALSE, na = "")
utils::write.csv(
  source_manifest,
  file.path(OUT_DIR, "package1_source_manifest.csv"),
  row.names = FALSE, na = "")

manifest <- data.frame(
  package = "P6_PACKAGE1_LOYO_GRID",
  package_hash = package_hash,
  checks = nrow(certification),
  checks_passed = sum(certification$pass),
  all_pass = all(certification$pass),
  certified_at = as.character(Sys.time()),
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest,
  file.path(OUT_DIR, "package1_certification_manifest.csv"),
  row.names = FALSE, na = "")
print(certification)
print(manifest)
if (!manifest$all_pass) {
  stop(
    "Package 1 terminal certification failed: ",
    paste(certification$check[!certification$pass], collapse = ", "))
}

