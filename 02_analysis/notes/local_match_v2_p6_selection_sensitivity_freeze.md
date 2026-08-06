# Local Match v2 — P6 selection-sensitivity freeze

**Frozen:** 2026-07-26, before opening any outcome or treatment-effect object.

This note fixes two separate sensitivity analyses. Common-support exclusion is
a pre-treatment overlap problem. Stayer selection is a post-treatment sample
selection problem. The analyses are reported separately because they require
different assumptions.

## 1. Common-support exclusion

The headline estimate is
`ATT_supported`, the ATT for treated inventors retained by the clean U2
support design. For each outcome, report

\[
 ATT_{\mathrm{all}}
 = p ATT_{\mathrm{supported}}
 + (1-p)ATT_{\mathrm{unsupported}},
\]

where `p` is realized inventor coverage under the frozen P5.3 design.

### Fixed sensitivity grid

Let `sigma_pre` be the standard deviation of the inventor-level mean of the
outcome over event years -5 through -1 among all eligible treated inventors.
Compute `sigma_pre` after winsorizing that pre-treatment mean at the 1st and
99th percentiles within outcome. Do not use post-treatment observations to
set this scale.

Evaluate

\[
 ATT_{\mathrm{unsupported}}
 = ATT_{\mathrm{supported}} + \delta\sigma_{\mathrm{pre}}
\]

for

\[
 \delta \in
 \{-3,-2,-1.5,-1,-0.5,0,0.5,1,1.5,2,3\}.
\]

Report the resulting `ATT_all` for every grid value, overall and for any
cohort below the 0.80 scope-review threshold. Do not select a preferred
delta after seeing the results.

### Reversal calculation

Report both:

\[
 ATT_{\mathrm{unsupported}}^{*}
 = -\frac{p}{1-p}ATT_{\mathrm{supported}},
\]

the unsupported-tail ATT that sets `ATT_all` to zero, and

\[
 \delta^{*}
 = -\frac{ATT_{\mathrm{supported}}}
          {(1-p)\sigma_{\mathrm{pre}}},
\]

the required supported-to-unsupported difference in pre-treatment standard
deviations. If `p=1`, report that no unsupported-tail calculation is needed.

### Descriptive table

For supported and unsupported treated inventors, report the pre-deal
distribution of:

- patent count;
- patent trajectory;
- career age;
- focal-group exclusivity;
- focal-group tenure; and
- every pre-treatment outcome scale used above.

Report means, standard deviations, the 10th, 25th, 50th, 75th, and 90th
percentiles, absolute SMDs, and unsupported-to-supported standard-deviation
ratios. The table must retain the previously observed ratios
1.70, 1.94, 2.70, and 1.94 as pilot benchmarks, while replacing them with
realized full-production values for inference.

These calculations are sensitivity analyses, not Lee bounds. They do not
claim that unsupported inventors are identified.

## 2. Post-treatment stayer selection

Use Lee (2009) trimming only for the post-treatment stayer-selection problem.
State the monotonicity assumption next to every bound.

Because the direction of stayer selection is empirically open, report both
directional exercises:

1. trim the upper tail of the selected comparison distribution; and
2. trim the lower tail of the selected comparison distribution.

Set the trimming share from the realized differential selection rate in the
corresponding cohort and event-time cell. Never substitute the P5
common-support rate for the post-treatment stayer-selection rate.

Report untrimmed and trimmed sample sizes, the realized trimming share, the
lower and upper Lee estimates, and deal-clustered uncertainty. If the
monotonicity condition or required selection-rate ordering fails in a cell,
label the Lee bound undefined rather than changing the trimming rule.

## 3. Reporting order

For every main outcome:

1. report the frozen supported-sample ATT;
2. report the common-support scenario grid and reversal value;
3. report supported-versus-unsupported descriptives;
4. report the separate Lee bounds for stayer selection; and
5. state which population and assumption each quantity covers.

No sensitivity result may be used to choose the matching design, outcome
definition, event window, or reported weighting scheme.

