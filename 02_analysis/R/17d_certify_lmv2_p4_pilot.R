# ============================================================================
# 17d_certify_lmv2_p4_pilot.R -- synthetic P4 acceptance checks (database-free)
# ============================================================================
# Every check runs on in-memory fixtures against the pure helpers in 17a and
# the reused 16c engine.  No database connection is opened, so this
# certification runs in the code-only delivery as well as inside 17e.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17a_lmv2_p4_pilot_config.R"))

audit_dir <- lmv2_p4_read_arg("audit-dir", required = FALSE)
if (is.na(audit_dir)) audit_dir <- LMV2_P4_PATHS$audit
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

checks <- list()
add_check <- function(check, observed, expected, pass) {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = check, observed = as.character(observed),
    expected = as.character(expected), pass = isTRUE(pass),
    stringsAsFactors = FALSE
  )
}

# --- Exact resolution-name mapping ------------------------------------------
parsed <- vapply(LMV2_P3$technology$resolutions,
                 function(r) lmv2_ipc_feature("A61K031/00", r), character(1))
add_check("ipc_parser_fixture", paste(parsed, collapse = ","),
          "A61K,A61K31,A61K31/00",
          identical(unname(parsed), c("A61K", "A61K31", "A61K31/00")))
add_check("seven_character_maps_to_main_group",
          LMV2_P4$resolution_rule$primary_candidate, "ipc_main_group",
          identical(LMV2_P4$resolution_rule$primary_candidate, "ipc_main_group"))
add_check("full_subgroup_is_diagnostic_only",
          LMV2_P4$resolution_rule$diagnostic_only, "ipc7",
          identical(LMV2_P4$resolution_rule$diagnostic_only, "ipc7"))

# --- Binary resolution rule -------------------------------------------------
make_diag <- function(cohort, resolution, feasible = 0.95, distinct = 6,
                      zero = 0.20, tied = 0.05) {
  data.frame(cohort = cohort, resolution = resolution,
             median_candidate_count = 40, median_positive_control_count = 30,
             median_zero_cosine_share = zero,
             median_distinct_positive_values = distinct,
             share_nearest_tied = tied,
             share_feasible_three_controls_two_firms = feasible,
             stringsAsFactors = FALSE)
}
all_pass <- do.call(rbind, lapply(LMV2_P4$pilot_cohorts, make_diag,
                                  resolution = "ipc_main_group"))
add_check("main_group_selected_when_all_thresholds_pass",
          lmv2_p4_resolution_choice(all_pass)$resolution, "ipc_main_group",
          identical(lmv2_p4_resolution_choice(all_pass)$resolution, "ipc_main_group"))

fail_variants <- list(
  share_three_positive_controls_two_firms = list(feasible = 0.89),
  median_distinct_positive_values = list(distinct = 4),
  median_zero_cosine_share_below = list(zero = 0.60),
  share_all_nearest_tied_below = list(tied = 0.25)
)
for (nm in names(fail_variants)) {
  broken <- all_pass
  fix <- do.call(make_diag, c(list(cohort = 2002L, resolution = "ipc_main_group"),
                              fail_variants[[nm]]))
  broken[broken$cohort == 2002L, ] <- fix
  add_check(paste0("single_failed_threshold_forces_ipc4_", nm),
            lmv2_p4_resolution_choice(broken)$resolution, "ipc4",
            identical(lmv2_p4_resolution_choice(broken)$resolution, "ipc4"))
}

perfect_ipc7 <- do.call(rbind, lapply(LMV2_P4$pilot_cohorts, make_diag,
                                      resolution = "ipc7", feasible = 1,
                                      distinct = 50, zero = 0, tied = 0))
failing_main <- do.call(rbind, lapply(LMV2_P4$pilot_cohorts, make_diag,
                                      resolution = "ipc_main_group",
                                      feasible = 0.50))
with_perfect_ipc7 <- rbind(perfect_ipc7, failing_main)
r1 <- lmv2_p4_resolution_choice(with_perfect_ipc7)$resolution
r2 <- lmv2_p4_resolution_choice(rbind(perfect_ipc7, all_pass))$resolution
add_check("full_subgroup_never_becomes_primary", paste(r1, r2, sep = ","),
          "ipc4,ipc_main_group",
          identical(r1, "ipc4") && identical(r2, "ipc_main_group"))
