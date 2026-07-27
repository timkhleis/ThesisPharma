# Local Match v2 — Package 1D mean-reversion diagnostic freeze

## Status

Prospectively frozen after Package 1 and before any Package 1D estimate was
computed.

Package 1D is diagnostic. It does not replace, repair, or select the frozen
P5c count-active design. No post-treatment estimate may determine whether a
matching design is retained.

## Question

Does the held-out imbalance at event times -3 and -2 reflect acquisition after
a temporary target-inventor productivity peak, a control-path trough, inventor
entry, or concentration in a small number of deals?

## Frozen tasks

1. Solve the missing `loyo_m1` arm by balancing the same P5c variables except
   patent count and active patenting at event time -1.
2. Evaluate its held-out event time -1 relative to event time -4. Event time
   -1 is a diagnostic outcome, not an anticipation test.
3. Re-estimate the average patent-count effect at event times +1 through +5:
   - under `loyo_m4`, using event time -4 as the reference;
   - under `loyo_m5`, using event time -5 as the reference;
   - under `loyo_m1`, using event time -4 as the reference.
4. Report two-way deal/inventor inference and the frozen deal-level wild
   bootstrap for each re-referenced post estimate.
5. Compare the existing unmatched raw paths with the frozen P5c matched paths.
6. Decompose the held-out -3 and -2 contrasts into mutually exclusive groups:
   career entry in the held-out year, focal-group entry in that year,
   established focal inventors, and later focal entry.
7. Report deal-level contribution concentration and the distribution of
   target-deal inventor-path peaks.

## Interpretation

- Shared raw rises and declines are not treatment effects.
- A negative re-referenced ATT is evidence only under the corresponding
  leave-one-year-out counterfactual.
- A concentrated held-out contrast is a deal-influence finding, not a failed
  sample-size rule.
- Earlier `t=-7/-6` recruitment is not implemented in Package 1D. It remains
  the next design decision after this diagnostic is reviewed.

## Stop rule

Package 1D ends with a results and certification note. It must not launch the
Verginer-style roster, change P5c weights, or continue to later outcome
packages.
