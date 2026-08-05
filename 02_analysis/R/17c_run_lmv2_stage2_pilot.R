# ============================================================================
# 17c_run_lmv2_stage2_pilot.R -- outcome-blind Stage-2 inventor-matching pilot
# ============================================================================
# Requires the frozen Stage-1 pools.  Per pilot cohort it builds the donor
# pool from the frozen firms only, runs the mutually exclusive exclusion
# funnel, computes technology-support diagnostics on the admissible pool for
# all three resolutions, applies the binary resolution rule, evaluates the
# locked caliper grid, selects a profile by the locked tiers, and freezes the
# P4 design.  The database is opened read-only; every output is a
# deterministic CSV in the explicit audit directory.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17a_lmv2_p4_pilot_config.R"))
for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

db_path <- lmv2_p4_read_arg("db")
p3_manifest_path <- lmv2_p4_read_arg("p3-manifest")
audit_dir <- lmv2_p4_read_arg("audit-dir")
invisible(lmv2_p4_validate_p3_manifest(p3_manifest_path))

# Stage 1 must be frozen, with an intact checksum, before any Stage-2 work.
freeze_path <- file.path(audit_dir, "p4_stage1_freeze.csv")
frozen_path <- file.path(audit_dir, "p4_stage1_frozen_firms.csv")
if (!file.exists(freeze_path) || !file.exists(frozen_path)) {
  stop("Stage-1 freeze missing in ", audit_dir, "; run 17b first")
}
freeze <- utils::read.csv(freeze_path, stringsAsFactors = FALSE)
frozen <- utils::read.csv(frozen_path, stringsAsFactors = FALSE)
if (!identical(freeze$p4_config_hash, LMV2_P4_CONFIG_HASH)) {
  stop("Stage-1 freeze was produced under a different P4 configuration")
}
if (!identical(lmv2_p4_frame_checksum(frozen), freeze$frozen_firms_sha256)) {
  stop("Frozen Stage-1 firm pools drifted from their recorded checksum")
}

con <- lmv2_p4_connect(db_path)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

s2_vars <- LMV2_P4$stage_2$core_balance_variables
cohort_sql <- paste(LMV2_P4$pilot_cohorts, collapse = ",")

spine <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, codinv, recency_bin, %s
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort IN (%s)
  ORDER BY cohort, deal_id, codinv",
  paste(s2_vars, collapse = ", "), cohort_sql))
spine_deals <- unique(spine[c("cohort", "deal_id")])

# Locked target-size indicator from the certified P2 interface (deal-level
# pre-treatment characteristic; no other column of the interface is read).
deal_size_map <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT deal_id, big_deal
  FROM lmv2_treated_primary
  WHERE cohort IN (%s)
  ORDER BY deal_id", cohort_sql))
stopifnot(!anyDuplicated(deal_size_map$deal_id),
          all(spine_deals$deal_id %in% deal_size_map$deal_id))
spine_deals <- merge(spine_deals, deal_size_map, by = "deal_id", sort = FALSE)
spine_deals <- spine_deals[order(spine_deals$cohort, spine_deals$deal_id), , drop = FALSE]

# ---------------------------------------------------------------------------
# Pass A per cohort: donor pools, funnel steps before the caliper, technology
# cache, and admissible-pool support diagnostics for all three resolutions.
# ---------------------------------------------------------------------------

pair_key_cols <- c("cohort", "deal_id", "treated_codinv", "control_codinv")
funnel_states <- list()
support_units <- list()
support_cohorts <- list()
donor_exclusions <- list()
# Genuine cohort sharding: Pass A writes each cohort's frames to a temporary
# shard file and frees them; Pass B reloads one shard at a time after the
# resolution decision.  Shards are removed before the pilot finishes.
shard_dir <- file.path(audit_dir, "shards")
dir.create(shard_dir, recursive = TRUE, showWarnings = FALSE)
shard_path <- function(g) file.path(shard_dir, sprintf("cohort_%d.rds", g))

