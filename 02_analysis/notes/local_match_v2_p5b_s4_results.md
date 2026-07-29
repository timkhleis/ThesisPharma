# Local Match v2 P5b S4--S6: initially retained results

Status: quantity and secondary outcomes estimated and certified under the
frozen 17-cohort S3 design

## Main result

Initially retained inventors produce 0.107 fewer patents per inventor-year
after acquisition than their entropy-balanced retained-control
counterfactual. The estimate implies 0.536 fewer patents over five years.
Treated stayers produce 0.816 patents per year after acquisition, compared
with a matched counterfactual of 0.923. The annual contrast therefore equals
11.6% of counterfactual post-acquisition output and 14.2% of the treated
group's average pre-acquisition output.

The primary two-way deal/inventor-clustered interval is
\([-0.204,\ -0.010]\), with \(p=0.031\). This is the thesis's reporting
inference because it allows both common deal shocks and repeated use of the
same inventor across comparison stacks. The deal-level wild-cluster bootstrap
is retained as a conservative sensitivity; its interval is
\([-0.224,\ 0.015]\), with \(p=0.081\). Thus the selected-group contrast is
statistically significant under the primary two-way inference, although the
bootstrap sensitivity and the selection diagnostics below preclude an
unqualified causal stayer interpretation.

The primary sample contains 2,663 initially retained treated inventors across
151 deals and 31.53 effective treated deals. All quantity outcomes have
complete pairwise coverage.

## Why the initially retained sample is much smaller

The clean full-cohort DiD contains 27,078 treated inventors across 341 deals.
The stayer analysis uses the exact same certified P6 outcome panel; all 43,508
rows of the primary S3 treated/control roster map one-to-one into that panel,
and every row has the same 11 event-time observations. The smaller sample is
therefore not caused by a different data pipeline.

It is primarily a consequence of what patents can identify. In the broader
status-classification universe of 28,483 treated inventors:

- 24,235 (85.1%) have no observed patent in years \(t=+1,\ldots,+5\);
- 1,158 (4.1%) first patent outside the focal entity and are classified as
  leavers; and
- 3,090 (10.8%) first patent inside the focal entity and are initially
  retained.

This should not be read as an employment-retention rate. The data identify
patent retention, not continued employment: an inventor who remains employed
but does not patent is in the no-post-patent group.

The initially retained inventors are positively selected on prior patenting.
Inside the clean P5c sample they have a mean five-year pre-deal stock of 3.78
patents and 1.93 active years, compared with 2.85 and 1.64 for leavers and
1.73 and 1.24 for inventors with no post-deal patent. This is the substantive
reason that only a minority can enter the initially retained analysis.

Of the 3,090 classified initially retained inventors, 412 were already outside
the frozen full-cohort P5c common-support roster. The stayer-specific design
then loses only 15 more: three prospectively declared convex-hull exclusions
and 12 inventors whose deal-cohort cell has no retained-control analogue. The
final 2,663 therefore retain 86.18% of all classified initially retained
inventors. The deal count falls from 341 in the full P5c cohort to 172 at
classification because many, particularly small, deals have no inventor with
an observed focal patent in the five-year post-deal window; P5c support and
stayer support reduce this further to 160 and 151 deals.

The 412 cannot simply be inserted with zero or extrapolated weights. A
stayer-specific recovery audit finds that only 34 have any candidate under the
already-frozen clean-U2 cardinality support, and only 22 have even one
candidate control who is also initially retained. Thus 390 of the 412 have no
retained-control edge under the accepted support rules. The earlier
full-cohort cardinality solution recovers four of these initially retained
inventors, but only two have a retained matched control. A separately labelled
stayer-recovery arm may test the maximum 22; it cannot restore the remaining
390 without relaxing technology, firm, or timing support.

## Censoring-clean companion

Restricting the sample to the 1994--2008 cohorts strengthens rather than
attenuates the estimate. The annual patent-count contrast is \(-0.120\), or
\(-0.602\) patents over five years. Its governing wild-bootstrap interval is
\([-0.245,\ 0.010]\), with \(p=0.070\).

