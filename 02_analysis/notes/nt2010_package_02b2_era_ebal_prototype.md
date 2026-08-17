# nt2010 — Package 02B.2 Era-Level Ebal Prototype (1994–1999) — INSUFFICIENT

Date: 2026-07-21
Scope: prototype uniform ERA-level P0H5 entropy balancing for the pre-specified
never-target era 1994–1999 (6 cohorts), with within-cohort validation. Isolated
diagnostic; shared `two_stage_ebal()` reused UNCHANGED on the era subset. No
outcomes/citations/annual-states/DiD. **Result: FAIL — era-level is insufficient.**

## 0. Verdict

Era-level balancing **passes every era-level gate** (including firm ESS 84.6 ≥ 50 —
it does not have the cohort-specific concentration failure) but **fails the
within-cohort balance gate in all six cohorts** (constrained max full-pooled |SMD|
0.30–0.79 ≫ 0.05). Critically, the era within-cohort imbalance is **comparable to
or worse than the old global design** — era pooling does **not** improve
conditional balance; it merely reproduces the pooled design's within-cohort
imbalance at a smaller scale. Per the pre-set rule, era-level balancing is
**classified insufficient** (within-cohort checks not weakened, era boundaries not
redrawn). **Recommend a formally specified partial-pooling design next.** Package
3A stays blocked; P5 untouched.

## 1. Commands run

```
Rscript 02_analysis/R/11t_prototype_nt2010_era_ebal.R
```
(A cosmetic `a2_worst` lookup bug — the 2A CSV column is `continuous`, not
`constrained`, so all 14 numeric covariates are constrained in P0H5 — was fixed and
the two descriptive CSVs, `2b2_support_map.csv` and `2b2_comparison_*`, were
regenerated from existing artifacts without re-solving.)

## 2. Method

Era-level balancing == the shared `two_stage_ebal()` (which already includes
`factor(stack)` in both stages) applied to the 1994–1999 subset — so the pooled
solver is reused **unchanged**. Firm stage: `treated ~ FIRM_COVARS + factor(stack)`,
`s.weights = n_qualifying_inventors`; inventor stage adds `INV_COVARS + factors`,
`base.weights = firm_multiplier`. `maxit=200000`, `reltol=1e-12`. Treated weights
≡ 1; no cohort/era mass normalisation. `factor(stack)` preserves each cohort's
treated/control mass separately. Structural audit removed **no** columns.

## 3. Cheap support map (all 17 cohorts; no solve) — the identifiability limit

Treated firm-stage model matrix (`FIRM_COVARS` + intercept = 11 cols) is
**rank-deficient in 15 of 17 cohorts**, because (a) thin cohorts have too few
treated firm cells and (b) ~1–2 firm covariates (the no-history binaries) are
constant among treated firms:

| Cohort | Treated deals | Treated firm cells | firm MM rank (of 11) | 2A worst full-pooled SMD |
|---|---:|---:|---:|---:|
| 1996 | 1 | 1 | **1** | 0.551 |
| 1994 | 3 | 3 | 3 | 0.171 |
| 1995 | 4 | 4 | 4 | 0.713 |
| 1997 | 6 | 6 | 6 | 0.457 |
| 1998 | 10 | 10 | 10 | 0.673 |
| 1999 | 12 | 12 | 10 | 0.499 |
| 2001 | 23 | 23 | 9 | 1.675 |
| 2007 | 46 | 46 | 10 | 1.363 |
| 2000 | 21 | — | **11 (full)** | 0.927 |
| 2004 | 27 | — | **11 (full)** | 0.596 |

Only 2000 and 2004 reach full firm-covariate rank among treated cells. This is the
structural reason cohort-specific balancing must concentrate control mass in thin
cohorts (few treated firm moments to match, but matching them exactly forces a
peaked control reweighting). All treated numeric means lie within control ranges
(no hard unsupported moment).

## 4. Era-level gates — ALL PASS

| Gate | Value | Threshold | Pass |
|---|---:|---:|:--:|
| treated weights ≡ 1 | 0 | <1e-8 | ✓ |
| finite/nonneg | all | — | ✓ |
| firm raw meandiff | 3.46e-5 | ≤1e-4 | ✓ |
| inventor raw meandiff | 1.64e-5 | ≤1e-4 | ✓ |
| era constrained max full-pooled SMD | 3.32e-5 | ≤0.05 | ✓ |
| per-cohort mass discrepancy (max) | 2.85e-5 | ≤1e-4 | ✓ |
| **firm ESS** | **84.6** | ≥50 | ✓ |
| max firm share | 0.049 | ≤0.10 | ✓ |

Era-*aggregate* covariate balance is excellent (3.3e-5) and concentration is
healthy (ESS 84.6; per-cohort within-era firm ESS 71.9–104.3, all ≥50).

## 5. Within-cohort validation — ALL SIX FAIL

Constrained max full-pooled |SMD| per cohort (gate ≤ 0.05):

| Cohort | max full-pooled SMD | firm ESS | max firm share | mass disc. | pass |
|---|---:|---:|---:|---:|:--:|
| 1994 | **0.296** | 104.3 | 0.040 | 5.1e-6 | ✗ (SMD) |
| 1995 | **0.758** | 95.4 | 0.043 | 6.3e-6 | ✗ (SMD) |
| 1996 | **0.637** | 92.7 | 0.043 | 2.8e-5 | ✗ (SMD) |
| 1997 | **0.361** | 83.7 | 0.050 | 7.8e-6 | ✗ (SMD) |
| 1998 | **0.788** | 77.6 | 0.055 | 2.3e-6 | ✗ (SMD) |
| 1999 | **0.401** | 71.9 | 0.056 | 2.6e-5 | ✗ (SMD) |

