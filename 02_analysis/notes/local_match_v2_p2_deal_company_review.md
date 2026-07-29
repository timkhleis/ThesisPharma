# Local Matching v2: P2 Deal and Company Assignment Review

Status: P2 implementation and independent certification complete; final freeze
awaits package review. P3 has not started.

Design hash: `cabba2c523bf5abdeb44ba28e61dec2eeaedf5c9df8aa6fba1b7087361521c52`

## What the fresh audit corrects

The reproducible count for Cassi--Ornaghi `T_STAYER` rows in 1994--2010 is
6,331 across 240 deals. Before the approved promotions, 5,734 rows across 222
deals mapped to the identifier-strict spine. After promotion, 5,783 rows across
226 deals map to the primary spine. The earlier 6,330/5,731 figures were
produced by an ad hoc crosswalk and should be replaced by these scripted counts.

The previously reported 172 deals were not the number of assigned acquisition
deals. They were deals surviving the overly restrictive rule that required an
observed focal-entity patent in event times 1--5. After the approved promotions
and earliest-exposure rebuild, the primary treatment cohort contains 29,170
inventors across 343 deals. The deal spine contains 352 primary deals in
1994--2010; nine have no inventor who passes the direct-company and
latest-affiliation rules.

## The 18-deal Cassi--Ornaghi discrepancy

The original 597-row, 18-deal discrepancy is fully accounted for:

| Reason | Deals | Cassi--Ornaghi stayers |
|---|---:|---:|
| Four rule-based supplementary promotions | 4 | 49 |
| Three unresolved identifiers/events | 3 | 385 |
| Target-drop exclusions | 7 | 118 |
| Unusable acquirer | 1 | 25 |
| Divestitures | 3 | 20 |

After the four promotions, the remaining non-primary discrepancy is 548
stayers across 14 deals.

The four primary promotions are deals 62, 97, 98, and 374. Each has a unique
supplementary `target_nmb`, exact year and value, one target group, one acquirer
group, no target/acquirer drop, and no divestiture flag. Their acquirer-company
group is also constant in `g-1`, `g`, and `g+1`. Deal 451 satisfies the same
structural rule but is outside the 1994--2010 analysis window. Deal 200 fails
because its acquirer is missing/dropped.

The unresolved loss is highly concentrated:

- Deal 96 (Aventis CropScience--Bayer, 2001): 137 stayers. It has no canonical
  identifier, but five target companies move unanimously from group 101516 in
  2000 to group 101662 in 2001--2002.
- Deal 323 (Ciba--BASF, 2008): 243 stayers. Its noncanonical identifier is
  `a128`; four target companies move unanimously from group 109742 in 2007 to
  group 300742 in 2008--2009.
- Deal 298 (2008): five stayers. The exact year/value key corresponds to two
  canonical target events and therefore remains genuinely ambiguous.

Deals 96 and 323 are real, economically important acquisitions with unusually
strong company-history evidence, but they fail the locked automatic promotion
rule because the canonical identifier/drop-flag record is absent. The proposed
primary design therefore leaves them excluded and co-reports an explicitly
named, history-validated sensitivity adding them. Deal 298 stays excluded.

## Target-company and acquirer checks

The strict target bridge contains 1,684 deal-company rows. At `g-1`:

- zero target companies lack a group;
- zero target companies have ambiguous groups; and
- zero target-company groups disagree with the assigned deal target group.

Among 484 strict deals, 439 use the explicit acquirer company, 11 use a
target-post-group fallback, 32 have no usable post group, and two explicit
acquirer records are ineligible. For every fallback deal, all target companies
move from the assigned target group at `g-1` to the assigned acquirer group in
`g` and remain there in `g+1`. No strict deal has more than one assigned
acquirer group.

These checks support the target and acquirer group construction. The reviewed
assignment builder is now ported to the clean branch. A complete source rebuild,
two independent P2 builds, and the logical interface hashes are deterministic.

## Why another 1,021 Cassi--Ornaghi stayers fail the company rule

Within the 222 identifier-strict Cassi--Ornaghi deals, 1,021 stayer rows do not have a
canonical patent linked to a deal-specific legal target company during
`g-5,...,g-1`:

- 318 have their Cassi--Ornaghi target-status year before `g-5` and therefore
  differ because of the recruitment-window convention;
- 183 inventor-deal rows (182 distinct inventors) are absent from the canonical
  patent-inventor link;
- 118 exist in the canonical link but have no canonical patent in the five-year
  pre-window;
- 54 have canonical pre-window patents only at other groups; and
- 348 have canonical pre-window patents linked to the future acquirer group,
  not to a legal target company.

