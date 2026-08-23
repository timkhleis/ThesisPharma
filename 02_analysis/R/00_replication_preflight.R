#!/usr/bin/env Rscript

# Read-only preflight for a fresh replication checkout. It validates repository
# layout, source syntax, licensed-input placement, and the R environment before
# any expensive or state-changing analysis stage is started.

options(stringsAsFactors = FALSE)
args <- commandArgs(trailingOnly = TRUE)
code_only <- "--code-only" %in% args

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(root, "02_analysis", "R", "00_utils.R"))) {
  stop("Run this script from the repository root.")
}
source(file.path(root, "02_analysis", "R", "00_utils.R"))
use_project_library()

required_inputs <- file.path(root, c(
  "01_Data/inventor.dta",
  "01_Data/patent.dta",
  "01_Data/patent_inventor.dta",
  "01_Data/ipc.dta",
  "01_Data/group.dta",
  "01_Data/firm.dta",
  "01_Data/firm_group.dta",
  "01_Data/L_group_history_target.dta",
  "01_Data/L_merge.dta",
  "01_Data/BvD_financial_all.dta",
  "01_Data/CassiOrnaghiPaperData/BvD_group_id.csv",
  "01_Data/CassiOrnaghiPaperData/group_production.csv",
  "01_Data/CassiOrnaghiPaperData/inventor_production.csv",
  "01_Data/CassiOrnaghiPaperData/inventor_status.csv",
  "01_Data/CassiOrnaghiPaperData/merger_list.csv",
  "01_Data/CassiOrnaghiPaperData/T_inventors_tech_similarity.csv",
  "01_Data/CassiOrnaghiPaperData/t_stayer_coinventors.csv",
  "01_Data/OECD_QualitaData/OECD_Quality_data.txt"
))

packages <- c(
  "cobalt", "cowplot", "data.table", "DBI", "did", "digest", "dplyr",
  "dqrng", "duckdb", "fixest", "fwildclusterboot", "ggplot2",
  "gridExtra", "haven", "HonestDiD", "janitor", "jsonlite",
  "lpSolveAPI", "MASS", "Matrix", "nleqslv", "optweight", "osqp",
  "processx", "ps", "purrr", "quadprog", "readr", "sandwich", "scales",
  "stringr", "tibble", "tidyr", "WeightIt"
)
package_ok <- vapply(packages, requireNamespace, logical(1), quietly = TRUE)
package_versions <- vapply(packages, function(package) {
  if (!requireNamespace(package, quietly = TRUE)) return(NA_character_)
  as.character(utils::packageVersion(package))
}, character(1))

active_scripts <- sort(list.files(
  file.path(root, "02_analysis", "R"), pattern = "\\.R$",
  full.names = TRUE, recursive = FALSE
))
parse_errors <- vapply(active_scripts, function(path) {
  tryCatch({
    parse(path)
    ""
  }, error = function(error) conditionMessage(error))
}, character(1))

registry_path <- file.path(
  root, "02_analysis", "notes", "final_thesis_results_registry_1993.csv"
)
registry <- utils::read.csv(
  registry_path, stringsAsFactors = FALSE, check.names = FALSE
)
registry_code <- unique(registry$code_file[nzchar(registry$code_file)])
registry_code <- file.path(root, registry_code)

required_entry_points <- file.path(root, "02_analysis", "R", c(
  "run_pipeline.R",
  "41_run_lmv2_current_release.R",
  "60_run_final_thesis_results_1993.R",
  "65_run_lmv2_relative_standing.R",
  "70_run_lmv2_retained_robustness.R",
  "71_estimate_lmv2_retained_robustness_core.R",
  "74_run_lmv2_retained_deal_value_quantiles.R",
  "75_run_lmv2_release_extensions.R"
))

private_pattern <- "(\\.worktrees[/\\\\]|\\.codex[/\\\\]worktrees)"
private_hits <- vapply(active_scripts, function(path) {
  any(grepl(
    private_pattern,
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    perl = TRUE
  ))
}, logical(1))

checks <- data.frame(
  check = c(
    "R_4_5_1_or_newer",
    "all_required_packages_installed",
    "frozen_fwildclusterboot_version",
    "frozen_HonestDiD_version",
    "all_active_R_scripts_parse",
    "all_registry_code_files_exist",
    "all_release_entry_points_exist",
    "no_active_private_worktree_paths",
    "all_licensed_inputs_present"
  ),
  pass = c(
    getRversion() >= "4.5.1",
    all(package_ok),
    identical(package_versions[["fwildclusterboot"]], "0.14.3"),
    identical(package_versions[["HonestDiD"]], "0.2.8"),
    all(!nzchar(parse_errors)),
    all(file.exists(registry_code)),
    all(file.exists(required_entry_points)),
    !any(private_hits),
    code_only || all(file.exists(required_inputs))
  ),
  detail = c(
    R.version.string,
    if (all(package_ok)) "all installed" else paste(
      packages[!package_ok], collapse = ", "
    ),
    package_versions[["fwildclusterboot"]],
    package_versions[["HonestDiD"]],
    if (all(!nzchar(parse_errors))) paste(length(active_scripts), "scripts")
      else paste(basename(active_scripts[nzchar(parse_errors)]), collapse = ", "),
    paste0(sum(file.exists(registry_code)), "/", length(registry_code)),
    paste0(sum(file.exists(required_entry_points)), "/",
           length(required_entry_points)),
    paste(basename(active_scripts[private_hits]), collapse = ", "),
    if (code_only) "skipped (--code-only)" else paste0(
      sum(file.exists(required_inputs)), "/", length(required_inputs)
    )
  ),
  stringsAsFactors = FALSE
)

print(checks, row.names = FALSE)
if (!all(checks$pass)) {
  stop(
    "Replication preflight failed: ",
    paste(checks$check[!checks$pass], collapse = ", "),
    call. = FALSE
  )
}
message("Replication preflight passed.")
