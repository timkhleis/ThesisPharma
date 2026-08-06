# Local Match v2: 1993 numerical-reproduction addendum

## Status and timing

This addendum was recorded on 2026-08-03 after the first independent P5
rebuild and before any outcome table or treatment-effect object was read. It
supplements, but does not alter, the matching design recorded in
`local_match_v2_1993_cohort_amendment.md`.

## Finding

Thirty of the 32 materialized 1994--2010 cohort-scheme weight cells reproduced
exactly after provenance hashes were excluded. The two non-exact cells are the
primary and equal-deal weights for cohort 2008.

The discrepancy is attributable to floating-point accumulation order, not to
a treatment, sample, or design change. The 2008 sparse IPC vector values are
identical to the frozen run. Recomputed vector norms differ by at most
2.22e-16, which changes 25 nearest-neighbour edge keys at the profile boundary
and five final control-roster keys out of approximately 28,650. The treated
roster, number of supported treated inventors, supported deals, feasibility
classifications, and frozen balance gates are unchanged.

## Numerical-equivalence gate

The incumbent-cohort reproduction gate is therefore supplemented, still
before outcome access, as follows:

1. all exactly reproducible cohort-scheme cells must remain exact;
2. at most one incumbent cohort may require numerical-equivalence review;
3. that cohort must have an identical treated roster and treated support;
4. the symmetric control-roster difference must be below 0.1 percent; and
5. the original balance, retention, concentration, and feasibility gates must
   continue to pass without fallback or retuning.

This addendum does not authorize any change to matching covariates, calipers,
donor universes, balancing targets, solver hierarchy, outcomes, or inference.
