# Memory-aware scheduler for the 17 cardinality-matching cohort workers.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE, default = NA_character_) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(default)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
production_root <- normalizePath(
  read_arg("production-root"), winslash = "/", mustWork = TRUE)
cardinality_root <- read_arg("cardinality-root")
p3_manifest <- normalizePath(
  read_arg("p3-manifest"), winslash = "/", mustWork = TRUE)
max_workers <- as.integer(read_arg(
  "max-workers", required = FALSE, default = "2"))
if (!max_workers %in% 1:2) stop("--max-workers= must be 1 or 2")
if (!requireNamespace("processx", quietly = TRUE) ||
    !requireNamespace("ps", quietly = TRUE)) {
  stop("Cardinality scheduler requires processx and ps")
}

cohorts <- 1994:2010
dir.create(cardinality_root, recursive = TRUE, showWarnings = FALSE)
cardinality_root <- normalizePath(
  cardinality_root, winslash = "/", mustWork = TRUE)
runner <- normalizePath(
  file.path(
    "02_analysis", "R", "20d_run_lmv2_p5_cardinality.R"),
  winslash = "/", mustWork = TRUE)
rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")
state <- data.frame(
  cohort = cohorts, status = "pending", attempts = 0L,
  pid = NA_integer_, started = NA_character_,
  finished = NA_character_, exit_status = NA_integer_,
  stringsAsFactors = FALSE)
workers <- list()
status_path <- file.path(
  cardinality_root, "cardinality_scheduler_status.csv")
write_status <- function() {
  temporary <- tempfile(
    "cardinality_status_", tmpdir = cardinality_root,
    fileext = ".tmp")
  utils::write.csv(state, temporary, row.names = FALSE)
  if (file.exists(status_path) && !file.remove(status_path)) {
    stop("Could not replace cardinality scheduler status")
  }
  if (!file.rename(temporary, status_path)) {
    stop("Could not commit cardinality scheduler status")
  }
}
available_gb <- function() {
  as.numeric(ps::ps_system_memory()[["avail"]]) / 1024^3
}
start_worker <- function(index) {
  cohort <- state$cohort[[index]]
  cohort_root <- file.path(
    cardinality_root, sprintf("cohort_%d", cohort))
  dir.create(cohort_root, recursive = TRUE, showWarnings = FALSE)
  process <- processx::process$new(
    rscript,
    c(
      runner, paste0("--cohort=", cohort),
      paste0("--db=", db_path),
      paste0("--production-root=", production_root),
      paste0("--cardinality-root=", cardinality_root),
      paste0("--p3-manifest=", p3_manifest)),
    wd = getwd(),
    stdout = file.path(cohort_root, "stdout.log"),
    stderr = file.path(cohort_root, "stderr.log"),
    cleanup_tree = TRUE)
  state$status[[index]] <<- "running"
  state$attempts[[index]] <<- state$attempts[[index]] + 1L
  state$pid[[index]] <<- process$get_pid()
  state$started[[index]] <<- as.character(Sys.time())
  workers[[as.character(cohort)]] <<- process
  write_status()
}
finish_worker <- function(index, status, exit_status) {
  cohort <- state$cohort[[index]]
  state$status[[index]] <<- status
  state$finished[[index]] <<- as.character(Sys.time())
  state$exit_status[[index]] <<- exit_status
  state$pid[[index]] <<- NA_integer_
  workers[[as.character(cohort)]] <<- NULL
  write_status()
}

write_status()
repeat {
  for (index in which(state$status == "running")) {
    process <- workers[[as.character(state$cohort[[index]])]]
    if (!process$is_alive()) {
      exit_status <- process$get_exit_status()
      finish_worker(
        index,
        if (identical(exit_status, 0L)) "complete" else "failed",
        exit_status)
    }
  }
  if (all(state$status %in% c("complete", "failed"))) break
  running_n <- sum(state$status == "running")
  pending <- which(state$status == "pending")
  while (running_n < max_workers && length(pending)) {
    if (running_n >= 1L && available_gb() < 12) break
    start_worker(pending[[1]])
    running_n <- running_n + 1L
    pending <- which(state$status == "pending")
  }
  Sys.sleep(2)
}
if (any(state$status == "failed")) {
  stop("At least one cardinality worker failed; see ", status_path)
}
coverage_paths <- list.files(
  cardinality_root, pattern = "^cardinality_coverage\\.csv$",
  recursive = TRUE, full.names = TRUE)
coverage <- do.call(rbind, lapply(
  coverage_paths, utils::read.csv, stringsAsFactors = FALSE))
utils::write.csv(
  coverage[order(coverage$cohort), ],
  file.path(cardinality_root, "cardinality_coverage_all.csv"),
  row.names = FALSE)
message("All 17 cardinality cohort workers completed")

