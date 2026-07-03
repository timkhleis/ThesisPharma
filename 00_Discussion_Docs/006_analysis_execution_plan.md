# Analysis Execution Plan
## Day-Level Plan: Analysis Completion (3 Weeks) → Writing Transition

**Goal:** Finish all analysis by end of Week 3; begin writing in Week 4.

**Status as of plan start:** Scripts 01–07 complete (data foundation, derived tables, own stayer/leaver classification, deal map, event panel, Table 1 / Figures 1–3 descriptive results). **Not yet started**: TechDrift, DealSim, and CS(2021) (`did` package) estimation — these gate everything else.

---

## Week 1 — Causal Spine: CS(2021) on the Full Cohort (Layer 1)

Highest-risk, highest-priority work. Nothing downstream is publishable until this holds up.

### Day 1 (Monday)
- [ ] Close the open `duckdb -ui` shell before running anything; confirm `.tmp` spill directory clears.
- [ ] Diagnostic query: count deals surviving `1993 ≤ deal_year ≤ 2010`. Record the number — this gates Week 3's DealSim tercile feasibility.
- [ ] Verify/build covariates needed for the CS(2021) doubly-robust propensity score model:
  - Pre-deal patent stock of target group (log, 5-year sum before `deal_year`)
  - Deal size (log `target_value`)
  - Pre-deal target inventor count
- [ ] Check these covariates exist in `deal_map` / `target_cohort_event_panel`, or write the SQL to build them.

**Deliverable:** one diagnostic table (deal counts under restriction) + covariate table joined to the event panel.

### Day 2 (Tuesday)
- [ ] Install/confirm `did` package in project library.
- [ ] Start `08_estimate_cs2021_main.R`. Reshape `target_cohort_event_panel` into the long-panel format `did::att_gt()` expects (idname, tname, gname, yname, xformla).
- [ ] First working call to `att_gt()` on patent count outcome, `control_group = "notyettreated"`, `est_method = "dr"`.

**Deliverable:** script runs end-to-end without error on patent count.

### Day 3 (Wednesday)
- [ ] Add `clustervars = "deal_id"` (inventors are nested within deals — cluster at deal level, not inventor level).
- [ ] Add `xformla` with the three covariates from Day 1.
- [ ] Repeat for `active_patenting` outcome.
- [ ] Sanity-check group-time ATT estimates against the descriptive Figure 1 pattern already built in `07_build_figures.R`.

**Deliverable:** `att_gt()` results object for both outcomes, covariates included, deal-level clustering confirmed.

### Day 4 (Thursday)
- [ ] Run `aggte(type = "dynamic")` to get the event-study aggregation, t = −5 to +5.
- [ ] Plot the event-study figure with confidence intervals.
- [ ] Run the formal joint pre-trend test (all pre-period ATTs = 0). Record the p-value — this goes in the main table header, not a footnote.

**Deliverable:** event-study figure + pre-trend test p-value.

### Day 5 (Friday)
- [ ] Placebo timing test: shift all `target_year` values by +3 and −3, re-run the Day 3 spec, plot resulting ATTs.
- [ ] **Decision gate**: do pre-trends hold (p > 0.1) and does the placebo test show flat ATTs?
  - **If yes** → proceed to Week 2 as planned.
  - **If no** → switch to the t = −2 terminal pre-period fallback spec (already documented in CLAUDE.md) — do not improvise a new fix under time pressure.
- [ ] Write a half-page summary of Week 1 results for your own record (and for the next Cassi meeting).

**Deliverable:** placebo test results + go/no-go decision recorded in writing.

---

## Week 2 — Stayer Analysis + Selection Diagnostics (Layer 2)

### Day 6 (Monday)
- [ ] Build `Quality_it`: aggregate OECD PQII composite score from `patent_inventor_enriched`, collapsed to inventor-year.
- [ ] Build `TechDrift_it`: cosine similarity of inventor's current-year IPC vector vs. pre-deal career-baseline IPC vector, from `inventor_ipc_year`.
- [ ] Validate both variables on a handful of known inventors (spot check, not full audit).

**Deliverable:** two new inventor-year columns, validated.

### Day 7 (Tuesday)
- [ ] Re-run the Week 1 `att_gt()` machinery restricted to `T_STAYER`, for patent count.
- [ ] Repeat for `Quality_it`.
- [ ] Repeat for `TechDrift_it`.
- [ ] Label all three explicitly as descriptive ATTs (per the identification caveat — `T_STAYER` is post-treatment).

