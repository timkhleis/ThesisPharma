# ============================================================================
# 17a_lmv2_p4_pilot_config.R -- effective P4 pilot configuration and helpers
# ============================================================================
# P4 is outcome blind.  It selects and freezes the pilot matching design for
# the locked pilot cohorts on the certified P3 interfaces.  The fixed P4 file
# list has no separate utils file, so the new pure pilot helpers (SMD, ESS,
# tier selection, resolution rule, funnel accounting, manifests) live here
# below the configuration.  All distance, cosine, caliper, and selector logic
# is reused from 16c and never duplicated.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "16c_lmv2_matching_utils.R"))

LMV2_P4_VERSION <- "local_match_v2_p4_v1"
LMV2_P4_P3_COMMIT <- "dea29fb"
LMV2_P4_P3_CONFIG_SHA256 <- "11929f9715f8b789fe2597805ad311d4352661d5040f0c62f2491d60f13cf8a4"
LMV2_P4_P3_MANIFEST_SHA256 <- "ce7ed077f7e8dac07ec68ffd991df919d64bd4012c7feede934e5f5f14874a9a"
LMV2_P4_RESOLUTION_LOCK_SHA256 <- "d144c61437bb2cceb8ea7981061f3d67933b17f4a4de078d83588110c5c790d5"
LMV2_P4_SMALL_COHORT_AMENDMENT_SHA256 <- "49e9efa9e8e5c1664685fc68bb94cbdab77ae2afe8c7c24b4a7d6b96dd38e579"
LMV2_P4_TRAJECTORY_FALLBACK_AMENDMENT_SHA256 <- "326d55a684993cea6a14888964a52e33c4078417980455cff81e8e25e277d054"
LMV2_P4_BISECTION_AMENDMENT_SHA256 <- "455e32453806371ca0dff809a03be24df3a400580fcbfb0a26ba120da77a9e72"
LMV2_P4_TEN_FIRM_AMENDMENT_SHA256 <- "c9b364b73bd597356efd0d444f9811539f3d1620d31c9cccb3c849ee5a104eac"

if (!identical(LMV2_P3_CONFIG_HASH, LMV2_P4_P3_CONFIG_SHA256)) {
  stop("Certified P3 configuration drifted: expected ", LMV2_P4_P3_CONFIG_SHA256,
       ", observed ", LMV2_P3_CONFIG_HASH)
}

LMV2_P4_PATHS <- list(
  resolution_lock = file.path(BASE, "notes", "local_match_v2_p4_resolution_lock.md"),
  small_cohort_amendment = file.path(BASE, "notes",
                                     "local_match_v2_p4_small_cohort_amendment.md"),
  trajectory_fallback_amendment = file.path(BASE, "notes",
                                            "local_match_v2_p4_trajectory_fallback_amendment.md"),
  bisection_amendment = file.path(BASE, "notes",
                                  "local_match_v2_p4_bisection_amendment.md"),
  ten_firm_amendment = file.path(BASE, "notes",
                                 "local_match_v2_p4_ten_firm_extension_amendment.md"),
  p3_manifest = file.path(BASE, "output", "audit", "local_match_v2", "P3",
                          "p3_interface_manifest.csv"),
  audit = file.path(BASE, "output", "audit", "local_match_v2", "P4")
)

