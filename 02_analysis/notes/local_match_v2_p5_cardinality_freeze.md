# Local Match v2 — P5.4 cardinality-matching freeze

**Frozen:** 2026-07-26, before opening any outcome or treatment-effect object.

The cardinality arm targets treated inventors who remain unsupported under
the frozen P5.3 entropy-balanced design. It is a co-equal, separately
reported identification design. Its rows are never appended to the P5.3
weights.

## Candidate support

- Donor universe: U2 clean.
- Stage-1 firm caliper: 2.0.
- Stage-2 inventor caliper: 1.5.
- Technology resolution: IPC4.
- Inventor distance: log five-year patent count, patent trajectory, career
  age, and IPC4 cosine distance.
- Candidate roster: at most the 50 nearest admissible controls per treated
  inventor, retaining candidates from at least two firms where available.
- Treated roster: inventors unsupported by the realized P5.3 primary support
  cover.

The cardinality arm does not relax U2 timing eligibility, the Stage-1 firm
caliper, or the Stage-2 distance caliper.

## Optimization

Within each cohort, maximize the number of matched treated inventors subject
to:

1. exactly two control inventors per matched treated inventor;
2. the two controls come from different control firms;
3. a control inventor is used for at most five treated inventors across the
   cohort;
4. absolute standardized mean differences do not exceed 0.10 for:
   - log five-year inventor patent count;
   - inventor patent trajectory;
   - inventor career age;
   - focal-group exclusivity;
   - firm log five-year patent stock;
   - firm log five-year inventor count; and
   - firm patent trajectory.

After maximizing cardinality, use total matching distance only as a numerical
tie-breaker. Do not trade away one matched treated inventor for a shorter
aggregate distance.

If the frozen model is infeasible or matches no treated inventor in a cohort,
report that cohort as unrecovered. Do not raise the balance tolerance, reuse
cap, Stage-1 caliper, Stage-2 caliper, or candidate count automatically.

## Weights and estimand

Each matched treated inventor receives weight one. Each of its two selected
control edges receives weight one-half. Reused control inventors are
aggregated for ESS and dependence diagnostics.

The resulting estimate is
`ATT_cardinality_recovered`, the ATT for previously unsupported treated
inventors recovered by the cardinality design. Report it separately from
`ATT_entropy_supported`.

Any population decomposition must first show:

\[
 p_S ATT_{\mathrm{entropy\ supported}},
 \qquad
 p_R ATT_{\mathrm{cardinality\ recovered}},
 \qquad
 p_N ATT_{\mathrm{still\ unsupported}},
\]

including the three population shares and balance diagnostics. Combining the
components into one number requires a further estimand review and does not
occur automatically.

