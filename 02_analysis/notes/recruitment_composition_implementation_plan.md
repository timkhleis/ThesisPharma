# Recruitment-composition diagnostic: revised implementation plan

## Status and implementation gate

Revised on 2026-08-08 after an external implementation review and a direct
check of the shipped Local Match v2 pipeline. This note replaces the initial
plan. No recruitment-composition code or new outcome estimate may be run until
this revision has been reviewed.

Before any outcome-bearing diagnostic is opened, the implementation must write
a freeze note containing the precise variable definitions, ordered feasibility
hierarchy, interpretation thresholds, input paths and SHA-256 hashes, source
hashes, estimator configuration, and random seeds.

## Question and estimand

Treated and placebo-control inventors use the same event-relative recruitment
window, \(g-5\) through \(g-1\). This aligns the mechanical clock induced by
requiring pre-deal focal-entity patent evidence. It does not ensure that both
arms contain the same shares of inventors first observed at the focal entity in
each of those five years.

The concern is composition, not headcount by itself. The headline outcome is
patents per recruited inventor, and treated and control weight mass is
normalized within cohort. A larger donor firm therefore does not mechanically
raise its inventor-level mean. A mechanical artifact can arise if the arms
contain different entry vintages and patenting is elevated in the year that
establishes focal affiliation. Recruitment requires a focal patent in
\(g-5,\ldots,g-1\), so the recruitment year contains at least one such patent
by construction.

The diagnostic asks two separate questions:

1. Does differential focal-affiliation timing explain the localized
   pre-treatment patent-count spike at \(t=-3\)?
2. Does conditioning the comparison on symmetric recruitment composition
   materially change the post-treatment full-cohort ATT?

These questions require different specifications. The shipped `count_active`
weights cannot answer the first because all five pre-period patent-count and
active-patenting outcomes are already balance constraints. They can only show
whether additional recruitment balance changes the post estimate or weight
quality.

## Verified coverage in the shipped pipeline

The final P5c `count_active` solve balances 15 variables:

- patent count at \(t=-5,\ldots,-1\);
- active patenting at \(t=-5,\ldots,-1\);
- career age and focal-group exclusivity; and
- firm log patent stock, firm log inventor count, and firm patent trajectory.

`focal_firm_tenure` is not a P5c balance variable. It appears in the earlier
Stage-2 matching lock, while recency bins constrain the matching/support step.
Neither enters the shipped P5c weight moments. The existing annual outcomes
also count all inventor patents, not only patents linked to the focal entity.
Entry timing is therefore not a deterministic function of the 15 balanced
moments.

Existing scripts provide useful but incomplete evidence:

- `22c_diagnose_lmv2_recruitment_rule.R` and
  `22d_decompose_lmv2_recruitment_lifecycle.R` compare current and early
  recruitment windows in the broad unmatched placebo pool;
- `24a_run_lmv2_verginer_early_recruitment_p6.R` fixes membership using
  \(t=-7/-6\) focal evidence and estimates an established-inventor sensitivity;
- P5c `loyo_m3` genuinely holds out \(t=-3\) from annual outcome balancing and
  currently estimates 0.0447 with a 95% interval of [0.0063, 0.0830]; and
- the P5a treated-minus-control level gap at \(t=-3\) is 0.0414. The other
  pre-period level gaps are much smaller.

The early-recruitment result remains a different estimand. It cannot rescue or
invalidate the full-cohort comparison by itself.

## Measurement contract

### Symmetric and as-is affiliation measures

The current treated roster is established with target-company patent links,
whereas control recruitment uses resolved business-group affiliation. This
asymmetry can make treated inventors appear more recent even when their true
histories are similar.

Construct two variants:

1. `as_is_company_group`: target-company history for treated inventors and
   control-group history for controls. Use this only to measure the consequence
   of the current definitional asymmetry.
2. `symmetric_group_group`: resolved target-group history for treated inventors
   and resolved control-group history for controls. This is the primary
   recruitment-composition measure and the only variant used for substantive
   balance, reweighting, or mechanism claims.

The group-level treated measure changes only the diagnostic covariate. It does
not redefine the frozen treated cohort or the headline treatment assignment.

