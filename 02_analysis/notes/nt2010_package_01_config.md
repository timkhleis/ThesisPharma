# nt2010 — Package 01 Configuration & Versioned Paths

Date: 2026-07-20
Scope: configuration and versioned-path work only. **No rosters, weights, panels,
or estimates were built.** No pipeline script was executed (only sourced/parsed).

## 0. Amendments (post-review, 2026-07-20)

Applied after the conditional Package-1 acceptance:

1. `build_never_target_arm(con, stacks)` — **default removed** (was
   `stacks = STACK_LO:STACK_HI_G7`). A never-target call can no longer silently
   inherit the g+7 ceiling. Legacy caller `11f_never_target_arm.R` now passes
   `stacks = STACK_LO:STACK_HI_G7` explicitly; the nt2010 builder (Package 2)
   must pass `stacks = STACK_LO:STACK_HI_NEVER_TARGET`.
2. Combined roster path renamed `NT2010_UNITS_PARQUET` →
   `NT2010_ANALYSIS_UNITS_PARQUET`
   (`main_did_v1_nt2010_analysis_units.parquet`). It holds **treated + never-target
   control** units, so it must not reuse the control-only `never_target_units`
   naming.
3. `11a` horizon comment corrected to state the binding upper bounds explicitly
   (never-target: `g+EVENT_HI <= 2015`; g+7: `g+CONTROL_LAG <= 2015`).

Re-verification after amendments (`scratchpad/pkg1_check.R`): all constants and
eras unchanged; `formals(build_never_target_arm)$stacks` has **no default**;
17 parquet path constants, all unique (path-collision check passed); no nt2010
target overlaps any frozen artifact; 7 edited scripts parse OK. Repo-wide search:
no bare `STACK_HI`/`BALANCE_ERAS`, no dangling `NT2010_UNITS_PARQUET`, no
defaulting `build_never_target_arm(con)` call. `git diff --check` clean.

## 1. What changed (config diff summary)

Six source files, all behavior-preserving renames plus new
(as-yet-unconsumed) constants:

| File | Change |
|---|---|
| `11a_main_design_config.R` | Retired global `STACK_HI <- 2008L`; added `STACK_HI_NEVER_TARGET <- 2010L` and `STACK_HI_G7 <- 2008L`. Replaced `BALANCE_ERAS` with disjoint `BALANCE_ERAS_NEVER_TARGET` (4 bins, adds `c(2009,2010)`) and `BALANCE_ERAS_G7` (3 bins, ends 2008). |
| `11b_build_main_sample.R` | 3× `STACK_HI` → `STACK_HI_G7` (treated-roster filter + 2 cs2021 membership/covariate queries). Value unchanged (2008); `main_did_v1_units.parquet` remains the frozen g+7 roster. |
| `11c_balance_main_sample.R` | Era-balance loop `BALANCE_ERAS` → `BALANCE_ERAS_G7` (11c balances the g+7/legacy units). Value unchanged. |
| `11_main_design_utils.R` | `build_never_target_arm(con, stacks)` — **`stacks` is now required (no default)**. Legacy caller (`11f`) passes `STACK_LO:STACK_HI_G7`; nt2010 builder passes `STACK_LO:STACK_HI_NEVER_TARGET`. |
| `11f_never_target_arm.R` | Call updated to `build_never_target_arm(con, stacks = STACK_LO:STACK_HI_G7)` (explicit legacy horizon). |
| `11i_robustness_config.R` | New nt2010 block: horizon constants + versioned parquet paths + result/figure/audit prefixes (see §3). |

**Design intent:** every legacy `STACK_HI`/`BALANCE_ERAS` reference now resolves
to `STACK_HI_G7` / `BALANCE_ERAS_G7`, whose values are numerically identical to
the old globals, so no existing script changes behavior or output. The 2010
horizon (`STACK_HI_NEVER_TARGET`) and the versioned paths have **no consumer
yet** — they will be wired up by the new nt2010 build scripts in Packages 2–5.

