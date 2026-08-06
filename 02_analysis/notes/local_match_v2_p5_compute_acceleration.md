# Local Match v2 — P5 compute acceleration

## Decision

Keep R as the orchestration and entropy-balancing layer. The dominant P4
runtime was not interpreted R code: it was a DuckDB SQL plan that first
expanded the complete treated-inventor × control-inventor cross and only then
joined the sparse IPC4 vectors. Porting the pipeline would preserve that bad
algorithm while adding a second implementation to certify.

P5 instead uses `17x_lmv2_p5_sparse_technology_cache.R`, which joins treated
and control IPC4 vectors by shared feature first and aggregates only those
sparse matches. The P4 files and its active `run2009` cache are unchanged.

## Outcome-blind benchmark

Real inputs: cohort 2009, universe u1, deal 346, block 1.

| Quantity | P4 legacy | P5 sparse join |
|---|---:|---:|
| Candidate inventor pairs | 981,288 | Not materialized |
| Output shared-IPC4 pairs | 282,641 | 282,641 |
| Missing/extra keys | — | 0 / 0 |
| Maximum absolute cosine difference | — | 3.33e-16 |
| Wall time for technology query | 258–680 s across recent comparable P4 blocks | 1.56 s at 4 DuckDB threads |

The observed block-level improvement is approximately 165×–435×. The cosine
difference is floating-point summation order only and is far below the
certification tolerance.

An end-to-end cohort-1995 smoke run through the new disk-backed path completed
all 24 balance profiles in 387 seconds. Its technology shards were produced
in roughly 40 seconds; sampled private memory stayed below 1 GB. The remaining
runtime is primarily the entropy-balancing profile grid.

## Checkpoint and memory contract

- P5 writes to its own audit directory. It never overwrites P4 pilot outputs.
- IPC vectors, every technology block, every deal generation, and every
  profile diagnostic row are atomically committed and checksum-validated.
- Restart skips completed artifacts only when the full P5 execution hash,
  input identity, and live checksum match.
- Every production cohort uses the disk-backed path. No cohort-wide pair
  matrix is collected into R.
- The P5 execution hash includes the sparse algorithm, P5 runner, P4/P3
  matching code, configuration, and P3 interface manifest.

## Resource strategy for the 12-logical-core workstation

1. Run one cohort worker first. This is the safe default and already removes
   the all-day technology-cache bottleneck.
2. Do not increase the 6 GB DuckDB limit merely to seek speed; memory was not
   the bottleneck, and a higher limit weakens the OOM guard.
3. After measuring a representative large cohort, at most two independent
   cohort workers may be run concurrently, each in a separate audit
   directory. Do not parallelize blocks inside one cache directory.
4. Keep DuckDB at two threads per worker initially. More threads have little
   value after the sparse rewrite and can reduce throughput when two cohort
   workers run concurrently.
5. Preserve one worker per cohort and atomic artifacts. If a worker fails,
   restart that cohort with the same command and audit directory.

## Commands

Run certification:

```powershell
$env:R_LIBS_USER = 'C:\Users\timkh\Documents\Thesis\.r_libs;C:\Users\timkh\AppData\Local\R\win-library\4.5'
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' `
  02_analysis\R\17y_run_lmv2_p5_fast_balancing.R `
  --p5-mode=certify
```

Run or resume production cohorts in a P5-specific output directory:

```powershell
$env:R_LIBS_USER = 'C:\Users\timkh\Documents\Thesis\.r_libs;C:\Users\timkh\AppData\Local\R\win-library\4.5'
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' `
  02_analysis\R\17y_run_lmv2_p5_fast_balancing.R `
  --p5-mode=production `
  --db='C:\Users\timkh\Documents\Thesis\.worktrees\lmv2-foundation\02_analysis\output\thesis_foundation.duckdb' `
  --audit-dir='02_analysis\output\audit\local_match_v2\P5' `
  --p3-manifest='02_analysis\output\audit\local_match_v2\P3\p3_interface_manifest.csv' `
  --cohorts=1995,2002,2009
```

The final P5 cohort list should replace the example list only after the full
balancing cohort definition is frozen.

## 2026-07-25 validated second-stage acceleration

The sparse join removed the first bottleneck but exposed two later ones:
collecting every Stage-2 admissible inventor pair into R, and WeightIt's
generic BFGS entropy solve. The selected-P5 path now also provides:

- an exact projection-preserving Stage-2 edge cover, atomically cached once
  per cohort/caliper/profile/universe and reused by both weighting schemes;
- five-million-pair technology blocks, reducing shard/manifest overhead;
- a direct Newton solve of the exact ATT entropy moment equations, with the
  original feasibility hierarchy and approximate `optweight` fallbacks left
  intact;
- a memory-aware scheduler with at most two cohort workers, a 12 GB
  second-worker start threshold, and a 4 GB critical requeue threshold.

The full 2009 P4 grid was completed with
`18l_run_lmv2_p4_fast_grid.R` in 2,089.8 seconds (34 minutes 50 seconds).
The replaced sparse-v1 run had needed about 49 minutes for u1 alone. All 24
profile rows, 11 edge covers, technology shards, checksums, and the assembled
diagnostics were saved under `P5FG_2009`; a no-op restart completed in 77
seconds without rewriting completed profile rows.

The 16 cells shared with the interrupted sparse-v1 run have identical support
counts, feasibility modes, and failure reasons. Numerical diagnostic
differences are solver-level only (maximum observed SMD difference 1.5e-5);
the Newton solution generally has tighter residual balance.

Certification after the real run passed all 249 checks:

- existing P4 suites: 218/218;
- sparse-cache suite: 10/10;
- selected edge-cover suite: 13/13;
- Newton solver suite: 8/8.

P4 remains a 24-cell selection pilot. P5 must freeze the selected
caliper/profile/universe and run only that specification under the two locked
weighting schemes. Use `18g_run_lmv2_p5_selected.R` for one or more selected
cohorts, or `18i_run_lmv2_p5_parallel.R` for the guarded two-worker schedule.
The final P5 materialization step must persist row-level final weights after
the P4 specification is chosen; the P4 pilot artifacts are diagnostics and
restart checkpoints, not the outcome-analysis weight table.
