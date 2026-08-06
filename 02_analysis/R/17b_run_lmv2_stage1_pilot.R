# ============================================================================
# 17b_run_lmv2_stage1_pilot.R -- outcome-blind Stage-1 firm-matching pilot
# ============================================================================
# Evaluates the locked caliper grid on the certified P3 IPC4 firm edges for
# the pilot cohorts, applies the prospective trajectory-promotion rule,
# selects a profile by the locked tiers, and freezes five control firms per
# deal before any Stage-2 construction.  The database is opened read-only;
# every output is a deterministic CSV in the explicit audit directory.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17a_lmv2_p4_pilot_config.R"))
for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

db_path <- lmv2_p4_read_arg("db")
p3_manifest_path <- lmv2_p4_read_arg("p3-manifest")
audit_dir <- lmv2_p4_read_arg("audit-dir")
# Ten-firm extension amendment: the runner activates the extended pool only
# after the five-firm design exhausts its bounded refinement.
pool_arg <- lmv2_p4_read_arg("pool-size", required = FALSE)
if (is.na(pool_arg)) pool_arg <- "5"
if (!pool_arg %in% c("5", "10")) stop("--pool-size must be 5 or 10")
pool_n <- if (pool_arg == "10") LMV2_P4$stage_1$ten_firm_extension$n_controls else
  LMV2_P4$stage_1$n_controls
pool_weight <- 1 / pool_n
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
invisible(lmv2_p4_validate_p3_manifest(p3_manifest_path))

con <- lmv2_p4_connect(db_path)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

cohort_sql <- paste(LMV2_P4$pilot_cohorts, collapse = ",")
edges <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, target_group, control_group,
         gap_log_patent_stock_5y, gap_log_inventor_count_5y,
         gap_patent_trajectory, distance_base, distance_with_trajectory
  FROM lmv2_p3_stage1_edges
  WHERE cohort IN (%s)
  ORDER BY cohort, deal_id, control_group", cohort_sql))
spine <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id FROM lmv2_p3_firm_units
  WHERE role = 'treated' AND cohort IN (%s)
  ORDER BY cohort, deal_id", cohort_sql))
deal_sizes <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, COUNT(*) AS n_treated_inventors
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort IN (%s)
  GROUP BY cohort, deal_id
  ORDER BY cohort, deal_id", cohort_sql))
scalers <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, component, component_sd, degenerate
  FROM lmv2_p3_stage1_scalers
  WHERE cohort IN (%s) AND resolution IS NULL
  ORDER BY cohort, component", cohort_sql))

stage1_vars <- c(LMV2_P4$stage_1$core_balance_variables,
                 LMV2_P4$stage_1$diagnostic_balance_variable)
stopifnot(nrow(spine) > 0, nrow(edges) > 0,
          setequal(unique(scalers$component), stage1_vars),
          nrow(scalers) == length(stage1_vars) * length(LMV2_P4$pilot_cohorts))

# Spine deals without any admissible IPC4 edge are unsupported by
# construction and profile-invariant.
deal_key <- function(x) paste(x$cohort, x$deal_id, sep = "\r")
missing_edges <- spine[!deal_key(spine) %in% deal_key(unique(edges[c("cohort", "deal_id")])), ,
                       drop = FALSE]
if (nrow(missing_edges)) missing_edges$reason <- "no_admissible_ipc4_edges"

# Small-cohort amendment: cohort-specific gates bind only in cohorts with
# enough treated deals in the pilot spine.
spine_deal_counts <- table(spine$cohort)
gate_cohorts <- lmv2_p4_gate_cohorts(
  stats::setNames(as.integer(spine_deal_counts), names(spine_deal_counts)))
message("P4 Stage 1 cohort-gate-eligible cohorts: ",
        if (length(gate_cohorts)) paste(gate_cohorts, collapse = ", ") else "none")

