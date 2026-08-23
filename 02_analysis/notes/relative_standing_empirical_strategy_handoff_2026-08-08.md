# Relative standing: empirical-strategy handoff

## Research question and prediction

The relative-standing test asks whether acquisition effects are more negative
for target inventors who begin as local stars and are predicted to fall in the
combined target-acquirer productivity hierarchy. Paruchuri, Nerkar, and
Hambrick (2006) motivate this mechanism with a highly productive scientist who
moves from being a "big frog in a small pond" to a less prominent position
after acquisition. The prediction is directional: among inventors with high
initial target standing, a larger predicted downward move should be associated
with a more negative post-acquisition patent-count ATT.

## Sample and predetermined standing measure

The analysis inherits the certified Local Match v2 P5c inventor roster,
matching weights, treatment assignment, and 1993--2010 cohort window. Deals
with missing or placeholder acquirer identifiers are excluded because their
combined inventor pools cannot be constructed.

For inventor (i) in acquisition cohort (g), pre-acquisition productivity is
the number of distinct patent applications assigned to the inventor's focal
organization during (g-5,ldots,g-1). Initial target standing is

\[
S^{T}_{ig}=100\times
\frac{\#\{j\in T_g:P_{jg}<P_{ig}\}}{N_{T_g}},
\]

where (P_{ig}) is inventor (i)'s five-year patent count and (N_{T_g}) is
the number of productive inventors in the target. Ties receive the same
strict-lower percentile.

Projected combined standing applies the same formula after pooling the target
and acquirer inventor populations:

\[
S^{C}_{ig}=100\times
\frac{\#\{j\in T_g\cup A_g:P_{jg}<P_{ig}\}}{N_{T_g\cup A_g}}.
\]

Predicted relative-standing loss is

\[
L_{ig}=S^{T}_{ig}-S^{C}_{ig}.
\]

Positive values denote downward movement. Every input predates acquisition.
For matched controls, the control inventor's focal organization is pooled
separately with the treated deal's acquirer. This produces a predetermined
pseudo-loss on the same scale without incorrectly pooling all control firms
together.

## Theory-aligned population and functional form

The primary population consists of inventors whose initial focal-firm standing
is at least the 80th percentile. This top-quintile cutoff was already encoded
in the frozen top-20 sensitivity and mechanically requires at least five
productive inventors in the focal organization. Cutoffs at the 75th and 90th
percentiles form a fixed sensitivity family.

Within the high-standing sample, define separate loss and gain magnitudes:

\[
L^+_{ig}=\max(L_{ig},0),\qquad
G^+_{ig}=\max(-L_{ig},0).
\]

The weighted regression is

\[
\Delta Y_{ig}=\alpha_g+\tau D_{ig}+\beta_L L^+_{ig}
+\beta_G G^+_{ig}+\delta_L(D_{ig}\times L^+_{ig})
+\delta_G(D_{ig}\times G^+_{ig})
+X_{ig}'\gamma+D_{ig}X_{ig}'\pi+\varepsilon_{ig}.
\]

(D_{ig}) identifies treated target inventors. The focal coefficient is
(\delta_L): the change in the acquisition ATT associated with a
ten-percentage-point larger predicted loss among initially high-standing
inventors. The gain hinge is included as a nuisance term and is not interpreted
as part of the status-loss mechanism.

(X_{ig}) contains initial standing itself, nonlinear five-year productivity,
the pre-deal patent trajectory, patenting at (t=-1), career age, focal-group
tenure and exclusivity, persistent-team measures, focal inventor-pool size,
and the number of inventors added by the acquirer. These predetermined
characteristics enter both directly and interacted with treatment.

## Weighting and identification diagnostics

The preferred specification applies a cohort-preserving entropy tilt within
the top-quintile sample. Treated P5c weights remain unchanged; control weights
are tilted to reproduce the treated means of loss and gain magnitudes, initial
standing, absolute productivity, the complete pre-deal patent path, career and
team characteristics, and organizational size. The maximum absolute audited
SMD falls from 0.228 under the inherited P5c weights to less than 0.000002.

Inference uses 9,999 Webb deal-level multiplier draws and two-way clustering by
deal and inventor. The wider confidence interval and larger p-value govern.
The joint pre-period trajectory diagnostic tests the loss-side gradient at
(t=-5,ldots,-2), relative to (t=-1). Under entropy weights its p-value is
.439, and none of the four individual pre-period coefficients is significant.
Because these years also enter the standing measure, the exercise is an
overlapping-window trajectory diagnostic rather than an independent held-out
pretrend test.

## Outcome and five-year aggregation

The underlying outcome is the inventor's mean annual patent count over
(t=+1,ldots,+5) minus the mean annual patent count over
(t=-5,ldots,-1). This is the conventional five-year-pre versus
five-year-post DiD used in the thesis heterogeneity section. The
relative-standing coefficient is therefore an effect on average annual
patenting across the two five-year windows.

Following the thesis reporting convention, the cumulative five-year
coefficient is five times the average annual coefficient:

\[
\widehat\delta_L^{5yr}=5\widehat\delta_L^{annual}.
\]

The standard error and confidence-interval endpoints are also multiplied by
five. The t-statistic and p-value are unchanged because this is a change of
units, not a new estimator or additional information.

## Preferred result

Under the entropy-balanced top-quintile specification, the average annual
loss-side gradient is

\[
\widehat\delta_L^{annual}=-0.0638,
\qquad 95\%\text{ CI }[-0.1670,0.0395],
\qquad p=.226.
\]

On the thesis's cumulative five-year scale, this is

\[
\widehat\delta_L^{5yr}=-0.319,
\qquad 95\%\text{ CI }[-0.835,0.197],
\qquad p=.226.
\]

Thus, among inventors initially in the target's top quintile, a ten-point
larger predicted standing loss is associated with 0.319 fewer patents over the
five post-acquisition years relative to matched controls. A forty-point loss,
such as a move from the 90th to the 50th percentile, corresponds to a point
estimate of approximately 1.28 fewer patents over five years.

The fixed threshold family is directionally consistent. The cumulative
five-year gradients are -0.336 at the 75th-percentile cutoff, -0.364 at the
80th-percentile cutoff before rebalancing, and -0.404 at the 90th-percentile
cutoff. The top-quintile actual-loss-only estimate is -0.274. All confidence
intervals include zero.

The initially retained standing-loss regression is not part of the main
results. Retention is determined after acquisition, and the top-quintile loss
subsample contains only 304 treated inventors. Its patent-count coefficient is
positive but very imprecise, while its active-patenting coefficient is
negative and equally imprecise. I retain both estimates in the appendix for
transparency rather than interpreting either sign.

## Interpretation and limitation

The negative sign is stable across the high-standing thresholds, the
actual-loss-only restriction, and entropy rebalancing. This is suggestive
evidence consistent with the relative-standing mechanism: former target stars
who are predicted to fall further in the combined hierarchy experience larger
patenting declines. The analysis does not establish statistical significance
or direct mediation. Patent rank is a proxy for status, and the data do not
observe perceived prestige, decision authority, autonomy, or Paruchuri et
al.'s acquisition-integration indicator.

This is a post-results, theory-driven refinement motivated by the documented
support failure of the symmetric full-cohort specification. It should be
reported transparently and should not be presented as if it were part of the
original confirmatory family.

## Reproducibility

The five-by-five analysis is produced by
`02_analysis/R/65k_estimate_lmv2_relative_standing_5x5.R`. The preferred
reader-facing estimates are stored in `table_relative_standing_5x5.csv`;
the complete results, including the inherited-weight sensitivity, are stored
in `relative_standing_5x5_results.csv`. Entropy-balance and weight diagnostics
are in the same `P7_RELATIVE_STANDING/nested_5x5` directory. The separate
retained standing-loss estimates are stored in
`table_relative_standing_5x5_retained_loss_appendix.csv`. The separate
pre-period trajectory diagnostic remains in
`P7_RELATIVE_STANDING/high_standing_loss_v2`.
