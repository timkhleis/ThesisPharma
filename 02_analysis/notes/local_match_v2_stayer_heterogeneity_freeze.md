# Local Match v2: initially retained inventor heterogeneity freeze

This package estimates heterogeneity only after importing the separately
constructed and entropy-balanced P5b initially-retained roster. It never
restricts or reuses the full-cohort P5c weights.

The population is an initially retained inventor: the first observed
post-deal patent in event time 0 through +5 contains focal-entity evidence and
no outside-group evidence. Event time 0 is used for classification but not as
a post-treatment outcome. Later movement does not change baseline status.

The primary specification is the certified P5b
`primary_count_active_scale` / `primary_resolved_t1` design. Outcomes are
patent count and the probability of patenting. For each outcome, the dependent
variable is the mean over event times +1 through +5 minus event time -1.
The censoring companion restricts cohorts to 1994--2008.

Four predetermined moderators form the primary eight-test family:

1. five-year pre-deal patent productivity;
2. career age at event time -1;
3. persistent pre-deal team collaboration;
4. inventor--acquirer IPC4 technological fit.

Persistent collaboration requires at least two joint pre-deal patents in at
least two distinct pre-deal years. TechFit uses all observable inventor and
acquirer histories strictly before treatment; a fixed five-year version is an
appendix robustness check. Focal-group tenure, measured at event time -1, is
an appendix-only alternative to career age and is excluded from the primary
multiplicity family.

Inference reports both deal-level Webb wild-bootstrap and two-way
deal/inventor clustered uncertainty, using the more conservative p-value and
interval. Main-text heterogeneity results use these unadjusted p-values. Holm
adjustment across the eight primary contrasts is retained as a labelled
appendix multiplicity sensitivity. Precision and Type-M diagnostics are
descriptive and never determine whether an estimate is reported.

The package also reports the aggregate initially-retained ATT and an exact
extensive/intensive accounting identity. The estimand remains conditional on
post-treatment initial patent retention and is not an unconditional
employment-retention effect.
