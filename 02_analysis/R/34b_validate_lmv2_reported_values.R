#!/usr/bin/env Rscript

# ============================================================================
# 34b_validate_lmv2_reported_values.R
#
# C1 gate: extract declared core numerical results from active notes,
# handovers, and thesis assets; compare them with the certified master
# inventory at the precision displayed; reject superseded decomposition
# values in active documents; and record the authoritative manuscript.
# ============================================================================

options(stringsAsFactors = FALSE, scipen = 999)

if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Package 'digest' is required")
}

ROOT <- normalizePath(".", winslash = "/", mustWork = TRUE)
RESULT_DIR <- file.path(
  ROOT, "02_analysis", "output", "results", "local_match_v2"
)
INVENTORY_DIR <- file.path(
  RESULT_DIR, "CURRENT_LOCAL_MATCH_V2", "results_inventory"
)
INVENTORY_PATH <- file.path(
  INVENTORY_DIR, "master_results_inventory.csv"
)
INVENTORY_CERT <- file.path(
  INVENTORY_DIR, "master_results_inventory_certification.csv"
)
CONTROL_ENDPOINT_CERT <- file.path(
  ROOT, "02_analysis", "output", "audit", "local_match_v2",
  "C1_CONTROL_ENDPOINT_DIAGNOSTIC", "control_endpoint_certification.csv"
)
P8_CERT <- file.path(
  ROOT, "02_analysis", "output", "audit", "local_match_v2",
  "P8_EXIT_DECOMPOSITION", "exit_decomposition_certification.csv"
)
SUPERVISOR_CERT <- file.path(
  RESULT_DIR, "supervisor_package", "certification.csv"
)

candidate_main_root <- normalizePath(
  file.path(ROOT, "..", ".."), winslash = "/", mustWork = TRUE
)
MAIN_ROOT <- if (
  file.exists(file.path(candidate_main_root, "00_Discussion_Docs",
                        "014_research_partner_progress_update_2026-07-29.tex"))
) {
  candidate_main_root
} else {
  ROOT
}

paths <- c(
  current_start_note = file.path(
    ROOT, "02_analysis", "notes",
    "current_local_match_v2_start_here.md"
  ),
  master_inventory_note = file.path(
    ROOT, "02_analysis", "notes",
    "local_match_v2_master_results_inventory.md"
  ),
  retained_results_note = file.path(
    ROOT, "02_analysis", "notes",
    "local_match_v2_stayer_heterogeneity_results.md"
  ),
  supervisor_p8_table = file.path(
    RESULT_DIR, "supervisor_package",
    "generated_stayer_decomposition_table.tex"
  ),
  thesis_vision_handover = file.path(
    MAIN_ROOT, "00_Discussion_Docs",
    "013_research_partner_thesis_vision_handover.tex"
  ),
  current_partner_update = file.path(
    MAIN_ROOT, "00_Discussion_Docs",
    "014_research_partner_progress_update_2026-07-29.tex"
  ),
  current_partner_pdf = file.path(
    MAIN_ROOT, "00_Discussion_Docs",
    "014_research_partner_progress_update_2026-07-29.pdf"
  ),
  authoritative_manuscript = file.path(
    MAIN_ROOT, "thesis_template", "main.tex"
  ),
  historical_handover_012 = file.path(
    MAIN_ROOT, "00_Discussion_Docs",
    "012_research_partner_methodology_results_handover.tex"
  ),
  historical_partner_docx = file.path(
    MAIN_ROOT, "00_Discussion_Docs",
    "014_research_partner_progress_update_2026-07-29.docx"
  )
)
required <- c(
  INVENTORY_PATH, INVENTORY_CERT, CONTROL_ENDPOINT_CERT,
  P8_CERT, SUPERVISOR_CERT, paths
)
missing <- required[!file.exists(required)]
if (length(missing)) {
  stop("Missing consistency-gate input(s): ", paste(missing, collapse = ", "))
}

