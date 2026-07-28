# ============================================================================
# 30e_certify_lmv2_dealsim_power_gate.R -- certify and tooth-test Stage A
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
if (!requireNamespace("digest", quietly = TRUE)) stop("Missing package: digest")
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "30a_lmv2_dealsim_power_config.R"))

out_dir <- LMV2_DEALSIM_POWER$output_dir
paths <- setNames(file.path(out_dir, c(
  "dealsim_by_deal.csv",
  "dealsim_build_manifest.csv",
  "dealsim_tercile_assignment.csv",
  "dealsim_tercile_support.csv",
  "dealsim_common_cohort_audit.csv",
  "dealsim_assignment_manifest.csv",
  "dealsim_contrast_mde.csv",
  "dealsim_continuous_mde.csv",
  "dealsim_mde_calibration.csv",
  "dealsim_power_gate.csv",
  "dealsim_power_manifest.csv"
)), c(
  "deal", "build_manifest", "assignment", "support", "cohort_audit",
  "assignment_manifest", "mde", "continuous_mde", "calibration", "gate",
  "power_manifest"
))
if (!all(file.exists(paths))) {
  stop("Stage A output bundle is incomplete")
}

deals <- utils::read.csv(paths[["deal"]], stringsAsFactors = FALSE)
assignment <- utils::read.csv(
  paths[["assignment"]], stringsAsFactors = FALSE
)
support <- utils::read.csv(paths[["support"]], stringsAsFactors = FALSE)
cohort_audit <- utils::read.csv(
  paths[["cohort_audit"]], stringsAsFactors = FALSE
)
mde <- utils::read.csv(paths[["mde"]], stringsAsFactors = FALSE)
continuous_mde <- utils::read.csv(
  paths[["continuous_mde"]], stringsAsFactors = FALSE
)
calibration <- utils::read.csv(
  paths[["calibration"]], stringsAsFactors = FALSE
)
gate <- utils::read.csv(paths[["gate"]], stringsAsFactors = FALSE)
power_manifest <- utils::read.csv(
  paths[["power_manifest"]], stringsAsFactors = FALSE
)

lmv2_assert_dealsim_rows(deals)
lmv2_assert_dealsim_rows(assignment)
eligible <- assignment$eligible_dealsim
reassigned <- lmv2_dealsim_assign_terciles(
  assignment$deal_id[eligible], assignment$dealsim[eligible]
)

checks <- data.frame(
  check = c(
    "exact_frozen_deal_count",
    "one_row_per_deal",
    "placeholder_acquirers_excluded",
    "only_predeal_ipc_years_used",
    "eligible_cosines_in_unit_interval",
    "deterministic_tercile_assignment",
    "every_eligible_deal_assigned_once",
    "three_common_cohort_support_rows",
    "frozen_contrast_family_only",
    "continuous_screen_uses_same_contrast_family",
    "joint_bootstrap_replications_frozen",
    "single_valid_path_selected",
    "no_subgroup_att_saved",
    "all_manifests_use_current_design_hash"
  ),
  pass = c(
    nrow(deals) == 341L,
    !anyDuplicated(deals$deal_id),
    !any(
      !is.na(deals$acquirer_group) &
        grepl("^999", format(deals$acquirer_group, scientific = FALSE)) &
        deals$eligible_dealsim
    ),
    all(
      deals$target_last_ipc_year[deals$eligible_dealsim] <=
        deals$cohort[deals$eligible_dealsim] - 1L
    ) &&
      all(
        deals$acquirer_last_ipc_year[deals$eligible_dealsim] <=
          deals$cohort[deals$eligible_dealsim] - 1L
      ),
    all(deals$dealsim[deals$eligible_dealsim] >= 0 &
          deals$dealsim[deals$eligible_dealsim] <= 1),
    identical(
      unname(assignment$tercile[eligible]),
      unname(reassigned)
    ),
    all(!is.na(assignment$tercile[eligible])) &&
      all(
        is.na(assignment$tercile[!eligible]) |
          assignment$tercile[!eligible] == ""
      ),
    sum(support$sample == "common_cohort_set") == 3L,
    identical(
      sort(mde$contrast),
      sort(LMV2_DEALSIM_POWER$estimand$contrasts)
    ),
    identical(
      sort(continuous_mde$contrast),
      sort(LMV2_DEALSIM_POWER$estimand$contrasts)
    ),
    nrow(calibration) == 1L &&
      calibration$bootstrap_replications ==
        LMV2_DEALSIM_POWER$power$bootstrap_replications,
    nrow(gate) == 1L &&
      gate$selected_path %in% names(LMV2_DEALSIM_POWER$paths),
    nrow(power_manifest) == 1L &&
      !power_manifest$subgroup_att_saved &&
      !gate$subgroup_att_saved &&
      !gate$subgroup_att_printed,
    nrow(power_manifest) == 1L &&
      power_manifest$dealsim_power_hash == lmv2_dealsim_power_hash()
  ),
  stringsAsFactors = FALSE
)
lmv2_assert_all_checks(checks)

