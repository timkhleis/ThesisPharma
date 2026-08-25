# Final thesis result scripts

This folder contains the 18 R scripts referenced directly by
`02_analysis/notes/final_thesis_results_registry_1993.csv`. Together, they
produce or certify the estimates and diagnostics represented in the final
thesis claim registry.

These scripts are canonical files, not convenience copies. They are not a
self-contained raw-data-to-results pipeline: shared configurations, estimation
cores, data builders, and certified intermediate artifacts remain in the parent
`02_analysis/R/` workflow. Start with `02_analysis/REPLICATION.md` for the full
build order and licensed-input requirements.

The main thesis-facing refresh remains:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\60_run_final_thesis_results_1993.R
```

That orchestrator calls the scripts in this folder and refreshes the final
registry and thesis-facing tables after the expensive certified artifacts
exist.
