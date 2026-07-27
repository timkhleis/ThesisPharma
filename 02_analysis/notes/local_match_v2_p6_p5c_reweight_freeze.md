# P6 freeze for P5c annual-trajectory weights

Frozen before opening any P5c or held-out-year ATT: 2026-07-27.

## Scope

The certified P6 outcome panel has unchanged membership, outcomes, event
window, censoring flags, and status fields. Three additive copies replace only
the weight attached to each unchanged `roster_row_id`:

1. `count_active`: balances patent count and active patenting at all five
   pre-treatment years;
2. `loyo_m3`: balances both measures at `t=-5,-4,-2,-1` and holds out `t=-3`;
3. `loyo_m4`: balances both measures at `t=-5,-3,-2,-1` and holds out `t=-4`.

All three use the same 500,906-row P5 support roster. P5a and the original P6
panel remain unchanged.

## Estimation contract

Reuse the certified P6 estimator without specification changes:

- samples: 1994--2010 and censoring-clean 1994--2008;
- event window: `t=-5,...,+5`, reference `t=-1`;
- primary outcomes: patent count, active patenting, and TechDrift;
- secondary outcomes: linkage-scaled PQII and five-year forward citations;
- headline: average annual ATT over `t=+1,...,+5`;
- terminal `t=+5` remains reported for comparability;
- 9,999-draw deal wild bootstrap is headline;
- if package confidence-set inversion returns no interval, use the equal-tailed
  percentile-t interval from the same 9,999 wild-bootstrap t statistics and
  the original deal-clustered standard error, and label that fallback;
- two-way deal/inventor and deal-only cluster intervals are companions;
- the wider interval governs when inference differs materially.

The full-cohort layer is estimated. Stayer ATT remains unauthorized until the
separately balanced P5b design exists.

## Interpretation fixed before estimation

- `count_active` is the main corrective P5c result.
- Its five patent-count and active-patenting leads are construction
  diagnostics, not falsification tests.
- `loyo_m3` is the primary matching placebo. Only its `t=-3` coefficient is
  held out of annual outcome balancing.
- `loyo_m4` is the companion matching placebo. Only its `t=-4` coefficient is
  held out of annual outcome balancing.
- Both placebo results are reported regardless of sign or significance.
- A placebo is reassuring when its omitted-year 95% interval includes zero
  and its absolute point estimate is below 0.05 patents per inventor-year.
- Post-treatment P5a, full P5c, `loyo_m3`, and `loyo_m4` estimates are all
  compared. No design is selected using those estimates.

## Frozen input hashes

- Base P6 construction manifest (`P6_V3_PRODUCTION_FREEZE_1ED`):
  `f5500e513565964f8b0fc1c3cd0a557c9804f8f079402fcc13f4b4d6b0dc741b`
- `count_active` P5c roster manifest:
  `e0baa64bf5aa19ef51217f6cb4f984a8571abc1594823aedbd5c3790ce085fe9`
- `loyo_m3` P5c roster manifest:
  `4a35058474089c894cc318a7f5368b037b3a108e7fd6af923831fa00e56e1054`
- `loyo_m4` P5c roster manifest:
  `9eb610f44fcb331f1ce9a6cd70684ceeeaaddb032537e08521395e9cfbb85116`
- `count_active` reweighted-panel manifest:
  `d734335fa4b780cbee36514c4d8647745bcdedd4c4e077a3c931228aa38e5d50`
- `loyo_m3` reweighted-panel manifest:
  `f13667a71c065f5ee8cc941fcd5c1fbba7695c9d9bb98fd979fb667b6b740243`
- `loyo_m4` reweighted-panel manifest:
  `92c4d0914d7661cb9d012e5936be6fc456c6be77a42d653f207625a77ff261a8`
- Estimation configuration:
  `c4b5cec45a6291761b8428317371096a2c4e1f26d5c2a25322ac2d467e490d88`
- Estimation core:
  `7e09ca4d5d15b242b5e2d511222b4147d3339bbe0067f190dda3b52afa7a639f`
- Estimation runner:
  `29a8f2200d793a2d2b032f6b7dd474923f75598a256bd07e081dccab696538ab`
- P6 panel reweighting source:
  `425e20aa5d018fa342b9f5df26691549d06db5cadc67caa5842ced3c96431462`
