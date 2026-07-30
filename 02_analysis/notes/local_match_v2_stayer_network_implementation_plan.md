# Local Match v2: stayer and knowledge-network implementation plan

Status: C1, C2, D1, and N0 completed and certified; N0 selects Path Q
Date: 2026-07-29

This document converts the remaining stayer and knowledge-network work into
independent implementation packages. Each package ends with a certification
and a review point. A later package must not begin until the preceding
package's exit gate has been reviewed.

## 1. Frozen empirical hierarchy

The implementation must preserve the following hierarchy.

1. The predetermined full pre-deal target-inventor cohort is the causal
   anchor.
2. Initially retained inventors form a separately balanced,
   post-treatment-selected population. Their results corroborate and
   anatomize the full-cohort result; they are not an always-retained
   principal-stratum effect.
3. The frozen retained patent-count estimate remains:
   `ATT = -0.1072306`, two-way deal/inventor 95% interval
   `[-0.2043392, -0.0101220]`, and `p = 0.0306763`.
4. The 1994--2010 estimate remains primary. The buffered 1994--2008 estimate
   is a sign-stability companion and will not replace the primary estimate
   post hoc.
5. P8 is the authoritative decomposition. The older retained 29.8/70.2 and
   32.5/67.5 decompositions must not appear in main-text assets.
6. The full-cohort patenting-cessation result carries the principal
   substantive extensive-margin claim. Retained cessation is descriptive
   because the retained population is defined using patenting in +1 through
   +5.
7. Knowledge-network effects may be estimated only after an outcome-blind
   census and a frozen pretrend/precision gate.
8. The retained-control endpoint filter is not part of the full-cohort P5c
   design. A separately labelled full-cohort diagnostic applying
   `NOT control_firm_exits_before_g_plus_5` must therefore be estimated before
   attributing the retained/full-cohort estimate gap to inventor retention.

## 2. Common implementation rules

Every new package must:

- run from the thesis root with the project R installation;
- use the certified Local Match v2 support and weights without silently
  rematching;
- write derived data to `02_analysis/output/audit/local_match_v2/`;
- write reportable tables and figures to
  `02_analysis/output/results/local_match_v2/`;
- write a machine-readable certification table containing `check`, `pass`,
  `value`, and `detail`;
- write a source-and-artifact manifest containing normalized paths, hashes,
  byte sizes, and creation times;
- fail on missing inputs, duplicated keys, non-finite weights, or failed
  upstream certification;
- preserve full precision in machine-readable files and round only in
  thesis-facing assets;
- distinguish `zero`, `not observed`, `not at risk`, and `right-censored`;
- never interpret a patent affiliation as an employment record;
- avoid modifying a frozen upstream result merely to improve a downstream
  gate.

Package completion means:

1. the runner exits with status zero;
2. every required certification check passes;
3. a clean-session rerun reproduces hashes for deterministic outputs;
4. the results note states the estimand, population, limitations, and release
   decision;
5. the package is reviewed before the next package begins.

## 3. Execution map

```text
C1 results synchronization
  -> C2 reproducible release runner
  -> D1 descriptive stayer completion
  -> N0 outcome-blind network census and freeze
  -> N1 pretrend/precision gate
       -> Path N: N2 full-cohort network effects
                     -> N3 retained-network companion, if separately powered
                     -> N4 optional treated-only team recomposition
       -> Path Q: report feasibility/precision limit; do not estimate effects
       -> Path F: report failed validation; stop network analysis
  -> W1 thesis integration
```

N3 and N4 are not prerequisites for a complete thesis. N2 is a contribution
upgrade conditional on N1. C1, C2, D1, N0, N1, and W1 are the planned core
work.

## 4. Package C1: synchronize results and documentation

Implementation status: completed. The governing certification is
`CURRENT_LOCAL_MATCH_V2/results_inventory/C1_RESULTS_SYNC_CERTIFICATION.csv`.
It passes the inventory, control-endpoint, P8, supervisor-package,
active-document, manuscript-authority, and displayed-value checks.

### Objective

Create one authoritative value, source, and interpretation for every current
stayer, exit, secondary-outcome, and heterogeneity result.

### Existing files to modify

