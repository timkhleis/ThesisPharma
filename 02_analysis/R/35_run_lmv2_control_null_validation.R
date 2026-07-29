# ============================================================================
# Restartable P6 runner for certified control-only placebo draws
# ============================================================================
# This runner deliberately accepts production draw IDs only. Assignment and
# support-only preflight draws (1--10) cannot be materialized or estimated.

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}

db_path <- normalizePath(arg("db"), winslash = "/", mustWork = TRUE)
design_root <- normalizePath(
  arg("design-root"), winslash = "/", mustWork = TRUE)
source_stamp <- normalizePath(
  arg("source-stamp"), winslash = "/", mustWork = TRUE)
output_root <- arg("output-root")
draw_ids <- as.integer(strsplit(arg("draws"), ",", fixed = TRUE)[[1]])
if (!length(draw_ids) || anyNA(draw_ids) || any(draw_ids < 1L)) {
  stop("--draws must be a comma-separated list of positive integers")
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "35a_lmv2_control_null_config.R"))
source(file.path(
  BASE, "R", "35d_summarize_lmv2_control_null_distribution.R"))
source(file.path(
  BASE, "R", "35e_certify_lmv2_control_null_results.R"))
if (any(draw_ids < LMV2_CONTROL_NULL_P6$minimum_production_draw_id)) {
  stop(
    "P6 refuses preflight draw IDs. Production draws must begin at ",
    LMV2_CONTROL_NULL_P6$minimum_production_draw_id, ".")
}

dir.create(output_root, recursive = TRUE, showWarnings = FALSE)
output_root <- normalizePath(
  output_root, winslash = "/", mustWork = TRUE)
rscript <- file.path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

run_child <- function(script, child_args, log_path) {
  status <- system2(
    rscript,
    c(file.path(BASE, "R", script), child_args),
    stdout = log_path, stderr = log_path)
  if (!identical(status, 0L)) {
    stop(script, " failed; see ", log_path)
  }
  invisible(TRUE)
}

status_rows <- list()
for (draw_id in draw_ids) {
  started <- Sys.time()
  design_draw <- file.path(
    design_root, sprintf("draw_%04d", draw_id))
  assignment_manifest <- file.path(
    design_draw, "assignment", "assignment_manifest.csv")
  roster_path <- file.path(
    design_draw, "handoff", "control_null_p6_roster.parquet")
  design_certification <- file.path(
    design_draw, "handoff", "design_certification.csv")
  if (any(!file.exists(c(
      assignment_manifest, roster_path, design_certification)))) {
    stop("Draw ", draw_id, " lacks a complete certified P5 handoff")
  }
  cert <- utils::read.csv(
    design_certification, stringsAsFactors = FALSE)
  if (!nrow(cert) || !all(as.logical(cert$pass))) {
    stop("Draw ", draw_id, " failed its P5 handoff certification")
  }

  draw_dir <- file.path(
    output_root, sprintf("draw_%04d", draw_id))
  panel_dir <- file.path(draw_dir, "panel")
  estimate_dir <- file.path(draw_dir, "estimate")
  dir.create(panel_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(estimate_dir, recursive = TRUE, showWarnings = FALSE)
  draw_status <- "complete"
  failure_stage <- NA_character_
  failure_reason <- NA_character_

  tryCatch({
    panel_manifest <- file.path(
      panel_dir, "control_null_panel_manifest.csv")
    if (!file.exists(panel_manifest)) {
      failure_stage <- "panel"
      run_child(
        "35b_materialize_lmv2_control_null_panel.R",
        c(
          paste0("--db=", db_path),
          paste0("--roster=", roster_path),
          paste0("--assignment-manifest=", assignment_manifest),
          paste0("--source-stamp=", source_stamp),
          paste0("--output-dir=", panel_dir)),
        file.path(panel_dir, "materialize.log"))
    }
    estimate_manifest <- file.path(
      estimate_dir, "control_null_estimation_manifest.csv")
    if (!file.exists(estimate_manifest)) {
      failure_stage <- "estimation"
      run_child(
        "35c_estimate_lmv2_control_null_draw.R",
        c(
          paste0("--panel-dir=", panel_dir),
          paste0("--panel-manifest=", panel_manifest),
          paste0("--output-dir=", estimate_dir)),
        file.path(estimate_dir, "estimate.log"))
    }
    failure_stage <- NA_character_
  }, error = function(e) {
    draw_status <<- "failed"
    failure_reason <<- conditionMessage(e)
  })

  status_rows[[length(status_rows) + 1L]] <- data.frame(
    draw_id = draw_id,
    status = draw_status,
    failure_stage = failure_stage,
    failure_reason = failure_reason,
    elapsed_seconds = as.numeric(
      difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE)
  utils::write.csv(
    do.call(rbind, status_rows),
    file.path(output_root, "p6_run_status.csv"),
    row.names = FALSE, na = "")
  message("P6 placebo draw ", draw_id, ": ", draw_status)
}

if (!all(vapply(
    status_rows, function(x) identical(x$status, "complete"),
    logical(1)))) {
  stop("One or more P6 placebo draws failed; summary was not produced")
}

summary_dir <- file.path(output_root, "summary")
lmv2_control_null_summarize(
  draw_root = output_root,
  output_dir = summary_dir)
checks <- lmv2_control_null_result_checks(
  file.path(summary_dir, "control_null_att_draws.csv"),
  file.path(summary_dir, "control_null_centering_summary.csv"))
lmv2_control_null_summary_tooth_test()
utils::write.csv(
  checks,
  file.path(summary_dir, "control_null_result_certification.csv"),
  row.names = FALSE)
if (!all(checks$pass)) {
  stop(
    "Control-null result certification failed: ",
    paste(checks$check[!checks$pass], collapse = ", "))
}
