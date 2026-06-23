# Research Proposal
## After the Acquisition: Retention, Inventive Output, and Technological Reorientation Among Target-Firm Inventors in Pharma M&A

**Author:** Tim Kuehleis  
**Supervisors:** Lorenzo Cassi, Carmine Ornaghi  
**Date:** May 2026  

---

## Proposed Thesis Structure

| # | Section | Content | Pages |
|---|---------|---------|-------|
| 1 | Introduction | Motivation, central result, literature, road map | 4 |
| 2 | Theoretical Framework | Organizational mechanisms, DealSim horse race, pattern-matching caveat | 3–4 |
| 3 | Data and Institutional Background | Sources, variable construction (TechDrift, DealSim), sample table, descriptives | 4–5 |
| 4 | Empirical Design | CS(2021) setup, t=−2 reference, stayer selection structure | 3 |
| 5 | Main Results: Full Cohort | Layer 1 event study, pre-trend test, placebo | 4 |
| 6 | Stayer Analysis: Quantity, Quality, TechDrift | Track A/B table; Quality + TechDrift ATTs; team disruption subsection; attrition decomposition plot | 5–6 |
| 7 | DealSim Heterogeneity | Tercile plot + second-stage WLS; deal-type splits; BvD financial controls as heterogeneity columns | 5 |
| 8 | Robustness | Never-treated, Verginer, alternative window, placebo, contamination buffer, Lee threshold | 2–3 |
| 9 | Conclusion | Summary, policy implications, scope | 2 |
|   | **Total (main text)** | | **32–38** |
|   | Online Appendix | Horizon cuts, specialist split, InvSim within-deal, pharma-IPC DealSim, EPO venue diagnostic, full Lee bounds table, full IPW first-stage table, classification validation | 10–15 |

---

## 1. Motivation

Pharmaceutical acquisitions have intensified over the past three decades, generating persistent concerns about their effect on inventive output. The industry combines high market concentration, long R&D cycles, and unusual dependence on patented knowledge. These features make the organization of inventive labor after deal-making economically important, even when the data do not allow broad welfare claims about ultimate drug development outcomes.

Prior work shows that mergers can reduce firm-level patenting and increase inventor departures from target firms. But the two dominant narratives in the literature — that acquisitions destroy inventive capacity via integration disruption, or that they create it via knowledge recombination — leave a critical question unanswered: what happens to the inventors who are retained after the acquisition?

This matters for two reasons. First, from an organizational economics perspective, the retention of human capital is often used as a proxy for the preservation of inventive capacity. However, headcount retention is observable while underlying inventive output is not. If retained inventors produce fewer patents, lower-quality patents, or shift into unfamiliar technological fields, then simple retention metrics may mask a decline in true inventive capacity.

Second, there is a fundamental organizational economics question about what acquirers do with retained inventive labor. Four mechanisms are empirically plausible and have distinct predictions:

- **Integration disruption**: organizational change creates friction that reduces inventive output temporarily; the effect should attenuate as integration completes.
- **Portfolio rationalization**: the acquirer terminates redundant R&D programs; patent counts fall even among retained inventors with no individual productivity decline.
- **Human-capital reallocation**: retained inventors are redirected into the acquirer's technological priorities; TechDrift rises even if total patent counts are stable.
- **Incentive restructuring**: internal priorities and autonomy change under the acquirer; inventors face altered career incentives with heterogeneous productivity consequences.

These mechanisms have different organizational and strategic implications, as well as distinct empirical signatures. The thesis is therefore framed primarily as an inventor-level organizational economics paper. IO and antitrust concerns motivate the setting, but the empirical object is early-stage inventive output, not final product-market welfare.

---

## 2. Core Research Question

> How do acquisitions affect the inventive output and technological direction of pre-deal target-firm inventors, with particular focus on the inventors who remain with the acquiring group?

The central causal estimand is the **average treatment effect on the pre-deal target-inventor cohort** — all inventors attached to the target before the acquisition, regardless of whether they subsequently stay, leave, or stop patenting. This avoids conditioning the main analysis on post-treatment survival.

A secondary analysis asks: among inventors who are observed to remain with the acquiring group, do acquisitions reduce patent quantity, patent quality, or technological focus — and does pre-deal technological overlap moderate these effects in a non-linear way? Because stayer status is defined after treatment, this does not identify a standard CATE. It estimates a **stayer-specific ATT for the observed retained inventor population**, with observable selection corrected via pre-treatment IPW reweighting and unobservable selection assessed through Lee (2009) bounds and sensitivity analysis. The identification caveat is conditioning on a post-treatment survival variable, not an absence of causal content.

---

## 3. Contribution

The thesis contributes three things that are not jointly present in any prior paper. Relative to closely related work on biotech acquisitions and inventor productivity, especially Verginer et al., the thesis uses a broader pharmaceutical acquisition panel, keeps the full pre-deal target-inventor cohort as the main causal population, adds richer pre-treatment controls, and studies multiple inventor-level outcomes rather than patent counts alone.

**First**, it uses the full pre-deal target-inventor cohort as the causal unit, rather than defining the sample by post-treatment stayer status. This avoids the sample selection problem that affects studies restricted to retained inventors.

**Second**, it introduces two novel inventor-level outcome measures alongside patent counts:
- **Quality_it**: OECD PQII composite quality score, linked via `appln_id`, measuring the quality of filed patents rather than just their number.
- **TechDrift_it**: cosine similarity of an inventor's current-year IPC vector relative to their career baseline, measuring the degree to which the inventor has been redirected into unfamiliar technology fields post-acquisition.

**Third**, it tests a specific non-linear empirical conjecture about **DealSim** — the pre-deal cosine similarity between target and acquirer IPC portfolios — as a moderator of acquisition effects. The horse-race prediction is an inverted-U: negative effects are largest at the extremes of technological overlap, smallest at moderate overlap. This is not treated as a fully derived equilibrium prediction; it is a disciplined reduced-form test of competing organizational mechanisms.

