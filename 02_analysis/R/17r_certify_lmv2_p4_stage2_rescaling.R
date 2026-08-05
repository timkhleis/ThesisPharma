# ============================================================================
# certify_stage2_candidate_pool_rescaling.R -- targeted fixture (review
# correction #1): proves the certified lmv2_prepare_stage2_edges() recomputes
# its Stage-2 distance scaler from whatever `controls` population is passed
# in (16c_lmv2_matching_utils.R:410-433, `control_scale_units <-
# unique(controls[...])`, folded into `lmv2_safe_sd()` per covariate), so
# caching the OUTPUT distance at one Stage-1 profile and merely subsetting
# rows for a tighter profile is wrong: the SAME raw pair gets a DIFFERENT
# standardized distance depending on which candidate population was used to
# compute the scaler, and this can flip whether the pair clears the Stage-2
# caliper. No database access; exercises only the certified 16c function
# directly (nothing in 15*/16*/17g is edited).

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")

checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1]] <<- data.frame(
    check = name, observed = paste(observed, collapse = ","),
    expected = paste(expected, collapse = ","), pass = isTRUE(pass), stringsAsFactors = FALSE)
}

vars <- LMV2_P3$stage_2$scalar_variables
mk_row <- function(codinv, deal_id = NULL, focal_group = NULL, val) {
  d <- list(cohort = 1L, codinv = codinv, recency_bin = 0)
  if (!is.null(deal_id)) d$deal_id <- deal_id
  if (!is.null(focal_group)) d$focal_group <- focal_group
  for (v in vars) d[[v]] <- if (v == vars[1]) val else 0   # isolate one covariate; rest contribute 0
  as.data.frame(d)
}

treated <- mk_row(codinv = 901, deal_id = 1L, val = 0)
pair_map <- data.frame(cohort = 1L, deal_id = 1L, treated_codinv = 901, control_codinv = 1)
similarity <- data.frame(cohort = 1L, treated_codinv = 901, control_codinv = 1, cosine = 1)  # tech_distance=0
shared_ipc4 <- data.frame(cohort = 1L, treated_codinv = 901, control_codinv = 1, shared_ipc4 = TRUE)

# control_codinv=1 is IDENTICAL in both populations (same raw covariate
# value, same actual pair) -- only the OTHER candidates in the population
# differ, changing the scaler.
controls_tight <- rbind(mk_row(1, focal_group = 101, val = 1), mk_row(2, focal_group = 102, val = 1),
                        mk_row(3, focal_group = 103, val = 1))
controls_wide <- rbind(mk_row(1, focal_group = 101, val = 1), mk_row(4, focal_group = 104, val = 10),
                       mk_row(5, focal_group = 105, val = -8))

edges_tight <- lmv2_prepare_stage2_edges(treated, controls_tight, pair_map, similarity, shared_ipc4,
                                         resolution = "ipc4")$edges
edges_wide <- lmv2_prepare_stage2_edges(treated, controls_wide, pair_map, similarity, shared_ipc4,
                                        resolution = "ipc4")$edges

d_tight <- edges_tight$distance[edges_tight$control_codinv == 1]
d_wide <- edges_wide$distance[edges_wide$control_codinv == 1]

# Hand-computable expected values: gap = 1-0 = 1 in both cases.
# tight population values = c(treated=0, 1,1,1) -> sd = 0.5 -> distance = 1/0.5 = 2.0
# wide population values  = c(treated=0, 1,10,-8) -> sd = sqrt(54.25) -> distance = 1/sd
expected_sd_tight <- stats::sd(c(0, 1, 1, 1))
expected_sd_wide <- stats::sd(c(0, 1, 10, -8))
add_check("RESCALING_same_pair_different_distance_tight_population",
          sprintf("%.6f", d_tight), sprintf("%.6f", 1 / expected_sd_tight),
          isTRUE(all.equal(d_tight, 1 / expected_sd_tight)))
add_check("RESCALING_same_pair_different_distance_wide_population",
          sprintf("%.6f", d_wide), sprintf("%.6f", 1 / expected_sd_wide),
          isTRUE(all.equal(d_wide, 1 / expected_sd_wide)))
add_check("RESCALING_distances_genuinely_differ_for_the_identical_raw_pair",
          sprintf("%.4f vs %.4f", d_tight, d_wide), "different",
          abs(d_tight - d_wide) > 0.5)
add_check("RESCALING_admissibility_flips_at_locked_stage2_caliper_1.5",
          sprintf("tight=%s wide=%s", d_tight <= 1.5, d_wide <= 1.5), "tight=FALSE wide=TRUE",
          isTRUE(!(d_tight <= 1.5)) && isTRUE(d_wide <= 1.5))
add_check("RESCALING_confirms_caching_the_output_distance_would_be_wrong",
          "a cached distance from either population would misclassify the other", "n/a", TRUE)

# ===========================================================================
report <- do.call(rbind, checks)
cat(sprintf("\n=== Stage-2 candidate-pool rescaling certification: %d checks, %d failing ===\n",
            nrow(report), sum(!report$pass)))
print(report[, c("check", "pass")], row.names = FALSE)
utils::write.csv(report, file.path(AUDIT_OUT_DIR, "certify_stage2_candidate_pool_rescaling_results.csv"), row.names = FALSE)
if (any(!report$pass)) {
  cat("\nFAILING CHECKS:\n"); print(report[!report$pass, ], row.names = FALSE)
  stop("Stage-2 candidate-pool rescaling certification FAILED")
}
cat("\nALL STAGE-2 CANDIDATE-POOL RESCALING CHECKS PASS.\n")
