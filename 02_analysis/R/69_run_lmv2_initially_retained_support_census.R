# ============================================================================
# 69_run_lmv2_initially_retained_support_census.R
# Outcome-blind support census for the initially retained analysis.
#
# Panel A restricts the completed full-cohort candidate-count census to the
# initially retained treated population. Panel B evaluates retained-control
# support at the deal-stack level used by the separately balanced S3 design.
# It does not estimate outcomes or imply that relaxed inherited support is
# feasible without rebuilding retained-control rosters and weights.
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

VERSION <- "lmv2_initially_retained_support_census_1993_v1"
AUDIT_ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
FULL_COUNTS <- file.path(
  AUDIT_ROOT, "SUPPORT_THRESHOLD_CENSUS", "support_counts.csv")
RETAINED_PARTITION <- file.path(
  AUDIT_ROOT, "P5B_STAYER_S0_S2", "treated_retention_partition.parquet")
S3_DEALS <- file.path(
  AUDIT_ROOT, "P5B_STAYER_S3", "s3_deal_support_diagnostics.csv")
S3_SUMMARY <- file.path(
  AUDIT_ROOT, "P5B_STAYER_S3", "s3_support_summary.csv")
OUTPUT_DIR <- file.path(
  AUDIT_ROOT, "INITIALLY_RETAINED_SUPPORT_CENSUS")
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

INPUTS <- c(
  full_candidate_counts = FULL_COUNTS,
  retained_partition = RETAINED_PARTITION,
  s3_deal_support = S3_DEALS,
  s3_support_summary = S3_SUMMARY)
EXPECTED_SHA256 <- c(
  full_candidate_counts =
    "223c64a77cf38b3e6f2e30cf404787dd49a18f7eccb487f6e128f8454004fdf3",
  retained_partition =
    "0b6f0ac2bd57d4707ad428516b796ecf167861ee1663929845eb04e982dcd09f",
  s3_deal_support =
    "3b688d9ad23c55038b4fc949216e651e4b8f1ec8df3a96512d3e43b3b5627e4b",
  s3_support_summary =
    "a4dce723322d163fe6e76107e9a0da75326be8883388d8c9d773c37bcc6ac5ff")
if (any(!file.exists(INPUTS))) {
  stop("A retained-support census input is missing")
}
OBSERVED_SHA256 <- vapply(
  INPUTS, digest::digest, character(1), file = TRUE, algo = "sha256")
if (!identical(unname(OBSERVED_SHA256), unname(EXPECTED_SHA256))) {
  stop("A pinned retained-support census input has drifted")
}