Prior work (Cassi and Ornaghi, 2026) establishes what happens to inventors who leave target firms after acquisition. This thesis asks what happens to those who stay.

---

## 4. Data

The empirical analysis combines four sources:

| Source | Content |
|--------|---------|
| Cassi–Ornaghi panel and group-history files (2026) | 311,358 inventors, 1988–2015, inventor affiliations, merger-linked group histories, and reference status classifications |
| EPO / PATSTAT | Patent application records, IPC classifications, co-inventor links |
| OECD Patent Quality Indicators | 24-column enrichment per `appln_id`, including PQII composite score (2024 vintage — all patents in the clean sample have complete citation windows) |
| Bureau van Dijk / Zephyr | Deal-level data: target, acquirer, deal year, deal value, and Cassi-Ornaghi merger quality flags |
| `T_inventors_tech_similarity.csv` (Cassi–Ornaghi auxiliary) | Inventor × acquirer technology similarity: Jaccard, Sørensen, and common-IPC-share measures for 26,627 stayer inventors across 280 acquirers; serves as the inventor-level analogue of DealSim, enabling within-deal heterogeneity tests with deal fixed effects |
| `t_stayer_coinventors.csv` (Cassi–Ornaghi auxiliary) | Patent-level co-inventor records for stayers (158,949 rows): co-inventor identity, status classification (`T_STAYER`, `T_LEAVER`, `A_STAYER`, `N_STAYER`, etc.), and a `working_there` flag indicating whether the co-inventor is observed at the acquirer group post-deal; primary source for team disruption and pre-deal cross-tie variables |

The main full-cohort CS(2021) analysis uses the broad merger-list treatment-timing universe and does not require acquirer group identity. Analyses that require acquirer identity, especially DealSim and the reconstructed stayer classification, use the new `L_group_history_target`/`L_merge` spine to recover target and acquirer group IDs. `L_group_history_target` records company-year group membership and merger-related group changes at the `compcod` level, while `L_merge` provides the corresponding Zephyr/BvD deal information. The older `(target_year, target_value)` bridge and `inventor_status_reference` remain useful as validation benchmarks, but they are no longer the primary source for acquirer-group assignment.

**Sample restrictions for clean causal identification:**
- Main causal window: `deal_year ≤ 2010` — ensures a full five-year post-acquisition observation window within the 2015 panel endpoint.
- Full five-year pre-period: `deal_year ≥ 1993` — ensures the pre-period is observable.
- Clean sample: `1993 ≤ deal_year ≤ 2010`.
- Merger rows flagged by Cassi-Ornaghi as problematic on the acquirer side (`todrop_acq = 1`) are excluded because they generally have unresolved placeholder post-merger group identifiers (`999xxxx`) and cannot be assigned a reliable acquirer group.
- A small set of deals without explicit acquirer-company linkage but with a clean target post-merger group transition is retained using the post-merger target group as the acquirer-group fallback; these cases are flagged and excluded in robustness checks.

**Effective deal counts by analysis layer:**

| Analysis window | Main full-cohort deal count | In group-history spine | DealSim-resolved non-placeholder acquirer groups |
|-----------------|----------------------------:|-----------------------:|-------------------------------------------------:|
| Unrestricted merger-list window | 513 | 491 | 455 |
| Five-year event window, 1993--2010 | 373 | 356 | 335 |
| Three-year event window, 1991--2012 | 431 | 413 | 388 |

The main full-cohort CS(2021) analysis uses the broad treatment-timing sample. DealSim analyses are necessarily restricted to deals with clean target and acquirer group identifiers. I therefore report DealSim as a subsample heterogeneity analysis and use the DealSim-resolved common sample as a robustness check for the main specification.

---

## 5. Treated Population

The main treated population is the **pre-deal target-inventor cohort**.

An inventor belongs to the treated cohort for deal `d` if their latest observed group affiliation in years `[deal_year − 5, deal_year − 1]` is the target group of deal `d`.

This definition is set **before treatment**. It does not condition on whether the inventor subsequently stays, leaves, or stops patenting. This is the design choice that makes the main causal analysis clean.

---

## 6. Treatment Timing

Treatment is defined as exposure to the acquisition of the inventor's pre-deal employer.

| Parameter | Value |
|-----------|-------|
| Treatment year | `target_year` — year the target firm was acquired |
| Event time | calendar year − `deal_year` |
| Main window | t = −5 to +5 |
| Preferred sample | `1993 ≤ deal_year ≤ 2010` |

Note: `acqui_year` (acquirer-side timing) is **not used** — it differs from `target_year` by up to ±8 years in some deals.

---

## 7. Post-Acquisition Status Classification

After defining the pre-deal target-inventor cohort, inventors are classified by observed patenting behaviour from `deal_year` to `deal_year + 5`.

**Primary status classification:**

| Status | Definition |
|--------|------------|
| `T_Ever_Stayed` | At least one post-deal patent affiliated with the acquirer group within five years |
| `T_LEAVER` | Post-deal patenting observed, but not with acquirer, and at least one post-deal group differs from the original target |
| `T_NO_POST_5Y` | No observed EPO patent in the five-year post-deal window |
| `T_UNRESOLVED_TARGET_POST` | Post-deal patenting only under the original target group (assignee-name lag or subsidiary autonomy) |

**Horizon-specific diagnostic variables (constructed within `T_Ever_Stayed`):**