observed_lock_hash <- lmv2_p3_file_hash(LMV2_P4_PATHS$resolution_lock)
if (!identical(observed_lock_hash, LMV2_P4_RESOLUTION_LOCK_SHA256)) {
  stop("P4 resolution lock drifted: expected ", LMV2_P4_RESOLUTION_LOCK_SHA256,
       ", observed ", observed_lock_hash)
}
observed_amendment_hash <- lmv2_p3_file_hash(LMV2_P4_PATHS$small_cohort_amendment)
if (!identical(observed_amendment_hash, LMV2_P4_SMALL_COHORT_AMENDMENT_SHA256)) {
  stop("P4 small-cohort amendment drifted: expected ",
       LMV2_P4_SMALL_COHORT_AMENDMENT_SHA256, ", observed ",
       observed_amendment_hash)
}
observed_fallback_hash <- lmv2_p3_file_hash(LMV2_P4_PATHS$trajectory_fallback_amendment)
if (!identical(observed_fallback_hash, LMV2_P4_TRAJECTORY_FALLBACK_AMENDMENT_SHA256)) {
  stop("P4 trajectory-fallback amendment drifted: expected ",
       LMV2_P4_TRAJECTORY_FALLBACK_AMENDMENT_SHA256, ", observed ",
       observed_fallback_hash)
}
observed_bisection_hash <- lmv2_p3_file_hash(LMV2_P4_PATHS$bisection_amendment)
if (!identical(observed_bisection_hash, LMV2_P4_BISECTION_AMENDMENT_SHA256)) {
  stop("P4 bisection amendment drifted: expected ",
       LMV2_P4_BISECTION_AMENDMENT_SHA256, ", observed ",
       observed_bisection_hash)
}
observed_ten_firm_hash <- lmv2_p3_file_hash(LMV2_P4_PATHS$ten_firm_amendment)
if (!identical(observed_ten_firm_hash, LMV2_P4_TEN_FIRM_AMENDMENT_SHA256)) {
  stop("P4 ten-firm extension amendment drifted: expected ",
       LMV2_P4_TEN_FIRM_AMENDMENT_SHA256, ", observed ",
       observed_ten_firm_hash)
}

LMV2_P4 <- list(
  pilot_cohorts = LMV2_LOCK$pilot$cohorts,
  stage_1 = list(
    calipers = LMV2_P3$stage_1$calipers,
    n_controls = LMV2_P3$stage_1$n_controls,
    control_weight = 1 / LMV2_P3$stage_1$n_controls,
    distance_variants = c("distance_base", "distance_with_trajectory"),
    core_balance_variables = LMV2_P3$stage_1$scalar_variables,
    diagnostic_balance_variable = LMV2_P3$stage_1$diagnostic_variable,
    trajectory_promotion = list(
      pooled_smd = LMV2_LOCK$matching$stage_1$trajectory_promotion_pooled_smd,
      cohort_smd = LMV2_LOCK$matching$stage_1$trajectory_promotion_era_smd
    ),
    preferred = LMV2_LOCK$pilot$stage_1_preferred,
    acceptable = LMV2_LOCK$pilot$stage_1_acceptable,
    selection_order = LMV2_LOCK$pilot$stage_1_selection_order,
    # Small-cohort amendment (pinned note): cohort-specific Stage-1 SMD and
    # trajectory-promotion gates bind only in cohorts with at least this many
    # treated deals in the primary pilot spine.  Pooled gates always bind.
    # Small-cohort SMDs remain computed and reported, ungated.
    minimum_treated_deals_for_cohort_smd_gate = 10L,
    deal_weighting_primary = "equal_treated_deal",
    deal_weighting_diagnostic = "treated_inventor_count",
    # Trajectory-fallback amendment (pinned note): when no promoted profile
    # is acceptable, fall back to the base profile only if it holds the
    # preferred tier; the pool is frozen provisionally and the final
    # inventor-weighted firm-trajectory balance must clear the locked
    # acceptable bound after Stage 2, or the pilot stops.
    # Ten-firm extension amendment (pinned note): a final structural
    # attempt activated only after the five-firm design exhausts its
    # bounded refinement at Stage 2.  Identical Stage-1 machinery and
    # gates; ten equal weights of 0.1; five-firm diagnostics preserved as
    # primary.  If the ten-firm design also fails, the pilot stops
    # permanently.
    ten_firm_extension = list(
      n_controls = 10L,
      control_weight = 1 / 10,
      activation = "five_firm_stage2_terminal_failure_only",
      stage1_failure_never_activates = TRUE,
      permanent_stop_if_it_fails = TRUE
    ),
    trajectory_fallback = list(
      requires_base_preferred = TRUE,
      provisional_mode_label = "trajectory_fallback_provisional",
      final_firm_balance_variables = c("log_patent_stock_5y",
                                       "log_inventor_count_5y",
                                       "patent_trajectory"),
      final_gated_variable = "patent_trajectory",
      final_max_smd = LMV2_LOCK$pilot$stage_1_acceptable$max_smd
    )
  ),
  stage_2 = list(
    calipers = LMV2_P3$stage_2$calipers,
    n_controls = LMV2_P3$stage_2$n_controls,
    minimum_control_firms = LMV2_P3$stage_2$minimum_control_firms,
    control_weight = LMV2_P3$stage_2$weight,
    core_balance_variables = LMV2_P3$stage_2$scalar_variables,
    preferred = LMV2_LOCK$pilot$stage_2_preferred,
    acceptable = LMV2_LOCK$pilot$stage_2_acceptable,
    # inventor_retention_max in the P0 lock describes the acceptable band's
    # position below the preferred gate; it is not a rejection bound.  A
    # profile above 90% retention with acceptable-only balance stays
    # acceptable.  Recorded prospectively before any pilot execution.
    acceptable_retention_is_minimum_only = TRUE,
    # The P0 lock declares a selection order for Stage 1 only.  The Stage-2
    # order below is declared prospectively here, before any pilot execution.
    selection_order = c("inventor_retention", "deal_retention", "balance",
                        "ess", "loosest_caliper"),
    retention_denominator = "all_primary_spine_treated_in_pilot_cohorts",
    exclusion_funnel = c(
      "deal_lost_at_stage_1", "treated_covariate_missing",
      "insufficient_complete_donors", "no_shared_ipc4_support",
      "recency_gap_failure", "selected_resolution_cosine_missing",
      "fewer_than_three_within_caliper", "no_second_firm", "matched"
    ),
    # Bounded caliper-bisection amendment (pinned note): when the locked
    # grid yields no acceptable profile and an adjacent pair fails on
    # complementary gates, at most two midpoint calipers are evaluated
    # under identical gates.
    bisection = list(
      max_midpoint_evaluations = 2L,
      requires_no_acceptable_initial_profile = TRUE,
      finite_loose_bound_required = TRUE
    )
  ),
  resolution_rule = list(
    # The P0 lock's "seven-character" resolution (threshold block
    # ipc7_primary_if) maps to runtime ipc_main_group; runtime ipc7 (full
    # subgroup) is diagnostic only.  See the pinned resolution-lock note.
    primary_candidate = "ipc_main_group",
    fallback = "ipc4",
    diagnostic_only = "ipc7",
    thresholds = LMV2_LOCK$matching$technology$ipc7_primary_if
  ),
  db = list(memory_limit = "9GB", threads = 4L, read_only = TRUE)
)
stopifnot(identical(LMV2_P4$pilot_cohorts, c(1995L, 2002L, 2009L)))

