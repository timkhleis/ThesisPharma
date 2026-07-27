# Analysis guide

## Data and result lineage

```text
Raw Cassi--Ornaghi / PATSTAT / Zephyr inputs
  -> P0--P2: canonical data, treatment/status interfaces
  -> P3--P5: local donor support and entropy-balanced weights
  -> P6: event-time outcome panel and weighted estimation
  -> certified result packages and supervisor memo
```

P0--P3 are authoritative in `lmv2-foundation`; P4--P5 are authoritative in
`lmv2-p4-ebal`; P6 is authoritative in this worktree. Do not run the legacy
root `run_pipeline.R` as a substitute for the Local Match v2 sequence.

## Active P6 sequence in this worktree

| Stage | Scripts | Purpose |
|---|---|---|
| Outcome configuration and materialization | `18a_*`--`18g_*` | Build and certify the outcome panel from frozen P5 inputs. |
| Estimation | `19a_*`--`20f_*` | Estimate the P5c full-cohort ATT, inference, and diagnostics. |
| Results diagnostics | `21a_*`--`24a_*` | Raw DiD, recruitment/lifecycle, mean-reversion, and early-recruitment checks. |
| Closeout and communication | `25a_*`--`27a_*` | Quantity package, citation robustness, final tables/figures, and supervisor memo. |

Use the stage-specific freeze notes in `notes/` before re-running an existing
analysis. The current full-cohort interpretation is in
`notes/local_match_v2_quantity_results_for_supervisors.md`.

## Current estimands

- **Full cohort (main):** treated inventors supported by local donor firms and
  entropy-balanced on five annual pre-treatment outcomes and characteristics.
- **Initially retained inventors (secondary):** a separately balanced,
  post-treatment-selected group. It is not interchangeable with the full
  cohort and must retain its selection qualification.

## Archived material

See `R/archive/README.md` and `notes/archive/README.md`. Archive contents are
retained research history, not production inputs.
