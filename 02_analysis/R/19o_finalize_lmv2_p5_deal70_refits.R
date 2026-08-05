# Certify and assemble the nine outcome-blind deal-70 refit weight manifests.

args <- commandArgs(trailingOnly = TRUE)
hit <- args[startsWith(args, "--refit-root=")]
if (!length(hit)) stop("Missing --refit-root=...")
refit_root <- normalizePath(
  sub("^--refit-root=", "", hit[[1]]),
  winslash = "/", mustWork = TRUE)
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))

expected_firms <- c(
  100569, 102374, 107670, 108594, 109770,
  200547, 203155, 303292, 307791)
status_paths <- list.files(
  refit_root, pattern = "^deal70_refit_status\\.csv$",
  recursive = TRUE, full.names = TRUE)
manifest_paths <- list.files(
  refit_root, pattern = "^deal70_refit_manifest\\.csv$",
  recursive = TRUE, full.names = TRUE)
weight_manifest_paths <- list.files(
  refit_root, pattern = "^manifest\\.csv$",
  recursive = TRUE, full.names = TRUE)
weight_manifest_paths <- weight_manifest_paths[
  grepl("[/\\\\]weights[/\\\\]manifest\\.csv$", weight_manifest_paths)]
if (length(status_paths) != 9L || length(manifest_paths) != 9L) {
  stop("Expected nine completed deal-70 refit design artifacts")
}
status <- do.call(rbind, lapply(
  status_paths, utils::read.csv, stringsAsFactors = FALSE))
run_manifest <- do.call(rbind, lapply(
  manifest_paths, utils::read.csv, stringsAsFactors = FALSE))
if (!identical(
    sort(as.numeric(status$omitted_control_group)), expected_firms) ||
    !identical(
      sort(as.numeric(run_manifest$omitted_control_group)), expected_firms)) {
  stop("Deal-70 refit firm identities do not match the freeze")
}

weights <- if (length(weight_manifest_paths)) {
  do.call(rbind, lapply(
    weight_manifest_paths, utils::read.csv,
    stringsAsFactors = FALSE))
} else {
  data.frame()
}
if (nrow(weights)) {
  weights$omitted_control_group <- vapply(
    weights$path, function(path) {
      as.numeric(sub(
        ".*omit_firm_([0-9]+).*", "\\1",
        normalizePath(path, winslash = "/", mustWork = TRUE)))
    }, numeric(1))
  for (index in seq_len(nrow(weights))) {
    if (!identical(
        lmv2_p3_file_hash(weights$path[[index]]),
        weights$checksum[[index]])) {
      stop("Deal-70 refit weight checksum failed at row ", index)
    }
  }
}
status$ess_ratio <- status$inventor_ess_reuse_adjusted /
  status$n_supported_treated
status$design_feasible <- status$mode != "infeasible" &
  is.finite(status$max_smd) &
  is.finite(status$ess_ratio) &
  status$ess_ratio >= 0.50
status <- status[order(status$omitted_control_group), ]
if (nrow(weights)) {
  weights <- weights[order(weights$omitted_control_group), ]
}
utils::write.csv(
  status,
  file.path(refit_root, "deal70_refit_design_status_all.csv"),
  row.names = FALSE)
utils::write.csv(
  weights,
  file.path(refit_root, "deal70_refit_weight_manifest_all.csv"),
  row.names = FALSE)
message(
  "Deal-70 refit certification complete: ",
  sum(status$design_feasible), "/9 feasible design refits")
