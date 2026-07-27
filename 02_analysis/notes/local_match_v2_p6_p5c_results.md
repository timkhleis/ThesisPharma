# P6 results under annual-trajectory balancing

Run completed and certified: 2026-07-27.

## Main result

Balancing the complete five-year pre-acquisition patent-count and
active-patenting paths strengthens the negative patent-count result. In the
1994--2010 sample, the average annual ATT over `t=+1,...,+5` is -0.0534
patents per supported inventor (95% governing interval
[-0.0909, -0.0168], wild-bootstrap p = 0.0077). The corresponding five-year
cumulative effect is -0.267 patents (interval [-0.455, -0.084]).

The censoring-clean 1994--2008 estimate is -0.0519 patents per inventor-year
(interval [-0.0912, -0.0119], p = 0.0163), or -0.259 over five years. The
near-identical point estimates show that late-sample outcome coverage does not
drive the patent-count result.

At `t=+5`, the full-sample ATT is -0.0410
([-0.0777, -0.00438]); the censoring-clean ATT is -0.0451
([-0.0813, -0.00887]). The effect therefore remains negative at the terminal
horizon rather than reflecting only a short transition.

## Outcome summary

| Outcome | 1994--2010 average annual ATT | 1994--2008 average annual ATT | Reading |
|---|---:|---:|---|
| Patent count | -0.0534 [-0.0909, -0.0168] | -0.0519 [-0.0912, -0.0119] | Negative and robust |
| Active patenting | -0.0182 [-0.0386, 0.00183] | -0.0166 [-0.0382, 0.00503] | Suggestive 1.7--1.8 pp decline |
| TechDrift | 0.00763 [-0.0256, 0.0409] | 0.0168 [-0.0142, 0.0477] | No precise evidence of drift |
| PQII, linkage-scaled | -0.0105 [-0.0200, -0.00108] | -0.00842 [-0.0181, 0.00129] | Secondary; full-sample signal is not censoring-robust |
| Forward citations, linkage-scaled | -0.00084 [-0.132, 0.130] | 0.0226 [-0.122, 0.177] | No informative effect |

OECD-based quality remains a secondary outcome because linkage and late-sample
coverage are incomplete. The full-sample PQII coefficient is negative, but its
buffered interval includes zero; it should not carry the headline.

## What the trajectory correction establishes

The five constrained patent-count leads in the `count_active` design are zero
to numerical precision. This is the intended consequence of conditioning on
the complete pre-treatment outcome path, not an independent pre-trend test.
The original P5a pre-trend must therefore remain visible in the paper.

The post-treatment patent-count estimate is stable across all four reported
designs:

| Design | 1994--2010 ATT | 1994--2008 ATT |
|---|---:|---:|
| Original P5a | -0.0459 | -0.0494 |
| Full five-year trajectory | -0.0534 | -0.0519 |
| Hold out `t=-3` | -0.0501 | -0.0487 |
| Hold out `t=-4` | -0.0540 | -0.0533 |

The full-sample range is only 0.0081 patents per inventor-year; the buffered
range is 0.0046. The negative post-treatment result is therefore not created
by directly balancing the problematic `t=-3` observation.

## Genuine held-out placebo evidence

The two held-out designs were frozen and both are reported:

| Held-out year | Sample | Estimate | 95% interval | Predeclared result |
|---|---|---:|---:|---|
| `t=-3` | 1994--2010 | 0.0447 | [0.00631, 0.0830] | Fails: interval excludes zero |
| `t=-3` | 1994--2008 | 0.0394 | [-0.00107, 0.0798] | Passes |
| `t=-4` | 1994--2010 | -0.00475 | [-0.0554, 0.0459] | Passes |
| `t=-4` | 1994--2008 | -0.0207 | [-0.0668, 0.0254] | Passes |

The correction therefore passes three of four predeclared sample-placebo
checks. It does not fully erase the `t=-3` spike when that year is genuinely
held out. The spike falls from 0.0506 under P5a to 0.0447 in the full sample
and from 0.0495 to 0.0394 in the buffered sample, but the full-sample interval
still excludes zero.

The pattern is more consistent with a localized `t=-3` composition or
productivity shock than with a persistent differential trend: `t=-4` is flat,
the buffered `t=-3` interval narrowly includes zero, and four post-treatment
designs give nearly identical negative ATTs. This evidence improves the
design materially but does not justify writing that every parallel-trends
falsification passes.

## Recommended interpretation

Report the full-trajectory estimate as the main conditional,
common-support full-cohort ATT and the original P5a estimate beside it. State
that the conclusion survives complete outcome-path conditioning and two
held-out-year exercises, while one full-sample `t=-3` placebo remains
positive. Do not select the `t=-4` design because it gives the cleaner
placebo; both held-out designs are part of the evidence.

Before thesis prose is frozen, decompose the remaining `t=-3` coefficient by
cohort and deal influence and test whether it is driven by the intensive
patent-count margin or by active patenting. This is diagnosis of the frozen
result, not another weight-selection exercise.

P6 currently delivers the full pre-deal target-inventor cohort. It does not
authorize the stayer ATT; that result remains gated on the separately balanced
P5b stayer design.

## Engineering and certification

- Three 5,509,966-row P6 panels preserve every outcome and roster identity and
  replace only the P5 weight.
- Each production estimate covers five outcomes, two samples, and 9,999 wild
  bootstrap draws; runtimes were 0.89, 0.88, and 0.90 minutes.
- Every design passed the existing 22-check terminal P6 certification.
- The P6/P5c freeze passed 12 mutation tooth tests.
- The hardcoded P5c execution ID was replaced by a content-derived hash; all
  11 P5c provenance mutation tests pass.
- The package's failed forward-citation confidence inversion is handled by a
  labeled equal-tailed bootstrap-t fallback using the same draws. Its positive
  and negative tooth tests pass. This fallback affects only the uninformative
  forward-citation interval, not patent count.
- Exact equal-deal P5c balance succeeds in the 15 cohorts other than 2000 and
  2005. No equal-deal ATT was opened in this comparison because it requires a
  separate 15-cohort freeze; the two failed mega-deal cohorts must not be
  silently replaced with primary weights.
