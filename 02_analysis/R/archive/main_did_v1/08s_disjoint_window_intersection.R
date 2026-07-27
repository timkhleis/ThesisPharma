# Diagnostic 3: Disjoint-window intersection test (real treated data)
#
# Tests whether relocating the productivity covariate to a structurally
# non-overlapping window [deal_year-10, deal_year-6] (no calendar-year overlap
# with the tested pre-period [-5, -1]) removes the pre-trend hump.
#
# Design: substitute ONLY log_predeal_patent_stock, holding population,
# outcomes, and all other covariates fixed. This isolates whether covariate-
# window overlap is the mechanical driver.
#
# Run from project root after 06_build_event_panel.R and 08h_primary_matched_bootstrap.R:
#   Rscript 02_analysis/R/08s_disjoint_window_intersection.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
CS_DIR  <- file.path(BASE, "output", "results", "cs2021_common_support")
RESULTS <- file.path(BASE, "output", "results", "cs2021_disjoint_window")
AUDIT   <- file.path(BASE, "output", "audit", "disjoint_window_intersection")
FIGS    <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "did", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(AUDIT, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_csv_base <- function(df, filename) {
  utils::write.csv(df, file.path(AUDIT, filename), row.names = FALSE, na = "")
}
write_result <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

banner("DISJOINT-WINDOW INTERSECTION TEST (Diagnostic 3)")
section("Building sample (deals in [1998, 2015])")

# Restrict to deals with deal_year in [1998, 2015] so deal_year-10 >= 1988
working_sample <- DBI::dbGetQuery(con, "
  SELECT CAST(codinv AS DOUBLE) AS codinv,
         CAST(deal_id AS INTEGER) AS deal_id,
         CAST(deal_year AS INTEGER) AS deal_year
  FROM target_cohort_own
  WHERE deal_year BETWEEN 1998 AND 2015
")

n_working <- nrow(working_sample)
n_working_deals <- length(unique(working_sample$deal_id))

message("Working sample: ", n_working, " inventor-deal rows from ",
        n_working_deals, " deals (in valid date range)")

write_csv_base(data.frame(
  metric = c("n_inventors_total", "n_deals_total"),
  count = c(length(unique(working_sample$codinv)), n_working_deals)
), "working_sample_counts.csv")

section("Step A: Standard spec on intersection sample (gate check)")

# Load the real 08h panel and filter to intersection sample
real_panel <- DBI::dbGetQuery(con, "
  SELECT CAST(codinv AS DOUBLE) AS codinv,
         CAST(deal_id AS INTEGER) AS deal_id,
         CAST(deal_year AS INTEGER) AS deal_year,
         CAST(calendar_year AS INTEGER) AS calendar_year,
         CAST(active_patenting AS DOUBLE) AS active_patenting,
         CAST(log_patent_count AS DOUBLE) AS log_patent_count,
         CAST(career_age_at_deal AS DOUBLE) AS career_age_at_deal,
         CAST(career_age_sq_at_deal AS DOUBLE) AS career_age_sq_at_deal,
         ipc_primary_field,
         CAST(log_predeal_patent_stock AS DOUBLE) AS log_predeal_patent_stock,
         CAST(log_group_size AS DOUBLE) AS log_group_size,
         CAST(log_deal_value AS DOUBLE) AS log_deal_value
  FROM cs2021_estimation_panel
  WHERE deal_year BETWEEN 1998 AND 2015
")

real_panel$ipc_primary_field <- factor(real_panel$ipc_primary_field)

# Rebuild common-support matched sample on working sample only
working_codinv_deals <- interaction(working_sample$codinv, working_sample$deal_id, drop = TRUE)
real_panel_working <- real_panel[interaction(real_panel$codinv, real_panel$deal_id, drop = TRUE) %in% working_codinv_deals, ]

message("Working sample panel: ", nrow(real_panel_working), " rows")

# Rebuild common-support cells (same rule as 08h)
cell_coverage <- DBI::dbGetQuery(con, "
  WITH unit AS (
    SELECT DISTINCT CAST(codinv AS DOUBLE) AS codinv, CAST(deal_id AS INTEGER) AS deal_id,
           CAST(deal_year AS INTEGER) AS deal_year, predeal_patent_stock_5y, ipc_primary_field
    FROM cs2021_estimation_panel
    WHERE deal_year BETWEEN 1998 AND 2015
  ),
  binned AS (
    SELECT *, NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
    FROM unit
  )
  SELECT patent_stock_quintile, ipc_primary_field,
         COUNT(DISTINCT deal_year) AS n_cohorts,
         MAX(deal_year) - MIN(deal_year) AS cohort_year_span
  FROM binned
  GROUP BY patent_stock_quintile, ipc_primary_field
")

cell_coverage$cell_passes <- cell_coverage$n_cohorts >= 3 & cell_coverage$cohort_year_span >= 5
allowed_cells <- cell_coverage[cell_coverage$cell_passes, c("patent_stock_quintile", "ipc_primary_field")]

unit_bins <- DBI::dbGetQuery(con, "
  WITH unit AS (
    SELECT DISTINCT CAST(codinv AS DOUBLE) AS codinv, CAST(deal_id AS INTEGER) AS deal_id,
           predeal_patent_stock_5y
    FROM cs2021_estimation_panel
    WHERE deal_year BETWEEN 1998 AND 2015
  )
  SELECT codinv, deal_id,
         NTILE(5) OVER (ORDER BY predeal_patent_stock_5y, codinv, deal_id) AS patent_stock_quintile
  FROM unit
")

unit_bins$codinv <- as.double(unit_bins$codinv)
real_panel_working <- merge(real_panel_working, unit_bins, by = c("codinv", "deal_id"))
real_panel_working <- merge(
  real_panel_working,
  transform(allowed_cells, in_common_support = TRUE),
  by = c("patent_stock_quintile", "ipc_primary_field"), all.x = TRUE
)
real_panel_working$in_common_support[is.na(real_panel_working$in_common_support)] <- FALSE
matched_working <- real_panel_working[real_panel_working$in_common_support, ]
matched_working <- matched_working[order(matched_working$codinv, matched_working$calendar_year), ]

message("Matched working sample: ", length(unique(matched_working$codinv)), " inventors, ",
        length(unique(matched_working$deal_id)), " deals")

# Run standard spec on matched intersection
xformla_standard <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock + log_group_size + log_deal_value

section("Running Step A DiD (standard spec on intersection sample)...")

set.seed(20260701L)
att_stepA <- did::att_gt(
  yname = "active_patenting", tname = "calendar_year", idname = "codinv", gname = "deal_year",
  xformla = xformla_standard, data = matched_working, panel = TRUE,
  allow_unbalanced_panel = FALSE,
  control_group = "notyettreated", anticipation = 1, base_period = "universal",
  est_method = "dr", bstrap = TRUE, biters = 999,
  clustervars = "deal_id", cband = TRUE, print_details = FALSE
)

dynamic_stepA <- did::aggte(
  att_stepA, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5,
  na.rm = TRUE, bstrap = TRUE, biters = 999, clustervars = "deal_id", cband = TRUE
)

# Debug: inspect structure
message("dynamic_stepA structure:")
message("egt length: ", length(dynamic_stepA$egt))
message("att.egt length: ", length(dynamic_stepA$att.egt))
message("se.egt length: ", length(dynamic_stepA$se.egt))
message("c.egt length: ", if(!is.null(dynamic_stepA$c.egt)) length(dynamic_stepA$c.egt) else "NULL")

# Build coefs dataframe - use shorter vector length as guide
n_events <- length(dynamic_stepA$egt)
c_vals <- if(!is.null(dynamic_stepA$c.egt) && length(dynamic_stepA$c.egt) == n_events) {
  dynamic_stepA$c.egt
} else {
  rep(1.96, n_events)  # default to normal 95% CI
}

stepA_coefs <- data.frame(
  outcome = rep("active_patenting", n_events),
  step = rep("A_standard_spec", n_events),
  event_time = dynamic_stepA$egt,
  att = dynamic_stepA$att.egt,
  se = dynamic_stepA$se.egt,
  ci_low = dynamic_stepA$att.egt - c_vals * dynamic_stepA$se.egt,
  ci_high = dynamic_stepA$att.egt + c_vals * dynamic_stepA$se.egt,
  stringsAsFactors = FALSE
)

# Remove rows with NaN
stepA_coefs <- stepA_coefs[!is.na(stepA_coefs$att), ]

message("Step A ATT at key event times:")
key_events <- stepA_coefs[stepA_coefs$event_time %in% c(-4, -3, 0, 5), ]
if (nrow(key_events) > 0) {
  print(key_events)
} else {
  message("No coefficients found for key event times")
}

# Gate check: is the hump present at t=-3?
hump_rows <- stepA_coefs[stepA_coefs$event_time == -3, ]
hump_present <- if (nrow(hump_rows) > 0) {
  hump_rows$ci_low[1] > 0
} else {
  FALSE
}

message("\nGate check: Hump at t=-3 present? ", hump_present)

if (!hump_present) {
  message("\n*** GATE CHECK FAILED ***")
  message("The pre-trend hump is NOT present on the working sample.")
  message("This means: the hump either doesn't replicate in this population subset,")
  message("or the working-sample size restriction has attenuated it.")
  message("Stopping diagnostic to investigate further.")
  write_result(stepA_coefs, "step_A_coefs_hump_absent.csv")
  banner("DIAGNOSTIC 3: GATE CHECK FAILED (hump not replicated in working sample)")
  stop("Gate check failed: hump not present on working sample.")
}

message("\nGate check PASSED: hump is present. Proceeding to Step B...")
saveRDS(att_stepA, file.path(RESULTS, "att_gt_stepA_active_patenting.rds"))
saveRDS(dynamic_stepA, file.path(RESULTS, "aggte_stepA_active_patenting.rds"))

section("Step B: Alternate covariate (disjoint window) on same intersection sample")

# Compute log_predeal_patent_stock_alt over [deal_year-10, deal_year-6]
alt_productivity <- DBI::dbGetQuery(con, "
  SELECT CAST(c.codinv AS DOUBLE) AS codinv,
         CAST(c.deal_id AS INTEGER) AS deal_id,
         LN(1 + COALESCE(SUM(iy.patent_count), 0)) AS log_predeal_patent_stock_alt
  FROM (
    SELECT DISTINCT codinv, deal_id, deal_year FROM target_cohort_own
    WHERE deal_year BETWEEN 1998 AND 2015
  ) c
  LEFT JOIN inventor_year iy
    ON CAST(iy.codinv AS DOUBLE) = c.codinv
   AND iy.year BETWEEN c.deal_year - 10 AND c.deal_year - 6
  GROUP BY c.codinv, c.deal_id
")

# Merge into matched_working, replace the standard covariate
matched_working <- merge(matched_working, alt_productivity, by = c("codinv", "deal_id"))

# Run Step B with alternate covariate
xformla_alt <- ~ career_age_at_deal + career_age_sq_at_deal +
  ipc_primary_field + log_predeal_patent_stock_alt + log_group_size + log_deal_value

message("Running Step B DiD (alternate covariate [g-10, g-6])...")

set.seed(20260701L)
att_stepB <- did::att_gt(
  yname = "active_patenting", tname = "calendar_year", idname = "codinv", gname = "deal_year",
  xformla = xformla_alt, data = matched_working, panel = TRUE,
  allow_unbalanced_panel = FALSE,
  control_group = "notyettreated", anticipation = 1, base_period = "universal",
  est_method = "dr", bstrap = TRUE, biters = 999,
  clustervars = "deal_id", cband = TRUE, print_details = FALSE
)

dynamic_stepB <- did::aggte(
  att_stepB, type = "dynamic", balance_e = 5, min_e = -4, max_e = 5,
  na.rm = TRUE, bstrap = TRUE, biters = 999, clustervars = "deal_id", cband = TRUE
)

# Build coefs dataframe - handle potential length mismatches
n_events_B <- length(dynamic_stepB$egt)
c_vals_B <- if(!is.null(dynamic_stepB$c.egt) && length(dynamic_stepB$c.egt) == n_events_B) {
  dynamic_stepB$c.egt
} else {
  rep(1.96, n_events_B)  # default to normal 95% CI
}

stepB_coefs <- data.frame(
  outcome = rep("active_patenting", n_events_B),
  step = rep("B_alt_covariate", n_events_B),
  event_time = dynamic_stepB$egt,
  att = dynamic_stepB$att.egt,
  se = dynamic_stepB$se.egt,
  ci_low = dynamic_stepB$att.egt - c_vals_B * dynamic_stepB$se.egt,
  ci_high = dynamic_stepB$att.egt + c_vals_B * dynamic_stepB$se.egt,
  stringsAsFactors = FALSE
)

# Remove rows with NaN
stepB_coefs <- stepB_coefs[!is.na(stepB_coefs$att), ]

message("\nStep B ATT at key event times:")
key_events_B <- stepB_coefs[stepB_coefs$event_time %in% c(-4, -3, 0, 5), ]
if (nrow(key_events_B) > 0) {
  print(key_events_B)
}

# Compare: did the hump shrink?
stepA_hump_row <- stepA_coefs[stepA_coefs$event_time == -3, ]
stepB_hump_row <- stepB_coefs[stepB_coefs$event_time == -3, ]

stepA_hump <- if (nrow(stepA_hump_row) > 0) stepA_hump_row$att[1] else NA
stepB_hump <- if (nrow(stepB_hump_row) > 0) stepB_hump_row$att[1] else NA

if (!is.na(stepA_hump) && !is.na(stepB_hump) && stepA_hump != 0) {
  shrinkage_pct <- (1 - stepB_hump / stepA_hump) * 100
} else {
  shrinkage_pct <- NA
}

message("\n*** SHRINKAGE CHECK ***")
message("Step A hump (t=-3): ", if (is.na(stepA_hump)) "NA" else round(stepA_hump, 4))
message("Step B hump (t=-3): ", if (is.na(stepB_hump)) "NA" else round(stepB_hump, 4))
if (!is.na(shrinkage_pct)) {
  message("Shrinkage: ", round(shrinkage_pct, 1), "%")
  message("Passes >50% threshold? ", shrinkage_pct > 50)
} else {
  message("Shrinkage: NA (cannot compute)")
}

section("Saving results and generating comparison figure")

saveRDS(att_stepB, file.path(RESULTS, "att_gt_stepB_active_patenting.rds"))
saveRDS(dynamic_stepB, file.path(RESULTS, "aggte_stepB_active_patenting.rds"))

# Combined comparison table
comparison <- rbind(stepA_coefs, stepB_coefs)
write_result(comparison, "stepA_vs_stepB_comparison.csv")

# Figure: side-by-side comparison
p <- ggplot2::ggplot(comparison, ggplot2::aes(x = event_time, y = att, colour = step, group = step)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = ci_low, ymax = ci_high, fill = step), alpha = 0.15, linetype = 0) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_point(size = 1.5) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = 0, colour = "grey65", linewidth = 0.4, linetype = 2) +
  ggplot2::scale_x_continuous(breaks = seq(-4, 5, 1)) +
  ggplot2::scale_colour_manual(
    values = c("A_standard_spec" = "#1f77b4", "B_alt_covariate" = "#ff7f0e"),
    labels = c("A_standard_spec" = "Step A: Standard [g-5,g-1]",
               "B_alt_covariate" = "Step B: Disjoint [g-10,g-6]")
  ) +
  ggplot2::scale_fill_manual(
    values = c("A_standard_spec" = "#1f77b4", "B_alt_covariate" = "#ff7f0e"),
    labels = c("A_standard_spec" = "Step A: Standard [g-5,g-1]",
               "B_alt_covariate" = "Step B: Disjoint [g-10,g-6]"),
    guide = "none"
  ) +
  ggplot2::labs(
    x = "Event time (years relative to acquisition)",
    y = "ATT (active_patenting)",
    title = "Disjoint-window covariate test: does hump shrink when covariate overlap is removed?",
    subtitle = "Intersection sample only (both qualification rules satisfied). Blue: standard [g-5,g-1] covariate.\nOrange: disjoint [g-10,g-6] covariate. Shading: 95% simultaneous CI.",
    colour = "Specification",
    fill = "Specification"
  ) +
  ggplot2::theme_minimal(base_size = 9.5) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major.x = ggplot2::element_blank(),
    plot.title = ggplot2::element_text(face = "bold", color = "#1B4332", size = 11),
    plot.subtitle = ggplot2::element_text(color = "#6B7280", size = 8),
    legend.position = "bottom",
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )

fig_path <- file.path(FIGS, "figure13_disjoint_window_comparison.png")
ggplot2::ggsave(fig_path, p, width = 8, height = 5, dpi = 300, bg = "white")
message("Figure saved: ", fig_path)

banner("DIAGNOSTIC 3 COMPLETE")
message("Shrinkage ", if(shrinkage_pct > 50) "EXCEEDS" else "DOES NOT EXCEED", " 50% threshold")
message("Audit outputs: ", AUDIT)
message("Results: ", RESULTS)
message("Figure: ", fig_path)
