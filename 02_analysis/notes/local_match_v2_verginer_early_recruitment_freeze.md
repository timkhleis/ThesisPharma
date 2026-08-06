# Verginer-style early-recruitment diagnostic freeze

Frozen before inspecting any outcome under this diagnostic.

## Purpose

This diagnostic tests whether the P5c patent-count result is created by the
main cohort rule, which admits inventors observed at any point in the five
years immediately before the deal. It defines an earlier, fixed cohort and
then observes that cohort through the same five pre-deal matching years and
the same P6 outcome window.

It is a separate established-inventor estimand. It does not replace or modify
the certified P5c full-cohort design.

## Cohort and recruitment rule

- Primary diagnostic cohorts: 1995--2010.
- Cohort 1994 is excluded because the patent layer starts in 1988, so event
  year -7 is unavailable for a 1994 deal.
- An inventor is early recruited if there is at least one patent carrying
  focal-entity evidence in event year -7 or -6.
- For controls, focal evidence is a patent assigned to the placebo focal
  control group.
- For treated inventors, focal evidence is a patent assigned to the pre-deal
  target group or to a strict target-company path already certified in P2/P6.
- Acquirer-group evidence is not a pre-deal recruitment route.
- Recruitment uses no information from event years -5 through +5.

## Support and weighting

- Begin from the certified P5a/P5c admissible support roster. The diagnostic
  never expands donor admissibility.
- After early recruitment, retain a deal only if it has at least one recruited
  treated inventor, at least three distinct recruited control inventors, and
  at least two recruited control firms.
- Recompute the primary treated-inventor ATT base weights within each retained
  deal: treated rows receive weight 1 and control rows jointly receive the
  treated deal mass.
- Rebalance, by cohort, the frozen P5c count-active set:
  annual patent count and active-patenting indicators for event years -5
  through -1; career age; focal-group exclusivity; firm five-year patent
  stock; firm inventor count; and firm patent trajectory.
- Use the existing P5c feasibility hierarchy unchanged. No variable may be
  dropped after outcomes are inspected.

## Predeclared diagnostics

Report treated-inventor retention relative to P5c, retained deals, control
inventors and firms, realized balance, reuse-adjusted ESS, and concentration.
Technical passage requires every 1995--2010 cohort to be feasible and maximum
absolute standardized difference no larger than 0.10.

## Outcome analysis

- Primary outcome: annual patent applications.
- Event window: -5 through +5; reference year: -1.
- Main post summary: average annual ATT over +1 through +5; cumulative effect
  is five times that average.
- Report the full dynamic path, the joint -5 through -2 pre-period test,
  deal-level Webb wild-bootstrap-t inference, and prominent two-way
  deal/inventor clustered inference.
- Report weighted treated and control mean paths to diagnose lifecycle shape.
- Compare with the frozen P5c result, but do not select either design based on
  which estimate is larger or more significant.

## Interpretation

Agreement with P5c would show that the negative result is not specific to
inventors recruited during the immediate five-year pre-deal window. It would
substantially weaken a recruitment/lifecycle explanation, but would not
logically prove parallel counterfactual trends or eliminate all mean
reversion. Attenuation would indicate that cohort construction contributes to
the P5c magnitude. Failure of support or precision is inconclusive rather than
evidence of no effect.
