# P6 v3 runtime refactor — review package

Status: implemented, all-cohort dual-computation certified, and full
production certified.

## Assessment of the review

Claude's two diagnosed nested-loop joins were real and material. The three
additional structural optimizations were also valid. One expectation was not
borne out: replacing `ORDER BY ALL` helped, but was small relative to the join
and cardinality fixes.

There is one factual correction to Claude's rationale for skipping the
treated-only production panel. `derive_treated_fixture_roster()` derives from
`lmv2_treated_primary`, not the frozen supported P5 roster, so it does contain
unsupported treated inventors. It remains safe to omit from production for a
different reason: it is a duplicate certification panel, not an outcome
deliverable; supported treated rows are certified in the matched panel, and
the all-treated version remains available in explicit fixture-only mode.

## Implemented changes

1. Split the three-way last-focal disjunction into equality joins for focal
   group 1, focal group 2, and the target-company path.
2. Preserve no-evidence semantics with an explicit NULL-safe maximum.
3. Add a regression fixture with NULL `focal_group_2`,
   `use_target_company_path = FALSE`, and no focal evidence.
4. Assert that `lmv2_control_firm_eligibility` is unique on
   `(cohort, control_group)`, cast `control_group` to BIGINT once, use
   equality-only join keys, and return the diagnostic through an arm-specific
   `CASE`.
5. Attach `stay`, `last_focal`, `bnorm`, and the firm-exit diagnostic before
   the eleven-row event-time expansion.
6. Materialize `r`, `baseline`, and `cvec`, and hoist the distinct roster
   inventor set.
7. Replace `ORDER BY ALL` with the unique deterministic key
   `(deal_id, arm, codinv, roster_row_id, event_time)`.
8. Omit the all-cohort treated-only duplicate panel in production; retain it
   in fixture-only mode.
9. Add a bounded cohort selector and per-shard timing/profiling hooks for
   certification.
10. Add a separate all-eligible-treated, pre-period-only artifact for the
    frozen common-support sensitivity. It contains no unsupported
    post-treatment outcomes.
11. Set P6 v3 to eight threads on measured evidence.

## Exact real-data A/B

The preserved v2 matched shards for cohorts 1994–1998 were compared with the
v3 rebuild on every output column. Together they contain 717,585 panel rows
(65,235 roster rows times eleven).

| Cohort | Rows | Schema | Old minus new | New minus old | Hash sum | Hash XOR |
|---:|---:|:---:|---:|---:|:---:|:---:|
| 1994 | 168,630 | equal | 0 | 0 | equal | equal |
| 1995 | 207,669 | equal | 0 | 0 | equal | equal |
| 1996 | 64,603 | equal | 0 | 0 | equal | equal |
| 1997 | 202,906 | equal | 0 | 0 | equal | equal |
| 1998 | 73,777 | equal | 0 | 0 | equal | equal |

This is exact multiset equality via bidirectional `EXCEPT ALL`, not Parquet
byte equality.

## Runtime and memory

- Interrupted v2 matched build, cohorts 1994–1998: 16 minutes 6 seconds.
- v3 at eight threads, same five cohorts: 7.06–7.68 seconds in the final
  repeated runs.
- Prospective thread comparison: four threads 10.01 seconds; eight threads
  9.07 seconds.
- DuckDB JSON-profiled peak at eight threads: 1,451,913,216 bytes
  (1.45 GB decimal).
- Temporary-directory spill: zero bytes.
- Prospective memory review threshold: 6 GB.

Isolated attribution on cohort 1996:

- split last-focal join: 16.41 seconds to 0.938 seconds;
- equality-only firm-exit join: 26.67 seconds to 0.0236 seconds.

Isolated deterministic-sort comparison on the 207,669-row cohort-1995 shard:

- `ORDER BY ALL`: 0.47–0.53 seconds;
- narrow unique key: 0.37–0.48 seconds.

The pre-expansion joins and CTE materialization interact with the two join
changes in DuckDB's planner, so their contributions are not additively
identified without maintaining artificial code variants. The end-to-end
five-cohort comparison is the governing runtime evidence.

## Unsupported-tail structural gap

The review's final question found a genuine gap. The frozen sensitivity scale
`sigma_pre` and supported-versus-unsupported outcome descriptives require
pre-treatment outcomes for all eligible treated inventors, while the causal
P5 roster is supported-only.

The new pre-period artifact is certified as:

- 29,170 eligible treated inventors;
- 27,078 supported;
- 2,092 unsupported;
- exactly five rows per inventor, event times -5 through -1;
- 145,850 rows total;
- supported membership exactly equal to the treated arm of the frozen P5
  roster;
- no event time at or after treatment.

The primary causal panel remains supported-only. No post-treatment
unsupported ATT is estimated; the frozen delta grid continues to vary it as
an unknown.

## Checks completed

- all `18*.R` files parse;
- frozen primary roster contract and P2 membership pass;
- NULL-safety fixture passes;
- all-eligible pre-period artifact passes all four structural checks;
- five preserved cohorts pass exact content A/B;
- four-versus-eight-thread benchmark complete;
- eight-thread peak memory is below 6 GB with no spill;
- `git diff --check` passes.

## Approval requested

Claude's conditional approval required one final all-cohort comparison of the
old and new last-focal and firm-exit computations. That temporary validator
ran once across all 17 cohorts and 500,906 roster rows:

- last-focal mismatches: 0;
- firm-exit mismatches: 0;
- all cohort checkpoints passed, including 2000 and 2009.

The temporary validation code was then deleted; its CSV and logs remain in
`P6_V3_DUAL_VALIDATION`.

The full pipeline was then run once into a fresh `P6_V3_PRODUCTION`
directory. `P6_V2_PRODUCTION` remains unchanged, and no v2 restart stamp was
reused. The production run passed the full double-build, provenance, fixture,
roster, shard, outcome, and upstream-integrity certification suite before
any ATT was estimated.

## Production result

The clean v3 production run completed in 1.79 minutes:

- design hash:
  `9a526c55806449674b9965306b9a4ec558e6ce6ccbac9d0de2c49f727197f5b4`;
- 60/60 certification checks passed;
- 17/17 cohort shards built;
- 5,509,966 matched-panel rows;
- 145,850 all-eligible-treated pre-period rows;
- approved roster hash retained exactly;
- no R process remained after completion.

An initial production attempt completed all substantive work but triggered a
false-positive source check because the substring `filing` matched the word
`profiling`. That directory is preserved as
`P6_V3_PRODUCTION_FALSE_POSITIVE`. The check now uses the standalone token
`\\bfiling\\b`; its regression test distinguishes `filing` from `profiling`.
