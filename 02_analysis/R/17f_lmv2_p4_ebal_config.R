# ============================================================================
# 17f_lmv2_p4_ebal_config.R -- effective P4-EB configuration and provenance
# ============================================================================
# P4-EB is outcome blind. It restores the intended entropy-balancing weight
# layer on top of the certified P3 support-finding machinery, after the
# fixed-weight P4 pilot (17a-17e) recorded a definitive design failure. It
# sources 16a/16c directly -- never 17a, which hash-gates on four amendment
# notes specific to the fixed five/ten-firm top-N selector and is unrelated
# to entropy balancing. 17a-17e are referenced by filename only, in comments,
# and are never sourced, called, or edited.
#
# The four choices local_match_v2_p4_ebal_amendment.md deferred (Stage-1
# caliper, Stage-2 caliper, inventor technology resolution, ESS/
# concentration thresholds) are now LOCKED here per
# local_match_v2_p4_ebal_pre_e2_amendment.md, from non-outcome candidate-
# pool diagnostics only. Every 17g/17h/17i function that uses them still
# takes them as explicit parameters (never a silent internal default); this
# file is simply where the caller (17h/17i's --stage1-caliper etc. CLI
# arguments) should now get the value to pass.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "16c_lmv2_matching_utils.R"))

for (pkg in c("digest", "WeightIt")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

LMV2_P4_EBAL_VERSION <- "local_match_v2_p4_ebal_1993_amendment_v1"
# Same certified P3 commit and interface manifest the fixed-weight P4 pilot
# was built on; P4-EB sits on the identical certified P1-P3 foundation. The
# commit string alone verifies nothing; what actually gates sourcing is the
# content-hash check on LMV2_P3_CONFIG_HASH below (P3's own effective-config
# hash, which already folds in the P2 manifest and amendment hashes) plus
# the direct file-content hashes of 16a/16c themselves, immediately below --
# together these are strictly stronger than trusting a commit label, since
# they verify what is actually on disk and sourced, not merely what the
# label claims.
LMV2_P4_EBAL_P3_COMMIT <- "local_match_v2_1993_amendment_v1"
LMV2_P4_EBAL_P3_CONFIG_SHA256 <- "dcf94dac45f5b7a451cd63b95c90d049b5545a7e30de593ee1d232ab56fb218b"
# The certified P3 tables retain the hash above.  The 1993 results amendment
# subsequently changed presentation/sample-routing fields in the P0 lock
# (including removal of the obsolete buffer co-report), which changes the
# recomputed wrapper hash without changing any P3 matching input or rule.
# Permit that one audited runtime hash while continuing to pin the P3
# manifest and the exact 16a/16c source files below.
LMV2_P4_EBAL_P3_AMENDED_RUNTIME_SHA256 <-
  "f59bdc057d15a49bd2c797002af359c5fd72f13eaefa9accec78f86e291c3030"
LMV2_P4_EBAL_P3_MANIFEST_SHA256 <- "b44e66ca8d3b357225d738ed7908346cc6ab598964fa8c40820a629074a6be3e"
LMV2_P4_EBAL_16A_SHA256 <- "582c7fd78a68baf685a81df8dd6aefaea82620e3e5ddf560dc5ce587a49f7ab2"
LMV2_P4_EBAL_16C_SHA256 <- "4496afecd8bb7324eb2d1f5dfd98cf6c6ba0dcd54750fbcc3a4d0e8bcc39e6f7"
# Pinned only after the base-weight semantics fixture (see the amendment,
# "Solver and the empirically resolved base-weight semantics") was resolved
# and the amendment text was finalized -- the amendment documents a result,
# it does not precede it. Revised after a corrective review found the
# treated-weight handling wrong for the equal-deal estimand; see the
# amendment's "Corrective revision" section.
LMV2_P4_EBAL_AMENDMENT_SHA256 <- "0940cec441b4ee39a3635cadb5363366fc062d5fdcb79bcdfd4856a50c4f9c83"
# Pinned only after the non-outcome candidate-pool diagnostics (17f's
# consumer, local_match_v2_p4_ebal_pre_e2_amendment.md) were gathered and
# the amendment text finalized -- same "document a result, don't precede
# it" convention as the main amendment's base-weight-semantics section.
LMV2_P4_EBAL_PRE_E2_AMENDMENT_SHA256 <- "48a57a2a6265d516dd0519f7d4adc3b99a1c2d5bd8dbc3bbcc6d7fcfa1d2424a"
LMV2_P4_EBAL_WEIGHTIT_VERSION <- "1.7.0"

if (!LMV2_P3_CONFIG_HASH %in% c(
    LMV2_P4_EBAL_P3_CONFIG_SHA256,
    LMV2_P4_EBAL_P3_AMENDED_RUNTIME_SHA256)) {
  stop("Certified P3 configuration drifted: expected ", LMV2_P4_EBAL_P3_CONFIG_SHA256,
       ", observed ", LMV2_P3_CONFIG_HASH)
}
observed_16a_hash <- lmv2_p3_file_hash(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
if (!identical(observed_16a_hash, LMV2_P4_EBAL_16A_SHA256)) {
  stop("Imported 16a source drifted: expected ", LMV2_P4_EBAL_16A_SHA256,
       ", observed ", observed_16a_hash)
}
observed_16c_hash <- lmv2_p3_file_hash(file.path(BASE, "R", "16c_lmv2_matching_utils.R"))
if (!identical(observed_16c_hash, LMV2_P4_EBAL_16C_SHA256)) {
  stop("Imported 16c source drifted: expected ", LMV2_P4_EBAL_16C_SHA256,
       ", observed ", observed_16c_hash)
}
observed_weightit_version <- as.character(utils::packageVersion("WeightIt"))
if (!identical(observed_weightit_version, LMV2_P4_EBAL_WEIGHTIT_VERSION)) {
  stop("Installed WeightIt version drifted: expected ", LMV2_P4_EBAL_WEIGHTIT_VERSION,
       ", observed ", observed_weightit_version)
}

LMV2_P4_EBAL_PATHS <- list(
  amendment = file.path(BASE, "notes", "local_match_v2_p4_ebal_amendment.md"),
  pre_e2_amendment = file.path(BASE, "notes", "local_match_v2_p4_ebal_pre_e2_amendment.md"),
  p3_manifest = file.path(BASE, "output", "audit", "local_match_v2", "P3",
                          "p3_interface_manifest.csv"),
  audit = file.path(BASE, "output", "audit", "local_match_v2", "P4_EB")
)

observed_amendment_hash <- lmv2_p3_file_hash(LMV2_P4_EBAL_PATHS$amendment)
if (!identical(observed_amendment_hash, LMV2_P4_EBAL_AMENDMENT_SHA256)) {
  stop("P4-EB amendment drifted: expected ", LMV2_P4_EBAL_AMENDMENT_SHA256,
       ", observed ", observed_amendment_hash)
}
observed_pre_e2_amendment_hash <- lmv2_p3_file_hash(LMV2_P4_EBAL_PATHS$pre_e2_amendment)
if (!identical(observed_pre_e2_amendment_hash, LMV2_P4_EBAL_PRE_E2_AMENDMENT_SHA256)) {
  stop("P4-EB pre-E2 amendment drifted: expected ", LMV2_P4_EBAL_PRE_E2_AMENDMENT_SHA256,
       ", observed ", observed_pre_e2_amendment_hash)
}

# ----------------------------------------------------------------------------
# Effective P4-EB design. Roster grains, balance moments, and the base-weight
# allocation rule are locked from the start (documented in the main
# amendment); support calipers, inventor technology resolution, and ESS/
# concentration thresholds are locked below per the pre-E2 amendment, from
# non-outcome candidate-pool diagnostics only -- never from inspecting real
# weights, balance, or outcomes. Every 17g/17h/17i function still takes
# these as explicit parameters; nothing here is a silent internal default.
# ----------------------------------------------------------------------------

LMV2_P4_EBAL <- list(
  pilot_cohorts = LMV2_LOCK$pilot$cohorts,
  estimand = list(
    primary = LMV2_LOCK$estimands$primary,
    co_report = LMV2_LOCK$estimands$co_report,
    common_support_label_below_retention =
      LMV2_LOCK$estimands$common_support_label_below_retention
  ),
  stage_1 = list(
    balance_variables = c(LMV2_P3$stage_1$scalar_variables,
                          LMV2_P3$stage_1$diagnostic_variable),
    base_s_weight = "uniform_one",
    # Locked by local_match_v2_p4_ebal_pre_e2_amendment.md section 1: the
    # tightest value in the locked grid c(Inf,2,1.5,1) at which every pilot
    # cohort still has 100% deal-level admissibility and an ample (49-3211
    # firm) candidate pool.
    caliper = 1.0,
    preferred = LMV2_LOCK$pilot$stage_1_preferred,
    acceptable = LMV2_LOCK$pilot$stage_1_acceptable,
    # Scale-dependent, non-outcome-derived (pre-E2 amendment section 4):
    # ESS relative to the number of treated deals in the cohort, and the
    # maximum share of cohort control mass any single firm may hold.
    ess_ratio = list(preferred = 1.0, acceptable = 0.5),
    max_share = list(preferred = 0.20, acceptable = 0.35)
  ),
  stage_2 = list(
    balance_variables = LMV2_P3$stage_2$scalar_variables,
    base_s_weight = "stage1_mass_allocated_equal_split_over_eligible_inventors",
    allocation_rule = "equal_split",
    # Locked by local_match_v2_p4_ebal_pre_e2_amendment.md section 3: the
    # tightest value in the locked grid at which every pilot cohort clears
    # the acceptable inventor-retention tier (>=80%) under the locked
    # ipc4 resolution.
    caliper = 1.5,
    # Locked by local_match_v2_p4_ebal_pre_e2_amendment.md section 2: ipc4
    # dominates both alternatives on retention at every caliper; ipc_main_group
    # breaches the locked 50% cohort floor at the tightest caliper; ipc7
    # collapses the eligible pool almost entirely at any real caliper.
    technology_resolution = "ipc4",
    treated_weighting_schemes = c("primary", "equal_deal"),
    preferred = LMV2_LOCK$pilot$stage_2_preferred,
    acceptable = LMV2_LOCK$pilot$stage_2_acceptable,
    firm_reaggregation_preferred_max_smd = 0.05,
    firm_reaggregation_acceptable_max_smd = 0.10,
    # Scale-dependent, non-outcome-derived (pre-E2 amendment section 4):
    # ESS relative to the number of supported treated inventors in the
    # cohort, and the maximum share of cohort control mass any single
    # inventor may hold. Tighter than Stage 1's max_share because Stage-2
    # pools are one to three orders of magnitude larger.
    ess_ratio = list(preferred = 1.0, acceptable = 0.5),
    max_share = list(preferred = 0.10, acceptable = 0.20)
  ),
  tolerances = list(
    exact_tol = 1e-6,
    residual_tol = 1e-3,
    maxit = 100000L
  ),
  # Activated by the pre-E2 amendment (were diagnostic-only through E1):
  # lmv2_ebal_ess_concentration_gate() now gates both stages using the
  # ess_ratio/max_share thresholds above.
  active_gates = c("inadequate_ess", "excessive_weight_concentration"),
  s_weight_convention = paste(
    "treated_final_weight_equals_s_weights_verbatim;",
    "control_final_weight_equals_s_weights_times_fit_weights,_rescaled_to_treated_mass;",
    "WeightIt_never_touches_the_treated_arm_(fit$weights[D==1]_is_always_a_constant),",
    "so_unequal_treated_s_weights_(e.g._the_equal_deal_scheme's_1/n_per_deal)_survive",
    "into_the_final_treated_weight_exactly_and_are_never_forced_to_one"
  )
)

lmv2_p4_ebal_effective_config <- function() {
  list(
    p4_ebal_version = LMV2_P4_EBAL_VERSION,
    p3_commit = LMV2_P4_EBAL_P3_COMMIT,
    p3_config_hash = LMV2_P3_CONFIG_HASH,
    p3_manifest_hash = LMV2_P4_EBAL_P3_MANIFEST_SHA256,
    amendment_hash = LMV2_P4_EBAL_AMENDMENT_SHA256,
    weightit_version = LMV2_P4_EBAL_WEIGHTIT_VERSION,
    p0_design_hash = LMV2_DESIGN_HASH,
    design = LMV2_P4_EBAL
  )
}

LMV2_P4_EBAL_EFFECTIVE_CONFIG <- lmv2_p4_ebal_effective_config()
LMV2_P4_EBAL_CONFIG_HASH <- digest::digest(
  LMV2_P4_EBAL_EFFECTIVE_CONFIG, algo = "sha256", serialize = TRUE
)

# ----------------------------------------------------------------------------
# Ported generic helpers (cited to their 17a originals; re-implemented here
# rather than sourced, so P4-EB never depends on 17a's amendment hash gate).
# ----------------------------------------------------------------------------

lmv2_ebal_read_arg <- function(name, args = commandArgs(trailingOnly = TRUE),
                               required = TRUE) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) != 1L || !nzchar(substring(hit, nchar(prefix) + 1L))) {
    if (!required) return(NA_character_)
    stop("Required argument ", prefix, "<value> is missing")
  }
  substring(hit, nchar(prefix) + 1L)
}

