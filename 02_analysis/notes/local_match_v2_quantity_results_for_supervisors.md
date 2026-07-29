# Full-cohort DiD: supervisor storyline and certified results

**Estimated reading time:** 15--20 minutes.

This note presents the full pre-deal target-inventor cohort. The separately
selected initially-retained-inventor analysis is deferred until the
full-cohort DiD package is complete.

## Decisions requested from supervisors

### 1. Thesis scope and page allocation

The thesis should remain a 35-page applied empirical paper. I propose one page
on what patents measure in pharmaceutical innovation. It will explain that
patents capture codified upstream inventive output, not complete R&D effort,
employment, clinical development, drug approval, or welfare.

| Section | Pages | Principal content |
|---|---:|---|
| Abstract | 0.5 | Question, design, principal magnitude, and qualification |
| 1. Introduction | 2.0 | Motivation, result, contribution, and roadmap |
| 2. Background, Literature, and Hypotheses | 4.0 | Pharmaceutical acquisitions; patent measurement; mechanisms; hypotheses |
| 3. Data and Sample Construction | 4.5 | Data, deal and inventor construction, outcomes, descriptives |
| 4. Empirical Design | 5.0 | Placebo cohorts, local support, entropy balancing, LOYO, inference |
| 5. Main Results: Full Target-Inventor Cohort | 5.5 | Balance, patent count, LOYO, margins, secondary outcomes |
| 6. Stayers, Selection, and Individual Heterogeneity | 5.5 | Initially retained definition, separate balance, selection, bounds |
| 7. Technological Relatedness and Mechanisms | 4.0 | DealSim, TechDrift, relatedness heterogeneity, mechanisms |
| 8. Robustness and Interpretation | 2.5 | Inference, support, timing, censoring, scope |
| 9. Conclusion | 1.5 | Findings, interpretation, policy relevance, limits |
| **Total** | **35.0** | |

### 2. How much technological-relatedness analysis belongs in the main text?

The current structure risks creating three separate results papers inside one
thesis: the full cohort, initially retained inventors, and technological
relatedness. Should Section 7 remain a four-page main section, be compressed to
roughly 2--2.5 pages, or move largely to the appendix? My recommendation is to
shorten rather than drop it: retain the DealSim prediction and one main
tercile figure in the text, but move the quadratic, spline, and extended
mechanism specifications to the appendix. This preserves the novel
relatedness contribution without weakening the central inventor-output story.

## Executive summary

- The first design applies standard Callaway--Sant'Anna (2021) DiD using the
  full universe of not-yet-treated inventors as controls, without placebo
  cohort construction or matching. Its strong pre-treatment differences show
  that this conventional CS(2021) comparison is not credible for this sample
  without further design work.
- The qualifying-year-gap analysis explains an important part of the failure.
  Inventors enter through a recent patent, so their measured output
  mechanically peaks in the qualifying year. The peak moves across event time
  with the recruitment gap rather than occurring at one common pre-acquisition
  date.
- I therefore assign eligible controls placebo cohort years and apply the same
  recruitment clock. This removes the mechanical timing mismatch, but the
  unmatched placebo DiD still shows different treated and control lifecycle
  trajectories. Recruitment alignment alone is not enough.
- The preferred design then restricts comparisons to clean local firm and
  IPC4 support and entropy-balances controls to the treated cohort's complete
  five-year pre-acquisition patent history and lifecycle characteristics.
- The matched design estimates **0.053 fewer patents per inventor-year**, or
  **0.267 fewer patents over five years**. This is a **13.5% decline relative
  to average pre-acquisition output** and 33.7% of estimated post-acquisition
  counterfactual patenting.
- The effect remains negative and statistically significant in every
  leave-one-pre-year-out specification. The largest point-estimate deviation
  is 6.2% of the headline effect, and the estimate is nearly unchanged in the
  censoring-clean cohorts.
