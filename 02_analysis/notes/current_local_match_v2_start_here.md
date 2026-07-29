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
4. `36_run_lmv2_simple_control_placebo.R`: run the 2,000-draw untreated-firm
   recruitment/pipeline falsification used in the robustness appendix.

## Current interpretation

The main result is the full pre-deal target-inventor cohort under clean local
support and five-year entropy-balanced outcome histories. The acquisition year
is excluded from the headline because annual patent data cannot order filings
relative to deal completion. The initially retained analysis is secondary and
post-treatment-selected.

The machine-readable authority for current numerical reporting is
`results_inventory/master_results_inventory.csv`. The C1 synchronization gate
is `results_inventory/C1_RESULTS_SYNC_CERTIFICATION.csv`. Active documents
must agree with the inventory at their displayed precision.

The authoritative working thesis manuscript is
`thesis_template/main.tex` in the main repository. Dated
`PSE_Thesis_Template_Bounded_*` directories and ZIP files are distribution
snapshots, not parallel manuscript authorities.

P8 is the authoritative patenting-exit decomposition. For initially retained
inventors, the three shares are 27.3% earlier end of observed patenting, 5.4%
fewer active years among patenting survivors, and 67.3% fewer patents per
active year. The two older two-factor decompositions are historical and must
not be used in current reporting.

The separately labelled control-endpoint diagnostic excludes full-cohort P5c
controls whose focal patent group exits before +5. It yields an annual
patent-count contrast of -0.0420 (deal-wild 95% interval
[-0.0803, -0.0033], p=0.035). Because this is less negative than the frozen
-0.0534 full-cohort estimate, the control endpoint requirement explains none
of the gap to the -0.1072 initially retained estimate. This diagnostic reuses
the frozen weights after removing controls; it does not re-solve entropy
balance. Its maximum absolute residual pre-period SMD is 0.0430, and it has no
genuine restricted-sample LOYO. Do not present its joint negative-period test
as a LOYO credential.

Both the frozen and endpoint-restricted patent-count paths attenuate
monotonically in absolute value from +1 through +5. The repeated shape is
consistent with temporary integration disruption but does not identify that
mechanism. Event time zero is the merger-completion year and is included as a
separately reported merger effect: -0.0377 in frozen P5c and -0.0288 in the
endpoint diagnostic. The frozen completion-through-+5 cumulative point effect
is -0.3047 patents per inventor (deal-wild 95% interval
[-0.5197, -0.0916], p=0.0086). The corresponding annual average across t=0
through +5 is -0.0508 [-0.0866, -0.0153]. The +1 to +5 average remains
separately reported because those are five fully exposed calendar years. Deal
timing is available only by year, so t=0 cannot be divided into pre- and
post-completion months or converted into a full-year exposure effect.

Read `03_Current_notes/local_match_v2_quantity_results_for_supervisors.md`
before interpreting the supervisor PDF in `04_Results/`.

The untreated-firm placebo distribution and thesis-ready robustness wording are
stored in `local_match_v2_simple_control_placebo_results.md`. The accepted
interpretation is that the results are inconsistent with a purely mechanical
lifecycle, recruitment, or simple observed mean-reversion explanation,
although residual violations of conditional parallel trends prevent an
unqualified causal interpretation.

## D1: retained-status descriptive completion

Run:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\42_run_lmv2_stayer_descriptives.R
```

The certified D1 package reports predetermined status distributions, annual
+1 through +5 patent-location paths, focal-affiliation persistence, symmetric
group-existence diagnostics, descriptive +6 continuation, and the
completion-year-inclusive timing results. Read
`local_match_v2_stayer_descriptive_results.md` for the substantive summary.
All location measures refer to patent affiliation, not employment.

## Archive

`99_Archive/` preserves completed Main-DiD-v1 and scratch exploration. It is
not part of the current analysis path.
