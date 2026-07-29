# Initially retained inventor heterogeneity results

## TL;DR

The separately balanced P5b design contains 2,663 initially retained treated inventors across 151 deals. Their aggregate patent-count ATT is -0.107 patents per inventor-year (two-way deal/inventor 95% CI -0.204 to -0.010; p=0.031).
The corresponding probability-of-patenting effect is -1.43 percentage points (two-way 95% CI -4.77 to 1.90; p=0.398).

## Predetermined heterogeneity

The p75-minus-p25 productivity contrast for patent count is -0.234 (p=0.131).
The career-age contrast is -0.124 (p=0.072), the persistent-team contrast is -0.144 (p=0.155), and the TechFit contrast is -0.227 (p=0.014).
Corrected focal tenure is appendix-only. Its p75-minus-p25 patent-count contrast is -0.038 (p=0.604) and is not part of the primary family.

All moderator variables end by event time -1. The same 9,999 Webb draws
are used for every heterogeneity test. Heterogeneity contrasts use the more
conservative of deal-wild and two-way deal/inventor inference; the aggregate
ATT reports the previously selected two-way inference with wild bootstrap
shown transparently as a companion.

## Multiplicity appendix

The main table reports unadjusted governing p-values. The complete eight-test Holm adjustment is retained in `table_stayer_heterogeneity_holm_appendix.csv`.
The decomposition's inferential diagnostics are retained separately in `table_stayer_margin_decomposition_inference_appendix.csv`. The main decomposition table reports quantities and shares only; its intensive component is descriptive because activity is post-treatment selected.

## Interpretation limit

Initial retention is defined using the first patent observed in event time +1 through +5. These estimates therefore describe heterogeneity within the post-treatment-selected, patent-observed initially retained population. They are not unconditional employment-retention effects.
Control observations face the symmetric requirement that the focal control group remains patent-active through +5. In the patent-based operational sense, the group therefore exists at the end of follow-up and remains at risk of patenting in +6 or later; an observed +6 patent is not required.
