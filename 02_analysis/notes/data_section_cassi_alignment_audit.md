# Cassi--Ornaghi alignment audit

The apparent differences in inventor productivity and group patent counts do not indicate a failed merge or a defective thesis sample. They arise mainly because the published Table 3 and the thesis descriptive table summarize different populations, observation units, time windows, and weighting schemes.

## Inventor productivity

Cassi and Ornaghi report a mean five-year productivity of 1.070 across 760,047 separation observations. This is not a target-inventor mean: 750,268 observations are non-target and only 9,779 are target observations. Reconstructing their sample from the supplied status and production files reproduces 1.070 exactly.

Within their target observations, mean annual productivity is 0.833: 0.891 for stayers and 0.681 for leavers. The thesis P2 sample produces 0.807 for status-eligible stayers and leavers, comprising 0.854 for stayers and 0.633 for leavers. The differences relative to the target-only Cassi--Ornaghi moments are therefore 0.037 patents for stayers and 0.048 patents for leavers, not the much larger difference suggested by comparing the thesis sample with the published all-observation mean of 1.070.

The remaining difference is consistent with the different clocks. Cassi--Ornaghi productivity is a rolling five-year measure ending in each status-observation year. Thesis productivity is fixed over the five calendar years immediately preceding the assigned deal year. Among the same 5,358 inventor--deal units, the Cassi--Ornaghi clock yields 0.860 patents per year and the thesis clock yields 0.781. Thus, holding the sample fixed, the timing convention accounts for 0.079 patents per year.

## Group patents

The published group-patent mean of 202.1 is calculated across all 760,047 inventor-status observations. It is therefore dominated by non-target firms and weights a group more heavily when it employs more observed inventors. The corresponding mean is 156.3 within target observations and 26.75 when each of the 380 target deals receives equal weight.

The thesis statistic is different: it counts distinct EPO patent applications assigned to each target group during `g-5` through `g-1` and gives each deal equal weight. Its mean is 75.0 across 343 P2 deals. On the same 292 overlapping deals, the supplied Cassi helper yields 21.59 patents for an annual status-year measure, whereas the thesis five-year stock is 87.25, or 17.45 when annualized.

Holding the deal, target group, and five-year window fixed provides the cleanest count comparison. The Cassi helper yields a mean five-year count of 85.96; the repaired thesis pipeline yields 75.20 distinct applications. The deal-level correlation is 0.991. The remaining 12.5 percent level difference therefore reflects the counting convention and the canonical distinct-application repair rather than different underlying target activity.

## Assessment

The deviations are not problematic for the thesis design:

- the supplied replication files reproduce the published Cassi--Ornaghi Table 3 statistics exactly;
- target-only inventor productivity is close across the two constructions;
- the remaining productivity difference follows from a documented timing rule;
- group patent counts track each other almost perfectly across deals once the sample and window are fixed.

The thesis should not compare its 0.439 full-cohort productivity mean with the published 1.070 separation-observation mean, nor its five-year deal-level group stock of 75.0 with the published observation-weighted group mean of 202.1. Table notes should state the population, observation unit, event window, patent-count definition, and weighting explicitly.
