#!/usr/bin/env Rscript

# Reproduce the exploratory deal-value quantile profile for the initially
# retained sample. The estimator is the certified generic 48r/48s quantile
# implementation; this wrapper constructs the retained deal roster and fixes
# the standard release paths.

options(stringsAsFactors = FALSE, scipen = 999)

args <- commandArgs(trailingOnly = TRUE)
arg <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  if (length(hit) != 1L) stop("Duplicate argument: ", flag)
  sub(paste0("^", flag, "="), "", hit)
}

BASE <- normalizePath(
  arg("--code-root", "02_analysis"), winslash = "/", mustWork = TRUE
)
ANALYSIS_ROOT <- normalizePath(
  arg("--analysis-root", "02_analysis"), winslash = "/", mustWork = TRUE
)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

BOOTSTRAP_REPS <- as.integer(arg("--bootstrap-reps", "9999"))
if (!is.finite(BOOTSTRAP_REPS) || BOOTSTRAP_REPS < 199L) {
  stop("--bootstrap-reps must be at least 199")
}

audit <- file.path(
  ANALYSIS_ROOT, "output", "audit", "local_match_v2_1993_amendment"
)
robust <- file.path(audit, "ROBUSTNESS_RELEASE_1993")
full_design <- file.path(
  robust, "DEAL_VALUE_QUANTILES", "DESIGN_V1",
  "deal_value_quantile_map.csv"
)
panel_dir <- file.path(robust, "RETAINED_INVENTORS", "PANEL_PRIMARY")
release_dir <- file.path(
  robust, "RETAINED_INVENTORS", "DEAL_VALUE_QUANTILES"
)
input_dir <- file.path(release_dir, "INPUT")
design_dir <- file.path(release_dir, "DESIGN_V1")
estimation_dir <- file.path(release_dir, "ESTIMATION_V1")

panel_files <- sort(list.files(
  panel_dir, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
required_cohorts <- 1993:2010
panel_cohorts <- as.integer(sub(
  "^.*_c([0-9]+)\\.parquet$", "\\1", panel_files
))
if (!file.exists(full_design) ||
    !identical(panel_cohorts, required_cohorts)) {
  stop(
    "Missing full-cohort quantile design or retained panel shards. Run ",
    "48r/48s for the full cohort and 70/71 for retained robustness first."
  )
}
for (path in c(design_dir, estimation_dir)) {
  if (dir.exists(path) && length(list.files(
      path, all.files = TRUE, no.. = TRUE))) {
    stop("Frozen retained quantile directory is not empty: ", path)
  }
}
dir.create(input_dir, recursive = TRUE, showWarnings = FALSE)

sql_paths <- paste0(
  "[", paste(vapply(
    normalizePath(panel_files, winslash = "/", mustWork = TRUE),
    function(x) paste0("'", gsub("'", "''", x), "'"), character(1)
  ), collapse = ","), "]"
)
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
retained_counts <- DBI::dbGetQuery(con, sprintf(paste0(
  "SELECT CAST(cohort AS INTEGER) cohort, ",
  "CAST(deal_id AS INTEGER) deal_id, ",
  "COUNT(DISTINCT roster_row_id)::INTEGER n_supported ",
  "FROM read_parquet(%s, union_by_name=true) ",
  "WHERE arm='treated' AND event_time=-1 ",
  "GROUP BY cohort,deal_id ORDER BY cohort,deal_id"
), sql_paths))

full_map <- utils::read.csv(full_design, stringsAsFactors = FALSE)
deal_map <- merge(
  retained_counts,
  unique(full_map[c(
    "cohort", "deal_id", "target_value", "decile", "quartile",
    "decile_label", "quartile_label"
  )]),
  by = c("cohort", "deal_id"), all.x = TRUE, sort = TRUE
)
if (nrow(deal_map) != 153L || sum(deal_map$n_supported) != 2792L ||
    anyNA(deal_map$target_value) || anyDuplicated(deal_map[c(
      "cohort", "deal_id"
    )])) {
  stop("Retained deal-map certification failed")
}
deal_map <- deal_map[c(
  "cohort", "deal_id", "target_value", "n_supported", "decile",
  "quartile", "decile_label", "quartile_label"
)]
deal_map_path <- file.path(input_dir, "retained_deal_map.csv")
utils::write.csv(deal_map, deal_map_path, row.names = FALSE)

# Retain the full-cohort cutpoints. Redefining quantiles inside the selected
# retained sample would answer a different question and would not reproduce
# the thesis table's stated full-cohort deal-size bins.
dir.create(design_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  deal_map, file.path(design_dir, "deal_value_quantile_map.csv"),
  row.names = FALSE
)
counts <- do.call(rbind, lapply(c(
  decile = "decile_label", quartile = "quartile_label"
), function(column) {
  do.call(rbind, lapply(sort(unique(deal_map[[column]])), function(label) {
    z <- deal_map[deal_map[[column]] == label, , drop = FALSE]
    data.frame(
      partition = if (column == "decile_label") "decile" else "quartile",
      bin = label,
      acquisitions = nrow(z),
      supported_treated_inventors = sum(z$n_supported),
      cohorts = length(unique(z$cohort)),
      minimum_target_value = min(z$target_value),
      median_target_value = stats::median(z$target_value),
      maximum_target_value = max(z$target_value),
      stringsAsFactors = FALSE
    )
  }))
}))
utils::write.csv(
  counts, file.path(design_dir, "deal_value_quantile_counts.csv"),
  row.names = FALSE
)
manifest <- data.frame(
  version = "lmv2_retained_deal_value_quantile_design_v1",
  designation = "post_hoc_exploratory_selected_population",
  unit_defining_quantiles = "full_cohort_acquisition_cutpoints",
  requested_partitions = "quartiles;deciles",
  acquisitions = nrow(deal_map),
  supported_treated_inventors = sum(deal_map$n_supported),
  cohorts = paste(sort(unique(deal_map$cohort)), collapse = ";"),
  post_outcomes_opened = FALSE,
  analysis_authorized = TRUE,
  parent_full_design_sha256 = digest::digest(
    full_design, file = TRUE, algo = "sha256"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(design_dir, "deal_value_quantile_design_manifest.csv"),
  row.names = FALSE
)

rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")
run <- function(script, script_args) {
  status <- system2(
    rscript, c(file.path(BASE, "R", script), script_args),
    stdout = "", stderr = ""
  )
  if (!identical(status, 0L)) stop(script, " failed with status ", status)
}

run("48s_run_lmv2_deal_value_quantiles.R", c(
  paste0("--code-root=", BASE),
  paste0("--panel-dir=", panel_dir),
  paste0("--design-dir=", design_dir),
  paste0("--output-dir=", estimation_dir),
  paste0("--bootstrap-reps=", BOOTSTRAP_REPS),
  "--expected-deals=153",
  "--cohort-start=1993",
  "--cohort-end=2010",
  "--designation=post_hoc_exploratory_selected_population",
  "--weight-scheme=frozen_certified_retained_relative_weights"
))

message("Retained deal-value quantile release complete: ", estimation_dir)