- `02_analysis/R/33e_report_certify_lmv2_stayer_heterogeneity.R`
- `02_analysis/R/34_build_lmv2_master_results_inventory.R`
- `02_analysis/R/34a_run_lmv2_control_endpoint_diagnostic.R` (new)
- `02_analysis/R/34b_validate_lmv2_reported_values.R` (new)
- the active `00_Discussion_Docs/012_*.tex` handover, or its replacement
- `02_analysis/R/39_build_lmv2_exit_decomposition_thesis_assets.R`
- `02_analysis/R/27a_build_lmv2_supervisor_package.R`
- `02_analysis/notes/current_local_match_v2_start_here.md`
- `02_analysis/notes/local_match_v2_master_results_inventory.md`

The correction in `33e` defining initial retention over +1 through +5 has
already been implemented and regenerated.

### Inputs

- certified P5b retained-support and retained-effect outputs;
- P7 retained heterogeneity outputs;
- P8 full-cohort and retained decomposition outputs;
- full-cohort, retained, and recurrent exit packages;
- 2,000-draw untreated-firm placebo outputs;
- PQII, TechDrift, and forward-citation diagnostics;
- all package certification and manifest files.

### Implementation steps

1. Extend the inventory input map in `34` to include every P8 and later
   certified result.
2. Add an explicit `status` field with allowed values:
   `primary`, `companion`, `appendix`, `descriptive`, `failed_gate`,
   `superseded`, and `not_run`.
3. Add fields for population selection, governing inference, sample window,
   pretrend/sign-stability qualification, and main-text eligibility.
4. Record the retained full-window and buffered estimates separately.
5. Mark the two older retained decompositions `superseded`.
6. Mark the P8 three-factor decomposition `primary_descriptive_anatomy`.
7. Retain the exact two-way retained estimate and record the wild-bootstrap
   result as sensitivity inference.
8. Add the full-window sign-breakdown ratio `0.946` and buffered ratio
   `1.407`.
9. Regenerate the human-readable inventory from the CSV rather than editing
   it manually.
10. Update thesis assets so only P8 appears in the main decomposition table.
11. Remove the detailed persistent-team/Holm discussion from the main
    supervisor narrative; retain the complete multiplicity table in the
    appendix.
12. Inventory every `00_Discussion_Docs/012_*.tex` handover. Either update the
    current partner-facing handover to P8 or place an older version on an
    explicit frozen-historical list that cannot be confused with current
    results.
13. Resolve and record the authoritative thesis manuscript path in the
    machine-readable inventory and `START_HERE` note.
14. Add a separately labelled full-cohort diagnostic that re-estimates the
    P5c patent-count effect after excluding controls whose focal group exits
    before +5. This is a sample-definition diagnostic, not a replacement
    primary specification.
15. Implement `34b_validate_lmv2_reported_values.R`. It must parse active
    generated notes, handovers, and thesis assets for declared result tokens,
    join those tokens to the master inventory, and fail on an unknown token,
    a mismatched value, an active superseded token, or a reportable inventory
    row without a declared source.
16. Rebuild all affected manifests and certification hashes.

### Required checks

- unique key across population, outcome, analysis, sample, and reporting tier;
- no two active primary values for one estimand;
- every inventory row points to an existing certified source;
- exact reconstruction of `-0.1072306`;
- only the P8 decomposition is main-text eligible;
- no active note says retention begins at event time zero;
- all generated tables agree with the authoritative inventory;
- every active handover and thesis asset passes `34b`;
- historical handovers are explicitly excluded by a frozen path manifest;
- the authoritative manuscript path exists and is unique;
- the endpoint-filter diagnostic cannot overwrite the frozen P5c estimate.

### Outputs

- refreshed `master_results_inventory.csv`;
- refreshed inventory certification and source manifest;
- refreshed `local_match_v2_master_results_inventory.md`;
- corrected supervisor tables and narrative;
- regenerated stayer and exit-decomposition thesis assets;
- full-cohort control-endpoint diagnostic and comparison table;
- active-document and historical-document manifests;
- reported-value consistency log;
- `C1_RESULTS_SYNC_CERTIFICATION.csv`.

### Exit gate

C1 passes when `34b_validate_lmv2_reported_values.R` certifies that every
declared numeric result in the active-document manifest agrees with exactly
one certified inventory row, every superseded result is absent from active
assets, and every reportable table can be traced to a certified source.

## 5. Package C2: reproducible current-release runner

