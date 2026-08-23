#!/usr/bin/env Rscript

# Outcome-blind deal-value quantile design. The bins are defined over
# acquisitions, not inventors, and are frozen before any outcome is opened.

options(stringsAsFactors = FALSE, scipen = 999)

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NA_character_) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (!length(hit)) return(default)
  if (length(hit) != 1L) stop("Duplicate argument: ", flag)
  sub(paste0("^", flag, "="), "", hit)
}

DEAL_MAP <- get_arg("--deal-map")
OUTPUT_DIR <- get_arg("--output-dir")
EXPECTED_DEALS <- as.integer(get_arg("--expected-deals", "343"))
COHORT_START <- as.integer(get_arg("--cohort-start", "1993"))
COHORT_END <- as.integer(get_arg("--cohort-end", "2010"))
DESIGNATION <- get_arg("--designation", "post_hoc_exploratory")
if (any(is.na(c(DEAL_MAP, OUTPUT_DIR)))) {
  stop("48r requires --deal-map= and --output-dir=")
}
if (anyNA(c(EXPECTED_DEALS, COHORT_START, COHORT_END)) ||
    EXPECTED_DEALS < 10L || COHORT_START > COHORT_END) {
  stop("Invalid expected-deals or cohort range")
}
if (!file.exists(DEAL_MAP)) stop("Deal map missing: ", DEAL_MAP)
if (dir.exists(OUTPUT_DIR) && length(list.files(
    OUTPUT_DIR, all.files = TRUE, no.. = TRUE))) {
  stop("Output directory must be new or empty: ", OUTPUT_DIR)
}
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

deal <- utils::read.csv(DEAL_MAP, stringsAsFactors = FALSE)
required <- c("cohort", "deal_id", "target_value", "n_supported")
if (!all(required %in% names(deal))) {
  stop("Deal map lacks: ", paste(setdiff(required, names(deal)), collapse = ", "))
}
deal <- deal[required]
if (anyDuplicated(deal[c("cohort", "deal_id")]) ||
    any(!is.finite(deal$target_value)) || any(deal$target_value <= 0) ||
    any(!is.finite(deal$n_supported)) || any(deal$n_supported <= 0)) {
  stop("Deal map contains duplicate keys or invalid values")
}
if (nrow(deal) != EXPECTED_DEALS ||
    !identical(sort(unique(deal$cohort)), COHORT_START:COHORT_END)) {
  stop("Deal map does not match the declared frozen roster")
}

# Stable ordering is used only after confirming that no bin boundary cuts a
# target-value tie. Thus identical deal values can never enter different bins.
deal <- deal[order(deal$target_value, deal$deal_id), ]
deal$value_rank <- seq_len(nrow(deal))
deal$decile <- ceiling(10 * deal$value_rank / nrow(deal))
deal$quartile <- ceiling(4 * deal$value_rank / nrow(deal))
deal$decile_label <- sprintf("D%02d", deal$decile)
deal$quartile_label <- sprintf("Q%d", deal$quartile)

boundary_audit <- do.call(rbind, lapply(c(4L, 10L), function(k) {
  do.call(rbind, lapply(seq_len(k - 1L), function(j) {
    index <- ceiling(j * nrow(deal) / k)
    left <- deal$target_value[[index]]
    right <- deal$target_value[[index + 1L]]
    data.frame(
      partition = if (k == 10L) "decile" else "quartile",
      boundary = j,
      left_rank = index,
      left_value = left,
      right_value = right,
      boundary_splits_tie = isTRUE(all.equal(left, right)),
      stringsAsFactors = FALSE
    )
  }))
}))
if (any(boundary_audit$boundary_splits_tie)) {
  stop("A requested quantile boundary splits a target-value tie")
}

summarise_bins <- function(bin, partition) {
  split_deal <- split(deal, bin)
  out <- do.call(rbind, lapply(names(split_deal), function(label) {
    z <- split_deal[[label]]
    data.frame(
      partition = partition,
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
  rownames(out) <- NULL
  out
}

counts <- rbind(
  summarise_bins(deal$decile_label, "decile"),
  summarise_bins(deal$quartile_label, "quartile")
)

write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = "")
}
write_csv(deal, "deal_value_quantile_map.csv")
write_csv(counts, "deal_value_quantile_counts.csv")
write_csv(boundary_audit, "deal_value_quantile_boundary_audit.csv")

manifest <- data.frame(
  version = "lmv2_deal_value_quantile_design_v2",
  designation = DESIGNATION,
  unit_defining_quantiles = "acquisition",
  requested_partitions = "quartiles;deciles",
  tie_rule = "fail_if_empirical_boundary_splits_equal_target_values",
  target_value_units = "thousands_of_currency_units",
  acquisitions = nrow(deal),
  supported_treated_inventors = sum(deal$n_supported),
  cohorts = paste(sort(unique(deal$cohort)), collapse = ";"),
  post_outcomes_opened = FALSE,
  analysis_authorized = TRUE,
  source_deal_map = normalizePath(DEAL_MAP, winslash = "/", mustWork = TRUE),
  stringsAsFactors = FALSE
)
write_csv(manifest, "deal_value_quantile_design_manifest.csv")
message(sprintf(
  "Frozen outcome-blind value quantiles for %d acquisitions (%d--%d); no boundary ties.",
  nrow(deal), COHORT_START, COHORT_END
))
