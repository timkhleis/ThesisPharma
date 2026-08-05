# ============================================================================
# Database-free certification for P5 final configuration and weight output
# ============================================================================

checks <- list()
add_check <- function(name, observed, expected, pass) {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = name,
    observed = paste(observed, collapse = ";"),
    expected = paste(expected, collapse = ";"),
    pass = isTRUE(pass),
    stringsAsFactors = FALSE)
}

add_check(
  "p5_amendment_hash",
  observed_p5_amendment_hash,
  LMV2_P5_FINAL_AMENDMENT_SHA256,
  identical(
    observed_p5_amendment_hash,
    LMV2_P5_FINAL_AMENDMENT_SHA256))

settings_ok <- tryCatch({
  lmv2_p5_assert_selected_settings(
    1.5, "nearest_50", "u1",
    c("primary", "equal_deal"), "newton", 1995L)
  TRUE
}, error = function(e) FALSE)
add_check("selected_settings_accept_lock", settings_ok, TRUE, settings_ok)

settings_reject <- tryCatch({
  lmv2_p5_assert_selected_settings(
    2.0, "nearest_50", "u1",
    c("primary", "equal_deal"), "newton", 1995L)
  FALSE
}, error = function(e) TRUE)
add_check(
  "selected_settings_reject_caliper_drift",
  settings_reject, TRUE, settings_reject)

tmp <- tempfile("lmv2_p5_weight_cert_")
dir.create(tmp, recursive = TRUE)
drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, dbdir = ":memory:")

roster <- data.frame(
  D = c(1L, 1L, 0L, 0L, 0L, 0L),
  cohort = rep(1995L, 6),
  deal_id = c(1L, 1L, 1L, 1L, 1L, 1L),
  treated_codinv = c(101, 102, NA, NA, NA, NA),
  control_codinv = c(NA, NA, 201, 202, 203, 204),
  control_group = c(NA, NA, 301, 301, 302, 302),
  base_weight = c(1, 1, 0.5, 0.5, 0.5, 0.5),
  stringsAsFactors = FALSE)
result <- list(weight = roster$base_weight)
diagnostic <- data.frame(
  mode = "exact_ebal", tier = "preferred",
  stringsAsFactors = FALSE)
context <- list(
  con = con,
  roster = roster,
  result = result,
  diagnostic = diagnostic,
  deal_balance = data.frame(
    cohort = 1995L, deal_id = 1L, max_abs_smd = 0,
    signed_smd_log_patent_count_5y = 0),
  cohort = 1995L,
  caliper = 1.5,
  profile = "nearest_50",
  universe = "u1",
  scheme = "primary",
  target_group_by_deal = data.frame(
    cohort = 1995L, deal_id = 1L, target_group = 9999))

path <- lmv2_p5_materialize_weight_context(
  context, tmp, "fixture_execution_hash", "main", NA_integer_)
rows <- DBI::dbGetQuery(
  con, sprintf("SELECT * FROM read_parquet('%s')", path))
add_check(
  "materialized_weight_row_count",
  nrow(rows), nrow(roster), nrow(rows) == nrow(roster))
add_check(
  "materialized_weight_unique_key",
  anyDuplicated(rows$roster_row_id), 0L,
  !anyDuplicated(rows$roster_row_id))
add_check(
  "materialized_weight_mass",
  c(
    sum(rows$final_weight[rows$treated == 1L]),
    sum(rows$final_weight[rows$treated == 0L])),
  c(2, 2),
  isTRUE(all.equal(
    sum(rows$final_weight[rows$treated == 1L]),
    sum(rows$final_weight[rows$treated == 0L]),
    tolerance = 1e-12)))
add_check(
  "materialized_treated_target_group",
  unique(rows$group_id[rows$treated == 1L]),
  9999,
  identical(unique(rows$group_id[rows$treated == 1L]), 9999))

manifest_path <- file.path(tmp, "weights", "manifest.csv")
manifest_before <- utils::read.csv(
  manifest_path, stringsAsFactors = FALSE)
path_again <- lmv2_p5_materialize_weight_context(
  context, tmp, "fixture_execution_hash", "main", NA_integer_)
manifest_after <- utils::read.csv(
  manifest_path, stringsAsFactors = FALSE)
add_check(
  "materialization_restart_reuses_valid_shard",
  c(path_again == path, nrow(manifest_after)),
  c(TRUE, nrow(manifest_before)),
  identical(path_again, path) &&
    nrow(manifest_after) == nrow(manifest_before))
DBI::dbDisconnect(con, shutdown = TRUE)

report <- do.call(rbind, checks)
dir.create(AUDIT_OUT_DIR, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  report,
  file.path(AUDIT_OUT_DIR, "certify_lmv2_p5_final_results.csv"),
  row.names = FALSE)
if (any(!report$pass)) {
  print(report[!report$pass, ], row.names = FALSE)
  stop("P5 final certification failed")
}
cat(sprintf(
  "\n=== P5 final certification: %d checks, 0 failing ===\n",
  nrow(report)))
