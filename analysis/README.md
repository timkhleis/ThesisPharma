# Thesis Data Foundation

This folder contains the R-based data engineering pipeline for the thesis data foundation.

## What It Builds

- Canonical base tables from the raw Stata and helper files
- Parquet outputs for canonical, helper, enrichment, derived, and audit layers
- A DuckDB database for reproducible joins and validation
- An inventor disambiguation audit based on the published `codinv` assignment

## How To Run

Run the scripts from the thesis root in this order:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' analysis\R\01_build_data_foundation.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' analysis\R\02_build_derived_tables.R
```

Run the merged database pipeline:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' analysis\R\run_pipeline.R
```

Run the audit later when you want to review disambiguation and data quality flags:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' analysis\R\03_run_audit.R
```

## Output Layout

- `analysis/output/thesis_foundation.duckdb`: DuckDB database
- `analysis/output/parquet/canonical`: canonical source-of-truth tables
- `analysis/output/parquet/helper`: helper and benchmark tables
- `analysis/output/parquet/enrichment`: enrichment tables
- `analysis/output/parquet/derived`: derived research tables
- `analysis/output/parquet/audit`: flagged audit records
- `analysis/output/metadata`: table inventory and key checks
- `analysis/output/audit`: audit summaries and validation metrics

## Notes

- The published inventor disambiguation is kept as the thesis baseline.
- `inventor_status.csv`, `T_inventors_tech_similarity.csv`, and `t_stayer_coinventors.csv`
  are intentionally not part of the canonical foundation.
- Similarity measures are meant to be computed later from the raw IPC-based derived tables.
- The default runner builds the merged database only; the audit is optional and can be run later.
