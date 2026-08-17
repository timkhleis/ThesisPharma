# Verginer-Variable Entropy-Balanced Reconstruction

Run status: **DEVELOPMENT FEASIBILITY BLOCKED** (stopped before outcome estimation and bootstrap).

This is a separate literature-comparison exercise. It does not alter the completed main design or its weights.

## Sample

- Starting merged-sample inventors/deals: 29533 / 348.
- Locked complete-case inventors/deals: 29445 / 339.
- Excluded inventor share: 0.003.

## Validation

- Explicit cell engine versus finite `did::att_gt()` overlap max discrepancy: 1.665e-16.
- `1e-8` overlap gate passed: TRUE.
- Supported cell-key equality passed: FALSE.
- Unmatched custom/did cells: 4 / 0.
- Unmatched-cell reason: unresolved_validation_mismatch_did_att_gt_returned_no_group_time_row.
- Unmatched custom cells: 2014/2009 e=-5 pre=2008 N_t=42 N_c=3897 did_e={NA}; 2014/2010 e=-4 pre=2009 N_t=42 N_c=2406 did_e={NA}; 2014/2011 e=-3 pre=2010 N_t=42 N_c=1384 did_e={NA}; 2014/2012 e=-2 pre=2011 N_t=42 N_c=404 did_e={NA}.
- Validation interpretation: unresolved_validation_mismatch_pending_specific_did_support_rule.

## Feasibility Result

- Required cells total: 430; category-count sum: 430; reconciles: TRUE.
- Exact-pass required cells: 80.
- Solver-tolerance residual required cells (`>1e-06` and `<=1e-05`): 217.
- Review-residual required cells (`>1e-05` and `<=0.01`): 117.
- Maximum review residual among required cells: 0.0008179.
- True feasibility failures among required cells: 16.
- VR2 raw-variable true failures: 2.
- VR2B logged/categorical true failures: 14.
- True failures with residual above `0.01`: 14.
- Maximum recorded balance discrepancy among true failures: 0.4683.

Outcome estimation remains blocked by three separate issues: true feasibility failures, unresolved review residuals, and the unresolved unmatched-cell validation explanation. Review residuals require a documented and approved substantive tolerance before they can enter outcome estimation. The four custom-only cells are not treated as explained until a specific `did::att_gt()` support rule is identified and documented. Numerical solver-tolerance residuals are retained in diagnostics but are not treated as support failures.

The citation outcome uses OECD five-year forward citations and is not numerically identical to Verginer and Riccaboni's citation window.

## Diagnostics

- `02_analysis/output/audit/verginer_ebal/group_time_required_failures.csv`
- `02_analysis/output/audit/verginer_ebal/group_time_problem_cell_diagnostics.csv`
- `02_analysis/output/audit/verginer_ebal/group_time_required_cell_status.csv`
- `02_analysis/output/audit/verginer_ebal/group_time_residual_summary.csv`
- `02_analysis/output/audit/verginer_ebal/group_time_balance.csv`
- `02_analysis/output/audit/verginer_ebal/group_time_weight_diagnostics.csv`
- `02_analysis/output/audit/verginer_ebal/cell_engine_unmatched_cells.csv`
- `02_analysis/output/audit/verginer_ebal/cell_engine_equivalence.csv`
