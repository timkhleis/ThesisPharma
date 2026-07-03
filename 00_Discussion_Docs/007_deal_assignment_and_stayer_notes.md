# Deal Assignment and Stayer Classification Notes

**Purpose:** Notes for the next deliverable to Prof. Cassi. These record the current empirical-design decisions, remaining questions, and caveats that should be made explicit.

---

## 1. Deal Assignment: Current Status

The empirical design separates treatment timing from acquirer identity. The final full-cohort CS(2021) design does not require acquirer identity, but the first-results estimate uses the uniquely matched target-spine subset because the 22 unmatched merger-list deals do not yet have a validated target-group fallback. Analyses that require acquirer identity, especially DealSim and the reconstructed stayer classification, use the narrower acquirer-resolved subset of the Cassi-provided group-history files:

- `L_group_history_target.dta`: company-year group history, including merger-related group changes.
- `L_merge.dta`: Zephyr/BvD merger information used by Cassi-Ornaghi to construct the group-history merger rows.

The acquirer-identity linkage is therefore:

```text
dealnumber -> target compcod -> group-history transition -> pre/post group IDs
```

The older `(target_year, target_value)` bridge and `inventor_status_reference` remain useful as validation benchmarks, but they are no longer the primary source for acquirer-group assignment.

## 1.1 Effective Deal Counts by Analysis Layer

The main full-cohort analysis and the DealSim analysis do not use exactly the same deal universe.

- The main CS(2021) full-cohort analysis can use the broad treatment-timing sample because it does not require acquirer group identity.
- DealSim requires clean target and acquirer group identifiers, so it is restricted to deals resolved in the group-history spine with non-placeholder acquirer groups.

Current counts using the 513-deal `merger_list` universe:

| Analysis window | Merger-list deals | Unique year-value matches | Target spine after `todrop_tar` | Status-eligible after acquirer resolution and `todrop_acq` |
|---|---:|---:|---:|---:|
| Unrestricted merger-list window | 513 | 490 | 478 | 444 |
| Five-year event window, 1993--2010 | 372 | 354 | 345 | 326 |

The correction matters because `L_group_history_target` is broader than the published 513-deal sample. Before the 513-deal restriction was implemented, the reconstructed spine contained 594 dealnumbers and 520 entered `inventor_status_own`. Those figures mixed additional Zephyr/group-history events with the thesis sample and are retired. The corrected code anchors every deal to `deal_map.deal_id`, excludes 22 unmatched merger-list rows and one ambiguous 2008/25,000 match, and applies Cassi's target- and acquirer-side drop flags.

Design decision:

> Do not force all analyses onto the DealSim-resolved sample as the main sample. Use the broad clean treatment-timing sample for the main full-cohort ATT, restrict DealSim analyses to deals with clean acquirer group IDs, and report a common-sample robustness check using the DealSim-resolved deals.

Interpretation:

> The new group-history spine does not mainly increase the DealSim sample size; it improves the quality of acquirer identification. This matters because the target-acquirer cosine similarity is only meaningful if the acquirer group ID is cleanly assigned.

## 2. Deals With Missing Acquirer Groups

The raw deal spine contains cases with `ACQUIRER_GROUP_MISSING`. These are not simply missing names. They generally have acquirer names, but lack reliable acquirer group assignment.

Current audit facts:

- 102 target-company rows.
- 53 dealnumbers.
- 0 missing acquirer names.
- 100 of 102 rows missing `acquirer_compcod`.
- All 102 rows have placeholder post-group IDs of the form `999xxxx`.
- All 102 rows have `todrop_acq = 1`.

Decision:

> Exclude merger rows flagged by Cassi-Ornaghi as problematic on the acquirer side (`todrop_acq = 1`). These cases typically have unresolved placeholder post-merger group identifiers (`999xxxx`) and cannot be assigned a reliable acquirer group for inventor-level retention classification.

Question for Prof. Cassi:

> Should deals with `todrop_acq = 1` and placeholder post-acquirer group `999xxxx` be excluded from the inventor-level event-study sample, or is there an intended fallback mapping for these cases?

## 3. Fallback Acquirer Assignment