| Variable | Definition |
|----------|------------|
| `first_acquirer_year` | First post-deal year with at least one acquirer-affiliated patent |
| `first_outside_year` | First post-deal year (strictly after `first_acquirer_year`) where the inventor's primary resolved affiliation is a non-acquirer and non-target group[^outside] |
| `short_stayer` | 1 if `first_outside_year ≤ deal_year + 2`; robustness reported for cutoffs of 1 and 3 years |
| `career_end_year` | Last year with any EPO patent in the full panel — Cassi-Ornaghi career exit definition; used for descriptive and attrition purposes only, never as a regression sample filter |
| `persistent_stayer_h` | At least one acquirer-affiliated patent by horizon h and no observed non-acquirer patent through h; allows patenting gaps after initial acquirer observation and does not condition on future patent activity after h — **preferred horizon robustness cut** |
| `patent_active_survivor_h` | `persistent_stayer_h` AND `career_end_year > deal_year + h`; excludes career exits but conditions on future patent activity — **selected intensive-margin robustness only** |
| `career_exit_within_stayer_h` | `T_Ever_Stayed` AND `career_end_year ≤ deal_year + h` — within-stayer analogue of `T_NO_POST_5Y` |

[^outside]: `first_outside_year` relies on the `inventor_affiliation_own` structure, which collapses every inventor-year into exactly one primary `resolved_group`. The primary affiliation is defined as the modal group (highest patent count) for that year, with career-continuity tie-breakers. This structurally ensures that isolated trailing collaborations do not mistakenly trigger departure signals, fulfilling the intent of a majority filter.

**Important classification notes:**

- `T_Ever_Stayed` is defined post-treatment. Every analysis restricted to this group — or any horizon-specific subset of it — conditions on a post-treatment selection variable. These are post-treatment selected samples, not clean identification samples. The direction and magnitude of selection are characterised empirically (see Section 11).
- `persistent_stayer_h` is the preferred horizon robustness cut because it does not condition on future patent activity. However, it still conditions on not being observed outside the acquirer through h — it remains a survivor-style sample and should not be labelled "preferred evidence," only "preferred horizon robustness."
- `patent_active_survivor_h` conditions on `career_end_year > deal_year + h`, which selects on future patent activity — an outcome variable. It is reported only as a selected intensive-margin robustness check, not as the main sample.
- After an initial acquirer-affiliated patent by horizon h, silent years within the horizon are kept in `persistent_stayer_h` as unobserved staying states unless an outside patent is observed. Pre-deal career age diagnostics assess whether the silent subgroup looks systematically more senior — if so, management transition within the stayer pool is noted as a classification caveat. **Implementation note**: code must explicitly distinguish a **gap year** (zero patents in year t, but acquirer-affiliated patents observed both before and after t within the horizon window) from **truncation** (zero patents in year t with no subsequent observation within the window, whether due to panel end at 2015 or true career exit). Gap years are kept inside `persistent_stayer_h`; truncation years trigger the `career_exit_within_stayer_h` flag. The logic branch must be tested on known cases before the classification runs at scale.
- `T_NO_POST_5Y` does not necessarily indicate labour-market exit. **Diagnostic**: compare pre-deal career age and patent count distributions across all four primary status groups. If `T_NO_POST_5Y` inventors are systematically more senior pre-deal, note the management transition interpretation as a classification caveat.
- Cassi and Ornaghi (2026) already characterise the `T_LEAVER` and `T_NO_POST_5Y` populations. **This thesis does not replicate that analysis**; it uses it as a motivating baseline and focuses on `T_Ever_Stayed`.

---

## 8. Main Outcomes

**Primary outcomes (all three empirical layers):**

| Outcome | Construction |
|---------|-------------|
| `patent_count` | Count of EPO applications per inventor per year |
| `fractional_patent_count` | Patent count weighted by 1/(number of inventors) |
| `active_patenting` | Indicator: `patent_count > 0` |

**Secondary outcomes (stayer and heterogeneity analyses):**

| Outcome | Construction |
|---------|-------------|
| `Quality_it` | OECD PQII composite score, averaged over inventor's patents in year t; OECD PQII uses a standardised five-year citation window, mitigating the truncation bias that affects raw citation counts |
| `TechDrift_it` | 1 − cosine similarity of inventor's IPC vector in year t vs. career baseline; baseline is the inventor's mean IPC distribution over [deal_year − 5, deal_year − 1], consistent with the cohort definition window; higher values indicate greater technological displacement |

**Deal-level moderator:**

| Variable | Construction |
|----------|-------------|
| `DealSim` | Pre-deal cosine similarity between target group and acquirer group IPC portfolio vectors, computed from `group_ipc_year`; IPC aggregated to the Main Group level (e.g., `A61K 31` or `A61P 35`, typically 6-7 characters). This provides meaningful variation in pharmaceutical technologies (distinguishing small molecules from biologics, or oncology from cardiovascular), as 4-character subclasses are too broad in this sector. |

**Inventor-level moderator (from `T_inventors_tech_similarity.csv`):**

| Variable | Construction |
|----------|-------------|
| `InvSim_jaccard` | Jaccard similarity between the stayer's pre-deal IPC portfolio and the acquirer's IPC portfolio; inventor-level analogue of `DealSim` capturing within-deal variation in technological alignment; used in within-deal robustness tests with deal fixed effects |

**Deal-level motivation proxy (from `group_ipc_year`):**

| Variable | Construction |
|----------|-------------|
| `AcqPriorOverlap` | Indicator: acquirer has any pre-deal patenting in the target's primary IPC Main Group (same level as DealSim, e.g., `A61K 31`). Zero → market-access or pipeline-asset acquisition, autonomy preservation more plausible at low DealSim. Positive → technology-complementarity deal, friction more plausible. Used to condition the low-DealSim fork prediction in H4. |

**Co-inventor network variables (from `t_stayer_coinventors.csv`, pre-deal years only):**

| Variable | Construction |
|----------|-------------|
| `co_leaver_share_i` | Share of stayer's pre-deal co-inventors classified as `T_LEAVER` or `T_NO_POST_5Y`; operationalises team disruption from departure of knowledge complements; requires minimum 3 pre-deal co-inventors to compute |
| `pre_deal_acquirer_ties_i` | Count of pre-deal co-inventors with `working_there = 1`; indicates pre-deal social ties to acquirer-side inventors; inventor-level complement to `AcqPriorOverlap` for the low-DealSim fork test |
| `network_centrality_i` | Pre-deal degree centrality in the target's co-invention network (from `t_stayer_coinventors.csv`); used as an additional covariate in the IPW first stage, since central inventors are harder to replace and thus more likely to be selectively retained |

