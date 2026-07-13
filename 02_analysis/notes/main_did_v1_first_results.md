# Main acquisition DiD v1 — first results memo

**Status:** sample build (11a–11b) complete and certified; two-stage entropy
balancing (11c) implemented and run — it surfaced a **feasibility finding that
requires a design decision** before the panel/estimation stages (11d–11e) are wired.
Nothing is corrupted; the pipeline stops cleanly at the balancing gate.

**Design recap.** Full pre-deal inventor cohort (inventors affiliated with a target
in `[g-5,g-1]` before announcement year `g`), Fadlon–Nielsen future-treated **g+7**
controls on an aligned placebo clock, `stack^event_time` fixed effects, two-stage
entropy balancing (firm then inventor), event window `t=-5..+3`, outcomes = active
patenting / patent count / 5y forward citations, anticipation δ∈{0,1}. Estimand as
briefed: **inventor-weighted** ATT (firm sampling weight = its qualifying-inventor count).

---

## 1. Sample build — all gates pass

| Item | Result |
|---|---|
| **Treated cohort** | 25,524 inventor-deal units, **290 deals**, g∈1994–2008 |
| **4a membership certification** | row-for-row match vs `cs2021_estimation_panel` (only_in_new = 0, only_in_cs = 0) ✓ |
| **4b covariate certification** | max abs diff = 0 for career age / log stock / log group; IPC match = 1.00 ✓ |
| **g+7 controls** | 10,952 qualified → **10,630 retained** (253 deals) after cleanliness |
| **Control:treated ratio** | **0.42** (L=7); 0.33 (L=9) |
| **Covariate missingness** | **zero** across all firm + inventor covariates |

**Control cleanliness (lineage-aware, non-exclusive counts):** prior inventor exposure
122, competing inventor exposure 58, firm-as-acquirer event 168, prior firm-target deal 6,
competing firm-target deal 0. Total dropped 322/10,952 (~3%).

**Placebo-group identity [addresses the reviewer's blocker 3].** Of 478 resolvable deals:
**424 unique**, 41 ambiguous (excluded), 13 missing (excluded). For **all 424 unique cases
the placebo-time group (g−1) equals the deal-time group** — the "groups are stable" branch
is empirically confirmed. 48 deals show pre-period (g−6..g−1) group instability, so it was
a genuine test, not a trivial identity.

**Emerging-firm handling [B2].** 335 control + 55 treated units sit at firms with no patents
through g−3; retained via `no_firm_patent_by_g3` / `no_technology_activity_g6_g3` indicators
rather than dropped.

---

## 2. The imbalance is large and mega-deal-concentrated

Pre-balance, **inventor-weighted** firm |SMD| (standardized):

| covariate | |SMD| | covariate | |SMD| |
|---|---|---|---|
| log firm inventor count | 0.66 | firm patent age | 0.55 |
| no firm patent by g−3 | 0.63 | log patents early | 0.50 |
| log patents recent | 0.63 | share small molecule | 0.34 |
| log firm patent stock | 0.60 | share biotech | 0.29 |
| no tech activity g6–g3 | 0.51 | share formulation | 0.14 |

Treated firms are systematically **larger**; inventor-level covariates are already close
(career-age diff 0.33, tenure 0.21, log stock −0.03, exclusivity −0.01 — all in raw units).

**Concentration:** the **top-10 treated deals hold ~50%** of all treated inventors (top-5 =
36%). Treated firm size reaches **2,422** qualifying inventors; the largest control firm is
**1,501**. So under inventor weighting the estimand is dominated by a handful of mega-mergers
for which no comparably large control firm exists.

---

## 3. Balancing feasibility — the finding

Two-stage entropy balancing **as specified (inventor-weighted) is effectively infeasible**:
matching the mega-deal-dominated target forces the optimizer to collapse the control mass
onto ~1 firm. A **deal-weighted** firm stage balances cleanly. Firm-stage `ebal` variants
(exact mean balance; standardized covariates; maxit = 20,000):

| firm-stage spec | balances? | control ESS | notes |
|---|---|---|---|
| **inventor-wtd + stack** (current primary) | ✗ degenerate | **1 (0.4%)** | 252/253 controls → 0 weight |
| inventor-wtd, no stack | ✗ | 5 (1.8%) | still collapses |
| **deal-weighted + stack** | ✓ exact (SMD 0.000) | **109 (43%)** | clean, min weight 0.012 |
| deal-weighted, no stack | ✓ exact | 159 (63%) | clean, min weight 0.173 |
| inventor-wtd, s.weights capped at p90 + stack | ✓ exact | 27 (11%) | feasible but noisy |
| reduced 5 covars + stack, inventor-wtd | ✗ | 0 | dropping covars does not rescue it |

(ESS = Kish effective sample size of the 253 control firms; % of 253.)

---

## 4. Interpretation & recommendation

- The infeasibility is driven **specifically by inventor weighting**, not by the covariate
  set or the stack indicators (dropping either does not rescue it; dropping covariates makes
  it worse). It reflects a real **lack of control support** for the few mega-deals that
  dominate the inventor-weighted target.
- **Deal-weighted balancing is clean** (exact SMD, 43% ESS with stack indicators, 63% without).
  The deal-weighted ATT — each acquisition counts equally — is arguably the more defensible
  headline anyway: it is not hostage to 2–3 mega-mergers with no comparable controls.

**Recommendation:** make **deal-weighted + stack indicators** the primary firm-stage weighting
(ESS 43%); report **capped-inventor-weighting (p90)** as a sensitivity (ESS ~11%); and state
the mega-deal concentration explicitly as a scope/limitation of any inventor-weighted estimand.

## 5. Open questions for review (Fable / GPT-sol)

1. **Estimand:** adopt deal-weighted as primary, or insist on inventor-weighted and accept the
   capped-p90 version (ESS ~11%, noisy)? The brief made inventor-weighted primary; the data
   inverts the feasibility ordering.
2. **Stack indicators at the firm stage:** keep (ESS 43%, guarantees weighted cohort-year mass
   matches) or drop for power (ESS 63%), reporting per-stack/era balance as diagnostics either way?
3. Is the mega-deal concentration (top-10 deals = 50% of treated inventors, no comparable
   control firms) better framed as (a) a reason to prefer deal-weighting, (b) a motivation for
   a size-restricted subsample, or (c) both?
4. Anything in the control-cleanliness or placebo-group logic you'd tighten before we commit to
   the weighted panel and estimation (11d–11e)?

---

*Reproduce:* `Rscript 02_analysis/R/11b_build_main_sample.R` (sample + census + covariates →
`output/audit/main_did_v1/`, `output/parquet/derived/main_did_v1_units.parquet`), then
`Rscript 02_analysis/R/11c_balance_main_sample.R` (self-test + balancing; currently stops at the
gate under the inventor-weighted spec). Requires `WeightIt` + `cobalt` in `.r_libs`.
