# Two-worker scheduler for the nine preregistered deal-70 deletion refits.

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
refit_root <- read_arg("refit-root")
p3_manifest <- normalizePath(
  read_arg("p3-manifest"), winslash = "/", mustWork = TRUE)
max_workers <- as.integer(read_arg(
  "max-workers", required = FALSE, default = "2"))
if (!max_workers %in% 1:2) stop("--max-workers= must be 1 or 2")
if (!requireNamespace("processx", quietly = TRUE) ||
    !requireNamespace("ps", quietly = TRUE)) {
  stop("Refit scheduler requires processx and ps")
}

firms <- c(
  100569, 102374, 107670, 108594, 109770,
  200547, 203155, 303292, 307791)
dir.create(refit_root, recursive = TRUE, showWarnings = FALSE)
refit_root <- normalizePath(
  refit_root, winslash = "/", mustWork = TRUE)
runner <- normalizePath(
  file.path(
    "02_analysis", "R", "19m_run_lmv2_p5_deal70_refits.R"),
  winslash = "/", mustWork = TRUE)
rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")

state <- data.frame(
  omitted_control_group = firms, status = "pending",
  attempts = 0L, pid = NA_integer_, started = NA_character_,
  finished = NA_character_, exit_status = NA_integer_,
  stringsAsFactors = FALSE)
workers <- list()
status_path <- file.path(refit_root, "refit_scheduler_status.csv")
write_status <- function() {
  temporary <- tempfile(
    "refit_status_", tmpdir = refit_root, fileext = ".tmp")
  utils::write.csv(state, temporary, row.names = FALSE)
  if (file.exists(status_path) && !file.remove(status_path)) {
    stop("Could not replace refit scheduler status")
  }
  if (!file.rename(temporary, status_path)) {
    stop("Could not commit refit scheduler status")
  }
}
available_gb <- function() {
  as.numeric(ps::ps_system_memory()[["avail"]]) / 1024^3
}
start_worker <- function(i) {
  firm <- state$omitted_control_group[[i]]
  firm_dir <- file.path(refit_root, paste0("omit_firm_", firm))
  dir.create(firm_dir, recursive = TRUE, showWarnings = FALSE)
  process <- processx::process$new(
    rscript,
    c(
      runner, paste0("--db=", db_path),
      paste0("--refit-root=", refit_root),
      paste0("--p3-manifest=", p3_manifest),
      paste0("--omitted-control-group=", firm)),
    wd = getwd(),
    stdout = file.path(firm_dir, "stdout.log"),
    stderr = file.path(firm_dir, "stderr.log"),
    cleanup_tree = TRUE)
  state$status[[i]] <<- "running"
  state$attempts[[i]] <<- state$attempts[[i]] + 1L
  state$pid[[i]] <<- process$get_pid()
  state$started[[i]] <<- as.character(Sys.time())
  workers[[as.character(firm)]] <<- process
  write_status()
}
finish_worker <- function(i, status, exit_status) {
  firm <- state$omitted_control_group[[i]]
  state$status[[i]] <<- status
  state$finished[[i]] <<- as.character(Sys.time())
  state$exit_status[[i]] <<- exit_status
  state$pid[[i]] <<- NA_integer_
  workers[[as.character(firm)]] <<- NULL
  write_status()
}

write_status()
repeat {
  for (i in which(state$status == "running")) {
    process <- workers[[
      as.character(state$omitted_control_group[[i]])]]
    if (!process$is_alive()) {
      exit_status <- process$get_exit_status()
      finish_worker(
        i, if (identical(exit_status, 0L)) "complete" else "failed",
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
  stop("At least one deal-70 refit failed; see ", status_path)
}
message("All nine outcome-blind deal-70 deletion refits completed")

