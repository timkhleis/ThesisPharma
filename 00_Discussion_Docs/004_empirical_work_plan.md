# Empirical Work Plan
### After the Acquisition — Stayers' Innovation in Pharma M&A

*Last revised: 2026-05-04*  
*Status: Reviewed (Claude + Codex). Ready to implement after final read.*

---

## Orientation: What Is Already Built

### Pipeline outputs (DuckDB + Parquet, `02_analysis/output/`)

| Table | Grain | Contents |
|---|---|---|
| `inventor_year` | inventor × year | Patent counts, fractional counts, career index |
| `inventor_ipc_year` | inventor × year × IPC | Technology specialisation — basis for TechDrift |
| `group_ipc_year` | group × year × IPC | Corporate portfolios — basis for DealSim |
| `patent_enriched` | patent application | OECD quality indicators (24 cols) |
| `patent_inventor_enriched` | inventor × patent | Inventor-patent bridge with enrichment |
| `group_year_status` | group × year | Merger status, firm counts |
| `patent_company_link` | patent × company | Patent-to-group linkage |

### Inherited from Cassi-Ornaghi (reference only — not the analysis spine)

| File | Location | Role |
|---|---|---|
| `inventor_status.csv` | `01_Data/CassiOrnaghiPaperData/` | Their stayer/leaver classification — **benchmark only** |
| `T_inventors_tech_similarity.csv` | same | Inventor-level similarity to acquirer — validation asset |
| `merger_list.csv` | same | Summary counts by deal year — not deal-level pairs |
| Stata `.do` files | same | Original estimation logic — read to understand their design |

### What is NOT yet built (the five things to build)

1. Canonical deal-level table (target group, acquirer group, deal year)
2. Own stayer/leaver classification — validated against `inventor_status.csv`
3. `Quality_it` at inventor × year grain
4. `TechDrift_it` — cosine similarity of IPC vectors, current year vs. career baseline
5. `DealSim` — deal-level cosine similarity between target and acquirer IPC portfolios

---

## Discipline Rules (do not violate)

- `inventor_status.csv` is a **benchmark**, not the analysis spine. Use it to validate your own classification, not to replace it.
- Every deal-level construct must be validated against the benchmark before use.
- Wrong target-acquirer pairing contaminates both stayer classification and DealSim.
- Multi-exposure inventors: **keep first treated exposure** in main spec; **drop entirely** as robustness check.
- Include zero-patent inventor-years in the panel. Dropping them conditions on the outcome and mechanically hides output declines.
- Quality aggregation: fractional weighted mean — `SUM(quality × 1/inventor_count) / SUM(1/inventor_count)` — not a simple average.

---

## Phase 1 — Deal List and Data Audit

### 1a. Review the Professor Cassi deal list

Before writing a line of code, check what Professor Cassi has provided or can provide:

- Is there a deal-level file with explicit `(target_group_id, acquirer_group_id, deal_year, deal_value)` columns?
- If a file exists already (e.g., from an email or shared folder), compare it against what can be extracted from `inventor_status.csv`.
- If no such file exists: prepare the extraction from Phase 1b as input for the **next meeting with Prof. Cassi**. Present the reconstruction approach and ask him to confirm or correct the deal pairs. This step is important — wrong pairing corrupts both stayer classification and DealSim.

### 1b. Deep audit of `inventor_status.csv`

Load into DuckDB as `inventor_status_reference` and export to `02_analysis/output/parquet/reference/inventor_status_reference.parquet` (not `canonical/` — it is a reference benchmark, not an analysis-spine table). Add the `reference` parquet folder to the output layout before writing this table.

Run the following structural checks:

```r
# Row counts by type
SELECT type, COUNT(*) AS n FROM inventor_status_reference GROUP BY type ORDER BY n DESC;

# Is (codinv, year) unique within a type spell?
SELECT codinv, year, COUNT(*) AS n FROM inventor_status_reference
WHERE type NOT IN ('last year') GROUP BY codinv, year HAVING n > 1;

# How many unique codinv appear as T_STAYER?
SELECT COUNT(DISTINCT codinv) FROM inventor_status_reference WHERE type = 'T_STAYER';

# Multi-exposure inventors: T_STAYER in more than one deal
SELECT codinv, COUNT(DISTINCT target_year) AS n_deals
FROM inventor_status_reference WHERE type = 'T_STAYER'
GROUP BY codinv HAVING n_deals > 1;

# Group table coverage: do id_group and id_group_Tplus join to canonical group?
SELECT COUNT(DISTINCT s.id_group) AS total,
       COUNT(DISTINCT g.id_group) AS matched
FROM inventor_status_reference s LEFT JOIN "group" g ON s.id_group = g.id_group
WHERE s.type = 'T_STAYER';

# Sentinel row structure
SELECT type, MIN(year) AS min_yr, MAX(year) AS max_yr FROM inventor_status_reference GROUP BY type;
```

