# Local matching v2: P4 bounded caliper-bisection amendment

Status: immutable prospective record, written 2026-07-23, approved by the
review after the third pilot execution stopped at the Stage-2 profile gate
and before any outcome inspection. Only balance, retention, and support
diagnostics were read in reaching this rule. Its SHA-256 is pinned in
`17a_lmv2_p4_pilot_config.R` and folded into the P4 configuration hash.

## Scope

This rule refines the Stage-2 inventor caliper grid of the P4 pilot. It
relaxes no balance, retention, cohort, or target-size threshold; every
midpoint profile faces exactly the gates of the locked design.

## The rule

1. Bisection is considered only when the locked grid yields no acceptable
   profile, and triggers only when two **adjacent** calipers in the locked
   grid fail **exclusively on complementary gates**: the looser caliper
   fails balance only (max gated |SMD| above the acceptable bound, all
   retention and target-size gates passing) and the tighter caliper fails
   retention only (any retention-family gate — inventor, deal, or minimum
   cohort retention — failing, with balance and target-size passing). The
   loosest such adjacent pair is taken; the loose bound must be finite.
2. The midpoint of the bracket is evaluated as a full profile.
3. The bracket updates by the midpoint's failure type: a balance-only
   failure replaces the loose bound; a retention-only failure replaces the
   tight bound. A midpoint failing on any non-complementary gate ends the
   refinement.
4. If the midpoint is acceptable it is retained, and refinement continues
   toward the looser boundary (the midpoint becomes the tight bound) to
   seek higher retention.
5. At most two midpoint evaluations are performed.
6. The existing lexicographic selector is then applied to all evaluated
   profiles — locked grid points and midpoints alike — under the unchanged
   tier definitions and ordering.
7. The final inventor-weighted firm-trajectory result is never used to
   select among calipers; it remains a stop check on the selected design.
8. If no acceptable profile emerges, or the final firm-trajectory gate
   fails, the design stops. No further local gate amendments follow this
   one.

## Rationale

The caliper grid {inf, 2.0, 1.5, 1.0} is an arbitrary coarse tuning grid,
not a substantive design commitment. When adjacent grid points fail on
complementary unchanged gates they bracket a feasible region that the grid
merely failed to sample. Bounded bisection samples inside the bracket under
identical gates, so it cannot admit any design the locked thresholds would
reject; it can only find designs the coarse grid overlooked. The procedure
is deterministic, capped at two evaluations, and entirely outcome-blind.
