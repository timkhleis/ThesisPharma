# Local Match v2 — P3 matching engine handover

Date: 2026-07-23

Branch: `codex/lmv2-p3`

P2 baseline: `5d602a7`

P3 version: `local_match_v2_p3_v2`

P3 config hash: `11929f9715f8b789fe2597805ad311d4352661d5040f0c62f2491d60f13cf8a4`

P3 interface-manifest SHA-256:
`ce7ed077f7e8dac07ec68ffd991df919d64bd4012c7feede934e5f5f14874a9a`

## Scope

P3 builds and certifies the outcome-blind, decoupled two-stage matching
infrastructure. It does not choose a caliper or inventor IPC resolution, inspect
outcomes, estimate a treatment effect, or begin P4.

Stage 1 is locked to IPC4 firm cosine similarity plus log five-year patent stock
and log five-year inventor count. Firm cosine matrices at IPC main-group and
full-subgroup resolution are exposed only as diagnostics. Stage 2 exposes a
single cached interface for inventor cosine similarity at IPC4, IPC main group,
and normalized full subgroup (`ipc7`). P4 will compare those three inventor
resolutions only after the five-firm Stage-1 pools have frozen.

## Review changes incorporated

- Control-firm early and recent patent windows now use a null-safe deal-ID join.
  This repairs the P3 v1 defect in which every control has a null deal ID and
  therefore failed a conventional null-equality join. The v2 certification
  independently reconstructs both windows from group-year patent counts and
  verifies that they sum to the certified five-year control-firm patent stock.
- Treated focal tenure and exclusivity now use the same dual evidence route as
  P2: target-group links or deal-specific target-company links. The build
  recovered 13 pre-period target-company patent links not carried by the group
  route. No treated inventor depends exclusively on that company route, but the
  recovered patents prevent understated tenure or exclusivity.
- Stage-2 scalar standard deviations are calculated over treated and eligible
  control units within cohort before IPC-overlap and recency pair filters. Equal
  values remain separate unit observations.
- Stage-1 matching edges contain IPC4 only. The two finer firm matrices remain
  diagnostics and cannot enter the Stage-1 selector.
- Unsupported firms and inventors are returned explicitly with reasons; the
  two-firm requirement is never silently relaxed.
- Stage-2 technology vectors are cached once for the frozen candidate pool, and
  shared IPC4 support uses a feature semi-join.
- The P2 interface-manifest SHA-256 is pinned and checked before P3 runs. The P3
  manifest also records the P0 design, P2 manifest, amendment, and effective P3
  configuration hashes.
- Certification fixtures use deterministic ordering and test the exact
  trajectory formula, caliper boundary, IPC4 Stage-1 lock, unit-level scaling,
  two-firm repair, unsupported reasons, control reuse, and all three inventor
  technology interfaces.

## Certified interfaces

The build creates 12 derived interfaces, including 29,170 treated-inventor
matching rows, 167,604 firm-cohort rows, 11,638,752 three-resolution Stage-1
similarity rows, and 3,879,584 IPC4 Stage-1 matching edges. Each interface is
exported to Parquet and recorded in `p3_interface_manifest.csv`.

All 343 treated deals have an IPC4 target-firm vector. Across the candidate
firm matrices, 2,233 deal-control-firm pairs lack a control IPC4 vector and are
therefore unsupported by construction. Every deal nevertheless retains at
least 5,392 admissible IPC4 candidate pairs before calipers. The per-deal census
is in `p3_stage1_vector_support_by_deal.csv`.

The firm-pair diagnostics show the expected sparsity ordering: IPC4 has the
greatest positive overlap, main groups are intermediate, and full subgroups are
the sparsest. This is diagnostic evidence only. Inventor-level support,
gradation, tie frequency, and three-controls-from-two-firms feasibility require
the frozen Stage-1 pools and therefore belong to P4.

## Acceptance

- 46/46 certification checks pass.
- Two complete builds have identical logical manifests.
- First deterministic build: 4.64 minutes.
- Second deterministic build: 3.90 minutes.
- No treatment outcomes were read or estimated.

Primary audit files are under
`02_analysis/output/audit/local_match_v2/P3/`. Reproduce the package from the
thesis root with:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\16e_run_lmv2_p3.R
```

## P4 review gate

Before P4 starts, review the matching-variable construction, the Stage-1
firm-pair IPC diagnostics, the per-deal vector-support census, and the explicit
decision to defer inventor-resolution selection until after Stage 1 freezes.
P4 must remain outcome blind and must stop if no acceptable Stage-1 or Stage-2
profile satisfies the locked balance and retention rules.