lmv2_p4_effective_config <- function() {
  list(
    p4_version = LMV2_P4_VERSION,
    p3_commit = LMV2_P4_P3_COMMIT,
    p3_config_hash = LMV2_P3_CONFIG_HASH,
    p3_manifest_hash = LMV2_P4_P3_MANIFEST_SHA256,
    resolution_lock_hash = LMV2_P4_RESOLUTION_LOCK_SHA256,
    small_cohort_amendment_hash = LMV2_P4_SMALL_COHORT_AMENDMENT_SHA256,
    trajectory_fallback_amendment_hash = LMV2_P4_TRAJECTORY_FALLBACK_AMENDMENT_SHA256,
    bisection_amendment_hash = LMV2_P4_BISECTION_AMENDMENT_SHA256,
    ten_firm_amendment_hash = LMV2_P4_TEN_FIRM_AMENDMENT_SHA256,
    p0_design_hash = LMV2_DESIGN_HASH,
    pilot = LMV2_P4
  )
}

LMV2_P4_EFFECTIVE_CONFIG <- lmv2_p4_effective_config()
LMV2_P4_CONFIG_HASH <- digest::digest(
  LMV2_P4_EFFECTIVE_CONFIG, algo = "sha256", serialize = TRUE
)

# ----------------------------------------------------------------------------
# Pure pilot helpers
# ----------------------------------------------------------------------------

