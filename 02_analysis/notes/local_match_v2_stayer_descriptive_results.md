# Package D1 retained-status descriptive results

Status: implemented and certified

## Population and selection

The certified primary partition contains 28,483 inventors: 3,090 initially retained, 1,158 leavers, and 24,235 with no observed post-deal patent.

Median career age at t=-1 is 3.0 years for initially retained, 3.0 for leavers, and 2.0 for the no-post-patent group.
Median five-year pre-deal patent stock is 2.0, 2.0, and 1.0, respectively.
Initially retained inventors and leavers have effectively identical career age (SMD -0.008), while initially retained inventors have a modestly higher pre-deal patent stock (SMD 0.180). This is modest positive productivity selection into initial retention, not a large seniority difference.
The frozen management-transition diagnostic is **not_supported_by_frozen_effect_size_rule**. The no-post-patent career-age SMD is -0.372 versus initially retained inventors and -0.394 versus leavers.

## Patent-location paths

The endpoint-based persistent-inside share is 32.7% through +3 and 20.9% through +5.
The stricter uninterrupted annual-focal shares are 10.0% and 3.1%.
At +5, 19.1% are focal-only, 2.3% have both focal and outside evidence, 3.8% have outside/no-focal evidence, 17.5% have no patent that year but patent later, and 53.5% have reached the end of observed patenting; 3.9% are right-censored.
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
