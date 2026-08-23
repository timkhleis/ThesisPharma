# Historical Local matching v2: P4 outcome-blind pilot

## FINAL STATUS: definitive design failure (2026-07-23)

The fifth and final pilot execution established, under every locked and
prospectively amended rule, that this matching design is **infeasible under
the locked standards** for the pilot cohorts:

- **Five-firm design (primary)**: Stage-1 base grid preferred
  (max gated |SMD| 0.057, 100% retention) but with a genuine
  firm-trajectory breach (pooled −0.31); the promoted trajectory grid and
  the bounded bisection produced no acceptable Stage-2 profile — nearest
  misses 0.004 in balance (1995 focal tenure) or 0.77pp in retention.
- **Ten-firm extension (final structural attempt)**: doubling the pool
  degraded Stage-1 base balance to acceptable-tier only (max gated |SMD|
  0.089 > 0.075), the trajectory breach persisted, the promoted grid had
  no acceptable profile (0.116–0.120 balance or 67.6% retention), and the
  guarded fallback correctly refused a non-preferred base. Stage-1 design
  failure; permanent stop per the ten-firm amendment.

No design was frozen, no matched sets were published, and no outcome was
inspected at any point. Per the pinned amendments, no further tuning
follows. The definitive-run diagnostics live in
`02_analysis/output/audit/local_match_v2/P4/run1/` (five-firm at the root,
ten-firm under `ten_firm/`); the four earlier stops are archived beside it.
The P0 lock's predeclared both-pools-fail language applies: report
selection and descriptive results without a matched ATT from this design.

---

Original package record follows.


Status: code-only delivery, 2026-07-23. The synthetic certification (17d) has
been executed; the real pilot has not been run, no production database was
provisioned by this delivery, and no outcome was inspected. Stop point:
Codex review before any pilot execution.

## What P4 does

P4 selects and freezes the pilot matching design for the locked pilot
cohorts (1995, 2002, 2009), using only pre-treatment matching variables from
the certified P3 version-2 interfaces (commit `dea29fb`, P3 config hash
`11929f97…3cf8a4`, P3 interface-manifest hash `ce7ed077…874a9a`; version 2
repairs the control-firm trajectory windows found broken by the first pilot
execution).

- **Stage 1** (`17b`): evaluates total-distance calipers {inf, 2.0, 1.5,
  1.0} on `lmv2_p3_stage1_edges` (IPC4 only, `distance_base` first),
  computes equal-treated-deal-weighted core firm balance
  (inventor-size-weighted reported diagnostically), applies the prospective
  trajectory-promotion rule (promote and evaluate
  `distance_with_trajectory` when the selected base profile breaches the
  locked trajectory SMD trigger, or when no acceptable base profile
  exists), selects by the locked tiers and the locked lexicographic order,
  and freezes five control firms per deal (weight 1/5) with a logical
  checksum before any Stage-2 work.
- **Stage 2** (`17c`): builds the donor pool only from the frozen firms,
  computes control focal tenure/exclusivity on demand, runs a mutually
  exclusive terminal-reason funnel (deal lost at Stage 1 → treated
  covariate missing → insufficient complete donors → no shared IPC4 →
  recency failure → selected-resolution cosine missing → caliper reasons →
  matched; reconciles exactly to the pilot spine). Pre-caliper funnel steps
  test donor count only; an inventor whose remaining donors sit in one firm
  stays pending and receives `no_second_firm` from the selector, so
  firm-diversity failures are attributed correctly. Stage 2 is genuinely
  cohort-sharded: Pass A writes each cohort's frames to a temporary
  `shards/` file and frees them, and Pass B reloads one shard at a time
  after the resolution decision (shards are deleted before the pilot
  finishes). One technology cache per cohort produces admissible-pool
  support diagnostics for `ipc4`, `ipc_main_group`, and diagnostic-only
  `ipc7`; the binary resolution rule from the pinned resolution lock is
  applied **before** inspecting any caliper; the caliper grid runs through
  the reused 16c engine (three distinct controls from at least two firms,
  weight 1/3, deterministic ties, replacement across treated, no silent
  relaxation); the P4 design is frozen or the pilot stops with a
  design-failure record. The locked `big` target-size indicator is read
  from the certified P2 interface `lmv2_treated_primary` (deal-level
  pre-treatment columns only).
