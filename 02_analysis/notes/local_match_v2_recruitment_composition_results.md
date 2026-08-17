# Recruitment-composition audit: results

The symmetric `t=-3` entry-share gap is 0.0178 under P5a (95% wild-bootstrap CI 0.0042 to 0.0315, p=0.009) and 0.0038 under `loyo_m3` (CI -0.0096 to 0.0170, p=0.564).

Under P5a, the original `t=-3` coefficient is 0.0506. Subtracting one mechanical patent in the inventor's focal-group entry year reduces it to 0.0290, a change of 0.0216. The control-path shift-share calculation attributes 0.0217 patents to entry composition.

Under `loyo_m3`, the coefficient moves from 0.0447 to 0.0369 after entry-year subtraction, a change of 0.0078. This is below the frozen 0.010 materiality threshold, and the adjusted coefficient remains positive.

The joint entry-plus-original-moment calibration passes 13/17 `loyo_m3` cohorts and 13/17 `count_active` cohorts. Because the frozen design forbids dropping the failing cohorts or relaxing support, B1 and B3 are infeasible as full-sample specifications and their exploratory entry-only tilts are not promoted.

Interpretation: recruitment timing materially explains part of the raw P5a pre-period spike, but it does not fully explain the held-out pretrend violation. The main post-acquisition decline also does not disappear under deterministic entry-year subtraction; because `t=-1` is the reference period, its numerical value can move even though post-period patent counts themselves are unchanged.
