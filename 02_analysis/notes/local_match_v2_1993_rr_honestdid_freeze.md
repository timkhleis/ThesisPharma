# Local Match v2: amended 1993--2010 joint-holdout HonestDiD freeze

Frozen on 4 August 2026 before the 1993 joint-holdout weights or HonestDiD
results were computed. The 1993 headline outcome was already known. This is a
downstream propagation of the prospectively frozen 3 August 2026
Rambachan--Roth contract, not a new outcome-blind design choice.

## Purpose

Re-run the existing full-cohort joint-holdout relative-magnitude analysis on
the amended 1993--2010 main sample. The entropy-balanced headline estimate is
unchanged. The sensitivity analysis is reported whether favorable or not.

The former 1994--2010 analysis is used only as an internal numerical-
reproduction check and is not routinely co-reported. The former 1994--2008
double-buffer specification is omitted.

## Population and weighting

- Reuse the certified 512,625-row amended P5c support roster.
- Retain all 18 cohorts, 1993--2010, or stop.
- Recompute final cohort weights from the primary deal-normalized base
  weights.
- Balance patent count and active patenting at event times -5, -4, and -1.
- Leave patent count and active patenting at -3 and -2 outside the final
  entropy-balance constraints.
- Retain career age, focal-group exclusivity, firm five-year patent stock,
  firm five-year inventor count, and firm patent trajectory.
- Reuse the certified feasibility hierarchy and ESS gate without retuning.

The held-out years are unconstrained in the final weighting solve, but the
support screen and five-year firm summaries use the full pre-period. This
limitation must be reported.

## Estimation and inference

- Outcome: annual inventor patent count.
- Reference period: -1.
- HonestDiD coefficient order: -3, -2, 0, +1, +2, +3, +4, +5.
- Target: the equal average over +1 through +5; event time 0 remains in the
  consecutive path with zero contrast weight.
- Primary covariance: analytic two-way acquisition/inventor covariance.
- Companion covariance: analytic acquisition-cluster covariance.
- The existing 9,999-draw acquisition wild bootstrap remains the governing
  conventional inference. HonestDiD uses analytic covariance and conditions
  on the estimated weights; weight-estimation uncertainty is not propagated.

## HonestDiD contract

- Package version: 0.2.8 from the project library.
- Restriction: `DeltaRM`, deviation from parallel trends.
- Method: conditional least favorable (`C-LF`).
- No sign, direction, or monotonicity restriction.
- Seed: 20260803; package evaluation is single-threaded.
- Discovery grid: Mbar 0, 0.05, ..., 0.50 with 200 inversion points; extend
  to 1 only if no crossing appears.
- Refine the first crossing bracket in 0.005 steps with 500 points and repeat
  with 1,000 points. The breakdowns must agree within 0.01.
- Use nearest-positive-semidefinite repair only when the minimum covariance
  eigenvalue is below -1e-10, and record the adjustment.

Smoothness restrictions are not run because only two pre-treatment
coefficients are genuinely free. The raw-base-weight design is not run because
those weights do not retain the entropy-balance covariate moments. LOYO
HonestDiD curves are not run because each arm contains only one genuinely free
lead and the resulting Mbar values are not comparable across arms.

## Reproduction gate

The amended 1994--2010 internal run must differ from the frozen joint-holdout
event estimates and post average by no more than 0.001 patent per inventor-
year. Its two covariance-specific breakdown values must differ by no more than
0.01. A failure stops certification and is reported rather than repaired.

## Archived split-preperiod design

The existing split-preperiod design with t=-7,-6 recruitment remains archived:
only four cohorts were feasible and its untouched leads rejected jointly. It
is not relabeled as HonestDiD evidence. A design without the long-history
recruitment restriction would be genuinely new and is considered only after
this amended joint-holdout analysis is certified.