for (g in LMV2_P4$pilot_cohorts) {
  gc()
  frozen_g <- frozen[frozen$cohort == g, , drop = FALSE]
  treated_g <- spine[spine$cohort == g, , drop = FALSE]
  state <- data.frame(cohort = treated_g$cohort, deal_id = treated_g$deal_id,
                      treated_codinv = treated_g$codinv,
                      terminal_reason = NA_character_,
                      stringsAsFactors = FALSE)

  # Funnel step 1: deal lost at Stage 1.
  lost <- !(treated_g$deal_id %in% unique(frozen_g$deal_id))
  state$terminal_reason[lost] <- "deal_lost_at_stage_1"

  # Funnel step 2: treated matching covariate missing (never imputed).
  treated_complete <- stats::complete.cases(treated_g[c(s2_vars, "recency_bin")])
  state$terminal_reason[is.na(state$terminal_reason) & !treated_complete] <-
    "treated_covariate_missing"
  treated_c <- treated_g[treated_complete & !lost, , drop = FALSE]

  # Donor pool: eligible control inventors from the frozen firms only, with
  # focal tenure and exclusivity computed on demand.
  donors_g <- DBI::dbGetQuery(con, sprintf("
    SELECT DISTINCT cohort, codinv, focal_group, recency_bin,
           log_patent_count_5y, patent_trajectory, career_age
    FROM lmv2_p3_inventor_general_units
    WHERE role = 'control' AND cohort = %d AND focal_group IN (%s)
    ORDER BY codinv, focal_group",
    g, paste(sort(unique(frozen_g$control_group)), collapse = ",")))
  # Locked control rule: one candidate control group per inventor-cohort.
  stopifnot(!anyDuplicated(donors_g$codinv))
  focal <- lmv2_build_control_focal_covariates(
    con, donors_g[c("cohort", "codinv", "focal_group")])
  donors_g <- merge(donors_g, focal, by = c("cohort", "codinv", "focal_group"),
                    sort = FALSE)
  donor_complete <- stats::complete.cases(donors_g[c(s2_vars, "recency_bin")])
  incomplete <- donors_g[!donor_complete, , drop = FALSE]
  donor_exclusions[[as.character(g)]] <- data.frame(
    cohort = g,
    donors_in_frozen_firms = nrow(donors_g),
    donors_complete = sum(donor_complete),
    donors_missing_focal_group_tenure = sum(is.na(incomplete$focal_group_tenure)),
    donors_missing_focal_group_exclusivity = sum(is.na(incomplete$focal_group_exclusivity)),
    donors_missing_other_covariate = sum(
      !stats::complete.cases(incomplete[c("log_patent_count_5y", "patent_trajectory",
                                          "career_age", "recency_bin")]))
  )
  donors_c <- donors_g[donor_complete, , drop = FALSE]

  # Candidate pairs: treated x complete donors from the deal's frozen firms.
  pool <- frozen_g[c("cohort", "deal_id", "control_group")]
  donor_cols <- donors_c
  names(donor_cols)[names(donor_cols) == "codinv"] <- "control_codinv"
  names(donor_cols)[names(donor_cols) == "focal_group"] <- "control_group"
  pairs_a <- merge(pool, donor_cols[c("cohort", "control_codinv", "control_group")],
                   by = c("cohort", "control_group"))
  treated_key <- treated_c[c("cohort", "deal_id", "codinv")]
  names(treated_key)[names(treated_key) == "codinv"] <- "treated_codinv"
  pairs_a <- merge(treated_key, pairs_a, by = c("cohort", "deal_id"))

  # Funnel step 3: insufficient complete donors.
  state <- lmv2_p4_funnel_step(state, pairs_a, "insufficient_complete_donors")
  pending <- paste(state$cohort, state$deal_id, state$treated_codinv, sep = "\r")[
    is.na(state$terminal_reason)]
  pairs_a <- pairs_a[paste(pairs_a$cohort, pairs_a$deal_id,
                           pairs_a$treated_codinv, sep = "\r") %in% pending, ,
                     drop = FALSE]

  # One technology cache per pilot cohort (all three resolutions plus the
  # shared-IPC4 matrix), built once for the surviving candidate pool.
  cache <- lmv2_stage2_technology_cache(con, pairs_a[pair_key_cols])

  # Funnel step 4: shared IPC4 support.
  shared_true <- cache$shared_ipc4[cache$shared_ipc4$shared_ipc4, , drop = FALSE]
  pairs_b <- merge(pairs_a, shared_true[c("cohort", "treated_codinv", "control_codinv")],
                   by = c("cohort", "treated_codinv", "control_codinv"))
  state <- lmv2_p4_funnel_step(state, pairs_b, "no_shared_ipc4_support")

  # Funnel step 5: recency-bin gap of at most one.
  bins_t <- treated_c[c("cohort", "deal_id", "codinv", "recency_bin")]
  names(bins_t) <- c("cohort", "deal_id", "treated_codinv", "recency_bin_treated")
  bins_c <- donor_cols[c("cohort", "control_codinv", "recency_bin")]
  names(bins_c)[3] <- "recency_bin_control"
  pairs_c <- merge(merge(pairs_b, bins_t, by = c("cohort", "deal_id", "treated_codinv")),
                   bins_c, by = c("cohort", "control_codinv"))
  pairs_c <- pairs_c[abs(pairs_c$recency_bin_treated - pairs_c$recency_bin_control) <=
                       LMV2_P3$stage_2$maximum_recency_bin_gap, , drop = FALSE]
  state <- lmv2_p4_funnel_step(state, pairs_c, "recency_gap_failure")
  pending <- paste(state$cohort, state$deal_id, state$treated_codinv, sep = "\r")[
    is.na(state$terminal_reason)]
  pairs_c <- pairs_c[paste(pairs_c$cohort, pairs_c$deal_id,
                           pairs_c$treated_codinv, sep = "\r") %in% pending, ,
                     drop = FALSE]

  # Admissible-pool support diagnostics for all three resolutions (the
  # locked resolution rule is evaluated only on this pool).
  sim_admissible <- merge(cache$similarity, unique(pairs_c[pair_key_cols[-2]]),
                          by = c("cohort", "treated_codinv", "control_codinv"),
                          sort = FALSE)
  diag <- lmv2_inventor_ipc_diagnostics(
    pairs_c[c("cohort", "treated_codinv", "control_codinv", "control_group")],
    sim_admissible[c("cohort", "treated_codinv", "control_codinv",
                     "resolution", "cosine")])
  if (!nrow(diag$cohort)) {
    # No admissible pairs in this cohort: keep well-formed empty frames so
    # the binary resolution rule degrades to the fallback, not to an error.
    diag$cohort <- data.frame(
      cohort = integer(), resolution = character(),
      median_candidate_count = numeric(), median_positive_control_count = numeric(),
      median_zero_cosine_share = numeric(),
      median_distinct_positive_values = numeric(),
      share_nearest_tied = numeric(),
      share_feasible_three_controls_two_firms = numeric()
    )
    diag$unit <- data.frame(
      cohort = integer(), treated_codinv = numeric(), resolution = character(),
      candidate_count = integer(), positive_control_count = integer(),
      positive_control_firms = integer(), zero_cosine_share = numeric(),
      distinct_positive_values = integer(), nearest_tied = logical(),
      feasible_three_controls_two_firms = logical()
    )
  }
  support_units[[as.character(g)]] <- diag$unit
  support_cohorts[[as.character(g)]] <- diag$cohort

  funnel_states[[as.character(g)]] <- state
  saveRDS(list(treated = treated_c, donors = donors_c, pairs = pairs_c,
               similarity = sim_admissible), shard_path(g))
  rm(cache, pairs_a, pairs_b, pairs_c, shared_true, donors_g, donors_c,
     treated_c, treated_g, sim_admissible, focal, diag)
}

