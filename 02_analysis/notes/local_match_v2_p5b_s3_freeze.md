# Local Match v2 P5b S3: retained-inventor support and weighting freeze

Status: amended and frozen before S3 outcome estimation

## 1. Estimand and interpretation

S3 compares initially retained treated inventors with inventors who remain in
their clean control firms. It estimates a balanced selected-group contrast.
It is not a principal-stratum ATT unless retention is unaffected by
acquisition, an assumption the thesis does not impose. Selection diagnostics
and later bounds carry the causal interpretation.

The main initially-retained estimate will be accompanied by a predeclared
established-versus-recently-recruited split. This separates retention from
career-stage heterogeneity and is a primary stayer output, not an
after-the-fact subgroup search.

## 2. Required sample variants

All variants will be estimated and reported regardless of their results.

1. **Primary resolved \(t=+1,\ldots,+5\)**: the approved resolved-affiliation
   rule, including both P2 focal routes.
2. **Route-consistent \(t=+1,\ldots,+5\)**: exclude the 151 treated inventors
   whose target-company and resolved-group routes disagree.
3. **Raw-unmixed \(t=+1,\ldots,+5\)**: exclude treated and control rows with
   both focal and outside raw patent-level group evidence in the first
   post-patenting year.
4. **Timing companion \(t=+2,\ldots,+5\)**: repeat the resolved rule while
   excluding \(t=+1\) classification evidence.

The primary specification is not chosen by comparing these results.

## 3. Frozen local support

S3 reuses the certified P5 U2 edge-cover graph and P5c covariates. It does not
recompute technological distances, change IPC4 granularity, admit U3
acquirers, or search across calipers.

For each sample variant:

1. retain only treated and control inventors satisfying the symmetric
   retention rule;
2. semi-join both sides to the finalized, certified P5c roster;
3. retain deal stacks with at least one retained treated inventor and at least
   one retained control row;
4. allocate new primary base weights: one to each treated inventor and, within
   each deal, treated count divided by control-row count to each control row;
5. resolve new cohort-level entropy weights from scratch.

No three-control threshold is imposed on each treated inventor. That proposed
rule is not required by the cohort-level entropy estimator and would be
invalid on P5's projection-preserving edge cover. The number of retained
control firms is reported as a dependence diagnostic, not imposed as a hard
support gate. This preserves five small deal stacks containing 18 treated
inventors whose one retained control firm nevertheless supplies eligible
inventors. Inference remains deal-aware, and these stacks receive a dedicated
single-firm sensitivity flag. This amendment was made outcome-blind, before
any S3 outcome was opened.

## 4. Balance vectors and outcome-blind feasibility amendment

The strict S3 stress test balanced, within each acquisition cohort:

- five annual patent counts at \(t=-5,\ldots,-1\);
- five annual active-patenting indicators at \(t=-5,\ldots,-1\);
- `career_age`;
- `focal_group_exclusivity`;
- `firm_log_patent_stock_5y`;
- `firm_log_inventor_count_5y`;
- `firm_patent_trajectory`.

The strict vector was initially reported infeasible before outcomes were
opened in cohorts 1995, 2001, 2008, and 2010. Firm patent trajectory had
already been designated for removal in the approved stayer plan. Removing
only that trajectory restored exact count-plus-active balance in 1995 and
2001. Subsequent outcome-blind diagnostics showed that the remaining two
failures had different causes:

- **2010 was a numerical false failure.** A generic entropy solution followed
  by an exact Newton refinement reaches the same moment solution while
  preserving the complete production vector.
- **2008 had three treated observations at the convex-hull boundary.** A
  maximum-retention support program identified inventors `174106`, `556447`,
  and `556448` as the only three exclusions needed for a stable exact solution.
  Excluding only two was technically feasible but produced much weaker ESS and
  concentration. The three-inventor exclusion was therefore frozen using
  support and ESS only, without inspecting outcomes.

The common production vector therefore retains:

- all five annual patent counts;
- all five annual active-patenting indicators;
- `career_age`;
- `focal_group_exclusivity`;
- `firm_log_patent_stock_5y`;
- `firm_log_inventor_count_5y`.

`firm_patent_trajectory` is the only balance variable removed from the
headline, both LOYO designs, route-consistent design, and raw-unmixed design.
The two firm-scale measures preserve explicit matching on inventive output and
organizational size. All 17 acquisition cohorts enter those five designs.

The \(t=+2,\ldots,+5\) timing companion has only 57 treated inventors in cohort
2010. Exact balance on both closely related firm-scale measures produced a
reuse-adjusted ESS ratio of 0.335, below the prospectively frozen 0.50 floor.
For this sensitivity only, firm patent scale remains balanced and firm
inventor-count scale is omitted. All five annual patent counts, all five
annual active-patenting indicators, career age, and exclusivity remain.

All included production cells balance the retained variables exactly. Main
design in-sample pre-period equality is therefore a mechanical balance check,
not a placebo test.

## 5. Solver and feasibility hierarchy

S3 uses the certified P5/P5c hierarchy, augmented only by a numerically robust
warm-start path for feasible boundary cells:

1. exact Newton entropy balancing;
2. if Newton fails numerically, obtain a generic entropy solution and refine
   it to the exact Newton moment solution;
3. if exact balance fails, `optweight` with 0.05 tolerance;
4. if needed, `optweight` with 0.10 tolerance;
5. otherwise classify the cohort cell as infeasible.

All 17 acquisition cohorts are used in all six production specifications.
Treated weights remain their prescribed base weights. Control mass must equal
treated mass. Reuse-adjusted control-inventor ESS, not stack-row ESS, governs
the existing acceptable ESS ratio floor of 0.50.

The certification reports:

- pre-support and supported treated counts and common-support coverage (not
  the economic initial-retention rate);
- supported deals and pooled effective treated-deal count;
- exact/approximate solver tier by cohort;
- maximum balanced SMD;
- reuse-adjusted inventor ESS and concentration;
- effective control-firm count;
- largest treated-deal share.

The pooled primary design must retain at least 80% of all status-eligible
treated inventors and at least 20 effective treated deals.

## 6. Held-out diagnostics

Only the two pre-periods that were problematic in the full-cohort analysis are
held out from the production vector:

- LOYO \(t=-3\): omit patent count and active patenting at \(t=-3\);
- LOYO \(t=-2\): omit patent count and active patenting at \(t=-2\).

These variants use the same primary support roster and all 17 cohorts. They
differ only in balance constraints. Their outcome estimates are diagnostic
and cannot be used to select the main design.

The patent-count equivalence band is \(\pm0.05\) patents per inventor-year. A
held-out confidence interval not contained in that band is labeled
**uninformative**, not passed.

## 7. Composition benchmark

Before any S3 outcome is opened, the stayer sample's established/recent
composition is used to calculate a fixed descriptive benchmark. The frozen
reference effects are \(-0.0867\) for established inventors and \(-0.0534\)
for the recent/full-cohort reference. Their stayer-share-weighted average is
stored in `s3_composition_benchmark.csv`.

This benchmark is not an estimator and cannot select the design. It answers a
narrow interpretation question: whether a smaller observed stayer contrast is
approximately what the stayer sample's recruitment composition alone would
predict. The established-stayer subgroup contains relatively few inventors
per deal, so imprecision is anticipated and will be reported.

## 8. Outcome firewall

S3 reads only P2/P3 status and covariate interfaces, the frozen P5 support
graph, P5c balance covariates, and the raw first-post affiliation audit. It
does not read P6 outcomes or treatment-effect estimates. All sample variants
and constraints are hashed before the first stayer outcome is opened.
