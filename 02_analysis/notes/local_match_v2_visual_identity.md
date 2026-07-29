# Local Match v2 visual identity

## Objective

Every thesis figure should look like part of one empirical argument. The style
uses muted consulting-style colours, a white background, restrained grids,
short titles, and direct subtitles that state the comparison or identifying
qualification.

The implementation lives in
`02_analysis/R/00_lmv2_visual_style.R`.

## Semantic colour system

| Use | Colour | Hex |
|---|---|---|
| Headline estimate / treated group / titles | Forest green | `#1B4332` |
| Control group / counterfactual / secondary specification | Slate blue | `#4F6F8F` |
| Confidence band for green series | Pale sage | `#DCE8E1` |
| Confidence band for blue series | Pale blue | `#DDE6EE` |
| Placebo or held-out diagnostic | Muted amber | `#C28B3C` |
| Identification caution or failed diagnostic | Muted brick | `#A65F5B` |
| Fifth categorical series where required | Muted plum | `#766A8F` |
| Body text, axes, and reference lines | Charcoal/grey | `#2F3A3F`, `#6B7280` |

Colour never encodes treatment status alone. Treated paths use solid lines and
circles; placebo-control paths use long-dashed lines and triangles. Main
figures must remain interpretable in grayscale.

## Figure rules

1. Use forest green for the thesis's main empirical object. Do not change the
   headline colour across outcomes.
2. Use slate blue for controls and alternate specifications.
3. Use amber for diagnostics regardless of whether they pass. Use brick only
   when the figure explicitly communicates an identification caution.
4. Use pale fills at low opacity for uncertainty. Do not use saturated
   confidence bands.
5. Use a grey horizontal zero line and a thin dashed event-time line. The
   acquisition boundary is placed consistently at \(t=0\), or at \(-0.5\)
   when separating pre- and post-treatment intervals.
6. Use a sans-serif font, sentence-case titles, and at most one subtitle.
   Captions contain inference, sample, and reference-period details.
7. Avoid rainbow palettes, heavy borders, three-dimensional effects, and
   outcome-dependent colour choices.
8. Export every final figure as a 320-dpi PNG and a vector PDF at the same
   aspect ratio.

## Main-text visual sequence

1. **Raw treated path:** forest line and pale-sage interval.
2. **Recruitment fingerprint:** five muted categorical colours with identical
   line weight; the qualifying-gap legend explains the mechanical shift.
3. **Unmatched placebo DiD:** treated forest/solid/circle and control
   blue/dashed/triangle, followed by forest DiD coefficients.
4. **Balance love plot:** before weighting in grey, after weighting in forest;
   the 0.10 SMD threshold is a muted brick reference line.
5. **Matched event study:** forest estimate and pale-sage interval.
6. **LOYO forest plot:** headline in forest, LOYO specifications in slate blue,
   held-out pre-period diagnostics in amber.
7. **Extensive/intensive decomposition:** forest for extensive and slate blue
   for intensive; the caption states that the intensive component is
   descriptive.
8. **Secondary-outcome forest plot:** one common forest estimate style; colour
   never changes according to statistical significance.

The appendix follows the same mappings. Appendix status is communicated in
the title or caption, not by switching to a different visual theme.
