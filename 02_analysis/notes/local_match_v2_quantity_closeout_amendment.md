# Local Match v2 — quantity closeout amendment

Recorded on 2026-07-27 after the complete Package 1 diagnostics and the
early-recruitment analysis were opened.

This amendment narrows the accepted post-results package freeze. It does not
change the frozen P5c weights or any certified P6 estimate.

## 1. Completed Package 1

Package 1 is complete and certified. It contains the complete held-out-year
diagnostic over the five available pre-periods, the post-ATT stability grid, the
valid timing-placebo output, the raw-versus-matched lifecycle comparison, and
the early-recruitment analysis.

The main communication package reports:

- the P5c full-cohort patent-count ATT;
- the held-out-year estimates for \(t=-5,\ldots,-1\);
- the post-ATT range for the directly comparable LOYO \(t=-5,\ldots,-2\)
  designs;
- the early-recruited inventor results as heterogeneity evidence; and
- an appendix table containing the full and buffered estimates.

No new Verginer-sample funnel, Deal 70 diagnostic, or cohort-feasibility table
is required for this closeout.

## 2. Sensitivity to imperfect parallel trends

A full Rambachan–Roth exercise is not applied mechanically to the P5c event
study. Its constrained pre-period coefficients do not provide an unconstrained
pre-period covariance path, and the separately weighted LOYO estimates cannot
be treated as coefficients from one regression.

Instead, the communication package reports a transparent, LOYO-calibrated
sign-breakdown statistic:

\[
B
=
\frac{|\widehat{ATT}_{post}|}
{\max_{s\in\{-5,\ldots,-1\}}|\widehat{\Delta}_{s}^{LOYO}|}.
\]

The statistic states how many multiples of the largest genuinely held-out
pre-period discrepancy an additive post-period violation would need to reach
to offset the estimated post effect. This calculation is a sensitivity
calibration, not a formal Honest DiD confidence set.

## 3. Extensive and intensive margins

The patent-count point estimate is decomposed using

\[
E[Y]=P(Y>0)E[Y\mid Y>0].
\]

The extensive margin is the acquisition effect on the probability of any
patenting in an inventor-year. The intensive margin is the difference in
patents per active inventor-year. The reported contribution uses the
order-invariant Shapley decomposition and sums exactly to the patent-count ATT.

The intensive component is descriptive because conditioning on active
patenting conditions on a post-treatment outcome. It is not presented as a
separate causal ATT.

## 4. Location categories for the next stage

The supervisor-facing location partition uses four categories:

1. **initially retained inventors**: the earliest observed post-deal patent year
   contains focal-ecosystem evidence and no outside evidence;
2. **initial leavers**: that year contains outside evidence and no focal
   evidence;
3. **mixed first-year affiliation**: both focal and outside evidence occur in
   that year; and
4. **no observed post-deal patent** in \(t=0,\ldots,+5\).

Status-ineligible unresolved observations remain outside this analysis universe
and are not a reported substantive category.

The initial-leaver category is used only to define the partition and describe
selection. It is not developed as a separate contribution, because prior work
already studies leavers.

## 5. Remaining sequence

1. Close the full-cohort quantity result with the communication figure,
   appendix table, sign-breakdown statistic, and margin decomposition.
2. Complete the already-planned supported-versus-unsupported descriptive table
   and common-support sensitivity.
3. Certify the four-category first-year partition.
4. Build and diagnose a separately balanced initially-retained P5b design
   before opening stayer outcomes.

