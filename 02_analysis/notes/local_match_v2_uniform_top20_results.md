# Uniform top-20 symmetric-landmark results

Date run: 2026-07-29
Design: `P6_UNIFORM_TOP20_SYMMETRIC_V1`

## Terminal result

The fixed uniform top-20 estimator passes pre-period validation but fails the
precommitted control-null gate. The branch therefore stops without querying
real treated post-acquisition outcomes. It produces no uniform post ATT,
same-sample Verginer estimate, or HonestDiD sensitivity result.

## Pre-period validation

The design retains 10,818 treated inventors across 235 deals and gives each
deal's 20 selected donor-firm cohorts weight 1/20. The inventor-weighted
held-out gaps are:

| Event time | Treated mean | Uniform donor mean | Gap |
|---:|---:|---:|---:|
| -3 | 0.3187 | 0.2955 | 0.0233 |
| -2 | 0.2508 | 0.2618 | -0.0110 |
| -1 | 0.2202 | 0.2350 | -0.0148 |

The three-period RMSE is 0.0171 and the largest absolute gap is 0.0233.
The joint test gives **p = 0.156**, above the frozen 0.10 threshold. The
effective treated-deal count is 30.23. The largest leave-one-cohort-out gap is
0.0326, and the largest gap after deleting one of the ten most influential
deals is 0.0309. All eight governing validation checks pass.

The equal-deal diagnostic does not pass the corresponding absolute-fit
standard: its RMSE is 0.0687 and its largest gap is 0.1075. This diagnostic was
explicitly declared non-governing before the joint test because it estimates
the average acquisition rather than the average treated inventor. It limits
the scope of the result: the good pre-fit is specific to the
inventor-weighted estimand.

## Control-null calibration

The pipeline completed all 499 frozen pseudo-treatment draws using only
acquisition-clean control inventors. Donors were ranked against the full
within-cohort eligible universe using the original scalar and technological
distance. The largest selected donor rank after excluding pseudo-treated firms
was 33, well inside the exact 256-rank cache. Assignment and donor pools were
disjoint within every draw.

Only 150 of 499 draws are inference-comparable, below the required 400:

| Comparability condition | Passing draws |
|---|---:|
| Supported inventor volume | 159 |
| Nominal deal count | 499 |
| Effective deal count | 485 |
| Maximum deal-weight share | 486 |
| All conditions jointly | 150 |

Supported pseudo-treated volume is the binding problem. Its mean is 87.31% of
the real treated volume, below the frozen 90% lower bound; draw-level ratios
range from 70.84% to 117.08%. The hull and support rules therefore generate too
few real-sample-sized placebo experiments for the planned calibration.

Among the 150 comparable draws:

- the mean pseudo-ATT is 0.0118 patents per inventor-year;
- its Monte Carlo 95% interval is [0.0084, 0.0152], wholly inside the frozen
  [-0.05, 0.05] equivalence band;
- 8 of 150 draws reject at 5%, a rejection share of 5.33%; and
- the exact binomial 95% interval is [2.33%, 10.24%].

The false-rejection interval contains 5%, but its upper endpoint exceeds the
frozen 10% ceiling by 0.24 percentage points. This is a second governing
failure. The small positive mean is also systematic—the Monte Carlo interval
does not include zero—even though its magnitude passes the frozen equivalence
criterion.

Mean pseudo-effects at +1 through +5 range from 0.0066 to 0.0150, all inside
the equivalence band.

## Interpretation

Uniform weighting solves the narrow held-out pre-fit problem. It does not
complete the stronger validation sequence needed for a new causal estimate.
The control-null failure is not evidence of a large mechanical pseudo-effect:
placebo effects are small and the rejection share is close to 5%. The failure
is that the acquisition-clean control universe does not reliably reproduce
the real landmark sample's supported inventor volume under the frozen
assignment and hull rules, leaving too few comparable draws to certify
calibration. The exact false-rejection interval then narrowly misses its
ceiling.

The thesis may report the uniform pre-period construction result:

> Equal weighting of the 20 prespecified donor firms closely tracks the
> inventor-weighted treated trajectory in held-out pre-acquisition years
> (RMSE 0.017; joint p = 0.156). A stricter control-only pipeline calibration
> does not certify a post-treatment uniform-donor estimate because only 150 of
> 499 pseudo-experiments reproduce the real design's sample and cluster
> structure.

The thesis should not report or imply a uniform-donor post-acquisition ATT.
Changing the pseudo-assignment rule, volume bound, required draw count, or
false-rejection ceiling after observing these results would be
post-outcome specification search.

## Reproducibility

The freeze is
`local_match_v2_uniform_top20_freeze.md`, with SHA-256
`263494b2380dedcc1dd1bf832ff4570f1d9b84555edb7c819f905cd2043b5ce6`.

Validation artifacts are under
`P6_UNIFORM_TOP20_SYMMETRIC/stage_b_validation/`. Ten files pass their
recorded SHA-256 checks, and the manifest status is
`CERTIFIED_TO_CONTROL_NULL`.

Control-null artifacts are under
`P6_UNIFORM_TOP20_SYMMETRIC/stage_c_control_null/`. Seven files pass their
recorded SHA-256 checks. The terminal manifest records:

- `completed_draws=499`;
- `inference_comparable_draws=150`;
- `control_post_outcomes_queried=TRUE`;
- `real_post_outcomes_queried=FALSE`;
- `control_null_pass=FALSE`; and
- `status=CONTROL_NULL_FAILED`.

The pseudo assignments and selected donor pools are saved as hashed parquet
files. No stage-D real-post directory was created.
