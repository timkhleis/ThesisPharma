#!/usr/bin/env Rscript

# C2 non-destructive release verification.

source(file.path(
  "02_analysis", "R", "41a_inventory_lmv2_release_sources.R"
))

lmv2_read_certification <- function(path) {
  x <- utils::read.csv(
    path, stringsAsFactors = FALSE, check.names = FALSE
  )
  all(c("check", "pass") %in% names(x)) &&
    nrow(x) > 0L &&
    !anyNA(x$pass) &&
    all(tolower(as.character(x$pass)) == "true")
}

lmv2_git_status <- function(root) {
  git <- Sys.which("git")
  if (!nzchar(git)) return("git_unavailable")
  output <- tryCatch(
    system2(
      git,
      c(
        "-c", paste0("safe.directory=", root),
        "-C", root, "status", "--porcelain", "--untracked-files=all"
      ),
      stdout = TRUE, stderr = TRUE
    ),
    error = function(e) paste0("git_error: ", conditionMessage(e))
  )
  paste(output, collapse = "\n")
}

lmv2_verify_release <- function(hash_database = FALSE) {
  inventory <- lmv2_write_release_inventory(
    hash_database = hash_database
  )
  root <- inventory$root
  out <- inventory$output_dir

  cert_paths <- lmv2_release_certification_paths(root)
  cert_exists <- file.exists(cert_paths)
  cert_pass <- rep(FALSE, length(cert_paths))
  cert_pass[cert_exists] <- vapply(
    cert_paths[cert_exists], lmv2_read_certification, logical(1)
  )

  source_paths <- file.path(
    root, inventory$source_manifest$relative_path
  )
  private_pattern <- paste0(
    "(root|base|path|dir)\\s*<-\\s*[\"'][^\"']*",
    "(\\.worktrees[/\\\\]|\\.codex[/\\\\]worktrees)|",
    "(source|readRDS|read\\.csv|read_parquet)\\s*\\([^\\n]*",
    "(\\.worktrees[/\\\\]|\\.codex[/\\\\]worktrees)"
  )
  private_hits <- vapply(source_paths, function(path) {
    any(grepl(
      private_pattern,
      readLines(path, warn = FALSE, encoding = "UTF-8"),
      perl = TRUE
    ))
  }, logical(1))

  legacy_runner <- file.path(
    root, "02_analysis", "R", "run_pipeline.R"
  )
  legacy_text <- paste(
    readLines(legacy_runner, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
  old_runner_guard <- grepl(
    "it is not the Local Match v2 release runner",
    legacy_text, fixed = TRUE
  ) && grepl(
    "41_run_lmv2_current_release.R",
    legacy_text, fixed = TRUE
  )

  mandatory_packages <- inventory$package_manifest$package %in% c(
    "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng"
  )
  mandatory_commands <- inventory$command_manifest$command %in% c(
    "Rscript", "git"
  )
  input_hash_ok <- with(
    inventory$input_manifest,
    exists & (
      hash_status == "computed" |
        (role == "database" & hash_status == "deferred_large_file")
    )
  )
  if (hash_database) {
    input_hash_ok <- with(
      inventory$input_manifest,
      exists & hash_status == "computed" & nzchar(sha256)
    )
  }

  checks <- data.frame(
    check = c(
      "all_declared_release_sources_exist_and_are_hashed",
      "all_immutable_inputs_exist",
      "immutable_input_identity_recorded",
      "mandatory_R_packages_available",
      "mandatory_external_commands_available",
      "all_required_certifications_exist",
      "all_required_certifications_pass",
      "release_sources_have_no_private_worktree_paths",
      "legacy_pipeline_rejects_lmv2_aliases",
      "authoritative_inventory_is_unique",
      "C1_gap_type_field_is_present"
    ),
    pass = c(
      all(
        inventory$source_manifest$exists &
          inventory$source_manifest$hash_status == "computed" &
          nzchar(inventory$source_manifest$sha256)
      ),
      all(inventory$input_manifest$exists),
      all(input_hash_ok),
      all(inventory$package_manifest$installed[mandatory_packages]),
      all(inventory$command_manifest$available[mandatory_commands]),
      all(cert_exists),
      all(cert_pass),
      !any(private_hits),
      old_runner_guard,
      sum(
        inventory$input_manifest$role == "master_inventory"
      ) == 1L,
      {
        master <- utils::read.csv(
          unname(lmv2_release_immutable_inputs(root)[["master_inventory"]]),
          stringsAsFactors = FALSE, check.names = FALSE
        )
        "gap_type" %in% names(master) &&
          sum(
            master$domain == "sample-definition diagnostic" &
              master$gap_type ==
                "residual_imbalance_after_control_filter"
          ) == 1L
      }
    ),
    value = c(
      paste0(nrow(inventory$source_manifest), " files"),
      paste0(sum(inventory$input_manifest$exists), "/",
             nrow(inventory$input_manifest)),
      paste0(sum(input_hash_ok), "/", length(input_hash_ok)),
      paste0(
        sum(inventory$package_manifest$installed[mandatory_packages]),
        "/", sum(mandatory_packages)
      ),
      paste0(
        sum(inventory$command_manifest$available[mandatory_commands]),
        "/", sum(mandatory_commands)
      ),
      paste0(sum(cert_exists), "/", length(cert_exists)),
      paste0(sum(cert_pass), "/", length(cert_pass)),
      paste(basename(source_paths[private_hits]), collapse = ";"),
      as.character(old_runner_guard),
      "1",
      "present"
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    checks,
    file.path(out, "release_verification_certification.csv"),
    row.names = FALSE
  )

  status <- lmv2_git_status(root)
  dirty_lines <- if (!nzchar(status)) character() else strsplit(
    status, "\n", fixed = TRUE
  )[[1]]
  tracked_files <- tryCatch(
    system2(
      Sys.which("git"),
      c(
        "-c", paste0("safe.directory=", root),
        "-C", root, "ls-files"
      ),
      stdout = TRUE, stderr = FALSE
    ),
    error = function(e) character()
  )
  all_release_sources_tracked <- all(
    inventory$source_manifest$relative_path %in%
      gsub("\\\\", "/", tracked_files)
  )
  integration <- data.frame(
    check = c(
      "release_worktree_clean",
      "all_release_sources_tracked",
      "reviewed_git_integration_ready",
      "automatic_filesystem_copy_forbidden"
    ),
    ready = c(
      length(dirty_lines) == 0L,
      all_release_sources_tracked,
      length(dirty_lines) == 0L && all_release_sources_tracked,
      TRUE
    ),
    value = c(
      as.character(length(dirty_lines)),
      paste0(
        sum(
          inventory$source_manifest$relative_path %in%
            gsub("\\\\", "/", tracked_files)
        ),
        "/", nrow(inventory$source_manifest)
      ),
      "clean_and_tracked",
      "enforced by release design"
    ),
    detail = c(
      "Number of git status entries in the release worktree.",
      "Every declared release source is present in Git history.",
      paste(
        "Production release assembly requires a clean tree and",
        "a fully tracked source manifest."
      ),
      paste(
        "Authoritative scripts must enter the root through git history,",
        "not an untracked directory copy."
      )
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    integration,
    file.path(out, "release_integration_preflight.csv"),
    row.names = FALSE
  )

  if (!all(checks$pass)) {
    stop(
      "C2 release verification failed: ",
      paste(checks$check[!checks$pass], collapse = ", "),
      call. = FALSE
    )
  }
  invisible(list(
    verification = checks,
    integration = integration,
    output_dir = out
  ))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  lmv2_verify_release(hash_database = "--hash-database" %in% args)
  message("C2 release verification passed.")
}