support_cohort_all <- do.call(rbind, support_cohorts)
support_unit_all <- do.call(rbind, support_units)
decision <- lmv2_p4_resolution_choice(support_cohort_all)

lmv2_p4_write_csv(support_cohort_all[order(support_cohort_all$cohort,
                                           support_cohort_all$resolution), ],
                  audit_dir, "p4_stage2_support_cohorts.csv")
support_unit_all <- support_unit_all[order(support_unit_all$cohort,
                                           support_unit_all$resolution,
                                           support_unit_all$treated_codinv), ]
lmv2_p4_write_csv(support_unit_all, audit_dir, "p4_stage2_support_units.csv")
lmv2_p4_write_csv(do.call(rbind, donor_exclusions), audit_dir,
                  "p4_stage2_donor_exclusions.csv")
decision_out <- decision$evidence
decision_out$selected_resolution <- decision$resolution
decision_out$p4_config_hash <- LMV2_P4_CONFIG_HASH
lmv2_p4_write_csv(decision_out, audit_dir, "p4_resolution_decision.csv")
message("P4 resolution decision: ", decision$resolution)

# ---------------------------------------------------------------------------
# Pass B per cohort: cosine support at the selected resolution, edge
# construction through 16c, and the caliper grid.
# ---------------------------------------------------------------------------

all_edges <- list()
all_scalers <- list()