Some deals do not have explicit acquirer-company linkage but show a clean target group transition. In these cases, the target's post-merger group is used as the acquirer-group fallback.

Current corrected-sample audit fact:

- 10 deals with assigned inventors use `target_post_group_fallback`.
- No explicit `L_merge` acquirer/target names.
- No `year_merge`.
- Acquirer group inferred from `target_group_post`.

Decision:

> Keep these fallback deals in the baseline for now, but flag them and report a robustness check excluding them.

Suggested deliverable wording:

> A small set of deals lacks explicit acquirer-company linkage but exhibits a clean post-merger target group change. These are retained using the post-merger group as the acquirer-group fallback and flagged in robustness checks.

## 4. Treatment Year Mismatch

There is one observed mismatch between the group-history transition year and the Zephyr merger year.

Current audit fact:

- Corange Ltd / Roche Holding AG:
  - `deal_year = 1997` from group history.
  - `year_merge = 1998` from Zephyr.
  - Affects 5 target-company rows.

Current decision:

> Use the group-history transition year as treatment timing because the event study measures exposure to organizational group integration, not necessarily legal closing date.

Question for Prof. Cassi:

> When `L_group_history_target.year` differs from `L_merge.year_merge`, should the event-study treatment year follow the group-history transition year or the Zephyr legal merger year?

## 5. Reference Classification Mismatch

The own classification only partially overlaps with the Cassi-Ornaghi reference `T_STAYER` and `T_LEAVER` labels.

Current audit facts:

- `T_STAYER`: 3,738 overlapping inventors out of 7,110 in the benchmark, match rate about 52.6%.
- `T_LEAVER`: 987 overlapping inventors out of 2,692 in the benchmark, match rate about 36.7%.

Interpretation:

This is not necessarily an error. The thesis classification uses a fixed-window pre-deal target-cohort design, while the reference labels appear closer to the original Cassi-Ornaghi spell/status classification.

Deliverable note:

> Mention explicitly to Prof. Cassi that the own classification only partially overlaps with the published `T_STAYER`/`T_LEAVER` reference, likely because the thesis uses a fixed five-year post-deal cohort definition rather than the original spell-level status construction.

## 5.1 Comparison to Cassi-Ornaghi Status Figures

The deal-level M&A data replicate Cassi-Ornaghi closely because both use the same `merger_list` source.

| Item | Cassi-Ornaghi | Thesis data |
|---|---:|---:|
| Deals | 513 | 513 |
| Big deals | 63 | 63 |
| Mean target value | 2,679,925 | 2,679,926 |
| Min value | 10,050 | 10,050 |
| Max value | 93,409,440 | 93,409,440 |

For inventor status, the absolute counts differ, but the stay/leave split among observed post-deal stayers and leavers is close.

| Source | Stayers | Leavers | Stay + Leave | Stayer share |
|---|---:|---:|---:|---:|
| Cassi-Ornaghi Table 2 | 7,104 | 2,675 | 9,779 | 72.6% |
| Thesis rebuilt classification | 4,419 | 1,771 | 6,190 | 71.4% |

Interpretation:

> The reconstructed stay/leave split is close to Cassi-Ornaghi's Table 2 among inventors with observed post-deal mobility or retention. The absolute number of observed stayers and leavers is smaller because the thesis imposes a fixed five-year post-deal window and a stricter group-history-based cohort assignment, while Cassi-Ornaghi's published status table reflects their broader spell-level classification.

Important note:

> This difference is not necessarily a data error. It follows from the thesis design choice to keep the full pre-deal target-inventor cohort and classify no-post inventors separately as `T_NO_POST_5Y`, rather than restricting attention to the observed stay/leave spell population.

Implemented diagnostic:

> The five-year status window intentionally aligns the mobility classification with the event-study outcome horizon. Cassi-Ornaghi's higher active stayer/leaver count may reflect a broader observed-career status window. To quantify this, the thesis now reports an unrestricted post-deal status diagnostic: inventors are flagged if they ever patent with the acquirer or with an outside group after the deal year, without imposing the five-year upper bound. The diagnostic is used only to explain the count gap relative to Cassi-Ornaghi; it does not redefine the frozen five-year MECE status categories used in the main analysis.

