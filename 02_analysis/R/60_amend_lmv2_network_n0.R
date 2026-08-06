#!/usr/bin/env Rscript

# Outcome-blind amendment to the certified Local Match v2 network N0 gate.
# This script reads only the existing N0 support/certification artifacts. It
# never opens validation-period or post-treatment network outcomes.

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
if (!requireNamespace("digest", quietly = TRUE)) stop("Missing package: digest")

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
N0 <- file.path(ROOT, "NETWORK_N0_CENSUS")
OUT <- file.path(ROOT, "NETWORK_N0_AMENDMENT_20260806")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

read_one <- function(name) {
  path <- file.path(N0, name)
  if (!file.exists(path)) stop("Missing certified N0 input: ", path)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}
sha <- function(path) digest::digest(path, file = TRUE, algo = "sha256")

original <- read_one("network_n0_path_decision.csv")
original_cert <- read_one("network_n0_certification.csv")
support <- read_one("network_support_census.csv")
original_freeze <- file.path(N0, "network_preanalysis_freeze.md")
original_ties <- file.path(N0, "network_persistent_ties.parquet")

if (nrow(original) != 1L || original$selected_path[[1L]] != "Q") {
  stop("The amendment requires the certified original N0 Path-Q decision")
}
if (!all(as.logical(original_cert$pass))) {
  stop("The original N0 certification does not pass")
}
treated <- support[support$arm == "treated", , drop = FALSE]
control <- support[support$arm == "control", , drop = FALSE]
if (nrow(treated) != 1L || nrow(control) != 1L) {
  stop("N0 support must contain one treated and one control row")
}

# The tie definition and 0.05 meaningful-effect threshold remain unchanged.
# Only the raw-inventor threshold is replaced. Deal-level support is the
# relevant quantity because all governing inference clusters by deal.
amended_support_pass <-
  treated$nominal_deals[[1L]] >= 150L &&
  treated$effective_deals[[1L]] >= 20 &&
  treated$largest_deal_share[[1L]] <= 0.10 &&
  control$focal_inventors[[1L]] > 0L

outcome_freeze <- data.frame(
  field = c(
    "primary_population", "secondary_population", "anchor_window",
    "persistent_tie", "validation_window", "post_window",
    "primary_outcome", "primary_numerator", "primary_denominator",
    "partner_at_risk", "partner_focal_organization",
    "missing_denominator", "right_censoring", "aggregation",
    "reference_period", "meaningful_effect", "primary_inference",
    "multiplicity", "secondary_outcomes", "rematching"
  ),
  value = c(
    "certified P5c full pre-deal target-inventor cohort and frozen controls",
    "certified P5b initially retained selected population",
    "event times -5 through -3",
    "at least two distinct joint applications in at least two anchor years",
    "event times -2 and -1 only",
    "event times +1 through +5; inaccessible before certified Path N",
    "collaborator focal-organization persistence share",
    "persistent baseline collaborators with at least one patent linked to the focal organization in the evaluation year",
    "all persistent baseline collaborators because every evaluation year is inside the 1988-2015 data window",
    "all persistent baseline collaborators remain at risk through event time +5; no-patent years are observed zeros, not missing observations",
    "before treatment use focal_group_1; after treatment use focal_group_2 when present and otherwise focal_group_1; controls use focal_group_1 throughout; multiple links count once",
    "never missing within the strict-tie population; a zero numerator is coded zero",
    "cohorts end by 2010 so +5 is observed by 2015; an individual last patent never removes a partner from the denominator",
    "focal-inventor share first, then frozen inventor weights and common treated cohort shares",
    "event time -1 for dynamic changes; held-out level gaps also reported at -2 and -1",
    "absolute 0.05 change on the share scale",
    "wider of deal-wild and two-way deal/inventor 95 percent intervals",
    "one governing primary outcome; no Holm-adjusted p-value",
    "legacy-tie recurrence, composition, Jaccard, team size, and extensive/intensive accounting are non-governing",
    "none; frozen P5c and P5b weights are reused and balance is audited"
  ),
  stringsAsFactors = FALSE
)
write_csv(outcome_freeze, "network_outcome_freeze.csv")

decision <- data.frame(
  original_path = original$selected_path[[1L]],
  amended_path = if (amended_support_pass) "N1" else "Q",
  amendment_basis = paste(
    "Replace the raw 3,000-inventor cutoff with prespecified deal-level",
    "support because governing inference clusters by deal; preserve the",
    "strict tie definition, all outcome definitions, and the 0.05 threshold."
  ),
  treated_focal_inventors = treated$focal_inventors[[1L]],
  treated_nominal_deals = treated$nominal_deals[[1L]],
  treated_effective_deals = treated$effective_deals[[1L]],
  treated_largest_deal_share = treated$largest_deal_share[[1L]],
  meaningful_effect_threshold = 0.05,
  validation_or_post_outcomes_read = FALSE,
  stringsAsFactors = FALSE
)
write_csv(decision, "network_n0_amended_path_decision.csv")