### Implementation status

Completed on 2026-07-30. The root runner, source/environment inventory,
dependency verifier, clean-session smoke test, legacy-runner guard,
production assembly, and compact staging-handoff builder pass. The source set
was committed and fast-forwarded into `main-did-v1` at `356c159`, then pushed
to GitHub. The certified handoff excludes the 2.6 GB database binary.

### Objective

Make the authoritative analysis reproducible from the root repository without
requiring knowledge of the worktree in which a result was developed.

### Proposed files

- `02_analysis/R/41_run_lmv2_current_release.R`
- `02_analysis/R/41a_inventory_lmv2_release_sources.R`
- `02_analysis/R/41b_verify_lmv2_release_dependencies.R`
- `02_analysis/R/41c_build_lmv2_current_handoff.R`
- `02_analysis/R/41d_smoke_lmv2_current_release.R`
- `02_analysis/notes/local_match_v2_current_release_implementation.md`

### Implementation steps

1. Enumerate the authoritative P0--P8 scripts and immutable inputs.
2. Compare worktree and root versions by hash.
3. Integrate authoritative scripts through git, not filesystem copying:
   first commit the analysis worktree, then either commit the root changes or
   preserve them in a named stash, and only then merge or cherry-pick the
   reviewed worktree commits. Abort on overlapping uncommitted paths.
4. Create a dependency manifest containing R version, package versions,
   expected database hash, and required external commands.
5. Implement runner modes:
   - `--verify`: paths, dependencies, hashes, and certifications only;
   - `--smoke`: small deterministic builds and all lightweight reports;
   - `--production`: complete released pipeline;
   - `--handoff-only`: rebuild the handoff from certified outputs.
6. Require an explicit failure if the old pipeline is invoked as though it
   were Local Match v2.
7. Rebuild `CURRENT_LOCAL_MATCH_V2` from a declared include list.
8. Include P8 and all post-P8 diagnostics, current notes, source scripts,
   manifests, and thesis assets.
9. Write a single `START_HERE.md` with the root command and package map.

### Required checks

- all included scripts match the source manifest;
- no current output depends on an undeclared worktree path;
- smoke mode can run from a clean R session;
- the handoff contains no stale duplicate result presented as current;
- handoff inventory and root inventory hashes agree;
- production mode cannot overwrite frozen inputs.

### Outputs

- root release runner;
- environment and source manifests;
- smoke log and certification;
- rebuilt `CURRENT_LOCAL_MATCH_V2`;
- new partner/supervisor handoff.

### Exit gate

A collaborator starting from the root repository can execute one documented
command and reach the same certified inventory and current thesis assets.

## 6. Package D1: complete descriptive stayer evidence

### Implementation status

Completed and certified on 2026-07-30. The package reports the three status
distributions, annual +1 through +5 patent-location paths, persistence through
+3 and +5, a weighted treated/control persistence rider, symmetric
endpoint-existence diagnostics, descriptive +6 continuation, and the
completion-year-inclusive timing results. All 25 certification checks pass.

### Objective

Finish the descriptive facts required to interpret initial retention,
selection, persistence, and patent-record disappearance.

### Proposed files

- `02_analysis/R/42_run_lmv2_stayer_descriptives.R`
- `02_analysis/R/42a_lmv2_stayer_descriptives_config.R`
- `02_analysis/R/42b_build_lmv2_stayer_status_paths.R`
- `02_analysis/R/42c_analyze_lmv2_stayer_distributions.R`
- `02_analysis/R/42d_report_certify_lmv2_stayer_descriptives.R`
- `02_analysis/notes/local_match_v2_stayer_descriptive_results.md`

### Inputs

- certified S0--S2 first-post status partition;
- canonical inventor-year and inventor-group-year panels;
- global career endpoints from P8;
- deal years and focal/acquirer group mappings;
- P5b support only for clearly labelled retained-design summaries.

### Implementation steps

1. Freeze status definitions before computing tables.
2. Construct pre-deal career age and five-year patent stock for:
   - initially retained;
   - leaver;
   - no observed post-deal patent.
3. Report mean, standard deviation, p10, p25, median, p75, p90, and sample
   size.
4. Report standardized differences and distribution tests, with effect sizes
   taking precedence over mechanical large-sample significance.
5. Assess whether the no-post-patent population is materially more senior,
   as required by the management-transition diagnostic.
