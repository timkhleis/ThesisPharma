# Final thesis results inventory: 1993--2010 cohort release

This is the authoritative map from thesis claims to result artifacts and code.
Every estimation sample starts in 1993. The complete machine-readable index is
`FINAL_THESIS_RELEASE_1993/final_thesis_results_registry_1993.csv` in the audit output.

## Main full-cohort results

Average annual t=+1,...,+5 Local Match v2 estimates; 9,999-draw deal-wild inference.

| Outcome | ATT | 95% CI | p | Status | Code |
|---|---:|---:|---:|---|---|
| patent_count | -0.0521 | [-0.0898, -0.0147] | 0.0074 | primary | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| active_patenting | -0.0174 | [-0.0381, 0.0029] | 0.0868 | primary | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| tech_drift | 0.0068 | [-0.0247, 0.0393] | 0.6655 | qualified: joint pretrend rejected | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| pqii_scaled | -0.0104 | [-0.0197, -0.0016] | 0.0225 | primary | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| fwd_cits5_scaled | -0.0022 | [-0.1217, 0.1282] | 0.9771 | primary | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |

## Key newly built robustness results

| Specification | Outcome | ATT | 95% CI | p | Code |
|---|---|---:|---:|---:|---|
| Alternative post window, t=+1,...,+3 | patent_count | -0.0518 | [-0.0916, -0.0131] | 0.0097 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | patent_count | -0.1554 | [-0.2747, -0.0393] | 0.0097 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | active_patenting | -0.0141 | [-0.0379, 0.0091] | 0.2181 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | active_patenting | -0.0424 | [-0.1136, 0.0274] | 0.2181 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | tech_drift | 0.0009 | [-0.0292, 0.0309] | 0.9475 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | tech_drift | 0.0028 | [-0.0876, 0.0926] | 0.9475 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | pqii_scaled | -0.0099 | [-0.0185, -0.0017] | 0.0195 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | pqii_scaled | -0.0297 | [-0.0555, -0.0051] | 0.0195 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | fwd_cits5_scaled | -0.0074 | [-0.1308, 0.1286] | 0.9106 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Alternative post window, t=+1,...,+3 | fwd_cits5_scaled | -0.0221 | [-0.3925, 0.3859] | 0.9106 | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Treatment timing shifted three years early | patent_count | 0.0064 | [-0.0406, 0.0549] | 0.7914 | [`53_run_lmv2_timing_placebo.R`](../R/53_run_lmv2_timing_placebo.R) |
| Treatment timing shifted three years early | patent_count | 0.0127 | [-0.0813, 0.1099] | 0.7914 | [`53_run_lmv2_timing_placebo.R`](../R/53_run_lmv2_timing_placebo.R) |
| Treatment timing shifted three years early | active_patenting | 0.0083 | [-0.0193, 0.0374] | 0.5483 | [`53_run_lmv2_timing_placebo.R`](../R/53_run_lmv2_timing_placebo.R) |
| Treatment timing shifted three years early | active_patenting | 0.0166 | [-0.0386, 0.0749] | 0.5483 | [`53_run_lmv2_timing_placebo.R`](../R/53_run_lmv2_timing_placebo.R) |

## Collaboration-network gate

The strict persistent-tie design uses one governing outcome: the share of baseline collaborators who remain patent-active in the focal organization while observable and at risk.

| Held-out event time | Treated-control gap | 95% CI | p |
|---:|---:|---:|---:|
| -2 | -0.0227 | [-0.0722, 0.0267] | 0.3671 |
| -1 | -0.1053 | [-0.1508, -0.0597] | 0.0001 |

The joint held-out test has p=0.0001 and the largest 80% MDE is 0.0706, versus the frozen 0.05 threshold. N1 therefore selects Path F and no positive-event network outcome is opened.
The strict retained companion contains 574 inventors across 75 deals (24.8736 effective deals) and remains blocked by the full-cohort gate.
No Holm-adjusted p-value is reported because the amended design has one governing network outcome.
A provisional endpoint-conditioned denominator was superseded before any positive event time was opened; partner patenting cessation is treated as an observed zero, not denominator attrition.

## Extensive/intensive decomposition

