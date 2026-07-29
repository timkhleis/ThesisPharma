# PPSCM second-attempt census result

Date run: 2026-07-29

## Terminal result

The frozen symmetric-landmark census passed every pre-optimization gate and is
certified to proceed to rolling validation. No optimized synthetic-control
weights were estimated, no control-null post-period exercise was run, and no
real post-acquisition outcomes were queried.

## Sample

The symmetric -7/-6 landmark construction identified 11,036 treated inventors
across 242 acquisition deals. The donor side contained 1,345,465 eligible
inventor-cohort rows in 37,723 U2-clean firm-cohorts. The census retained 10,818
treated inventors across 235 deals after the top-20 donor-pool and two-period
hull-support rules:

- treated-inventor coverage: 98.02%;
- retained-deal share: 97.11%;
- retained deals with at least five donors: 235 of 235; and
- selected donors per retained deal: 20.

Relative to attempt 1, symmetric landmark eligibility increased the treated
population from 3,483 to 11,036 inventors and the ultimately supported deal
count from 203 to 235. The new landmark population remains narrower than the
27,078 supported inventors in the full P5c analysis, as intended.

Only 3,494 of the 10,818 retained landmark inventors (32.30%) have any strict
target-company patent during -5 through -1. The full landmark estimator is
therefore an intention-to-exposure design: it preserves symmetric cohort
formation but includes many inventors who detach from the target before the
deal. The paper must report this dilution together with the improved
pre-period fit and present the frozen `symmetric_attached` specification as a
secondary result.

Seven deals fail the two-period hull check, excluding 218 inventors. Deal 69
alone accounts for 201 of them. This is Monsanto Company's 2000 acquisition by
Pharmacia & Upjohn Inc. (`target_value=27,765,956`, stored in thousands and
classified as a big deal). Its treated `log1p` mean at -5 lies 0.1083 below the
nearest boundary of the selected donor interval. The primary sample excludes
the deal; the frozen non-governing sensitivity retains it with its original
top-20 pool.

## Frozen uniform-donor diagnostic

The inventor-weighted uniform-donor gaps in raw annual patents per inventor
were:

| Event time | Treated mean | Uniform donor mean | Gap |
|---:|---:|---:|---:|
| -3 | 0.3187 | 0.2955 | 0.0233 |
| -2 | 0.2508 | 0.2618 | -0.0110 |
| -1 | 0.2202 | 0.2350 | -0.0148 |

The three-period RMSE was 0.0171 and the largest absolute gap was 0.0233. Both
are well inside the frozen census limits of 0.10. The sample gates also passed:
235 retained deals exceeded the minimum of 100, and 98.02% treated-inventor
coverage exceeded the minimum of 80%.

## Interpretation

Attempt 1's failure was not evidence that the data categorically lack
deal-specific synthetic-control support. It was substantially driven by an
asymmetric population definition and additive demeaning. Under the
precommitted symmetric landmark construction, coarse untreated support and
unweighted held-out pre-fit are strong enough to justify the next stage. The
residual -3 anomaly is attenuated from 0.0506 to 0.0233 and now lies within the
frozen tolerance; it is not eliminated.

The uniform estimator already passes the stricter 0.05 validation standard.
Optimization did not produce this improvement. Uniform donors and PPSCM are
therefore co-primary in the next stage, and PPSCM asks whether flexible weights
move the eventual post estimate rather than whether they can rescue pre-fit.

This is not yet evidence that PPSCM itself works. The decisive next test is the
frozen rolling validation in which ridge selection, the partial-pooling
parameter, and donor weights are recomputed within each training fold. The
census result authorizes that validation but says nothing about post-treatment
effects.

## Reproducibility

The certified manifest reports `CERTIFIED_TO_VALIDATE`,
`optimized_weights_estimated=FALSE`, and `post_outcomes_queried=FALSE`.
Artifact hashes, cohort counts, donor-pool edges, distance scalers,
coordinatewise hull checks, and uniform paths are stored under
`P6_PPSCM_V2_SYMMETRIC/stage_c_census`.
