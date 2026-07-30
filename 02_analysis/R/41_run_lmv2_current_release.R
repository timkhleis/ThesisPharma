#!/usr/bin/env Rscript

# Root entry point for the Local Match v2 current release.

args <- commandArgs(trailingOnly = TRUE)
modes <- intersect(
  args, c("--verify", "--smoke", "--production", "--handoff-only")
)
if (length(modes) != 1L) {
  stop(
    paste(
      "Choose exactly one mode: --verify, --smoke, --production,",
      "or --handoff-only."
    ),
    call. = FALSE
  )
}
hash_database <- "--hash-database" %in% args

if (modes == "--verify") {
  source(file.path(
    "02_analysis", "R",
    "41b_verify_lmv2_release_dependencies.R"
  ))
  lmv2_verify_release(hash_database = hash_database)
  message("Local Match v2 release verification passed.")
} else if (modes == "--smoke") {
  source(file.path(
    "02_analysis", "R", "41d_smoke_lmv2_current_release.R"
  ))
  lmv2_run_smoke(hash_database = hash_database)
  message("Local Match v2 smoke reproduction passed.")
} else if (modes == "--handoff-only") {
  source(file.path(
    "02_analysis", "R",
    "41c_build_lmv2_current_handoff.R"
  ))
  built <- lmv2_build_handoff(
    replace_staging = "--replace-staging" %in% args
  )
  message("Local Match v2 handoff staging built: ", built$staging)
} else {
  source(file.path(
    "02_analysis", "R",
    "41d_smoke_lmv2_current_release.R"
  ))
  source(file.path(
    "02_analysis", "R",
    "41c_build_lmv2_current_handoff.R"
  ))
  preflight <- lmv2_verify_release(hash_database = hash_database)
  integration_ready <- with(
    preflight$integration,
    ready[check == "reviewed_git_integration_ready"]
  )
  if (length(integration_ready) != 1L || !integration_ready) {
    stop(
      paste(
        "Production mode requires a clean release worktree and every",
        "declared release source tracked in Git. Commit or restore the",
        "worktree, then re-run --production."
      ),
      call. = FALSE
    )
  }

  rscript <- file.path(R.home("bin"), "Rscript.exe")
  production_scripts <- file.path(
    "02_analysis", "R",
    c(
      "40e_certify_lmv2_completion_year_window.R",
      "34a_run_lmv2_control_endpoint_diagnostic.R",
      "42_run_lmv2_stayer_descriptives.R",
      "43_run_lmv2_network_census.R",
      "47_run_lmv2_n4_team_recomposition.R",
      "34_build_lmv2_master_results_inventory.R",
      "34b_validate_lmv2_reported_values.R"
    )
  )
  release_out <- lmv2_release_output_dir()
  dir.create(release_out, recursive = TRUE, showWarnings = FALSE)
  production_log <- character()
  for (script in production_scripts) {
    started <- Sys.time()
    output <- system2(
      rscript, script, stdout = TRUE, stderr = TRUE
    )
    status <- attr(output, "status")
    if (is.null(status)) status <- 0L
    production_log <- c(
      production_log,
      paste0("SCRIPT: ", script),
      paste0(
        "STARTED_UTC: ",
        format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      ),
      output,
      paste0("STATUS: ", status),
      ""
    )
    if (status != 0L) {
      writeLines(
        production_log,
        file.path(release_out, "release_production.log"),
        useBytes = TRUE
      )
      stop("Production script failed: ", script, call. = FALSE)
    }
  }
  writeLines(
    production_log,
    file.path(release_out, "release_production.log"),
    useBytes = TRUE
  )

  smoke <- lmv2_run_smoke(hash_database = hash_database)
  handoff <- lmv2_build_handoff(replace_staging = TRUE)
  final_verification <- lmv2_verify_release(
    hash_database = hash_database
  )
  production_certification <- data.frame(
    check = c(
      "integration_preflight_passed",
      "production_scripts_passed",
      "smoke_reproduction_passed",
      "handoff_certification_passed",
      "final_release_verification_passed"
    ),
    pass = c(
      integration_ready,
      TRUE,
      all(smoke$pass),
      all(handoff$checks$pass),
      all(final_verification$verification$pass)
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    production_certification,
    file.path(release_out, "release_production_certification.csv"),
    row.names = FALSE
  )
  if (!all(production_certification$pass)) {
    stop("C2 production certification failed.", call. = FALSE)
  }
  message(
    "Local Match v2 production release passed. Handoff: ",
    handoff$staging
  )
}
