# Monday Classification Checklist

## Objective

Re-align the current code with the revised empirical design before producing initial results.

The main sample must be the pre-deal target-inventor cohort. Stayers remain central to the thesis, but they are a post-deal pathway within this cohort, not the object used to define the main sample.

## Frozen Design Decisions

### Treated cohort

An inventor belongs to the treated target-inventor cohort for deal `d` if:

```text
latest observed affiliation in [deal_year - 5, deal_year - 1] equals target_group
```

This rule is already conceptually correct and should remain the cohort definition.

### Post-deal classification window

Use the common post-deal window:

```text
[deal_year, deal_year + 5]
```

Every post-deal status must be defined over this same window.

### Post-deal statuses

The status variable should have four main values:

| Status | Definition |
|--------|------------|
| `T_STAYER` | At least one post-deal patent affiliated with `acquirer_group` |
| `T_LEAVER` | No post-deal acquirer patent, but at least one post-deal patent with a group different from `target_group` |
| `T_NO_POST_5Y` | No observed patent in the five-year post-deal window |
| `T_UNRESOLVED_TARGET_POST` | Post-deal patenting exists, but only under the original `target_group` |

Use `T_NO_POST_5Y` in outputs instead of `T_EXIT`. It means no observed EPO patenting within five years, not confirmed labor-market exit.

## Current Code Gap

### `04c_build_prelim_own_status.R`

Current behavior:

- Builds `cassi_deal_spine`.
- Builds `cassi_deal_group_spine`.
- Uses latest pre-deal affiliation to define target-side inventors.
- Classifies only:
  - `T_STAYER`
  - `T_LEAVER`

Needed change:

- Replace binary status logic with four-way status logic.
- Keep the latest-pre-affiliation target rule.
- Add post-deal patenting diagnostics.
- Add censoring flags.

### `06_preliminary_results.R`

Current behavior:

- Builds `stayer_event_panel_prelim`.
- Restricts the event panel to `type = 'T_STAYER'`.
- Produces stayer-only patent-count figures.

Needed change:

- Build event panel for all target-side inventors.
- Keep status attached as a decomposition variable.
- Produce one figure for the full target cohort and one figure for `T_STAYER`.

## Implementation To-Dos For Tuesday

### 1. Update `inventor_status_own`

Add post-deal variables:

```text
has_post_patent
has_acquirer_post_patent
has_target_post_patent
has_other_post_patent
first_post_patent_year
first_post_group
n_post_patent_years
n_acquirer_post_years
n_target_post_years
n_other_post_years
```

Add censoring variables:

```text
post_window_observable = deal_year + 5 <= 2015
no_post_5y_censored = type == 'T_NO_POST_5Y' & deal_year + 5 > 2015
full_window_sample = deal_year BETWEEN 1993 AND 2010
```

Use status assignment:

```text
if has_acquirer_post_patent:
    T_STAYER
else if not has_post_patent:
    T_NO_POST_5Y
else if has_other_post_patent:
    T_LEAVER
else:
    T_UNRESOLVED_TARGET_POST
```

### 2. Preserve multi-exposure handling

Keep earliest exposure per inventor:

```text
ROW_NUMBER() OVER (PARTITION BY codinv ORDER BY deal_year, cassi_deal_group_id)
```

Keep diagnostics:

```text
n_candidate_exposures
multi_exposure_inventor
```

### 3. Update validation outputs

Write audit tables for:

```text
status counts overall
status counts for full-window sample
status counts by deal year
multi-exposure counts
censoring counts
reference validation for T_STAYER and T_LEAVER
```

The Cassi-Ornaghi reference validation will remain imperfect because the reference is closer to a spell classification, while our design is a fixed-window event-study cohort.

### 4. Update preliminary results script

Rename or rebuild the table from:

```text
stayer_event_panel_prelim
```

to something closer to:

```text
target_inventor_event_panel_prelim
```

Panel requirements:

```text
event_time = -5 to +5
one row per inventor-deal-event_time
year = deal_year + event_time
left join inventor_year
zero-fill missing patent_count and fractional_patent_count
active_patenting = patent_count > 0
```

### 5. First result outputs

Produce:

```text
Table 1: sample construction and status counts
Figure 1: mean patent_count by event_time for all target inventors
Figure 2: mean patent_count by event_time for T_STAYER inventors
Figure 3: active_patenting by event_time for all target inventors, if time allows
```

## Non-Goals For This Week

Do not start:

```text
CS(2021)
TechDrift
DealSim
OECD quality outcomes
Heckman or Lee bounds
financial controls
full matching design
```

These belong after the first status table and event profiles are stable.
