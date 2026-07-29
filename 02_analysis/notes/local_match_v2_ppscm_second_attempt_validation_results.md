# PPSCM second-attempt rolling-validation result

Date run: 2026-07-29

## Terminal result

The frozen partially pooled synthetic-control second attempt **fails rolling
pre-period validation**. The partially pooled estimator has a three-period
inventor-weighted validation RMSE of 0.02361, compared with 0.01714 for the
same-sample uniform-donor estimator. It therefore fails governing Gate 6
(`PPSCM RMSE <= uniform RMSE`).

This is a terminal deterministic failure. A Webb bootstrap cannot change the
two observed RMSEs or reverse Gate 6, so the precommitted 9,999-replication
bootstrap was not run. The control-null stage, same-sample Verginer comparison,
HonestDiD sensitivity, and real post-acquisition estimation were not run. No
post-treatment outcome was queried.

The result is not that the symmetric landmark sample lacks donor support.
Coverage and coarse support are strong. The narrower conclusion is that
flexible partially pooled weights do not improve held-out pre-period fit over
simple uniform weights in these data.

## Primary held-out paths

All outcomes below are raw annual patents per inventor. Each outer fold
reselected the ridge penalty and heuristic pooling parameter using only the
available training periods.

| Held-out time | Training times | Treated | PPSCM | PPSCM gap | Uniform gap |
|---:|---|---:|---:|---:|---:|
| -3 | -5, -4 | 0.31873 | 0.31251 | 0.00622 | 0.02328 |
| -2 | -5, -4, -3 | 0.25079 | 0.28659 | -0.03581 | -0.01100 |
| -1 | -5, -4, -3, -2 | 0.22019 | 0.23894 | -0.01875 | -0.01478 |

The nested one-standard-error rule selected the largest ridge value in the
frozen grid, `lambda=0.1`, in all three folds. The heuristic pooling parameter
was 0.1519, 0.1431, and 0.1557. Optimization sharply attenuates the -3 anomaly,
but it overcorrects at -2 enough to make its total validation loss worse than
uniform weighting.

The pure separate and pure pooled endpoints also lose to uniform weighting:

| Estimator | Validation RMSE | Largest absolute gap |
|---|---:|---:|
| Uniform, inventor-weighted | 0.01714 | 0.02328 |
| PPSCM, heuristic pooling | 0.02361 | 0.03581 |
| PPSCM, pure separate endpoint | 0.02284 | 0.03356 |
| PPSCM, pure pooled endpoint | 0.02107 | 0.02923 |
| Nearest donor | 0.04585 | 0.05932 |

Thus the failure is not driven only by the heuristic value of the pooling
parameter.

## Governing-gate audit

The following deterministic gates pass:

- 235 retained deals, above the minimum of 100;
- 10,818 of 11,036 eligible treated inventors retained (98.02%), above 80%;
- at least 20 donor firms for every retained deal, above five;
- the redundant absolute-fit checks (RMSE and every pooled gap below 0.05);
- PPSCM fit better than the nearest-donor benchmark; and
- leave-one-cohort-out and ten largest-contribution deletion checks.

Three deterministic gates fail:

1. **Uniform comparison:** PPSCM RMSE is 0.02361 rather than at most 0.01714.
2. **Equal-deal stability:** equal-deal RMSE is 0.04982, but its largest
   absolute gap is 0.07684, just outside the frozen 0.075 limit.
3. **Weight concentration:** median donor ESS is 7.65 and tenth-percentile ESS
   is 1.92, but the maximum donor weight is effectively one. Nineteen
   deal-folds place more than 0.90 on one donor.

The joint Webb p-value is unevaluated, not interpreted as an additional
empirical rejection. The deterministic Gate 6 failure makes that expensive
inference step incapable of changing the terminal decision.

## Frozen screening sensitivities

Every screening variant has higher PPSCM RMSE than its own same-sample uniform
benchmark.

