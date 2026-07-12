# Pre-Commitment Thresholds for Mechanical-Artifact Diagnostics

**Date:** 6 July 2026  
**Session:** Three-diagnostic triage (Diagnostics 1, 2, 3 — mechanical artifact vs. genuine timing selection)  
**Recorded by:** Claude Code (session record)

---

## Overview

Three diagnostic tests are designed to triangulate whether the observed pre-trend hump at event-time −3/−4 (magnitude ~+0.05 on active-patenting) is:
1. A mechanical artifact of cohort-construction mechanics (requiring panel redesign), or
2. Genuine Ashenfelter-mirror timing selection (requiring bounding/modeling), or
3. A mixture of both (requiring staged fixes).

Before running any diagnostic, the following thresholds and design decisions are pre-committed (not data-dependent).

---

## Threshold 1: Diagnostic 3 (Disjoint-Window Intersection Test) — Covariate Substitution Window

**Decision:** Substitute *only* the productivity covariate (`log_predeal_patent_stock`), relocating its measurement window to `[deal_year-10, deal_year-6]`, holding all other covariates, population, and outcomes fixed.

**Rationale:** The suspect `[deal_year-5, deal_year-1]` window appears in two places: (1) the cohort-inclusion rule (confounds who enters the sample), and (2) the productivity covariate. If the pre-trend is mechanical, it requires these two to share calendar years. Relocating the covariate one full non-overlapping window-length back (same 5-year span, zero calendar overlap with the tested pre-period) breaks that structural dependence while keeping the covariate a like-for-like "5-year patent stock" measure. If the hump shrinks when this overlap is removed, the mechanical channel is material.

**Pass/fail:** If the −3/−4 coefficient shrinks by **more than 50%** under the alternate covariate (or loses significance), evidence supports the mechanical-artifact hypothesis. If materially unchanged, the hump isn't primarily a covariate-overlap artifact.

---

## Threshold 2: Diagnostic 2 (Never-Treated Placebo) — Covariate Strategy

**Decision:** Run the placebo CS(2021) estimation twice in parallel:
- **Arm A (drop):** `xformla` without `log_deal_value` (documented deviation from real spec).
- **Arm B (borrow):** `xformla` with `log_deal_value` borrowed from the real deal used to size the placebo block.

Report both dynamic-ATT sets side by side. Flag if they materially disagree (indicating the deal-value covariate is doing real work in the DR estimator, requiring further investigation post-diagnostics).

**Rationale:** `log_deal_value` is a real financial-market property with no placebo analogue. Borrowing it from a size-matched real deal implicitly asserts a headcount-to-valuation mapping that cannot be independently justified. Running both arms surfaces whether this covariate choice materially affects the placebo coefficients, rather than silently picking an arbitrary default.

**Pass/fail:** If both arms agree (hump magnitude, shape, and significance near-identical), the choice is low-risk. If they materially diverge, the issue is flagged for post-diagnostic review; do not resolve further this pass.

---

## Threshold 3: Diagnostic 2 (Never-Treated Placebo) — Pre-Flight Symmetry Check

**Decision:** Mandatory hard checkpoint before reading any `att_gt()` coefficient. Compare pre-period (event-time ∈ [−5, −1]) activity profiles between real and placebo cohorts on their respective common-support matched samples.

**Divergence criterion:** Abort further interpretation if, at *any* event-time in [−5, −1], the absolute difference between real and placebo mean `active_patenting` exceeds **0.025** (or equivalently, the proportional analog for `log_patent_count` derived from the real 08h hump magnitude).

**Rationale:** If the placebo cohort's baseline pre-window activity differs from the real cohort by more than half the effect size being diagnosed (~0.05 hump → 0.025 threshold), the placebo is not maximally symmetric and any hump (or flatness) cannot be attributed to the construction mechanism rather than to an off-baseline mismatch. This threshold enforces the "maximum construction symmetry" principle central to the placebo design.

**Implementation:** Print a loud, impossible-to-miss warning (not a hard `stop()`) if breached — the fit is still saved for the record but flagged as compromised. Divergence findings go to Cassi before proceeding with panel redesign.

---

## Rationale Chain

1. **Diagnostic 1** (qualifying-year split): Shows whether the hump's peak event-time "fingerprint" tracks individual inventors' own qualification timing (mechanical signature) or is synchronized across all inventors (genuine selection).
2. **Diagnostic 2** (never-treated placebo): Shows whether the hump emerges in a construction-identical scenario with zero real treatment (establishing mechanical plausibility).
3. **Diagnostic 3** (disjoint-window covariate): Shows whether the hump's magnitude changes when the suspected overlapping covariate window is relocated, isolating the mechanical channel's contribution on the real treated population.

**Triangulation:** If all three agree (fingerprint present, placebo hump reproduced, real hump shrinks under disjoint covariate), mechanical construction is the primary driver. Donor-pool restriction + IPW become **confirmatory**, and the panel should be rebuilt on the disjoint rule. If they disagree, the disagreement itself is the finding — report to Cassi.

---

## Sign-off

These thresholds are recorded *before* any diagnostic is run, per the project's pre-registration discipline. They are not data-dependent and will not be revised based on preliminary results.

**Approved by:** Claude Code (session record), 6 July 2026  
**Context:** Supervisor meeting follow-up (Prof. Gagnepain); resolution of methodological fork requiring expedited triage before further specification work.

---

## Addendum (9 July 2026): Heterogeneity pre-registration

The trajectory-matched FN pooled effect is a small, transitory, near-zero-at-the-mean result on active_patenting / patent count / forward citations. Per the standing discipline, the following subgroup splits and **predicted signs are recorded before running the heterogeneity**, to prevent post-hoc sign-fishing.

**Split 1 — Pre-deal productivity quartiles (Q1 low … Q4 high, on `log_predeal_patent_stock`), trajectory-matched FN within each quartile.**
- **Predicted pattern (incentive-restructuring / star-disruption mechanism):** the post-acquisition decline is *monotonically more negative in higher productivity quartiles* — Q4 (pre-deal high-productivity inventors) most negative, Q1 least. Rationale: reduced autonomy and changed internal incentives bind hardest on the most productive inventors, whose pre-deal output had the most room to fall.
- **Reading rule:** report all four quartiles regardless of outcome. A monotone Q1→Q4 gradient with Q4 significantly negative is the pre-registered confirmation. A flat/null gradient is reported as such (no cut is dropped). Multiple-testing acknowledged: the *pattern* (monotone gradient), not any single significant cell, is the evidential unit.

**Split 2 — DealSim terciles (to run after DealSim is built).** Pre-registered prediction is the inverted-U already in CLAUDE.md: low and high terciles significantly negative, middle ~0. Recorded here for completeness; not run this pass.

These predictions are fixed before estimation and will not be revised based on output.
