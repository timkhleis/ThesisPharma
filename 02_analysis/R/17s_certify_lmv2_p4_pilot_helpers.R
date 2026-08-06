# ============================================================================
# certify_run_cohort_hybrid_pilot_helpers.R -- database-free fixtures for the
# harness's OWN new pure helper functions (lmv2_left_join_checked,
# attach_firm_covariates, build_stage2_edges_for_profile). Sourcing the
# harness file itself is safe here: the CLI invocation block at its end is
# guarded on --mode= actually being present in commandArgs(), which is empty
# for this fixture script's own invocation.

if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT_OUT_DIR <- file.path(BASE, "output", "audit", "local_match_v2", "P4")
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
message("(harness sourced cleanly -- CLI block correctly did not trigger)")

checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1]] <<- data.frame(
    check = name, observed = paste(observed, collapse = ","),
    expected = paste(expected, collapse = ","), pass = isTRUE(pass), stringsAsFactors = FALSE)
}
expect_error <- function(expr) tryCatch({ force(expr); FALSE }, error = function(e) TRUE)

# ===========================================================================
# Fixture LEFTJOIN -- uniqueness, unchanged-row-count, no-missing-value.
# ===========================================================================
left_ok <- data.frame(cohort = 1L, key = c(1, 2, 3))
right_ok <- data.frame(cohort = 1L, key = c(1, 2, 3), val = c(10, 20, 30))
add_check("LEFTJOIN_ok_on_clean_unique_lookup",
          !expect_error(lmv2_left_join_checked(left_ok, right_ok, by = c("cohort", "key"), context = "test")), TRUE,
          !expect_error(lmv2_left_join_checked(left_ok, right_ok, by = c("cohort", "key"), context = "test")))
right_dup <- rbind(right_ok, data.frame(cohort = 1L, key = 1, val = 999))
add_check("LEFTJOIN_errors_on_duplicate_lookup_key",
          expect_error(lmv2_left_join_checked(left_ok, right_dup, by = c("cohort", "key"), context = "test")), TRUE,
          expect_error(lmv2_left_join_checked(left_ok, right_dup, by = c("cohort", "key"), context = "test")))
# Missing match: right lacks key=3 -- left join keeps the row (NA val), row
# count UNCHANGED (this is what a plain inner merge would instead silently
# DROP) -- the no_missing_cols check is what catches it explicitly.
right_incomplete <- right_ok[right_ok$key != 3, ]
joined_incomplete <- lmv2_left_join_checked(left_ok, right_incomplete, by = c("cohort", "key"), context = "test")
add_check("LEFTJOIN_missing_match_keeps_row_count_not_silently_dropped",
          nrow(joined_incomplete), nrow(left_ok), nrow(joined_incomplete) == nrow(left_ok))
add_check("LEFTJOIN_missing_match_produces_NA_not_silent_drop",
          anyNA(joined_incomplete$val), TRUE, anyNA(joined_incomplete$val))
add_check("LEFTJOIN_no_missing_cols_check_catches_it",
          expect_error(lmv2_left_join_checked(left_ok, right_incomplete, by = c("cohort", "key"),
                                              context = "test", no_missing_cols = "val")), TRUE,
          expect_error(lmv2_left_join_checked(left_ok, right_incomplete, by = c("cohort", "key"),
                                              context = "test", no_missing_cols = "val")))
# Fan-out: right has TWO rows matching one left row on a non-unique-checked
# subset -- would silently duplicate the left row; row-count check catches it
# even when the "duplicate key" check on `by` alone wouldn't (different by).
left_fanout <- data.frame(cohort = 1L, key = c(1, 2))
right_fanout_prone <- data.frame(cohort = 1L, key = c(1, 1, 2), val = c(10, 11, 20))
add_check("LEFTJOIN_errors_on_key_that_is_not_actually_unique_in_lookup",
          expect_error(lmv2_left_join_checked(left_fanout, right_fanout_prone, by = c("cohort", "key"),
                                              context = "test")), TRUE,
          expect_error(lmv2_left_join_checked(left_fanout, right_fanout_prone, by = c("cohort", "key"),
                                              context = "test")))

# ===========================================================================
# Fixture ATTACH -- attach_firm_covariates() left-join behavior.
# ===========================================================================
# fc_ok deliberately matches the REAL call site's actual shape (a column
# literally named "control_group", the result of the SQL's own `id_group AS
# control_group` aliasing) -- NOT a hypothetical "id_group" column. This
# distinction is exactly what the first version of this fixture got wrong
# (matched to attach_firm_covariates()'s then-incorrect internal assumption
# rather than to reality), which the end-to-end fixture then caught.
rows_ok <- data.frame(cohort = 1L, control_group = c(901, 902))
fc_ok <- data.frame(cohort = 1L, control_group = c(901, 902), log_patent_stock_5y = c(1, 2),
                    log_inventor_count_5y = c(3, 4), patent_trajectory = c(0.1, 0.2))
attached <- attach_firm_covariates(rows_ok, "control_group", fc_ok)
add_check("ATTACH_produces_prefixed_columns",
          all(names(LMV2_HYBRID_FIRM_ATTACH_MAP) %in% names(fc_ok)) &&
            all(unlist(LMV2_HYBRID_FIRM_ATTACH_MAP) %in% names(attached)), TRUE,
          all(unlist(LMV2_HYBRID_FIRM_ATTACH_MAP) %in% names(attached)))
