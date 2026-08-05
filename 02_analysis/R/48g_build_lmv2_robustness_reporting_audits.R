# ============================================================================
# 48g_build_lmv2_robustness_reporting_audits.R
# ============================================================================
# Corrects two reporting issues without re-estimation:
#   1. LOYO stability applies to holdouts -5..-2, not the t=-1 timing check.
#   2. The lead multiplicity family is Holm m=8; per-outcome m=4 is shown as
#      a transparent secondary, post-hoc family.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}
LOYO <- get_arg("--loyo")
HETEROGENEITY <- get_arg("--heterogeneity")
OUTPUT_DIR <- get_arg("--output-dir")
if (any(is.na(c(LOYO, HETEROGENEITY, OUTPUT_DIR)))) {
  stop("48g requires --loyo=, --heterogeneity=, and --output-dir=")
}
if (!file.exists(LOYO) || !file.exists(HETEROGENEITY)) stop("Input file missing")
if (dir.exists(OUTPUT_DIR) && length(list.files(
  OUTPUT_DIR, all.files = TRUE, no.. = TRUE
))) stop("Output directory must be new or empty: ", OUTPUT_DIR)
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

loyo <- utils::read.csv(LOYO, stringsAsFactors = FALSE)
needed_loyo <- c("design", "reference_period", "estimate")
if (!all(needed_loyo %in% names(loyo))) stop("LOYO table lacks required columns")
headline <- loyo[loyo$design == "P5c headline", , drop = FALSE]
if (nrow(headline) != 1L) stop("Expected one P5c headline row")
loyo$heldout_period <- suppressWarnings(as.integer(sub(
  ".*t=", "", loyo$design
)))
loyo$diagnostic_role <- ifelse(
  loyo$design == "P5c headline", "headline",
  ifelse(
    loyo$heldout_period %in% -5:-2,
    "mean_reversion_loyo",
    "timing_reference_sensitivity"
  )
)
loyo$absolute_deviation <- abs(loyo$estimate - headline$estimate[[1]])
loyo$relative_magnitude_change <- ifelse(
  loyo$design == "P5c headline", 0,
  abs(loyo$estimate / headline$estimate[[1]]) - 1
)
loyo$stable_mean_reversion_grid <-
  loyo$diagnostic_role == "mean_reversion_loyo" &
  loyo$absolute_deviation <= 0.005
loyo$timing_flag <-
  loyo$diagnostic_role == "timing_reference_sensitivity" &
  loyo$relative_magnitude_change >= 0.25
utils::write.csv(
  loyo, file.path(OUTPUT_DIR, "corrected_loyo_timing_classification.csv"),
  row.names = FALSE, na = ""
)

timing <- data.frame(
  headline_reference = headline$reference_period[[1]],
  headline_estimate = headline$estimate[[1]],
  alternative_reference = loyo$reference_period[
    loyo$diagnostic_role == "timing_reference_sensitivity"
  ][[1]],
  alternative_estimate = loyo$estimate[
    loyo$diagnostic_role == "timing_reference_sensitivity"
  ][[1]],
  magnitude_change_percent = 100 * loyo$relative_magnitude_change[
    loyo$diagnostic_role == "timing_reference_sensitivity"
  ][[1]],
  conclusion = paste(
    "LOYO -5 through -2 is stable; holding out -1 changes the reference",
    "period and is a timing/anticipation sensitivity, not part of the",
    "mean-reversion stability claim."
  ),
  anticipation_1_status = "not_identified_by_loyo_requires_timing_resolution",
  stringsAsFactors = FALSE
)
utils::write.csv(
  timing, file.path(OUTPUT_DIR, "timing_reference_summary.csv"),
  row.names = FALSE, na = ""
)

het <- utils::read.csv(HETEROGENEITY, stringsAsFactors = FALSE)
needed_het <- c(
  "outcome", "moderator", "governing_p", "holm_adjusted_governing_p",
  "reporting_status"
)
if (!all(needed_het %in% names(het))) stop("Heterogeneity table lacks required columns")
primary <- het[
  het$reporting_status == "included_primary_heterogeneity_table",
  needed_het, drop = FALSE
]
if (nrow(primary) != 8L || anyDuplicated(primary[c("outcome", "moderator")])) {
  stop("Expected exactly eight primary heterogeneity contrasts")
}
primary$holm_m8_recomputed <- stats::p.adjust(primary$governing_p, "holm")
if (max(abs(
  primary$holm_m8_recomputed - primary$holm_adjusted_governing_p
)) > 1e-12) stop("Stored Holm m=8 values do not reproduce")
primary$holm_m4_within_outcome <- ave(
  primary$governing_p, primary$outcome,
  FUN = function(p) stats::p.adjust(p, "holm")
)
primary$survives_lead_m8_005 <- primary$holm_m8_recomputed < 0.05
primary$survives_secondary_m4_005 <- primary$holm_m4_within_outcome < 0.05
primary$lead_family <- "all_8_primary_contrasts"
primary$secondary_family <- "4_contrasts_within_outcome_posthoc"
utils::write.csv(
  primary, file.path(OUTPUT_DIR, "heterogeneity_holm_families.csv"),
  row.names = FALSE, na = ""
)

manifest <- data.frame(
  version = "lmv2_robustness_reporting_audit_v1",
  lead_multiplicity_family = "Holm_m8",
  n_lead_significant_005 = sum(primary$survives_lead_m8_005),
  secondary_family = "Holm_m4_within_outcome_posthoc",
  n_secondary_significant_005 = sum(primary$survives_secondary_m4_005),
  timing_sensitivity_flag = timing$magnitude_change_percent >= 25,
  loyo_sha256 = digest::digest(file = LOYO, algo = "sha256"),
  heterogeneity_sha256 = digest::digest(
    file = HETEROGENEITY, algo = "sha256"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(OUTPUT_DIR, "robustness_reporting_audit_manifest.csv"),
  row.names = FALSE, na = ""
)
message("Robustness reporting audit complete")