lmv2_p4_read_arg <- function(name, args = commandArgs(trailingOnly = TRUE),
                             required = TRUE) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) != 1L || !nzchar(substring(hit, nchar(prefix) + 1L))) {
    if (!required) return(NA_character_)
    stop("Required argument ", prefix, "<value> is missing")
  }
  substring(hit, nchar(prefix) + 1L)
}

lmv2_p4_validate_p3_manifest <- function(path) {
  observed <- lmv2_p3_file_hash(path)
  if (!identical(observed, LMV2_P4_P3_MANIFEST_SHA256)) {
    stop("P3 interface manifest drifted: expected ", LMV2_P4_P3_MANIFEST_SHA256,
         ", observed ", observed)
  }
  manifest <- utils::read.csv(path, stringsAsFactors = FALSE)
  if (!identical(unique(manifest$p3_config_hash), LMV2_P3_CONFIG_HASH)) {
    stop("P3 interface manifest carries a foreign config hash: ",
         paste(unique(manifest$p3_config_hash), collapse = ","))
  }
  manifest
}

invisible(lmv2_p4_validate_p3_manifest(LMV2_P4_PATHS$p3_manifest))

lmv2_p4_connect <- function(db_path) {
  if (!file.exists(db_path)) stop("Database not found: ", db_path)
  con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = LMV2_P4$db$read_only)
  DBI::dbExecute(con, sprintf("PRAGMA memory_limit='%s'", LMV2_P4$db$memory_limit))
  DBI::dbExecute(con, sprintf("PRAGMA threads=%d", LMV2_P4$db$threads))
  con
}

# Stable profile identifiers: the infinite caliper is labeled "_inf" so that
# no Inf value ever reaches CSV formatting.  Elements are formatted one by
# one so a label never depends on which other calipers sit in the vector.
lmv2_p4_caliper_label <- function(prefix, caliper) {
  paste0(prefix, "_", vapply(caliper, function(x) {
    if (is.infinite(x)) "inf" else format(x, trim = TRUE)
  }, character(1)))
}

# Cohort-standardized SMD in the treated-minus-control convention.  `gap` is
# one control-minus-treated value per weighted unit (deal or treated
# inventor).  Every observation is divided by its own cohort's locked scaler
# SD first; the pooled SMD then averages the standardized observations across
# cohorts.  A degenerate cohort SD contributes zero and is flagged.
lmv2_p4_smd <- function(gap, cohort, weight, scalers) {
  stopifnot(length(gap) == length(cohort), length(gap) == length(weight),
            all(c("cohort", "component_sd") %in% names(scalers)))
  sd_of <- scalers$component_sd[match(cohort, scalers$cohort)]
  degenerate <- is.na(sd_of) | sd_of < LMV2_P3_DISTANCE_EPSILON
  std <- ifelse(degenerate, 0, gap / sd_of)
  ok <- is.finite(std) & is.finite(weight) & weight > 0
  pooled <- if (any(ok)) -sum(std[ok] * weight[ok]) / sum(weight[ok]) else NA_real_
  cohorts <- sort(unique(cohort))
  by_cohort <- vapply(cohorts, function(g) {
    idx <- ok & cohort == g
    if (any(idx)) -sum(std[idx] * weight[idx]) / sum(weight[idx]) else NA_real_
  }, numeric(1))
  names(by_cohort) <- as.character(cohorts)
  list(pooled = pooled, by_cohort = by_cohort,
       degenerate_cohorts = sort(unique(cohort[degenerate])))
}

lmv2_p4_ess <- function(weights) {
  w <- weights[is.finite(weights) & weights > 0]
  if (!length(w)) return(0)
  sum(w)^2 / sum(w^2)
}

lmv2_p4_reuse_adjusted_ess <- function(weight, unit_id) {
  if (!length(weight)) return(0)
  lmv2_p4_ess(as.numeric(tapply(weight, unit_id, sum)))
}