**Deliverable:** three stayer-restricted ATT estimates with event-study plots.

### Day 8 (Wednesday)
- [ ] Build the stayer selection table: pre-deal patent count distribution (mean, SD, quartile shares) for `T_STAYER` vs. `T_LEAVER`, same deals.
- [ ] Run a formal test of the difference (t-test or rank-sum).
- [ ] Write one paragraph interpreting the sign: does the gap suggest positive or negative selection into staying?

**Deliverable:** Table 2 (selection table) — this is a required result, not a side check.

### Day 9 (Thursday)
- [ ] Implement Lee (2009) trimming bounds for the stayer ATT (patent count, and quality if time allows).
- [ ] Time-box to one day: if no R package fits cleanly, implement the trimming logic directly — it is a few dozen lines.
- [ ] Report bounds alongside the naive stayer ATT from Day 7.

**Deliverable:** Lee bounds table.

### Day 10 (Friday)
- [ ] Robustness: re-run the Week 1 main spec with `control_group = "nevertreated"`.
- [ ] Compile placebo test results from Day 5 into a clean robustness table.
- [ ] Write a half-page Week 2 summary.

**Deliverable:** never-treated robustness comparison + consolidated placebo table.

---

## Week 3 — DealSim Heterogeneity + Consolidation (Layer 3)

### Day 11 (Monday)
- [ ] Build `DealSim`: cosine similarity between target and acquirer `group_ipc_year` vectors, pre-deal window.
- [ ] Exclude the 15 placeholder-acquirer deals (`999xxxx` IDs, zero IPC data).
- [ ] Check deal count per DealSim tercile using the Day 1 restricted-sample number. Rule of thumb: flag any tercile under ~30–40 deals as too thin to trust on its own.

**Deliverable:** DealSim variable built + tercile sample-size check recorded.

### Day 12 (Tuesday)
- [ ] Split deals into DealSim terciles.
- [ ] Re-run CS(2021) ATT separately within each tercile (or extract from a stratified spec).
- [ ] Plot ATT by tercile — the main heterogeneity visual.

**Deliverable:** Figure: tercile-bin ATT plot.

### Day 13 (Wednesday)
- [ ] Extract deal/cohort-level ATT estimates via `aggte(type = "group")`.
- [ ] Run the second-stage WLS: regress deal-level ATTs on DealSim + DealSim².
- [ ] Check sign pattern (positive on DealSim, negative on DealSim²) and compute the estimated peak.

**Deliverable:** quadratic test table + estimated peak value.

### Day 14 (Thursday)
- [ ] Spline robustness (2 knots at tercile breaks) — check sensitivity to the quadratic functional form.
- [ ] If time allows: BvD financial controls as a heterogeneity check (deal size, target R&D intensity).
- [ ] Verginer-style matching: optional, only if Weeks 1–2 finished on schedule. Do not let this slip the deadline.

**Deliverable:** spline robustness figure; financial heterogeneity table if time allows.

### Day 15 (Friday)
- [ ] Validate the own stayer/leaver classification against the `inventor_status.csv` reference benchmark.
- [ ] Consolidate all tables and figures from Weeks 1–3 into one results package (organized by thesis section number).
- [ ] Write a one-page memo summarizing the full analysis for the next Cassi/Ornaghi meeting.
- [ ] Freeze the analysis — no further changes without a specific reason.

**Deliverable:** complete results package + supervisor memo.

---

## Decision Gates (do not skip)

| Gate | When | If it fails |
|------|------|--------------|
| Pre-trends + placebo test | End of Day 5 | Switch to t = −2 terminal pre-period fallback spec |
| Deal-level cluster count | Day 1 + Day 11 | If clusters too few for asymptotic SEs, plan wild cluster bootstrap explicitly |
| DealSim tercile sample size | Day 11 | If terciles too thin, make the quadratic test the primary DealSim spec; terciles become illustrative only |

---

## Week 4+ — Writing Transition

Write in dependency order, not document order:

1. **Data section** — start immediately, sample/variables are already fixed by Week 1 Day 1.
2. **Empirical Design** — write once Week 1's spec is locked (after Day 5 gate).
3. **Results, Section 5 (full cohort)** — write as soon as Week 1 finishes; do not wait for Week 3.
4. **Results, Section 6 (stayer analysis)** — write after Week 2.
5. **Results, Section 7 (DealSim heterogeneity)** — write after Week 3.
6. **Theoretical Framework** — mechanism-to-prediction mapping is already final; write any time.
7. **Introduction and Conclusion** — last, once actual numbers are known.
