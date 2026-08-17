# nt2010 — Package 02 Expanded Roster, Weights & Design Diagnostics

Date: 2026-07-20 (updated 2026-07-21: P0H5 solver-tightening resolution)
Scope: build the 1994–2010 never-target design (roster + P0H5/P5 weights +
diagnostics). **Design-only: no outcome panel, no patent_enriched, no treatment
effects.** Frozen 1994–2008 artifacts untouched.

## 0. Headline result — RESOLVED (all four specs FEASIBLE)

Initial build: the full-horizon **P0H5** was marginally INFEASIBLE on a single
gate — per-stack **stack-mass discrepancy 1.293e-4 vs the 1.0e-4 tolerance** —
driven entirely by the **2010** cohort's ebal mass residual (control mass
1533.198 vs 1533). Every other gate passed with wide margin.

Diagnosis (approved route "try tighter ebal solver"): WeightIt 1.7.0's ebal
default `reltol=1e-10` left a convergence residual on the larger 4.5M-unit
problem. Re-solving P0H5 with `reltol=1e-12`, `maxit=200000` (an **optimiser
setting, not a feasibility threshold**) converged it fully:

| P0H5_nt2010 | reltol 1e-10 (default) | reltol 1e-12 (nt2010) |
|---|---|---|
| stack-mass discrepancy | 1.293e-4 ❌ | **9.97e-6 ✅** |
| global max \|SMD\| | 6.06e-5 | 2.22e-6 |
| status | INFEASIBLE | **FEASIBLE** |

**No feasibility threshold was changed.** All four specs are now FEASIBLE and all
four weight parquets are saved. The tightened `reltol` is applied to the nt2010
P0H5 inventor path only (full + common-cohort); P5 uses the default solver (its
explicit within-stack normalisation already gives ~1e-16 mass balance).

## 1. Files created / changed

New scripts:
- `02_analysis/R/11n_build_nt2010_roster.R` — treated (fresh) + never-target
  control (fresh) roster, membership/cleanliness/integrity audits.
- `02_analysis/R/11o_build_nt2010_weights.R` — P0H5 + P5 weights (full 1994–2010
  and 1994–2008 common cohort) + design diagnostics; reuses 11j helpers via the
  functions-only guard.
- `02_analysis/R/11p_plot_nt2010_balance.R` — nt2010 balance love plot + per-era
  balance figure (from diagnostics; no ebal re-run).

Changed (all behavior-preserving; defaults reproduce frozen results byte-for-byte):
- `02_analysis/R/11j_build_robustness_weights.R` — (a) wrapped the execution body
  in `if (!isTRUE(getOption("main_did_v1.source_functions_only", FALSE))) { … }`
  (functions-only sourcing skips the frozen P0–P5 build, opens no DB connection —
  verified); (b) `run_inventor_weighted()` gained `maxit = 30000L, reltol = 1e-10`
  params, threaded to `two_stage_ebal`. Defaults = the previous hardcoded values.
