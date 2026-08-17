# Start here: current Local Match v2 replication

The complete current code path is on the `main` branch. Run every command from
the repository root; no auxiliary worktree is required.

## Inputs

Authorized raw Cassi--Ornaghi, PATSTAT, BvD/Zephyr, and OECD files belong in
`01_Data/`. They are not published in Git because of licensing and size. The
pipeline materializes its DuckDB and Parquet layers under `02_analysis/output/`.

## Build order

1. Run `02_analysis/R/run_pipeline.R` to build the canonical data foundation
   and derived tables.
2. Scripts `15a_*`--`21e_*` define the Local Match v2 design, support, and
   entropy-balanced weights.
3. Scripts `18a_*`--`25a_*` construct outcomes and estimate the main
   full-cohort results.
4. Scripts `26_*`--`33_*` estimate selected-population retained-inventor and
   heterogeneity packages.
5. Scripts `34_*`--`64_*` build diagnostics, robustness checks, mechanism
   analyses, network gates, and the final release.
6. Scripts `66_*`--`70_*` create thesis-facing exhibits from certified output.

## Final release

Refresh the claim-to-code registry and thesis tables after the expensive
artifacts exist:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\60_run_final_thesis_results_1993.R
```

Add `--rebuild-new` to rerun the newer CS(2021), short-window, timing-placebo,
mechanism, DealSim, and network packages first.

The numerical reporting authority is
`notes/final_thesis_results_registry_1993.csv`; read
`notes/final_thesis_results_inventory_1993.md` for the corresponding
interpretation and qualification of each result.

## Main interpretation

The primary estimand covers the full pre-deal target-inventor cohort on common
local support. The acquisition year is separate from the `+1` through `+5`
headline because calendar-year patent records cannot order applications around
the completion date. Initially retained inventors form a post-treatment-selected
population and must retain that qualification.

TechDrift fails its Local Match joint pretrend diagnostic. DealSim failed its
prospective power gate. The persistent-team-tie design failed its held-out
validation/precision gate. Those outputs remain useful diagnostics, but the
final inventory deliberately does not present them as clean causal headline
effects.

## Archive

`02_analysis/R/archive/` and `02_analysis/notes/archive/` preserve superseded
Main-DiD-v1 and scratch work for auditability. They are not part of the current
production path.
