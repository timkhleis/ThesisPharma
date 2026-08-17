# Reconciling the patent-count results with Cassi and Ornaghi (2026)

## Answer in one paragraph

The two studies agree that retained target inventors can look worse than a
comparison group, but their reported percentages are not estimates of the
same quantity. The bridge reproduces Cassi and Ornaghi's Table 9 almost
exactly: the R port estimates 0.980 fewer patents over five years, compared
with their reported 0.970. That negative gap disappears when the unchanged
matched observations are measured from the acquisition year: treated
inventors produce 2.936 patents and controls produce 2.932, a difference of
0.004. The thesis estimate of -0.536 arises only after constructing controls
that are comparable at the acquisition date and balancing the complete
pre-acquisition patent trajectory. The discrepancy therefore comes from the
event clock, selected population, and counterfactual—not from the thesis's
patent-count construction.

## Exact reproduction benchmark

The published Stata code selects 7,104 `T_STAYER` observations and retains
6,946 with two controls. The independent port:

- selects the same 7,104 treated status observations;
- retains the same number of matched treated observations, 6,946;
- assigns two distinct controls without replacement;
- estimates -0.980 patents, only 0.010 below the published -0.970.

The small coefficient difference reflects the random processing of tied
Mahalanobis distances. The published code fixes Stata's `sortseed`; the port
uses a deterministic tie draw. This difference is too small to affect any
conclusion.

The reproduction also recovers the published outcome levels. The port gives
3.228 patents for treated inventors and 4.208 for controls, compared with
3.23 and 4.20 in Table 9.

## Bridge results

| Step | Design change | Treated patents | Control patents | Five-year difference |
|---:|---|---:|---:|---:|
| 0 | Published Table 9 | 3.230 | 4.200 | -0.970 |
| 1 | Independent port of published design | 3.228 | 4.208 | -0.980 |
| 2 | Same matches, acquisition-year outcome clock | 2.936 | 2.932 | +0.004 |
| 3 | Acquisition years 1994--2010, rematched | 3.037 | 3.086 | -0.049 |
| 4 | Common selected analysis population, rematched | 3.942 | 2.919 | +1.023 |
| 5 | Canonical patent counts on the same units | 3.923 | 2.832 | +1.091 |
| 6 | Add an event-time -1 baseline adjustment | 3.923 | 2.832 | +2.793 |
| 7 | Frozen thesis selected-group design | 4.081 | 4.617 | -0.536 |

Steps 4--6 use the intersection of the paper's `T_STAYER` observations and
the thesis's frozen selected-stayer analysis sample. The thesis sample has
2,663 supported treated inventor-deal units. Of these, 2,326 appear as a
paper `T_STAYER`, and the paper matching rule finds two controls for 2,302.

The sequential rows are descriptive because design components interact. An
exact Shapley calculation, conditional on the 1994--2010 cohorts, confirms
that the large offsets are the clock, population, and counterfactual:

| Component | Contribution to the five-year estimate |
|---|---:|
| Restrict acquisition cohorts to 1994--2010 | -0.052 |
| Change status-year clock to acquisition-year clock | +1.935 |
| Change to the common selected analysis population | +1.036 |
| Change helper counts to canonical counts | -0.119 |
| Add the event-time -1 baseline adjustment | +0.973 |
| Remaining change to the thesis support and weighting design | -3.329 |

The positive and negative components largely cancel. They should not be
reported as percentage shares of the final gap.

## Why the acquisition-year correction changes the result

Table 9 describes the outcomes as patents in the three or five years after
treatment. Its replication code constructs them from the year of the
inventor-status observation:

```stata
gen tmp=patent if year>`y' & year<=(`y'+`i')
by codinv: egen tmpsum=sum(tmp)
replace ex_patent`i'=tmpsum if year==`y'
```

The code retains `target_year` but does not use it for these outcomes. Every
`T_STAYER` status observation precedes the acquisition. The mean difference
is 2.135 years: 52.7 percent are one year before acquisition, 20.6 percent
are two years before, and 26.7 percent are at least three years before.

Consequently, the paper's five-year window often includes the acquisition
year and sometimes includes pre-acquisition years. It never equals the
thesis window of acquisition event times +1 through +5.

This is not a cosmetic timing difference. On the published matched sample,
the status-year clock produces the -0.980 gap. Re-anchoring those same
inventors and controls to the acquisition year produces +0.004. The paper's
reported quantity is therefore not a clean five-year post-acquisition
contrast under the implementation supplied in its replication package.

## Why the thesis counterfactual differs

The paper exact-matches on first patent year, experience, and the rolling
five-year patent total at the earlier status observation. It then matches on
cumulative inventor patents and group patents. These restrictions balance
the paper's status date, not the acquisition date.

This becomes clear in the common selected sample. Under the paper's control
design, acquisition-aligned treated inventors produce 3.923 canonical patents
and controls produce only 2.832. The controls also differ sharply at event
time -1, so a baseline adjustment raises the contrast to +2.793.

The thesis instead defines a placebo acquisition date for controls, requires
local firm and IPC support, and entropy-balances all five annual
pre-acquisition patent outcomes and other lifecycle and firm covariates.
Those acquisition-aligned controls have counterfactual five-year output of
4.617, giving the selected-group estimate of -0.536.

The remaining -3.329 Shapley component is therefore not an unexplained
coding residual. It captures the substantive replacement of controls that
are similar at an earlier patent-status date with controls that reproduce
the treated inventors' trajectory at the acquisition date, plus the thesis's
event-study weighting.

## Are the percentages aligned?

No. The published "11 percent" divides the five-year gap by pre-treatment
output plus counterfactual post-treatment output:

`0.97 / (4.04 + 4.20) = 11.8%`.

The thesis headline percentage divides an annual ATT by annual pre-deal
output. On the common post-treatment counterfactual denominator:

- Cassi and Ornaghi: `0.97 / 4.20 = 23.1%`;
- thesis selected group: `0.536 / 4.617 = 11.6%`.

The estimates agree in sign when each study's preferred design is used, but
they do not agree in percentage magnitude.

## Did the thesis do something wrong?

The bridge provides no evidence of a thesis coding error. Three facts point
the other way:

1. The independent port reproduces Table 9 before any thesis variables are
   introduced.
2. Replacing the helper patent field with canonical distinct
   inventor-application counts changes the harmonized estimate by about
   0.12 patents, far less than the timing and counterfactual changes.
3. Using `target_year` is the correct choice for an acquisition effect. The
   paper's status observation is an inventor-patent transition date, not the
   treatment date.

The thesis would create a problem only by calling its estimate a direct
replication, comparing -0.267 with -0.970 without describing the populations,
or presenting 13.5 percent and 11 percent as the same percentage estimand.

## Recommended thesis treatment

Keep the full-cohort estimate as the main result and the selected retained
estimate as a conditional companion result. Add one short reconciliation
paragraph and place the bridge table in the appendix:

> Cassi and Ornaghi (2026) report 0.97 fewer patents over five years among
> matched target stayers. I reproduce their result in the supplied data
> (-0.98). Their replication code measures the outcome from an inventor-status
> observation that precedes acquisition by 2.1 years on average. Holding their
> matches fixed and measuring patents from the acquisition year reduces the
> gap to zero. My selected retained-inventor estimate (-0.54) instead compares
> acquisition-aligned trajectories after balancing all five pre-acquisition
> annual outcomes. The estimates therefore use different event clocks and
> counterfactuals.

Ask Prof. Cassi whether the status-year outcome clock was intentional. Until
that is confirmed, describe it neutrally as the implementation in the
replication code rather than as an error in the paper.

## Reproducible outputs

The complete bridge is generated by
`02_analysis/R/36_build_cassi_ornaghi_bridge.R`. Its certified outputs are in
`02_analysis/output/results/cassi_ornaghi_bridge/`:

- `bridge_estimates.csv`: sequential bridge;
- `bridge_shapley_decomposition.csv`: order-invariant attribution;
- `bridge_validation.csv`: reproduction and arithmetic checks;
- `matches_*.csv`: saved treated and control row identifiers;
- `pair_outcomes_*.csv`: pair-level outcomes under every clock and source.

The bridge contains diagnostic point estimates, not new uncertainty
estimates. The thesis should retain the inference from each governing design
and use this exercise to explain estimands rather than compare significance
across bridge rows.