6. For every initially retained inventor and each year +1 through +5, create
   one mutually exclusive state:
   - focal/acquiring group only;
   - outside group only;
   - both focal and outside;
   - no patent this year but a later patent is observed;
   - end of observed patenting;
   - right-censored/not observable.
7. Construct persistent-inside indicators through +3 and +5.
8. Audit treated and control focal-group patent activity at +5.
9. Where calendar support permits, report descriptive +6 activity without
   changing the original cohort or requiring a +6 patent for inclusion.
10. Reconcile the annual states to S0--S2 and P8 global career endpoints.
11. Include event time zero as the merger-completion-year effect. Report it
    separately from the +1 to +5 full-calendar-year average and add it to the
    completion-through-+5 cumulative effect. State that timing is
    observed only by year, so t=0 cannot be split into pre- and
    post-completion months.

### Required checks

- annual states are mutually exclusive and exhaustive;
- annual state shares sum to one within numerical tolerance;
- no event-year patent determines initial retention;
- +6 is used only as an endpoint diagnostic, never as an inclusion rule;
- career-age calculations use only information available by event time -1;
- right-censoring is separated from career end;
- patent location is never labelled employment.

### Outputs

- full career-age/productivity distribution table;
- management-transition diagnostic;
- annual patent-location transition table;
- persistent-inside path figure;
- +5 endpoint and descriptive +6 audit;
- certification and manifest.

### Exit gate

D1 passes when all status paths reconcile and the thesis can state precisely
who is called an initial stayer, how selected that group is, and how often
initial patent-based retention persists.

## 7. Package N0: freeze network definitions and run outcome-blind census

### Implementation status

Completed and certified on 2026-07-30. All 20 construction and process checks
pass, but the frozen support gate selects Path Q. The -5 through -3 anchor
retains 2,230 treated focal inventors across 173 nominal and 33.3 effective
deals. It misses the 3,000-inventor threshold. Conditional composition is
defined for 745 treated rows at -2 and 557 at -1, below the frozen 1,000-row
minimum; control concentration also exceeds the symmetric frozen limits.
N1 and post-treatment network estimation remain closed.

### Objective

Determine whether collaboration-network analysis is feasible and freeze the
network estimands before any post-acquisition effect is opened.

### Proposed files

- `02_analysis/R/43_run_lmv2_network_census.R`
- `02_analysis/R/43a_lmv2_network_freeze_config.R`
- `02_analysis/R/43b_build_lmv2_predeal_dyads.R`
- `02_analysis/R/43c_census_lmv2_network_support.R`
- `02_analysis/R/43d_certify_lmv2_network_census.R`
- `02_analysis/notes/local_match_v2_network_preanalysis_freeze.md`
- `02_analysis/notes/local_match_v2_network_census_results.md`

### Frozen primary population

The certified P5c full pre-deal target-inventor cohort, restricted to focal
inventors with at least one persistent baseline collaborator.

The P5b initially retained cohort is secondary and must not determine the
full-cohort network definition.

### Frozen anchor

1. Baseline anchor: -5 through -3.
2. Validation leads: -2 and -1.
3. If this definition lacks support, report infeasibility and stop. Do not
   reach outside the frozen P5c pre-period to event time -6.

A persistent baseline tie requires:

- at least two distinct joint patent applications; and
- joint patenting in at least two distinct anchor years.

Event time zero and all positive event times are inaccessible to N0 code.

### Primary network outcomes to freeze

1. **Collaborator focal-organization persistence share:** among persistent
   baseline collaborators who are observable and at risk in the evaluation
   year, the fraction patent-active in the relevant focal organization. This
   is the governing primary outcome because it is defined by the partner's
   behavior rather than the focal inventor's patent count.
2. **Legacy-collaborator composition share:** among distinct collaborators
   observed with the focal inventor in an evaluation period, the fraction who
   are persistent baseline collaborators. Define this outcome only when the
   focal inventor has at least one co-invented patent in that period.
3. **Legacy-link composition share:** among all focal-inventor collaborator
   link-instances in an evaluation period, the fraction involving persistent
   baseline collaborators. A collaborator on two distinct applications
   contributes two link-instances. Define this outcome only when the focal
   inventor has at least one co-invented patent.

