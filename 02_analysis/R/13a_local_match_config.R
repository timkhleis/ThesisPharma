# ============================================================================
# 13a_local_match_config.R  -- design version: local_match_v1
# ----------------------------------------------------------------------------
# Frozen configuration for the LOCAL TWO-STAGE NEAREST-NEIGHBOUR MATCHING pilot
# (Stage 1: 5 nearest control firms per treated target;
#  Stage 2: 3 nearest control inventors per treated inventor, weight 1/3 each).
#
# This is a NEW, self-contained design. It does NOT source 11a/11i and does NOT
# reuse the entropy-balancing machinery. It reuses only certified functions-only
# helpers from 11_main_design_utils.R (qualify_sql, keep_first_exposure,
# compute_inventor_covariates, ipc_family_case_sql, smd_weighted, ess).
#
# Acquisition year is ALWAYS target_year (== spine deal_year, verified 0 mismatch
# vs deal_map.target_year). acqui_year is never used.
#
# Bare-global-assignment config pattern (mirrors 11a). Sourced into .GlobalEnv.
# ============================================================================

DESIGN_VERSION_LM <- "local_match_v1"

# --- paths -----------------------------------------------------------------
# BASE is expected to be set by the sourcing build script to normalizePath("02_analysis").
if (!exists("BASE")) BASE <- normalizePath("02_analysis", mustWork = TRUE)

DUCKDB      <- normalizePath(file.path(BASE, "output", "thesis_foundation.duckdb"), mustWork = TRUE)
OUT_ROOT    <- file.path(BASE, "output")
DERIVED_PAR <- file.path(OUT_ROOT, "parquet", "derived")
DUCKDB_TMP  <- file.path(OUT_ROOT, "duckdb_tmp_local_match_v1")

# LM_SAMPLE selects the authoritative treatment-assignment definition (v2):
#   strict   = company-level primary  (cassi_deal_group_spine + deal_target_company_strict)
#   expanded = company-level sensitivity (…_expanded; adds supplementary-linkage deals)
#   group    = OLD corporate-group sensitivity (target_cohort_group_sensitivity) -- NOT primary
# These are SEPARATELY LABELLED builds and must never be pooled.
LM_SAMPLE <- tolower(Sys.getenv("LM_SAMPLE", "strict"))
stopifnot(LM_SAMPLE %in% c("strict", "expanded", "group"))

# Authoritative spine tables (built by 04c_build_prelim_own_status.R). The old
# deal_map / inventor_status_reference / group-level qualify are NOT used for the
# primary treated path.
TBL_SPINE_STRICT   <- "cassi_deal_group_spine"
TBL_SPINE_EXPANDED <- "cassi_deal_group_spine_expanded"
TBL_DTC_STRICT     <- "deal_target_company_strict"
TBL_DTC_EXPANDED   <- "deal_target_company_expanded"
TBL_DEAL_ASSIGN    <- "deal_assignment"
TBL_GROUP_SENS     <- "target_cohort_group_sensitivity"
TBL_TARGET_COHORT  <- "target_cohort_own"

# LM_TAG lets a full / smoke / sensitivity build write to SEPARATE versioned
# artifacts so the frozen pilot parquet/shards/results are never overwritten.
LM_TAG   <- Sys.getenv("LM_TAG", "")
lm_stub  <- if (nzchar(LM_TAG)) paste0("local_match_v1_", LM_TAG) else "local_match_v1"
tag_pref <- paste0(lm_stub, "_")
SHARD_DIR   <- file.path(DERIVED_PAR, paste0(lm_stub, "_shards"))
AUDIT_DIR   <- file.path(OUT_ROOT, "audit",   lm_stub)
RESULTS_DIR <- file.path(OUT_ROOT, "results", lm_stub)

