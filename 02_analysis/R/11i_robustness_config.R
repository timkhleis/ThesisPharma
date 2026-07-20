# ============================================================================
# 11i_robustness_config.R -- Main DiD v1 robustness Phase 1 constants
# ----------------------------------------------------------------------------
# Design-only robustness checkpoint. No outcome construction or patent_enriched
# access belongs in Phase 1.
# ============================================================================

ROBUSTNESS_VERSION <- "main_did_v1_robustness_phase1c"
ROBUSTNESS_NOTE <- file.path(BASE, "notes", "main_did_v1_robustness_design_checkpoint.md")

ROBUSTNESS_DESIGN_COMPARISON <- file.path(RESULTS_DIR, "main_robustness_design_comparison.csv")
ROBUSTNESS_BALANCE_ALL <- file.path(RESULTS_DIR, "main_robustness_balance_all_covariates.csv")
ROBUSTNESS_CONCENTRATION <- file.path(RESULTS_DIR, "main_robustness_weight_concentration.csv")
ROBUSTNESS_STACK_MASS <- file.path(RESULTS_DIR, "main_robustness_stack_mass.csv")
ROBUSTNESS_QUANTILES <- file.path(RESULTS_DIR, "main_robustness_weighted_quantiles.csv")
ROBUSTNESS_FEASIBILITY <- file.path(RESULTS_DIR, "main_robustness_feasibility_decisions.csv")

NT_UNITS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_units.parquet")
P0_WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_weights.parquet")

P0H5_WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_h5_weights.parquet")
P1_WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_h5_reduced_numeric_weights.parquet")
P2_WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_h5_acquirer_clean_weights.parquet")
P3_WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_g7_reduced4x4_weights.parquet")
P3_DIAGNOSTIC_WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_g7_reduced4x4_weights_diagnostic.parquet")
P4_WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_g7_deal_weighted_weights.parquet")
P5_WEIGHTS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_h5_deal_weighted_weights.parquet")

FIRM_COVARS_REDUCED <- c(
  "log_firm_inventor_count",
  "log_patents_recent",
  "share_small_molecule",
  "share_biotech"
)

INVENTOR_COVARS_REDUCED <- c(
  "log_inventor_patent_stock",
  "observed_inventor_career_age",
  "observed_target_patent_tenure",
  "target_exclusivity"
)

FULL_NUMERIC_COVARS <- c(FIRM_COVARS, INV_COVARS)
FULL_CONT_COVARS <- c(
  "log_firm_patent_stock", "log_firm_inventor_count", "observed_firm_patent_age",
  "log_patents_early", "log_patents_recent", "observed_inventor_career_age",
  "observed_target_patent_tenure", "log_inventor_patent_stock", "target_exclusivity"
)

STACK_MASS_TOL <- 1e-4
P4_DEAL_MASS_TOL <- 1e-8
ROBUST_MAX_SMD_CONSTRAINED <- 0.05
ROBUST_MAX_SMD_OMITTED <- 0.10
ROBUST_MIN_ESS <- 50
ROBUST_MAX_SHARE <- 0.10

ROBUSTNESS_SPECS <- data.frame(
  spec = c("P0", "P0H5", "P1", "P2", "P3", "P4", "P5"),
  label = c(
    "Frozen legacy never-target benchmark, full covariates, inventor-weighted ATT",
    "Corrected never-target H5, full covariates, inventor-weighted ATT",
    "Reduced numeric covariates on P0H5, with categorical controls retained",
    "Corrected never-target H5, acquirer-clean controls, inventor-weighted ATT",
    "g+7 future-treated controls, reduced 4x4, inventor-weighted ATT",
    "g+7 future-treated controls, full covariates, proper deal-weighted ATT",
    "Corrected never-target H5, full covariates, deal-weighted ATT"
  ),
  donor_pool = c("never_target_legacy", "never_target_h5", "never_target_h5",
                 "never_target_h5_acquirer_clean", "future_g7", "future_g7",
                 "never_target_h5"),
  estimand = c("inventor_weighted_ATT", "inventor_weighted_ATT", "inventor_weighted_ATT",
               "inventor_weighted_ATT",
               "inventor_weighted_ATT", "deal_weighted_ATT", "deal_weighted_ATT"),
  stringsAsFactors = FALSE
)

invisible(ROBUSTNESS_VERSION)
