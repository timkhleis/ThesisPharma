# Partially pooled synthetic control: post-diagnostic second-attempt freeze

Date frozen: 2026-07-29

## Pre-execution operationalization amendment

The following choices were recorded before the census queried any outcomes.
They resolve details that the original freeze named but did not fully
operationalize:

- U2 donor cleanliness is reconstructed from the target-group and acquirer-event
  predicates only. The existing `lmv2_control_firm_eligibility` table is not
  used because its membership also conditions on patent activity after the
  -7/-6 landmark.
- Fixed-cohort outcomes and career dates come from the unrestricted
  `inventor_year` table. Whole-firm patent and inventor counts are reconstructed
  from `patent_company_link` and `patent_inventor`.
- Career-age composition is represented by the mean and median career age at
  -4 among the fixed landmark inventors.
- IPC4 portfolios use the finite -7 through -4 window. A valid pair with no
  shared IPC4 codes has cosine similarity zero; a firm with no valid IPC vector
  is excluded and counted.
- Scalar distance components are standardized within placebo cohort across
  treated and eligible donor firms. Candidate distance is Euclidean in those
  standardized components, with unstandardized `(1 - IPC4 cosine)` as the
  technology component.
- The hull is the coordinatewise donor interval in `log1p` mean patenting,
  separately at -5 and -4, using the selected top-20 donor pool. A zero-width
  interval supports the treated value only within `1e-12`.

These choices do not alter the thresholds, outcomes, donor cap, validation
periods, or stopping rules below.

## Post-census, pre-validation amendment

This amendment was recorded after the census passed but before any optimized
weights were estimated. The known census facts are that the uniform top-20
donor estimator has raw validation gaps of 0.0233, -0.0110, and -0.0148 at
-3, -2, and -1, respectively, for an RMSE of 0.0171. The symmetric landmark
construction, rather than optimization, therefore restored pre-period
comparability.

The uniform-donor estimator is co-primary with PPSCM from this point onward.
Both estimators use the same primary deal sample and donor pools. The paper
reports both post estimates with equal prominence. If they agree, the uniform
estimate is the parsimonious headline because it does not depend on optimized
weights. PPSCM now tests whether a flexible counterfactual materially changes
the post estimate, not whether a scientifically small reduction below an RMSE
of 0.0171 establishes identification.

Validation Gates 4 and 5 remain recorded but are labelled logically redundant,
not independent hurdles: any estimator satisfying Gate 6, an RMSE no greater
than 0.0171, necessarily satisfies the 0.05 RMSE and componentwise-gap limits
over three validation periods. The gates that remain independently
informative are comparison with uniform fit, the joint validation test, weight
concentration, leave-one-cohort-out stability, and largest-contribution
deletions.

The primary full landmark cohort is intentionally symmetric and does not
condition on patenting at -5 through -1. Before validation, the analysis
reports the share of retained treated inventors with at least one strict
target-company patent in that interval. Post estimates must describe the full
cohort as an intention-to-exposure effect that may be diluted when inventors
detach from the target before acquisition.

A secondary `symmetric_attached` specification requires a strict
target-company patent at -5 through -1 for treated inventors and an own-donor-
group patent in the same relative interval for donor inventors. This secondary
sample cannot replace the full landmark primary because it conditions on
continued patenting after cohort formation.

Every post ATT is reported both in patents per inventor-year and as a
percentage of the estimator-specific weighted control mean over +1 through +5.
The same-sample Verginer/entropy estimate is mandatory. Honest DiD
Rambachan--Roth sensitivity is also mandatory on the final landmark event
study; it reports the largest relative pretrend violation consistent with the
sign of the average +1 through +5 estimate.

Deal 69 in cohort 2000 accounts for 201 of the 218 inventors excluded by the
primary hull restriction. The primary sample remains unchanged. A named,
non-governing sensitivity retains deal 69 with its frozen primary top-20 donor
pool despite its hull failure and reports its leverage on validation and post
estimates.

Screening sensitivities replace the uninformative all-available-donor
sensitivity. They are:

- donor caps of 10, 20, and 50;
- `drop_ipc`, which omits `(1 - IPC4 cosine)` from candidate distance;
- `drop_career`, which omits mean and median career age at -4; and
- `drop_outcome_level`, which omits fixed-cohort `log1p` mean patenting at -5
  and -4 from candidate distance while retaining active shares, firm scale,
  career age, and IPC similarity.

