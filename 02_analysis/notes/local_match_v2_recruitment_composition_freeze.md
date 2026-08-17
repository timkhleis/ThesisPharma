# Recruitment-composition audit: frozen design

Frozen on 2026-08-08 before constructing or inspecting any recruitment-composition outcome.
This audit follows `recruitment_composition_implementation_plan.md`, including the
corrections incorporated from the external implementation review.

## Question and estimand

The audit asks whether different timing and duration of affiliation with the focal
firm/group mechanically generates the visible pre-treatment patent-count path, in
particular the P5a level gap and the held-out `loyo_m3` coefficient at event time
`t=-3`. The primary recruitment definition is symmetric across arms: the first and
last year in which the inventor is resolved to the focal group in
`inventor_affiliation_own`, using all available years up to `g-1`. An inventor with
no resolved focal-group year is retained in an explicit `unresolved` category.

The as-is granularity diagnostic uses target-company patent links for treated
inventors and resolved focal-group affiliation for controls. It is never the primary
measure because its arm-specific entity definition can itself create a difference.

## Frozen bins and statistics

- Entry bins: `pre_g5`, `m5`, `m4`, `m3`, `m2`, `m1`, and `unresolved`.
- End bins: `pre_g5`, `m5`, `m4`, `m3`, `m2`, `m1`, and `unresolved`.
- Observed spell lengths: `1`, `2`, `3_5`, `6_plus`, and `unresolved`.
- Primary composition statistic: cohort-weighted treated-minus-control share in
  symmetric group-level entry bin `m3`.
- Primary outcome threshold: 0.010 patents per inventor-year, with the correct sign,
  for opening B3.
- Calibration benchmark: the previously reported P5a `t=-3` level gap, 0.0414.
- Primary inference unit: deal-cluster wild bootstrap, matching the production design.
- All event times and all frozen variants are co-reported; none is selected because
  it gives a flatter path.

## Frozen diagnostic sequence

1. Construct and certify symmetric and as-is affiliation histories.
2. B0: entry-year indicator and deterministic subtraction, primarily under P5a,
   with `loyo_m3` as a companion held-out diagnostic.
3. Shift-share accounting using the same parent weights as each gap.
4. B1: add symmetric entry-bin constraints to `loyo_m3`; `t=-3` patent count and
   active patenting remain excluded from its original balance set.
5. B2: add symmetric entry-bin constraints to P5a while preserving its original
   non-annual design moments.
6. Open B3 only if B0, B1, or B2 reaches the frozen 0.010 threshold.

Entry/end/length is a separately labelled expanded variant for B1 and B2. Entry-only
remains primary.

## Frozen feasibility gates

The hierarchy is exact balance, then approximate balance with maximum absolute SMD
of 0.05 on new recruitment moments while preserving original gates, then infeasible.
No bins or cohorts may be dropped after outcomes are seen. Relative to the parent:

- reuse-adjusted ESS ratio must be at least 0.50;
- absolute ESS-ratio loss must not exceed 0.10;
- maximum weight share may rise by at most 25%; and
- all weights must be positive and finite, with treated weights and within-cohort
  treated/control mass identities preserved.

The same gates are imposed on P5a as on P5c.

## Frozen inputs

| Input | SHA-256 |
|---|---|
| P5a primary weighted roster | `458036894BE7AE16648AB41DE7D6A4E6F3FD489D11373F9E6A18E7686D268AB0` |
| P5c `loyo_m3` primary weighted roster | `7F8F3EF1728CA5638843B0EE395E105C06A48ABFFE7D231C0F91E32B1B933356` |
| P5c `count_active` primary weighted roster | `3184AEE524BB2DAC5A42D83FD86F1B7A80D8D24566787C5A95536DDC2DA71315` |
| Root thesis foundation DuckDB | `F2C4238B37C78B52DA8591F882EB08A091DCC2099A57B160A4EC1E5566134053` |

The implementation manifest records script and panel-manifest hashes before the
first audit run. Any mismatch is a hard failure.