for (g in LMV2_P4$pilot_cohorts) {
  st <- readRDS(shard_path(g))
  state <- funnel_states[[as.character(g)]]

  sim_sel <- st$similarity[st$similarity$resolution == decision$resolution, ,
                           drop = FALSE]
  sim_sel <- sim_sel[c("cohort", "treated_codinv", "control_codinv", "cosine")]

  # Funnel step 6: cosine missing at the selected resolution.
  pairs_d <- merge(st$pairs, sim_sel[!is.na(sim_sel$cosine), pair_key_cols[-2]],
                   by = c("cohort", "treated_codinv", "control_codinv"))
  state <- lmv2_p4_funnel_step(state, pairs_d, "selected_resolution_cosine_missing")
  pending <- paste(state$cohort, state$deal_id, state$treated_codinv, sep = "\r")[
    is.na(state$terminal_reason)]
  pairs_d <- pairs_d[paste(pairs_d$cohort, pairs_d$deal_id,
                           pairs_d$treated_codinv, sep = "\r") %in% pending, ,
                     drop = FALSE]

  shared_flags <- unique(pairs_d[pair_key_cols[-2]])
  shared_flags$shared_ipc4 <- rep(TRUE, nrow(shared_flags))
  prep <- lmv2_prepare_stage2_edges(
    treated = st$treated, controls = st$donors,
    pair_map = pairs_d[pair_key_cols],
    similarity = sim_sel, shared_ipc4 = shared_flags,
    resolution = decision$resolution
  )
  all_edges[[as.character(g)]] <- prep$edges
  all_scalers[[as.character(g)]] <- prep$scalers
  funnel_states[[as.character(g)]] <- state
  rm(st, prep, pairs_d, sim_sel, shared_flags)
  file.remove(shard_path(g))
  gc()
}
unlink(shard_dir, recursive = TRUE)

edges <- do.call(rbind, all_edges)
scalers <- do.call(rbind, all_scalers)
scalers_out <- scalers
scalers_out$resolution <- ifelse(scalers_out$component == "tech_distance",
                                 decision$resolution, NA_character_)
lmv2_p4_write_csv(scalers_out[order(scalers_out$cohort, scalers_out$component), ],
                  audit_dir, "p4_stage2_scalers.csv")
rm(all_edges, all_scalers)
gc()

# ---------------------------------------------------------------------------
# Caliper grid, matched-set balance, and tier selection.
# ---------------------------------------------------------------------------

spine_n <- nrow(spine)
base_state <- do.call(rbind, funnel_states)

