# Local-match-v2 P5b stayer design: configuration and provenance helpers.
#
# This package is intentionally additive. It reads the authoritative P2
# interfaces but does not modify the frozen P5a/P5c roster or weights.

LMV2_STAYER_VERSION <- "lmv2_p5b_stayer_s0_s2_1993_amendment_v1"

lmv2_stayer_existing_path <- function(candidates, label) {
  hits <- candidates[file.exists(candidates) | dir.exists(candidates)]
  if (length(hits) == 0L) {
    stop(
      "Could not locate ", label, ". Checked:\n",
      paste(" -", candidates, collapse = "\n"))
  }
  normalizePath(hits[[1L]], winslash = "/", mustWork = TRUE)
}

lmv2_stayer_config <- function(base = getwd()) {
  base <- normalizePath(base, winslash = "/", mustWork = TRUE)
  foundation_candidates <- unique(c(
    Sys.getenv("LMV2_FOUNDATION_ROOT"),
    base
  ))
  foundation_candidates <- foundation_candidates[nzchar(foundation_candidates)]
  foundation_root <- lmv2_stayer_existing_path(
    file.path(foundation_candidates, "02_analysis", "output",
              "thesis_foundation.duckdb"),
    "the foundation database on the consolidated main branch")

  output_dir <- file.path(
    base, "02_analysis", "output", "audit",
    "local_match_v2_1993_amendment",
    "P5B_STAYER_S0_S2")

  list(
    version = LMV2_STAYER_VERSION,
    base = base,
    foundation_db = foundation_root,
    output_dir = output_dir,
    primary_window = c(1L, 5L),
    timing_sensitivity_window = c(2L, 5L),
    power = list(
      minimum_retained_inventors = 3000L,
      minimum_retained_deals = 150L,
      minimum_raw_effective_deals = 20
    ),
    continuity = list(
      minimum_post_inventors = 5L,
      modal_outside_share = 0.50,
      maximum_same_group_share = 0.25,
      maximum_affected_post_share = 0.01
    ),
    unresolved_share_maximum = 0.005,
    source_files = file.path(
      base, "02_analysis", "R",
      c(
        "26a_lmv2_stayer_config.R",
        "26b_build_lmv2_stayer_s0_s2.R",
        "26c_certify_lmv2_stayer_s0_s2.R",
        "26_run_lmv2_stayer_s0_s2.R"
      )
    ),
    freeze_file = file.path(
      base, "02_analysis", "notes",
      "local_match_v2_p5b_stayer_preanalysis_freeze.md")
  )
}

lmv2_sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}

lmv2_git_blob_hash <- function(path) {
  if (!file.exists(path)) stop("Cannot hash missing file: ", path)
  out <- system2(
    "git", c("hash-object", shQuote(normalizePath(
      path, winslash = "/", mustWork = TRUE))),
    stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop("git hash-object failed for ", path, ":\n", paste(out, collapse = "\n"))
  }
  hash <- trimws(out[[length(out)]])
  if (!grepl("^[0-9a-f]{40}$", hash)) {
    stop("Unexpected git hash-object output for ", path, ": ", hash)
  }
  hash
}

lmv2_composite_source_hash <- function(paths) {
  paths <- normalizePath(paths, winslash = "/", mustWork = TRUE)
  entries <- paste(basename(paths), vapply(
    paths, lmv2_git_blob_hash, character(1)), sep = "=")
  manifest <- tempfile(fileext = ".txt")
  on.exit(unlink(manifest), add = TRUE)
  writeLines(entries, manifest, useBytes = TRUE)
  lmv2_git_blob_hash(manifest)
}

lmv2_hash_tooth_test <- function() {
  probe <- tempfile(fileext = ".txt")
  on.exit(unlink(probe), add = TRUE)
  writeLines("before", probe, useBytes = TRUE)
  before <- lmv2_git_blob_hash(probe)
  writeLines("after", probe, useBytes = TRUE)
  after <- lmv2_git_blob_hash(probe)
  !identical(before, after)
}

lmv2_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(x, path, row.names = FALSE, na = "")
  invisible(path)
}
