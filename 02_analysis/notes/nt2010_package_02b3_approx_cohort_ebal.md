# nt2010 — Package 02B.3 Approximate Within-Cohort Ebal — BLOCKED (WeightIt bug)

Date: 2026-07-21
Scope: (1) document the provenance/scope of the ESS gate and revise the rank
interpretation; (2) prototype approximate within-cohort P0H5 balancing via
WeightIt per-covariate `tols` + `solver="FISTA"` on cohorts 1995 & 1996.
Design-only; no outcomes/citations/annual-states/DiD. **Result: the balancing
method is BLOCKED by a WeightIt 1.7.0 bug** (per-covariate `tols` unusable via the
public interface). Correct tolerance translation derived, verified, and saved; no
weights produced; no internals modified; no method silently substituted.

## 0. Verdict

The specified method — most-diffuse ebal weights subject to a per-covariate
full-pooled-SMD ≤ 0.05 tolerance — **cannot be run via the public
`WeightIt::weightit()` interface in the installed version 1.7.0**: a **vector
`tols` triggers an error** (`if (tols > 0)` at `weightit2ebal` evaluates a
length-`>1` condition). Scalar `tols` runs but cannot encode per-covariate targets
(it means treated-SD SMD for continuous vs raw mean-diff for binary, and cannot
keep factors exact), so it is not a valid realization of the spec. `optweight` and
`sbw` (the natural per-covariate-tolerance packages) are **not installed** (`osqp`
is). Per the standing rules I did not modify internals, did not tune a scalar by
which value passes, and did not substitute a method. **Halting for review.**

## 1. Methodological correction — ESS gate scope (important)

Provenance: in the frozen robustness code, `positive_concentration()` aggregates
control weight by underlying firm **across the complete specification**, and
`gate_inventor()` applies `ROBUST_MIN_ESS = 50` to that **specification-wide**
firm-mass distribution. It was **not** originally applied separately within each
treatment cohort.

Therefore, corrected framing (retroactively clarifying Packages 2B.0–2B.2):

- `ESS ≥ 50` remains a **full-design gate** (evaluated on the assembled design's
  spec-wide firm-mass distribution), unchanged.
- Per-**cohort** firm ESS is an **additional conservative diagnostic** introduced
  during this conditional-balance investigation — **not** the original gate.
- Consequently, the Package-2B.1 halt at cohort 1995 (per-cohort firm ESS 43.6)
  was a **conservative-diagnostic** trip, **not** a violation of the original
  full-design ESS gate. The assembled cohort-specific design's spec-wide firm ESS
  was never evaluated (2B.1 stopped at the first cohort tripping the per-cohort
  diagnostic). **Whether cohort-specific is feasible under the original full-design
  ESS gate is therefore still open** and is a live option for review (see §6).

Prior results are not erased; short addenda were added to the 2B.1 and 2B.2 notes.
Note: era-level balancing (2B.2) still fails on **within-cohort SMDs of 0.30–0.79**,
which is independent of this ESS-scope clarification.

## 2. Rank interpretation — revised

Low treated firm-stage model-matrix rank (§support map: 1996 rank 1; 1994 rank 3;
1995 rank 4; and rank ≤ 10 even in deal-rich cohorts due to collinear no-history
binaries) **documents thin and collinear treated support**. It does **not**
mathematically prove that entropy balancing must produce concentrated control
weights — fewer independent moments can reduce rather than increase the number of
binding constraints. The correct statement: the **observed exact-balance weights
for 1995 demonstrate concentration** (firm ESS 43.6); the rank map merely
**flags** cohorts where similar problems may arise. **1996 is not claimed to fail
before being estimated.**

## 3. Correct WeightIt `tols` translation (verified; delivered)

Derived from the WeightIt 1.7.0 source (`weightit2ebal`, ATT):
`.make_closer_to_1` keeps binaries 0/1 and z-scores continuous; `sds` = treated
weighted SD (nonbinary) or 1 (binary); constraint `= c(0, tols*sds)` with an exact
intercept. Because `tols` multiplies `sds`, the enforced bound is:

- **nonbinary**: treated-SD SMD ≤ `tols[j]` (scale-invariant) ⇒ to get
  `raw_diff ≤ 0.05·pooled_sd[j]`, set **`tols[j] = 0.05·pooled_sd[j] / sd_treated[j]`**;
- **binary**: raw mean-diff ≤ `tols[j]` ⇒ **`tols[j] = 0.05·pooled_sd[j]`**;
- **factor dummies + intercept**: exact (`tols = 0`);
- **zero-treated-SD nonbinary**: kept exact and flagged.

