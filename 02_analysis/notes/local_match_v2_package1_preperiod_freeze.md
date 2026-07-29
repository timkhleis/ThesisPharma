# Local Match v2 — Package 1 pre-period diagnostic freeze

Frozen on 2026-07-27 before estimating the three missing leave-one-year-out
arms or any timing-placebo contrast.

This is a post-results diagnostic package. It does not change the frozen P5a
support roster, the P5c count-plus-active headline weights, or the primary P6
ATT. Every LOYO arm is reported regardless of sign or significance.

## Four-year LOYO placebo grid

The grid contains one arm for each testable placebo year. The terminal
pre-period \(t=-1\) remains balanced and is the common reference because the
design assumes no anticipation; it is not itself held out or tested. This
prospective Package 1 decision supersedes the earlier Package 0 shorthand
"complete five-year LOYO grid."

| Arm | Held-out year | Balanced annual patent outcomes | Placebo reference |
|---|---:|---|---:|
| `loyo_m5` | \(t=-5\) | \(t=-4,-3,-2,-1\) | \(t=-1\) |
| `loyo_m4` | \(t=-4\) | \(t=-5,-3,-2,-1\) | \(t=-1\) |
| `loyo_m3` | \(t=-3\) | \(t=-5,-4,-2,-1\) | \(t=-1\) |
| `loyo_m2` | \(t=-2\) | \(t=-5,-4,-3,-1\) | \(t=-1\) |

Each arm balances both patent count and active patenting in the four included
years. It also retains career age, focal-group exclusivity, firm patent stock,
firm inventor count, and firm patent trajectory. No year outside
\(t=-5,\ldots,-1\) enters matching, weighting, support ranking, or distance.
No second moments are added: the complete annual count vector plus annual
active-patenting vector is already demanding, and Package 1 changes only the
single held-out pair in each arm.

The certified `loyo_m3` and `loyo_m4` weights and estimates are reused
verbatim. Package 1 solves only `loyo_m2` and `loyo_m5` on the unchanged P5a
roster.

## Placebo assessment

For each sample and LOYO arm report:

1. the held-out contrast and 95% confidence interval;
2. whether the interval lies entirely within the equivalence region
   \([-0.05,+0.05]\) patents per inventor-year;
3. the two one-sided equivalence-test decisions at alpha 0.05;
4. whether zero lies in the ordinary 95% confidence interval.

Failure to reject zero is not called evidence of equivalence. Conversely, a
small estimate may be imprecise and therefore fail the equivalence test.

All four arms test the held-out year relative to the balanced \(t=-1\) year.

The original P5a joint pretrend test remains the non-mechanical formal
pretrend diagnostic. The P5c/LOYO grid is an appendix robustness analysis,
not a search for a preferred design.

## Post-treatment stability

All four LOYO arms retain their separately estimated post-treatment results.
Relative to the frozen count-plus-active headline, report:

- sign;
- whether the LOYO point estimate lies inside the headline 95% confidence
  interval;
- absolute point-estimate deviation;
- maximum deviation and full range across the four arms.

No arm may replace the headline because its post-treatment ATT is more
favourable.

## Timing placebo

A pseudo-event three years earlier has two uncontaminated pseudo-post years:
pseudo \(t=+1,+2\) correspond to actual \(t=-2,-1\). Package 1 reports these
contrasts relative to pseudo \(t=-1\), which is actual \(t=-4\).

A pseudo-event three years later is not a valid no-effect placebo in this
panel: its pseudo-pre period already contains actual post-acquisition years.
Package 1 records this construction failure explicitly. It may show the
shifted path descriptively as a persistence diagnostic, but it must not call a
non-flat estimate evidence against the design or a flat estimate a passed
placebo.

## Certification

Package 1 passes only if:

- all 17 cohorts exist in every LOYO arm;
- roster membership is identical to the certified P5c/P6 roster;
- all weights are finite and positive;
- treated weights are unchanged;
- treated and control mass agree within cohort;
- every balanced variable has absolute standardized difference no greater
  than 0.10;
- every guard is tooth-tested with a real failing fixture;
- all four held-out results and all four post-treatment estimates are reported.