Patent-data right censoring therefore does not explain the negative quantity
contrast. The companion contains 134 nominal and 26.60 effective treated
deals.

## Classification and design sensitivities

The negative annual patent-count estimate is stable across every frozen
full-sample specification:

| Specification | Annual contrast | Governing 95% interval |
|---|---:|---:|
| Headline | -0.107 | [-0.224, 0.015] |
| LOYO \(t=-3\) | -0.099 | [-0.218, 0.024] |
| LOYO \(t=-2\) | -0.096 | [-0.210, 0.024] |
| Route-consistent retention | -0.108 | [-0.229, 0.017] |
| Raw-unmixed retention | -0.101 | [-0.225, 0.026] |
| Retention classified from \(t=+2\) | -0.127 | [-0.259, 0.011] |

The range, \(-0.096\) to \(-0.127\), is narrow relative to the effect. The
result does not depend materially on affiliation-route disagreement,
patent-level mixed affiliation, or using the first post-acquisition year to
classify initial retention. The censoring-clean estimates are similarly
stable, ranging from \(-0.108\) to \(-0.132\).

## Held-out pre-period diagnostics

The headline pre-period coefficients are zero by construction because S3
balances all five annual patent outcomes. The LOYO estimates provide the
relevant falsification evidence:

- Holding out \(t=-3\) produces a full-sample gap of \(+0.113\) patents
  (\(95\%\ CI=[0.006,\ 0.220]\)); the joint pre-period test has \(p=0.0028\).
- Holding out \(t=-2\) produces a gap of \(+0.097\)
  (\(95\%\ CI=[-0.042,\ 0.236]\)); the joint test has \(p=0.122\).
- In the censoring-clean sample, the \(t=-3\) gap is \(+0.086\)
  (\(95\%\ CI=[-0.020,\ 0.191]\)); the joint test has \(p=0.066\).

None of the held-out confidence intervals lies inside the predeclared
\(\pm0.05\) equivalence band. The post-acquisition contrast remains close to
the headline estimate when either year is held out, but the positive
\(t=-3\) gap shows that balancing cannot fully establish parallel trends.
Pre-acquisition productivity selection or mean reversion may explain part of
the post-acquisition decline. The estimate is the closest balanced
selected-group comparison supported by the data, not an unqualified causal
effect for always-stayers.

## Extensive versus intensive margin

The formal Shapley decomposition confirms that the result is concentrated on
the intensive margin:

| Component | Patents per inventor-year | Share of total | Two-way 95% interval |
|---|---:|---:|---:|
| Total | -0.1072 | 100.0% | [-0.2043, -0.0101] |
| Extensive margin | -0.0320 | 29.8% | [-0.1064, 0.0425] |
| Intensive margin | -0.0753 | 70.2% | [-0.1323, -0.0183] |

The extensive component is imprecise (\(p=0.398\)); the intensive component
is significant (\(p=0.010\)). Treated initially retained inventors patent in
38.23% of post-deal inventor-years, versus a 39.66% counterfactual. Conditional
on an active year, they produce 2.135 patents instead of 2.328, an 8.3%
reduction. Acquisitions therefore appear to reduce output mainly in years in
which initially retained inventors continue patenting, rather than primarily
by pushing them immediately to the zero-patent margin.

## Acquisition-year selection diagnostic

The positive \(t=0\) coefficient is not a coding or timing error. Event time is
constructed from application year minus deal year, missing inventor-years are
zero-filled identically to the full-cohort analysis, and retention begins only
at \(t=+1\). The following table makes the source of the coefficient explicit:

| Arm and subsequent status | Patents at \(t=-1\) | Patents at \(t=0\) | Change | Active at \(t=-1\) | Active at \(t=0\) | Change |
|---|---:|---:|---:|---:|---:|---:|
| Treated, initially retained | 1.064 | 1.054 | -0.011 | 53.69% | 43.16% | -10.53 pp |
| Control, initially retained | 1.057 | 0.994 | -0.063 | 54.18% | 39.55% | -14.63 pp |
| Treated, no post-deal patent | 0.299 | 0.070 | -0.229 | 22.26% | 4.82% | -17.44 pp |
| Control, not initially retained | 0.279 | 0.101 | -0.178 | 21.42% | 6.17% | -15.24 pp |

