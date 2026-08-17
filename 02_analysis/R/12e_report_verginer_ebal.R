# ============================================================================
# 12e_report_verginer_ebal.R -- Figures and checkpoint note
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "12a_verginer_ebal_config.R"))
required_packages_12(c("ggplot2"))

args <- commandArgs(trailingOnly = TRUE)
RUN_MODE <- run_mode_12(args)
BITERS <- bootstrap_iters_12(RUN_MODE)

banner_12(sprintf("12e: Report Verginer ebal (%s)", RUN_MODE))

status_path <- file.path(RESULTS_DIR, "feasibility_status.csv")
dynamic_path <- file.path(RESULTS_DIR, "event_study_dynamic.csv")
if (file.exists(status_path) && !file.exists(dynamic_path)) {
  status <- utils::read.csv(status_path, stringsAsFactors = FALSE)
  sample_flow <- utils::read.csv(file.path(AUDIT_DIR, "estimation_sample_flow.csv"),
                                 stringsAsFactors = FALSE)
  cell_equiv <- utils::read.csv(file.path(AUDIT_DIR, "cell_engine_equivalence.csv"),
                                stringsAsFactors = FALSE)
  req_fail <- utils::read.csv(file.path(AUDIT_DIR, "group_time_required_failures.csv"),
                              stringsAsFactors = FALSE)
  residual_summary <- utils::read.csv(file.path(AUDIT_DIR, "group_time_residual_summary.csv"),
                                      stringsAsFactors = FALSE)
  problem_cells <- utils::read.csv(file.path(AUDIT_DIR, "group_time_problem_cell_diagnostics.csv"),
                                   stringsAsFactors = FALSE)
  unmatched <- utils::read.csv(file.path(AUDIT_DIR, "cell_engine_unmatched_cells.csv"),
                               stringsAsFactors = FALSE)
  by_spec <- as.data.frame(table(specification = req_fail$specification))
  spec_n <- function(spec) {
    out <- by_spec$Freq[match(spec, by_spec$specification)]
    ifelse(is.na(out), 0L, out)
  }
  residual_n <- function(category) {
    sum(residual_summary$n_required_cells[
      residual_summary$balance_category == category
    ], na.rm = TRUE)
  }
  unmatched_reason <- if (nrow(unmatched) > 0L) {
    paste(unique(unmatched$did_nonfinite_reason), collapse = "; ")
  } else {
    "none"
  }
  unmatched_interpretation <- if (nrow(unmatched) > 0L) {
    paste(unique(unmatched$validation_interpretation), collapse = "; ")
  } else {
    "supported cell keys match"
  }
  unmatched_cells <- if (nrow(unmatched) > 0L) {
    paste(
      paste0(unmatched$group, "/", unmatched$time, " e=", unmatched$event_time,
             " pre=", unmatched$custom_pre_time,
             " N_t=", unmatched$custom_n_treated,
             " N_c=", unmatched$custom_n_control,
             " did_e={", unmatched$did_group_event_times_returned, "}"),
      collapse = "; "
    )
  } else {
    "none"
  }
  category_total <- status$n_required_exact_pass[1] +
    status$n_required_solver_tolerance_residual[1] +
    status$n_required_review_residual[1] +
    status$n_required_true_feasibility_failures[1]
  maxdiff <- suppressWarnings(as.numeric(sub(
    ".*maxdiff_([0-9.eE+-]+).*", "\\1", req_fail$reason
  )))
  large_problem <- problem_cells[
    problem_cells$balance_category == "true_feasibility_failure" &
      is.finite(problem_cells$max_abs_mean_difference) &
      problem_cells$max_abs_mean_difference > LARGE_RESIDUAL_TOL,
    , drop = FALSE
  ]
  note <- c(
    "# Verginer-Variable Entropy-Balanced Reconstruction",
    "",
    paste0("Run status: **", RUN_MODE, " FEASIBILITY BLOCKED** (stopped before outcome estimation and bootstrap)."),
    "",
    "This is a separate literature-comparison exercise. It does not alter the completed main design or its weights.",
    "",
    "## Sample",
    "",
    sprintf("- Starting merged-sample inventors/deals: %s / %s.",
            sample_flow$n_inventors[1], sample_flow$n_deals[1]),
    sprintf("- Locked complete-case inventors/deals: %s / %s.",
            sample_flow$n_inventors[2], sample_flow$n_deals[2]),
    sprintf("- Excluded inventor share: %.3f.", sample_flow$excluded_share_from_start[2]),
    "",
    "## Validation",
    "",
    sprintf("- Explicit cell engine versus finite `did::att_gt()` overlap max discrepancy: %.3e.",
            cell_equiv$max_abs_difference[1]),
    sprintf("- `1e-8` overlap gate passed: %s.", cell_equiv$pass_overlap_1e_8[1]),
    sprintf("- Supported cell-key equality passed: %s.", cell_equiv$supported_key_equality[1]),
    sprintf("- Unmatched custom/did cells: %s / %s.",
            cell_equiv$n_custom_only_cells[1], cell_equiv$n_did_only_cells[1]),
    sprintf("- Unmatched-cell reason: %s.", unmatched_reason),
    sprintf("- Unmatched custom cells: %s.", unmatched_cells),
    sprintf("- Validation interpretation: %s.", unmatched_interpretation),
    "",
    "## Feasibility Result",
    "",
    sprintf("- Required cells total: %s; category-count sum: %s; reconciles: %s.",
            status$n_required_total[1], category_total,
            status$required_category_counts_reconcile[1]),
    sprintf("- Exact-pass required cells: %s.", status$n_required_exact_pass[1]),
    sprintf("- Solver-tolerance residual required cells (`>%g` and `<=%g`): %s.",
            BALANCE_TOL, SOLVER_RESIDUAL_TOL,
            status$n_required_solver_tolerance_residual[1]),
    sprintf("- Review-residual required cells (`>%g` and `<=%g`): %s.",
            SOLVER_RESIDUAL_TOL, LARGE_RESIDUAL_TOL,
            status$n_required_review_residual[1]),
    sprintf("- Maximum review residual among required cells: %.4g.",
            status$max_required_review_residual[1]),
    sprintf("- True feasibility failures among required cells: %s.",
            status$n_required_true_feasibility_failures[1]),
    sprintf("- VR2 raw-variable true failures: %s.",
            spec_n("VR2_entropy_balanced")),
    sprintf("- VR2B logged/categorical true failures: %s.",
            spec_n("VR2B_logged_categorical")),
    sprintf("- True failures with residual above `%g`: %s.",
            LARGE_RESIDUAL_TOL, nrow(large_problem)),
    if (length(maxdiff) && any(is.finite(maxdiff))) {
      sprintf("- Maximum recorded balance discrepancy among true failures: %.4f.",
              max(maxdiff, na.rm = TRUE))
    } else {
      "- Maximum recorded balance discrepancy among true failures: not applicable."
    },
    "",
    "Outcome estimation remains blocked by three separate issues: true feasibility failures, unresolved review residuals, and the unresolved unmatched-cell validation explanation. Review residuals require a documented and approved substantive tolerance before they can enter outcome estimation. The four custom-only cells are not treated as explained until a specific `did::att_gt()` support rule is identified and documented. Numerical solver-tolerance residuals are retained in diagnostics but are not treated as support failures.",
    "",
    "The citation outcome uses OECD five-year forward citations and is not numerically identical to Verginer and Riccaboni's citation window.",
    "",
    "## Diagnostics",
    "",
    "- `02_analysis/output/audit/verginer_ebal/group_time_required_failures.csv`",
    "- `02_analysis/output/audit/verginer_ebal/group_time_problem_cell_diagnostics.csv`",
    "- `02_analysis/output/audit/verginer_ebal/group_time_required_cell_status.csv`",
    "- `02_analysis/output/audit/verginer_ebal/group_time_residual_summary.csv`",
    "- `02_analysis/output/audit/verginer_ebal/group_time_balance.csv`",
    "- `02_analysis/output/audit/verginer_ebal/group_time_weight_diagnostics.csv`",
    "- `02_analysis/output/audit/verginer_ebal/cell_engine_unmatched_cells.csv`",
    "- `02_analysis/output/audit/verginer_ebal/cell_engine_equivalence.csv`"
  )
  writeLines(note, CHECKPOINT_NOTE)
  banner_12("12e feasibility checkpoint complete")
  message("Checkpoint: ", CHECKPOINT_NOTE)
  quit(save = "no", status = 0L)
}