| Population | Component | Contribution | Interpretation | Code |
|---|---|---:|---|---|
| Pre-deal target-inventor cohort | extensive_active_patenting | -0.0380 | Order-invariant Shapley contribution of the active-patenting margin. Share: 73.0%. | [`58_build_final_thesis_release_1993.R`](../R/58_build_final_thesis_release_1993.R) |
| Pre-deal target-inventor cohort | intensive_patents_per_active_year | -0.0140 | Order-invariant Shapley contribution of patents per active inventor-year; descriptive conditioning on post-treatment activity. Share: 27.0%. | [`58_build_final_thesis_release_1993.R`](../R/58_build_final_thesis_release_1993.R) |
| Initially retained inventors | extensive_active_patenting | -0.0256 | Order-invariant Shapley contribution of the active-patenting margin. Share: 26.7%. | [`58_build_final_thesis_release_1993.R`](../R/58_build_final_thesis_release_1993.R) |
| Initially retained inventors | intensive_patents_per_active_year | -0.0703 | Order-invariant Shapley contribution of patents per active inventor-year; descriptive conditioning on post-treatment activity. Share: 73.3%. | [`58_build_final_thesis_release_1993.R`](../R/58_build_final_thesis_release_1993.R) |

## Coverage and identification status

| Section | Result | Status | Code |
|---|---|---|---|
| Main results | Local Match v2 ATT, t=+1,...,+5 | primary | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| Main results | Local Match v2 ATT, t=+1,...,+5 | qualified: joint pretrend rejected | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| Identification diagnostic | Local Match joint pretreatment test | passes reporting threshold | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| Identification diagnostic | Local Match joint pretreatment test | pretrend rejected | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| Initially retained | Initially retained matched ATT, t=+1,...,+5 | selected-population result | [`28b_run_lmv2_p5b_s4_estimation.R`](../R/28b_run_lmv2_p5b_s4_estimation.R) |
| Initially retained | Initially retained matched ATT, t=+1,...,+5 | selected-population result | [`30_run_lmv2_p5b_secondary_outcomes.R`](../R/30_run_lmv2_p5b_secondary_outcomes.R) |
| Robustness | Alternative post window, t=+1,...,+3 | completed | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Robustness | Treatment timing shifted three years early | completed | [`53_run_lmv2_timing_placebo.R`](../R/53_run_lmv2_timing_placebo.R) |
| Co-equal identification | CS(2021), notyettreated, anticipation=0, post window 1:3 | qualified: pretrend rejected or unavailable | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| Co-equal identification | CS(2021), notyettreated, anticipation=0, post window 1:5 | qualified: pretrend rejected or unavailable | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| Co-equal identification | CS(2021), notyettreated, anticipation=1, post window 1:3 | qualified: pretrend rejected or unavailable | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| Co-equal identification | CS(2021), notyettreated, anticipation=1, post window 1:5 | qualified: pretrend rejected or unavailable | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| Co-equal identification | CS(2021), notyettreated, anticipation=1, failed stage aggte_dynamic | unavailable after attempted estimation | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| Co-equal identification | CS(2021), nevertreated, anticipation=0, failed stage control_group_support | unavailable after attempted estimation | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| Co-equal identification | CS(2021), nevertreated, anticipation=1, failed stage control_group_support | unavailable after attempted estimation | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| Decomposition | Three-factor patent-count accounting decomposition | accounting component | [`36c_estimate_lmv2_exit_decomposition.R`](../R/36c_estimate_lmv2_exit_decomposition.R) |
| Decomposition | Three-factor patent-count accounting decomposition | completed | [`36c_estimate_lmv2_exit_decomposition.R`](../R/36c_estimate_lmv2_exit_decomposition.R) |
| Decomposition | Full-cohort two-factor Shapley decomposition | accounting decomposition | [`58_build_final_thesis_release_1993.R`](../R/58_build_final_thesis_release_1993.R) |
| Decomposition | Retained two-factor Shapley decomposition | accounting decomposition | [`58_build_final_thesis_release_1993.R`](../R/58_build_final_thesis_release_1993.R) |
| Mechanism diagnostic | TechDrift-quality within-retained association | association only | [`54_run_lmv2_mechanism_selection.R`](../R/54_run_lmv2_mechanism_selection.R) |
| Classification diagnostic | T_NO_POST_5Y career-age comparison | completed | [`54_run_lmv2_mechanism_selection.R`](../R/54_run_lmv2_mechanism_selection.R) |
| DealSim | Exploratory DealSim tercile: low | exploratory after failed prospective power gate | [`55_run_dealsim_exploratory.R`](../R/55_run_dealsim_exploratory.R) |
| DealSim | Exploratory DealSim tercile: middle | exploratory after failed prospective power gate | [`55_run_dealsim_exploratory.R`](../R/55_run_dealsim_exploratory.R) |
| DealSim | Exploratory DealSim tercile: high | exploratory after failed prospective power gate | [`55_run_dealsim_exploratory.R`](../R/55_run_dealsim_exploratory.R) |
| Team disruption | Persistent pre-deal tie support census | original support gate failed | [`56_run_lmv2_network_census.R`](../R/56_run_lmv2_network_census.R) |
| Team disruption | Partner focal-organization persistence, t=-2 | validation gate failed | [`61_run_lmv2_network_n1.R`](../R/61_run_lmv2_network_n1.R) |
| Team disruption | Partner focal-organization persistence, t=-1 | validation gate failed | [`61_run_lmv2_network_n1.R`](../R/61_run_lmv2_network_n1.R) |
| Team disruption | Network N1 release decision | failed validation and precision gate | [`61_run_lmv2_network_n1.R`](../R/61_run_lmv2_network_n1.R) |
| Team disruption | Initially retained strict-tie support census | blocked after failed full-cohort N1 gate | [`63_census_lmv2_retained_network_support.R`](../R/63_census_lmv2_retained_network_support.R) |
| Selection | Lee-bounds identification decision | not identified under defensible assumptions | [`57_certify_selection_bounds_decision.R`](../R/57_certify_selection_bounds_decision.R) |
| Robustness | Full robustness battery | completed | [`49a_build_lmv2_1993_robustness_release.R`](../R/49a_build_lmv2_1993_robustness_release.R) |
| Co-equal identification | Verginer-style matched comparison | completed with design-specific qualification | [`24a_run_lmv2_verginer_early_recruitment_p6.R`](../R/24a_run_lmv2_verginer_early_recruitment_p6.R) |