The retained treated and retained control groups start at almost identical
levels in \(t=-1\). Between \(t=-1\) and \(t=0\), treated retainers lose only
0.011 patents while retained controls lose 0.063. Their difference-in-changes
is therefore approximately \(+0.052\), which produces the positive
acquisition-year coefficient. The same calculation for active patenting is
\(-10.53-(-14.63)=+4.10\) percentage points.

This does not mean that acquisition raises stayer output. "Initially retained"
is defined using the first patent observed in \(t=+1,\ldots,+5\). Conditioning
on this future event selects treated inventors who remain unusually active
around acquisition. The table is therefore evidence that the selected-group
estimand differs from an unconditional workforce effect. It is a selection
diagnostic, not a treatment-effect estimate.

## Selection and common-support bounds

The pooled trimming calculation gives a wide annual patent-count range from
\(-0.714\) to \(+0.424\). The calculation is transparent but answers only a
narrow descriptive question.

For every inventor classified as initially retained under the original P5c
weights, define
\[
\Delta_i=\frac{1}{5}\sum_{t=1}^{5}Y_{it}-Y_{i,-1}.
\]
The weighted initially retained share is 9.89% among treated inventors and
12.82% among controls. The ratio \(9.89/12.82=0.7714\) means that the
calculation retains 77.14% and discards 22.86% of retained-control weight. It
does this in two deliberately extreme ways:

1. For the lower endpoint, retain the 77.14% of controls with the most
   favorable \(\Delta_i\) values and discard the 22.86% with the most negative
   changes. The retained-control mean is \(+0.466\). Comparing it with the
   treated-retainer mean of \(-0.249\) gives
   \(-0.249-0.466=-0.714\).
2. For the upper endpoint, retain the 77.14% of controls with the most
   negative \(\Delta_i\) values and discard the 22.86% with the most favorable
   changes. The retained-control mean is \(-0.673\). The corresponding
   comparison is \(-0.249-(-0.673)=+0.424\).

The range therefore reports how far the pooled selected-group comparison can
move if the entire excess retention rate among controls is concentrated at
one outcome-change extreme. It is calculated from P5c weights, not the
separately balanced S3 stayer weights. It does not use the unobserved untreated
outcome for a treated inventor, identify who would be retained under both
treatment states, or attach sampling uncertainty to the endpoints. It must be
labelled a pooled worst-tail trimming sensitivity---not a confidence interval,
not a common-support bound, and not a Lee identified set for an
always-retained causal effect.

Ordinary Lee bounds are not valid here without additional assumptions. They
require treatment exchangeability for potential selection and outcomes and a
monotone treatment effect on selection. Entropy balance supports a conditional
parallel-trends argument for outcome changes; it does not establish the
stronger joint independence condition. The pooled lower-treated-retention
direction also reverses in four cohorts (1998, 2002, 2006, and 2010).

A conditional/generalized Lee extension is technically possible but not
automatic. It would have to predefine the always-initially-retained principal
stratum, assume conditional exchangeability or conditional parallel trends
inside that latent stratum, and allow the sign of the retention response to
vary across pretreatment strata. With 151 nominal and 31.53 effective treated
deals, fine strata would be unstable; estimating the sign and trimming within
the same small cells would create a new discretion surface. Moreover, patent
outcomes are observed for non-retainers, so the original missing-outcome
motivation for Lee trimming is not literal here.

The recommended thesis treatment is consequently:

1. report the selected-group ATT transparently;
2. retain the pooled range as a descriptive worst-tail sensitivity;
3. use the supported-versus-unsupported tipping calculation below; and
4. reserve generalized Lee bounds for an appendix only if a coarse,
   prospectively frozen stratification can be defended.

