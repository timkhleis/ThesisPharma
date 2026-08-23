# Relative-standing re-audit (2026-08-08)

## Bottom line

The old $+0.103$ result and pre-period $p=.007$ should not be reported.
The control-side moderator was constructed at the wrong grain: for each treated
deal, the code pooled all matched control firms together with the acquirer
before ranking control inventors. Treated inventors were correctly ranked in
the target-plus-acquirer pool. A treated deal has one target group but an
average of 37.7 matched control groups, so the error made the control
counterfactual pool much larger and arm-specific.

After constructing each pseudo-combined control pool separately at the
deal-by-control-focal-group level, the continuous patent-count gradient is
$+0.091$ per ten percentage points (95% CI $[0.049,0.133]$). The joint
overlapping-window pre-gradient diagnostic changes from $p=.007$ to
$p=.230$. The corrected P5c weights leave the moderator somewhat imbalanced
(SMD $=-0.115$), but a cohort-preserving entropy tilt reduces the largest
absolute SMD across the audited moderator, baseline, size, and interaction
terms to 0.048. The rebalanced, fully interacted gradient is $+0.047$ (95%
CI $[0.017,0.076]$). Deal-by-arm fixed effects give a similar $+0.049$.
Observable imbalance therefore explains part of the magnitude but not the
positive sign.

The remaining sign is not evidence that inventors who lose standing benefit
from acquisition. The moderator has a large mass point: 66.1% of treated
inventors have zero predicted change, and only 10.7% have an actual predicted
loss. Every one-patent inventor has zero loss under the strict-lower-rank
definition. The continuous regression is therefore dominated by the contrast
between the zero mass and predicted rank gains. Descriptively, the ATT is most
negative among inventors predicted to gain more than five points
($-0.166$ under P5c and $-0.184$ after rebalancing) and approximately zero
among inventors predicted to lose more than five points. It is incorrect to
translate the positive interaction as a positive acquisition effect for
high-loss inventors.

When the slope is estimated only over actual predicted losses and productivity
and organizational characteristics are allowed to enter flexibly, its sign
turns negative, as the theory predicts, but it is imprecise: $-0.146$ per ten
points (95% CI $[-0.444,0.151]$, $p=.333$). A binary positive-loss contrast
among inventors with at least two pre-deal patents is $+0.109$ (95% CI
$[-0.031,0.249]$, $p=.126$). The earlier three-plus-patent subgroup also
fails its balance gate. The sign is therefore specification-sensitive on the
theoretically relevant support, and the data do not distinguish a negative
standing-loss effect from zero or a moderately positive gradient.

## What drove the original pattern

1. **Arm-specific control construction.** The pseudo-combined control rank used
   all control firms assigned to a deal instead of one control focal firm. This
   error explains the failed pre-gradient diagnostic and reduces the corrected
   headline gradient from $+0.103$ to $+0.091$.
2. **A mechanically degenerate moderator.** Strict-lower percentile rank is
   zero for every inventor at the bottom productivity mass in both pools. This
   puts all one-patent inventors at zero predicted change and leaves little
   actual-loss support.
3. **Baseline and organizational composition.** Fully interacting the five-year
   patent path, nonlinear productivity, career/team characteristics, focal
   exclusivity, and focal/acquirer-pool sizes reduces the gradient. TechFit does
   not explain the remainder: adding it changes the flexible estimate from
   $+0.074$ to $+0.073$.
4. **Gain-side comparisons.** The most stable empirical pattern is worse
   post-acquisition performance among predicted gainers, not better performance
   among predicted losers. Predicted gain/loss also separates organizational
   regimes: the greater-than-five-point loss group has a much smaller focal
   pool and a larger added acquirer pool than the greater-than-five-point gain
   group. The moderator therefore mixes relative rank with target-acquirer
   composition.

## Causal interpretation

Rebalancing supports a conditional comparison of acquisition effects across
predetermined inventor types. It does not make predicted standing loss an
exogenous treatment or identify the causal effect of standing loss itself.
The construct is a deterministic function of own productivity and the target
and acquirer productivity distributions. The regressions can test whether the
acquisition ATT varies with that prediction under conditional parallel trends;
they cannot establish standing loss as the mediator.

