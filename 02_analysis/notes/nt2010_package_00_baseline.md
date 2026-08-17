# nt2010 — Package 00 Baseline & Dependency Audit

Date: 2026-07-20
Author: baseline audit (read-only; no design changes)

## 0. Scope of this note

Package 0 establishes the repository state before any code change for the
"expand never-target main horizon to 1994–2010" work (`nt2010`). **No source
file was modified in this package.** The only new file is this note. Existing
untracked `12*` Verginer files and `AGENTS.md` were left untouched.

## 1. Git / working-tree state

- HEAD: `f45f960` — "Add never-target balance plot script"
- Branch: `main-did-v1` (tracks `origin/main-did-v1`, in sync)
- Untracked (DO NOT modify/stage): `02_analysis/R/12_run_verginer_ebal.R`,
  `12a_verginer_ebal_config.R`, `12b_build_verginer_covariates.R`,
  `12c_verginer_ebal_utils.R`, `12d_estimate_verginer_ebal.R`,
  `12e_report_verginer_ebal.R`, `AGENTS.md`
- `11m_plot_never_target_balance.R`: **tracked** (confirmed via `git ls-files`).

## 2. Prefix availability

- `12*` prefix is **occupied** by the untracked Verginer files above.
- Plan reserves `13*` for the new heterogeneity helpers (Package 6). Confirmed
  no new script in this plan will use `12*`.

## 3. Two design families in the current `11*` pipeline

The thesis "main" spec (per project memory) is **P0H5** (never-target,
entropy-balanced, inventor-weighted) with **P5** its deal-weighted sibling.
These are currently produced by the *robustness* script chain, not the older
`11b–11e` "main" chain. Mapping:

| Function | Script(s) |
|---|---|
| Frozen design constants (STACK_LO/HI, BALANCE_ERAS, paths, outcomes) | `11a_main_design_config.R` |
| Robustness constants (P0/P0H5/P1/P2/P3/P4/P5 weight paths + spec table) | `11i_robustness_config.R` |
| Shared builders (`build_control_arm`, `build_never_target_arm`) | `11_main_design_utils.R` |
| **Treated roster** | `11b_build_main_sample.R` |
| **Never-target control arm** | `11f_never_target_arm.R` → `build_never_target_arm()` |
| **Main entropy weights** (legacy main chain) | `11c_balance_main_sample.R` |
| **Robustness weights P0–P5** (incl. P0H5/P5/P3/P4) | `11j_build_robustness_weights.R` |
| Main panel (legacy chain) | `11d_build_main_panel.R` |
| **Robustness panels** (P0H5/P5/P3/P4) | `11k_build_robustness_panels.R` |
| Main estimation (legacy chain) | `11e_estimate_main_results.R` |
| **Robustness estimation** (P0H5/P5/P3/P4) | `11l_estimate_robustness_results.R` |
| Support / stage-2 diagnostics | `11g_support_comparison.R`, `11h_never_target_stage2.R` |
| Balance figures | `11m_plot_never_target_balance.R` (+ `07_build_figures.R`) |
| Runners | `11_run_main_results.R` (11d,11e); `11_run_robustness.R` (11j); `11_run_robustness_results.R` (11k,11l) |

Spec → donor pool (from `11i` `ROBUSTNESS_SPECS`):
- **P0H5, P5** → `never_target_h5` donor pool → **must extend to 1994–2010**.
- **P3, P4** → `future_g7` donor pool → **stay 1994–2008** (g+7 robustness).

## 4. `STACK_HI` usages — every site to disambiguate in Package 1

| Site | Current meaning | Package-1 assignment |
|---|---|---|
| `11a_main_design_config.R:26-27` | `STACK_LO<-1994L`, `STACK_HI<-2008L` (global) | replace with `STACK_LO`, `STACK_HI_NEVER_TARGET<-2010L`, `STACK_HI_G7<-2008L` |
| `11b_build_main_sample.R:66,71,91` | treated roster filter `deal_year BETWEEN STACK_LO AND STACK_HI` | **key**: treated roster is shared. Never-target needs treated cohorts to 2010; g+7 needs 2008. Must widen roster build and filter g+7 down. |
| `11_main_design_utils.R:336` | `build_control_arm(... stack_hi = 2015L - control_lag)` = 2008 for L=7 | already lag-derived (g+7); leave logic, conceptually `STACK_HI_G7` |
| `11_main_design_utils.R:539` | `build_never_target_arm(con, stacks = STACK_LO:STACK_HI)` = 1994:2008 | → `STACK_LO:STACK_HI_NEVER_TARGET` = 1994:2010 |

`11f_never_target_arm.R:27` calls `build_never_target_arm(con)` with defaults, so
its horizon is governed entirely by the `build_never_target_arm` default above.

## 5. Citation-maturity cohort restriction (`max_patent_year - 5`)

The rule Package 3 must remove:
- `11d_build_main_panel.R:244-246` and `11k_build_robustness_panels.R:455-457`
  compute `citation_filing_cutoff = max_patent_year - 5` and
  `citation_stack_cutoff = citation_filing_cutoff - max(POST_PERIODS)`.
- The flag `fwd_cits5_stack_sample = (stack <= citation_stack_cutoff)` is written
  into the panels (`11d:319`, `11k:286`).
- It is **consumed** as an estimation restriction at:
  - `11e_estimate_main_results.R:113-114` (`fwd_cits5_stack_sample = TRUE`)
  - `11l_estimate_robustness_results.R:105-107` (`p.stack <= citation_stack_cutoff`),
    where the cutoff is read from
    `AUDIT_DIR/main_robustness_citation_followup_cutoff.csv` (`11l:252-254`).
