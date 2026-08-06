# ============================================================================
# 17i_run_lmv2_p4_ebal_stage2.R -- P4-EB Stage-2 inventor entropy-balance
# ============================================================================
# Requires explicit --mode=certify|production, exactly like 17h.
# --mode=certify performs no database work. --mode=production requires the
# frozen Stage-1 weights/scalers (17h) and a live --db, verifies the
# --stage2-caliper/--technology-resolution arguments match what Stage 1 was
# actually built with, then runs the thin DB-facing wrapper around
# lmv2_ebal_stage2_pipeline() (17g) TWICE -- once per treated_weighting
# scheme -- followed by lmv2_ebal_terminal_gate() for each. Written and
# reviewed as part of E1's code-only deliverable; NOT executed against real
# data in E1.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))

mode <- lmv2_ebal_mode()
audit_dir <- lmv2_ebal_read_arg("audit-dir")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

if (mode == "certify") {
  message("17i --mode=certify: argument handling only, no database work performed")
  quit(status = 0L, save = "no")
}

for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

db_path <- lmv2_ebal_read_arg("db")
p3_manifest_path <- lmv2_ebal_read_arg("p3-manifest")
parse_caliper <- function(name) {
  raw <- lmv2_ebal_read_arg(name)
  if (identical(raw, "Inf")) return(Inf)
  val <- suppressWarnings(as.numeric(raw))
  if (!is.finite(val)) stop("--", name, " must be numeric or 'Inf', got: ", raw)
  val
}
stage2_caliper <- parse_caliper("stage2-caliper")
technology_resolution <- lmv2_ebal_read_arg("technology-resolution")
if (!file.exists(db_path)) stop("Database not found: ", db_path)
observed_p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
if (!identical(observed_p3_hash, LMV2_P4_EBAL_P3_MANIFEST_SHA256)) {
  stop("P3 interface manifest drifted: expected ", LMV2_P4_EBAL_P3_MANIFEST_SHA256,
       ", observed ", observed_p3_hash)
}

# Stage 1 must remain frozen while Stage 2 runs (locked production
# invariant, LMV2_LOCK$production$stage_1_must_remain_frozen_during_stage_2).
weights_path <- file.path(audit_dir, "p4_ebal_stage1_weights.csv")
scalers_path <- file.path(audit_dir, "p4_ebal_stage1_scalers.csv")
admissible_firm_edges_path <- file.path(audit_dir, "p4_ebal_stage1_admissible_firm_edges.csv")
freeze_path <- file.path(audit_dir, "p4_ebal_stage1_freeze.csv")
if (!all(file.exists(c(weights_path, scalers_path, admissible_firm_edges_path, freeze_path)))) {
  stop("Stage-1 freeze missing in ", audit_dir, "; run 17h first")
}
stage1_weights <- utils::read.csv(weights_path, stringsAsFactors = FALSE)
stage1_scalers <- utils::read.csv(scalers_path, stringsAsFactors = FALSE)
admissible_firm_edges <- utils::read.csv(admissible_firm_edges_path, stringsAsFactors = FALSE)
freeze <- utils::read.csv(freeze_path, stringsAsFactors = FALSE)
if (!identical(freeze$p4_ebal_config_hash, LMV2_P4_EBAL_CONFIG_HASH)) {
  stop("Stage-1 freeze was produced under a different P4-EB configuration")
}
if (!identical(lmv2_ebal_frame_checksum(stage1_weights), freeze$frozen_weights_sha256)) {
  stop("Frozen Stage-1 firm weights drifted from their recorded checksum")
}
if (!identical(lmv2_ebal_frame_checksum(stage1_scalers), freeze$frozen_scalers_sha256)) {
  stop("Frozen Stage-1 scalers drifted from their recorded checksum")
}
if (!identical(lmv2_ebal_frame_checksum(admissible_firm_edges),
               freeze$frozen_admissible_firm_edges_sha256)) {
  stop("Frozen Stage-1 admissible firm edges drifted from their recorded checksum")
}
if (!isTRUE(freeze$all_cohorts_pass)) {
  stop("Stage 1 did not pass in all cohorts; Stage 2 cannot proceed")
}
if (!isTRUE(freeze$stage1_ess_concentration_pass)) {
  stop("Stage 1 ESS/concentration gate did not reach the acceptable tier (tier=",
       freeze$stage1_ess_concentration_tier, "); Stage 2 cannot proceed")
}
# Stage 2 must run under the EXACT caliper and technology resolution Stage 1
# was built with -- these determined which firms/inventors were eligible
# and therefore which firms received Stage-1 weight in the first place.
freeze_match <- lmv2_ebal_verify_stage2_matches_freeze(freeze, stage2_caliper, technology_resolution)
if (!freeze_match$ok) {
  stop("Stage-2 configuration does not match the Stage-1 freeze: ",
       if (!freeze_match$caliper_ok) sprintf("--stage2-caliper=%s vs freeze=%s; ",
                                             stage2_caliper, freeze$stage2_caliper) else "",
       if (!freeze_match$resolution_ok) sprintf("--technology-resolution=%s vs freeze=%s",
                                                technology_resolution, freeze$technology_resolution) else "")
}