missing_cohort <- all_pass[all_pass$cohort != 2009L, , drop = FALSE]
add_check("missing_cohort_diagnostics_force_ipc4",
          lmv2_p4_resolution_choice(missing_cohort)$resolution, "ipc4",
          identical(lmv2_p4_resolution_choice(missing_cohort)$resolution, "ipc4"))

# --- Small-cohort amendment: gate eligibility and Stage-1 gate logic --------
add_check("small_cohort_gate_minimum_is_ten",
          LMV2_P4$stage_1$minimum_treated_deals_for_cohort_smd_gate, 10L,
          identical(LMV2_P4$stage_1$minimum_treated_deals_for_cohort_smd_gate, 10L))
eligible <- lmv2_p4_gate_cohorts(c(`1995` = 4L, `2002` = 9L, `2009` = 10L,
                                   `2010` = 25L))
add_check("gate_eligibility_boundary_at_ten",
          paste(eligible, collapse = ","), "2009,2010",
          identical(eligible, c("2009", "2010")))

gate_cases <- c(
  small_breach_ignored = lmv2_p4_stage1_gate_pass(
    pooled_core = c(0.04, -0.02), cohort_core_eligible = c(0.06, 0.05),
    deal_retention = 0.95)$preferred,
  eligible_breach_blocks_preferred = lmv2_p4_stage1_gate_pass(
    pooled_core = c(0.04, -0.02), cohort_core_eligible = c(0.08, 0.05),
    deal_retention = 0.95)$preferred,
  eligible_breach_still_acceptable = lmv2_p4_stage1_gate_pass(
    pooled_core = c(0.04, -0.02), cohort_core_eligible = c(0.08, 0.05),
    deal_retention = 0.95)$acceptable,
  eligible_gross_breach_blocks_acceptable = lmv2_p4_stage1_gate_pass(
    pooled_core = c(0.04, -0.02), cohort_core_eligible = c(0.12, 0.05),
    deal_retention = 0.95)$acceptable,
  pooled_breach_always_blocks = lmv2_p4_stage1_gate_pass(
    pooled_core = c(0.12, -0.02), cohort_core_eligible = numeric(0),
    deal_retention = 1)$acceptable,
  no_eligible_cohort_is_vacuous = lmv2_p4_stage1_gate_pass(
    pooled_core = c(0.04, -0.02), cohort_core_eligible = numeric(0),
    deal_retention = 0.95)$preferred
)
add_check("stage1_gates_respect_small_cohort_amendment",
          paste(gate_cases, collapse = ","),
          "TRUE,FALSE,TRUE,FALSE,FALSE,TRUE",
          identical(unname(gate_cases),
                    c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE)))

# --- Trajectory-fallback amendment: resolve logic and final gate pins -------
mk_choice <- function(tier) list(tier = tier,
                                 selected = if (tier == "none") NULL else "p",
                                 best_dominated = "d")
resolve_cases <- c(
  no_promotion_is_standard =
    lmv2_p4_stage1_resolve(mk_choice("preferred"))$mode,
  promoted_acceptable_wins =
    lmv2_p4_stage1_resolve(mk_choice("preferred"), mk_choice("acceptable"))$mode,
  fallback_requires_base_preferred =
    lmv2_p4_stage1_resolve(mk_choice("preferred"), mk_choice("none"))$mode,
  acceptable_base_cannot_qualify =
    lmv2_p4_stage1_resolve(mk_choice("acceptable"), mk_choice("none"))$mode,
  no_tier_anywhere_fails =
    lmv2_p4_stage1_resolve(mk_choice("none"), mk_choice("none"))$mode
)
add_check("stage1_resolve_respects_fallback_amendment",
          paste(resolve_cases, collapse = ","),
          "standard,promoted,trajectory_fallback_provisional,failed,failed",
          identical(unname(resolve_cases),
                    c("standard", "promoted", "trajectory_fallback_provisional",
                      "failed", "failed")))
add_check("fallback_final_gate_is_locked_acceptable_bound",
          LMV2_P4$stage_1$trajectory_fallback$final_max_smd,
          LMV2_LOCK$pilot$stage_1_acceptable$max_smd,
          identical(LMV2_P4$stage_1$trajectory_fallback$final_max_smd,
                    LMV2_LOCK$pilot$stage_1_acceptable$max_smd) &&
            identical(LMV2_P4$stage_1$trajectory_fallback$final_gated_variable,
                      "patent_trajectory") &&
            isTRUE(LMV2_P4$stage_1$trajectory_fallback$requires_base_preferred))