### Untruncated spell history

Do not use the existing `first_target_affiliation_year` as the main entry
measure because its construction is truncated to \(g-5,\ldots,g-1\). For each
frozen inventor-stack, search all observed years no later than \(g-1\) and
construct:

- `first_focal_year`;
- `last_focal_pre_year`;
- `observed_focal_span = last_focal_pre_year - first_focal_year + 1`;
- `observed_focal_active_years`, the number of years with focal evidence;
- `entry_event_time = first_focal_year - g`;
- `end_event_time = last_focal_pre_year - g`; and
- `qualifying_gap = g - last_focal_pre_year`.

These are patent-affiliation spells, not employment spells. The thesis must use
that wording.

Define entry bins as `pre_g-5`, `g-5`, `g-4`, `g-3`, `g-2`, and `g-1`.
Lookback depth varies across cohorts because patent records begin in 1988.
Record the observable lookback for each cohort. Compare `pre_g-5` shares only
within cohort, then aggregate with the frozen treated-cohort weights. Never
pool raw `pre_g-5` counts across cohorts.

Build the same bins for spell end and a small prespecified set of spell-length
categories. Avoid data-dependent regrouping. If sparse cells prevent a solve,
follow the frozen feasibility hierarchy rather than combining bins after
seeing results.

### Patent-system entry

Report the distribution of first observed patent-system year as a secondary
lifecycle diagnostic. Its mean is already represented by mean-balanced career
age; the new information is distributional balance, not another mean covariate.
Flag left-censoring by cohort.

## Ordered implementation

### Phase 0: freeze, inputs, and invariants

Use the unchanged frozen P5a/P5c support roster and existing estimator. The
freeze note must specify the primary statistic, tests, thresholds, weighting
schemes, feasibility rungs, and reporting order below. It must also state that
all variants will be reported regardless of sign or significance.

Certify before estimation that:

- roster membership and all original weights are byte-identical to their
  frozen inputs;
- every new spell variable uses only years \(\leq g-1\);
- `first_focal_year <= last_focal_pre_year <= g-1` whenever a spell exists;
- the symmetric measure uses group history in both arms;
- the as-is measure uses company history only for treated inventors;
- entry, end, and span fields reconcile with their underlying annual rows;
- cohort-specific lookback depths are recorded; and
- no result-dependent cohort or inventor exclusion is permitted.

### B0: cheap diagnostic without new weights

Run this first. Its primary application is P5a, where the raw pre-period hump
is visible. Apply it to `loyo_m3` as a companion and to `count_active` only as
a reference-period/post-ATT bookkeeping check.

Add `is_first_focal_year_it`, defined from the symmetric group-level measure,
to the frozen event panel. It equals one in the inventor's first observed focal
year when that year lies inside the event window and zero otherwise. Estimate
the unchanged stacked event-study model with this common time-varying control.
Report every lead and the \(t=+1,\ldots,+5\) average.

Also run a transparent deterministic adjustment:

\[
Y^{\mathrm{net\ entry}}_{it}
=Y_{it}-\mathbf{1}\{t=\text{first focal year}_i\}.
\]

This removes only the single patent mechanically guaranteed by entry. It does
not remove additional patents produced in that year. Treat it as an accounting
sensitivity, not an alternative outcome.

Do not assume that the post ATT is unchanged. The post-period outcome values
are unchanged because the indicator is zero after treatment, but DiD
coefficients referenced to \(t=-1\) can move if the adjustment changes the
reference-period treated-control gap. Report both the post-level contrast and
the reference-period-based ATT to make this distinction explicit.

If the \(t=-3\) lead is essentially unchanged under both B0 adjustments, the
entry-composition explanation is weak. Continue through B2 because those tests
are prespecified, but do not open the more expensive B3 branch.

### Pre-check calibration benchmark

Before reweighting, quantify whether the proposed mechanism is large enough.
For each event year, report:

- the symmetric treated-minus-control entry-share gap;
- the treated-minus-control outcome-level gap under the same weights;
- mean patent count in an inventor's entry year and in non-entry years; and
- the entry-share gap required to generate the observed outcome gap given the
  observed entry-year uplift.

