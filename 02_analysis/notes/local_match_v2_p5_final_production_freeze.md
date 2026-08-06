# Local Match v2 — P5.3 final production freeze

**Frozen:** 2026-07-26, before opening any outcome or treatment-effect object.

**Status:** Approved by Tim after review with Claude. This amendment
authorizes the outcome-blind 17-cohort production run and supersedes only the
candidate-selection status of the P5.2 industry-support diagnostic. It does
not rewrite or delete any earlier design record.

## Outcome boundary

P5.3 may read treatment assignments, donor eligibility, pre-treatment
covariates, support edges, matching weights, and design diagnostics. It must
not read outcomes, event-study objects, DiD estimates, placebo estimates, or
any treatment-effect result. Outcome estimation begins only after the P5
design package is reviewed.

## Frozen headline design

- Donor universe: `u2` clean.
- Stage-1 profile: `nearest_50`.
- Stage-1 caliper: `2.0`.
- Stage-2 caliper: `1.5`.
- Technology resolution: `ipc4`.
- Stage-2 distance variables:
  `log_patent_count_5y`, `patent_trajectory`, and `career_age`, plus the
  existing IPC4 cosine component.
- Exact inventor balance moments:
  `log_patent_count_5y`, `patent_trajectory`, `career_age`, and
  `focal_group_exclusivity`.
- Exact firm balance moments:
  firm log five-year patent stock, firm log five-year inventor count, and
  firm patent trajectory.
- Each supported treated inventor must have at least three admissible control
  inventors from at least two control firms.
- Primary scheme: inventor-weighted entropy balance.
- Secondary scheme: equal-deal entropy balance.
- Solver: certified direct Newton entropy solver with the locked
  exact/0.05/0.10 feasibility hierarchy.
- Cohorts: 1994 through 2010, solved separately.

Stage-1 caliper 2.0 is frozen because it restores firm-level counterfactual
support for large deals while preserving the clean U2 timing rules and every
balance moment. For deal 70, it increased the clean usable donor-firm set from
3 to 9, raised the effective firm count to 4.94, limited the largest firm
share to 29.85%, and produced a primary reuse-adjusted ESS ratio of 0.765.
It is not justified as the candidate that “performed best.”

The adaptive five-nearest-control design is rejected for production because
its increased raw coverage came with excessive donor reuse and failures of
the reuse-adjusted ESS hierarchy. It remains in the specification-search
record.

## Prospective production rules

The following rules are fixed before the 17-cohort run:

1. A primary scheme that fails the locked balance hierarchy or the
   reuse-adjusted ESS ratio of 0.50 stops that cohort for design review.
2. No failed cohort triggers an automatic caliper change, covariate deletion,
   universe change, or solver change.
3. Equal-deal infeasibility is recorded but does not invalidate successful
   primary weights and does not stop primary production.
4. Aggregate inventor coverage must be at least 0.80, aggregate deal coverage
   at least 0.80, every productivity quartile at least 0.70, and every cohort
   at least 0.60 under the previously frozen support gates.
5. The retained-versus-unsupported SMD is reported but is not a terminal gate
   only when realized coverage makes the unsupported mass explicitly
   quantifiable. Aggregate coverage below 0.85, or a cohort below 0.80,
   triggers a separate selection-and-scope review. A cohort below 0.80 cannot
   receive an unqualified cohort-specific interpretation.
6. Projected results that mix specifications are labelled “projected.”
   Production acceptance uses only realized P5.3 results.
7. Firm concentration is reported for every deal. Deal 70's effective firm
   count below 2.5 remains a review trigger, not a solver constraint.

## Deal-70 influence reporting

The leave-one-firm-out covariate diagnostic is retained in full and is not
relabeled as passing. P6 will additionally refit the frozen design after
omitting each of deal 70's nine donor firms in turn and report the deal-70 ATT
sensitivity band

\[
  \left[\min_f ATT_{70,-f},\ \max_f ATT_{70,-f}\right].
\]

All nine estimates and the identity of the omitted firm will be reported.
This band is a required influence analysis and not a conventional confidence
interval.

## Weighting-scheme comparisons

Three outcome estimates are preregistered:

1. primary weights on every primary-feasible supported cohort;
2. equal-deal weights on every equal-deal-feasible cohort; and
3. primary weights restricted to exactly the equal-deal-feasible
   cohort/deal sample.

The third estimate is required for a like-for-like comparison of weighting
schemes. It prevents sample composition from being mistaken for a weighting
effect.

## Common-support and stayer selection

The headline estimand is the ATT for treated inventors with clean common
support. The scope condition must appear in the abstract if realized
aggregate coverage is materially below one.

Common-support exclusion will be examined using

\[
  ATT_{\mathrm{all}}
  = p\,ATT_{\mathrm{supported}}
  + (1-p)\,ATT_{\mathrm{unsupported}},
\]

where `p` is realized support coverage. Before outcomes are opened, P6 must
pin the unsupported-effect scenario grid, reversal calculation, outcome
scale, and any logical outcome bounds. Supported-versus-unsupported means,
SMDs, and standard-deviation ratios are mandatory.

Lee (2009) bounds remain the planned analysis for post-treatment stayer
selection where their monotonicity assumptions apply. They are not silently
relabelled as bounds for pre-treatment common-support exclusion. Any use of
Lee-style trimming for the latter requires a separate written justification.

## Cardinality matching

Reuse-constrained cardinality matching is a co-equal identification design,
not an extension of the entropy-balanced weights. Entropy-balanced supported
inventors, cardinality-recovered inventors, and still-unsupported inventors
must be reported as separate components. Weights from the two estimators are
never stitched together without first verifying a common estimand definition
and obtaining a further design review.

## Required production artifacts

- one atomic row-level weight shard per successful cohort and scheme;
- checksummed manifests and deal-balance shards;
- realized coverage by cohort, deal, and productivity quartile;
- balance, ESS, reuse, and firm-concentration diagnostics;
- the equal-deal-feasibility map and like-for-like primary sample map;
- the complete nine-firm deal-70 influence diagnostic;
- a dated specification-search table including every evaluated design and
  every governance reclassification;
- a final manifest pinning this amendment and all execution inputs.

