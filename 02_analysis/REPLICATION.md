# Replication guide

This guide separates source-code verification, raw-data reconstruction, and
the computationally expensive estimator release. Run all commands from the
repository root. The certified environment is Windows with R 4.5.1; direct R
package versions are recorded in `02_analysis/package_versions.csv`.

## 1. Licensed inputs

Raw PATSTAT-derived, Cassi--Ornaghi, BvD/Zephyr, and OECD data are excluded
from Git because of licensing and file size. An authorized replication copy
must contain these files at the exact paths below:

```text
01_Data/
  inventor.dta
  patent.dta
  patent_inventor.dta
  ipc.dta
  group.dta
  firm.dta
  firm_group.dta
  L_group_history_target.dta
  L_merge.dta
  BvD_financial_all.dta
  CassiOrnaghiPaperData/
    BvD_group_id.csv
    group_production.csv
    inventor_production.csv
    inventor_status.csv
    merger_list.csv
    T_inventors_tech_similarity.csv
    t_stayer_coinventors.csv
  OECD_QualitaData/
    OECD_Quality_data.txt
```

The preflight checks names and locations without reading confidential content:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\00_replication_preflight.R
```

Use `--code-only` when reviewing GitHub without licensed inputs.

## 2. Data foundation

The foundation runner imports the raw sources used by the canonical layer and
rebuilds DuckDB plus Parquet derivatives:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\run_pipeline.R
```

Then build the Cassi deal/status interfaces and event panel in order:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\04a_build_inventor_affiliation.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\04b_import_cassi_deal_files.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\04c_build_prelim_own_status.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\05_build_deal_map.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\06_build_event_panel.R
```

Generated databases, Parquet files, result tables, figures, and logs are
written under `02_analysis/output/` and are intentionally ignored by Git.

## 3. Core Local Match v2 analysis

The production sequence is staged because P3--P5 matching and entropy
balancing are expensive and checkpointed. The authoritative order and frozen
inputs are documented in:

- `notes/current_local_match_v2_start_here.md`;
- `notes/local_match_v2_authoritative_repository_map.md`;
- `notes/final_thesis_results_inventory_1993.md`.

Scripts `15a_*`--`21e_*` create and certify the treatment/control interfaces,
support, and P5c weights. Scripts `18a_*`--`25a_*` materialize outcomes and
estimate the full cohort. Scripts `26_*`--`33_*` estimate the initially
retained and heterogeneity packages. Each production stage writes its own
manifest and certification file; failed gates are intentionally retained as
failed diagnostics rather than overwritten.

This repository does not claim that `60_run_final_thesis_results_1993.R` is a
raw-data-to-results runner. It refreshes the thesis release after the expensive
core artifacts exist. With those artifacts in place:

```powershell
# Refresh the final registry and thesis tables.
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\60_run_final_thesis_results_1993.R

# Re-estimate the late CS(2021), timing, mechanism, network, and
# relative-standing packages before refreshing the release.
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\60_run_final_thesis_results_1993.R --rebuild-new
```

## 4. Final robustness extensions

After the certified 1993 P5c/P6 artifacts exist, the standard-path extension
runner reproduces the financial-condition, supported-size, deal-value,
retained-inventor, and quantile packages, then rebuilds the robustness release:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\75_run_lmv2_release_extensions.R
```

The frozen builders refuse to write into non-empty version directories. This
protects existing certified outputs and makes accidental mixed-version runs
fail loudly.

Thesis exhibits are regenerated only after their certified inputs exist:

```powershell
# Rebuild the descriptive table used by the appendix package.
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\14_build_data_section_descriptives.R

& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\66_build_results_blueprint_figures.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\67_build_retained_secondary_event_studies.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\68_build_robustness_exhibits.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\69_build_appendix_exhibits.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\70_build_techdrift_pre_post_diagnostic.R
```

## 5. Release authority and qualifications

The machine-readable claim-to-code map is
`notes/final_thesis_results_registry_1993.csv`; its human-readable companion is
`notes/final_thesis_results_inventory_1993.md`. Important negative or qualified
results remain part of the release: TechDrift fails its joint pretrend gate,
DealSim fails its prospective power gate, the network design fails validation,
and ordinary Lee bounds are not identified under defensible assumptions.

The GitHub repository is therefore a code-and-documentation release. A fully
executable replication handoff also requires the separately authorized raw
inputs (or a certified generated-artifact bundle) because neither can be
distributed publicly.
