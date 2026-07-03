# Common-support / trajectory matching (Phase 4, "restore PT" lever #2).
#
# Bins pre-deal patent stock (predeal_patent_stock_5y) into quintiles, crossed
# with ipc_primary_field, and checks -- BEFORE restricting anything -- whether
# each cell has enough distinct deal-year cohorts spread over enough calendar
# time for the not-yet-treated design to actually draw a comparison from
# similar units, rather than extrapolating across a covariate cell where only
# one or two cohorts are ever observed. Cells failing the coverage rule are
# dropped; the primary CS(2021) spec (universal base, anticipation = 1, lean
# xformla) is then re-run on the restricted sample and compared to the
# full-sample estimates from 08f_estimate_cs2021_primary.R.
#
# Coverage rule (pre-registered before restricting, not tuned on results):
#   a (patent-stock quintile x ipc_primary_field) cell is kept only if it
#   contains >= 3 distinct deal_year cohorts spanning >= 5 calendar years.
#   This is not a matching ALGORITHM (no 1:1 pairing) -- it's the coarsened-
#   cell common-support restriction the plan calls for, applied as a sample
#   restriction upstream of att_gt(), not a change to the estimator itself.
#
# Run from the project root after 06_build_event_panel.R:
#   Rscript 02_analysis/R/08g_common_support_matching.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
RESULTS <- file.path(BASE, "output", "results", "cs2021_common_support")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "did")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_result <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

banner("COMMON-SUPPORT CELL COVERAGE (before restricting)")

cell_coverage <- DBI::dbGetQuery(con, "
WITH unit AS (
  SELECT DISTINCT codinv, deal_id, deal_year, predeal_patent_stock_5y, ipc_primary_field
  FROM cs2021_estimation_panel
),
binned AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
  FROM unit
)
SELECT
  patent_stock_quintile,
  ipc_primary_field,
  COUNT(DISTINCT deal_year) AS n_cohorts,
  COUNT(DISTINCT codinv) AS n_units,
  MIN(deal_year) AS min_deal_year,
  MAX(deal_year) AS max_deal_year,
  MAX(deal_year) - MIN(deal_year) AS cohort_year_span
FROM binned
GROUP BY patent_stock_quintile, ipc_primary_field
ORDER BY patent_stock_quintile, ipc_primary_field
")
write_result(cell_coverage, "common_support_cell_coverage.csv")
print(cell_coverage)

cell_coverage$cell_passes <- cell_coverage$n_cohorts >= 3 & cell_coverage$cohort_year_span >= 5
n_pass <- sum(cell_coverage$cell_passes)
n_total <- nrow(cell_coverage)
n_units_pass <- sum(cell_coverage$n_units[cell_coverage$cell_passes])
n_units_total <- sum(cell_coverage$n_units)
message(sprintf(
  "\nCells passing coverage rule (n_cohorts>=3, span>=5y): %d / %d (%.1f%% of cells)",
  n_pass, n_total, 100 * n_pass / n_total
))
message(sprintf(
  "Units retained: %d / %d (%.1f%% of estimation sample)",
  n_units_pass, n_units_total, 100 * n_units_pass / n_units_total
))
write_result(cell_coverage, "common_support_cell_coverage_with_flag.csv")

banner("BUILDING MATCHED (COMMON-SUPPORT) SAMPLE")

allowed_cells <- cell_coverage[cell_coverage$cell_passes, c("patent_stock_quintile", "ipc_primary_field")]

