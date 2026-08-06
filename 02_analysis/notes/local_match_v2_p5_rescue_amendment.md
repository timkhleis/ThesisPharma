# Local Match v2: P5.1 main-ATT support rescue

**Date:** 2026-07-26

## Status and evidentiary boundary

This amendment supersedes the P5 per-cohort retention rule for the main-ATT
support rescue. It does not alter or overwrite the completed P5 artifacts.
The rescue is selected and assessed using only treatment assignments,
pre-treatment covariates, donor eligibility, support, balance, effective
sample size, concentration, and retained-versus-unsupported diagnostics.

The purpose of matching is to make conditional parallel trends credible and
to identify a meaningful ATT. Pre-treatment outcome coefficients and timing
placebos are therefore required validation tests after the design is frozen.
They are not used to choose among the attribution stages below. If the frozen
design fails those tests, the failure is reported and any redesign receives a
new amendment rather than silently selecting another result.

No cohort may be removed merely because it is difficult to support. Cohort
2000 is mandatory because it is the largest cohort and contains economically
important mega-deals. If it remains below the cohort gate after the permitted
rescue stages, P5.1 stops for design review.

## Outcome-blind preflight facts

The completed U1 run supports 23,324 of 29,170 treated inventors before its
old whole-cohort terminal gate (79.96%). Cohort 2000 supports 1,381 of 3,726
inventors (37.06%) and accounts for 2,345 of the 5,846 unsupported inventors.

For cohort 2000, the pre-period active-firm decomposition contains 9,390
firms. U1 admits 8,971. A clean not-yet-treated U2 adds 157 future-target
firms. Ninety-six active firms have an acquirer event during 1995--2005 and
remain excluded. The U2 additions are larger than ordinary U1 firms: median
inventor count is 13 versus 6, and the 90th percentile is approximately 135
versus 44.

Under the completed U1 support, pooled treated-inventor coverage by
rank-based pre-deal productivity quartile is 71.16%, 96.48%, 85.92%, and
66.28%. The top-quartile failure makes productivity-quartile heterogeneity a
binding design concern rather than a reporting footnote.

## Attribution-first rescue sequence

Only the smallest stage that clears every gate may be frozen:

1. `baseline_gate`: apply the new aggregate/cohort gate to the completed U1
   support. This is an audit baseline, not an acceptable final design because
   cohort 2000 fails.
2. `u2_inventor_first`: use U2 and remove the five-firm terminal deal gate.
   A treated inventor is supported only when it has at least three admissible
   control inventors spanning at least two control firms. Keep both absolute
   calipers, the original Stage-2 distance, balance moments, weighting
   schemes, and solver unchanged.
3. `u2_reduced`: only if stage 2 fails, reduce the Stage-2 local distance to
   four components: log five-year inventor patent count, inventor patent
   trajectory, career age, and one-minus IPC4 cosine similarity.
4. `u2_reduced_knn`: only if stage 3 fails, replace the absolute Stage-2
   screen with the five nearest admissible control inventors, spanning at
   least two firms. The sanity bound is the cohort-specific 99th percentile
   of the fifth-nearest distance recomputed under the same distance metric
   among treated inventors supported before this fallback. A global
   candidate-distance quantile is forbidden because it does not specifically
   rescue treated inventors in sparse tails.

Stages are first run on cohorts 2000 and 2009. Cohort 2000 is the pathological
case; 2009 is the large successful anchor. Full-cohort production begins only
after the smallest successful stage passes its fixtures and both-cohort
diagnostics.

## U2 definition

For treatment cohort `g`, a control firm is U2-eligible when:

1. it has no target event on or before `g+5`; and
2. it has no acquirer event between `g-5` and `g+5`, inclusive.

Thus never-target firms and firms first treated after the complete five-year
outcome window are eligible. A firm targeted during or before the outcome
window is ineligible. The existing inventor-level rule excluding control
inventors with target exposure on or before `g+5` remains unchanged.

An acquirer-admitting U3 robustness pool must exclude each focal deal's own
acquirer (`U3*`). U3* is not a headline or co-primary design. It may produce
separately labelled robustness weights only after U2-clean is frozen. The
share of U3* control weight assigned to acquirer-exposed firms is reported
overall and by deal.

