# nt2010 — Package 02B.0 P0H5 Cohort-Specific Ebal Prototype (cohort 2009)

Date: 2026-07-21
Scope: prototype the cohort-specific two-stage entropy-balancing correction for
**P0H5, cohort 2009 only**. Isolated implementation; shared `two_stage_ebal()`
untouched. Design-only — no outcomes, no citation work, no DiD. **Result: PASS.**

## 0. Verdict

The cohort-specific solve **fully corrects the substantive 2009 conditional
imbalance** while satisfying every unchanged balance, mass, concentration, and
support gate. Constrained max full-pooled |SMD|: **0.967 → 2.0e-7**. All 8 gates
pass. Estimand preserved (treated weights ≡ 1; cohort control mass = treated
mass = 689, not normalised). **Recommend Package 2B.1** (sequential 1994–2010)
— for review, not executed here.

## 1. Commands run

```
Rscript 02_analysis/R/11r_prototype_nt2010_cohort_ebal.R
```
(Isolated script; loads only `stack==2009` from `NT2010_ANALYSIS_UNITS_PARQUET`,
runs the within-cohort two-stage ebal, writes 2B.0 diagnostics + a labelled
diagnostic weight parquet. `maxit=200000`, `reltol=1e-12`. A first run exposed a
display bug — the side-by-side balanced on the ebal's standardized covariates;
fixed to balance on raw covariates. Gates were unaffected.)

## 2. Method

Same two-stage hierarchy as the global P0H5, solved **within** cohort 2009 with
`factor(stack)` omitted (stack constant):
1. Firm stage: `weightit(treated ~ FIRM_COVARS, method="ebal", estimand="ATT",
   s.weights = n_qualifying_inventors, maxit=200000, reltol=1e-12)` → firm multiplier.
2. Inventor stage: `weightit(treated ~ FIRM_COVARS + INV_COVARS + qualifying_gap_cat
   + modal_family, ebal ATT, base.weights = firm_multiplier, …)` → final weights.

Sample membership, cleanliness, covariate definitions, and thresholds are
identical to the global design. `n_qualifying_inventors` recomputed per
`(underlying_group_id, stack)` cell — identical to the global `prepare_units`
within a fixed stack. Roster keys/counts identical to the global P0H5 2009 slice
(689 treated + 377,404 control; `keys_identical = TRUE`).

## 3. Structural-column & support audit

- **No columns removed.** All 14 numeric covariates had non-zero variance across
  both arms in 2009; both factors (`qualifying_gap_cat`, `modal_family`) retained
  ≥2 realised levels. (`..._2b0_structural_removed_columns.csv` is empty.)
- **Support satisfied.** Every realised treated factor level has control support;
  every constrained numeric covariate's treated mean lies inside the control value
  range (ATT convex-hull necessity). No covariate/level classified unsupported.

## 4. Old-vs-new balance (cohort 2009, constrained covariates)

Full-pooled |SMD| (raw diff ÷ full-specification pooled SD; the collapse-robust
diagnostic). "Treated-SD SMD" is the frozen `smd_weighted` value (NA when treated
variance = 0, i.e. denominator collapse).

| Covariate | Old raw diff | Old full-pooled SMD | Old treated-SD SMD | New full-pooled SMD |
|---|---:|---:|---:|---:|
| log_firm_inventor_count | −1.778 | **−0.967** | −1.923 | −2e-7 |
| log_patents_early | −1.861 | −0.932 | −1.894 | 2e-7 |
| log_firm_patent_stock | −1.914 | −0.914 | −1.631 | 2e-7 |
| log_patents_recent | −1.709 | −0.904 | −1.755 | ~0 |
| share_biotech | 0.083 | 0.457 | 0.320 | ~0 |
| observed_firm_patent_age | −0.966 | −0.214 | −0.183 | ~0 |
| share_small_molecule | 0.034 | 0.194 | 0.177 | ~0 |
| observed_inventor_career_age | 0.441 | 0.124 | 0.102 | 9e-8 |
| no_technology_activity_g6_g3 | −0.002 | −0.037 | NA (collapse) | ~0 |
| no_firm_patent_by_g3 | −0.001 | −0.021 | NA (collapse) | ~0 |
| … (all 14) | | | | ≤ 2.03e-7 |

The old firm-size / patent-intensity imbalance (full-pooled 0.9–1.0) is
eliminated. Two binary covariates are treated-SD denominator collapses (treated
constant in 2009); their full-pooled SMDs are small and the **full-pooled gate**
(not the treated-SD SMD) governs feasibility — collapses flagged, not dismissed.

## 5. Gates (all thresholds unchanged)

