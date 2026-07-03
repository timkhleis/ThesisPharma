# Verginer–Riccaboni Reconstruction

## Bottom line

The reconstruction does **not** improve the credibility of parallel trends. It successfully recovers the earlier Verginer-style sample (29,533 inventors and 348 deals), but neither announcement timing nor deal-survival selection removes the patent-count lead pattern. Under the corrected universal-base, event-balanced specification, the patent estimate at (t=-3) is (+0.065), with a simultaneous 95% interval of ([0.029,,0.102]). Three of four reported patent leads then exclude zero.

The decision rule is therefore met: close the Verginer-reconstruction branch and proceed to the never-treated construction placebo and calendar-symmetric, deal-disjoint risk-set design. The survival filter and forward-looking outcomes should not become the primary identification strategy.

## What was reconstructed

The standalone script `02_analysis/R/08p_verginer_reconstruction.R` reads the existing database in read-only mode and implements:

- a sample ladder from the full estimation cohort to acquirer and merged-entity survival;
- announcement-year treatment timing using `deal_map.target_year`;
- log annual patents, log OECD five-year forward citations, forward-looking R&D activity, and forward-looking exit;
- not-yet-treated Callaway–Sant’Anna estimates with doubly robust estimation, no anticipation, varying base periods, no balancing, and no covariates;
- corrected estimates with a universal base, `balance_e=5`, and 999 multiplier-bootstrap draws clustered by `deal_id`;
- a separate analytical comparison using the current predetermined covariates.

The 999-draw bootstrap is applied to the reported dynamic aggregation. Group-time influence functions are estimated analytically, avoiding a redundant first-stage bootstrap.

## Sample and data audits

The requested operational sample was recovered exactly:

| Sample | Inventors | Deals |
|---|---:|---:|
| Full estimation cohort | 32,265 | 450 |
| Acquirer patents after acquisition | 29,533 | 348 |
| Target-or-acquirer patents after acquisition | 29,533 | 348 |
| Literal old target group survives five years | 606 | 6 |

Across the complete 478-deal spine, only 6 deals retain the literal old target identifier during the five-year post-deal window. This is a mapping failure, not evidence that 472 targets stopped R&D: target identifiers generally transition to the acquirer. The operational merged-entity criterion is therefore the defensible interpretation, although it remains a post-treatment deal-selection rule.

All 450 estimation deals have identical `deal_year` and `deal_map.target_year`; there are zero announcement/integration-year disagreements. “Correcting” timing consequently cannot change any estimate in these data.

All outcome audits pass:

- inventor-year observations are unique;
- annual patent counts match counts from distinct patent–inventor links;
- `vr_rd_activity` matches the career endpoint and is weakly decreasing;
- `vr_left` matches the final target/acquirer patent endpoint and is weakly increasing;
- OECD five-year forward citations are nonnegative.

## Main estimates

### Patent quantity

| Specification | (t=-3) | (t=0) | (t=5) | Average ATT, (0\ldots5) |
|---|---:|---:|---:|---:|
| Paper conventions, full cohort | +0.014 | −0.142 | −0.336 | −0.242 |
| Add acquirer survival | +0.016 | −0.146 | −0.354 | −0.256 |
| Add merged-entity survival | +0.016 | −0.146 | −0.354 | −0.256 |
| Paper-faithful, deal-clustered | +0.016 | −0.146 | −0.354 | −0.256 (SE 0.017) |
| Corrected base/balance, deal-clustered | **+0.065** | −0.157 | −0.354 | −0.264 (SE 0.017) |
| Predetermined controls, analytical only | +0.043 | −0.165 | −0.372 | −0.273 |

The corrected estimates are close to the earlier partial emulation: (t=-3=+0.065) versus (+0.070), (t=0=-0.157) versus (−0.159), and (t=5=-0.354) versus (−0.373). The small differences arise from the exact operational filter and the deliberately separated covariate comparison.

The controls do not rescue the design. They reduce the (t=-3) coefficient from (+0.065) to (+0.043), but the controlled DR models generate, for each outcome, 201 overlap warnings, 120 ill-conditioned-covariate warnings, and an extreme fitted-probability warning. Those estimates are reported as a support diagnostic, not promoted to the preferred specification.

### Citations

| Specification | (t=-3) | (t=0) | (t=5) | Average ATT, (0\ldots5) |
|---|---:|---:|---:|---:|
| Paper conventions, full cohort | +0.008 | −0.090 | −0.212 | −0.152 |
| Add merged-entity survival | +0.005 | −0.092 | −0.229 | −0.156 |
| Paper-faithful, deal-clustered | +0.005 | −0.092 | −0.229 | −0.156 (SE 0.015) |
| Corrected base/balance, deal-clustered | **+0.068** | −0.103 | −0.229 | −0.170 (SE 0.015) |
| Predetermined controls, analytical only | +0.034 | −0.107 | −0.261 | −0.180 |

The same conclusion holds for citations: survival selection barely changes (t=-3), whereas a common reference period and balanced event-time support reveal a larger positive lead.

## Pre-period diagnostics

The paper-style varying-base specification does not produce flat leads; it produces a saw-tooth pattern that makes (t=-3) look small in isolation:

- patents: (t=-5=+0.120), (t=-4=-0.014), (t=-3=+0.016), (t=-2=-0.033);
- citations: (t=-5=+0.083), (t=-4=-0.003), (t=-3=+0.005), (t=-2=-0.052).

