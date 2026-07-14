# Main DiD v1 Robustness Design Checkpoint

Generated: 2026-07-15 00:04:59 CEST

## Scope

This checkpoint implements Phase 1 only: robustness weights, balance diagnostics, feasibility decisions, and design notes. It does not build outcomes, open `patent_enriched`, run citation checks, or estimate treatment effects.

P0 remains frozen at commit `99923f8`; Phase 1 never overwrites its weights, panel, estimates, or figures.

## Specifications

- `P0`: Frozen primary never-target, full covariates, inventor-weighted ATT.
- `P1`: Never-target, reduced 4x4, inventor-weighted ATT.
- `P2`: Never-target, full covariates, acquirer-clean controls, inventor-weighted ATT.
- `P3`: g+7 future-treated controls, reduced 4x4, inventor-weighted ATT.
- `P4`: g+7 future-treated controls, full covariates, proper deal-weighted ATT.

Reduced 4x4 covariates are firm `log_firm_inventor_count`, `log_patents_recent`, `share_small_molecule`, `share_biotech`; inventor `log_inventor_patent_stock`, `observed_inventor_career_age`, `observed_target_patent_tenure`, `target_exclusivity`.

## Feasibility Decisions

- `P0`: **FROZEN_PRIMARY**. frozen primary benchmark; not reweighted
- `P1`: **INFEASIBLE**. omitted max |SMD| 0.2291 > 0.10; stack mass discrepancy 1.16e-04 > 1.0e-04
- `P2`: **FEASIBLE**. all gates passed
- `P3`: **INFEASIBLE**. 10612 finite but nonpositive weights
- `P4`: **INFEASIBLE**. stack mass discrepancy above 1e-4

## Key Diagnostics

- `P0`: constrained max |SMD| 0.000012; omitted/all max |SMD| NA; max stack-mass discrepancy 0.00007273; treated N 25524; control N 3721005.
- `P1`: constrained max |SMD| 0.00000589; omitted/all max |SMD| 0.229; max stack-mass discrepancy 0.0001161; treated N 25524; control N 3721005.
- `P2`: constrained max |SMD| 0.00000671; omitted/all max |SMD| NA; max stack-mass discrepancy 0.00007334; treated N 25524; control N 3178585.
- `P3`: constrained max |SMD| NA; omitted/all max |SMD| NA; max stack-mass discrepancy NA; treated N 25524; control N 10766.
- `P4`: constrained max |SMD| 0.00000596; omitted/all max |SMD| NA; max stack-mass discrepancy 0.0001533; treated N 25524; control N 10766.

## Control Concentration

- `P0` underlying_control_firm: ESS  102; max share 0.0417; top-five share 0.169.
- `P1` underlying_control_firm: ESS  117; max share 0.038; top-five share 0.152.
- `P2` underlying_control_firm: ESS 74.5; max share 0.057; top-five share 0.213.
- `P3` underlying_control_firm: ESS NA; max share NA; top-five share NA. Not valid: 10612 finite but nonpositive weights.
- `P4` underlying_control_firm: ESS  106; max share 0.0269; top-five share 0.114.
- `P4` future_control_deal: ESS  106; max share 0.0269; top-five share 0.114.

## Unit Comparisons

- `P1` vs P0: shared units 3746529; only in spec 0; only in P0 0.
- `P2` vs P0: shared units 3204109; only in spec 0; only in P0 542420.
- `P3` vs P0: shared units 27042; only in spec 9248; only in P0 3719487.
- `P4` vs P0: shared units 27042; only in spec 9248; only in P0 3719487.

## P4 Contract Self-Test

- unequal_deals_equal_mass: pass (deal masses: 3.5, 3.5).
- firm_size_enters_once: pass (identical-control mass ratio=2.000).
- controls_match_deal_weighted_moments: pass (treated x=0.500000 control x=0.499997).
- treated_not_reset_to_one: pass (treated weight range 0.7000..1.7500).
- global_rescaling_invariant: pass (coef 0.000001134849 vs 0.000001134849).

## g+7 Identity Checks

- real_control_deal_year_minus_stack: pass.
- panel_end_buffer: pass.
- unit_maps_one_real_control_deal: pass.
- deal_maps_one_year_target: pass.

## Mandatory Phase 2 Safeguards

- Check duplicate `patent_enriched` rows for conflicting non-missing `fwd_cits5` values.
- Verify the citation follow-up cutoff without treating the database maximum patent year as full certification.
- Audit citation missingness and missing citation mass among patent-active rows by treatment status.
- Recompute all original balance diagnostics on the restricted citation sample for each feasible specification.
- Keep citation results provisional when raw citing-year histories remain unavailable.

