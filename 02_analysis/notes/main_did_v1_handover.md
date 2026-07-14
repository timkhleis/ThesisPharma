# Main DiD v1 — implementation handover (for Codex)

**Branch:** `main-did-v1` (pushed to `origin`, github.com/timkhleis/ThesisPharma).
**Latest commit:** `0102374`. **Do not touch the certified `08*` scripts.**
**Full narrative + numbers:** `02_analysis/notes/main_did_v1_first_results.md` (esp. §6).

## Where we are

The thesis's main causal design = **full pre-deal inventor cohort** (inventors affiliated with a
target in `[g-5,g-1]` before announcement year `g`), Fadlon–Nielsen clock alignment, **two-stage
hierarchical entropy balancing** (firm → inventor), inventor-weighted ATT, outcomes = active
patenting / patent count / 5y forward citations, δ∈{0,1}.

**Decisive result reached:** the inventor-weighted ATT is **infeasible with g+7 future-treated
controls** (control ESS collapses to ~1 — a few mega-deals dominate and have no comparable control
firm) but is **fully feasible with a never-(observed-)target control pool**. After correcting the
`ever_target` construction (target-side pre-deal identity only) the full two-stage balance passes
cleanly: all 14 covariates balanced to ~1e-5, **unique-firm ESS 101.7**, max single control-firm
weight 4.2%, weighted pharma-core 0.43 vs treated 0.46. **~42% of control weight is from acquirer
firms** (acquirers are legitimate never-targets and were wrongly excluded before the fix).

## Pipeline (all in `02_analysis/R/`), run from repo root

| script | status | what it does |
|---|---|---|
| `11a_main_design_config.R` | done | all constants, paths, covariate vectors, `EBAL_CONSTRAINT_TOL=1e-4` |
| `11_main_design_utils.R` | done | `qualify_sql`, `keep_first_exposure`, `build_control_arm` (g+L placebo), `build_never_target_arm`, `compute_firm_covariates`, `compute_inventor_covariates`, `two_stage_ebal` [A1], `ebal_max_meandiff`, `model_matrix_cols`, `post_average`, `joint_pretrend`, `extract_es_coefs`, IPC family classifier |
| `11b_build_main_sample.R` | done, validated | treated cohort + 4a/4b certification (exact), g+7 controls (placebo-group identity, lineage-aware cleanliness, acquirer=diagnostic), census L∈{7,9}, firm+inventor covariates → `main_did_v1_units.parquet` |
| `11c_balance_main_sample.R` | done | g+7 two-stage balance; self-test (incl. N-vs-N² probe) passes; **stops at convergence gate under inventor-weighting by design** (g+7 is degenerate) |
| `11f_never_target_arm.R` | done, validated | never-target universe + assignment + firm covariates + audits → `main_did_v1_never_target_units.parquet` (3.72M rows, 79,087 cells) |
| `11g_support_comparison.R` | done | firm-stage support: future_g7 / never_target / hybrid + donor audits + decision gate → `never_target_support_comparison.csv` |
| `11h_never_target_stage2.R` | done | full two-stage for never-target (3.75M units, ~11 min) → `never_target_stage2_*.csv`, `main_did_v1_never_target_weights.parquet` |
| `11d_build_main_panel.R` | **NOT built** | next task — see below |
| `11e_estimate_main_results.R` | **NOT built** | next task |
| `11_run_main_results.R` | **NOT built** | runner (separate processes) |

Run order to reproduce: `11b` → `11f` → `11g` → `11h` (each `Rscript 02_analysis/R/<f>.R`).

## NEXT TASK: `11d` panel + `11e` event study (pre-trends) for the never-target arm