## Inventor-first support and dependence

The completed five-firm gate is a conservative firm-diversity rule, not a
mathematical requirement for inventor matching. For deal 70, the three clean
U2 firms contain 2,794 distinct eligible control inventors (1,174, 905, and
715) against 2,154 treated inventors. P5.1 therefore admits a deal with fewer
than five Stage-1 firms but does not call every treated inventor supported by
mere presence of one edge. Each supported treated inventor must have at least
three admissible control inventors from at least two firms.

Deal 70 receives additional prospective dependence diagnostics:

- report effective firm count from final control weights;
- an effective firm count below 2.5 triggers design review but is not imposed
  as a solver constraint;
- remove each donor firm in turn, renormalize remaining control weights to
  the original deal mass, and recompute every weighted balance mean;
- standardize each leave-one-firm-out mean shift by the unweighted pooled
  treated-plus-control standard deviation within deal 70;
- every absolute standardized mean shift must be below 0.10; and
- report control-inventor reuse-adjusted ESS and realized match-distance
  distributions, including by pre-deal productivity quartile.

## Reduced distance and balance moments

`focal_group_tenure` is removed from the reduced local distance because group
tenure is mechanically bounded by career age and therefore double-counts
seniority.

`focal_group_exclusivity` is also not a reduced-distance component, but it is
not discarded. Exclusivity is a bounded measure of pre-deal organizational
attachment rather than inventive capacity or technological proximity.
Requiring close individual-level equality on a mass-at-one attachment
measure isolates mobile inventors even when close productivity and technology
comparators exist. Aggregate confounding from attachment is instead handled
by:

1. retaining exclusivity as an exact entropy-balance moment;
2. including it in the subsequent CS(2021) doubly robust covariate model; and
3. reporting retained-versus-unsupported and residual local imbalance on
   exclusivity.

The existing firm-level balance moments and Stage-1 firm recruitment remain
unchanged in `u2_inventor_first` and `u2_reduced`, except that a deal is not
discarded solely for having fewer than five firms. They are not otherwise
redesigned unless both stages fail.

## Main-ATT acceptance gates

The rescue must satisfy all of the following before P6:

- aggregate treated-inventor coverage at least 80%;
- every cohort, including 2000, has coverage at least 60%;
- aggregate treated-deal coverage at least 80%;
- every rank-based pre-deal productivity quartile has coverage at least 70%;
- pooled absolute retained-versus-unsupported SMD is at most 0.20 for log
  patent count, career age, focal-group exclusivity, and focal-group tenure;
- 0.20--0.25 is a review band and any value above 0.25 is a failure;
- variance ratios for the same selection variables are reported;
- the certified exact/0.05/0.10 balance hierarchy passes;
- reuse-adjusted ESS ratio is at least 0.50; and
- effective control-firm count, concentration, and selected support stage are
  reported by cohort and weighting scheme.

The old rule that discarded every supported inventor in a cohort below 80%
is replaced by the 60% cohort floor plus the aggregate and quartile gates.
Unsupported inventors remain outside the common-support estimand and are
reported; supported inventors in a passing cohort are not discarded.

## Production and stopping rule

Both `primary` and `equal_deal` weights are materialized in atomic,
checksum-verified cohort shards. Every rescue artifact uses a new execution
hash containing this amendment, the rescue configuration, the selected
attribution stage, and input identities. Completed P5 and DealSim artifacts
are read-only.

P5.1 stops after design diagnostics and row-level weights are certified. P6
then estimates outcomes using the frozen weights and treats event-study
pre-trends and timing placebos as validation. DealSim and cardinality matching
remain outside this rescue.

Before any P6 outcome is opened, P5.1 pre-registers and freezes three reported
comparisons:

1. U2-clean on its supported treated sample;
2. U3* on the identical U2-supported treated sample; and
3. U3* on its full supported sample.

All three are reported regardless of ATT sign, magnitude, pre-trend, or
placebo performance. They separate donor-universe sensitivity from the
addition of mega-deals; they cannot be used to select the preferred result.
U2-clean remains the headline specification. Promotion of U3* would require
a separately documented design change after reporting the frozen validation
evidence and every design examined.