## 2. STACK_HI disambiguation ledger (from Package 0 §4)

| Former site | Now references | Rationale |
|---|---|---|
| `11a:26-27` (definition) | split into `STACK_HI_NEVER_TARGET`, `STACK_HI_G7` | explicit per design family |
| `11b:66,71,91` (treated roster + cs2021 checks) | `STACK_HI_G7` | `11b` output is the frozen g+7 roster |
| `11_main_design_utils.R:542` (`build_never_target_arm`) | `stacks` argument now **required (no default)** | prevents a never-target call silently inheriting the g+7 ceiling; legacy `11f` passes `STACK_LO:STACK_HI_G7`, nt2010 passes `STACK_LO:STACK_HI_NEVER_TARGET` |
| `11_main_design_utils.R:336` (`build_control_arm`) | unchanged (`2015L - control_lag`) | already g+7-lag-derived, never used the global |
| `11c:165` (era balance) | `BALANCE_ERAS_G7` | balances g+7/legacy units |

## 3. Versioned path map (new build targets, none exist on disk yet)

Frozen 1994–2008 artifacts (untouched): `main_did_v1_units.parquet` (g+7 roster),
`main_did_v1_never_target_units.parquet`, `..._h5_weights.parquet` (P0H5),
`..._h5_deal_weighted_weights.parquet` (P5), `..._g7_reduced4x4_weights_diagnostic.parquet` (P3),
`..._g7_deal_weighted_weights.parquet` (P4).

New nt2010 targets (defined in `11i`):

| Constant | Basename | Purpose |
|---|---|---|
| `NT2010_ANALYSIS_UNITS_PARQUET` | `main_did_v1_nt2010_analysis_units.parquet` | expanded analysis roster: **treated + never-target control** (1994–2010) |
| `P0H5_NT2010_WEIGHTS_PARQUET` | `main_did_v1_nt2010_p0h5_weights.parquet` | P0H5 inventor-weighted, 1994–2010 |
| `P5_NT2010_WEIGHTS_PARQUET` | `main_did_v1_nt2010_p5_weights.parquet` | P5 deal-weighted, 1994–2010 |
| `NT2010_PANEL_PARQUET` | `main_did_v1_nt2010_panel_never_target_h5.parquet` | expanded event panel |
| `P0H5_CC9408_WEIGHTS_PARQUET` | `main_did_v1_nt2010_p0h5_cc9408_weights.parquet` | common-cohort (1994–2008) P0H5 twin |
| `P5_CC9408_WEIGHTS_PARQUET` | `main_did_v1_nt2010_p5_cc9408_weights.parquet` | common-cohort (1994–2008) P5 twin |
| `NT2010_RESULTS_PREFIX` / `_FIGS_` / `_AUDIT_` | `main_did_v1_nt2010` | compose `<prefix>_<name>` for CSVs/PNGs |

Horizon constants: `NT2010_STACK_LO=1994`, `NT2010_STACK_HI=2010`, `CC_STACK_HI=2008`.

## 4. Instruction compliance

1. **Versioned 1994–2010 input for P0H5/P5** — defined via `NT2010_*` paths; do
   not overwrite `main_did_v1_units.parquet` (kept as frozen g+7 input; not
   silently changed — its builder now explicitly reads `STACK_HI_G7`). ✔
2. **P3/P4 restricted to 1994–2008** — g+7 stays on its own frozen roster
   (`main_did_v1_units.parquet`, `..._g7_*` weights) via `STACK_HI_G7`.
   **Architecture decision: separate/frozen g+7 roster path is used, so no shared
   expanded artifact feeds P3/P4.** Therefore the "filter both arms to
   `STACK_HI_G7` at the loader + hard assertion `no P3/P4 stack > 2008`" applies
   only if a later package chooses to source P3/P4 from a shared expanded roster;
   since we do not, that guard will be added at the g+7 loader boundary in
   Package 5 **iff** that choice is ever made. Flagged for Package 5. ✔ (design)