This is the only remaining pre-decision check (reviewer's step 6). Build the outcome panel and the
inventor-weighted event study, δ=0 first.

- **Panel `11d`:** expand each unit (treated + never-target control) to `t ∈ [-5,+3]`
  (`calendar_year = stack + t`); LEFT JOIN `inventor_year` → zero-fill `patent_count`;
  `active_patenting = as.integer(patent_count>0)`. **fwd_cits5 [B3]: preserve missingness** —
  aggregate `patent_enriched.fwd_cits5 ⋈ patent_inventor` on `patent_year`, carrying
  `n_patents / n_patents_missing_fwd_cits5 / sum_observed_fwd_cits5 / citation_complete`; outcome =
  0 if no patents that year, observed sum if all non-missing, **missing** if any filed patent lacks
  `fwd_cits5` (do NOT `SUM(COALESCE(fwd_cits5,0))`). Attach `final_weight` from
  `main_did_v1_never_target_weights.parquet` (treated weight = 1; controls from Stage 2), constant
  across the 9 event years. Assertions: 9 rows/inventor-stack, `active_patenting==(patent_count>0)`,
  weights finite/positive.
- **Estimator `11e`** (mirror [08u:122-156]):
  `feols(y ~ i(event_time, treated, ref=-(1+delta)) | stack^event_time + uid_stack, weights=final_weight, cluster=~cluster_id)`
  with `uid_stack = interaction(codinv, stack, drop=TRUE)`. Use `extract_es_coefs`, `post_average`
  (t1–t3, clustered vcov), `joint_pretrend` (δ=0: t∈{-5..-2}). **Also run the unweighted spec** for
  contrast. Figure: 3 outcomes × δ, mark t=0 partial-exposure, CIs labeled "conditional on estimated
  weights" [A10]. CIs hold the EB weights fixed (bootstrap deferred).
- **OPEN DECISION — clustering:** never-target controls repeat across stacks with **no real deal**, so
  cluster on `underlying_group_id` for controls and the real deal for treated. Tim to confirm the
  intended inference unit before finalizing SEs. (Treated cluster key = `focal_deal_id`.)

## Open decisions awaiting Tim / Fable / GPT-sol
1. Proceed to `11d/11e` now, or hold for external review of memo §6 first.
2. Clustering unit for never-target controls (see above).
3. If pre-trends are credible + ESS/concentration hold (they do at the balancing stage), **lock
   inventor-weighted ATT as primary**; else fall back to deal-weighting (feasible, ESS 43%, see §3–4).

## Environment / gotchas (critical for Codex)
- R: `C:\Program Files\R\R-4.5.1\bin\Rscript.exe`. **Run scripts from the repo root** (paths use
  `normalizePath("02_analysis")` and `use_project_library()` resolves `.r_libs` via `getwd()`).
- **Use the PowerShell tool for Rscript+duckdb** — it segfaults under the Bash/Git-Bash tool on this
  machine. For temp R scripts, **write with the Write tool** (PowerShell `Set-Content -Encoding utf8`
  adds a BOM that breaks Rscript).
- Every script header: `source(.../00_utils.R); use_project_library()` then
  `library(DBI/duckdb/WeightIt/cobalt/fixest/ggplot2)`. `WeightIt` 1.7.0 + `cobalt` 4.6.3 are in
  `.r_libs`; `fixest`, `did`, `sandwich`, `ggplot2` in the user lib.
- DB read-only: `dbConnect(duckdb::duckdb(), DUCKDB, read_only=TRUE)`; register R frames with
  `duckdb::duckdb_register` (works read-only); write parquet via `COPY (...) TO '...' (FORMAT PARQUET,
  COMPRESSION ZSTD)`. Set `PRAGMA memory_limit='8-10GB'`, `threads=4`, `temp_directory=DUCKDB_TMP`.
- Outputs live under `02_analysis/output/{audit,results,figures,parquet}/main_did_v1/` — **gitignored**
  (regenerable). The memo carries the numbers.

## Key data facts
- Treatment year = `target_year`/`deal_year` (`g`); do NOT use `acqui_year`.
- Certified cohort spine: `cassi_deal_group_spine` (`deal_id, deal_year, target_group, acquirer_group,
  target_compcod_list, todrop_acq`); `target_cohort_own`; `cs2021_estimation_panel` (4a/4b cert target,
  has treated outcomes for equivalence check).
- `firm_group(compcod, year, id_group)` = time-varying company→group map (placebo-group source).
- `ipc.ipc_code` is the **zero-padded** full symbol (`A61K031`, `A61K009`, …) — family predicates use
  the padded forms; C07K→biotech evaluated before C07→small-molecule.
- `patent_company_link(appln_id, compcod, year, id_group)`; `patent_enriched.fwd_cits5` (no raw
  citing-years exist → citation completeness can't be verified from the DB; label provisional [A8]).
- `two_stage_ebal` [A1]: firm stage `s.weights=n_qualifying_inventors`; inventor stage
  `base.weights=firm_multiplier` (NOT the mass — firm size enters once); treated weights must stay 1
  (asserted). Firm-cell key for never-target = `(underlying_group_id, stack)`.
