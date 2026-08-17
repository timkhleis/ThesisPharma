# nt2010 Matching-Design — Pause & Consolidated Handover

Date: 2026-07-21
Status: **PAUSED for review of the matching strategy.** No design is
production-ready or approved for estimation. Package 3A (outcomes) has never been
started and remains blocked. P5 is untouched throughout. All frozen 1994–2008
artifacts verified unchanged.

This is a self-contained handover of everything done in the "expand the
never-target main design to 1994–2010 (nt2010)" work, from Package 0 through the
blocked Package 2B.3. It supersedes nothing; the per-package notes remain the
detailed record. Git HEAD unchanged at `f45f960` (nothing committed; all work is
in the working tree).

---

## 1. Initial design and sample horizons

**Main design (P0H5 / P5): cohorts 1994–2010 (17 cohorts).**
**g+7 robustness (P3 / P4): cohorts 1994–2008 (15 cohorts).**

Why the horizons differ (both bounded by the 1988–2015 patent panel):
- Never-target (P0H5/P5): treated cohort `g` needs its event window to fit —
  `g + EVENT_HI (=+5) ≤ 2015` ⇒ `g ≤ 2010`. Lower bound `g − 6 ≥ 1988` ⇒ `g ≥ 1994`.
- g+7 (P3/P4): the future-treated control clock needs `g + CONTROL_LAG (=7) ≤ 2015`
  ⇒ `g ≤ 2008`. So g+7 mechanically cannot reach 2009–2010 and stays 1994–2008.

**Expanded roster (`main_did_v1_nt2010_analysis_units.parquet`), built fresh:**
- Treated arm: `qualify_sql(0L)` (all years) → `keep_first_exposure()` on the full
  population → restrict `1994 ≤ deal_year ≤ 2010`.
- Control arm: `build_never_target_arm(con, STACK_LO:STACK_HI_NEVER_TARGET)` —
  never-observed-target pharma groups, latest pre-deal affiliation, cleanliness
  through g+5 built-in (the legacy g+3 `build_h5_control_roster` was NOT used).
- Membership: **27,746 treated inventors** (336 deals) + **4,473,727 control
  inventor-stacks** = **4,501,473 rows**, cohorts 1994–2010, one row per
  `(codinv, stack)`, no cross-arm overlap, all covariate columns present, 0 missing.
- **Frozen-overlap equivalence:** the fresh 1994–2008 treated keys exactly equal
  the frozen treated design (0/0 diffs, 25,524 keys); overlapping covariates
  reproduce frozen values to < 4.5e-16 (≪ COV_TOL 1e-6); modal/gap match = 1.000.
- New 2009/2010 cohorts: 2009 → 689 treated (17 deals); 2010 → 1,533 (29 deals).

**Frozen-artifact protection:** the frozen 1994–2008 outputs
(`main_did_v1_never_target_h5_weights.parquet`, `..._h5_deal_weighted_weights`,
`..._g7_*`, `..._panel_*`, and the frozen `main_robustness_*` result CSVs) were
md5-checksummed in Package 0 and **re-verified identical after every subsequent
package.** No frozen artifact was written by any nt2010 script.

---

## 2. Package-by-package record

Git HEAD `f45f960` throughout (nothing committed). Modified **tracked** files
(behavior-preserving; defaults reproduce frozen results byte-for-byte):
`11a_main_design_config.R`, `11b_build_main_sample.R`, `11c_balance_main_sample.R`,
`11f_never_target_arm.R`, `11_main_design_utils.R`, `11i_robustness_config.R`,
`11j_build_robustness_weights.R`. New **untracked** scripts: `11n`–`11u`.

### Package 0 — Baseline & dependency audit
- Purpose: map the pipeline, `STACK_HI`/`BALANCE_ERAS`/citation-cutoff usages, and
  checksum frozen outputs before any change.
- Created: `nt2010_package_00_baseline.md`. No code change.
- Findings: P0H5/P5 are produced by the *robustness* chain (`11i/11j/11k/11l`), not
  the legacy `11b–11e` chain; treated roster shared with g+7; 25,524 treated / 290
  deals / 15 cohorts (1994–2008) at baseline.
- Status: **passed**. Outputs: documentation only.

