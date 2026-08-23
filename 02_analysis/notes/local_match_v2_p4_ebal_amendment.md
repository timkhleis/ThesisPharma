# Local matching v2: P4-EB entropy-balancing amendment

Status: immutable prospective record, written 2026-07-23, approved by the
review after the five/ten-firm fixed-weight P4 pilot recorded a definitive
design failure (`archive/local_match_v2_p4_outcome_blind_pilot.md`, run of
2026-07-23: "the five-firm design misses acceptability by 0.004 in balance
or 0.77pp in retention after bounded bisection, and the ten-firm final
structural attempt degrades Stage-1 balance below the preferred tier ...
Permanent stop per the pinned amendments; no design frozen, no outcome
inspected"). Only pre-treatment balance, retention, and solver-feasibility
diagnostics from that failed pilot and from the synthetic fixtures below
were read in reaching this design. This record lives outside the P3-hashed
amendments file, like the other P4 records; its SHA-256 is pinned in
`17f_lmv2_p4_ebal_config.R` and folded into the P4-EB configuration hash.
It does not edit `15a_lmv2_design_lock.R`, `local_match_v2_p0_prospective_lock.md`,
or any existing P4 amendment note, and it does not modify `17a`-`17e`, which
remain the fixed-weight pilot's own record and are archived as a
support-finding diagnostic.

**Corrective revision, 2026-07-23, before any database execution or outcome
inspection:** a review of the first E1 commit found several errors in the
production-facing path that the initial 42-check synthetic suite did not
exercise. The design below reflects the corrected implementation; the
corrections are:

1. `lmv2_ebal_finalize_weights()` forced every treated unit's final weight
   to 1. For the equal-deal scheme this silently discarded the entire
   point of unequal treated `s.weights` (1 per inventor split across its
   deal): it reverted the solver's target back to the inventor-weighted
   mean, rescaled controls to the wrong (inventor-count) mass, and made
   downstream balance diagnostics compare controls calibrated to one
   target against treated units labeled for another. Fixed: treated final
   weight is now the caller-supplied `s.weights`, verbatim.
2. The Stage-1 firm-caliper step collapsed deal-level admissible edges to
   a unique firm pool *before* that pool was used to build Stage-2
   inventor pairs, which need the deal_id to know which candidate firms a
   given treated inventor's deal actually admits. Fixed: deal-level
   admissible edges and the unique firm pool are now two explicit,
   separately retained interfaces.
3. The Stage-2 local-support step collapsed away `(deal_id,
   treated_codinv)`, so every treated inventor looked "retained" and
   retention was computed from control-row counts instead of treated
   inventors. Fixed: a third explicit interface, supported treated
   inventors keyed by `(cohort, deal_id, treated_codinv)`, now drives
   retention, the exclusion log, and which treated inventors enter Stage 2
   at all (enforced inside the roster builder itself, not merely assumed
   from caller discipline).
4. The terminal stop checked only the firm-reaggregation gate. Fixed: a
   single terminal-gate function now requires, separately for each scheme,
   that every expected cohort produced a result, every cohort's inventor
   balance passed, firm reaggregation covered every expected cohort,
   retention met at least the acceptable tier, no cohort fell below the
   50% floor, no target-size category disappeared, and all diagnostics
   are finite.
5. The firm-reaggregation gate treated a missing treated target or a
   missing scaler as SMD = 0 (a silent pass). Fixed: missing target or
   scaler is now a hard certification failure; the actual Stage-1
   entropy-balancing standardization scaler (not the broader, differently
   -populated P3 distance-caliper scaler) is persisted in the Stage-1
   freeze and reused here; zero-variance omission is allowed only when the
   persisted scaler explicitly recorded it.
6. Donor uniqueness is now checked at `(cohort, codinv)`, not `codinv`
   alone (the same inventor can legitimately recur at different
   pseudo-event dates). Controls dropped for missing covariates are now
   logged. `17i` now verifies its `--stage2-caliper`/
   `--technology-resolution` arguments match what Stage 1 was actually
   built with. `17f` now verifies the file-content hashes of the imported
   `16a`/`16c` sources directly, not merely a stored commit label.

Sections below describe the corrected design throughout; where a formula or
interface changed, it is stated as it now is, not as it originally (and
briefly) was.

## Why entropy balancing, not another fixed-weight repair

The fixed five/ten-firm nearest-neighbor design assigns weights (1/5, 1/10,
1/3) purely by rank within a caliper. It was never intended as the primary
estimator: the P3 matching machinery exists to define local common support
(technology, recency, and covariate calipers), not to solve for balance. Its
definitive failure under the locked standards is a failure of that
weighting layer, not of the support-finding machinery it sits on top of.
This amendment restores the originally intended second layer: within the
support pool P3/17a-17e already define, solve for entropy weights that hit
near-exact covariate balance directly, rather than hoping a fixed-rank
neighborhood happens to balance.

## The design (P4-EB)

### Pipeline

```
P3 admissibility screen (pairwise caliper rules, reused unedited)
  -> Stage-2 inventor eligibility pre-check (which firms have >=1 eligible inventor)
  -> cohort-level firm entropy balance (Stage 1, unique control firms with >=1 eligible inventor)
  -> firm-weight allocation to eligible inventors (base weights, zero lost mass by construction)
  -> cohort-level inventor entropy balance (Stage 2, unique control inventors; two solves: primary + equal-deal)
  -> final inventor-level AND estimand-correct re-aggregated firm-level balance certification
```

P3's pairwise caliper rules (technology, recency-gap, IPC4 overlap) are used
only to construct admissible donor pools, never to produce pair-specific
weights. Entropy balancing runs once per cohort on unique units and
produces one cohort-level entropy weight per unique control firm or
inventor.

### Stage-1 roster

Two interfaces feed the roster, kept explicitly separate (never collapsed
into one, per the corrective revision): `admissible_firm_edges`, one row
per `(cohort, deal_id, control_group)` surviving the Stage-1 caliper, used
downstream to build Stage-2 inventor pairs (a control inventor is locally
admissible for a treated inventor only if the inventor's own deal admits
that inventor's firm); and the `firm_pool` collapsed from those edges to
one row per unique `(cohort, control_group)`, which is what the entropy
solver actually balances. The roster itself: one row per `(cohort, side,
unit_key)`, `unit_key = deal_id` if treated else `control_group`,
deduplicated across all treated deals in the cohort, **pre-filtered to
firms with at least one Stage-2-eligible inventor** (see "Zero lost mass by
construction" below). Balance moments: `log_patent_stock_5y`,
`log_inventor_count_5y`, `patent_trajectory`. Technology (IPC4 firm cosine)
stays a caliper/support restriction only, never an entropy moment.

### Stage-2 roster

Three interfaces feed the roster, kept explicitly separate: `admissible_edges`
(one row per `(cohort, deal_id, treated_codinv, control_codinv)` surviving
the Stage-2 caliper, restricted to positive-weight Stage-1 firms);
`eligible_controls` (the cohort-level union of unique control inventors,
used to build the donor pool); and `supported_treated` (treated inventors
keyed by `(cohort, deal_id, treated_codinv)` retained in common support --
this is what drives retention and the exclusion log, and what the roster
builder itself uses to restrict the treated side, not merely a promise
enforced by caller discipline). The roster: one row per `(cohort, side,
unit_key)`, `unit_key = (deal_id, treated_codinv)` if treated (restricted
to `supported_treated`) else `control_codinv`. Balance moments:
`log_patent_count_5y`, `patent_trajectory`, `career_age`,
`focal_group_tenure`, `focal_group_exclusivity`. Technology stays
diagnostic-only.

### Base-weight allocation (Stage 1 -> Stage 2)

Equal split:

```
b_jc = w^F_fc / N^eligible_fc
```

where `w^F_fc` is firm `f`'s Stage-1 entropy weight in cohort `c` and
`N^eligible_fc` is the count of Stage-2-eligible control inventors at that
firm-cohort. Allocating by an inventor's own covariates would pre-bias the
exact dimension the Stage-2 tilt adjusts, so equal split is the
ex-ante-exchangeable null.

### Zero lost mass by construction

A control firm never enters the Stage-1 balancing pool unless it already
has at least one Stage-2-eligible inventor (shared-IPC4, recency-gap, and
technology-caliper support for at least one retained treated inventor). So
`N^eligible_fc >= 1` for every firm receiving Stage-1 weight, and base-weight
allocation conserves total mass exactly; no lost-mass exception path
exists. Firms excluded at this pre-check are logged with an explicit reason
in `p4_ebal_stage1_excluded_firms.csv`, never silently dropped.

### Two separate Stage-2 solves

The equal-deal-weighted inventor ATT has a different treated target
distribution than the primary inventor-weighted ATT and requires its own
solve:

- **Primary solve**: every treated inventor enters with `s.weights = 1`.
- **Equal-deal solve**: every treated inventor enters with `s.weights = 1 /
  (retained treated inventors in its deal)`, so each deal contributes equal
  total weight.

These `s.weights` values become the treated units' FINAL weights, verbatim
(see "Solver and the empirically resolved base-weight semantics" below) --
they are never overwritten by the solver or forced to a constant. Stage 1
(firm weights, base-weight allocation) is shared. Stage 2 -- solve,
diagnostics, gates, firm-reaggregation check -- is fully recomputed for
each.

### Solver and the empirically resolved base-weight semantics

`WeightIt::weightit(D ~ <balance_vars>, data = standardized, method =
"ebal", estimand = "ATT", moments = 1, s.weights = <base weights>, maxit =
100000L)`, wrapped in `tryCatch`, following the convention already used for
`method = "ebal"` in `12c_verginer_ebal_utils.R` (ported, not sourced --
`12c` requires `12a_verginer_ebal_config.R`, which defines outcome-bearing
globals at top level and forces unrelated `did`/`ggplot2` dependencies).

`12c`'s existing usage always passes `s.weights = rep(1, n)` for EVERY unit,
treated and control alike, so it never exercises either (a) whether
`WeightIt`'s returned `fit$weights` for `method = "ebal"` already
incorporates `s.weights` multiplicatively, or (b) what happens when the
TREATED arm's `s.weights` are unequal. Stage 2's equal-deal solve is the
first use of both in this codebase, so both were resolved empirically
before writing any downstream code, using WeightIt 1.7.0:

**Finding 1, control-side semantics.** Two hand-computable synthetic
fixtures (a single-covariate case with 3 control units, unequal `s.weights
= c(1, 2, 1)`, and target requiring a genuine non-zero exponential tilt;
and a two-covariate case with 8 control units and unequal `s.weights`) were
solved via `weightit(..., method = "ebal", estimand = "ATT", moments = 1,
s.weights = <unequal weights>)`. The weighted covariate mean was recomputed
two ways: using `fit$weights` alone, and using `fit$weights * s.weights`.
The balance residual against the known target was 1e-2 to 4e-1 under
"`fit$weights` alone" and 5e-9 to 1e-7 under "`fit$weights * s.weights`" in
every case, so the control-side calibration weight is `s.weights *
fit$weights`.

**Finding 2, treated-side semantics (added in the corrective revision).** A
third fixture gave the TREATED arm unequal `s.weights` (two synthetic
"deals": 2 treated units at `s.weights = 0.5` each, 1 treated unit at
`s.weights = 1`, so each deal's aggregate mass is 1 -- exactly the
equal-deal scheme's construction) and compared against a uniform-treated
-weight run. Two results, both confirmed on control supports that bracket
the targets so the solver converges cleanly:

- `fit$weights[D == 1]` was `1, 1, 1` in EVERY run, regardless of what
  `s.weights` were passed for treated units. `WeightIt` never echoes the
  treated-side `s.weights` back through `fit$weights`; that field is
  uninformative for the treated arm and must never be used there.
- The target the solver tilted the controls toward DID shift with the
  treated `s.weights`: 6.667 (the raw treated mean) under uniform
  weights, 5.0 (the `s.weights`-weighted treated mean) under the unequal
  weights, both recovered by the controls to residual <1e-6, and in both
  cases `sum(s.weights[control] * fit$weights[control])` equaled
  `sum(s.weights[treated])` exactly.

Together these findings fully determine the convention: unequal treated
`s.weights` are precisely how a scheme's target moment is defined, and the
treated arm's final weight must be exactly that `s.weights`, never a value
derived from `fit$weights` and never forced to a constant.

**Resolved convention, used consistently everywhere downstream (balance
recomputation, ESS, concentration, firm-reaggregation):**

```
w_j^final = s.weights_j                       (treated units, verbatim)
w_j^final = s.weights_j * fit$weights_j        (control units, rescaled so
                                                 total control mass equals
                                                 total treated mass under
                                                 THIS solve's own target)
```

This is implemented once in `lmv2_ebal_finalize_weights()`
(`17g_lmv2_p4_ebal_utils.R`) and used by Stage 1 and both Stage-2 solves.
For Stage 1 and the primary Stage-2 solve, treated `s.weights` are
uniformly 1, so this reduces to `12c`'s original behavior exactly
(`w^final=1` for treated), and the distinction is only load-bearing for the
equal-deal solve. `lmv2_ebal_run_cohort()` exposes `treated_weight` and
`control_weight` as separate fields in its return value, in addition to
the combined `weight` vector, so no downstream caller can accidentally
assume treated weight one for both estimands.

### Post-Stage-2 firm-balance gate

After each Stage-2 solve (primary and equal-deal, separately):

1. Aggregate final control-inventor weights back to `control_group` (sum
   per firm) to get the re-aggregated control-firm covariate distribution.
2. Compute the treated target appropriate to that estimand from RETAINED
   (supported) treated inventors only -- never the unrestricted P3
   population, and never the original Stage-1 firm weights:
   - Primary solve target: retained deals weighted by their retained
     treated-inventor counts.
   - Equal-deal solve target: each retained deal contributes equal total
     weight.
3. Compute max absolute SMD between the re-aggregated control-firm
   distribution and that target on `log_patent_stock_5y`,
   `log_inventor_count_5y`, `patent_trajectory`, using the ACTUAL Stage-1
   entropy-balancing standardization scaler persisted in the Stage-1
   freeze (`lmv2_ebal_run_cohort()$scaler`) -- never the broader P3
   distance-caliper scaler, which is computed over a different,
   unfiltered population and is not guaranteed to match the EB roster's
   own standardization population. A missing treated target or a missing
   scaler row for a cohort/variable is a **hard certification failure**,
   not `smd = 0`; a variable may be treated as `smd = 0` only when the
   persisted scaler explicitly recorded `zero_variance = TRUE` for it.
4. Classify using the existing balance tiers: preferred <=0.05, acceptable
   <=0.10, fail >0.10 (or any hard failure above).
5. Separately report (diagnostic only, not gated) how far the re-aggregated
   firm mass moved from the original Stage-1 prior weights. Movement is
   expected, especially for the primary inventor-weighted estimand, and is
   not itself a failure condition.

The design passes only if both the Stage-2 inventor-level balance and this
estimand-correct re-aggregated firm-level balance pass, for every cohort
that produced Stage-2 weights (see "Terminal design gate" below).

### Retention and common support

Retention is computed at the `(cohort, deal_id, treated_codinv)` grain
(`lmv2_ebal_retention_summary()`): inventor retention = retained treated
inventors / eligible treated inventors (the P3 population for the pilot
cohorts, after dropping only those with missing balance covariates);
deal retention = deals with >=1 retained treated inventor / eligible
deals. Reported overall, by cohort, and by target-size category (`big_deal`).

Reuses the tiers already pinned in `15a_lmv2_design_lock.R`
(`LMV2_LOCK$pilot$stage_2_preferred/acceptable`,
`LMV2_LOCK$estimands$common_support_label_below_retention = 0.90`), not a
new "all treated units must remain supported" rule and not new numbers:
preferred requires >=90% inventor and >=90% deal retention; acceptable
requires >=80% inventor and >=85% deal retention; every cohort must clear
the acceptable tier's 50% floor; no target-size category may lose every
retained inventor. Below 90% treated-inventor retention the result is
explicitly labeled `common-support ATT`
(`lmv2_ebal_retention_label()`). Every excluded treated unit is logged
with an explicit reason code (`treated_covariate_missing` or
`no_admissible_control_inventor`) in `p4_ebal_exclusion_log.csv`; no
silent complete-case deletion anywhere in roster-building -- this is
enforced inside `lmv2_ebal_stage2_roster()` itself (which restricts the
treated side to `supported_treated`), not merely assumed from caller
discipline.

### Terminal design gate

`lmv2_ebal_terminal_gate()` requires, separately for the primary and
equal-deal schemes: every expected pilot cohort produced a solver result;
every cohort's inventor-level entropy balance passed; the firm-
reaggregation gate passed AND its output explicitly covers every cohort
that produced Stage-2 weights; retention met at least the acceptable tier;
no cohort fell below the 50% floor; no target-size category disappeared;
and all balance diagnostics are finite. A missing or failed cohort can
never silently drop out of an aggregate and thereby pass -- every check
compares against the full expected cohort set, not against whatever
happens to survive upstream filtering.

### Entropy-balancing invariants

- Standardization happens separately within each cohort, using only that
  cohort's treated units and eligible candidate pool (no cross-cohort
  pooling).
- Zero-variance balance-moment columns within a cohort are dropped from
  that cohort's formula and recorded in the persisted per-cohort scaler
  (`variable, mean, sd, zero_variance`, from `lmv2_ebal_run_cohort()$scaler`)
  -- the same table the firm-reaggregation gate reuses to distinguish a
  genuine recorded zero-variance omission from a missing scaler.
- Only pre-event/pre-deal information enters any balance moment.
- The installed `WeightIt` version is recorded in the run manifest (`1.7.0`
  at the time this amendment was written).
- Convergence = solver terminates without error and realized balance
  residual <= tolerance, two tiers: `LMV2_EBAL_EXACT_TOL = 1e-6` (exact,
  informational sub-label of pass), `LMV2_EBAL_RESIDUAL_TOL = 1e-3`
  (acceptable; convergence holds up to here). Above `1e-3`:
  `failed_residual_balance_tolerance`.

### Deferred E2 choices

The following remain unresolved in E1 and must be prospectively frozen in a
pre-E2 amendment, using defensible scale-dependent rules, never selected
after inspecting real-data E2 weight distributions:

1. Stage-1 support caliper.
2. Stage-2 support caliper.
3. Inventor technology resolution (`ipc4` vs `ipc_main_group` vs `ipc7`).
4. ESS and weight-concentration gate thresholds.

Every E1 function that depends on these takes them as explicit parameters,
never a hardcoded default. `inadequate_ess` and `excessive_weight_concentration`
are diagnostic-only in E1: computed and reported (max normalized unit
share, top-5 and top-1% weight share, control ESS, ESS relative to treated
units, count of materially weighted units) but never gate.

## Failure-state taxonomy (E1)

Per-cohort solve, active/gating: `no_feasible_entropy_solution`,
`inadequate_control_mass`, `failed_residual_balance_tolerance`,
`empty_treated_or_control_cell`, `zero_negative_or_undefined_weight`,
`pass` (with `exact`/`acceptable` sub-labels).

Firm-reaggregation gate, active/gating: `stage2_firm_reaggregation_failure`
(covers both a genuine SMD breach and any hard-failure detail row --
`missing_target_or_scaler`, `unrecorded_degenerate_scaler`,
`empty_control_mass` -- since any of those makes the gate's balance claim
unverifiable), `pass` (with `preferred`/`acceptable` sub-tiers).

Terminal gate, active/gating (any one reason fails the whole scheme):
`missing_cohort_in_solver_results`, `cohort_inventor_balance_failed`,
`firm_reaggregation_failed`, `firm_reaggregation_missing_cohort`,
`retention_below_acceptable_tier`, `cohort_below_fifty_percent_floor`,
`target_size_category_disappeared`, `nonfinite_diagnostics`.

Diagnostic-only (reported, never gates in E1): `inadequate_ess`,
`excessive_weight_concentration`.

Invariant, tested but should never trigger by construction: zero
unexplained Stage-1-to-Stage-2 lost mass.

## Estimand

Primary: average treated inventor (`LMV2_LOCK$estimands$primary`). Co-report:
equal-deal-weighted average inventor effect
(`LMV2_LOCK$estimands$co_report`), obtained by the fully separate Stage-2
equal-deal solve above, never by renormalizing the primary solve's weights.

## What this amendment does not do

It does not select real Stage-1/Stage-2 support calipers, does not select
the inventor technology resolution, does not lock ESS/concentration
thresholds, does not run against real data, and does not inspect any
outcome. Those steps belong to a pre-E2 amendment (deferred choices above)
and to E2 itself.
