# Verginer-style early-recruitment diagnostic: results

## Design question

The diagnostic fixes inventor membership before the five-year trajectory used
for matching. An inventor enters only with focal-entity patent evidence at
event year -7 or -6. The five annual patent counts and active-patenting
indicators from -5 through -1 are then balanced. Cohort 1994 is omitted because
the patent layer begins in 1988 and therefore does not observe its event year
-7.

This is an established-inventor estimand, not a replacement for the P5c
full-cohort ATT.

## Feasibility result

The strict design, which also balances all three firm variables within every
cohort, is feasible in 13 of 16 cohorts. It is infeasible in:

- 1995: 137 early-recruited treated inventors across 4 retained deals;
- 1998: 12 inventors across 2 deals; and
- 1999: 196 inventors across 9 deals.

The feasible 13-cohort strict sample contains 2,591 treated inventors and 166
deals. It retains 88.2% of the 2,936 early-recruited treated inventors. All
inventor and firm balance constraints are exact in this feasible sample.

An inventor-only version is feasible for all 16 cohorts and contains 2,936
treated inventors across 181 deals. It exactly balances the complete inventor
trajectory but leaves pooled firm SMDs of 0.155, 0.225, and 0.416. It is
therefore supplementary to the strict feasible-cohort result.

## Patent-count result

For the strict feasible-cohort design, the average annual ATT over event years
+1 through +5 is:

| Inference | ATT | 95% CI | p-value |
|---|---:|---:|---:|
| Deal-level wild bootstrap (governing) | -0.0867 | [-0.1715, -0.0025] | 0.0436 |
| Two-way deal/inventor cluster | -0.0867 | [-0.1506, -0.0228] | 0.0081 |
| Deal-cluster robust | -0.0867 | [-0.1494, -0.0240] | 0.0070 |

The implied five-year cumulative difference is -0.434 patents per inventor.
Relative to the matched control mean of 0.312 patents per inventor-year over
+1 through +5, the annual effect is approximately -27.8%.

The full 16-cohort inventor-only estimate is -0.0894 patents per
inventor-year. Its governing wild-bootstrap interval is
[-0.1492, -0.0242] with p=0.0074. The closeness of the two estimates shows
that the three cohorts lacking strict firm balance do not drive the result.

The censoring-buffered strict estimate is -0.0805. Its two-way interval
excludes zero, but the governing wild-bootstrap interval
[-0.1809, 0.0289] does not (p=0.147). The sign and magnitude remain similar;
precision falls because the effective treated-deal count declines.

## Interpretation

The raw weighted paths for early-recruited inventors fall steeply before the
deal in both arms. This confirms that inventor lifecycle is real. However, the
treated and control paths are identical throughout -5 through -1 and separate
only after treatment. The negative P5c effect therefore is not generated only
by admitting inventors during the immediate five-year pre-deal window.

The pre-period coefficients and joint test are mechanically zero because all
five pre-period outcomes are balance constraints. They are balance checks, not
independent placebo tests. Identification still requires the conditional
parallel-trends assumption after conditioning on the complete observed path
and support variables.

The result materially weakens recruitment/lifecycle and simple observed
mean-reversion explanations. It does not logically eliminate latent shocks
that both predict acquisition and begin only after the matched pre-period.
The thesis should therefore present convergence across P5c, LOYO diagnostics,
the raw-path decomposition, and this established-inventor design, while
retaining Honest DiD sensitivity analysis.

## Certified artifacts

- Strict feasible P5 execution:
  `b9232490c0f9afb6b6cce7df396a39df8b4b18dd052f9b47bf1ac38c5fa100f8`
- Strict feasible P6 execution:
  `57bdb7d4e89f1d5986442894751e3095848f4c417533cfac3e33237978562e8b`
- Inventor-only P5 execution:
  `1932722eb6cd2dedfae831c673d01d68a344b766348e6969992dad3de5474b3e`
- Inventor-only P6 execution:
  `02dca63f023f94f74a3e756cd831c3f52d78db6ff72b975d2ee59b9259569c49`
