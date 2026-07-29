# Local Match v2 P5b S4: initially retained outcome-estimation freeze

Status: frozen after S3 certification and before opening any S4 estimate

## Estimand

S4 estimates the weighted post-acquisition contrast between initially retained
treated inventors and inventors who remain with clean control firms. Because
initial retention is measured after treatment, this is a selected-group
contrast. It is not interpreted as the causal ATT for an always-retained
principal stratum without the later selection analysis and bounds.

## Point estimator

S4 uses the same cohort-pooled first-difference estimator as the certified
full-cohort P6 analysis. For each cohort \(g\) and event time \(e\), it
computes

\[
\widehat{ATT}_{ge}
=
\overline{(Y_e-Y_{-1})}_{T,g,w}
-
\overline{(Y_e-Y_{-1})}_{C,g,w}.
\]

Cohort effects are aggregated using each cohort's share of frozen treated S3
weight. Event time \(t=-1\) is the reference period. The headline post
estimate is the equal-horizon average over \(t=+1,\ldots,+5\); for patent
counts, five times this annual average is also reported as the cumulative
five-year contrast.

S4 reports the full 1994--2010 sample and the 1994--2008 censoring-clean
companion. Event time \(t=+5\) remains in both results for comparability.

## Outcomes in the first package

The first S4 package estimates:

1. annual patent count, the primary outcome;
2. the probability of patenting in a given year, the extensive-margin
   companion.

Quality, forward citations, TechDrift, location, and the intensive/extensive
decomposition remain later packages. Their omission from the first package
does not change the quantity design.

## Frozen specifications

Every specification is reported regardless of sign or precision:

1. primary resolved retention over \(t=+1,\ldots,+5\);
2. LOYO \(t=-3\);
3. LOYO \(t=-2\);
4. route-consistent retention;
5. raw-patent unmixed retention;
6. retention classified over \(t=+2,\ldots,+5\).

The primary estimate is not selected by comparing these results. The two LOYO
specifications are held-out pre-period diagnostics. The route, raw-unmixed,
and timing specifications test the retained-inventor classification.

## Inference

S4 inherits the certified P6 inference contract:

- deal-level Webb wild-cluster bootstrap-t inference;
- 9,999 replications, seed 20260722, null imposed;
- two-way deal/inventor clustered inference as a prominent companion;
- deal-only cluster-robust inference as an additional diagnostic;
- the wider of the wild-bootstrap and two-way confidence intervals governs.

Dynamic event-study intervals and the joint test over
\(t=-5,-4,-3,-2\) use the two-way deal/inventor covariance. LOYO held-out
coefficients are evaluated against the predeclared \(\pm0.05\)
patent-per-inventor-year equivalence band but cannot select the headline
design.

## Reporting

The first report must include:

- the annual and cumulative patent-count contrast;
- the active-patenting contrast in percentage points;
- all six frozen specifications for both cohort windows;
- event-time paths and formal pre-period tests;
- nominal and effective treated-deal counts;
- comparison with the frozen \(-0.0606\) composition benchmark;
- an explicit statement that the estimates condition on observed initial
  retention.

No sample, balance constraint, weight, estimator, horizon, or inference rule
may change after S4 outcomes are opened.
