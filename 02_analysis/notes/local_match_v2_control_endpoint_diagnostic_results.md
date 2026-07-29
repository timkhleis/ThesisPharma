# Control-endpoint sample diagnostic

The endpoint restriction does not explain why the initially retained estimate
is more negative than the full-cohort estimate. Restricting controls to firms
that still patent through event time +5 moves the full-cohort patent-count ATT
from -0.0534 to -0.0420 patents per inventor-year. The initially retained
estimate remains -0.1072. The diagnostic therefore widens, rather than closes,
the retained/full-cohort point-estimate gap.

This exercise is a sample-definition diagnostic, not a newly balanced design.
It removes 91,546 of 473,828 control units and reuses the frozen P5c entropy
weights on the remaining controls; it does not re-solve those weights. The
maximum absolute residual standardized mean difference across patent count and
active patenting at event times -5 through -1 is 0.0430. The negative-period
differences in this restricted sample are residual imbalances after filtering,
not genuine leave-one-year-out (LOYO) gaps. No restricted-sample LOYO has been
run, and the joint negative-period test (`p = 0.688`) must not be used as a
substitute for one.

The residual patent-count gaps at -5 and -4 are positive: treated inventors
patent more than the remaining weighted controls. Mean reversion from those
gaps would tend to make the post estimate more negative. The estimate instead
moves toward zero. This directional fact makes it less plausible that the
attenuation is generated solely by the observed loss of balance, but it does
not restore a causal interpretation to the diagnostic.

## Dynamic pattern

Both the frozen P5c path and the endpoint diagnostic attenuate monotonically in
absolute value from +1 through +5:

| Event time | Frozen P5c | Endpoint diagnostic |
|---:|---:|---:|
| +1 | -0.0644 | -0.0564 |
| +2 | -0.0588 | -0.0486 |
| +3 | -0.0570 | -0.0449 |
| +4 | -0.0459 | -0.0324 |
| +5 | -0.0410 | -0.0276 |

This decay is consistent with temporary integration disruption. It is not a
mechanism test and does not rule out persistent portfolio rationalization. The
endpoint-diagnostic interval includes zero at +4 and +5; the frozen P5c
interval remains below zero at +5.

Event time zero is the deal-completion year and is negative in both paths
(-0.0377 in frozen P5c and -0.0288 in the endpoint diagnostic). The paper will
include this coefficient as a merger effect. The +1 to +5 average remains a
separate full-calendar-year flow estimand because exposure during t=0 begins
partway through the year. Adding the frozen t=0 coefficient to the five
subsequent annual effects gives a completion-through-+5 cumulative point
effect of -0.3047 patents per inventor (deal-wild 95% interval
[-0.5197, -0.0916], p=0.0086). The corresponding average annual contrast
across t=0 through +5 is -0.0508 [-0.0866, -0.0153].

Deal timing is available only by year. The data therefore cannot separate
post-completion exposure within t=0 from changes earlier in the same calendar
year, nor can they annualize the partially exposed completion-year effect.
This resolution limit does not change the decision to include t=0 in the
event-study narrative and certified cumulative effect.

Authoritative machine-readable evidence is in
`C1_CONTROL_ENDPOINT_DIAGNOSTIC/control_endpoint_balance_audit.csv`,
`control_endpoint_dynamic_comparison.csv`, and
`control_endpoint_certification.csv`.
