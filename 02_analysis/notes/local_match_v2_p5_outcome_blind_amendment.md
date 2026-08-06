# Local Match v2: P5 outcome-blind selected-spec amendment

**Date:** 2026-07-26

## Evidentiary boundary

This amendment was written before P5 weights were joined to any outcome and
before any P5 treatment effect, event study, or CS(2021) estimate was
computed. The evidence used is restricted to P4 support, retention, balance,
effective-sample-size, weight-concentration, and runtime diagnostics for the
complete 1995, 2002, and 2009 pilot cohorts.

This note does not edit the earlier P4-EB amendments. It records and explains
the outcome-blind specification selected for the redesigned cohort-level P5
balancing pipeline.

## Selected main specification

P5 freezes:

- control universe: `u1`;
- Stage-1 profile: `nearest_50`;
- Stage-1 support caliper: `1.5`;
- Stage-2 support caliper: `1.5`;
- inventor technology resolution: `ipc4`;
- weighting schemes: `primary` and `equal_deal`;
- exact solver: the certified direct Newton entropy solver;
- solve level: separately within each treatment-year cohort.

U1 remains primary because it excludes firms that are ever acquisition
targets and firms with an acquirer event within plus or minus five years of
the cohort. U3 admits acquirer firms and remains outside the P5 primary run.

The cohort-level hybrid redesign makes final full-spine inventor retention
the binding support diagnostic. Under U1 and `nearest_50`, Stage-1 caliper
`1.0` fails the locked 80% inventor-retention floor in the 2009 pilot.
Caliper `1.5` is the tightest tested value that clears the 80% floor in all
three pilot cohorts. Caliper `2.0` retains 40 additional inventors out of the
4,420-inventor pilot spine but no additional deal. Both values achieve exact
pooled balance and pass ESS. The tighter value is selected to preserve local
comparability without sacrificing locked feasibility.

At the selected value, the pilot retains 4,027 of 4,420 inventors (91.11%)
and 36 of 37 deals (97.30%). Cohort retention is 84.25% in 1995, 86.29% in
2002, and 93.58% in 2009. Estimates for cohorts below the preferred 90% tier
must be labelled common-support ATTs. P5 must report the complete retention
funnel, effective control-firm count, and retained-versus-unsupported treated
inventor characteristics.

## Feasibility hierarchy

The existing hierarchy remains unchanged:

1. the full-spine retention gate is terminal;
2. exact entropy balance must also pass reuse-adjusted ESS;
3. otherwise attempt the locked 0.05 approximate-balance rung;
4. otherwise attempt the locked 0.10 rung;
5. otherwise mark the cohort unsupported.

P5 must not respond to an unsupported cohort by changing the caliper,
universe, profile, technology resolution, or balance variables.

## DealSim branch

DealSim weighting is separate from the headline weights and is used only for
the DealSim heterogeneity analysis.

1. Construct and certify DealSim before freezing terciles. DealSim is the
   cosine similarity between target and acquirer IPC4 portfolios over years
   `g-5` through `g-1`. Construct both portfolios from `group_ipc_year`
   using the certified P3 normalized IPC4 code map. The P3 firm-vector table
   itself is not used because its matching-specific roster intentionally
   contains targets and eligible controls but not acquirer groups.
2. Exclude missing and `999xxxx` placeholder acquirers.
3. Form global deal-level terciles with R quantile `type = 7`; the lower
   boundary is included. Cutpoints are frozen before matching-support
   failures are inspected.
4. Solve separately within each cohort-by-tercile stratum because CS(2021)
   identifies cohort-specific group-time ATTs.
5. Attempt both schemes. `primary` is headline; `equal_deal` is a
   co-reported sensitivity scheme.
6. Apply the unchanged exact/0.05/0.10 and ESS hierarchy. Never pool cohorts,
   move cutpoints, or retune support after a failure.
7. A tercile ATT may be reported only when supported primary cells jointly
   retain at least 80% of that tercile's treated inventors and 85% of its
   treated deals. Otherwise the tercile is unsupported.

The continuous DealSim quadratic and spline specifications use the main
cohort weights and remain supplementary descriptive analyses.

## P5 stopping rule

P5 ends after checksum-verified row-level weights and design diagnostics are
materialized and reviewed. It must not read outcome-analysis objects or
estimate treatment effects.
