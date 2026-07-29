# Prospective freeze: partially pooled synthetic control

Date frozen: 2026-07-29

## Purpose

This is a prospective triangulation exercise, not a replacement chosen after
seeing post-acquisition estimates. It asks whether deal-specific synthetic
controls can repair the residual pre-period mismatch in Local Match v2.

## Frozen sample and estimand

- Treated units are acquisition deals in cohorts 1995--2010.
- Inventors must be attached to the target at event time -7 or -6.
- Donor firms must satisfy the Local Match v2 U2 acquisition-clean rule through
  event time +5.
- Each treated outcome is the mean patent count of the fixed early-recruited
  target-inventor cohort.
- Each donor outcome is the mean patent count of the corresponding fixed
  early-recruited inventor cohort in that donor firm.
- The post-acquisition estimand, if validation passes, is the average effect
  over event times +1 through +5. The primary aggregation weights deals by
  their number of treated inventors; equal-deal weighting is secondary.

## Information timing

- Donor-firm screening uses firm size, patenting, and IPC4 information available
  no later than event time -4.
- Five nearest acquisition-clean donor firms are retained per deal; a deal must
  have at least three.
- Synthetic weights use only event times -7 through -4.
- Event times -3, -2, and -1 are untouched validation periods.
- No event-time 0 or post-acquisition outcome may be queried unless all primary
  validation gates pass.

Recruitment occurs at -7 or -6, so those two outcomes are conditioned by the
cohort definition. They are included in fitting to provide four training
periods, but the untouched -3 to -1 validation block carries the credibility
test.

## Estimator

- Outcomes are intercept-adjusted by subtracting each unit's mean over the
  training periods.
- Donor weights are nonnegative and sum to one separately for every deal.
- The primary ridge penalty is 1e-4 after normalizing the pooled and separate
  imbalance objectives.
- The partial-pooling parameter is fixed by the Ben-Michael--Feller--Rothstein
  heuristic: the ratio of pooled to separate RMS imbalance under separately
  fitted synthetic controls, capped to [0,1].
- The fit frontier at pooling parameters 0, the heuristic value, and 1 is
  retained as a diagnostic.

## Prospective validation gates

All of the following must pass before post-acquisition outcomes are opened:

1. At least 100 deals and at least 80% of early-recruited treated inventors are
   retained.
2. Primary partially pooled validation RMSE is no larger than the uniform-donor
   benchmark RMSE.
3. Primary partially pooled validation RMSE is at most 0.05 patents.
4. Every pooled validation gap at -3, -2, and -1 is inside [-0.05, 0.05].
5. The joint test of the three pooled validation gaps has p > 0.10.
6. Donor weights are not pathologically concentrated: median donor effective
   sample size is at least 2, the tenth percentile is at least 1.25, and the
   largest donor weight is at most 0.90.
7. The partially pooled training objective is finite and no worse than the
   uniform-donor objective under the same normalization.

Failure means that synthetic control does not improve identification enough for
this dataset. In that case the exercise ends with pre-period diagnostics and no
post-acquisition estimate.