Understand what `d1`–`d26` encode (deal-time relative years) and whether they align with `target_year`.

### 1c. Audit `firm_group.merger_status`

Confirm the known distribution and understand what `target` and `divestment` flag:

```sql
SELECT merger_status, COUNT(*) AS n FROM firm_group GROUP BY merger_status ORDER BY n DESC;
```

Understand how Cassi-Ornaghi constructed firm-group-year assignments for treated firms — this is needed to rebuild classification from canonical tables in Phase 3.

---

## Phase 2 — Extract and Validate the Provisional Deal Map

**Goal:** produce a table `deal_map(target_group, acquirer_group, deal_year, deal_value)` — one row per acquisition event.

**Method:**
1. Restrict `inventor_status_reference` to `type IN ('T_STAYER', 'T_LEAVER')`.
2. Extract distinct `(id_group AS target_group, id_group_Tplus AS acquirer_group, target_year AS deal_year, target_value AS deal_value)`.
3. Validate:
   - Count of distinct deals — should be close to the 513 reported by Cassi-Ornaghi.
   - Distribution of `deal_year` — should match `merger_list.csv` year counts.
   - All `target_group` and `acquirer_group` values should join to the canonical `group` table.
   - Inspect rows where `target_group = acquirer_group` or where `id_group_Tplus` is NULL.
4. Flag suspicious pairs for discussion with Prof. Cassi.

**Output:** `parquet/helper/deal_map.parquet` + DuckDB table `deal_map`.

> **Next meeting with Prof. Cassi:** Present the extracted deal map (N deals, year distribution, any anomalies). Ask whether he can confirm or provide a more authoritative deal-level file. This meeting should happen before Phase 3 is finalised.

---

## Phase 3 — Rebuild Stayer Classification Independently

**Goal:** produce `inventor_status_own` — your own classification of inventor-deal exposure. The main priority is to correctly reproduce target-side treated inventors (`T_STAYER`, `T_LEAVER`) and future-treated/not-yet-treated controls for the CS(2021) design. Reproducing all Cassi-Ornaghi categories (`N_STAYER`, `A_STAYER`, `N_LEAVER`, etc.) is useful for validation and robustness, but secondary to the main treatment/control spine.

**Stayer definition (follow Cassi-Ornaghi logic from Stata scripts):**

- An inventor is **target-side** for deal `e` if they filed ≥1 patent for a firm in `target_group` in the 5 years before `deal_year`.
- They are a **T_STAYER** if they subsequently file ≥1 patent for the acquiring group (`acquirer_group`) within `x` years post-deal (main: `x = 5`, robustness: `x ∈ {2, 3}`).
- They are a **T_LEAVER** if they were target-side but do not file for the acquirer group within the window.

**Sample filters (replicate Cassi-Ornaghi exactly):**
- Drop inventors with ≤1 patent observation in their career (`by codinv: drop if sum(1) <= 1`).
- Drop inventors who appear as `N_LEAVER` in more than one firm (their `tmprat > 1` rule).
- For multi-exposure inventors (T_STAYER in more than one deal): keep first treated exposure in main spec; drop in robustness.

**Validation:**
- Compare your classification counts to the benchmark:

| type | Benchmark | Own | Difference |
|---|---|---|---|
| T_STAYER | 7,110 rows | ? | ? |
| T_LEAVER | 2,692 rows | ? | ? |
| N_STAYER | 584,032 rows | ? | ? |
| A_STAYER | 68,131 rows | ? | ? |

- Investigate any systematic divergence before proceeding.

**Output:** `parquet/derived/inventor_status_own.parquet` + DuckDB table.

**Script:** `02_analysis/R/04_build_stayer_classification.R`

---

## Phase 4 — Build Outcome Variables

### 4a. Quality_it (inventor × year)

Aggregate from `patent_inventor_enriched` + `patent_enriched`. Use fractional weighting:

```sql
SELECT
  pie.codinv,
  pie.year,
  SUM(CASE WHEN pe.quality_index_4 IS NOT NULL THEN pe.quality_index_4 / pie.inventor_count END) /
    NULLIF(SUM(CASE WHEN pe.quality_index_4 IS NOT NULL THEN 1.0 / pie.inventor_count END), 0) AS quality_it_4,
  SUM(CASE WHEN pe.quality_index_6 IS NOT NULL THEN pe.quality_index_6 / pie.inventor_count END) /
    NULLIF(SUM(CASE WHEN pe.quality_index_6 IS NOT NULL THEN 1.0 / pie.inventor_count END), 0) AS quality_it_6,
  SUM(CASE WHEN pe.fwd_cits5 IS NOT NULL THEN pe.fwd_cits5 / pie.inventor_count END) /
    NULLIF(SUM(CASE WHEN pe.fwd_cits5 IS NOT NULL THEN 1.0 / pie.inventor_count END), 0) AS fwd_cits5_it
FROM patent_inventor_enriched pie
LEFT JOIN patent_enriched pe ON pie.appln_id = pe.appln_id
GROUP BY pie.codinv, pie.year
```