add_check("fallback_gate_boundary_inclusive",
          paste(abs(c(0.10, 0.1001)) <=
                  LMV2_P4$stage_1$trajectory_fallback$final_max_smd,
                collapse = ","),
          "TRUE,FALSE",
          identical(abs(c(0.10, 0.1001)) <=
                      LMV2_P4$stage_1$trajectory_fallback$final_max_smd,
                    c(TRUE, FALSE)))

# --- Bounded caliper-bisection amendment ------------------------------------
mk_s2 <- function(caliper, smd, inv_ret, deal_ret = 0.95, min_coh = 0.60,
                  big = TRUE) {
  acc <- LMV2_P4$stage_2$acceptable
  data.frame(
    profile_id = lmv2_p4_caliper_label("cI", caliper), caliper = caliper,
    max_abs_smd = smd, inventor_retention = inv_ret,
    deal_retention = deal_ret, min_cohort_retention = min_coh,
    big_categories_preserved = big,
    acceptable_pass = smd <= acc$max_smd &&
      inv_ret >= acc$inventor_retention_min && deal_ret >= acc$deal_retention &&
      min_coh >= acc$minimum_cohort_retention && big,
    stringsAsFactors = FALSE
  )
}
ftypes <- c(
  acceptable = lmv2_p4_stage2_failure_type(mk_s2(2, 0.05, 0.90)),
  balance_only = lmv2_p4_stage2_failure_type(mk_s2(2, 0.12, 0.90)),
  retention_only = lmv2_p4_stage2_failure_type(mk_s2(1.5, 0.05, 0.75)),
  min_cohort_is_retention = lmv2_p4_stage2_failure_type(
    mk_s2(1, 0.05, 0.90, min_coh = 0.40)),
  big_lost_is_other = lmv2_p4_stage2_failure_type(mk_s2(2, 0.12, 0.90, big = FALSE)),
  joint_failure_is_other = lmv2_p4_stage2_failure_type(mk_s2(1.5, 0.12, 0.75))
)
add_check("stage2_failure_type_classification",
          paste(ftypes, collapse = ","),
          "acceptable,balance_only,retention_only,retention_only,other,other",
          identical(unname(ftypes),
                    c("acceptable", "balance_only", "retention_only",
                      "retention_only", "other", "other")))

run3_like <- rbind(mk_s2(Inf, 0.36, 0.98), mk_s2(2, 0.117, 0.83),
                   mk_s2(1.5, 0.05, 0.75), mk_s2(1, 0.01, 0.63))
bracket <- lmv2_p4_bisection_bracket(run3_like)
add_check("bisection_bracket_finds_loosest_finite_complementary_pair",
          paste(bracket$loose, bracket$tight, sep = ","), "2,1.5",
          identical(bracket, list(loose = 2, tight = 1.5)))
no_pair <- rbind(mk_s2(Inf, 0.36, 0.98), mk_s2(2, 0.30, 0.95),
                 mk_s2(1.5, 0.20, 0.90), mk_s2(1, 0.15, 0.85))
add_check("bisection_requires_complementary_adjacency",
          is.null(lmv2_p4_bisection_bracket(no_pair)), TRUE,
          is.null(lmv2_p4_bisection_bracket(no_pair)))
inf_pair <- rbind(mk_s2(Inf, 0.36, 0.98), mk_s2(2, 0.05, 0.75))
add_check("bisection_requires_finite_loose_bound",
          is.null(lmv2_p4_bisection_bracket(inf_pair)), TRUE,
          is.null(lmv2_p4_bisection_bracket(inf_pair)))

b0 <- list(loose = 2, tight = 1.5)
updates <- c(
  balance_tightens_loose =
    identical(lmv2_p4_bisection_next(b0, 1.75, "balance_only"),
              list(loose = 1.75, tight = 1.5)),
  retention_loosens_tight =
    identical(lmv2_p4_bisection_next(b0, 1.75, "retention_only"),
              list(loose = 2, tight = 1.75)),
  acceptable_refines_toward_looser =
    identical(lmv2_p4_bisection_next(b0, 1.75, "acceptable"),
              list(loose = 2, tight = 1.75)),
  other_stops = is.null(lmv2_p4_bisection_next(b0, 1.75, "other"))
)
add_check("bisection_bracket_updates", paste(updates, collapse = ","),
          "TRUE,TRUE,TRUE,TRUE", all(updates))
