# Analysis guide

All current analysis code is consolidated in this repository's `main` branch.
Run commands from the repository root; active scripts must not depend on a
separate Git worktree.

## Pipeline

| Stage | Principal scripts | Purpose |
|---|---|---|
| Data foundation | `01_*`--`06_*` | Import, clean, link, and materialize canonical inventor, patent, firm, deal, and status tables. |
| Early comparison designs | `11n_*`--`15_*` | Not-yet-treated, Verginer-style, Local Match pilot, and data-alignment diagnostics. |
| Local Match v2 foundation and weights | `15a_*`--`21e_*` | Lock the design, construct treatment/control interfaces, build local support, and solve/certify entropy-balanced weights. |
| Main outcomes and estimation | `18a_*`--`25a_*` | Build event panels, estimate full-cohort outcomes, run inference, and construct closeout packages. |
| Initially retained and heterogeneity | `26_*`--`33_*` | Selected-population retained-inventor estimates, selection diagnostics, DealSim, and inventor/VR heterogeneity. |
| Diagnostics and final release | `34_*`--`65m_*` | Inventories, placebos, decompositions, HonestDiD, robustness, CS(2021), mechanisms, network gates, and relative standing. |
| Release extensions | `66_run_*`--`75_run_*` | Selection/support diagnostics, retained robustness, deal-value quantiles, and the standard-path extension runner. |
| Thesis exhibits | `66_build_*`--`70_build_*` | Build results, robustness, appendix, and TechDrift exhibits from certified artifacts. |

The main thesis-facing refresh command is:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\60_run_final_thesis_results_1993.R
```

Add `--rebuild-new` to rerun the estimators listed by that orchestrator before
rebuilding the release index and tables.

Run `00_replication_preflight.R` before any production stage. See
[`REPLICATION.md`](REPLICATION.md) for the licensed-input layout, exact scope
of each runner, package versions, and the final robustness-extension command.

## Authoritative outputs

- `R/final_thesis/` contains the 18 scripts linked directly from the final
  thesis claim registry; shared pipeline dependencies remain in `R/`.
- `notes/final_thesis_results_inventory_1993.md` is the human-readable
  claim-to-code map.
- `notes/final_thesis_results_registry_1993.csv` is its machine-readable
  companion.
- Generated results live under
  `output/audit/local_match_v2_1993_amendment/FINAL_THESIS_RELEASE_1993/`.
- Generated outputs and licensed inputs are intentionally excluded from Git.

## Interpretation boundaries

- Initially retained inventors are a post-treatment-selected population.
- TechDrift fails its Local Match joint pretrend diagnostic and is not a clean
  causal result.
- DealSim is exploratory because the prospective power gate failed.
- The persistent-team-tie design failed its validation/precision gate; the
  retained network results are descriptive.
- Ordinary Lee bounds are not reported because the required identifying
  conditions are not defensible in this setting.

Archived Main-DiD-v1 and scratch scripts are retained under `R/archive/` for
auditability and are not inputs to the current release.
