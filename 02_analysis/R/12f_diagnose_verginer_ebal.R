# ============================================================================
# 12f_diagnose_verginer_ebal.R -- Diagnosis-only support and validation audits
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "12a_verginer_ebal_config.R"))
source(file.path(BASE, "R", "12c_verginer_ebal_utils.R"))
required_packages_12(c("did"))

banner_12("12f: Diagnose Verginer ebal feasibility blockers")

if (!file.exists(PANEL_PARQUET)) {
  stop("Missing complete-case panel parquet; run development feasibility first.")
}

panel <- read_parquet_12(PANEL_PARQUET)
panel$vr_common_ipc_cat <- factor(panel$vr_common_ipc_cat, levels = c("0", "1-3", "4+"))
panel$design_dummy <- 0
units <- panel[!duplicated(panel$codinv), ]

status <- utils::read.csv(file.path(RESULTS_DIR, "feasibility_status.csv"),
                          stringsAsFactors = FALSE)
req_fail <- utils::read.csv(file.path(AUDIT_DIR, "group_time_required_failures.csv"),
                            stringsAsFactors = FALSE)
problem_cells <- utils::read.csv(file.path(AUDIT_DIR, "group_time_problem_cells.csv"),
                                 stringsAsFactors = FALSE)
required_status <- utils::read.csv(file.path(AUDIT_DIR, "group_time_required_cell_status.csv"),
                                   stringsAsFactors = FALSE)
unmatched <- utils::read.csv(file.path(AUDIT_DIR, "cell_engine_unmatched_cells.csv"),
                             stringsAsFactors = FALSE)

