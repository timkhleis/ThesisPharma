# P5b S0-S2 results: initially-retained inventor design

Status: implemented and certified
Execution hash: `b7e97836125116424a55e5fa21e566bf49f6a329`

## Bottom line

The primary \(t=+1,\ldots,+5\) initially-retained definition is feasible and
passes all prospective population, deal-count, concentration, control-symmetry,
timing, uniqueness, and classification-coherence checks.

It identifies 3,090 initially retained treated inventors across 172 deals. The
raw effective deal count is 33.39, above the predeclared floor of 20. P5b may
therefore proceed to a separately balanced stayer design; the full-cohort P5c
weights must not simply be restricted.

## Treated partition

The full status-eligible P2 population contains 28,483 treated inventors.

| Primary \(t=+1,\ldots,+5\) status | Inventors | Share of all treated |
|---|---:|---:|
| Initially retained | 3,090 | 10.85% |
| Leaver | 1,158 | 4.07% |
| No post-deal patent | 24,235 | 85.08% |

Among inventors with any observed patent in the classification window, 72.74%
are initially retained.

There are no unresolved first-post affiliations under the production resolver,
and a synthetic unresolved case now proves that the unresolved check can fire.
The zero is therefore a property of the completed resolver, not a structurally
non-firing guard.

The raw patent-level audit shows that mixed evidence is economically relevant:
352 of 3,090 retained treated inventors (11.39%) and 37,971 of 531,614 retained
control-cohort rows (7.14%) contain both focal and outside group evidence in the
first post-patenting year. The production resolver selects one annual group
using career continuity, modal career affiliation, inventor-year patent
counts, and a deterministic final tie-break. The resolved rule remains the
headline, but a raw-unmixed sensitivity is now required.

The P2 target-company route qualifies 151 initially retained inventors whose
resolved group ID alone points outside the target/acquirer group pair. A
required route-consistent sensitivity excludes these 151 cases.

## Power and concentration

| Classification window | Retained inventors | Deals | Raw effective deals | Largest deal share |
|---|---:|---:|---:|---:|
| \(t=+1,\ldots,+5\), primary | 3,090 | 172 | 33.39 | 8.67% |
| \(t=+2,\ldots,+5\), sensitivity | 2,360 | 150 | 32.48 | 9.11% |

The effective deal count is lower than the nominal deal count because treated
inventors are concentrated across deals. It is a concentration measure,
\((\sum_d n_d)^2/\sum_d n_d^2\), not evidence of a bootstrap error.

The \(+2,\ldots,+5\) definition is a required timing companion. Its inventor
count is lower, but its 32.48 effective deals are almost identical to the
primary design's 33.39. If its estimate differs, the unresolved
announcement-versus-completion timing question becomes substantively
important.

## Symmetric controls

The primary rule produces 531,614 eligible retained control-inventor cohort
rows, representing 159,587 distinct inventors and 6,467 control groups before
local P5 support restrictions.

Controls remain tied to the same clean pre-event group. Actual movement to
another group is classified as leaving; no successor group has been
automatically admitted.

The synchronized group-ID audit flags 331 firm-cohorts. They contain 5,030 of
631,945 post-patenting control-inventor cohort rows, or 0.796%. This is below
the prospective 1% review threshold, so mechanical group-ID discontinuity is
not a primary-design blocker.

For the \(+2,\ldots,+5\) sensitivity, the analogous share is 1.044%. This small
threshold exceedance is retained as a sensitivity qualification; it does not
alter the primary definition or justify automatic successor remapping.

## Certification

All production checks pass:

- source hashes change under a real source mutation;
- synthetic duplicate, concentration, and continuity positives make their
  corresponding checks fire;
- the affiliation table is unique by inventor-year;
- treated and control partition keys are unique;
- no first-post year falls outside its declared window;
- every status belongs to the frozen status domain;
- every retained record has coherent focal evidence;
- unresolved shares are zero;
- all three primary feasibility gates pass.

## Next implementation gate

The next package is S3, the separately balanced P5b design:

1. restrict treated and control candidates to the primary initially-retained
   populations;
2. apply the frozen clean U2 firm and IPC4 support rules;
3. report retained-control-firm dependence at the deal-stack level without
   imposing an invalid per-inventor edge-count threshold on the
   projection-preserving P5 graph;
4. rebuild entropy weights rather than subsetting P5c weights;
5. certify balance, treated retention, control ESS, nominal/effective deals,
   and concentration before opening outcomes.

The subsequent outcome-blind S3 amendment restored all 17 cohorts. It
excludes three cohort-2008 convex-hull outliers, retains five single-control-
firm deal stacks as flagged diagnostics, and uses a robust entropy warm start
when the original Newton initialization fails numerically.

The subsequent selection table will report the inventor's five-year linear
pre-trend, not five separate annual rows, and will omit firm patent trajectory.
Those reporting choices do not silently weaken the annual P5c balance
constraints or the frozen firm-support screen.