---

## 9. Empirical Design

The thesis has three empirical layers, ordered by identification strength.

### Layer 1: Full Target-Inventor Cohort (Main Causal Analysis)

**Estimand**: the average treatment effect of acquisition exposure on the pre-deal target-inventor cohort.

**Method**: Callaway and Sant'Anna (2021) group-time ATT with doubly-robust estimation (`did` R package, `est_method = "dr"`, `control_group = "notyettreated"`).

**Why not-yet-treated controls?** Never-treated pharma firms are systematically different from acquisition targets — structurally outside deal flow, smaller, or more specialised. Not-yet-treated firms share the acquisition-target characteristic that makes conditional parallel trends plausible. This is an affirmative theoretical justification, not a concession. Never-treated controls are used as a robustness specification.

Conditional on the included covariates — pre-deal patent stock, deal size, target inventor count, inventor career age, pre-deal inventor patenting trajectory, primary technology class, and target pre-trend slope — future acquisition targets are comparable to current acquisition targets: both are firms that have entered the acquisition market. These covariates capture the observable dimensions of that shared selection characteristic. The remaining identifying assumption is that, given these observables, early-treated and not-yet-treated cohorts would have followed the same inventor-level patent trajectory absent acquisition — a condition the pre-trend plots and joint pre-period test directly assess.

**Conditional parallel trends — covariates entering the propensity score model:**
- Pre-deal patent stock of the target group (log, five-year sum before `deal_year`)
- Deal size (log `target_value`)
- Pre-deal target inventor count
- Inventor-level pre-deal patent trajectory over t = −5 to t = −1
- Inventor career age and pre-deal active-patenting rate
- Primary IPC/technology class and target-group pre-trend slope

**Aggregation**: event-time weighted average, reported as an event-study plot from t = −5 to t = +5.

**Standard errors**: clustered at the deal level; wild cluster bootstrap reported for the main table.

**Note on count outcomes**: the doubly-robust CS(2021) estimator applies a linear outcome regression. For count outcomes this is valid under mild regularity conditions; `active_patenting` (binary) is reported as the **primary extensive-margin outcome** alongside `patent_count` to avoid concerns about predicted-value sign violations. Patent panels are heavily zero-inflated — the share of inventor-years with zero patents is expected to be large both pre- and post-deal. Report the percentage of zero observations by event time in the descriptive statistics table; a large post-deal increase in the zero share is itself a finding and confirms the extensive-margin interpretation.

### Layer 2: Stayer Productivity (Stayer-Specific ATT)

**Estimand**: stayer-specific ATT for observed `T_Ever_Stayed` inventors on patent counts, quality, and TechDrift, interpreted subject to selection into post-treatment retention.[^sace]

**Sample scope note**: `T_UNRESOLVED_TARGET_POST` inventors (post-deal patenting only under the original target group) are included in the full-cohort Layer 1 ATT — they belong to the pre-deal target-inventor cohort regardless of post-deal status. They are excluded from Layer 2 because they cannot be reliably classified as either stayer or leaver; their count and share are reported in Table 1 as a data quality check.

**Identification structure**: `T_Ever_Stayed` is defined post-treatment, so this analysis does not identify a standard CATE. Instead it estimates acquisition effects for the observed retained inventor population under explicitly characterised selection. The preferred Layer 2 specification uses the broad `T_Ever_Stayed` sample; horizon-specific `persistent_stayer_h` samples are reported as survivor-sample robustness checks; and `patent_active_survivor_h` samples isolate the intensive margin among continuing patenters. Because continued patenting is itself an outcome, these intensive-margin estimates are substantively important but selected. Layer 2 addresses selection in three steps:

[^sace]: The formal benchmark is the Survivor Average Causal Effect (SACE): E[Y(1) − Y(0) | S(1) = 1, S(0) = 1], where S(1) denotes retention under acquisition and S(0) denotes retention absent acquisition — i.e., the effect among "always-stayers" who would remain regardless of the deal. The SACE is not point-identified without additional assumptions, most importantly monotonicity: the acquisition can only induce inventors to leave, never cause an otherwise-departing inventor to stay. This assumption is questionable in the pharmaceutical M&A context. Acqui-hires — deals whose rationale is precisely to lock in specific key inventors through retention packages — constitute a class of transactions where the acquisition actively induces inventors to stay who would otherwise have departed. Monotonicity fails for these inventors by construction. Because the SACE's identifying assumption is empirically doubtful here, Layer 2 does not claim to identify the SACE. It instead reports the observable-selection-adjusted stayer ATT alongside Lee bounds and a sensitivity analysis.

1. **Observable selection correction (Track A vs. Track B)**: A first-stage probit models P(T_Ever_Stayed | pre-deal X) as a function of pre-deal patent count, career age, IPC Herfindahl, log deal size, and interactions between inventor quality quartile and target-level deal characteristics (to capture heterogeneous retention package likelihood in acqui-hire type deals). Stabilised IPW weights (w_i = P̄/P̂_i) reweight the stayer sample to resemble the full pre-deal target cohort on observables. Track A reports the unweighted stayer ATT from `att_gt(..., est_method = "dr")`; Track B passes the first-stage weights via `att_gt(..., weightsname = "stayer_ipw", bstrap = TRUE)`, with bootstrapped standard errors to account for first-stage estimation uncertainty. Similarity between Track A and Track B indicates observable selection does not drive the result; divergence identifies its direction and magnitude.