The common-support question is much less threatening. The final design covers
86.18% of classified initially retained inventors. Using
\[
ATT_{\rm all}=pATT_{\rm supported}+(1-p)ATT_{\rm unsupported},
\]
the unsupported 13.82% would need an average effect of \(+0.669\) patents per
inventor-year to reverse the supported-sample estimate. This is a tipping
calculation, not an imputation, but it shows that plausible unsupported-tail
effects are unlikely to reverse the sign.

## Recruitment-composition benchmark

Before outcomes were opened, the established/recent composition of the S3
sample predicted an annual contrast of \(-0.0606\). The observed estimate,
\(-0.1072\), is 0.0467 patents more negative and 77% larger in magnitude.
Recruitment composition alone therefore does not account for the observed
stayer contrast.

This comparison is descriptive. It does not solve post-treatment selection:
initially retained inventors are observed only after acquisition, and
acquisition may itself affect who enters this group.

## Secondary outcomes

All secondary outcomes use the same primary S3 roster and weights. No outcome
changes support, matching, or sample membership. The table reports the
predeclared two-way deal/inventor-clustered inference:

| Outcome | Annual contrast | Two-way 95% interval | \(p\) | Joint pretrend \(p\) |
|---|---:|---:|---:|---:|
| Probability of patenting | -1.43 pp | [-4.77, 1.90] | 0.398 | balanced by design |
| Technology drift | +0.009 | [-0.009, 0.028] | 0.332 | 0.512 |
| OECD PQII total | -0.043 | [-0.086, -0.001] | 0.047 | 0.460 |
| Cassi--Ornaghi five-year citations | +0.119 | [0.028, 0.210] | 0.010 | \(<0.001\) |
| Cassi--Ornaghi citations per patent | +0.197 | [0.108, 0.287] | \(<0.001\) | 0.025 |

The quantity result is not primarily an extensive-margin effect. The annual
probability of patenting falls by only 1.43 percentage points and is
imprecisely estimated. Relative to the matched counterfactual active-patenting
rate of 39.66%, the point estimate is a 3.6% reduction, but the interval also
includes no reduction. This does not show that acquisition never causes
inventors to stop patenting. The sample already conditions on an observed
post-deal focal patent, which selects inventors who patent at least once after
acquisition. Within that selected group, evidence for a persistent change in
the probability of patenting is weak. This agrees with the Shapley
decomposition, which attributes 70.2% of the patent-count decline to fewer
patents in active years.

Technology drift is small and statistically indistinguishable from zero. Its
positive sign would indicate movement away from the inventor's pre-deal IPC4
portfolio, but the interval includes both a small convergence and a moderate
increase in drift. Its joint pretrend test is reassuring. The outcome is,
however, defined for only about 39% of weighted inventor-years because a
technology vector requires observed patenting and classified IPC information.
The result therefore says that the technologies embodied in observed stayer
patents do not shift detectably. It cannot rule out technological redirection
among inventors who stop patenting or in work that never produces a patent.

Linkage-scaled OECD PQII falls by 0.043 units per inventor-year. Its pretrend
test passes and the two-way interval barely excludes zero. PQII coverage is
approximately 83% for treated and 82% for control weight, so this remains
secondary evidence. PQII here is a total quality-weighted output measure, not
quality per surviving patent. It can decline because fewer patents are filed,
because the remaining patents have lower PQII, or both. The conditional
per-patent PQII contrast is much smaller, \(-0.006\), and statistically
indistinguishable from zero, although that conditional series has unfavorable
pretrends. The most defensible interpretation is therefore that total
quality-adjusted inventive output falls alongside patent quantity; the data
do not establish that each surviving patent becomes worse.

The Cassi--Ornaghi citation fields produce positive post-deal contrasts,
including 0.119 additional five-year citations per inventor-year and 0.197
additional citations per patent. The source matches 97.0% of active treated
rows and 95.6% of active control rows, so missing linkage is not the main
problem. The strong rejection of parallel pretrends is: treated retainers
already have a more favorable citation path before acquisition. The positive
post coefficient may therefore reflect persistent selection of highly cited
inventors, differences in patent composition, or genuine post-deal portfolio
pruning. The current design cannot distinguish these explanations. The
buffered sample also attenuates the total-citation contrast to 0.044 and it is
no longer statistically significant.

