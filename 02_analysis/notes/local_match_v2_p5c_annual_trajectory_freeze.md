# P5c annual pre-treatment trajectory freeze

Date frozen: 2026-07-26

## Purpose

P6 found a non-zero pre-treatment patent-count difference under the frozen
P5a weights. P5c is an additive reweighting layer that asks whether the result
survives after directly balancing the complete five-year annual patenting
history. It does not overwrite or silently replace P5a.

## Frozen support and sample

- Reuse the finalized P5a U2-clean, nearest-50, IPC4 support roster.
- Do not add or remove treated inventors, controls, deals, or firms.
- Recompute base weights from that roster for the primary and equal-deal
  schemes.
- Use only event years `t=-5,-4,-3,-2,-1`. No `t=-6`, `t=-7`, or earlier
  outcome enters matching, weighting, diagnostics used for selection, or the
  P5c production artifacts.
- Annual patent counts use the certified P3 `inventor_year` definition, which
  is identical to the certified P6 patent-count panel definition.

The retained P5a support screen was originally built using five-year firm and
inventor summaries. P5c therefore changes final weighting, not donor
admissibility. This is intentional: it preserves the already-certified common
support and avoids reopening the expensive P4 graph.

## Balance specifications

Both variants balance these five raw annual patent counts:

`patent_count_m5`, `patent_count_m4`, `patent_count_m3`,
`patent_count_m2`, `patent_count_m1`.

Both also retain:

- inventor career age;
- inventor focal-group exclusivity;
- firm log patent stock over the five pre-treatment years;
- firm log inventor count over the five pre-treatment years;
- firm patent trajectory.

The two prespecified variants are:

1. `count_only`: the variables above.
2. `count_active`: all `count_only` variables plus
   `active_patenting_m5`, ..., `active_patenting_m1`, where an indicator is
   one if the corresponding annual patent count is positive.

No second moments are part of this main probe.

## Probe and production rule

Probe cohorts 2000 and 2005 under primary base weighting. The earlier
equal-deal probes for these two cohorts were infeasible under both annual
variants, matching their P5a status. Equal-deal P5c is therefore run
separately for the other 15 cohorts rather than repeated for the two known
failures.
The existing per-cohort feasibility hierarchy is unchanged:

`exact entropy balance -> tolerance 0.05 -> tolerance 0.10 -> infeasible`.

The primary scheme governs production because it is the main ATT. The
equal-deal cells are reported diagnostics: cohort 2000 was already infeasible
under equal-deal P5a, so that known secondary-scheme limitation must not
mechanically choose between the two primary-ATT variants.

The complete Candidate-A specification is `count_active`; it is fixed as the
primary P5c production specification. `count_only` is a feasibility diagnostic,
not a design-selection candidate. Production proceeds only if, across the two
primary-scheme probe cells, `count_active`:

1. both cells are feasible;
2. every cell passes the existing reuse-adjusted ESS ratio floor of 0.50;
3. relative to `count_only`, no cell loses more than 0.10 in absolute
   reuse-adjusted ESS ratio;
4. relative to `count_only`, no cell's reuse-adjusted maximum control-inventor
   weight share rises by more than 25 percent.

If any condition fails, production stops for design review. It does not switch
to `count_only`. No post-treatment outcome or treatment-effect estimate is used.

## Held-out-year placebos

Two separate leave-one-year-out designs are fixed:

- `loyo_m3`: omit both `patent_count_m3` and `active_patenting_m3`;
- `loyo_m4`: omit both `patent_count_m4` and `active_patenting_m4`.

Each balances both annual measures in the other four years and retains all
non-annual inventor and firm controls. `t=-3` is the primary placebo because it
was the original failed lead. `t=-4` is the companion because it is outside the
plausible negotiation window and is not the five-year support boundary.

For each placebo, the omitted year's P6 event-study estimate is the
falsification statistic. The other four pre-treatment coefficients are
construction diagnostics. A placebo is considered reassuring when the
omitted-year 95% interval includes zero and its absolute point estimate is
below 0.05 patents per inventor-year. These conditions are reporting
benchmarks, not a basis for choosing between the two placebo designs; both are
reported.

## Production and reporting

- Run the selected primary specification for every cohort 1994--2010.
- Run both held-out-year primary placebo specifications for every cohort.
- Preserve the equal-deal P5a results as the secondary weighting comparison;
  P5c equal-deal probes are reported but are not required for production.
- Exhaust the per-cohort feasibility hierarchy before considering any global
  simplification.
- Preserve P5a and P5c weights side by side.
- Report P5a and P5c outcome estimates side by side in P6.
- Because all five displayed pre-treatment patent-count years are balanced in
  P5c, those years are construction diagnostics, not independent placebo
  tests. P5a remains the design that supplied the original falsification test.
