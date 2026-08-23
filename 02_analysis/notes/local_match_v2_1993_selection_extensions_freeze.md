# Local Match v2: 1993 selection extensions freeze

**Frozen:** 8 August 2026, before estimating either extension.

## Evidentiary boundary

This extension adds two diagnostics to the certified 1993--2010 release. It
does not alter the P5c support roster, P5b retained-inventor weights, outcome
definitions, event window, or existing treatment-effect estimates.

The retention models quantify selection on observed pre-acquisition
characteristics. They do not identify an effect for inventors who would have
been retained under either acquisition state. The common-support calculations
are sensitivity analyses for the eligible treated inventors excluded by the
outcome-blind local-support screen. They do not estimate those inventors'
counterfactual outcomes.

## Retention-selection models

The analysis uses the primary `t1_t5_primary` treated status partition. It
estimates two models:

1. continuation: any observed patent during event years +1 through +5 versus
   no post-deal patent;
2. observed retention: initially retained versus leaver, conditional on any
   observed post-deal patent.

The logit is primary. A probit with the identical sample and regressors is a
functional-form check. Both include acquisition-cohort fixed effects and use
deal-clustered inference. Deal fixed effects are prohibited. IPC technology is
collapsed to IPC section to limit separation.

All regressors are determined before acquisition: log five-year patent stock,
pre-deal active-patenting rate, patent trajectory, career age and its square,
focal-group tenure, focal-group exclusivity, log target-group inventor count,
log deal value, and primary pre-deal IPC section. Continuous regressors are
standardized in the full status-eligible treated sample. Missing continuous
values are median-imputed with explicit missingness indicators.

The primary outputs are average marginal effects, deal-clustered confidence
intervals, predicted probabilities at pre-deal productivity quartiles, a joint
test of the productivity block, AUC, Brier score, and calibration summaries.
The classification sensitivities are:

- `t2_t5_timing` instead of `t1_t5_primary`;
- exclusion of raw mixed-affiliation cases;
- exclusion of route-disagreement cases; and
- descriptive retention rates by time to the first post-deal patent.

Time to the first post-deal patent is post-treatment. It is reported as a
classification diagnostic and is never included as a regressor or weighting
variable.

No inverse-selection-weighted treatment effect is authorized by this freeze.
Any later standardization must target the eligible treated cohort's pre-deal
covariate distribution and must predeclare an effective-sample-size floor,
maximum-weight rule, truncation rule, and post-weighting absolute SMD ceiling
of 0.10 before opening outcomes.

## Full-cohort common-support sensitivity

The eligible population is the unique 1993--2010 treated-inventor roster in
`lmv2_p3_treated_inventor_units`. The supported population is the treated arm
of the certified P5c/P6 roster. Every supported treated inventor must have
weight one. The package must verify that the unsupported set is exactly the
eligible-minus-supported anti-join and that support was determined before
outcomes were opened.

For patent count, use the previously frozen delta grid

`-3, -2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2, 3`.

The scale is the standard deviation of mean annual pre-deal patenting over
event years -5 through -1 among all eligible treated inventors after 1st/99th
percentile winsorization. For fixed delta,

`ATT_unsupported = ATT_supported + delta * sigma_pre`

and

`ATT_all = p * ATT_supported + (1-p) * ATT_unsupported`,

where `p` is the eligible-inventor headcount share entering P5c. Conditional
confidence intervals shift the governing supported-sample interval by
`(1-p) * delta * sigma_pre`; delta is an assumption, not an estimated random
quantity.

For active patenting, report both the same standardized scenario grid and the
logical unsupported-effect bound `[-1, 1]`. The logical bound is not presumed
to establish the sign. PQII is excluded because outcome availability and
conditioning on patenting prevent a common headcount decomposition.

The raw unsupported ATT required to reverse the patent-count result is the
principal sensitivity statistic. The standardized reversal value is reported
second. No supported-sample heterogeneity estimate is extrapolated into the
unsupported covariate region.

## Release rule

Both packages write to new audit directories and receive source, input, and
result certification. They remain outside the final thesis registry until the
outputs have been inspected and explicitly promoted.