atomic_csv <- function(x, path) {
  temporary <- tempfile(
    paste0(basename(path), "_"), tmpdir = dirname(path), fileext = ".tmp")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(x, temporary, row.names = FALSE, na = "")
  if (file.exists(path) && !file.remove(path)) stop("Could not replace ", path)
  if (!file.rename(temporary, path)) stop("Could not finalize ", path)
}
sql_path <- function(con, path) {
  as.character(DBI::dbQuoteString(
    con, normalizePath(path, winslash = "/", mustWork = TRUE)))
}
key_string <- function(x) {
  do.call(paste, c(x[c("cohort", "deal_id", "codinv")], sep = ":"))
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
retained <- DBI::dbGetQuery(con, sprintf("
  SELECT CAST(cohort AS INTEGER) cohort,
         CAST(deal_id AS INTEGER) deal_id,
         CAST(codinv AS BIGINT) codinv,
         CAST(route_disagreement AS BOOLEAN) route_disagreement
  FROM read_parquet(%s)
  WHERE retention_window='t1_t5_primary'
    AND retention_status='initially_retained'
  ORDER BY cohort,deal_id,codinv", sql_path(con, RETAINED_PARTITION)))
if (nrow(retained) != 3220L ||
    anyDuplicated(retained[c("cohort", "deal_id", "codinv")])) {
  stop("Current initially retained denominator does not equal 3,220 unique keys")
}

full_counts <- utils::read.csv(FULL_COUNTS, stringsAsFactors = FALSE)
if (anyDuplicated(full_counts[c("cohort", "deal_id", "codinv")])) {
  stop("Full-cohort support census has duplicate treated keys")
}
retained_counts <- merge(
  retained, full_counts,
  by = c("cohort", "deal_id", "codinv"), all.x = TRUE, sort = TRUE)
if (nrow(retained_counts) != nrow(retained) ||
    anyNA(retained_counts$n_controls)) {
  stop("Initially retained keys do not map one-to-one into support counts")
}

RULES <- data.frame(
  rule = c("1c_1f", "2c_2f", "3c_2f"),
  minimum_controls = c(1L, 2L, 3L),
  minimum_firms = c(1L, 2L, 2L),
  inherited_preferred = c(FALSE, FALSE, TRUE),
  stringsAsFactors = FALSE)
for (i in seq_len(nrow(RULES))) {
  expected <- retained_counts$n_controls >= RULES$minimum_controls[[i]] &
    retained_counts$n_firms >= RULES$minimum_firms[[i]]
  observed <- retained_counts[[paste0("supported_", RULES$rule[[i]])]]
  if (!identical(as.logical(observed), expected)) {
    stop("Stored support predicate disagrees with counts for ", RULES$rule[[i]])
  }
}
if (!all(retained_counts$supported_3c_2f <=
         retained_counts$supported_2c_2f) ||
    !all(retained_counts$supported_2c_2f <=
         retained_counts$supported_1c_1f)) {
  stop("Inherited retained-sample support rules are not nested")
}

summarize_inherited <- function(z, dimensions = character()) {
  split_key <- if (length(dimensions)) {
    interaction(z[dimensions], drop = TRUE, lex.order = TRUE)
  } else {
    factor(rep("aggregate", nrow(z)))
  }
  do.call(rbind, lapply(split(z, split_key), function(x) {
    out <- if (length(dimensions)) x[1, dimensions, drop = FALSE] else {
      data.frame(scope = "aggregate", stringsAsFactors = FALSE)
    }
    out$eligible <- nrow(x)
    for (rule in RULES$rule) {
      supported <- x[[paste0("supported_", rule)]]
      out[[paste0("supported_", rule)]] <- sum(supported)
      out[[paste0("coverage_", rule)]] <- mean(supported)
      out[[paste0("deals_", rule)]] <- length(unique(
        x$deal_id[supported]))
    }
    out
  }))
}
inherited_aggregate <- summarize_inherited(retained_counts)
inherited_cohort <- summarize_inherited(retained_counts, "cohort")
inherited_quartile <- summarize_inherited(
  retained_counts, "productivity_quartile")

retained_counts$support_increment <- ifelse(
  retained_counts$supported_3c_2f, "preferred_3c_2f",
  ifelse(retained_counts$supported_2c_2f, "added_by_2c_2f",
    ifelse(retained_counts$supported_1c_1f, "added_by_1c_1f",
           "unsupported_1c_1f")))
composition_variables <- c(
  "log_patent_count_5y", "patent_trajectory", "career_age",
  "focal_group_tenure", "focal_group_exclusivity")
preferred <- retained_counts$support_increment == "preferred_3c_2f"
composition <- do.call(rbind, lapply(
  unique(retained_counts$support_increment), function(group) {
    member <- retained_counts$support_increment == group
    do.call(rbind, lapply(composition_variables, function(variable) {
      reference <- retained_counts[[variable]][preferred]
      comparison <- retained_counts[[variable]][member]
      pooled_sd <- sqrt(
        (stats::var(reference) + stats::var(comparison)) / 2)
      data.frame(
        support_increment = group, variable = variable,
        inventors = sum(member), mean = mean(comparison),
        preferred_mean = mean(reference),
        smd_increment_minus_preferred = if (
          is.finite(pooled_sd) && pooled_sd > 0) {
          (mean(comparison) - mean(reference)) / pooled_sd
        } else 0,
        stringsAsFactors = FALSE)
    }))
  }))
candidate_quality <- do.call(rbind, lapply(
  unique(retained_counts$support_increment), function(group) {
    z <- retained_counts[
      retained_counts$support_increment == group, , drop = FALSE]
    data.frame(
      support_increment = group, inventors = nrow(z),
      mean_controls = mean(z$n_controls),
      median_controls = stats::median(z$n_controls),
      mean_firms = mean(z$n_firms),
      median_firms = stats::median(z$n_firms),
      mean_nearest_distance = mean(z$nearest_distance, na.rm = TRUE),
      median_nearest_distance = stats::median(
        z$nearest_distance, na.rm = TRUE),
      stringsAsFactors = FALSE)
  }))

# S3 balances deal-stacked retained groups. Its support thresholds therefore
# apply to the retained-control pool of a deal stack, not separately to every
# treated inventor. The current preferred S3 rule is 1 row / 1 firm.
s3_deals <- utils::read.csv(S3_DEALS, stringsAsFactors = FALSE)
s3_deals <- s3_deals[
  s3_deals$support_variant == "primary_resolved_t1", , drop = FALSE]
if (nrow(s3_deals) != 153L || anyDuplicated(
    s3_deals[c("cohort", "deal_id")])) {
  stop("Current primary S3 deal-stack diagnostic is not 153 unique deals")
}
stack_rows <- lapply(seq_len(nrow(RULES)), function(i) {
  keep <- s3_deals$n_control_rows >= RULES$minimum_controls[[i]] &
    s3_deals$n_control_firms >= RULES$minimum_firms[[i]]
  data.frame(
    rule = RULES$rule[[i]],
    level = "retained_control_deal_stack",
    minimum_control_rows = RULES$minimum_controls[[i]],
    minimum_control_firms = RULES$minimum_firms[[i]],
    current_preferred = RULES$rule[[i]] == "1c_1f",
    classified_initially_retained = nrow(retained_counts),
    supported_treated = sum(s3_deals$n_treated[keep]),
    coverage = sum(s3_deals$n_treated[keep]) / nrow(retained_counts),
    supported_deals = sum(keep),
    excluded_vs_current = sum(s3_deals$n_treated) -
      sum(s3_deals$n_treated[keep]),
    stringsAsFactors = FALSE)
})
stack_support <- do.call(rbind, stack_rows)

s3_summary <- utils::read.csv(S3_SUMMARY, stringsAsFactors = FALSE)
primary_summary <- s3_summary[
  s3_summary$support_variant == "primary_resolved_t1", , drop = FALSE]
if (nrow(primary_summary) != 1L ||
    primary_summary$eligible_treated != nrow(retained_counts) ||
    primary_summary$supported_treated !=
      stack_support$supported_treated[stack_support$rule == "1c_1f"] ||
    primary_summary$supported_deals !=
      stack_support$supported_deals[stack_support$rule == "1c_1f"]) {
  stop("The 1c/1f stack census does not reproduce current S3 support")
}

certification <- data.frame(
  check = c(
    "pinned_input_hashes", "retained_denominator",
    "retained_keys_map_to_full_census", "inherited_rule_nesting",
    "current_s3_is_stack_level_1c_1f",
    "current_s3_supported_treated_reconciles",
    "current_s3_supported_deals_reconcile",
    "outcome_or_att_objects_read"),
  realized = c(
    "4 of 4 exact hashes", paste0(nrow(retained_counts), " unique keys"),
    paste0(nrow(retained_counts), " exact joins"),
    "3c_2f subset 2c_2f subset 1c_1f",
    "TRUE", as.character(primary_summary$supported_treated),
    as.character(primary_summary$supported_deals), "FALSE"),
  pass = TRUE,
  stringsAsFactors = FALSE)

manifest <- data.frame(
  version = VERSION,
  release = "local_match_v2_1993_amendment",
  population = "initially_retained_t1_t5_primary",
  interpretation = paste(
    "Inherited rules are per treated inventor in the full donor graph;",
    "retained-control rules are per deal stack in S3. They are not the",
    "same restriction and must not be combined into one coverage claim."),
  current_s3_rule = paste(
    "At least one retained control row from at least one retained-control",
    "firm in the deal stack; no per-inventor retained-control threshold."),
  outcome_boundary = paste(
    "Reads only support counts, retention classifications, and S3 support",
    "diagnostics. Reads no outcome or ATT object."),
  classified_initially_retained = nrow(retained_counts),
  current_s3_supported_treated = primary_summary$supported_treated,
  current_s3_supported_deals = primary_summary$supported_deals,
  timestamp = as.character(Sys.time()),
  stringsAsFactors = FALSE)

atomic_csv(retained_counts, file.path(
  OUTPUT_DIR, "retained_inherited_support_counts.csv"))
atomic_csv(inherited_aggregate, file.path(
  OUTPUT_DIR, "inherited_support_aggregate.csv"))
atomic_csv(inherited_cohort, file.path(
  OUTPUT_DIR, "inherited_support_by_cohort.csv"))
atomic_csv(inherited_quartile, file.path(
  OUTPUT_DIR, "inherited_support_by_productivity_quartile.csv"))
atomic_csv(composition, file.path(
  OUTPUT_DIR, "inherited_increment_composition.csv"))
atomic_csv(candidate_quality, file.path(
  OUTPUT_DIR, "inherited_increment_candidate_quality.csv"))
atomic_csv(stack_support, file.path(
  OUTPUT_DIR, "retained_control_stack_support.csv"))
atomic_csv(certification, file.path(OUTPUT_DIR, "certification.csv"))
atomic_csv(manifest, file.path(OUTPUT_DIR, "manifest.csv"))

summary_lines <- c(
  "# Initially retained support-threshold census",
  "",
  paste0(
    "The current release classifies ", nrow(retained_counts),
    " treated inventors as initially retained."),
  "",
  paste0(
    "In the inherited full donor graph, 3c/2f supports ",
    inherited_aggregate$supported_3c_2f, " inventors (",
    sprintf("%.2f", 100 * inherited_aggregate$coverage_3c_2f),
    "%), 2c/2f supports ", inherited_aggregate$supported_2c_2f,
    " (", sprintf("%.2f", 100 * inherited_aggregate$coverage_2c_2f),
    "%), and 1c/1f supports ", inherited_aggregate$supported_1c_1f,
    " (", sprintf("%.2f", 100 * inherited_aggregate$coverage_1c_1f),
    "%)."),
  "",
  paste0(
    "The separately balanced retained design already uses 1c/1f at the ",
    "deal-stack level and supports ",
    stack_support$supported_treated[stack_support$rule == "1c_1f"],
    " inventors across ",
    stack_support$supported_deals[stack_support$rule == "1c_1f"],
    " deals. Tightening retained-stack support to 2c/2f or 3c/2f would ",
    "support ",
    stack_support$supported_treated[stack_support$rule == "2c_2f"],
    " and ",
    stack_support$supported_treated[stack_support$rule == "3c_2f"],
    " inventors, respectively."),
  "",
  paste(
    "The inherited relaxed-rule counts are upper recovery ceilings, not",
    "ready alternative stayer samples. Added inventors still require a",
    "retained-control analogue, feasible balance, and new weights."),
  "",
  paste(
    "The outcome-blind evidence supports keeping 3c/2f for inherited local",
    "support while keeping the current 1c/1f retained-stack rule. The two",
    "restrictions operate at different levels and serve different purposes."))
writeLines(summary_lines, file.path(OUTPUT_DIR, "README.md"), useBytes = TRUE)

message(
  "Initially retained support census complete: inherited 3c/2f ",
  inherited_aggregate$supported_3c_2f, "/", nrow(retained_counts),
  "; current retained-control stack 1c/1f ",
  primary_summary$supported_treated, "/", nrow(retained_counts), ".")
