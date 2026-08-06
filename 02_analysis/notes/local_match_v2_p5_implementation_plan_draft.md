# Local Match v2 — P5 implementation plan

**Status:** Review draft for Tim and Claude. This document is not a design
lock and authorizes no implementation or outcome estimation.

**Outcome boundary:** No outcome, event-study, DiD, or treatment-effect object
may be read or estimated during P5. P5 ends after final weights and their
design diagnostics have been reviewed.

## 1. Decisions to approve before implementation

### 1.1 Main analysis specification

Freeze the following specification for the headline full-cohort and stayer
analyses:

- control universe: `u1` (never-target and acquirer-event clean);
- Stage-1 profile: `nearest_50`;
- Stage-1 support caliper: `1.5`;
- Stage-2 support caliper: `1.5`;
- technology resolution: `ipc4`;
- weighting schemes: `primary` and `equal_deal`;
- solver: the certified direct Newton entropy solver, retaining the locked
  approximate-balance fallback hierarchy;
- solve separately within each treatment-year cohort.

The three-cohort P4 pilot supports this choice:

| Coverage measure | Result |
|---|---:|
| Pooled inventor retention | 4,027 / 4,420 = 91.11% |
| Deal retention | 36 / 37 = 97.30% |
| 1995 inventor retention | 642 / 762 = 84.25% |
| 2002 inventor retention | 453 / 525 = 86.29% |
| 2009 inventor retention | 2,932 / 3,133 = 93.58% |
| Worst cohort-by-scheme pooled max-SMD | 1.59e-8 |
| Minimum reuse-adjusted ESS ratio | 0.756 |
| Minimum effective control-firm count | 7.26 |

The 1995 and 2002 coverage rates clear the locked 80% acceptable floor.
They are sufficient for estimation, but the estimand is the ATT for treated
inventors retained on common support. P5 must report the retention funnel and
must not extrapolate the estimates to excluded inventors.

Caliper `1.5` is the tightest Stage-1 value in the tested grid that clears the
80% inventor-retention floor in every pilot cohort. Caliper `2.0` adds only
40 retained inventors across the 4,420-inventor pilot spine, retains no
additional deal, and does not improve every scheme's deal-level diagnostic.
The tighter value therefore preserves local comparability without sacrificing
feasibility. This uses the same tightest-adequate-support principle as the
earlier locks; it does not make deal-level SMD a new selection criterion.

### 1.2 Required outcome-blind amendment

Before production, add a dated, hashed amendment that:

1. states that no outcome or treatment-effect estimate was inspected;
2. lists the P4 design diagnostics used: retention, deal coverage, pooled
   balance, ESS, and weight concentration;
3. states explicitly that the cohort-hybrid redesign supersedes the earlier
   P4-EB Stage-1 caliper `1.0` lock;
4. freezes `u1 / nearest_50 / Stage-1 1.5 / Stage-2 1.5 / ipc4`;
5. explains that retaining the theoretically preferred U1 donor population
   is preferable to changing the primary analysis to U3;
6. records that Stage-1 `1.0` fails the full-spine retention gate in the 2009
   U1 pilot and that `1.5` is the tightest tested value that clears the 80%
   floor in all three cohorts;
7. preserves both weighting schemes and the existing feasibility hierarchy;
8. pins the amendment hash in the selected-P5 configuration and manifest.

Do not edit or silently reinterpret the older amendment. The new record must
preserve the history of the design change.

### 1.3 DealSim is a separate analysis branch

DealSim-tercile weights are used **only** for the DealSim heterogeneity
analysis. They do not replace, modify, or pool with the main-analysis weights.

- The headline full-cohort and stayer analyses use the cohort-level main
  weights from Section 1.1.
- The primary DealSim analysis uses separate entropy solves within each
  DealSim tercile.
- The continuous DealSim and DealSim-squared model and the natural-spline
  model use the main cohort weights and remain supplementary descriptive
  analyses. Their lack of deal-level balance must be stated next to their
  interpretation.

## 2. Output and restart contract

P5 must materialize analysis weights, not only diagnostics.

### 2.1 Row-level weight grain

Each weight row must retain enough information to reconstruct the stacked
comparison without ambiguous joins:

- `analysis_scope`: `main` or `dealsim_tercile`;
- `cohort`;
- `dealsim_tercile`, missing for `main`;
- `deal_id`;
- `codinv`;
- treated/control indicator;
- treated or control group identifier as applicable;
- weighting scheme;
- base weight;
- raw entropy tilt;
- final analysis weight;
- solver and feasibility tier;
- support-profile hash and execution hash.

The composite key must be certified as unique. The same control inventor may
legitimately appear in more than one deal stack, so `deal_id` cannot be
dropped from the key.

### 2.2 Files

Write:

- one atomic Parquet weight shard per
  `(analysis_scope, cohort, tercile if applicable, scheme)`;
- a checksum manifest for every shard;
- an assembled main-weight Parquet dataset;
- a separate assembled DealSim-tercile weight dataset;
- retention-funnel, balance, ESS, concentration, and per-deal balance CSVs;
- the fixed DealSim tercile map and cutpoints;
- a run manifest containing input identities, code hashes, configuration,
  package versions, solver, thread count, memory limits, and timestamps;