evaluate_stage1_profile <- function(caliper, distance_col, core_vars) {
  e <- edges
  e$distance <- e[[distance_col]]
  sel <- lmv2_select_stage1(e, caliper, n_controls = pool_n)
  unsupported <- attr(sel, "unsupported")
  if (!is.null(unsupported) && nrow(unsupported)) {
    unsupported$reason <- lmv2_p4_relabel_stage1_reason(unsupported$reason, pool_n)
  }
  profile_id <- lmv2_p4_caliper_label("cF", caliper)

  if (nrow(sel)) {
    deal_gap <- stats::aggregate(sel[paste0("gap_", stage1_vars)],
                                 sel[c("cohort", "deal_id")], mean)
    deal_gap <- merge(deal_gap, deal_sizes, by = c("cohort", "deal_id"), sort = FALSE)
    stopifnot(!anyNA(deal_gap$n_treated_inventors))
    deal_gap <- deal_gap[order(deal_gap$cohort, deal_gap$deal_id), , drop = FALSE]
  } else {
    deal_gap <- data.frame(cohort = integer(), deal_id = integer(),
                           n_treated_inventors = integer())
    for (v in stage1_vars) deal_gap[[paste0("gap_", v)]] <- numeric(0)
  }

  smd_of <- function(var, weights) {
    sc <- scalers[scalers$component == var, c("cohort", "component_sd")]
    lmv2_p4_smd(deal_gap[[paste0("gap_", var)]], deal_gap$cohort, weights, sc)
  }
  smd_equal <- lapply(stage1_vars, smd_of, weights = rep(1, nrow(deal_gap)))
  smd_invw <- lapply(stage1_vars, smd_of, weights = deal_gap$n_treated_inventors)
  names(smd_equal) <- names(smd_invw) <- stage1_vars

  reuse <- if (nrow(sel)) {
    z <- stats::aggregate(rep.int(1L, nrow(sel)),
                          sel[c("cohort", "control_group")], sum)
    names(z)[ncol(z)] <- "reuse_count"
    z
  } else data.frame(cohort = integer(), control_group = numeric(),
                    reuse_count = integer())
  sel$firm_key <- paste(sel$cohort, sel$control_group, sep = "\r")
  weight <- rep(pool_weight, nrow(sel))

  scopes <- c("pooled", as.character(sort(LMV2_P4$pilot_cohorts)))
  metrics <- do.call(rbind, lapply(scopes, function(scope) {
    in_scope <- if (scope == "pooled") rep(TRUE, nrow(sel)) else sel$cohort == as.integer(scope)
    spine_scope <- if (scope == "pooled") spine else spine[spine$cohort == as.integer(scope), , drop = FALSE]
    matched <- unique(sel[in_scope, c("cohort", "deal_id")])
    reuse_scope <- if (scope == "pooled") reuse$reuse_count else
      reuse$reuse_count[reuse$cohort == as.integer(scope)]
    smd_val <- function(smd) if (scope == "pooled") smd$pooled else
      unname(smd$by_cohort[scope])
    row <- data.frame(
      distance_variant = distance_col, profile_id = profile_id,
      caliper = if (is.infinite(caliper)) NA_real_ else caliper,
      scope = scope, deals_spine = nrow(spine_scope), deals_matched = nrow(matched),
      deal_retention = nrow(matched) / nrow(spine_scope),
      ess_raw = lmv2_p4_ess(weight[in_scope]),
      ess_reuse_adjusted = lmv2_p4_reuse_adjusted_ess(weight[in_scope],
                                                      sel$firm_key[in_scope]),
      max_firm_reuse = if (length(reuse_scope)) max(reuse_scope) else 0L,
      top_decile_firm_reuse = if (length(reuse_scope))
        as.numeric(stats::quantile(reuse_scope, 0.9, type = 1)) else 0,
      stringsAsFactors = FALSE
    )
    for (v in stage1_vars) {
      row[[paste0("smd_", v)]] <- smd_val(smd_equal[[v]])
      row[[paste0("smd_", v, "_invw")]] <- smd_val(smd_invw[[v]])
    }
    row
  }))

  smd_in_scope <- function(vars, scopes) {
    unlist(lapply(vars, function(v)
      metrics[[paste0("smd_", v)]][metrics$scope %in% scopes]))
  }
  small_cohorts <- setdiff(as.character(LMV2_P4$pilot_cohorts), gate_cohorts)
  pooled_core <- smd_in_scope(core_vars, "pooled")
  cohort_core_eligible <- smd_in_scope(core_vars, gate_cohorts)
  cohort_core_small <- smd_in_scope(core_vars, small_cohorts)
  pooled_row <- metrics[metrics$scope == "pooled", , drop = FALSE]
  # An empty or cohort-degenerate selection yields NA SMDs; NA gates fail and
  # the worst possible balance metric keeps the profile last in the ordering.
  max_abs <- function(x) if (all(is.na(x))) Inf else max(abs(x), na.rm = TRUE)
  # Reporting variant: NA when there is nothing to report, never Inf.
  max_abs_report <- function(x) if (!length(x) || all(is.na(x))) NA_real_ else
    max(abs(x), na.rm = TRUE)
  gate <- lmv2_p4_stage1_gate_pass(pooled_core, cohort_core_eligible,
                                   pooled_row$deal_retention)
  traj_eligible <- smd_in_scope("patent_trajectory", gate_cohorts)
  profile <- data.frame(
    distance_variant = distance_col, profile_id = profile_id, caliper = caliper,
    deal_retention = pooled_row$deal_retention,
    # Ordering and gating use the gated scope (pooled plus eligible cohorts);
    # small-cohort SMDs stay visible in the reporting columns below and in
    # the full profile-metrics output.
    max_abs_smd = max_abs(c(pooled_core, cohort_core_eligible)),
    max_abs_smd_small_cohorts = max_abs_report(cohort_core_small),
    ess_reuse_adjusted = pooled_row$ess_reuse_adjusted,
    gate_cohorts = paste(gate_cohorts, collapse = ";"),
    preferred_pass = gate$preferred,
    acceptable_pass = gate$acceptable,
    trajectory_smd_pooled =
      metrics$smd_patent_trajectory[metrics$scope == "pooled"],
    max_abs_trajectory_smd_cohort =
      if (!length(traj_eligible)) 0 else max_abs(traj_eligible),
    max_abs_trajectory_smd_small_cohorts =
      max_abs_report(smd_in_scope("patent_trajectory", small_cohorts)),
    stringsAsFactors = FALSE
  )

  parts <- Filter(function(d) !is.null(d) && nrow(d) > 0,
                  list(unsupported, missing_edges))
  unsupported_all <- if (length(parts)) {
    do.call(rbind, lapply(parts, function(d) d[c("cohort", "deal_id", "reason")]))
  } else data.frame(cohort = integer(), deal_id = integer(), reason = character())
  unsupported_counts <- if (nrow(unsupported_all)) {
    z <- stats::aggregate(rep.int(1L, nrow(unsupported_all)),
                          unsupported_all[c("cohort", "reason")], sum)
    names(z)[ncol(z)] <- "n_deals"
    z$distance_variant <- distance_col
    z$profile_id <- profile_id
    z[order(z$cohort, z$reason), c("distance_variant", "profile_id", "cohort",
                                   "reason", "n_deals")]
  } else data.frame(distance_variant = character(), profile_id = character(),
                    cohort = integer(), reason = character(), n_deals = integer())
  reuse$distance_variant <- rep(distance_col, nrow(reuse))
  reuse$profile_id <- rep(profile_id, nrow(reuse))
  sel$firm_key <- NULL
  list(profile = profile, metrics = metrics, unsupported = unsupported_counts,
       reuse = reuse[order(reuse$cohort, reuse$control_group),
                     c("distance_variant", "profile_id", "cohort",
                       "control_group", "reuse_count")],
       selection = sel)
}