Check OECD quality coverage rate separately for each outcome before treating `NULL` as zero. Do not let missingness in one quality measure drop observations that are usable for another measure.

**Output:** `parquet/derived/inventor_year_quality.parquet`

### 4b. TechDrift_it (inventor × year)

Built in R from `inventor_ipc_year`. Steps:

1. For each stayer inventor, define **career baseline IPC vector**: normalised sum of IPC activity in the 3 years strictly before `deal_year`.
2. For each year `t` (including pre-deal years for pre-trend validation), compute cosine similarity between the year-`t` IPC vector and the baseline.
3. `TechDrift_it = 1 − cosine_similarity` (higher = more drift).

Design choices to document explicitly:
- IPC granularity: **4-character subclass** (recommended — avoids extreme sparsity of full codes, avoids over-aggregation at section level).
- Baseline window: **3 years pre-deal** (not full career — more responsive, less contaminated by early-career patterns).
- Use `Matrix` package for sparse cosine similarity.

**Output:** `parquet/derived/inventor_tech_drift.parquet`

### 4c. DealSim (deal level)

Built in R from `group_ipc_year` + `deal_map`. Steps:

1. For each deal `e`, extract the target group's IPC vector: sum of `patent_count` by `ipc_code` over the 3 years before `deal_year`. Normalise to unit length.
2. Same for the acquirer group.
3. `DealSim_e` = cosine similarity of the two normalised vectors.

**Validation:** DealSim should correlate positively with `T_inventors_tech_similarity.csv` (inventor-acquirer Jaccard/Sørensen). If not, investigate the deal map.

**Output:** `parquet/derived/deal_similarity.parquet`

**Script:** `02_analysis/R/05_build_outcomes.R`

---

## Phase 5 — Build the Estimation Panel

**Goal:** single long-format panel ready for `did::att_gt()`.

**Grain:** inventor × year for treated stayers and valid comparison inventors.

For the main CS(2021) design, controls are **not-yet-treated future-treated inventors**: inventors whose own acquisition exposure occurs in a later cohort and who are untreated in the comparison year. `N_STAYER` inventors from the Cassi-Ornaghi benchmark can be used for descriptive comparisons and robustness checks, but should not be conflated with the main not-yet-treated control group.

**Columns:**

| Column | Source |
|---|---|
| `codinv` | key |
| `year` | key |
| `patent_count` | `inventor_year` |
| `fractional_patent_count` | `inventor_year` |
| `quality_it_4`, `quality_it_6` | `inventor_year_quality` |
| `fwd_cits5_it` | `inventor_year_quality` |
| `tech_drift_it` | `inventor_tech_drift` |
| `deal_year` (= g in CS notation) | `inventor_status_own` |
| `deal_id` | `deal_map` |
| `deal_sim`, `deal_sim_sq` | `deal_similarity` |
| `career_year_index`, `inventor_country` | `inventor_year` |

**Key decisions:**
- Include inventor × years with zero patents (do not drop — see discipline rules).
- `deal_year` for not-yet-treated controls: their own future `deal_year`, not `Inf`. The `did` package handles this correctly given a clean `gname` column.
- CS(2021) unit: `codinv`. If multi-exposure inventors are retained, the `deal_id` scoped unit may be needed — resolve in Phase 3.

**Script:** `02_analysis/R/06_build_estimation_panel.R`

---

## Phase 6 — Descriptive Analysis

Before any regression:

**6a. Summary statistics table (Table 1)**
Mean / SD / min / max for all outcomes and key covariates. Separately by: pre/post merger, T_STAYER vs. T_LEAVER, main not-yet-treated comparison group, and deal year cohort. Use `N_STAYER` only as a benchmark/descriptive category unless it is explicitly part of a robustness design.

**6b. Stayer vs. leaver selection bias test**
Compare pre-merger `patent_count` (and `quality_it`) between T_STAYER and T_LEAVER inventors:
- Two-sample t-test + Kolmogorov-Smirnov test on full distribution.
- Direction determines whether ATT is conservative (positive selection) or anti-conservative (negative selection).
- Report the direction and frame it explicitly in the identification section.

