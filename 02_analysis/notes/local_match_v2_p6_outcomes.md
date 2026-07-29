# Local Match v2 — P6 certified outcome panel

Status: implemented against the certified P5 weighted-pool interface. The
binding methodological decisions are in
`local_match_v2_p6_preanalysis_freeze.md`; its SHA-256 is pinned in
`18a_lmv2_outcome_config.R`.

## Authoritative interface

The primary roster contains all 17 locked cohorts and arrives with
cohort-level entropy weights. It is not a three-controls-per-inventor
matching object. Its row identifier is `roster_row_id`; P6 independently
rejects duplicates at the conceptual
`(cohort, deal_id, arm, codinv, focal_group_1)` grain so a synthetic row
number cannot conceal duplicate analysis rows.

The runner pins the exact approved roster hash, P5 design hash, P5
production-freeze hash, row count, and certification status. It requires
equal treated/control weight mass within each cohort and positive control
weight from at least two firms for every treated deal. P6 never recomputes,
repairs, renormalizes, or rebalances P5 weights.

P2 assignment provenance is carried into the roster and panel:
`qualification_route`, `target_to_acquirer_transition_strict`,
`latest_pre_candidate_group_count`, `multi_exposure_inventor`, and
`big_deal`. Membership certification compares those fields with
`lmv2_treated_primary`.

## Outcome priority and horizon

Primary outcomes are patent count, active patenting, and TechDrift.
OECD PQII and five-year forward citations are secondary because linkage and
late-year coverage are incomplete. All OECD variants retain the locked
missing-not-zero semantics.

The event window remains \(t=-5,\ldots,+5\). The main post-treatment summary
is \(t=+1,\ldots,+5\), and \(t=+5\) is retained for all cohorts for direct
comparability with the main ATT. The panel marks calendar years 2014–2015,
and the runner writes weighted event-time linkage and outcome coverage.
The 1994–2008 censoring-clean cohort companion is frozen alongside the
1994–2010 result.

## IPC4 and Henkel

IPC4 is the frozen primary technology granularity. Henkel remains in the
primary donor pool because it is present in the source data and passes the
same IPC4 and firm-support rules as other donors. Main-group disaggregation
is reported as a granularity diagnostic, not as a reason to change the
primary roster after outcome inspection.

The Henkel-omitted exact-balance roster is a labeled influence sensitivity.
It is reported with its realized ESS and interval even though it does not
pass the primary ESS gate. Cohort-level refit weights are used to report
changes in the full headline and cohort-2000 ATTs; they are not labeled a
causal deal-70 ATT.

## Files

| File | Role |
|---|---|
| `18a_lmv2_outcome_config.R` | Frozen hashes, outcome priority, roster contract, horizons, inference rules |
| `18b_build_lmv2_outcome_ingredients.R` | Deterministic roster-independent outcome ingredients and OECD audits |
| `18c_materialize_lmv2_outcome_panel.R` | Weighted-roster validation, cohort-sharded supported panel, and all-eligible-treated pre-period artifact |
| `18d_certify_lmv2_outcomes.R` | Fixtures, NULL-safety and duplicate-row regression tests, coverage/linkage diagnostics, certification |
| `18e_run_lmv2_p6.R` | Exact provenance gate, double build, materialization, certification, manifest |
| `18g_certify_lmv2_p6_runtime_refactor.R` | Bounded five-cohort content A/B and thread/runtime benchmark |

## Runtime refactor

P6 v3 removes the two blockwise nested-loop joins, attaches roster-grain
state before the eleven-row event-time expansion, materializes reused CTEs,
hoists the roster inventor set, and sorts on the unique narrow key. The
control-firm table is explicitly certified unique on
`(cohort, control_group)` and its key is cast once before joining.

The preserved 1994–1998 v2 shards provide the real-data regression baseline.
At eight threads, all five rebuilt in 7.06 seconds versus 16 minutes 6
seconds in the interrupted v2 run. All five were exactly equal in schema,
row count, bidirectional `EXCEPT ALL`, hash-sum, and hash-XOR. Four threads
took 10.01 seconds in the prospective comparison; eight threads took 9.07
seconds. DuckDB JSON profiling at eight threads records a 1.45 GB peak and
zero temporary-directory spill, below the prospective 6 GB review threshold,
so v3 uses eight threads. The production treated-only duplicate panel is
omitted; it remains available in fixture-only mode.

The primary causal panel remains supported-only. A separate artifact contains
only event times -5 through -1 for all 29,170 eligible treated inventors
(27,078 supported and 2,092 unsupported). This closes the
supported-versus-unsupported descriptive and `sigma_pre` requirement without
materializing or identifying post-treatment outcomes for the unsupported
tail.

## Certification

The suite verifies:

- all five frozen P2 interfaces and consumed P1 inputs;
- two independent ingredient builds with identical logical checksums;
- exact primary roster and design hashes;
- all 17 cohorts and conceptual roster uniqueness;
- treated/control mass equality and two positive-weight control firms per
  deal;
- exact P2 treatment-assignment and stayer fields;
- panel grain and roster-row count times eleven;
- exact five-row pre-period coverage for every eligible treated inventor and
  exact supported-membership reconciliation;
- structural zeros versus missing OECD values;
- absorbing Left NULL propagation and TechDrift sign conventions;
- event-time coverage, OECD linkage non-randomness on observable pre-link
  patent characteristics, and explicit field-availability limitations;
- complete source-bundle and pre-analysis-freeze provenance in shard stamps.

Headline inference is the deal-cluster wild bootstrap, with two-way
deal/inventor clustering reported prominently. If intervals differ
materially, the wider interval governs the conclusion.
