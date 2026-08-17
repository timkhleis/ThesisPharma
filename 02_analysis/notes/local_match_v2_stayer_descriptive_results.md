# Package D1 retained-status descriptive results

Status: implemented and certified

## Population and selection

The certified primary partition contains 28,483 inventors: 3,090 initially retained, 1,158 leavers, and 24,235 with no observed post-deal patent.

Median career age at t=-1 is 3.0 years for initially retained, 3.0 for leavers, and 2.0 for the no-post-patent group.
Median five-year pre-deal patent stock is 2.0, 2.0, and 1.0, respectively.
Initially retained inventors and leavers have effectively identical career age (SMD -0.008), while initially retained inventors have a modestly higher pre-deal patent stock (SMD 0.180). This raw retained-leaver difference documents status sorting. It does not sign bias in the selected-group ATT; the P5b design separately balances pre-deal patent counts between treated and control retained rows.
The management-transition interpretation is not supported under the frozen effect-size rule (diagnostic: **not_supported_by_frozen_effect_size_rule**). The no-post-patent career-age SMD is -0.372 versus initially retained inventors and -0.394 versus leavers.

## Patent-location paths

The endpoint-based persistent-inside share is 32.7% through +3 and 20.9% through +5.
At +3, this is 36.6% among inventors whose first post-deal patent is observed by +3, compared with 32.7% of all initially retained inventors.
The stricter uninterrupted annual-focal shares are 10.0% and 3.1%.
At +5, 19.1% are focal-only, 2.3% have both focal and outside evidence, 3.8% have outside/no-focal evidence, 17.5% have no patent that year but patent later, and 53.5% have reached the end of observed patenting; 3.9% are right-censored.
Focal-only patent affiliation falls from 51.3% at +1 to 19.1% at +5. Initial retention therefore records a first post-deal patent-location state, not durable organizational attachment.
In the separately balanced retained design, the endpoint-based persistence shares through +3 are 31.4% for treated rows and 36.4% for matched controls; through +5 they are 20.2% and 24.2%. The corresponding uninterrupted annual-focal shares through +5 are 2.6% and 4.7%.
This treated-control comparison is descriptive and partly mechanical: matched controls are drawn from groups required to remain patent-active through +5, while treated focal groups have no symmetric existence requirement. Higher control persistence therefore cannot be read as a causal acquisition effect.
1 inventor-year(s), or 0.006% of the annual grid, contain patents without resolvable company/group evidence. These are flagged and never interpreted as confirmed outside employment.

## Endpoint activity

At +5, the weighted focal-group existence-through-horizon share is 95.7% for treated retained-design rows and 100.0% for controls. Exact-year patent activity is 95.5% for treated retained-design rows and 97.3% for controls.
Among cohorts observable at +6, the corresponding descriptive existence shares are 92.0% and 93.2%; exact-year activity shares are 92.0% and 92.1%. +6 never enters cohort inclusion or weighting.

## Completion-year effect

Event time zero is the merger-completion calendar year: ATT = -0.0377, 95% CI [-0.0650, -0.0104].
The completion-through-+5 average annual ATT is -0.0508, 95% CI [-0.0866, -0.0153]; the cumulative effect is -0.3047, 95% CI [-0.5197, -0.0916].
Timing is observed only by year, so t=0 cannot be split into
pre- and post-completion months.

All path results describe patent affiliation, not employment, and are
descriptive rather than a new landmark causal estimand.
