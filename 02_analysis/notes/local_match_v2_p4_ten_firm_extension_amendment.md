# Local matching v2: P4 ten-firm Stage-1 extension amendment

Status: immutable prospective record, written 2026-07-23, approved by the
review after the fourth pilot execution exhausted the bounded caliper
refinement and before any outcome inspection. Only balance, retention, and
support diagnostics were read in reaching this rule. Its SHA-256 is pinned
in `17a_lmv2_p4_pilot_config.R` and folded into the P4 configuration hash.

## The rule (final structural attempt)

1. The five-firm design remains primary. Its complete diagnostics,
   including its design-failure record, are preserved at the run root as
   the primary pilot diagnostic; the ten-firm attempt writes to a separate
   `ten_firm/` location and never overwrites them.
2. The ten-firm extension activates **only after** the five-firm design
   exhausts its bounded refinement: a five-firm Stage-2 terminal failure —
   no acceptable profile after the locked grid plus bounded bisection, or
   a failure of the final inventor-weighted firm-trajectory gate. A
   five-firm **Stage-1** design failure does not activate the extension
   and stops the pilot permanently, because pool expansion addresses
   donor flexibility, not a firm-level design defect.
3. The extended Stage-1 pool holds ten control firms per deal with equal
   weights of 0.1, selected by the identical Stage-1 machinery: same
   caliper grid, same trajectory-promotion rule, same guarded fallback,
   same tiers and lexicographic order, same small-cohort gate rule.
4. Stage 2 is unchanged: three control inventors from at least two firms,
   weight one third, identical technology, recency, and support rules.
5. Every balance, retention, technology-support, target-size, and final
   firm-trajectory gate is unchanged in every respect.
6. The same bounded caliper refinement applies: at most two midpoint
   evaluations under the pinned bisection amendment.
7. The pilot still runs twice end to end and publishes only on identical
   logical manifests; both runs must traverse the same five-firm and
   ten-firm path deterministically.
8. If the ten-firm design also fails any gate, the pilot stops
   **permanently**: the conclusion is that this matching design is
   infeasible under the locked standards, and no further tuning,
   refinement, or amendment follows.

## Rationale

Four executions consistently locate the binding constraint in donor
flexibility for 1995 focal-tenure matching, with the five-firm design
missing feasibility by margins of 0.004 in balance or 0.77 percentage
points in retention. Doubling the Stage-1 pool is a meaningful support
expansion that attacks that bottleneck directly — more donors per deal at
every caliper — without moving any threshold. A ten-firm pool already
exists conceptually in the locked stayer design
(`stayer_design$fallback_pool = "predeclared_ten_firm_stayer_extension"`);
applying it to the full-cohort pilot is a new decision and is therefore
recorded here explicitly. This is the final structural attempt.
