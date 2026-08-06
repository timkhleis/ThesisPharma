# Restartable, memory-aware P5.3 final production runner.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE, default = NA_character_) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(default)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

mode <- read_arg("production-mode")
db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
audit_root <- read_arg("audit-root")
p3_manifest_path <- normalizePath(
  read_arg("p3-manifest"), winslash = "/", mustWork = TRUE)
cohorts <- unique(as.integer(strsplit(
  read_arg("cohorts"), ",", fixed = TRUE)[[1]]))
if (!length(cohorts) || anyNA(cohorts) ||
    any(!cohorts %in% 1993:2010)) {
  stop("--cohorts= must be a subset of 1993:2010")
}

run_worker <- function(cohort) {
  BASE <- normalizePath("02_analysis", mustWork = TRUE)
  assign("BASE", BASE, envir = .GlobalEnv)
  source(file.path(
    BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
  source(file.path(
    BASE, "R", "17x_lmv2_p5_sparse_technology_cache.R"))
  lmv2_install_p5_sparse_cache()
  source(file.path(
    BASE, "R", "18f_lmv2_p5_selected_acceleration.R"))
  source(file.path(
    BASE, "R", "18j_lmv2_p5_newton_solver.R"))
  source(file.path(
    BASE, "R", "19a_lmv2_p5_rescue_config.R"))
  source(file.path(
    BASE, "R", "18n_lmv2_p5_weight_materialization.R"))
  source(file.path(
    BASE, "R", "19f_lmv2_p5_rescue_dependence_diagnostics.R"))
  source(file.path(
    BASE, "R", "19i_lmv2_p5_final_production_config.R"))

  STAGE1_CALIPERS <<-
    LMV2_P5_PRODUCTION$selected$stage1_caliper
  STAGE1_PROFILES <<-
    LMV2_P5_PRODUCTION$selected$profile
  STAGE2_CALIPER <<-
    LMV2_P5_PRODUCTION$selected$stage2_caliper
  UNIVERSES <<- LMV2_P5_PRODUCTION$selected$universe
  SCHEMES <<- LMV2_P5_PRODUCTION$selected$schemes
  COHORTS <<- as.integer(cohort)
  LMV2_DISKBACKED_COHORTS <<- as.integer(cohort)
  LMV2_P5_SOLVER <<- LMV2_P5_PRODUCTION$selected$solver
  MIN_ELIGIBLE_FIRMS <<-
    LMV2_P5_RESCUE$inventor_first$minimum_stage1_firms
  lmv2_p5_production_apply()
  lmv2_install_p5_selected_acceleration()
  lmv2_install_p5_newton_solver()

  p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
  execution_hash <- lmv2_p5_production_execution_hash(
    BASE, p3_hash)
  # The core runner uses this function for every sparse-cache and profile-row
  # provenance check. Override it only after the selected implementation is
  # installed so the final freeze hash enters every production checkpoint.
  assign(
    "lmv2_composite_execution_hash",
    function(base_dir, p3_manifest_hash) execution_hash,
    envir = .GlobalEnv)

  cohort_dir <- file.path(
    audit_root, sprintf("cohort_%d", as.integer(cohort)))
  dir.create(cohort_dir, recursive = TRUE, showWarnings = FALSE)
  lmv2_install_p5_weight_materializer(
    audit_dir = cohort_dir,
    execution_hash = execution_hash,
    analysis_scope = "main",
    dealsim_tercile = NA_integer_)
  lmv2_install_p5_rescue_dependence_diagnostics(
    audit_dir = cohort_dir,
    execution_hash = execution_hash)

  manifest <- data.frame(
    timestamp = as.character(Sys.time()),
    version = LMV2_P5_PRODUCTION_VERSION,
    production_freeze_hash =
      LMV2_P5_PRODUCTION_FREEZE_SHA256,
    rescue_amendment_hash =
      LMV2_P5_RESCUE_AMENDMENT_SHA256,
    industry_support_amendment_hash =
      LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256,
    execution_hash = execution_hash,
    cohort = as.integer(cohort),
    universe = UNIVERSES,
    profile = STAGE1_PROFILES,
    stage1_caliper = STAGE1_CALIPERS,
    stage2_caliper = STAGE2_CALIPER,
    distance_variables = paste(
      LMV2_P3$stage_2$scalar_variables, collapse = ";"),
    balance_variables = paste(
      LMV2_HYBRID_INV_VARS, collapse = ";"),
    schemes = paste(SCHEMES, collapse = ";"),
    solver = LMV2_P5_SOLVER,
    outcome_boundary = LMV2_P5_PRODUCTION$outcome_boundary,
    stringsAsFactors = FALSE)
  utils::write.csv(
    manifest,
    file.path(cohort_dir, "p5_production_manifest.csv"),
    row.names = FALSE)

  run_cohort_hybrid_pilot(
    db_path, cohort_dir, p3_manifest_path,
    cohorts_to_run = as.integer(cohort))

  diagnostic_path <- file.path(
    cohort_dir,
    sprintf("cohort_hybrid_diagnostics_%d.csv", cohort))
  diagnostics <- utils::read.csv(
    diagnostic_path, stringsAsFactors = FALSE)
  status <- lmv2_p5_production_scheme_status(diagnostics)
  primary <- status[status$scheme == "primary", , drop = FALSE]
  if (nrow(primary) != 1L || !isTRUE(primary$feasible[[1]])) {
    stop(
      "Frozen primary design failed balance/ESS for cohort ", cohort,
      "; no automatic design change is authorized")
  }
  invisible(diagnostics)
}

if (identical(mode, "worker")) {
  if (length(cohorts) != 1L) {
    stop("Worker mode requires exactly one cohort")
  }
  run_worker(cohorts[[1]])
  message("P5.3 production worker complete: cohort ", cohorts[[1]])
} else if (identical(mode, "schedule")) {
  if (!requireNamespace("processx", quietly = TRUE) ||
      !requireNamespace("ps", quietly = TRUE)) {
    stop("Scheduler requires processx and ps")
  }
  max_workers <- as.integer(read_arg(
    "max-workers", required = FALSE, default = "2"))
  if (!max_workers %in% 1:2) {
    stop("--max-workers= must be 1 or 2")
  }
  min_start_gb <- 12
  critical_gb <- 4
  critical_polls <- 0L
  dir.create(audit_root, recursive = TRUE, showWarnings = FALSE)
  audit_root <- normalizePath(
    audit_root, winslash = "/", mustWork = TRUE)
  runner <- normalizePath(
    file.path(
      "02_analysis", "R",
      "19j_run_lmv2_p5_final_production.R"),
    winslash = "/", mustWork = TRUE)
  rscript <- file.path(R.home("bin"), "Rscript.exe")
  if (!file.exists(rscript)) {
    rscript <- file.path(R.home("bin"), "Rscript")
  }
  state <- data.frame(
    cohort = cohorts, status = "pending", attempts = 0L,
    pid = NA_integer_, started = NA_character_,
    finished = NA_character_, exit_status = NA_integer_,
    reason = NA_character_, stringsAsFactors = FALSE)
  workers <- list()
  status_path <- file.path(audit_root, "scheduler_status.csv")

  write_status <- function() {
    temporary <- tempfile(
      "scheduler_status_", tmpdir = audit_root, fileext = ".tmp")
    utils::write.csv(state, temporary, row.names = FALSE)
    if (file.exists(status_path) && !file.remove(status_path)) {
      stop("Could not replace scheduler status")
    }
    if (!file.rename(temporary, status_path)) {
      stop("Could not atomically commit scheduler status")
    }
  }
  available_gb <- function() {
    as.numeric(ps::ps_system_memory()[["avail"]]) / 1024^3
  }
  start_worker <- function(i) {
    cohort <- state$cohort[[i]]
    cohort_dir <- file.path(
      audit_root, sprintf("cohort_%d", cohort))
    dir.create(cohort_dir, recursive = TRUE, showWarnings = FALSE)
    worker_args <- c(
      runner, "--production-mode=worker",
      paste0("--db=", db_path),
      paste0("--audit-root=", audit_root),
      paste0("--p3-manifest=", p3_manifest_path),
      paste0("--cohorts=", cohort))
    process <- processx::process$new(
      rscript, worker_args, wd = getwd(),
      stdout = file.path(cohort_dir, "stdout.log"),
      stderr = file.path(cohort_dir, "stderr.log"),
      cleanup_tree = TRUE)
    state$status[[i]] <<- "running"
    state$attempts[[i]] <<- state$attempts[[i]] + 1L
    state$pid[[i]] <<- process$get_pid()
    state$started[[i]] <<- as.character(Sys.time())
    state$finished[[i]] <<- NA_character_
    state$exit_status[[i]] <<- NA_integer_
    state$reason[[i]] <<- NA_character_
    workers[[as.character(cohort)]] <<- process
    write_status()
    message(
      "Started cohort ", cohort, " (pid ", process$get_pid(),
      ", available RAM ", sprintf("%.1f GB", available_gb()), ")")
  }
  finish_worker <- function(i, status, exit_status, reason = NA_character_) {
    cohort <- state$cohort[[i]]
    state$status[[i]] <<- status
    state$finished[[i]] <<- as.character(Sys.time())
    state$exit_status[[i]] <<- exit_status
    state$reason[[i]] <<- reason
    state$pid[[i]] <<- NA_integer_
    workers[[as.character(cohort)]] <<- NULL
    write_status()
  }

  write_status()
  repeat {
    for (i in which(state$status == "running")) {
      process <- workers[[as.character(state$cohort[[i]])]]
      if (!process$is_alive()) {
        exit_status <- process$get_exit_status()
        if (identical(exit_status, 0L)) {
          finish_worker(i, "complete", exit_status)
          message("Completed cohort ", state$cohort[[i]])
        } else {
          finish_worker(
            i, "failed", exit_status,
            paste0("worker_exit_", exit_status))
          message(
            "Stopped for review: cohort ", state$cohort[[i]],
            " exited with status ", exit_status)
        }
      }
    }
    if (all(state$status %in% c("complete", "failed"))) break

    running <- which(state$status == "running")
    if (length(running) >= 2L && available_gb() < critical_gb) {
      critical_polls <- critical_polls + 1L
    } else {
      critical_polls <- 0L
    }
    if (critical_polls >= 3L) {
      newest <- running[which.max(
        as.POSIXct(state$started[running]))]
      cohort <- state$cohort[[newest]]
      workers[[as.character(cohort)]]$kill_tree()
      state$status[[newest]] <- "pending"
      state$pid[[newest]] <- NA_integer_
      state$reason[[newest]] <- "memory_guard_requeued"
      workers[[as.character(cohort)]] <- NULL
      critical_polls <- 0L
      write_status()
      message("Requeued cohort ", cohort, " after memory guard")
    }

    running_n <- sum(state$status == "running")
    pending <- which(state$status == "pending")
    while (running_n < max_workers && length(pending)) {
      if (running_n >= 1L && available_gb() < min_start_gb) break
      start_worker(pending[[1]])
      running_n <- running_n + 1L
      pending <- which(state$status == "pending")
    }
    Sys.sleep(2)
  }
  if (any(state$status == "failed")) {
    stop(
      "One or more cohorts require design review; see ", status_path)
  }
  message(
    "P5.3 production scheduler complete: ",
    paste(state$cohort, collapse = ", "))
} else {
  stop("--production-mode= must be worker or schedule")
}