evaluate_stage2_profile <- function(caliper) {
  profile_id <- lmv2_p4_caliper_label("cI", caliper)
  sel <- lmv2_select_stage2(edges, caliper,
                            n_controls = LMV2_P4$stage_2$n_controls,
                            minimum_firms = LMV2_P4$stage_2$minimum_control_firms,
                            weight = LMV2_P4$stage_2$control_weight)
  unsupported <- attr(sel, "unsupported")

  # Funnel steps 7-9: caliper support, second firm, matched.
  state <- base_state
  if (!is.null(unsupported) && nrow(unsupported)) {
    reason_map <- c(
      no_candidates_within_total_distance_caliper = "fewer_than_three_within_caliper",
      fewer_than_three_within_total_distance_caliper = "fewer_than_three_within_caliper",
      no_second_eligible_control_firm = "no_second_firm"
    )
    key <- paste(state$cohort, state$deal_id, state$treated_codinv, sep = "\r")
    ukey <- paste(unsupported$cohort, unsupported$deal_id,
                  unsupported$treated_codinv, sep = "\r")
    hit <- match(key, ukey)
    assign_idx <- is.na(state$terminal_reason) & !is.na(hit)
    state$terminal_reason[assign_idx] <-
      unname(reason_map[unsupported$reason[hit[assign_idx]]])
  }
  matched_key <- unique(paste(sel$cohort, sel$deal_id, sel$treated_codinv, sep = "\r"))
  key <- paste(state$cohort, state$deal_id, state$treated_codinv, sep = "\r")
  state$terminal_reason[is.na(state$terminal_reason) & key %in% matched_key] <- "matched"
  # Every pending inventor entered the caliper stage with feasible support,
  # so the selector must have either matched it or recorded a reason.  Any
  # remainder is an accounting defect and stops the pilot.
  if (anyNA(state$terminal_reason)) {
    stop("P4 Stage 2 funnel accounting defect: ",
         sum(is.na(state$terminal_reason)), " treated inventors unaccounted")
  }
  stopifnot(all(state$terminal_reason %in% LMV2_P4$stage_2$exclusion_funnel),
            nrow(state) == spine_n)
  funnel <- stats::aggregate(rep.int(1L, nrow(state)),
                             state[c("cohort", "terminal_reason")], sum)
  names(funnel)[ncol(funnel)] <- "n_treated"
  funnel$profile_id <- rep(profile_id, nrow(funnel))
  funnel <- funnel[order(funnel$cohort, funnel$terminal_reason),
                   c("profile_id", "cohort", "terminal_reason", "n_treated")]
  stopifnot(sum(funnel$n_treated) == spine_n)

  # Matched-set weighted balance: per-treated mean control-minus-treated gap,
  # cohort-standardized by the locked Stage-2 scalers, equal weight per
  # matched treated inventor (the estimand is the average treated inventor).
  if (nrow(sel)) {
    set_gap <- stats::aggregate(sel[paste0("gap_", s2_vars)],
                                sel[c("cohort", "deal_id", "treated_codinv")], mean)
    set_gap <- set_gap[order(set_gap$cohort, set_gap$deal_id,
                             set_gap$treated_codinv), , drop = FALSE]
  } else {
    set_gap <- data.frame(cohort = integer(), deal_id = integer(),
                          treated_codinv = numeric())
    for (v in s2_vars) set_gap[[paste0("gap_", v)]] <- numeric(0)
  }
  smds <- lapply(s2_vars, function(v) {
    sc <- scalers[scalers$component == v, c("cohort", "component_sd")]
    lmv2_p4_smd(set_gap[[paste0("gap_", v)]], set_gap$cohort,
                rep(1, nrow(set_gap)), sc)
  })
  names(smds) <- s2_vars

  sel$control_key <- paste(sel$cohort, sel$control_codinv, sep = "\r")
  reuse <- lmv2_control_reuse_counts(sel)

  matched_deals <- unique(sel[c("cohort", "deal_id")])
  matched_deals_big <- merge(matched_deals, deal_size_map, by = "deal_id",
                             sort = FALSE)
  spine_big <- sort(unique(spine_deals$big_deal))
  big_preserved <- all(spine_big %in% unique(matched_deals_big$big_deal))
  big_retention <- do.call(rbind, lapply(spine_big, function(b) {
    spine_b <- spine_deals[spine_deals$big_deal == b, , drop = FALSE]
    data.frame(profile_id = profile_id, big_deal = b,
               deals_spine = nrow(spine_b),
               deals_matched = sum(matched_deals_big$big_deal == b),
               stringsAsFactors = FALSE)
  }))

  # Structural checks: weight sums and two-firm diversification.
  if (nrow(sel)) {
    wsum <- tapply(sel$weight, paste(sel$cohort, sel$deal_id,
                                     sel$treated_codinv, sep = "\r"), sum)
    firms <- tapply(sel$control_group, paste(sel$cohort, sel$deal_id,
                                             sel$treated_codinv, sep = "\r"),
                    function(x) length(unique(x)))
    weight_sum_ok <- all(abs(wsum - 1) < 1e-12)
    two_firm_ok <- all(firms >= LMV2_P4$stage_2$minimum_control_firms)
  } else {
    weight_sum_ok <- TRUE
    two_firm_ok <- TRUE
  }

  scopes <- c("pooled", as.character(sort(LMV2_P4$pilot_cohorts)))
  metrics <- do.call(rbind, lapply(scopes, function(scope) {
    in_scope <- if (scope == "pooled") rep(TRUE, nrow(sel)) else sel$cohort == as.integer(scope)
    spine_scope <- if (scope == "pooled") spine else spine[spine$cohort == as.integer(scope), , drop = FALSE]
    state_scope <- if (scope == "pooled") state else state[state$cohort == as.integer(scope), , drop = FALSE]
    deals_scope <- if (scope == "pooled") spine_deals else
      spine_deals[spine_deals$cohort == as.integer(scope), , drop = FALSE]
    matched_n <- sum(state_scope$terminal_reason == "matched")
    survivors_n <- sum(state_scope$terminal_reason != "deal_lost_at_stage_1")
    deals_matched <- length(unique(paste(sel$cohort, sel$deal_id, sep = "\r")[in_scope]))
    reuse_scope <- if (scope == "pooled") reuse$reuse_count else
      reuse$reuse_count[reuse$cohort == as.integer(scope)]
    gap_scope <- sel$recency_bin_treated[in_scope] - sel$recency_bin_control[in_scope]
    smd_val <- function(smd) if (scope == "pooled") smd$pooled else
      unname(smd$by_cohort[scope])
    row <- data.frame(
      profile_id = profile_id,
      caliper = if (is.infinite(caliper)) NA_real_ else caliper,
      scope = scope,
      treated_spine = nrow(spine_scope),
      treated_matched = matched_n,
      inventor_retention = matched_n / nrow(spine_scope),
      inventor_retention_conditional_stage1 =
        if (survivors_n) matched_n / survivors_n else NA_real_,
      deals_spine = nrow(deals_scope),
      deals_matched = deals_matched,
      deal_retention = deals_matched / nrow(deals_scope),
      ess_raw = lmv2_p4_ess(sel$weight[in_scope]),
      ess_reuse_adjusted = lmv2_p4_reuse_adjusted_ess(sel$weight[in_scope],
                                                      sel$control_key[in_scope]),
      max_control_reuse = if (length(reuse_scope)) max(reuse_scope) else 0L,
      top_decile_control_reuse = if (length(reuse_scope))
        as.numeric(stats::quantile(reuse_scope, 0.9, type = 1)) else 0,
      mean_abs_recency_gap = if (any(in_scope)) mean(abs(gap_scope)) else NA_real_,
      share_recency_gap_zero = if (any(in_scope)) mean(gap_scope == 0) else NA_real_,
      weight_sum_ok = weight_sum_ok,
      two_firm_ok = two_firm_ok,
      stringsAsFactors = FALSE
    )
    for (v in s2_vars) row[[paste0("smd_", v)]] <- smd_val(smds[[v]])
    row
  }))

  pooled_row <- metrics[metrics$scope == "pooled", , drop = FALSE]
  cohort_rows <- metrics[metrics$scope != "pooled", , drop = FALSE]
  pooled_smds <- unlist(lapply(s2_vars, function(v) pooled_row[[paste0("smd_", v)]]))
  cohort_smds <- unlist(lapply(s2_vars, function(v) cohort_rows[[paste0("smd_", v)]]))
  max_abs <- function(x) if (all(is.na(x))) Inf else max(abs(x), na.rm = TRUE)
  pref <- LMV2_P4$stage_2$preferred
  acc <- LMV2_P4$stage_2$acceptable
  profile <- data.frame(
    profile_id = profile_id, caliper = caliper,
    resolution = decision$resolution,
    inventor_retention = pooled_row$inventor_retention,
    deal_retention = pooled_row$deal_retention,
    min_cohort_retention = min(cohort_rows$inventor_retention),
    max_abs_smd = max_abs(c(pooled_smds, cohort_smds)),
    ess_reuse_adjusted = pooled_row$ess_reuse_adjusted,
    big_categories_preserved = big_preserved,
    weight_sum_ok = weight_sum_ok, two_firm_ok = two_firm_ok,
    preferred_pass =
      isTRUE(all(abs(pooled_smds) <= pref$pooled_smd)) &&
      isTRUE(all(abs(cohort_smds) <= pref$era_smd)) &&
      isTRUE(pooled_row$inventor_retention >= pref$inventor_retention) &&
      isTRUE(pooled_row$deal_retention >= pref$deal_retention),
    # inventor_retention_min is a floor only: higher retention with
    # acceptable-only balance remains acceptable (prospective 17a rule).
    acceptable_pass =
      isTRUE(all(abs(c(pooled_smds, cohort_smds)) <= acc$max_smd)) &&
      isTRUE(pooled_row$inventor_retention >= acc$inventor_retention_min) &&
      isTRUE(pooled_row$deal_retention >= acc$deal_retention) &&
      isTRUE(min(cohort_rows$inventor_retention) >= acc$minimum_cohort_retention) &&
      big_preserved,
    stringsAsFactors = FALSE
  )

  # Retained-versus-excluded treated composition (pooled, by funnel status).
  spine_status <- merge(
    spine, cbind(state, status = ifelse(state$terminal_reason == "matched",
                                        "matched", "excluded")),
    by.x = c("cohort", "deal_id", "codinv"),
    by.y = c("cohort", "deal_id", "treated_codinv"), sort = FALSE)
  composition <- stats::aggregate(spine_status[s2_vars],
                                  spine_status["status"], mean, na.rm = TRUE)
  composition <- cbind(profile_id = profile_id,
                       composition[order(composition$status), , drop = FALSE])

  reuse$profile_id <- rep(profile_id, nrow(reuse))
  sel$control_key <- NULL
  list(profile = profile, metrics = metrics, funnel = funnel,
       composition = composition, big_retention = big_retention,
       reuse = reuse[c("profile_id", "cohort", "control_codinv",
                       "control_group", "reuse_count")],
       selection = sel)
}

