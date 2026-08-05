# Local Match v2: amended initially retained HonestDiD freeze

Frozen on 4 August 2026 before the amended 1993 initially retained
joint-holdout estimate was opened. The full-cohort HonestDiD result and the
main initially retained result were already known. This package propagates the
existing 3 August 2026 selected-group contract to the amended cohort window.

## Design

- Use the certified initially retained S3 population and all 18 cohorts,
  1993--2010.
- Retain the existing selected-group support and base weights.
- Balance patent count and active patenting at -5, -4, and -1.
- Leave patent count and active patenting at -3 and -2 outside the final
  entropy-balance constraints.
- Retain career age, focal-group exclusivity, firm five-year patent stock, and
  firm five-year inventor count.
- Use the same feasibility hierarchy and ESS gate without retuning.
- Estimate the equal average over +1 through +5, with -1 as reference.

This is a selected-group contrast, not a principal-stratum stayer ATT. The
post-treatment retention definition must remain explicit in reporting.

## Inference and HonestDiD

- The 9,999-draw acquisition wild bootstrap remains the governing conventional
  inference for the selected-group estimate.
- HonestDiD uses analytic two-way acquisition/inventor covariance as primary
  and analytic acquisition-cluster covariance as companion.
- Use HonestDiD 0.2.8, `DeltaRM`, C-LF, no sign restriction, seed 20260803,
  and single-threaded evaluation.
- Search Mbar in 0.05 steps through 0.50, extending to 1 only if required;
  refine the crossing bracket in 0.005 steps at 500 and 1,000 inversion
  points. The two breakdowns must agree within 0.01.
- Weight-estimation uncertainty is not propagated.

The former 1994--2010 selected-group result is used only as an internal
reproduction check. Event estimates and the post average must agree within
0.001, and the breakdown must agree within 0.01. It is not routinely
co-reported. No smoothness or LOYO HonestDiD analysis is authorized.