dynamic <- utils::read.csv(file.path(RESULTS_DIR, "event_study_dynamic.csv"),
                           stringsAsFactors = FALSE)
summary_att <- utils::read.csv(file.path(RESULTS_DIR, "summary_att.csv"),
                               stringsAsFactors = FALSE)
comparison <- utils::read.csv(file.path(RESULTS_DIR, "verginer_paper_comparison.csv"),
                              stringsAsFactors = FALSE)
balance <- utils::read.csv(file.path(AUDIT_DIR, "group_time_balance.csv"),
                           stringsAsFactors = FALSE)
wd <- utils::read.csv(file.path(AUDIT_DIR, "group_time_weight_diagnostics.csv"),
                      stringsAsFactors = FALSE)
sample_flow <- utils::read.csv(file.path(AUDIT_DIR, "estimation_sample_flow.csv"),
                               stringsAsFactors = FALSE)
success <- utils::read.csv(file.path(RESULTS_DIR, "bootstrap_success_by_specification.csv"),
                           stringsAsFactors = FALSE)
feasibility <- utils::read.csv(file.path(RESULTS_DIR, "feasibility_status.csv"),
                               stringsAsFactors = FALSE)
support_counts <- utils::read.csv(file.path(AUDIT_DIR, "supported_cell_counts_by_specification.csv"),
                                  stringsAsFactors = FALSE)