For \(t=-3\), calculate

\[
\Delta s^{\mathrm{required}}_{-3}
=\frac{0.0414}
 {\bar Y_{\mathrm{entry},-3}-\bar Y_{\mathrm{nonentry},-3}}.
\]

Report the denominator and uncertainty rather than presenting this ratio as a
known constant. A mechanical-composition claim requires the entry-share gap to
have the same sign and event year as the outcome spike. A gap concentrated at
\(t=-1\) or \(t=-2\) does not explain the \(t=-3\) spike.

The primary composition statistic is the cohort-weighted, symmetric
group-level treated-minus-control share first observed at the focal group in
\(t=-3\). Test equality with the same deal-cluster wild bootstrap used for the
main design and report its 95% interval. All other entry bins, spell-end bins,
spell lengths, and cohort-specific gaps are descriptive family members.

Define a composition channel as materially relevant when its shift-share
contribution at \(t=-3\) has the correct sign and absolute magnitude of at
least 0.010 patents per inventor-year, about one-quarter of the observed
0.0414 level gap. For the entry-share equivalence check, translate this 0.010
outcome margin into a share margin using the frozen observed entry-year uplift
and use two one-sided deal-wild-bootstrap tests at the 5% level. Cap the share
margin at five percentage points.

### Shift-share accounting

Estimate bin-specific paths within cohort and aggregate with the frozen
treated-cohort weights. Use the same weight set as the gap being explained:
P5a weights for the P5a pre-path and `loyo_m3` weights for its held-out lead.
The control-path decomposition is

\[
\widehat{\Delta}^{C,\mathrm{composition}}_e
=\sum_g \omega_g\sum_b
 (s^T_{gb}-s^C_{gb})\bar Y^C_{gbe}.
\]

Report the reverse decomposition using treated bin-specific paths:

\[
\widehat{\Delta}^{T,\mathrm{composition}}_e
=\sum_g \omega_g\sum_b
 (s^T_{gb}-s^C_{gb})\bar Y^T_{gbe}.
\]

Treat the two values as a sanity band because the decomposition is not
symmetric. This is descriptive accounting, not causal mediation.

### B1: primary discriminating reweighting

Add the symmetric group-level entry-bin shares to the `loyo_m3` calibration
while continuing to hold patent count and active patenting at \(t=-3\) out of
the balance set. This is the main test of whether recruitment composition
explains the failed held-out placebo.

Report the reweighted \(t=-3\) coefficient, its deal-wild-bootstrap interval,
weight diagnostics, and every other event-time coefficient. If recruitment
composition drives the spike, the held-out \(t=-3\) coefficient should move
toward zero. Do not call balance-constrained entry shares an independent
pretrend test.

Spell-end and spell-length constraints enter a separately labelled expanded
variant. The entry-only B1 result remains primary so that the test maps directly
to the stated mechanism.

### B2: P5a composition-only reweighting

Add symmetric group-level entry-bin constraints to P5a without adding annual
outcome balance. Preserve P5a's original support and non-annual constraints.
This test asks whether recruitment composition alone flattens the visible
\(t=-3\) lead.

Report entry-only and expanded entry/end/length versions under the same frozen
hierarchy. Do not promote a version because it produces a flatter path.

### B3: conditional extended sensitivities

Open B3 only if B0, B1, or B2 meets the frozen 0.010-patent materiality rule.
Regardless of whether B3 opens, B0-B2 remain reported.

If opened:

1. Recalibrate `count_active` on symmetric entry-bin shares. This tests movement
   in the post ATT and weight quality; it cannot diagnose the pre-path because
   all five pre-period outcomes remain exact balance constraints.
2. Estimate entry-stratified effects in one stacked regression with
   stratum-by-event-time interactions. Aggregate with treated stratum shares
   and obtain inference from one deal-level wild bootstrap on the combined
   contrast. Do not estimate separate stratum bootstraps and combine them as
   independent because strata share deals.
3. Co-report the existing \(g-7/g-6\) established-inventor result, clearly
   labelled as a different estimand.

## Weighting feasibility and certification

Apply the following hierarchy to every new solve, in this order:

1. exact balance at the existing solver's numerical tolerance;
2. approximate balance with maximum absolute SMD of 0.05 for the new
   recruitment-composition moments while preserving every original balance
   gate; and
3. record the cohort/specification as infeasible.

Do not merge bins, drop cohorts, drop strata, or relax support after seeing a
failure. Report all infeasible cells and support loss.

Reuse the shipped P5c concentration gates wherever a P5c parent is used:

- reuse-adjusted ESS ratio at least 0.50;
- absolute ESS-ratio loss no greater than 0.10 relative to the parent solve;
- reuse-adjusted maximum share no more than 25% above the parent solve; and
- positive, finite weights with treated weight and within-cohort treated/control
  mass identities preserved.

For P5a, freeze analogous parent-relative gates before running the solve. Every
weight package must report ESS, reuse-adjusted ESS, maximum and top-five weight
shares, retained inventor/deal counts, and moment residuals.

Certification must include mutation tooth tests that deliberately alter:

- one affiliation year;
- one company/group granularity flag;
- one entry-bin assignment;
- one input hash;
- one weight; and
- one cohort lookback depth.

Each mutation must cause the corresponding certification gate to fail.

## Firm-flow audit

Report counts and rates at the deal-stack level, not by pooling donor-firm
rows. A treated stack has one target-company set, whereas a control stack can
contain several donor groups. For both arms, state the denominator explicitly
and aggregate donor flows with the final within-stack weights.

Report:

- recruited inventor mass;
- new focal-affiliation mass by event year;
- entry rate relative to five-year focal inventor stock;
- last-focal-year/qualifying-gap composition; and
- observed focal-span composition.

Raw donor-pool counts are descriptive database totals and are not balance
statistics for the inventor-weighted ATT.

## Governance and interpretation

All frozen variants are co-reported. No design becomes preferred because its
ATT is larger, smaller, significant, or closer to the existing estimate.

Define a material change in the \(t=+1,\ldots,+5\) average ATT as an absolute
change of at least 0.010 patents per inventor-year relative to the parent
specification. This is fixed before opening any new ATT and is used only to
describe sensitivity, not to select a design.

Interpretation follows the evidence pattern:

- same-year entry imbalance plus a shift-share contribution of at least 0.010
  and attenuation of the held-out B1 coefficient supports a material
  recruitment-composition explanation for the \(t=-3\) spike;
- imbalance without same-year alignment does not fit the proposed mechanical
  channel;
- stable B1/B2 leads and stable post ATTs weaken the observable recruitment-
  composition explanation;
- a material post-ATT movement is reported as sensitivity of the full-cohort
  estimate, while both parent and amended estimates remain co-equal reported
  results; and
- stability of the early-recruitment estimand speaks only to established
  inventors.

These diagnostics address observed patent-affiliation composition. They do not
identify actual hiring dates or eliminate unobserved workforce changes.

## Deliverables

1. A pre-outcome freeze note with input and source hashes, thresholds, seeds,
   feasibility order, and the full reporting contract.
2. `recruitment_spell_measurement_audit.csv`, containing symmetric and as-is
   spell measures plus cohort lookback depth.
3. `recruitment_composition_balance.csv`, containing weighted and unweighted
   entry/end/span statistics by cohort and pooled with treated-cohort weights.
4. `recruitment_composition_firm_flows.csv`, containing deal-stack counts,
   rates, weights, and explicit denominators.
5. `recruitment_composition_calibration.csv`, containing required-versus-
   observed entry gaps and year alignment.
6. Two shift-share paths, using control and treated bin-specific paths, plus a
   compact sanity-band figure.
7. B0, B1, and B2 event-study tables and figures; B3 outputs only if the frozen
   gate opens.
8. A comparison table containing the parent and amended specifications,
   weight diagnostics, \(t=-3\) lead, and post ATT. Every frozen row appears.
9. A certification script with provenance checks, grain checks, invariants,
   mass reconciliation, and mutation tooth tests.
10. A short appendix subsection titled “Recruitment composition and inventor
    lifecycle,” which distinguishes patent affiliation from employment and
    separates the pre-path question from post-ATT sensitivity.
