# Local matching v2: P4 trajectory-fallback amendment

Status: immutable prospective record, written 2026-07-23, approved by the
review after the second pilot execution stopped at the Stage-1 gate and
before any outcome inspection. Only pre-treatment balance and retention
diagnostics were read in reaching this rule. Like the other P4 records, it
lives outside the P3-hashed amendments file; its SHA-256 is pinned in
`17a_lmv2_p4_pilot_config.R` and folded into the P4 configuration hash.

## The rule (general fallback, not a one-off repair)

1. Trajectory promotion is attempted exactly as locked: a trajectory-SMD
   breach on the selected base profile mandates evaluation of the
   `distance_with_trajectory` grid, and a promoted profile that reaches any
   acceptable tier is selected from that grid as before.
2. If no promoted profile is acceptable, fallback to the base grid is
   permitted **only** when the selected base profile passes the
   **preferred** tier. A base profile passing only the acceptable tier
   cannot qualify; in that case the pilot stops with a design failure as
   before.
3. A fallback Stage-1 pool is frozen **provisionally**, labeled
   `trajectory_fallback_provisional` in the freeze record.
4. Stage 2 then runs unchanged, matching inventors directly on their own
   patent trajectories under the locked Stage-2 gates.
5. After the Stage-2 profile is selected, firm-level balance is
   recalculated under the **final inventor-match weights**: each matched
   treated inventor contributes its deal's target-firm covariates with
   weight one; each matched control inventor contributes its own firm's
   covariates with weight one third within its matched set. Firm patent
   stock (log), firm size (log inventor count), and firm trajectory are all
   recalculated and reported, standardized by the locked Stage-1 cohort
   scalers.
6. The binding requirement is final firm-**trajectory** balance within the
   existing acceptable threshold, |SMD| <= 0.10, applied pooled and in
   gate-eligible cohorts (per the small-cohort amendment), alongside all
   existing Stage-2 inventor-level gates. The threshold is the locked
   Stage-1 acceptable bound; no gate is widened.
7. If the final firm-trajectory balance fails, the pilot stops without
   freezing a P4 design and no treatment effect is estimated. The gate is a
   stop check on the selected design, never a selection criterion among
   profiles.

## Rationale

The estimand is the average treated inventor, not the average firm. The
Stage-1 firm pool is preliminary; what must ultimately be balanced is the
final inventor-weighted comparison. A provisional fallback to a
preferred-tier base pool avoids relaxing the 0.10 bound to fit an observed
value, avoids an arbitrary trajectory weight in the composite distance, and
avoids another P3 rebuild — while the final inventor-weighted firm gate
ensures the firm-level trajectory selection problem cannot silently
propagate into estimation.