run_stage1_grid <- function(distance_col, core_vars) {
  results <- lapply(LMV2_P4$stage_1$calipers, evaluate_stage1_profile,
                    distance_col = distance_col, core_vars = core_vars)
  list(
    profiles = do.call(rbind, lapply(results, `[[`, "profile")),
    metrics = do.call(rbind, lapply(results, `[[`, "metrics")),
    unsupported = do.call(rbind, lapply(results, `[[`, "unsupported")),
    reuse = do.call(rbind, lapply(results, `[[`, "reuse")),
    selections = stats::setNames(lapply(results, `[[`, "selection"),
                                 vapply(results, function(r) r$profile$profile_id,
                                        character(1)))
  )
}

stage1_order_keys <- c(deal_retention = 1, max_abs_smd = -1,
                       ess_reuse_adjusted = 1, caliper = 1)

base_grid <- run_stage1_grid("distance_base", LMV2_P4$stage_1$core_balance_variables)
base_choice <- lmv2_p4_tier_select(base_grid$profiles, stage1_order_keys)

promotion_reason <- "not_triggered"
if (base_choice$tier == "none") {
  promotion_reason <- "no_acceptable_base_profile"
} else if (lmv2_p4_trajectory_promotion_triggered(
  base_choice$selected$trajectory_smd_pooled,
  base_choice$selected$max_abs_trajectory_smd_cohort)) {
  promotion_reason <- "trajectory_smd_breach"
}
promoted <- promotion_reason != "not_triggered"