# Guard against accidentally pooling strict / expanded / group builds: a non-strict
# sample must write to a tag that names it, and a strict tag must not name another.
if (LM_SAMPLE == "expanded") stopifnot(grepl("expanded", LM_TAG))
if (LM_SAMPLE == "group")    stopifnot(grepl("group",    LM_TAG))
if (LM_SAMPLE == "strict")   stopifnot(!grepl("expanded|group", LM_TAG))

for (d in c(DERIVED_PAR, SHARD_DIR, AUDIT_DIR, RESULTS_DIR, DUCKDB_TMP))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)

# Versioned derived-parquet targets (never overwrite existing artifacts).
LM_TREATED_PARQUET       <- file.path(DERIVED_PAR, paste0(tag_pref, "treated_pilot.parquet"))
LM_TREATED_COV_PARQUET   <- file.path(DERIVED_PAR, paste0(tag_pref, "treated_covariates.parquet"))
LM_TREATED_FIRM_PARQUET  <- file.path(DERIVED_PAR, paste0(tag_pref, "treated_firm_covariates.parquet"))
LM_FIRMPOOL_PARQUET      <- file.path(DERIVED_PAR, paste0(tag_pref, "control_firm_pool.parquet"))
LM_MAHISTORY_PARQUET     <- file.path(DERIVED_PAR, paste0(tag_pref, "ma_history.parquet"))
LM_ROUTE_AUDIT_CSV       <- "route_audit"                 # written under AUDIT_DIR
LM_SUPPORT_CENSUS_CSV    <- "support_census"              # written under AUDIT_DIR

# --- event-time windows (relative to acquisition year g) -------------------
QUAL_LO      <- -5L   # qualification window g-5 .. g-1
QUAL_HI      <- -1L
EVENT_LO     <- -5L   # event window g-5 .. g+5
EVENT_HI     <-  5L
EARLY_LO     <- -5L   # trajectory: early = g-5 .. g-3 (3 years)
EARLY_HI     <- -3L
RECENT_LO    <- -2L   # trajectory: recent = g-2 .. g-1 (2 years)
RECENT_HI    <- -1L
POST_LO      <-  1L   # primary post g+1 .. g+5 (NOT used for matching)
POST_HI      <-  5L
ANTICIPATION <-  0L
REF_OFFSET   <- -1L   # reference year = g-1
PANEL_LO     <- 1988L # patent panel bounds
PANEL_HI     <- 2015L

# --- cohorts ---------------------------------------------------------------
FULL_COHORTS  <- 1994:2010            # full-cohort target set (needs g-6>=1988? no; g-5>=1988 & g+5<=2015)
PILOT_COHORTS <- c(1995L, 2002L, 2009L)  # 1995 thin, 2002 middle, 2009 late

# --- matching parameters ---------------------------------------------------
N_FIRM_MATCH <- 5L                    # exactly 5 control firms per treated target
N_INV_MATCH  <- 3L                    # exactly 3 control inventors per treated inventor
INV_WEIGHT   <- 1 / 3                 # per-match weight

# Caliper profiles: max ABS standardized component gap allowed. Applied BEFORE
# nearest-neighbour selection, at BOTH stages, using the same profile at both.
# Both stages are re-run for every profile (the 5 matched firms may change).
CALIPER_PROFILES <- c(uncalipered = Inf, loose = 2.0, medium = 1.5, tight = 1.0)

# --- matching covariates ---------------------------------------------------
# Stage 1 (firm-level, all measured over g-5..g-1):
#   log_patent_stock_5y    = log1p(sum patents g-5..g-1)
#   log_inventor_count_5y  = log1p(distinct inventors g-5..g-1)
#   patent_trajectory      = log1p(recent/2) - log1p(early/3)   [annualized rates]
#   tech_distance          = 1 - cosine(target, control) over IPC-subclass vectors g-5..g-1
FIRM_MATCH_VARS <- c("log_patent_stock_5y", "log_inventor_count_5y",
                     "patent_trajectory", "tech_distance")

