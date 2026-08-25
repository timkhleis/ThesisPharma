#!/usr/bin/env Rscript

# Certify the selection-bounds reporting decision. Ordinary Lee bounds require
# a treatment-induced selection indicator with defensible monotonicity and
# exchangeability. Initial retention is defined only after acquisition using
# patent affiliation, and both positive and negative selection are empirically
# plausible. The code therefore records non-identification instead of emitting
# mechanically trimmed numbers with a causal label.

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
OUT <- file.path(ROOT, "SELECTION_BOUNDS_DECISION")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}

selection <- utils::read.csv(
  file.path(
    BASE, "output", "results", "local_match_v2_1993_amendment",
    "stayer_heterogeneity", "table_stayer_selection_summary.csv"
  ),
  stringsAsFactors = FALSE
)
required <- c("initially_retained", "leaver", "no_post_patent")
status_col <- if ("retention_status" %in% names(selection)) {
  "retention_status"
} else if ("status" %in% names(selection)) {
  "status"
} else {
  stop("Selection table has no status column")
}

decision <- data.frame(
  analysis = "ordinary_Lee_2009_bounds",
  status = "not_identified_not_reported",
  cohort_window = "1993--2010",
  monotonic_selection_established = FALSE,
  exchangeable_selection_indicator = FALSE,
  bounded_outcome_support_available = FALSE,
  reason = paste(
    "Initial retention is a post-acquisition patent-affiliation classification;",
    "the data allow both positive and negative selection, and patent counts",
    "have no defensible finite upper support. Ordinary Lee trimming would not",
    "identify a causal stayer ATT under the current design."
  ),
  thesis_action = paste(
    "Remove the promised Lee-bounds result. Report the observed pre-deal",
    "selection contrasts and interpret retained-inventor estimates as",
    "selected-group evidence."
  )
)
write_csv(decision, "selection_bounds_decision.csv")

cert <- data.frame(
  check = c(
    "selection_table_has_three_statuses",
    "monotonicity_not_assumed_without_evidence",
    "ordinary_Lee_numbers_not_emitted",
    "thesis_action_recorded"
  ),
  pass = c(
    all(required %in% selection[[status_col]]),
    !decision$monotonic_selection_established,
    decision$status == "not_identified_not_reported",
    nzchar(decision$thesis_action)
  ),
  value = c(
    paste(sort(unique(selection[[status_col]])), collapse = ";"),
    FALSE, decision$status, decision$thesis_action
  ),
  detail = c(
    "retained, leaver, and no-post classifications are present",
    "direction of selection remains empirically open",
    "no invalid trimming estimate is released",
    "selected-group interpretation replaces the unsupported promise"
  )
)
write_csv(cert, "selection_bounds_certification.csv")
message("Selection-bounds decision written to: ", OUT)
if (!all(cert$pass)) quit(status = 1L)