add_check("bisection_capped_at_two_midpoints",
          LMV2_P4$stage_2$bisection$max_midpoint_evaluations, 2L,
          identical(LMV2_P4$stage_2$bisection$max_midpoint_evaluations, 2L))
add_check("bisection_midpoint_labels",
          paste(lmv2_p4_caliper_label("cI", c(1.75, 1.625)), collapse = ","),
          "cI_1.75,cI_1.625",
          identical(lmv2_p4_caliper_label("cI", c(1.75, 1.625)),
                    c("cI_1.75", "cI_1.625")))

# --- Ten-firm extension amendment -------------------------------------------
ten <- LMV2_P4$stage_1$ten_firm_extension
add_check("ten_firm_extension_pins",
          paste(ten$n_controls, ten$control_weight,
                ten$stage1_failure_never_activates, sep = ","),
          "10,0.1,TRUE",
          identical(ten$n_controls, 10L) &&
            abs(ten$control_weight - 0.1) < 1e-12 &&
            abs(ten$n_controls * ten$control_weight - 1) < 1e-12 &&
            isTRUE(ten$stage1_failure_never_activates) &&
            isTRUE(ten$permanent_stop_if_it_fails))

s1_ten <- data.frame(
  cohort = 1L, deal_id = 1L, target_group = 9,
  control_group = as.numeric(11:22),
  distance = seq(0.1, 1.2, by = 0.1)
)
ten_sel <- lmv2_select_stage1(s1_ten, Inf, n_controls = ten$n_controls)
add_check("ten_firm_selector_takes_ten_deterministically",
          paste(range(ten_sel$control_group), collapse = "-"), "11-20",
          nrow(ten_sel) == 10L &&
            identical(ten_sel$control_group, as.numeric(11:20)) &&
            abs(sum(rep(ten$control_weight, nrow(ten_sel))) - 1) < 1e-12)
ten_short <- lmv2_select_stage1(s1_ten[1:8, , drop = FALSE], Inf,
                                n_controls = ten$n_controls)
short_uns <- attr(ten_short, "unsupported")
short_uns$reason <- lmv2_p4_relabel_stage1_reason(short_uns$reason,
                                                  ten$n_controls)
add_check("ten_firm_shortfall_is_unsupported_and_relabeled",
          paste(nrow(ten_short), short_uns$reason, sep = ","),
          "0,fewer_than_ten_within_total_distance_caliper",
          nrow(ten_short) == 0L &&
            identical(short_uns$reason,
                      "fewer_than_ten_within_total_distance_caliper"))
add_check("five_firm_reasons_not_relabeled",
          lmv2_p4_relabel_stage1_reason(
            "fewer_than_five_within_total_distance_caliper",
            LMV2_P4$stage_1$n_controls),
          "fewer_than_five_within_total_distance_caliper",
          identical(lmv2_p4_relabel_stage1_reason(
            "fewer_than_five_within_total_distance_caliper",
            LMV2_P4$stage_1$n_controls),
            "fewer_than_five_within_total_distance_caliper"))

# --- Trajectory-promotion trigger -------------------------------------------
trigger <- c(
  at_pooled_boundary = lmv2_p4_trajectory_promotion_triggered(0.05, c(0, 0, 0)),
  above_pooled_boundary = lmv2_p4_trajectory_promotion_triggered(0.0501, c(0, 0, 0)),
  at_cohort_boundary = lmv2_p4_trajectory_promotion_triggered(0, c(0.075, 0, 0)),
  above_cohort_boundary = lmv2_p4_trajectory_promotion_triggered(0, c(0.0751, 0, 0)),
  negative_breach = lmv2_p4_trajectory_promotion_triggered(-0.06, c(0, 0, 0))
)
add_check("trajectory_promotion_trigger_boundaries",
          paste(trigger, collapse = ","), "FALSE,TRUE,FALSE,TRUE,TRUE",
          identical(unname(trigger), c(FALSE, TRUE, FALSE, TRUE, TRUE)))

# --- Cohort-standardized SMD ------------------------------------------------
smd_scalers <- data.frame(cohort = c(1L, 2L, 3L),
                          component_sd = c(1, 2, 1e-12))
