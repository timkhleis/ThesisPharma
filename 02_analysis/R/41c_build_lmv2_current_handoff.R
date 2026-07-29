#!/usr/bin/env Rscript

# C2 builds a compact, versioned handoff staging directory. It deliberately
# does not replace CURRENT_LOCAL_MATCH_V2 or copy the 2.6 GB database.

source(file.path(
  "02_analysis", "R", "41b_verify_lmv2_release_dependencies.R"
))

lmv2_handoff_file_map <- function(root, release_out) {
  audit <- file.path(
    root, "02_analysis", "output", "audit", "local_match_v2"
  )
  results <- file.path(
    root, "02_analysis", "output", "results", "local_match_v2"
  )
  inventory_dir <- file.path(
    results, "CURRENT_LOCAL_MATCH_V2", "results_inventory"
  )

  add_tree <- function(source_dir, destination_dir, category) {
    files <- list.files(source_dir, recursive = TRUE, full.names = TRUE)
    files <- files[file.info(files)$isdir %in% FALSE]
    data.frame(
      source = files,
      destination = file.path(
        destination_dir,
        substring(
          normalizePath(files, winslash = "/", mustWork = TRUE),
          nchar(normalizePath(
            source_dir, winslash = "/", mustWork = TRUE
          )) + 2L
        )
      ),
      category = category,
      stringsAsFactors = FALSE
    )
  }

  maps <- list(
    data.frame(
      source = lmv2_release_source_paths(root),
      destination = file.path(
        "02_Code", basename(lmv2_release_source_paths(root))
      ),
      category = "release_source",
      stringsAsFactors = FALSE
    ),
    add_tree(
      inventory_dir, file.path("04_Results", "results_inventory"),
      "authoritative_inventory"
    ),
    add_tree(
      file.path(audit, "C1_CONTROL_ENDPOINT_DIAGNOSTIC"),
      file.path("04_Results", "control_endpoint_diagnostic"),
      "C1_diagnostic"
    ),
    add_tree(
      file.path(audit, "P6_COMPLETION_YEAR_SENSITIVITY"),
      file.path("04_Results", "completion_year_sensitivity"),
      "completion_year_sensitivity"
    ),
    add_tree(
      file.path(audit, "D1_STAYER_DESCRIPTIVES"),
      file.path("04_Results", "D1_stayer_descriptives", "audit"),
      "D1_stayer_descriptives"
    ),
    add_tree(
      file.path(results, "D1_STAYER_DESCRIPTIVES"),
      file.path("04_Results", "D1_stayer_descriptives", "results"),
      "D1_stayer_descriptives"
    ),
    add_tree(
      file.path(audit, "P8_EXIT_DECOMPOSITION"),
      file.path("04_Results", "P8_exit_decomposition"),
      "P8_decomposition"
    ),
    add_tree(
      file.path(results, "supervisor_package"),
      file.path("04_Results", "supervisor_package"),
      "supervisor_package"
    ),
    add_tree(
      release_out, "06_Environment", "C2_release_metadata"
    )
  )

  notes <- file.path(
    root, "02_analysis", "notes",
    c(
      "current_local_match_v2_start_here.md",
      "local_match_v2_master_results_inventory.md",
      "local_match_v2_stayer_heterogeneity_results.md",
      "local_match_v2_control_endpoint_diagnostic_results.md",
      "local_match_v2_remaining_stayer_packages_plan.md",
      "local_match_v2_stayer_network_implementation_plan.md",
      "local_match_v2_stayer_descriptive_freeze.md",
      "local_match_v2_stayer_descriptive_results.md",
      "local_match_v2_current_release_implementation.md"
    )
  )
  maps[[length(maps) + 1L]] <- data.frame(
    source = notes,
    destination = file.path("03_Current_notes", basename(notes)),
    category = "current_note",
    stringsAsFactors = FALSE
  )

  main_candidate <- normalizePath(
    file.path(root, "..", ".."), winslash = "/", mustWork = TRUE
  )
  main_root <- if (file.exists(file.path(
    main_candidate, "thesis_template", "main.tex"
  ))) main_candidate else root
  thesis_files <- c(
    file.path(
      main_root, "00_Discussion_Docs",
      "013_research_partner_thesis_vision_handover.tex"
    ),
    file.path(
      main_root, "00_Discussion_Docs",
      "014_research_partner_progress_update_2026-07-29.tex"
    ),
    file.path(
      main_root, "00_Discussion_Docs",
      "014_research_partner_progress_update_2026-07-29.pdf"
    ),
    file.path(main_root, "thesis_template", "main.tex")
  )
  maps[[length(maps) + 1L]] <- data.frame(
    source = thesis_files,
    destination = file.path("05_Thesis", basename(thesis_files)),
    category = "thesis_asset",
    stringsAsFactors = FALSE
  )

  map <- do.call(rbind, maps)
  map <- map[!duplicated(map$destination), , drop = FALSE]
  map
}

