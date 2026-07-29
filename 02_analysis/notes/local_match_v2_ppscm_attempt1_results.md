# Partially pooled synthetic control: attempt 1 results

Date documented: 2026-07-29

## Status

The first partially pooled synthetic-control implementation completed its
pre-period validation stage and failed. It stopped before querying
post-treatment outcomes. The script, freeze, and output directory are retained
unchanged as evidence from a failed first attempt:

- script: `02_analysis/R/37_run_lmv2_partially_pooled_scm.R`;
- freeze: `02_analysis/notes/local_match_v2_ppscm_freeze.md`;
- output: `02_analysis/output/audit/local_match_v2/P6_PPSCM_PROSPECTIVE/`.

This was not merely an interrupted draft. Any later PPSCM analysis is a
post-diagnostic second attempt and must not be described as blinded,
prospectively registered, or independent of these results.

## Frozen implementation

Attempt 1:

- used cohorts 1995--2010;
- selected treated inventor rows from `lmv2_treated_primary` and additionally
  required a target-group or target-company patent at event time -7 or -6;
- selected donor inventors using only unique group affiliation at -7 or -6;
- retained five donor firms per treated deal, with a minimum of three;
- trained on event times -7 through -4;
- subtracted each treated and donor cohort's training-period mean;
- validated at event times -3, -2, and -1;
- used a fixed ridge penalty of 1e-4;
- evaluated the heuristic partially pooled estimator as primary.

The execution hash was
`b6befcf6a5ba72cea977b44350e459e3ec0044d44f7f64cf40a52e0e45008943`.
The source hash was
`967a4510dd21d34c81ba387d172f694343542941175b18a34f1caa00cfafd7ca`,
and the freeze hash was
`51bc4ea1e8ed63dd840b3341a53a3f5211972d74e1b7c45844346b4f96299d25`.

## Validation results

The design retained 3,483 treated inventors across 203 deals. It passed the two
sample gates and the in-sample training-objective gate, but failed the seven
out-of-sample fit and weight-concentration gates.

| Gate | Observed value | Threshold | Result |
|---|---:|---:|:---:|
| Retained deals | 203 | at least 100 | pass |
| Treated coverage | 1.000 | at least 0.80 | pass |
| PPSCM validation RMSE | 0.2443 | no greater than uniform RMSE 0.2368 | fail |
| PPSCM validation RMSE | 0.2443 | no greater than 0.05 | fail |
| Largest absolute validation gap | 0.3600 | no greater than 0.05 | fail |
| Joint validation p-value | 0.00048 | greater than 0.10 | fail |
| Median donor ESS | 1.560 | at least 2 | fail |
| Tenth-percentile donor ESS | 1.000 | at least 1.25 | fail |
| Largest donor weight | 1.000 | no greater than 0.90 | fail |
| Training objective | 0.1811 | no greater than uniform 0.3065 | pass |

The inventor-weighted held-out gaps were:

| Event time | Treated path | Synthetic path | Gap |
|---:|---:|---:|---:|
| -3 | -0.3513 | -0.2270 | -0.1243 |
| -2 | -0.5083 | -0.3238 | -0.1845 |
| -1 | -0.6548 | -0.2948 | -0.3600 |

These are gaps in outcomes demeaned over -7 through -4. The reported held-out
gaps belong to the heuristic pooling value, \(\nu=0.2624\), not to the fully
pooled endpoint. The fully pooled endpoint attained a training pooled RMSE of
0.0010, which shows that the short training block permitted nearly exact
in-sample pooled fit. Its held-out path was not saved.

## Diagnosis

The first implementation did not condition the two arms symmetrically.
`lmv2_treated_primary` already requires at least one deal-specific
target-company patent somewhere in event times -5 through -1. Attempt 1 then
added the -7/-6 requirement. Donor inventors needed only an early -7/-6 group
patent and unique early affiliation. The control construction also omitted the
frozen inventor-level exclusion of target exposure through event time +5.

Additive demeaning compounded this difference. It removed average training
levels even though patent-count declines can be proportional to initial
patenting. The increasingly negative held-out gaps are consistent with this
level-scaling problem, although the saved results alone do not prove that
mechanism.

Uniform donor weights performed better out of sample, and fitted weights
collapsed onto single donor firms for many deals. The evidence therefore points
to arm asymmetry, weak time-series information, and overfitting rather than a
simple shortage of candidate donors.

## Consequence

Attempt 1 supplies no post-acquisition estimate. A second attempt is warranted
only because it changes the cohort construction and outcome scale that produced
the diagnosed failure. It cannot be rescued by changing the donor count,
pooling endpoint, ridge penalty, or validation threshold after the fact.