smd <- lmv2_p4_smd(gap = c(2, 2, 100), cohort = c(1L, 2L, 3L),
                   weight = c(1, 1, 1), scalers = smd_scalers)
add_check("smd_uses_per_cohort_scalers_before_pooling",
          format(smd$pooled), format(-1), abs(smd$pooled - (-1)) < 1e-12)
add_check("smd_by_cohort_values",
          paste(format(unname(smd$by_cohort)), collapse = ","),
          paste(format(c(-2, -1, 0)), collapse = ","),
          all(abs(unname(smd$by_cohort) - c(-2, -1, 0)) < 1e-12))
add_check("smd_degenerate_cohort_contributes_zero_and_is_flagged",
          paste(smd$degenerate_cohorts, collapse = ","), "3",
          identical(smd$degenerate_cohorts, 3L))

# --- Tier selection and lexicographic tie-breaking --------------------------
mk_profile <- function(id, pref, acc, retention, smd, ess, caliper) {
  data.frame(profile_id = id, preferred_pass = pref, acceptable_pass = acc,
             deal_retention = retention, max_abs_smd = smd,
             ess_reuse_adjusted = ess, caliper = caliper,
             stringsAsFactors = FALSE)
}
keys <- c(deal_retention = 1, max_abs_smd = -1, ess_reuse_adjusted = 1, caliper = 1)
tiers <- rbind(mk_profile("pref", TRUE, TRUE, 0.91, 0.04, 50, 1),
               mk_profile("acc", FALSE, TRUE, 0.99, 0.09, 90, 2))
sel <- lmv2_p4_tier_select(tiers, keys)
add_check("preferred_tier_beats_better_acceptable",
          paste(sel$tier, sel$selected$profile_id, sep = ","), "preferred,pref",
          identical(sel$tier, "preferred") && identical(sel$selected$profile_id, "pref"))

lex <- rbind(
  mk_profile("a", FALSE, TRUE, 0.95, 0.09, 50, 1),
  mk_profile("b", FALSE, TRUE, 0.93, 0.01, 99, 2),   # retention decides first
  mk_profile("c", FALSE, TRUE, 0.95, 0.05, 10, 1),   # then lower max SMD
  mk_profile("d", FALSE, TRUE, 0.95, 0.05, 60, 1),   # then higher ESS
  mk_profile("e", FALSE, TRUE, 0.95, 0.05, 60, 2)    # then loosest caliper
)
sel <- lmv2_p4_tier_select(lex, keys)
add_check("lexicographic_tie_breaking", sel$selected$profile_id, "e",
          identical(sel$selected$profile_id, "e"))
inf_loosest <- rbind(mk_profile("f", FALSE, TRUE, 0.95, 0.05, 60, 2),
                     mk_profile("g", FALSE, TRUE, 0.95, 0.05, 60, Inf))
add_check("infinite_caliper_is_loosest",
          lmv2_p4_tier_select(inf_loosest, keys)$selected$profile_id, "g",
          identical(lmv2_p4_tier_select(inf_loosest, keys)$selected$profile_id, "g"))

none <- rbind(mk_profile("h", FALSE, FALSE, 0.80, 0.20, 50, 2),
              mk_profile("i", FALSE, FALSE, 0.84, 0.15, 50, 1))
sel <- lmv2_p4_tier_select(none, keys)
add_check("no_acceptable_design_returns_none_with_best_dominated",
          paste(sel$tier, is.null(sel$selected), sel$best_dominated$profile_id,
                sep = ","),
          "none,TRUE,i",
          identical(sel$tier, "none") && is.null(sel$selected) &&
            identical(sel$best_dominated$profile_id, "i"))

add_check("stable_caliper_labels",
          paste(lmv2_p4_caliper_label("cI", c(Inf, 2, 1.5, 1)), collapse = ","),
          "cI_inf,cI_2,cI_1.5,cI_1",
          identical(lmv2_p4_caliper_label("cI", c(Inf, 2, 1.5, 1)),
                    c("cI_inf", "cI_2", "cI_1.5", "cI_1")))

# --- Total-caliper boundary -------------------------------------------------
boundary <- lmv2_apply_total_caliper(c(1, 1 + 1e-9, NA), 1)
add_check("total_caliper_boundary_inclusive",
          paste(boundary, collapse = ","), "TRUE,FALSE,FALSE",
          identical(boundary, c(TRUE, FALSE, FALSE)))