con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=4")

cohort_sql <- paste(LMV2_P4_EBAL$pilot_cohorts, collapse = ",")
s2_vars <- LMV2_P3$stage_2$scalar_variables

# --- Eligible treated population (funnel step 1: covariate completeness) ---
raw_treated <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, codinv AS treated_codinv, recency_bin, %s
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort IN (%s)
  ORDER BY cohort, deal_id, codinv", paste(s2_vars, collapse = ", "), cohort_sql))
funnel_state <- data.frame(cohort = raw_treated$cohort, deal_id = raw_treated$deal_id,
                           treated_codinv = raw_treated$treated_codinv,
                           terminal_reason = NA_character_, stringsAsFactors = FALSE)
treated_complete <- stats::complete.cases(raw_treated[c(s2_vars, "recency_bin")])
funnel_state$terminal_reason[!treated_complete] <- "treated_covariate_missing"
treated_spine <- raw_treated[treated_complete, , drop = FALSE]

# --- Donor pool at frozen Stage-1 positive-weight firms only ----------------
frozen_firms <- sort(unique(stage1_weights$control_group))
# lmv2_p3_inventor_general_units has no focal_group_tenure/focal_group_exclusivity
# columns for control rows (those are treated-only, computed relative to the
# TREATED unit's own focal group); the control-side equivalents are computed
# on demand below via lmv2_build_control_focal_covariates() and merged in.
donor_sql_vars <- setdiff(s2_vars, c("focal_group_tenure", "focal_group_exclusivity"))
donors_raw <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT cohort, codinv, focal_group, recency_bin, %s
  FROM lmv2_p3_inventor_general_units
  WHERE role = 'control' AND cohort IN (%s) AND focal_group IN (%s)
  ORDER BY codinv, focal_group",
  paste(donor_sql_vars, collapse = ", "), cohort_sql, paste(frozen_firms, collapse = ",")))
stopifnot(!anyDuplicated(donors_raw[c("cohort", "codinv")]))
focal <- lmv2_build_control_focal_covariates(con, donors_raw[c("cohort", "codinv", "focal_group")])
donors_raw <- merge(donors_raw, focal, by = c("cohort", "codinv", "focal_group"), sort = FALSE)
donor_complete <- stats::complete.cases(donors_raw[c(s2_vars, "recency_bin")])
donors_excluded <- donors_raw[!donor_complete, , drop = FALSE]
if (nrow(donors_excluded)) donors_excluded$reason <- "missing_covariate"
donors <- donors_raw[donor_complete, , drop = FALSE]

