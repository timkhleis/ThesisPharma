# Local Match v2 — P6 pre-analysis freeze

Frozen on 2026-07-26 before opening any treatment-effect estimate.

This document is the consolidated P6 estimation freeze. It supersedes no P0
or P5 design decision; it collects the exact outcome, estimator, inference,
censoring, and reporting choices needed to make the outcome stage
reproducible. No ATT had been computed when the estimator details below were
added.

## Design authority

The certified P5 U2-clean, reduced-covariate, Stage-1-caliper 2.0,
Stage-2-caliper 1.5, IPC4 entropy-balanced roster remains the headline
design. P6 may attach outcomes and estimate the specifications listed here;
it may not repair, rebalance, renormalize, or select among P5 rosters after
seeing outcomes.

IPC4 is the prospectively agreed technology resolution and remains the
primary support screen. It is consistent with the matching granularity used
in the relevant literature and is appropriate for the primary design.
Henkel remains an eligible control firm because it is present in the source
data and passes the frozen IPC4 and firm-support rules. Finer-resolution
diagnostics show that IPC4 is a coarse screen for some donor pairs; this is a
disclosed limitation and motivates a labeled robustness check, not a
post-outcome deletion from the primary design.

## Outcomes and horizons

Primary outcomes:

1. integer patent count;
2. active-patenting indicator;
3. TechDrift, reported as one minus the frozen IPC4 cosine similarity.

Secondary outcomes:

1. OECD PQII patent quality;
2. five-year forward citations.

The OECD outcomes are secondary because linkage and late-year coverage are
incomplete. For each secondary outcome P6 materializes a linkage-scaled
total, an observed total, a complete-linkage total, and a conditional mean.
The linkage-scaled total is the leading secondary measure; the other three
variants diagnose sensitivity to missing linkage and the extensive margin.
Missing OECD linkage is never coded as zero.

The event-study window is \(t=-5,\ldots,+5\). The headline post-treatment
summary is \(t=+1,\ldots,+5\), and \(t=+5\) remains reported for every locked
cohort so that the outcome analysis is directly comparable with the main
ATT design. Late-sample coverage warnings do not remove \(t=+5\). P6 also
reports:

- the locked 1994–2010 cohort result;
- the 1994–2008 censoring-clean companion;
- event-time-specific patent and OECD coverage, including explicit flags for
  calendar years 2014–2015.

Any interpretation of \(t=+4\) or \(t=+5\) must display the corresponding
coverage rather than treating the late tail as fully observed.

## Point estimator

P5 solved balance once per treatment-year cohort on the pooled cross-deal
roster. It did not achieve or require balance separately within every deal.
P6 therefore estimates the frozen cohort-pooled event study

\[
Y_{idge}
=\alpha_{idg}+\lambda_{ge}
+\sum_{k\ne-1}\beta_k
  1\{e=k\}\,\mathrm{Treated}_{idg}
+\varepsilon_{idge},
\]

where \(i\) is the inventor, \(d\) the focal deal stack, \(g\) the acquisition
cohort, \(e\) event time, \(\alpha_{idg}\) a conceptual roster-row fixed
effect, and \(\lambda_{ge}\) a cohort-by-event-time fixed effect. For
transparent and memory-safe computation, P6 evaluates the algebraically
equivalent first-difference form separately at each event time:

\[
\widehat{ATT}_{ge}
=\overline{(Y_e-Y_{-1})}_{T,g,w}
-\overline{(Y_e-Y_{-1})}_{C,g,w},
\qquad
\widehat{ATT}_{e}=\sum_g q_g\widehat{ATT}_{ge},
\]

where \(q_g\) is the cohort's share of the frozen treated P5 weight in the
reported sample. The certified P5 weights enter every mean verbatim. There
is no weight repair, trimming, or outcome-based cohort reweighting.
Controls reused across deal stacks remain separate conceptual roster rows;
their common inventor identifier is retained for two-way inference.

For outcomes with missing values, each \(e\) uses roster rows observed both
at \(e\) and at the reference year \(-1\). The treated and control means are
formed within cohort on those pairwise-observed rows. A cohort-event cell
enters only when both arms have positive observed weight; the frozen design
shares \(q_g\) are then renormalized over the estimable cohorts for that
event. This is an availability standardization, not outcome-value weighting.
Pairwise coverage, treated/control observed weight mass, excluded cohorts,
and the retained frozen treated-weight share are reported for every event
time. The event-study plot must visibly flag any event whose cohort set is
not complete, and \(t=+5\) remains displayed even when its availability set
is smaller.

This availability rule was added after the memory-safe estimator's first
production tooth-check detected two structurally empty TechDrift cells
(treated cohort 1996 at \(t=-5\), and treated cohort 2010 at \(t=+5\)).
The failed run wrote no result artifact and no inference output. Its error
message did expose the provisional direct TechDrift post average; this is
recorded here rather than hidden. The rule is dictated solely by the
defined-outcome support failure, applies identically to every outcome, and
does not use effect sign, magnitude, or significance.

Deal-by-event-time comparisons are not used because they would convert the
frozen cohort-pooled design into a deal-specific comparison for which P5 did
not require balance.

The dynamic coefficients \(\beta_k\) are reported for \(k=-5,\ldots,+5\),
with \(k=-1\) fixed to zero. The headline ATT is the equal-horizon average
\(\frac{1}{5}\sum_{k=1}^{5}\beta_k\). For count outcomes its five-times
multiple is additionally reported as the cumulative five-year effect.
Event time zero is shown but excluded from the headline post average.