# --- Stage-2 selector: three controls from two firms, weights, determinism --
s2 <- data.frame(
  cohort = 1L, deal_id = 1L, treated_codinv = 10,
  control_codinv = c(101, 102, 103, 104),
  control_group = c(1, 1, 1, 2),
  distance = c(0.1, 0.2, 0.3, 0.9)
)
s2m <- lmv2_select_stage2(s2, Inf)
add_check("three_controls_from_two_firms_repair",
          paste(sort(s2m$control_codinv), collapse = ","), "101,102,104",
          identical(sort(s2m$control_codinv), c(101, 102, 104)))
add_check("stage2_weight_sum_is_one", format(sum(s2m$weight)), format(1),
          abs(sum(s2m$weight) - 1) < 1e-12 &&
            all(abs(s2m$weight - LMV2_P4$stage_2$control_weight) < 1e-12))
add_check("stage1_weight_sum_is_one",
          format(LMV2_P4$stage_1$control_weight * LMV2_P4$stage_1$n_controls),
          format(1),
          abs(LMV2_P4$stage_1$control_weight * LMV2_P4$stage_1$n_controls - 1) < 1e-12)

s2_perm <- s2[c(3, 1, 4, 2), , drop = FALSE]
s2m_perm <- lmv2_select_stage2(s2_perm, Inf)
add_check("stage2_selection_is_permutation_invariant",
          paste(s2m_perm$control_codinv, collapse = ","),
          paste(s2m$control_codinv, collapse = ","),
          identical(s2m_perm$control_codinv, s2m$control_codinv) &&
            identical(s2m_perm$rank, s2m$rank))

tie <- data.frame(
  cohort = 1L, deal_id = 1L, treated_codinv = 10,
  control_codinv = c(202, 201, 203, 301),
  control_group = c(1, 1, 1, 2),
  distance = c(0.5, 0.5, 0.5, 0.6)
)
tie_sel <- lmv2_select_stage2(tie, Inf)
add_check("deterministic_id_tie_break",
          paste(tie_sel$control_codinv, collapse = ","), "201,202,301",
          identical(tie_sel$control_codinv, c(201, 202, 301)))

s1 <- data.frame(
  cohort = 1L, deal_id = 1L, target_group = 9,
  control_group = c(11, 12, 13, 14, 15, 16),
  distance = c(0.1, 0.2, 0.3, 0.3, 0.4, 2.5)
)
s1_perm <- s1[c(6, 4, 2, 5, 1, 3), , drop = FALSE]
s1a <- lmv2_select_stage1(s1, 2)
s1b <- lmv2_select_stage1(s1_perm, 2)
add_check("stage1_selection_is_permutation_invariant",
          paste(s1b$control_group, collapse = ","),
          paste(s1a$control_group, collapse = ","),
          identical(s1a$control_group, c(11, 12, 13, 14, 15)) &&
            identical(s1b$control_group, s1a$control_group))

# --- Unsupported-unit accounting --------------------------------------------
mixed <- rbind(
  s2,
  data.frame(cohort = 1L, deal_id = 1L, treated_codinv = 20,
             control_codinv = c(105, 106), control_group = c(1, 2),
             distance = c(0.1, 0.2)),
  data.frame(cohort = 1L, deal_id = 1L, treated_codinv = 30,
             control_codinv = c(107, 108, 109), control_group = c(3, 3, 3),
             distance = c(0.1, 0.2, 0.3))
)
mix_sel <- lmv2_select_stage2(mixed, Inf)
mix_uns <- attr(mix_sel, "unsupported")
matched_units <- length(unique(mix_sel$treated_codinv))
add_check("unsupported_units_reconcile_to_eligible",
          paste(matched_units, nrow(mix_uns), sep = "+"), "1+2",
          matched_units + nrow(mix_uns) == 3 &&
            setequal(mix_uns$reason,
                     c("fewer_than_three_within_total_distance_caliper",
                       "no_second_eligible_control_firm")))

# --- Funnel: mutually exclusive terminal reasons ----------------------------
# Inventor 5 keeps three donors from a single firm through every pre-caliper
# step: it must stay pending (firm diversity is judged only by the selector,
# whose no_second_firm outcome is certified above).
state <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = c(1, 2, 3, 4, 5),
                    terminal_reason = c("deal_lost_at_stage_1", NA, NA, NA, NA),
                    stringsAsFactors = FALSE)