stage2_order_keys <- c(inventor_retention = 1, deal_retention = 1,
                       max_abs_smd = -1, ess_reuse_adjusted = 1, caliper = 1)
results <- lapply(LMV2_P4$stage_2$calipers, evaluate_stage2_profile)

# Bounded caliper bisection (pinned amendment): only when the locked grid
# yields no acceptable profile and adjacent calipers fail on complementary
# gates; at most two midpoints, identical gates, refinement toward the
# looser boundary after an acceptable midpoint.  The final firm-trajectory
# result plays no role here.
grid_profiles <- do.call(rbind, lapply(results, `[[`, "profile"))
bisection_steps <- data.frame(step = integer(), caliper = numeric(),
                              loose = numeric(), tight = numeric(),
                              failure_type = character())
if (lmv2_p4_tier_select(grid_profiles, stage2_order_keys)$tier == "none") {
  bracket <- lmv2_p4_bisection_bracket(grid_profiles)
  step <- 0L
  while (!is.null(bracket) &&
         step < LMV2_P4$stage_2$bisection$max_midpoint_evaluations) {
    midpoint <- (bracket$loose + bracket$tight) / 2
    message("P4 Stage 2 bisection midpoint: ", format(midpoint, trim = TRUE))
    res_m <- evaluate_stage2_profile(midpoint)
    results <- c(results, list(res_m))
    step <- step + 1L
    ftype <- lmv2_p4_stage2_failure_type(res_m$profile)
    bisection_steps <- rbind(bisection_steps, data.frame(
      step = step, caliper = midpoint, loose = bracket$loose,
      tight = bracket$tight, failure_type = ftype, stringsAsFactors = FALSE))
    bracket <- lmv2_p4_bisection_next(bracket, midpoint, ftype)
  }
}
lmv2_p4_write_csv(bisection_steps, audit_dir, "p4_stage2_bisection.csv")