section_12("Inspect installed did support rule")
d <- panel
d$est_deal_year <- d$treatment_year
did_warnings <- character()
dp <- withCallingHandlers(
  did:::pre_process_did(
    yname = "design_dummy",
    tname = "calendar_year",
    idname = "codinv",
    gname = "est_deal_year",
    xformla = ~1,
    data = d,
    panel = TRUE,
    allow_unbalanced_panel = FALSE,
    control_group = CONTROL_GROUP,
    anticipation = ANTICIPATION,
    bstrap = FALSE,
    cband = FALSE,
    est_method = function(y1, y0, D, covariates, i.weights, inffunc = FALSE) {
      list(ATT = 0)
    },
    base_period = BASE_PERIOD,
    print_details = FALSE,
    faster_mode = FALSE,
    pl = FALSE,
    cores = 1
  ),
  warning = function(w) {
    did_warnings <<- c(did_warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)

att_warnings <- character()
zero_estimator_12 <- function(y1, y0, D, covariates, i.weights, inffunc = FALSE) {
  list(ATT = 0)
}
att_zero <- withCallingHandlers(
  did::att_gt(
    yname = "design_dummy",
    tname = "calendar_year",
    idname = "codinv",
    gname = "est_deal_year",
    xformla = ~1,
    data = d,
    panel = TRUE,
    allow_unbalanced_panel = FALSE,
    control_group = CONTROL_GROUP,
    anticipation = ANTICIPATION,
    est_method = zero_estimator_12,
    base_period = BASE_PERIOD,
    bstrap = FALSE,
    cband = FALSE,
    print_details = FALSE,
    compute_inffunc = FALSE
  ),
  warning = function(w) {
    att_warnings <<- c(att_warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)

original_glist <- sort(unique(units$treatment_year))
original_tlist <- sort(unique(panel$calendar_year))
latest_g <- max(original_glist[original_glist > 0], na.rm = TRUE)
has_never <- any(original_glist == 0)
did_rule_active <- !has_never && identical(CONTROL_GROUP, "notyettreated")
support_rule <- data.frame(
  did_version = as.character(utils::packageVersion("did")),
  control_group = CONTROL_GROUP,
  base_period = BASE_PERIOD,
  anticipation = ANTICIPATION,
  original_has_never_treated = has_never,
  original_latest_treated_group = latest_g,
  original_min_time = min(original_tlist),
  original_max_time = max(original_tlist),
  did_preprocessed_min_time = min(dp$tlist),
  did_preprocessed_max_time = max(dp$tlist),
  did_preprocessed_glist = paste(dp$glist, collapse = ";"),
  did_latest_group_in_glist = latest_g %in% dp$glist,
  did_rule_active_no_never_notyet_latest_cohort_control_only = did_rule_active,
  rule_diagnosis = if (did_rule_active && !(latest_g %in% dp$glist)) {
    "installed_did_pre_process_did_excludes_latest_cohort_from_estimated_glist_when_no_never_treated_group_and_control_group_is_notyettreated"
  } else {
    "unresolved_from_pre_process_did"
  }
)
write_audit_12(support_rule, "did_support_rule_audit.csv")

did_structure <- data.frame(
  group = as.integer(att_zero$group),
  time = as.integer(att_zero$t),
  event_time = as.integer(att_zero$t - att_zero$group),
  att = as.numeric(att_zero$att),
  finite_att = is.finite(att_zero$att)
)
write_audit_12(did_structure, "did_returned_group_time_structure.csv")

did_warning_audit <- data.frame(
  source = c(rep("pre_process_did", length(unique(did_warnings))),
             rep("att_gt_zero_estimator", length(unique(att_warnings)))),
  warning = c(unique(did_warnings), unique(att_warnings))
)
if (nrow(did_warning_audit) == 0L) {
  did_warning_audit <- data.frame(
    source = "did_validation",
    warning = "no_warnings_captured"
  )
}
write_audit_12(did_warning_audit, "did_validation_warnings.csv")

if (nrow(unmatched) > 0L) {
  custom_comp <- lapply(seq_len(nrow(unmatched)), function(i) {
    row <- unmatched[i, ]
    g <- as.integer(row$group)
    tt <- as.integer(row$time)
    pre <- as.integer(row$custom_pre_time)
    D <- as.integer(units$treatment_year == g)
    C <- as.integer(units$treatment_year == 0L |
                      (units$treatment_year > tt + ANTICIPATION &
                         units$treatment_year != g))
    ctl <- units[C == 1L, , drop = FALSE]
    control_cohorts <- as.data.frame(table(control_treatment_year = ctl$treatment_year))
    data.frame(
      group = g,
      time = tt,
      event_time = as.integer(row$event_time),
      custom_pre_time = pre,
      custom_rule = "treated_if_treatment_year_equals_group; control_if_never_or_treatment_year_gt_time",
      custom_n_treated = sum(D == 1L),
      custom_n_control = sum(C == 1L),
      custom_control_cohorts = paste(
        paste0(control_cohorts$control_treatment_year, ":", control_cohorts$Freq),
        collapse = ";"
      ),
      did_rule = support_rule$rule_diagnosis,
      did_preprocessed_glist_contains_group = g %in% dp$glist,
      did_returned_rows_for_group = sum(did_structure$group == g, na.rm = TRUE),
      did_returned_finite_rows_for_group = sum(did_structure$group == g &
                                                did_structure$finite_att,
                                              na.rm = TRUE),
      validation_status = if (g %in% dp$glist) {
        "unresolved"
      } else {
        "resolved_expected_did_support_feature"
      }
    )
  })
  write_audit_12(do.call(rbind, custom_comp), "did_custom_eligibility_comparison.csv")
}

section_12("Diagnose true entropy-balancing failures")
problem_key <- c("specification", "bootstrap_replication", "group", "time", "event_time")
fail_detail <- merge(
  req_fail,
  problem_cells[, c(problem_key, "n_treated", "n_control", "max_abs_mean_difference",
                   "control_ess", "max_control_share")],
  by = problem_key,
  all.x = TRUE
)

cell_units_12 <- function(g, tt) {
  D <- as.integer(units$treatment_year == g)
  C <- as.integer(units$treatment_year == 0L |
                    (units$treatment_year > tt + ANTICIPATION &
                       units$treatment_year != g))
  out <- units[D == 1L | C == 1L, , drop = FALSE]
  out$D <- D[D == 1L | C == 1L]
  out
}

q_12 <- function(x, p) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else as.numeric(stats::quantile(x, p, names = FALSE))
}

raw_support <- list()
cat_support <- list()
class_rows <- list()
for (i in seq_len(nrow(fail_detail))) {
  ff <- fail_detail[i, ]
  cd <- cell_units_12(as.integer(ff$group), as.integer(ff$time))
  raw_rows <- lapply(VR_RAW_COVARS, function(v) {
    tx <- cd[[v]][cd$D == 1L]
    cx <- cd[[v]][cd$D == 0L]
    tm <- mean(tx, na.rm = TRUE)
    cmin <- min(cx, na.rm = TRUE)
    cmax <- max(cx, na.rm = TRUE)
    data.frame(
      specification = ff$specification,
      group = ff$group,
      time = ff$time,
      event_time = ff$event_time,
      reason = ff$reason,
      covariate = v,
      treated_n = sum(!is.na(tx)),
      control_n = sum(!is.na(cx)),
      treated_min = min(tx, na.rm = TRUE),
      treated_p25 = q_12(tx, 0.25),
      treated_mean = tm,
      treated_p75 = q_12(tx, 0.75),
      treated_max = max(tx, na.rm = TRUE),
      control_min = cmin,
      control_p25 = q_12(cx, 0.25),
      control_mean = mean(cx, na.rm = TRUE),
      control_p75 = q_12(cx, 0.75),
      control_max = cmax,
      treated_mean_outside_control_range = is.finite(tm) &&
        (tm < cmin || tm > cmax),
      treated_range_outside_control_range =
        min(tx, na.rm = TRUE) < cmin || max(tx, na.rm = TRUE) > cmax
    )
  })
  raw_cell <- do.call(rbind, raw_rows)
  raw_support[[length(raw_support) + 1L]] <- raw_cell

  cat_rows <- lapply(levels(panel$vr_common_ipc_cat), function(lev) {
    treated_n <- sum(cd$D == 1L & cd$vr_common_ipc_cat == lev, na.rm = TRUE)
    control_n <- sum(cd$D == 0L & cd$vr_common_ipc_cat == lev, na.rm = TRUE)
    data.frame(
      specification = ff$specification,
      group = ff$group,
      time = ff$time,
      event_time = ff$event_time,
      reason = ff$reason,
      vr_common_ipc_cat = lev,
      treated_n = treated_n,
      control_n = control_n,
      treated_share = treated_n / sum(cd$D == 1L),
      control_share = control_n / sum(cd$D == 0L),
      treated_category_has_zero_control_mass = treated_n > 0L && control_n == 0L
    )
  })
  cat_cell <- do.call(rbind, cat_rows)
  cat_support[[length(cat_support) + 1L]] <- cat_cell

  cat_gap <- any(cat_cell$treated_category_has_zero_control_mass)
  raw_mean_gap <- any(raw_cell$treated_mean_outside_control_range)
  raw_range_gap <- any(raw_cell$treated_range_outside_control_range)
  failure_class <- if (cat_gap) {
    "lack_common_support_categorical"
  } else if (raw_mean_gap) {
    "lack_common_support_raw_moment"
  } else if (grepl("nonpositive_control_mass", ff$reason)) {
    "numerical_nonconvergence_degenerate_control_mass"
  } else if (is.finite(ff$max_abs_mean_difference) &&
             ff$max_abs_mean_difference > LARGE_RESIDUAL_TOL) {
    "numerical_nonconvergence_or_high_moment_stress"
  } else {
    "implementation_issue_unconfirmed"
  }
  class_rows[[length(class_rows) + 1L]] <- data.frame(
    specification = ff$specification,
    group = ff$group,
    time = ff$time,
    event_time = ff$event_time,
    reason = ff$reason,
    n_treated = ff$n_treated,
    n_control = ff$n_control,
    max_abs_mean_difference = ff$max_abs_mean_difference,
    control_ess = ff$control_ess,
    max_control_share = ff$max_control_share,
    any_treated_category_zero_control_mass = cat_gap,
    any_treated_mean_outside_control_range = raw_mean_gap,
    any_treated_range_outside_control_range = raw_range_gap,
    failure_class = failure_class
  )
}

raw_support <- do.call(rbind, raw_support)
cat_support <- do.call(rbind, cat_support)
failure_class <- do.call(rbind, class_rows)
write_audit_12(raw_support, "true_failure_raw_covariate_support.csv")
write_audit_12(cat_support, "true_failure_common_ipc_cat_support.csv")
write_audit_12(failure_class, "true_failure_classification.csv")

failure_type_counts <- as.data.frame(table(
  failure_class = failure_class$failure_class,
  specification = failure_class$specification
))
names(failure_type_counts)[3] <- "n_cells"
write_audit_12(failure_type_counts, "true_failure_type_counts.csv")

section_12("Review residual sensitivity")
review <- required_status[required_status$balance_category == "review_residual", ]
tols <- c(1e-4, 5e-4, 1e-3)
sensitivity <- do.call(rbind, lapply(tols, function(tol) {
  accepted <- review[is.finite(review$max_abs_mean_difference) &
                       review$max_abs_mean_difference <= tol, ]
  remaining <- review[is.finite(review$max_abs_mean_difference) &
                        review$max_abs_mean_difference > tol, ]
  data.frame(
    tolerance = tol,
    review_cells_accepted_at_tolerance = nrow(accepted),
    review_cells_remaining_unresolved = nrow(remaining),
    max_residual_accepted = if (nrow(accepted)) max(accepted$max_abs_mean_difference) else NA_real_,
    max_residual_remaining = if (nrow(remaining)) max(remaining$max_abs_mean_difference) else NA_real_,
    affected_specifications_accepted = if (nrow(accepted)) {
      paste(sort(unique(accepted$specification)), collapse = ";")
    } else {
      ""
    },
    affected_specifications_remaining = if (nrow(remaining)) {
      paste(sort(unique(remaining$specification)), collapse = ";")
    } else {
      ""
    }
  )
}))
write_audit_12(sensitivity, "review_residual_tolerance_sensitivity.csv")

validation_retained <- sum(did_structure$event_time >= EVENT_LO &
                             did_structure$event_time <= EVENT_HI &
                             did_structure$finite_att)
categorical_gap_n <- sum(failure_class$any_treated_category_zero_control_mass)
moment_stress_n <- sum(failure_class$failure_class ==
                         "numerical_nonconvergence_or_high_moment_stress")
nonpositive_mass_n <- sum(grepl("nonpositive_control_mass", failure_class$reason))
large_residual_n <- sum(is.finite(failure_class$max_abs_mean_difference) &
                          failure_class$max_abs_mean_difference > LARGE_RESIDUAL_TOL)

proposal_rows <- rbind(
  data.frame(
    failure_type = "validation_latest_cohort_mismatch",
    proposed_revision = "For validation only, compare the custom engine against the did-supported group-time universe after did::pre_process_did.",
    changed_rule = "When no never-treated group exists and control_group='notyettreated', do not require latest cohort cells as treated cells in the did equivalence test.",
    cells_retained = validation_retained,
    cells_excluded = nrow(unmatched),
    identification_tradeoff = "Aligns validation to did's estimand and uses the latest cohort only as comparison support; loses pseudo-pre-period treated diagnostics for that latest cohort."
  ),
  data.frame(
    failure_type = "categorical_common_support_gap",
    proposed_revision = "Coarsen or remove the categorical common-IPC balance constraint, or declare affected cells unsupported.",
    changed_rule = "Do not require exact balance on `factor(vr_common_ipc_cat)` in cells where a treated category has zero control observations unless a coarsening rule is approved.",
    cells_retained = status$n_required_total[1] - categorical_gap_n,
    cells_excluded = categorical_gap_n,
    identification_tradeoff = "Avoids impossible categorical balance but weakens or changes the Verginer-variable transformation sensitivity."
  ),
  data.frame(
    failure_type = "large_residual_true_failure",
    proposed_revision = "Declare large-residual ebal cells unsupported unless covariates are coarsened or the cell is excluded before estimation.",
    changed_rule = "Exclude required ebal cells with max residual above LARGE_RESIDUAL_TOL until a prespecified coarsening or trimming rule is approved.",
    cells_retained = status$n_required_total[1] - large_residual_n,
    cells_excluded = large_residual_n,
    identification_tradeoff = "Preserves exact balance standards but changes event-time/cohort composition toward supported cells."
  ),
  data.frame(
    failure_type = "nonpositive_control_mass",
    proposed_revision = "Declare nonpositive-control-mass cells unsupported.",
    changed_rule = "Exclude cells where the entropy-balancing solver returns nonpositive or undefined control mass.",
    cells_retained = status$n_required_total[1] -
      nonpositive_mass_n,
    cells_excluded = nonpositive_mass_n,
    identification_tradeoff = "Avoids using degenerate weights; identifies effects only where the donor pool can receive positive mass."
  ),
  data.frame(
    failure_type = "moment_stress_without_categorical_gap",
    proposed_revision = "Keep these cells unresolved unless an approved solver or covariate-scaling diagnostic shows the remaining large residual is numerical rather than support-driven.",
    changed_rule = "Retain the current cell and sample definition, but require a successful ebal solve or a prespecified fallback before outcome estimation.",
    cells_retained = status$n_required_total[1] - moment_stress_n,
    cells_excluded = moment_stress_n,
    identification_tradeoff = "Avoids post hoc solver relaxation; may drop late thin-control cells if no numerical fix is approved."
  ),
  data.frame(
    failure_type = "review_residual",
    proposed_revision = "Choose a prespecified numerical acceptance tolerance, or leave review residual cells unresolved.",
    changed_rule = "Possible tolerances are audited at 1e-4, 5e-4, and 1e-3; no tolerance is implemented here.",
    cells_retained = NA_integer_,
    cells_excluded = NA_integer_,
    identification_tradeoff = "A higher tolerance retains more cells but accepts small remaining covariate imbalance as approximation error."
  )
)
write_audit_12(proposal_rows, "diagnostic_revision_options.csv")

diagnostic_note <- file.path(NOTES_DIR, "verginer_ebal_diagnostic_checkpoint.md")
max_true <- max(failure_class$max_abs_mean_difference, na.rm = TRUE)
failure_counts <- aggregate(n_cells ~ failure_class, failure_type_counts, sum)
failure_count_lines <- paste0(
  "- ", failure_counts$failure_class, ": ", failure_counts$n_cells,
  collapse = "\n"
)
sensitivity_lines <- paste0(
  "- `", sensitivity$tolerance, "`: accepts ",
  sensitivity$review_cells_accepted_at_tolerance,
  ", leaves ", sensitivity$review_cells_remaining_unresolved,
  ", max accepted residual ",
  sprintf("%.4g", sensitivity$max_residual_accepted),
  ".",
  collapse = "\n"
)
note <- c(
  "# Verginer Ebal Diagnostic Checkpoint",
  "",
  "Run status: **DIAGNOSIS ONLY**. No outcome estimation, final mode, staging, commit, or push was run.",
  "",
  "## Validation Mismatch",
  "",
  sprintf("The installed `did` package is version `%s`.", support_rule$did_version[1]),
  "The reproducible audit points to a specific support rule in `did:::pre_process_did()`: when there is no never-treated group and `control_group = \"notyettreated\"`, the latest treated cohort is not included in the estimated `glist` and periods at or after that cohort's treatment year are removed from the support universe.",
  sprintf("In this data, there is no never-treated group, the latest cohort is `%s`, and `did`'s preprocessed `glist` excludes `%s`.",
          latest_g, latest_g),
  sprintf("The four custom-only cells are cohort 2014 pre-period cells; see `%s`.",
          "did_custom_eligibility_comparison.csv"),
  "",
  "## True Feasibility Failures",
  "",
  sprintf("There are `%s` true ebal failures among `%s` required cells; the maximum true-failure residual is `%.4g`.",
          status$n_required_true_feasibility_failures[1],
          status$n_required_total[1],
          max_true),
  failure_count_lines,
  "",
  "The covariate-level support audit reports treated and control support for all four raw covariates and all `vr_common_ipc_cat` categories for every failed cell. The current classification finds no confirmed implementation issue; the failures are classified as support or numerical/degenerate-weight problems pending design approval.",
  sprintf("A treated `vr_common_ipc_cat` category has zero control observations in `%s` failed cells. `%s` failed cells have large residuals above `1e-2`, and `%s` cells have nonpositive control mass.",
          categorical_gap_n, large_residual_n, nonpositive_mass_n),
  "",
  "## Review Residual Sensitivity",
  "",
  sprintf("There are `%s` unresolved review-residual cells; the maximum review residual is `%.4g`.",
          status$n_required_review_residual[1],
          status$max_required_review_residual[1]),
  sensitivity_lines,
  "",
  "I do not recommend accepting a tolerance automatically. The largest review residual is small in absolute units, but a tolerance decision should be prespecified and justified as numerical approximation, not used after seeing outcome estimates.",
  "",
  "## Decision Options",
  "",
  "1. Align validation to the `did` support universe after `pre_process_did()`: retain 215 validation cells and exclude the 4 latest-cohort custom-only cells from the equivalence test.",
  "2. Treat large-residual true failures as unsupported cells unless a prespecified covariate coarsening/trimming rule is approved.",
  "3. Treat nonpositive-control-mass cells as unsupported donor-pool failures.",
  "4. Choose one review-residual tolerance from the sensitivity audit, or keep all 117 review-residual cells unresolved.",
  "",
  "The existing feasibility block remains in place."
)
writeLines(note, diagnostic_note)

banner_12("12f diagnosis complete")
message("Diagnostic checkpoint: ", diagnostic_note)
