# Baseline and mutation tooth tests for every P6/P5c frozen input.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Missing package: digest")
}
source(file.path(BASE, "R", "20b_lmv2_p6_p5c_freeze.R"))

items <- c(
  list(freeze = list(
    path = LMV2_P6_P5C_FREEZE_PATH,
    sha256 = LMV2_P6_P5C_FREEZE_SHA256)),
  LMV2_P6_P5C_INPUTS)
results <- do.call(rbind, lapply(names(items), function(label) {
  item <- items[[label]]
  lmv2_p6_p5c_assert_hash(item$path, item$sha256, label)
  temp <- tempfile(paste0("p6_p5c_tooth_", label, "_"))
  if (!file.copy(item$path, temp, overwrite = TRUE)) {
    stop("Could not create tooth-test copy for ", label)
  }
  cat("\nP6_P5C_TOOTH_MUTATION\n", file = temp, append = TRUE)
  rejected <- inherits(
    try(
      lmv2_p6_p5c_assert_hash(
        temp, item$sha256, label),
      silent = TRUE),
    "try-error")
  unlink(temp)
  data.frame(
    check = label,
    baseline_pass = TRUE,
    mutated_file_rejected = rejected,
    pass = rejected,
    stringsAsFactors = FALSE)
}))
out <- file.path(
  BASE, "output", "audit", "local_match_v2",
  "P6_P5C_FREEZE_TOOTH_TESTS.csv")
utils::write.csv(results, out, row.names = FALSE)
if (!all(results$pass)) {
  stop(
    "P6/P5c freeze tooth test failed for: ",
    paste(results$check[!results$pass], collapse = ", "))
}
message(
  "P6/P5c freeze baseline and ", nrow(results),
  " mutation tooth tests passed")

