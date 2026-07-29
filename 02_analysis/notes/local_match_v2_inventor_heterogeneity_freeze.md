# Local Match v2: inventor-level heterogeneity freeze

Frozen before opening any inventor-subgroup outcome estimate.

This is a post-results extension of the certified P5c/P6 full-cohort design. It
does not change the matched roster, entropy weights, headline patent-count ATT,
or its interpretation. The overall ATT remains the first result. Heterogeneity
is estimated only for patent counts and is used to distinguish mechanisms, not
to search for a favourable subgroup.

## Predetermined moderators

The primary moderators are career age (0--1, 2--3, 4+ years), five-year
pre-deal productivity (1, 2, 3+ patents), and team embeddedness. Focal-firm
exclusivity is estimated subject to a prospective support and power gate because
the non-exclusive treated group is small. Focal-group tenure is an appendix
alternative to career age because the two measures are strongly correlated.

Focal-group tenure is measured on the same \(t=-1\) clock as career age:
\[
\text{tenure}_{i,g-1}=(g-1)-\text{first focal-group patent year}.
\]
The original moderator build inherited an inclusive P3 count,
\(g-\text{first focal-group patent year}\), while career age used \(g-1\).
The one-year clock correction was made after the first heterogeneity estimates
were produced and before their use in the thesis. It subtracts the same
constant from every tenure value, so it cannot change matching, balance,
weights, point estimates, or inference; it only corrects the subgroup labels
from 1--2/3--4/5+ to 0--1/2--3/4+. Certification now requires
\(0\leq\text{tenure}_{i,g-1}\leq\text{career age}_{i,g-1}\).

Team embeddedness is strictly pre-treatment. For each roster observation, a
stable tie is a co-inventor appearing on at least two of the focal inventor's
patents during t=-5,...,-1. Embeddedness is the share of pre-deal patents with
at least one such tie, grouped as zero, partial, or all. No treatment or
post-treatment patent enters its construction.

## Estimand and inference

For each moderator, subgroup patent-count ATTs average t=+1,...,+5 and use t=-1
as the reference. Every subgroup is standardized to the same full-treated
acquisition-cohort shares over the cohorts in which all of that moderator's
groups have treated and control support. The 1994--2010 estimate is primary and
1994--2008 is the right-censoring companion.

Inference uses 9,999 Webb deal-level multiplier draws. Two-way deal/inventor
clustering is reported prominently, and the wider interval governs. Contrasts
within a moderator are tested jointly; moderator omnibus p-values are
Holm-adjusted across the four primary/conditional moderators. The meaningful
heterogeneity contrast is frozen at 0.053 annual patents, the magnitude of the
headline full-cohort ATT.

## Prospective reporting gates

A moderator group is main-text eligible only if it contains at least 500
treated inventors, has at least 15 effective treated deals, no treated deal
exceeds 25% of its treated mass, and its residual within-group balance has
maximum absolute SMD at or below 0.10. Failed gates do not delete estimates:
they move them to the appendix and are reported as descriptive or underpowered.

The package will report the overall certified ATT beside all predeclared
subgroups, regardless of sign or significance. Team embeddedness is retained
even if it fails the main-text gate because feasibility itself is informative
about whether stable pre-deal collaboration networks can be studied in this
sample.