The formal pre-trend test is the joint test
\(\beta_{-5}=\beta_{-4}=\beta_{-3}=\beta_{-2}=0\). The four individual
coefficients are always shown; they are falsification diagnostics for the
frozen design and never criteria for selecting another P5 roster.

Patent count and active patenting use the complete balanced panel. TechDrift
uses inventor-years for which the IPC4 cosine is defined and is explicitly
labelled a conditional-technology outcome. OECD variants retain their frozen
missing-value rules; model-specific observed row counts and treated/control
weight masses are mandatory because missing linkage can change the
estimation sample.

## Frozen estimands and sensitivity rosters

The following comparisons are all reported; none is used to choose the
design:

1. headline primary-weight ATT on the full certified supported sample;
2. equal-deal-weight ATT for cohorts where the frozen P5 equal-deal solve is
   feasible;
3. primary-weight ATT on the same cohorts as item 2;
4. a no-deal-70 sensitivity that re-solves cohort 2000 under the unchanged
   support and balance rules after excluding deal 70;
5. nine single-firm-deletion influence refits for deal 70;
6. a Henkel-omitted exact-balance sensitivity, accepted without applying the
   headline ESS gate and accompanied by its realized ESS and interval.

The reporting hierarchy is fixed as follows:

1. full 17-cohort primary-weight patent count and active patenting;
2. their 1994--2008 censoring-clean companions;
3. primary TechDrift with its defined-outcome coverage;
4. secondary OECD PQII and forward-citation variants with linkage coverage;
5. equal-deal and like-for-like weighting comparisons;
6. no-deal-70, all single-firm-deletion, and Henkel-omission sensitivities;
7. common-support selection scenarios;
8. DealSim heterogeneity only after the main full-cohort package is complete.

Every available enumerated sensitivity is reported. Missing or infeasible
rosters are recorded as such, never silently omitted. Sign, magnitude,
pre-trends, or precision cannot change this hierarchy.

Deal 70 carries 7.60% of treated weight and 10.19% of control weight in the
headline roster. Henkel carries 29.85% of deal-70 control weight, 23.53% of
cohort-2000 control weight, and 3.04% of total headline control weight.

No sensitivity weight is interpreted as a causal “deal-70 ATT” when its
weights were solved at cohort level. Instead, P6 reports how each deletion
changes the full headline ATT and the cohort-2000 ATT. The no-deal-70 design
is labeled as a re-estimated exclusion sensitivity, not a row filter.

## Inference

Every aggregated headline ATT uses `fwildclusterboot` 0.14.3 with deal-level
clusters, Webb six-point weights, 9,999 replications, seed 20260722,
null-imposed resampling, a two-sided test, and a 95% bootstrap-t confidence
interval. The tested parameter is the equal-weight linear combination of the
five \(t=+1,\ldots,+5\) event coefficients. The bootstrap is evaluated on
the compact deal-by-arm-by-cohort-by-event sufficient-statistics regression;
its coefficient is tooth-checked against the direct estimator before
resampling.

Two-way deal/inventor cluster-robust and deal-only cluster-robust intervals
are reported as companions. Dynamic plots and the joint pre-trend test use
the two-way covariance computed from the exact conceptual-roster-row
influence contributions. The governing headline interval is whichever of the
wild-bootstrap and two-way intervals has greater width; an exact width tie
is resolved in favour of the wild-bootstrap interval. If the intervals are
non-nested or imply different directional conclusions, the result is
described as inference-sensitive rather than resolved by selecting one.

Nominal treated-deal count and the treated-weight effective deal count
\(1/\sum_d s_d^2\) accompany every headline result. Cohort-specific and
small-cluster results carry an explicit few-cluster warning.

The placebo-timing and alternative-control-group exercises remain required
falsifications, but they require new, explicitly labelled rosters/event
windows. They cannot be approximated by relabelling the certified P5 panel
or used to choose among the results listed above.

## Support and selection

The primary ATT remains the ATT for the entropy-balanced common-support
sample. Cardinality recovery, when feasible, is a separate
recovered-inventor estimand and is not inserted into the primary weights.
The all-eligible target-population decomposition is

\[
ATT_{\mathrm{all}}
=p\,ATT_{\mathrm{supported}}
+(1-p)\,ATT_{\mathrm{unsupported}}.
\]

P6 reports the unsupported-versus-supported pre-treatment descriptive
statistics and sensitivity bounds. These analyses do not retroactively
select a matching design.

Stayer-specific causal estimates require the separately certified P5b
stayer-selection handoff. P6 outcome construction alone does not authorize a
stayer ATT. In particular, restricting P5a full-cohort rows to observed
post-treatment stayers does not preserve P5 balance and is prohibited as a
headline estimate.

## Provenance and stop rules

The P6 runner must:

- pin the exact approved P5 roster hash and P5 design hash;
- require all 17 locked cohorts in the primary roster;
- reject duplicate conceptual roster rows independently of a row identifier;
- require positive-weight control support from at least two firms per deal;
- preserve P2 assignment-route and ambiguity fields;
- double-build and checksum all outcome ingredients;
- report OECD linkage non-randomness diagnostics using every available
  pre-link patent characteristic;
- stop before any ATT if a certification check fails.

The P5 design-search history, including the Henkel diagnostic, is retained in
the specification-search record. The primary IPC4/Henkel decision stated
above is frozen before outcome inspection.
