# Local-match v2: split-preperiod identification freeze

Frozen before the first estimate from this design is computed.

## Purpose and estimand

This is the final patent-count identification exercise. It estimates the ATT
for established target inventors: inventors with focal-entity patent evidence
at event time `t=-7` or `t=-6`. It is a deliberately narrower estimand than
the full target-inventor-cohort ATT.

The design separates sample construction, matching, and validation in time:

- recruitment/establishment: `t=-7,-6`;
- matching and balancing: `t=-5,-4`;
- untouched validation leads: `t=-3,-2,-1`;
- treatment and post period: `t=0,...,+5`.

No support, distance, matching, weighting, cohort-feasibility, or tuning
decision may read patent outcomes at `t=-3` or later.

## Population and donor eligibility

- Cohorts: 1995--2010. Cohort 1994 is unavailable because the patent data
  begin in 1988 and do not supply both recruitment years.
- Treated units: the frozen P2 primary treated roster, restricted to focal
  group or deal-specific target-company patent evidence at `t=-7` or `t=-6`.
- Candidate control units: inventors with patent evidence at exactly one
  control group over `t=-7,-6`.
- Donor universe: clean U2. A donor group must have no target event on or
  before `g+5` and no acquirer event in `[g-5,g+5]`.
- Controls may be reused across treated deals, but occur only once within a
  deal stack.

## Prospective local support

All inputs below are dated no later than `g-4`.

### Firm support

For each target deal, control firms must have positive IPC4 portfolio overlap
with the target over `t=-7,...,-4`. Among those firms, retain the five nearest
on the Euclidean distance formed from:

- `log(1 + patents)` at `t=-5` and `t=-4`;
- `log(1 + active inventors)` at `t=-5` and `t=-4`;
- one minus IPC4 cosine similarity over `t=-7,...,-4`.

Scalar components are standardized within cohort over treated and eligible
control firms. Cosine distance is left on its natural scale. There is no
outcome-selected absolute caliper.

### Inventor support

Within the selected firms, candidate pairs must have positive IPC4 portfolio
overlap over `t=-7,...,-4`. Distance uses:

- `log(1 + patent count)` at `t=-5` and `t=-4`;
- career age measured at `t=-4`;
- one minus IPC4 cosine similarity over `t=-7,...,-4`.

Scalar components are standardized within cohort. Each treated inventor keeps
the three nearest distinct control inventors, with a deterministic repair that
selects the nearest donor from a second firm when the unrestricted nearest
three all come from one firm. A treated inventor is supported only with three
controls from at least two firms. No distance caliper is tuned after outcomes.

## Cohort-level entropy balance

Within each cohort, controls receive deal-normalized base weights and are
entropy-balanced to the retained treated inventors on first moments of:

- inventor patent count at `t=-5` and `t=-4`;
- inventor active-patenting indicators at `t=-5` and `t=-4`;
- career age at `t=-4`;
- focal-firm patent count at `t=-5` and `t=-4`;
- focal-firm active-inventor count at `t=-5` and `t=-4`.

The treated weight is one. Control mass is normalized to treated mass within
cohort. Exact entropy balance is attempted once. A cohort without a finite
exact solution is reported as infeasible and omitted; it is not rescued after
examining outcomes.

## Estimation and inference

- Outcome: annual inventor patent count.
- Reference period: `t=-4`.
- Joint event study: untouched leads `t=-3,-2,-1` and effects
  `t=0,...,+5`.
- Main post contrast: equal-weight average of `t=+1,...,+5`.
- Covariance: one coherent deal-clustered covariance matrix for the complete
  joint coefficient vector. Two-way deal/inventor clustered estimates are a
  diagnostic if computationally available.
- Conventional confidence intervals and the joint Wald test of the three
  untouched leads are reported.
- Formal Rambachan--Roth sensitivity uses the same coefficient vector and
  covariance matrix, relative-magnitude restrictions, and the equal-weight
  `t=+1,...,+5` post contrast. Report the first evaluated `Mbar` for which the
  robust upper confidence limit reaches zero, plus the full sensitivity grid.

## Reporting rule

The result is reported whether favorable, null, or infeasible. It does not
replace the full-cohort P5c ATT. It is an identification diagnostic for a
narrower established-inventor population.