## Thesis requirement matrix

| Requirement | Build status | Thesis action | Code |
|---|---|---|---|
| Full-cohort patent count and active-patenting ATT | built and primary | Main table and event study. | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| Full-cohort PQII, forward-citation, and TechDrift outcomes | built; TechDrift is pretrend-qualified | Main/secondary table; qualify TechDrift. | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| Initially retained quantity, quality, citations, and TechDrift | built; selected-population interpretation | Retained-inventor section with selection caveat. | [`30_run_lmv2_p5b_secondary_outcomes.R`](../R/30_run_lmv2_p5b_secondary_outcomes.R) |
| Full-cohort cessation/activity/intensity decomposition | built as accounting decomposition | Mechanism accounting table. | [`36c_estimate_lmv2_exit_decomposition.R`](../R/36c_estimate_lmv2_exit_decomposition.R) |
| Full-cohort extensive/intensive Shapley decomposition | built as accounting decomposition | Extensive/intensive table; intensive part is descriptive. | [`58_build_final_thesis_release_1993.R`](../R/58_build_final_thesis_release_1993.R) |
| Initially retained extensive/intensive Shapley decomposition | built as accounting decomposition | Retained extensive/intensive table; intensive part is descriptive. | [`58_build_final_thesis_release_1993.R`](../R/58_build_final_thesis_release_1993.R) |
| Local Match formal pretreatment tests | built | Report p-values with outcome tables. | [`19c_run_lmv2_p6_estimation.R`](../R/19c_run_lmv2_p6_estimation.R) |
| Short post window (+1 through +3) | built | Robustness table. | [`52_run_lmv2_short_window.R`](../R/52_run_lmv2_short_window.R) |
| Treatment timing shifted three years early | built and null for count/activity | Robustness table. | [`53_run_lmv2_timing_placebo.R`](../R/53_run_lmv2_timing_placebo.R) |
| Treatment timing shifted three years late | not identified: pseudo-preperiod overlaps true treatment | State why it is not a valid placebo; do not estimate it. | [`53_run_lmv2_timing_placebo.R`](../R/53_run_lmv2_timing_placebo.R) |
| CS(2021) not-yet-treated, anticipation 0 and 1 | attempted; available cells fail pretrend gate and one did aggregation cell is unavailable | Use as failed-diagnostic evidence, not as a causal main result. | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| CS(2021) never-treated robustness, anticipation 0 and 1 | not identified: repaired CS spine contains zero g=0 never-treated units | State that this robustness is infeasible in the repaired CS spine; Local Match supplies the separate never-observed-target comparison. | [`51_run_cs2021_1993.R`](../R/51_run_cs2021_1993.R) |
| Verginer-style matched companion design | built with design-specific support qualification | Co-equal design with its own qualification. | [`24a_run_lmv2_verginer_early_recruitment_p6.R`](../R/24a_run_lmv2_verginer_early_recruitment_p6.R) |
| Broader weight/outcome/inference/placebo robustness battery | built | Appendix and compact robustness table. | [`49a_build_lmv2_1993_robustness_release.R`](../R/49a_build_lmv2_1993_robustness_release.R) |
| Stayer-versus-leaver pre-deal selection comparison | built; retained inventors are positively selected on pre-deal patenting | Discuss direction of selection bias. | [`29a_lmv2_p5b_selection_diagnostics.R`](../R/29a_lmv2_p5b_selection_diagnostics.R) |
| Lee bounds for post-treatment retention selection | not identified under defensible maintained assumptions | Remove the promised numerical bounds and state the identification reason. | [`57_certify_selection_bounds_decision.R`](../R/57_certify_selection_bounds_decision.R) |
| TechDrift-quality mechanism diagnostic | built as association, not ATT | Mechanism diagnostic only. | [`54_run_lmv2_mechanism_selection.R`](../R/54_run_lmv2_mechanism_selection.R) |
| T_NO_POST_5Y management-transition diagnostic | built; management-transition interpretation not supported | Classification caveat: evidence points away from senior management exit. | [`54_run_lmv2_mechanism_selection.R`](../R/54_run_lmv2_mechanism_selection.R) |
| DealSim tercile, quadratic, and spline patterns | built as exploratory only after failed power gate | Appendix/descriptive figure; no confirmatory inverted-U claim. | [`55_run_dealsim_exploratory.R`](../R/55_run_dealsim_exploratory.R) |
| DealSim by deal-size regime | not estimated after failed DealSim power gate | List as power-gated future work, not a missing regression to fill post hoc. | [`55_run_dealsim_exploratory.R`](../R/55_run_dealsim_exploratory.R) |
| Persistent-team-tie post-acquisition effect | not estimated after failed held-out validation and precision gate | Report the N1 gate result: the t=-1 gap is nonzero and precision is below the frozen threshold; no post-treatment effect is opened. | [`61_run_lmv2_network_n1.R`](../R/61_run_lmv2_network_n1.R) |
| Inventor productivity and team heterogeneity | built for feasible cells; failed prospective cells remain appendix-only | Report only pre-specified feasible cells and omnibus qualification. | [`31c_estimate_lmv2_inventor_heterogeneity.R`](../R/31c_estimate_lmv2_inventor_heterogeneity.R) |
| VR and retained-inventor heterogeneity | built for cells passing prospective power/balance gates | Report gate outcomes and feasible contrasts. | [`32_run_lmv2_vr_heterogeneity.R`](../R/32_run_lmv2_vr_heterogeneity.R) |

## Required thesis qualifications

- TechDrift rejects its Local Match joint pretrend test and is not a clean causal result.
- CS(2021) is a co-equal not-yet-treated companion, but each outcome must be read with its own pretrend result.
- DealSim estimates are exploratory because the prospective power gate selected Path U; they do not confirm the inverted-U hypothesis.
- The strict persistent-tie N1 gate fails: the t=-1 partner-persistence gap is nonzero and the design cannot detect the frozen 0.05 effect. No post-treatment network effect is estimated.
- Ordinary Lee bounds are not reported because defensible monotonicity/exchangeability and bounded-support conditions are not established.
- The retained-inventor decomposition is an exact Shapley accounting identity; its intensive component conditions descriptively on post-treatment activity.

## One-command refresh

Run `Rscript 02_analysis/R/60_run_final_thesis_results_1993.R` from the thesis root after the expensive estimator artifacts exist, or add `--rebuild-new` to rerun all new packages.