3. **Disjoint never-target balance eras with 2009–2010 diagnostic bin** — encoded
   exactly as specified in `BALANCE_ERAS_NEVER_TARGET`; `BALANCE_ERAS_G7` ends
   2008. No feasibility thresholds were altered. ✔
4. **Protected files** — added `02_analysis/notes/verginer_ebal_checkpoint.md`
   (newly untracked) to the protected list alongside the untracked `12*` scripts
   and `AGENTS.md`. Not modified, staged, or deleted. ✔
5. **P3 remains infeasible diagnostic** — no gate touched; `P3_DIAGNOSTIC_WEIGHTS_PARQUET`
   and `ROBUSTNESS_SPECS` P3 row unchanged. ✔

## 5. Verification results

Ran `scratchpad/pkg1_check.R` (sources `11a`+`11i`, parses edited scripts):

- `STACK_LO=1994  STACK_HI_NEVER_TARGET=2010  STACK_HI_G7=2008`; `NT2010=[1994,2010]`, `CC_STACK_HI=2008`. ✔
- `BALANCE_ERAS_NEVER_TARGET` = 4 bins incl. `2009-2010`; `BALANCE_ERAS_G7` = 3 bins ending 2008. ✔
- Retired globals gone: `!exists("STACK_HI")` and `!exists("BALANCE_ERAS")`. ✔
- Grep (`STACK_HI\b` / `BALANCE_ERAS\b`, `\b` excludes `_G7`/`_NEVER_TARGET`): only the retired-global comment and the intentional `NT2010_STACK_HI`/`CC_STACK_HI` names remain — no bare operational use. ✔
- All 6 nt2010 build targets `exists_on_disk=FALSE` (no overwrite risk); frozen P0H5/P5/NT/UNITS artifacts still present and at distinct paths. ✔
- `parse()` OK for `11b`, `11c`, `11_main_design_utils.R`, `11f`, `11j`, `11k`, `11l`. ✔
- **ALL PACKAGE 1 CHECKS PASSED.**

## 6. Notes for Package 2

- Expanded treated cohort (1994–2010) is **not** in `main_did_v1_units.parquet`
  (that file's treated rows stop at 2008). Package 2 must derive treated
  1994–2010 (via `qualify_sql` filtered to `STACK_HI_NEVER_TARGET`) and combine
  with `build_never_target_arm(con, stacks = STACK_LO:STACK_HI_NEVER_TARGET)`
  into `NT2010_ANALYSIS_UNITS_PARQUET`. Per review, Package 2 must add hard
  membership checks: (a) fresh 1994–2008 treated keys == frozen treated keys;
  (b) overlapping covariates reproduce frozen values within existing tolerances;
  (c) 2009 & 2010 counts reported separately by cohort, deal, inventor-stack, and
  exclusion reason; (d) exactly one row per analysis-unit key; (e) treated and
  control arms disjoint on `(codinv, stack)`; (f) no outcome information enters
  roster construction.
- Era-level balance for nt2010 uses `BALANCE_ERAS_NEVER_TARGET`; treat the
  `2009-2010` bin as an expanded-cohort diagnostic.
- g+7 (2009–2010) is mechanically infeasible (`stack_hi = 2015 - lag`), consistent
  with keeping P3/P4 at 1994–2008.

## 7. Protected-file list (do not modify/stage/delete)

- `02_analysis/R/12_run_verginer_ebal.R`, `12a_`, `12b_`, `12c_`, `12d_`, `12e_verginer_ebal.R`
- `02_analysis/notes/verginer_ebal_checkpoint.md`  ← added this package
- `AGENTS.md`
- All frozen 1994–2008 `main_did_v1_*` outputs (checksums in Package 0 note).
