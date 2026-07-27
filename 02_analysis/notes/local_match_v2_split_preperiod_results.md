# Split-preperiod identification exercise: final status

## Decision

Archive this exercise as a feasibility diagnostic. Do not add its estimate to
the current supervisor results package and do not present it as a replacement
for the full-cohort P5c ATT.

## Design

The implementation follows the prospective time split:

- establish focal affiliation at `t=-7,-6`;
- build clean-U2 firm and inventor support using information through `t=-4`;
- entropy-balance only `t=-5,-4` outcomes and predetermined covariates;
- leave `t=-3,-2,-1` untouched;
- reference the joint event study to `t=-4`.

No P5c support edge or weight is reused. Source, freeze, amendment, and weight
files are hashed.

## Feasibility

- 3,483 early-recruited treated inventors were available.
- 3,414 (98.02%) obtained three IPC4-supported controls from at least two
  firms. Local matching support is therefore not the binding problem.
- Exact nine-moment entropy balance was feasible in only four cohorts:
  1995, 2002, 2006, and 2007.
- The estimable subset contains 570 treated inventors and 48 treated deals.
- It has 961 control rows, pooled control ESS 142.88, and maximum residual
  standardized imbalance `8.27e-6`.

The binding problem is the convex-hull requirement created by combining a
long-history inventor restriction, local firm support, three controls per
treated inventor, and nine exact balance moments.

## Estimates

For the four feasible cohorts, the equal average over `t=+1,...,+5` is:

`ATT = -0.0021`, deal-clustered 95% CI `[-0.4298, 0.4255]`,
`p = 0.9922`.

The untouched leads are individually imprecise but reject jointly:

- `t=-3`: `+0.1431`;
- `t=-2`: `-0.1245`;
- `t=-1`: `-0.1752`;
- joint Wald `p = 0.00124`.

The same post contrast under two-way deal/inventor clustering is effectively
identical: 95% CI `[-0.4309, 0.4266]`, `p = 0.9922`.

## Interpretation

This exercise does not deliver the hoped-for clean validation:

1. only four cohorts survive exact balancing, so the estimand is highly
   selected relative to the main full-cohort ATT;
2. the untouched leads still reject jointly, so the design does not establish
   parallel trends;
3. the post estimate is too imprecise to distinguish a negative effect from
   zero or a positive effect.

The near-zero point estimate is not evidence that the main negative ATT is
spurious. It pertains to a narrow four-cohort, long-history subset and fails
its own pretrend test. Conversely, it cannot be cited as robustness evidence
for the main result.

Formal HonestDiD was dropped after the design failed these feasibility and
validation checks. Sensitivity optimization cannot turn a selected,
four-cohort design with rejected leads into a stronger identification design.

## Reproducibility

The finalized single-threaded implementation completed twice with identical
SHA-256 hashes for both `results_summary.csv` and
`design_diagnostics.csv`. This removes the near-tie instability observed in
the first multithreaded diagnostic.

The authoritative output directory is:

`02_analysis/output/audit/local_match_v2/P6_SPLIT_PREPERIOD_HONESTDID`