pair_key_cols <- c("cohort", "deal_id", "treated_codinv", "control_codinv")
donor_cols <- donors
names(donor_cols)[names(donor_cols) == "codinv"] <- "control_codinv"
names(donor_cols)[names(donor_cols) == "focal_group"] <- "control_group"
# Restricted to firms holding positive Stage-1 weight IN THAT SPECIFIC
# COHORT (cohort, control_group) -- never control_group alone, since the
# same firm id can recur across pseudo-event cohorts weighted in one and
# not another. This must happen before technology/recency filtering and
# distance construction, so an extra (cohort, firm) combination can never
# influence within-cohort scaling or calipers in the first place.
admissible_firm_edges_frozen <- lmv2_ebal_restrict_to_frozen_firms(admissible_firm_edges, stage1_weights)
# The one shared join (17g_lmv2_p4_ebal_utils.R): a control inventor is a
# candidate for a treated inventor only through a firm admissible for THAT
# inventor's own deal -- never any positive-weight firm in the cohort.
# Crossing every treated inventor against every positive-weight firm (as
# an earlier version of this file did) would let a firm admitted only for
# one deal silently supply controls to a different deal, bypassing the
# Stage-1 admissibility check entirely.
pairs <- lmv2_ebal_build_stage2_candidate_pairs(
  admissible_firm_edges_frozen, donor_cols, treated_spine[c("cohort", "deal_id", "treated_codinv")])

bins_t <- treated_spine[c("cohort", "deal_id", "treated_codinv", "recency_bin")]
names(bins_t)[4] <- "recency_bin_treated"
bins_c <- donor_cols[c("cohort", "control_codinv", "recency_bin")]
names(bins_c)[3] <- "recency_bin_control"
pairs <- merge(merge(pairs, bins_t, by = c("cohort", "deal_id", "treated_codinv")),
               bins_c, by = c("cohort", "control_codinv"))
pairs <- pairs[!is.na(pairs$recency_bin_treated) & !is.na(pairs$recency_bin_control) &
                abs(pairs$recency_bin_treated - pairs$recency_bin_control) <=
                  LMV2_P3$stage_2$maximum_recency_bin_gap, , drop = FALSE]

cache <- lmv2_stage2_technology_cache(con, pairs[pair_key_cols])
shared_true <- cache$shared_ipc4[cache$shared_ipc4$shared_ipc4, , drop = FALSE]
pairs <- merge(pairs, shared_true[c("cohort", "treated_codinv", "control_codinv")],
               by = c("cohort", "treated_codinv", "control_codinv"))
sim_sel <- cache$similarity[cache$similarity$resolution == technology_resolution, ,
                            drop = FALSE]
sim_sel <- sim_sel[c("cohort", "treated_codinv", "control_codinv", "cosine")]
pairs <- merge(pairs, sim_sel[!is.na(sim_sel$cosine), pair_key_cols[-2]],
               by = c("cohort", "treated_codinv", "control_codinv"))
# pair_key_cols[-2] drops deal_id: lmv2_prepare_stage2_edges() merges its
# shared_ipc4 argument by (cohort, treated_codinv, control_codinv) only, so
# a deal_id column here would collide with the edges' own deal_id on that
# merge and get silently suffixed to deal_id.x/deal_id.y instead of merged,
# breaking every deal_id reference downstream in that function.
shared_flags <- unique(pairs[pair_key_cols[-2]])
shared_flags$shared_ipc4 <- rep(TRUE, nrow(shared_flags))

treated_for_prep <- treated_spine
names(treated_for_prep)[names(treated_for_prep) == "treated_codinv"] <- "codinv"
prep <- lmv2_prepare_stage2_edges(
  treated = treated_for_prep, controls = donors, pair_map = pairs[pair_key_cols],
  similarity = sim_sel, shared_ipc4 = shared_flags, resolution = technology_resolution
)
stage2_candidate_edges <- prep$edges

# --- Firm-level covariates, deal-size (big_deal) category ---------------------
control_firm_covars <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, id_group AS control_group, log_patent_stock_5y, log_inventor_count_5y,
         patent_trajectory
  FROM lmv2_p3_firm_units WHERE role = 'control' AND cohort IN (%s)
  ORDER BY cohort, id_group", cohort_sql))