grids <- list(base_grid)
promoted_choice <- NULL
if (promoted) {
  trajectory_grid <- run_stage1_grid(
    "distance_with_trajectory",
    c(LMV2_P4$stage_1$core_balance_variables,
      LMV2_P4$stage_1$diagnostic_balance_variable)
  )
  grids <- c(grids, list(trajectory_grid))
  promoted_choice <- lmv2_p4_tier_select(trajectory_grid$profiles, stage1_order_keys)
}
resolution <- lmv2_p4_stage1_resolve(base_choice, promoted_choice)
if (resolution$mode == "promoted") {
  final_choice <- promoted_choice
  final_grid <- trajectory_grid
} else {
  final_choice <- base_choice
  final_grid <- base_grid
}

write_grid_outputs <- function(grids) {
  profiles <- do.call(rbind, lapply(grids, `[[`, "profiles"))
  profiles_out <- profiles
  profiles_out$caliper <- ifelse(is.infinite(profiles_out$caliper), NA_real_,
                                 profiles_out$caliper)
  lmv2_p4_write_csv(profiles_out, audit_dir, "p4_stage1_profiles.csv")
  lmv2_p4_write_csv(do.call(rbind, lapply(grids, `[[`, "metrics")),
                    audit_dir, "p4_stage1_profile_metrics.csv")
  lmv2_p4_write_csv(do.call(rbind, lapply(grids, `[[`, "unsupported")),
                    audit_dir, "p4_stage1_unsupported.csv")
  lmv2_p4_write_csv(do.call(rbind, lapply(grids, `[[`, "reuse")),
                    audit_dir, "p4_stage1_reuse.csv")
}
write_grid_outputs(grids)

if (resolution$mode == "failed") {
  failure <- resolution$choice$best_dominated
  failure$caliper <- ifelse(is.infinite(failure$caliper), NA_real_, failure$caliper)
  failure$p4_version <- LMV2_P4_VERSION
  failure$p4_config_hash <- LMV2_P4_CONFIG_HASH
  failure$failure <- "no_acceptable_promoted_profile_and_base_not_preferred"
  failure$base_tier <- base_choice$tier
  failure$trajectory_promoted <- promoted
  failure$promotion_reason <- promotion_reason
  lmv2_p4_write_csv(failure, audit_dir, "p4_stage1_design_failure.csv")
  stop("P4 Stage 1: no acceptable promoted profile and the base profile is ",
       "not preferred-tier; design-failure record written, Stage 1 not frozen")
}

selected <- final_choice$selected
frozen <- final_grid$selections[[selected$profile_id]]
frozen <- frozen[c("cohort", "deal_id", "target_group", "control_group", "rank")]
frozen$weight <- rep(pool_weight, nrow(frozen))
frozen$distance_variant <- rep(selected$distance_variant, nrow(frozen))
frozen$profile_id <- rep(selected$profile_id, nrow(frozen))
frozen <- frozen[order(frozen$cohort, frozen$deal_id, frozen$rank), , drop = FALSE]
frozen_checksum <- lmv2_p4_frame_checksum(frozen)
lmv2_p4_write_csv(frozen, audit_dir, "p4_stage1_frozen_firms.csv")

freeze <- data.frame(
  p4_version = LMV2_P4_VERSION,
  p4_config_hash = LMV2_P4_CONFIG_HASH,
  pool_size = pool_n,
  stage1_mode = resolution$mode,
  distance_variant = selected$distance_variant,
  profile_id = selected$profile_id,
  tier = final_choice$tier,
  trajectory_promoted = promoted,
  promotion_reason = promotion_reason,
  deal_retention = selected$deal_retention,
  max_abs_smd = selected$max_abs_smd,
  trajectory_smd_pooled = selected$trajectory_smd_pooled,
  max_abs_trajectory_smd_cohort = selected$max_abs_trajectory_smd_cohort,
  ess_reuse_adjusted = selected$ess_reuse_adjusted,
  n_frozen_deals = length(unique(deal_key(frozen))),
  n_frozen_firm_rows = nrow(frozen),
  frozen_firms_sha256 = frozen_checksum,
  stringsAsFactors = FALSE
)
lmv2_p4_write_csv(freeze, audit_dir, "p4_stage1_freeze.csv")
message("P4 Stage 1 frozen (", resolution$mode, ", pool ", pool_n, "): ",
        selected$profile_id, " / ", selected$distance_variant, " (",
        final_choice$tier, "), ", freeze$n_frozen_deals, " deals")
