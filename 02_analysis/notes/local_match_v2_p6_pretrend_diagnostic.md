# Local Match v2 — P6 pre-trend diagnostic

Diagnostic completed on 2026-07-26. No P5 weight was changed or re-estimated.

## Bottom line

The frozen P5a design does not pass the patent-count or active-patenting
pre-trend test. This is a real design limitation rather than an outcome-panel
or inference-code defect. The failure is concentrated at event time -3, but
it is distributed across cohorts and survives the 1994--2008 censoring-clean
sample.

The post-acquisition patent-count estimate is negative and similar in the
full and censoring-clean samples, but it should not yet be presented as an
unqualified causal headline. A trajectory-augmented P5 design is a plausible
rescue, subject to fresh balance, retention, ESS, and influence checks.

## Evidence

### Dynamic patent-count estimates

Relative to event time -1, the full-sample patent-count leads are:

| Event time | ATT | Two-way SE | 95% CI |
|---:|---:|---:|---:|
| -5 | -0.0218 | 0.0246 | [-0.0702, 0.0267] |
| -4 | -0.0027 | 0.0252 | [-0.0523, 0.0470] |
| -3 | 0.0506 | 0.0188 | [0.0136, 0.0875] |
| -2 | 0.0077 | 0.0163 | [-0.0244, 0.0397] |

Active patenting has the same shape: its event-time -3 coefficient is
0.0287 (95% CI [0.0028, 0.0547]), while the other individual leads include
zero.

The analytic two-way joint tests reject:

- patent count, full 1994--2010: p = 0.00057;
- active patenting, full 1994--2010: p = 0.00016;
- patent count, buffered 1994--2008: p = 0.00593;
- active patenting, buffered 1994--2008: p = 0.00658.

A separate 9,999-draw deal-level Webb multiplier joint test also rejects:

- patent count, full: p = 0.0001;
- active patenting, full: p = 0.0001;
- patent count, buffered: p = 0.0021;
- active patenting, buffered: p = 0.0031.

The rejection is therefore not an artifact of relying on nominal-cluster
two-way asymptotics when the effective treated-deal count is about 37.

### The reference year is not the whole explanation

The weighted treated-minus-control patent-count level gaps are:

| Event time | Level gap |
|---:|---:|
| -5 | -0.0310 |
| -4 | -0.0119 |
| -3 | 0.0414 |
| -2 | -0.0015 |
| -1 | -0.0092 |

The event-time -3 coefficient is the difference between the -3 and -1 level
gaps: 0.0414 - (-0.0092) = 0.0506. Most of the rejection is therefore a
genuine treated-group patenting spike at -3, although the slightly negative
-1 gap increases its size. Re-referencing the event study to -2 would leave
an approximately 0.0429 gap at -3 and would not solve the problem.

### Why the frozen trajectory balance missed the spike

The P5 trajectory variable is

`log(1 + patents_recent / 2) - log(1 + patents_early / 3)`,

where `patents_early` aggregates event times -5, -4, and -3, and
`patents_recent` aggregates -2 and -1. It balances the early block against
the recent block; it does not balance the five annual outcomes.

The three early level gaps almost cancel:

`-0.0310 - 0.0119 + 0.0414 = -0.0015`.

Thus the frozen scalar can be balanced almost perfectly while treated
inventors have too few patents at -5 and -4 and too many at -3. The event
study revealed variation that the compressed trajectory measure was
structurally unable to see.

### The failure is influential but not isolated

The event-time -3 cohort ATT is positive in 14 of 17 cohorts. The largest
weighted cohort contributions come from 2006 (0.0115), 2009 (0.0102), 1995
(0.0058), and 2000 (0.0055). At the deal-stack level, deal 70 contributes
about 0.0127 and deal 346 about 0.0100 to the total 0.0506 coefficient.

Deal 70 is important, but removing it mechanically would leave an
approximately 0.038 coefficient before proper re-estimation. Moreover, the
same direction appears across most cohorts. Dropping deal 70, cohort 2000,
or a hand-picked cohort set is therefore neither a complete fix nor a
defensible primary response.

### What did not cause the failure

- Patent count and active patenting have complete pairwise coverage.
- The 1994--2008 censoring-clean sample also rejects.
- The compact sufficient-statistics estimator reproduces all three point
  estimates to within 2.2e-15.
- Construction passed 60/60 checks; estimation passed 22/22 checks.
- The Webb joint test confirms the rejection.
- The pattern is not produced by the two structurally empty TechDrift cells.

## Recovery options

### Option A — targeted trajectory amendment

Add event-time -3 patent count and the -3 active-patenting indicator to the
cohort entropy-balance constraints while retaining every existing P5
constraint and the same support roster.

This is the smallest amendment and directly addresses the observed failure.
It is likely feasible because it adds only two cohort-level moments to large
control rosters. It is not guaranteed until all 17 solves pass and ESS,
concentration, and retention are re-certified.

The limitation is governance and validation: -3 would then be balanced by
construction. It could no longer be cited as independent evidence of
parallel trends.

### Option B — full annual trajectory balance (preferred methodologically)

Replace the compressed two-block trajectory with the five annual
pre-treatment patent counts and active-patenting indicators from -5 through
-1, or add the annual vector while retaining the existing scalar.

This is less ad hoc than targeting the one failed year after observing it,
and it implements the already-approved idea of trajectory matching more
faithfully. It may cost more ESS or require approximate rather than exact
balance. A prospective hierarchy should be frozen before running:

1. exact annual mean balance with the existing constraints;
2. approximate annual balance at a predeclared tolerance;
3. reuse-constrained/cardinality trajectory matching if entropy balance is
   infeasible.

### Option C — co-equal exact trajectory matching

Use the Verginer-style five-year trajectory match as the second
identification design already contemplated by the project. It is especially
attractive if the augmented entropy solve loses too much ESS. It may reduce
retention because matching annual zero/count patterns is stricter.

## Required validation after any rescue

1. Keep the current failed design and its plots in the audit trail.
2. Freeze the augmented variables, tolerances, ESS gates, and fallback order
   before reopening post-treatment estimates.
3. Re-run all 17 cohorts without dropping cohort 2000 or deal 70 merely to
   obtain a pass.
4. Report annual pre-outcome balance as design balance, not as an independent
   pre-trend victory.
5. Preserve an external falsification margin: placebo timing, outcomes not
   used in trajectory construction (for example pre-period quality or
   TechDrift where defined), and the no-deal-70 influence refit.
6. Require the rescued post estimate to be reported alongside the original
   frozen estimate regardless of sign or significance.

## Recommended next decision

Run an outcome-blind feasibility pilot on the existing support roster that
adds the full annual patent-count and active-patenting trajectory. Do not
inspect new post-treatment estimates during that pilot. If exact balance
passes with acceptable reuse-adjusted ESS, use it as the candidate rescue.
If it fails, test the predeclared approximate-balance rung and then the
co-equal trajectory-matching design.

No such reweighting was performed as part of this diagnostic.