The original baseline-tie recurrence share and collaborator-set Jaccard are
retained only as secondary quantity-sensitive diagnostics. Both can fall
mechanically when the focal inventor patents less, even without
organizational disruption. They must not govern the network claim.

For every outcome, the freeze must define the numerator, denominator,
partner-at-risk rule, treatment of solo patents, annual versus pooled
aggregation, zero cases, missing cases, and right-censoring.

### Economically meaningful effect and precision rule

Before N1 estimation, freeze an absolute five-percentage-point change
(`0.05` on the share scale) as the smallest main-text-relevant effect for each
primary outcome. N1 passes the precision component only if its governing MDE
is no larger than `0.05`. This threshold may be revised during N0 only on
substantive grounds written before validation outcomes are computed; support,
realized standard errors, and validation estimates cannot justify a revision.

### Implementation steps

1. Build one unique undirected inventor dyad per patent application.
2. Eliminate self-links and duplicate inventor names on an application.
3. Map applications to event time using the focal inventor's deal.
4. Build persistent ties using anchor-period information only.
5. Attach P5c treated and weighted-control support without rematching.
6. Produce inventor-, deal-, and cohort-level coverage tables.
7. Calculate effective treated and control deal counts under frozen weights.
8. Document the coverage cost of the single -5 through -3 anchor.
9. Freeze the `0.05` meaningful-effect threshold.
10. Write and hash the freeze before N1.

### Feasibility thresholds to review and freeze

- at least 3,000 treated full-cohort focal inventors with a persistent tie;
- at least 150 nominal treated deals;
- effective treated deals at least 20;
- no single deal dominates the weighted tie sample;
- symmetric treated/control construction;
- sufficient validation-period observability for all three primary outcomes.

Support-threshold revisions are permitted only during N0, must use support
data only, and require a written amendment. The meaningful-effect threshold
may not be revised in response to support, realized precision, or validation
estimates.

### Required checks

- unique application-inventor and application-dyad keys;
- dyad symmetry;
- no post-event input is read;
- anchor and validation windows do not overlap and both stay inside -5:-1;
- baseline-tie definition is identical for treated and controls;
- deal and inventor weights reconcile to P5c;
- complete denominator audit for all shares.

### Outputs

- frozen network design;
- baseline dyad and focal-inventor census;
- coverage and concentration tables;
- single-anchor support decision;
- frozen meaningful-effect declaration;
- construction fixtures, certification, and manifest.

### Exit gate

N0 releases N1 only if the frozen anchor passes the support gate. N0
never releases post-treatment effect estimation. The certified census selects
Path Q, so N1 is not released.

## 8. Package N1: network validation and precision gate

### Objective

Use only pre-acquisition validation periods to decide whether opening network
effects would be credible and informative.

### Proposed files

- `02_analysis/R/44_run_lmv2_network_validation.R`
- `02_analysis/R/44a_materialize_lmv2_network_validation_panel.R`
- `02_analysis/R/44b_estimate_lmv2_network_leads.R`
- `02_analysis/R/44c_compute_lmv2_network_mde.R`
- `02_analysis/R/44d_falsify_lmv2_network_design.R`
- `02_analysis/R/44e_report_certify_lmv2_network_gate.R`
- `02_analysis/notes/local_match_v2_network_validation_results.md`

### Implementation steps

1. Lock and verify the N0 freeze hash.
2. Materialize only anchor and negative-event-time network measures.
3. Apply P5c weights without new selection or rebalancing.
4. Estimate every available held-out lead for all three primary outcomes.
5. Report individual lead intervals and a joint lead test.
6. Define equivalence bands before examining estimates.
7. Calculate deal-wild and two-way minimum detectable effects.
8. Calculate effective deal counts and influence diagnostics.
9. Run unit fixtures with known partner-persistence, composition-share,
   recurrence, and Jaccard values.
10. Run the untreated-firm pseudo-event falsification. Failure to construct
    or pass it is a failed gate; the falsification is not optional.
11. Produce one deterministic path decision.

### Gate to freeze before estimation

The provisional release rule is:

- no validation lead has an absolute gap above 0.05 on a share scale;
- the joint validation-lead test does not reject at 10%;
- validation-lead intervals satisfy the frozen equivalence criterion;
- the MDE is no larger than the frozen economically meaningful effect;
- effective treated deals remain at least 20;
- the mandatory untreated-firm falsification is constructed and passes its
  frozen criterion;
