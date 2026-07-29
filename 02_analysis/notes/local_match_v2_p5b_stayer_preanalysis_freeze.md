# Local Match v2 P5b: initially-retained inventor pre-analysis freeze

Status: frozen before P5b outcome estimation
Version: `lmv2_p5b_stayer_s0_s2_v1`

## 1. Purpose and estimand

P5b asks how inventors who are initially retained in the focal corporate
ecosystem patent after an acquisition. It is a separately balanced design. The
full-cohort P5c weights are not restricted and reused.

The resulting contrast is a selected-group comparison between retained treated
inventors and retained control inventors. It is not a treatment-invariant
principal-stratum ATT unless acquisition is assumed not to affect retention.
That assumption is not imposed. Selection diagnostics and bounds therefore
carry the causal interpretation; the point estimate alone is not described as
the causal effect for an always-retained principal stratum.

## 2. Treated initially-retained definition

The primary classification window is event time \(t=+1,\ldots,+5\). Event time
zero is excluded because a deal-year patent may precede completion.

For each status-eligible treated inventor:

1. Find the first observed patenting year in the classification window.
2. Classify the inventor as **initially retained** when that year's patent
   evidence places the inventor in the focal ecosystem: the target group, the
   acquirer group, or the deal-specific target-company route already frozen in
   P2.
3. Classify an inventor whose first observed post-deal patent is outside that
   ecosystem as a **leaver**.
4. Classify an inventor without a patent in the window as **no post-deal
   patent**. Patent data cannot determine whether this means employment exit,
   an internal nonpatenting role, or exit from inventive activity.

The timing sensitivity repeats the definition over \(t=+2,\ldots,+5\). It is
reported as a sensitivity, not used to replace the primary rule based on which
estimate is more favorable.

`inventor_affiliation_own` assigns one resolved group per inventor-year using
the following ordered rule: unique group; previous-year continuity; next-year
continuity; career-modal group; unique inventor-year patent-count maximum; and
finally the smallest numeric group ID as a deterministic tie-break. This
resolved assignment defines the headline classification, but it does not imply
that the underlying patent links contain only one group.

The raw patent links are therefore audited before S3. An inventor is
raw-mixed when the first post-patenting year contains both focal and outside
group evidence. The headline keeps the approved resolved affiliation, while a
required raw-unmixed sensitivity excludes raw-mixed treated and control rows.
Disagreement between the resolved-group and P2 target-company routes is also
retained as an audit field and receives a required route-consistent
sensitivity.

Unresolved first-post affiliations are excluded from the substantive location
universe and retained only in the certification output. They are not presented
as a separate economic group.

## 3. Symmetric control analogue

For every eligible control inventor and pseudo-event cohort, the focal entity
is the same clean control group used in the pre-period. A control is initially
retained when the first patent in the same classification window resolves to
that group.

There is no acquisition in the control arm, so an actual move to another group
is a leaver event and is not admitted as retention. A separate diagnostic looks
for synchronized group-ID transitions that could reflect a mechanical database
recode rather than inventor mobility. The diagnostic does not automatically
admit successor groups.

A control firm-cohort is flagged for review when it has at least five
post-patenting inventors, at least 50% move to the same outside modal group, and
at most 25% remain under the original group ID. The design proceeds without
successor remapping when flagged firm-cohorts contain no more than 1% of all
post-patenting control-inventor cohort rows.

## 4. Prospective feasibility gates

The primary treated-retained population must contain:

- at least 3,000 inventors;
- at least 150 acquisition deals;
- a raw effective deal count of at least 20, where
  \[
  N_{\mathrm{eff,deal}} =
  \frac{(\sum_d n_d)^2}{\sum_d n_d^2}.
  \]

The effective count measures deal concentration and can be much smaller than
the nominal number of deals. It is not a bootstrap implementation diagnostic.

No new three-control requirement is imposed per treated inventor. The
projection-preserving P5 edge cover is not a complete pair graph, so that rule
would be both unnecessarily restrictive and invalid on the persisted object.
P5b reports the number of retained control firms for each treated-deal stack
as a dependence diagnostic. It does not impose two firms as a hard support
gate: five small stacks containing 18 treated inventors have one retained
control firm but remain usable for cohort-level balancing. They are flagged
for sensitivity analysis and remain covered by deal-aware inference.

## 5. P5b balancing stage after S0-S2

If the primary feasibility and continuity gates pass, P5b will rebuild
entropy-balancing weights within the initially-retained treated and control
populations. The frozen clean U2 firm restrictions and local technological
support rules remain the headline design. The \(t=+2,\ldots,+5\) companion is
required because it is immune to the unresolved announcement-versus-completion
timing question; it is not described as merely optional.

The balancing specification inherits the P5c annual inventor patent-count and
active-patenting constraints. The later selection table compresses the five
annual patent counts into an inventor-specific linear slope for readable
reporting. This reporting compression does not replace the annual balance
constraints.

Firm patent trajectory is omitted from the new stayer-selection diagnostic
table and from the final S3 balancing vector. Existing firm-support
restrictions are not silently changed. Three cohort-2008 treated inventors are
excluded by an outcome-blind maximum-retention convex-hull diagnostic; this
minimal support amendment restores stable exact balance and all 17 cohorts.
For the \(t=+2,\ldots,+5\) timing companion only, firm patent stock remains
balanced while the highly related firm inventor-count scale is omitted to
preserve the prospectively frozen ESS floor in cohort 2010.

## 6. Diagnostics and reporting commitments

- The principal held-out pre-period checks are \(t=-3\) and \(t=-2\). A
  held-out confidence interval that is not contained inside the predeclared
  equivalence band is labeled uninformative, not a placebo pass.
- The main outcome is annual patent count. Active patenting, quality, forward
  citations, and technology drift are secondary.
- The initially-retained sample is split into established and more recently
  recruited inventors as a predeclared heterogeneity result. This does not
  replace the main initially-retained estimand.
- Null and imprecise results are reported without changing the sample,
  retention definition, balance variables, or inference method.
- Inference remains deal-aware; the nominal inventor count is never treated as
  the independent sample size.

## 7. Approved implementation order

1. S0: provenance and freeze certification.
2. S1: treated partition under \(+1\ldots+5\) and \(+2\ldots+5\).
3. S2: symmetric control partition and group-ID continuity audit.
4. Check-in on feasibility and continuity.
5. Only then freeze and run the P5b entropy-balancing solve.
