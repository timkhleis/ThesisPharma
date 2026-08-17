# nt2010 — Package 02B.1 Full Sequential Cohort-Specific P0H5 — HALTED (review)

Date: 2026-07-21
Scope: apply the validated Package-2B.0 cohort-specific two-stage ebal to all 17
cohorts (1994–2010), assemble the full + 1994–2008 production-candidate weights.
**Result: HALTED — cohort 1995 fails a gate.** No production file assembled.
Design-only; no outcomes/citations/annual-states/DiD. Frozen artifacts untouched.

## 0. Verdict

**Package 2B.1 does not complete.** The sequential build **failed at cohort
1995** on the underlying-control-firm **ESS gate (43.57 < 50)**. Per the specified
failure behavior, the script **stopped without assembling** any production weight
file, wrote the failing cohort's diagnostics, and made **no** solver/threshold/
covariate change. This is a **genuine concentration failure** (balance was
achieved; the fragility floor is the binding constraint), rooted in cohorts with
very few treated deals. **Package 3A stays blocked; P5 stays untouched.** Requesting
review of how to proceed.

## 1. Commands run

```
Rscript 02_analysis/R/11s_build_nt2010_cohort_ebal_weights.R
```
(First attempt aborted on a 0-row `cbind` when a cohort removes no columns — a
harness bug, fixed; no shard written. Re-run reached cohort 1995 and halted on the
gate.)

## 2. Implementation (as specified)

- Sequential, one cohort at a time; only that cohort loaded (projected columns);
  no 4.5M-row collect; no `covariate × factor(stack)` matrix.
- Verbatim Package-2B.0 `cohort_two_stage_ebal` (no `factor(stack)`), `maxit=200000`,
  `reltol=1e-12`; the shared pooled `two_stage_ebal()` is untouched.
- Restartable: each cohort writes a verified shard + meta (cohort, keys, input
  path, covariate set, solver settings, gate results) only after passing.
- New versioned config paths added to `11i` (collision-checked):
  `P0H5_COHORT_EBAL_WEIGHTS_PARQUET`, `P0H5_COHORT_EBAL_CC9408_WEIGHTS_PARQUET`,
  `P0H5_COHORT_EBAL_SHARD_DIR`.

## 3. Per-cohort results before halt

| Cohort | Treated deals | Status | firm_raw_meandiff | max full-pooled SMD (constr.) | firm ESS | max firm share |
|---|---:|---|---:|---:|---:|---:|
| 1994 | 3 | PASS (shard written) | ≤1e-4 | ≤0.05 | **81.5** (marginal) | 0.064 |
| 1995 | 4 | **FAIL — firm_ess** | 2.82e-5 ✓ | 1.47e-5 ✓ | **43.57 (<50)** ✗ | 0.084 ✓ |
| (2009, from 2B.0 prototype) | 17 | PASS | 9.25e-8 | 2.03e-7 | 636.3 | 0.013 |

Cohort 1995 gate detail (`..._2b1_cohort_1995_FAILED_gates.csv`): treated weights
≡1 ✓; finite/nonneg ✓; firm raw meandiff 2.82e-5 ✓; inventor raw meandiff 8.50e-6 ✓;
mass discrepancy 8.42e-9 ✓; **max full-pooled |SMD| (constrained) 1.47e-5 ✓** (the
conditional imbalance IS corrected); **firm ESS 43.57 < 50 ✗**; max firm share
0.084 ✓; positive controls/firms present ✓.

## 4. Precise diagnosis — genuine concentration failure, not solver failure

The firm stage **balanced** 1995's covariates (raw meandiff 2.8e-5, full-pooled
SMD 1.5e-5 — excellent), but only by **concentrating** control mass onto an
effective ~44 firms, below the ESS≥50 floor. The binding constraint is
concentration, not balance or convergence.

**Root cause: too few treated deals/firms in the cohort.** 1995 has **4 treated
deals** (≈4 target firms). Matching a handful of target-firm covariate profiles
within a single cohort forces the never-target controls into heavy concentration.
The monotone-ish pattern (firm ESS: 1994/3-deals = 81.5 marginal; 1995/4-deals =
43.6 fail; 2009/17-deals = 636 comfortable) confirms the mechanism — the thin
early cohorts are the fragile region. Cohort 1996 (**1 deal**) would be worse still.

Note on the `WeightIt` "degenerate solution" warning and slow solves (1994 80.2 s,
1995 672.6 s): with so few treated firm-cells the firm-stage problem is near
rank-deficient, so BFGS runs long and WeightIt flags degeneracy — yet the **raw
constraint residuals are ≤3e-5** (balance achieved). This is disclosed, not
described as conventional optimizer convergence; it reflects the thin-cohort
firm-stage difficulty, consistent with the concentration failure.

