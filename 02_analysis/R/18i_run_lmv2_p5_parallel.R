# Memory-aware cohort scheduler for the selected P5 specification.
#
# Each cohort has an isolated audit/cache directory. At most two workers run
# concurrently. If system-available memory stays below the critical floor for
# three polls, the newest worker is stopped and requeued; its atomic
# checkpoints are reused after the older worker completes.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE, default = NA_character_) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(default)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

db_path <- normalizePath(read_arg("db"), winslash = "/", mustWork = TRUE)
audit_root <- read_arg("audit-root")
p3_manifest <- normalizePath(
  read_arg("p3-manifest"), winslash = "/", mustWork = TRUE)
cohorts <- unique(as.integer(
  strsplit(read_arg("cohorts"), ",", fixed = TRUE)[[1]]))
caliper <- as.numeric(read_arg("caliper"))
profile <- read_arg("profile")
universe <- read_arg("universe")
schemes <- read_arg(
  "schemes", required = FALSE, default = "primary,equal_deal")
solver <- read_arg(
  "solver", required = FALSE, default = "newton")
analysis_scope <- read_arg(
  "analysis-scope", required = FALSE, default = "main")
dealsim_tercile <- as.integer(read_arg(
  "dealsim-tercile", required = FALSE, default = NA_character_))
dealsim_map <- read_arg(
  "dealsim-map", required = FALSE, default = NA_character_)
max_workers <- as.integer(read_arg(
  "max-workers", required = FALSE, default = "2"))
min_start_gb <- as.numeric(read_arg(
  "min-start-available-gb", required = FALSE, default = "12"))
critical_gb <- as.numeric(read_arg(
  "critical-available-gb", required = FALSE, default = "4"))

if (!length(cohorts) || anyNA(cohorts)) {
  stop("--cohorts= must contain integer cohort years")
}
if (!max_workers %in% 1:2) {
  stop("--max-workers= must be 1 or 2")
}
if (!solver %in% c("weightit", "newton")) {
  stop("--solver= must be weightit or newton")
}
if (!analysis_scope %in% c("main", "dealsim_tercile")) {
  stop("--analysis-scope= must be main or dealsim_tercile")
}
if (identical(analysis_scope, "dealsim_tercile")) {
  if (is.na(dealsim_tercile) || !dealsim_tercile %in% 1:3 ||
      is.na(dealsim_map)) {
    stop(
      "DealSim scope requires --dealsim-tercile=1|2|3 and ",
      "--dealsim-map=...")
  }
  dealsim_map <- normalizePath(
    dealsim_map, winslash = "/", mustWork = TRUE)
  map <- utils::read.csv(dealsim_map, stringsAsFactors = FALSE)
  available_cohorts <- unique(as.integer(map$cohort[
    !is.na(map$dealsim_tercile) &
      map$dealsim_tercile == dealsim_tercile]))
  cohorts <- cohorts[cohorts %in% available_cohorts]
  if (!length(cohorts)) {
    stop("No requested cohort has a deal in the requested DealSim tercile")
  }
} else if (!is.na(dealsim_tercile) || !is.na(dealsim_map)) {
  stop("Main scope cannot receive DealSim tercile arguments")
}
if (!is.finite(min_start_gb) || !is.finite(critical_gb) ||
    min_start_gb <= critical_gb || critical_gb <= 0) {
  stop("Memory floors must satisfy min-start > critical > 0")
}
if (!requireNamespace("processx", quietly = TRUE) ||
    !requireNamespace("ps", quietly = TRUE)) {
  stop("The processx and ps packages are required")
}

dir.create(audit_root, recursive = TRUE, showWarnings = FALSE)
audit_root <- normalizePath(audit_root, winslash = "/", mustWork = TRUE)
base_dir <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
runner <- file.path(base_dir, "R", "18g_run_lmv2_p5_selected.R")
rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) {
  rscript <- file.path(R.home("bin"), "Rscript")
}

state <- data.frame(
  cohort = cohorts, status = "pending", attempts = 0L,
  pid = NA_integer_, started = NA_character_, finished = NA_character_,
  exit_status = NA_integer_, reason = NA_character_,
  stringsAsFactors = FALSE)
workers <- list()
critical_polls <- 0L

status_path <- file.path(audit_root, "scheduler_status.csv")
write_status <- function() {
  tmp <- paste0(status_path, ".tmp_", Sys.getpid())
  utils::write.csv(state, tmp, row.names = FALSE)
  if (file.exists(status_path)) file.remove(status_path)
  if (!file.rename(tmp, status_path)) {
    stop("Could not atomically update scheduler status")
  }
}

available_gb <- function() {
  as.numeric(ps::ps_system_memory()[["avail"]]) / 1024^3
}