Each sensitivity uses the same eligible donor universe, reports its own
coordinatewise -5/-4 hull rate, and is non-governing. No sensitivity may
replace the primary top-20 full-metric result after validation.

### Validation execution details

These details were recorded before the first optimized weight fit.

For inventor aggregation, \(a_j\) is deal \(j\)'s share of retained treated
inventors; for equal-deal aggregation, \(a_j=1/J\). With \(L\) common training
periods, define

\[
q_{\mathrm{sep}}^2=\sum_j a_j L^{-1}\sum_t e_{jt}^2,\qquad
q_{\mathrm{pool}}^2=L^{-1}\sum_t\left(\sum_j a_j e_{jt}\right)^2.
\]

The normalization values come from ridge-penalized separate SCM at the
candidate \(\lambda\). The Ben-Michael--Feller--Rothstein heuristic is
\(\widehat\nu=q_{\mathrm{pool}}/
\sum_j a_j q_j\), truncated to [0,1], where all quantities are evaluated at
that separate fit. The penalty is
\(\lambda\sum_j a_j\|\gamma_j\|_2^2\). Thus the exact paper heuristic replaces
attempt 1's ratio of pooled to root-mean-square unit imbalance.

Within an outer fold, internal leave-one-training-period-out loss is the
inventor-weighted mean squared raw-count prediction error. Its standard error
is the weighted deal-cluster standard error of deal-level mean squared errors.
The selected penalty is the largest \(\lambda\) no more than one standard error
above the minimum loss. Each internal split recomputes separate weights,
normalizers, and \(\widehat\nu\). The chosen penalty is then refit on the full
outer training block with a newly computed \(\widehat\nu\).

Weight-concentration Gate 10 summarizes deal-by-fold weights across all three
outer validation folds. Leave-one-cohort-out and largest-contribution deletion
gates use the three raw held-out deal-gap vectors produced by rolling
validation.

The governing Webb test null-imposes zero pooled pre-period gap as follows.
Using the fitted all-five-preperiod model, center each deal's raw gap at the
inventor-weighted pooled gap for that period. For replication \(b\), draw one
Webb multiplier \(\xi_{jb}\) per deal and set the bootstrap treated path to the
synthetic raw path plus \(\xi_{jb}\) times that centered deal residual; truncate
only negative reconstructed patent means to zero and report the truncation
rate. Donor paths remain fixed. Every replication reruns the complete rolling
procedure, including nested penalty selection, the heuristic pooling
parameter, and weights. The observed and bootstrap statistics are
studentized three-degree-of-freedom Wald statistics using their respective
deal-cluster covariance matrices. The p-value is
\((1+\sum_b 1\{Q_b\geq Q\})/(B+1)\).

Each screening sensitivity selects its donor pool from the complete eligible
edge table and applies its own two-period hull restriction. Its validation
sample and coverage are reported explicitly. The deal-69 sensitivity is the
only exception: it adds deal 69 to the primary sample with the frozen primary
top-20 pool despite the failed -5 hull check.

## Governance and purpose

This is a procedurally precommitted second attempt. It follows a completed first
attempt whose pre-period validation failed. The first-attempt results are
documented in `local_match_v2_ppscm_attempt1_results.md`.

The exercise is not blinded. Post-acquisition outcomes for related estimands
have already been analyzed and published within the project. In addition, the
control-null stage below observes post-period outcomes for acquisition-clean
firms drawn from the donor population. The safeguards in this document prevent
further specification changes and enforce a computational stopping rule; they
do not recreate statistical blindness.

Local Match v2 remains the primary design. This PPSCM analysis is
triangulation. It asks whether a symmetric established-inventor population and
deal-specific synthetic counterfactuals can produce credible out-of-sample
pre-period fit.

## Historical evidence known at freeze

Attempt 1 retained 3,483 inventors across 203 deals. Its inventor-weighted
held-out gaps at -3, -2, and -1 were -0.124, -0.185, and -0.360. Validation RMSE
was 0.244, compared with 0.237 under uniform donor weights. The joint validation
p-value was 0.00048, median donor ESS was 1.56, and the largest donor weight was
one.

The canonical full-cohort P5c estimate is -0.0534 patents per inventor-year.
The closest published established-inventor reference is the strict
Verginer-style estimate of -0.0867 over +1 through +5. That reference used
2,591 treated inventors and 166 deals in 13 feasible cohorts. It is not an exact
same-sample benchmark for PPSCM.

