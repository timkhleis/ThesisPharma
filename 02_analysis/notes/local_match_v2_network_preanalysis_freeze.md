# Local Match v2 network pre-analysis freeze

Status: frozen before the N0 network census

Date: 2026-07-30

## Scope and sequencing

N0 is an outcome-blind support census. Its code may use the certified P5c
roster and patent links from event times -5 through -1. It may not construct,
read, summarize, or estimate an event-time-zero or post-acquisition network
outcome. N0 can release N1, which remains pre-treatment, but it cannot release
N2 directly.

The predetermined full target-inventor cohort on the certified P5c
count-active roster is primary. Each `roster_row_id` is an analysis row.
Initially retained P5b inventors do not enter N0 and cannot change the network
definition.

## Application and dyad construction

The application-inventor source is `patent_inventor_enriched`, whose
`(appln_id, codinv)` key must be unique. An application-level undirected dyad
is the ordered pair `(min(codinv_a, codinv_b), max(codinv_a, codinv_b))`.
Self-links and duplicate names on an application are removed. A pair appearing
on two applications contributes two application-dyad records.

For each P5c roster row, a focal-partner link is one distinct
`(appln_id, focal_codinv, partner_codinv)` record on a focal inventor's patent.
Event time equals application year minus the roster row's acquisition cohort.

## Baseline ties and analysis support

The anchor is event time -5 through -3. A partner is a persistent baseline
collaborator only if the focal-partner pair has:

- at least two distinct joint patent applications in the anchor; and
- joint applications in at least two distinct anchor years.

Event times -2 and -1 are validation years. They never enter the persistent-tie
definition. Event time -6 is not an allowed fallback.

The network analysis support consists of P5c roster rows with at least one
persistent baseline collaborator. P5c weights are retained without rematching,
renormalizing, or outcome-based trimming.

## Frozen annual outcomes

All outcomes are constructed at the `roster_row_id` by event-year level.
Dynamic estimates use annual outcomes. Any +1 through +5 summary, if N2 is
released, is the equal-weight mean of the five annual event-time effects; it
does not pool applications across years.

### 1. Collaborator focal-organization persistence share

The denominator is the focal inventor's full set of persistent baseline
collaborators in every calendar year observed by the design. A baseline
collaborator remains in the denominator if the collaborator does not patent in
that year; no patent is a substantive zero, not missingness. "At risk" means
that the baseline tie exists and the evaluation calendar year lies within the
1988--2015 study window. It does not condition on a collaborator's future last
patent year.

The numerator counts baseline collaborators with at least one patent assigned
to the focal organization in the evaluation year. Before acquisition, the
treated focal organization is the target group or a strict target company.
After acquisition, it is the target group, the certified acquirer group, or a
strict target company. For controls it is the frozen control group in every
year. This broader treated post-acquisition definition weakly favors measured
persistence and is therefore conservative for a disruption interpretation.
Event time zero is excluded.

The share is always defined on network support and lies in `[0,1]`. Solo
patents and years without focal-inventor patents do not affect its
denominator.

### 2. Legacy-collaborator composition share

For each annual focal-inventor row, the denominator is the number of distinct
partners who co-invent at least one application with the focal inventor in
that year. The numerator is the number of those partners who are persistent
baseline collaborators.

The outcome is missing when the focal inventor has no co-invented application
in the year. This includes years with no focal-inventor patent and years with
only solo patents. Such cases are never coded as zero. Repeated applications
with the same partner do not increase this denominator.

### 3. Legacy-link composition share

For each annual focal-inventor row, the denominator is the number of distinct
application-partner link-instances. A partner appearing with the focal
inventor on two distinct applications contributes two link-instances. The
numerator counts link-instances involving persistent baseline collaborators.

The outcome is missing when the denominator is zero, including solo-only
years. It is not pooled across years, so high-patenting years do not receive
extra weight in the +1 through +5 average beyond their annual share.

## Secondary diagnostics

- Baseline-tie recurrence is the number of persistent baseline collaborators
  co-inventing with the focal inventor in a year divided by the baseline
  collaborator count. It is zero when no baseline tie recurs.
- Collaborator-set Jaccard is the intersection of baseline and current
  collaborator sets divided by their union. Because the baseline set is
  nonempty, a year with no current collaborator has value zero.
- Collaborator patenting anywhere is the share of baseline collaborators with
  any patent in the year, regardless of assignee.
- Tie-strength-weighted focal persistence weights each baseline collaborator
  by the number of anchor-period joint applications and otherwise follows
  primary outcome 1.
- Strongest-tie concentration is a predetermined descriptor: the largest
  anchor-period joint-application count divided by the sum across persistent
  baseline ties.

Recurrence and Jaccard are quantity-sensitive and cannot govern the thesis
network claim.

## Missingness and right-censoring

Zero, undefined composition, and right-censoring are distinct. Primary outcome
1 and the recurrence/Jaccard diagnostics have valid zero values on network
support. Composition outcomes 2 and 3 are missing when their annual
co-invention denominator is zero. A row is right-censored only when its
calendar year exceeds 2015. The frozen 1994--2010 cohorts are observable
through +5, so the primary post window has no calendar right-censoring.

## N0 feasibility gates

N0 releases N1 only if all conditions hold:

1. at least 3,000 distinct treated focal inventors have a persistent tie;
2. at least 150 treated deals contribute network support;
3. the effective number of treated deals is at least 20, using
   `1 / sum(deal_weight_share^2)`;
4. the largest treated deal holds no more than 10% of treated network weight;
5. construction is identical by arm and weights reconcile to the P5c roster;
6. primary outcome 1 is defined for every network-support row at -2 and -1;
7. each validation year has at least 1,000 treated rows and 100 treated deals
   with a defined composition denominator;
8. each validation-year composition sample has at least 20 effective treated
   deals.

These thresholds are frozen before the census. A failure produces a
feasibility-only result; it does not permit a weaker tie definition.

### Symmetric concentration amendment

The first census exposed that the initial list stated concentration thresholds
only for treated rows even though the implementation plan required treated
and control effective-deal counts. Before any validation outcome was
constructed, the gate was made strictly stronger: control network support and
each control validation-year composition sample must also have at least 20
effective deals, and no control deal may exceed 10% of the corresponding
weight. This amendment cannot convert a failed gate into a pass and does not
alter any tie, denominator, or outcome definition.

## N1 precision threshold

The smallest main-text-relevant effect is an absolute 0.05 on the share scale
for each primary outcome. N1 must use governing inference to show an MDE no
larger than 0.05. Support, realized standard errors, or validation estimates
cannot revise this threshold.

## Interpretation and inventory rule

N0 reports support and denominator coverage only. It emits no treatment-effect
estimate, confidence interval, or post-acquisition network result. Therefore
its package-level inventory gate must certify that there is no reportable
effect estimate to register. Any later N1 or N2 estimate must receive a unique
master-inventory result ID before that package can pass.