Current audit result:

> Removing the five-year upper bound increases the active stay/leave count from 6,190 to 6,688 in the full sample, and from 5,822 to 6,316 in the clean 1993-2010 sample. The unrestricted diagnostic therefore narrows, but does not eliminate, the gap to Cassi-Ornaghi's 9,779 active stayers/leavers. This suggests that the count difference is only partly due to late post-year-5 reappearance; the matched-spine restriction and stricter cohort construction also matter.

Implemented target-cohort reconciliation:

> The target-inventor cohort is now assigned using deal-specific pre-treatment evidence in the five-year pre-window. The main rule includes inventors whose latest pre-deal active year resolves to the target group, inventors whose latest pre-deal candidate group list contains the target group, and a narrow `t = -1` acquirer-transition case where the first pre-deal acquirer-resolved year is exactly `deal_year - 1` and the inventor had recent target evidence immediately before. This corrects annual-compression cases without using post-treatment Cassi status labels.

Deliverable note:

> Report the new `target_assignment_rule_counts.csv` audit to Prof. Cassi. It separates `resolved_latest`, `candidate_latest`, and `acquirer_transition_strict` cases, so we can show how much of the mismatch comes from affiliation-resolution mechanics rather than from the post-deal stayer/leaver definition.

Current audit result:

> Within the status-eligible sample, the target-cohort assignment contains 28,759 `resolved_latest`, 2,239 `candidate_latest`, and 359 `acquirer_transition_strict` inventors. In the clean 1993-2010 window, the corresponding counts are 25,102, 2,065, and 343. The non-resolved rules therefore recover a meaningful but still bounded set of pre-treatment target inventors.

## 6. Multiple Target Companies Per Deal

Multiple target companies per deal are expected in merger data and are not, by themselves, a problem.

Important audit result:

> After aggregation, the usable group spine does not map any deal to multiple target/acquirer group rows.

This suggests that the company-level multiplicity does not create ambiguous group-level treatment assignment in the current spine.

## 7. Multiple Candidate Exposures Per Inventor

Some inventors are candidate-treated by more than one acquisition event.

Current audit facts:

- Total inventors in `target_cohort_own`: 32,438.
- Inventors with multiple candidate exposures: 658.
- Share affected: 2.03%.
- Maximum candidate exposures: 3.

Decision:

> Keep each inventor at the earliest observed acquisition exposure.

Reason:

Event-study DiD requires a clean first treatment date. Once an inventor has already been exposed to an acquisition, later "pre-periods" are potentially already post-treatment relative to the first deal. Keeping the first exposure preserves a clean event-time interpretation.

Robustness check:

> Exclude multi-exposure inventors entirely and confirm that main results are unchanged.

Question for Prof. Cassi:

> Does the earliest-exposure rule match the intended treatment assignment convention in the Cassi-Ornaghi data, or is there a preferred way to handle inventors appearing in multiple acquisition events?

## 8. Stayer Classification: Current Conceptual Decisions

The old `T_STAYER` definition, "at least one acquirer-affiliated patent in the five-year post-deal window," is better understood as an ever-retained measure.

Naming decision:

> Rename or describe baseline `T_STAYER` conceptually as `T_Ever_Stayed`: at least one post-deal patent affiliated with the acquirer group within five years.

Important caveat:

> This is an "ever observed with acquirer" measure, not evidence of continuous five-year retention.

### 8.1 Classification Freeze and Analysis Use

Decision as of 29 June 2026:

> Freeze the revised classification for the first-results analysis. The method is spell-informed because it reconstructs annual target, acquirer, and outside-group affiliations, but the primary MECE status remains defined over the fixed five-year post-deal window. Cassi-Ornaghi's career-wide spell labels remain an external validation benchmark rather than the thesis's assignment rule.

The aggregate comparison supports moving forward: among inventors classified as active stayers or leavers, the thesis stayer share is 71.4%, compared with 72.6% in Cassi-Ornaghi. The remaining differences in absolute counts and inventor-level overlap should be reported as consequences of the matched-spine restriction, fixed event window, stricter pre-deal cohort construction, group-resolution rules, and earliest-exposure assignment. They do not currently justify changing the frozen classification.