# Tier selection: highest available tier (preferred over acceptable), then
# lexicographic ordering by `order_keys` (named +1 higher-is-better / -1
# lower-is-better numeric columns).  When no profile is acceptable, the best
# dominated profile under the same ordering is returned for the failure
# record.
lmv2_p4_tier_select <- function(profiles, order_keys) {
  stopifnot(nrow(profiles) > 0,
            all(c("preferred_pass", "acceptable_pass") %in% names(profiles)),
            all(names(order_keys) %in% names(profiles)))
  rank_rows <- function(x) {
    do.call(order, lapply(names(order_keys), function(k) -order_keys[[k]] * x[[k]]))
  }
  tier <- if (any(profiles$preferred_pass)) "preferred"
          else if (any(profiles$acceptable_pass)) "acceptable" else "none"
  pool <- switch(tier,
                 preferred = profiles[profiles$preferred_pass, , drop = FALSE],
                 acceptable = profiles[profiles$acceptable_pass, , drop = FALSE],
                 none = NULL)
  selected <- if (!is.null(pool)) pool[rank_rows(pool), , drop = FALSE][1, , drop = FALSE] else NULL
  list(tier = tier, selected = selected,
       best_dominated = profiles[rank_rows(profiles), , drop = FALSE][1, , drop = FALSE])
}

# Small-cohort amendment: cohort-specific Stage-1 gates bind only where the
# pilot spine holds enough treated deals.  `deal_counts` is a named vector
# (cohort label -> treated deals in the primary pilot spine).
lmv2_p4_gate_cohorts <- function(deal_counts,
                                 minimum = LMV2_P4$stage_1$minimum_treated_deals_for_cohort_smd_gate) {
  names(deal_counts)[deal_counts >= minimum]
}

# Stage-1 gate evaluation under the small-cohort amendment: pooled gates
# always bind; `cohort_core_eligible` holds only SMDs from gate-eligible
# cohorts, so the cohort conditions are vacuously satisfied when no cohort
# is eligible.  NA balance fails both tiers.
lmv2_p4_stage1_gate_pass <- function(pooled_core, cohort_core_eligible,
                                     deal_retention,
                                     preferred = LMV2_P4$stage_1$preferred,
                                     acceptable = LMV2_P4$stage_1$acceptable) {
  list(
    preferred =
      isTRUE(all(abs(pooled_core) <= preferred$pooled_smd)) &&
      isTRUE(all(abs(cohort_core_eligible) <= preferred$era_smd)) &&
      isTRUE(deal_retention >= preferred$deal_retention),
    acceptable =
      isTRUE(all(abs(c(pooled_core, cohort_core_eligible)) <= acceptable$max_smd)) &&
      isTRUE(deal_retention >= acceptable$deal_retention)
  )
}

lmv2_p4_trajectory_promotion_triggered <- function(pooled_smd, cohort_smds) {
  isTRUE(abs(pooled_smd) > LMV2_P4$stage_1$trajectory_promotion$pooled_smd) ||
    isTRUE(any(abs(cohort_smds) > LMV2_P4$stage_1$trajectory_promotion$cohort_smd,
               na.rm = TRUE))
}

# Trajectory-fallback amendment: resolve the Stage-1 selection across the
# base and (when evaluated) promoted grids.  A promoted profile in any
# acceptable tier wins; otherwise fallback to the base profile only if it
# holds the preferred tier (acceptable-only base cannot qualify); otherwise
# the pilot fails.  `promoted_choice = NULL` means promotion never triggered.
lmv2_p4_stage1_resolve <- function(base_choice, promoted_choice = NULL) {
  if (is.null(promoted_choice)) {
    return(list(mode = "standard", choice = base_choice))
  }
  if (promoted_choice$tier != "none") {
    return(list(mode = "promoted", choice = promoted_choice))
  }
  if (identical(base_choice$tier, "preferred")) {
    return(list(mode = LMV2_P4$stage_1$trajectory_fallback$provisional_mode_label,
                choice = base_choice))
  }
  list(mode = "failed", choice = promoted_choice)
}

