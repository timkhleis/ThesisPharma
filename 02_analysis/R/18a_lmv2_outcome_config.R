# ============================================================================
# 18a_lmv2_outcome_config.R -- P6 outcome-panel configuration (local_match_v2)
# ============================================================================
# Code-only stage: this file defines the P6 configuration, the frozen P5a
# roster contract, the zero-vs-missing matrix, and provenance helpers.
# It performs no data access. Authority order: approved amendments
# (02_analysis/notes/local_match_v2_amendments.md) > frozen P0 lock (15a).

LMV2_P6_VERSION <- "local_match_v2_p6_v3"

LMV2_P6_PREANALYSIS_FREEZE_SHA256 <-
  "1ed37807124f72ae85d10fed00c3959016530f1e6fade61c416227d8350ff2d4"
LMV2_P6_APPROVED_PRIMARY_ROSTER_SHA256 <-
  "19c8245b499a5186b3c8a83e796def82dba522303eccd3507ab7cdc362f26107"
LMV2_P6_APPROVED_P5_DESIGN_HASH <-
  "188f7735a6fe39dd090c03eb7a15b01b7bafc7e3118e5a75f411020cf5423507"
LMV2_P6_APPROVED_P5_PRODUCTION_FREEZE_SHA256 <-
  "637e7535239a835ffadc5cbba17a96c2f9a2410d997f36ff127568493b9b33d4"