Use the classification as follows:

- Estimate the main CS(2021) effects on the full pre-deal target-inventor cohort, without conditioning on post-deal status.
- Use `T_Ever_Stayed` for the conservative acquirer-observed stayer analysis.
- Add `T_TARGET_CONTINUING` only in the expanded retained-sample robustness check.
- Use `persistent_stayer_h` for horizon-specific survivor robustness.
- Use `patent_active_survivor_h` for the continuing-patenter intensive margin and label it as a selected post-treatment sample.
- Keep the Cassi-Ornaghi comparison, unrestricted post-deal diagnostic, and assignment-rule decomposition as validation material for the supervisor deliverable.

Reopen the classification only if a failed invariant, a material coding error, or new information from Prof. Cassi changes the interpretation of the underlying group-history fields.

## 9. Dynamic Stayer Refinement

The following options were rejected:

- Dynamic `T_STAYER_t` defined as "patented with acquirer in year t or later," because it uses future information.
- Presence-based yearly stayer status requiring a patent in year h, because patenting is lumpy in pharma and the rule mechanically conditions on the patent-count outcome.
- Heckman selection correction, because no credible exclusion restriction is currently available.

Planned classification architecture:

| Object | Interpretation |
|---|---|
| `T_Ever_Stayed` | Main Layer 2 sample: ever observed with acquirer within five years |
| `persistent_stayer_h` | Horizon survivor robustness: at least one acquirer-affiliated patent by horizon h and no observed non-acquirer patent through h; allows patenting gaps after initial acquirer observation and does not condition on future patent activity after h |
| `patent_active_survivor_h` | Selected intensive-margin robustness only |
| `career_end_year` | Descriptive attrition state, not regression filter |
| `first_outside_year` | Descriptive departure timing |
| `short_stayer` | Descriptive subgroup, robust to 1/2/3-year cutoffs |

Key wording discipline:

> The preferred Layer 2 specification uses the broad ever-acquirer sample; horizon-specific persistent-stayer samples are reported as survivor-sample robustness checks, and patent-active survivor samples are interpreted only as selected intensive-margin estimates.

## 10. Lee Bounds and Selection Language

Do not call Lee bounds a clean correction for the stayer selection problem.

Reason:

The monotonicity assumption is doubtful in this setting. Acquisitions can induce retention through retention packages or acqui-hire motives, so acquisition may cause some inventors to stay who otherwise would have left.

Preferred wording:

> Lee-style bounds provide a sensitivity range for the stayer ATT under alternative trimming assumptions; they do not identify the SACE because monotonicity is not assumed.

## 11. IPC Herfindahl: Specialist vs. Generalist Inventors

IPC Herfindahl should be treated as more than a selection-control variable. It measures how concentrated an inventor's pre-deal patenting is across IPC technology classes:

```text
HHI_i = sum_k s_ik^2
```

where `s_ik` is inventor i's pre-deal share of IPC assignments in class k.

Interpretation:

- High IPC Herfindahl: narrow technological specialist.
- Low IPC Herfindahl: broader technological generalist.

Empirical use:

> Use IPC Herfindahl in the balance table and IPW first stage, but also report specialist-vs-generalist heterogeneity. Specialists may be more harmed if acquisition redirects them away from a narrow knowledge niche, but may be protected if the acquirer bought the target precisely for their niche expertise.

This is a useful mechanism test because both signs are economically meaningful.

## 12. Items To Ask Prof. Cassi

1. Should `todrop_acq = 1` cases with placeholder `999xxxx` post-groups be excluded, or is there an intended fallback mapping?
2. For year mismatches, should treatment timing follow group-history transition year or Zephyr legal merger year?
3. Does the earliest-exposure rule for multi-exposure inventors match the intended convention?
4. Should fallback acquirer assignments based on `target_group_post` be retained in the baseline or only in robustness?
5. Is the partial overlap with the reference `T_STAYER`/`T_LEAVER` classification expected given our fixed-window cohort definition?