lmv2_ebal_mode <- function(args = commandArgs(trailingOnly = TRUE)) {
  mode <- lmv2_ebal_read_arg("mode", args)
  if (!mode %in% c("certify", "production")) {
    stop("--mode must be 'certify' or 'production', got: ", mode)
  }
  mode
}

# Stable profile identifiers: the infinite caliper is labeled "_inf" so no
# Inf value ever reaches CSV formatting.
lmv2_ebal_caliper_label <- function(prefix, caliper) {
  paste0(prefix, "_", vapply(caliper, function(x) {
    if (is.infinite(x)) "inf" else format(x, trim = TRUE)
  }, character(1)))
}

# Canonical checksum of a caller-ordered data frame; row order matters by
# design.
lmv2_ebal_frame_checksum <- function(x) {
  cols <- lapply(x, function(col) {
    out <- as.character(col)
    out[is.na(col)] <- "<NA>"
    out
  })
  rows <- if (nrow(x)) do.call(paste, c(cols, sep = "|")) else character(0)
  digest::digest(paste(c(paste(names(x), collapse = "|"), rows), collapse = "\n"),
                 algo = "sha256", serialize = FALSE)
}

lmv2_ebal_write_csv <- function(x, dir, name) {
  utils::write.csv(x, file.path(dir, name), row.names = FALSE, na = "")
}

# Logical manifest of a run directory. Scripts write deterministically
# ordered rows and no timestamps, absolute paths, or run labels, so the byte
# hash of each CSV is its logical fingerprint.
lmv2_ebal_logical_manifest <- function(dir) {
  files <- sort(list.files(dir, pattern = "\\.csv$", recursive = TRUE))
  out <- do.call(rbind, lapply(files, function(f) {
    path <- file.path(dir, f)
    data.frame(file = f,
               rows = nrow(utils::read.csv(path, stringsAsFactors = FALSE)),
               logical_sha256 = lmv2_p3_file_hash(path),
               stringsAsFactors = FALSE)
  }))
  if (is.null(out)) out <- data.frame(file = character(), rows = integer(),
                                      logical_sha256 = character())
  out$p4_ebal_version <- rep(LMV2_P4_EBAL_VERSION, nrow(out))
  out$p4_ebal_config_hash <- rep(LMV2_P4_EBAL_CONFIG_HASH, nrow(out))
  out
}