- no unresolved construction failure exists.

### Path decision

- **Path N:** all governing validity and precision gates pass; N2 may run.
- **Path Q:** construction and validation are acceptable but precision is
  inadequate; report feasibility and stop without post effects.
- **Path F:** construction, validation, or falsification fails; report the
  failed design and stop.

### Outputs

- validation-lead table and plot;
- equivalence and joint-test results;
- MDE/power table;
- influence and falsification diagnostics;
- signed gate decision, certification, and manifest.

### Exit gate

Only a certified Path N permits N2 to access positive event times.

## 9. Package N2: full-cohort network effects

### Condition

Implement only after N1 certifies Path N.

### Objective

Estimate whether acquisitions disrupt predetermined collaboration networks
for the full pre-deal target-inventor cohort.

### Proposed files

- `02_analysis/R/45_run_lmv2_network_effects.R`
- `02_analysis/R/45a_materialize_lmv2_network_post_panel.R`
- `02_analysis/R/45b_estimate_lmv2_network_effects.R`
- `02_analysis/R/45c_decompose_lmv2_collaborator_destinations.R`
- `02_analysis/R/45d_report_certify_lmv2_network_effects.R`
- `02_analysis/notes/local_match_v2_network_effect_results.md`

### Implementation steps

1. Verify N0 and N1 hashes and Path N.
2. Materialize +1 through +5 outcomes using the frozen definitions.
3. Estimate dynamic effects for the three primary outcomes.
4. Estimate the average +1 through +5 effect.
5. Use two-way deal/inventor inference as governing because network outcomes
   repeat within inventors and deals. Report deal-wild inference as the
   transparent cluster-sensitivity companion.
6. Estimate the buffered 1994--2008 companion without changing its status.
7. Apply Holm adjustment across the three primary outcomes in the appendix.
8. Decompose lost baseline collaborators into:
   - remains in focal organization but tie does not recur;
   - patents outside the focal organization;
   - reaches the end of observed patenting;
   - right-censored or unresolved.
9. Create thesis-ready plots and tables.

### Required checks

- frozen definitions and support hashes match N0/N1;
- no rematching or post-outcome sample adaptation;
- shares stay in their natural bounds;
- aggregate and dynamic effects reconcile;
- collaborator destinations are mutually exclusive and exhaustive;
- raw, governing, and multiplicity-adjusted inference are all preserved;
- decomposition is described as accounting evidence, not causal mediation.

### Outputs

- network event-study figure;
- main network-effect table;
- buffered companion table;
- collaborator-destination decomposition;
- appendix multiplicity table;
- certification and manifest.

### Exit gate

N2 enters the main thesis only if the result remains credible under the
frozen gate and governing inference. A null result remains a valid result and
must not trigger a redefinition of ties or outcomes.

## 10. Package N3: retained-inventor network companion

### Condition

Begin only after N2 certification and a separate retained-sample power gate.

### Objective

Assess network preservation within the selected initially retained population
using certified P5b support and weights.

### Proposed files

- `02_analysis/R/46_run_lmv2_retained_network.R`
- `02_analysis/R/46a_census_lmv2_retained_network_support.R`
- `02_analysis/R/46b_gate_lmv2_retained_network_power.R`
- `02_analysis/R/46c_estimate_lmv2_retained_network_effects.R`
- `02_analysis/R/46d_report_certify_lmv2_retained_network.R`

### Implementation steps

1. Reuse the frozen N0 tie and outcome definitions.
2. Intersect them with certified P5b support without rematching.
3. Report retained tie coverage, effective deals, and MDEs.
4. Freeze the retained release rule.
5. Estimate effects only if the retained rule passes.
6. Otherwise report treated paths and feasibility descriptively.

### Expected constraint

The existing -5 through -1 definition contains about 1,058 retained treated
inventors with a persistent tie. The narrower -5 through -3 anchor will
materially reduce this count. Path Q (valid construction but inadequate
precision) is therefore the base case for N3, not a remote contingency, and
is an acceptable reason not to estimate a retained network ATT.

### Exit gate

The package must choose between a certified selected-group effect and a
certified feasibility-only result. It must not weaken the tie definition
after seeing an MDE or effect.

## 11. Package N4: optional team recomposition appendix

