# ============================================================================
# Package 0: certify the accepted post-results freeze and existing interfaces
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
SHARED_R_LIB <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(SHARED_R_LIB)) {
  .libPaths(unique(c(SHARED_R_LIB, .libPaths())))
}
P6_ROOT <- normalizePath(file.path(BASE, ".."), winslash = "/", mustWork = TRUE)
WORKTREES <- normalizePath(
  file.path(P6_ROOT, ".."), winslash = "/", mustWork = TRUE)
P4_ROOT <- normalizePath(
  file.path(WORKTREES, "lmv2-p4-ebal"), winslash = "/", mustWork = TRUE)
FOUNDATION_ROOT <- normalizePath(
  file.path(WORKTREES, "lmv2-foundation"), winslash = "/", mustWork = TRUE)

for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

AUDIT_DIR <- file.path(
  BASE, "output", "audit", "local_match_v2",
  "PACKAGE0_POSTRESULTS_FREEZE")
dir.create(AUDIT_DIR, recursive = TRUE, showWarnings = FALSE)

paths <- c(
  package0_certifier = file.path(
    BASE, "R", "21a_certify_lmv2_postresults_package0.R"),
  package_freeze = file.path(
    BASE, "notes", "local_match_v2_postresults_package_freeze.md"),
  repository_map = file.path(
    BASE, "notes", "local_match_v2_authoritative_repository_map.md"),
  prior_amendments = file.path(
    BASE, "notes", "local_match_v2_amendments.md"),
  p6_preanalysis_freeze = file.path(
    BASE, "notes", "local_match_v2_p6_preanalysis_freeze.md"),
  p2_builder = file.path(
    FOUNDATION_ROOT, "02_analysis", "R", "15e_build_lmv2_p2.R"),
  p2_certifier = file.path(
    FOUNDATION_ROOT, "02_analysis", "R", "15f_certify_lmv2_p2.R"),
  mece_builder = file.path(BASE, "R", "06_build_event_panel.R"),
  p5c_config = file.path(
    P4_ROOT, "02_analysis", "R",
    "21a_lmv2_p5c_annual_trajectory_config.R"),
  p5c_provenance_certifier = file.path(
    P4_ROOT, "02_analysis", "R",
    "21e_certify_lmv2_p5c_provenance.R"),
  p5c_tooth_results = file.path(
    P4_ROOT, "02_analysis", "output", "audit", "local_match_v2",
    "P5C_ANNUAL_TRAJECTORY", "p5c_provenance_tooth_tests.csv")
)

missing <- paths[!file.exists(paths)]
if (length(missing)) {
  stop("Package 0 source missing: ", paste(names(missing), collapse = ", "))
}

file_sha256 <- function(path) {
  digest::digest(file = path, algo = "sha256")
}

source_manifest <- data.frame(
  source = names(paths),
  path = unname(normalizePath(paths, winslash = "/", mustWork = TRUE)),
  bytes = unname(file.info(paths)$size),
  sha256 = unname(vapply(paths, file_sha256, character(1))),
  stringsAsFactors = FALSE
)
source_manifest <- source_manifest[order(source_manifest$source), ]
utils::write.csv(
  source_manifest,
  file.path(AUDIT_DIR, "package0_source_manifest.csv"),
  row.names = FALSE, na = "")

bundle_hash <- function(manifest) {
  digest::digest(
    manifest[, c("source", "sha256")],
    algo = "sha256", serialize = TRUE)
}
package_hash <- bundle_hash(source_manifest)

checks <- list()
add_check <- function(check, observed, expected, pass) {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = check,
    observed = as.character(observed),
    expected = as.character(expected),
    pass = isTRUE(pass),
    stringsAsFactors = FALSE)
}

add_check(
  "all_authoritative_sources_exist",
  length(paths) - length(missing), length(paths),
  length(missing) == 0L)

freeze_text <- paste(
  readLines(paths[["package_freeze"]], warn = FALSE, encoding = "UTF-8"),
  collapse = "\n")
required_freeze_terms <- c(
  "initially retained inventors",
  "mixed/tied first year",
  "persistent-inside descriptive subgroup",
  "no observed post-deal patent",
  "Deal 70 remains in the headline design",
  "Henkel remains in the headline donor pool",
  "Package 1",
  "Package 5A",
  "Package 5B")
missing_terms <- required_freeze_terms[
  !vapply(required_freeze_terms, grepl, logical(1),
          x = freeze_text, fixed = TRUE)]
add_check(
  "accepted_decisions_are_frozen",
  if (length(missing_terms)) paste(missing_terms, collapse = " | ") else "all",
  "all", length(missing_terms) == 0L)

map_text <- paste(
  readLines(paths[["repository_map"]], warn = FALSE, encoding = "UTF-8"),
  collapse = "\n")
