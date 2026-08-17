# Financial-condition robustness: certified results and placement decision

## Design

The check starts from the certified 1993--2010 P5c roster and uses only
pre-acquisition financial information from `cassi_financial_all`. The primary
rule requires turnover and operating income in `g-1`; the prespecified
sensitivity uses the latest jointly observed record between `g-3` and `g-1`.
Both rules preserve the locked requirement of at least five financially
observed control firms per treated deal. The same restricted roster is used to
solve (i) the original balance vector and (ii) the original vector plus log
turnover, asinh operating income, and a negative-operating-income indicator.

Four estimates separate the sources of any change:

1. the full-sample headline ATT;
2. headline weights restricted to the feasible deal set, without a re-solve;
3. the financially linked roster re-solved on the original balance vector;
4. the identical roster additionally balanced on financial conditions.

All reported inference below uses two-way acquisition--inventor clustering.
Wild-cluster-bootstrap results are stored with the certified output and lead to
the same substantive conclusion.

## Coverage and feasibility

The exact `g-1` linkage initially retains 11,303 treated inventors from 50
acquisitions and 12 cohorts after the five-control-firm rule. Once the original
and financially adjusted designs are both required to pass the balance and
reuse-adjusted ESS gates, the common feasible sample falls to 2,752 treated
inventors from 14 acquisitions in the 2005 and 2010 cohorts. This represents
10.0% of the headline treated sample, and the effective deal count is only
2.65. The restricted sample is also strongly selected toward larger firms: the
largest standardized difference between included and excluded treated
inventors is 0.727 for the target firm's inventor count.

Allowing the latest jointly observed record from `g-3` to `g-1` does not solve
the support problem. Although 11,970 treated inventors from 64 acquisitions
initially pass the five-firm rule, only 918 inventors from 20 acquisitions in
the 2008 and 2010 cohorts jointly pass both weighting designs. The effective
deal count is 11.91, and the largest initial included--excluded standardized
difference remains 0.629.

## Estimates

| Financial rule and specification | ATT | SE | 95% CI | p-value |
|---|---:|---:|---:|---:|
| Full-sample headline | -0.0521 | 0.0166 | [-0.0848, -0.0194] | .002 |
| Exact `g-1`: composition only | 0.0420 | 0.0344 | [-0.0323, 0.1162] | .244 |
| Exact `g-1`: linked benchmark | -0.0012 | 0.0303 | [-0.0668, 0.0643] | .968 |
| Exact `g-1`: financially adjusted | -0.0026 | 0.0343 | [-0.0768, 0.0716] | .940 |
| Latest `g-3:g-1`: composition only | -0.0222 | 0.0609 | [-0.1497, 0.1053] | .719 |
| Latest `g-3:g-1`: linked benchmark | -0.0444 | 0.0668 | [-0.1842, 0.0954] | .514 |
| Latest `g-3:g-1`: financially adjusted | -0.0514 | 0.0655 | [-0.1884, 0.0857] | .442 |

Within a common roster, adding financial variables changes the exact-`g-1`
estimate by -0.0014 patents per inventor-year and the `g-3:g-1` estimate by
-0.0070. Financial adjustment therefore does not attenuate the negative point
estimate in either comparison. The fallback adjusted estimate is also close to
the full-sample headline estimate. These similarities are descriptive,
however, because the feasible samples retain only two cohorts and the
confidence intervals are wide.

The large differences between the composition-only and re-solved estimates
show why the intermediate benchmark is necessary. Restricting the treated-deal
composition, shrinking the donor pool, and re-solving the weights are distinct
changes and should not be attributed to financial adjustment.

## Placement decision

This check should **not** enter the main robustness table. The placement was
determined by outcome-blind gates, all of which fail except final covariate
balance: treated and deal coverage are low, only two cohorts remain, the
effective deal counts are below 20, and financial availability is strongly
related to firm size. The results therefore cannot establish that the headline
ATT is robust to financial adjustment across the original supported sample.

The complete exercise belongs in the appendix as a feasibility and restricted-
sample diagnostic. The main robustness text can include one short sentence:

> I additionally rebalance firms on pre-acquisition turnover and operating
> income. Sparse financial coverage and limited common support reduce this
> exercise to two cohorts, so I report it as a restricted-sample diagnostic in
> Appendix~\ref{app:financial_robustness}; within the feasible samples, adding
> financial conditions changes the estimated effect only slightly.

The financial file contains consolidation codes but no currency metadata.
This comparability limitation should be recorded in the appendix table note.

## Certified artifacts

- Primary design: `ROBUSTNESS_RELEASE_1993/FINANCIAL_CONDITIONS_DESIGN`
- Primary estimates: `ROBUSTNESS_RELEASE_1993/FINANCIAL_CONDITIONS_ESTIMATION`
- `g-3:g-1` design: `ROBUSTNESS_RELEASE_1993/FINANCIAL_CONDITIONS_DESIGN_GM3`
- `g-3:g-1` estimates: `ROBUSTNESS_RELEASE_1993/FINANCIAL_CONDITIONS_ESTIMATION_GM3`

Both specifications pass all independent checks in
`financial_robustness_certification.csv`.
