# Start here: current Local Match v2 replication package

This is the complete current analysis path. Read and run it in order; do not
use the archived Main-DiD-v1 scripts for headline results.

## Input data

`01_Data/` is the exact raw input bundle used by the analysis: Cassi--Ornaghi
inventor, patent, firm-group, merger, and replication files, together with the
OECD patent-quality files. The replication package contains this folder.

## Materialized research database

`05_Database/thesis_foundation.duckdb` is the authoritative P6 DuckDB snapshot
used to inspect the constructed research tables without rebuilding the raw
data foundation. It is a derived, read-only convenience snapshot; the raw
inputs and P0--P3 code remain the provenance source. Do not substitute the
older databases from the root or other worktrees.

## P0--P3: construct the research data and matching inputs

Source folder: `02_Code/P0_P3_foundation/`.

1. `01_build_data_foundation.R`: read and standardize the raw inputs.
2. `02_build_derived_tables.R`: build canonical DuckDB and Parquet analysis
   interfaces.
3. `15a_lmv2_design_lock.R` through `16e_run_lmv2_p3.R`: lock the design,
   define treated/control status, construct matching covariates, and certify
   the foundation interfaces.

## P4--P5: local support and entropy-balanced weights

Source folder: `02_Code/P4_P5_weights/`.

1. `17a_*` through `17z_*`: construct clean local firm and IPC4 donor support,
   execute the accelerated balancing pipeline, and certify its artifacts.
2. `21a_lmv2_p5c_annual_trajectory_config.R` through `21e_*`: create the
   annual-trajectory P5c weights and the frozen P6 handoff.

## P6: outcomes, estimates, and results communication

Source folder: `02_Code/P6_outcomes/`.

1. `18a_*` through `18g_*`: construct and certify the outcome panel.
2. `19a_*` through `20f_*`: estimate the full-cohort P5c effect, inference,
   censoring companion, and held-out-year diagnostics.
3. `21a_*` through `27a_*`: build the raw-DiD/lifecycle diagnostics, result
   packages, and supervisor memo.

## Current interpretation

The main result is the full pre-deal target-inventor cohort under clean local
support and five-year entropy-balanced outcome histories. The acquisition year
is excluded from the headline because annual patent data cannot order filings
relative to deal completion. The initially retained analysis is secondary and
post-treatment-selected.

Read `03_Current_notes/local_match_v2_quantity_results_for_supervisors.md`
before interpreting the supervisor PDF in `04_Results/`.

## Archive

`99_Archive/` preserves completed Main-DiD-v1 and scratch exploration. It is
not part of the current analysis path.