# Binary primary-resolution rule over the admissible-pool cohort diagnostics
# produced by lmv2_inventor_ipc_diagnostics().  Selects the primary candidate
# (ipc_main_group) if and only if every pilot cohort passes all four locked
# thresholds; otherwise the fallback (ipc4).  Structurally cannot return the
# diagnostic-only full-subgroup resolution.
lmv2_p4_resolution_choice <- function(cohort_diagnostics,
                                      cohorts = LMV2_P4$pilot_cohorts,
                                      thresholds = LMV2_P4$resolution_rule$thresholds) {
  candidate <- LMV2_P4$resolution_rule$primary_candidate
  if (!all(c("cohort", "resolution") %in% names(cohort_diagnostics))) {
    # A cohort without admissible pairs yields no diagnostics; missing
    # evidence fails the binary rule and forces the fallback resolution.
    cohort_diagnostics <- data.frame(cohort = integer(), resolution = character())
  }
  x <- cohort_diagnostics[cohort_diagnostics$resolution == candidate, , drop = FALSE]
  threshold_names <- c("share_three_positive_controls_two_firms",
                       "median_distinct_positive_values",
                       "median_zero_cosine_share_below",
                       "share_all_nearest_tied_below")
  required <- c(thresholds$share_three_positive_controls_two_firms,
                thresholds$median_distinct_positive_values,
                thresholds$median_zero_cosine_share_below,
                thresholds$share_all_nearest_tied_below)
  evidence <- do.call(rbind, lapply(sort(cohorts), function(g) {
    z <- x[x$cohort == g, , drop = FALSE]
    value <- if (nrow(z) == 1L) c(
      z$share_feasible_three_controls_two_firms,
      z$median_distinct_positive_values,
      z$median_zero_cosine_share,
      z$share_nearest_tied
    ) else rep(NA_real_, 4L)
    pass <- c(value[1] >= required[1], value[2] >= required[2],
              value[3] < required[3], value[4] < required[4])
    pass[is.na(pass)] <- FALSE
    data.frame(cohort = g, resolution = candidate, threshold = threshold_names,
               value = value, required = required, pass = pass,
               stringsAsFactors = FALSE)
  }))
  all_pass <- isTRUE(all(evidence$pass))
  list(resolution = if (all_pass) candidate else LMV2_P4$resolution_rule$fallback,
       evidence = evidence)
}

# Mutually exclusive terminal-reason funnel.  `state` holds one row per
# treated inventor with terminal_reason NA while still pending; each step
# assigns `reason` to pending inventors that lost feasible support (fewer
# than `n_controls` distinct donors) in `surviving_pairs`.  Firm
# diversification is deliberately not checked before the caliper stage: an
# inventor whose remaining donors sit in a single firm stays pending and
# receives the terminal reason no_second_firm from the selector, so the
# causal decomposition attributes firm-diversity failures correctly.
lmv2_p4_feasible_treated <- function(pair_map,
                                     n_controls = LMV2_P4$stage_2$n_controls) {
  if (!nrow(pair_map)) return(character(0))
  key <- paste(pair_map$cohort, pair_map$deal_id, pair_map$treated_codinv, sep = "\r")
  donors <- tapply(pair_map$control_codinv, key, function(x) length(unique(x)))
  names(donors)[donors >= n_controls]
}

lmv2_p4_funnel_step <- function(state, surviving_pairs, reason) {
  stopifnot(all(c("cohort", "deal_id", "treated_codinv", "terminal_reason") %in% names(state)))
  feasible <- lmv2_p4_feasible_treated(surviving_pairs)
  key <- paste(state$cohort, state$deal_id, state$treated_codinv, sep = "\r")
  newly_lost <- is.na(state$terminal_reason) & !(key %in% feasible)
  state$terminal_reason[newly_lost] <- reason
  state
}

# Bounded caliper-bisection amendment: classify a Stage-2 profile's failure
# for the bracket logic.  "balance_only" = max gated |SMD| above the
# acceptable bound with all retention-family and target-size gates passing;
# "retention_only" = any retention-family gate failing with balance and
# target-size passing; anything else (including a lost target-size
# category or joint failures) is "other" and never enters a bracket.
lmv2_p4_stage2_failure_type <- function(profile,
                                        acceptable = LMV2_P4$stage_2$acceptable) {
  if (isTRUE(profile$acceptable_pass)) return("acceptable")
  balance_fail <- !isTRUE(profile$max_abs_smd <= acceptable$max_smd)
  retention_fail <-
    !isTRUE(profile$inventor_retention >= acceptable$inventor_retention_min) ||
    !isTRUE(profile$deal_retention >= acceptable$deal_retention) ||
    !isTRUE(profile$min_cohort_retention >= acceptable$minimum_cohort_retention)
  other_fail <- !isTRUE(profile$big_categories_preserved)
  if (balance_fail && !retention_fail && !other_fail) return("balance_only")
  if (retention_fail && !balance_fail && !other_fail) return("retention_only")
  "other"
}