profiles <- do.call(rbind, lapply(results, `[[`, "profile"))
selections <- stats::setNames(lapply(results, `[[`, "selection"),
                              profiles$profile_id)

profiles_out <- profiles
profiles_out$caliper <- ifelse(is.infinite(profiles_out$caliper), NA_real_,
                               profiles_out$caliper)
lmv2_p4_write_csv(profiles_out, audit_dir, "p4_stage2_profiles.csv")
lmv2_p4_write_csv(do.call(rbind, lapply(results, `[[`, "metrics")),
                  audit_dir, "p4_stage2_profile_metrics.csv")
lmv2_p4_write_csv(do.call(rbind, lapply(results, `[[`, "funnel")),
                  audit_dir, "p4_stage2_funnel.csv")
lmv2_p4_write_csv(do.call(rbind, lapply(results, `[[`, "composition")),
                  audit_dir, "p4_stage2_composition.csv")
lmv2_p4_write_csv(do.call(rbind, lapply(results, `[[`, "big_retention")),
                  audit_dir, "p4_stage2_big_retention.csv")
lmv2_p4_write_csv(do.call(rbind, lapply(results, `[[`, "reuse")),
                  audit_dir, "p4_stage2_reuse.csv")

choice <- lmv2_p4_tier_select(profiles, stage2_order_keys)

if (choice$tier == "none") {
  failure <- choice$best_dominated
  failure$caliper <- ifelse(is.infinite(failure$caliper), NA_real_, failure$caliper)
  failure$p4_version <- LMV2_P4_VERSION
  failure$p4_config_hash <- LMV2_P4_CONFIG_HASH
  failure$failure <- "no_acceptable_stage2_profile"
  lmv2_p4_write_csv(failure, audit_dir, "p4_stage2_design_failure.csv")
  stop("P4 Stage 2: no acceptable profile; design-failure record written, ",
       "no P4 design frozen")
}

selected <- choice$selected
matched <- selections[[selected$profile_id]]
matched <- matched[c("cohort", "deal_id", "treated_codinv", "control_codinv",
                     "control_group", "rank", "weight", "distance")]
matched <- matched[order(matched$cohort, matched$deal_id,
                         matched$treated_codinv, matched$rank), , drop = FALSE]

# ---------------------------------------------------------------------------
# Final inventor-weighted firm balance (trajectory-fallback amendment): each
# matched treated inventor contributes its target firm's covariates with
# weight one, each matched control inventor its own firm's covariates with
# weight one third, standardized by the locked Stage-1 cohort scalers.  The
# firm-trajectory bound binds when Stage 1 was a provisional fallback
# freeze; it is a stop check on the selected design, never a selection
# criterion.
# ---------------------------------------------------------------------------
fb <- LMV2_P4$stage_1$trajectory_fallback
fb_vars <- fb$final_firm_balance_variables
firm_treated <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, %s FROM lmv2_p3_firm_units
  WHERE role = 'treated' AND cohort IN (%s)
  ORDER BY cohort, deal_id", paste(fb_vars, collapse = ", "), cohort_sql))
firm_control <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, id_group AS control_group, %s FROM lmv2_p3_firm_units
  WHERE role = 'control' AND cohort IN (%s)
  ORDER BY cohort, id_group", paste(fb_vars, collapse = ", "), cohort_sql))
s1_scalers <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, component, component_sd FROM lmv2_p3_stage1_scalers
  WHERE cohort IN (%s) AND resolution IS NULL
  ORDER BY cohort, component", cohort_sql))

fbm <- merge(matched, firm_control, by = c("cohort", "control_group"),
             sort = FALSE)
stopifnot(nrow(fbm) == nrow(matched), !anyNA(fbm[fb_vars]))
set_mean <- stats::aggregate(fbm[fb_vars],
                             fbm[c("cohort", "deal_id", "treated_codinv")], mean)
