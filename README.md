# Pharmaceutical acquisitions and inventor patenting

This repository contains the analysis code and reproducibility documentation
for a master's thesis on how pharmaceutical acquisitions affect the inventive
output of target-firm inventors, with particular attention to inventors who
remain with the acquiring group.

## Current empirical design

The main specification is Local Match v2 for the pre-deal target-inventor
cohort. It restricts controls to acquisition-clean local firm and IPC support,
then entropy-balances five annual pre-treatment patent-count and active-patenting
histories. The main post-treatment window is event years `+1` through `+5`;
the acquisition year is reported separately because annual patent data cannot
order filings relative to deal completion.

The certified release covers acquisition cohorts 1993--2010. The headline
average annual patent-count estimate is -0.0521 patents per inventor (95%
deal-wild-bootstrap interval [-0.0898, -0.0147]). Results for initially retained
inventors are reported as selected-population evidence, not as an
always-retained causal effect. TechDrift and DealSim results retain the
identification and power qualifications recorded in the final results
inventory.

## Repository map

- `02_analysis/R/` contains the consolidated production, robustness, and
  thesis-exhibit scripts.
- `02_analysis/notes/` contains design freezes, certification notes, and the
  claim-to-code results inventory.
- `02_analysis/R/archive/` and `02_analysis/notes/archive/` contain superseded
  specifications retained for auditability.
- `00_Discussion_Docs/` contains the previously committed proposal and research
  memos. New working drafts are intentionally excluded.

Start with
[`02_analysis/notes/current_local_match_v2_start_here.md`](02_analysis/notes/current_local_match_v2_start_here.md)
and the
[`final thesis results inventory`](02_analysis/notes/final_thesis_results_inventory_1993.md).

## Reproduction

The code was run with R 4.5.1 on Windows. Raw PATSTAT, Cassi--Ornaghi,
BvD/Zephyr, and OECD inputs are not version-controlled because of size and
licensing restrictions. Place authorized inputs in `01_Data/` before rebuilding
the data foundation.

From the repository root:

```powershell
# Rebuild the canonical database and derived tables
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\run_pipeline.R

# Refresh the final thesis-facing release from completed estimator artifacts
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\60_run_final_thesis_results_1993.R

# Also rerun the newer estimators and diagnostics
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\60_run_final_thesis_results_1993.R --rebuild-new
```

Generated DuckDB, Parquet, figures, tables, and logs are written below
`02_analysis/output/` and are intentionally ignored by Git.

## Branch policy

`main` is the single authoritative branch for the current thesis code. The
complete P0--P6 pipeline, the 1993 cohort amendment, retained-inventor packages,
robustness analyses, and thesis-exhibit builders are all consolidated here.
Historical branches remain only as development history; no worktree checkout is
required to run the current code.

The active manuscript, local AI instructions/context, licensed data, and dated
distribution ZIPs are maintained outside this public analysis repository.
