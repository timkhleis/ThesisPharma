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

## 6. Never-observed-target control feasibility (rev. 5)

**Question:** does opening the control pool to firms **never observed as an acquisition target**
(they *may* be acquirers) restore support for the **inventor-weighted** ATT, before we abandon it for
deal-weighting?

**Universe (target-side, pre-deal only).** After the reviewer's correction (exclude only
`target_group` + `target_group_pre` + the target company's `firm_group` id **at deal_year−1**; **drop
`target_group_post` and the ±2y window**, both of which capture the merged/acquirer group and were
wrongly re-excluding acquirers), ever-target groups fall 903→**646** and the universe grows to
**13,978 never-observed-target pharma groups**. Latest-affiliation assignment over `[g-5,g-1]` →
**3,721,005 control inventor-units** across **79,087 group×stack cells**; firms reach **10,313
inventors**. Cleanliness drops (any prior `deal_year<g` or competing `[g,g+3]` real target) ≈ 40k.

**Firm-stage support comparison** (inventor-weighted target, stack indicators, standardized covariates;
convergence tol relaxed to 1e-4 per reviewer; ESS≥50 / max-firm≤10% are warnings):

| spec | max \|SMD\| pre→post | unique-firm ESS | max single-firm wt | converged | gate |
|---|---|---|---|---|---|
| future_g7 | 0.67 → **1.31** | **1.0** | 100% | no (0.90) | **FAIL** |
| never_target | 0.84 → **9e-5** | **102.7** | **4.0%** | yes (4e-5) | **PASS** |
| hybrid | 0.84 → **3e-5** | **103.3** | 4.0% | yes (2e-5) | **PASS** (≈never_target) |

**Findings (the correction flips the conclusion).**
- **Never-target fully restores support**: max \|SMD\| 0.84→9e-5; unique-firm ESS **1 → 102.7** (clears
  the strict ≥50); max single control-firm weight **4.0%** (clears the strict ≤10%); no empty stack.
- **~42% of control weight comes from acquirer firms** — the earlier "≈0" was precisely the target-history
  bug (post/deal-year mapping re-excluded acquirers). Big pharma acquirers are large *and* never-targets,
  and they supply much of the needed size support.
- **Weighted controls are technologically relevant — no pharma filter needed**: entropy-weighted
  never-target pharma-core = **0.431 vs treated 0.458**; only **12.6% of post-weight mass** is in
  <5%-pharma firms (vs 51% *unweighted*) — ebal down-weights the distant giants automatically. (The
  reviewer was right to judge relevance on weighted, not unweighted, mass.)
- **Hybrid ≈ never-target**: g+7 keeps 108 of ~25,524 mass units (~0.4%) — the g+7 pool is redundant once
  never-target firms are available.

**Stage 2 — full two-stage balance (never-target, 3.75M units, 10.9 min).** The complete firm→inventor
balance **confirms the firm-stage result**: both stages converge (firm meandiff 2.9e-5, inventor 4.1e-6);
**all 14 firm+inventor covariates balance to ~1e-5** (large unweighted diffs — firm size −0.59 to −0.86,
tech shares +0.8 to +1.57, exclusivity −0.20 — all driven to ~1e-6); **unique-firm ESS 101.7** (survives
Stage 2), **max single-firm weight 4.2%**, top-5 16.9%. Even the inventor covariates that were somewhat
imbalanced unweighted (exclusivity −0.20, tenure −0.08) are perfectly balanced after Stage 2.

**Recommendation.** Never-target (inventor-weighted) is a **credible primary control pool**: it passes the
strict pre-registered gate at both the firm stage *and* the full two-stage, is technologically relevant
post-weighting (weighted pharma-core 0.43 vs treated 0.46), is not driven by a single firm (max 4.2%,
top-5 16.9%), and holds ESS ~102 unique firms. **The inventor-weighted ATT is retained as feasible.** The
only remaining pre-decision check is **event-study pre-trends**, which requires building the outcome panel
(11d) + event study (11e) on the never-target arm — the authorized next step. Deal-weighting remains a
major alternative specification, not the automatic default.

*Stage-2 audit:* `never_target_stage2_diagnostics.csv`, `never_target_stage2_balance.csv`,
`never_target_stage2_stack_ess.csv`; weights → `main_did_v1_never_target_weights.parquet`.

**Audit trail:** `never_target_support_comparison.csv`, `never_target_top_donors_{never_target,hybrid}.csv`,
`never_target_weighted_relevance_*.csv`, `never_target_tech_relevance_audit.csv`.

---

*Reproduce:* `Rscript 02_analysis/R/11b_build_main_sample.R` (sample/census/covariates, g+7 arm) →
`11f_never_target_arm.R` (never-target arm + audits) → `11g_support_comparison.R` (firm-stage
comparison + decision gate → `results/main_did_v1/never_target_support_comparison.csv`).
`11c_balance_main_sample.R` runs the g+7 two-stage (self-test passes; stops at the convergence gate
under inventor-weighting, by design). Requires `WeightIt` + `cobalt` in `.r_libs`.
