# Local Match v2: patenting-exit decomposition freeze

This additive P8 package decomposes the certified patent-count ATT into
patenting survival, activity conditional on survival, and patents per active
year. It does not alter any P0--P7 input or result.

The primary sample is the exact headline sample: cohorts 1994--2010 and event
times +1 through +5. Cohorts 1994--2008, cohorts 1994--2005, the common
1994--2010 window +1 through +3, and a fixed three-year look-ahead are
censoring sensitivities.

Patenting exit means that the inventor's last patent anywhere in the observed
database predates the calendar year. It is not Cassi--Ornaghi firm leaving.
The patent clock is capped at the frozen analysis boundary of 2015; source
records after that boundary are counted in the endpoint audit and excluded.

The reference survival factor is anchored at one. Raw survival at event time
-1 depends on post-acquisition patenting and is diagnostic only. Thus the
reference activity factor is unconditional, while post-treatment activity is
conditional on patenting survival. All component estimates are accounting
contributions, not causal mediators.

The full-cohort decomposition must reproduce the certified 1994--2010
patent-count ATT to numerical tolerance. The broad initially retained sample
is reported only as a selected-group accounting reconciliation. A separately
weighted event-time +1 landmark must govern any claim about cessation after
initial retention.
