# Local matching v2: P0 prospective lock

Status: frozen before rebuilding outcomes or estimating treatment effects.

The authoritative machine-readable record is `02_analysis/R/15a_lmv2_design_lock.R`. Its SHA-256 design hash is generated from the complete nested decision object and validated by `02_analysis/R/15b_validate_lmv2_p0.R`. Any substantive change after this point requires a new design version plus a dated amendment that states whether outcomes had been inspected.

## Locked estimands and sample clocks

- The main estimand is the average effect for a treated inventor. The equal-deal-weighted estimand is the average inventor effect in the average acquisition.
- Cohorts run from 1994 through 2010, with event time -5 through +5, reference year -1, and aggregate post-period +1 through +5.
- Treatment timing is `target_year`, anticipation is zero, patent timing is application year, and only the earliest inventor exposure defines treatment. Later acquisition exposure is retained under intention-to-treat and audited.
- Absorbing Left and the stayer design use buffered cohorts 1994--2008. The full cohort is co-reported through +3; +5 full-cohort Left is explicitly right-censored descriptive evidence.
- The buffered design stops before matching unless P2 retains at least 3,000 status-eligible stayers, 150 deals with stayers, and raw inventor-weighted deal ESS of 20.

## Affiliation and counterfactual rules

Treated inventors need a deal-specific target-company patent in the five pre-event years and either a latest pre-event affiliation resolved to the target or the strict target-to-acquirer transition route. Transition cases must remain below 5% overall and 10% in every broad era; an estimate excluding them is always co-reported.

Controls must be uniquely affiliated with the candidate control group at their latest pre-event affiliation, come from firms that are never targets and acquirer-clean over g-5 through g+5, and have no inventor-level target exposure on or before g+5. The broad target-company-link cohort is a robustness population, not the primary cohort.

Control-firm exit is retained in the primary intention-to-treat counterfactual. A post-event-conditioned diagnostic removes control firms whose last patent precedes g+5 and rebuilds Stage 2 within the frozen Stage-1 pool. This diagnostic is not interpreted as a superior causal design.

## Matching and inference

Stage 1 and Stage 2 have separate caliper grids and use within-cohort standardization. Stage 1 is frozen before Stage 2. The pilot is outcome-blind and may stop the pipeline; its numeric balance, support, retention, IPC-resolution, and fallback rules are stored in the machine-readable lock.

Every aggregated headline ATT uses a deal-level wild cluster bootstrap-t interval and p-value with Webb six-point weights, 9,999 fixed-seed replications, and null-imposed resampling. The fixed project dependency is `fwildclusterboot` 0.14.3. Nominal and weight-based effective treated-deal counts accompany the bootstrap result; two-way deal/inventor and deal-only cluster-robust standard errors are companion diagnostics.

## Provisional power benchmark to be reproduced in P2

The pre-repair audit recorded 28,643 treated inventors across 339 deals for 1994--2010 and 24,074 inventors across 290 deals for 1994--2008. It recorded 4,157 status-eligible stayers across 198 deals and 3,656 buffered stayers across 169 deals, with raw deal ESS falling from 31.98 to 25.97. These values are benchmarks, not frozen outputs: P2 must reproduce or explain every material difference after the inventor-year repair.

## Parallel work boundary

Until P2 passes, Codex is the only writer and Claude may review read-only. After the P2 table interfaces and hashes freeze, Codex owns P3--P5a and Claude may build P6 in separate files and a separate branch/worktree. P5b begins only after integration.

