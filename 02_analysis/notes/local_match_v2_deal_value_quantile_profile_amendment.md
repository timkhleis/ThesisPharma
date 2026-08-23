# Deal-value quantile profile amendment

Status: frozen before opening outcomes for this analysis.

The exploratory financial-size profile forms quartiles and deciles over
acquisitions, not inventors, using `target_value` and a deterministic
`deal_id` tie-break. A build aborts if a boundary splits equal deal values.
The outcome is the average annual patent-count ATT over event years `+1`
through `+5`, relative to `-1`.

The certified P5c relative weights remain fixed. Control mass is rescaled only
within cohort-by-bin cells. The release reports each bin, the top-minus-bottom
contrast, and joint equality tests with both deal-level Webb wild-bootstrap
and two-way deal-inventor inference; the more conservative result governs.

This is post-hoc exploratory heterogeneity. It does not replace the headline
inventor-weighted estimand, and subgroup significance patterns are not treated
as evidence of heterogeneity. The initially retained version is additionally
a post-treatment-selected-population description.

Reproducible implementations:

- `48r_build_lmv2_deal_value_quantiles.R` freezes either declared roster.
- `48s_run_lmv2_deal_value_quantiles.R` estimates and certifies the profile.
- `74_run_lmv2_retained_deal_value_quantiles.R` constructs and runs the
  initially retained profile from the certified retained panel.
