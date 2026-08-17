# ============================================================================
# 48b_certify_lmv2_ipc_main_group_feasibility.R
# ============================================================================
# Formalizes the prospective P4 technology-resolution gate. The input contains
# the outcome-blind pilot diagnostics recorded on 2026-07-23. A full IPC
# main-group weighting/ATT run is authorized only if every pilot cohort clears
# the locked 80% inventor-retention threshold. This prevents outcomes from
# determining whether the finer design is pursued.

args <- commandArgs(trailingOnly = TRUE)
`%+%` <- function(x, y) paste0(x, y)
get_arg <- function(flag, default = NA_character_) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(default)
  sub(paste0("^", flag, "="), "", hit)
}

INPUT <- get_arg(
  "--input",
  "02_analysis/notes/local_match_v2_ipc_main_group_feasibility_input.csv"
)
SOURCE_NOTE <- get_arg(
  "--source-note",
  "02_analysis/notes/" %+%
    "local_match_v2_p4_ebal_pre_e2_amendment.md"
)
OUTPUT_DIR <- get_arg(
  "--output-dir",
  "02_analysis/output/audit/local_match_v2/ROBUSTNESS_IPC_MAIN_GROUP"
)

if (!file.exists(INPUT)) stop("Feasibility input not found: ", INPUT)
if (!file.exists(SOURCE_NOTE)) stop("Prospective source note not found: ", SOURCE_NOTE)
if (dir.exists(OUTPUT_DIR) && length(list.files(
  OUTPUT_DIR, all.files = TRUE, no.. = TRUE
))) stop("Output directory must be new or empty: ", OUTPUT_DIR)

x <- utils::read.csv(INPUT, stringsAsFactors = FALSE)
required <- c(
  "cohort", "resolution", "stage2_caliper", "inventor_retention",
  "diagnostic_scope", "seed"
)
if (!identical(names(x), required) || nrow(x) != 3L ||
    !identical(as.integer(x$cohort), c(1995L, 2002L, 2009L)) ||
    any(x$resolution != "ipc_main_group") ||
    any(abs(x$stage2_caliper - 1.5) > 1e-12) ||
    any(!is.finite(x$inventor_retention)) ||
    any(x$inventor_retention < 0 | x$inventor_retention > 1)) {
  stop("IPC main-group feasibility input violates its locked schema")
}

minimum_retention <- 0.80
x$minimum_required <- minimum_retention
x$cohort_gate_pass <- x$inventor_retention >= minimum_retention
x$shortfall_pp <- 100 * (x$inventor_retention - minimum_retention)
authorize_att <- all(x$cohort_gate_pass)

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  x, file.path(OUTPUT_DIR, "ipc_main_group_cohort_feasibility.csv"),
  row.names = FALSE, na = ""
)
manifest <- data.frame(
  version = "lmv2_ipc_main_group_feasibility_v1",
  resolution = "ipc_main_group",
  stage2_caliper = 1.5,
  gate = "every_fixed_pilot_cohort_inventor_retention_ge_0.80",
  minimum_observed_retention = min(x$inventor_retention),
  maximum_observed_retention = max(x$inventor_retention),
  failed_cohorts = paste(x$cohort[!x$cohort_gate_pass], collapse = ";"),
  att_authorized = authorize_att,
  status = if (authorize_att) "support_gate_pass" else
    "feasibility_failure_no_att",
  outcome_data_accessed = FALSE,
  source_note_sha256 = digest::digest(
    file = SOURCE_NOTE, algo = "sha256"
  ),
  input_sha256 = digest::digest(file = INPUT, algo = "sha256"),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(OUTPUT_DIR, "ipc_main_group_feasibility_manifest.csv"),
  row.names = FALSE, na = ""
)
message(
  "IPC main-group status: ", manifest$status,
  "; ATT authorized: ", manifest$att_authorized
)