set_mean <- merge(set_mean, firm_treated, by = c("cohort", "deal_id"),
                  suffixes = c("_control", "_treated"), sort = FALSE)
set_mean <- set_mean[order(set_mean$cohort, set_mean$deal_id,
                           set_mean$treated_codinv), , drop = FALSE]
stopifnot(!anyNA(set_mean[paste0(fb_vars, "_treated")]))

gate_cohorts_final <- lmv2_p4_gate_cohorts(
  stats::setNames(as.integer(table(spine_deals$cohort)),
                  names(table(spine_deals$cohort))))
final_smds <- lapply(fb_vars, function(v) {
  sc <- s1_scalers[s1_scalers$component == v, c("cohort", "component_sd")]
  lmv2_p4_smd(set_mean[[paste0(v, "_control")]] - set_mean[[paste0(v, "_treated")]],
              set_mean$cohort, rep(1, nrow(set_mean)), sc)
})
names(final_smds) <- fb_vars
final_balance <- do.call(rbind, lapply(fb_vars, function(v) {
  smd <- final_smds[[v]]
  data.frame(
    variable = v,
    scope = c("pooled", names(smd$by_cohort)),
    smd = c(smd$pooled, unname(smd$by_cohort)),
    gate_eligible_scope = c(TRUE, names(smd$by_cohort) %in% gate_cohorts_final),
    stringsAsFactors = FALSE
  )
}))
final_balance$stage1_mode <- freeze$stage1_mode
final_balance$gated_variable <- fb$final_gated_variable
final_balance$threshold <- fb$final_max_smd
final_balance$binding <- freeze$stage1_mode == fb$provisional_mode_label &
  final_balance$variable == fb$final_gated_variable &
  final_balance$gate_eligible_scope
final_balance$pass <- !final_balance$binding | abs(final_balance$smd) <= fb$final_max_smd
lmv2_p4_write_csv(final_balance, audit_dir, "p4_final_firm_balance.csv")

if (!isTRUE(all(final_balance$pass))) {
  stop("P4 final inventor-weighted firm-trajectory balance failed (",
       paste(sprintf("%s %s=%.4f", final_balance$scope[!final_balance$pass],
                     final_balance$variable[!final_balance$pass],
                     final_balance$smd[!final_balance$pass]), collapse = "; "),
       "); no P4 design frozen, do not estimate treatment effects")
}

matched_checksum <- lmv2_p4_frame_checksum(matched)
lmv2_p4_write_csv(matched, audit_dir, "p4_stage2_matched_sets.csv")

design <- data.frame(
  p4_version = LMV2_P4_VERSION,
  p4_config_hash = LMV2_P4_CONFIG_HASH,
  p3_config_hash = LMV2_P3_CONFIG_HASH,
  p3_manifest_hash = LMV2_P4_P3_MANIFEST_SHA256,
  resolution_lock_hash = LMV2_P4_RESOLUTION_LOCK_SHA256,
  small_cohort_amendment_hash = LMV2_P4_SMALL_COHORT_AMENDMENT_SHA256,
  trajectory_fallback_amendment_hash = LMV2_P4_TRAJECTORY_FALLBACK_AMENDMENT_SHA256,
  bisection_amendment_hash = LMV2_P4_BISECTION_AMENDMENT_SHA256,
  ten_firm_amendment_hash = LMV2_P4_TEN_FIRM_AMENDMENT_SHA256,
  stage1_pool_size = freeze$pool_size,
  stage1_mode = freeze$stage1_mode,
  stage1_profile_id = freeze$profile_id,
  stage1_distance_variant = freeze$distance_variant,
  stage1_tier = freeze$tier,
  stage1_frozen_firms_sha256 = freeze$frozen_firms_sha256,
  final_firm_trajectory_smd_pooled =
    final_smds[[fb$final_gated_variable]]$pooled,
  resolution = decision$resolution,
  stage2_profile_id = selected$profile_id,
  stage2_tier = choice$tier,
  inventor_retention = selected$inventor_retention,
  deal_retention = selected$deal_retention,
  max_abs_smd = selected$max_abs_smd,
  ess_reuse_adjusted = selected$ess_reuse_adjusted,
  matched_sets_sha256 = matched_checksum,
  stringsAsFactors = FALSE
)
lmv2_p4_write_csv(design, audit_dir, "p4_design.csv")
message("P4 design frozen: Stage 1 ", freeze$profile_id, "/",
        freeze$distance_variant, ", resolution ", decision$resolution,
        ", Stage 2 ", selected$profile_id, " (", choice$tier, ")")