read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
read_text <- function(path) {
  paste(
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
}
write_csv <- function(x, name) {
  utils::write.csv(
    x, file.path(INVENTORY_DIR, name), row.names = FALSE, na = ""
  )
}
hash_file <- function(path) {
  digest::digest(file = path, algo = "sha256")
}

inventory <- read_csv(INVENTORY_PATH)
inventory_cert <- read_csv(INVENTORY_CERT)
if (!all(c("check", "pass") %in% names(inventory_cert)) ||
    !all(tolower(as.character(inventory_cert$pass)) == "true")) {
  stop("Master inventory certification does not pass")
}
endpoint_cert <- read_csv(CONTROL_ENDPOINT_CERT)
p8_cert <- read_csv(P8_CERT)
supervisor_cert <- read_csv(SUPERVISOR_CERT)
cert_passes <- function(x) {
  all(c("check", "pass") %in% names(x)) &&
    !anyNA(x$pass) &&
    all(tolower(as.character(x$pass)) == "true")
}

historical_ids <- c(
  "historical_handover_012", "historical_partner_docx"
)
active_ids <- setdiff(names(paths), historical_ids)
active_manifest <- data.frame(
  document_id = active_ids,
  path = normalizePath(
    paths[active_ids], winslash = "/", mustWork = TRUE
  ),
  role = c(
    "current_start_and_authority_note",
    "generated_inventory_note",
    "generated_retained_results_note",
    "generated_supervisor_table",
    "current_conceptual_handover",
    "current_partner_update",
    "compiled_current_partner_update",
    "authoritative_thesis_manuscript"
  ),
  numerical_assertions = c(
    TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE
  ),
  sha256 = vapply(paths[active_ids], hash_file, character(1)),
  stringsAsFactors = FALSE
)
historical_manifest <- data.frame(
  document_id = historical_ids,
  path = normalizePath(
    paths[historical_ids], winslash = "/", mustWork = TRUE
  ),
  status = c(
    "frozen_historical_superseded",
    "frozen_historical_stale_export"
  ),
  superseded_by = rep(normalizePath(
    paths[["current_partner_pdf"]],
    winslash = "/", mustWork = TRUE
  ), 2L),
  sha256 = vapply(paths[historical_ids], hash_file, character(1)),
  stringsAsFactors = FALSE
)
manuscript_manifest <- data.frame(
  role = "authoritative_thesis_manuscript",
  path = normalizePath(
    paths[["authoritative_manuscript"]],
    winslash = "/", mustWork = TRUE
  ),
  sha256 = hash_file(paths[["authoritative_manuscript"]]),
  selection_reason = paste(
    "The thesis_template copy is the compiled working manuscript;",
    "dated template exports are distribution snapshots."
  ),
  stringsAsFactors = FALSE
)

write_csv(active_manifest, "active_document_manifest.csv")
write_csv(historical_manifest, "historical_document_manifest.csv")
write_csv(manuscript_manifest, "authoritative_manuscript.csv")

find_result <- function(domain = NULL, population = NULL, outcome = NULL,
                        analysis = NULL, sample = NULL) {
  keep <- rep(TRUE, nrow(inventory))
  if (!is.null(domain)) keep <- keep & inventory$domain == domain
  if (!is.null(population)) keep <- keep & inventory$population == population
  if (!is.null(outcome)) keep <- keep & inventory$outcome == outcome
  if (!is.null(analysis)) keep <- keep & inventory$analysis == analysis
  if (!is.null(sample)) keep <- keep & inventory$sample == sample
  z <- inventory[keep, , drop = FALSE]
  if (nrow(z) != 1L) {
    stop(
      "Inventory selector returned ", nrow(z), " rows: ",
      paste(c(domain, population, outcome, analysis, sample), collapse = " | ")
    )
  }
  z
}

full_att <- find_result(
  "aggregate", "full target-inventor cohort", "patent_count",
  "entropy-balanced ATT", "full_1994_2010"
)
retained_att <- find_result(
  "aggregate", "initially retained inventors", "patent_count",
  "separately balanced selected-group ATT", "full_1994_2010"
)
p8_total <- find_result(
  "P8 decomposition", "initially retained inventors", "patent_count",
  "P8 Shapley total", "headline_1994_2010"
)
p8_cessation <- find_result(
  "P8 decomposition", "initially retained inventors", "patent_count",
  "P8 Shapley cessation", "headline_1994_2010"
)
p8_active <- find_result(
  "P8 decomposition", "initially retained inventors", "patent_count",
  "P8 Shapley active_given_survival", "headline_1994_2010"
)
p8_intensive <- find_result(
  "P8 decomposition", "initially retained inventors", "patent_count",
  "P8 Shapley patents_per_active_year", "headline_1994_2010"
)
control_endpoint <- find_result(
  "sample-definition diagnostic", "full target-inventor cohort",
  "patent_count",
  "P5c controls restricted to focal-group patent activity through +5",
  "full_1994_2010"
)
completion_t0 <- find_result(
  "timing", "full target-inventor cohort", "patent_count",
  "completion-year ATT (partially exposed calendar year)",
  "full_1994_2010"
)
completion_cumulative <- find_result(
  "timing", "full target-inventor cohort", "patent_count",
  "completion-through-plus-five cumulative effect",
  "full_1994_2010"
)

extract_capture <- function(document_id, pattern, capture) {
  path <- active_manifest$path[
    active_manifest$document_id == document_id
  ]
  if (length(path) != 1L) stop("Unknown active document: ", document_id)
  text <- gsub("\\s+", " ", read_text(path), perl = TRUE)
  m <- regexec(pattern, text, perl = TRUE)
  hit <- regmatches(text, m)[[1]]
  if (!length(hit) || length(hit) <= capture) {
    stop(
      "Pattern did not yield capture ", capture,
      " in ", document_id, ": ", pattern
    )
  }
  value <- suppressWarnings(as.numeric(hit[[capture + 1L]]))
  if (!is.finite(value)) {
    stop("Captured value is not numeric in ", document_id)
  }
  value
}

assertion_rows <- list()
add_assertions <- function(document_id, result, pattern, fields, captures,
                           digits, scale = 1) {
  if (length(fields) != length(captures) ||
      length(fields) != length(digits)) {
    stop("Malformed assertion specification")
  }
  for (i in seq_along(fields)) {
    observed <- extract_capture(document_id, pattern, captures[[i]])
    expected <- as.numeric(result[[fields[[i]]]]) * scale
    tolerance <- 0.5 * 10^(-digits[[i]]) + 1e-12
    assertion_rows[[length(assertion_rows) + 1L]] <<- data.frame(
      document_id = document_id,
      result_id = result$result_id,
      field = fields[[i]],
      observed = observed,
      expected = expected,
      display_digits = digits[[i]],
      tolerance = tolerance,
      difference = observed - expected,
      pass = is.finite(expected) &&
        abs(observed - expected) <= tolerance,
      pattern = pattern,
      stringsAsFactors = FALSE
    )
  }
}

partner_full_pattern <- paste0(
  "Annual patent-count ATT\\s*&\\s*\\$(-?[0-9.]+)\\$\\s*&\\s*",
  "\\$\\[(-?[0-9.]+),(-?[0-9.]+)\\]\\$"
)
partner_retained_pattern <- paste0(
  "Initially retained patent-count ATT\\s*&\\s*\\$(-?[0-9.]+)\\$\\s*&\\s*",
  "\\$\\[(-?[0-9.]+),(-?[0-9.]+)\\]\\$"
)
partner_completion_pattern <- paste0(
  "Completion-year ATT \\(\\$t=0\\$\\)\\s*&\\s*",
  "\\$(-?[0-9.]+)\\$\\s*&\\s*",
  "\\$\\[(-?[0-9.]+),(-?[0-9.]+)\\]\\$"
)
partner_completion_cumulative_pattern <- paste0(
  "Completion-through-\\$\\+5\\$ cumulative effect\\s*&\\s*",
  "\\$(-?[0-9.]+)\\$\\s*&\\s*",
  "\\$\\[(-?[0-9.]+),(-?[0-9.]+)\\]\\$"
)
partner_p8_pattern <- paste0(
  "Initially retained\\s*&\\s*\\$(-?[0-9.]+)\\$\\s*&\\s*",
  "\\$(-?[0-9.]+)\\$\\s*&\\s*\\$(-?[0-9.]+)\\$\\s*&\\s*",
  "\\$(-?[0-9.]+)\\$"
)
partner_p8_share_pattern <- paste0(
  "Initially retained\\s*&.*?Share of total\\s*&\\s*100\\\\%\\s*&\\s*",
  "([0-9.]+)\\\\%\\s*&\\s*([0-9.]+)\\\\%\\s*&\\s*",
  "([0-9.]+)\\\\%"
)

add_assertions(
  "current_partner_update", full_att, partner_full_pattern,
  c("estimate", "ci_low", "ci_high"), 1:3, c(4L, 4L, 4L)
)
add_assertions(
  "current_partner_update", retained_att, partner_retained_pattern,
  c("estimate", "ci_low", "ci_high"), 1:3, c(4L, 4L, 4L)
)
add_assertions(
  "current_partner_update", completion_t0, partner_completion_pattern,
  c("estimate", "ci_low", "ci_high"), 1:3, c(4L, 4L, 4L)
)
add_assertions(
  "current_partner_update", completion_cumulative,
  partner_completion_cumulative_pattern,
  c("estimate", "ci_low", "ci_high"), 1:3, c(3L, 3L, 3L)
)
add_assertions(
  "current_partner_update", p8_total, partner_p8_pattern,
  "estimate", 1L, 4L
)
add_assertions(
  "current_partner_update", p8_cessation, partner_p8_pattern,
  "estimate", 2L, 4L
)
add_assertions(
  "current_partner_update", p8_active, partner_p8_pattern,
  "estimate", 3L, 4L
)
add_assertions(
  "current_partner_update", p8_intensive, partner_p8_pattern,
  "estimate", 4L, 4L
)
add_assertions(
  "current_partner_update", p8_cessation, partner_p8_share_pattern,
  "component_share", 1L, 1L, scale = 100
)
add_assertions(
  "current_partner_update", p8_active, partner_p8_share_pattern,
  "component_share", 2L, 1L, scale = 100
)
add_assertions(
  "current_partner_update", p8_intensive, partner_p8_share_pattern,
  "component_share", 3L, 1L, scale = 100
)

vision_att_pattern <- paste0(
  "ATT of \\$(-?[0-9.]+)\\$ per year.*?",
  "interval is\\s*\\$\\[(-?[0-9.]+),(-?[0-9.]+)\\]\\$, ",
  "\\$p=([0-9.]+)\\$"
)
vision_p8_share_pattern <- paste0(
  "decomposition assigns ([0-9.]+)\\\\%.*?",
  "([0-9.]+)\\\\% to fewer active years.*?",
  "([0-9.]+)\\\\% to fewer patents"
)
add_assertions(
  "thesis_vision_handover", retained_att, vision_att_pattern,
  c("estimate", "ci_low", "ci_high", "p_value"),
  1:4, c(4L, 4L, 4L, 3L)
)
add_assertions(
  "thesis_vision_handover", p8_cessation, vision_p8_share_pattern,
  "component_share", 1L, 1L, scale = 100
)
add_assertions(
  "thesis_vision_handover", p8_active, vision_p8_share_pattern,
  "component_share", 2L, 1L, scale = 100
)
add_assertions(
  "thesis_vision_handover", p8_intensive, vision_p8_share_pattern,
  "component_share", 3L, 1L, scale = 100
)

supervisor_component_pattern <- function(label) {
  paste0(
    label, "\\s*&\\s*(-?[0-9.]+)\\s*&\\s*(-?[0-9.]+)",
    "\\s*&\\s*([0-9.]+)\\\\%"
  )
}
for (spec in list(
  list("Earlier end of observed patenting", p8_cessation),
  list("Fewer active years among patenting survivors", p8_active),
  list("Fewer patents per active year", p8_intensive),
  list("Total", p8_total)
)) {
  add_assertions(
    "supervisor_p8_table", spec[[2]],
    supervisor_component_pattern(spec[[1]]),
    c("estimate", "five_year_effect", "component_share"),
    1:3, c(3L, 3L, 1L), scale = 1
  )
}
# The share capture in the supervisor table is displayed in percent.
last_rows <- (length(assertion_rows) - 11L):length(assertion_rows)
for (i in last_rows) {
  if (assertion_rows[[i]]$field == "component_share") {
    assertion_rows[[i]]$expected <- assertion_rows[[i]]$expected * 100
    assertion_rows[[i]]$difference <-
      assertion_rows[[i]]$observed - assertion_rows[[i]]$expected
    assertion_rows[[i]]$pass <-
      abs(assertion_rows[[i]]$difference) <= assertion_rows[[i]]$tolerance
  }
}

retained_note_pattern <- paste0(
  "aggregate patent-count ATT is (-?[0-9.]+).*?",
  "95% CI (-?[0-9.]+) to (-?[0-9.]+); p=([0-9.]+)"
)
add_assertions(
  "retained_results_note", retained_att, retained_note_pattern,
  c("estimate", "ci_low", "ci_high", "p_value"),
  1:4, c(3L, 3L, 3L, 3L)
)

start_endpoint_pattern <- paste0(
  "contrast of (-?[0-9.]+).*?",
  "95% interval\\s*\\[(-?[0-9.]+),\\s*(-?[0-9.]+)\\], ",
  "p=([0-9.]+)"
)
add_assertions(
  "current_start_note", control_endpoint, start_endpoint_pattern,
  c("estimate", "ci_low", "ci_high", "p_value"),
  1:4, c(4L, 4L, 4L, 3L)
)

assertions <- do.call(rbind, assertion_rows)
write_csv(assertions, "reported_value_assertions.csv")

fmt <- function(x) {
  ifelse(is.na(x), "", formatC(x, digits = 4, format = "f"))
}
expected_note_rows <- vapply(seq_len(nrow(inventory)), function(i) {
  z <- inventory[i, ]
  ci <- if (is.na(z$ci_low) || is.na(z$ci_high)) {
    ""
  } else {
    sprintf("[%s, %s]", fmt(z$ci_low), fmt(z$ci_high))
  }
  sprintf(
    "| %s | %s | %s | %s: %s | %s | %s | %s |",
    z$status, z$reporting_tier, z$population, z$outcome, z$analysis,
    fmt(z$estimate), ci, fmt(z$p_value)
  )
}, character(1))
inventory_note_lines <- readLines(
  paths[["master_inventory_note"]], warn = FALSE, encoding = "UTF-8"
)
note_rows_match <- all(expected_note_rows %in% inventory_note_lines) &&
  sum(startsWith(inventory_note_lines, "| ")) == nrow(inventory) + 1L

active_text_paths <- active_manifest$path[
  tolower(tools::file_ext(active_manifest$path)) %in%
    c("md", "tex", "txt", "csv")
]
active_text <- paste(
  vapply(active_text_paths, read_text, character(1)),
  collapse = "\n"
)
superseded_patterns <- c(
  "29.8\\\\%", "70.2\\\\%", "32.5\\\\%", "67.5\\\\%",
  "symmetric_extensive", "symmetric_intensive"
)
superseded_hits <- vapply(
  superseded_patterns,
  function(pattern) grepl(pattern, active_text, perl = TRUE),
  logical(1)
)

historical_text <- read_text(paths[["historical_handover_012"]])
historical_banner_present <- grepl(
  "FROZEN HISTORICAL RECORD --- NOT THE CURRENT NUMERICAL HANDOVER",
  historical_text, fixed = TRUE
)
historical_excluded <- !any(paths[historical_ids] %in% active_manifest$path)
vision_handover_text <- read_text(paths[["thesis_vision_handover"]])
vision_task_supersession_present <- grepl(
  "CURRENT CONCEPTUAL HANDOVER; IMPLEMENTATION TASK",
  vision_handover_text, fixed = TRUE
) && grepl(
  "LIST SUPERSEDED",
  vision_handover_text, fixed = TRUE
)

checks <- data.frame(
  check = c(
    "master_inventory_certification_passes",
    "control_endpoint_diagnostic_certification_passes",
    "p8_decomposition_certification_passes",
    "supervisor_package_certification_passes",
    "active_document_paths_exist",
    "active_document_ids_unique",
    "compiled_partner_pdf_not_older_than_tex",
    "authoritative_manuscript_unique_and_exists",
    "historical_012_has_supersession_banner",
    "historical_012_excluded_from_active_manifest",
    "active_013_marks_implementation_tasks_superseded",
    "all_declared_values_match_inventory_at_display_precision",
    "master_inventory_note_matches_csv",
    "no_superseded_decomposition_tokens_in_active_documents"
  ),
  pass = c(
    cert_passes(inventory_cert),
    cert_passes(endpoint_cert),
    cert_passes(p8_cert),
    cert_passes(supervisor_cert),
    all(file.exists(active_manifest$path)),
    !anyDuplicated(active_manifest$document_id),
    file.info(paths[["current_partner_pdf"]])$mtime >=
      file.info(paths[["current_partner_update"]])$mtime,
    nrow(manuscript_manifest) == 1L &&
      file.exists(manuscript_manifest$path[[1]]),
    historical_banner_present,
    historical_excluded,
    vision_task_supersession_present,
    nrow(assertions) > 0 && all(assertions$pass),
    note_rows_match,
    !any(superseded_hits)
  ),
  value = c(
    paste0(sum(tolower(as.character(inventory_cert$pass)) == "true"),
           "/", nrow(inventory_cert)),
    paste0(sum(tolower(as.character(endpoint_cert$pass)) == "true"),
           "/", nrow(endpoint_cert)),
    paste0(sum(tolower(as.character(p8_cert$pass)) == "true"),
           "/", nrow(p8_cert)),
    paste0(sum(tolower(as.character(supervisor_cert$pass)) == "true"),
           "/", nrow(supervisor_cert)),
    as.character(nrow(active_manifest)),
    as.character(anyDuplicated(active_manifest$document_id)),
    paste(
      file.info(paths[["current_partner_update"]])$mtime,
      file.info(paths[["current_partner_pdf"]])$mtime,
      sep = " <= "
    ),
    manuscript_manifest$path[[1]],
    as.character(historical_banner_present),
    as.character(historical_excluded),
    as.character(vision_task_supersession_present),
    paste0(sum(assertions$pass), "/", nrow(assertions)),
    as.character(note_rows_match),
    paste(
      superseded_patterns[superseded_hits],
      collapse = ";"
    )
  ),
  detail = c(
    "Upstream machine-readable inventory gate.",
    "Full-cohort control endpoint diagnostic is certified and read-only.",
    "The P8 decomposition supplying current shares is certified.",
    "The regenerated supervisor PDF and assets are certified.",
    "All active notes, handovers, assets, and manuscript paths resolve.",
    "Document identifiers must be unique.",
    "The compiled current partner PDF must reflect the current TeX source.",
    "C1 records one manuscript rather than allowing W1 to search.",
    "The stale July 28 numerical handover is visibly historical.",
    "Historical records cannot enter active numerical validation.",
    paste(
      "The active conceptual handover explicitly defers implementation",
      "tasks to the current C2/D1/network plans."
    ),
    "Regex-extracted estimates, intervals, p-values, and shares agree.",
    "Every generated markdown inventory row agrees with the CSV.",
    "Old 29.8/70.2 and 32.5/67.5 decompositions are absent."
  ),
  stringsAsFactors = FALSE
)
write_csv(checks, "reported_value_consistency_certification.csv")
write_csv(checks, "C1_RESULTS_SYNC_CERTIFICATION.csv")
write_csv(data.frame(
  pattern = superseded_patterns,
  active_hit = superseded_hits,
  stringsAsFactors = FALSE
), "superseded_token_audit.csv")

source_files <- file.path(
  ROOT, "02_analysis", "R",
  c(
    "34_build_lmv2_master_results_inventory.R",
    "34b_validate_lmv2_reported_values.R"
  )
)
artifact_files <- file.path(INVENTORY_DIR, c(
  "active_document_manifest.csv",
  "historical_document_manifest.csv",
  "authoritative_manuscript.csv",
  "reported_value_assertions.csv",
  "reported_value_consistency_certification.csv",
  "C1_RESULTS_SYNC_CERTIFICATION.csv",
  "superseded_token_audit.csv"
))
manifest_paths <- c(
  source_files, INVENTORY_PATH, INVENTORY_CERT, CONTROL_ENDPOINT_CERT,
  P8_CERT, SUPERVISOR_CERT,
  active_manifest$path, historical_manifest$path, artifact_files
)
manifest <- data.frame(
  path = normalizePath(manifest_paths, winslash = "/", mustWork = TRUE),
  sha256 = vapply(
    manifest_paths, digest::digest, character(1),
    file = TRUE, algo = "sha256"
  ),
  bytes = unname(file.info(manifest_paths)$size),
  stringsAsFactors = FALSE
)
write_csv(manifest, "reported_value_consistency_manifest.csv")

if (!all(checks$pass)) {
  stop(
    "Reported-value consistency certification failed: ",
    paste(checks$check[!checks$pass], collapse = ", ")
  )
}
message(
  "C1 reported-value consistency gate passed: ",
  normalizePath(INVENTORY_DIR, winslash = "/", mustWork = TRUE)
)
