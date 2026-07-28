# Local Match v2: DealSim Stage A power gate

## Decision

The frozen, outcome-gated power analysis selects **Path U**: the proposed
inverted-U DealSim hypothesis is not testable with credible precision in the
current effective deal sample. No DealSim subgroup ATT or continuous
moderation coefficient was calculated, printed, or saved.

This is a power result, not evidence against the inverted-U hypothesis. The
thesis can report the DealSim construction and support limitation, but should
not interpret noisy tercile rankings or quadratic coefficients as evidence for
or against the mechanism.

## Frozen design

- DealSim is the IPC4 cosine similarity between target and acquirer patent
  portfolios over event times \(t=-5,\ldots,-1\), weighted by patent counts.
- Deals are sorted by DealSim and then `deal_id` before being divided into
  three equal-count bins.
- The only primary outcome used to calibrate variance is annual patent count.
- The primary multiplicity family contains two contrasts:
  low minus middle and high minus middle.
- Familywise alpha is 5%, target power is 80%, and the predeclared meaningful
  contrast is 0.053 patents per inventor-year.
- Joint critical values use 9,999 Webb deal-level multiplier draws.

## Support results

DealSim is valid for 312 of the 341 deals in the frozen P5c panel. The 29
excluded deals consist of 18 without a resolved acquirer group, 10 without a
usable acquirer IPC4 portfolio, and one placeholder acquirer. The eligible
sample retains 26,374 of 27,078 treated inventors and 35.15 effective deals.

Each tercile contains 104 nominal deals. On the 14-cohort set common to all
three bins, however, the effective deal counts are:

- low: 7.62;
- middle: 19.21;
- high: 13.31.

The largest deal supplies 32.1% of treated weight in the low-overlap tercile.
The tercile design therefore fails the frozen effective-deal and concentration
gates before any heterogeneity estimate is opened.

## Power results

For the tercile design, the joint-family 80% MDEs are 0.083 patents for low
minus middle and 0.107 for high minus middle. Both exceed the meaningful
contrast of 0.053.

The continuous quadratic screen uses all 312 eligible deals and is more
efficient, but remains underpowered. Its corresponding MDEs are 0.074 and
0.098 patents per inventor-year. The continuous sample itself has adequate
support (35.15 effective deals; largest deal share 7.8%), so the binding
problem is precision rather than a failed continuous-support gate.

## Reproduction

Run from the worktree root:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\30b_build_lmv2_dealsim_table.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\30c_assign_lmv2_dealsim_terciles.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\30d_compute_lmv2_dealsim_power.R
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' 02_analysis\R\30e_certify_lmv2_dealsim_power_gate.R
```

The generated audit bundle is
`02_analysis/output/audit/local_match_v2/P7_DEALSIM_POWER_GATE`.
