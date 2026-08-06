# Assemble and certify the 17-cohort cardinality-matching design package.

args <- commandArgs(trailingOnly = TRUE)
hit <- args[startsWith(args, "--cardinality-root=")]
if (!length(hit)) stop("Missing --cardinality-root=...")
root <- normalizePath(
  sub("^--cardinality-root=", "", hit[[1]]),
  winslash = "/", mustWork = TRUE)
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "20b_lmv2_cardinality_engine.R"))

scheduler_path <- file.path(root, "cardinality_scheduler_status.csv")
if (!file.exists(scheduler_path)) stop("Cardinality scheduler status is missing")
scheduler <- utils::read.csv(
  scheduler_path, stringsAsFactors = FALSE)
if (!identical(sort(scheduler$cohort), 1994:2010) ||
    any(scheduler$status != "complete")) {
  stop("The 17-cohort cardinality run is incomplete")
}
coverage_paths <- list.files(
  root, pattern = "^cardinality_coverage\\.csv$",
  recursive = TRUE, full.names = TRUE)
manifest_paths <- list.files(
  root, pattern = "^cardinality_manifest\\.csv$",
  recursive = TRUE, full.names = TRUE)
balance_paths <- list.files(
  root, pattern = "^cardinality_balance\\.csv$",
  recursive = TRUE, full.names = TRUE)
if (any(c(
    length(coverage_paths), length(manifest_paths),
    length(balance_paths)) != 17L)) {
  stop("Expected one cardinality artifact set per cohort")
}
coverage <- do.call(rbind, lapply(
  coverage_paths, utils::read.csv, stringsAsFactors = FALSE))
manifest <- do.call(rbind, lapply(
  manifest_paths, utils::read.csv, stringsAsFactors = FALSE))
balance <- do.call(rbind, lapply(seq_along(balance_paths), function(index) {
  x <- utils::read.csv(
    balance_paths[[index]], stringsAsFactors = FALSE)
  x$cohort <- rep(
    as.integer(sub(
      ".*cohort_([0-9]{4}).*", "\\1",
      normalizePath(
        balance_paths[[index]], winslash = "/", mustWork = TRUE))),
    nrow(x))
  x
}))
if (!identical(sort(coverage$cohort), 1994:2010) ||
    !identical(sort(manifest$cohort), 1994:2010)) {
  stop("Cardinality cohort identities are incomplete")
}
weight_rows <- manifest[
  manifest$status == "optimal", , drop = FALSE]
for (index in seq_len(nrow(weight_rows))) {
  if (!file.exists(weight_rows$path[[index]]) ||
      !identical(
        lmv2_p3_file_hash(weight_rows$path[[index]]),
        weight_rows$checksum[[index]])) {
    stop("Cardinality weight checksum failed at row ", index)
  }
}
if (nrow(balance) &&
    any(abs(balance$smd) >
      LMV2_CARDINALITY$maximum_balance_smd + 1e-6)) {
  stop("A cardinality cohort violates the frozen balance tolerance")
}
coverage <- coverage[order(coverage$cohort), ]
manifest <- manifest[order(manifest$cohort), ]
if (nrow(balance)) balance <- balance[order(balance$cohort), ]
utils::write.csv(
  coverage, file.path(root, "cardinality_coverage_all.csv"),
  row.names = FALSE)
utils::write.csv(
  manifest, file.path(root, "cardinality_manifest_all.csv"),
  row.names = FALSE)
utils::write.csv(
  balance, file.path(root, "cardinality_balance_all.csv"),
  row.names = FALSE)

totals <- data.frame(
  full_treated = sum(coverage$full_treated),
  entropy_supported = sum(coverage$entropy_supported),
  cardinality_recovered = sum(coverage$cardinality_recovered),
  still_unsupported = sum(coverage$still_unsupported),
  entropy_share =
    sum(coverage$entropy_supported) / sum(coverage$full_treated),
  recovered_share =
    sum(coverage$cardinality_recovered) / sum(coverage$full_treated),
  combined_descriptive_share =
    sum(
      coverage$entropy_supported +
        coverage$cardinality_recovered) /
      sum(coverage$full_treated),
  optimal_cohorts = sum(manifest$status == "optimal"),
  zero_recovery_cohorts = sum(manifest$status != "optimal"),
  stringsAsFactors = FALSE)
utils::write.csv(
  totals, file.path(root, "cardinality_totals.csv"),
  row.names = FALSE)
message(
  "Cardinality finalization complete: recovered ",
  totals$cardinality_recovered, " previously unsupported inventors")