| Specification | Deals | Treated inventors | Coverage | PPSCM RMSE | Uniform RMSE |
|---|---:|---:|---:|---:|---:|
| Full metric, K=10 | 223 | 10,359 | 93.87% | 0.01750 | 0.01308 |
| Full metric, K=20 (primary) | 235 | 10,818 | 98.02% | 0.02361 | 0.01714 |
| Full metric, K=50 | 240 | 11,030 | 99.95% | 0.02814 | 0.01711 |
| Drop IPC distance, K=20 | 233 | 10,781 | 97.69% | 0.01844 | 0.01604 |
| Drop career distance, K=20 | 235 | 10,916 | 98.91% | 0.02376 | 0.01618 |
| Drop outcome-level distance, K=20 | 223 | 10,763 | 97.53% | 0.01730 | 0.01705 |
| Include Deal 69, K=20 | 236 | 11,019 | 99.85% | 0.02747 | 0.01725 |

Dropping the outcome-level screening coordinate produces the closest contest,
but PPSCM still does not beat uniform weighting. No sensitivity replaces the
frozen primary result.

## Attachment and Deal 69 diagnostics

Only 3,494 of the 10,818 retained landmark inventors (32.30%) have any strict
target-company patent during -5 through -1. The full landmark estimand is
therefore an intention-to-exposure design with substantial pre-deal
detachment. The frozen attached-inventor subgroup remains a secondary
post-treatment estimand, but it is not opened after this validation failure.

Seven primary deals fail the two-period hull check, representing 218
inventors. Deal 69 alone represents 201 of them: Monsanto Company's 2000
acquisition by Pharmacia & Upjohn Inc. Its treated `log1p` mean at -5 is
0.10834 below the nearest selected-donor boundary. Retaining Deal 69 increases
coverage but worsens PPSCM validation RMSE from 0.02361 to 0.02747.

## Interpretation for the thesis

The symmetric construction resolves attempt 1's sample-support problem and
shows that simple uniform donors track the pooled treated trajectory well.
It does not validate partially pooled synthetic control as a superior
triangulation estimator. With only five pre-periods, sparse inventor outcomes,
and strong uniform pre-fit, optimized weights add variance and local
concentration without lowering held-out error.

The disciplined stopping rule is therefore:

- do not report a PPSCM post-treatment ATT;
- retain the uniform-donor pre-fit result as evidence that the revised donor
  architecture is promising, not as a certified post-treatment estimate; and
- if a uniform-only post design is pursued, freeze and validate it as a
  separate branch with its own inference and control-null gates.

## Reproducibility

The terminal production output is under
`P6_PPSCM_V2_SYMMETRIC/stage_d_validation/`. Twenty published files pass their
recorded SHA-256 checks. The production run records:

- freeze SHA-256:
  `c1b7907eb4a954e73f2e0775eb736fcc7db575a27fe2c3928394163a5898ee11`;
- census-manifest SHA-256:
  `e1bbb5b876cf036903060d2b41b39bea9a6311ffea189453e06ebb762b73536b`;
- validation source SHA-256 used for estimation:
  `faa6de7323e40d331eb4517577ecaa02d4bd8ade03782442efa2d8405062b332`;
- deterministic computation time: 1,044.79 seconds;
- 9,999 bootstrap draws requested, zero completed, and the explicit
  terminal-deterministic-failure skip flag set to true;
- `optimized_weights_estimated=TRUE`;
- `post_outcomes_queried=FALSE`; and
- terminal status `VALIDATION_FAILED`.

The strict production solver reproduced every primary estimate from the
noncertifying run. After substantive outputs were written, the first
publication pass encountered the pre-existing `_deterministic` directory while
constructing file hashes. The directory filter and an empty projected-runtime
field were repaired without refitting or changing estimates; the final
20-file hash manifest was then independently reverified with zero mismatches.
The validation summary deliberately retains the exact source hash used for the
strict estimation run.
