# nt2010 — Package 02A Conditional-Balance & Support Diagnostic

Date: 2026-07-21
Scope: diagnose within-cohort (conditional) balance and support for the four
nt2010 weighted designs. **No reweighting, no outcomes, no estimation, no change
to saved weights or thresholds.** Aggregation-first (DuckDB); the 4.5M-row panel
is never collected into R.

## 0. Verdict

**Substantive conditional imbalance found** (not a thin-cohort standardisation
artifact). Global entropy balancing (max |SMD| ≈ 2e-6) conceals large
**within-cohort** imbalances on **firm-size / patent-intensity** covariates that
remain material under the full-specification pooled SD. Per the pre-set rule,
this routes to **Package 2B** (propose memory-feasible cohort-specific
corrections). P0H5 stays the pre-specified primary; **P5 is not promoted** despite
balancing more easily. No solver was re-run.

## 1. Method (aggregation-first, numerically stable)

One grouped DuckDB scan per spec (weights ⨝ roster) produces wide sufficient
statistics at `cohort × arm`: `sum(w)`, `sum(w²)`, counts, and per covariate
`sum(w·x)` and the **centered** `sum(w·(x − m_cohort_arm)²)` (centering done
inside a CTE to avoid catastrophic cancellation). Cohort → era → full variances
are pooled via the **parallel-axis identity**, reproducing the frozen
`smd_weighted` denominator (treated weighted SD) exactly. Firm concentration is a
separate grouped query at `cohort × control-firm` grain. 14 balance variables
(`FULL_NUMERIC_COVARS`); the existing cohort/era maxima were over the 9
continuous, verified against those.

Runtime/memory (complete data): 4.8–6.9 s per spec, ~143–147 MB peak R memory.
Panel never materialised in R (largest R object = the firm-mass table, ≤93k rows).

## 2. Pilot (2A.0) — P0H5, cohort 2009

- Driver of the 2009 maximum: **`log_firm_inventor_count`**.
- Reproduced |SMD| = **1.923181** vs existing 1.923181 (**rel err 5.5e-13**).
- Raw weighted-mean diff = **−1.778** (log inventor count ⇒ ≈ 6× firm-size gap);
  denominator (treated weighted SD) = 0.924; full-pooled SMD = **−0.967**.
- Elapsed 0.3 s; approx peak R mem 87 MB; panel not collected. **Pilot passed.**

## 3. Reproduction verification (2A.1)

**78/78 group maxima reproduced** (rel tol 1e-3; well-conditioned groups far
tighter). Three cohorts (1996 in P0H5/P5, 1994 in P5) are **machine-epsilon
denominator collapses** (a covariate is (near-)constant among treated ⇒
within-cohort variance at 4e-17…1e-14 ⇒ SMD mathematically undefined). Both the
frozen in-memory `smd_weighted` and this method produce numerically meaningless
values there; they are flagged, not treated as reproduction failures. Real
conditional imbalances are O(0.1–3); any |SMD| > 100 is a collapse artifact.

## 4. Which covariates drive the large SMDs

Per-cohort maxima for the **primary P0H5_nt2010** (covariate | raw diff |
within-cohort SMD | full-pooled SMD | class):

| Cohort | Driver | Raw diff | Within SMD | Full-pooled SMD | Class |
|---|---|---:|---:|---:|---|
| 1994 | share_formulation | 0.009 | 1.26 | 0.11 | artifact (tiny denom, negligible) |
| 1995 | log_patents_early | 0.495 | 2.59 | 0.25 | borderline |
| 1996 | share_formulation | 0.036 | 8.6e14 | 0.46 | collapse artifact (modest real 0.46) |
| 1997 | share_small_molecule | −0.074 | −0.99 | −0.42 | substantive |
| 1998 | log_firm_patent_stock | −1.06 | −0.99 | −0.50 | **substantive** |
| 1999 | share_biotech | −0.091 | −1.19 | −0.50 | substantive |
| 2000 | log_patents_recent | 1.75 | 0.99 | 0.93 | **substantive** |
| 2001 | log_patents_recent | −1.47 | −1.19 | −0.78 | **substantive** |
| 2002 | log_firm_inventor_count | −1.83 | −2.03 | −0.99 | **substantive** |
| 2003 | share_small_molecule | 0.072 | 0.56 | 0.41 | substantive |
| 2004 | log_patents_early | 1.19 | 0.64 | 0.60 | **substantive** |
| 2005 | share_formulation | −0.018 | −0.54 | −0.23 | mild |
| 2006 | log_patents_recent | −0.67 | −0.55 | −0.35 | substantive |
| 2007 | log_firm_inventor_count | −2.21 | −2.23 | −1.20 | **substantive** |
| 2008 | log_patents_recent | −1.34 | −1.09 | −0.71 | **substantive** |
| 2009 | log_firm_inventor_count | −1.78 | −1.92 | −0.97 | **substantive** |
| 2010 | log_firm_inventor_count | −1.17 | −0.99 | −0.64 | **substantive** |

Era maxima (P0H5): 1994–99 `log_patents_recent` full-pooled 0.24; 2000–04
`log_patents_recent` 0.34; 2005–08 `log_patents_recent` 0.42; **2009–10
`log_firm_inventor_count` 0.74**. Full driver list: `..._2a_max_smd_drivers.csv`.

**Pattern**: the dominant drivers are `log_firm_inventor_count`,
`log_patents_recent`, `log_firm_patent_stock`, `log_patents_early` — firm-size and
patent-intensity. Treated (target) firms are systematically **smaller / less
patent-intensive within a cohort** than the reweighted never-target controls,
with raw log differences of 1–2.2 (≈3×–9×) that remain material (full-pooled SMD
0.5–1.2) under the design's own pooled standardisation. Worst in 2002, 2007,
2009 and the 2009–2010 era, but **pervasive across the whole 1994–2010 window** —
so this is not specific to the thin new cohorts.