2. **Unobservable selection — Lee-style sensitivity ranges**: because monotonicity is empirically doubtful in this setting (acqui-hires violate it by construction), Lee bounds do not identify a well-defined SACE. They are reported as sensitivity ranges — a range of ATT estimates under alternative trimming assumptions — not as a definitive correction. Career-exit contamination within the stayer pool is shown descriptively in the attrition plot and assessed through these sensitivity ranges, not removed by pre-filtering.

3. **Sensitivity analysis**: quantify the tolerance threshold — how large would unobservable selection need to be (as a share of variance in stayer status) to overturn the main finding? Report as a single threshold sentence: *"The result survives unless unobservable factors account for more than X% of the variance in stayer status."*

**Horizon-specific robustness and intensive margin**: re-run Layer 2 restricting to `persistent_stayer_h` for h = 2, 3, 5. These are survivor-sample robustness checks — they condition on not being observed outside the acquirer through horizon h, which is itself a post-treatment condition. The `patent_active_survivor_h` sample additionally excludes career exits and is reported as the continuing-patenter intensive margin. It answers whether productivity falls even among inventors who remain visible in patent data, but it is not preferred evidence for the total stayer effect because `career_end_year > deal_year + h` conditions on future patent activity.

**Attrition plot**: for each event year t = 0 to +5, decompose `T_Ever_Stayed` into four mutually exclusive states: (1) active with acquirer — acquirer-affiliated patent in year t; (2) outside departure — no acquirer patent in year t but patents with a non-acquirer group; (3) silent/gap — no patent anywhere in year t, career not yet ended (`career_end_year > deal_year + t`); (4) career exit — `career_end_year ≤ deal_year + t`. This is the honest context for reading the event-study shape: late post-deal coefficients average over a progressively more selected subsample, and the plot shows what that selection looks like.

**What is not feasible**: a Heckman selection correction requires an exclusion restriction — a variable that predicts stayer status but has no direct effect on post-deal patenting. Candidate instruments (geographic distance between labs, pre-deal co-invention ties with acquirer) are all plausibly correlated with post-deal outcomes directly. Absent a defensible instrument, Heckman identification relies on functional form alone. The IPW + sensitivity ranges + sensitivity threshold package is the appropriate frontier given the data constraints.

**Pre-trend divergence test**: before the acquisition, plot patent trajectories for `T_Ever_Stayed` and `T_LEAVER` inventors from the same deals separately over t = −5 to t = −1. Divergence in the pre-period is direct evidence of selection on pre-trends and would be reported as a classification caveat alongside the balance table.

**Team disruption heterogeneity**: within the stayer sample, regress post-deal patent count and quality on `co_leaver_share_i`, with event-time and deal fixed effects. Prediction: negative coefficient — stayers who lost a larger share of their pre-deal co-inventor team show larger output declines. The distinguishing temporal signature is that the effect should be **immediate and non-attenuating**: network damage from co-inventor departure is permanent, unlike integration disruption (which attenuates as the organisation stabilises). Compare the event-study slope for high vs. low `co_leaver_share_i` terciles to test this. Constructed from `t_stayer_coinventors.csv` restricted to `year < deal_year`.

**TechDrift ambiguity test**: TechDrift is directionally ambiguous. Displacement from the career IPC baseline may indicate *misallocation* — the inventor is forced into unfamiliar territory — or *productive recombination* — the inventor brings novel knowledge to a new technological area. To discriminate, regress `Quality_it` on `TechDrift_it` within the stayer sample, conditioning on event-time and deal fixed effects. A negative coefficient (more drift → lower patent quality) supports the misallocation interpretation. A positive coefficient supports recombination. This test is reported in Section 6 alongside the main TechDrift ATT.

### Layer 3: DealSim Heterogeneity

**Estimand**: how the acquisition effect varies with pre-deal technological overlap between target and acquirer.

**Method**: three-step test (see Section 10, H4).

**BvD financial controls as heterogeneity columns** *(supervisor requirement)*: re-run the tercile table and second-stage WLS with deal-level financial controls from BvD/Zephyr — log deal value, target pre-deal R&D intensity (R&D expenditure / revenue where available), and target employment. Report as additional columns in the main DealSim heterogeneity table, not merely as covariate controls. This tests whether the DealSim gradient persists after conditioning on the financial scale and character of the deal, and whether deal value or target size independently moderate the acquisition effect.

**Deal-type heterogeneity**: split the main results by organizationally meaningful deal types that are observable in the existing data. The two primary splits are (i) large-acquirer/small-target deals versus large-acquirer/large-target deals, using pre-deal inventor count or employment as the size measure, and (ii) cross-border versus domestic acquisitions. These splits test whether declines are concentrated in transactions where integration complexity is likely to be higher. They are interpreted as organizational heterogeneity, not as separate causal designs.

**Within-deal robustness using inventor-level DealSim** *(appendix)*: use `InvSim_jaccard` from `T_inventors_tech_similarity.csv` to test the DealSim heterogeneity hypothesis within deals, with deal fixed effects. Reported in the appendix as a within-deal robustness check; cited in the main text in one sentence.

---

## 10. Main Hypotheses

### H1 — Stayer Quantity
Acquisitions reduce patent output among retained target-firm inventors.

### H2 — Stayer Quality
Acquisitions reduce quality-adjusted patent output (OECD PQII) among retained inventors, not only raw counts.

### H3 — TechDrift
Retained inventors shift away from their pre-acquisition technological specialisation post-merger.

### H4 — DealSim Heterogeneity (horse race between three functional forms)

The effect of acquisition on stayer inventive output varies with pre-deal technological overlap (DealSim). Theory generates three candidate functional forms, and the empirical test is a **horse race** between them:

- **Monotone positive**: absorptive capacity dominates throughout — more overlap facilitates knowledge integration — predicting monotonically better stayer outcomes at higher DealSim.
- **Monotone negative**: portfolio redundancy dominates throughout — more overlap always increases program duplication and termination — predicting monotonically worse outcomes.
- **Inverted-U** (motivated empirical conjecture): absorptive capacity gains dominate at moderate overlap while redundancy-driven program termination dominates at high overlap, yielding an interior optimum. This requires that redundancy costs grow faster than absorptive capacity gains beyond the moderate-overlap range — plausible in pharma given how narrowly R&D programs are defined, but not guaranteed by theory alone. The inverted-U is therefore treated as a horse-race pattern, not a derived equilibrium result.