Every cohort passes ESS, firm-share, and mass gates but **fails the conditional
balance gate**. Full per-covariate within-cohort detail (raw diff, treated-SD SMD +
collapse flags, full-pooled SMD, factor-level differences) in
`2b2_within_cohort_balance.csv`.

## 6. Comparison — era pooling does not help conditional balance

Within-cohort constrained max full-pooled |SMD| (and firm ESS):

| Cohort | old global | cohort-specific | era 1994–1999 |
|---|---:|---:|---:|
| 1994 | 0.171 | — (ESS 81.5) | 0.296 (ESS 104) |
| 1995 | 0.713 | **1.5e-5** (ESS **43.6 FAIL**) | 0.758 (ESS 95) |
| 1996 | 0.551 | — | 0.637 (ESS 93) |
| 1997 | 0.457 | — | 0.361 (ESS 84) |
| 1998 | 0.673 | — | 0.788 (ESS 78) |
| 1999 | 0.499 | — | 0.401 (ESS 72) |

**Era ≈ global on conditional balance (worse in 4 of 6 cohorts), and concentration
was never the problem for pooled designs.** The three regimes map the tension:

- **Global / era (pooled)**: healthy firm ESS (~119 / 72–104) but within-cohort
  imbalance 0.3–1.2 (conditional imbalance unresolved).
- **Cohort-specific**: within-cohort imbalance ≈ 0, but firm ESS collapses (<50)
  for thin cohorts (1995 = 43.6).

No single global/era/cohort solve occupies the feasible region on **both**
dimensions simultaneously.

## 7. Solver convergence (disclosed)

`WeightIt` reports `converged = FALSE` for both stages (the `maxit`-cap flag), but
the raw model-matrix mean differences are 3.46e-5 (firm) and 1.64e-5 (inventor) —
far below `EBAL_CONSTRAINT_TOL`. Disclosed as a max-iteration flag, **not**
described as conventional optimizer convergence; balance is achieved by the raw
residual test.

## 8. Runtime & memory

| Stage | Elapsed | Peak R mem |
|---|---:|---:|
| era load (1994–1999, projected) | 4.8 s | 372 MB |
| firm + inventor balance | **6537.6 s (109 min)** | 3,280 MB |
| diagnostics | 10.6 s | 2,132 MB |

Only 1994–1999 queried; sequential stages; no full-roster collect; 6 GB DuckDB
limit retained (not expanded); peak R memory 3.3 GB (no memory-pressure stop
needed). **Runtime is a serious concern**: 109 min for one era at `reltol=1e-12` on
938k units implies a four-era production build would be very expensive as specified.

## 9. Protected-output integrity

- Diagnostic weights written only to
  `main_did_v1_nt2010_p0h5_era9499_PROTOTYPE_weights.parquet`; **no production
  cohort_ebal file created.**
- Frozen `never_target_h5_weights.parquet`, `main_robustness_post_summaries.csv`:
  md5 identical to Package-0 baseline. Old global nt2010 P0H5 weights untouched
  (mtime Jul 20 21:49). P5 untouched. `two_stage_ebal()` unmodified.
- Package 2A / 2B.0 / 2B.1 outputs and the 1994 diagnostic shard: read-only,
  unchanged. Protected/unrelated files untouched.

## 10. Deliverables

- Script: `02_analysis/R/11t_prototype_nt2010_era_ebal.R`.
- Diagnostic weights: `..._p0h5_era9499_PROTOTYPE_weights.parquet`.
- Audit CSVs: `..._2b2_{support_map, era_gates, within_cohort_gates,
  within_cohort_balance, era_balance, solver_convergence, weight_quantiles,
  comparison_old_vs_cohort_vs_era, structural_removed_columns, runtime_resource_log,
  status}.csv`.
- This checkpoint.

## 11. Recommendation — formally specified partial-pooling design

Era-level balancing is **insufficient**: it inherits the pooled design's
within-cohort conditional imbalance (0.30–0.79) and adds nothing on the dimension
that actually fails. The prototype sequence has now bracketed the problem — pure
pooling leaves conditional imbalance; pure cohort-specific breaks thin-cohort
concentration; era-pooling does neither well.

**Recommend (do not execute) a formally specified partial-pooling design**: solve a
single hierarchical / penalised entropy-balancing problem that targets
**within-cohort** covariate balance with a shrinkage penalty toward a common
solution, strength increasing as a cohort's treated firm-moment support thins
(cf. the rank map in §3). Tuned so thin cohorts borrow strength (keeping firm ESS
≥ 50) while well-supported cohorts approach exact within-cohort balance — i.e., a
continuous interpolation between the two extremes bracketed here, chosen by a
principled criterion rather than after inspecting which cohorts fail.

Per the standing rule, **do not** adopt a cohort-specific/era-level hybrid or
thin-cohort covariate parsimony. The 109-min era runtime also argues for a
solver/complexity review before any production partial-pooling build. Package 3A
remains blocked; P5 remains untouched, pending approval of a partial-pooling spec.

---

## Addendum (2026-07-21, from Package 2B.3): ESS gate scope

`ROBUST_MIN_ESS = 50` is a **full-design** gate in the frozen code (spec-wide
firm-mass ESS), not a per-cohort rule; per-cohort ESS is a conservative diagnostic
added during this investigation. This clarification does **not** change the 2B.2
conclusion: era-level balancing fails on **within-cohort full-pooled SMDs of
0.30–0.79**, independent of any ESS-scope question. Also, per 2B.3, the treated
firm-matrix rank map documents thin/collinear support but does not by itself prove
concentration; concentration is demonstrated by the observed 1995 exact-balance
weights, and no claim is made that a cohort "must" fail before it is estimated.
