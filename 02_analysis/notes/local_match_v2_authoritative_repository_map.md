# Local Match v2 authoritative repository map

Updated 2026-08-17. The GitHub default branch, `main`, is the single source of
truth for the current thesis analysis. Earlier worktree-specific branches are
historical development records and are not required for reproduction.

## Consolidated layers

| Layer | Principal sources | Principal generated artifacts |
|---|---|---|
| P0--P3 foundation and interfaces | `02_analysis/R/15a_lmv2_design_lock.R` through `16e_run_lmv2_p3.R` | `02_analysis/output/audit/local_match_v2/P0` through `P3`; derived Parquet interfaces |
| P4--P5 support and balancing | `02_analysis/R/17a_*` through `21e_certify_lmv2_p5c_provenance.R` | `P5_PRODUCTION_FINAL`, P5/P6 handoffs, and `P5C_ANNUAL_TRAJECTORY` |
| P6 outcomes and estimation | `02_analysis/R/18a_*` through `25a_*` | outcome panels, event-study estimates, inference, and closeout packages |
| Retained-inventor and heterogeneity packages | `02_analysis/R/26_*` through `33_*`, plus `42_*`, `43_*`, and `47_*` | selected-population estimates, status descriptions, network support, and heterogeneity packages |
| Final diagnostics and thesis release | `02_analysis/R/34_*` through `64_*` | robustness releases, final results registry, and thesis-facing tables |
| Thesis exhibits | `02_analysis/R/66_*` through `70_*` | generated figures and LaTeX table wrappers |

## Frozen lineage

1. `lmv2_treated_primary`, built by `15e_build_lmv2_p2.R`, is the treated
   inventor interface; `15f_certify_lmv2_p2.R` independently certifies it.
2. Scripts `17*` build local firm/technology support and the P5 weights.
3. Scripts `21a_*`--`21e_*` construct and certify annual-trajectory P5c
   weights and the P6 handoff.
4. Scripts `18a_*`--`20f_*` construct outcomes and estimate the main
   full-cohort results.
5. `60_run_final_thesis_results_1993.R` refreshes the final thesis release and,
   with `--rebuild-new`, reruns the newer robustness and mechanism packages.

The machine-readable authority for thesis claims is
`final_thesis_results_registry_1993.csv`; the human-readable companion is
`final_thesis_results_inventory_1993.md`.

## Package 8 and later diagnostics

Package 8 and subsequent scripts remain additive: they read frozen support,
weights, and panels and do not silently redefine the main estimand. Where a
prospective power or pretrend gate failed, the final inventory records the
result as exploratory, descriptive, or unavailable rather than promoting it to
a causal headline result.

## Repository hygiene

Superseded Main-DiD-v1 code and one-off inspection utilities are retained under
`02_analysis/R/archive/`; corresponding research notes are under
`02_analysis/notes/archive/`. Local worktrees, AI context/instruction files,
licensed data, generated outputs, manuscript drafts, and dated ZIP snapshots
are excluded from GitHub.