- Held-out \(t=-3\) and \(t=-2\) gaps still qualify parallel trends. The result
  is the closest supported causal approximation available in these data, not
  an assumption-free causal estimate.
- Secondary results suggest that acquisition changes the composition as well
  as the amount of inventive output: patent quality is lower in the full
  sample, while the original Cassi--Ornaghi citation measure is positive but
  not robust to the censoring-clean cohort restriction.

## 1. Descriptive statistics

The presentation begins with the descriptive-statistics package already
constructed and certified by `14_build_data_section_descriptives.R`. It reports
the acquisition sample, treated inventors and deals by cohort, inventor
patenting, status composition, and deal/inventor concentration. The
transaction descriptions distinguish acquisitions from mergers of equals and
name the resulting entity where appropriate.

These existing outputs will be imported rather than regenerated. Their
denominators will be labelled as the full acquisition sample, eligible
full-cohort sample, or supported P5c sample so that descriptive and matched
counts are not inadvertently combined.

The descriptive evidence establishes two facts. First, inventor patenting
declines sharply around acquisition. Second, patenting also declines with
inventor age and time since recruitment, so the raw decline cannot by itself
be interpreted as an acquisition effect.

## 2. From standard CS(2021) to the matched placebo DiD

The first design is a conventional Callaway--Sant'Anna (2021) DiD. It uses the
full universe of not-yet-treated inventors as the counterfactual, without
placebo cohort construction, local matching, or entropy balancing. Inventor
output peaks before acquisition and then falls, but the event study also shows
large pre-treatment differences. The standard CS(2021) design is therefore
not applicable to this sample as a credible causal design without additional
counterfactual construction.

The qualifying-year-gap diagnostic identifies one source of that failure.
Inventors qualify through a recent pre-deal patent. When the sample is split
by the gap between the qualifying patent and the deal year, each subgroup
peaks in its own qualifying year. The hump moves with the recruitment clock;
it is not synchronized at one common pre-acquisition event time.

The next design assigns eligible controls placebo cohort years and applies the
same recruitment rule. Treated and placebo-control inventors then share the
broad post-event lifecycle decline. The unmatched placebo-DiD estimate is
close to zero (\(-0.0028\), \(p=0.858\)), but their pre-period levels and
trajectories still differ, and the joint raw pretrend test rejects equality
(\(p<0.001\)). Placebo cohort construction fixes the mechanical recruitment
clock, but it does not by itself create comparable inventor lifecycles.

The final design therefore imposes local technological and firm support and
entropy-balances the admissible controls to the treated cohort's
pre-acquisition patent history and lifecycle characteristics. The first two
designs diagnose why this matched placebo DiD is necessary; they are not
competing headline estimates.

## 3. Entropy balancing as the matching strategy

