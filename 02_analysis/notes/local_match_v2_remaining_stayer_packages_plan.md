# Local Match v2: remaining retained-inventor and network packages

Status: implementation plan frozen for sequencing, but not yet a
network-outcome pre-analysis freeze. No new network post-treatment outcome has
been opened.

C1 and C2 are complete. C2 was committed, integrated into `main-did-v1`,
production-certified from a clean worktree, and pushed to GitHub at commit
`356c159`. Package D1 is the active next package.

Date: 2026-07-29

The executable file-level implementation plan, including proposed scripts,
inputs, validation checks, exit gates, and package handoffs, is
`local_match_v2_stayer_network_implementation_plan.md`.

## 1. Governing interpretation

The full pre-deal target-inventor cohort remains the causal anchor. The
initially retained comparison is a separately supported and entropy-balanced
selected-group comparison. It is not an always-retained principal-stratum
effect.

The retained-control construction is deliberately symmetric. Both arms
condition on a first patent in event time +1 through +5 that remains attached
to the relevant focal group. Candidate control groups must also remain
patent-active through the end of the +5 window. This confirms that the
comparison group still exists at the end of follow-up in the patent-based
operational sense and remains at risk of patenting in +6 or later; it does not
require an observed patent in +6.

The frozen full-window retained estimate remains:

- annual patent-count contrast: -0.1072306;
- two-way deal/inventor 95% interval: [-0.2043392, -0.0101220];
- two-way p-value: 0.0306763;
- deal-wild sensitivity interval: [-0.2244100, 0.0152509];
- deal-wild p-value: 0.0809081.

The full 1994--2010 estimate remains the frozen primary result. Its held-out
t=-3 patent-count gap is +0.1133285, implying an absolute sign-breakdown ratio
of 0.946. The buffered 1994--2008 companion has an estimate of -0.1204541, a
t=-3 gap of +0.0856217, and a ratio of 1.407. The buffered result is therefore
the more reassuring sign-stability companion, but it is not promoted
post hoc to replace the frozen primary sample.

The retained estimate must be presented as corroborating the full-cohort
quantity result and describing the retained population's anatomy. Its
magnitude is not cleanly separable from the largest held-out pre-period
discrepancy under the paper's own descriptive calibration.

## 2. Decomposition hierarchy

The P8 three-factor Shapley decomposition supersedes the two older
retained-inventor decomposition tables for main-text reporting.

For the 1994--2010 initially retained population:

- earlier end of observed patenting: -0.0293086, 27.3%;
- active years among patenting survivors: -0.0057414, 5.4%;
- patents per active year: -0.0721806, 67.3%;
- total: -0.1072306.

The first two components sum to -0.0350501, which reconciles with the
two-factor symmetric extensive component (-0.0349107) up to the documented
decomposition ordering difference. The older 29.8/70.2 delta-method table and
the generated 32.5/67.5 table are retired from main-text use rather than shown
beside P8.

The retained population is itself defined by patenting in +1 through +5.
Consequently, "earlier end of observed patenting" inside the same window is
partly mechanical. Symmetric construction mitigates but does not eliminate
this issue. The retained cessation share is therefore descriptive and
secondary; the full-cohort cessation decomposition carries the stronger
substantive claim.

## 3. Package sequence

### Package C1: Documentation and results synchronization

Purpose: remove stale or contradictory reporting before any new analysis.

Status: completed and certified on 2026-07-29. Governing gate:
`CURRENT_LOCAL_MATCH_V2/results_inventory/C1_RESULTS_SYNC_CERTIFICATION.csv`.

Tasks:

1. Correct every active statement that says initial retention begins at t=0;
   the production definition is +1 through +5.
2. Add the retained sign-breakdown calibration to current results notes.
3. Mark P8 as the main decomposition and retire the two older main-text
   decompositions.
