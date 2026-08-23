# Local Match V2 support-threshold census

This diagnostic explains, but does not re-select, the frozen local-support
restriction. It is attached to the 1993--2010 amendment candidate because that
release supplies the current thesis-result audit. The diagnostic does not
promote the candidate release and does not change any headline treatment-effect
estimate.

The estimand remains the effect for treated inventors with credible local
comparisons. The two-firm condition is a source-diversity requirement: it avoids
calling an inventor supported when every admissible comparison comes from one
firm-specific environment. The three-control condition provides minimal local
redundancy within that diversified set: losing or perturbing one donor does not
collapse the comparison to a single inventor. These are defensible safeguards,
but their numerical cutoffs are conventions rather than identified constants.
Their credibility therefore depends on an outcome-blind sensitivity census.

The census evaluates exactly three nested, pre-specified rules, all defined per
treated inventor:

1. at least one control from at least one firm;
2. at least two controls from at least two firms; and
3. at least three controls from at least two firms, the frozen preferred rule.

A deal is supported under a rule if at least one eligible treated inventor in
that deal satisfies the rule. There is no separate deal-level support threshold.

The implementation reuses the frozen P5 candidate construction. Within each
cohort, it computes the candidate graph and standardization once under the
least restrictive one-control/one-firm census, retains only the number of
distinct controls and firms for each treated inventor, and then applies all
three predicates in R. It does not persist the full edge graph. Scalar standard
deviations are computed from the treated spine union the profile-specific donor
firms, while the technology-distance standard deviation is computed from the
pre-support matched candidate join. These populations are fixed before any of
the three support predicates is applied.

The script must reproduce the certified preferred roster key for key before it
will publish results. It also checks nesting, cohort-specific scaler signatures,
the hashes of the frozen builder and certified input artifacts, and the absence
of outcome or ATT inputs.

Coverage alone is not a selection criterion. The output therefore reports the
pre-treatment composition and candidate density of the inventors added by each
relaxation. If relaxed rules disproportionately recover older or more prolific
inventors, that does not by itself favor relaxation: those inventors may be
recovered precisely through thinner or poorer donor support. The composition
and candidate-quality tables must be interpreted jointly.

Run from the amendment worktree root:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' `
  02_analysis\R\68_run_lmv2_support_threshold_census.R
```

The output is written to
`02_analysis/output/audit/local_match_v2_1993_amendment/SUPPORT_THRESHOLD_CENSUS`.

## Realized census and interpretation

| Per-inventor rule | Supported inventors | Coverage | Supported deals |
|---|---:|---:|---:|
| at least 1 control from at least 1 firm | 28,605 | 96.33% | 343 of 345 |
| at least 2 controls from at least 2 firms | 27,802 | 93.63% | 343 of 345 |
| at least 3 controls from at least 2 firms (preferred) | 27,598 | 92.94% | 343 of 345 |

The third-control requirement excludes 204 inventors relative to the two-control,
two-firm rule, a coverage cost of 0.69 percentage points. Requiring a second
firm excludes a further 803 inventors relative to the one-control, one-firm
rule. Neither relaxation recovers either of the two unsupported deals. Thus,
the relaxed rules expand the inventor estimand but do not broaden deal-level
coverage.

The candidate distribution also shows that the preferred result is not driven
by a large mass just below the cutoff. Of 29,694 eligible inventors, 1,089 have
no admissible control, 440 have exactly one, 369 have exactly two, and 26,153
have at least ten. The preferred supported inventors have a median of 267
controls from 25 firms. By contrast, the 204 inventors added by the two-control,
two-firm rule have exactly two controls from two firms, and the 803 added only
by the one-control, one-firm rule have a median of one control from one firm.

The composition comparison makes a coverage-only decision inappropriate. The
inventors added by the two-control, two-firm rule are substantially more
prolific and senior than the preferred supported sample: the standardized
differences are 1.03 for log five-year patent count, 1.20 for career age, and
0.87 for target-group tenure. The corresponding differences for the additional
one-control, one-firm group are 0.70, 0.67, and 0.52. At the same time, their
median nearest-control distances are 1.13 and 1.19, respectively, compared with
0.12 in the preferred sample. Relaxation therefore recovers selected inventors
by accepting much thinner and more distant local comparisons. It should not be
described as an unambiguous improvement in representativeness.

These results make the preferred rule defensible. The two-firm requirement has
a direct design purpose: it prevents support from being supplied entirely by
one firm-specific environment. The third control adds minimal within-support
redundancy at a small coverage cost. The exact numbers two and three remain
conventional cutoffs rather than parameters identified by theory, but they are
not functioning as arbitrary sample trimming in this application. They trade
0.69 percentage points of coverage for avoiding comparisons that sit at the
edge of the admissible donor set. The appropriate interpretation is therefore
an ATT for inventors with credible local support, accompanied by an explicit
scope qualification for the older and more prolific inventors who remain
unsupported. The census does not justify extrapolating the preferred ATT to
that excluded population.
