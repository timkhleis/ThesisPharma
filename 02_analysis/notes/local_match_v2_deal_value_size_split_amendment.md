# Local Match v2 deal-value size split amendment

Date: 2026-08-14

Status: post-results exploratory financial-size robustness. This amendment
fixes the design before post-acquisition outcomes are estimated by the
deal-value split.

## Question and size definition

Following the Cassi--Ornaghi transaction-size convention, split acquisitions
using target transaction value. The source stores transaction values in
thousands, so the EUR 5 billion threshold is `target_value = 5,000,000`.

- `under_5bn`: `target_value <= 5,000,000`;
- `over_5bn`: `target_value > 5,000,000`.

The outcome is annual patent count. The estimand is the average ATT over event
times `t=1,...,5` relative to `t=-1`. This is a financial-size split and does
not use the number of supported treated inventors to define the groups.

## Common sample and balance

Begin with the certified 1993--2010 P5c roster. The primary Cassi--Ornaghi
comparison retains the 16 cohorts represented in both value groups and uses
the frozen P5c weights. This preserves 302 below-threshold and 38
above-threshold acquisitions and changes only the financial-size aggregation.

As a stricter balance sensitivity, re-solve Stage-2 weights by value group.
Before reweighting, each retained cohort-by-value cell must
contain at least one acquisition, 50 supported treated inventors, and 100
distinct control inventors. If either value cell fails a floor or a weight
quality gate, remove the cohort from both groups.

For the sensitivity, Stage 1 remains frozen. Re-solve only Stage-2 inventor balance within each
cohort-by-value cell, starting from the frozen P5c deal-normalised base
weights. Balance the same 15 count-active variables. Prefer exact entropy
balance; retain the existing 0.05 and 0.10 approximate-balance fallbacks.
Require reuse-adjusted control-inventor ESS divided by the treated count of at
least 0.50 and a maximum aggregated control-inventor weight share of 0.20.

The primary frozen-weight comparison belongs in the main influence and
aggregation table because it directly implements the requested published
threshold on the broad common sample. The rebalanced sensitivity belongs in
the appendix if it retains fewer than ten common cohorts or fewer than 25
acquisitions in either group.

## Inference and reporting

Before opening the split outcomes, estimate the two-way clustered standard
error and 80%-power MDE for the over-minus-under contrast using the change from
the mean of `t=-5,...,-2` to `t=-1`.

Report the pooled ATT on the exact retained cohort set, both subgroup ATTs,
and the direct over-minus-under test. Compute deal-level Webb wild-bootstrap
and two-way acquisition--inventor inference. The wider confidence interval
governs, with the wild interval governing an exact tie.

The filtered-headline contribution decomposition must sum exactly to the
pooled ATT. Do not impose this identity on the separately re-solved subgroup
ATTs. Label the exercise exploratory and state that financial size differs
from the number of inventors affected by an acquisition.
