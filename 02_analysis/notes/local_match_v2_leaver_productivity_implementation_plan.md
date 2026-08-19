# Local Match v2 leaver-productivity implementation plan

Status: approved and implemented on 2026-08-18. Certified results are reported
in [`local_match_v2_initially_outside_productivity_results.md`](local_match_v2_initially_outside_productivity_results.md).

Date: 2026-08-18

Review amendment: this plan is governed, where modified, by
[`local_match_v2_initially_outside_productivity_plan_amendment.md`](local_match_v2_initially_outside_productivity_plan_amendment.md).
The amendment changes the technical population name to `initially_outside`,
adds classification and coverage diagnostics, freezes an exact-balance
fallback ladder and MDE, and aligns inference with the retained-inventor
package. Approval must cover both documents.

## 1. Purpose and scope

This package will estimate acquisition-aligned patent output among inventors
whose first observed post-acquisition patent is outside the combined target and
acquirer group. It will answer whether these inventors produce less, the same,
or more patent output than similarly selected inventors who leave matched
control firms.

The result is a short companion to the full-cohort and initially-retained
results. It is not a new headline contribution. Ornaghi and Cassi (2026,
Table 8) already report that target-firm leavers produce 2.21 fewer patents
over five years than their controls. The value added here is a comparison that
uses the thesis's acquisition-year event clock, fixed five-year horizon, local
support restrictions, complete pre-acquisition trajectory balance, and
deal-aware inference.

The package will be additive. It will not change the frozen full-cohort roster,
weights, estimates, retained-inventor package, or final-release artifacts until
the new results have been certified.

## 2. Interpretation and estimand

Departure is observed after treatment and may itself be affected by an
acquisition. The proposed estimate is therefore a **departure-conditioned
selected-group comparison**, not a principal-stratum ATT for inventors who
would leave under either treatment state.

The selected populations are:

- treated leavers: acquisition-exposed target inventors whose first observed
  patent during event times +1 through +5 is outside the target-acquirer
  ecosystem;
- control leavers: inventors attached to matched control firms whose first
  observed patent during the corresponding pseudo-event window is outside
  their original control group.

For event time \(k\), the estimated contrast will compare the change in patent
output from event time -1 among treated leavers with the entropy-weighted
change among control leavers. The headline summary will average the annual
event-time contrasts over +1 through +5.

The thesis may call this a **selected-group ATT** in tables for consistency
with the retained-inventor package, but every substantive discussion must state
that treatment can change selection into the leaver group.

## 3. Frozen population and event clock

The package will inherit the current final-release design wherever the leaver
question does not require a different choice:

- acquisition cohorts: 1993 through 2010;
- recruitment and earliest-treatment assignment: frozen Local Match v2 P2
  interfaces;
- support universe: frozen clean U2 firm and technology support;
- event-time panel: -5 through +5;
- baseline: event time -1;
- classification and headline outcome window: event times +1 through +5;
- event time zero: excluded from classification and headline aggregation
  because annual patent data cannot order applications around the completion
  date.

The existing Cassi-Ornaghi `T_LEAVER` field remains a validation benchmark. It
will not replace the thesis's fixed-window, acquisition-aligned classification.

## 4. Leaver classification

### 4.1 Treated inventors

For each status-eligible treated inventor:

1. Find the first year with an observed patent during +1 through +5.
2. Resolve the inventor's group using the frozen annual affiliation resolver.
3. Classify the inventor as a leaver when the resolved group is outside both
   the deal-specific target and acquirer groups.
4. Exclude inventors whose first post-deal affiliation is unresolved from the
   substantive location universe, while retaining them in the audit output.
5. Keep inventors with no patent during +1 through +5 in the existing
   no-post-patent category; do not treat them as leavers.

An acquirer group must be known and non-placeholder for the treated leaver
classification. This is necessary to distinguish an outside employer from the
combined entity. The exclusion and its inventor/deal counts will be reported.

### 4.2 Control inventors

For each eligible control inventor and pseudo-event cohort:

1. Define the focal entity as the same clean control group used during the
   pre-period.
2. Find the first observed patent during +1 through +5.
3. Classify the inventor as a control leaver when the resolved affiliation is
   outside the original control group.
4. Apply the existing synchronized group-ID transition audit so that a
   database recode is not silently interpreted as individual mobility.

### 4.3 Classification sensitivities

The package will construct four outcome-blind support variants before patent
outcomes are estimated:

1. `primary_resolved_t1`: frozen resolved affiliation, +1 through +5;
2. `route_consistent_t1`: exclude treated rows for which the resolved-group and
   target-company routes disagree;
3. `raw_unmixed_t1`: exclude rows whose first post-patenting year contains both
   focal and outside applicant evidence;
4. `timing_resolved_t2`: repeat classification over +2 through +5.

The primary result will not be replaced by a sensitivity based on its sign or
precision.

## 5. Outcomes

### 5.1 Primary outcome

