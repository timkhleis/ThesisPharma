# Package D1 retained-status descriptive freeze

Status: frozen before Package D1 descriptive outputs were computed

Date: 2026-07-30

## Population and status

The population is the certified primary `t1_t5_primary` treated partition.
The three reported statuses are `initially_retained`, `leaver`, and
`no_post_patent`. Event time zero never determines status. Initial retention
requires the first observed patent in event time +1 through +5 to carry focal
target/acquirer-group or strict target-company evidence.

## Predetermined descriptors

Career age is calendar year `cohort - 1` minus the inventor's first observed
patent year. Five-year patent stock is the sum of annual patent counts over
event times -5 through -1. No post-acquisition information enters either
descriptor.

Distribution tables report the mean, standard deviation, p10, p25, median,
p75, p90, and N. Pairwise comparisons report standardized mean differences
and Kolmogorov-Smirnov distribution tests. Effect sizes govern interpretation.
The management-transition interpretation is labelled plausible only if the
no-post-patent group's career age exceeds both other groups by at least 0.20
pooled standard deviations.

## Annual patent-location states

For every initially retained inventor and event time +1 through +5, exactly
one state is assigned:

1. focal group only;
2. outside group only;
3. both focal and outside;
4. no patent in the year but a later patent is observed;
5. end of observed patenting;
6. right-censored/not observable.

Focal evidence means an assignee group is the deal's target or acquirer group,
or the assignee is a strict target company. "Outside group only" requires
patenting without focal evidence. Any patent-year lacking resolvable
company/group evidence is flagged in the audit and must never be described as
confirmed outside employment.

Persistent-inside status through horizon h requires focal patent evidence at
h and no outside-only patent year from the first post-deal patent through h.
No-patent gaps are allowed. An uninterrupted annual-focal companion requires
focal evidence in every year +1 through h.

## Endpoint and timing rules

Group existence through +5, defined by a last observed group patent year of at
least `cohort + 5`, is audited symmetrically for treated and weighted control
rows. Exact-year +5 activity is reported separately. Event time +6 is
descriptive only, restricted to cohorts observable by 2015, and never changes
inclusion or weights.

Event time zero is the partially exposed merger-completion calendar year. It
is reported separately and included in the completion-through-+5 cumulative
effect. The data contain years, not months, so pre- and post-completion months
within event time zero cannot be separated.

All location language refers to patent affiliation, never employment.