## 5. Raw vs within-cohort vs full-pooled

The within-cohort SMD (treated-SD denominator) is inflated relative to the
full-pooled SMD when the within-cohort treated SD is small, and explodes at
machine epsilon (1996, 1994-P5). But the **full-pooled** SMD — immune to
within-cohort denominator collapse — still shows material conditional imbalance
(0.4–1.2) in ~13 of 17 P0H5 cohorts. Only 1994 (0.11) and 2005 (0.23) are
conditionally well balanced. The large numbers are therefore **not merely a
standardisation artifact**: a real, economically meaningful within-cohort
firm-size gap underlies them.

## 6. Cohort/era support and concentration

**Support is ample — the imbalance is not a support problem.** Per cohort: 3,059–
7,104 positive-weight control firms; max control-firm weight share 3.4–4.4%; top-5
share 13–17%; inventor-weight ESS 47k–128k. So thousands of control firms are
available in every cohort.

**Firm-level ESS (fragility diagnostic)** — effective number of control *firms*
carrying the cross-cohort mass:

| Grain | P0H5_nt2010 firm ESS | P5_nt2010 firm ESS |
|---|---:|---:|
| full (all cohorts) | **118.8** | 3821.3 |
| era 1994–99 | 118.1 | 2094.0 |
| era 2000–04 | 114.6 | 3056.6 |
| era 2005–08 | 113.8 | 3728.9 |
| era 2009–10 | 115.3 | 3607.1 |

P0H5's ~119 firm ESS (11,256 firms available) passes the ROBUST_MIN_ESS = 50 gate
but is a genuine **fragility**: the inventor-weighted control comparison
effectively rests on ~119 firms. Treated as a fragility flag only — **the
feasibility threshold is not redefined after the fact.** P5's deal-weighting
spreads mass across ~3.8k effective firms (max share 0.17%), which is why it
"balances more easily"; this is not grounds to promote it.

Root cause: the two-stage global ebal targets the **pooled** treated moments;
`factor(stack)` balances only stack *mass*, not stack×covariate interactions.
Treated firm-size composition drifts across cohorts, so global reweighting cannot
match each cohort → residual within-cohort firm-size imbalance despite ample
support.

## 7. Classification (per the rule)

- **Standardisation artifacts** (retain & report; do not change threshold):
  cohort **1996** (P0H5 `share_formulation`, P5 `share_formulation`) and **1994**
  (P5 `observed_firm_patent_age`) — within-cohort denominator at machine epsilon,
  raw diffs negligible. Note even here a modest real imbalance exists
  (1996 P0H5 full-pooled 0.46). Also mild: 1994/2005 (P0H5), most 2000s P5 cohorts.
- **Substantive conditional imbalance** (dominant): firm-size / patent-intensity
  covariates across most P0H5 cohorts and all eras (full-pooled 0.4–1.2); P5's
  1995 (`log_firm_patent_stock`, full-pooled 1.45) is its worst. Raw differences
  are large and remain material under full-sample standardisation; support is
  ample, so it is a **balancing-scheme** limitation, not a support/thin-cohort one.

## 8. Runtime & memory observations

| Spec | cohorts | suff rows | firm rows | elapsed (s) | ~peak mem (MB) |
|---|---|---|---|---|---|
| P0H5_nt2010 | 17 | 34 | 93,256 | 6.9 | 144 |
| P5_nt2010 | 17 | 34 | 93,256 | 6.0 | 147 |
| P0H5_cc9408 | 15 | 30 | 79,065 | 4.8 | 143 |
| P5_cc9408 | 15 | 30 | 79,065 | 5.0 | 143 |

Aggregation-first held: no full raw diagnostic panel collected; DuckDB streamed
the grouped scans; R held only ≤93k-row aggregates. No `covariate × factor(stack)`
model matrix constructed.

## 9. Outputs (versioned; NT2010 audit prefix)

`main_did_v1_nt2010_2a_{conditional_balance[,_<spec>], support[_<spec>,_concentration],
max_smd_drivers, pilot_p0h5_2009, reproduction_check, runtime_resource_log}.csv`
(14 files). No Package 0–2 output overwritten.

## 10. Verification

- Pilot reproduces P0H5–2009 max (rel err 5.5e-13). ✔
- Aggregated method reproduces all 78 cohort/era maxima within tol (collapses
  flagged). ✔
- All four specs diagnosed exactly on complete data. ✔
- No complete raw diagnostic panel collected into R (peak ~145 MB). ✔
- Output paths versioned and collision-free. ✔
- `11q` parses. ✔
- Frozen parquets, result CSVs, figures unchanged (md5 spot-checks identical;
  nt2010 weights read-only). ✔
- Protected/unrelated files (`12*`, Verginer checkpoints,
  `00_Discussion_Docs/011_thesis_paper_structure.md`, `AGENTS.md`) untouched. ✔

## 11. Recommendation

**Package 2B is required** (substantive conditional imbalance). Proposed
direction (for 2B review, not implemented here): sequential, memory-feasible
**cohort-specific entropy-balancing** for P0H5 — re-solve balance within each
treatment cohort (or add cohort×covariate constraints) so the never-target
controls match treated firm-size/intensity *within* cohort, not just pooled. A
prototype would start with P0H5–2009, **only after explicit approval**. Do not
promote P5; do not re-run a global solver. Package 3A does **not** proceed until
2B is reviewed.