4. Refresh the master results inventory to include:
   - retained PQII, TechDrift, and citation diagnostics;
   - P8 full-cohort and retained decompositions;
   - full-cohort, retained, and recurrent patenting-exit contrasts;
   - the 2,000-draw untreated-firm placebo;
   - failed or omitted analyses with explicit status.
5. inventory `00_Discussion_Docs/012_*.tex`, update the active partner
   handover to P8, and explicitly mark older handovers historical;
6. record the unique authoritative thesis manuscript path;
7. run a separately labelled full-cohort P5c diagnostic excluding controls
   whose focal group exits before +5;
8. implement a scripted active-document consistency check that parses
   declared result tokens and fails on any disagreement with the inventory;
9. rebuild generated thesis tables and manifests from the refreshed inventory.

Gate:

- one unique current value and interpretation for every reported estimand;
- no stale two-factor retained decomposition in main-text assets;
- all source hashes and certification references resolve;
- every active note, handover, and thesis asset passes the scripted
  inventory-consistency check.

Outputs:

- refreshed `master_results_inventory.csv`;
- refreshed human-readable inventory;
- updated stayer and decomposition LaTeX tables;
- synchronization certification.

### Package C2: Reproducible root runner and frozen handoff

Purpose: ensure that the current results do not depend on knowing which
worktree contains the authoritative implementation.

Status: completed and production-certified on 2026-07-30 at commit
`356c159`.

Tasks:

1. inventory the authoritative P0--P8 scripts and frozen inputs;
2. decide between merging scripts into the root tree and shipping a frozen
   root orchestration runner that points to a versioned source snapshot;
3. integrate through reviewed git commits only: commit the worktree, commit
   or stash root changes, and merge or cherry-pick without filesystem copying;
4. add dependency, package-version, and path checks;
5. run a non-destructive smoke reproduction of certifications and small
   result tables;
6. build a new `CURRENT_LOCAL_MATCH_V2` handoff containing P8 and later
   diagnostics.

Gate:

- a clean checkout following one documented root command reaches the current
  certified inventories and tables;
- the old root pipeline cannot silently masquerade as the Local Match v2
  pipeline;
- hashes of copied or merged scripts match the source manifest.

Outputs:

- root runner;
- complete source manifest;
- smoke log and reproduction certification;
- refreshed frozen handoff.

### Package D1: Descriptive retained-status completion

Purpose: finish the descriptive facts required to interpret "initially
retained" without claiming a new causal estimand.

Status: completed and certified on 2026-07-30. Governing gate:
`D1_STAYER_DESCRIPTIVES/d1_stayer_descriptives_certification.csv`.

Tasks:

1. produce full career-age and pre-deal patent-stock distributions by
   initially retained, leaver, and no-post-patent status;
2. report quantiles and distribution tests, not means alone;
3. evaluate the management-transition diagnostic;
4. rebuild annual +1 through +5 location states for initially retained
   inventors:
   - focal/acquiring group only;
   - outside group only;
   - both inside and outside;
   - no patent in the year but a later patent exists;
   - end of observed patenting;
5. report persistent-inside shares through +3 and +5;
6. audit focal/control-group patent activity at the +5 endpoint and, where
   observed without changing cohort support, descriptive +6 continuation;
7. include the event-time-zero coefficient as a merger-completion-year effect.
   Report it separately from the +1 to +5 full-year average and include it in
   a completion-through-+5 cumulative effect. State that deal timing is
   observed only by year, so pre- and post-completion months within t=0 cannot
   be separated;
8. add a post-certification rider applying the same annual states and
   persistence horizons to the weighted P5b retained-control arm.

Interpretation:

- patent location, not employment;
- descriptive paths, not a landmark causal effect;
- the failed +1 landmark gate remains failed and is not relaxed.

Gate:

- mutually exclusive annual states sum to one;
- all states reconcile to the certified S0--S2 first-post partition;
- right-censoring labels are explicit;
- no event-year patent defines retention.
- all reportable completion-year outputs resolve to distinct master-inventory
  rows, while the frozen +1 through +5 result remains primary;
