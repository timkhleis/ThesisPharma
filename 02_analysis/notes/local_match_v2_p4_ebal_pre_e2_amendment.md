# Local matching v2: P4-EB pre-E2 amendment (support calipers, technology resolution, ESS/concentration thresholds)

Status: immutable prospective record, written 2026-07-23, after E1 was
approved (`f5dedc6`, `3256dbe`) and before any E2 execution or outcome
inspection. This amendment locks the four values
`local_match_v2_p4_ebal_amendment.md`'s "Deferred E2 choices" section
explicitly deferred: the Stage-1 support caliper, the Stage-2 support
caliper, the inventor technology resolution, and the ESS/weight-
concentration gate thresholds. Its SHA-256 is pinned in
`17f_lmv2_p4_ebal_config.R` and folded into the P4-EB configuration hash,
alongside the main amendment's hash. It does not edit `15a_lmv2_design_lock.R`,
the main P4-EB amendment, or any other existing amendment note.

## What evidence this amendment is based on, and what it is not

All four values below were chosen from **non-outcome, purely structural**
diagnostics run read-only against the certified P1-P3 database
(`.worktrees/lmv2-foundation/02_analysis/output/thesis_foundation.duckdb`):
candidate-pool sizes, distance distributions, shared-technology support
rates, and inventor/deal retention counts under the locked caliper grid
(`c(Inf, 2, 1.5, 1)`) and all three technology resolutions. At no point was
any entropy weight solved, any balance diagnostic computed, or any
treatment effect inspected -- the diagnostics below are entirely upstream
of the point where `WeightIt::weightit()` is ever called. This is the same
evidentiary boundary `local_match_v2_p4_ebal_amendment.md`'s "Deferred E2
choices" section drew in advance.

**Sampling note (Stage-2 diagnostics only):** the full-population Stage-2
diagnostic (all treated deals, all three technology resolutions) proved
computationally impractical -- `lmv2_stage2_technology_cache()` builds
normalized IPC vectors and cosine similarity for the full treated+control
`codinv` union across all three resolutions in one query, and at full
population size (cohort 2002 alone: 2.3M candidate pairs after the
recency-gap filter) this did not finish in 55+ minutes of active CPU work.
The reported Stage-2 diagnostics instead use a fixed, reproducible sample
of treated deals per cohort (`set.seed(20260723L)`; all deals for cohorts
with <=6, a seeded random sample of 6 otherwise: cohort 1995 used all 4
deals; cohort 2002 sampled 6 of 13 (deal_ids 102, 104, 108, 111, 112, 113);
cohort 2009 sampled 6 of 20 (deal_ids 331, 334, 338, 340, 342, 346)). This
sampling is a diagnostic-only convenience for setting prospective
parameters; it never affects the production roster, which always uses the
full population. The Stage-1 diagnostics (candidate-pool sizes, distance
distributions, deal-level admissibility) used the full population in every
cohort -- only the heavier Stage-2 technology/cosine computation was
sampled.

**A defect found while gathering this evidence, before any of it was
used:** the first attempt at the Stage-2 diagnostic crashed inside
`lmv2_prepare_stage2_edges()` (16c, certified P3 engine) with an
"undefined columns selected" error. Tracing it found that both `17h` and
`17i` built the `shared_ipc4` argument to that function from the full
`pair_key_cols`, including `deal_id` -- but the function merges that
argument by `(cohort, treated_codinv, control_codinv)` only, so the extra
column collided with the edges' own `deal_id` and was silently suffixed to
`deal_id.x`/`deal_id.y`. This was a real defect in already-approved E1
code that would have crashed the very first real Stage-2 execution; it was
fixed in `3256dbe`, with a database-free regression fixture, before any of
the diagnostics below were run. See that commit for detail; it is noted
here only because it is why gathering this evidence took two passes.

## 1. Stage-1 support caliper: `1.0`

The locked grid is `c(Inf, 2, 1.5, 1)`. At every value in the grid, every
pilot cohort has 100% of treated deals with at least one admissible
control firm (deal-level admissibility never binds). At the tightest
caliper (`1.0`):

| cohort | unique candidate firm pool | median firms per deal |
|---|---|---|
| 1995 | 49 | 30 |
| 2002 | 1,168 | 365 |
| 2009 | 3,211 | 774 |

Every cohort's pool at `caliper = 1.0` is far larger than the three Stage-1
balance moments (`log_patent_stock_5y`, `log_inventor_count_5y`,
`patent_trajectory`) require for a well-posed entropy solve. Since deal-
level admissibility is unaffected across the whole grid and the pool stays
ample even at the tightest value, `1.0` is chosen as the tightest caliper
that does not sacrifice admissibility -- the same "tightest support window
that preserves adequate size" principle used elsewhere in this package's
locked retention tiers, applied here to firm-pool size instead of
inventor retention. This is confirmed, not merely assumed: at
`stage1_caliper = 1.0` combined with the Stage-2 choices below, 100%
(1995), 89.6% (2002), and 85.8% (2009) of these candidate firms go on to
have at least one Stage-2-eligible inventor (survive the zero-lost-mass
pre-filter), so the tight Stage-1 caliper does not starve Stage 2 either.

## 2. Inventor technology resolution: `ipc4`

Comparing all three candidate resolutions at Stage-2 caliper `1.5` (chosen
below), on the sampled deals:

| resolution | 1995 inventor retention | 2002 inventor retention | 2009 inventor retention |
|---|---|---|---|
| `ipc4` | 81.8% | 93.8% | 95.7% |
| `ipc_main_group` | 59.3% | 66.6% | 75.4% |
| `ipc7` | 0.9% | 0.6% | 2.2% |

