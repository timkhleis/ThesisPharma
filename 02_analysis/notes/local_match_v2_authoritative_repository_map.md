# Local Match v2 — authoritative repository map

Recorded on 2026-07-27. The root worktree contains legacy exploratory material
and is not an authority for reproducible Local Match v2 results.

## Worktree ownership

| Layer | Authoritative worktree | Principal sources | Principal certified artifacts |
|---|---|---|---|
| P0-P3 foundation and interfaces | `.worktrees/lmv2-foundation` | `02_analysis/R/15a_lmv2_design_lock.R` through `16e_run_lmv2_p3.R` | `02_analysis/output/audit/local_match_v2/P0` through `P3`; derived Parquet interfaces |
| P4-P5 support, balancing, recovery, and P5c trajectory weights | `.worktrees/lmv2-p4-ebal` | `02_analysis/R/17a_*` through `21e_certify_lmv2_p5c_provenance.R` | `P5_PRODUCTION_FINAL`, `P5_final_certification`, `P5_CARDINALITY_FINAL`, `P5_P6_HANDOFF_V2`, `P5C_P6_HANDOFF_V2_*`, and `P5C_ANNUAL_TRAJECTORY` |
| P6 outcomes and estimation | `.worktrees/lmv2-p6-outcomes` | `02_analysis/R/18a_*` through `20f_summarize_lmv2_p6_p5c_results.R` | `P6_V3_PRODUCTION_FINAL_FREEZE`, `P6_P5C_ESTIMATION_*`, `P6_P5C_COMPARISON`, and `P6_WEIGHTED_PRIMARY` |
| Accepted post-results packages | `.worktrees/lmv2-p6-outcomes` | `02_analysis/notes/local_match_v2_postresults_package_freeze.md` plus new package scripts | package-specific audit directories beginning with `PACKAGE0_POSTRESULTS_FREEZE` |

The repeated `15a`-`15f` scripts in downstream worktrees are synchronized
copies used to construct their local databases. New foundation changes, if any,
must be made and certified in `lmv2-foundation` first and then propagated
explicitly.

## Status and retention interfaces

- `lmv2_treated_primary`, built by
  `lmv2-foundation/02_analysis/R/15e_build_lmv2_p2.R`, is the authoritative
  treated-inventor interface. It supplies first-post-patent timing and
  focal-entity evidence.
- Exact independent recomputation is implemented in
  `lmv2-foundation/02_analysis/R/15f_certify_lmv2_p2.R`.
- The existing five-state annual MECE construction is in
  `lmv2-p6-outcomes/02_analysis/R/06_build_event_panel.R`, with partition
  invariants in that same script.
- `cs2021_estimation_panel` and `stayer_attrition_panel` are the current
  materialized status panels. The post-results location package may reuse their
  logic but must not create an inconsistent second definition.
- The pure initially-retained, initially-outside, mixed/tied, and no-post-patent
  partition defined in the package freeze is a new Package 3 output. Until that
  output is certified, the existing P2 at-least-one-focal-evidence flag must not
  be relabelled as the pure initially-retained group.

## Frozen full-cohort weight and outcome lineage

1. P5a headline weights: `lmv2-p4-ebal` certified P5 production and P5/P6
   handoff artifacts.
2. P5c annual-trajectory weights: `lmv2-p4-ebal` scripts `21a`-`21e` and
   `P5C_P6_HANDOFF_V2_COUNT_ACTIVE`; LOYO `m3` and `m4` are existing diagnostic
   arms, not the complete future LOYO grid.
3. P6 outcome construction: `lmv2-p6-outcomes` scripts `18a`-`18g`, certified
   by `P6_V3_PRODUCTION_FINAL_FREEZE`.
4. P6 estimation: scripts `19a`-`20f` and the corresponding `P6_P5C_*`
   artifacts.

The P5c execution identifier is content-derived in
`21a_lmv2_p5c_annual_trajectory_config.R`. Its 11-file mutation suite is
recorded in
`P5C_ANNUAL_TRAJECTORY/p5c_provenance_tooth_tests.csv`. This corrects the stale
review claim that the function returns an ignored hard-coded constant.

## Repository hygiene

The Main-DiD-v1 exploration scripts and notes are retained under
`02_analysis/R/archive/main_did_v1/` and
`02_analysis/notes/archive/main_did_v1/`. They are audit history, not inputs
to the Local Match v2 production pipeline. One-off inspection utilities are
in `02_analysis/R/archive/scratch/`.

The active worktree-level ownership above remains deliberate: P0--P3,
P4--P5, and P6 have separate certified authorities. This repository does not
consolidate those layers into an unverified single copy.
