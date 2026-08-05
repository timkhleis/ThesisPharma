# ============================================================================
# 17k_run_lmv2_p4_ebal.R -- P4-EB outcome-blind source audit + determinism
# ============================================================================
# Requires explicit --mode=certify|production, exactly like 17h/17i, so a
# certification-only invocation can never look ambiguously like a production
# run. --mode=certify: audits 17f-17k for outcome references, then runs the
# synthetic certification (17j) twice into isolated directories and confirms
# identical logical manifests. No database connection is opened. --mode=
# production is not implemented in E1 (E1 is code-only; the real Stage-1/
# Stage-2 orchestration across 17h/17i is deferred to E2, after this design
# is reviewed).

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))

mode <- lmv2_ebal_mode()
audit_dir <- lmv2_ebal_read_arg("audit-dir")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

if (mode == "production") {
  stop("17k --mode=production is not implemented in E1: E1 is code-only ",
       "(synthetic certification and source audit only). Real Stage-1/",
       "Stage-2 orchestration belongs to E2, after review.")
}

p4_ebal_sources <- file.path(BASE, "R", c(
  "17f_lmv2_p4_ebal_config.R", "17g_lmv2_p4_ebal_utils.R",
  "17h_run_lmv2_p4_ebal_stage1.R", "17i_run_lmv2_p4_ebal_stage2.R",
  "17j_certify_lmv2_p4_ebal.R", "17k_run_lmv2_p4_ebal.R"
))

# --- Outcome-blind source audit ---------------------------------------------
# Identical mechanism to 17e_run_lmv2_p4.R's audit (not sourced -- 17e is a
# fixed-weight-pilot file left unedited; this reproduces its exact
# token-filtering approach so P4-EB is held to the same standard). Only
# executable R tokens are scanned: files are parsed and comment tokens are
# excluded, so prose in comments can neither trigger nor mask a violation.
frag <- function(...) paste0(...)
forbidden <- c(
  frag("pq", "ii"), frag("quality", "_index"), frag("forward", "_citations"),
  frag("oe", "cd"), frag("cit", "ation"), frag("tech", "_drift"),
  frag("tech", "drift"), frag("absorbing", "_left"), frag("left", "_onset"),
  frag("event", "_panel"), frag("lmv2", "_p6"), frag("patent", "_enriched"),
  frag("18", "[a-z]_lmv2")
)
audit_pattern <- paste0("\\b(?:", paste(forbidden, collapse = "|"), ")")
violations <- list()
for (path in p4_ebal_sources) {
  pd <- utils::getParseData(parse(path, keep.source = TRUE))
  code <- pd[pd$terminal & pd$token != "COMMENT", , drop = FALSE]
  hits <- grepl(audit_pattern, code$text, ignore.case = TRUE, perl = TRUE)
  if (any(hits)) {
    violations[[basename(path)]] <- data.frame(
      file = basename(path), line = code$line1[hits], token = code$text[hits],
      stringsAsFactors = FALSE
    )
  }
}
if (length(violations)) {
  bad <- do.call(rbind, violations)
  lmv2_ebal_write_csv(bad, audit_dir, "p4_ebal_source_audit_violations.csv")
  stop("P4-EB source audit found outcome references in: ",
       paste(unique(bad$file), collapse = ", "))
}

source_hashes <- do.call(rbind, lapply(
  c(p4_ebal_sources, LMV2_P4_EBAL_PATHS$amendment), function(p) {
    data.frame(file = basename(p), sha256 = lmv2_p3_file_hash(p), stringsAsFactors = FALSE)
  }))
source_hashes$p4_ebal_version <- LMV2_P4_EBAL_VERSION
source_hashes$p4_ebal_config_hash <- LMV2_P4_EBAL_CONFIG_HASH
lmv2_ebal_write_csv(source_hashes, audit_dir, "p4_ebal_source_hashes.csv")

# --- Twice-run synthetic certification, compared for determinism -----------
rscript <- file.path(R.home("bin"), "Rscript.exe")
run_certification <- function(run_dir) {
  if (dir.exists(run_dir) && length(list.files(run_dir, recursive = TRUE))) {
    stop("Run directory already populated; refusing restart-skipped results: ", run_dir)
  }
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
  status <- system2(rscript, c(
    shQuote(file.path(BASE, "R", "17j_certify_lmv2_p4_ebal.R"), type = "cmd"),
    shQuote(paste0("--audit-dir=", run_dir), type = "cmd")
  ))
  if (!identical(status, 0L)) stop("P4-EB certification run failed in ", run_dir)
}

run1_dir <- file.path(audit_dir, "certify_run1")
run2_dir <- file.path(audit_dir, "certify_run2")
run_certification(run1_dir)
run_certification(run2_dir)

first <- lmv2_ebal_logical_manifest(run1_dir)
second <- lmv2_ebal_logical_manifest(run2_dir)
deterministic <- identical(first, second)
comparison <- merge(first[c("file", "rows", "logical_sha256")],
                    second[c("file", "rows", "logical_sha256")],
                    by = "file", all = TRUE, suffixes = c("_run1", "_run2"))
comparison$identical <- !is.na(comparison$logical_sha256_run1) &
  !is.na(comparison$logical_sha256_run2) &
  comparison$logical_sha256_run1 == comparison$logical_sha256_run2
lmv2_ebal_write_csv(comparison[order(comparison$file), ], audit_dir,
                    "p4_ebal_manifest_comparison.csv")

determinism <- data.frame(
  p4_ebal_version = LMV2_P4_EBAL_VERSION, p4_ebal_config_hash = LMV2_P4_EBAL_CONFIG_HASH,
  check = "two_certification_runs_have_identical_logical_manifests",
  pass = deterministic, stringsAsFactors = FALSE
)
lmv2_ebal_write_csv(determinism, audit_dir, "p4_ebal_rebuild_determinism.csv")
if (!deterministic) stop("P4-EB logical manifests differ across two certification runs")

message("P4-EB E1 certification-only run complete: source audit passed, ",
        "two certification runs produced identical logical manifests. ",
        "No database was opened; no real Stage-1/Stage-2 execution occurred.")
