#!/usr/bin/env Rscript

# Certify the conditional N2 access decision. This script never reads network
# outcome data; it records whether N1 permits a post-treatment build.

options(stringsAsFactors = FALSE)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
if (!requireNamespace("digest", quietly = TRUE)) stop("Missing package: digest")

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
N1 <- file.path(ROOT, "NETWORK_N1_VALIDATION")
OUT <- file.path(ROOT, "NETWORK_N2_ACCESS_DECISION")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

decision_path <- file.path(N1, "network_n1_path_decision.csv")
cert_path <- file.path(N1, "network_n1_certification.csv")
if (!file.exists(decision_path) || !file.exists(cert_path)) {
  stop("Missing certified N1 decision")
}
n1 <- utils::read.csv(
  decision_path, check.names = FALSE, colClasses = "character"
)
n1_cert <- utils::read.csv(cert_path, check.names = FALSE)
if (nrow(n1) != 1L || !all(as.logical(n1_cert$pass))) {
  stop("N1 is not certified")
}

released <- identical(n1$selected_path[[1L]], "N")
access <- data.frame(
  n1_path = n1$selected_path[[1L]],
  n2_released = released,
  post_treatment_network_outcomes_opened = FALSE,
  required_action = if (released) {
    "N2 may be implemented from the frozen N0 definitions."
  } else {
    "Do not materialize or estimate post-treatment network outcomes."
  },
  stringsAsFactors = FALSE
)
utils::write.csv(
  access, file.path(OUT, "network_n2_access_decision.csv"), row.names = FALSE
)

cert <- data.frame(
  check = c(
    "n1_certification_verified", "n2_release_matches_n1_path",
    "post_outcomes_remain_closed_when_not_released"
  ),
  pass = c(
    all(as.logical(n1_cert$pass)), released == (n1$selected_path[[1L]] == "N"),
    released || !access$post_treatment_network_outcomes_opened[[1L]]
  ),
  value = c(
    digest::digest(cert_path, file = TRUE, algo = "sha256"),
    paste(n1$selected_path[[1L]], released, sep = ":"),
    access$post_treatment_network_outcomes_opened[[1L]]
  ),
  detail = c(
    "N1 software certification passes",
    "only certified Path N can release N2",
    "Path Q/F cannot access positive event times"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  cert, file.path(OUT, "network_n2_access_certification.csv"), row.names = FALSE
)
if (!all(cert$pass)) stop("N2 access certification failed")

note <- c(
  "# Local Match v2 network N2 access decision",
  "",
  paste0("N1 selected **Path ", n1$selected_path[[1L]], "**."),
  "",
  access$required_action[[1L]],
  "",
  "No positive-event network outcome was opened by this package."
)
writeLines(note, file.path(OUT, "network_n2_access_decision.md"), useBytes = TRUE)
message("N2 access decision certified: released=", released)
