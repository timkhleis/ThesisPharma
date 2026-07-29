#!/usr/bin/env Rscript

# C2 source and environment inventory for the Local Match v2 current release.

source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()
release_shared_libs <- c(
  file.path(normalizePath(".", winslash = "/", mustWork = TRUE), ".r_libs"),
  file.path(
    normalizePath(".", winslash = "/", mustWork = TRUE),
    "..", "..", ".r_libs"
  )
)
release_shared_libs <- release_shared_libs[dir.exists(release_shared_libs)]
if (length(release_shared_libs)) {
  .libPaths(unique(c(release_shared_libs, .libPaths())))
}

lmv2_release_root <- function() {
  normalizePath(".", winslash = "/", mustWork = TRUE)
}

lmv2_release_output_dir <- function(root = lmv2_release_root()) {
  file.path(
    root, "02_analysis", "output", "results", "local_match_v2",
    "C2_CURRENT_RELEASE"
  )
}

lmv2_release_source_paths <- function(root = lmv2_release_root()) {
  r_dir <- file.path(root, "02_analysis", "R")
  candidates <- list.files(r_dir, pattern = "\\.R$", full.names = TRUE)
  base <- basename(candidates)
  numbered_lmv2 <- grepl(
    "^(15[a-h]|1[89][a-z]?|2[0-9][a-z]?|3[0-9][a-z]?|4[0-2][a-z]?)_.*lmv2.*\\.R$",
    base
  )
  infrastructure <- base %in% c(
    "00_utils.R", "00_lmv2_visual_style.R", "run_pipeline.R"
  )
  sort(candidates[numbered_lmv2 | infrastructure])
}

lmv2_release_phase <- function(path) {
  prefix <- suppressWarnings(as.integer(substr(basename(path), 1, 2)))
  if (is.na(prefix)) return("infrastructure")
  if (prefix == 15L) return("P0_P2_design")
  if (prefix %in% 18:25) return("P5c_P6_full_cohort")
  if (prefix %in% 26:30) return("P5b_retained")
  if (prefix %in% 31:33) return("heterogeneity")
  if (prefix == 34L) return("C1_inventory")
  if (prefix %in% 35:40) return("post_C1_diagnostics")
  if (prefix == 41L) return("C2_release")
  if (prefix == 42L) return("D1_stayer_descriptives")
  "other"
}

lmv2_release_certification_paths <- function(root = lmv2_release_root()) {
  audit <- file.path(
    root, "02_analysis", "output", "audit", "local_match_v2"
  )
  results <- file.path(
    root, "02_analysis", "output", "results", "local_match_v2"
  )
  c(
    master_inventory = file.path(
      results, "CURRENT_LOCAL_MATCH_V2", "results_inventory",
      "master_results_inventory_certification.csv"
    ),
    reported_values = file.path(
      results, "CURRENT_LOCAL_MATCH_V2", "results_inventory",
      "C1_RESULTS_SYNC_CERTIFICATION.csv"
    ),
    control_endpoint = file.path(
      audit, "C1_CONTROL_ENDPOINT_DIAGNOSTIC",
      "control_endpoint_certification.csv"
    ),
    completion_year = file.path(
      audit, "P6_COMPLETION_YEAR_SENSITIVITY",
      "completion_year_certification.csv"
    ),
    stayer_descriptives = file.path(
      audit, "D1_STAYER_DESCRIPTIVES",
      "d1_stayer_descriptives_certification.csv"
    ),
    exit_decomposition = file.path(
      audit, "P8_EXIT_DECOMPOSITION",
      "exit_decomposition_certification.csv"
    ),
    supervisor_package = file.path(
      results, "supervisor_package", "certification.csv"
    )
  )
}

lmv2_release_immutable_inputs <- function(root = lmv2_release_root()) {
  audit <- file.path(
    root, "02_analysis", "output", "audit", "local_match_v2"
  )
  results <- file.path(
    root, "02_analysis", "output", "results", "local_match_v2"
  )
  c(
    database = file.path(
      root, "02_analysis", "output", "thesis_foundation.duckdb"
    ),
    p5c_manifest = file.path(
      audit, "P6_P5C_PANEL_COUNT_ACTIVE", "p6_manifest.csv"
    ),
    retained_weight_manifest = file.path(
      audit, "P5B_STAYER_S3", "s3_manifest.csv"
    ),
    master_inventory = file.path(
      results, "CURRENT_LOCAL_MATCH_V2", "results_inventory",
      "master_results_inventory.csv"
    )
  )
}

