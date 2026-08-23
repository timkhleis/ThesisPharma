# Initially retained support-threshold census

This outcome-blind census separates two restrictions that operate at different
levels in the initially retained analysis.

First, every initially retained treated inventor inherits the full-cohort local
support decision. The rules requiring one control from one firm, two controls
from two firms, or three controls from two firms are defined per treated
inventor in that original donor graph.

Second, the separately balanced retained design requires a symmetric retained
comparison population. This restriction operates at the deal-stack level. The
current design retains a stack when it contains at least one retained treated
inventor and at least one retained control row from one retained-control firm.
It does not require three retained controls for each treated inventor. The
number of retained-control firms is a dependence diagnostic because entropy
balancing pools control rows within acquisition cohorts.

The census therefore reports two panels rather than combining the restrictions
into one misleading coverage statistic:

1. the three inherited per-inventor rules among all inventors classified as
   initially retained; and
2. the three analogous deal-stack thresholds applied to the current retained
   control pool.

The inherited relaxed-rule counts are recovery ceilings, not alternative
stayer estimation samples. An inventor admitted by a relaxed full-cohort rule
still needs an initially retained control analogue, admissible balance, and new
retained-sample weights. No outcome or treatment-effect object enters this
census.

Run from the amendment worktree root:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' `
  02_analysis\R\69_run_lmv2_initially_retained_support_census.R
```

Outputs are written to
`02_analysis/output/audit/local_match_v2_1993_amendment/INITIALLY_RETAINED_SUPPORT_CENSUS`.

## Realized census

### Inherited per-inventor support

| Rule in the original donor graph | Supported inventors | Coverage | Deals represented |
|---|---:|---:|---:|
| at least 1 control from at least 1 firm | 3,016 | 93.66% | 168 |
| at least 2 controls from at least 2 firms | 2,855 | 88.66% | 163 |
| at least 3 controls from at least 2 firms | 2,807 | 87.17% | 162 |

Moving from the preferred inherited three-control, two-firm rule to two
controls from two firms adds 48 inventors, or 1.49 percentage points of the
initially retained population. Moving to one control from one firm adds a
further 161 inventors. Even the permissive rule leaves 204 initially retained
inventors with no admissible control.

The relaxed-rule increments are strongly selected. Relative to inventors
passing the inherited three-control, two-firm rule, the 48 inventors added by
the two-control rule have standardized differences of 0.79 in log five-year
patent count, 0.97 in career age, and 0.64 in target-group tenure. The 161
inventors added only by the one-control rule have corresponding differences of
0.85, 0.67, and 0.45. Their median nearest-control distances are 1.12 and 1.23,
compared with 0.31 for the preferred inherited sample. Relaxing inherited
support therefore recovers more senior and prolific inventors by admitting
substantially thinner and more distant comparisons.

### Retained-control deal-stack support

| Deal-stack rule | Supported inventors | Coverage | Supported deals |
|---|---:|---:|---:|
| at least 1 retained control row from at least 1 firm, current rule | 2,792 | 86.71% | 153 |
| at least 2 retained control rows from at least 2 firms | 2,774 | 86.15% | 148 |
| at least 3 retained control rows from at least 2 firms | 2,773 | 86.12% | 147 |

The current retained design already adopts the permissive one-control,
one-firm rule at the deal-stack level. Tightening this rule to two firms would
remove 18 treated inventors across five small stacks; adding a third retained
control row would remove one additional inventor and deal. These thresholds do
not measure how many retained controls each treated inventor has. They measure
the pooled retained-control population available to an entire deal stack, and
the entropy estimator balances controls at the cohort level. The two-firm rule
is therefore appropriately retained as a dependence sensitivity rather than a
per-inventor identification requirement.

## Decision

The two layers warrant different choices. The current one-control, one-firm
retained-stack rule should remain the primary S3 rule because the estimator
does not require a separate retained match for each treated inventor and the
stricter stack rules only discard small stacks. The inherited three-control,
two-firm rule remains defensible because relaxing it changes which treated
inventors enter through much weaker original comparisons. The nearby
two-control, two-firm alternative recovers only 48 initially retained
inventors. The one-control, one-firm inherited alternative recovers 209 in
total, but this is an upper recovery ceiling: those inventors still require a
retained-control analogue, feasible balance, and newly estimated weights.

The thesis should therefore state that the initially retained analysis already
uses a permissive retained-control support condition. Its larger coverage loss
is inherited mainly from the original common-support design and from the need
to find controls who are themselves initially retained. Relaxing the original
rule would redefine the selected treated population and require a separately
certified retained-sample sensitivity; it cannot be implemented by simply
inserting the additional inventors into the frozen S3 weights.
