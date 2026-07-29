# Local Match v2 — Package 1D mean-reversion diagnostic results

## Certification

Package 1D passed 17 of 17 terminal checks. The certified bundle hash is:

`33164a217f20d31bf6f2c8eb4b00aae4adeec6eb0ab733039f3adecb72440ce1`

The `loyo_m1` extension retained the frozen 500,906-row roster. All 17 cohort
cells were feasible and passed the existing balance, weight, mass, artifact,
and handoff checks.

## Main conclusion

The evidence does not support the strongest version of the
acquisition-at-a-temporary-peak explanation. The unmatched treated and control
groups share a broad rise before their assigned event and a decline afterward,
and the unmatched full-cohort post DiD is effectively zero. This confirms that
the raw post decline is largely an inventor-cohort life-cycle pattern.

The treated group nevertheless peaks earlier than the unmatched controls, and
held-out event times -3 and -2 remain imperfectly aligned. That concern matters
for identification, but it does not explain away the matched post estimate.
When the post effect is measured relative to genuinely held-out pre-surge
baselines, the full-sample estimate remains between -0.046 and -0.049 patents
per inventor-year.

## Unmatched and matched paths

In the unmatched eligible sample:

- treated mean patenting rises from 0.402 at -5 to 0.488 at -3 and then falls
  to 0.418 at -1;
- control mean patenting rises from 0.348 at -5 to 0.454 at -1;
- the joint -5 through -2 pre-trend test rejects equality
  (`p = 0.000073`);
- the average post DiD relative to -1 is -0.0028
  (`95% CI [-0.0336, 0.0280]`, `p = 0.858`).

The P5c count-active design gives treated and control groups the same complete
five-year mean path to numerical precision. After the event, their paths
separate.

This comparison shows that matching is doing substantive identifying work. It
does not by itself show that matching creates a spurious result; the
leave-one-year-out estimates below test that concern.

## Missing event-time -1 holdout

Under `loyo_m1`, event time -1 relative to event time -4 is:

- full sample: 0.0306, `95% CI [-0.0193, 0.0806]`;
- 1994–2008 sample: 0.0287, `95% CI [-0.0184, 0.0758]`.

The point estimates are positive but not statistically distinguishable from
zero. Event time -1 therefore does not add another significant pre-period
failure.

Using the held-out -1 period itself as the reference produces an average post
estimate of -0.0795. Re-referencing the same `loyo_m1` design to -4 reduces it
to -0.0489. This confirms that a terminal-pre-period reference can materially
inflate the estimated decline when that terminal period is left unmatched.

## Properly re-referenced post effects

All estimates below average event times +1 through +5. The intervals and
`p`-values are from the frozen 9,999-draw deal-level wild bootstrap.

| Design | Sample | Reference | ATT | 95% CI | p |
|---|---|---:|---:|---:|---:|
| `loyo_m4` | 1994–2010 | -4 | -0.0493 | [-0.0857, -0.0118] | 0.009 |
| `loyo_m4` | 1994–2008 | -4 | -0.0326 | [-0.0669, 0.0037] | 0.078 |
| `loyo_m5` | 1994–2010 | -5 | -0.0462 | [-0.0835, -0.0056] | 0.027 |
| `loyo_m5` | 1994–2008 | -5 | -0.0444 | [-0.0866, 0.0029] | 0.063 |
| `loyo_m1` | 1994–2010 | -4 | -0.0489 | [-0.0758, -0.0202] | 0.002 |
| `loyo_m1` | 1994–2008 | -4 | -0.0477 | [-0.0745, -0.0187] | 0.003 |

The two-way deal/inventor intervals exclude zero in all six cells. The two
buffered wild-bootstrap intervals for `loyo_m4` and `loyo_m5` narrowly include
zero, so the reporting hierarchy should preserve that distinction.

## Who generates the held-out deviations?

For event time -3, the full-sample held-out estimate is 0.0447:

- established focal inventors contribute 0.0335;
- inventors first observed patenting in -3 contribute 0.0179;
- later focal entrants contribute -0.0042;
- focal recruits in -3 contribute -0.0025.

For event time -2, the full-sample held-out estimate is 0.0422:

- established focal inventors contribute 0.0301;
- inventors first observed patenting in -2 contribute 0.0144;
- later focal entrants contribute 0.0021;
- focal recruits in -2 contribute -0.0044.

Established inventors therefore account for approximately 75% of the -3
deviation and 71% of the -2 deviation. Career entry contributes approximately
40% and 34%, respectively, before offsetting categories. Direct focal
recruitment is uncommon and contributes negatively. The pre-period concern is
not primarily a mechanical inflow of newly recruited focal inventors.

## Deal concentration and target-deal peaks

The held-out deviations are not attributable to one mega-deal:

- at -3, the largest deal accounts for 9.4% of absolute contributions and the
  ten largest account for 36.1%;
- at -2, the largest accounts for 5.4% and the ten largest for 31.6%.

Across the 341 target deals, the pre-period patent peak occurs at:

- -5 for 20.5% of deals;
- -4 for 24.0%;
- -3 for 20.2%;
- -2 for 17.6%;
- -1 for 17.6%.

Only 50.7% of deals have a positive middle-period surge relative to the outer
pre-period years. The median surge is 0.0074 patents per inventor, while the
inventor-weighted mean is 0.0360. The aggregate hump is therefore real but not
an industry-wide rule that every target is acquired at its productivity peak.

## Design decision

Package 1D does not justify replacing P5c. It shows:

1. raw outcome levels contain a strong shared life-cycle decline;
2. the unmatched control group has an unsuitable pre-event path;
3. terminal-period normalization can exaggerate the matched effect;
4. the negative post effect remains near -0.05 under held-out -4 and -5
   baselines;
5. the localized -3/-2 discrepancy remains a parallel-trends limitation.

The next defensible step is the distinct Verginer-style design that recruits a
fixed inventor cohort at -7/-6 and matches its -5 through -1 trajectory. It
should be presented as a co-equal established-inventor estimand, not as a
repair selected because of a preferred post estimate. Package 1D stops before
that implementation.
