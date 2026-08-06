# Certify the prospective 1993 cohort amendment before outcome access.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}

db_path <- normalizePath(read_arg("db"), winslash = "/", mustWork = TRUE)
old_root <- normalizePath(
  read_arg("old-production-root"), winslash = "/", mustWork = TRUE)
new_root <- normalizePath(
  read_arg("new-production-root"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))

read_current_weights <- function(root) {
  production_paths <- list.files(
    root, pattern = "^p5_production_manifest\\.csv$",
    recursive = TRUE, full.names = TRUE)
  weight_paths <- list.files(
    root, pattern = "^manifest\\.csv$",
    recursive = TRUE, full.names = TRUE)
  weight_paths <- weight_paths[grepl(
    "[/\\\\]weights[/\\\\]manifest\\.csv$", weight_paths)]
  production <- do.call(rbind, lapply(
    production_paths, utils::read.csv, stringsAsFactors = FALSE))
  weights <- do.call(rbind, lapply(
    weight_paths, utils::read.csv, stringsAsFactors = FALSE))
  merge(
    production[c("cohort", "execution_hash")], weights,
    by = c("cohort", "execution_hash"))
}

old_weights <- read_current_weights(old_root)
new_weights <- read_current_weights(new_root)
old_weights <- old_weights[
  old_weights$cohort %in% LMV2_LOCK$timing$frozen_reproduction_cohorts,
  ]
new_weights <- new_weights[
  new_weights$cohort %in% LMV2_LOCK$timing$frozen_reproduction_cohorts,
  ]
cells <- merge(
  old_weights[c("cohort", "scheme", "path", "row_count")],
  new_weights[c("cohort", "scheme", "path", "row_count")],
  by = c("cohort", "scheme"), suffixes = c("_old", "_new"))
if (nrow(cells) != nrow(old_weights) ||
    nrow(cells) != nrow(new_weights[
      paste(new_weights$cohort, new_weights$scheme) %in%
        paste(old_weights$cohort, old_weights$scheme), ])) {
  stop("Frozen reproduction manifests do not contain all realized weight cells")
}

sql_path <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  gsub("'", "''", path, fixed = TRUE)
}
drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
comparison_columns <- paste(c(
  "roster_row_id", "analysis_scope", "cohort", "dealsim_tercile",
  "deal_id", "codinv", "treated", "group_id", "target_group",
  "control_group", "scheme", "base_weight", "entropy_tilt_normalized",
  "final_weight", "solver", "feasibility_mode", "feasibility_tier",
  "universe", "profile", "stage1_caliper", "stage2_caliper",
  "technology_resolution"), collapse = ",")
reproduction <- do.call(rbind, lapply(seq_len(nrow(cells)), function(i) {
  old_path <- sql_path(cells$path_old[[i]])
  new_path <- sql_path(cells$path_new[[i]])
  query <- sprintf(
    paste0(
      "WITH old AS (SELECT %s FROM read_parquet('%s')), ",
      "new AS (SELECT %s FROM read_parquet('%s')), ",
      "old_keys AS (SELECT roster_row_id,treated FROM old), ",
      "new_keys AS (SELECT roster_row_id,treated FROM new) ",
      "SELECT ",
      "(SELECT count(*) FROM old) old_rows, ",
      "(SELECT count(*) FROM new) new_rows, ",
      "(SELECT count(*) FROM (SELECT * FROM old EXCEPT ALL SELECT * FROM new)) old_only, ",
      "(SELECT count(*) FROM (SELECT * FROM new EXCEPT ALL SELECT * FROM old)) new_only, ",
      "(SELECT count(*) FROM (SELECT * FROM old_keys EXCEPT ALL SELECT * FROM new_keys)) old_key_only, ",
      "(SELECT count(*) FROM (SELECT * FROM new_keys EXCEPT ALL SELECT * FROM old_keys)) new_key_only, ",
      "(SELECT count(*) FROM old_keys WHERE treated=0) old_control_rows, ",
      "(SELECT count(*) FROM new_keys WHERE treated=0) new_control_rows, ",
      "(SELECT count(*) FROM (SELECT * FROM old_keys WHERE treated=1 EXCEPT ALL SELECT * FROM new_keys WHERE treated=1)) old_treated_key_only, ",
      "(SELECT count(*) FROM (SELECT * FROM new_keys WHERE treated=1 EXCEPT ALL SELECT * FROM old_keys WHERE treated=1)) new_treated_key_only"),
    comparison_columns, old_path, comparison_columns, new_path)
  result <- DBI::dbGetQuery(con, query)
  control_key_difference_share <-
    (result$old_key_only + result$new_key_only) /
    max(result$old_control_rows, result$new_control_rows)
  data.frame(
    cohort = cells$cohort[[i]], scheme = cells$scheme[[i]], result,
    exact_reproduction = result$old_only == 0L && result$new_only == 0L,
    control_key_difference_share = control_key_difference_share,
    structural_equivalence =
      result$old_treated_key_only == 0L &&
      result$new_treated_key_only == 0L &&
      control_key_difference_share < 0.001,
    stringsAsFactors = FALSE)
}))
nonexact_cohorts <- unique(reproduction$cohort[
  !reproduction$exact_reproduction])
