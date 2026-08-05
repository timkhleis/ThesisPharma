# Local Match v2 control-only pseudo-treatment preflight freeze

## Purpose

This diagnostic tests whether the certified U2-clean matching, annual-trajectory
entropy-balancing, and P6 estimation pipeline systematically produces negative
post-period patent-count effects when treatment is randomly assigned among
eligible control firms.

It is not literal randomization inference for the observed acquisitions and
does not resolve acquisition-related mean reversion. It validates the pipeline
under randomized pseudo-treatment.

## Assignment

- Randomization occurs at the firm level.
- Firms are sampled in random order within cohort until the pseudo-treated
  donor-eligible inventor volume is as close as possible to the corresponding
  real treated-inventor volume. The design does not reproduce the 341-deal
  template.
- Candidate pseudo firms satisfy U2 cleanliness around the assigned cohort.
- Pseudo-treated inventors are exactly the donor-eligible control rows for the
  sampled firm and cohort.
- A firm receives at most one pseudo-treatment cohort per draw.
- Pseudo-treated firms and pseudo-treated inventors are excluded from every
  donor role in that draw.
- Failed assignments are recorded and never silently replaced.
- Two zero-centered falsification arms are run: unrestricted 1994--2010 and
  unrestricted censoring-clean 1994--2008.
- A paired 1994--2008 diagnostic conditions on an observed firm patent at or
  after \(g+5\). This is a patent-continuity selection diagnostic, not a firm
  survival measure; its placebo mean is expected to be positive.
- Within each draw, 200 deterministic random allocations are attempted. The
  selected allocation must place every cohort between 80 and 125 percent of
  its real treated-inventor target. Failure is recorded rather than waived.
- Each draw owns a disjoint block of 200 attempt seeds; preflight and
  production seed blocks cannot overlap.
- The preflight stops if two completed draws nevertheless publish the same
  assignment hash.
- Firm covariate similarity to real targets remains a reported scope
  diagnostic and is not an assignment gate.

## Design

The runner imports, rather than transcribes, the frozen full-cohort P5/P5c
configuration: U2, nearest-50, Stage-1 caliper 2.0, Stage-2 caliper 1.5, IPC4,
three controls and two firms per supported inventor, primary weights, and the
count-active annual trajectory over event times -5 through -1.

## Preflight boundary

Draw identifiers 1 through 10 are reserved for support-only preflight. The
preflight may inspect assignments, support, balance, ESS, runtime, and memory.
It must not materialize or inspect post-period outcomes or treatment effects.

The number of production draws will be frozen only after this pre-outcome
preflight. Preflight draws are excluded from the final empirical-null
distribution. Production draw identifiers begin at 1001, so they cannot
silently reuse any preflight assignment.

The initial ten draws determine feasible inventor volume, runtime, retention,
ESS, and estimator dispersion. The final draw count is then frozen before any
production outcome is opened.

## Inference

Production draws use patent count, reference period -1, average post period
+1 through +5, and 999 pseudo-firm-level Webb wild-bootstrap replications.
The placebo distribution is never recentered.

The report contains the placebo mean, Monte Carlo standard error, dispersion,
retention, ESS, nominal pseudo-firm count, effective pseudo-firm count, and
patent-continuity diagnostics. Centering uses every completed draw. A
false-rejection rate uses only draws with 90--110 percent of the matched real
treated-inventor volume and both nominal and effective firm counts between 50
and 200 percent of the corresponding real design. Its denominator is reported
explicitly.
The report does not calculate an empirical tail probability against the real
ATT, a placebo/real bias ratio, or a real-minus-placebo estimate.
