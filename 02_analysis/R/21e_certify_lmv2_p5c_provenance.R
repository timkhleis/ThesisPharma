# Tooth-test every P5c provenance guard against a real mutated file.

args <- commandArgs(trailingOnly = TRUE)
hit <- args[startsWith(args, "--weight-manifest=")]
if (length(hit) != 1L) stop("Missing --weight-manifest=...")
source_manifest_path <- normalizePath(
  sub("^--weight-manifest=", "", hit),
  winslash = "/", mustWork = TRUE)

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(
  BASE, "R", "21a_lmv2_p5c_annual_trajectory_config.R"))
source(file.path(
  BASE, "R", "21d_lmv2_p5c_provenance_lock.R"))

lmv2_p5c_assert_provenance(source_manifest_path)
provenance <- lmv2_p5c_provenance(source_manifest_path)
paths <- c(
  config = file.path(
    BASE, "R", "21a_lmv2_p5c_annual_trajectory_config.R"),
  runner = file.path(
    BASE, "R", "21b_run_lmv2_p5c_annual_trajectory.R"),
  freeze = LMV2_P5C$freeze_note,
  source_manifest = source_manifest_path,
  matching_config = file.path(
    BASE, "R", "16a_lmv2_matching_config.R"),
  matching_utils = file.path(
    BASE, "R", "16c_lmv2_matching_utils.R"),
  ebal_config = file.path(
    BASE, "R", "17f_lmv2_p4_ebal_config.R"),
  ebal_utils = file.path(
    BASE, "R", "17g_lmv2_p4_ebal_utils.R"),
  hybrid_core = file.path(
    BASE, "R", "17l_lmv2_p4_hybrid_core.R"),
  cohort_core = file.path(
    BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"),
  newton_solver = file.path(
    BASE, "R", "18j_lmv2_p5_newton_solver.R"))

results <- do.call(rbind, lapply(names(paths), function(label) {
  extension <- tools::file_ext(paths[[label]])
  temp <- tempfile(
    paste0("p5c_tooth_", label, "_"),
    fileext = if (nzchar(extension)) paste0(".", extension) else "")
  if (!file.copy(paths[[label]], temp, overwrite = TRUE)) {
    stop("Could not create tooth-test copy for ", label)
  }
  cat("\nP5C_TOOTH_MUTATION\n", file = temp, append = TRUE)
  fired <- inherits(
    try(
      lmv2_p5c_assert_hash(
        temp, provenance[[label]], label),
      silent = TRUE),
    "try-error")
  unlink(temp)
  data.frame(
    check = label,
    baseline_pass = TRUE,
    mutated_file_rejected = fired,
    pass = fired,
    stringsAsFactors = FALSE)
}))

out <- file.path(
  BASE, "output", "audit", "local_match_v2",
  "P5C_ANNUAL_TRAJECTORY", "p5c_provenance_tooth_tests.csv")
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(results, out, row.names = FALSE)
if (!all(results$pass)) {
  stop(
    "P5c provenance tooth test failed for: ",
    paste(results$check[!results$pass], collapse = ", "))
}
message(
  "P5c provenance baseline and ", nrow(results),
  " mutation tooth tests passed")