reproduction$reproduction_pass <-
  reproduction$exact_reproduction | reproduction$structural_equivalence

db_con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(db_con, shutdown = TRUE), add = TRUE)
boundary <- DBI::dbGetQuery(db_con, "
  SELECT count(*) AS eligible_inventors,
         count(DISTINCT deal_id) AS eligible_deals,
         count(*) FILTER (WHERE career_first_year = 1988) AS boundary_inventors,
         avg(CAST(career_first_year = 1988 AS INTEGER)) AS boundary_share
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort = 1993")
panel <- DBI::dbGetQuery(db_con, "
  SELECT min(year) AS first_year, max(year) AS last_year
  FROM inventor_year")

p2 <- utils::read.csv(file.path(
  BASE, "output", "audit", "local_match_v2", "P2",
  "p2_certification_checks.csv"), stringsAsFactors = FALSE)
p3 <- utils::read.csv(file.path(
  BASE, "output", "audit", "local_match_v2", "P3",
  "p3_acceptance_checks.csv"), stringsAsFactors = FALSE)
p5 <- utils::read.csv(file.path(
  dirname(new_root), "P5_PRODUCTION_FINAL", "finalized",
  "production_scheme_status.csv"), stringsAsFactors = FALSE)
p5_1993 <- p5[p5$cohort == 1993L, ]

checks <- data.frame(
  gate = c(
    "prospective_amendment_exists",
    "p2_all_checks_pass",
    "p3_all_checks_pass",
    "p5_all_primary_cohorts_feasible",
    "p5_1993_primary_feasible",
    "p5_1993_equal_deal_feasible",
    "p5_1993_both_deals_retained",
    "frozen_1994_2010_weights_exact_or_structurally_equivalent",
    "numerical_review_limited_to_one_cohort",
    "five_year_pre_window_inside_panel",
    "five_year_post_window_inside_panel"),
  observed = c(
    file.exists(LMV2_1993_AMENDMENT_PATH),
    all(as.logical(p2$pass)),
    all(as.logical(p3$pass)),
    all(p5$scheme != "primary" | as.logical(p5$feasible)),
    as.logical(p5_1993$feasible[p5_1993$scheme == "primary"]),
    as.logical(p5_1993$feasible[p5_1993$scheme == "equal_deal"]),
    boundary$eligible_deals[[1]] == 2L &&
      all(p5_1993$headline_inventor_retention > 0),
    all(reproduction$reproduction_pass),
    length(nonexact_cohorts) <= 1L,
    panel$first_year[[1]] <= 1988L,
    panel$last_year[[1]] >= 1998L),
  expected = TRUE,
  stringsAsFactors = FALSE)
checks$pass <- checks$observed == checks$expected

utils::write.csv(
  reproduction, file.path(output_dir, "frozen_weight_reproduction.csv"),
  row.names = FALSE)
utils::write.csv(
  checks, file.path(output_dir, "preoutcome_gate_checks.csv"),
  row.names = FALSE)
utils::write.csv(
  boundary, file.path(output_dir, "cohort_1993_left_boundary.csv"),
  row.names = FALSE)

status <- if (all(checks$pass)) "PASS" else "FAIL"
lines <- c(
  "# Local Match v2 1993 pre-outcome gate",
  "",
  paste0("- Status: **", status, "**."),
  sprintf(
    "- 1993 eligible roster: %d inventors across %d deals.",
    boundary$eligible_inventors[[1]], boundary$eligible_deals[[1]]),
  sprintf(
    "- Left-boundary diagnostic: %d inventors (%.2f%%) first appear in 1988.",
    boundary$boundary_inventors[[1]], 100 * boundary$boundary_share[[1]]),
  sprintf(
    "- Frozen reproduction: %d/%d cohort-scheme weight cells are exactly equal after excluding provenance hashes.",
    sum(reproduction$exact_reproduction), nrow(reproduction)),
  sprintf(
    "- Numerical-equivalence review: %d non-exact cohort(s); maximum symmetric control-key difference %.4f%%.",
    length(nonexact_cohorts),
    100 * max(reproduction$control_key_difference_share)),
  "- No outcome table or treatment-effect object was read by this certification.")
writeLines(lines, file.path(output_dir, "preoutcome_gate.md"), useBytes = TRUE)

if (!all(checks$pass)) stop("The 1993 pre-outcome gate failed")
message("1993 pre-outcome gate PASS: ", output_dir)