- scheduler status and separate worker logs.

Never overwrite P4 artifacts. A restart may reuse an artifact only when its
execution hash, input hash, row count, and live checksum all match.

## 3. Main-weight implementation

1. Derive the complete list of gate-eligible treatment cohorts from the
   certified P3 analysis spine; do not hard-code the three pilot cohorts.
2. Build or reuse the disk-backed sparse IPC4 technology cache.
3. Select only `u1 / nearest_50 / caliper 1.5`; do not run the 24-cell grid.
4. Construct and atomically persist one projection-preserving Stage-2 edge
   cover per cohort. Reuse it across `primary` and `equal_deal`.
5. Solve both schemes with Newton and materialize the row-level weights
   immediately after each successful solve.
6. Recompute all diagnostics from the persisted weights rather than trusting
   only the in-memory solver object.
7. Compare retained and unsupported treated inventors on pre-deal five-year
   patent count and career age, overall and by cohort. Report means,
   quantiles, standardized differences, and the direction of selection.
8. Report the effective control-firm count by cohort and scheme prominently.
   In the pilot, 1995 has only 10.61 effective firms under `primary` and 7.26
   under `equal_deal`, despite acceptable inventor retention.
9. Assemble cohorts only after every completed shard passes validation.

The existing exact/0.05/0.10 feasibility hierarchy remains operative. If a
cohort fails the 80% retention floor or all allowed balance rungs, save its
completed cache and diagnostics, mark the cohort unsupported, and stop the
final merge for review. Do not tune the caliper, change universe, or drop
covariates automatically.

## 4. DealSim-tercile implementation

### 4.1 Construct and certify DealSim

DealSim must exist as a certified, outcome-free input before terciles are
formed:

1. construct each target and acquirer group's pre-deal IPC portfolio from
   `group_ipc_year` using the frozen lookback window;
2. compute deal-level target-acquirer cosine similarity;
3. exclude and separately flag the 15 placeholder acquirers;
4. certify one row per deal, the timing window, group assignments, cosine
   bounds, missingness, and placeholder exclusions;
5. persist the DealSim table and pin its definition and file hashes.

No tercile cutpoint may be frozen until this certification passes.

### 4.2 Fixed deal classification

Construct DealSim terciles once, before any heterogeneity outcome is opened:

1. start from one observation per analysis-spine deal with at least one
   treated inventor;
2. exclude all 15 placeholder-acquirer deals (`999xxxx`);
3. require a finite DealSim value;
4. compute global deal-level one-third and two-thirds quantiles, not
   inventor-weighted or cohort-specific quantiles;
5. pin the quantile method and boundary rule in the amendment;
6. persist `deal_id`, DealSim, tercile, exclusion reason, and the two
   cutpoints.

Global cutpoints keep “low,” “middle,” and “high” technological overlap
comparable across acquisition cohorts. Support failures must not move the
cutpoints.

### 4.3 Tercile-specific weights

For each cohort, DealSim tercile, and weighting scheme:

1. subset the selected-spec U1 admissible support and cached Stage-2 edges to
   deals assigned to that tercile;
2. rebuild the cohort roster within that tercile;
3. solve entropy balance within the cohort-tercile stratum;
4. apply the same retention, balance, ESS, and concentration diagnostics as
   the main branch;
5. persist and validate the weight shard before moving on.

Do not add within-deal balance constraints and do not solve separately for
every deal. If a cohort-tercile stratum is too small or infeasible, report it
as unsupported. Do not borrow deals across terciles, alter the cutpoints, or
change the selected matching specification.

The DealSim branch should reuse the main sparse technology shards and
deal-specific edge support. It should not rebuild overlapping inventor-pair
similarities.

### 4.4 Pre-specified small-stratum rule

The DealSim estimator re-runs CS(2021) within each tercile, but its underlying
comparisons remain cohort-specific group-time ATTs. P5 therefore must not pool
cohorts into one unconstrained tercile balance solve: pooled balance could
hide imbalance in the cohort-specific comparisons that identify CS(2021).

- Attempt both schemes in every cohort-tercile stratum.
- `primary` is the headline DealSim weighting scheme.
- `equal_deal` is a co-reported sensitivity scheme.
- Apply the existing exact/0.05/0.10 balance hierarchy and ESS floor.
- If `equal_deal` fails while `primary` passes, mark that cell unsupported
  under `equal_deal`; do not impute or retune it.
- If `primary` fails, exclude that cohort-tercile cell from the supported
  tercile estimand and report its inventor and deal mass explicitly.
- Report a tercile ATT only if the supported primary cells jointly retain at
  least 80% of that tercile's treated inventors and 85% of its treated deals.
  Otherwise label the tercile unsupported and do not estimate its ATT.

This rule is frozen before DealSim outcomes are inspected. P5 still stops for
review after reporting any unsupported cells.

## 5. Diagnostics and certification

### 5.1 Mandatory checks for every weight shard

