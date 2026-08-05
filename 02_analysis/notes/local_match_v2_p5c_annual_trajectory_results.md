# P5c annual-trajectory implementation results

Run completed: 2026-07-27

## Design implemented

P5c preserves the finalized P5a U2-clean support roster and replaces only the
final cohort-level entropy weights. The production specification was fixed as
`count_active` before the corrected run and balances:

- annual patent counts at `t=-5,-4,-3,-2,-1`;
- annual active-patenting indicators at `t=-5,-4,-3,-2,-1`;
- career age and focal-group exclusivity;
- the three frozen firm-level balance variables.

No pre-period earlier than `t=-5` was used. No post-treatment outcome or
treatment-effect estimate was read during the probe or production solve.

## Feasibility probe

| Cohort | Variant | Feasible | Reuse-adjusted ESS ratio | Maximum annual-count SMD | Maximum active-rate SMD |
|---:|---|:---:|---:|---:|---:|
| 2000 | count only | yes, exact | 0.7603 | 1.4e-14 | 0.0639 |
| 2000 | count + active | yes, exact | 0.7507 | 9.2e-15 | 8.8e-15 |
| 2005 | count only | yes, exact | 4.9103 | 5.9e-09 | 0.0426 |
| 2005 | count + active | yes, exact | 4.8531 | 1.1e-09 | 2.8e-10 |

Adding the five active-patenting constraints eliminates the remaining
extensive-margin imbalance at a small ESS cost. `count_only` is retained as a
feasibility diagnostic; it was not used to select the production variant after
opening results.

Both equal-deal probe cells (cohorts 2000 and 2005) were infeasible under both
variants. A separate run established that exact equal-deal `count_active`
balance is feasible in every other cohort (15/15). Its minimum
reuse-adjusted ESS ratio is 0.5923. Equal-deal P5c can therefore be reported
for those 15 cohorts, with 2000 and 2005 explicitly excluded rather than
generalising two failed probes to the full design.

## Full production

- 17 of 17 cohorts completed.
- Every cohort used exact entropy balance; no approximate rung was needed.
- The frozen roster remains 500,906 rows:
  - 27,078 supported treated-inventor rows;
  - 473,828 stacked control rows.
- Minimum reuse-adjusted ESS ratio: 0.7507 (cohort 2000).
- Maximum constrained annual-count SMD: 8.61e-08.
- Maximum constrained active-rate SMD: 3.21e-08.
- Maximum reuse-adjusted control-inventor weight share: 0.00995.
- Maximum cohort treated/control weight-mass difference: 6.62e-11.
- Maximum treated-weight change from its prescribed base weight: 0.

Production certification passed all 17 cells and all artifact checks.

## Held-out-year placebo weights

Two additional 17-cohort designs were run and certified without changing the
support roster:

- `loyo_m3` omits patent count and active patenting at `t=-3` while balancing
  both measures at the other four pre-treatment years;
- `loyo_m4` analogously holds out `t=-4`.

All 34 cohort-design cells achieved exact balance on their included
constraints. Their omitted-year P6 coefficients are reported as genuine
placebo diagnostics; the constrained pre-period coefficients are not
falsification tests.

The execution provenance is content-derived rather than hardcoded. Baseline
validation and 11 mutation tooth tests passed, so a source or manifest change
now invalidates the run as intended.

## P6 handoff

The certified P5c P6 roster preserves every P5a roster field and row identity
and replaces only the final weight:

- roster rows: 500,906;
- roster SHA-256:
  `3184aee524bb2dac5a42d83fd86f1b7a80d8d24566787c5a95536ddc2da71315`;
- P5c design hash:
  `528a554b982bdef0e429beee5956776da9db5a15621b2a48c1a9ec9fe2639d03`;
- content-derived P5c execution hash:
  `b64ecb850b840df3163fbe686da7713500be14fd16c83868eece6f3f41d7af02`.

P6 must pin this new roster and design hash in a new additive freeze. The old
P5a/P6 artifacts remain unchanged.

## Interpretation

P5c should be reported beside P5a, not as though the original design never
existed. P5a supplied the genuine pre-trend falsification and failed it. P5c
directly conditions on the complete five-year pre-treatment outcome path and
tests whether the post-treatment result survives that correction.

The five P5c pre-treatment patent-count coefficients are balance-by-
construction diagnostics, not independent evidence for parallel trends. The
important empirical comparison is therefore whether the P5a post-treatment
estimate is stable under P5c, together with the retained P5a pre-trend plot and
the explicit explanation of why P5c was introduced.
