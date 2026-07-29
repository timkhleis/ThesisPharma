#!/usr/bin/env Rscript

# C2 deterministic smoke reproduction from clean R subprocesses.

source(file.path(
  "02_analysis", "R", "41b_verify_lmv2_release_dependencies.R"
))

lmv2_run_smoke <- function(hash_database = FALSE) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required.", call. = FALSE)
  }
  root <- lmv2_release_root()
  out <- lmv2_release_output_dir(root)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  rscript <- file.path(R.home("bin"), "Rscript.exe")
  scripts <- file.path(
    "02_analysis", "R",
    c(
      "34_build_lmv2_master_results_inventory.R",
      "34b_validate_lmv2_reported_values.R"
    )
  )
  master <- unname(
    lmv2_release_immutable_inputs(root)[["master_inventory"]]
  )
  before_hash <- if (file.exists(master)) {
    digest::digest(file = master, algo = "sha256")
  } else {
    NA_character_
  }

  log_lines <- character()
  statuses <- integer(length(scripts))
  for (i in seq_along(scripts)) {
    started <- Sys.time()
    output <- system2(
      rscript, scripts[[i]], stdout = TRUE, stderr = TRUE
    )
    status_i <- attr(output, "status")
    if (is.null(status_i)) status_i <- 0L
    statuses[[i]] <- status_i
    log_lines <- c(
      log_lines,
      paste0("SCRIPT: ", scripts[[i]]),
      paste0("STARTED_UTC: ",
             format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
      output,
      paste0("STATUS: ", statuses[[i]]),
      ""
    )
  }
  writeLines(
    log_lines, file.path(out, "release_smoke.log"),
    useBytes = TRUE
  )

  after_hash <- if (file.exists(master)) {
    digest::digest(file = master, algo = "sha256")
  } else {
    NA_character_
  }
  verification <- lmv2_verify_release(
    hash_database = hash_database
  )

  checks <- data.frame(
    check = c(
      "inventory_builder_clean_session_passes",
      "reported_value_gate_clean_session_passes",
      "master_inventory_rebuild_is_deterministic",
      "release_verification_passes"
    ),
    pass = c(
      statuses[[1]] == 0L,
      statuses[[2]] == 0L,
      !is.na(before_hash) && identical(before_hash, after_hash),
      all(verification$verification$pass)
    ),
    value = c(
      as.character(statuses[[1]]),
      as.character(statuses[[2]]),
      paste(before_hash, after_hash, sep = " == "),
      paste0(
        sum(verification$verification$pass), "/",
        nrow(verification$verification)
      )
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    checks,
    file.path(out, "release_smoke_certification.csv"),
    row.names = FALSE
  )
  if (!all(checks$pass)) {
    stop(
      "C2 smoke failed: ",
      paste(checks$check[!checks$pass], collapse = ", "),
      call. = FALSE
    )
  }
  invisible(checks)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  lmv2_run_smoke(hash_database = "--hash-database" %in% args)
  message("C2 smoke reproduction passed.")
}
