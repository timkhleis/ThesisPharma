# Amendment to the initially-outside inventor productivity plan

Status: approved and implemented on 2026-08-18. Certified results are reported
in [`local_match_v2_initially_outside_productivity_results.md`](local_match_v2_initially_outside_productivity_results.md).

Date: 2026-08-18

Governing plan:
[`local_match_v2_leaver_productivity_implementation_plan.md`](local_match_v2_leaver_productivity_implementation_plan.md)

This note responds to the methodological review of the governing plan. It
supersedes the governing plan where the two conflict. All additions remain
prospective with respect to the proposed post-acquisition patent-count result.

## 1. Decisions on the review

| Review item | Decision | Governing change |
|---|---|---|
| Classification and outcome clocks | Modify, not adopt literally | Keep the acquisition-aligned +1 through +5 primary estimand; add first-post-patent timing diagnostics and a prospectively defined early-outside sensitivity. Do not balance a post-treatment timing variable. |
| Treated and control inside sets | Accept as a limitation and sensitivity | Report arm-specific selection rates and a target-only treated sensitivity. Do not interpret the two definitions as formal bounds. |
| Late-tail coverage | Accept | Add a censoring-clean 1993--2008 companion and calendar-year coverage audit. |
| Control-group existence | Accept | Add group-existence and group-ID-transition audits and state the institutional asymmetry explicitly. |
| Small-sample feasibility | Accept | Freeze an ordered, exact-balance fallback ladder and retain failed tiers in the audit. |
| Minimum detectable effect | Accept | Freeze a pre-period, design-stage MDE and a rule for describing a null estimate. |
| Inference convention | Accept | Make analytic two-way deal/inventor clustering primary and the deal-wild bootstrap the conservative companion, matching the retained package. |
| Selection sensitivity | Accept with qualification | Add common-support tipping. Do not report ordinary Lee bounds without defensible principal-stratum assumptions. |
| P5c roster inheritance | Accept | Require the new roster to be nested inside the certified P5c common-support roster. |
| Terminology and percentage inference | Accept | Use `initially_outside`; soften the zero-effect interpretation; report fixed-denominator and jointly recomputed ratio intervals. |

## 2. Revised population and interpretation

The technical population name is **initially-outside inventors**. A treated
inventor enters this population when the first resolved patent affiliation
observed during event times +1 through +5 is outside the combined target and
acquirer group. A control inventor enters when the corresponding first resolved
affiliation is outside the original control group. “Leaver” may be used when
discussing the Cassi--Ornaghi benchmark, but the thesis must not imply that the
two classifications are identical.

This classification reveals the inventor's location only when a patent is
observed. It does not identify the calendar year of employment departure. An
inventor whose first post-acquisition patent is at +4 has observed zero patent
output at +1 through +3, but the data do not establish whether the inventor was
inside or outside during those years.

The primary acquisition-aligned outcome will retain those zero-output years.
They are part of the thesis's question about total inventive output following
acquisition and preserve comparability with the full-cohort and
initially-retained rows. Restricting the primary sample to inventors who patent
by +2 would condition additionally on an early post-treatment outcome and
would answer a narrower question. Indexing outcomes from the first outside
patent would instead answer a mobility-clock question and mechanically include
the patent that defines entry. Neither replaces the primary estimand.

Accordingly, the estimand remains a separately balanced, acquisition-aligned
selected-group comparison. It is not an ATT for a treatment-invariant
always-leaver principal stratum, and it is not a clean effect of departure.

## 3. Governing classification variants

The four variants in Section 4.3 of the governing plan are replaced by the
following prospectively ordered definitions:

1. `primary_initially_outside_t1_t5`: first resolved patent affiliation during
   +1 through +5 is outside the combined target--acquirer group for treated
   inventors and outside the original group for controls;
2. `route_consistent_initially_outside_t1_t5`: the primary definition after
   excluding treated observations for which resolved-group and target-company
   routes disagree;
3. `raw_unmixed_initially_outside_t1_t5`: the primary definition after
   excluding first-patenting years containing both focal and outside applicant
   evidence;
4. `early_initially_outside_t1_t2`: first resolved post-event patent occurs at
   +1 or +2 and satisfies the primary outside definition;
5. `target_only_initially_outside_t1_t5`: for treated inventors only, the inside
   set is the target group rather than the combined target--acquirer group;
6. `censoring_clean_initially_outside_1993_2008`: the primary definition,
   restricted to cohorts whose complete +1 through +5 window ends by 2013.

The former `timing_resolved_t2` variant is removed. Beginning the search at +2
does not resolve the difference between the acquisition and observed-mobility
clocks.

The early-outside and target-only variants are sensitivities, not candidate
replacements chosen by sign or precision. The target-only result is not a
formal lower or upper bound: moving from the target to the acquirer is economic
retention within the post-merger entity, so target-only status can misclassify
integration as departure.