full_panel <- DBI::dbGetQuery(con, "
SELECT
  CAST(codinv AS DOUBLE) AS codinv,
  CAST(deal_id AS INTEGER) AS deal_id,
  CAST(deal_year AS INTEGER) AS deal_year,
  CAST(calendar_year AS INTEGER) AS calendar_year,
  CAST(active_patenting AS DOUBLE) AS active_patenting,
  CAST(log_patent_count AS DOUBLE) AS log_patent_count,
  CAST(career_age_at_deal AS DOUBLE) AS career_age_at_deal,
  CAST(career_age_sq_at_deal AS DOUBLE) AS career_age_sq_at_deal,
  ipc_primary_field,
  CAST(log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
  CAST(predeal_patent_stock_5y AS DOUBLE) AS predeal_patent_stock_5y,
  CAST(log_group_size AS DOUBLE) AS log_group_size,
  CAST(log_deal_value AS DOUBLE) AS log_deal_value
FROM cs2021_estimation_panel
ORDER BY codinv, calendar_year
")
full_panel$ipc_primary_field <- factor(full_panel$ipc_primary_field)

# NTILE (rank-based) rather than cut() on quantile breakpoints: predeal_patent_stock_5y
# is heavily right-skewed with a median of 1 patent, so quantile breakpoints collide
# (e.g. the 20th/40th percentile can both be 1), which cut() rejects as non-unique.
# NTILE ranks ties consistently instead, matching the coverage-audit query above.
unit_bins <- DBI::dbGetQuery(con, "
  WITH unit AS (
    SELECT DISTINCT codinv, deal_id, predeal_patent_stock_5y
    FROM cs2021_estimation_panel
  )
  SELECT codinv, deal_id,
    NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
  FROM unit
")
unit_bins$codinv <- as.double(unit_bins$codinv)
full_panel <- merge(
  full_panel, unit_bins[c("codinv", "deal_id", "patent_stock_quintile")],
  by = c("codinv", "deal_id")
)

full_panel <- merge(
  full_panel,
  data.frame(
    patent_stock_quintile = allowed_cells$patent_stock_quintile,
    ipc_primary_field = allowed_cells$ipc_primary_field,
    in_common_support = TRUE
  ),
  by = c("patent_stock_quintile", "ipc_primary_field"), all.x = TRUE
)
full_panel$in_common_support[is.na(full_panel$in_common_support)] <- FALSE

matched_panel <- full_panel[full_panel$in_common_support, , drop = FALSE]
message(
  "Matched sample: ", length(unique(matched_panel$codinv)), " inventors | ",
  length(unique(matched_panel$deal_id)), " deals (full sample: ",
  length(unique(full_panel$codinv)), " inventors | ",
  length(unique(full_panel$deal_id)), " deals)"
)

xformla_lean <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

run_spec <- function(outcome, data, label) {
  section(paste(label, "|", outcome))
  set.seed(20260701L)
  att <- did::att_gt(
    yname = outcome, tname = "calendar_year", idname = "codinv", gname = "deal_year",
    xformla = xformla_lean, data = data, panel = TRUE, allow_unbalanced_panel = FALSE,
    control_group = "notyettreated", anticipation = 1, base_period = "universal",
    est_method = "dr", bstrap = FALSE, cband = FALSE, print_details = FALSE
  )
  dynamic <- did::aggte(
    att, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5,
    na.rm = TRUE, bstrap = FALSE, cband = FALSE
  )
  pretrend_p <- if (!is.null(att$Wpval) && length(att$Wpval) == 1) as.numeric(att$Wpval) else NA_real_

  cells <- data.frame(group = att$group, t = att$t, att = att$att, se = att$se)
  cells$event_time <- cells$t - cells$group
  cells <- cells[is.finite(cells$att) & is.finite(cells$se) & cells$se > 0 & cells$event_time <= -2, ]
  restricted <- cells[cells$event_time >= -4, ]
  restricted_chisq <- sum((restricted$att / restricted$se)^2)
  restricted_p <- pchisq(restricted_chisq, nrow(restricted), lower.tail = FALSE)

  coefs <- data.frame(
    outcome = outcome, label = label,
    n_inventors = length(unique(data$codinv)), n_deals = length(unique(data$deal_id)),
    event_time = dynamic$egt, att = dynamic$att.egt, se = dynamic$se.egt
  )
  message(sprintf(
    "Pretrend p (all pre-periods) = %.4g | restricted -4..-1 p = %.4g (n=%d cells)",
    pretrend_p, restricted_p, nrow(restricted)
  ))
  print(coefs[c("event_time", "att", "se")])

  list(
    coefs = coefs,
    diagnostics = data.frame(
      outcome = outcome, label = label,
      n_inventors = length(unique(data$codinv)), n_deals = length(unique(data$deal_id)),
      pretrend_p_all = pretrend_p, restricted_pretrend_p = restricted_p,
      restricted_n_cells = nrow(restricted)
    )
  )
}

banner("COMPARISON: FULL SAMPLE VS MATCHED (COMMON-SUPPORT) SAMPLE")

outcomes <- c("active_patenting", "log_patent_count")
all_results <- list()
for (oc in outcomes) {
  all_results[[paste0(oc, "_full")]] <- run_spec(oc, full_panel, "full_sample")
  all_results[[paste0(oc, "_matched")]] <- run_spec(oc, matched_panel, "matched_common_support")
}

all_coefs <- do.call(rbind, lapply(all_results, `[[`, "coefs"))
all_diag <- do.call(rbind, lapply(all_results, `[[`, "diagnostics"))
write_result(all_coefs, "common_support_dynamic_att_comparison.csv")
write_result(all_diag, "common_support_pretrend_comparison.csv")

banner("COMMON-SUPPORT MATCHING COMPLETE")
print(all_diag)
message("Outputs: ", RESULTS)
