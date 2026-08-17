# Verginer Ebal Diagnostic Checkpoint

Run status: **DIAGNOSIS ONLY**. No outcome estimation, final mode, staging, commit, or push was run.

## Validation Mismatch

The installed `did` package is version `2.5.0`.
The reproducible audit points to a specific support rule in `did:::pre_process_did()`: when there is no never-treated group and `control_group = "notyettreated"`, the latest treated cohort is not included in the estimated `glist` and periods at or after that cohort's treatment year are removed from the support universe.
In this data, there is no never-treated group, the latest cohort is `2014`, and `did`'s preprocessed `glist` excludes `2014`.
The four custom-only cells are cohort 2014 pre-period cells; see `did_custom_eligibility_comparison.csv`.

## True Feasibility Failures

There are `16` true ebal failures among `430` required cells; the maximum true-failure residual is `0.4683`.
- lack_common_support_categorical: 12
- numerical_nonconvergence_or_high_moment_stress: 4

The covariate-level support audit reports treated and control support for all four raw covariates and all `vr_common_ipc_cat` categories for every failed cell. The current classification finds no confirmed implementation issue; the failures are classified as support or numerical/degenerate-weight problems pending design approval.
A treated `vr_common_ipc_cat` category has zero control observations in `12` failed cells. `14` failed cells have large residuals above `1e-2`, and `2` cells have nonpositive control mass.

## Review Residual Sensitivity

There are `117` unresolved review-residual cells; the maximum review residual is `0.0008179`.
- `1e-04`: accepts 108, leaves 9, max accepted residual 7.335e-05.
- `5e-04`: accepts 116, leaves 1, max accepted residual 0.0004568.
- `0.001`: accepts 117, leaves 0, max accepted residual 0.0008179.

I do not recommend accepting a tolerance automatically. The largest review residual is small in absolute units, but a tolerance decision should be prespecified and justified as numerical approximation, not used after seeing outcome estimates.

## Decision Options

1. Align validation to the `did` support universe after `pre_process_did()`: retain 215 validation cells and exclude the 4 latest-cohort custom-only cells from the equivalence test.
2. Treat large-residual true failures as unsupported cells unless a prespecified covariate coarsening/trimming rule is approved.
3. Treat nonpositive-control-mass cells as unsupported donor-pool failures.
4. Choose one review-residual tolerance from the sensitivity audit, or keep all 117 review-residual cells unresolved.

The existing feasibility block remains in place.