### Package 1 — Config split & versioned paths
- Purpose: separate the never-target horizon (2010) from g+7 (2008) without running.
- Config changes: retired global `STACK_HI`; added `STACK_HI_NEVER_TARGET=2010`,
  `STACK_HI_G7=2008`; split `BALANCE_ERAS` → `BALANCE_ERAS_NEVER_TARGET`
  (adds `2009–2010`) and `BALANCE_ERAS_G7`; `build_never_target_arm(con, stacks)`
  made **required-arg** (no default); added versioned `NT2010_*` parquet paths +
  result/figure/audit prefixes to `11i`. All legacy references repointed to the
  `_G7` variants (numerically identical → frozen behavior preserved).
- Created: `nt2010_package_01_config.md`.
- Status: **passed** (parse/source checks; 17 unique path constants; no collisions).
  Outputs: config only.

### Package 2 — Expanded roster + global P0H5/P5 weights + feasibility
- Purpose: build the 1994–2010 roster and the P0H5 (inventor-weighted) and P5
  (deal-weighted) global entropy weights, plus 1994–2008 common-cohort twins.
- Scripts: `11n_build_nt2010_roster.R`, `11o_build_nt2010_weights.R`,
  `11p_plot_nt2010_balance.R`; a behavior-preserving functions-only guard added to
  `11j`; `reltol` parameter threaded through `two_stage_ebal()` (default 1e-10 =
  WeightIt default → frozen callers byte-identical) and `run_inventor_weighted()`.