step_pairs <- data.frame(
  cohort = 1L, deal_id = 1L,
  treated_codinv = c(rep(2, 3), rep(3, 2), rep(5, 3)),
  control_codinv = c(11, 12, 13, 11, 12, 14, 15, 16),
  control_group = c(1, 1, 2, 1, 1, 3, 3, 3)
)
state <- lmv2_p4_funnel_step(state, step_pairs, "insufficient_complete_donors")
state <- lmv2_p4_funnel_step(state, step_pairs[step_pairs$control_codinv != 13, ,
                                               drop = FALSE],
                             "no_shared_ipc4_support")
reasons <- state$terminal_reason
expected_reasons <- c("deal_lost_at_stage_1", "no_shared_ipc4_support",
                      "insufficient_complete_donors",
                      "insufficient_complete_donors", NA)
add_check("funnel_reasons_mutually_exclusive_and_reconcile",
          paste(ifelse(is.na(reasons), "pending", reasons), collapse = ","),
          paste(ifelse(is.na(expected_reasons), "pending", expected_reasons),
                collapse = ","),
          identical(reasons, expected_reasons) &&
            sum(!is.na(reasons)) + sum(is.na(reasons)) == 5L)
add_check("single_firm_support_stays_pending_before_caliper",
          ifelse(is.na(reasons[5]), "pending", reasons[5]), "pending",
          is.na(reasons[5]))

# --- Control reuse and ESS ---------------------------------------------------
sets <- data.frame(
  cohort = 1L,
  deal_id = c(rep(1L, 3), rep(2L, 3)),
  treated_codinv = c(rep(10, 3), rep(20, 3)),
  control_codinv = c(201, 202, 203, 201, 204, 205),
  control_group = c(1, 1, 2, 1, 2, 3),
  weight = rep(1 / 3, 6)
)
reuse <- lmv2_control_reuse_counts(sets)
add_check("control_reuse_counts", max(reuse$reuse_count), 2,
          max(reuse$reuse_count) == 2 &&
            reuse$control_codinv[which.max(reuse$reuse_count)] == 201)
raw_ess <- lmv2_p4_ess(sets$weight)
adj_ess <- lmv2_p4_reuse_adjusted_ess(sets$weight,
                                      paste(sets$cohort, sets$control_codinv))
add_check("raw_ess_hand_value", format(raw_ess), format(6),
          abs(raw_ess - 6) < 1e-12)
add_check("reuse_adjusted_ess_hand_value", format(adj_ess), format(4.5),
          abs(adj_ess - 4.5) < 1e-12)

# --- Frame checksum determinism ---------------------------------------------
frame <- data.frame(a = c(1L, 2L), b = c("x", NA))
add_check("frame_checksum_is_stable_and_order_sensitive",
          paste(identical(lmv2_p4_frame_checksum(frame),
                          lmv2_p4_frame_checksum(frame)),
                identical(lmv2_p4_frame_checksum(frame),
                          lmv2_p4_frame_checksum(frame[c(2, 1), ])),
                sep = ","),
          "TRUE,FALSE",
          identical(lmv2_p4_frame_checksum(frame), lmv2_p4_frame_checksum(frame)) &&
            !identical(lmv2_p4_frame_checksum(frame),
                       lmv2_p4_frame_checksum(frame[c(2, 1), ])))

# --- Report ------------------------------------------------------------------
checks_df <- do.call(rbind, checks)
checks_df$p4_version <- LMV2_P4_VERSION
checks_df$p4_config_hash <- LMV2_P4_CONFIG_HASH
checks_df <- checks_df[c("p4_version", "p4_config_hash", "check", "observed",
                         "expected", "pass")]
lmv2_p4_write_csv(checks_df, audit_dir, "p4_acceptance_checks.csv")

status <- data.frame(
  p4_version = LMV2_P4_VERSION, p4_config_hash = LMV2_P4_CONFIG_HASH,
  checks = nrow(checks_df), failures = sum(!checks_df$pass),
  pass = all(checks_df$pass), stringsAsFactors = FALSE
)
lmv2_p4_write_csv(status, audit_dir, "p4_package_status.csv")
print(status)
if (!status$pass) stop("P4 certification failed; inspect p4_acceptance_checks.csv")