## 4. Required design-stage classification audits

Before weights or outcomes are built, report:

- the event-time distribution of the first observed post-event patent by arm,
  cohort, and classification status;
- initially-outside counts and rates, using all status-eligible inventors in
  each arm as denominators;
- no-post-patent, unresolved-affiliation, combined-entity retained, and
  initially-outside shares as mutually exclusive categories;
- the number of treated inventors and deals changing status under the
  target-only definition;
- the number of treated inventors and deals removed by placeholder acquirer
  IDs, and the overlap of the resulting deal set with the retained-inventor
  deal set;
- the number and share of observations satisfying the early +1/+2 definition;
- a cohort-by-event-time table mapping each event time to calendar year and
  the underlying patent-record count;
- target, acquirer, and control focal-group existence and patent-activity
  indicators throughout the event window; and
- synchronized group-ID transitions, disappearances, and successor mappings,
  separated from inventor mobility.

First-post-patent timing is post-treatment and therefore will not be added to
the entropy-balancing vector. Its arm difference is reported as a selection
diagnostic, not “controlled away.”

The text must state that controls are drawn from stable, non-target groups and
are required by the parent design to have post-event support. Their outside
moves may therefore differ institutionally from moves out of an absorbed
target. The group-existence audit documents this limitation but cannot remove
it.

## 5. Support-roster inheritance

The production initially-outside roster must be a subset of the certified P5c
common-support roster for the same inventor--cohort--arm cells. S0--S2 will
first reproduce the P5c roster hash and row keys, build the status census in
the broader status-eligible universe for the attrition and tipping audits, and
then intersect classified rows with P5c for production. No clean-U2 unit
excluded by P5c may re-enter the estimated sample.

The package will solve new weights after this nested selection. This preserves
the parent design's firm and technology support while allowing treated and
control initially-outside populations to be balanced separately.

## 6. Prospectively frozen exact-balance ladder

The primary design remains cohort-specific entropy balancing. To avoid an
outcome-informed rescue if small cells are infeasible, S3 will attempt the
following tiers in order and select the first tier that passes all governing
support, balance, and ESS gates:

1. `A_cohort_count_active_scale`: exact cohort-specific balance on five annual
   patent counts, five annual active-patenting indicators, career age,
   focal-group exclusivity, log five-year firm patent stock, and log five-year
   firm inventor count;
2. `B_cohort_count_scale`: exact cohort-specific balance on the same vector
   after omitting the five active-patenting indicators, which are deterministic
   transformations of the annual count outcomes but impose additional moment
   constraints;
3. `C_era_count_active_scale`: exact balance within the pre-specified eras
   1993--1998, 1999--2004, and 2005--2010, retaining the full Tier A vector and
   exact treated cohort-share constraints within each era;
4. `D_era_count_scale`: the Tier C era design after omitting the five active
   indicators.

Focal-group exclusivity remains in every tier because it is a substantively
important pretreatment predictor of mobility. Firm patent trajectory remains
omitted, consistent with the accepted retained-inventor production design.

Every attempted tier and variant will remain in the audit with its convergence,
balance, retention, ESS, concentration, and cohort-support result. A tier can
govern production only if it was reached by the fixed order above. No
approximate-balance fallback, post-outcome covariate deletion, or unplanned
cohort pooling is authorized. If Tier D fails, the package stops before opening
post-acquisition outcomes.

Only the primary classification must pass the production gate. A sensitivity
that fails is reported as infeasible; its failure neither stops a feasible
primary design nor licenses a new specification.

The 80 percent treated-retention and 20 effective-treated-deal thresholds are
retained as governance conventions inherited from the selected-population
package, not as thresholds derived from sampling theory. Realized values will
be reported continuously so readers can assess sensitivity to those cutoffs.

## 7. Late-tail rule

The 1993--2010 acquisition-cohort result remains primary for direct comparison
with the final thesis release. The 1993--2008 censoring-clean result is a
required companion because its +5 endpoint is 2013, before the documented 2014
and 2015 patent-record collapse.

Dynamic estimates through +5 must display the number of contributing cohorts,
treated deals, treated inventors, control firms, and patent applications at
each event time. The 2010 cohort and calendar years 2014--2015 will be flagged
in the table and figure. If primary and censoring-clean results differ, the
thesis will describe the difference without selecting the preferred result by
significance.

## 8. Precision and null-result language

Before opening +1 through +5 outcomes, compute the design-stage standard error
from each of the two held-out pretreatment contrasts at -3 and -2 under the
selected balance tier and primary analytic clustering. Define

\[
 SE_{\rm design}=\max\{SE(\widehat{ATT}_{-3}),
                         SE(\widehat{ATT}_{-2})\}
\]

and the two-sided 5 percent, 80 percent-power minimum detectable effect as

\[
 MDE_{80}=(1.96+0.84)SE_{\rm design}.
\]