# Find the loosest adjacent complementary pair in the locked grid (profiles
# must be in locked grid order, loosest first).  The loose bound must be
# finite for a midpoint to exist.  Returns list(loose, tight) or NULL.
lmv2_p4_bisection_bracket <- function(profiles) {
  types <- vapply(seq_len(nrow(profiles)), function(i) {
    lmv2_p4_stage2_failure_type(profiles[i, , drop = FALSE])
  }, character(1))
  for (i in seq_len(max(nrow(profiles) - 1L, 0L))) {
    if (types[i] == "balance_only" && types[i + 1L] == "retention_only" &&
        is.finite(profiles$caliper[i])) {
      return(list(loose = profiles$caliper[i], tight = profiles$caliper[i + 1L]))
    }
  }
  NULL
}

# Update the bracket after a midpoint evaluation.  A balance-only failure
# replaces the loose bound; a retention-only failure replaces the tight
# bound; an acceptable midpoint also becomes the tight bound so refinement
# continues toward the looser boundary for higher retention.  Any other
# failure ends the refinement (NULL).
lmv2_p4_bisection_next <- function(bracket, midpoint, failure_type) {
  if (failure_type == "balance_only") {
    list(loose = midpoint, tight = bracket$tight)
  } else if (failure_type %in% c("retention_only", "acceptable")) {
    list(loose = bracket$loose, tight = midpoint)
  } else {
    NULL
  }
}

# The 16c Stage-1 selector labels its unsupported reason for the locked
# five-firm pool; the ten-firm extension relabels its own outputs without
# touching the certified engine.
lmv2_p4_relabel_stage1_reason <- function(reasons, pool_n) {
  if (identical(pool_n, LMV2_P4$stage_1$ten_firm_extension$n_controls)) {
    reasons <- sub("^fewer_than_five_", "fewer_than_ten_", reasons)
  }
  reasons
}

# Canonical checksum of a caller-ordered data frame (frozen Stage-1 pools,
# matched sets, the selected design).  Column names and NA markers are part
# of the payload; row order matters by design.
lmv2_p4_frame_checksum <- function(x) {
  cols <- lapply(x, function(col) {
    out <- as.character(col)
    out[is.na(col)] <- "<NA>"
    out
  })
  rows <- if (nrow(x)) do.call(paste, c(cols, sep = "|")) else character(0)
  digest::digest(paste(c(paste(names(x), collapse = "|"), rows), collapse = "\n"),
                 algo = "sha256", serialize = FALSE)
}

lmv2_p4_write_csv <- function(x, dir, name) {
  utils::write.csv(x, file.path(dir, name), row.names = FALSE, na = "")
}

# Logical manifest of a pilot run directory.  Scripts write deterministically
# ordered rows and no timestamps, absolute paths, or run labels, so the byte
# hash of each CSV is its logical fingerprint.
lmv2_p4_logical_manifest <- function(dir) {
  files <- sort(list.files(dir, pattern = "\\.csv$", recursive = TRUE))
  out <- do.call(rbind, lapply(files, function(f) {
    path <- file.path(dir, f)
    data.frame(file = f,
               rows = nrow(utils::read.csv(path, stringsAsFactors = FALSE)),
               logical_sha256 = lmv2_p3_file_hash(path),
               stringsAsFactors = FALSE)
  }))
  if (is.null(out)) out <- data.frame(file = character(), rows = integer(),
                                      logical_sha256 = character())
  out$p4_version <- rep(LMV2_P4_VERSION, nrow(out))
  out$p4_config_hash <- rep(LMV2_P4_CONFIG_HASH, nrow(out))
  out
}