map_terms <- c(
  ".worktrees/lmv2-foundation",
  ".worktrees/lmv2-p4-ebal",
  ".worktrees/lmv2-p6-outcomes",
  "Package 8")
missing_map_terms <- map_terms[
  !vapply(map_terms, grepl, logical(1), x = map_text, fixed = TRUE)]
add_check(
  "authoritative_worktrees_are_mapped",
  if (length(missing_map_terms)) {
    paste(missing_map_terms, collapse = " | ")
  } else {
    "all"
  },
  "all", length(missing_map_terms) == 0L)

# Tooth-test the new content hash: a real mutation must change it.
temp_freeze <- tempfile("package0_freeze_", fileext = ".md")
if (!file.copy(paths[["package_freeze"]], temp_freeze, overwrite = TRUE)) {
  stop("Could not create Package 0 mutation fixture.")
}
cat("\nPACKAGE0_REAL_MUTATION\n", file = temp_freeze, append = TRUE)
mutated_manifest <- source_manifest
mutated_manifest$sha256[
  mutated_manifest$source == "package_freeze"] <- file_sha256(temp_freeze)
mutation_changes_hash <- !identical(
  package_hash, bundle_hash(mutated_manifest))
unlink(temp_freeze)
add_check(
  "package_hash_mutation_tooth_test",
  mutation_changes_hash, TRUE, mutation_changes_hash)

# Verify the earlier P5c guard has both a content-derived implementation and
# passing real-positive mutation tests.
p5c_src <- paste(
  readLines(paths[["p5c_config"]], warn = FALSE), collapse = "\n")
p5c_content_derived <- grepl(
  "lmv2_p5c_execution_hash <- function", p5c_src, fixed = TRUE) &&
  grepl("provenance = lmv2_p5c_provenance", p5c_src, fixed = TRUE) &&
  grepl("digest::digest", p5c_src, fixed = TRUE)
add_check(
  "p5c_execution_hash_is_content_derived",
  p5c_content_derived, TRUE, p5c_content_derived)

p5c_tooth <- utils::read.csv(
  paths[["p5c_tooth_results"]], stringsAsFactors = FALSE)
p5c_tooth_pass <- nrow(p5c_tooth) == 11L &&
  all(p5c_tooth$baseline_pass) &&
  all(p5c_tooth$mutated_file_rejected) &&
  all(p5c_tooth$pass)
add_check(
  "p5c_real_positive_mutation_suite",
  paste0(sum(p5c_tooth$pass), "/", nrow(p5c_tooth)),
  "11/11", p5c_tooth_pass)

# Tooth-test a MECE partition guard on a deliberately invalid row.
mece_valid <- function(x) {
  all(!is.na(x)) && all(rowSums(x) == 1L)
}
valid_fixture <- matrix(
  c(1L, 0L, 0L, 0L, 0L,
    0L, 1L, 0L, 0L, 0L),
  nrow = 2L, byrow = TRUE)
invalid_fixture <- valid_fixture
invalid_fixture[1L, 2L] <- 1L
mece_tooth_pass <- mece_valid(valid_fixture) && !mece_valid(invalid_fixture)
add_check(
  "mece_partition_real_positive_tooth_test",
  mece_tooth_pass, TRUE, mece_tooth_pass)

# Tooth-test the accepted first-year semantics, including later exit and ties.
classify_fixture <- function(year, inside, outside) {
  if (!length(year)) {
    return(c(initial_retained = FALSE, persistent_inside = FALSE,
             no_post = TRUE, mixed_first = FALSE))
  }
  first <- min(year)
  first_inside <- any(inside[year == first])
  first_outside <- any(outside[year == first])
  c(
    initial_retained = first_inside && !first_outside,
    persistent_inside = all(inside & !outside),
    no_post = FALSE,
    mixed_first = first_inside && first_outside)
}
fixture_cases <- rbind(
  inside_then_outside = classify_fixture(
    c(0L, 2L), c(TRUE, FALSE), c(FALSE, TRUE)),
  outside_first = classify_fixture(
    c(0L, 1L), c(FALSE, TRUE), c(TRUE, FALSE)),
  no_post = classify_fixture(
    integer(), logical(), logical()),
  persistent_inside = classify_fixture(
    c(0L, 2L), c(TRUE, TRUE), c(FALSE, FALSE)),
  mixed_first = classify_fixture(
    c(0L, 0L), c(TRUE, FALSE), c(FALSE, TRUE))
)
fixture_expected <- rbind(
  inside_then_outside = c(TRUE, FALSE, FALSE, FALSE),
  outside_first = c(FALSE, FALSE, FALSE, FALSE),
  no_post = c(FALSE, FALSE, TRUE, FALSE),
  persistent_inside = c(TRUE, TRUE, FALSE, FALSE),
  mixed_first = c(FALSE, FALSE, FALSE, TRUE))
first_year_tooth_pass <- identical(
  unname(fixture_cases), unname(fixture_expected))
