# ============================================================================
# 17h_run_lmv2_p4_ebal_stage1.R -- P4-EB Stage-1 firm entropy-balance runner
# ============================================================================
# Requires explicit --mode=certify|production. --mode=certify performs no
# database work at all. --mode=production requires a live --db and runs the
# thin DB-facing wrapper around lmv2_ebal_stage1_pipeline() (17g): build the
# Stage-1 firm admissible edges (deal-level, cohort/deal_id/control_group --
# never collapsed before the Stage-2 candidate pairs are built from them),
# build Stage-2 candidate edges restricted to firms admissible for the
# SPECIFIC deal a treated inventor belongs to, then hand both to the pipeline
# for the zero-lost-mass pre-filter and the per-cohort entropy solve. Written
# and reviewed as part of E1's code-only deliverable; NOT executed against
# real data in E1.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))

mode <- lmv2_ebal_mode()
audit_dir <- lmv2_ebal_read_arg("audit-dir")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

if (mode == "certify") {
  message("17h --mode=certify: argument handling only, no database work performed")
  quit(status = 0L, save = "no")
}

for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

db_path <- lmv2_ebal_read_arg("db")
p3_manifest_path <- lmv2_ebal_read_arg("p3-manifest")
# Deferred E2 choices (see the amendment): every caller must supply these
# explicitly; there is no default anywhere in this package.
parse_caliper <- function(name) {
  raw <- lmv2_ebal_read_arg(name)
  if (identical(raw, "Inf")) return(Inf)
  val <- suppressWarnings(as.numeric(raw))
  if (!is.finite(val)) stop("--", name, " must be numeric or 'Inf', got: ", raw)
  val
}
stage1_caliper <- parse_caliper("stage1-caliper")
stage2_caliper <- parse_caliper("stage2-caliper")
technology_resolution <- lmv2_ebal_read_arg("technology-resolution")
if (!file.exists(db_path)) stop("Database not found: ", db_path)
observed_p3_hash <- lmv2_p3_file_hash(p3_manifest_path)
if (!identical(observed_p3_hash, LMV2_P4_EBAL_P3_MANIFEST_SHA256)) {
  stop("P3 interface manifest drifted: expected ", LMV2_P4_EBAL_P3_MANIFEST_SHA256,
       ", observed ", observed_p3_hash)
}

con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=4")

cohort_sql <- paste(LMV2_P4_EBAL$pilot_cohorts, collapse = ",")
s2_vars <- LMV2_P3$stage_2$scalar_variables

# --- Stage-1 firm edges (single chosen distance variant), never collapsed --
firm_edges <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, control_group, distance_base AS distance
  FROM lmv2_p3_stage1_edges
  WHERE resolution = 'ipc4' AND cohort IN (%s)
  ORDER BY cohort, deal_id, control_group", cohort_sql))
admissible_firm_edges <- lmv2_ebal_stage1_admissible_edges(firm_edges, stage1_caliper)

# --- Stage-2 candidate edges for ALL firm-caliper-admissible firms, built
# from the DEAL-LEVEL admissible edges so a control inventor is only a
# candidate for a treated inventor whose deal actually admits that
# inventor's firm (not merely any candidate firm in the cohort).
treated_inv <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, codinv, recency_bin, %s
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort IN (%s)
  ORDER BY cohort, deal_id, codinv", paste(s2_vars, collapse = ", "), cohort_sql))

candidate_firms <- sort(unique(admissible_firm_edges$control_group))
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
  paste(donor_sql_vars, collapse = ", "), cohort_sql, paste(candidate_firms, collapse = ",")))
# Donor uniqueness is required at the (cohort, codinv) grain, not codinv
# alone: the same inventor may legitimately appear at different pseudo-event
# dates (different cohorts) with different covariate snapshots.
stopifnot(!anyDuplicated(donors_raw[c("cohort", "codinv")]))
focal <- lmv2_build_control_focal_covariates(con, donors_raw[c("cohort", "codinv", "focal_group")])
donors_raw <- merge(donors_raw, focal, by = c("cohort", "codinv", "focal_group"), sort = FALSE)
donor_complete <- stats::complete.cases(donors_raw[c(s2_vars, "recency_bin")])
donors_excluded <- donors_raw[!donor_complete, , drop = FALSE]
if (nrow(donors_excluded)) donors_excluded$reason <- "missing_covariate"
donors <- donors_raw[donor_complete, , drop = FALSE]

donor_cols <- donors
names(donor_cols)[names(donor_cols) == "codinv"] <- "control_codinv"
names(donor_cols)[names(donor_cols) == "focal_group"] <- "control_group"
treated_key <- treated_inv[c("cohort", "deal_id", "codinv")]
names(treated_key)[names(treated_key) == "codinv"] <- "treated_codinv"
# The one shared join (17g_lmv2_p4_ebal_utils.R): a control inventor is a
# candidate for a treated inventor only through a firm admissible for THAT
# inventor's own deal -- never any admissible firm in the cohort.
pairs <- lmv2_ebal_build_stage2_candidate_pairs(admissible_firm_edges, donor_cols, treated_key)

# Funnel: recency-bin gap, then shared IPC4, then selected-resolution cosine
# present -- identical rules to the certified P3/17c pattern, applied here
# to the deal-restricted candidate pairs.
bins_t <- treated_inv[c("cohort", "deal_id", "codinv", "recency_bin")]
names(bins_t) <- c("cohort", "deal_id", "treated_codinv", "recency_bin_treated")
bins_c <- donor_cols[c("cohort", "control_codinv", "recency_bin")]
names(bins_c)[3] <- "recency_bin_control"
pairs <- merge(merge(pairs, bins_t, by = c("cohort", "deal_id", "treated_codinv")),
               bins_c, by = c("cohort", "control_codinv"))
