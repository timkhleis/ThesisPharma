# Simple untreated-firm placebo

## Purpose

This is a preliminary falsification of the recruitment and event-time
construction. It asks whether the analysis produces a systematic patent-count
effect when treatment is assigned randomly among untreated firms. It does not
reproduce the P5 support restrictions or entropy-balancing solve and therefore
does not validate the full preferred design.

## Design

For each acquisition cohort from 1994 through 2010, the procedure randomly
selects 200 eligible U2-clean control firms and assigns 100 to pseudo-treatment
and 100 to pseudo-control. A firm cannot be used in more than one cohort within
a draw. Both arms use the same pre-period inventor recruitment rule. Inventors
with a real treatment on or before five years after the pseudo-event are
excluded.

The outcome is annual patent count. The coefficient compares the change from
event time -1 to the average of event times +1 through +5 between the two
pseudo-arms. The regression includes cohort fixed effects and weights firm
means by the number of recruited inventors. Analytic inference uses firm-level
HC3 standard errors, which correct for leverage from very large firms. A
second, small-cluster inference uses a 999-replication Webb wild bootstrap at
the 17 pseudo-cohort level. The conservative decision rule labels a draw
significant only when both methods reject; its reported p-value is the larger
of the two. The reported implementation repeats the assignment 2,000 times.

## Results

The placebo estimates center close to zero:

- mean placebo ATT: -0.00074 patents per inventor-year;
- Monte Carlo standard error of the mean: 0.00058;
- test of a zero mean: p = 0.203;
- 2.5th and 97.5th percentiles: -0.0507 and 0.0520;
- 50.55% of the estimates are negative;
- mean recruited inventors per draw: 45,184 in pseudo-treatment and 45,192 in
  pseudo-control.

The firm-level HC3 test rejects in 5.10% of draws, and the cohort-level wild
bootstrap rejects in 5.55%. Under the conservative requirement that both
methods reject, 77 of 2,000 draws (3.85%) are significant: 36 negative and
41 positive. The signs and rejection rates therefore show no systematic
negative displacement.

The certified full-cohort ATT is -0.05340 patents per inventor-year. Only 41
of 2,000 placebo estimates are at least as negative, giving a descriptive
left-tail probability of 2.05% (plus-one estimate: 2.10%; exact binomial 95%
interval: 1.48% to 2.77%). This is informative about how unusual the result is
under the simplified untreated-firm assignment. It is not a formal
randomization-inference p-value for the preferred ATT because the placebo firms
do not reproduce the actual target sample's firm-size and composition
distribution.

If the placebo assignments were perfectly comparable to the actual treated
sample, this tail frequency would resemble a one-sided p-value of 0.021 and,
using the approximately symmetric placebo distribution, a two-sided p-value of
about 0.041. These values are useful descriptive benchmarks, not formal
randomization-inference p-values, because the untreated placebo firms differ
slightly from acquisition targets.

## Interpretation

The useful preliminary result is narrow: random untreated-firm assignments do
not generate a systematic negative effect. This reduces concern about a
deterministic coding or recruitment-clock artifact that mechanically forces
post-period estimates below zero.

The 2,000-draw distribution also shows that the inference is appropriately
calibrated under random assignment. The test should nevertheless appear as a
short appendix pipeline falsification. It is not randomization inference for
the preferred ATT because the pseudo-treated samples differ from the actual
target sample in firm size and composition. It also does not resolve
acquisition-related selection or mean reversion.

## Thesis-ready robustness paragraph

As a pipeline falsification, I randomly assign placebo treatment among
untreated U2-clean firms and apply the same inventor-recruitment and event-time
rules. Across 2,000 assignments, the mean placebo effect is -0.0007 patents per
inventor-year and is statistically indistinguishable from zero. HC3 and
cohort-level wild-bootstrap rejection rates remain close to 5%, while the
conservative rule requiring both methods to reject does so in 3.85% of draws.
Only 41 assignments (2.05%) produce an estimate at least as negative as the
preferred ATT of -0.0534. If the placebo and actual target samples were
perfectly comparable, this frequency would resemble a one-sided p-value of
0.021 and a two-sided p-value of about 0.041. Because untreated placebo firms
differ slightly from acquisition targets, I interpret these values as
descriptive tail probabilities rather than formal randomization-inference
p-values. The exercise shows that the recruitment and estimation pipeline does
not mechanically generate negative post-event effects.

## Reproduction

Run from the P6 worktree:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' `
  '02_analysis/R/36_run_lmv2_simple_control_placebo.R' `
  --draws=2000 `
  --firms-per-arm=100 `
  --headline-only=true `
  --bootstrap-reps=999 `
  --output-dir='02_analysis/output/appendix/simple_control_placebo_2000draw'
```
