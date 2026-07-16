# Main DiD v1 Robustness Design Checkpoint

Generated: 2026-07-16 18:43:13 CEST

## Scope

This Phase 1B checkpoint repairs the design horizon and reruns design-only robustness diagnostics. It does not build outcomes, open `patent_enriched`, run citation checks, or estimate treatment effects.

P0 remains the frozen legacy benchmark from commit `99923f8`; its never-target control-inventor contamination screening ended at g+3. P0H5 is the corrected candidate primary never-target design with control-inventor competing acquisitions excluded through g+5.

## Final Design Decisions

| Spec | Roster/estimand | Decision | Principal reason |
| --- | --- | --- | --- |
| P0 | Frozen legacy benchmark | FROZEN | legacy benchmark; control cleanliness originally through g+3 |
| P0H5 | Corrected never-target, inventor ATT | FEASIBLE | all gates passed |
| P1 | Reduced numeric specification on P0H5 | INFEASIBLE | omitted max \|SMD\| 0.2291 > 0.10; stack mass discrepancy 1.19e-04 > 1.0e-04 |
| P2 | No observed acquirer event g-1..g+5 | FEASIBLE | all gates passed |
| P3 | g+7, inventor ATT | INFEASIBLE | firm stage did not converge; inventor stage did not converge; constrained max \|SMD\| 1.1000 > 0.05; omitted max \|SMD\| 0.7669 > 0.10; underlying-firm ESS 1.0 < 50; max underlying-firm share 1.000 > 0.10; empty positive-control stack; stack mass discrepancy 1.02e+02 > 1.0e-04; 10735 zero/numerically zero weights |
| P4 | g+7, deal ATT | FEASIBLE | all post-normalization gates passed |

## P0H5 Contamination Repair

- existing_g_to_g3_hits: 0
- additional_excluded_units_g4_g5:    3109
- excluded_p0_control_weight_mass: 60.8374
- p0_control_units: 3721005
- p0h5_control_units: 3717896
- Additional exclusions by relative year: g+4=1745, g+5=1364.

## P1 Omitted-Covariate Diagnostics

The largest omitted weighted imbalance is `share_formulation`, with weighted SMD 0.2291.
| Covariate | Unweighted SMD | Weighted SMD | Abs weighted SMD | Exceeds 0.10 |
| --- | ---: | ---: | ---: | --- |
| share_formulation | 0.3464 | 0.2291 | 0.2291 | TRUE |
| observed_firm_patent_age | 0.03686 | 0.0767 | 0.0767 | FALSE |
| log_firm_patent_stock | 0.05765 | 0.06949 | 0.06949 | FALSE |
| log_patents_early | -0.0006372 | 0.01926 | 0.01926 | FALSE |
| no_technology_activity_g6_g3 | -0.296 | 0.01694 | 0.01694 | FALSE |
| no_firm_patent_by_g3 | -0.3213 | 0.005334 | 0.005334 | FALSE |

## P2 Acquirer-Clean Diagnostics

- excluded_control_units: 0
- excluded_firm_stack_cells:    1073
- excluded_p0h5_weighted_mass: 0
- remaining_control_units: 3717896

## P3 Positive-Weight Diagnostics

- n_negative_weights: 0
- n_zero_weights:   10735
- n_below_near_zero:     145
- n_positive_weights:     154
- positive_weight_underlying_firms:       1
- stacks_with_zero_positive_control_mass:      14
- max_balance_discrepancy: 1.09999

## P4 Normalization Diagnostics

- Pre-normalization max stack-mass discrepancy: 0.000153333.
- Stack scale factors: min 0.99995, max 1.00015, max absolute deviation from one 0.000153356.

## g+7 Sample Count Reconciliation

- Authoritative current `main_did_v1_units.parquet` control count: 10766.
- The older `10,630` count appears in `main_did_v1_first_results.md` and is a stale memo count from an earlier cleanliness/artifact state.
- The Phase 1B runner uses the current derived artifact and records 10766 g+7 controls for P3/P4.

## Core Diagnostics

- `P0`: max |SMD| all 0.000012; constrained 0.000012; omitted NA; max stack-mass discrepancy 0.0000727293; treated N 25524; control N 3721005.
- `P0H5`: max |SMD| all 0.0000113; constrained 0.0000113; omitted NA; max stack-mass discrepancy 0.0000765254; treated N 25524; control N 3717896.
- `P1`: max |SMD| all 0.229; constrained 0.00000626; omitted 0.229; max stack-mass discrepancy 0.000118684; treated N 25524; control N 3717896.
- `P2`: max |SMD| all 0.0000113; constrained 0.0000113; omitted NA; max stack-mass discrepancy 0.0000765254; treated N 25524; control N 3717896.
- `P3`: max |SMD| all  1.1; constrained  1.1; omitted 0.767; max stack-mass discrepancy 101.651; treated N 25524; control N 10766.
- `P4_pre_norm`: max |SMD| all 0.00000596; constrained 0.00000596; omitted NA; max stack-mass discrepancy 0.000153333; treated N 25524; control N 10766.
- `P4`: max |SMD| all 0.00000592; constrained 0.00000592; omitted NA; max stack-mass discrepancy 0.000000000000000215282; treated N 25524; control N 10766.

## Control Concentration

- `P0` underlying_control_firm: ESS  102; max share 0.0417; top-five share 0.169.
- `P0H5` underlying_control_firm: ESS  102; max share 0.0418; top-five share 0.169.
- `P1` underlying_control_firm: ESS  117; max share 0.038; top-five share 0.152.
- `P2` underlying_control_firm: ESS  102; max share 0.0418; top-five share 0.169.
- `P3` underlying_control_firm: ESS    1; max share    1; top-five share    1.
- `P4_pre_norm` underlying_control_firm: ESS  106; max share 0.0269; top-five share 0.114.
- `P4_pre_norm` future_control_deal: ESS  106; max share 0.0269; top-five share 0.114.
- `P4` underlying_control_firm: ESS  106; max share 0.0269; top-five share 0.114.
- `P4` future_control_deal: ESS  106; max share 0.0269; top-five share 0.114.

## Unit Comparisons

- `P0H5`: shared with P0 3743420; only in spec vs P0 0; only in P0 3109; shared with P0H5 NA; only in spec vs P0H5 NA; only in P0H5 NA.
- `P1`: shared with P0 3743420; only in spec vs P0 0; only in P0 3109; shared with P0H5 3743420; only in spec vs P0H5 0; only in P0H5 0.
- `P2`: shared with P0 3743420; only in spec vs P0 0; only in P0 3109; shared with P0H5 3743420; only in spec vs P0H5 0; only in P0H5 0.
- `P3`: shared with P0 27042; only in spec vs P0 9248; only in P0 3719487; shared with P0H5 27042; only in spec vs P0H5 9248; only in P0H5 3716378.
- `P4`: shared with P0 27042; only in spec vs P0 9248; only in P0 3719487; shared with P0H5 27042; only in spec vs P0H5 9248; only in P0H5 3716378.

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