- matched treated and control state shares each sum to one.

Outputs:

- career-age and productivity distribution table;
- status-transition table;
- persistent-inside path figure;
- symmetric matched-control persistence comparison;
- endpoint-existence audit;
- certification and manifest.

### Package N0: Network design freeze and outcome-blind census

Purpose: define the network estimands, support, and decision rules before
opening post-acquisition network effects.

Primary population:

- full pre-deal target-inventor cohort on certified P5c support;
- inventors with at least one baseline persistent collaborator;
- initially retained P5b inventors are secondary and selected.

Baseline-tie construction:

- single anchor window: t=-5 through -3;
- a persistent tie requires at least two joint applications in at least two
  distinct anchor years;
- validation leads: t=-2, -1;
- post window, if released: t=+1 through +5;
- event year zero is excluded.

If the -5:-3 anchor lacks support, report feasibility only and do not open
post effects. Event time -6 is outside the frozen P5c design and is not an
allowed fallback.

Primary symmetric network outcomes:

1. collaborator focal-organization persistence share among observable,
   at-risk baseline collaborators; this partner-behavior outcome governs;
2. legacy-collaborator composition share among the focal inventor's distinct
   collaborators, conditional on at least one co-invented patent;
3. legacy-link composition share among the focal inventor's collaboration
   link-instances, conditional on at least one co-invented patent.

Secondary descriptive outcomes:

- baseline-tie recurrence and collaborator-set Jaccard, explicitly labelled
  quantity-sensitive because both fall mechanically when the focal inventor
  patents less;
- collaborator patenting anywhere;
- weighted tie persistence using pre-deal joint applications;
- concentration in the strongest pre-deal tie.

Feasibility gates to freeze before N1:

- at least 3,000 treated full-cohort inventors with a baseline tie, or a
  documented revised minimum justified only by pre-outcome census;
- at least 150 nominal treated deals;
- effective treated deals at least 20;
- no baseline or validation input uses event time zero or later;
- treated and control definitions are symmetric;
- all primary shares are bounded and missingness is explicit.
- smallest main-text-relevant effect frozen at 0.05 on the share scale, with
  governing MDE required to be no larger than 0.05.

Outputs:

- network pre-analysis freeze;
- baseline dyad census;
- deal concentration and coverage tables;
- outcome-blind construction certification.

### Package N1: Network pretrend, precision, and falsification gate

Purpose: decide whether network post effects may be opened.

Tasks:

1. construct only anchor and validation-period network outcomes;
2. apply the frozen P5c weights without reselecting on post outcomes;
3. estimate held-out gaps for each primary network outcome;
4. calculate MDEs under deal-wild and two-way inference;
5. run code fixtures and the mandatory untreated-firm network falsification.

Proposed release rules, to be reviewed and frozen in N0:

- no validation lead has an absolute gap above 0.05 on a share scale;
- the joint validation-lead test does not reject at 10%;
- the 95% interval for each lead lies inside a predeclared equivalence band
  where feasible;
- MDE is no larger than the predeclared economically meaningful effect;
- effective treated deals remain at least 20;
- the mandatory untreated-firm falsification passes its frozen criterion.

Path decision:

- Path N: all governing gates pass, so N2 may open post effects;
- Path Q: construction is valid but precision is inadequate, so report
  feasibility and do not open post effects;
- Path F: validation fails, so report the failed design and stop.

Outputs:

- validation-lead table and plot;
- power/MDE table;
- gate decision and certification;
- no post-acquisition network estimate in this package.

### Package N2: Full-cohort network effects

Condition: execute only under Path N.

Purpose: estimate acquisition effects on collaboration-network preservation
for the predetermined full cohort.

Tasks:

1. estimate dynamic +1 through +5 effects for the three primary network
   outcomes;