# Stage 2 (inventor-level, all measured with data no later than g-1):
#   log_patent_count_5y    = log1p(sum patents g-5..g-1)               [= compute_inventor_covariates log_inventor_patent_stock]
#   patent_trajectory      = log1p(recent/2) - log1p(early/3)          [annualized]
#   career_age             = (g-1) - career_first_year
#   tenure                 = (g-1) - first focal-group affiliation year
#   exclusivity            = focal-group share of pre-period patents
#   fam_small_molecule / fam_biotech / fam_formulation                 [4-family transparent indicators; 'other' = reference]
INV_CONT_VARS   <- c("log_patent_count_5y", "patent_trajectory",
                     "career_age", "tenure", "exclusivity")
INV_FAMILY_VARS <- c("fam_small_molecule", "fam_biotech", "fam_formulation")
INV_MATCH_VARS  <- c(INV_CONT_VARS, INV_FAMILY_VARS)
FAMILIES        <- c("small_molecule", "biotech", "formulation", "other")  # certified 4-family set

# Family indicators enter the Stage-2 distance as RAW 0/1 mismatch terms scaled by
# this weight (NOT divided by their pooled binary SD, which would let a rare-family
# mismatch dominate). Continuous vars are standardized; the caliper is continuous-only.
# A cross-family mismatch flips 2 dummies -> distance contribution sqrt(2)*weight.
FAMILY_PENALTY_WEIGHT <- 0.5

# Donor "ever-target" screen (Fix 1):
#   predeal = event-specific pre-deal target group only (firm_group in [g-5,g-1]) -- PRIMARY
#   allyear = target company mapped through firm_group over ALL years -- robustness only
#             ("never any M&A participation"); mechanically also excludes acquirers.
LM_DONOR_SCREEN <- tolower(Sys.getenv("LM_DONOR_SCREEN", "predeal"))
stopifnot(LM_DONOR_SCREEN %in% c("predeal", "allyear"))

# --- broad eras (for within-era balance reporting) -------------------------
BROAD_ERAS <- list(
  "1994-1999" = c(1994L, 1999L),
  "2000-2004" = c(2000L, 2004L),
  "2005-2010" = c(2005L, 2010L)
)

# --- diagnostic gates (reporting only; NOT frozen tonight) -----------------
SMD_POOLED_PREF   <- 0.05   # preferred pooled |ATT-standardized diff|
SMD_WITHIN_PREF   <- 0.10   # preferred within cohort / era
RETAIN_REJECT     <- 0.80   # reject profile below this treated-inventor retention
RETAIN_PREFER     <- 0.90   # prefer profiles at/above this
ROUTE_OVERALL_TH  <- 0.05   # transition-route reporting threshold (overall)
ROUTE_ERA_TH      <- 0.10   # transition-route reporting threshold (any broad era)

SEED <- 20260721L

# Deterministic design hash over the frozen design (incl. sample). Stamped into
# inputs, shards, manifests, and results so every artifact is traceable to one
# design. base-R only (tools::md5sum on a temp file).
LM_DESIGN_HASH <- local({
  canon <- paste(DESIGN_VERSION_LM, LM_SAMPLE, LM_DONOR_SCREEN,
                 QUAL_LO, QUAL_HI, EVENT_LO, EVENT_HI, EARLY_LO, EARLY_HI, RECENT_LO, RECENT_HI,
                 ANTICIPATION, REF_OFFSET, N_FIRM_MATCH, N_INV_MATCH, INV_WEIGHT,
                 FAMILY_PENALTY_WEIGHT,
                 paste(names(CALIPER_PROFILES), CALIPER_PROFILES, collapse = ","),
                 paste(FIRM_MATCH_VARS, collapse = ","), paste(INV_MATCH_VARS, collapse = ","),
                 paste(FAMILIES, collapse = ","), SEED, sep = "|")
  tf <- tempfile(); writeLines(canon, tf)
  h <- unname(tools::md5sum(tf)); file.remove(tf)
  substr(h, 1, 12)
})

invisible(DESIGN_VERSION_LM)