- OECD/citation *audits* to retain & strengthen live in `11d:332-389` and
  `11k:245-491` (coverage, missingness, duplicate-conflict, restricted balance).

## 6. Balance eras

- `BALANCE_ERAS <- list(c(1994,1999), c(2000,2004), c(2005,2008))` at `11a:50`,
  consumed at `11c_balance_main_sample.R:165`.
- Package 1 must add a never-target era set ending 2010 (e.g. extend/replace the
  final bin to `c(2005,2010)` or `c(2005,2008),(2009,2010)`) while keeping the
  g+7 era set ending 2008.

## 7. Hardcoded cohort years found

- `11a:26-27` (`1994`, `2008`); `11a:50` (era bounds).
- `11_main_design_utils.R:336` (`2015L`), `:539` (`STACK_LO:STACK_HI`).
- Citation cutoffs are *computed*, not hardcoded (`max_patent_year` from DB).
- No other literal `2009`/`2010` cohort ceilings found in `11*`.

## 8. Existing 1994–2008 outputs (protection baseline)

All current `main_did_v1` outputs are **1994–2008** and must be preserved; new
work writes versioned `main_did_v1_nt2010_*` names.

### Derived parquet (path — md5 — size)
- `main_did_v1_never_target_units.parquet` — `9abcbc84ed78c9bc80fa4f9536666ea4` — 13.5 MB
- `main_did_v1_never_target_h5_weights.parquet` — `c22a2dcb5d1ac2cabe26e452bcc8de27` — 25.7 MB
- `main_did_v1_never_target_h5_deal_weighted_weights.parquet` — `a3ee699182a4e473bb7e049c401fb14a` — 25.7 MB
- `main_did_v1_g7_reduced4x4_weights_diagnostic.parquet` — `43a5b3a9ff1033406606192362a0dcc6` — 140 KB
- `main_did_v1_g7_deal_weighted_weights.parquet` — `c5452769d3df421ff4af56379a001b89` — 206 KB
- `main_did_v1_panel_never_target_h5.parquet` — `92d8ffcdceb00650512221d1f944de3f` — 191 MB
- `main_did_v1_panel_g7.parquet` — `b479329bdc9b708e052ee23bdaeef717` — 2.9 MB
- (also present, legacy main chain: `main_did_v1_units.parquet`, `main_did_v1_never_target_weights.parquet`,
  `main_did_v1_never_target_acquirer_clean_weights.parquet`, `main_did_v1_never_target_h5_acquirer_clean_weights.parquet`,
  `main_did_v1_panel.parquet`)

### Key result CSVs (md5)
- `main_robustness_post_summaries.csv` — `feaea5714c8b28d9515c9be0a47a0b67`
- `main_robustness_design_comparison.csv` — `fe678e7f518b3ce825a7819a5039d447`
- `main_robustness_feasibility_decisions.csv` — `c344dfc7086e0df414c3f28ad7ba46e6`
- `main_robustness_stack_mass.csv` — `3f2310c6f10f005c92ebe04220738ffe`
- (full results dir also holds event-study dynamic/joint/post CSVs, balance, concentration, quantiles, figure manifest)

### Figures (`02_analysis/output/figures/main_did_v1/`)
`main_event_study_never_target_delta0.png`, `main_event_study_p0h5.png`,
`never_target_stage2_balance_loveplot.png`, `robustness_event_study_p0h5_vs_p5.png`,
`robustness_event_study_p5_vs_p4.png`, `robustness_post_effects_forest.png`

## 9. Baseline sample counts (read-only from parquet, stacks 1994–2008)

| Roster | rows/units | treated inv-stacks | treated deals | cohorts |
|---|---|---|---|---|
| `never_target_units` (controls only) | 3,721,005 | 0 (treated added in weights) | — | 1994–2008 |
| P0H5 weights (`never_target_h5_weights`) | 3,743,420 | 25,524 | 290 | 15 (1994–2008) |
| P5 weights (`never_target_h5_deal_weighted`) | 3,743,420 | 25,524 | 290 | 15 (1994–2008) |
| P3 diag (`g7_reduced4x4_diag`) | 36,290 | 25,524 | — | 1994–2008 |
| P4 (`g7_deal_weighted`) | 36,290 | 25,524 | — | 1994–2008 |

Treated set (25,524 inventor-stacks / 290 deals) is identical across never-target
and g+7 designs, confirming a single shared treated roster.

## 10. Exit-criteria confirmation

- [x] No files changed except this checkpoint note.
- [x] All affected scripts and outputs mapped (§3–§8).
- [x] Existing user changes (untracked `12*`, `AGENTS.md`) identified and left untouched.
- [x] `11m_plot_never_target_balance.R` confirmed tracked.
- [x] Confirmed no new script will use the occupied `12*` prefix (heterogeneity → `13*`).

## Open design questions surfaced for Package 1/2 review

1. **Treated roster horizon.** P0H5/P5 need treated cohorts 1994–2010, but the
   treated roster (`11b`) is shared with g+7 (which needs 1994–2008). Cleanest
   approach: build the treated roster to 1994–2010, and have g+7 weight/panel
   steps filter treated to ≤2008. To confirm before Package 2.
2. **g+7 feasibility for 2009–2010.** `build_control_arm` derives `stack_hi =
   2015 - control_lag`, so g+7 mechanically cannot reach 2009–2010 (no g+7
   control-year within data). This is why g+7 stays a 1994–2008 robustness design.
3. **Balance-era shape for 2009–2010** (single `(2005,2010)` bin vs. adding a
   `(2009,2010)` bin) — decide in Package 1.
