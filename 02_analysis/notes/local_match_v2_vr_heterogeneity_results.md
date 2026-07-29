# Local Match v2: five-year inventor heterogeneity

## TL;DR

The aggregate quantity result is unchanged: acquisitions reduce patent output by 0.053 patents per inventor-year, or 0.267 patents over five years. The symmetric accounting assigns 0.197 of the cumulative loss (74%) to fewer active inventor-years and 0.070 (26%) to fewer patents during active inventor-years.

All eight predeclared heterogeneity contrasts are included. Career age does not moderate patent-count effects (contrast -0.002; p=0.923), and pre-deal productivity does not moderate active patenting (-0.004; p=0.340).

Three patent-count gradients are conventionally significant. The p75-p25 productivity contrast is -0.050 (p=0.031); the persistent-team contrast is -0.119 (p=0.008); and the TechFit contrast is -0.050 (p=0.015).

## Interpretation

The productivity point estimates are not only a mechanical stock pattern. At the treated p25, the predicted annual loss is -0.009, or 4.4% of pre-deal annual output; at p75 it is -0.059, or 14.7%.
Persistent collaborators are a plausible relationship-specific human-capital channel, but only 4,363 treated inventors have a temporal persistent tie. The outcome-blind StrongestTie extension is reported separately among inventors with a persistent tie. Within that subgroup, a p75-p25 increase in dependence on the strongest collaborator has a positive patent-count contrast of 0.108 (p=0.098) and a positive active-patenting contrast of 0.035 (p=0.117); neither is significant. The data therefore support a persistent-team gradient but do not show that greater dependence on one particular collaborator magnifies the loss.
Higher inventor-acquirer TechFit is associated with a more negative, not less negative, patent-count effect. The full-history and five-year contrasts are close. This pattern is compatible with redundancy-driven program rationalization, but it does not identify that mechanism.

## Design notes

The five-year regression retains Verginer and Riccaboni's After structure but uses treated versus matched-control status instead of their post-treatment Left indicator. The latter belongs in the separate stayer analysis. Full-history IPC4 cosine is primary; the five-year cosine and 1994--2008 sample are fixed robustness variants and cannot replace their primary specifications.
Both valid extensive/intensive orderings are reported. They place 69--78% of the total loss on reduced active patenting; the symmetric 74/26 split is the primary accounting presentation. P5c reference-year patent-count and active-patenting gaps are below 5e-9 and 1e-9.

## Appendix diagnostics

Holm-adjusted p-values, minimum detectable effects, and Type-M diagnostics are retained in `table_vr_heterogeneity_diagnostics_appendix.csv`. They are not used to decide which predeclared heterogeneity estimates are reported.