The tercile ATT plot is the primary diagnostic: most negative at the extremes and least negative in the middle → inverted-U; monotone pattern → one of the first two forms. Formal tests (second-stage WLS regression of deal-level ATTs on DealSim and DealSim², estimated peak) supplement the visual.

- **Low DealSim — friction vs. autonomy preservation**: two competing predictions at the low end. Under *friction*, the acquirer cannot absorb target knowledge but still attempts integration, so stayers face high TechDrift and productivity declines. Under *autonomy preservation*, a technologically distant acquirer has no operational reason to interfere with target programs and leaves them undisturbed. **Operationalisation of the fork via deal motivation**: construct `AcqPriorOverlap` — whether the acquirer has any pre-deal patenting in the target's primary IPC subclass (computable from `group_ipc_year`). Zero prior overlap suggests a market-access or pipeline-asset acquisition (autonomy preservation more likely); positive prior overlap suggests a technology-complementarity deal (friction more likely). Additionally split by `pre_deal_acquirer_ties_i > 0` vs. `= 0` at the inventor level. A cross-border deal indicator (from `firm.dta`) provides a third proxy for organisational distance.
- **Moderate DealSim**: enough common ground to integrate knowledge, enough novelty to generate recombinations → least integration disruption, best stayer outcomes.
- **High DealSim**: portfolio redundancy triggers program termination — the acquirer closes overlapping R&D lines, reducing stayer patent counts even without any decline in individual inventor productivity. This empirical signature is also consistent with replacement-effect or killer-acquisition logic, but the patent data cannot distinguish strategic suppression from efficient elimination of duplicate research. The interpretation is therefore reduced-form.

**Empirical test — three steps:**

1. **Tercile bins (main visual)**: re-run CS(2021) separately within each DealSim tercile; plot ATT on patent count and quality by tercile. The shape directly reads off the horse race: inverted-U, monotone positive, or monotone negative.
2. **Second-stage WLS regression (formal test)**: extract deal-level aggregated ATTs from the main CS(2021) run; regress these on DealSim and DealSim² using WLS weighted by the inverse variance of each deal-level ATT. Test joint significance; report the estimated peak `DealSim* = −β₁ / (2β₂)`. This approach respects CS(2021) identification in the first stage and tests the nonlinear relationship in a clean second stage, avoiding the known heterogeneity bias of TWFE with staggered treatment timing and an interacted moderator.
3. **Spline (functional-form robustness)**: natural spline with two knots at the DealSim tercile breaks in the second-stage regression; checks robustness to the quadratic functional form assumption.

### H5 — Team Disruption
Among retained target-firm inventors, those who lost a larger share of their pre-deal co-inventor team to departure (`co_leaver_share_i`) show larger post-acquisition declines in patent quantity and quality. The effect should be **immediate and non-attenuating**, distinguishing it from integration disruption. *Caveat*: Team disruption is highly endogenous. The departure of co-inventors may be driven by unobservable project failures, lab closures, or selection (e.g., the most capable inventors leaving together). This hypothesis is tested acknowledging these selection issues, using it to describe patterns of co-movement rather than a purely exogenous shock. Constructed from `t_stayer_coinventors.csv` pre-deal co-invention records.

---

## 11. Identification Challenges

### 11.1 Parallel Trends

The CS(2021) design requires conditional parallel trends: conditional on covariates, treated inventors' outcomes would have followed the same trend as not-yet-treated inventors in the absence of acquisition.

**Validation protocol (required for all specifications):**
- **Primary reference period: t = −2.** Pharmaceutical deal negotiations typically begin 12–18 months before close. R&D decisions inside the target — R&D freezes during due diligence, retention-package incentives contingent on deal close, management redirection of programs toward acquirer priorities — may respond before `deal_year`. This makes t = −1 a first-order identification threat, not a diagnostic. t = −2 is the primary reference period in the main specification. The t = −1 coefficient is reported separately as a diagnostic coefficient outside the pre-period validity window; if it is large and significant while t = −5 to t = −2 are flat, pre-announcement contamination is real and the t = −2 reference is validated ex post.
- Event-study plot for t = −5 to t = −2 with 95% confidence intervals; t = −1 shown as a separate diagnostic coefficient
- Formal joint test that all pre-period group-time ATTs from t = −5 to t = −2 jointly equal zero; report p-value in the main table header
- Placebo timing test: shift all treatment years by +3 and −3, re-run main specification, confirm ATTs are flat
- **Control group pre-announcement contamination**: not-yet-treated inventors in the control group may themselves be within the pre-announcement window of their own future acquisition. If deals cluster in time (as they do in pharma), a material share of control-inventor-years may be within 1–2 years of the control's own `deal_year`. Diagnostic: plot the distribution of control-inventor-years by time-to-own-deal. Robustness specification: exclude control-inventor-years within two years of the control inventor's own `deal_year`.

### 11.2 Stayer Selection Bias

Restricting Layer 2 to `T_Ever_Stayed` introduces selection whose direction is empirically open. Every restricted stayer sample in this thesis — including horizon-specific cuts — conditions on a post-treatment variable and should be described as a post-treatment selected sample, not as clean identification.

- **Negative selection** (high-productivity inventors exit): stayers are less productive on average than the pre-deal target workforce → unweighted stayer ATT overstates the negative acquisition effect.
- **Positive selection** (high-productivity inventors stay): stayers are the best inventors → unweighted stayer ATT understates the effect; even the most productive inventors are being harmed.