## Cohorts and estimands

- Cohorts are 1995--2010. Cohort 1994 is excluded because event time -7 is 1987
  and the patent layer begins in 1988.
- The treated unit is an acquisition deal.
- The inventor cohort is fixed at event time -7 or -6.
- The primary outcome is annual patent count per established inventor.
- The primary post estimand, if every gate passes, is the inventor-weighted
  average annual ATT over event times +1 through +5.
- Equal-deal weighting is secondary.
- Event time 0 is shown but excluded from the average post estimand.

## Symmetric landmark eligibility

The analysis reproduces the landmark logic in
`22c_diagnose_lmv2_recruitment_rule.R`. It does not select inventor rows from
`lmv2_treated_primary`.

### Treated inventors

An inventor must:

1. belong to an accepted acquisition deal;
2. have a patent linked to a strict target company at -7 or -6;
3. have a unique latest affiliation within -7/-6;
4. have that affiliation resolve to the target group; and
5. be retained only at the inventor's earliest eligible acquisition exposure.

### Donor inventors and firms

A donor inventor must:

1. have a patent and observed affiliation at -7 or -6;
2. have a unique latest affiliation within -7/-6;
3. have that affiliation resolve to the candidate donor group; and
4. have no target exposure on or before the placebo cohort's event time +5.

A donor firm must satisfy the complete U2 target- and acquirer-clean rules. A
donor-firm cohort must contain at least five eligible established inventors.
Treated and donor membership may not use patent outcomes from -5 onward.

## Stage A: eligibility, pool, and hull census

The first executable stage constructs no synthetic weights and queries no
outcomes later than -1. It reports:

- treated inventors, deals, and firms by cohort;
- corresponding attempt-1 counts of 3,483 inventors and 203 deals;
- the full P5c treated population of 27,078 supported inventors;
- exclusion counts for ambiguous affiliation, repeat exposure, contamination,
  and donor-cohort size;
- available donor firms per deal before and after the cohort-size rule;
- raw and `log1p` patenting levels at -5 and -4;
- active-patenting shares, career age, firm size, and technology overlap; and
- uniform-donor pooled paths and gaps at -3, -2, and -1.

### Candidate donor pool

For deal \(j\), the primary candidate count is

\[
K_j=\min(20,\text{number of eligible donor firms}).
\]

A deal needs at least five donor firms. Candidate distance uses information no
later than -4:

- `log1p` mean patent count at -5 and -4;
- active-inventor share at -5 and -4;
- firm patent count and inventor count;
- career-age composition; and
- IPC4 cosine similarity using patent information through -4.

Pool caps of 10 and all available donors are sensitivity analyses. They cannot
replace the primary cap after validation.

The post-census amendment supersedes the preceding sensitivity sentence:
candidate-pool caps are 10, 20, and 50, accompanied by the three frozen
screening-metric omissions. There is no all-available-donor sensitivity.

### Convex-hull certification

For every deal and each of -5 and -4, the census records:

- the treated `log1p` mean;
- the minimum and maximum candidate-donor `log1p` means;
- whether the treated value is inside that interval;
- the signed distance to the nearest boundary; and
- that distance divided by the donor range.

A deal enters validation only if its treated value is inside the donor interval
at both -5 and -4. The ordinary sample gates below apply after this support
restriction. The census reports the share of initially eligible deals with
two-period hull support.

### Census-stage abort

Before any optimized weights are fitted, calculate the inventor-weighted
uniform-donor gaps at -3, -2, and -1 for the retained hull-supported sample.
Stop the entire second attempt if either:

1. uniform-donor pooled RMSE exceeds 0.10 patents; or
2. any absolute uniform-donor pooled gap exceeds 0.10 patents.

Failure produces a negative census result and no PPSCM optimization. This rule
is deliberately twice the project's 0.05 equivalence band.

## Stage B: estimator

### Fitting scale

Weights fit levels of

\[
\log(1+\bar Y_{jt}),
\]

where \(\bar Y_{jt}\) is mean patents per established inventor in deal or donor
cohort \(j\). The primary estimator does not subtract a training-period
intercept. This makes level support part of the fit and approximates
proportional patenting dynamics.