Entropy balancing is used to adjust the control sample for observable
differences in inventor lifecycle, recent productivity, technology, and firm
environment. Following [Hainmueller
(2012)](https://doi.org/10.1093/pan/mpr025), it reweights admissible controls so
that their specified pre-treatment moments match those of the treated cohort.
The objective is a clean common-support ATT, not merely a visually similar
control path.

Before weighting, the preferred design imposes these firm and inventor support
restrictions separately within each acquisition cohort \(g\):

1. **U2-clean donor firms.** A control firm is eligible only if it has no
   target event on or before \(g+5\) and no acquirer event during
   \(g-5,\ldots,g+5\). Control inventors with target exposure on or before
   \(g+5\) are also excluded.
2. **Firm support.** Candidate firms must share IPC4 technology with the target
   and lie within the frozen Stage-1 caliper of 2.0 on the standardized
   firm-distance system. The design retains the nearest 50 admissible firms,
   using IPC4 cosine similarity, five-year firm patent stock, and five-year
   inventor count; firm patent trajectory remains an exact balance moment.
3. **Inventor support.** Inventor pairs must share IPC4 support and satisfy the
   frozen Stage-2 caliper of 1.5 on log five-year patent output, pre-deal patent
   trajectory, career age, and one-minus IPC4 cosine distance. Every supported
   treated inventor must have at least three admissible controls drawn from at
   least two control firms.

Only after these restrictions does entropy balancing reweight the controls to
the treated cohort within acquisition cohorts. The final P5c design balances:

- annual patent counts from \(t=-5\) through \(t=-1\);
- annual active-patenting indicators over the same years;
- inventor career age and focal-group exclusivity;
- firm patent stock, inventor count, and patent trajectory; and
- the frozen IPC4 support structure.

The frozen roster contains 27,078 supported treated inventors across 341
estimating deals. The finalized support construction retains 92.8% of 29,170
eligible treated inventors and 99.4% of the 343 eligible deals, leaving 341
nominal deals in the ATT. The
effective treated-deal count is 36.9 after accounting for deal-size
concentration. Every production cohort solves exactly; the largest
post-weighting absolute standardized difference is below
\(9\times10^{-8}\). The most demanding cohort retains a reuse-adjusted control
ESS equal to 75.1% of its treated count.

The final presentation will include:

1. a balance table with retention, ESS, nominal and effective deals;
2. a love plot showing absolute standardized differences before and after
   weighting on pre-deal variables; and
3. cohort-level support and ESS distributions in the appendix.

Post-deal outcomes will not appear in the love plot. They are outcomes that
acquisition may change, not balance targets.

## 4. Main patent-count result and LOYO analysis

The preferred matched design estimates an average effect of **-0.0534 patents
per inventor-year** over \(t=+1,\ldots,+5\) (wild-bootstrap 95% CI
\([-0.0909,-0.0168]\), \(p=0.0077\)). This equals **0.267 fewer patents per
inventor over five years**, or a **13.5% decline** relative to the treated
cohort's average annual patent output over \(t=-5,\ldots,-1\).

Patent applications fall sharply at the end of the underlying data: from
54,850 applications in 2013 to 28,096 in 2014 and 1,143 in 2015. The
1994--2008 cohort restriction therefore checks whether the headline quantity
effect is created by right-censoring of late-cohort post-treatment years. This
censoring-clean companion is almost identical: \(-0.0519\) patents per
inventor-year (95% CI \([-0.0912,-0.0119]\), \(p=0.0163\)), a 13.4% decline
relative to average pre-treatment output. Right-censoring exists in the source
data, but it does not explain the estimated quantity result.

### Complete leave-one-pre-year-out evidence

Balancing every displayed pre-treatment outcome makes those displayed
coefficients zero by construction. Hainmueller's [official entropy-balancing
explainer](https://j-hai.github.io/projects/entropy-balancing-explainer/)
therefore recommends leaving at least one pre-period outside the constraints
when a genuine placebo check is desired. The complete leave-one-pre-year-out
(LOYO) grid implements that recommendation.

The post-treatment effect survives every LOYO specification. In the directly
comparable designs that hold out \(t=-5,-4,-3,\) or \(-2\), the annual
full-sample ATT ranges only from \(-0.0543\) to \(-0.0501\). Every estimate:

- remains negative;
- is statistically distinguishable from zero under the governing wild
  bootstrap;
- lies inside the headline confidence interval; and
- differs from the headline estimate by no more than 0.0033 patents per
  inventor-year, or **6.2% of the headline effect's magnitude**. The complete
  LOYO range is 0.0042 patents, or 7.9% of the headline magnitude.

The \(t=-1\) held-out design, which uses \(t=-4\) as its reference, also
produces a negative and significant post estimate
(\(-0.0795\), \(p=0.0001\)). It is reported separately because its reference
period differs from the other LOYO designs.

The genuinely held-out pre-period gaps are:

| Held-out year | Gap | 95% CI |
|---:|---:|---:|
| \(t=-5\) | -0.008 | [-0.059, 0.043] |
| \(t=-4\) | -0.005 | [-0.055, 0.046] |
| \(t=-3\) | 0.045 | [0.006, 0.083] |
| \(t=-2\) | 0.042 | [0.010, 0.074] |
| \(t=-1\) | 0.031 | [-0.019, 0.081] |

The positive \(t=-3\) and \(t=-2\) gaps are a genuine parallel-trends
qualification. They show that exact balance in the full P5c design does not,
by itself, reassure us about the counterfactual trend once individual years
are deliberately left unmatched. The negative post estimate nevertheless
survives the specifications in which each hump is left visible, remains
stable in the censoring-clean sample, and persists under an alternative
recruitment rule. The design is therefore the closest supported approximation
to the causal ATT available in these data, but the held-out humps prevent an
unqualified causal interpretation.

[Verginer et al.
(2025)](https://www.nature.com/articles/s41599-025-04894-w) explicitly
separate an early recruitment phase from the later pre-treatment observation
period. Applying that structure here checks whether the P5c result is created
by admitting inventors during the five-year baseline window. It is not an
equivalent replacement estimand: requiring evidence at \(t=-7\) or \(t=-6\)
selects established, experienced inventors with longer firm histories and is
less representative of the recently active target workforce that motivates
the thesis. It also makes strict inventor-and-firm balance infeasible in three
cohorts.

Where feasible, the early-recruitment design produces an even larger negative
estimate: \(-0.0867\) patents per inventor-year (95% CI
\([-0.1715,-0.0025]\), \(p=0.0436\)). The 16-cohort inventor-balanced
companion estimates \(-0.0894\) (95% CI \([-0.1492,-0.0242]\),
\(p=0.0074\)). These results show that the headline finding is not merely an
artifact of the main recruitment rule. Because the sample and estimand differ,
the full Verginer-style analysis belongs in the appendix as
established-inventor heterogeneity rather than as a superior headline design.

A transparent additive calibration gives a sign-breakdown multiple of 1.20:
an unobserved post-period violation would need to be 1.20 times the largest
observed held-out pre-period discrepancy to offset the annual point estimate.
This is a sensitivity statistic, not a formal Rambachan--Roth confidence set.

## 5. Extensive and intensive margins

Under the frozen P5c weights, the estimated post-acquisition counterfactual
for treated inventors is 0.159 patents per inventor-year, while their weighted
observed mean is 0.105. Their difference is the headline ATT of \(-0.0534\).
It equals **33.7% of estimated post-acquisition counterfactual patenting** and
13.5% of average pre-treatment output. The accounting decomposition of that
difference is:

- **Extensive margin:** \(-0.0396\) patents per inventor-year, or **74.2%** of
  the total decline. The probability of patenting in a given year falls from
  6.93% to 5.11%, a decline of 1.82 percentage points.
- **Intensive margin:** \(-0.0138\) patents per inventor-year, or **25.8%** of
  the accounting difference. Among active inventor-years, the weighted mean
  is 2.29 patents under the counterfactual and 2.06 among treated inventors.

The decomposition is exact and order-independent. The intensive component is
descriptive because active patenting is itself affected by acquisition; it is
not a separate causal ATT conditional on post-treatment activity.

The result therefore reflects both a lower probability that an inventor
patents in a given year and, in accounting terms, fewer patents in active
inventor-years. The latter is not interpreted here as a causal effect among
active inventors. Its substantive interpretation is deferred to the later
analysis of what happens to inventors initially retained in the merged entity.

## 6. Secondary outcomes

The same frozen design produces:

| Outcome | 1994--2010 average annual ATT | 1994--2008 companion |
|---|---:|---:|
| Probability of patenting | -0.0182 [-0.0386, 0.0018] | -0.0166 [-0.0382, 0.0050] |
| OECD PQII | -0.0105 [-0.0200, -0.0011] | -0.0084 [-0.0181, 0.0013] |
| TechDrift | 0.0076 [-0.0256, 0.0409] | 0.0168 [-0.0142, 0.0477] |
| Forward citations of patents | 0.0446 [0.0011, 0.0894] | 0.0189 [-0.0184, 0.0552] |

The following figures show the complete matched DiD paths. Patent count and
active patenting are annual balance targets, so their headline pre-period
coefficients are zero by construction and the LOYO estimates in Section 4
provide their genuine placebo tests. PQII, TechDrift, and forward citations
were not balance targets; their displayed pre-period paths are therefore
genuine diagnostics.

![All outcomes, full cohorts](../output/figures/local_match_v2/fullcohort_results/figure_d5a_all_outcomes_event_study_full.png)

![All outcomes, censoring-clean cohorts](../output/figures/local_match_v2/fullcohort_results/figure_d5b_all_outcomes_event_study_buffered.png)

The forward-citation measure is the original Cassi--Ornaghi `fwCit5w` field,
aggregated at the inventor-year level. The source contains 2,034,982 unique
inventor-years, has no missing or negative citation values, and matches 93.7%
of active inventor-years in the P6 panel. On matched active rows, its patent
count correlates 0.984 with the P6 patent count. The source-total and
observed-row citation variants are nearly identical.

The positive full-sample citation estimate does not establish an overall
quality gain: it is smaller and statistically indistinguishable from zero in
the censoring-clean cohorts. Citations per source patent are positive in both
samples, which is consistent with selective filing or portfolio
rationalization among the patents that remain. This is secondary,
composition-oriented evidence, not a reversal of the main quantity result.
OECD PQII is also secondary because linkage and late-sample coverage are
incomplete. The qualifying-year-gap fingerprint remains important when
showing naive citation paths because recruitment is itself triggered by a
pre-treatment patent.

### Precision and robustness

The secondary results are not uniformly insignificant. PQII is statistically
negative in the full sample (\(p=0.029\)); total Cassi--Ornaghi forward
citations are statistically positive in the full sample (\(p=0.045\)); and
citations per source patent are positive in both cohort windows. These
findings are not uniformly robust to the censoring-clean restriction, so they
remain secondary.

The dynamic estimates contain more signal than the five-year average alone
suggests. Active patenting and PQII are individually negative at
\(t=+1,+2,+3\) under two-way deal/inventor-clustered inference. Cassi--Ornaghi
forward citations are individually positive throughout \(t=0,\ldots,+5\).
These event-time results clarify the timing, but they do not replace the
governing wild-bootstrap inference for the average post-treatment ATT and
should not be read as independent hypothesis tests.

The unbalanced secondary-outcome pretrend tests sharpen this assessment:

| Outcome | Joint pretrend \(p\), 1994--2010 | Joint pretrend \(p\), 1994--2008 |
|---|---:|---:|
| OECD PQII | 0.589 | 0.656 |
| TechDrift | 0.017 | 0.032 |
| Forward citations of patents | 0.090 | 0.136 |

PQII has reassuring pre-period evidence. Its full-sample result also survives
every LOYO weighting scheme: the annual estimate ranges from \(-0.0155\) to
\(-0.0097\), and every governing 95% interval remains below zero. Its weakness
is late-sample coverage, not instability across the matching designs.

TechDrift fails the joint pretrend test in both cohort windows, and its LOYO
point estimates range from \(-0.0021\) to \(0.0123\), with every interval
crossing zero. This outcome currently supports neither a positive nor a
negative acquisition effect. Forward citations have a mild full-sample
pretrend qualification and lose significance in the censoring-clean sample.

Active patenting narrowly misses the conventional 5% threshold in the full
sample (\(p=0.072\)). Its confidence interval ends only 0.18 percentage points
above zero. The nominal sample is large, but treatment varies across 341
deals and the treated-weight concentration implies only 36.9 effective deals.
The low annual patenting rate and conservative deal-level wild-bootstrap
inference therefore limit precision.

Active-patenting estimates are nevertheless stable across LOYO designs:
they range from \(-0.0262\) to \(-0.0170\). Most intervals narrowly include
zero; only the \(t=-1\) holdout excludes it. This is robust directional and
magnitude evidence, but not uniform 5% significance.

TechDrift is different: its estimates are small and its intervals span
meaningful positive and negative effects in both samples. The current data do
not reveal a direction. This is an informative null rather than a result that
can be repaired by changing inference.

The defensible route to greater precision is better measurement or more
independent treatment variation: extended patent coverage after 2015,
improved OECD linkage, additional acquisition cohorts, or a prospectively
frozen covariate-adjusted efficiency specification. Changing samples,
transformations, clustering, or outcome definitions after seeing which
version crosses \(p=0.05\) would not make the evidence more robust. Any added
efficiency specification should be frozen first and reported alongside the
current estimates, regardless of its significance.

## 7. Interpretation and overall story

The evidence supports the following account:

1. Inventor patenting falls substantially around acquisition, but raw paths
   mix acquisition effects with common inventor lifecycles and the mechanical
   timing of cohort qualification.
2. Unmatched treated and control inventors are not comparable before the deal,
   motivating local support restrictions and entropy balancing.
3. U2-clean firm restrictions and entropy balancing adjust the comparison for
   observable lifecycle, recruitment, technology, and firm-environment
   differences while retaining most treated inventors and deals.
4. The matched design estimates a persistent 13.5% decline relative to average
   pre-acquisition patent output, equal to 33.7% of estimated post-acquisition
   counterfactual patenting.
5. The estimate survives every LOYO specification, including designs that
   leave the observed \(t=-3\) and \(t=-2\) pre-treatment humps visible; the
   largest point-estimate deviation is only 6.2% of the headline magnitude.
6. Those humps require an explicit parallel-trends qualification, but neither
   lifecycle diagnostics nor the feasible early-recruitment design explains
   away the negative post effect.
7. Approximately three-quarters of the accounting difference operates through
   the probability of patenting in a given year and one-quarter through output
   conditional on an active inventor-year.
8. Secondary outcomes are mixed: PQII falls in the full sample, TechDrift is
   imprecise, and forward citations rise only in the full sample. The robust
   conclusion is therefore about patent quantity; the composition results are
   informative but secondary.

Recommended supervisor wording:

> Raw inventor patenting declines after acquisition, but untreated inventors
> exhibit similar lifecycle dynamics and differ from treated inventors before
> the deal. I therefore restrict donors to clean local firm and IPC4 support
> and use entropy balancing to align the complete five-year pre-acquisition
> patent path and lifecycle characteristics. The matched design estimates
> 0.053 fewer patents per inventor-year, equivalent to a 13.5% decline relative
> to average pre-acquisition output and 33.7% of estimated post-acquisition
> counterfactual patenting. The estimate remains negative and statistically
> significant in every leave-one-pre-year-out specification, with a maximum
> point-estimate deviation equal to 6.2% of the headline effect. The visible
> held-out humps prevent an unqualified causal claim, but their inability to
> explain the post estimate, together with the lifecycle and early-recruitment
> diagnostics, makes the matched ATT the closest supported causal
> approximation available in these data.

## Presentation assets

- Descriptive tables and concentration text: outputs of
  `02_analysis/R/14_build_data_section_descriptives.R`.
- Raw treated-inventor path:
  `supervisor_memo/memo_figure1_raw_patents.png`.
- Naive full-cohort DiD:
  `appendix_raw_did/appendix_raw_did_full_cohort.png`.
- Recruitment-rule fingerprint:
  `preliminary_results/figure12_qualifying_gap_split.png`.
- Matched patent-count and LOYO summary:
  `P6_QUANTITY_COMMUNICATION_PACKAGE/quantity_supervisor_summary.png`.
- Final design, balance, LOYO, decomposition, and secondary-outcome figures:
  `figures/local_match_v2/fullcohort_results/`.
- Certified final tables and source manifests:
  `P6_FULLCOHORT_RESULTS_PACKAGE/`.
