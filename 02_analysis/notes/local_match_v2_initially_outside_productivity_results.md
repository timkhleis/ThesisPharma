# Initially-outside inventor productivity results

Status: certified selected-group companion result.

Date: 2026-08-18

## Main result

Inventors whose first observed post-acquisition patent is outside the combined
target--acquirer group produce 0.0645 fewer patents per year than separately
balanced inventors whose first post-event patent is outside a matched control
group. The analytic two-way deal/inventor-clustered 95 percent confidence
interval is [-0.183, 0.0535] (p = 0.284). The estimate corresponds to 0.323
fewer patents over five years and a 9.30 percent reduction relative to the
weighted control post-period mean of 0.694 patents per year.

The fixed-denominator percentage interval is [-26.3%, 7.71%]. The 9,999-draw
deal-wild interval for the absolute ATT is [-0.172, 0.0446] (p = 0.255), and
the jointly recomputed percentage interval is [-24.9%, 6.21%]. The data
therefore do not distinguish the point estimate from zero. They also do not
establish an economically small effect: the pre-specified 20 percent
equivalence test fails, and the design-stage MDE is 0.198 patents per year,
or 28.5 percent of counterfactual post-period output.

## Design certification

The broad classification identifies 1,191 acquisition-exposed initially-
outside inventors, 4.11 percent of the status-eligible treated population.
The corresponding control rate is 3.08 percent. The first-post-patent timing
distribution is similar across arms: 59.3 percent of treated and 60.2 percent
of control initially-outside inventors first patent by event time +2.

The P5c intersection retains 1,008 treated rows. Requiring treated and control
support within the same deal stacks leaves 987 treated inventor--deal rows,
9,105 control rows, and 169 nominal treated deals. Treated retention is 82.9
percent and the effective treated-deal count is 42.2.

The cohort-specific full and count-only tiers fail in sparse acquisition
cohorts. The fixed ladder therefore selects exact balance within the three
pre-specified acquisition eras, with exact cohort-share constraints. The
maximum absolute balance discrepancy is 2.16e-11 and the minimum reuse-
adjusted ESS ratio is 1.17. The held-out -3 and -2 estimates are 0.122 and
0.112 patents; their separate intervals include zero and their joint p-value
is 0.173.

## Sensitivities

| Specification | ATT per year | 95% analytic CI | p-value | Percentage |
|---|---:|---:|---:|---:|
| Primary, 1993--2010 | -0.0645 | [-0.183, 0.0535] | 0.284 | -9.30% |
| Censoring-clean, 1993--2008 | -0.0441 | [-0.167, 0.0784] | 0.480 | -6.45% |
| First outside patent by +2 | -0.111 | [-0.283, 0.0618] | 0.209 | -12.4% |
| Exclude mixed first-patenting years | -0.0524 | [-0.166, 0.0615] | 0.367 | -7.79% |
| Route-consistent classification | -0.0645 | [-0.183, 0.0535] | 0.284 | -9.30% |

The target-only definition fails its prospectively fixed ESS gate in the first
two acquisition eras and is reported as infeasible rather than estimated.
Dropping one treated deal at a time leaves the primary ATT between -0.0939 and
-0.0534, so no single deal determines its sign.

The common-support tipping exercise shows that the unsupported 17.1 percent
would need an ATT of +0.312 patents per year to bring the full-population point
estimate to zero. This equals a 0.490-pre-period-standard-deviation difference
between supported and unsupported effects. The calculation concerns support
exclusion only; it does not solve post-treatment selection into initially-
outside status.

## Interpretation

The estimates consistently point toward a modest output loss after acquisition
among initially-outside inventors, but they are too imprecise to establish
either a decline or no economically meaningful change. They provide no evidence
that inventors become more productive after patenting outside the combined
entity. Because acquisition can affect who becomes initially outside, the
estimate remains a selected-group comparison rather than an effect for an
always-leaver principal stratum or a causal effect of departure.

Suggested thesis paragraph:

> As a companion to the retained-inventor analysis, I compare target inventors
> whose first observed post-acquisition patent is outside the combined group
> with separately balanced inventors who patent outside matched control groups.
> Acquisition-exposed initially-outside inventors produce 0.065 fewer patents
> per year over the following five years (95% CI: -0.183 to 0.054), equivalent
> to a 9.3 percent reduction relative to their estimated counterfactual output.
> The estimate is not statistically distinguishable from zero, and the
> confidence interval cannot rule out economically meaningful losses. Because
> acquisition can affect who patents outside the group, this result is a
> post-treatment-selected comparison rather than an effect for a fixed
> population of always-leavers.

## Reproducible artifacts

- Classification and audit outputs:
  `02_analysis/output/audit/local_match_v2_1993_amendment/INITIALLY_OUTSIDE_S0_S2/`
- Support, balance, held-out tests, and MDE:
  `02_analysis/output/audit/local_match_v2_1993_amendment/INITIALLY_OUTSIDE_S3/`
- Estimates, inference, sensitivities, and tipping:
  `02_analysis/output/audit/local_match_v2_1993_amendment/INITIALLY_OUTSIDE_S4_RESULTS/`
- Entry points: `71_run_lmv2_initially_outside_s0_s2.R`,
  `72_run_lmv2_initially_outside_s3.R`, and
  `73_run_lmv2_initially_outside_s4.R`.