LMV2_P6_CONFIG <- list(
  # -- sample clocks (P0 lock + P2 amendments) -------------------------------
  cohorts = 1994:2010,
  buffered_cohorts = 1994:2008,
  event_window = -5:5,
  headline_post_window = 1:5,
  headline_terminal_event_time = 5L,
  late_tail_calendar_year = 2014L,   # calendar years >= this are flagged
  patent_clock = "application_year", # authoritative; OECD `filing` audit-only

  # -- P2 interfaces validated by the runner hard-gate (all five) ------------
  p2_interfaces = c(
    "lmv2_treated_primary", "lmv2_treated_broad",
    "lmv2_treated_unique_affiliation_robustness",
    "lmv2_control_firm_eligibility", "lmv2_control_inventor_eligibility"
  ),
  # P2 hash method: digest::digest(sha256, serialize) over SELECT * ORDER BY ALL
  # (identical to 15e table_hash). Never replaced by another algorithm.

  # -- P1-layer inputs consumed by P6; certified with P1's hash-sum/hash-XOR --
  # inventor_year uses the exact 15c column list; other consumed foundation
  # tables use the same method over all columns. Both recorded before and
  # after the P6 build.
  p1_inventor_year_hash_columns = c(
    "codinv", "year", "patent_count", "fractional_patent_count",
    "distinct_firm_count", "distinct_group_count",
    "career_first_year", "career_last_year", "career_year_index"
  ),
  p6_consumed_foundation_tables = c(
    "inventor_year", "patent_inventor", "patent_application",
    "patent_company_link", "inventor_ipc_year", "inventor_affiliation_own",
    "oecd_quality", "deal_target_company_strict"
  ),

  # -- ingredient tables (built into an isolated build schema) ---------------
  ingredient_tables = c(
    "lmv2_outcome_inventor_year",
    "lmv2_outcome_inventor_affiliation_year",
    "lmv2_inventor_group_patent_year",
    "lmv2_inventor_target_company_patent_year",
    "lmv2_inventor_ipc4_year",
    "lmv2_oecd_coverage_appyear",
    "lmv2_oecd_coverage_filingyear",
    "lmv2_oecd_filing_delta",
    "lmv2_oecd_linkage_decline_appyear",
    "lmv2_oecd_linkage_decline_filingyear"
  ),

  # -- P5 weighted-roster contract --------------------------------------------
  # Weights arrive as certified P5a weights (whatever balancing rule P5
  # certifies). P6 never recomputes, rebalances, repairs, or renormalizes them.
  roster_columns = c(
    deal_id = "BIGINT", cohort = "INTEGER", arm = "VARCHAR",
    codinv = "BIGINT", roster_row_id = "VARCHAR", weight = "DOUBLE",
    status_eligible = "BOOLEAN",
    focal_group_1 = "BIGINT", focal_group_2 = "BIGINT",
    use_target_company_path = "BOOLEAN",
    qualification_route = "VARCHAR",
    target_to_acquirer_transition_strict = "BOOLEAN",
    latest_pre_candidate_group_count = "INTEGER",
    multi_exposure_inventor = "BOOLEAN",
    big_deal = "BOOLEAN"
  ),
  roster_arms = c("treated", "control"),
  min_control_firms_per_deal = 2L,
  cohort_weight_mass_tolerance = 1e-7,
  approved_primary = list(
    roster_sha256 = LMV2_P6_APPROVED_PRIMARY_ROSTER_SHA256,
    roster_rows = 500906L,
    p5_design_hash = LMV2_P6_APPROVED_P5_DESIGN_HASH,
    p5_production_freeze_sha256 =
      LMV2_P6_APPROVED_P5_PRODUCTION_FREEZE_SHA256
  ),

  outcome_status = list(
    primary = c("patent_count", "active_patenting", "techdrift"),
    secondary = c("pqii", "fwd_cits5"),
    oecd_leading_variant = "scaled"
  ),
  inference = list(
    headline = "deal_cluster_wild_bootstrap_t",
    package = "fwildclusterboot",
    package_version = "0.14.3",
    weights = "webb",
    replications = 9999L,
    seed = 20260722L,
    impose_null = TRUE,
    confidence_level = 0.95,
    prominent_companion = "two_way_deal_inventor_cluster",
    deal_only_companion = "deal_cluster_robust",
    disagreement_rule = "use_wider_interval_wild_on_exact_width_tie"
  ),
  sensitivity_designs = c(
    "equal_deal_feasible",
    "primary_equal_deal_feasible_sample",
    "no_deal70_resolved",
    "deal70_single_firm_deletions",
    "omit_henkel_exact_without_ess_gate"
  ),

  # -- TechDrift -------------------------------------------------------------
  techdrift = list(
    ipc_level = "ipc4_substr_1_4",
    weights = "integer_patent_count",
    stored_measure = "cosine_similarity", # drift = 1 - similarity at analysis
    baseline_window = "g-5..g-1",
    undefined_value = NA_real_ # empty baseline or unclassified current year
  ),

  # -- execution settings ----------------------------------------------------
  memory_limit = "9GB",
  # Five-cohort exact-A/B benchmark: 8 threads = 9.07s versus 4 threads =
  # 10.01s. JSON profiling at 8 threads records a 1.45GB peak and zero spill.
  threads = 8L,
  build_schemas = c("p6_build_a", "p6_build_b") # isolated double-build
)

LMV2_P6_PREANALYSIS_FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_p6_preanalysis_freeze.md")
if (!identical(
    digest::digest(
      file = LMV2_P6_PREANALYSIS_FREEZE_PATH, algo = "sha256"),
    LMV2_P6_PREANALYSIS_FREEZE_SHA256)) {
  stop("P6 pre-analysis freeze drifted")
}

# Zero-vs-missing matrix (lock: incomplete_oecd_linkage = "missing_not_zero").
# Applied separately to citations (n_fwd_nonmiss) and PQII (n_pqii_nonmiss):
#   patents > 0, n_nonmiss = patent_count : complete=sum, observed=sum,
#                                            scaled=sum, cond=sum/n
#   patents > 0, 0 < n_nonmiss < count    : complete=NA, observed=sum_obs,
#                                            scaled=sum_obs*count/n, cond=sum_obs/n
#   patents > 0, n_nonmiss = 0            : complete=NA, observed=NA,
#                                            scaled=NA, cond=NA
#   genuine zero-patent year              : complete=0, observed=0, scaled=0,
#                                            cond=NA (intensive margin)
# Encoded in SQL by lmv2_outcome_variant_sql() below.