treated_firm_covars <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, log_patent_stock_5y, log_inventor_count_5y, patent_trajectory
  FROM lmv2_p3_firm_units WHERE role = 'treated' AND cohort IN (%s)
  ORDER BY cohort, deal_id", cohort_sql))
deal_category <- DBI::dbGetQuery(con, sprintf("
  SELECT DISTINCT cohort, deal_id, big_deal AS category
  FROM lmv2_treated_primary WHERE cohort IN (%s)
  ORDER BY cohort, deal_id", cohort_sql))

stage1_result <- list(weights = stage1_weights, scalers = stage1_scalers)

run_scheme <- function(scheme) {
  lmv2_ebal_stage2_pipeline(
    stage1_result = stage1_result, stage2_candidate_edges = stage2_candidate_edges,
    stage2_caliper = stage2_caliper, treated_spine = treated_spine,
    treated_inv_covars = treated_spine, treated_firm_covars = treated_firm_covars,
    control_inv_covars = donor_cols, control_firm_covars = control_firm_covars,
    deal_category = deal_category, treated_weighting = scheme,
    cohorts = LMV2_P4_EBAL$pilot_cohorts
  )
}

primary <- run_scheme("primary")
equal_deal <- run_scheme("equal_deal")

# --- Exclusion log: one terminal reason for every treated inventor ----------
# `supported`/`excluded_treated` are scheme-invariant (common support
# depends only on admissible_edges and positive Stage-1 firms, never on
# treated_weighting), so either scheme's result documents the funnel.
key3 <- function(d) paste(d$cohort, d$deal_id, d$treated_codinv, sep = "\r")
funnel_state <- lmv2_ebal_funnel_step(funnel_state, key3(primary$supported_treated),
                                      "no_admissible_control_inventor")
funnel_state$terminal_reason[is.na(funnel_state$terminal_reason)] <- "matched"
stopifnot(!anyNA(funnel_state$terminal_reason))
lmv2_ebal_write_csv(funnel_state, audit_dir, "p4_ebal_exclusion_log.csv")
lmv2_ebal_write_csv(donors_excluded, audit_dir, "p4_ebal_stage2_donor_exclusions.csv")

# --- Per-scheme outputs -------------------------------------------------------
write_scheme_outputs <- function(r) {
  diagnostics <- do.call(rbind, lapply(r$per_cohort, function(x) {
    data.frame(scheme = r$scheme, cohort = x$cohort, status = x$status,
              tier = if (is.null(x$tier)) NA_character_ else x$tier,
              maxdiff = if (is.null(x$maxdiff)) NA_real_ else x$maxdiff,
              ess = if (is.null(x$ess)) NA_real_ else x$ess,
              max_share = if (is.null(x$concentration)) NA_real_ else x$concentration$max_share,
              n_treated = x$n_treated, n_control = x$n_control, stringsAsFactors = FALSE)
  }))
  list(diagnostics = diagnostics,
      weights = cbind(scheme = r$scheme, r$weights),
      treated_weights = cbind(scheme = r$scheme, r$treated_weights),
      retention_overall = cbind(scheme = r$scheme, r$retention$overall),
      retention_by_cohort = cbind(scheme = r$scheme, r$retention$by_cohort),
      retention_by_category = if (is.null(r$retention$by_category)) NULL else
        cbind(scheme = r$scheme, r$retention$by_category),
      retention_gate = data.frame(scheme = r$scheme, tier = r$retention_gate$tier,
                                  pass = r$retention_gate$pass, label = r$retention_gate$label,
                                  cohort_floor_ok = r$retention_gate$cohort_floor_ok,
                                  category_preserved = r$retention_gate$category_preserved,
                                  stringsAsFactors = FALSE),
      firm_reaggregation = cbind(scheme = r$scheme, r$firm_gate$detail),
      prior_movement = cbind(scheme = r$scheme, r$prior_movement))
}
out_primary <- write_scheme_outputs(primary)
out_equal_deal <- write_scheme_outputs(equal_deal)

lmv2_ebal_write_csv(rbind(out_primary$diagnostics, out_equal_deal$diagnostics),
                    audit_dir, "p4_ebal_stage2_diagnostics.csv")
lmv2_ebal_write_csv(rbind(out_primary$weights, out_equal_deal$weights),
                    audit_dir, "p4_ebal_stage2_weights.csv")
# Treated weights, keyed by (scheme, cohort, deal_id, treated_codinv) --
# without this, the equal-deal scheme's non-uniform treated weights are
# computed inside the solve and then discarded, leaving no way for
# downstream estimation to recover them.
combined_treated_weights <- rbind(out_primary$treated_weights, out_equal_deal$treated_weights)
lmv2_ebal_write_csv(combined_treated_weights, audit_dir, "p4_ebal_stage2_treated_weights.csv")
lmv2_ebal_write_csv(rbind(out_primary$retention_overall, out_equal_deal$retention_overall),
                    audit_dir, "p4_ebal_retention_overall.csv")
lmv2_ebal_write_csv(rbind(out_primary$retention_by_cohort, out_equal_deal$retention_by_cohort),
                    audit_dir, "p4_ebal_retention_by_cohort.csv")
lmv2_ebal_write_csv(rbind(out_primary$retention_by_category, out_equal_deal$retention_by_category),
                    audit_dir, "p4_ebal_retention_by_category.csv")
lmv2_ebal_write_csv(rbind(out_primary$retention_gate, out_equal_deal$retention_gate),
                    audit_dir, "p4_ebal_retention_gate.csv")
lmv2_ebal_write_csv(rbind(out_primary$firm_reaggregation, out_equal_deal$firm_reaggregation),
                    audit_dir, "p4_ebal_stage2_firm_reaggregation.csv")
lmv2_ebal_write_csv(rbind(out_primary$prior_movement, out_equal_deal$prior_movement),
                    audit_dir, "p4_ebal_stage1_prior_movement.csv")

# --- Terminal design gate: every condition, both schemes --------------------
gate_primary <- lmv2_ebal_terminal_gate(primary, LMV2_P4_EBAL$pilot_cohorts)
gate_equal_deal <- lmv2_ebal_terminal_gate(equal_deal, LMV2_P4_EBAL$pilot_cohorts)
gate_summary <- rbind(
  data.frame(scheme = "primary", pass = gate_primary$pass,
            reasons = paste(gate_primary$reasons, collapse = ";")),
  data.frame(scheme = "equal_deal", pass = gate_equal_deal$pass,
            reasons = paste(gate_equal_deal$reasons, collapse = ";"))
)
lmv2_ebal_write_csv(gate_summary, audit_dir, "p4_ebal_terminal_gate.csv")

design <- data.frame(
  p4_ebal_version = LMV2_P4_EBAL_VERSION, p4_ebal_config_hash = LMV2_P4_EBAL_CONFIG_HASH,
  stage2_caliper = ifelse(is.infinite(stage2_caliper), NA_real_, stage2_caliper),
  technology_resolution = technology_resolution,
  primary_terminal_gate_pass = gate_primary$pass,
  equal_deal_terminal_gate_pass = gate_equal_deal$pass,
  control_weights_sha256 = lmv2_ebal_frame_checksum(rbind(out_primary$weights, out_equal_deal$weights)),
  treated_weights_sha256 = lmv2_ebal_frame_checksum(combined_treated_weights),
  stringsAsFactors = FALSE
)
lmv2_ebal_write_csv(design, audit_dir, "p4_ebal_design.csv")

if (!gate_primary$pass || !gate_equal_deal$pass) {
  stop("P4-EB: terminal design gate failed -- primary: [",
       paste(gate_primary$reasons, collapse = ", "), "]; equal_deal: [",
       paste(gate_equal_deal$reasons, collapse = ", "),
       "]; design not frozen, do not estimate treatment effects")
}
message("P4-EB Stage 2 complete: primary and equal-deal terminal gates both passed")