The corrected pre-gradient diagnostic no longer rejects, but the theoretically
relevant actual-loss region remains thin and poorly balanced. The defensible
conclusion is that the present patent-rank measure does not provide a precise
test of the relative-standing channel. It neither supports the proposed
mechanism nor establishes the opposite mechanism.

## Recommended main-text treatment

Keep the test in the main heterogeneity section because it addresses a stated
prediction, but report the support problem and the corrected result. Do not
headline the full-sample linear coefficient as the mechanism test. The
continuous specification, entropy-balanced specification, actual-loss-only
estimate, and complete construction details should appear in the appendix.

Suggested main-text paragraph:

> Predicted relative-standing loss does not explain the larger patenting
> decline among previously productive inventors. After correcting the rank
> comparison so that each matched control firm is pooled separately with the
> acquirer, the pre-period gradient is no longer significant
> ($p=.230$). The full-sample continuous interaction remains positive, but
> this coefficient is not a clean test of the hypothesis: two thirds of
> treated inventors have no predicted rank change, only 10.7% have a predicted
> loss, and the positive slope mainly reflects larger patenting declines among
> inventors predicted to gain rank. Within the actual-loss region, the
> fully adjusted gradient is negative but imprecise ($-0.146$, 95% CI
> $[-0.444,0.151]$). I therefore find no precise evidence that predicted
> relative-standing loss accounts for the productivity gradient.

## Reproducible files

- Corrected construction and certification:
  `02_analysis/R/65a_lmv2_relative_standing_config.R` and
  `02_analysis/R/65b_build_lmv2_relative_standing.R`.
- Corrected frozen estimates and diagnostics:
  `02_analysis/R/65c_estimate_lmv2_relative_standing.R` through
  `02_analysis/R/65e_interview_lmv2_relative_standing.R`.
- Entropy rebalance, fully interacted models, and deal-by-arm fixed effects:
  `02_analysis/R/65f_diagnose_lmv2_relative_standing_confounding.R`.
- Flexible productivity, TechFit, and actual-loss/gain support probes:
  `02_analysis/R/65g_probe_lmv2_relative_standing_channels.R`.

All new models in 65f and 65g are explicitly post-results diagnostics. They do
not replace the frozen confirmatory family and should be labelled exploratory.

## Power and initially retained follow-up

The corrected analysis above was originally run only for the full eligible
cohort. An exploratory follow-up now applies the same corrected moderator to
the P5b initially retained population. The join is complete: it covers all
2,792 treated retainers and 42,478 matched control rows across 153 deals.
However, only 509 treated retainers across 69 deals have a strictly positive
predicted loss; 970 retainers (34.7%) are at zero and 1,313 are predicted to
gain standing.

The retained results are unstable across reasonable ways of using the thin
loss support. The full-support linear interaction is positive and precise
($+0.176$, governing $p=.006$). A deal-by-arm fixed-effect hinge model, which
allows separate slopes for predicted losses and gains while retaining the
full sample, estimates essentially no loss-side gradient ($-0.008$, 95% CI
$[-0.207,0.191]$). Restricting the sample to positive losses produces
$-0.397$ (95% CI $[-0.777,-0.016]$, conventional two-way clustered $p=.041$),
but replacing the saturated deal-by-arm effects with cohort effects changes
the estimate to $+0.047$ (governing $p=.739$). This is post-results
specification sensitivity, not robust evidence for a negative retained-cohort
effect. Moreover, initially retained status is post-treatment selected, so
these estimates do not identify unconditional acquisition-effect
heterogeneity.

The main power problem is independent deal-level variation rather than the
raw inventor count. In the full cohort, the actual-loss region contains 2,894
treated inventors across 153 treated deals, but the distribution of analysis
weight is equivalent to only 16.6 equally weighted deals; the largest deal
accounts for 19.4% of the treated actual-loss weight. The retained counterpart
has 509 treated inventors across 69 deals and 18.8 equally weighted deals. For
the full-cohort actual-loss estimate, the standard error is about 0.151 per
ten percentage points. Its approximate 80%-power minimum detectable effect is
therefore 0.423. Detecting an effect equal to the current point estimate
($0.146$ in absolute value) with 80% power would require about 8.4 times as
much independent information; merely crossing a two-sided 5% threshold at
that same point estimate would require about 4.1 times as much information.

Legitimate precision improvements should be specified before comparing their
results:

1. Use a loss/gain hinge model as the primary functional form. It uses all
   observations while allowing the loss-side prediction to differ from the
   empirically distinct gain side, avoiding the 90% sample loss caused by the
   positive-loss restriction.
2. Reduce ties in the pre-deal moderator with an outcome-blind, theory-aligned
   alternative such as fractional five-year patent output or a pre-specified
   midrank percentile. Keep the strict-lower patent-count rank as the benchmark
   and report all variants with an omnibus or multiplicity-adjusted test.
3. Add prognostic pre-deal outcomes through a pre-specified ANCOVA/residualized
   specification or cross-fitting. This can reduce residual variance, but it
   cannot manufacture the missing deal-level variation.
4. Add genuinely independent acquisitions. Extending the data beyond 2015 may
   recover late deals and is the most credible route to a materially narrower
   interval. Adding more inventor-year rows within the same concentrated set
   of deals will help much less.
5. Report the confidence interval and minimum detectable effect rather than
   optimizing the specification for a smaller observed p-value. A one-sided
   test cannot be introduced after seeing these results.

The reproducible retained-cohort probe is
`02_analysis/R/65h_probe_lmv2_relative_standing_stayers.R`. It is exploratory
and does not yet constitute a separately frozen, pre-period-certified retained
heterogeneity package.

## Implemented power improvement

An exploratory power package now estimates separate loss and gain slopes on
the full support instead of discarding inventors with zero or predicted gains.
It also adds pre-deal outcome and organizational predictors symmetrically by
treatment arm. With the original strict count rank, the baseline hinge gives a
loss-side estimate of $+0.024$ (governing SE $0.0375$, $p=.551$). The richer
pre-deal adjustment gives $+0.029$ (SE $0.0225$, 95% CI
$[-0.015,0.074]$, $p=.196$). Its 80%-power minimum detectable effect is
$0.063$ per ten percentage points, compared with approximately $0.423$ for the
positive-loss-only estimate. The joint overlapping-window pre-period
diagnostic passes the stated threshold ($p=.109$), although the individual
$t=-3$ coefficient is significant. The joint test is the governing diagnostic.

This specification provides the most defensible current test. It retains the
original moderator definition, separates the theoretically relevant loss side
from the empirically different gain side, and sharply narrows the negative
side of the confidence interval. The estimate does not support a negative
standing-loss gradient; the 95% interval rules out declines larger than about
$0.015$ patents per ten-point predicted loss under this functional form.

The package also constructs standing from fractional five-year patent output.
This outcome-blind alternative reduces the treated zero mass from 66.1% to
1.45%, raises positive-loss support from 2,894 to 9,591 inventors, and raises
the effective treated loss-deal count from 16.6 to 26.1. Its estimate is
$+0.015$ (SE $0.0129$, 95% CI $[-0.010,0.041]$, $p=.241$). However, its joint
pre-period diagnostic is $p=.0748$, below the thesis's $p>0.10$ threshold.
Fractional standing should therefore remain an appendix sensitivity rather
than replace the count-based measure.

The reproducible implementation is
`02_analysis/R/65i_improve_lmv2_relative_standing_power.R`. It writes the
full-support estimates, support diagnostics, and pre-period tests to
`P7_RELATIVE_STANDING/power_improvement_v2`. These models remain exploratory
until their specification is frozen; the original loss-only result should not
be silently replaced.

## Theory-aligned high-standing refinement

A subsequent rereading of Paruchuri, Nerkar, and Hambrick (2006) clarifies that
the motivating mechanism concerns target-firm stars who lose stature in the
combined organization. Restricting the population to inventors initially above
the target's 80th percentile and estimating separate loss and gain slopes
produces a negative loss gradient of $-0.073$ (95% CI
$[-0.173,0.027]$, $p=.152$). Cohort-preserving entropy balance changes the
estimate only to $-0.064$ (95% CI $[-0.167,0.039]$, $p=.229$), reduces the
maximum audited SMD below 0.000002, and passes the joint pre-period diagnostic
($p=.439$). The 75th- and 90th-percentile thresholds also produce negative
estimates.

This is the closest empirical test of the stated mechanism. It is suggestive,
not conclusive, and remains a post-results refinement. Full details are in
`02_analysis/notes/local_match_v2_high_standing_relative_loss_2026-08-08.md`.