amendment <- c(
  "# Local Match v2 network N0 amendment",
  "",
  "Date: 2026-08-06",
  "",
  "The original strict N0 result remains Path Q under its original rule.",
  "This amendment does not overwrite that result. It replaces only the raw",
  "3,000-inventor support threshold before any held-out or post-treatment",
  "network outcome is materialized.",
  "",
  "## Substantive reason",
  "",
  "Governing inference clusters at the acquisition-deal level. The strict",
  sprintf(
    "tie sample contains %d inventors across %d nominal and %.1f effective deals;",
    treated$focal_inventors[[1L]], treated$nominal_deals[[1L]],
    treated$effective_deals[[1L]]
  ),
  sprintf(
    "the largest deal contributes %.1f%% of weighted support.",
    100 * treated$largest_deal_share[[1L]]
  ),
  "The amended support gate therefore uses nominal deals, effective deals,",
  "and deal concentration rather than an additional raw-inventor cutoff.",
  "",
  "## What remains frozen",
  "",
  "- Full-cohort P5c population is primary; P5b retained inventors are secondary.",
  "- Anchor is event times -5 through -3.",
  "- A persistent tie requires two joint applications in two anchor years.",
  "- The governing outcome is partner focal-organization persistence.",
  "- The smallest main-text-relevant effect remains 0.05 on the share scale.",
  "- One governing primary outcome is reported; no Holm p-value is used.",
  "- Frozen weights are reused without rematching.",
  "- N1 may read only event times -2 and -1.",
  "- Positive event times remain closed unless N1 certifies Path N.",
  "",
  "## Technical denominator correction",
  "",
  "A provisional N1 dry run conditioned the denominator on each partner's",
  "global last observed patent. Before any positive event time was opened, that",
  "rule was rejected because partner patenting cessation is an outcome, not",
  "missingness. All strict baseline collaborators now remain in the denominator",
  "through +5 because the data window covers every evaluation year. The",
  "endpoint-conditioned dry run is archived as superseded and is not reported.",
  "",
  paste0("Amended release decision: **", decision$amended_path[[1L]], "**.")
)
writeLines(amendment, file.path(OUT, "network_n0_amendment.md"), useBytes = TRUE)

cert <- data.frame(
  check = c(
    "original_path_q_preserved", "original_n0_certified",
    "strict_tie_artifact_unchanged", "full_cohort_primary",
    "one_partner_based_primary_outcome", "meaningful_effect_unchanged",
    "no_validation_or_post_outcomes_read", "deal_support_passes",
    "amended_decision_is_valid"
  ),
  pass = c(
    original$selected_path[[1L]] == "Q", all(as.logical(original_cert$pass)),
    file.exists(original_ties),
    outcome_freeze$value[outcome_freeze$field == "primary_population"] ==
      "certified P5c full pre-deal target-inventor cohort and frozen controls",
    outcome_freeze$value[outcome_freeze$field == "primary_outcome"] ==
      "collaborator focal-organization persistence share",
    decision$meaningful_effect_threshold[[1L]] == 0.05,
    !decision$validation_or_post_outcomes_read[[1L]], amended_support_pass,
    decision$amended_path[[1L]] %in% c("N1", "Q")
  ),
  value = c(
    original$selected_path[[1L]], all(as.logical(original_cert$pass)),
    sha(original_ties), outcome_freeze$value[1L],
    outcome_freeze$value[outcome_freeze$field == "primary_outcome"],
    decision$meaningful_effect_threshold[[1L]],
    decision$validation_or_post_outcomes_read[[1L]], amended_support_pass,
    decision$amended_path[[1L]]
  ),
  detail = c(
    "original decision remains separately archived", "all original checks pass",
    "uses the certified strict N0 tie parquet without rewriting it",
    "retained population cannot determine the causal network definition",
    "partner behavior, not focal co-patenting, governs",
    "not revised in response to support or outcomes",
    "this script reads support artifacts only",
    "nominal deals >=150; effective deals >=20; max share <=0.10",
    "N1 is released only by the amended support rule"
  ),
  stringsAsFactors = FALSE
)
write_csv(cert, "network_n0_amendment_certification.csv")
if (!all(cert$pass)) stop("N0 amendment certification failed")

manifest_names <- c(
  "network_n0_amendment.md", "network_outcome_freeze.csv",
  "network_n0_amended_path_decision.csv",
  "network_n0_amendment_certification.csv"
)
manifest <- data.frame(
  artifact = manifest_names,
  sha256 = vapply(file.path(OUT, manifest_names), sha, character(1)),
  bytes = file.info(file.path(OUT, manifest_names))$size,
  stringsAsFactors = FALSE
)
write_csv(manifest, "network_n0_amendment_manifest.csv")

source_manifest <- data.frame(
  source = c(original_freeze, original_ties,
             file.path(N0, "network_support_census.csv"),
             file.path(N0, "network_n0_path_decision.csv")),
  sha256 = vapply(c(original_freeze, original_ties,
                    file.path(N0, "network_support_census.csv"),
                    file.path(N0, "network_n0_path_decision.csv")),
                  sha, character(1)),
  stringsAsFactors = FALSE
)
write_csv(source_manifest, "network_n0_amendment_source_manifest.csv")
message("Certified network N0 amendment written to: ", OUT)