start_worker <- function(i) {
  g <- state$cohort[i]
  cohort_dir <- file.path(audit_root, sprintf("cohort_%d", g))
  dir.create(cohort_dir, recursive = TRUE, showWarnings = FALSE)
  worker_args <- c(
    runner,
    "--selected-mode=production",
    paste0("--db=", db_path),
    paste0("--audit-dir=", cohort_dir),
    paste0("--p3-manifest=", p3_manifest),
    paste0("--cohorts=", g),
    paste0("--caliper=", caliper),
      paste0("--profile=", profile),
      paste0("--universe=", universe),
      paste0("--schemes=", schemes),
      paste0("--solver=", solver),
      paste0("--analysis-scope=", analysis_scope))
  if (identical(analysis_scope, "dealsim_tercile")) {
    worker_args <- c(
      worker_args,
      paste0("--dealsim-tercile=", dealsim_tercile),
      paste0("--dealsim-map=", dealsim_map))
  }
  p <- processx::process$new(
    rscript, worker_args, wd = getwd(),
    stdout = file.path(cohort_dir, "stdout.log"),
    stderr = file.path(cohort_dir, "stderr.log"),
    cleanup_tree = TRUE)
  state$status[i] <<- "running"
  state$attempts[i] <<- state$attempts[i] + 1L
  state$pid[i] <<- p$get_pid()
  state$started[i] <<- as.character(Sys.time())
  state$finished[i] <<- NA_character_
  state$exit_status[i] <<- NA_integer_
  state$reason[i] <<- NA_character_
  workers[[as.character(g)]] <<- p
  message(
    "Started cohort ", g, " (pid ", p$get_pid(),
    ", available RAM ", sprintf("%.1f GB", available_gb()), ")")
  write_status()
}

finish_worker <- function(i, status, exit_status, reason = NA_character_) {
  g <- state$cohort[i]
  state$status[i] <<- status
  state$finished[i] <<- as.character(Sys.time())
  state$exit_status[i] <<- exit_status
  state$reason[i] <<- reason
  state$pid[i] <<- NA_integer_
  workers[[as.character(g)]] <<- NULL
  write_status()
}

write_status()
repeat {
  running_idx <- which(state$status == "running")
  for (i in running_idx) {
    p <- workers[[as.character(state$cohort[i])]]
    if (!p$is_alive()) {
      exit_status <- p$get_exit_status()
      if (identical(exit_status, 0L)) {
        finish_worker(i, "complete", exit_status)
        message("Completed cohort ", state$cohort[i])
      } else {
        finish_worker(
          i, "failed", exit_status,
          paste0("worker_exit_", exit_status))
        message(
          "Failed cohort ", state$cohort[i],
          " with exit status ", exit_status)
      }
    }
  }

  if (all(state$status %in% c("complete", "failed"))) break

  avail <- available_gb()
  running_idx <- which(state$status == "running")
  if (length(running_idx) >= 2L && avail < critical_gb) {
    critical_polls <- critical_polls + 1L
  } else {
    critical_polls <- 0L
  }
  if (critical_polls >= 3L) {
    # Stop the newest worker. Atomic blocks/covers/profile rows remain valid.
    start_times <- as.POSIXct(state$started[running_idx])
    i <- running_idx[which.max(start_times)]
    g <- state$cohort[i]
    workers[[as.character(g)]]$kill_tree()
    state$status[i] <- "pending"
    state$pid[i] <- NA_integer_
    state$reason[i] <- "memory_guard_requeued"
    workers[[as.character(g)]] <- NULL
    critical_polls <- 0L
    message(
      "Requeued cohort ", g,
      " after sustained available RAM below ",
      critical_gb, " GB")
    write_status()
  }

  running_n <- sum(state$status == "running")
  pending_idx <- which(state$status == "pending")
  while (running_n < max_workers && length(pending_idx)) {
    # Always permit one worker. A second requires the start-memory floor.
    if (running_n >= 1L && available_gb() < min_start_gb) break
    i <- pending_idx[1]
    start_worker(i)
    running_n <- running_n + 1L
    pending_idx <- which(state$status == "pending")
  }
  Sys.sleep(2)
}

complete <- state$cohort[state$status == "complete"]
diagnostics <- lapply(complete, function(g) {
  path <- file.path(
    audit_root, sprintf("cohort_%d", g),
    sprintf("cohort_hybrid_diagnostics_%d.csv", g))
  if (!file.exists(path)) {
    stop("Completed worker lacks diagnostics: ", path)
  }
  utils::read.csv(path, stringsAsFactors = FALSE)
})
if (length(diagnostics)) {
  utils::write.csv(
    do.call(rbind, diagnostics),
    file.path(audit_root, "p5_selected_diagnostics_all.csv"),
    row.names = FALSE)
}
if (any(state$status == "failed")) {
  stop("One or more selected-P5 cohort workers failed; see ", status_path)
}
message("Selected-P5 parallel run complete for cohorts: ",
        paste(complete, collapse = ", "))
