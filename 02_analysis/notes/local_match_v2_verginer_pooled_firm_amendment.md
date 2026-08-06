# Pre-outcome amendment: pooled firm balance

No post-treatment outcome has been inspected under the early-recruitment
diagnostic.

The inventor-level Verginer solve passes all 16 cohorts and exactly balances
the complete annual count-plus-active trajectory. Its unconstrained
cohort-specific firm diagnostics are uneven, with a maximum absolute
firm-variable standardized difference of 1.14. This is expected in cohorts
containing only two or four retained treated deals, but it is too large to
ignore.

The final weighting step is therefore aligned to the pooled inventor ATT:

- preserve treated/control weight mass separately within each cohort;
- preserve inventor-variable balance separately within every cohort by
  including cohort-by-inventor-variable constraints;
- balance the three firm variables globally under the treated-inventor
  cohort shares used by the pooled ATT;
- use the certified inventor-only weights as control priors;
- report cohort-specific firm differences as heterogeneity diagnostics, but
  assess firm balance for the pooled estimand at the global level.

This specification does not claim that a two-deal cohort can independently
identify a firm-balanced cohort ATT. It identifies the pooled established-
inventor ATT while retaining exact within-cohort inventor trajectories and
global firm comparability. No constraint is chosen using outcomes.