- unique composite key;
- no missing, infinite, or materially negative weights;
- treated and control masses match their scheme-specific targets;
- persisted weights reproduce the in-memory balance vector within tolerance;
- pooled max-SMD meets the selected feasibility rung;
- reuse-adjusted ESS passes its locked threshold;
- retention and deal coverage use the complete treated-spine denominator;
- max weight share and reuse concentration are reported;
- effective control-firm count is reported by cohort and scheme;
- retained-versus-unsupported treated characteristics are reported;
- every retained roster row appears exactly once in the correct shard;
- the file passes checksum and round-trip read validation.

### 5.2 Solver verification

All production weights use Newton, so P5 does not cross a solver boundary.
Before the full run:

1. solve one feasible real pilot cell with both Newton and WeightIt;
2. compare support, final weight masses, weighted covariate means, ESS, and
   normalized row weights;
3. report numerical differences;
4. gate on identical support and equivalent weighted moments, not bitwise
   equality of floating-point weights.

Retain the existing synthetic certification and add a materialization
round-trip test.

### 5.3 Deal-level imbalance and DealSim diagnostic

For the non-placeholder DealSim sample:

- report the distribution of per-deal max-SMD under the main weights;
- report Pearson and Spearman correlations between per-deal max-SMD and
  DealSim;
- regress each signed deal-level covariate imbalance on standardized DealSim;
- apply a Holm correction across the signed-covariate tests;
- report the same diagnostics within DealSim terciles;
- label these as diagnostics of residual within-deal heterogeneity, not as
  automatic specification-selection gates.

A null scalar correlation alone is not proof that residual deal-level
confounding is absent. The signed covariate diagnostics show whether
cross-deal offsets vary systematically with technological similarity.

## 6. Compute and memory strategy

1. Keep R for orchestration and the solver and DuckDB for sparse joins.
2. Use five-million-pair sparse technology blocks.
3. Keep each cohort in an isolated audit/cache directory.
4. Start with one representative large cohort.
5. After its memory check passes, run at most two independent cohorts
   concurrently.
6. Keep DuckDB at two threads and a 6 GB limit per worker initially.
7. Start a second worker only with at least 12 GB available memory.
8. If available memory remains below 4 GB for three polls, terminate and
   requeue the newer worker; reuse its atomic checkpoints.
9. Increase block size or worker count only after recorded memory evidence,
   never merely to keep all CPU threads busy.

U3 is not part of this P5 production run. Preserve cache compatibility for a
later U3 robustness analysis, but do not spend P5 time rebuilding a second
universe.

## 7. Execution order

1. Tim and Claude review this draft.
2. Resolve comments and sign the outcome-blind superseding amendment.
3. Implement row-level weight materialization.
4. Run all database-free and synthetic main-weight certifications.
5. Run the real-cell Newton/WeightIt comparison.
6. Run one large selected-spec cohort and verify speed, memory, restart, and
   persisted weights.
7. Run all main cohorts with the guarded two-worker scheduler.
8. Validate and assemble the main weights.
9. Construct and certify DealSim and pin its provenance hashes.
10. Freeze the global DealSim tercile map.
11. Implement and certify the DealSim-only weighting branch.
12. Run the DealSim cohort-tercile solves using the existing caches and the
    pre-specified small-stratum rule.
13. Produce the final P5 diagnostics and computational report.
14. Stop for design review. Do not estimate outcomes.

## 8. P5 completion criteria

P5 is complete only if:

- the superseding amendment and configuration hashes agree;
- every supported cohort has both main weighting schemes;
- every successful solve has a checksum-verified row-level weight shard;
- assembled tables reproduce all source shards exactly;
- coverage, balance, ESS, concentration, and deal-level diagnostics exist;
- DealSim weights exist only in the separate DealSim branch;
- unsupported cohorts or terciles are explicit and have not been silently
  removed;
- restart and memory-guard behavior are verified;
- the run manifest proves that no outcome-analysis program was invoked.

Only after Tim and Claude approve the completed P5 report should P6 join the
weights to outcomes and estimate CS(2021) effects.

## 9. Questions for Claude

1. Do you agree that the new outcome-blind amendment should supersede the
   old Stage-1 `1.0` lock and freeze `u1 / nearest_50 / 1.5`?
2. Do you agree that 84.25% and 86.29% coverage are sufficient because they
   clear the locked 80% floor, with the estimand described as a
   common-support ATT?
3. Do you agree that DealSim-tercile weights are isolated to the DealSim
   analysis and never used for the headline estimates?
4. Should the DealSim cutpoints use the global deal-level R quantile rule
   (`type = 7`, lower boundary included), or do you prefer another rule
   pinned before execution?
5. Do you agree that cohort-specific balancing must be retained for the
   DealSim CS(2021) comparisons rather than pooling cohorts into one
   unconstrained tercile solve?
6. Do you approve the pre-specified DealSim fallback: `primary` headline,
   attempt `equal_deal`, no retuning, and report a tercile ATT only when
   supported primary cells retain at least 80% of inventors and 85% of deals?
