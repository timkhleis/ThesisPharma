# Local Match v2 supported-inventor size split amendment

Date: 2026-08-14

Status: post-results exploratory diagnostic. This amendment fixes the design
before any size-split post-acquisition outcome is estimated.

## Question and estimand

The diagnostic asks whether the inventor-weighted five-year patent-count ATT
differs between acquisitions with relatively few and relatively many supported
treated inventors. It does not measure monetary transaction size. Supported
size is determined after the frozen P3 support stage, so it is not a direct
measure of the target's pre-support R&D workforce.

The outcome is annual patent count. The summary is the average ATT over event
times `t=1,...,5` relative to `t=-1`. Within each size group, every supported
treated inventor receives weight one.

## Frozen size rule

One observation per `(cohort, deal_id)` enters the threshold calculation.
Supported size is the number of distinct treated `roster_row_id` values in the
certified P5c primary count-active roster. The median is 16. Define:

- `small`: at most 16 supported treated inventors;
- `large`: at least 17 supported treated inventors.

Seven acquisitions lie at the median and remain in the small group. The full
roster contains 177 small and 166 large acquisitions.

## Outcome-blind information and feasibility gates

The initial comparison set contains cohorts in which both size groups exist.
Each retained cohort-by-size cell must contain, before weighting:

- at least 10 treated acquisitions;
- at least 50 supported treated inventors; and
- at least 100 distinct control inventors.

Only cohorts passing all three floors in both size groups remain. If a cell
fails the entropy-balance or weight-quality gate, remove that cohort from both
groups. Do not substitute a different threshold or asymmetric cohort set.

Stage 1 is not re-solved. The certified cohort-level donor-firm composition and
deal-specific support are inherited. Only Stage-2 inventor balance is re-solved
within cohort-by-size cells, starting from the frozen deal-normalised P5c base
weights.

Balance the 15 P5c count-active variables. Exact entropy balance is preferred;
the existing 0.05 and 0.10 approximate-balance fallbacks are allowed. Require:

- maximum absolute standardized difference no greater than the selected
  tolerance;
- reuse-adjusted control-inventor ESS divided by the treated count at least
  0.50; and
- maximum aggregated control-inventor weight share no greater than 0.20, the
  P4 Stage-2 acceptable absolute concentration ceiling.

The P5c rules measuring ESS loss and concentration increase relative to the
P5a cohort-level solve are not applied because a subgroup-specific P5a
reference does not exist.

## Power and inference

Before opening post-acquisition outcomes, estimate the two-way clustered
standard error of the large-minus-small contrast using the pre-period placebo
change from the mean of `t=-5,...,-2` to `t=-1`. Report the two-sided 5% level,
80% power minimum detectable difference. This is a precision diagnostic, not
an inclusion gate.

For the post-period subgroup difference, compute deal-level Webb wild-bootstrap
and two-way acquisition--inventor inference. The frozen P6 governing rule
applies: the wider confidence interval governs, with the wild interval
governing an exact width tie.

## Required anchors and diagnostics

Report a pooled inventor-weighted ATT on exactly the retained cohort set before
the two subgroup estimates. Report the direct large-minus-small test; do not
infer heterogeneity from subgroup significance patterns.

The existing equal-acquisition estimate of -0.008 (`p=.677`) covers only the 16
cohorts for which equal-deal P5c weights were feasible. Any comparison with the
18-cohort headline must disclose that sample difference and should also show
the inventor-weighted estimate on those same 16 cohorts.

For a filtered-headline-weight diagnostic, decompose the pooled ATT influence
contributions by size and require the contributions to sum exactly to the
pooled ATT. Do not impose that identity on the re-solved subgroup ATTs because
their counterfactual weights differ.

Also report:

- Pearson and Spearman correlations of supported size with the pre-support
  treated-inventor count;
- Pearson and Spearman correlations with `target_value` and `log1p(target_value)`;
- the five largest acquisitions' share of supported treated inventors; and
- a full-sample, frozen-weight `treated x log(n_supported)` interaction,
  labelled descriptive rather than causal heterogeneity.

## Reporting rule

The split is exploratory and belongs in the main Influence and aggregation
panel only if all common-sample balance and weight-quality gates pass. Otherwise
place the estimates in the appendix. In either location, "larger" means a
larger supported treated-inventor population, not a larger transaction value.
If the formal difference is imprecise, report the point-estimate pattern and
state that the data do not distinguish the subgroup effects precisely.