This translation and a full mapping table (stage, covariate, model-matrix column,
type, treated SD, fixed full-pooled SD, desired raw tol, supplied WeightIt `tols`,
implied raw tol) are saved per cohort:
`..._2b3_cohort_{1995,1996}_tolerance_map.csv`, `..._2b3_tolerance_map_all.csv`.
Design columns were pre-built full-rank (dummies expanded manually) so WeightIt
drops nothing; `length(tols) == ncol(X)` asserted pre-solve for both stages.

## 4. The blocker (verified)

Minimal reproduction (`scratchpad/tols_probe.R`):

| Call | Result |
|---|---|
| `weightit(..., method="ebal", solver="FISTA", tols = 0.05)` (scalar) | OK |
| `weightit(..., tols = c(0.05,0.05,0.05))` (vector) | **ERROR: "condition has length > 1"** |

Cause: `weightit2ebal` line `if (tols > 0)` (gating `tols <- c(0, tols*sds)`) is
scalar-assuming; a length-`>1` `tols` errors under R ≥ 4.2. The FISTA objective
itself uses `tols` per-column (`sum(tols*abs(Z))`), so this is a guard bug, not a
design limitation — but fixing it requires modifying package internals, which is
disallowed. `WeightIt 1.7.0`; `optweight` not installed; `sbw` not installed;
`osqp` installed.

Why scalar `tols` is not a valid fallback: a single scalar means **treated-SD SMD**
for continuous columns but **raw mean-diff** for binary columns; because a
binary's pooled SD (~0.3–0.5) forces the raw bound tiny (`t ≤ 0.05·pooled ≈ 0.02`),
a scalar over-constrains all continuous columns toward exact — defeating the
diffuseness objective — and cannot keep factors exact. It is not the specified
per-covariate method.

## 5. What was produced / not produced

- **Produced**: `11u` script (correct for a fixed/compatible solver); per-cohort
  tolerance maps (1995, 1996); blocker status CSV.
- **Not produced**: approximate weights (blocked before any solve completed); no
  diagnostic weight parquet; no balance/concentration/gate CSVs (no solve).
- **Not done**: no internals patched; no scalar-tuning; no method substitution;
  no production path.

## 6. Options for review (no preference; none executed)

1. **Reconsider cohort-specific under the ORIGINAL full-design ESS gate** (§1). The
   per-cohort ESS < 50 that halted 2B.1 is a conservative diagnostic, not the
   original gate. Assembling the 17 cohort-specific shards and evaluating the
   **spec-wide** firm ESS (and max-share) may show cohort-specific is feasible
   under original scope — it delivers exact within-cohort balance, which nothing
   else does. Cheapest path to a possibly-feasible design.
2. **Enable the approximate method** by installing a per-covariate-tolerance
   balancer — `optweight` (Greifer's companion; minimum-variance weights with
   per-covariate `tols`, exactly this method) or `sbw`, or a WeightIt build where
   the `tols` guard is fixed. Environment change; needs approval.
3. **Implement min-variance + per-covariate-tolerance QP directly via `osqp`**
   (installed). Substantial custom method; needs approval and validation.
4. **Formally specified partial-pooling design** (the 2B.2 fallback), if the above
   are declined.

## 7. Protected-output integrity

- No approximate weight parquet created (blocked before write). Frozen
  `never_target_h5_weights.parquet` md5 identical to baseline. Old global nt2010
  P0H5 weights untouched (mtime Jul 20 21:49). 2B.0 (`cohort2009_PROTOTYPE`) and
  2B.2 (`era9499_PROTOTYPE`) parquets and the 1994 shard unchanged. P5 untouched.
  `two_stage_ebal()` unmodified. 2A/2B.0/2B.1/2B.2 CSVs read-only. Protected/
  unrelated files untouched.

## 8. Deliverables

- `02_analysis/R/11u_prototype_nt2010_approx_cohort_ebal.R` (correct translation +
  blocker-aware).
- `..._2b3_cohort_{1995,1996}_tolerance_map.csv`, `..._2b3_tolerance_map_all.csv`,
  `..._2b3_status.csv`.
- This checkpoint; addenda appended to 2B.1 and 2B.2 notes.
- (No weight parquets, gates, or comparison — blocked.)

## 9. Recommendation

The approximate-balancing method as specified is not runnable here without an
environment change (per-covariate-tolerance solver). **Two productive next steps
for review**, in order of cost: (a) **assemble the cohort-specific shards and
evaluate the original full-design ESS/max-share gate** — this may already yield a
feasible, exact-within-cohort design and directly uses §1's clarification; and,
only if desired, (b) **install `optweight`** (or `sbw`) and run the (now-correct)
approximate translation in `11u`. I did not choose between these or execute either.
Package 3A remains blocked; P5 remains untouched.
