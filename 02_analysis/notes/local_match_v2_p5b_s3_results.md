# Local Match v2 P5b S3: retained-inventor design results

Status: implemented and certified; no S3 outcome was opened

## Bottom line

The recovered retained-inventor design preserves annual patent-count,
annual active-patenting, and firm-scale balance while restoring all 17
acquisition cohorts. The primary sample contains 2,663 initially retained
treated inventors across 151 deals. It covers 86.18% of the 3,090 inventors
classified as initially retained.

The 86.18% figure is **common-support coverage, not an employee-retention
rate**. All 3,090 inventors in its denominator already satisfy the
patent-based initial-retention definition. The coverage rate is lower than in
the full target-inventor analysis because the stayer design requires two
conditions simultaneously: a treated inventor must belong to the previously
certified local common-support population, and the corresponding donor pool
must contain control inventors who continue patenting with their clean control
firm after the pseudo-event. Conditioning both treatment arms on this
post-event patent-location status reduces the available comparison population.

All 102 cohort cells in the six required production specifications solve with
exact entropy balance. The largest post-weighting absolute SMD is
\(8.93\times10^{-8}\). The minimum reuse-adjusted control-inventor ESS ratio is
0.513 across all production cells and 0.536 in the primary specification.
The primary design has 31.53 effective treated deals, and its largest deal
holds 9.46% of treated mass.

These facts establish design feasibility. They do not turn the retained-group
comparison into a principal-stratum causal ATT: retention is measured after
treatment and can itself respond to acquisition. S3 identifies a balanced
comparison between selected initially retained groups. Selection diagnostics
and bounds remain necessary for causal interpretation.

## Why common-support coverage is below 100%

The exact primary funnel separates three reasons:

1. The status classification identifies 3,090 initially retained inventors
   across 172 deals.
2. Of these, 412 inventors, or 13.33% of the initially retained population,
   are outside the previously certified full-cohort common-support sample.
   Under the frozen local-matching design they therefore do not have an
   admitted clean-U2 comparison set. Including them would require reopening
   the earlier support-construction stage rather than merely recalculating
   stayer weights. This step also removes 12 deals.
3. Another 12 inventors, or 0.39%, belong to nine deals for which none of the
   otherwise admissible control inventors satisfies the symmetric
   initial-retention rule. These observations have full-cohort comparators but
   no retained-control analogue.
4. Finally, three cohort-2008 inventors, or 0.10%, lie at the boundary of the
   retained-control convex hull. Their outcome-blind exclusion materially
   improves ESS and weight concentration without removing another deal.

Thus,
\[
3{,}090-412-12-3=2{,}663,
\]
which yields 86.18% common-support coverage. These losses do not indicate that
the excluded inventors left the acquired firm. They indicate that the data do
not provide a sufficiently comparable retained-control counterfactual under
the frozen design.

The previous two-control-firm hard gate additionally removed 18 inventors and
five deals. It has been changed to a dependence diagnostic because the
cohort-level entropy estimator does not require two firms in every deal
stack. Those five stacks represent only 0.676% of primary treated weight.

The earlier loss of cohorts 2008 and 2010 was not a defensible reason to omit
both cohorts:

- cohort 2010 is exactly feasible under the complete primary vector;
- cohort 2008 becomes exactly feasible after excluding only three treated
  support outliers identified by a maximum-retention convex-hull diagnostic.

No cohort is now excluded.

## Support and dependence

S3 restricts both sides of the certified P5c roster using the approved
first-observed-post-patent retention rule. New deal-normalized base weights
and new cohort-level entropy weights are computed; full-cohort P5c weights are
not reused as stayer weights.

No per-inventor three-control rule is imposed. The persisted P5 edge cover is
projection-preserving rather than a complete pair graph, so such a rule would
be invalid and unnecessarily restrictive. Five single-control-firm deal
stacks containing 18 treated inventors remain in the primary roster and are
flagged for sensitivity reporting.

The certified primary design contains:

- 2,663 treated inventors;
- 151 treated deals;
- 40,845 control rows;
- 31.53 effective treated deals;
- a minimum primary cohort-level effective control-firm count of 5.43.

## Final balance vector

The primary, both LOYO designs, route-consistent design, and raw-unmixed design
balance:

- patent count separately at \(t=-5,-4,-3,-2,-1\);
- active patenting separately at \(t=-5,-4,-3,-2,-1\);
- career age;
- focal-group exclusivity;
- five-year firm patent stock;
- five-year firm inventor count.

Firm patent trajectory is omitted, as approved before outcomes. The
\(t=+2,\ldots,+5\) timing companion retains all inventor variables and firm
patent stock but omits firm inventor count. With only 57 treated inventors in
cohort 2010, jointly imposing both closely related firm-scale moments reduced
reuse-adjusted ESS to 0.335 of the treated count. The reduced timing vector
raises its ESS ratio to 0.579 while preserving explicit firm matching.

## Required specifications

All 17 cohorts are used for:

1. primary resolved retention over \(t=+1,\ldots,+5\);
2. LOYO \(t=-3\), holding out both count and active patenting at \(t=-3\);
3. LOYO \(t=-2\), holding out both count and active patenting at \(t=-2\);
4. route-consistent retention;
5. raw-patent unmixed retention;
6. retention classified over \(t=+2,\ldots,+5\).

Every cell solves exactly and passes the frozen ESS gate. The sample and
constraint set were fixed without opening outcomes and cannot be selected
according to the resulting estimates.

## Composition benchmark

The final treated roster contains:

- 574 established inventors, 21.55%;
- 2,089 recently recruited inventors, 78.45%.

Applying the frozen reference effects of \(-0.0867\) and \(-0.0534\) to those
shares gives a composition-predicted ATT of \(-0.0606\) patents per
inventor-year. This is a descriptive pre-outcome benchmark, not a stayer
result or a new estimator.

## Remaining coverage ceiling

The largest remaining loss comprises the 412 initially retained inventors
outside the previously certified full-cohort common-support population.
Recovering them cannot be achieved by another S3 weighting tweak. It would
require a separate rebuild from the original clean-U2 edge covers, with new
covariate assembly and certification. The present design already clears its
prospective coverage, deal-count, effective-deal, exact-balance, and ESS gates.

## Certified artifacts

- `s3_primary_weights.parquet`: primary row-level handoff.
- `s3_production_weights.parquet`: all six production specifications.
- `s3_weight_diagnostics.csv`: solver, balance, ESS, and concentration.
- `s3_support_summary.csv`: final sample funnel by retention definition.
- `s3_deal_support_diagnostics.csv`: deal-level retained controls and firms.
- `s3_treated_support_exclusions.csv`: the three frozen 2008 exclusions.
- `s3_established_recent_counts.csv`: frozen recruitment split.
- `s3_composition_benchmark.csv`: pre-outcome composition benchmark.
- `s3_certification.csv`: all certification gates.
- `s3_tooth_tests.csv`: positive tests for source drift, duplicate rows,
  mass corruption, and exclusion drift.
- `s3_manifest.csv`: paths, checksums, and composite execution hash.

All 21 certification checks and all four tooth-tests pass.

## Decision for the next package

S3 is ready for outcome estimation under the frozen 17-cohort design. No
stayer treatment effect has yet been estimated. The first result package must
label the estimand as a selected-group contrast, report the primary and all
required sensitivity estimates, compare the observed result with the
\(-0.0606\) composition benchmark, and place selection diagnostics and bounds
before any strong causal interpretation.