With deal-clustered simultaneous bands, two of four paper-faithful pre-period patent intervals and two of four citation intervals exclude zero. Under the corrected universal-base and balanced specification, three of four exclude zero for each outcome. The corrected patent (t=-3) interval is ([0.029,,0.102]); the corresponding citation interval is ([0.026,,0.109]).

The analytical Wald pre-test is unavailable because its pre-period covariance matrix is singular. The simultaneous deal-clustered bands are therefore the relevant joint diagnostic. They reject the visual claim that the leads are uniformly compatible with zero.

No design choice provides a credible flattening:

- announcement timing changes nothing because the two year fields agree for every deal;
- acquirer survival changes patent (t=-3) by only (+0.002);
- merged-entity survival adds no deal beyond the resolved acquirer-survival sample;
- universal-base balancing makes the positive (t=-3) lead larger, not smaller;
- controls attenuate the lead only modestly and fail overlap/support diagnostics;
- the forward-looking outcomes radically reshape leads, but mechanically rather than through improved identification.

## Forward-looking outcomes

The two paper outcomes behave as expected for variables that use future information. Under paper conventions, (t=-3) is (−0.079) for `vr_rd_activity` and (+0.083) for `vr_left`. Under the universal-base/balanced specification, the same estimates become (+0.221) and (−0.241), respectively. All four pre-period simultaneous intervals exclude zero for both outcomes.

These paths are not evidence for or against parallel trends. Entry into the cohort requires a target patent in the five years before acquisition. `vr_rd_activity` asks whether an inventor patents at or after year (t), while `vr_left` asks whether the inventor’s last target/acquirer patent is before (t). Their pre-period values are therefore constrained by the qualifying patent and the career endpoint. A flatter version would be mechanical; the non-flat version here remains mechanically difficult to interpret. Neither outcome should be used to declare identification restored.

## Comparison with the published magnitudes

Verginer and Riccaboni report average effects of (−0.136) for patents and (−0.350) for citations. The reconstruction gives:

| Outcome | Published | Paper-faithful reconstruction | Corrected reconstruction |
|---|---:|---:|---:|
| Log patents | −0.136 | −0.256 | −0.264 |
| Log citations | −0.350 | −0.156 | −0.170 |

The reconstructed patent effect is 0.120–0.128 log points more negative. The reconstructed citation effect is 0.180–0.194 log points less negative. These are benchmarking differences, not replication failures with a common estimand.

The citation outcomes are especially non-comparable: the paper counts citations received through 2022, whereas this reconstruction uses the inventor-year sum of OECD five-year forward citations. The reconstruction also uses `log1p` transformations; the paper’s patent-log handling is not sufficiently documented to guarantee an identical zero treatment.

## Similarities and deviations from the paper

The reconstruction matches the paper in the economically important conventions requested for this exercise: treatment-relative five-year recruitment, announcement-year dating, not-yet-treated comparisons for the aggregate ATT, doubly robust estimation, no anticipation, the deal-survival restriction, and the four outcome concepts.

It does not claim to reproduce the published tables or Figure 3 exactly:

- this is the thesis’s pharma acquisition population, not the paper’s smaller biotech-target population;
- the paper’s event-study figure is a fixed-effects specification, whereas this reconstruction consistently reports Callaway–Sant’Anna dynamic effects; the paper uses the `did` implementation for its aggregate ATT;
- exited inventors remain in the balanced thesis panel as zero-patent years, while the published panel is not fully balanced;
- the target-survival rule must be translated to a target-or-acquirer group because literal target identifiers disappear after integration;
- the citation windows and potentially the log transformations differ;
- corrected inference uses deal-level clustering and balanced event-time support, which are improvements over—not reproductions of—the paper’s disclosed inference;
- the predetermined covariates are from the thesis design and are not part of the paper-faithful specification.

## Identification verdict and next step

The reconstruction is useful because it rules out three tempting explanations: wrong event-year construction, omission of the paper’s deal-survival filter, and omission of its forward-looking outcomes. None supplies a credible parallel-trends repair.

It does not solve the underlying problem. Both the thesis design and the comparator recruit inventors using an event-relative patent window and draw controls from eventually treated units at different distances from their own acquisition. Conditioning deal inclusion on post-acquisition patenting changes the population and can select smoother acquisitions; it does not make untreated outcome trajectories comparable. Changing the outcome to a forward-looking absorbing state constrains the pre-period mechanically; it does not identify a causal counterfactual.

The next empirical branch should therefore be:

1. replicate the complete cohort-construction machinery on never-treated inventors with pseudo-deal years matched to the treated cohort-year distribution;
2. build a calendar-symmetric or deal-disjoint risk set whose activity requirement ends before the tested leads;
3. re-estimate with not-yet-treated and never-treated donors on that risk set;
4. treat any remaining hump as timing selection and move to specification-consistent sensitivity bounds rather than further specification search.

## Reproducibility files

- Script: `02_analysis/R/08p_verginer_reconstruction.R`
- Results: `02_analysis/output/results/verginer_reconstruction/`
- Main figure: `02_analysis/output/figures/preliminary_results/figure13_verginer_reconstruction.png`
- Key audits: `sample_and_survival_audit.csv`, `outcome_definition_audit.csv`, `timing_audit.csv`, and `bootstrap_inference_audit.csv`
- Main summaries: `specification_ladder_comparison.csv`, `five_year_average_att.csv`, `joint_preperiod_diagnostics.csv`, and `comparison_to_published_att.csv`