- **Certification** (`17d`): database-free synthetic checks (resolution
  mapping and binary rule, trajectory trigger, cohort-standardized SMD,
  tier and lexicographic selection, caliper boundary, no-acceptable stop,
  unsupported accounting, two-firm repair, weight sums, deterministic IDs,
  reuse/ESS, funnel exclusivity, checksum stability).
- **Runner** (`17e`): requires explicit `--db`, `--p3-manifest`,
  `--audit-dir`; refuses P3 hash drift; audits P4 sources for
  outcome-specific identifiers by scanning executable R tokens only
  (files are parsed and comment tokens excluded; string literals such as
  SQL remain in scope); hashes all P4 source/config/lock files; runs 17d,
  then two complete pilot runs in fresh isolated run directories;
  publishes `p4_interface_manifest.csv` only when both logical manifests
  are identical.

## Prospective decisions recorded in this package

- The resolution-naming lock (`local_match_v2_p4_resolution_lock.md`, SHA-256
  `d144c614…c790d5`) fixes the "seven-character" → `ipc_main_group` mapping,
  the binary selection rule, and the diagnostic-only status of full-subgroup
  `ipc7`. It is pinned in `17a` and folded into the P4 config hash.
- **Line-ending caveat for hashed design records.** The certified hash chain
  (amendments, resolution lock) is computed on LF file bytes, matching the
  git blobs and the certified lmv2-foundation worktree. `core.autocrlf=true`
  rewrites these files to CRLF on a fresh checkout, which breaks the chain
  (observed and repaired in this worktree during delivery: the amendments
  file had to be restored to its certified LF bytes). Any future checkout
  must renormalize the hashed notes to LF, or the repository should pin
  `eol=lf` for them in `.gitattributes` (left to review, since P4 may only
  create its own files).
- The small-cohort amendment (`local_match_v2_p4_small_cohort_amendment.md`,
  SHA-256 `49e9efa9…38e579`, pinned in `17a`): cohort-specific Stage-1 SMD
  and trajectory-promotion gates bind only in pilot cohorts with at least
  10 treated deals in the primary spine; pooled gates always bind;
  small-cohort SMDs stay computed and prominently reported, ungated;
  Stage-2 gates unchanged; the same principle applies prospectively in P5a
  via era-level balance evaluation. Approved by review after the first
  pilot execution stopped at the Stage-1 gate (only pre-treatment balance
  diagnostics were inspected; outcome-blindness maintained).
- The trajectory-fallback amendment
  (`local_match_v2_p4_trajectory_fallback_amendment.md`, SHA-256
  `326d55a6…77d054`, pinned in `17a`): promotion is attempted exactly as
  locked; if no promoted profile is acceptable, fallback to the base grid
  is permitted only when the base profile holds the preferred tier
  (acceptable-only base cannot qualify); the fallback pool is frozen
  provisionally; after Stage 2, firm stock/size/trajectory balance is
  recalculated under the final inventor-match weights and the
  firm-trajectory |SMD| must clear the locked 0.10 acceptable bound
  (pooled and gate-eligible cohorts) or the pilot stops without a frozen
  design. Adopted outcome-blind after the second pilot execution stopped
  at the promoted grid (base preferred 0.057/100%; promoted grid failed by
  0.014 on pooled stock or 6.6pp on retention; only balance/retention
  diagnostics inspected).
