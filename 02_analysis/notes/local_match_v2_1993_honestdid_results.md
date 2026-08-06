# Local Match v2: amended 1993--2010 HonestDiD results

## Status

The full-cohort and initially retained joint-holdout packages completed and
passed every terminal certification check on 4 August 2026. Both packages use
HonestDiD 0.2.8, conditional least-favorable inference, the frozen relative-
magnitude grid, and analytic covariance matrices. The 9,999-draw acquisition
wild bootstrap remains the governing conventional inference.

## Critical review of the proposed implementation

The external review correctly identified the pre-existing 1994--2010
joint-holdout implementation, the installed project-library package, the need
for a fine Mbar grid, and the C-LF and analytic-covariance contract. The
implementation therefore ports that frozen design to 1993--2010 instead of
using the proposed raw `base_weight` analysis.

The raw base weights are deal-normalized local-support weights before entropy
balance. They do not preserve the nine balance moments and are not a credible
replacement for the joint-holdout design. LOYO HonestDiD curves are also
dropped because each arm has only one genuinely free lead, so their Mbar
values are not comparable. Smoothness restrictions are not identified with
only the two free leads in the governing joint-holdout design.

The review overstates one point: the proposed second-tier design was not
identical to the archived split-preperiod design. The archived design required
establishment at -7 or -6; the proposal removed that restriction. Removing it,
however, would define the treated cohort and support using later pre-treatment
observations that were supposed to serve as untouched validation periods. A
clean implementation would therefore require a new treated-population
definition rather than a simple repair. That expansion is not part of this
amendment. The archived four-cohort design remains a reported feasibility
failure, and no new split-preperiod estimate is produced.

## Full target-inventor cohort

The amended joint-holdout design retains all 18 cohorts and the complete
512,625-row P5c support roster. It balances patent count and active patenting
at -5, -4, and -1 while leaving -3 and -2 outside the final entropy-balance
constraints.

| Quantity | 1993--2010 result |
|---|---:|
| Lead at -3 | 0.0456 |
| Lead at -2 | 0.0510 |
| Joint lead test | p = 0.00484 |
| Average ATT, +1 to +5 | -0.0450 |
| Wild-bootstrap 95% CI | [-0.0832, -0.00755] |
| Wild-bootstrap p-value | 0.0195 |
| Analytic two-way 95% CI | [-0.0777, -0.0122] |
| Original HonestDiD analytic CI | [-0.0776, -0.0123] |
| Relative-magnitude sign breakdown | Mbar = 0.060 |

The freed leads are positive and jointly reject zero. Under the
Rambachan--Roth relative-magnitude restriction, the robust confidence set
first includes zero at Mbar = 0.060 under both the two-way and acquisition-
cluster covariance matrices. The corresponding worst-case average bias is
0.0122 patents per inventor-year. Neither covariance matrix required a
positive-semidefinite repair.

The result therefore indicates fragility, not robustness. The joint-holdout
post estimate remains negative under conventional inference, but deviations
from parallel trends only six percent as large as the largest pre-treatment
change are sufficient for the robust confidence set to include zero.

## Initially retained inventors

The selected-group package retains 2,792 treated inventors across 153
acquisitions and all 18 cohorts.

| Quantity | 1993--2010 result |
|---|---:|
| Lead at -3 | 0.1336 |
| Lead at -2 | 0.1111 |
| Joint lead test | p = 0.0323 |
| Average post contrast, +1 to +5 | -0.0727 |
| Wild-bootstrap 95% CI | [-0.184, 0.0427] |
| Wild-bootstrap p-value | 0.205 |
| Analytic two-way 95% CI | [-0.165, 0.0196] |
| Original HonestDiD analytic CI | [-0.164, 0.0189] |
| Relative-magnitude sign breakdown | Mbar = 0 |

The analytic confidence interval already includes zero before any additional
parallel-trends violation is permitted. A breakdown of zero therefore means
that HonestDiD cannot certify sign robustness for this selected group; it does
not mean that an identified effect is overturned by a known zero-sized bias.
This remains a post-treatment-selected contrast rather than a principal-
stratum stayer ATT.

## Reproduction and numerical checks

The internal 1994--2010 full-cohort reproduction differs from the frozen
event-study coefficients by at most 1.29e-6 and from the frozen post average
by 4.98e-7. Its breakdown reproduces exactly at 0.065. The initially retained
reproduction is numerically exact to machine precision and reproduces its
zero breakdown.

The full amended package was run twice. The weight and certification hashes
are identical. The eight-thread estimator changes some exported decimal tails
at approximately 1e-15, so coefficient and sensitivity CSV hashes are not
byte-identical. Displayed estimates, confidence intervals, p-values, and both
breakdown values are unchanged. This is numerical equivalence, not a
substantive or inferential difference.

## Reporting rule

The entropy-balanced 1993--2010 headline estimate remains the main result.
The joint-holdout HonestDiD analysis must appear alongside the identification
caveat: its unconstrained leads reject jointly and its sign breakdown is
Mbar = 0.060. The old 1994--2010 sample remains an internal reproduction check
and is not routinely co-reported.
