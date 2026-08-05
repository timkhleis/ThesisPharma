# P5 Henkel technology-resolution diagnostic

## Question

Henkel (control group 303292) enters the cohort-2000 donor pool only when the
Stage-1 firm caliper expands to 2.0. It is the only selected donor close to
SmithKline Beecham in firm scale. Because IPC4 class A61K contains both
pharmaceutical and cosmetic/toiletry inventions, this diagnostic tests
whether their measured technological similarity survives finer
classification.

## Results

| Resolution | Henkel--SmithKline cosine | Technology distance |
|---|---:|---:|
| IPC4 | 0.4284 | 0.5716 |
| IPC main group | 0.0437 | 0.9563 |
| IPC7 | 0.0209 | 0.9791 |

The IPC4 similarity does not survive disaggregation. The portfolio
composition explains the collapse:

- A61K8 accounts for 88.51% of Henkel's A61K portfolio and 23.05% of its
  overall portfolio.
- A61K31 accounts for 44.29% of SmithKline Beecham's A61K portfolio but only
  3.27% of Henkel's.
- SmithKline Beecham also concentrates 22.29% of its A61K portfolio in
  A61K39, while Henkel's A61K portfolio is overwhelmingly A61K8.

IPC4 therefore treats distinct cosmetic/toiletry and pharmaceutical
activities as the same technology class.

## Frozen interpretation and reporting rule

Henkel remains in the baseline donor pool. IPC4 is the prospectively agreed
technology resolution, Henkel is present in the source data, and the pair
passes the same frozen IPC4 and firm-support rules as every other donor pair.
This is a suitable primary comparison at the chosen level of granularity.
Henkel is also uniquely close to SmithKline Beecham in five-year patent stock
and inventor count and materially improves the reuse-adjusted effective
sample size.

The finer-resolution collapse is disclosed as a limitation of IPC4
granularity: selected donor pairs can be comparable within the broad IPC4
class while specializing in different main groups. It does not make Henkel
an invalid control and does not justify a post-outcome deletion. The thesis
therefore describes IPC4 as a coarse technology screen and reports the
Henkel-omitted exact-balance result as a labeled influence sensitivity.

The Henkel-deletion refit must not be described as simply infeasible. Exact
balance is attainable without Henkel, but the solution fails the
predeclared 0.50 reuse-adjusted ESS gate. Henkel is required for acceptable
precision under the frozen hierarchy, not for balance.

P6 will report:

1. the baseline headline and cohort-2000 ATT with Henkel;
2. the changes in those two ATTs under the eight deletion refits that pass
   the frozen ESS hierarchy; and
3. the Henkel-omitted exact-balance sensitivity with its realized ESS and
   interval, accepted for influence reporting despite failing the primary
   0.50 ESS gate.

Because these weights are solved at cohort level, none is labeled a causal
deal-70 ATT.

The diagnostic is interpretive and does not change the certified P5 roster.

## Artifacts

- `P5_HENKEL_DIAGNOSTIC/henkel_skb_similarity_by_resolution.csv`
- `P5_HENKEL_DIAGNOSTIC/henkel_skb_portfolio_composition.csv`
- `P5_HENKEL_DIAGNOSTIC/henkel_skb_a61k_main_groups.csv`
- `P5_HENKEL_DIAGNOSTIC/henkel_skb_shared_technology_contributions.csv`