Taken together, the secondary outcomes sharpen rather than overturn the
quantity result. Initially retained inventors file fewer patents, and most of
the reduction occurs within years in which they continue patenting. There is
no detectable shift into more distant IPC4 technologies. Total PQII declines,
but neither PQII nor citations support a causal claim that the remaining
patents become lower quality. If anything, the descriptive citation evidence
suggests that the smaller patent portfolio is compositionally more highly
cited. This pattern is consistent with selective project pruning or portfolio
rationalization, but it is not a mechanism test: post-treatment stayer
selection and citation pretrends prevent that causal interpretation.

## Interpretation

The results support a focused empirical statement: among inventors observed
patenting initially within the merged corporate ecosystem, patent output
falls by roughly 0.11 patents per year relative to similarly retained
inventors at clean control firms. The decline appears from approximately the
third post-acquisition year and survives all frozen sample and classification
variants.

The result is economically meaningful, robust in sign, and significant under
the chosen two-way inference. The held-out \(t=-3\) diagnostic and the broad
Lee selection range nevertheless prevent a strong principal-stratum causal
claim. The most defensible wording is a negative, entropy-balanced contrast
for observed initially retained inventors, with a formal selection caveat.

## Artifacts

- `s4_headline_post_att.csv`: all point estimates and inference methods.
- `s4_event_study_dynamic.csv`: complete event-study coefficients.
- `s4_joint_pretrend_tests.csv`: formal pre-period tests.
- `reporting/s4_primary_magnitude.csv`: levels and relative magnitudes.
- `reporting/s4_loyo_heldout_diagnostics.csv`: held-out-year results.
- `reporting/figure_s4_primary_event_study.*`: primary event study.
- `reporting/figure_s4_patent_sensitivity.*`: frozen-specification forest
  plot.
- `s4_certification.csv` and `s4_tooth_tests.csv`: production checks.
- `../P5B_STAYER_S5_SELECTION_DECOMP/s5_sample_funnel.csv`: full-cohort to
  initially retained sample audit.
- `../P5B_STAYER_S5_SELECTION_DECOMP/s5_pipeline_alignment.csv`: proof that
  S4 uses the same certified P6 panel as the clean full-cohort DiD.
- `../P5B_STAYER_S5_SELECTION_DECOMP/s5_extensive_intensive_decomposition.csv`:
  exact Shapley decomposition with two-way clustered uncertainty.
- `../P5B_STAYER_S5_SELECTION_DECOMP/s5_t0_selection_diagnostic.csv`:
  acquisition-year changes by arm and retention status.
- `../P5B_STAYER_S5_SELECTION_DECOMP/reporting/table_s5_t0_selection.*`:
  thesis-ready acquisition-year selection table.
- `../P5B_STAYER_S5_SELECTION_DECOMP/s5_lee_selection_bounds.csv` and
  `s5_common_support_tipping_summary.csv`: selection and support sensitivity.
- `../P5B_STAYER_S5_SELECTION_DECOMP/s5_lee_assumption_audit.csv`:
  explicit audit of why the pooled trimming range is not a formal Lee bound.
- `../P5B_STAYER_S5_SELECTION_DECOMP/s5_recovery_feasibility_summary.csv`:
  audit of whether the 412 P5c-excluded initially retained inventors have
  clean-U2 retained controls.
- `../P5B_STAYER_S6_SECONDARY_OUTCOMES/s6_secondary_headline.csv`:
  all secondary-outcome estimates and inference methods.
- `../P5B_STAYER_S6_SECONDARY_OUTCOMES/reporting/table_s6_stayer_outcomes.*`:
  thesis-ready combined outcome table.
- `../P5B_STAYER_S6_SECONDARY_OUTCOMES/reporting/figure_s6_secondary_event_studies.*`:
  dynamic secondary-outcome estimates.

All original S4 checks continue to pass. The S5 decomposition reproduces the
frozen S4 point estimate to numerical precision, its components sum exactly
to that estimate, and both new positive tooth-tests fire.
