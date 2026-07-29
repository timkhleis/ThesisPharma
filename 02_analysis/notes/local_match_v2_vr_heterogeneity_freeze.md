# Local Match v2: five-year inventor heterogeneity freeze

Frozen before the new moderator outcomes are estimated. This package leaves the
certified P5c roster, entropy weights, headline ATT, LOYO results, and P6
outcomes unchanged. It replaces neither the full-cohort event study nor the
later stayer analysis.

## Estimand and regression structure

The primary effect is the existing average annual ATT over \(t=+1,\ldots,+5\),
referenced to \(t=-1\). For presentation, this is written in the
Verginer--Riccaboni `After` form:

\[
Y_{irt}=\alpha_{ir}+\lambda_{g\times t}
 +\tau(T_i\times After_t)
 +\gamma'(After_t\times M_{ir})
 +\delta'(T_i\times After_t\times M_{ir})+\varepsilon_{irt}.
\]

Here \(T_i\) distinguishes treated inventors from their matched placebo
controls. It replaces Verginer and Riccaboni's `Left` status because leaving is
post-treatment and would mix the full-cohort ATT with stayer selection. The
computational implementation uses the algebraically equivalent roster-level
change from \(t=-1\) to mean \(t=+1,\ldots,+5\), with cohort-standardized P5c
weights. A five-pre versus five-post change is an appendix companion.

Patent count is the primary outcome. Active patenting is the co-reported
extensive-margin outcome. No log-patent or citation outcome enters this
heterogeneity family.

## Predetermined moderators and prior evidence

The four primary moderator families are:

1. five-year pre-deal productivity, \(\log(1+\text{patents}_{-5:-1})\);
2. career age at \(t=-1\), \(\log(1+\text{years since first patent})\);
3. persistent-team dependence during \(t=-5,\ldots,-1\);
4. inventor--acquirer IPC4 cosine similarity.

A temporally persistent collaborator must appear with the focal inventor on at
least two distinct patents in at least two distinct pre-deal years. The main
team contrast compares no persistent tie with the average inventor having a
persistent tie. Persistence share among positive cases is secondary.
`StrongestTie`, the maximum pairwise joint-patent share, is constructed
outcome-blind. Because the persistent-tie patent-count contrast is examined in
the complete heterogeneity package, `StrongestTie` is also reported as a
clearly labelled appendix extension among inventors with a persistent tie. It
does not enter the primary eight-test family.

The productivity prediction is stated in absolute and proportional terms. A
larger absolute loss among productive inventors can arise mechanically from
their larger patent stock even if the proportional disruption is constant.
Accordingly, the package reports both the level contrast and the effect relative
to the matched counterfactual output of each productivity profile. It does not
label a larger level loss as greater vulnerability unless the proportional
effect also differs.

Career-age evidence is not independent of prior diagnostics. The previously
estimated established-inventor design, which requires focal patent evidence at
\(t=-7\) or \(t=-6\), returned an annual effect of approximately \(-0.0867\)
against roughly \(-0.0499\) in its comparison design. Establishment and career
age are distinct, but correlated. Career-age results are therefore presented as
a continuous refinement of known heterogeneity, not independent confirmation.
The direction is left two-sided. Focal tenure replaces career age in one
appendix specification and never enters jointly with it.

Exclusivity is excluded from the primary family because its multi-firm cell
failed the prior balance gate and because focal exposure mechanically scales
the attainable effect. If the existing exclusivity diagnostic is referenced,
the exposure-implied contrast must be reported beside it.

## TechFit

Primary TechFit uses all observable inventor and acquirer patents strictly
before the focal acquisition and IPC4 patent-count vectors. The same focal
acquirer is used for the treated inventor and every matched control roster row.
The five-year \(t=-5,\ldots,-1\) cosine is a fixed robustness measure.
Placeholder acquirers and zero-norm portfolios are ineligible rather than
assigned similarity zero.

There is no substitution rule. A null or imprecise full-history TechFit
result cannot be replaced by a significant five-year result. Likewise, the
1994--2008 companion cannot replace the 1994--2010 primary sample. Every frozen
variant is reported with its original designation.

## Inference, multiplicity, and precision

The primary family contains eight tests: four moderators by two outcomes.
All use the same 9,999 Webb deal-level multiplier draws. Two-way deal/inventor
inference is reported, and the wider interval and larger p-value govern. Holm
adjustment covers all eight governing p-values.

Before point estimates are written, each moderator-outcome pair receives a
prospective MDE assessment for its frozen contrast. The meaningful annual
thresholds are 0.053 patents and 0.020 active-patenting probability. MDE and
the Type-M exaggeration ratio are precision diagnostics, not publication
gates. All eight predeclared estimates remain in the same heterogeneity table.
Raw and Holm-adjusted governing p-values are shown together, so a conventionally
significant estimate is not hidden but is also not presented as
multiplicity-robust when it is not.

## Extensive and intensive accounting

For \(p=P(Y>0)\) and \(\mu=E(Y\mid Y>0)\), the patent-count gap is decomposed
under both valid orderings:

\[
(p_T-p_C)\mu_C+p_T(\mu_T-\mu_C)
\]

and

\[
(p_T-p_C)\mu_T+p_C(\mu_T-\mu_C).
\]

The symmetric average of the two orderings is the primary accounting split;
both orderings are reported. Components are calculated at \(t=-1\) and in the
average post period, differenced within cohort, and aggregated with frozen
cohort shares. Certification requires the components to sum to the ATT and
verifies rather than assumes that P5c makes both reference-period components
approximately zero. The total ATT is causal subject to the main design; the
conditional intensive component is descriptive because activity is
post-treatment selected.

## Reporting commitments

All frozen estimates are reported regardless of sign or significance.
Robustness variants never replace their primary specification. The
heterogeneity table shows all four moderators for both outcomes, together with
confidence intervals, raw p-values, Holm-adjusted p-values, MDEs, and Type-M
diagnostics. The aggregate five-year ATT and extensive/intensive patent
quantities remain separate headline results. Sample funnels, alternative
windows, joint models, and the `StrongestTie` extension remain in the complete
results package.