`ipc7` collapses the eligible pool almost completely at any real caliper
(as few as 0-16 eligible firms per cohort) -- consistent with the P3 lock's
own framing of `ipc7` as diagnostic-only, never a primary candidate absent
an extraordinarily permissive support profile that plainly does not hold
here. `ipc_main_group` is meaningfully worse than `ipc4` at every caliper
and, critically, drops **below the locked 50% cohort floor** at
`caliper = 1` in every pilot cohort (37.4% / 43.8% / 48.1%) -- an outright
infeasible combination under `LMV2_LOCK$pilot$stage_2_acceptable$minimum_cohort_retention`.
`ipc4` clears the acceptable retention tier's 80% inventor-retention
requirement in every cohort at `caliper = 1.5` (below) and never comes
close to the 50% floor at any caliper in the grid. `ipc4` is locked as the
Stage-2 technology resolution.

## 3. Stage-2 support caliper: `1.5`

Using `ipc4` (above), across the locked grid:

| cohort | caliper | inventor retention | deal retention | eligible firms |
|---|---|---|---|---|
| 1995 | 2 | 88.6% | 100% | 49 |
| 1995 | **1.5** | **81.8%** | **100%** | **49** |
| 1995 | 1 | 74.0% | 100% | 49 |
| 2002 | 2 | 95.8% | 100% | 702 |
| 2002 | **1.5** | **93.8%** | **100%** | **666** |
| 2002 | 1 | 87.0% | 100% | 598 |
| 2009 | 2 | 98.5% | 100% | 1,170 |
| 2009 | **1.5** | **95.7%** | **100%** | **1,129** |
| 2009 | 1 | 88.7% | 100% | 1,052 |

Deal retention is 100% in every cohort at every caliper (deal-level
admissibility never binds; only inventor-level retention does).
`caliper = 1.5` clears the acceptable tier
(`LMV2_LOCK$pilot$stage_2_acceptable`: >=80% inventor retention, >=85%
deal retention) in **every** pilot cohort with room to spare (81.8% is the
worst case, against an 80% floor), while `caliper = 1` drops the pooled
cohort (1995, 74.0%) below the acceptable floor. `caliper = 2` is looser
and gets closer to the preferred tier (>=90%) for two of three cohorts but
still leaves 1995 short (88.6%) -- it does not buy feasibility that
`1.5` lacks, only extra looseness. `1.5` is locked as the Stage-2 support
caliper: the tightest value in the grid at which every pilot cohort clears
the acceptable retention tier.

Because 1995's pooled inventor retention under this choice (81.8%, and it
will differ under the actual, unsampled full population at E2) may land on
either side of the locked 90% common-support threshold, `local_match_v2_p4_ebal_amendment.md`'s
already-specified `common-support ATT` labeling
(`lmv2_ebal_retention_label()`) applies exactly as designed; this amendment
does not change that rule or pre-judge which label the real E2 run will
carry.

## 4. ESS and weight-concentration thresholds

These cannot be chosen from real weights (none were computed), so they are
derived here as scale-dependent rules against the candidate-pool sizes
established in sections 1-3, following the same construction already
present (as inactive placeholders) in `17f`'s original E1 commit:

- **ESS ratio** (control ESS relative to the number of treated units in
  that cohort -- treated deals at Stage 1, retained treated inventors at
  Stage 2): preferred `>= 1.0`, acceptable `>= 0.5`. At Stage 1 the
  smallest cohort (1995) has 4 treated deals against a 49-firm pool, so an
  ESS of 4 (preferred) or 2 (acceptable) is structurally easy to reach
  without meaningful concentration; at Stage 2 the smallest eligible-
  control pool at the locked caliper/resolution (1995: 5,790 controls
  under the earlier, pre-shared-ipc4-fix count; re-derive against the
  final production numbers at E2) against up to ~759 supported treated
  inventors makes the ratio a genuine, non-trivial requirement -- it is
  not satisfied merely by the pool being large.
- **Maximum single-unit share of cohort control mass**: Stage 1 (firms)
  preferred `<= 0.20`, acceptable `<= 0.35`; Stage 2 (inventors) preferred
  `<= 0.10`, acceptable `<= 0.20`. Stage 2's cap is tighter because its
  pools are one to three orders of magnitude larger than Stage 1's (49-
  3,211 firms vs. thousands of eligible inventors), so a single inventor
  holding even 10% of cohort mass is a materially stronger warning sign
  than a single firm holding 20% of a 49-firm pool.

These thresholds are **activated** as gating checks by this amendment
(previously diagnostic-only per the main amendment's "Deferred E2
choices"): `lmv2_ebal_ess_concentration_gate()` (17g) is now called inside
both `lmv2_ebal_stage1_pipeline()` and `lmv2_ebal_stage2_pipeline()`, and
Stage 2's result is folded into `lmv2_ebal_terminal_gate()` as a new
gating reason (`stage2_ess_concentration_below_acceptable_tier`); Stage
1's result is checked by `17h` before the Stage-1 freeze is written, so a
Stage-1 ESS/concentration failure stops the pipeline before Stage 2 ever
runs, exactly like a Stage-1 balance failure already did.

## What this amendment does not do

It does not run E2, does not open a live production connection beyond the
read-only diagnostic queries described above, and does not inspect any
weight, balance result, or treatment effect. The sampled Stage-2 numbers
above are diagnostic estimates, not a certification that the full-
population E2 run will reproduce them exactly; E2 itself will report the
real, full-population retention and ESS/concentration figures under these
now-locked parameters, and the terminal gate will enforce the acceptable
tier against the real numbers, not the sampled ones reported here.
