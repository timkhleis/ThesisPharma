# ============================================================================
# 13_run_local_match_pilot.R  -- orchestrator / launcher (design local_match_v1)
# ----------------------------------------------------------------------------
# Modes (first CLI arg):
#   (none) | "pilot"  : 13b -> 13c -> 13d on the pilot cohorts (1995/2002/2009),
#                       untagged artifacts.
#   "full"            : restartable 17-cohort launcher. Sets LM_TAG=full so ALL
#                       artifacts are written to SEPARATE *_full_* parquet and a
#                       local_match_v1_full_shards/ dir -- the pilot is untouched.
#                       Builds inputs (13b) for 1994-2010 then matches (13c),
#                       which is restartable per cohort via shards.
#   "smoke" <year>    : same as full (LM_TAG=full) but for a single extra cohort,
#                       to smoke-test the launcher without a long run.
#
# Runs stages directly with Rscript (no elaborate timeout orchestrator).
# Completed cohort shards are preserved if a later cohort fails (13c guards).
# ============================================================================

BASE   <- normalizePath("02_analysis", mustWork = TRUE)
RSCRIPT <- file.path(R.home("bin"), "Rscript.exe")
args   <- commandArgs(trailingOnly = TRUE)
mode   <- if (length(args) >= 1) args[1] else "pilot"
Rf     <- function(f) file.path(BASE, "R", f)

run_stage <- function(script, sargs = character(0), env = character(0)) {
  cat("\n>>> RUN", script, if (length(sargs)) paste(sargs, collapse=" ") else "",
      if (length(env)) paste0("[", paste(env, collapse=";"), "]") else "", "\n")
  old <- Sys.getenv("LM_TAG", unset = NA)
  if (length(env)) { kv <- strsplit(env, "=", fixed=TRUE)[[1]]; Sys.setenv(LM_TAG = kv[2]) }
  code <- system2(RSCRIPT, c(shQuote(Rf(script)), sargs), stdout = "", stderr = "")
  if (length(env)) { if (is.na(old)) Sys.unsetenv("LM_TAG") else Sys.setenv(LM_TAG = old) }
  if (!is.null(attr(code, "status")) && attr(code, "status") != 0)
    stop("stage failed: ", script, " (exit ", attr(code,"status"), ")")
  if (is.numeric(code) && code != 0) stop("stage failed: ", script, " (exit ", code, ")")
  invisible(TRUE)
}

if (mode %in% c("pilot", "")) {
  cat("=== PILOT run (cohorts 1995/2002/2009) ===\n")
  run_stage("13b_build_local_match_inputs.R")
  run_stage("13c_run_local_match_pilot.R")
  run_stage("13d_report_local_match_pilot.R")
  cat("=== PILOT complete ===\n")

} else if (mode == "full") {
  cat("=== FULL 17-cohort launcher (LM_TAG=full, cohorts 1994-2010) ===\n")
  cohorts <- as.character(1994:2010)
  run_stage("13b_build_local_match_inputs.R", cohorts, env = "LM_TAG=full")
  run_stage("13c_run_local_match_pilot.R",    cohorts, env = "LM_TAG=full")
  cat("=== FULL build complete (shards under local_match_v1_full_shards/) ===\n")

} else if (mode == "smoke") {
  yr <- if (length(args) >= 2) args[2] else "2005"
  cat("=== SMOKE test of full launcher on cohort", yr, "(LM_TAG=full) ===\n")
  run_stage("13b_build_local_match_inputs.R", yr, env = "LM_TAG=full")
  run_stage("13c_run_local_match_pilot.R",    yr, env = "LM_TAG=full")
  cat("=== SMOKE complete ===\n")

} else stop("unknown mode: ", mode)