**Step 1 — Observable selection test (Table 2 in the paper)**: compare the pre-deal distribution of `T_Ever_Stayed` vs. `T_LEAVER` across at least five dimensions: patent count, OECD quality score, career age (years since first patent), IPC Herfindahl (specialization), and co-inventor network size. Report means, SDs, and difference-in-means tests. This balance table characterises the direction of any observable selection and validates the covariate set used in the IPW first stage.

**Step 2 — IPW correction for observable selection**: first-stage probit on the treated population using a **parsimonious covariate set** to avoid the curse of dimensionality: `T_Ever_Stayed ~ log_pre_patent_count + career_age + ipc_herfindahl + log_deal_size + (inventor_quality_quartile × log_deal_size)`. The interaction term captures heterogeneous retention-package likelihood in acqui-hire type deals. Covariates `inventor_country` and `network_centrality` are reserved for the outcome-regression side of the doubly-robust estimator rather than the propensity score, reducing the risk of complete separation or extreme propensity scores. **Implementation check**: inspect the propensity score distribution before weighting; trim the top and bottom 1% of estimated probabilities if extreme weights emerge. Stabilised weights `w_i = P̄ / P̂_i` reweight the stayer sample toward the full pre-deal target cohort on observables. Track A (unweighted) and Track B (IPW-weighted, bootstrapped SEs via `bstrap = TRUE`) are reported side-by-side.

**Step 3 — Lee-style sensitivity ranges**: because monotonicity is empirically doubtful here — acqui-hires violate it by construction — Lee bounds do not identify a well-defined SACE. They are reported as sensitivity ranges under alternative trimming assumptions. Career-exit contamination within the stayer pool is shown descriptively in the attrition plot and assessed through these ranges; it is not removed by pre-filtering.

**Step 4 — Sensitivity threshold**: report the tolerance to unobservable confounding as a single sentence: *"The result survives unless unobservable factors account for more than X% of the variance in stayer status."*

**Step 5 — Pre-trend divergence test**: plot event-study pre-trends for `T_Ever_Stayed` and `T_LEAVER` separately over t = −5 to t = −1. Pre-period divergence is direct evidence of selection on pre-trends.

**Final sample hierarchy**:

| Sample | Role | Selection caveat |
|--------|------|-----------------|
| `T_Ever_Stayed` | Main Layer 2 sample | Post-treatment selection into retention |
| `persistent_stayer_h` (h = 2, 3, 5) | Preferred horizon robustness cut | Additionally conditions on no outside departure through h |
| `patent_active_survivor_h` (h = 2, 3, 5) | Continuing-patenter intensive margin | Additionally conditions on future patent activity — selected upward |

---

## 12. Robustness and Extensions

Robustness checks are divided into those reported in the main text (Section 8 of the paper, ~2–3 pages) and those deferred to the online appendix.

**Main text robustness (~2–3 pages):**

| Check | Description |
|-------|-------------|
| Never-treated controls | Re-run main CS(2021) spec with `control_group = "nevertreated"`. Frame affirmatively: "results hold under an even more restrictive comparison group." |
| Verginer-style double matching | Match each treated inventor to a control inventor with the same pre-deal five-year patent trajectory and primary IPC class; produces inventor-level parallel trends by construction. CS(2021) preferred for the ATT; Verginer reported alongside as an alternative with different identifying assumptions. Agreement between the two substantially strengthens the evidence. |
| Alternative event window | ±3-year post window as a check on the ±5-year baseline |
| Placebo timing | Shift all treatment years by ±3; confirm flat ATTs |
| Control group pre-announcement contamination buffer | Exclude control-inventor-years within two years of the control inventor's own future `deal_year`; tests whether results hold when the not-yet-treated control group is cleaned of imminent-deal inventors |
| Lee-style sensitivity threshold | Report the single threshold sentence — "result survives unless unobservable factors account for more than X% of variance in stayer status" — with the full sensitivity range table cited to the appendix |

**Appendix robustness:**

| Check | Description |
|-------|-------------|
| Horizon-specific stayer cuts | `persistent_stayer_h` at h = 2, 3, 5 and `patent_active_survivor_h` (continuing-patenter intensive margin); full tables in appendix, results cited in one sentence in main text |
| Specialist vs. generalist inventors | Pre-deal IPC Herfindahl split; appendix table |
| Inventor-level DealSim within-deal test | `InvSim_jaccard` within deals with deal fixed effects; appendix robustness for Section 7 |
| DealSim restricted to pharma-relevant IPC classes | Re-compute DealSim using A61K, A61P, C07D, C07K, C12N only; appendix sensitivity check |
| EPO filing-venue diagnostic | Check concentration of count declines among US-headquartered acquirers; appendix |
| Placeholder-acquirer exclusion | Exclude 15 deals with `999xxxx` acquirer IDs; sensitivity of DealSim results |
| Full Lee bounds derivation | Appendix table; main text cites the sensitivity threshold only |
| Full IPW first-stage probit table | Appendix; main text reports Track A/B comparison only |

---

## 13. Theoretical Framework (outline for Section 2 of the thesis)

The theoretical section maps mechanisms to distinct empirical predictions so that the results section can test channels.

**Important scope caveat on mechanism identification**: the mechanisms below are not mutually exclusive. In any real acquisition, several may operate simultaneously — integration disruption early, portfolio rationalisation in the medium term, human-capital reallocation as integration stabilises, and incentive restructuring throughout. This reduced-form design cannot estimate the relative contribution of each mechanism, and several mechanisms can generate similar empirical footprints. It instead tests which empirical *signatures* are present and absent — a pattern-matching approach. A mechanism is "supported" if its distinctive prediction is observed; it is "contradicted" if the opposite pattern holds; mechanisms with overlapping predictions cannot be discriminated by this design, and conclusions are framed accordingly.