The single primary outcome is annual inventor patent count, defined as the
number of distinct inventor-application links in each event year and zero
filled on the complete event-time grid. Patent count includes all of the
inventor's patents after acquisition, regardless of the applicant on later
patents. The outcome therefore measures the inventor's research output rather
than only output assigned to the first destination firm.

The package will report:

- the dynamic event-time contrasts for -5 through +5;
- the average annual selected-group ATT over +1 through +5;
- the corresponding five-year cumulative effect;
- treated and weighted-control post-period means;
- the 95 percent confidence interval and p-value.

### 5.2 Outcomes intentionally excluded

Active patenting will not be promoted as a second outcome because membership
in the leaver population already requires at least one post-event patent.
Quality, citations, technology drift, destination characteristics, and
heterogeneity analyses are outside this package. They would add multiple
testing and weaken the intended one-paragraph role of the result.

## 6. Separate support and weighting design

Full-cohort and retained-inventor weights will not be restricted and reused.
The package will solve new entropy-balancing weights within the treated-leaver
and control-leaver populations for each cohort.

The primary balancing vector will mirror the certified retained-inventor
design:

- patent counts at -5, -4, -3, -2, and -1;
- active-patenting indicators at -5, -4, -3, -2, and -1;
- inventor career age at -1;
- focal-group exclusivity;
- log five-year firm patent stock;
- log five-year firm inventor count.

The primary specification will omit firm patent trajectory, matching the
accepted retained-inventor count-and-active specification. Required
leave-one-year-out variants will omit the patent-count and active-patenting
conditions at -3 and -2 in turn. These variants provide held-out pre-period
diagnostics that are not mechanically forced to zero by exact balance.

Control base weights will continue to give each treated-deal stack the same
combined initial control weight as its treated inventors. Final aggregation
will preserve the inventor-weighted ATT interpretation used elsewhere in the
thesis.

## 7. Outcome-blind feasibility and validity gates

The following checks must pass before the first leaver patent outcome is
estimated:

### 7.1 Classification and support

- every classified row has a valid inventor, cohort, focal group, and arm;
- classification is mutually exclusive and deterministic;
- primary treated-leaver census is reported by cohort and deal;
- at least 80 percent of classified treated leavers survive support and
  balancing restrictions;
- the supported sample retains at least 20 effective treated deals;
- every included cohort has treated and control leaver support;
- control-firm reuse and treated-deal concentration are reported.

The existing certified descriptive census contains roughly 1,158 leavers, so
the design is expected to be smaller than the retained-inventor package. No
minimum nominal sample size will be chosen merely to guarantee passage. If the
effective-deal or support gates fail, the package stops without producing a
selected-group ATT.

### 7.2 Balance and held-out checks

- exact-balance specifications: maximum post-weighting absolute SMD no larger
  than \(10^{-6}\);
- reuse-adjusted control effective-sample-size ratio at least 0.50;
- leave-one-year-out estimates at -3 and -2 shown with confidence intervals;
- joint held-out pre-period test reported without treating non-rejection as
  proof of parallel trends.

No approximate-balance fallback is authorized by this plan. Failure of the
exact-balance or effective-sample-size gate stops estimation unless the user
reviews and approves a written outcome-blind amendment.

No support restriction, covariate omission, cohort deletion, or weighting
variant may be selected after viewing post-acquisition patent outcomes.

## 8. Estimation and inference

The estimation stage will reuse the certified Local Match v2 event-study core
and differ only in the new selected roster and weights.

- reference event time: -1;
- headline post window: +1 through +5;
- inference: 9,999 deal-level wild-bootstrap draws;
- fixed bootstrap seed recorded in the configuration file;
- two-way deal/inventor clustering reported as a companion diagnostic when
  computationally feasible;
- nominal inventor counts never treated as independent observations;
- null estimates reported with confidence intervals and detectable-magnitude
  discussion rather than re-specification.

## 9. Percentage effect

The headline percentage will use the weighted control-leaver post-period mean
as the counterfactual denominator:

\[
100 \times
\frac{\widehat{ATT}_{L}}
     {\widehat{E}[Y_L(0)\mid D=1,\,L=1]}.
\]

The numerator and denominator will use the same supported cohorts, event-time
window, and aggregation weights. Each wild-bootstrap ATT draw will be rescaled
by the fixed weighted counterfactual mean from the certified analysis sample.
The interval will therefore preserve the headline deal-level inference while
treating the percentage as a transparent normalization of the absolute ATT.

This normalization differs from Ornaghi and Cassi's Table 8 calculation, which
divides the five-year gap by the sum of pre-period and counterfactual
post-period patents. The thesis will report its denominator explicitly and
will not describe the two percentages as the same estimand.

## 10. Proposed implementation files

The implementation will add new scripts rather than modify the frozen stayer
or full-cohort packages:

| Stage | Proposed files | Purpose |
|---|---|---|
| Classification | `71a_lmv2_leaver_config.R`, `71b_build_lmv2_leaver_s0_s2.R`, `71c_certify_lmv2_leaver_s0_s2.R`, `71_run_lmv2_leaver_s0_s2.R` | Build and certify symmetric treated/control leaver partitions and classification audits. |
| Support and weights | `72a_lmv2_leaver_s3_config.R`, `72b_build_lmv2_leaver_s3_support.R`, `72c_run_lmv2_leaver_s3_weights.R`, `72d_certify_lmv2_leaver_s3.R`, `72_run_lmv2_leaver_s3.R` | Construct leaver-specific support, solve weights, run balance and feasibility gates, and freeze the execution hash. |
| Outcomes | `73a_lmv2_leaver_s4_config.R`, `73b_run_lmv2_leaver_s4_estimation.R`, `73c_certify_lmv2_leaver_s4_results.R`, `73d_summarize_lmv2_leaver_s4_results.R` | Estimate and certify patent-count effects only after S3 passes. |

Reusable weighting and estimation functions will be sourced from the existing
Local Match v2 code. Frozen scripts will not be refactored merely to support
this package.

Proposed generated artifacts:

- `02_analysis/output/audit/local_match_v2_1993_amendment/LEAVER_PRODUCTIVITY_S0_S2/`;
- `02_analysis/output/audit/local_match_v2_1993_amendment/LEAVER_PRODUCTIVITY_S3/`;
- `02_analysis/output/audit/local_match_v2_1993_amendment/LEAVER_PRODUCTIVITY_S4_RESULTS/`.

After certification, the package will add one qualified row to the final
results registry and one thesis-facing table fragment. It will not overwrite
existing rows.

## 11. Required audit outputs

Before outcome estimation:

- treated and control status counts by cohort;
- leaver counts by treated deal and control firm;
- unresolved, placeholder-acquirer, mixed-affiliation, and route-disagreement
  counts;
- overlap with the Cassi-Ornaghi `T_LEAVER` benchmark;
- synchronized control group-ID transition audit;
- support attrition funnel;
- balance table for every production specification;
- effective inventor, control-firm, and treated-deal counts;
- weight concentration and control reuse diagnostics;
- a hashed manifest linking source files, inputs, and outputs.

After estimation:

- dynamic coefficients and confidence intervals;
- average annual and cumulative post-period effects;
- treated and counterfactual post-period means;
- percentage effect and bootstrap confidence interval;
- leave-one-year-out pre-period diagnostics;
- deal influence or leave-one-deal-out diagnostic;
- certification report checking row counts, event coverage, weight totals,
  hashes, and numerical reproducibility.

## 12. Thesis reporting

The result should occupy one paragraph and, at most, one row or compact panel
next to the initially-retained result. Full balance and dynamic estimates belong
in the appendix.

Proposed main-text wording template:

> As a companion to the retained-inventor analysis, I compare target inventors
> whose first observed post-acquisition patent is outside the combined group
> with similarly selected inventors who leave matched control firms. Departing
> target inventors produce [ATT] fewer/more patents per year over the five
> post-acquisition years (95% CI [LOW, HIGH]), a [PERCENT]% decrease/increase
> relative to their estimated counterfactual output. Because acquisition can
> affect who leaves, this is a
> separately balanced selected-group comparison rather than an effect for a
> treatment-invariant population of always-leavers.

The discussion will compare the sign and magnitude with Ornaghi and Cassi's
published five-year gap, while emphasizing the different event clock,
population, counterfactual, and percentage denominator.

Interpretation will follow three cases:

- negative: disruption follows inventors after relocation and outside mobility
  does not restore their expected patent output;
- approximately zero with informative precision: output losses are
  concentrated among inventors who remain in the combined entity;
- positive: outside mobility may release inventors from post-acquisition
  disruption, although the selected-group qualification remains.

## 13. Execution order after approval

1. Add and hash the S0-S2 classification code.
2. Run classification and audit outputs without estimating patent outcomes.
3. Add, hash, run, and certify S3 support and weights.
4. Stop without outcomes if any governing feasibility or balance gate fails.
5. If the gates pass, run the frozen S4 patent-count estimation.
6. Certify all numerical outputs and rerun completed cells to verify
   determinism.
7. Update the final results registry and thesis-facing artifact only after
   certification.
8. Report the estimate regardless of sign or statistical significance.

## 14. Approval checklist

Approval of this plan authorizes the later implementation and estimation of
the following fixed choices:

- [ ] selected-group, not principal-stratum, interpretation;
- [ ] treated and control leavers defined symmetrically by the first observed
      outside patent during +1 through +5;
- [ ] 1993-2010 cohorts and acquisition-year event clock;
- [ ] separate leaver-specific support and entropy-balancing weights;
- [ ] patent count as the only primary outcome;
- [ ] average annual +1 through +5 estimate plus five-year cumulative effect;
- [ ] 9,999-draw deal-level wild-bootstrap inference;
- [ ] percentage normalized by weighted counterfactual post-period output;
- [ ] one-paragraph main-text treatment, with full diagnostics in the appendix;
- [ ] no outcome-driven changes if the preferred estimate is null or has an
      unexpected sign.

The user approved this plan and its amendment on 2026-08-18. The implementation
followed the amended execution order and passed the governing S0--S4 gates.
