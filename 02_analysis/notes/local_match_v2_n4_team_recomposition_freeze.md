# N4 exploratory team-recomposition freeze

Status: frozen before construction of any positive-event-time N4 outcome

Date: 2026-07-30

## Scope and interpretation

N4 is an exploratory, treated-only descriptive appendix for the certified
matched initially retained population. It does not estimate an ATT, identify
a mechanism, or reopen the N0 Path Q decision. The strict persistent-tie
definition and its failed coverage gate remain the governing design for any
causal collaboration-network claim.

N4 may use event times +1 through +5 only after this document is written and
hashed. Its purpose is to describe how the observed patent collaboration
teams of initially retained inventors change after completion.

## Population and weights

1. Start from treated rows in the certified P5b S3 production roster.
2. Require the certified primary `initially_retained` status.
3. Use the frozen S3 treated weight. Do not rematch, rebalance, trim, or select
   on a post-acquisition network outcome.
4. Report the number of supported focal inventors, nominal deals, effective
   deals, and the largest deal weight share.

## Patent and collaborator unit

1. A collaborator appearance is a distinct focal-inventor x partner-inventor
   x event-year tuple supported by at least one joint patent application.
2. Self-links are excluded. Duplicate patent-company links and duplicate
   inventor rows do not create additional appearances.
3. Event time is patent application year minus the acquisition completion
   year. The analysis window is +1 through +5. Event time zero is excluded.
4. A focal-partner-year is composition-defined only if at least one joint
   application has a resolvable company-group link. Rows with no resolvable
   group link are excluded from composition shares and reported separately.
5. A focal-inventor-year with patents but no co-inventor has no team-
   composition denominator. The package reports its incidence separately.
6. The primary composition estimand first calculates category shares within
   each focal-inventor-year, then averages those shares with the frozen S3
   weights. This prevents inventors with very large teams from dominating.
   Raw collaborator-appearance shares are secondary.

## Mutually exclusive collaborator categories

Each focal-partner-year is assigned once, in this order:

1. **Outside-group collaborator:** none of the focal-partner joint patent
   applications in that event-year has a company link to either certified
   focal group for the deal.
2. **Legacy target collaborator:** at least one joint application is
   focal-group linked, and the partner patented with the certified pre-deal
   target group at least once during event times -5 through -1.
3. **Legacy acquirer collaborator:** at least one joint application is
   focal-group linked; the partner has no legacy-target link; and the partner
   patented with the certified acquirer group at least once during -5
   through -1.
4. **New-to-both collaborator:** at least one joint application is
   focal-group linked, and the partner has neither a legacy-target nor a
   legacy-acquirer patent link during -5 through -1.

If a partner has both pre-deal target and acquirer links, target takes
priority. If a focal-partner-year contains both focal-linked and outside-only
joint patents, it remains an inside category and is separately flagged as
mixed; the mixed flag does not create a fifth category.

## Direct-tie persistence definitions

Both definitions use only the -5 through -3 anchor:

- **Strict persistent tie (governing N0 definition):** at least two distinct
  joint patent applications in at least two distinct anchor years.
- **Weak one-patent tie (exploratory):** at least one joint patent application
  in the anchor.

For each definition and horizon +1 through +5, the recurrence outcome equals
the share of a focal inventor's anchor partners who have reappeared on at
least one joint patent by that horizon. The package first calculates the
share within focal inventor and then averages over focal inventors with at
least one qualifying anchor partner using frozen S3 weights.

The weak definition must always be reported beside the strict definition and
labelled exploratory. It cannot replace the strict N0 definition in the
causal design.

## Frozen outputs

1. Annual focal-normalized collaborator-category shares.
2. Pooled +1 through +5 focal-normalized category shares.
3. Raw collaborator-appearance shares as a secondary accounting view.
4. Strict and weak anchor coverage.
5. Strict and weak cumulative tie recurrence through each post horizon.
6. Solo/no-team denominator audit and mixed-affiliation audit.
7. One appendix figure, one appendix table, certification, and artifact
   manifest.

## Guardrails

- No control comparison, ATT, p-value, confidence interval, or causal word
  may describe an N4 estimate.
- No category may be redefined after results are constructed.
- No outcome association with patent count, PQII, citations, or TechDrift is
  included in this package.
- Categories must be mutually exclusive and exhaustive on every
  composition-defined focal-partner-year; unresolved rows must reconcile to
  the separate audit denominator.
- All headline N4 values must be labelled exploratory and descriptive.