support_comp <- utils::read.csv(file.path(AUDIT_DIR, "supported_cell_composition_by_event_time.csv"),
                                stringsAsFactors = FALSE)
support_universe <- utils::read.csv(file.path(AUDIT_DIR, "did_support_universe_alignment.csv"),
                                    stringsAsFactors = FALSE)
remaining_failures <- utils::read.csv(file.path(AUDIT_DIR, "group_time_required_failures.csv"),
                                      stringsAsFactors = FALSE)

plot_dyn <- dynamic[dynamic$specification %in% c("VR0_unadjusted", "VR2_entropy_balanced"), ]
plot_dyn$specification_label <- factor(
  plot_dyn$specification,
  levels = c("VR0_unadjusted", "VR2_entropy_balanced"),
  labels = c("VR0 unadjusted", "VR2 entropy balanced")
)
p1 <- ggplot2::ggplot(plot_dyn, ggplot2::aes(event_time, att, colour = specification_label)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.3) +
  ggplot2::geom_vline(xintercept = -0.5, colour = "grey55", linetype = "dashed") +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = simul_low, ymax = simul_high, fill = specification_label),
    alpha = 0.12, colour = NA
  ) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.4) +
  ggplot2::facet_wrap(~ outcome_label, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = EVENT_WINDOW) +
  ggplot2::labs(x = "Years relative to treatment year",
                y = "ATT", colour = "Specification", fill = "Specification",
                title = "Verginer-variable entropy balancing",
                subtitle = paste(RUN_MODE, "run with", BITERS, "deal-cluster bootstrap draws")) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(legend.position = "bottom",
                 panel.grid.minor = ggplot2::element_blank(),
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
ggplot2::ggsave(file.path(FIGS_DIR, "event_study_unadjusted_vs_ebal.png"),
                p1, width = 10, height = 6, dpi = 300, bg = "white")

overall <- summary_att[summary_att$summary == "overall_post_t1_to_t5", ]
p2 <- ggplot2::ggplot(overall, ggplot2::aes(specification, att, colour = specification)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  ggplot2::geom_pointrange(ggplot2::aes(ymin = ci_low, ymax = ci_high), linewidth = 0.4) +
  ggplot2::facet_wrap(~ outcome_label, scales = "free_y", ncol = 2) +
  ggplot2::coord_flip() +
  ggplot2::labs(x = NULL, y = "Mean ATT, event years 1 to 5",
                title = "Overall post-treatment comparison") +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(legend.position = "none",
                 panel.grid.minor = ggplot2::element_blank(),
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
ggplot2::ggsave(file.path(FIGS_DIR, "overall_att_comparison.png"),
                p2, width = 9, height = 6, dpi = 300, bg = "white")

p3 <- ggplot2::ggplot(balance, ggplot2::aes(event_time, max_abs_mean_difference,
                                           colour = specification)) +
  ggplot2::geom_hline(yintercept = BALANCE_TOL, linetype = "dashed", colour = "grey50") +
  ggplot2::geom_point(alpha = 0.5, size = 1) +
  ggplot2::scale_y_log10() +
  ggplot2::labs(x = "Event time", y = "Max absolute weighted mean difference",
                title = "Group-time entropy-balance constraints") +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(legend.position = "bottom",
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
ggplot2::ggsave(file.path(FIGS_DIR, "verginer_covariate_balance.png"),
                p3, width = 8, height = 5, dpi = 300, bg = "white")

p4 <- ggplot2::ggplot(wd, ggplot2::aes(event_time, control_ess, colour = specification)) +
  ggplot2::geom_hline(yintercept = 50, linetype = "dashed", colour = "grey50") +
  ggplot2::geom_point(alpha = 0.45, size = 1) +
  ggplot2::labs(x = "Event time", y = "Control effective sample size",
                title = "Group-time control support") +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(legend.position = "bottom",
                 plot.background = ggplot2::element_rect(fill = "white", colour = NA))
ggplot2::ggsave(file.path(FIGS_DIR, "group_time_ess.png"),
                p4, width = 8, height = 5, dpi = 300, bg = "white")

pat <- comparison[comparison$outcome == "log1p_patents", ]
pre <- utils::read.csv(file.path(RESULTS_DIR, "pretrend_diagnostics.csv"),
                       stringsAsFactors = FALSE)
vr0_pat <- pat$att[pat$specification == "VR0_unadjusted"]
vr1_pat <- pat$att[pat$specification == "VR1_DR_four_variables"]
vr2_pat <- pat$att[pat$specification == "VR2_entropy_balanced"]
min_ess <- min(wd$control_ess, na.rm = TRUE)
max_share <- max(wd$max_control_share, na.rm = TRUE)
success_min <- min(success$success_share, na.rm = TRUE)

note <- c(
  "# Verginer-Variable Entropy-Balanced Reconstruction",
  "",
  paste0("Run status: **", RUN_MODE, "** (", BITERS,
         " prespecified deal-cluster bootstrap draws)."),
  "",
  "This is a separate literature-comparison exercise. It does not alter the completed main design or its weights.",
  "",
  "## Sample",
  "",
  sprintf("- Starting merged-sample inventors/deals: %s / %s.",
          sample_flow$n_inventors[1], sample_flow$n_deals[1]),
  sprintf("- Locked complete-case inventors/deals: %s / %s.",
          sample_flow$n_inventors[2], sample_flow$n_deals[2]),
  sprintf("- Excluded inventor share: %.3f.", sample_flow$excluded_share_from_start[2]),
  "",
  "## Main Answers",
  "",
  sprintf("1. Entropy balancing changes the pre-treatment pattern as shown in `event_study_unadjusted_vs_ebal.png`; the largest reported pre-period absolute ATT is %.4f for VR0 and %.4f for VR2.",
          max(abs(pre$max_abs_pre_att[pre$specification == "VR0_unadjusted"]), na.rm = TRUE),
          max(abs(pre$max_abs_pre_att[pre$specification == "VR2_entropy_balanced"]), na.rm = TRUE)),
  sprintf("2. For patents, the mean post-treatment ATT moves from %.4f in complete-case VR0 to %.4f in VR1 and %.4f in VR2.",
          vr0_pat, vr1_pat, vr2_pat),
  "3. The decomposition table separates the existing full-sample estimate, the complete-case restriction, ordinary four-variable DR adjustment, and entropy balancing.",
  sprintf("4. Minimum group-time control ESS is %.2f and maximum single-control share is %.3f; see `group_time_ess.png` and weight diagnostics.", min_ess, max_share),
  "5. Movement toward Verginer and Riccaboni is reported as a diagnostic comparison, not as evidence that the balanced specification is better.",
  "",
  "The citation outcome uses OECD five-year forward citations and is not numerically identical to Verginer and Riccaboni's citation window.",
  "",
  "## Bootstrap",
  "",
  sprintf("The minimum bootstrap success share across specifications is %.3f.", success_min),
  "",
  "## Generated Figures",
  "",
  "- `02_analysis/output/figures/verginer_ebal/event_study_unadjusted_vs_ebal.png`",
  "- `02_analysis/output/figures/verginer_ebal/overall_att_comparison.png`",
  "- `02_analysis/output/figures/verginer_ebal/verginer_covariate_balance.png`",
  "- `02_analysis/output/figures/verginer_ebal/group_time_ess.png`"
)
writeLines(note, CHECKPOINT_NOTE)

count_line_12 <- function(spec) {
  row <- support_counts[support_counts$specification == spec, , drop = FALSE]
  sprintf("- `%s`: %s supported of %s required cells; %s unsupported; %s exact, %s accepted numerical approximations; max accepted residual %.4g.",
          spec, row$n_supported_cells[1], row$n_required_cells[1],
          row$n_unsupported_cells[1], row$n_exact_pass[1],
          row$n_accepted_numerical_approximation[1],
          row$max_accepted_residual[1])
}
unsupported_comp <- support_comp[support_comp$n_unsupported_cells > 0, , drop = FALSE]
unsupported_lines <- if (nrow(unsupported_comp)) {
  paste0(
    "- `", unsupported_comp$specification, "`, event `",
    unsupported_comp$event_time, "`: ",
    unsupported_comp$n_unsupported_cells,
    " unsupported cell(s), cohorts `",
    unsupported_comp$unsupported_groups, "`."
  )
} else {
  "- None."
}
decision_note <- c(
  "# Verginer Ebal Design-Decision Checkpoint",
  "",
  paste0("Run status: **", RUN_MODE, "** with ", BITERS,
         " prespecified deal-cluster bootstrap draws."),
  "",
  "## Approved Development Design",
  "",
  sprintf("- Custom cells are aligned to installed `did` 2.5.0 support: `%s`.",
          support_universe$support_rule[1]),
  sprintf("- Latest treated cohort excluded from treated-cell universe: `%s`; retained as an eligible not-yet-treated control where calendar-time rules allow.",
          support_universe$excluded_latest_treated_group[1]),
  sprintf("- Supported treated-cell years run from `%s` to `%s`.",
          support_universe$support_year_min[1],
          support_universe$support_year_max[1]),
  sprintf("- Entropy-balance residuals at or below `%g` are accepted numerical approximations.",
          feasibility$numerical_acceptance_tolerance[1]),
  "- `vr_common_ipc_cat` is unchanged; no coarsening or removal was implemented.",
  "",
  "## Supported Cell Counts",
  "",
  count_line_12("VR2_entropy_balanced"),
  count_line_12("VR2B_logged_categorical"),
  "",
  "## Unsupported Cell Composition",
  "",
  unsupported_lines,
  "",
  sprintf("Remaining unsupported specification-cells: `%s`.",
          nrow(remaining_failures)),
  "",
  "## Result Files",
  "",
  "- `02_analysis/output/results/verginer_ebal/group_time_point_estimates.csv`",
  "- `02_analysis/output/results/verginer_ebal/event_study_dynamic.csv`",
  "- `02_analysis/output/results/verginer_ebal/summary_att.csv`",
  "- `02_analysis/output/results/verginer_ebal/bootstrap_success_by_specification.csv`",
  "- `02_analysis/output/results/verginer_ebal/bootstrap_failure_by_group.csv`",
  "- `02_analysis/output/audit/verginer_ebal/supported_cell_counts_by_specification.csv`",
  "- `02_analysis/output/audit/verginer_ebal/supported_cell_composition_by_event_time.csv`"
)
writeLines(decision_note, DESIGN_DECISION_NOTE)

banner_12("12e complete")
message("Checkpoint: ", CHECKPOINT_NOTE)
message("Design-decision checkpoint: ", DESIGN_DECISION_NOTE)
