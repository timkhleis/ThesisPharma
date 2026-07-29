# Uniform top-20 symmetric-landmark design freeze

Freeze date: 2026-07-29
Design label: `P6_UNIFORM_TOP20_SYMMETRIC_V1`

## Purpose and status at freeze

This branch asks whether a transparent, fixed-weight counterfactual corroborates
the main Local Match v2 result. It is independent of the failed partially
pooled synthetic-control branch. It uses no optimized donor weights.

The following facts were already disclosed before this freeze:

- the symmetric-landmark census retains 10,818 treated inventors in 235 deals;
- each retained deal has 20 selected donor-firm cohorts;
- the inventor-weighted uniform-donor validation RMSE over -3 through -1 is
  0.01714 and the largest absolute gap is 0.02328;
- the equal-deal uniform path fits materially worse; and
- only 3,494 retained treated inventors have strict target-company patent
  attachment during -5 through -1.

No joint uniform-donor validation p-value, control-null result, or real
post-treatment uniform-donor outcome has been inspected at this freeze.

## Population and donor architecture

The primary treated population is the certified symmetric-landmark population
from `P6_PPSCM_V2_SYMMETRIC`:

1. treated inventors have target-firm patent evidence at -7 or -6;
2. their latest affiliation during -7/-6 is the target group;
3. each inventor enters at the earliest qualifying acquisition;
4. donor inventors are affiliated with an acquisition-clean control group at
   the same landmark;
5. donor firm-cohorts contain at least five established inventors;
6. candidate donor firms are ranked using only -7 through -4 information;
7. the frozen full screening metric and top-20 cap are used; and
8. retained deals satisfy the two-coordinate hull check at -5 and -4.

The retained deal roster, treated inventor roster, selected donor-firm pools,
screening scalers, and hull decision are immutable inputs. Deal 69 remains
excluded in the primary sample and appears only in the already frozen
non-governing sensitivity.

## Estimator

For deal \(j\), each of its 20 donor-firm cohorts receives weight \(1/20\).
Inventors receive equal weight within their firm-cohort. Let
\(\bar Y_{jt}^{T}\) be the mean patent count among deal \(j\)'s fixed treated
inventor cohort and \(\bar Y_{jkt}^{C}\) the mean for donor firm \(k\). The
deal-time gap is

\[
g_{jt}=\bar Y_{jt}^{T}-\frac{1}{20}\sum_{k=1}^{20}\bar Y_{jkt}^{C}.
\]

The primary path weights deals by their fixed treated-inventor counts:

\[
\widehat g_t=\sum_j
\frac{N_j^T}{\sum_\ell N_\ell^T}g_{jt}.
\]

This is the average gap for a treated inventor. The equal-deal path is a
mandatory companion but is non-governing because it estimates the average
acquisition rather than the average treated inventor. Its known poor -3 fit is
reported, not suppressed.

Patent counts include explicit zero-patent inventor-years. The primary effect
is the unadjusted treated-minus-uniform-donor gap. A -4-referenced
difference-in-differences path is reported only as a companion and supplies
the event-study input for HonestDiD.

## Pre-period validation

Screening uses -5 and -4. Event times -3, -2, and -1 are untouched validation
periods. The validation stage reads only certified -5 through -1 artifacts and
may not connect to the analysis database.

### Joint inference

The joint null is

\[
H_0:\widehat g_{-3}=\widehat g_{-2}=\widehat g_{-1}=0.
\]

The governing p-value uses a 9,999-replication deal-level Webb multiplier
bootstrap with seed `20260730`. Donor weights and the treated-inventor deal
weights are fixed. The bootstrap multiplies centered deal-level influence
vectors and recomputes the joint Wald statistic. A deal-cluster sandwich Wald
test is reported as a companion.

### Governing validation gates

Every gate must pass:

1. all source, freeze, census, roster, selected-pool, and prepanel hashes match;
2. exactly 235 deals and 10,818 treated inventors remain, with exactly 20
   donors per deal;
3. the inventor-weighted validation RMSE is at most 0.05 and every validation
   gap is inside [-0.05, 0.05];
4. the governing joint Webb p-value is greater than 0.10;
5. effective treated-deal count is at least 20;
6. every leave-one-cohort-out validation gap is inside [-0.075, 0.075]; and
7. deleting each of the ten largest absolute deal contributions leaves every
   validation gap inside [-0.075, 0.075].

The maximum treated-deal weight share, equal-deal path, log1p path, and
Deal-69/K/metric sensitivities are mandatory diagnostics but do not alter the
primary pass/fail decision.

Failure of any governing gate terminates this branch. No control post-period
or real post-treatment outcome may then be queried.

## Control-null calibration

If validation passes, the branch runs 499 fixed-seed pseudo-treatment draws
among acquisition-clean control firms. This is pipeline falsification, not
randomization inference for the real ATT and may not be compared with the real
ATT.

For each draw:

1. one pseudo-treated control firm-cohort is assigned to each retained real
   deal within the same acquisition cohort;
2. real deals are processed in descending treated-cohort size, with deal ID as
   the tie-breaker;
3. assignment is without replacement from the 50 control firm-cohorts closest
   in absolute `log1p` cohort size, using a seeded random choice within that
   set;
4. every pseudo-treated firm in the draw is excluded from all donor pools;
5. the original full screening metric, standardization rules, top-20 cap, and
   -5/-4 hull rule are rebuilt;
6. fixed uniform weights are applied; and
7. the average +1 through +5 pseudo-effect and event-time path are estimated.

Each draw uses 999 deal-level Webb bootstrap-t replications for its 5% test.
The master seed is `20260731`; draw and bootstrap seeds are deterministic
functions of the draw ID.

A draw is inference-comparable when:

- supported treated-inventor volume is between 90% and 110% of 10,818;
- nominal supported pseudo-deal count is between 90% and 110% of 235;
- effective pseudo-deal count is between 50% and 200% of the real effective
  count; and
- its maximum pseudo-deal weight share is no greater than twice the real
  maximum share.

At least 400 of 499 draws must be inference-comparable. Among comparable
draws, all governing control-null gates must pass:

1. the 95% Monte Carlo confidence interval for the mean pseudo-ATT lies wholly
   inside [-0.05, 0.05];
2. the exact binomial 95% interval for the 5% rejection share contains 0.05
   and has an upper endpoint no greater than 0.10;
3. the mean pseudo-event coefficient at every event time +1 through +5 lies
   inside [-0.05, 0.05]; and
4. assignment disjointness, no-recentering, no-real-ATT, hash, and result
   certification checks pass.

No draw count, comparability bound, or gate may be changed after control
post-period outcomes are opened.

## Gated real post estimation

Real post-treatment outcomes may be queried only if both validation and
control-null manifests certify passage.

The primary outputs are:

- the raw inventor-weighted event path at 0 through +5;
- the average annual gap over +1 through +5;
- the five-year cumulative gap;
- the uniform-donor mean over +1 through +5; and
- the average annual gap as a percentage of that donor mean.

The governing confidence interval and p-value use a 9,999-replication
deal-level Webb bootstrap-t with seed `20260801`. Deal-cluster analytic
inference is a companion. The equal-deal and -4-referenced paths are
non-governing companions.

## Attached-inventor secondary estimand

The secondary `symmetric_attached` specification requires:

- treated inventors to have a strict target-company patent during -5 through
  -1; and
- donor inventors to have a patent assigned to their own landmark firm during
  the same window.

It retains the primary deal roster and selected donor firms but recomputes
firm-time means on the attached inventor cohorts. It is reported as a
selection-conditioned secondary estimate and cannot replace the full
landmark result.

## Same-sample Verginer comparison

After the real uniform sample is fixed, a Verginer-style entropy estimator is
rebuilt using:

- exactly the same 235 treated deals and 10,818 treated inventors;
- controls drawn only from the union of the same selected donor firm-cohorts;
- cohort-level entropy balance on the five annual patent counts and five
  active-patenting indicators from -5 through -1, career age, and primary IPC
  section shares; and
- no substitution of cohorts, deals, or treated inventors if balance is
  infeasible.

The comparison is apples-to-apples in treated population and available donor
architecture. It remains a cohort-level balancing estimator rather than a
deal-specific synthetic control. Its estimate, control mean, percentage
effect, balance, feasibility, and difference from the uniform estimate are
reported. It does not govern certification of the uniform branch.

## HonestDiD sensitivity

HonestDiD is run only after a certified real post estimate. It uses the
-4-referenced event-study vector, validation leads -3 through -1, post periods
0 through +5, and the deal-cluster covariance matrix. Relative-magnitude
sensitivity is reported over the frozen grid
`Mbar = 0, 0.25, ..., 2.00`, together with the breakdown value at which the
95% confidence interval first contains zero.

HonestDiD is a sensitivity analysis for violations of parallel trends. It is
not another point estimator and cannot rescue a failed validation or
control-null gate.

## Files and stopping rule

The branch uses:

- `40a_lmv2_uniform_top20_config.R`;
- `40b_validate_lmv2_uniform_top20.R`;
- `40c_run_lmv2_uniform_top20_control_null.R`;
- `40d_estimate_lmv2_uniform_top20_post.R`; and
- `40e_report_certify_lmv2_uniform_top20.R`.

Outputs go to
`02_analysis/output/audit/local_match_v2/P6_UNIFORM_TOP20_SYMMETRIC/`.

Terminal interpretations are:

- validation failure: fixed uniform donors do not support a post estimate;
- control-null failure: the fixed pipeline creates systematic pseudo-effects
  or miscalibrated inference;
- both gates pass: report the uniform estimate as transparent complementary
  evidence, followed by the same-sample Verginer comparison and HonestDiD
  sensitivity.