All validation gates and post effects are evaluated in raw patents per
inventor-year. Every fit table reports both raw-count and `log1p` gaps. A
raw-level, no-intercept estimator is a frozen sensitivity analysis and cannot
replace the primary `log1p` specification.

### Weight constraints and partial pooling

For every treated deal, donor weights are nonnegative and sum to one.
The primary objective is the normalized Ben-Michael--Feller--Rothstein
combination of deal-specific and pooled trajectory imbalance plus an L2
penalty. The pooling parameter is the paper's heuristic value, computed using
training data only.

Separate fitting (\(\nu=0\)) and full pooling (\(\nu=1\)) are mandatory
diagnostics. If the heuristic estimator fails while either endpoint passes, the
primary analysis still fails.

### Ridge grid

The grid is:

\[
\lambda\in
\{10^{-6},10^{-5},10^{-4},10^{-3},10^{-2},10^{-1}\}.
\]

Within each outer validation fold, leave-one-training-period-out prediction
selects the penalty using only that fold's training block. Errors are
aggregated across deal-period observations under the frozen inventor weights.
The chosen value is the largest \(\lambda\) within one standard error of the
minimum. Remaining ties favor the larger penalty. Every control-null draw
repeats this selection; it may not inherit the real design's penalty.

## Stage C: rolling validation

The fixed outer folds are:

| Held-out event time | Weight-training periods |
|---:|---|
| -3 | -5, -4 |
| -2 | -5, -4, -3 |
| -1 | -5, -4, -3, -2 |

The donor pool is fixed before observing -3. Each fold reselects the ridge
penalty and recomputes the heuristic pooling parameter using only its training
block.

## Validation gates

Every governing gate must pass:

1. At least 100 treated deals remain.
2. At least 80% of eligible landmark treated inventors remain after donor,
   cohort-size, and hull-support restrictions.
3. Every retained deal has at least five donor firms, each with at least five
   established inventors.
4. Inventor-weighted pooled raw-count validation RMSE is no greater than 0.05.
5. Every inventor-weighted pooled raw-count validation gap is inside
   [-0.05, 0.05].
6. PPSCM validation RMSE is no greater than uniform-donor RMSE. If
   uniform-donor RMSE is greater than 0.05, PPSCM must additionally reduce it
   by at least 50%. The improvement ratio is always reported.
7. PPSCM validation RMSE is no greater than the nearest-donor benchmark RMSE.
8. The governing joint validation test has p greater than 0.10.
9. Equal-deal validation RMSE is no greater than 0.075 and all equal-deal gaps
   are inside [-0.075, 0.075].
10. Median donor ESS is at least 2, tenth-percentile ESS is at least 1.25, and
    the largest individual donor weight is no greater than 0.90.
11. Every leave-one-cohort-out pooled gap is inside [-0.075, 0.075].
12. Removing each of the ten largest absolute deal contributions leaves every
    pooled gap inside [-0.075, 0.075].

Gate 2 is accompanied by, but not replaced by, retained-count comparisons
against attempt 1, the full landmark population, and the full P5c population.

### Governing validation inference

The governing procedure is a 9,999-replication, fixed-seed, deal-level Webb
multiplier bootstrap-t. Each replication reconstructs bootstrap outcomes and
reselects the ridge penalty, heuristic pooling parameter, and donor weights.
The seed is 20260729. This keeps the P0 convention of 9,999 Webb replications
and makes weight-estimation uncertainty part of the governing procedure.

Two-way deal/donor-firm clustered covariance estimates conditional on fitted
weights are mandatory companion diagnostics. They do not govern Gate 8 because
they omit weight-estimation uncertainty. Any disagreement with the governing
bootstrap is flagged in the results note and table.

## Stage D: control-null post-period gate

The control-null stage adapts the certified architecture of scripts 35a--35g
but rebuilds the entire PPSCM pipeline for every draw. It is pipeline
falsification, not randomization inference for the acquisition ATT.

### Compute profile and production budget

First run one noninferential profiling draw in each arm. Record elapsed time,
peak memory, and output size. These profiling draws do not enter any
distribution. The production design then uses 499 certified draws per arm.

The DuckDB memory cap is 9GB and execution uses at most two threads. If the
profile projects more than 48 hours for the 998 production draw-arms or exceeds
the memory cap, stop and write a compute-feasibility amendment. The draw count
may not be reduced silently.

### Null arms

The two arms are:

1. `symmetric_landmark`: exact primary PPSCM eligibility; and
2. `symmetric_landmark_plus_continuity`: both pseudo-arms additionally require
   own-firm patent evidence somewhere in -5 through -1.

The second arm diagnoses selection induced by conditioning on continued
patenting. The first arm governs.

### Per-draw procedure

Each draw:

1. assigns pseudo-acquisition cohorts to acquisition-clean firms;
2. constructs symmetric landmark inventor cohorts;
3. applies the five-inventor donor-cohort rule;
4. rebuilds candidate pools and hull support;
5. performs nested ridge selection and heuristic partial pooling;
6. runs the complete rolling pre-period validation; and
7. estimates the pseudo-ATT over +1 through +5.

Draw-level ridge penalties and weights are re-estimated. Comparable draws must
match the real design's supported inventor volume, nominal deal count,
effective deal count, and maximum deal-weight share within the frozen bounds
adapted from the 35a--35g framework.

Each draw's 5% rejection indicator uses 999 fixed-seed, deal-level Webb
bootstrap-t replications, matching the existing 35a control-null convention.
The seed is a deterministic function of the production draw ID. Using 999
rather than the real validation stage's 9,999 replications is an explicit
compute concession for the repeated null exercise; it does not affect the
draw-level ATT used to assess centering.

### Control-null gates

For inference-comparable draws in the governing arm:

1. the 95% Monte Carlo confidence interval for the mean pseudo-ATT lies wholly
   inside [-0.05, 0.05];
2. the exact binomial confidence interval for the 5% false-rejection share
   contains 0.05 and has an upper endpoint no greater than 0.10;
3. the mean pseudo-event coefficient at every event time +1 through +5 lies
   inside [-0.05, 0.05]; and
4. all result-certification, disjointness, provenance, and no-recentering checks
   pass.

The null summary may not calculate an empirical p-value against the real ATT,
recenter the placebo distribution, estimate a bias ratio, or bias-adjust the
real result.

Completing this stage necessarily reveals donor-side post-period trajectories.
It is therefore a falsification gate, not a blindness mechanism.

## Stage E: gated post estimation

The real post script may run only if:

- the census, validation, and control-null manifests all pass;
- the source, freeze, cohort roster, donor pool, transformation, grid, and seed
  hashes match;
- no sensitivity specification has replaced the primary estimator; and
- all required output files are present and certified.

The final weights use all five pre-periods, -5 through -1, and repeat the frozen
nested ridge-selection rule. The post stage estimates event times 0 through +5
and the average over +1 through +5 on the raw-count scale.

After the final PPSCM sample is fixed, the existing Verginer/entropy estimator
is re-estimated on the identical deal and inventor sample. That same-sample
estimate is the comparison target. The published -0.0867 estimate remains a
related reference, not an exact target.

## Code and output map

Existing 37* and 38* files remain unchanged. The second attempt uses:

- `39_run_lmv2_ppscm_second_attempt.R`;
- `39a_lmv2_ppscm_second_attempt_config.R`;
- `39b_build_lmv2_ppscm_symmetric_units.R`;
- `39c_build_lmv2_ppscm_prepanel.R`;
- `39d_validate_lmv2_ppscm_second_attempt.R`;
- `39e_run_lmv2_ppscm_control_null.R`;
- `39f_summarize_certify_lmv2_ppscm_control_null.R`;
- `39g_estimate_certify_lmv2_ppscm_post.R`; and
- `39h_report_lmv2_ppscm_second_attempt.R`.

Outputs go to
`02_analysis/output/audit/local_match_v2/P6_PPSCM_V2_SYMMETRIC/`.
All material outputs use atomic publication, stable row ordering, source and
input hashes, and fail-closed certification.

## Terminal interpretations

- Census abort: symmetric landmark cohorts lack even coarse untreated support;
  no optimized PPSCM estimate is reported.
- Validation failure: flexible synthetic weights do not produce parallel
  pre-trends out of sample.
- Control-null failure: the pipeline generates systematic pseudo-effects or
  miscalibrated inference among untreated firms.
- All gates pass: PPSCM supplies complementary evidence. Agreement with the
  same-sample Verginer estimate strengthens the interpretation; disagreement
  must be reported and explained.

No alternative pooling endpoint, donor cap, outcome transformation, penalty,
or inference method may change these terminal decisions.
