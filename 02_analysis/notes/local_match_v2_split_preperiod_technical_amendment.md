# Split-preperiod technical amendment

This amendment was written after the first frozen implementation exposed two
numerical feasibility issues. The support and balance specification is
unchanged.

The first implementation supported 3,414 of 3,483 early-recruited treated
inventors (98.02%), but classified 15 of 16 cohort solves as infeasible. The
classification used two technical rules that were stricter than the design
freeze:

1. it rejected a finite entropy solution if any control weight was exactly
   zero after floating-point underflow; and
2. it required realized standardized imbalance below `1e-6`, although four
   otherwise finite solutions had residuals between `1.4e-6` and `1.1e-5`.

The corrected numerical contract is:

- final weights must be finite and nonnegative;
- treated weights remain strictly positive;
- total control mass must be positive and is normalized to treated mass;
- numerically zero donor weights are permitted and counted as zero in ESS;
- the exact-balance numerical tolerance is `2e-5` standardized units.

This does not alter recruitment, U2 eligibility, IPC4 support, nearest-firm
or nearest-inventor selection, balance variables, event windows, or the
estimand.

The first implementation mechanically proceeded to a cohort-2002-only
outcome before the low-feasibility state was reviewed. That preliminary
estimate was imprecise and is not used to motivate this amendment. It remains
in the audit history. This amendment responds only to the solver feasibility
diagnostics above.

The amended run still produced only four feasible cohorts and its untouched
leads rejected jointly. On the user's instruction, HonestDiD is therefore not
part of the default run: the design is archived as an infeasible
identification diagnostic. Passing `--honestdid` retains an explicit route to
evaluate a grid from 0 to 3 in increments of 0.1 with 500 numerical grid
points, but this computation is not needed for the current results package.
