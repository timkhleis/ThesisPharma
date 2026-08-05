# Control-only pseudo-treatment validation

## Scope

This package asks whether the certified Local Match v2 pipeline produces a
systematically negative patent-count ATT when treatment is randomly assigned
among U2-clean control firms.

It is a pipeline-validity diagnostic, not literal randomization inference for
actual acquisitions. The surge-conditioned arm discussed during review is not
implemented.

## Revised simple-random design

- Assignment is at the firm level and deterministic from the recorded seed.
- Random U2-clean firms are accumulated within cohort until the
  donor-eligible pseudo-treated inventor volume is as close as possible to
  the real treated-inventor volume.
- A pseudo firm can be used once per draw.
- Pseudo-treated firms and inventors are excluded from every donor role.
- The main unrestricted arm covers 1994--2010 and is predicted to center on
  zero. A censoring-clean unrestricted arm covers 1994--2008 and is also
  predicted to center on zero.
- A paired 1994--2008 patent-continuity arm conditions on an observed firm
  patent at or after \(g+5\). It is a post-period selection diagnostic with an
  expected positive sign, not a firm-exit correction.
- Two hundred deterministic allocations are searched per draw. Every cohort
  must attain 80--125 percent of its real inventor-volume target.
- Attempt-seed blocks are disjoint across draws and between preflight and
  production; a positive tooth test enforces this.
- P4/P5 imports the production configuration: U2, nearest-50, Stage-1 caliper
  2.0, Stage-2 caliper 1.5, IPC4, at least three controls and two firms,
  primary weights, and count-active annual trajectory balance over
  event times -5 through -1.
- P6 uses patent count, reference period -1, average post period +1 through
  +5, and 999 pseudo-firm-level wild-bootstrap replications.
- The placebo distribution is not recentered. It is summarized by its mean,
  Monte Carlo standard error, and dispersion. False rejection is reported
  only for draws comparable in supported inventor volume and in both nominal
  and effective pseudo-firm counts.
- No empirical p-value against the real ATT, bias ratio, or adjusted real ATT
  is calculated.

Preflight draw IDs are 1-10. Production IDs begin at 1001 and remain locked
until the production draw count is frozen.

## Code map

P4/P5 worktree:

- `25a_lmv2_control_null_config.R`: frozen settings and production lock.
- `25b_build_lmv2_control_null_assignments.R`: U2 candidates, deterministic
  firm assignment, pseudo-treated units, exclusions, and raw pre-period gaps.
- `25c_run_lmv2_control_null_design.R`: one-cohort adapter into the certified
  P4/P5 engine.
- `25d_certify_lmv2_control_null_design.R`: assignment and weight
  certification.
- `25e_build_lmv2_control_null_handoff.R`: annual-trajectory entropy balance
  and P6 roster.
- `25f_report_lmv2_control_null_preflight.R`: reproducible real-versus-pseudo
  feasibility and retention comparison.
- `25_run_lmv2_control_null_preflight.R`: assignment-only preflight.
- `25_run_lmv2_control_null_design.R`: restartable 17- or 15-cohort support
  and balancing runner. It never reads post-period outcomes.

P6 worktree:

- `35a_lmv2_control_null_config.R`: P6 settings plus sample-specific volume
  and effective-cluster benchmarks.
- `35b_materialize_lmv2_control_null_panel.R`: certified P6 panel
  materialization.
- `35c_estimate_lmv2_control_null_draw.R`: certified P6 estimator and
  pseudo-deal wild bootstrap.
- `35d_summarize_lmv2_control_null_distribution.R`: centering, Monte Carlo
  uncertainty, and conditional false-rejection reporting.
- `35e_certify_lmv2_control_null_results.R`: result guards and tooth tests.
- `35f_test_lmv2_control_null_summary.R`: fast positive/negative summary
  fixtures, including a tooth test for the per-draw comparability flags.
- `35g_compare_lmv2_control_null_arms.R`: one-table comparison of the
  1994--2008 patent-continuity and unrestricted placebo means.
- `35_run_lmv2_control_null_validation.R`: restartable production runner;
  it rejects all preflight draw IDs.

## Revised v3 assignment smoke

All ten outcome-blind unrestricted assignments passed every assignment,
exclusion, checksum, uniqueness, covariate-completeness, cohort-volume, and
raw-preperiod-grid check. They contain 28,368--29,831 pseudo-treated inventor
exposures, or 97.27--102.29 percent of the real treated volume, across
1,114--1,520 pseudo firms. Every cohort lies inside the frozen 80--125 percent
band; the observed extrema are 86.99 and 115.24 percent. The draws use ten
disjoint seed blocks and publish ten distinct assignment hashes.