The 348-row bucket is specifically an ownership-relabeling limitation, not
Cassi--Ornaghi over-inclusion. A deterministic 20-case check and a full census
show that all 348 status companies belong to the target group at `g-1` and all
348 switch to the assigned acquirer group at `g`; 347 remain there at `g+1`.
Their canonical pre-period patent records carry the future-acquirer ownership
label. This is the last-owner problem corrected by Cassi--Ornaghi's Step II.

The raw-file check also clears P1. The source `patent_inventor.dta` and the
canonical table both contain exactly 4,313,558 rows and distinct
inventor-application pairs. None of the 182 missing inventor identifiers exists
in the raw bridge. They originate in the prepared production/status layer, not
from a link dropped by the P1 rebuild.

Thus the loss is not caused by one join bug. It reflects the five-year
recruitment rule, a genuine last-owner limitation, and differences between the
prepared Cassi--Ornaghi status layer and the raw patent-inventor bridge. Using
the prepared status label to repair these rows would make treatment assignment
depend on the benchmark outcome-classification file. The recommendation is to
keep the direct-company rule primary, characterize the 348 correctly, and
explain the crosswalk in the appendix.

## Downstream filters

Among the strict Cassi--Ornaghi stayers:

- 273 direct-company observations are reassigned to an earlier acquisition
  exposure. Every retained exposure predates the displaced one by 1--11 years;
  this is the intended earliest-exposure rule.
- 401 then fail the latest-affiliation/transition test. Their latest resolved
  group is the acquirer or another group, rather than the target; none is an
  unresolved null affiliation.
- 37 otherwise qualified observations lie on eight deals without a usable
  acquirer group and cannot enter the stayer classification.

One asymmetry remains deliberate. The current treated table includes 3,015
inventors whose latest year has multiple candidate groups but whose conservative
pre-treatment tie-breaker resolves to the target/acquirer. Controls require
`candidate_group_count == 1`. The treated cases already require a patent linked
to the deal-specific legal target company, which provides an anchor that a
generic control candidate does not have. The primary design therefore retains
the conservative treated tie-breaker as intended. The uniquely affiliated
treated cohort remains a required robustness check; it contains 25,628
inventors across 337 deals before the four supplementary promotions, and its
buffered first-post stayer sample still passes all power floors (3,353 stayers,
162 deals, raw deal ESS 26.07).

## Stayer definition and sample-period recommendation

The `t=1,...,5` positive-focal-output rule should be removed. It conditions
treated stayers on positive post-treatment output and mechanically understates
a negative productivity effect. Define a treated or control stayer by the
entity of the first observed post-event patent in `t=0,...,5`; event time zero
may classify status but never enters the post-treatment outcome sum, which
remains `t=1,...,5`.

After promotions and earliest-exposure reassignment, this rule yields 4,328
status-eligible stayers across 205 deals for 1994--2010, with raw deal ESS
33.92. The 1994--2008 companion contains 3,812 stayers across 173 deals, with
raw deal ESS 27.61. The unique-affiliation robustness contains 3,847 stayers
across 196 deals for 1994--2010 (ESS 32.88) and 3,414 across 165 buffered deals
(ESS 26.92). Every locked power floor passes.

Recommended timing:

- Patent Count and Active Patenting: 1994--2010 through `t=+5` as headline.
- Stayer classification and stayer outcomes: 1994--2010 through `t=+5` as
  headline; 1994--2008 as an identical-cohort companion.
- Absorbing Left: report both full and buffered `t=+5`. The buffered estimate is
  the censoring-clean result; the full estimate is the literature-comparable
  result. The earlier return audit suggests the practical bias is modest but
  not zero.
- Forward citations and PQII: let P6 certify the OECD fixed-window coverage.
  Use 1994--2010 if the OECD values are complete; otherwise use 1994--2008 as
  the primary quality sample. Do not infer incompleteness merely from the patent
  panel ending in 2015.

## Implemented P2 amendment

1. Deals 62, 97, 98, and 374 enter through the explicit supplementary rule.
2. Deals 96 and 323 remain outside the automatic primary spine and are reserved
   for the named company-history sensitivity; deal 298 remains excluded.
3. The authoritative deal-assignment builder runs from the clean branch.
4. The conservative pre-treatment treated-side tie-breaker remains primary; a
   separate robustness interface requires `candidate_group_count == 1`.
5. First-post focal-entity status replaces the positive-output stayer rule.
6. The source rebuild, two-pass determinism check, structural certification,
   and buffered-stayer power gate all pass. P3 remains blocked pending review.

The audit script is `02_analysis/R/15h_audit_lmv2_deal_company_assignment.R`.
Its CSV outputs are deterministic across repeated runs and are stored under
`02_analysis/output/audit/local_match_v2/P2/deal_company_review/`.
