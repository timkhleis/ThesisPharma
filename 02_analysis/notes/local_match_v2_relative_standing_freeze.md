# Local Match v2: predicted relative-standing loss freeze

Frozen before opening any outcome estimate from this package. The package leaves
the certified 1993--2010 P5c roster, entropy weights, outcomes, and headline ATT
unchanged. It extends the predeclared inventor-productivity heterogeneity result
with a theory-facing, predetermined moderator.

## Construct

For each roster inventor, productivity is the number of distinct patent
applications assigned to the inventor's focal organization during
\(g-5,\ldots,g-1\). Target standing is the percentage of productive inventors
in the focal organization with strictly lower productivity. Projected combined
standing is the analogous percentage after pooling the focal organization with
the treated deal's acquirer. Predicted relative-standing loss is target standing
minus projected combined standing, in percentage points. Ties receive the same
standing. Event time zero and every post-treatment observation are inaccessible
to the moderator builder.

For treated inventors, the focal organization is the acquisition target. For a
matched control, it is the control inventor's certified focal organization; the
control is then hypothetically pooled with the treated deal's acquirer. This
defines a predetermined pseudo-loss on the same scale for both arms.

Deals with missing or placeholder acquirer identifiers are ineligible. An
inventor appearing in both organizations is counted once in the combined pool,
with distinct applications counted across both organizations.

## Estimands

Patent count is primary and active patenting is a co-reported companion. The
outcome is the existing change from \(t=-1\) to the annual mean over
\(t=+1,\ldots,+5\). The primary moderator coefficient is the change in the ATT
associated with a ten-percentage-point increase in predicted standing loss.

The primary regression includes cohort fixed effects, treatment, standing loss,
the treatment--standing-loss interaction, and the existing predetermined
productivity, career-age, and persistent-team controls. The discriminating
horse race adds the treatment--absolute-productivity interaction. A negative
standing-loss interaction after this addition is the result that distinguishes
relative standing from absolute productivity.

Because the outcome-blind census shows a mass point at zero, no full-sample
interquartile contrast or tercile split is allowed. A secondary specification
within the already defined three-or-more-patent group compares positive loss
with no loss or a predicted gain. A Kapoor--Lim top-20 split is appendix-only
and excludes focal organizations with fewer than five productive inventors.

## Diagnostics and inference

The package must:

1. reproduce the overall ATT on the standing-eligible subset;
2. report treated and control support, weighted balance, deal concentration,
   and the complete standing-loss distribution before interpretation;
3. estimate the standing gradient at each pre-period lead \(t=-5,\ldots,-2\)
   relative to \(t=-1\), with an omnibus max-|t| trajectory diagnostic. These
   years overlap the five-year moderator window, so this is not an independent
   held-out pretrend test. It instead asks whether the post-deal gradient is
   already visible in the patent path used to define the moderator;
4. use 9,999 Webb deal-level multiplier draws and two-way deal/inventor
   clustering, with the wider interval and larger p-value governing;
5. apply Holm adjustment across the two primary outcome gradients; and
6. retain every frozen estimate regardless of sign or significance.

The existing balance threshold of maximum absolute SMD 0.10, minimum 500
treated inventors, minimum 15 effective treated deals, and maximum 25 percent
treated mass from one deal continues to govern subgroup language. Statistical
significance cannot repair a failed support, balance, or trajectory diagnostic.

## Interpretation

The measure is called patent-based predicted relative-standing loss. It does
not observe titles, authority, autonomy, influence, or perceived status.
Results may therefore be described as consistent with relative-standing loss,
not as direct mediation evidence.
