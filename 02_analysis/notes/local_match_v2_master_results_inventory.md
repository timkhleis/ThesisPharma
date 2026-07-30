# Local Match v2 master results inventory

This is the human-readable index of the certified thesis results. The CSV in `CURRENT_LOCAL_MATCH_V2/results_inventory` is authoritative.

| Status | Tier | Population | Outcome / analysis | Estimate | 95% CI | p |
|---|---|---|---|---:|---:|---:|
| primary | main | full target-inventor cohort | patent_count: entropy-balanced ATT | -0.0534 | [-0.0909, -0.0168] | 0.0077 |
| primary | main | full target-inventor cohort | end_of_observed_patenting: global career-endpoint ATT | 0.0306 | [0.0076, 0.0520] | 0.0103 |
| companion | secondary | full target-inventor cohort | active_patenting: entropy-balanced ATT | -0.0182 | [-0.0386, 0.0018] | 0.0715 |
| companion | secondary | full target-inventor cohort | fwcit5w_cassi_total: entropy-balanced ATT | 0.0446 | [0.0011, 0.0894] | 0.0447 |
| companion | secondary | full target-inventor cohort | pqii_scaled: entropy-balanced ATT | -0.0105 | [-0.0200, -0.0011] | 0.0291 |
| companion | secondary | full target-inventor cohort | patent_count: completion-year ATT (partially exposed calendar year) | -0.0377 | [-0.0650, -0.0104] | 0.0069 |
| companion | secondary | full target-inventor cohort | patent_count: completion-through-plus-five average annual ATT | -0.0508 | [-0.0866, -0.0153] | 0.0086 |
| companion | secondary | full target-inventor cohort | patent_count: completion-through-plus-five cumulative effect | -0.3047 | [-0.5197, -0.0916] | 0.0086 |
| primary | main heterogeneity | full target-inventor cohort | active_patenting: predeal_productivity high-minus-low contrast | -0.0044 | [-0.0134, 0.0046] | 0.3398 |
| primary | main heterogeneity | full target-inventor cohort | active_patenting: career_age high-minus-low contrast | 0.0059 | [-0.0097, 0.0215] | 0.4734 |
| primary | main heterogeneity | full target-inventor cohort | active_patenting: team_persistence high-minus-low contrast | -0.0177 | [-0.0425, 0.0072] | 0.1626 |
| primary | main heterogeneity | full target-inventor cohort | active_patenting: techfit high-minus-low contrast | -0.0150 | [-0.0329, 0.0028] | 0.0981 |
| primary | main heterogeneity | full target-inventor cohort | patent_count: predeal_productivity high-minus-low contrast | -0.0499 | [-0.0951, -0.0047] | 0.0306 |
| primary | main heterogeneity | full target-inventor cohort | patent_count: career_age high-minus-low contrast | -0.0017 | [-0.0357, 0.0323] | 0.9228 |
| primary | main heterogeneity | full target-inventor cohort | patent_count: team_persistence high-minus-low contrast | -0.1194 | [-0.2073, -0.0315] | 0.0079 |
| primary | main heterogeneity | full target-inventor cohort | patent_count: techfit high-minus-low contrast | -0.0497 | [-0.0897, -0.0096] | 0.0152 |
| descriptive | main decomposition | full target-inventor cohort | patent_count: P8 Shapley cessation | -0.0347 |  |  |
| descriptive | main decomposition | full target-inventor cohort | patent_count: P8 Shapley active_given_survival | -0.0045 |  |  |
| descriptive | main decomposition | full target-inventor cohort | patent_count: P8 Shapley patents_per_active_year | -0.0141 |  |  |
| descriptive | main decomposition | full target-inventor cohort | patent_count: P8 Shapley total | -0.0534 | [-0.0860, -0.0208] |  |
| companion | robustness | full target-inventor cohort | patent_count: entropy-balanced ATT | -0.0519 | [-0.0912, -0.0119] | 0.0163 |
| companion | stayer main | initially retained inventors | active_patenting: separately balanced selected-group ATT | -0.0143 | [-0.0477, 0.0190] | 0.3977 |
| companion | stayer main | initially retained inventors | patent_count: separately balanced selected-group ATT | -0.1072 | [-0.2043, -0.0101] | 0.0307 |
| companion | stayer main | initially retained inventors | patent_count: separately balanced selected-group ATT | -0.1205 | [-0.2233, -0.0176] | 0.0220 |
| companion | stayer main | initially_retained | active_years_5y: pre-deal descriptive mean | 1.9261 |  |  |
| companion | stayer main | leaver | active_years_5y: pre-deal descriptive mean | 1.6390 |  |  |
| companion | stayer main | no_post_patent | active_years_5y: pre-deal descriptive mean | 1.2443 |  |  |
| companion | stayer main | initially_retained | career_age: pre-deal descriptive mean | 3.8753 |  |  |
| companion | stayer main | leaver | career_age: pre-deal descriptive mean | 3.9159 |  |  |
| companion | stayer main | no_post_patent | career_age: pre-deal descriptive mean | 2.9667 |  |  |
| companion | stayer main | initially_retained | patent_stock_5y: pre-deal descriptive mean | 3.7797 |  |  |
| companion | stayer main | leaver | patent_stock_5y: pre-deal descriptive mean | 2.8482 |  |  |
| companion | stayer main | no_post_patent | patent_stock_5y: pre-deal descriptive mean | 1.7260 |  |  |
| companion | stayer secondary | initially retained inventors | fwcit5w_cassi_per_patent: separately balanced selected-group ATT | 0.1975 | [0.0474, 0.3563] | 0.0082 |
| companion | stayer secondary | initially retained inventors | fwcit5w_cassi_total: separately balanced selected-group ATT | 0.1189 | [-0.0389, 0.2880] | 0.1436 |
| companion | stayer secondary | initially retained inventors | pqii_conditional_mean: separately balanced selected-group ATT | -0.0062 | [-0.0336, 0.0197] | 0.6287 |
| companion | stayer secondary | initially retained inventors | pqii_observed: separately balanced selected-group ATT | -0.0275 | [-0.0620, 0.0063] | 0.1130 |
| companion | stayer secondary | initially retained inventors | pqii_scaled: separately balanced selected-group ATT | -0.0432 | [-0.0944, 0.0087] | 0.1016 |
| companion | stayer secondary | initially retained inventors | tech_drift: separately balanced selected-group ATT | 0.0091 | [-0.0144, 0.0324] | 0.4321 |
| descriptive | stayer decomposition | initially retained inventors | patent_count: P8 Shapley cessation | -0.0293 |  |  |
| descriptive | stayer decomposition | initially retained inventors | patent_count: P8 Shapley active_given_survival | -0.0057 |  |  |
| descriptive | stayer decomposition | initially retained inventors | patent_count: P8 Shapley patents_per_active_year | -0.0722 |  |  |
| descriptive | stayer decomposition | initially retained inventors | patent_count: P8 Shapley total | -0.1072 | [-0.2043, -0.0101] |  |
| descriptive | stayer decomposition | initially retained inventors | end_of_observed_patenting: global career-endpoint ATT | 0.0165 | [-0.0169, 0.0512] | 0.3583 |
| companion | diagnostic | full target-inventor cohort | patent_count: P5c controls restricted to focal-group patent activity through +5 | -0.0420 | [-0.0803, -0.0033] | 0.0350 |
| companion | diagnostic | initially retained inventors | patent_count: absolute ATT-to-largest-held-out-gap ratio | 0.9462 |  |  |
| companion | diagnostic | initially retained inventors | patent_count: absolute ATT-to-largest-held-out-gap ratio | 1.4068 |  |  |
| companion | diagnostic | full target-inventor cohort | patent_count: endpoint-restricted completion-year ATT | -0.0288 | [-0.0554, -0.0023] | 0.0335 |
| appendix | stayer heterogeneity | initially retained inventors | active_patenting: predeal_productivity high-minus-low contrast | -0.0062 | [-0.0520, 0.0397] | 0.7906 |
| appendix | stayer heterogeneity | initially retained inventors | active_patenting: career_age high-minus-low contrast | -0.0190 | [-0.0487, 0.0106] | 0.2066 |
| appendix | stayer heterogeneity | initially retained inventors | active_patenting: team_persistence high-minus-low contrast | 0.0064 | [-0.0504, 0.0633] | 0.8230 |
| appendix | stayer heterogeneity | initially retained inventors | active_patenting: techfit high-minus-low contrast | -0.0264 | [-0.0750, 0.0222] | 0.2844 |
| appendix | stayer heterogeneity | initially retained inventors | patent_count: predeal_productivity high-minus-low contrast | -0.2341 | [-0.5387, 0.0705] | 0.1309 |
| appendix | stayer heterogeneity | initially retained inventors | patent_count: career_age high-minus-low contrast | -0.1244 | [-0.2599, 0.0111] | 0.0716 |
| appendix | stayer heterogeneity | initially retained inventors | patent_count: team_persistence high-minus-low contrast | -0.1438 | [-0.3424, 0.0549] | 0.1547 |
| appendix | stayer heterogeneity | initially retained inventors | patent_count: techfit high-minus-low contrast | -0.2266 | [-0.4071, -0.0461] | 0.0142 |
| appendix | appendix | full target-inventor cohort | tech_drift: entropy-balanced ATT | 0.0076 | [-0.0256, 0.0409] | 0.6393 |
| failed_gate | appendix | initially retained at +1 | patent_count_t2_to_t5: landmark survivor-population ATT |  |  |  |
| appendix | appendix | untreated-firm pseudo events | patent_count: 2,000-draw mean placebo ATT | -0.0007 |  |  |
| appendix | appendix | untreated-firm pseudo events | reference_left_tail_probability: share of placebo ATTs at or below frozen P5c ATT | 0.0210 |  |  |
| appendix | appendix | untreated-firm pseudo events | rejection_share_5pct: 2,000-draw calibrated rejection share | 0.0555 |  |  |
| failed_gate | appendix | DealSim-eligible deals | DealSim inverted-U: prospective power gate | 7.6156 |  |  |
| descriptive | appendix | initially retained inventors | legacy_acquirer: pooled focal-normalized collaborator share | 0.0340 |  |  |
| descriptive | appendix | initially retained inventors | legacy_acquirer: focal-normalized collaborator share at t=1 | 0.0339 |  |  |
| descriptive | appendix | initially retained inventors | legacy_acquirer: focal-normalized collaborator share at t=2 | 0.0326 |  |  |
| descriptive | appendix | initially retained inventors | legacy_acquirer: focal-normalized collaborator share at t=3 | 0.0359 |  |  |
| descriptive | appendix | initially retained inventors | legacy_acquirer: focal-normalized collaborator share at t=4 | 0.0322 |  |  |
| descriptive | appendix | initially retained inventors | legacy_acquirer: focal-normalized collaborator share at t=5 | 0.0363 |  |  |
| descriptive | appendix | initially retained inventors | legacy_target: pooled focal-normalized collaborator share | 0.3458 |  |  |
| descriptive | appendix | initially retained inventors | legacy_target: focal-normalized collaborator share at t=1 | 0.4953 |  |  |
| descriptive | appendix | initially retained inventors | legacy_target: focal-normalized collaborator share at t=2 | 0.3777 |  |  |
| descriptive | appendix | initially retained inventors | legacy_target: focal-normalized collaborator share at t=3 | 0.2581 |  |  |
| descriptive | appendix | initially retained inventors | legacy_target: focal-normalized collaborator share at t=4 | 0.2494 |  |  |
| descriptive | appendix | initially retained inventors | legacy_target: focal-normalized collaborator share at t=5 | 0.1968 |  |  |
| descriptive | appendix | initially retained inventors | new_to_both: pooled focal-normalized collaborator share | 0.5127 |  |  |
| descriptive | appendix | initially retained inventors | new_to_both: focal-normalized collaborator share at t=1 | 0.4384 |  |  |
| descriptive | appendix | initially retained inventors | new_to_both: focal-normalized collaborator share at t=2 | 0.4957 |  |  |
| descriptive | appendix | initially retained inventors | new_to_both: focal-normalized collaborator share at t=3 | 0.5544 |  |  |
| descriptive | appendix | initially retained inventors | new_to_both: focal-normalized collaborator share at t=4 | 0.5875 |  |  |
| descriptive | appendix | initially retained inventors | new_to_both: focal-normalized collaborator share at t=5 | 0.5561 |  |  |
| descriptive | appendix | initially retained inventors | outside_group: pooled focal-normalized collaborator share | 0.1075 |  |  |
| descriptive | appendix | initially retained inventors | outside_group: focal-normalized collaborator share at t=1 | 0.0324 |  |  |
| descriptive | appendix | initially retained inventors | outside_group: focal-normalized collaborator share at t=2 | 0.0940 |  |  |
| descriptive | appendix | initially retained inventors | outside_group: focal-normalized collaborator share at t=3 | 0.1516 |  |  |
| descriptive | appendix | initially retained inventors | outside_group: focal-normalized collaborator share at t=4 | 0.1309 |  |  |
| descriptive | appendix | initially retained inventors | outside_group: focal-normalized collaborator share at t=5 | 0.2108 |  |  |
| descriptive | appendix | initially retained inventors | strict_persistent: baseline-tie focal-inventor coverage | 0.1960 |  |  |
| descriptive | appendix | initially retained inventors | strict_persistent: baseline-tie recurrence through +1 | 0.1916 |  |  |
| descriptive | appendix | initially retained inventors | strict_persistent: baseline-tie recurrence through +2 | 0.2627 |  |  |
| descriptive | appendix | initially retained inventors | strict_persistent: baseline-tie recurrence through +3 | 0.2892 |  |  |
| descriptive | appendix | initially retained inventors | strict_persistent: baseline-tie recurrence through +4 | 0.3086 |  |  |
| descriptive | appendix | initially retained inventors | strict_persistent: baseline-tie recurrence through +5 | 0.3102 |  |  |
| descriptive | appendix | initially retained inventors | weak_one_patent: baseline-tie focal-inventor coverage | 0.5847 |  |  |
| descriptive | appendix | initially retained inventors | weak_one_patent: baseline-tie recurrence through +1 | 0.0987 |  |  |
| descriptive | appendix | initially retained inventors | weak_one_patent: baseline-tie recurrence through +2 | 0.1321 |  |  |
| descriptive | appendix | initially retained inventors | weak_one_patent: baseline-tie recurrence through +3 | 0.1442 |  |  |
| descriptive | appendix | initially retained inventors | weak_one_patent: baseline-tie recurrence through +4 | 0.1586 |  |  |
| descriptive | appendix | initially retained inventors | weak_one_patent: baseline-tie recurrence through +5 | 0.1638 |  |  |
| companion | appendix | recurrent pre-deal inventors | patent_count: P8 recurrent Shapley cessation | -0.0925 |  |  |
| companion | appendix | recurrent pre-deal inventors | patent_count: P8 recurrent Shapley active_given_survival | -0.0241 |  |  |
| companion | appendix | recurrent pre-deal inventors | patent_count: P8 recurrent Shapley patents_per_active_year | -0.0535 |  |  |
| companion | appendix | recurrent pre-deal inventors | patent_count: P8 recurrent Shapley total | -0.1701 | [-0.2317, -0.1085] |  |
