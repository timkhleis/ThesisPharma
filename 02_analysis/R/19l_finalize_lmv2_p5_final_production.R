# Outcome-blind finalizer for the realized P5.3 production run.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "16c_lmv2_matching_utils.R"))
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))
source(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path(BASE, "R", "19a_lmv2_p5_rescue_config.R"))
source(file.path(BASE, "R", "19i_lmv2_p5_final_production_config.R"))

db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
production_root <- normalizePath(
  read_arg("production-root"), winslash = "/", mustWork = TRUE)
search_root <- normalizePath(
  read_arg("search-root"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(
  output_dir, winslash = "/", mustWork = TRUE)

atomic_csv <- function(x, path) {
  temporary <- tempfile(
    paste0(basename(path), "_"), tmpdir = dirname(path),
    fileext = ".tmp")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(x, temporary, row.names = FALSE, na = "")
  if (file.exists(path) && !file.remove(path)) {
    stop("Could not replace ", path)
  }
  if (!file.rename(temporary, path)) stop("Could not finalize ", path)
}
collect_csv <- function(root, pattern) {
  paths <- list.files(
    root, pattern = pattern, recursive = TRUE, full.names = TRUE)
  if (!length(paths)) return(data.frame())
  rows <- lapply(paths, function(path) {
    x <- utils::read.csv(path, stringsAsFactors = FALSE)
    x$artifact_path <- rep(
      normalizePath(path, winslash = "/", mustWork = TRUE),
      nrow(x))
    x$artifact_timestamp <- rep(
      as.character(file.info(path)$mtime), nrow(x))
    x
  })
  common <- Reduce(union, lapply(rows, names))
  rows <- lapply(rows, function(x) {
    for (name in setdiff(common, names(x))) x[[name]] <- NA
    x[common]
  })
  do.call(rbind, rows)
}
sql_paths <- function(paths) {
  paste(sprintf(
    "'%s'", gsub("'", "''", normalizePath(
      paths, winslash = "/", mustWork = TRUE), fixed = TRUE)),
    collapse = ",")
}

status_path <- file.path(production_root, "scheduler_status.csv")
if (!file.exists(status_path)) stop("Production scheduler status is missing")
scheduler <- utils::read.csv(status_path, stringsAsFactors = FALSE)
if (!identical(sort(scheduler$cohort), LMV2_P5_PRODUCTION$cohorts) ||
    any(scheduler$status != "complete")) {
  stop("The realized production run is not complete")
}

diagnostic_paths <- list.files(
  production_root,
  pattern = "^cohort_hybrid_diagnostics_[0-9]{4}\\.csv$",
  recursive = TRUE, full.names = TRUE)
if (length(diagnostic_paths) !=
    length(LMV2_P5_PRODUCTION$cohorts)) {
  stop("Expected exactly one diagnostics shard per production cohort")
}
diagnostics <- do.call(rbind, lapply(
  diagnostic_paths, utils::read.csv, stringsAsFactors = FALSE))
if (anyDuplicated(diagnostics[c("cohort", "scheme")]) ||
    !identical(
      sort(unique(diagnostics$cohort)),
      LMV2_P5_PRODUCTION$cohorts)) {
  stop("Production diagnostics have duplicate or missing cohort/scheme cells")
}
scheme_status <- lmv2_p5_production_scheme_status(diagnostics)
primary_status <- scheme_status[
  scheme_status$scheme == "primary", , drop = FALSE]
if (nrow(primary_status) != length(LMV2_P5_PRODUCTION$cohorts) ||
    any(!primary_status$feasible)) {
  stop("At least one frozen primary cohort fails balance/ESS")
}
comparison_map <- lmv2_p5_production_comparison_map(diagnostics)

production_manifests <- list.files(
  production_root, pattern = "^p5_production_manifest\\.csv$",
  recursive = TRUE, full.names = TRUE)
production_manifests <- do.call(rbind, lapply(
  production_manifests, utils::read.csv, stringsAsFactors = FALSE))
cover_manifests <- list.files(
  production_root, pattern = "^manifest\\.csv$",
  recursive = TRUE, full.names = TRUE)
cover_manifests <- cover_manifests[grepl(
  "[/\\\\]profile_edge_covers[/\\\\]manifest\\.csv$",
  cover_manifests)]
cover_manifests <- do.call(rbind, lapply(
  cover_manifests, utils::read.csv, stringsAsFactors = FALSE))
current_covers <- merge(
  production_manifests[c("cohort", "execution_hash")],
  cover_manifests[cover_manifests$status == "complete", ],
  by = c("cohort", "execution_hash"))
if (nrow(current_covers) != length(LMV2_P5_PRODUCTION$cohorts) ||
    anyDuplicated(current_covers$cohort)) {
  stop("Expected exactly one current U2 support cover per production cohort")
}
cover_paths <- current_covers$path
if (any(!file.exists(cover_paths))) {
  stop("A current U2 support-cover path is missing")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=2")
DBI::dbExecute(con, "SET memory_limit='6GB'")
DBI::dbExecute(con, "SET preserve_insertion_order=false")
full_treated <- DBI::dbGetQuery(con, sprintf("
  SELECT CAST(cohort AS INTEGER) cohort,
         CAST(deal_id AS INTEGER) deal_id,
         CAST(codinv AS BIGINT) codinv,
         log_patent_count_5y, patent_trajectory, career_age,
         focal_group_exclusivity, focal_group_tenure
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort IN (%s)
  ORDER BY cohort,deal_id,codinv",
  paste(LMV2_P5_PRODUCTION$cohorts, collapse = ",")))
supported <- DBI::dbGetQuery(con, sprintf(
  "SELECT DISTINCT CAST(cohort AS INTEGER) cohort,
          CAST(deal_id AS INTEGER) deal_id,
          CAST(treated_codinv AS BIGINT) codinv
   FROM read_parquet([%s], union_by_name=true)",
  sql_paths(cover_paths)))
if (anyDuplicated(supported[c("cohort", "deal_id", "codinv")])) {
  stop("Realized support keys are not unique")
}
full_treated$supported <- paste(
  full_treated$cohort, full_treated$deal_id,
  full_treated$codinv) %in% paste(
    supported$cohort, supported$deal_id, supported$codinv)
score <- lmv2_p5_rescue_score_gates(full_treated)
score$checks$source <- paste0(
  "realized_p5_3_all_", length(LMV2_P5_PRODUCTION$cohorts),
  "_cohorts")
aggregate_coverage <- score$checks$realized[
  score$checks$gate == "aggregate_inventor_coverage"]
scope_review <- data.frame(
  scope = c("aggregate", paste0("cohort_", score$by_cohort$cohort)),
  coverage = c(aggregate_coverage, score$by_cohort$coverage),
  threshold = c(
    LMV2_P5_PRODUCTION$scope_review$aggregate_inventor_coverage,
    rep(
      LMV2_P5_PRODUCTION$scope_review$cohort_inventor_coverage,
      nrow(score$by_cohort))),
  review = c(
    aggregate_coverage <
      LMV2_P5_PRODUCTION$scope_review$aggregate_inventor_coverage,
    score$by_cohort$coverage <
      LMV2_P5_PRODUCTION$scope_review$cohort_inventor_coverage),
  stringsAsFactors = FALSE)

full_treated$productivity_quartile <-
  lmv2_p5_rescue_assign_productivity_quartile(full_treated)
coverage_by_cohort_quartile <- do.call(rbind, lapply(
  split(
    full_treated,
    interaction(
      full_treated$cohort, full_treated$productivity_quartile,
      drop = TRUE, lex.order = TRUE)),
  function(z) data.frame(
    cohort = z$cohort[[1]],
    productivity_quartile = z$productivity_quartile[[1]],
    eligible = nrow(z), supported = sum(z$supported),
    coverage = mean(z$supported))))
coverage_by_deal <- do.call(rbind, lapply(
  split(
    full_treated,
    interaction(
      full_treated$cohort, full_treated$deal_id,
      drop = TRUE, lex.order = TRUE)),
  function(z) data.frame(
    cohort = z$cohort[[1]], deal_id = z$deal_id[[1]],
    eligible = nrow(z), supported = sum(z$supported),
    coverage = mean(z$supported))))

weight_manifests <- list.files(
  production_root, pattern = "^manifest\\.csv$",
  recursive = TRUE, full.names = TRUE)
weight_manifests <- weight_manifests[
  grepl("[/\\\\]weights[/\\\\]manifest\\.csv$", weight_manifests)]
weights <- do.call(rbind, lapply(
  weight_manifests, utils::read.csv, stringsAsFactors = FALSE))
if (!nrow(weights)) stop("No production weight manifests found")
weights <- merge(
  production_manifests[c("cohort", "execution_hash")],
  weights,
  by = c("cohort", "execution_hash"))
for (i in seq_len(nrow(weights))) {
  if (!file.exists(weights$path[[i]]) ||
      !identical(
        lmv2_p3_file_hash(weights$path[[i]]),
        weights$checksum[[i]])) {
    stop("Weight checksum failed for manifest row ", i)
  }
}
weight_key <- weights[c("cohort", "scheme")]
if (anyDuplicated(weight_key)) {
  stop("Production weight manifests duplicate a cohort/scheme")
}
expected_weight_cells <- scheme_status[
  scheme_status$feasible, c("cohort", "scheme")]
if (!all(paste(
    expected_weight_cells$cohort,
    expected_weight_cells$scheme) %in% paste(
      weights$cohort, weights$scheme))) {
  stop("A feasible cohort/scheme lacks a materialized weight shard")
}

comparison_manifest <- merge(
  weights, comparison_map, by = "cohort", all.x = TRUE)
comparison_manifest$estimand <- NA_character_
comparison_manifest$estimand[
  comparison_manifest$scheme == "primary" &
    comparison_manifest$include_primary_full] <-
  "primary_full_supported"
equal_rows <- comparison_manifest[
  comparison_manifest$scheme == "equal_deal" &
    comparison_manifest$include_equal_deal, , drop = FALSE]
equal_rows$estimand <- "equal_deal_feasible"
like_rows <- comparison_manifest[
  comparison_manifest$scheme == "primary" &
    comparison_manifest$include_primary_like_for_like, , drop = FALSE]
like_rows$estimand <- "primary_equal_deal_feasible_sample"
comparison_manifest <- rbind(
  comparison_manifest[!is.na(comparison_manifest$estimand), ],
  equal_rows, like_rows)

dependence <- collect_csv(
  production_root, "^dependence_[0-9]{4}_.*\\.csv$")
loo <- collect_csv(
  production_root, "^leave_one_firm_out_[0-9]{4}_.*\\.csv$")
deal_70_dependence <- dependence[
  dependence$cohort == 2000L & dependence$deal_id == 70L, ]
deal_70_loo <- loo[
  loo$cohort == 2000L & loo$deal_id == 70L, ]
deal_70_loo_summary <- do.call(rbind, lapply(
  split(
    deal_70_loo,
    interaction(
      deal_70_loo$scheme,
      deal_70_loo$omitted_control_group,
      drop = TRUE, lex.order = TRUE)),
  function(z) data.frame(
    scheme = z$scheme[[1]],
    omitted_control_group = z$omitted_control_group[[1]],
    n_balance_variables = nrow(z),
    maximum_absolute_shift_sd = max(z$absolute_shift_sd),
    stringsAsFactors = FALSE)))

specification_search <- collect_csv(
  search_root,
  "^cohort_hybrid_diagnostics_[0-9]{4}\\.csv$")
if (nrow(specification_search)) {
  specification_search <- specification_search[order(
    specification_search$artifact_timestamp,
    specification_search$cohort,
    specification_search$caliper,
    specification_search$profile,
    specification_search$universe,
    specification_search$scheme), ]
  specification_search$search_order <- seq_len(
    nrow(specification_search))
}
stage1_search <- collect_csv(
  search_root, "^p4_ebal_stage1_diagnostics\\.csv$")
stage2_search <- collect_csv(
  search_root, "^p4_ebal_stage2_diagnostics\\.csv$")
governance <- data.frame(
  date = c(
    "2026-07-26", "2026-07-26", "2026-07-26", "2026-07-26",
    "2026-07-26"),
  change = c(
    "LOO hard gate reclassified as required influence diagnostic",
    "selection SMD reclassified as scope/bounding diagnostic conditional on coverage",
    "U2 reduced S1=2.0 S2=1.5 frozen for production",
    "Henkel retained in deal-70 baseline with cross-industry scale-counterfactual disclosure",
    "cardinality-recovered estimate reported regardless of precision"),
  rationale = c(
    "Nine clean firms and EFC 4.94 show a narrow but real industry counterfactual; full deletion distribution and P6 ATT band required",
    "Realized aggregate coverage is 92.83 percent, minimum cohort coverage is 82.72 percent, and minimum productivity-quartile coverage is 85.63 percent; lower-coverage cells trigger separate review",
    "Stage-1 expansion repaired firm-level counterfactual support for the mega-deal without dropping firm trajectory",
    "Henkel is uniquely comparable in firm scale and improves reuse-adjusted ESS, but its SmithKline cosine falls from 0.4284 at IPC4 to 0.0437 at IPC main-group resolution; Henkel omission attains exact balance but fails the ESS hierarchy",
    "Only 17 unsupported inventors are recovered; their separate point estimate and confidence interval are reported and labelled uninformative if imprecise rather than conditionally omitted"),
  freeze_hash = LMV2_P5_PRODUCTION_FREEZE_SHA256,
  stringsAsFactors = FALSE)

atomic_csv(scheduler, file.path(output_dir, "scheduler_status.csv"))
atomic_csv(diagnostics, file.path(
  output_dir, "production_cell_diagnostics.csv"))
atomic_csv(scheme_status, file.path(
  output_dir, "production_scheme_status.csv"))
atomic_csv(comparison_map, file.path(
  output_dir, "comparison_sample_map.csv"))
atomic_csv(comparison_manifest, file.path(
  output_dir, "comparison_weight_manifest.csv"))
atomic_csv(score$checks, file.path(
  output_dir, "realized_gate_checks.csv"))
atomic_csv(score$by_cohort, file.path(
  output_dir, "realized_coverage_by_cohort.csv"))
atomic_csv(score$by_quartile, file.path(
  output_dir, "realized_coverage_by_productivity_quartile.csv"))
atomic_csv(coverage_by_cohort_quartile, file.path(
  output_dir, "realized_coverage_by_cohort_quartile.csv"))
atomic_csv(coverage_by_deal, file.path(
  output_dir, "realized_coverage_by_deal.csv"))
atomic_csv(score$selection, file.path(
  output_dir, "realized_retained_vs_unsupported.csv"))
atomic_csv(scope_review, file.path(
  output_dir, "scope_review_flags.csv"))
atomic_csv(deal_70_dependence, file.path(
  output_dir, "deal_70_dependence.csv"))
atomic_csv(deal_70_loo, file.path(
  output_dir, "deal_70_leave_one_firm_out_long.csv"))
atomic_csv(deal_70_loo_summary, file.path(
  output_dir, "deal_70_leave_one_firm_out_summary.csv"))
atomic_csv(specification_search, file.path(
  output_dir, "specification_search_all_evaluated_cells.csv"))
atomic_csv(stage1_search, file.path(
  output_dir, "specification_search_stage1_cells.csv"))
atomic_csv(stage2_search, file.path(
  output_dir, "specification_search_stage2_cells.csv"))
atomic_csv(governance, file.path(
  output_dir, "specification_search_governance_changes.csv"))

lines <- c(
  "# P5.3 final outcome-blind production audit",
  "",
  paste0(
    "- Production freeze SHA-256: `",
    LMV2_P5_PRODUCTION_FREEZE_SHA256, "`."),
  "- All coverage figures in this package are realized under the frozen P5.3 specification.",
  "- No outcome table was read and no treatment effect was estimated.",
  sprintf(
    "- Realized aggregate inventor coverage: %.2f%%.",
    100 * aggregate_coverage),
  sprintf(
    "- Minimum realized cohort coverage: %.2f%%.",
    100 * min(score$by_cohort$coverage)),
  sprintf(
    "- Minimum realized productivity-quartile coverage: %.2f%%.",
    100 * min(score$by_quartile$coverage)),
  sprintf(
    "- Primary-feasible cohorts: %d/%d.",
    sum(comparison_map$primary_feasible),
    nrow(comparison_map)),
  sprintf(
    "- Equal-deal-feasible cohorts: %d/%d.",
    sum(comparison_map$equal_deal_feasible),
    nrow(comparison_map)),
  "",
  "The headline estimand is the ATT for treated inventors with clean common support. Cohorts flagged in `scope_review_flags.csv` require qualified cohort-specific interpretation.")
writeLines(
  lines, file.path(output_dir, "p5_final_production_audit.md"),
  useBytes = TRUE)

message("P5.3 finalization complete: ", output_dir)
