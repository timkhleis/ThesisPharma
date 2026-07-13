# ============================================================================
# 11a_main_design_config.R  --  Main acquisition DiD v1: frozen design constants
# ----------------------------------------------------------------------------
# All design decisions live here. Do NOT scatter constants across 11b-11e.
# Sourced by every 11* script (after 00_utils.R + use_project_library()).
# ============================================================================

# --- Design version ---------------------------------------------------------
DESIGN_VERSION <- "main_did_v1"

# --- Cohort / event windows (event time relative to announcement year g) ----
QUALIFICATION_LO <- -5L    # qualification window [g-5, g-1]
QUALIFICATION_HI <- -1L
FIRM_MATCH_LO    <- -6L    # firm matching window [g-6, g-3]
FIRM_MATCH_HI    <- -3L
INV_MATCH_LO     <- -5L    # inventor matching window [g-5, g-1]  (B1: full pre-window)
INV_MATCH_HI     <- -1L
EVENT_LO         <- -5L    # estimation event window [-5, +3]
EVENT_HI         <-  3L

# --- Control design ---------------------------------------------------------
CONTROL_LAG <- 7L                 # primary future-treated control lag (G_c = g + 7)
CENSUS_LAGS <- c(7L, 9L)          # control-lag feasibility census; only 7 is estimated

# Treated stacks: g-6 >= 1988 (earliest patent year) and g+CONTROL_LAG <= 2015.
STACK_LO <- 1994L
STACK_HI <- 2008L                 # for L=7; the census uses STACK_HI = 2015 - L per lag

# --- Anticipation conventions ----------------------------------------------
ANTICIPATION_GRID <- c(0L, 1L)    # delta=0 ref t=-1; delta=1 ref t=-2 (t=-1 = anticipation)
PRIMARY_POST      <- 1:3          # primary post-treatment summary: mean of t=1,2,3
ANNOUNCEMENT_YEAR_PARTIAL <- TRUE # t=0 is partial exposure; reported separately

# --- Gates / thresholds -----------------------------------------------------
COV_TOL              <- 1e-6      # 4b numeric covariate certification tolerance
IPC_MATCH_MIN        <- 0.99      # 4b modal-IPC-section match-rate floor
ACQ_TRANSITION_HARD_GATE <- FALSE # [A4] acquirer-transition route: report-first, do not stop
EBAL_CONSTRAINT_TOL  <- 1e-6      # exact mean-balance tolerance for the EB convergence gate
NEAR_ZERO_WEIGHT     <- 1e-4      # control 'near-zero weight' threshold for diagnostics
SMD_DESIRED          <- 0.05      # desired |SMD|
SMD_ACCEPTABLE       <- 0.10      # acceptable |SMD| (reported, not an auto-stop under EB)

# --- Broad calendar eras for era-level balance diagnostics ------------------
BALANCE_ERAS <- list(c(1994L, 1999L), c(2000L, 2004L), c(2005L, 2008L))

# --- Technology families (broad_pharma_v1) ----------------------------------
# Predicates operate on the FULL zero-padded ipc_code string (main group padded
# to 3 digits): A61K31 -> 'A61K031', A61K9 -> 'A61K009', A61K38/39 -> 'A61K038/9'.
TECH_PROFILE_VERSION <- "broad_pharma_v1"
TECH_FAMILIES        <- c("small_molecule", "biotech", "formulation", "other")
TECH_SHARE_COLS      <- c("share_small_molecule", "share_biotech", "share_formulation")  # 'other' omitted

# --- Covariate name vectors (consumed by 11c balancing) ---------------------
FIRM_COVARS <- c("log_firm_patent_stock", "log_firm_inventor_count", "observed_firm_patent_age",
                 "log_patents_early", "log_patents_recent",
                 "share_small_molecule", "share_biotech", "share_formulation",
                 "no_firm_patent_by_g3", "no_technology_activity_g6_g3")
INV_COVARS  <- c("observed_inventor_career_age", "observed_target_patent_tenure",
                 "log_inventor_patent_stock", "target_exclusivity")
# qualifying-gap and modal-family enter as factor indicators (built in 11b/11c)
INV_FACTOR_COVARS <- c("qualifying_gap_cat", "modal_family")

# --- Reproducibility --------------------------------------------------------
SEED <- 20260712L

# --- Paths (mirror 08u header; NOT the 00_utils path helpers which use 'analysis/') ---
if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB      <- file.path(BASE, "output", "thesis_foundation.duckdb")
DERIVED_PAR <- file.path(BASE, "output", "parquet", "derived")
AUDIT_DIR   <- file.path(BASE, "output", "audit",   DESIGN_VERSION)
RESULTS_DIR <- file.path(BASE, "output", "results", DESIGN_VERSION)
FIGS_DIR    <- file.path(BASE, "output", "figures", DESIGN_VERSION)
DUCKDB_TMP  <- file.path(BASE, "output", "duckdb_tmp")
for (d in c(DERIVED_PAR, AUDIT_DIR, RESULTS_DIR, FIGS_DIR, DUCKDB_TMP))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)

UNITS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_units.parquet")
PANEL_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_panel.parquet")

# --- Outcomes ---------------------------------------------------------------
# First results: levels of active patenting, patent count, and 5y forward cites.
# log_* are retained in the panel but NOT part of the initial main-results table.
OUTCOMES     <- c("active_patenting", "patent_count", "fwd_cits5")
OUTCOME_LABS <- c(active_patenting = "Active patenting (0/1)",
                  patent_count     = "Patent count",
                  fwd_cits5        = "Forward citations (5y)")

invisible(DESIGN_VERSION)