lmv2_build_handoff <- function(replace_staging = FALSE) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required.", call. = FALSE)
  }
  verification <- lmv2_verify_release(hash_database = FALSE)
  root <- lmv2_release_root()
  release_out <- verification$output_dir
  staging <- file.path(
    release_out, "CURRENT_LOCAL_MATCH_V2_STAGING"
  )
  if (dir.exists(staging) && !replace_staging) {
    stop(
      "Handoff staging already exists. Use --replace-staging explicitly.",
      call. = FALSE
    )
  }
  if (dir.exists(staging)) {
    unlink(staging, recursive = TRUE, force = TRUE)
  }
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)

  map <- lmv2_handoff_file_map(root, release_out)
  if (any(!file.exists(map$source))) {
    stop(
      "Missing handoff source(s): ",
      paste(map$source[!file.exists(map$source)], collapse = ", "),
      call. = FALSE
    )
  }
  source_size <- file.info(map$source)$size
  if (any(source_size > 500 * 1024^2)) {
    stop("Handoff map unexpectedly includes a file above 500 MB.")
  }

  for (i in seq_len(nrow(map))) {
    destination <- file.path(staging, map$destination[[i]])
    dir.create(
      dirname(destination), recursive = TRUE, showWarnings = FALSE
    )
    if (!file.copy(
      map$source[[i]], destination,
      overwrite = FALSE, copy.mode = TRUE, copy.date = TRUE
    )) {
      stop("Failed to copy handoff file: ", map$source[[i]])
    }
  }

  source_hash <- vapply(
    map$source, digest::digest, character(1),
    file = TRUE, algo = "sha256"
  )
  destination_path <- file.path(staging, map$destination)
  destination_hash <- vapply(
    destination_path, digest::digest, character(1),
    file = TRUE, algo = "sha256"
  )
  manifest <- data.frame(
    category = map$category,
    destination = gsub("\\\\", "/", map$destination),
    source_sha256 = source_hash,
    destination_sha256 = destination_hash,
    bytes = unname(file.info(destination_path)$size),
    matches = source_hash == destination_hash,
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    manifest, file.path(staging, "handoff_manifest.csv"),
    row.names = FALSE
  )

  start_here <- c(
    "# Local Match v2 current release",
    "",
    "From the thesis root, verify the release with:",
    "",
    "```powershell",
    "& 'C:\\Program Files\\R\\R-4.5.1\\bin\\Rscript.exe' 02_analysis\\R\\41_run_lmv2_current_release.R --verify",
    "```",
    "",
    "Run the deterministic reporting smoke test with `--smoke`.",
    "After reviewed Git integration, run the certified release assembly with",
    "`--production`; it requires a clean tree and fully tracked source set.",
    "The database is not duplicated in this compact handoff. Its size,",
    "timestamp, and optional SHA-256 are recorded under `06_Environment`.",
    "The master results inventory under `04_Results/results_inventory` is",
    "the numerical authority.",
    "",
    "This staging handoff was assembled from the current tracked release."
  )
  writeLines(
    start_here, file.path(staging, "START_HERE.md"),
    useBytes = TRUE
  )

  checks <- data.frame(
    check = c(
      "all_mapped_files_copied",
      "all_copied_hashes_match",
      "database_binary_not_duplicated",
      "authoritative_inventory_hash_matches",
      "staging_does_not_replace_current_handoff"
    ),
    pass = c(
      all(file.exists(destination_path)),
      all(manifest$matches),
      !any(grepl("\\.duckdb$", manifest$destination)),
      {
        inventory_rows <- manifest[
          basename(manifest$destination) ==
            "master_results_inventory.csv", ,
          drop = FALSE
        ]
        nrow(inventory_rows) == 1L && inventory_rows$matches[[1]]
      },
      !identical(
        normalizePath(
          staging, winslash = "/", mustWork = TRUE
        ),
        normalizePath(
          file.path(
            root, "02_analysis", "output", "results",
            "local_match_v2", "CURRENT_LOCAL_MATCH_V2"
          ),
          winslash = "/", mustWork = TRUE
        )
      )
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    checks, file.path(staging, "handoff_certification.csv"),
    row.names = FALSE
  )
  if (!all(checks$pass)) {
    stop(
      "C2 handoff certification failed: ",
      paste(checks$check[!checks$pass], collapse = ", ")
    )
  }
  invisible(list(staging = staging, checks = checks))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  built <- lmv2_build_handoff(
    replace_staging = "--replace-staging" %in% args
  )
  message("C2 handoff staging built: ", built$staging)
}