### Objective

Describe with whom initially retained inventors collaborate after acquisition.
This is a mechanism-oriented descriptive package, not a causal design.

### Proposed files

- `02_analysis/R/47_run_lmv2_team_recomposition.R`
- `02_analysis/R/47a_classify_lmv2_postdeal_collaborators.R`
- `02_analysis/R/47b_analyze_lmv2_team_recomposition.R`
- `02_analysis/R/47c_report_certify_lmv2_team_recomposition.R`

### Collaborator categories

- legacy target collaborator;
- legacy acquirer collaborator;
- entirely new collaborator;
- outside-group collaborator.

### Optional associations

- legacy-tie loss with patent count, total PQII, and TechDrift;
- new-acquirer ties with patent count, total PQII, and TechDrift.

### Guardrails

- treated-only and post-post association labels must be prominent;
- no mediation or mechanism-proof language;
- deal and event-time fixed effects plus predetermined controls;
- full multiple-testing disclosure;
- appendix placement unless a separate symmetric design is developed.

### Exit gate

N4 is complete when the categories reconcile and every table is labelled
descriptive. It may be skipped without weakening the core thesis.

## 12. Package W1: thesis integration

### Objective

Build the final retained-inventor and knowledge-network section from certified
assets only.

### Proposed file

- `02_analysis/R/48_build_lmv2_stayer_network_thesis_assets.R`

The package will edit the authoritative thesis `.tex` file recorded and
certified during C1. W1 must fail rather than search for or guess a manuscript
path.

### Main-text order

1. Full-cohort quantity and patenting-cessation anchor.
2. Dynamic shape: report the monotone attenuation in absolute patent-count
   effects from t=+1 through +5 in both the frozen P5c path and the
   control-endpoint diagnostic. Interpret the repetition as consistent with
   temporary integration disruption, not as a mechanism proof and not as
   sufficient evidence to exclude portfolio rationalization.
3. Definition and selection of initially retained inventors.
4. Retained patent-count estimate, exact two-way interval, and wild
   sensitivity.
5. Full-window sign-stability limitation and buffered companion.
6. Retained quantity, PQII, TechDrift, and P8 anatomy.
7. Career-age, management-transition, and persistence diagnostics.
8. Full-cohort network result if N2 passes.
9. Retained or treated-only network evidence only as secondary evidence.

The t=0 coefficient belongs in the main event-study narrative as a
merger-completion-year effect. Keep the +1 to +5 average as the comparable
full-calendar-year flow estimand, and report a separate cumulative effect that
includes t=0. State that exposure in the completion year is partial because
the data are annual.

### Target length

- retained-population definition and selection: 1.0--1.5 pages;
- retained quantity, quality, TechDrift, and decomposition: 2.0--2.5 pages;
- persistence and career-age diagnostics: 0.75--1.0 page;
- full-cohort network evidence, if released: 2.0--2.5 pages;
- limitations and interpretation: 0.5 page.

Expected total: approximately 4.5 pages without a released network result and
6.5--8 pages with a released network result, excluding appendix material.

### Required checks

- every number resolves to the master inventory;
- the retained two-way estimate remains in full;
- selection and sign-stability limitations appear adjacent to the retained
  estimate;
- old decomposition values do not appear;
- the detailed team/Holm result is absent from the main text;
- causal language is reserved for the supported full-cohort design;
- the five-year scope condition is explicit;
- all tables and figures compile and render cleanly.

### Outputs

- final section text;
- thesis-ready tables and figures;
- appendix tables;
- generated-values file;
- asset manifest and compilation certification.

## 13. Package review protocol

At the end of each package, deliver:

1. a two-paragraph substantive result summary;
2. the certification table;
3. a list of files created or changed;
4. any failed checks or deviations from the plan;
5. the exact decision required before beginning the next package.

No package should silently spill into the next one. In particular:

- C1 must not begin new estimation;
- D1 must remain descriptive;
- N0 must not read post-treatment outcomes;
- N1 must not estimate post-treatment effects;
- N2 must not run without Path N;
- N3 must not run merely because N2 is interesting;
- N4 must not be presented as causal.

## 14. Immediate next action

Review the certified D1 bundle and its interpretation. If accepted, begin N0
with an outcome-blind network census and freeze; do not estimate any
post-treatment network effect during N0.