- The bounded caliper-bisection amendment
  (`local_match_v2_p4_bisection_amendment.md`, SHA-256 `455e3245…77a9e72`,
  pinned in `17a`): when the locked Stage-2 grid yields no acceptable
  profile and adjacent calipers fail exclusively on complementary gates
  (looser fails balance only, tighter fails retention only), at most two
  midpoint calipers are evaluated under identical unrelaxed gates; the
  bracket updates by failure type; an acceptable midpoint refines toward
  the looser boundary for higher retention; the existing lexicographic
  selector then runs over all evaluated profiles; the final firm-trajectory
  result never selects among calipers; if no acceptable profile emerges or
  the final gate fails, the design stops with no further local gate
  amendments. Adopted outcome-blind after the third pilot execution
  (cI_2 failed only on 1995 focal-tenure SMD 0.117; cI_1.5 failed only on
  75.3% inventor retention).
- The ten-firm extension amendment
  (`local_match_v2_p4_ten_firm_extension_amendment.md`, SHA-256
  `c9b364b7…104eac`, pinned in `17a`): the final structural attempt. The
  five-firm design stays primary with its diagnostics preserved at the run
  root; ten firms (equal weights 0.1) activate only after a five-firm
  Stage-2 terminal failure (bounded refinement exhausted or final
  firm-trajectory gate), never after a Stage-1 failure; identical Stage-1
  machinery, gates, small-cohort rule, bisection, and Stage-2 design; the
  ten-firm attempt writes to `ten_firm/` inside the run directory; if it
  also fails, the pilot stops permanently — the design is infeasible under
  the locked standards and no further tuning follows.
- Core SMD gates use unit-level scalars only; technology cosine is reported
  through support/distribution diagnostics, never as an SMD with an
  implicit treated value of zero.
- Stage-2 retention gates use the full pilot spine (all primary-spine
  treated inventors/deals in the pilot cohorts); Stage-1-conditional
  retention is reported as a diagnostic decomposition only.
- The Stage-2 lexicographic selection order (inventor retention → deal
  retention → max |SMD| → reuse-adjusted ESS → loosest caliper) is declared
  prospectively in `17a`; the P0 lock names a Stage-1 order only.
- `inventor_retention_min = 0.80` is a floor: retention above 0.90 with
  acceptable-only balance remains acceptable.
- Pooled SMDs standardize each observation by its own cohort's locked P3
  scaler SD before pooling.

## Provisioning contract for the later execution stage

The isolated P4 worktree carries exact byte copies of the certified audit
manifests (never committed, hash-verified at source time by `16a`/`17a`):

- `02_analysis/output/audit/local_match_v2/P2/p2_interface_manifest.csv`
  (SHA-256 `463f8ee9…74dec`);
- `02_analysis/output/audit/local_match_v2/P3/p3_interface_manifest.csv`
  (SHA-256 `ce7ed077…874a9a`, P3 version 2).

The production database is **not** provisioned by this delivery. The pilot
reads the certified P3 worktree database read-only.

Operator command (from `.worktrees/lmv2-p4-pilot`, PowerShell):

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\17e_run_lmv2_p4.R `
  --db=..\lmv2-foundation\02_analysis\output\thesis_foundation.duckdb `
  --p3-manifest=..\lmv2-foundation\02_analysis\output\audit\local_match_v2\P3\p3_interface_manifest.csv `
  --audit-dir=02_analysis\output\audit\local_match_v2\P4
```

Anticipated cost: the pilot cohorts hold roughly a fifth of the Stage-1
edge table; Stage 2 is cohort-sharded with one technology cache per cohort.
Expected 10–25 minutes per pilot run under the 9 GB / 4-thread DuckDB caps,
so certification plus both runs should finish within about an hour on this
machine. Peak R-side memory is bounded by a single cohort's admissible pair
frames (order of a few million rows, three resolutions long-format): only
one cohort shard is in memory at a time in both passes.

## Code-only boundary

- Executed in this delivery: parsing of all `17*` files, sourcing of `17a`
  (full hash chain against the provisioned manifests), the complete `17d`
  synthetic certification, and negative tests of the runner's refusal
  paths. Nothing touched the production database.
- Not executed: `17b`/`17c` against real data, the twice-run determinism
  gate, publication of any `p4_interface_manifest.csv`.
- No outcome variable, outcome table, or treatment-effect estimate was
  read or constructed.