- Commands: `Rscript 11n`, `Rscript 11o` (×2), `Rscript 11p`.
- Findings: first build left P0H5 marginally infeasible on the stack-mass gate
  (1.293e-4 vs 1e-4, from the 2010 cohort's ebal residual). **Resolved by tightening
  the optimizer** (`reltol=1e-12`, `maxit=200000`) — an optimizer setting, not a
  threshold. Final: **all four specs FEASIBLE.** P0H5_nt2010 max|SMD| 2.2e-6,
  stack-mass 9.97e-6, control firm ESS ~119; P5_nt2010 excellent; cc9408 twins
  match frozen counts (25,524 treated / 290 deals).
- Created: `nt2010_package_02_design.md`.
- Status: **passed**. Outputs: **diagnostic** (not approved for estimation) —
  `..._nt2010_p0h5_weights.parquet`, `..._p5_weights.parquet`,
  `..._p0h5_cc9408_weights.parquet`, `..._p5_cc9408_weights.parquet`, +figures/CSVs.

### Package 2A — Conditional-balance diagnosis (aggregation-first)
- Purpose: test whether the excellent *global* balance hides *within-cohort*
  imbalance. Memory-first: DuckDB sufficient statistics; the 4.5M panel never
  collected into R.
- Script: `11q_diagnose_nt2010_conditional_balance.R`. Reproduced all 78 cohort/era
  maxima (pilot P0H5-2009 exact to 5e-13).
- Findings: **substantive within-cohort imbalance**, concentrated on **firm size /
  patent intensity** (`log_firm_inventor_count`, `log_patents_recent`,
  `log_firm_patent_stock`, `log_patents_early`); full-pooled SMD 0.4–1.2 in most
  P0H5 cohorts and all eras, while global max|SMD| = 2e-6. Per-cohort support is
  ample (thousands of control firms); the limitation is the balancing scheme, not
  support. Firm-level ESS ≈ 119 (P0H5) is a fragility diagnostic.
- Created: `nt2010_package_02a_conditional_balance.md`.
- Status: **passed (diagnosis)** — routed to a within-cohort correction.

### Package 2B.0 — Cohort-specific prototype, cohort 2009
- Purpose: prototype cohort-specific two-stage ebal (no `factor(stack)`) for 2009.
- Script: `11r_prototype_nt2010_cohort_ebal.R` (isolated; shared `two_stage_ebal()`
  not modified). `maxit=200000`, `reltol=1e-12`.
- Findings: **PASS, all gates.** Constrained max full-pooled SMD **0.967 → ~2e-7**;
  treated weights ≡1; control mass = treated mass (689); **firm ESS 636**; max firm
  share 0.013; no columns removed. Fully corrects 2009's conditional imbalance.
- Created: `nt2010_package_02b0_cohort_ebal_prototype.md`; diagnostic parquet
  `..._p0h5_cohort2009_PROTOTYPE_weights.parquet`.
- Status: **passed (prototype)**.

### Package 2B.1 — Full sequential cohort-specific build (1994–2010)
- Purpose: apply the 2B.0 method to all 17 cohorts, restartable, assemble full +
  cc9408 production-candidate weights.
- Script: `11s_build_nt2010_cohort_ebal_weights.R`; new config paths
  `P0H5_COHORT_EBAL_{WEIGHTS,CC9408_WEIGHTS}_PARQUET`, `..._SHARD_DIR`.
- Findings: **HALTED at cohort 1995** on the **per-cohort firm ESS (43.57 < 50)**.
  All other gates passed (balance excellent: max full-pooled SMD 1.5e-5). Root
  cause: thin treated support (1995 has 4 treated deals). Ran cohort 1994 first
  (PASS, firm ESS 81.5, shard written). No production file assembled.
- Created: `nt2010_package_02b1_full_cohort_ebal.md` (+ ESS-scope addendum);
  diagnostic shard `nt2010_p0h5_cohort_ebal_shards/cohort_1994.parquet` (+meta);
  `..._2b1_cohort_1995_FAILED_{gates,balance}.csv`.
- Status: **halted**. Outputs: **incomplete** (one diagnostic shard; no assembly).
- **Reclassified (see §4):** the per-cohort ESS<50 is a *conservative diagnostic*,
  not the *original* full-design gate — so 2B.1 did not fail the original gate; the
  assembled design's spec-wide ESS was never evaluated.

### Package 2B.2 — Era-level prototype, 1994–1999
- Purpose: test whether pooling within the pre-specified era fixes both dimensions.
  Era-level == shared `two_stage_ebal()` (with `factor(stack)`) on the 6-cohort
  subset — solver reused unchanged.
- Script: `11t_prototype_nt2010_era_ebal.R`.
- Findings: **INSUFFICIENT.** Era-level gates all pass (firm ESS 84.6) BUT every
  constituent cohort **fails within-cohort balance** (full-pooled SMD 0.30–0.79),
  comparable to or worse than the old global. Era pooling reproduces the pooled
  problem; it does not solve within-cohort imbalance. Support map: treated
  firm-stage matrices rank-deficient in 15/17 cohorts.
- Created: `nt2010_package_02b2_era_ebal_prototype.md` (+ ESS-scope addendum);
  diagnostic parquet `..._p0h5_era9499_PROTOTYPE_weights.parquet`.
- Status: **failed (insufficient)**.

### Package 2B.3 — Approximate within-cohort ebal (attempt), cohorts 1995 & 1996
- Purpose: most-diffuse ebal weights satisfying full-pooled SMD ≤ 0.05 (not exact),
  via WeightIt per-covariate `tols` + `solver="FISTA"`.
- Script: `11u_prototype_nt2010_approx_cohort_ebal.R` (correct `tols` translation +
  full mapping tables produced).
- Findings: **BLOCKED** — a verified WeightIt 1.7.0 bug (vector `tols` errors; §6).
  No weights produced; tolerance maps delivered. Also recorded the ESS-scope and
  rank-interpretation corrections (§4, §3).
- Created: `nt2010_package_02b3_approx_cohort_ebal.md`;
  `..._2b3_cohort_{1995,1996}_tolerance_map.csv`, `..._2b3_status.csv`.
- Status: **blocked**.

### Package 2B.3A — Full 17-cohort approximate build
- **Proposed only; NOT executed.** Would follow a successful 2B.3 with a
  restartable 17-cohort approximate build + the *original* full-design ESS and
  max-share gates. Not started.

---

## 3. Main empirical findings from the design audit

- Pooled **global** entropy balancing achieves near-perfect *aggregate* balance
  (max|SMD| ≈ 2e-6) but **conceals substantial within-cohort imbalance** (full-pooled
  SMD 0.4–1.2 across most cohorts).
- The within-cohort imbalance is concentrated on **firm size and patent intensity**
  (log firm inventor count, log firm patent stock, log recent/early patents).
- **Era-level** balancing reproduces the pooled problem (within-cohort SMD 0.30–0.79)
  rather than solving it.
- **Exact cohort-specific** balancing can *eliminate* within-cohort imbalance
  (2009 → 2e-7; 1995 → 1.5e-5).
- Exact matching can produce **concentrated control weights in thin treated
  cohorts**: 1995 balances but with local firm ESS **43.57**; 2009 balances with
  firm ESS ≈ **636**.
- Treated-firm support is **thin and often rank-deficient** in early cohorts
  (treated firm-stage MM rank: 1996 = 1, 1994 = 3, 1995 = 4; ≤10 even in deal-rich
  cohorts due to collinear no-history binaries).
- **Rank deficiency is a support diagnostic, not a proof** that concentration is
  mathematically inevitable. Concentration is *demonstrated* by the observed 1995
  exact-balance weights; the rank map only *flags* where similar problems may
  arise. No claim is made that 1996 must fail before it is estimated.

### Compact comparison (within-cohort constrained max full-pooled |SMD| ; firm ESS)

| Design | Aggregate balance | Within-cohort balance | Concentration (firm ESS) | Status |
|---|---|---|---|---|
| Global pooled (P0H5_nt2010) | max\|SMD\| ≈ 2e-6 | **0.4–1.2** (unresolved) | ~119 (full-design) | feasible-diagnostic |
| Era pooled (1994–1999) | 3.3e-5 | **0.30–0.79** (unresolved) | 72–104 (per-cohort) | insufficient |
| Exact cohort-specific | (per cohort) | **≈0** (2009: 2e-7; 1995: 1.5e-5) | 2009: 636 ✓ ; **1995: 43.6** (local) | halted at 1995 (local diag.) |
| Approximate (per-covariate ≤0.05) | — | *intended ≤0.05* | *intended higher than exact* | **blocked** (not run) |

(Old-global vs exact vs era, per cohort, in `..._2b2_comparison_*` and the 2B.1/2B.2 notes.)

---

## 4. Gate-scope clarification (important)

- `ROBUST_MIN_ESS = 50` and `ROBUST_MAX_SHARE = 0.10` were, in the frozen
  robustness implementation, applied to the **complete-specification** control
  firm-mass distribution (`positive_concentration()` aggregates by underlying firm
  across the whole spec; `gate_inventor()` applies the thresholds there).
- Applying these **separately within each cohort** (as in Packages 2B.0–2B.2) was an
  **additional conservative diagnostic** introduced during the conditional-balance
  investigation — **not** the original gate.
- **The original numerical thresholds were never changed** (`ROBUST_MIN_ESS = 50`,
  `ROBUST_MAX_SHARE = 0.10`, `ROBUST_MAX_SMD_CONSTRAINED = 0.05`,
  `STACK_MASS_TOL = 1e-4`, `EBAL_CONSTRAINT_TOL = 1e-4`).
- Consequently the exact cohort-specific **full design was never completed under the
  clarified original gate scope**: 2B.1 halted at the first cohort tripping the
  per-cohort diagnostic, so the assembled design's spec-wide ESS/max-share were
  never evaluated. Whether exact cohort-specific is feasible under the original
  full-design gate is **open**.
- **No design should currently be labelled production-ready or approved for
  estimation.** All nt2010 weight parquets are diagnostic/incomplete.

---

## 5. Runtime and memory lessons

- Single-cohort 2009 solve (2B.0): firm+inventor balance ≈ 40 s, peak ≈ 1.5 GB.
- Thin-cohort solves are slow (near rank-deficient firm stage): 1994 ≈ 80 s,
  **1995 ≈ 672 s**; WeightIt emits a "degenerate solution" warning yet achieves raw
  residuals ≤ 3e-5.
- **Era 1994–1999 solve (2B.2): ≈ 6,538 s (109 min)**, peak R memory ≈ 3.3 GB, at
  `reltol=1e-12` on 938k units — a four-era build would be very expensive as specified.
- Aggregation-first diagnostics (2A): ≈ 5–7 s per spec, peak ≈ 145 MB (the 4.5M
  panel was never materialised in R).
- Lessons for any future method: **sequential** (one cohort at a time), **projected**
  columns, **restartable** (verified shards, two-way key anti-joins, not counts
  alone), and **memory-bounded**; assemble from shards via DuckDB without collecting
  the 4.5M design into R; **avoid a global `covariate × factor(stack)` interaction
  matrix**; treat `WeightIt converged = FALSE` as a max-iteration flag (disclose it,
  do not call it convergence) and use the raw model-matrix residual as the
  convergence test.

---

## 6. WeightIt approximate-balance blockage

**Intended per-covariate tolerance translation (correct; ready for reuse).** From
the WeightIt 1.7.0 source: for ATT, the enforced constraint is a treated-SD SMD
bound for nonbinary columns (scale-invariant to internal rescaling) and a raw
mean-diff bound for binary columns; the intercept is exact. To realize
`raw_diff ≤ 0.05 × pooled_full_sd[j]`:
- nonbinary: `tols[j] = 0.05 × pooled_sd[j] / sd_treated_raw[j]`
- binary: `tols[j] = 0.05 × pooled_sd[j]`
- factor dummies + intercept: exact (`tols = 0`)
- zero-treated-SD nonbinary: keep exact and flag.

This translation and full mapping tables (stage, covariate, model-matrix column,
type, treated SD, fixed full-pooled SD, desired raw tol, supplied WeightIt `tols`,
implied raw tol) are implemented in `11u` and saved as
`..._2b3_cohort_{1995,1996}_tolerance_map.csv` / `..._2b3_tolerance_map_all.csv`.
`11u` pre-builds a full-rank numeric design (dummies expanded manually) and asserts
`length(tols) == ncol(X)` per stage, so column/tolerance alignment is exact.

**The verified problem.** In the installed WeightIt 1.7.0, `weightit2ebal` contains
`if (tols > 0) { … tols <- c(0, tols * sds) … }` — a scalar-assuming `if` that,
under R ≥ 4.2, **errors on a length-`>1` (per-covariate) `tols`** ("condition has
length > 1"). Minimal reproduction (`scratchpad/tols_probe.R`): scalar `tols=0.05`
runs; `tols=c(0.05,0.05,0.05)` errors. The FISTA objective itself uses `tols`
per-column, so this is a guard bug, not a design limitation — but fixing it needs
modifying package internals, which was disallowed.

**Why scalar `tols` cannot reproduce the intended per-covariate raw tolerances.** A
single scalar means *treated-SD SMD* for continuous columns but *raw mean-diff* for
binary columns (different units); a binary's pooled SD (~0.3–0.5) forces the raw
bound tiny, over-constraining all continuous columns toward exact and defeating the
diffuseness objective; and a scalar cannot keep the inventor factor indicators
exact. It is therefore not a valid realization of the specification.

**The translation work should be preserved for reuse.** It is correct and
solver-agnostic; against a working per-covariate-tolerance solver (`optweight` or
`sbw`, both by WeightIt's author; or a WeightIt build with the `tols` guard fixed)
the `11u` mapping drops in directly. `optweight`/`sbw` are **not installed** in the
project library; `osqp` is.

---

## 7. Current artifact inventory & protection status

**Diagnostic (NOT production, NOT approved for estimation):**
`main_did_v1_nt2010_analysis_units.parquet` (roster);
`..._p0h5_weights.parquet`, `..._p5_weights.parquet`,
`..._p0h5_cc9408_weights.parquet`, `..._p5_cc9408_weights.parquet` (global/cc);
`..._p0h5_cohort2009_PROTOTYPE_weights.parquet`,
`..._p0h5_era9499_PROTOTYPE_weights.parquet` (prototypes);
`nt2010_p0h5_cohort_ebal_shards/cohort_1994.parquet` (one incomplete shard).
Plus all `..._2a_*`, `..._2b0_*`, `..._2b1_*`, `..._2b2_*`, `..._2b3_*` audit CSVs,
result CSVs, and two nt2010 balance figures.

**Frozen (verified unchanged, md5-identical to Package-0 baseline):** all
`main_did_v1_never_target_*`, `..._g7_*`, `..._panel_*` parquets, and the frozen
`main_robustness_*` result CSVs; the 6 pre-existing figures.

**Protected & untouched throughout:** the untracked `12*` Verginer scripts, both
Verginer checkpoints, `00_Discussion_Docs/011_thesis_paper_structure.md`,
`AGENTS.md`, and all P5 artifacts. The shared `two_stage_ebal()` was extended only
with a behavior-preserving `reltol` parameter (default = WeightIt default).

---

## 8. Where things stand / open decision

The design audit has bracketed the matching problem precisely: pooled designs
(global, era) leave substantial within-cohort firm-size imbalance; exact
cohort-specific removes it but concentrates control weight in thin cohorts under
the *per-cohort* ESS diagnostic; the approximate-ebal route is blocked by a WeightIt
bug pending an environment change. Under the *original* full-design gate scope,
exact cohort-specific has **not** been evaluated end-to-end and may still be
feasible.

**No further implementation** (2B.3A, `optweight`, partial pooling, cohort/era
solvers, outcome panels, citation changes, annual-state construction, exit
outcomes, or DiD estimation) will proceed until the matching-strategy choice is
resolved. Package 3A remains blocked; P5 remains untouched.