add_check("ATTACH_values_match_source", attached$firm_log_patent_stock_5y, c(1, 2),
          identical(attached$firm_log_patent_stock_5y, c(1, 2)))
fc_missing_one <- fc_ok[fc_ok$control_group != 902, ]
add_check("ATTACH_errors_when_authoritative_row_missing_for_some_group",
          expect_error(attach_firm_covariates(rows_ok, "control_group", fc_missing_one)), TRUE,
          expect_error(attach_firm_covariates(rows_ok, "control_group", fc_missing_one)))

# ===========================================================================
# Fixture PROFILE_DISTANCE -- direct test of the ACTUAL harness function
# build_stage2_edges_for_profile(), proving it produces DIFFERENT composite
# distances for the SAME raw pair under two different profile-scoped donor
# populations (the actual fix, exercised through the real function, not just
# the underlying certified 16c function in isolation).
# ===========================================================================
vars <- LMV2_P3$stage_2$scalar_variables
mk <- function(codinv, deal_id = NULL, focal_group = NULL, val) {
  d <- list(cohort = 1L, codinv = codinv, recency_bin = 0)
  if (!is.null(deal_id)) d$deal_id <- deal_id
  if (!is.null(focal_group)) d$focal_group <- focal_group
  for (v in vars) d[[v]] <- if (v == vars[1]) val else 0
  as.data.frame(d)
}
treated_inv_ok_pf <- mk(901, deal_id = 1L, val = 0)
# Two candidate control inventors: #1 (the pair under test, val=1, firm 101)
# and #2/#3 in the tight population vs #4/#5 in the wide population -- same
# admissible-firm structure otherwise.
admissible_tight <- data.frame(cohort = 1L, deal_id = 1L, control_group = c(101, 102, 103))
admissible_wide <- data.frame(cohort = 1L, deal_id = 1L, control_group = c(101, 104, 105))
# `controls` for lmv2_prepare_stage2_edges() needs `focal_group`, matching
# what donors_profile actually carries in production; donor_cols_* (used for
# candidate-pair construction) is the SAME data with focal_group renamed to
# control_group and codinv renamed to control_codinv -- exactly mirroring
# the real harness's two views of the same fetched covariate table.
donors_tight <- rbind(mk(1, focal_group = 101, val = 1), mk(2, focal_group = 102, val = 1),
                      mk(3, focal_group = 103, val = 1))
donors_wide <- rbind(mk(1, focal_group = 101, val = 1), mk(4, focal_group = 104, val = 10),
                     mk(5, focal_group = 105, val = -8))
donor_cols_tight <- donors_tight
names(donor_cols_tight)[names(donor_cols_tight) == "codinv"] <- "control_codinv"
names(donor_cols_tight)[names(donor_cols_tight) == "focal_group"] <- "control_group"
donor_cols_wide <- donors_wide
names(donor_cols_wide)[names(donor_cols_wide) == "codinv"] <- "control_codinv"
names(donor_cols_wide)[names(donor_cols_wide) == "focal_group"] <- "control_group"

cached_shared <- data.frame(cohort = 1L, treated_codinv = 901, control_codinv = c(1, 2, 3, 4, 5), shared_ipc4 = TRUE)
cached_sim <- data.frame(cohort = 1L, treated_codinv = 901, control_codinv = c(1, 2, 3, 4, 5), cosine = 1)

edges_tight_pf <- build_stage2_edges_for_profile(1L, admissible_tight, treated_inv_ok_pf, donors_tight,
                                                 donor_cols_tight, cached_shared, cached_sim)
edges_wide_pf <- build_stage2_edges_for_profile(1L, admissible_wide, treated_inv_ok_pf, donors_wide,
                                                donor_cols_wide, cached_shared, cached_sim)
d_tight_pf <- edges_tight_pf$distance[edges_tight_pf$control_codinv == 1]
d_wide_pf <- edges_wide_pf$distance[edges_wide_pf$control_codinv == 1]
add_check("PROFILE_DISTANCE_harness_function_recomputes_not_caches",
          sprintf("tight=%.4f wide=%.4f", d_tight_pf, d_wide_pf), "genuinely different",
          length(d_tight_pf) == 1L && length(d_wide_pf) == 1L && abs(d_tight_pf - d_wide_pf) > 0.5)
add_check("PROFILE_DISTANCE_matches_hand_computed_values",
          sprintf("%.6f, %.6f", d_tight_pf, d_wide_pf),
          sprintf("%.6f, %.6f", 1 / stats::sd(c(0, 1, 1, 1)), 1 / stats::sd(c(0, 1, 10, -8))),
          isTRUE(all.equal(d_tight_pf, 1 / stats::sd(c(0, 1, 1, 1)))) &&
            isTRUE(all.equal(d_wide_pf, 1 / stats::sd(c(0, 1, 10, -8)))))

# ===========================================================================
report <- do.call(rbind, checks)
cat(sprintf("\n=== run_cohort_hybrid_pilot.R helper certification: %d checks, %d failing ===\n",
            nrow(report), sum(!report$pass)))
print(report[, c("check", "pass")], row.names = FALSE)
utils::write.csv(report, file.path(AUDIT_OUT_DIR, "certify_run_cohort_hybrid_pilot_helpers_results.csv"), row.names = FALSE)
if (any(!report$pass)) {
  cat("\nFAILING CHECKS:\n"); print(report[!report$pass, ], row.names = FALSE)
  stop("harness helper certification FAILED")
}
cat("\nALL HARNESS HELPER CHECKS PASS.\n")
