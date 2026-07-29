# Local Match v2 current-release implementation

Package C2 now has a non-destructive root entry point:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\41_run_lmv2_current_release.R --verify
```

Available modes:

- `--verify` inventories active Local Match v2 source files, immutable inputs,
  R packages, external commands, and required certifications;
- `--smoke` rebuilds the master inventory and reported-value consistency gate
  in clean R subprocesses and verifies that the authoritative inventory hash
  is deterministic;
- `--handoff-only` builds a compact, hash-certified staging handoff without
  replacing `CURRENT_LOCAL_MATCH_V2` or duplicating the 2.6 GB database;
- `--production` requires a clean worktree with every declared release source
  tracked in Git. It then re-certifies the completion-year window, rebuilds the
  endpoint diagnostic and master inventory, runs the reported-value gate and
  deterministic smoke test, and replaces the hash-certified staging handoff.

Add `--hash-database` to `--verify` or `--smoke` when a fresh SHA-256 of the
large DuckDB file is required. The default records its exact size and modified
time while hashing every smaller immutable input.

The old `run_pipeline.R` remains the canonical data-foundation runner. It now
rejects Local Match v2 mode aliases and directs the caller to the C2 runner, so
the foundation pipeline cannot silently masquerade as the analysis release.

## Integration state

`release_integration_preflight.csv` records technical verification separately
from Git integration readiness. Production remains locked whenever the release
worktree is dirty or any declared source is untracked. This makes the release
command usable after reviewed Git integration without permitting an automatic
filesystem copy of authoritative scripts.

This separation is deliberate:

- technical verification may pass in a dirty development worktree;
- release integration cannot pass until git status is clean;
- no script treats an untracked filesystem copy as authoritative history.
