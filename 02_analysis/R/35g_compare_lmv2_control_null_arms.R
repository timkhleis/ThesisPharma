# ============================================================================
# Compare patent-continuity selection with the censoring-clean null arm
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}

continuity_path <- normalizePath(
  arg("conditioned"), winslash = "/", mustWork = TRUE)
unrestricted_path <- normalizePath(
  arg("unrestricted"), winslash = "/", mustWork = TRUE)
output_path <- arg("output")

continuity <- utils::read.csv(
  continuity_path, stringsAsFactors = FALSE)
unrestricted <- utils::read.csv(
  unrestricted_path, stringsAsFactors = FALSE)
if (nrow(continuity) != 1L ||
    continuity$assignment_arm !=
      "patent_continuity_conditioned") {
  stop("Continuity-conditioned summary has the wrong arm label")
}
if (nrow(unrestricted) != 1L ||
    unrestricted$assignment_arm !=
      "unrestricted_censoring_clean") {
  stop("Censoring-clean summary has the wrong arm label")
}
if (continuity$sample != "buffered_1994_2008" ||
    unrestricted$sample != "buffered_1994_2008") {
  stop("Arm comparison requires the shared 1994-2008 sample")
}

comparison <- rbind(unrestricted, continuity)
comparison$continuity_minus_unrestricted_mean <- c(
  NA_real_,
  continuity$placebo_mean - unrestricted$placebo_mean)
dir.create(
  dirname(output_path), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(comparison, output_path, row.names = FALSE, na = "")
