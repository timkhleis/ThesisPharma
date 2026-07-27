# Pharmaceutical acquisitions and inventor patenting

This repository snapshot contains the reproducible Local Match v2 research
pipeline and the completed full-cohort results package. The project is split
across clean worktrees so that each computational layer has one authoritative
implementation.

## Current empirical approach

The main result is a common-support ATT for the full pre-deal target-inventor
cohort. It compares treated inventors with acquisition-clean donor inventors
under local firm and IPC4 support, and uses entropy balancing to align the
five annual pre-treatment patent-count and active-patenting histories. The
headline post window is `t=+1` through `t=+5`; the acquisition year is not
used in the headline because annual patent data cannot order filings relative
to deal completion.

The result is reported together with a censoring-clean companion and
leave-one-pre-year-out diagnostics. Initially retained inventors use a
separate post-treatment-selected design and are reported as suggestive
selected-group evidence, not as an always-retained causal effect.

## Authoritative worktrees

| Layer | Worktree | Active scripts |
|---|---|---|
| P0--P3: design lock, data construction, status interfaces, matching inputs | `.worktrees/lmv2-foundation` | `02_analysis/R/15a_*` through `16e_*` |
| P4--P5: support, entropy balancing, annual-trajectory weights | `.worktrees/lmv2-p4-ebal` | `02_analysis/R/17*` and `21a_*` through `21e_*` |
| P6: outcome construction, estimation, diagnostics, communication | `.worktrees/lmv2-p6-outcomes` | `02_analysis/R/18a_*` through `27a_*` |

The detailed source-to-artifact map is
[`02_analysis/notes/local_match_v2_authoritative_repository_map.md`](02_analysis/notes/local_match_v2_authoritative_repository_map.md).

## Where to start

- [`02_analysis/README.md`](02_analysis/README.md) explains the active data
  lineage and script sequence.
- [`02_analysis/notes/local_match_v2_quantity_results_for_supervisors.md`](02_analysis/notes/local_match_v2_quantity_results_for_supervisors.md)
  records the current full-cohort result and its qualifications.
- [`02_analysis/output/results/local_match_v2/supervisor_package/`](02_analysis/output/results/local_match_v2/supervisor_package/)
  is a generated, ignored output directory containing the supervisor PDF.

## Archive policy

`02_analysis/R/archive/` and `02_analysis/notes/archive/` contain completed
Main-DiD-v1 and scratch explorations. They are retained for auditability but
are not inputs to the Local Match v2 production pipeline. See the archive
README before reusing any of them.

Raw data, DuckDB databases, Parquet files, and regenerated output are not
version-controlled. They are intentionally excluded from the review ZIP.