| Mechanism | Empirical prediction | Where tested |
|-----------|---------------------|--------------|
| Integration disruption | Count and quality decline attenuates over post-acquisition years; effect largest at t = +1 to +2 and fades toward t = +5 | Section 5 event-study shape |
| Portfolio rationalisation | Patent counts fall; quality per filed patent stable or rises (surviving patents are the better ones; redundant programs terminated, not inventors) | Section 5 + Section 6 |
| Human-capital reallocation | TechDrift rises without a proportional count decline; inventor redirected into acquirer's priorities, not silenced | Section 6 (TechDrift vs. count comparison) |
| Incentive restructuring | Count decline largest among pre-deal high-productivity inventors; incentive changes hit the most productive hardest | Heterogeneity in Section 6 (pre-deal productivity quartile) |
| Product-market replacement effect (scope-limited) | If the acquirer already has a close therapeutic substitute, post-merger cannibalisation concerns may reduce the marginal return to continuing overlapping target research. Patent IPC overlap is only an imperfect proxy for this channel, because it does not directly measure product-market or clinical-indication overlap. This mechanism is therefore treated as a possible interpretation of high-overlap results, not as the central theoretical frame. | Section 7 (DealSim heterogeneity at high DealSim); directional TechDrift decomposition in Section 6 — selective vs. uniform drift |
| Specialist vulnerability vs. specialist protection | High pre-deal IPC Herfindahl identifies narrow specialists. If integration reallocates human capital, specialists should suffer larger output or TechDrift effects; if acquisitions target scarce niche knowledge, specialists may be protected and retained. | Heterogeneity in Section 6 (IPC Herfindahl split) |
| Team disruption | Count and quality decline concentrated among stayers with high `co_leaver_share_i`; effect is immediate and non-attenuating — network damage from co-inventor departure is permanent, unlike organisational friction which dissipates | Section 6 heterogeneity: `co_leaver_share_i` split and event-study slope by tercile |

The DealSim inverted-U conjecture integrates absorptive capacity theory (Cohen and Levinthal, 1990) and portfolio redundancy logic (Ahuja and Katila, 2001) into a single horse-race test at the inventor level. The theoretical contribution of the thesis is not to derive a structural curve from first principles, but to discipline the interpretation of DealSim heterogeneity: recombination gains may dominate at moderate overlap, while redundancy-driven program termination may dominate at high overlap.

**Scope condition**: the five-year post-acquisition window captures early organisational and integration effects on inventor patenting. It does not speak to long-run pipeline consequences, which operate on pharmaceutical R&D cycles of 10–15 years. All estimates should be interpreted as the immediate-to-medium-term effect on individual patent output, not as measures of ultimate drug development outcomes. Furthermore, this thesis relies on patent data as a proxy for early-stage inventive output. Because clinical trial progression, pipeline attrition, drug approvals, and product-market outcomes are outside the available data scope for this master's thesis, ultimate welfare implications cannot be fully resolved.

---

## 14. Preliminary Deliverables

For an initial results package:

| Output | Description |
|--------|-------------|
| **Table 1** | Sample construction: deals by year cohort, deal counts, inventor counts, status shares |
| **Table 2** | Pre-deal balance table: stayers vs. leavers across patent count, OECD quality, career age, IPC Herfindahl, and co-inventor network size; difference-in-means tests; used to validate IPW first-stage covariate set |
| **Figure 1** | Event-study plot: patent output for the full pre-deal target-inventor cohort, t = −5 to +5 |
| **Figure 2** | Stayer event-study plot with two panels: Panel A `persistent_stayer_5` (observed with acquirer and no observed outside departure through five years, allowing later silence); Panel B `patent_active_survivor_5` (continuing-patenter intensive margin, selected on future patent activity) |
| **Figure 3** | Attrition decomposition within `T_Ever_Stayed` over event years t = 0 to +5: four-way stacked plot showing shares of (1) active with acquirer, (2) outside departure, (3) silent/gap (career ongoing), (4) career exit — provides honest context for reading the event-study shape in Figure 2 |
| **Figure 4** | DealSim tercile ATT plot: average treatment effect on patent count by DealSim tercile |
| **Validation table** | Own reconstructed status classification vs. Cassi–Ornaghi reference benchmark |

---

## 15. Central Message

> Pharmaceutical acquisitions may preserve inventor employment relationships without necessarily preserving inventive output. While human capital retention is an important metric of acquisition success, it may mask shifts in underlying inventive capacity. Among retained inventors, the effect of an acquisition depends critically on how similar the acquirer's and target's technology portfolios were before the deal — with the largest declines in patenting occurring at the extremes of technological overlap.

---

## Key References

- Ahuja, G. and Katila, R. (2001). Technological acquisitions and the innovation performance of acquiring firms: a longitudinal study. *Strategic Management Journal*, 22(3), 197–220.
- Arrow, K. J. (1962). Economic welfare and the allocation of resources for invention. In R. R. Nelson (Ed.), *The Rate and Direction of Inventive Activity*. Princeton University Press.
- Callaway, B. and Sant'Anna, P. H. C. (2021). Difference-in-differences with multiple time periods. *Journal of Econometrics*, 225(2), 200–230.
- Cohen, W. M. and Levinthal, D. A. (1990). Absorptive capacity: a new perspective on learning and innovation. *Administrative Science Quarterly*, 35(1), 128–152.
- Cunningham, C., Ederer, F. and Ma, S. (2021). Killer acquisitions. *Journal of Political Economy*, 129(3), 649–702.
- Lee, D. S. (2009). Training, wages, and sample selection: estimating sharp bounds on treatment effects. *Review of Economic Studies*, 76(3), 1071–1102.
- Seru, A. (2014). Firm boundaries matter: evidence from conglomerates and R&D activity. *Journal of Financial Economics*, 111(2), 381–405.
- Verginer, L., Parisi, F., van Lidth de Jeude, J. and Riccaboni, M. (2026). The impact of acquisitions on inventors' turnover in the biotechnology industry. Working paper.
- Cassi, L. and Ornaghi, C. (2026). [Leaver and post-acquisition inventor mobility paper — cite full reference when available.]