## 5. What was NOT done (per the failure rules)

- No solver tuning; no covariate/factor dropped to force convergence; no weight
  trimming/capping; no threshold relaxed.
- **No production-candidate weight file assembled or published.**
- Stopped at the first failing cohort and halted the package.
- The completed **cohort_1994 shard** remains in the shard directory, clearly
  labelled as a shard — it is **not** presented as any final design.

## 6. Combined-design verification

Not reached (the build halted at 1995). No assembled full/cc9408 file exists, so
membership/algebraic/combined-balance checks were not run.

## 7. Runtime & memory

| Cohort | load | balance | peak mem |
|---|---:|---:|---:|
| 1994 | 0.6 s | 80.2 s | ~485 MB |
| 1995 | 1.1 s | 672.6 s | ~600 MB |

Memory bounded (<0.6 GB per cohort; one cohort at a time; gc between). Thin-deal
cohorts are slow (near-degenerate firm stage), so a full 17-cohort run would be
substantially slower than the 2009 prototype implied.

## 8. Protected-output integrity

- Frozen `never_target_h5_weights.parquet` and `main_robustness_post_summaries.csv`:
  md5 **identical** to Package-0 baseline.
- Old global nt2010 P0H5 weights: **not written** (mtime unchanged, Jul 20 21:49).
- No P5 file written; `two_stage_ebal()` unmodified.
- Package 2A and 2B.0 outputs: read-only (unchanged; 22 files intact); 11r not run.
- Protected/unrelated files (`12*`, both Verginer checkpoints,
  `00_Discussion_Docs/011_thesis_paper_structure.md`, `AGENTS.md`) untouched.

## 9. Deliverables

- Script: `02_analysis/R/11s_build_nt2010_cohort_ebal_weights.R` (restartable).
- Shard: `nt2010_p0h5_cohort_ebal_shards/cohort_1994.parquet` (+ meta) — diagnostic only.
- Failure diagnostics: `..._2b1_cohort_1995_FAILED_{gates,balance}.csv`,
  `..._2b1_cohort_meta_1994.csv`.
- This checkpoint.
- (No assembled production parquet — correct on failure.)

## 10. Recommendation — request review

The pure cohort-specific method **eliminates the conditional imbalance** (proven at
2009, and 1995's balance gates pass) but is **infeasible at the firm-level ESS≥50
gate for thin-treated-deal cohorts** (1995 fails; 1994 marginal; 1996 at 1 deal is
worse). This is the design tension between the two extremes:

- **Global P0H5**: strong firm ESS (~119) but large within-cohort firm-size imbalance.
- **Fully cohort-specific P0H5**: within-cohort imbalance removed, but firm ESS
  collapses (<50) for thin cohorts.

**I have not chosen or implemented a resolution** (the rules forbid tuning). For
review to decide, candidate directions (each a new, separately-approved package)
include, without preference:

1. **Partial pooling / hierarchical constraints** — shrink each cohort's balance
   targets toward the pooled solution, strongest for thin cohorts, trading a
   little within-cohort balance for ESS.
2. **Feasibility-gated hybrid** — cohort-specific where it passes all gates;
   an explicit, documented fallback for thin cohorts (noting the estimand caveat).
3. **Era-level balancing** — solve within the four never-target eras instead of
   single years (more treated firms per solve; coarser conditioning).
4. **Firm-stage covariate parsimony for thin cohorts only** — a reduced firm
   covariate set to relieve concentration (explicitly a change of method, not an
   ad-hoc drop-to-converge).

Do **not** proceed to Package 3A, and do **not** substitute P5, until a direction
is approved. If useful, I can run a **read-only diagnostic scan** (separately
approved) that solves each cohort's firm stage to enumerate exactly which cohorts
pass/fail the ESS gate and their margins, to size the problem before choosing a fix.

---

## Addendum (2026-07-21, from Package 2B.3): ESS gate scope

The `ROBUST_MIN_ESS = 50` gate is, in the frozen implementation, a **full-design**
gate: `positive_concentration()`/`gate_inventor()` apply it to the control
firm-mass distribution aggregated across the **complete specification**, not
per cohort. The per-cohort firm ESS used here (and in 2B.0/2B.2) is an **additional
conservative diagnostic** introduced during the conditional-balance investigation.
So the halt at cohort 1995 (per-cohort firm ESS 43.6) was a **conservative-diagnostic**
trip, **not** a violation of the original full-design ESS gate. The assembled
cohort-specific design's spec-wide firm ESS was never evaluated. Whether
cohort-specific is feasible under the **original** full-design ESS gate remains
**open** and is a live option for review (Package 2B.3 §6, option 1). The exact
within-cohort balance it delivers is not achieved by any other design tried.
