# Local matching v2: P4 technology-resolution lock

Status: immutable prospective record, written 2026-07-23 before any P4 pilot
execution and before any outcome inspection. This record is intentionally kept
outside `local_match_v2_amendments.md` because the certified P3 configuration
hashes that file; appending there would break the frozen P3 hash chain. The
SHA-256 of this file is pinned in `17a_lmv2_p4_pilot_config.R` and written into
every P4 manifest.

1. **Naming resolution.** The P0 design lock's finest technology resolution —
   historically referred to as the "seven-character" resolution and stored in
   `15a_lmv2_design_lock.R` under the threshold block
   `LMV2_LOCK$matching$technology$ipc7_primary_if` — maps to the runtime
   resolution `ipc_main_group` (IPC subclass plus zero-stripped main group,
   for example `A61K31`). The thresholds in `ipc7_primary_if` therefore govern
   whether `ipc_main_group` may become the primary Stage-2 inventor matching
   resolution.

2. **Binary primary-resolution rule.** The primary Stage-2 resolution is
   selected by a binary rule evaluated on the admissible pilot candidate
   pools: select `ipc_main_group` if and only if **every** pilot cohort
   (1995, 2002, 2009) passes **all** locked technology-support thresholds —
   at least 90% of treated inventors have three positive-cosine controls from
   at least two firms; the median candidate set has at least five distinct
   positive cosine values; the median zero-cosine share is below 50%; and
   fewer than 20% of treated inventors have all nearest candidates tied.
   Otherwise select IPC4. No intermediate or per-cohort mixture is permitted.

3. **Runtime `ipc7` is diagnostic only.** The runtime resolution named `ipc7`
   denotes the normalized full IPC subgroup (for example `A61K31/00`). It is
   reported in all support diagnostics but is not primary-eligible and cannot
   become the primary matching resolution under any pilot outcome.

4. **Outcome blindness.** No outcome variable, outcome table, or
   treatment-effect estimate was inspected before or while writing this
   record. P4 reads only pre-treatment matching interfaces certified by P3.

5. **Hash pinning.** The SHA-256 of this file is pinned as a constant in the
   P4 configuration (`17a_lmv2_p4_pilot_config.R`), folded into the P4
   configuration hash, and recorded in every P4 manifest. Any edit to this
   file after the pin invalidates the P4 configuration.