**6c. Deal-level DealSim distribution**
Histogram across the 513 deals. Check that the distribution has mass across the full [0,1] range — required to test the inverted-U. If most deals cluster near 0 or 1, the non-linearity test will be underpowered.

**6d. OECD quality coverage**
Report share of `inventor_year` observations with non-missing `quality_it`. This determines how prominently quality can feature as an outcome.

---

## Phase 7 — Main CS(2021) Estimation

Run separately for each outcome: `patent_count`, `fractional_patent_count`, `quality_it_4`, `tech_drift_it`.

```r
library(did)

out <- att_gt(
  yname     = "patent_count",
  tname     = "year",
  idname    = "codinv",
  gname     = "deal_year",
  data      = stayer_panel,
  control_group = "notyettreated",
  est_method    = "dr",
  panel         = FALSE   # adjust if balanced panel is built
)

agg_simple  <- aggte(out, type = "simple")   # headline ATT
agg_event   <- aggte(out, type = "dynamic")  # event-study plot
agg_cal     <- aggte(out, type = "calendar") # calendar-time effects
```

**Output for each outcome:**
- Event-study plot: ATT(τ) for τ = −5 to +5, with 95% uniform confidence bands.
- Pre-trend test: τ < 0 coefficients jointly insignificant (Roth 2022 sensitivity analysis).
- Headline number from `agg_simple`.

**Script:** `02_analysis/R/07_cs2021_main.R`

---

## Phase 8 — Heterogeneity: DealSim Moderator

**8a. Stratified (primary approach)**
Split deals into DealSim tertiles (low / medium / high). Re-run CS(2021) in each subsample. Plot three event-study curves on the same figure. Test whether medium-tertile ATT is less negative than both extremes.

**8b. Parametric interaction (TWFE, robustness only)**
TWFE is biased under heterogeneous treatment but useful for testing the interaction shape:

```r
feols(patent_count ~
        i(years_since_deal, ref = -1) +
        i(years_since_deal, deal_sim,    ref = -1) +
        i(years_since_deal, deal_sim_sq, ref = -1) |
        codinv + year,
      data = stayer_panel, cluster = ~deal_id)
```

A significant coefficient on `years_since_deal × deal_sim_sq` supports the inverted-U hypothesis.

**Script:** `02_analysis/R/08_heterogeneity_dealsim.R`

---

## Phase 9 — Robustness Checks

| Check | Implementation |
|---|---|
| Alternative stayer window | Re-run Phase 3 with `x ∈ {2, 3}` instead of `x = 5` |
| Alternative quality measure | Replace `quality_index_4` with raw `fwd_cits5` |
| Alternative TechDrift baseline | Full pre-career vs. 3-year window |
| Minimum pre-deal activity | Drop inventors with < 2 patents pre-deal |
| Exclude border cohorts | Drop deal cohorts 1988–1993 and 2010–2015 |
| Alternative control group | `control_group = "nevertreated"` in `att_gt()` |
| Multi-exposure handling | Drop all multi-exposure inventors (vs. keep-first main) |
| Drop multi-leaver inventors | Apply Cassi-Ornaghi `tmprat > 1` filter explicitly |

---

## Recommended Build Order and Timeline

| Week | Phases | Key deliverable |
|---|---|---|
| 1 | 1a — Prof. Cassi deal list review | Deal list confirmed or flagged for meeting |
| 1 | 1b–1c — Audit `inventor_status_reference` + `firm_group` | Structural audit document |
| 2 | 2 — Provisional deal map | `deal_map.parquet`, validated deal count |
| 2–3 | 3 — Rebuild stayer classification | `inventor_status_own.parquet`, comparison table |
| 3 | 4a–4b — Quality + TechDrift | `inventor_year_quality`, `inventor_tech_drift` |
| 4 | 4c + 5 — DealSim + estimation panel | `deal_similarity`, `stayer_panel` |
| 4 | 6 — Descriptives | Summary stats, selection bias test, DealSim histogram |
| 5 | 7 — Main CS(2021) estimation | Event-study plots, headline ATTs |
| 5–6 | 8 — DealSim heterogeneity | Tertile event studies, parametric interaction |
| 6 | 9 — Robustness | Robustness table |

---

## Open Questions (resolve before finalising classification)

1. **Does Prof. Cassi have a deal-level file** with explicit target/acquirer group IDs? This is the most important thing to check before Phase 2.
2. **What does `acquirer = 1` flag in `inventor_status.csv`?** The column exists but its exact encoding needs checking.
3. **How are inventors who switch from target to acquirer mid-career handled?** The `A_STAYER` category may capture some of these.
4. **Does `id_group_Tplus` represent the immediate post-acquisition group or the eventual parent?** Matters for how DealSim is computed.