Report it in patents per inventor-year and relative to the weighted control
pretreatment mean. After estimation, also translate the same absolute MDE
relative to the weighted counterfactual post mean. This translation cannot
alter the design or reporting decision.

“Approximately zero” is permitted only when the 95 percent confidence interval
lies wholly inside a prospectively fixed equivalence band of plus or minus 20
percent of weighted counterfactual output. Otherwise a non-significant result
must be described as imprecise or as failing to reject zero. The 20 percent
band is an explicitly labelled substantive convention, not a test-derived
threshold.

## 9. Estimation and inference hierarchy

The absolute patent-count contrast remains the primary statistic. Point
estimation, event window, baseline, and aggregation follow the governing plan.

The uncertainty hierarchy is revised to match the certified
initially-retained package:

1. primary: analytic two-way deal/inventor-clustered interval and p-value from
   the cohort-weighted influence functions;
2. conservative companion: 9,999-draw deal-level wild-cluster bootstrap with a
   fixed, recorded seed; and
3. diagnostic: leave-one-deal-out influence and concentration results.

Both primary and wild-bootstrap intervals will be shown. Inventor-level sample
size will never be treated as the number of independent observations.

## 10. Percentage effect

The percentage point estimate remains

\[
100\times\widehat{ATT}_{IO}/\widehat{\mu}_{C,post},
\]

where the numerator and weighted control post mean use identical supported
cohorts, event times, and aggregation weights. Report two intervals:

1. a fixed-denominator normalization of the primary ATT interval; and
2. a jointly recomputed ratio interval in which numerator and denominator are
   recalculated in each deal-level bootstrap draw.

The fixed-denominator interval keeps the percentage visibly tied to the
absolute primary estimate; the joint interval acknowledges uncertainty and
covariance in the denominator. The counterfactual interpretation of the
weighted control post mean follows from the selected comparison design and its
parallel-trends assumption. Exact balance at -1 improves baseline comparability
but does not, by itself, establish that counterfactual identity.

## 11. Selection sensitivity and limits

Two distinct selection problems will remain separate.

First, for observed initially-outside treated inventors excluded by P5c or the
new S3 support, port the frozen common-support tipping calculation:

\[
ATT_{all}=pATT_{supported}+(1-p)ATT_{unsupported}.
\]

Use the same fixed delta grid as the P6 selection-sensitivity freeze,
\(\delta\in\{-3,-2,-1.5,-1,-0.5,0,0.5,1,1.5,2,3\}\), with scale set by the
1st/99th-percentile-winsorized standard deviation of the treated inventor's
mean patent count over -5 through -1. Report the unsupported effect and delta
required to reverse the supported-sample conclusion. This is a support
sensitivity, not an imputation and not a Lee bound.

Second, selection into initially-outside status is itself post-treatment.
Ordinary Lee bounds are not identified here without a defensible common
monotonic direction, exchangeability or parallel trends for the relevant
principal stratum, and suitable outcome-support assumptions. The existing
selection audit found those assumptions inadequate for initially retained
inventors; departure is at least as treatment-dependent. The package will
therefore report arm- and cohort-specific selection rates, pretreatment
characteristics by status, and the selected-group qualification, but it will
not label mechanical trimming as a causal bound.

The common-support tipping calculation does not solve selection into
initially-outside status. The thesis must say this directly.

## 12. Revised interpretation cases

The selected-group result supports only statements about the separately
balanced initially-outside populations:

- a negative estimate means acquisition-exposed initially-outside inventors
  have lower acquisition-aligned patent output than similarly selected control
  inventors, conditional on the stated design and selection;
- an equivalently small estimate means no economically meaningful difference
  is detected for these selected populations within the pre-specified band; it
  does not show that losses are concentrated among retained inventors; and
- a positive estimate means acquisition-exposed initially-outside inventors
  have higher acquisition-aligned output, but does not by itself establish that
  departure caused the gain.

Every case retains the institutional-inside-set, stable-control, late-tail, and
post-treatment-selection qualifications above.

## 13. Revised execution and approval gate

After user approval:

1. implement and certify S0--S2 only, including the P5c nesting proof,
   classification variants, selection rates, timing distribution, group
   existence, placeholder, deal-overlap, and calendar-coverage audits;
2. return the design-stage census to the user before S3 if any material
   classification or coverage anomaly appears;
3. implement S3, attempt the exact-balance ladder in its fixed order, and freeze
   the first passing tier;
4. compute the held-out pretreatment diagnostics and MDE;
5. stop without post outcomes if all tiers fail or the governing support gates
   fail;
6. only then estimate and certify S4 under both inference conventions, the
   censoring-clean companion, the percentage intervals, and support tipping;
7. report all planned results regardless of sign or significance; and
8. update the final registry only after numerical certification.

The user approved the original plan as modified by this amendment on
2026-08-18. The implementation followed this sequence and passed the governing
classification, support, balance, ESS, precision, and numerical-certification
checks.