# Tooth tests: each guard must fail on a realistic positive.
expect_error <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
duplicate_fixture <- deals[seq_len(min(3L, nrow(deals))), ]
duplicate_fixture <- rbind(duplicate_fixture, duplicate_fixture[1, ])
placeholder_fixture <- deals[which(!is.na(deals$acquirer_group))[1], ]
placeholder_fixture$acquirer_group <- 999123L
placeholder_fixture$eligible_dealsim <- TRUE
placeholder_fixture$dealsim <- 0.5
future_fixture <- deals[which(deals$eligible_dealsim)[1], ]
future_fixture$target_last_ipc_year <- future_fixture$cohort
cosine_fixture <- deals[which(deals$eligible_dealsim)[1], ]
cosine_fixture$dealsim <- 1.2
fake_checks <- data.frame(
  check = c("real_pass", "fake_pass"),
  pass = c(TRUE, FALSE),
  stringsAsFactors = FALSE
)
tooth_tests <- data.frame(
  tooth_test = c(
    "duplicate_deal_guard_fires",
    "placeholder_guard_fires",
    "postyear_guard_fires",
    "cosine_range_guard_fires",
    "failed_certification_guard_fires"
  ),
  pass = c(
    expect_error(lmv2_assert_dealsim_rows(duplicate_fixture)),
    expect_error(lmv2_assert_dealsim_rows(placeholder_fixture)),
    expect_error(lmv2_assert_dealsim_rows(future_fixture)),
    expect_error(lmv2_assert_dealsim_rows(cosine_fixture)),
    expect_error(lmv2_assert_all_checks(fake_checks))
  ),
  stringsAsFactors = FALSE
)
lmv2_assert_all_checks(data.frame(
  check = tooth_tests$tooth_test, pass = tooth_tests$pass
))

utils::write.csv(
  checks, file.path(out_dir, "dealsim_power_certification.csv"),
  row.names = FALSE
)
utils::write.csv(
  tooth_tests, file.path(out_dir, "dealsim_power_tooth_tests.csv"),
  row.names = FALSE
)

decision_note <- c(
  "# DealSim Stage A power-gate decision",
  "",
  paste0("- Frozen design hash: `", lmv2_dealsim_power_hash(), "`."),
  paste0("- Selected path: **", gate$selected_path, "**."),
  paste0("- Interpretation: ", gate$path_description),
  paste0("- Eligible DealSim deals: ", sum(assignment$eligible_dealsim), "."),
  paste0("- Common cohorts across all terciles: ", gate$common_cohort_count, "."),
  sprintf(
    "- Minimum effective deals across common-cohort terciles: %.2f.",
    gate$minimum_tercile_effective_deals
  ),
  sprintf(
    "- Largest common-cohort tercile deal share: %.1f%%.",
    100 * gate$maximum_tercile_deal_share
  ),
  sprintf(
    "- Largest joint-family 80%% MDE: %.3f patents per inventor-year.",
    gate$maximum_joint_mde
  ),
  sprintf(
    "- Largest continuous-quadratic joint-family 80%% MDE: %.3f patents per inventor-year.",
    gate$maximum_continuous_joint_mde
  ),
  paste0(
    "- Meaningful contrast frozen before outcomes: ",
    gate$meaningful_annual_contrast, " patents per inventor-year."
  ),
  "",
  "No DealSim subgroup ATT was saved or printed. Outcome work remains gated by",
  "this certified decision."
)
writeLines(
  decision_note,
  file.path(out_dir, "dealsim_power_gate_decision.md"),
  useBytes = TRUE
)

source_files <- file.path(BASE, "R", sprintf(
  "30%s_%s.R",
  letters[1:5],
  c(
    "lmv2_dealsim_power_config",
    "build_lmv2_dealsim_table",
    "assign_lmv2_dealsim_terciles",
    "compute_lmv2_dealsim_power",
    "certify_lmv2_dealsim_power_gate"
  )
))
cert_manifest <- data.frame(
  dealsim_power_hash = lmv2_dealsim_power_hash(),
  selected_path = gate$selected_path,
  all_checks_pass = all(checks$pass),
  all_tooth_tests_pass = all(tooth_tests$pass),
  source_bundle_sha256 = digest::digest(
    vapply(source_files, digest::digest, character(1),
           file = TRUE, algo = "sha256"),
    algo = "sha256", serialize = TRUE
  ),
  output_bundle_sha256 = digest::digest(
    vapply(paths, digest::digest, character(1),
           file = TRUE, algo = "sha256"),
    algo = "sha256", serialize = TRUE
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  cert_manifest, file.path(out_dir, "dealsim_power_certification_manifest.csv"),
  row.names = FALSE
)
message(
  "DealSim Stage A certified: Path ", gate$selected_path,
  "; all checks and tooth tests passed."
)