lmv2_outcome_variant_sql <- function(prefix, count_expr, n_expr, sum_expr) {
  # prefix: output column prefix (e.g. "fwd_cits5" or "pqii")
  # count_expr / n_expr / sum_expr: SQL expressions for the patent count,
  # the non-missing OECD value count, and the observed sum. Callers pass
  # structural-zero-coalesced expressions for absent inventor-years.
  sprintf("
    CASE WHEN %2$s = 0 THEN 0
         WHEN %3$s = %2$s THEN %4$s
         ELSE NULL END AS %1$s_complete,
    CASE WHEN %2$s = 0 THEN 0
         WHEN %3$s = 0 THEN NULL
         ELSE %4$s END AS %1$s_observed,
    CASE WHEN %2$s = 0 THEN 0
         WHEN %3$s = 0 THEN NULL
         ELSE %4$s * %2$s / %3$s END AS %1$s_scaled,
    CASE WHEN %2$s = 0 THEN NULL
         WHEN %3$s = 0 THEN NULL
         ELSE %4$s / %3$s END AS %1$s_conditional_mean",
    prefix, count_expr, n_expr, sum_expr)
}

# --------------------------------------------------------------------------
# Provenance helpers (pure; used by 18d/18e at execution time)
# --------------------------------------------------------------------------

lmv2_p6_design_hash <- function() {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for the P6 design hash.")
  }
  digest::digest(list(LMV2_P6_VERSION, LMV2_P6_CONFIG),
                 algo = "sha256", serialize = TRUE)
}

lmv2_file_sha256 <- function(path) {
  if (!file.exists(path)) stop("Provenance file missing: ", path)
  digest::digest(file = path, algo = "sha256")
}

# Attribute-insensitive data-frame equality (row names reset, columns sorted;
# values compared as character to survive CSV round-trips).
lmv2_df_equal <- function(a, b) {
  a <- a[, order(names(a)), drop = FALSE]
  b <- b[, order(names(b)), drop = FALSE]
  if (!identical(names(a), names(b)) || nrow(a) != nrow(b)) return(FALSE)
  a[] <- lapply(a, as.character)
  b[] <- lapply(b, as.character)
  rownames(a) <- NULL
  rownames(b) <- NULL
  isTRUE(all.equal(a, b, check.attributes = FALSE))
}

# P2 hash method, byte-identical to 15e::table_hash.
lmv2_p2_table_hash <- function(con, table_name) {
  rows <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM %s ORDER BY ALL", DBI::dbQuoteIdentifier(con, table_name)))
  digest::digest(rows, algo = "sha256", serialize = TRUE)
}

# Quote a possibly schema-qualified table name part-by-part:
# "p6_build_a.tbl" -> "p6_build_a"."tbl". dbQuoteIdentifier on the raw string
# would quote it as one identifier and break schema-qualified lookups.
lmv2_quote_qualified <- function(con, table_name) {
  parts <- strsplit(table_name, ".", fixed = TRUE)[[1]]
  paste(vapply(parts, function(p) {
    as.character(DBI::dbQuoteIdentifier(con, p))
  }, character(1)), collapse = ".")
}

# P1 hash method: order-invariant hash-sum / hash-XOR over named columns
# (identical construction to 15c logical checksums).
lmv2_p1_logical_checksum <- function(con, table_name, columns = NULL) {
  qtn <- lmv2_quote_qualified(con, table_name)
  if (is.null(columns)) {
    columns <- DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s)", qtn))$name
  }
  collist <- paste(columns, collapse = ", ")
  DBI::dbGetQuery(con, sprintf("
    SELECT
      '%s' AS table_name,
      COUNT(*) AS n_rows,
      CAST(SUM(CAST(hash(%s) AS HUGEINT)) AS VARCHAR) AS hash_sum,
      CAST(bit_xor(hash(%s)) AS VARCHAR) AS hash_xor
    FROM %s", table_name, collist, collist, qtn))
}