lmv2_hash_manifest <- function(paths, root, role, hash_large = FALSE) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required.", call. = FALSE)
  }
  info <- file.info(paths)
  large <- !is.na(info$size) & info$size > 500 * 1024^2
  sha <- rep(NA_character_, length(paths))
  to_hash <- file.exists(paths) & (!large | hash_large)
  sha[to_hash] <- vapply(
    paths[to_hash], digest::digest, character(1),
    file = TRUE, algo = "sha256"
  )
  data.frame(
    role = role,
    relative_path = ifelse(
      startsWith(normalizePath(
        paths, winslash = "/", mustWork = FALSE
      ), paste0(root, "/")),
      substring(
        normalizePath(paths, winslash = "/", mustWork = FALSE),
        nchar(root) + 2L
      ),
      normalizePath(paths, winslash = "/", mustWork = FALSE)
    ),
    exists = file.exists(paths),
    bytes = unname(info$size),
    modified_utc = format(
      info$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    ),
    sha256 = sha,
    hash_status = ifelse(
      !file.exists(paths), "missing",
      ifelse(large & !hash_large, "deferred_large_file", "computed")
    ),
    stringsAsFactors = FALSE
  )
}

lmv2_write_release_inventory <- function(hash_database = FALSE) {
  root <- lmv2_release_root()
  out <- lmv2_release_output_dir(root)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)

  sources <- lmv2_release_source_paths(root)
  source_manifest <- lmv2_hash_manifest(
    sources, root, "release_source", hash_large = TRUE
  )
  source_manifest$phase <- vapply(
    sources, lmv2_release_phase, character(1)
  )
  utils::write.csv(
    source_manifest,
    file.path(out, "release_source_manifest.csv"),
    row.names = FALSE, na = ""
  )

  inputs <- lmv2_release_immutable_inputs(root)
  input_manifest <- lmv2_hash_manifest(
    inputs, root, names(inputs), hash_large = hash_database
  )
  utils::write.csv(
    input_manifest,
    file.path(out, "release_input_manifest.csv"),
    row.names = FALSE, na = ""
  )

  packages <- c(
    "DBI", "duckdb", "digest", "fixest", "fwildclusterboot",
    "dqrng", "data.table", "ggplot2", "arrow"
  )
  package_manifest <- data.frame(
    package = packages,
    installed = vapply(
      packages, requireNamespace, logical(1), quietly = TRUE
    ),
    version = vapply(packages, function(pkg) {
      if (!requireNamespace(pkg, quietly = TRUE)) return(NA_character_)
      as.character(utils::packageVersion(pkg))
    }, character(1)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    package_manifest,
    file.path(out, "release_package_manifest.csv"),
    row.names = FALSE, na = ""
  )

  commands <- c(
    Rscript = file.path(R.home("bin"), "Rscript.exe"),
    git = Sys.which("git"),
    pdflatex = Sys.which("pdflatex")
  )
  command_manifest <- data.frame(
    command = names(commands),
    path = unname(commands),
    available = nzchar(unname(commands)) & file.exists(unname(commands)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    command_manifest,
    file.path(out, "release_command_manifest.csv"),
    row.names = FALSE
  )

  session <- data.frame(
    field = c(
      "R_version", "platform", "root", "database_hash_mode",
      "created_utc"
    ),
    value = c(
      R.version.string, R.version$platform, root,
      if (hash_database) "sha256" else "size_mtime_only",
      format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    session, file.path(out, "release_environment.csv"),
    row.names = FALSE
  )

  invisible(list(
    root = root, output_dir = out, source_manifest = source_manifest,
    input_manifest = input_manifest, package_manifest = package_manifest,
    command_manifest = command_manifest
  ))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  lmv2_write_release_inventory(
    hash_database = "--hash-database" %in% args
  )
  message("C2 release inventory written.")
}