Between 21 and 75 inventors per draw appear in more than one pseudo-deal
exposure and are now flagged rather than silently coded as single exposure.
The pooled raw firm-covariate maximum SMD is 0.724--0.829, confirming that
random untreated firms are not substitutes for acquisition targets. This
limits the exercise to implementation falsification, as intended. Runtime is
111--208 seconds per assignment after the cohort-indexed allocator replaced
the original repeated full-table scans.

The two 1994--2008 arm smokes also pass. The censoring-clean unrestricted arm
assigns 24,301 inventor exposures across 1,229 firms (99.34 percent of the
real cohort volume; cohort range 91.87--109.00 percent). The
patent-continuity-conditioned diagnostic assigns 24,573 exposures across 682
firms (100.45 percent; cohort range 87.80--113.14 percent). The latter has
100-percent observed patent continuity by construction and retains its
prospectively predicted positive sign.

The complete outcome-blind support preflight for unrestricted draw 1 is not
fully feasible under the unchanged production design. Eleven of seventeen
cohorts pass; cohorts 1994, 1997, 1998, 2001, 2002, and 2007 fail. Five fail
the locked full-spine retention floor and cohort 2001 fails the permitted
overlap-weight tolerance ladder. Pooled support retention is 69.77 percent
and the minimum cohort retention is 27.08 percent. The 17 cohort runs consume
26.5 minutes in total. No design rule was relaxed and no placebo outcome was
opened. This establishes that matching pseudo-treated inventor volume does
not reproduce the support geometry of real acquisition targets.

Firm-level covariate similarity to real acquisition targets is deliberately
diagnostic rather than an acceptance gate. The pseudo firms are substantially
smaller and otherwise different from real targets; this limits the test to
implementation falsification.

The revised cohort-1996 engineering smoke passed the P4/P5 adapter:
107 pseudo-treated inventor exposures entered and 70 remained supported
(65.42 percent). Entropy balance was exact (maximum SMD
\(2.6\times10^{-11}\)); reuse-adjusted inventor ESS was 612.1 and effective
firm count was 141.2. The low support retention reinforces the need for the
post-support volume gate. This verifies wiring only. No placebo outcome has
been opened.

## Archived v1 preflight result

Draw 1 assigned 341 unique pseudo-deals to 341 unique U2-clean firms. The
corrected builder creates 17,248 pseudo-treated inventors by drawing exactly
from the donor-eligible `lmv2_p3_inventor_general_units` control rows. All
assignment, exclusion, checksum, cohort, covariate-completeness, and raw
pre-period-grid checks pass.

The corrected unchanged P4/P5 support stage completed for all 17 cohorts in
35.6 minutes:

- 9 cohorts passed the frozen support and balance decision.
- 7 cohorts failed the locked retention rule.
- cohort 1994 failed entropy feasibility.
- pooled inventor retention was 69.8 percent;
- median cohort inventor retention was 68.0 percent;
- mean deal retention was 82.9 percent.

For the identical real U2/nearest-50/caliper-2.0 production run, all 17
cohorts are feasible and pooled inventor retention is 92.8 percent
(27,078/29,170; cohort range 82.7--97.3 percent).

The assignment mismatch is directly measured rather than inferred. In draw
1, the pooled maximum absolute SMD between real target slots and assigned
pseudo firms is 0.255 across firm patent stock, inventor count, and patent
trajectory. The pseudo/real treated-inventor count ratio is 0.591. Both fail
the prospective assignment targets of maximum absolute SMD 0.10 and count
ratio 0.80--1.25.

The original pseudo-treated builder admitted 525 inventors who were absent
from the donor-eligible general-unit table, producing missing focal-group
exclusivity. The corrected assignment preserves all 341 originally assigned
firms exactly, removes only those 525 rows, and has zero missing matching
covariates. Cohort 1999 retention rises from the contaminated 20.9 percent to
47.0 percent but remains below the locked floor; the overall feasibility
conclusion is unchanged.

That size-tercile, 341-slot design has been superseded by v3. Its outputs
remain archived for reproducibility and cannot be mistaken for production
because the version and execution hashes differ.

## Validation completed

- Every added or modified R file parses.
- The patent-continuity condition has a positive tooth test.
- The seed schedule has a positive non-overlap tooth test.
- The forbidden-statistic guard detects an empirical-p field.
- The summary fixture verifies centering, draw-specific volume and
  effective-cluster classification, and restricted false-rejection
  denominators.
- The production-draw lock has a positive tooth test.
- P6 rejects preflight draw IDs.
- An engineering smoke test passed one small cohort through the adapter with
  exact balance and no solver warnings. This verifies wiring only; it is not
  evidence about null-distribution behavior.
- Temporary cache paths were shortened after a Windows path-length failure;
  no analysis rule changed.