add_check(
  "initial_retention_semantics_fixture",
  first_year_tooth_pass, TRUE, first_year_tooth_pass)

DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
con <- DBI::dbConnect(
  duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
scalar <- function(sql) DBI::dbGetQuery(con, sql)[[1L]][1L]

required_tables <- c(
  "lmv2_treated_primary", "cs2021_estimation_panel",
  "stayer_attrition_panel")
tables_present <- vapply(
  required_tables, DBI::dbExistsTable, logical(1), conn = con)
add_check(
  "status_interfaces_exist",
  paste(names(tables_present)[tables_present], collapse = ","),
  paste(required_tables, collapse = ","),
  all(tables_present))

mece_bad <- scalar("
SELECT COUNT(*)
FROM cs2021_estimation_panel
WHERE event_time BETWEEN 0 AND 5
  AND (
    with_entity + moved_thirdparty + active_unknown_affiliation
    + inactive_silent_gap + career_exited <> 1
    OR inventor_annual_state IS NULL
  )
")
add_check("annual_mece_partition_exact", mece_bad, 0, mece_bad == 0)

state_counts <- DBI::dbGetQuery(con, "
SELECT inventor_annual_state AS state, COUNT(*) AS n
FROM cs2021_estimation_panel
WHERE event_time BETWEEN 0 AND 5
GROUP BY inventor_annual_state
ORDER BY inventor_annual_state
")
expected_states <- sort(c(
  "with_entity", "moved_thirdparty", "active_unknown_affiliation",
  "inactive_silent_gap", "career_exited"))
states_exact <- identical(sort(state_counts$state), expected_states)
add_check(
  "annual_mece_state_set_exact",
  paste(state_counts$state, collapse = ","),
  paste(expected_states, collapse = ","),
  states_exact)
utils::write.csv(
  state_counts,
  file.path(AUDIT_DIR, "package0_mece_state_counts.csv"),
  row.names = FALSE, na = "")

p2_counts <- DBI::dbGetQuery(con, "
SELECT
  COUNT(*) AS treated,
  SUM(CAST(stayer_focal_entity_first_post_t0_t5 AS INTEGER))
    AS focal_evidence_first_year,
  SUM(CASE WHEN first_post_patent_year IS NULL THEN 1 ELSE 0 END)
    AS no_post_patent
FROM lmv2_treated_primary
")
p2_counts_pass <- p2_counts$treated == 29170 &&
  p2_counts$focal_evidence_first_year == 4335 &&
  p2_counts$no_post_patent == 23615
add_check(
  "p2_first_post_interface_counts",
  paste(unlist(p2_counts), collapse = ","),
  "29170,4335,23615",
  p2_counts_pass)

mixed_count <- scalar("
WITH first_year AS (
  SELECT
    p.codinv,
    p.deal_id,
    p.stayer_focal_entity_first_post_t0_t5 AS has_focal,
    BOOL_OR(
      ia.resolved_group IS NOT NULL
      AND ia.resolved_group NOT IN (p.target_group, p.acquirer_group)
    ) AS has_outside
  FROM lmv2_treated_primary p
  LEFT JOIN inventor_affiliation_own ia
    ON ia.codinv = p.codinv
   AND ia.year = p.first_post_patent_year
  WHERE p.first_post_patent_year IS NOT NULL
  GROUP BY
    p.codinv, p.deal_id,
    p.stayer_focal_entity_first_post_t0_t5
)
SELECT COUNT(*)
FROM first_year
WHERE has_focal AND has_outside
")
add_check(
  "mixed_first_year_cases_are_explicitly_detected",
  mixed_count, ">0 and reserved for Package 3",
  mixed_count > 0)

certification <- do.call(rbind, checks)
certification$package_hash <- package_hash
certification <- certification[
  , c("package_hash", "check", "observed", "expected", "pass")]
utils::write.csv(
  certification,
  file.path(AUDIT_DIR, "package0_certification.csv"),
  row.names = FALSE, na = "")

manifest <- data.frame(
  package = "PACKAGE0_POSTRESULTS_FREEZE",
  package_hash = package_hash,
  certified_at_utc = format(
    Sys.time(), tz = "UTC", usetz = TRUE),
  checks = nrow(certification),
  checks_passed = sum(certification$pass),
  all_pass = all(certification$pass),
  treated_inventors = p2_counts$treated,
  focal_evidence_first_year = p2_counts$focal_evidence_first_year,
  no_post_patent = p2_counts$no_post_patent,
  mixed_first_year_cases = mixed_count,
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest,
  file.path(AUDIT_DIR, "package0_manifest.csv"),
  row.names = FALSE, na = "")

print(certification)
print(manifest)
if (!all(certification$pass)) {
  stop(
    "Package 0 certification failed: ",
    paste(certification$check[!certification$pass], collapse = ", "))
}
