# High-standing relative-loss analysis (2026-08-08)

## Theory and revised estimand

Paruchuri, Nerkar, and Hambrick (2006) motivate relative-standing loss with a
target inventor who was a local star before acquisition and becomes a smaller
figure after entering the acquirer's larger technical organization. They
measure target standing as the percentage of productive target inventors with
lower five-year pre-acquisition patent output, calculate the analogous rank in
the pooled target-acquirer population, and define loss as the first percentile
minus the second. This is the same underlying construct used in the thesis.

The paper's mechanism concerns acquired scientists with high initial stature,
even though its reported loss variable is continuous in the acquired-inventor
sample. The closer thesis estimand is therefore the acquisition-ATT gradient
with respect to downward rank movement among inventors who begin near the top
of the target hierarchy. Predicted gains are not part of the mechanism.

The revised primary population consists of inventors at or above the target's
80th percentile before acquisition. This threshold was already encoded in the
frozen Kapoor--Lim top-20 sensitivity and mechanically requires at least five
productive inventors in the focal organization. The regression uses separate
hinges for losses and gains, controls for baseline target standing itself, and
interacts the predetermined productivity, patent-path, career, team, and
organizational controls with treatment. Only the loss-side treatment
interaction is interpreted. Thresholds at 75 and 90 are a fixed sensitivity
family; an actual-loss-only top-quintile regression is secondary.

## Results

All threshold estimates have the theoretically predicted negative sign:

| Initial target standing | Loss-side gradient per 10 points | 95% CI | Governing p |
|---|---:|---:|---:|
| At least 75th percentile | -0.067 | [-0.143, 0.009] | .084 |
| At least 80th percentile | -0.073 | [-0.173, 0.027] | .152 |
| At least 90th percentile | -0.081 | [-0.275, 0.113] | .418 |
| At least 80th, actual losses only | -0.055 | [-0.151, 0.041] | .261 |
| At least 80th, entropy balanced | -0.064 | [-0.167, 0.039] | .229 |

The top-quintile sample contains 3,405 treated inventors. Of these, 1,216
inventors across 125 deals have a predicted loss. Their analysis weight is
equivalent to 23.9 equally weighted loss-side deals, and the largest deal has
12.7% of loss-side weight.

The original top-quintile P5c comparison has a maximum absolute audited SMD of
0.228, driven by focal-group exclusivity. A cohort-preserving entropy tilt on
loss and gain magnitudes, initial standing, absolute productivity, the full
pre-deal patent path, career and team characteristics, and organizational size
reduces the maximum absolute SMD to less than 0.000002. The negative coefficient
survives, changing from -0.073 to -0.064. The entropy-weighted joint pre-period
trajectory diagnostic is clean (p=.439); none of the four individual leads is
significant.

The point estimate is economically meaningful. For a local star who falls 40
percentile points, as in Paruchuri et al.'s motivating example, the estimate
implies approximately 0.26 fewer patents per year, or 1.28 fewer patents over
five years. The confidence interval remains wide, so this calculation is
illustrative rather than a precise causal magnitude.

Following the thesis's aggregate reporting convention, the preferred
top-quintile entropy-balanced estimate is -0.319 patents over five years per
ten-percentage-point loss (95% CI [-0.835, 0.197], p=.229). This is exactly
five times the average annual coefficient and therefore has the same test
statistic and p-value; it changes the reporting scale but does not add
independent information.

## Interpretation and reporting

This analysis restores alignment between the empirical contrast and the
theory. The confusing positive full-cohort coefficient arose because most
inventors were not initially high status and the continuous slope was heavily
influenced by predicted gainers. Once the population is restricted to local
stars and the loss and gain sides are separated, the estimated gradient is
negative at every threshold and remains negative after rebalancing.

The evidence is suggestive rather than conclusive. The top-quartile estimate is
close to conventional significance, but the pre-existing top-quintile cutoff
should govern; choosing 75 after seeing the results would be specification
searching. The top-quintile estimate cannot reject zero and its interval still
allows a small positive gradient.

The thesis should present the top-quintile entropy-balanced estimate as the
theory-aligned relative-standing test and disclose that it is a post-results
refinement motivated by the support audit. The old full-cohort linear gradient
belongs in the appendix as evidence that a symmetric specification is poorly
matched to the mechanism. The fractional-rank analysis also remains appendix
only because its joint diagnostic fails the thesis threshold.

The regression still does not identify perceived status as a causal mediator.
Patent rank proxies local standing, and the data do not contain Paruchuri et
al.'s direct acquisition-integration measure. The result supports a pattern
consistent with status loss among former target stars; it does not prove that
demotivation caused their productivity decline.

## Reproducibility

`02_analysis/R/65j_test_lmv2_high_standing_loss.R` produces the threshold
family, actual-loss-only estimate, entropy-balanced estimate, support and
balance diagnostics, and P5c and entropy-weighted pre-period tests. Outputs are
stored under `P7_RELATIVE_STANDING/high_standing_loss_v2`.

References:

- Paruchuri, S., Nerkar, A., and Hambrick, D. C. (2006), "Acquisition
  Integration and Productivity Losses in the Technical Core," *Organization
  Science* 17(5): 545--562. https://doi.org/10.1287/orsc.1060.0207
- Hambrick, D. C., and Cannella, A. A. (1993), "Relative Standing: A Framework
  for Understanding Departures of Acquired Executives," *Academy of
  Management Journal* 36(4): 733--762. https://doi.org/10.5465/256757
