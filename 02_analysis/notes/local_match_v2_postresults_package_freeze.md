# Local Match v2 — accepted post-results package freeze

Frozen on 2026-07-27 before implementing any new post-results estimate.

This note records the package sequence and the methodological decisions accepted
after the first P6 full-cohort results. It is additive: it does not overwrite the
P0-P5 design lock, the P5c annual-trajectory design, or the consolidated P6
pre-analysis freeze. Where the present note defines a new analysis, that analysis
must be labelled as post-results and reported independently of the frozen P5a
full-cohort ATT.

## 1. Terminology and the existing MECE construction

The headline stayer term is **initially retained inventors**. In technical
methods text, this means initially patent-retained inventors: employment cannot
be observed directly in patent records.

The project already contains two complementary constructions and must reuse
them:

1. `lmv2_treated_primary` records the first observed post-deal patent year in
   \(t=0,\ldots,+5\) and whether focal-entity evidence occurs in that year.
2. `cs2021_estimation_panel` assigns every inventor-year to exactly one of five
   annual states: `with_entity`, `moved_thirdparty`,
   `active_unknown_affiliation`, `inactive_silent_gap`, or `career_exited`.

No competing Cassi-Ornaghi stayer classification and no comparison among
multiple patent-derived affiliation definitions will be added.

For the new location analysis, first-year status is mutually exclusive:

- **initially retained**: focal-entity evidence and no outside-group evidence in
  the earliest observed post-deal patent year;
- **initially outside**: outside-group evidence and no focal-entity evidence in
  that year;
- **mixed/tied first year**: both focal-entity and outside-group evidence in
  that same earliest year;
- **no observed post-deal patent**: no patent in \(t=0,\ldots,+5\).

The existing P2 flag `stayer_focal_entity_first_post_t0_t5` is an input to this
partition, not by itself the final pure initially-retained indicator, because it
uses an at-least-one-focal-evidence rule.

Once classified, an initially retained inventor remains in that baseline cohort
even if later patents move outside the focal ecosystem. Later movement is an
outcome. Inventors whose every observed post-deal patent remains inside the
focal ecosystem may be shown as a **persistent-inside descriptive subgroup**,
but that subgroup is not the headline estimand because it conditions on the
entire future five-year path.

The no-post-patent category is not interpreted as employment exit. It includes
unobserved employment, movement into management, genuine career exit, and
patenting gaps that cannot be distinguished without employment data.

## 2. Scope decisions

- Deal 70 remains in the headline design. No bespoke no-deal-70 refit or
  donor-firm deletion exercise is part of the accepted package sequence.
- Henkel remains in the headline donor pool under the frozen IPC4 rule. There is
  no Henkel-omitted sensitivity.
- A generic all-deal influence diagnostic remains required so that dependence
  on any one deal is visible without selecting a special deletion after seeing
  results.
- IPC4 remains the agreed technology granularity.
- The full-cohort P5c/P6 ATT and the new initially-retained design are separate
  estimands. Restrictions based on observed post-deal patenting are descriptive
  or separately balanced analyses; they never replace the frozen full-cohort
  weights.

## 3. Package sequence and check-ins

Implementation stops after each package for review.

### Package 0 — stabilization and provenance

- map authoritative scripts and artifacts across the clean worktrees;
- certify the existing MECE and first-post interfaces;
- verify that provenance checks have teeth;
- add this hashed freeze without changing frozen P5/P6 results.

### Package 1 — pre-period diagnostics

- estimate the complete leave-one-pre-year-out grid over the five available
  pre-periods \(t=-5,\ldots,-1\);
- retain the full annual count and active-patenting trajectories in the
  constraints except for the held-out year in each LOYO arm;
- treat the full grid as appendix evidence, with special discussion of the
  previously problematic \(t=-3\);
- report equivalence against the predeclared \(\pm0.05\) patent-count margin,
  not merely failure to reject zero;
- report sign, inclusion in the headline 95% interval, maximum point deviation,
  and the full LOYO range;
- run treatment-timing \(\pm3\) placebos as appendix diagnostics where their
  construction is valid.

The original P5a pretrend test remains the non-mechanical formal diagnostic.
The P5c joint test is not presented as a falsification test because constrained
pre-period means are mechanically balanced.

### Package 2 — common-support selection

- produce the supported-versus-unsupported descriptive table;
- report the frozen supported share and the characteristics of the unsupported
  tail;
- retain the identity
  \[
  ATT_{\mathrm{all}}
  =p\,ATT_{\mathrm{supported}}
   +(1-p)\,ATT_{\mathrm{unsupported}}
  \]
  for transparent sensitivity calculations;
- keep any cardinality-recovered ATT separate from the entropy-balanced primary
  ATT.

### Package 3 — location bridge

- build the mutually exclusive first-year categories in Section 1;
- track the existing five annual MECE states through \(t=0,\ldots,+5\);
- report first outside destination and the timing of later movement for
  initially retained inventors;
- report persistent-inside inventors descriptively only;
- if unresolved affiliation exceeds 15% in a reported cell, label that
  decomposition uninformative rather than treating missing location as inside
  or outside.

This package describes how initially retained inventors behave over time. It
does not attempt to recover nonpatenting employment.

### Package 4 — forward-citation construction audit

Before opening citation ATTs, compare the Cassi-Ornaghi `fwCit5w` measure with
the OECD construction on:

- time anchor and five-year window;
- patent-family construction;
- inventor/co-inventor attribution;
- complete linked subsets and calendar-year coverage;
- zero versus missing treatment.

If `fwCit5w` has a valid definition and materially better coverage, it becomes
the leading five-year forward-citation source. OECD remains a separately
reported secondary source. Source selection is based on construction and
coverage, never on which ATT is more favourable.

Citation totals are estimated at inventor-year level for the inventor ATT.
Patent-level analyses may diagnose attribution or conditional quality but do
not replace the inventor-level estimand.

### Package 5A — initially-retained P5b design

- construct a separately balanced design for initially retained inventors;
- use the accepted five-pre-period annual-trajectory machinery;
- run the complete LOYO grid before opening outcomes;
- report balance, support, ESS, reuse, and deal influence;
- do not reuse full-cohort weights after conditioning on initial retention.

### Package 5B — initially-retained outcomes

- estimate patent count, active patenting, quality, TechDrift, and the frozen
  citation measures only after Package 5A is certified;
- retain \(t=+5\) as the comparable main horizon and show the 1994-2008
  censoring-clean companion;
- use deal-level wild-bootstrap inference as headline and prominent two-way
  deal/inventor clustering; rely on the more conservative interval if they
  differ materially;
- precheck Lee-bound width and label bounds uninformative if the width exceeds
  four times the absolute point estimate before undertaking costly bootstrap
  work.

### Packages 6–8

- Package 6: full-cohort location, destination, and any-post-patent companion
  analyses.
- Package 7: consolidate remaining citation and P6 robustness outputs.
- Package 8: clean the repository only after the empirical packages are
  certified; then begin DealSim heterogeneity as a separate workstream.

## 4. Interpretation discipline

The any-post-patent and initially-retained analyses are useful comparisons with
studies that require post-treatment patent observation, but they condition on a
post-treatment event. They are not substitutes for the full-cohort causal ATT.
The paper must state that proportional effects are more comparable with those
studies than absolute patent losses because the full cohort contains many
inventors with zero post-deal patents.

Active patenting is interpreted as the extensive margin of observed patent
production, not employment retention. Citation nulls are interpreted together
with linkage, skewness, and attribution diagnostics. The five-year horizon
captures early organisational effects and not the full pharmaceutical R&D
pipeline.