- `02_analysis/R/11_main_design_utils.R` — `two_stage_ebal()` gained `reltol = 1e-10`
  (WeightIt's own ebal default), passed to both `weightit()` calls. Every existing
  caller (11c/11h/frozen 11j) is byte-identical.

Note edited: `nt2010_package_01_config.md` (five→six source files; ledger row for
required `stacks` argument).

New outputs (all versioned; no frozen artifact overwritten):
- Derived parquet: `main_did_v1_nt2010_analysis_units.parquet` (roster),
  `..._nt2010_p0h5_weights.parquet`, `..._nt2010_p5_weights.parquet`,
  `..._nt2010_p0h5_cc9408_weights.parquet`, `..._nt2010_p5_cc9408_weights.parquet`
  (all four spec weights saved; P0H5 after solver tightening).
- Results: `main_did_v1_nt2010_{feasibility_decisions, balance_all_covariates,
  weight_concentration, stack_mass, weighted_quantiles, design_comparison,
  era_balance, cohort_balance, treated_mass_by_cohort, p5_*_stack_scale_factors}.csv`.
- Audit: `nt2010_{treated_frozen_equivalence, treated_frozen_covariate_diffs,
  treated_new_cohort_waterfall, treated_by_cohort, control_cleanliness,
  control_by_cohort, membership_waterfall, roster_integrity_contract}.csv`.
- Figures: `main_did_v1_nt2010_balance_loveplot.png`, `..._nt2010_era_balance.png`.

## 2. Commands run

```
Rscript 02_analysis/R/11n_build_nt2010_roster.R     # roster + audits (exit 0)
Rscript 02_analysis/R/11o_build_nt2010_weights.R    # P0H5/P5 weights + diag (exit 0)
Rscript 02_analysis/R/11p_plot_nt2010_balance.R     # balance figures (exit 0)
```

## 3. Membership waterfall

| Stage | N |
|---|---|
| Treated qualified (all years) | 33,100 |
| Treated after first-exposure | 32,438 |
| Treated retained [1994,2010] | 27,746 |
| Treated covariate-missing | 0 |
| Never-target assigned | 4,525,635 |
| Never-target retained (clean) | 4,473,727 |
| Control covariate-missing | 0 |
| Combined roster rows | 4,501,473 |
| Roster covariate-complete rows | 4,501,473 |

Construction followed the approved order: `qualify_sql(0L)` (all years) →
`keep_first_exposure()` on the full population → filter 1994–2010. Control arm:
`build_never_target_arm(con, STACK_LO:STACK_HI_NEVER_TARGET)` (g+5 cleanliness
built-in; legacy `build_h5_control_roster` **not** used). Covariates via the
shared `compute_firm_covariates`/`compute_inventor_covariates`.

## 4. Frozen-overlap equivalence (1994–2008)

- Treated keys `(codinv, focal_deal_id, stack)`: **exactly equal** frozen —
  0 only-fresh, 0 only-frozen (25,524 keys).
- Covariate reproduction: worst absolute diff over all 14 numeric covariates =
  **4.44e-16** (≪ COV_TOL 1e-6); NA-pattern mismatches = 0; `modal_family` match
  = 1.000; `qualifying_gap` match = 1.000.

Legacy `cs2021_estimation_panel` row-for-row equivalence was intentionally **not**
imposed on 2009–2010 (that table is clipped at 2008); equivalence is asserted on
the frozen overlap only, and the new cohorts are reported separately.

## 5. New-cohort (2009, 2010) counts

| Cohort | Qualified obs | Removed by first-exposure | Retained units | Distinct inventors | Distinct deals | Covariate-missing |
|---|---|---|---|---|---|---|
| 2009 | 703 | 14 | 689 | 689 | 17 | 0 |
| 2010 | 1,539 | 6 | 1,533 | 1,533 | 29 | 0 |

One treatment exposure per retained inventor: verified (no duplicate `codinv`).
`stack == deal_year`: verified.

## 6. Control-cleanliness & roster integrity

- **Cleanliness** (direct audit vs `target_cohort_own`): retained controls with a
  prior (`deal_year < stack`) exposure = **0**; with a competing (`g..g+5`)
  exposure = **0**.
- **Integrity contract** (all pass): has treated rows; has control rows; unique
  `(codinv, stack)`; no cross-arm overlap on `(codinv, stack)`; cohorts exactly
  1994–2010; treated rows have a focal deal id; control rows have none; all
  covariate columns present; no outcome columns.

## 7. P0H5 / P5 balance and support gates

Per-spec design diagnostics — **final (post solver-tightening)**, existing
thresholds unmodified; P0H5 rows use `reltol=1e-12`, P5 uses the default solver:

| Spec | Cohorts (n) | Treated units | Treated inv | Treated deals | Control units | ebal firm/inv conv | Max \|SMD\| (global) | Control ESS | Max firm share | Top-5 share | Stack-mass disc. | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **P0H5_nt2010** | 1994–2010 (17) | 27,746 | 27,746 | 336 | 4,473,727 | ✓ / ✓ | 2.22e-6 | 118.8 | 0.0376 | 0.155 | 9.97e-6 | **FEASIBLE** |
| **P5_nt2010** | 1994–2010 (17) | 27,746 | 27,746 | 336 | 4,473,727 | ✓ / ✓ | 6.88e-6 | 3821.3 | 0.00172 | 0.00826 | 1.72e-16 | FEASIBLE |
| **P0H5_cc9408** | 1994–2008 (15) | 25,524 | 25,524 | 290 | 3,717,896 | ✓ / ✓ | 3.94e-6 | 101.7 | 0.0418 | 0.169 | 7.30e-6 | FEASIBLE |
| **P5_cc9408** | 1994–2008 (15) | 25,524 | 25,524 | 290 | 3,717,896 | ✓ / ✓ | 3.56e-5 | 3629.2 | 0.00179 | 0.00850 | 2.87e-16 | FEASIBLE |

Required cohort ranges: **P0H5/P5 = 1994–2010; common-cohort P0H5/P5 = 1994–2008;
P3/P4 remain frozen at 1994–2008** (untouched). Common-cohort treated deals (290)
and treated units (25,524) exactly match the frozen 1994–2008 counts.

**P5 deal-mass normalization**: treated deal totals equalised to `N_T/D`;
post-normalization max stack-mass discrepancy 1.7e-16 (full) / 2.9e-16 (cc).

**Initial stack-mass discrepancy driver (before tightening)**: cohort 2010 =
1.293e-4; after tightening `reltol`, the worst cohort (2002) = 9.97e-6, all ≤ 1e-5.

**2009–2010 diagnostic era** (per-stack weighted balance, `BALANCE_ERAS_NEVER_TARGET`):

| Era | P0H5_nt2010 max \|SMD\| | P5_nt2010 max \|SMD\| |
|---|---|---|
| 1994–1999 | 0.465 | 0.608 |
| 2000–2004 | 0.349 | 0.114 |
| 2005–2008 | 0.521 | 0.092 |
| **2009–2010** | **1.190** | **0.106** |

Per-era weighted SMDs are large across **all** eras (the design balances
*globally*: global max |SMD| = 6.1e-5), so per-era SMD is a within-window
diagnostic, not a global-balance failure. The 2009–2010 bin is the worst for
P0H5 (thin cohorts: 2,222 treated, homogeneous → SMD-standardisation instability),
but P5's within-window balance for 2009–2010 (0.106) is in line with the other
eras. This is the expected "dedicated diagnostic" signal for the expanded cohorts.

## 8. Resolution (approved route: tighter ebal solver)

Selected **Option 3** ("try tighter ebal solver"). Verified in a standalone
experiment (`scratchpad/p0h5_tighten_experiment.R`) then wired into the pipeline:
re-solving P0H5 with `reltol=1e-12`, `maxit=200000` clears the stack-mass gate
(1.293e-4 → 9.97e-6) and improves global balance (6.06e-5 → 2.22e-6). This is an
**optimiser setting, not a feasibility threshold** — `STACK_MASS_TOL` and every
gate are unchanged. Wired via `NT2010_EBAL_{MAXIT,RELTOL}` in `11o`, threaded
through the new (behavior-preserving) `reltol`/`maxit` params on
`run_inventor_weighted` and `two_stage_ebal`. All four specs are now FEASIBLE and
their weights are saved. Note for Package 5: cc9408 uses the same tightened solver
as the full horizon, so P0H5_cc9408-vs-P0H5_nt2010 isolates the cohort-range
effect cleanly; both are essentially fully converged (frozen P0H5 used the 1e-10
default, but its cc-range problem is feasible at either tolerance).

## 9. Frozen-outputs-unchanged verification

- All 7 frozen derived parquets: md5 **identical** to the Package-0 baseline
  (never_target_units, h5_weights, h5_deal_weighted, g7_reduced4x4_diag,
  g7_deal_weighted, panel_never_target_h5, panel_g7) — re-confirmed after the
  solver-tightening re-run.
- 4 spot-checked frozen result CSVs (`main_robustness_*`): md5 **identical** to
  Package-0 baseline.
- 6 frozen figures intact; 2 new nt2010 figures added (not replacements).
- `11j`/`11_main_design_utils.R` edits are guard + behavior-preserving optional
  params (defaults = prior hardcoded values / WeightIt default); frozen execution
  path byte-identical.

## 10. `git status -sb`

See package report. New untracked: `11n/11o/11p` scripts, this note; modified:
`11j` (guard). Protected files (untracked `12*`, `verginer_ebal_checkpoint.md`,
`AGENTS.md`) untouched.
