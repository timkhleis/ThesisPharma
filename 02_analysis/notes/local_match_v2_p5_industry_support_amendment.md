# Local Match v2: P5.2 industry-support interpretation

**Date:** 2026-07-26

## Status

This prospective amendment follows the outcome-blind `u2_reduced` diagnostic.
No outcome, pre-trend coefficient, placebo, or treatment effect has been
opened. It does not erase the P5.1 rules or results. It records which rules
are superseded after design review and preserves every original diagnostic.

The P5.1 `u2_reduced` stage supports 92.16% of cohort-2000 inventors, 96.55%
of cohort-2009 inventors, 92.62% of deal-70 inventors, and 73.47% of the
pooled top-productivity quartile. The remaining unsupported treated
inventors differ substantially from supported treated inventors. Deal 70 has
three clean U2 donor firms, an effective firm count of 2.99, and large
leave-one-firm-out mean shifts. Cohort-2000 primary weights fail the
reuse-adjusted ESS hierarchy; equal-deal weights pass only narrowly.

## Industry-support interpretation

The pharmaceutical industry contains only a small number of firms comparable
to a GSK-scale target. A rule requiring several mutually substitutable clean
mega-firms can reject economically central acquisitions because the relevant
industry population is intrinsically small, not because the available firms
are miscoded or irrelevant.

P5.2 therefore supersedes the deal-70 leave-one-firm-out threshold as an
acceptance gate. The diagnostic remains mandatory and is never relabelled as
passing. Deal 70 remains in the inclusive analysis, receives a standalone
estimate, and is accompanied by donor-firm influence ranges. Its
counterfactual is described as a narrow industry counterfactual based on the
available clean comparable firms.

The retained-versus-unsupported SMD threshold is also superseded as a
terminal feasibility gate once the aggregate, cohort, deal, and productivity-
quartile coverage gates pass. Selection statistics and variance ratios remain
mandatory. The resulting ATT is explicitly a common-support ATT. P6 must
report supported-versus-unsupported descriptives and sensitivity calculations
showing how large the unsupported-tail ATT must be to change the inclusive
conclusion. No unsupported inventor is silently represented as identified.

## Rules that remain binding

The following requirements are unchanged:

- U2-clean remains the headline donor universe; U3* is separately labelled
  robustness only.
- Each supported treated inventor has controls from at least two firms.
- Firm patent trajectory remains an exact balance moment. It is not removed
  because it binds.
- The certified exact/0.05/0.10 balance hierarchy must pass.
- Reuse-adjusted ESS ratio of at least 0.50 remains a hard feasibility gate
  for each reported weighting scheme. A result close to 0.50 is labelled
  acceptable but fragile, not preferred.
- The primary inventor-weighted scheme is required for the headline
  inventor ATT. Equal-deal weights do not substitute for a failed primary
  scheme.
- Every evaluated design, in chronological order, is retained in the
  specification-search audit.

## Authorized next stage

Because `u2_reduced` still lacks accepted cohort-2000 primary weights and
leaves a distinct unsupported tail, P5.2 authorizes the already specified
`u2_reduced_knn` stage:

1. use the reduced inventor distance and unchanged balance moments;
2. select five nearest admissible control inventors per treated inventor;
3. require the selected controls to span at least two control firms;
4. compute the cohort-specific sanity bound as the 99th percentile of the
   fifth-nearest distance among treated inventors with at least five
   candidate controls spanning at least two firms;
5. exclude candidates beyond that bound; and
6. rerun every coverage, selection, balance, ESS, concentration, and
   dependence diagnostic.

If this stage does not produce accepted primary weights, P5.2 next permits
an outcome-blind support diagnostic at Stage-1 caliper 2.0 while retaining
U2 eligibility and all balance moments. Cardinality matching or any final
estimand split receives a separate amendment after those diagnostics.