| Gate | Value | Threshold | Pass |
|---|---:|---:|:--:|
| treated weights ≡ 1 | 0 | <1e-8 | ✓ |
| finite, nonnegative weights | all | — | ✓ |
| firm-stage raw MM max mean diff | 9.25e-8 | ≤1e-4 | ✓ |
| inventor-stage raw MM max mean diff | 2.08e-7 | ≤1e-4 | ✓ |
| treated↔control mass discrepancy | 5.10e-8 | ≤1e-4 | ✓ |
| max full-pooled \|SMD\| (constrained) | 2.03e-7 | ≤0.05 | ✓ |
| underlying-control-firm ESS | 636.3 | ≥50 | ✓ |
| max control-firm weight share | 0.0131 | ≤0.10 | ✓ |

## 6. Support / concentration / estimand

| Metric | Value |
|---|---:|
| treated inventors | 689 |
| treated mass | 689 |
| control mass | 689.00004 |
| positive-weight control inventors | 377,404 |
| positive-weight control firms | 7,087 |
| control inventor-level ESS | 25,230 |
| control firm-level ESS | 636.3 |
| max firm share / top-5 share | 0.0131 / 0.0437 |

Control-weight quantiles in `..._2b0_weight_quantiles.csv`. **Estimand preserved**:
treated weights all exactly 1 and control mass equals the treated-inventor mass
(689) — the cohort is *not* normalised to unit or equal-cohort mass, so under the
eventual full design it contributes according to its 689 treated inventors
(inventor-weighted ATT, not an equally-weighted-cohort estimand).

Cohort-specific firm ESS (636) is far above the global design's cross-cohort
fragility figure (≈119), because within-cohort balancing does not force the same
few recurring firms to carry the whole cross-cohort comparison.

## 7. Runtime & memory (per stage)

| Stage | Elapsed | Peak R mem |
|---|---:|---:|
| roster load (2009 only, projected) | 1.9 s | 186 MB |
| firm + inventor balance | 40.1 s | 1,482 MB |
| diagnostics | 5.2 s | 917 MB |

Aggregation-first held: only the 2009 cohort was queried (required columns
projected in DuckDB); no 4.5M-row roster collected; no global
`covariate × factor(stack)` matrix built; solvers run sequentially. The 1.5 GB
peak is the inventor-stage ebal on ~378k control units — bounded per cohort and
released between stages, so a sequential 17-cohort 2B.1 is memory-feasible.

Solver: `weightit` reports `converged=FALSE` for both stages, but this is its
`maxit`-cap flag, not a balance failure — the **raw** model-matrix max mean
differences (9.25e-8 firm, 2.08e-7 inventor) are far below `EBAL_CONSTRAINT_TOL`,
which is the collapse-robust convergence test used here. (`..._2b0_solver_convergence.csv`.)

## 8. Protected-output integrity

- Production nt2010 P0H5 weights (`..._nt2010_p0h5_weights.parquet`): **not
  written** (mtime unchanged from the 11o run); prototype weights written only to
  the labelled diagnostic path `..._p0h5_cohort2009_PROTOTYPE_weights.parquet`.
- Frozen artifacts spot-checked (`never_target_h5_weights.parquet`,
  `main_robustness_post_summaries.csv`): md5 **identical** to Package-0 baseline.
- Package 2A CSVs: read-only (unchanged). No P5 artifact touched. Shared
  `two_stage_ebal()` unmodified.
- Protected/unrelated files (`12*`, both Verginer checkpoints,
  `00_Discussion_Docs/011_thesis_paper_structure.md`, `AGENTS.md`) untouched.

## 9. Deliverables (versioned)

- Script: `02_analysis/R/11r_prototype_nt2010_cohort_ebal.R`.
- Diagnostic weights: `main_did_v1_nt2010_p0h5_cohort2009_PROTOTYPE_weights.parquet`.
- Audit CSVs: `..._2b0_{structural_removed_columns, balance_old_vs_new, gates,
  support, weight_quantiles, solver_convergence, runtime_resource_log, status}.csv`.
- This checkpoint.

## 10. Recommendation

**Package 2B.1 is recommended** (do not execute without approval): solve P0H5
cohort-specific ebal sequentially for **1994–2010**, one cohort at a time,
releasing memory between cohorts, and **assemble the per-cohort weights without
equalising cohort mass** (each cohort keeps its treated-inventor mass, preserving
the inventor-weighted ATT). Carry the same gates per cohort; where a cohort has a
genuine denominator collapse on a covariate, use the raw balance residual for
convergence and the full-pooled SMD for the substantive check (as here). Flag any
cohort that fails support and stop rather than relax a threshold.

Do not proceed to Package 3A, and do not substitute P5 (untouched here), until
2B.1 is built and reviewed.
