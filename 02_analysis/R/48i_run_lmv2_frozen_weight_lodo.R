# ============================================================================
# 48i_run_lmv2_frozen_weight_lodo.R -- all-deal frozen-weight deletion audit
# ============================================================================
# Recomputes the standardized patent-count ATT after deleting each of the 343
# treated deal stacks in turn. It does not re-solve entropy weights; the
# precommitted deal-70/Henkel refits provide that stronger check for the most
# concentrated design component.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}
PANEL_DIR <- get_arg("--panel-dir")
CODE_ROOT <- get_arg("--code-root")
OUTPUT_DIR <- get_arg("--output-dir")
if (any(is.na(c(PANEL_DIR, CODE_ROOT, OUTPUT_DIR)))) {
  stop("48i requires --panel-dir=, --code-root=, and --output-dir=")
}
if (!dir.exists(PANEL_DIR) || !dir.exists(CODE_ROOT)) stop("Input directory missing")
if (dir.exists(OUTPUT_DIR) && length(list.files(
  OUTPUT_DIR, all.files = TRUE, no.. = TRUE
))) stop("Output directory must be new or empty: ", OUTPUT_DIR)

BASE <- normalizePath(CODE_ROOT, mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
cohorts <- as.integer(sub(
  "^.*_c([0-9]+)\\.parquet$", "\\1", panel_files
))
if (!identical(cohorts, 1993:2010)) stop("Panel cohort set is not 1993:2010")
panel_sql <- lmv2_panel_sql(panel_files)

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
pair <- lmv2_build_pair_table(
  con, panel_sql, "patent_count", cohorts, "lodo_all18"
)
cell <- DBI::dbGetQuery(con, sprintf(
  paste0(
    "SELECT cohort,event_time,arm,deal_id,SUM(weight) mass,",
    "SUM(weight*dy) weighted_dy FROM %s ",
    "GROUP BY cohort,event_time,arm,deal_id"
  ), pair
))
DBI::dbExecute(con, sprintf("DROP TABLE %s", pair))
design_deal <- DBI::dbGetQuery(con, sprintf(
  paste0(
    "SELECT cohort,deal_id,SUM(weight) treated_mass FROM %s ",
    "WHERE arm='treated' AND event_time=-1 GROUP BY cohort,deal_id"
  ), panel_sql
))
if (nrow(design_deal) != 343L || anyDuplicated(design_deal$deal_id)) {
  stop("Expected 343 unique treated deals")
}

cell_total <- stats::aggregate(
  cbind(mass, weighted_dy) ~ cohort + event_time + arm,
  data = cell, FUN = sum
)
design_total <- stats::aggregate(
  treated_mass ~ cohort, data = design_deal, FUN = sum
)

last_dynamic <- NULL
estimate_from_cells <- function(cells, design) {
  if (any(cells$mass <= 0) || any(design$treated_mass <= 0)) return(NA_real_)
  design$q <- design$treated_mass / sum(design$treated_mass)
  cells$mean_dy <- cells$weighted_dy / cells$mass
  wide <- reshape(
    cells[c("cohort", "event_time", "arm", "mean_dy")],
    idvar = c("cohort", "event_time"), timevar = "arm",
    direction = "wide"
  )
  if (any(!stats::complete.cases(wide)) ||
      !all(c("mean_dy.treated", "mean_dy.control") %in% names(wide))) return(NA_real_)
  wide$att <- wide$mean_dy.treated - wide$mean_dy.control
  wide <- merge(wide, design[c("cohort", "q")], by = "cohort")
  dynamic <- stats::aggregate(q * att ~ event_time, data = wide, FUN = sum)
  names(dynamic)[2] <- "estimate"
  last_dynamic <<- dynamic
  mean(dynamic$estimate[dynamic$event_time %in% 1:5])
}

headline <- estimate_from_cells(cell_total, design_total)
certified_headline <- -0.0520603086129782
if (abs(headline - certified_headline) > 1e-10) {
  utils::write.csv(
    last_dynamic,
    file.path(OUTPUT_DIR, "frozen_weight_lodo_reconstruction_diagnostic.csv"),
    row.names = FALSE, na = ""
  )
  stop(sprintf(
    "LODO reconstruction %.17g does not reproduce certified headline %.17g",
    headline, certified_headline
  ))
}

results <- vector("list", nrow(design_deal))
for (i in seq_len(nrow(design_deal))) {
  omitted <- design_deal[i, ]
  deleted_cells <- cell[cell$deal_id == omitted$deal_id, ]
  cells_i <- merge(
    cell_total, deleted_cells[c(
      "cohort", "event_time", "arm", "mass", "weighted_dy"
    )],
    by = c("cohort", "event_time", "arm"), all.x = TRUE,
    suffixes = c("", ".deleted")
  )
  cells_i$mass.deleted[is.na(cells_i$mass.deleted)] <- 0
  cells_i$weighted_dy.deleted[is.na(cells_i$weighted_dy.deleted)] <- 0
  cells_i$mass <- cells_i$mass - cells_i$mass.deleted
  cells_i$weighted_dy <- cells_i$weighted_dy - cells_i$weighted_dy.deleted
  design_i <- design_total
  design_i$treated_mass[design_i$cohort == omitted$cohort] <-
    design_i$treated_mass[design_i$cohort == omitted$cohort] -
    omitted$treated_mass
  estimate <- estimate_from_cells(cells_i, design_i)
  results[[i]] <- data.frame(
    omitted_deal_id = omitted$deal_id,
    cohort = omitted$cohort,
    omitted_treated_mass = omitted$treated_mass,
    estimate = estimate,
    deviation_from_headline = estimate - headline,
    absolute_deviation = abs(estimate - headline),
    deletion_feasible = is.finite(estimate),
    same_sign = if (is.finite(estimate)) sign(estimate) == sign(headline) else NA,
    inside_headline_ci = if (is.finite(estimate)) {
      estimate >= -0.0898254477875322 & estimate <= -0.0146995174967257
    } else NA,
    stringsAsFactors = FALSE
  )
}
results <- do.call(rbind, results)
results <- results[order(!results$deletion_feasible, -results$absolute_deviation), ]
utils::write.csv(
  results, file.path(OUTPUT_DIR, "frozen_weight_lodo_results.csv"),
  row.names = FALSE, na = ""
)
feasible <- results[results$deletion_feasible, ]
summary <- data.frame(
  headline = headline,
  minimum_lodo = min(feasible$estimate),
  maximum_lodo = max(feasible$estimate),
  maximum_absolute_deviation = max(feasible$absolute_deviation),
  largest_deletion_deal = feasible$omitted_deal_id[[which.max(feasible$absolute_deviation)]],
  all_same_sign = all(feasible$same_sign),
  all_inside_headline_ci = all(feasible$inside_headline_ci),
  n_deals = nrow(results),
  n_feasible_deletions = nrow(feasible),
  n_infeasible_deletions = sum(!results$deletion_feasible),
  stringsAsFactors = FALSE
)
utils::write.csv(
  summary, file.path(OUTPUT_DIR, "frozen_weight_lodo_summary.csv"),
  row.names = FALSE, na = ""
)
manifest <- data.frame(
  version = "lmv2_frozen_weight_lodo_v1",
  outcome = "patent_count",
  weights_re_solved = FALSE,
  interpretation = "all_deal_concentration_audit_complemented_by_presolved_refits",
  panel_bundle_sha256 = digest::digest(
    vapply(panel_files, tools::md5sum, character(1)),
    algo = "sha256", serialize = TRUE
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(OUTPUT_DIR, "frozen_weight_lodo_manifest.csv"),
  row.names = FALSE, na = ""
)
message("Frozen-weight LODO complete: ", nrow(results), " deals")