2. report the average +1 through +5 effect;
3. use two-way deal/inventor inference as governing and deal-wild inference
   as the cluster-sensitivity companion;
4. report the buffered 1994--2008 companion;
5. apply Holm adjustment across the three primary outcomes in the appendix;
6. decompose collaborator loss into:
   - partner remains in the focal organization but the tie ends;
   - partner patents outside;
   - partner reaches the end of observed patenting.

Interpretation:

- network outcomes for a predetermined population;
- the destination decomposition is accounting evidence, not causal
  mediation.

Outputs:

- network event-study figure;
- primary network ATT table;
- destination decomposition;
- certification, manifest, and thesis-ready assets.

### Package N3: Initially retained network companion

Condition: begin only after N2 is certified and after a separate retained
precision gate.

Purpose: describe network preservation within the selected initially retained
population using the existing P5b design.

Tasks:

1. reuse certified P5b support and weights;
2. report the retained baseline-tie census;
3. calculate MDEs before opening retained post effects;
4. estimate the same symmetric outcomes only if the retained gate passes;
5. otherwise report descriptive treated paths without a retained ATT.

Expected limitation:

- about 1,058 retained treated inventors have a persistent tie under the
  broader existing -5:-1 definition; the -5:-3 anchor will reduce this, so
  Path Q (valid but insufficiently precise) is the N3 base case.

Outputs:

- retained network feasibility/power table;
- selected-group network effects only if released;
- explicit post-treatment-selection warning.

### Package N4: Acquirer integration and outcome associations

Status: optional appendix package, never required for thesis completion.

Purpose: describe how retained inventors' teams are recomposed.

Treated-only collaborator categories:

- legacy target collaborator;
- legacy acquirer collaborator;
- entirely new collaborator;
- outside-group collaborator.

Optional associations:

- legacy-tie loss with patent count, total PQII, and TechDrift;
- new acquirer ties with patent count, total PQII, and TechDrift.

Guardrails:

- no causal language;
- no four-cell "mechanism proof" typology in the main text;
- deal and event-time fixed effects plus predetermined controls;
- complete multiple-testing disclosure;
- appendix placement unless a separate design identifies a symmetric
  controlled outcome.

### Package W1: Thesis-section integration

Purpose: write the section only after C1--D1 and the network path decision are
complete.

Main-text hierarchy:

1. full-cohort patent-count and cessation results;
2. dynamic shape: the certified frozen path attenuates monotonically from
   t=+1 through +5, and the control-endpoint diagnostic shows the same shape.
   Describe this as consistent with temporary integration disruption, not as
   proof of a mechanism or evidence against all portfolio rationalization;
3. initial-retention selection facts;
4. retained patent-count estimate with the two-way interval retained in full;
5. retained sign-stability qualification and buffered companion;
6. retained quantity/PQII/TechDrift anatomy;
7. full-cohort network result only if N2 passes;
8. selected or treated-only network evidence as secondary or appendix.

The t=0 estimate belongs in the main event-study narrative as a
merger-completion-year effect. Retain the +1 to +5 average as the comparable
full-calendar-year flow estimand, and additionally report the
completion-through-+5 cumulative effect. Label t=0 as partially exposed
because completion occurs within the calendar year.

The existing detailed retained heterogeneity paragraph, including the
persistent-team Holm discussion, is not required in the main text. It remains
available in the multiplicity appendix.

## 4. Immediate execution order

1. C1 documentation and inventory synchronization.
2. C2 reproducible root runner and frozen handoff.
3. D1 descriptive retained-status completion.
4. N0 network freeze and census.
5. N1 network validation/power gate.
6. N2 only if Path N.
7. N3 only after N2 and its own power gate.
8. N4 only if time remains.
9. W1 final thesis integration.

Packages C1, C2, and D1 are thesis-completion work. Packages N0 and N1 are
disciplined feasibility work. N2 is a contribution upgrade conditional on
validation. N3 and N4 are optional.