pairs <- pairs[!is.na(pairs$recency_bin_treated) & !is.na(pairs$recency_bin_control) &
                abs(pairs$recency_bin_treated - pairs$recency_bin_control) <=
                  LMV2_P3$stage_2$maximum_recency_bin_gap, , drop = FALSE]

pair_key_cols <- c("cohort", "deal_id", "treated_codinv", "control_codinv")
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
prep <- lmv2_prepare_stage2_edges(
  treated = treated_inv, controls = donors, pair_map = pairs[pair_key_cols],
  similarity = sim_sel, shared_ipc4 = shared_flags, resolution = technology_resolution
)
stage2_candidate_edges <- prep$edges

# --- Firm covariates and the Stage-1 pipeline --------------------------------
treated_firm_covars <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, deal_id, log_patent_stock_5y, log_inventor_count_5y, patent_trajectory
  FROM lmv2_p3_firm_units WHERE role = 'treated' AND cohort IN (%s)
  ORDER BY cohort, deal_id", cohort_sql))
control_firm_covars <- DBI::dbGetQuery(con, sprintf("
  SELECT cohort, id_group AS control_group, log_patent_stock_5y, log_inventor_count_5y,
         patent_trajectory
  FROM lmv2_p3_firm_units WHERE role = 'control' AND cohort IN (%s)
  ORDER BY cohort, id_group", cohort_sql))

result <- lmv2_ebal_stage1_pipeline(
  firm_edges = firm_edges, stage2_candidate_edges = stage2_candidate_edges,
  stage1_caliper = stage1_caliper, stage2_caliper = stage2_caliper,
  treated_firm_covars = treated_firm_covars, control_firm_covars = control_firm_covars,
  cohorts = LMV2_P4_EBAL$pilot_cohorts
)

lmv2_ebal_write_csv(donors_excluded, audit_dir, "p4_ebal_stage1_donor_exclusions.csv")
lmv2_ebal_write_csv(result$excluded_firms, audit_dir, "p4_ebal_stage1_excluded_firms.csv")
lmv2_ebal_write_csv(result$weights, audit_dir, "p4_ebal_stage1_weights.csv")
# Persisted so Stage 2 can rebuild deal-specific candidate pairs (through
# lmv2_ebal_build_stage2_candidate_pairs(), restricted to positive-weight
# firms) instead of re-deriving admissibility from scratch or, worse,
# silently widening it to "any positive-weight firm in the cohort."
lmv2_ebal_write_csv(result$admissible_firm_edges, audit_dir, "p4_ebal_stage1_admissible_firm_edges.csv")
# The ACTUAL Stage-1 entropy-balancing standardization scalers, persisted
# for downstream reuse by the firm-reaggregation gate -- never the broader
# P3 distance-caliper scaler, which is computed over a different population.
lmv2_ebal_write_csv(result$scalers, audit_dir, "p4_ebal_stage1_scalers.csv")

diagnostics <- do.call(rbind, lapply(result$per_cohort, function(r) {
  data.frame(cohort = r$cohort, status = r$status, tier = if (is.null(r$tier)) NA_character_ else r$tier,
            maxdiff = if (is.null(r$maxdiff)) NA_real_ else r$maxdiff,
            ess = if (is.null(r$ess)) NA_real_ else r$ess,
            max_share = if (is.null(r$concentration)) NA_real_ else r$concentration$max_share,
            top5_share = if (is.null(r$concentration)) NA_real_ else r$concentration$top5_share,
            n_treated = r$n_treated, n_control = r$n_control, stringsAsFactors = FALSE)
}))
lmv2_ebal_write_csv(diagnostics, audit_dir, "p4_ebal_stage1_diagnostics.csv")
# ESS/concentration is a bulk, across-cohort gate (unlike per-cohort balance
# status above) -- activated by the pre-E2 amendment. Its detail is written
# for audit regardless of outcome; its pass/fail is folded into the freeze
# so 17i can refuse to start Stage 2 on top of a failed Stage-1 gate, the
# same way it already refuses to start on all_cohorts_pass == FALSE.
lmv2_ebal_write_csv(result$ess_concentration_gate$detail, audit_dir,
                    "p4_ebal_stage1_ess_concentration.csv")

freeze <- data.frame(
  p4_ebal_version = LMV2_P4_EBAL_VERSION, p4_ebal_config_hash = LMV2_P4_EBAL_CONFIG_HASH,
  stage1_caliper = ifelse(is.infinite(stage1_caliper), NA_real_, stage1_caliper),
  stage2_caliper = ifelse(is.infinite(stage2_caliper), NA_real_, stage2_caliper),
  technology_resolution = technology_resolution,
  all_cohorts_pass = result$all_cohorts_pass,
  stage1_ess_concentration_pass = isTRUE(result$ess_concentration_gate$pass),
  stage1_ess_concentration_tier = result$ess_concentration_gate$tier,
  frozen_weights_sha256 = lmv2_ebal_frame_checksum(result$weights),
  frozen_scalers_sha256 = lmv2_ebal_frame_checksum(result$scalers),
  frozen_admissible_firm_edges_sha256 = lmv2_ebal_frame_checksum(result$admissible_firm_edges),
  stringsAsFactors = FALSE
)
lmv2_ebal_write_csv(freeze, audit_dir, "p4_ebal_stage1_freeze.csv")
message("P4-EB Stage 1 complete: ", sum(diagnostics$status == "pass"), "/", nrow(diagnostics),
        " cohorts passed (stage2-caliper=", freeze$stage2_caliper,
        ", technology-resolution=", technology_resolution,
        ", ess-concentration-tier=", freeze$stage1_ess_concentration_tier, ")")
