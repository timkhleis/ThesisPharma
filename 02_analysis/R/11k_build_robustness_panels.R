# ============================================================================
# 11k_build_robustness_panels.R -- Main DiD v1 robustness outcome panels
# ----------------------------------------------------------------------------
# Builds outcome panels for feasible robustness specifications only. P0/P1/P3
# frozen or infeasible outputs are not overwritten.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
source(file.path(BASE, "R", "11i_robustness_config.R"))

for (pkg in c("DBI", "duckdb"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb) })

PANEL_NT_H5_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_panel_never_target_h5.parquet")
PANEL_G7_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_panel_g7.parquet")
ROBUSTNESS_CITATION_BALANCE <- file.path(RESULTS_DIR, "main_robustness_citation_restricted_balance.csv")

EVENT_WINDOW_11K <- EVENT_LO:EVENT_HI
REFERENCE_11K <- -1L
POST_PERIODS_11K <- PRIMARY_POST

sql_path <- function(path) gsub("\\\\", "/", path)

write_phase_csv <- function(df, path) {
  df <- cbind(design_version = DESIGN_VERSION, robustness_version = ROBUSTNESS_VERSION, df)
  utils::write.csv(df, path, row.names = FALSE, na = "")
  invisible(path)
}

assert_feasible_specs <- function() {
  if (!file.exists(ROBUSTNESS_FEASIBILITY))
    stop("Missing robustness feasibility CSV. Run 11_run_robustness.R first.")
  f <- utils::read.csv(ROBUSTNESS_FEASIBILITY, stringsAsFactors = FALSE)
  required <- c("P0H5", "P2", "P4", "P5")
  bad <- f$spec %in% required & f$status != "FEASIBLE"
  if (any(bad)) stop("Cannot run Phase 2; infeasible required specs: ",
                     paste(f$spec[bad], collapse = ", "))
  skipped <- f$spec %in% c("P1", "P3") & f$status == "FEASIBLE"
  if (any(skipped)) stop("Unexpected feasible status for skipped specs P1/P3.")
  invisible(f)
}

check_weight_file <- function(con, path, spec, treated_deal_weighted = FALSE) {
  if (!file.exists(path)) stop("Missing weight file for ", spec, ": ", path)
  q <- dbGetQuery(con, sprintf("
    WITH w AS (SELECT * FROM read_parquet('%s')),
    keys AS (
      SELECT CAST(codinv AS BIGINT) AS codinv, CAST(stack AS INTEGER) AS stack,
             COUNT(*) AS n
      FROM w GROUP BY 1, 2
    )
    SELECT
      '%s' AS spec,
      COUNT(*) AS n_rows,
      COUNT(DISTINCT CAST(CAST(codinv AS BIGINT) AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_unit_keys,
      SUM(CASE WHEN n <> 1 THEN 1 ELSE 0 END) AS n_duplicate_unit_keys,
      SUM(CASE WHEN final_weight IS NULL OR NOT isfinite(final_weight) OR final_weight <= 0 THEN 1 ELSE 0 END) AS n_bad_weights,
      SUM(CASE WHEN treated = 1 THEN 1 ELSE 0 END) AS n_treated,
      SUM(CASE WHEN treated = 0 THEN 1 ELSE 0 END) AS n_control
    FROM w JOIN keys USING (codinv, stack)", sql_path(path), spec))
  if (q$n_duplicate_unit_keys > 0 || q$n_bad_weights > 0)
    stop("Invalid weights for ", spec)
  if (!treated_deal_weighted) {
    bad_t <- dbGetQuery(con, sprintf("
      SELECT SUM(CASE WHEN treated = 1 AND ABS(final_weight - 1) > 1e-8 THEN 1 ELSE 0 END) AS n
      FROM read_parquet('%s')", sql_path(path)))$n
    if (bad_t > 0) stop("Treated weights are not one for inventor-weighted spec ", spec)
  } else {
    deal_check <- dbGetQuery(con, sprintf("
      WITH d AS (
        SELECT focal_deal_id, SUM(final_weight) AS mass
        FROM read_parquet('%s')
        WHERE treated = 1
        GROUP BY focal_deal_id
      )
      SELECT MIN(mass) AS min_mass, MAX(mass) AS max_mass,
             MAX(ABS(mass - (SELECT AVG(mass) FROM d)) / (SELECT AVG(mass) FROM d)) AS max_rel_dev
      FROM d", sql_path(path)))
    if (deal_check$max_rel_dev > P4_DEAL_MASS_TOL)
      stop("Deal-weighted treated deal mass check failed for ", spec)
  }
  q
}

make_analysis_units <- function(con, weights_path, view_name, control_cluster = c("group", "future_deal")) {
  control_cluster <- match.arg(control_cluster)
  cluster_expr <- if (control_cluster == "group") {
    "'C_group_' || CAST(CAST(w.underlying_group_id AS BIGINT) AS VARCHAR)"
  } else {
    "'C_future_deal_' || CAST(CAST(w.real_control_deal_id AS BIGINT) AS VARCHAR)"
  }
  dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", view_name))
  dbExecute(con, sprintf("
    CREATE TEMP TABLE %s AS
    SELECT
      CAST(w.codinv AS BIGINT) AS codinv,
      CAST(w.underlying_group_id AS BIGINT) AS underlying_group_id,
      CAST(w.stack AS INTEGER) AS stack,
      CAST(w.treated AS INTEGER) AS treated,
      CAST(w.n_qualifying_inventors AS INTEGER) AS n_qualifying_inventors,
      CAST(w.focal_deal_id AS BIGINT) AS focal_deal_id,
      CAST(w.real_control_deal_id AS BIGINT) AS real_control_deal_id,
      CAST(CAST(w.codinv AS BIGINT) AS VARCHAR) || '|' || CAST(w.stack AS VARCHAR) AS uid_stack,
      CASE WHEN w.treated = 1
           THEN 'T_deal_' || CAST(CAST(w.focal_deal_id AS BIGINT) AS VARCHAR)
           ELSE %s END AS cluster_entity
    FROM read_parquet('%s') w",
    view_name, cluster_expr, sql_path(weights_path)))
}

write_panel <- function(con, unit_view, panel_path, panel_label) {
  dbExecute(con, sprintf("
    COPY (
      WITH
      event_grid AS (
        SELECT CAST(event_time AS INTEGER) AS event_time
        FROM range(%d, %d) AS r(event_time)
      ),
      patent_rows AS (
        SELECT DISTINCT
          CAST(pi.codinv AS BIGINT) AS codinv,
          CAST(pi.appln_id AS DOUBLE) AS appln_id,
          CAST(pa.patent_year AS INTEGER) AS filing_year
        FROM patent_inventor pi
        JOIN patent_application pa ON pa.appln_id = pi.appln_id
      ),
      patent_enriched_one AS (
        SELECT
          appln_id,
          MAX(CAST(fwd_cits5 AS DOUBLE)) FILTER (WHERE fwd_cits5 IS NOT NULL) AS fwd_cits5,
          COUNT(fwd_cits5) AS n_nonmissing_fwd_cits5
        FROM patent_enriched
        GROUP BY appln_id
      ),
      inventor_year_outcomes AS (
        SELECT
          pr.codinv,
          pr.filing_year AS calendar_year,
          COUNT(*) AS n_patents,
          SUM(CASE WHEN pe.n_nonmissing_fwd_cits5 IS NULL OR pe.n_nonmissing_fwd_cits5 = 0 THEN 1 ELSE 0 END) AS n_patents_missing_fwd_cits5,
          SUM(pe.fwd_cits5) AS sum_observed_fwd_cits5
        FROM patent_rows pr
        LEFT JOIN patent_enriched_one pe ON pe.appln_id = pr.appln_id
        GROUP BY pr.codinv, pr.filing_year
      )
      SELECT
        '%s' AS panel,
        u.codinv,
        u.underlying_group_id,
        u.stack,
        u.treated,
        u.n_qualifying_inventors,
        u.focal_deal_id,
        u.real_control_deal_id,
        u.uid_stack,
        u.cluster_entity,
        e.event_time,
        u.stack + e.event_time AS calendar_year,
        CAST(COALESCE(iyo.n_patents, 0) AS DOUBLE) AS patent_count,
        CAST(CASE WHEN COALESCE(iyo.n_patents, 0) > 0 THEN 1 ELSE 0 END AS INTEGER) AS active_patenting,
        CASE
          WHEN iyo.n_patents IS NULL THEN CAST(0 AS DOUBLE)
          WHEN iyo.n_patents_missing_fwd_cits5 = 0 THEN CAST(COALESCE(iyo.sum_observed_fwd_cits5, 0) AS DOUBLE)
          ELSE NULL
        END AS fwd_cits5,
        CAST(COALESCE(iyo.n_patents, 0) AS BIGINT) AS n_patents_for_cites,
        CAST(COALESCE(iyo.n_patents_missing_fwd_cits5, 0) AS BIGINT) AS n_patents_missing_fwd_cits5,
        CASE
          WHEN iyo.n_patents IS NULL THEN TRUE
          WHEN iyo.n_patents_missing_fwd_cits5 = 0 THEN TRUE
          ELSE FALSE
        END AS citation_complete
      FROM %s u
      CROSS JOIN event_grid e
      LEFT JOIN inventor_year_outcomes iyo
        ON iyo.codinv = u.codinv
       AND iyo.calendar_year = u.stack + e.event_time
    ) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
    min(EVENT_WINDOW_11K), max(EVENT_WINDOW_11K) + 1L,
    panel_label, unit_view, sql_path(panel_path)))
}

validate_panel <- function(con, panel_path, label) {
  d <- dbGetQuery(con, sprintf("
    WITH p AS (SELECT * FROM read_parquet('%s')),
    unit_rows AS (
      SELECT codinv, stack, COUNT(*) AS n_rows FROM p GROUP BY 1, 2
    ),
    dup_keys AS (
      SELECT codinv, stack, event_time, COUNT(*) AS n
      FROM p GROUP BY 1, 2, 3 HAVING COUNT(*) > 1
    )
    SELECT
      '%s' AS panel,
      COUNT(*) AS n_panel_rows,
      COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_units,
      MIN(n_rows) AS min_rows_per_unit,
      MAX(n_rows) AS max_rows_per_unit,
      SUM(CASE WHEN n_rows <> 11 THEN 1 ELSE 0 END) AS n_bad_unit_row_counts,
      (SELECT COUNT(*) FROM dup_keys) AS n_duplicate_panel_keys,
      SUM(CASE WHEN active_patenting <> CAST(patent_count > 0 AS INTEGER) THEN 1 ELSE 0 END) AS n_bad_active_patenting,
      SUM(CASE WHEN cluster_entity IS NULL OR cluster_entity = '' OR codinv IS NULL THEN 1 ELSE 0 END) AS n_missing_cluster_vars
    FROM p JOIN unit_rows USING (codinv, stack)", sql_path(panel_path), label))
  if (d$min_rows_per_unit != 11 || d$max_rows_per_unit != 11 ||
      d$n_bad_unit_row_counts > 0 || d$n_duplicate_panel_keys > 0 ||
      d$n_bad_active_patenting > 0 || d$n_missing_cluster_vars > 0)
    stop("Panel validation failed for ", label)
  d
}

weight_join_audit <- function(con) {
  specs <- data.frame(
    spec = c("P0H5", "P2", "P5", "P4"),
    panel_path = c(PANEL_NT_H5_PARQUET, PANEL_NT_H5_PARQUET, PANEL_NT_H5_PARQUET, PANEL_G7_PARQUET),
    weight_path = c(P0H5_WEIGHTS_PARQUET, P2_WEIGHTS_PARQUET, P5_WEIGHTS_PARQUET, P4_WEIGHTS_PARQUET),
    stringsAsFactors = FALSE
  )
  out <- lapply(seq_len(nrow(specs)), function(i) {
    dbGetQuery(con, sprintf("
      WITH
      p AS (
        SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv, CAST(stack AS INTEGER) AS stack
        FROM read_parquet('%s')
      ),
      w AS (
        SELECT CAST(codinv AS BIGINT) AS codinv, CAST(stack AS INTEGER) AS stack, COUNT(*) AS n
        FROM read_parquet('%s')
        GROUP BY 1, 2
      )
      SELECT '%s' AS spec,
             (SELECT COUNT(*) FROM p JOIN w USING (codinv, stack)) AS matched_units,
             (SELECT COUNT(*) FROM w LEFT JOIN p USING (codinv, stack) WHERE p.codinv IS NULL) AS weights_not_in_panel,
             (SELECT COUNT(*) FROM p LEFT JOIN w USING (codinv, stack) WHERE w.codinv IS NULL) AS panel_not_in_weights,
             (SELECT SUM(CASE WHEN n <> 1 THEN 1 ELSE 0 END) FROM w) AS duplicate_weight_keys",
      sql_path(specs$panel_path[i]), sql_path(specs$weight_path[i]), specs$spec[i]))
  })
  do.call(rbind, out)
}

check_citation_conflicts <- function(con) {
  conflicts <- dbGetQuery(con, "
    SELECT appln_id, COUNT(DISTINCT CAST(fwd_cits5 AS DOUBLE)) AS n_values
    FROM patent_enriched
    WHERE fwd_cits5 IS NOT NULL
    GROUP BY appln_id
    HAVING COUNT(DISTINCT CAST(fwd_cits5 AS DOUBLE)) > 1
    LIMIT 10")
  if (nrow(conflicts) > 0)
    stop("Conflicting duplicate non-missing fwd_cits5 values in patent_enriched.")
  data.frame(check = "duplicate_patent_enriched_fwd_cits5_conflicts", pass = TRUE)
}

citation_audits <- function(con, citation_stack_cutoff) {
  specs <- data.frame(
    spec = c("P0H5", "P2", "P5", "P4"),
    panel_path = c(PANEL_NT_H5_PARQUET, PANEL_NT_H5_PARQUET, PANEL_NT_H5_PARQUET, PANEL_G7_PARQUET),
    weight_path = c(P0H5_WEIGHTS_PARQUET, P2_WEIGHTS_PARQUET, P5_WEIGHTS_PARQUET, P4_WEIGHTS_PARQUET),
    stringsAsFactors = FALSE
  )
  cov <- lapply(seq_len(nrow(specs)), function(i) {
    dbGetQuery(con, sprintf("
      WITH joined AS (
        SELECT p.*, CAST(w.final_weight AS DOUBLE) AS final_weight
        FROM read_parquet('%s') p
        JOIN read_parquet('%s') w
          ON CAST(p.codinv AS BIGINT) = CAST(w.codinv AS BIGINT)
         AND CAST(p.stack AS INTEGER) = CAST(w.stack AS INTEGER)
      )
      SELECT
        '%s' AS spec,
        calendar_year, event_time, treated,
        COUNT(*) AS n_rows,
        COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_units,
        SUM(final_weight) AS weighted_observation_mass,
        SUM(CASE WHEN n_patents_for_cites > 0 THEN 1 ELSE 0 END) AS n_rows_with_patents,
        SUM(CASE WHEN n_patents_for_cites > 0 THEN final_weight ELSE 0 END) AS weighted_patent_row_mass,
        SUM(CASE WHEN n_patents_for_cites > 0 AND fwd_cits5 IS NULL THEN 1 ELSE 0 END) AS n_rows_missing_fwd_cits5,
        SUM(CASE WHEN n_patents_for_cites > 0 AND fwd_cits5 IS NULL THEN final_weight ELSE 0 END) AS weighted_missing_fwd_cits5_mass,
        SUM(n_patents_for_cites) AS n_patents,
        SUM(n_patents_missing_fwd_cits5) AS n_patents_missing_fwd_cits5,
        CAST(stack <= %d AS BOOLEAN) AS fwd_cits5_stack_sample
      FROM joined
      GROUP BY calendar_year, event_time, treated, CAST(stack <= %d AS BOOLEAN)
      ORDER BY event_time, calendar_year, treated",
      sql_path(specs$panel_path[i]), sql_path(specs$weight_path[i]), specs$spec[i],
      citation_stack_cutoff, citation_stack_cutoff))
  })
  miss <- lapply(seq_len(nrow(specs)), function(i) {
    dbGetQuery(con, sprintf("
      WITH joined AS (
        SELECT p.*, CAST(w.final_weight AS DOUBLE) AS final_weight
        FROM read_parquet('%s') p
        JOIN read_parquet('%s') w
          ON CAST(p.codinv AS BIGINT) = CAST(w.codinv AS BIGINT)
         AND CAST(p.stack AS INTEGER) = CAST(w.stack AS INTEGER)
        WHERE p.stack <= %d
      )
      SELECT '%s' AS spec, treated,
        SUM(CASE WHEN n_patents_for_cites > 0 THEN 1 ELSE 0 END) AS patent_active_rows,
        SUM(CASE WHEN n_patents_for_cites > 0 THEN final_weight ELSE 0 END) AS patent_active_weighted_mass,
        SUM(CASE WHEN n_patents_for_cites > 0 AND fwd_cits5 IS NULL THEN 1 ELSE 0 END) AS missing_rows,
        SUM(CASE WHEN n_patents_for_cites > 0 AND fwd_cits5 IS NULL THEN final_weight ELSE 0 END) AS missing_weighted_mass
      FROM joined
      GROUP BY treated",
      sql_path(specs$panel_path[i]), sql_path(specs$weight_path[i]), citation_stack_cutoff,
      specs$spec[i]))
  })
  list(coverage = do.call(rbind, cov), missing = do.call(rbind, miss))
}

unit_key_r <- function(df) {
  paste(format(df$codinv, scientific = FALSE, trim = TRUE), df$stack, sep = "|")
}

weighted_smd_r <- function(x, treated, w) {
  ok <- is.finite(x) & is.finite(w) & !is.na(treated)
  x <- x[ok]
  treated <- treated[ok]
  w <- w[ok]
  t <- treated == 1L
  c <- treated == 0L
  mt <- stats::weighted.mean(x[t], w[t])
  mc <- stats::weighted.mean(x[c], w[c])
  vt <- sum(w[t] * (x[t] - mt)^2) / sum(w[t])
  sdt <- sqrt(vt)
  if (!is.finite(sdt) || sdt == 0) return(0)
  (mt - mc) / sdt
}

load_h5_covariates <- function(con, citation_stack_cutoff) {
  banner("Citation restricted balance: never-target H5 covariates")
  treated <- dbGetQuery(con, sprintf("
    SELECT codinv, stack, analysis_target_group_id AS underlying_group_id,
           treated, %s
    FROM read_parquet('%s')
    WHERE treated = 1 AND stack <= %d",
    paste(c(FIRM_COVARS, INV_COVARS), collapse = ", "), sql_path(UNITS_PARQUET),
    citation_stack_cutoff))
  controls_firm <- dbGetQuery(con, sprintf("
    SELECT nt.codinv, nt.stack, nt.underlying_group_id, 0 AS treated, %s
    FROM read_parquet('%s') nt
    JOIN read_parquet('%s') w
      ON CAST(nt.codinv AS BIGINT) = CAST(w.codinv AS BIGINT)
     AND CAST(nt.stack AS INTEGER) = CAST(w.stack AS INTEGER)
     AND CAST(nt.underlying_group_id AS BIGINT) = CAST(w.underlying_group_id AS BIGINT)
    WHERE w.treated = 0 AND nt.stack <= %d",
    paste(sprintf("nt.%s", FIRM_COVARS), collapse = ", "), sql_path(NT_UNITS_PARQUET),
    sql_path(P0H5_WEIGHTS_PARQUET), citation_stack_cutoff))
  stacks <- sort(unique(controls_firm$stack))
  inv_list <- vector("list", length(stacks))
  for (i in seq_along(stacks)) {
    g <- stacks[i]
    keys <- unique(controls_firm[controls_firm$stack == g, c("codinv", "underlying_group_id")])
    keys <- data.frame(codinv = keys$codinv, g = g, grp = keys$underlying_group_id)
    t0 <- Sys.time()
    inv_list[[i]] <- compute_inventor_covariates(con, keys)
    message(sprintf("  citation stack %d: %d keys, %.1fs", g, nrow(keys),
                    as.numeric(Sys.time() - t0, units = "secs")))
  }
  inv <- do.call(rbind, inv_list)
  controls <- merge(controls_firm, inv,
    by.x = c("codinv", "stack", "underlying_group_id"),
    by.y = c("codinv", "g", "grp"), all.x = TRUE)
  missing <- rowSums(is.na(controls[, INV_COVARS, drop = FALSE])) > 0
  if (any(missing)) stop("Missing inventor covariates in restricted H5 citation balance.")
  rbind(treated[, c("codinv", "stack", "underlying_group_id", "treated", FULL_NUMERIC_COVARS)],
        controls[, c("codinv", "stack", "underlying_group_id", "treated", FULL_NUMERIC_COVARS)])
}

load_g7_covariates <- function(con, citation_stack_cutoff) {
  dbGetQuery(con, sprintf("
    SELECT u.codinv, u.stack, u.analysis_target_group_id AS underlying_group_id,
           u.treated, %s
    FROM read_parquet('%s') u
    JOIN read_parquet('%s') w
      ON CAST(u.codinv AS BIGINT) = CAST(w.codinv AS BIGINT)
     AND CAST(u.stack AS INTEGER) = CAST(w.stack AS INTEGER)
    WHERE u.stack <= %d",
    paste(sprintf("u.%s", FULL_NUMERIC_COVARS), collapse = ", "),
    sql_path(UNITS_PARQUET), sql_path(P4_WEIGHTS_PARQUET), citation_stack_cutoff))
}

load_weights_r <- function(con, path, citation_stack_cutoff) {
  dbGetQuery(con, sprintf("
    SELECT codinv, stack, treated, final_weight
    FROM read_parquet('%s')
    WHERE stack <= %d", sql_path(path), citation_stack_cutoff))
}

restricted_balance <- function(covars, weights, spec, citation_stack_cutoff) {
  covars$.key <- unit_key_r(covars)
  weights$.key <- unit_key_r(weights)
  d <- merge(weights[, c(".key", "final_weight")], covars, by = ".key")
  if (nrow(d) != nrow(weights)) stop("Restricted balance covariate join failed for ", spec)
  out <- do.call(rbind, lapply(FULL_NUMERIC_COVARS, function(v) {
    smd <- weighted_smd_r(d[[v]], d$treated, d$final_weight)
    data.frame(spec = spec, covariate = v, smd_weighted = smd,
      abs_smd_weighted = abs(smd), n_units = nrow(d),
      treated_weight = sum(d$final_weight[d$treated == 1L]),
      control_weight = sum(d$final_weight[d$treated == 0L]),
      restricted_stack_cutoff = citation_stack_cutoff,
      stringsAsFactors = FALSE)
  }))
  out$max_abs_smd_spec <- max(out$abs_smd_weighted, na.rm = TRUE)
  out$citation_balance_status <- ifelse(
    out$max_abs_smd_spec <= ROBUST_MAX_SMD_CONSTRAINED,
    "passes_restricted_balance_but_followup_provisional",
    "restricted_balance_fails_citation_provisional"
  )
  out
}

write_restricted_citation_balance <- function(con, citation_stack_cutoff) {
  h5_cov <- load_h5_covariates(con, citation_stack_cutoff)
  g7_cov <- load_g7_covariates(con, citation_stack_cutoff)
  out <- rbind(
    restricted_balance(h5_cov, load_weights_r(con, P0H5_WEIGHTS_PARQUET, citation_stack_cutoff),
                       "P0H5", citation_stack_cutoff),
    restricted_balance(h5_cov, load_weights_r(con, P2_WEIGHTS_PARQUET, citation_stack_cutoff),
                       "P2", citation_stack_cutoff),
    restricted_balance(h5_cov, load_weights_r(con, P5_WEIGHTS_PARQUET, citation_stack_cutoff),
                       "P5", citation_stack_cutoff),
    restricted_balance(g7_cov, load_weights_r(con, P4_WEIGHTS_PARQUET, citation_stack_cutoff),
                       "P4", citation_stack_cutoff)
  )
  write_phase_csv(out, ROBUSTNESS_CITATION_BALANCE)
  out
}

banner("11k ROBUSTNESS PANELS")
assert_feasible_specs()

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = FALSE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'")
dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sql_path(DUCKDB_TMP)))

weight_checks <- rbind(
  check_weight_file(con, P0H5_WEIGHTS_PARQUET, "P0H5"),
  check_weight_file(con, P2_WEIGHTS_PARQUET, "P2"),
  check_weight_file(con, P5_WEIGHTS_PARQUET, "P5", treated_deal_weighted = TRUE),
  check_weight_file(con, P4_WEIGHTS_PARQUET, "P4", treated_deal_weighted = TRUE)
)
write_audit(weight_checks, "main_robustness_panel_weight_file_checks.csv")

conflict_check <- check_citation_conflicts(con)
write_audit(conflict_check, "main_robustness_citation_duplicate_conflict_check.csv")

max_patent_year <- dbGetQuery(con, "SELECT MAX(patent_year) AS max_patent_year FROM patent_enriched")$max_patent_year
citation_filing_cutoff <- as.integer(max_patent_year) - 5L
citation_stack_cutoff <- citation_filing_cutoff - max(POST_PERIODS_11K)
citation_followup <- data.frame(
  source = "patent_enriched",
  max_patent_year_in_db = as.integer(max_patent_year),
  conservative_filing_cutoff_for_fwd_cits5 = citation_filing_cutoff,
  stack_cutoff_for_full_t_plus_5_followup = citation_stack_cutoff,
  certification_status = "provisional_db_filing_cutoff_no_raw_citing_years",
  stringsAsFactors = FALSE
)
write_audit(citation_followup, "main_robustness_citation_followup_cutoff.csv")

banner("Never-target H5 panel")
make_analysis_units(con, P0H5_WEIGHTS_PARQUET, "robust_units_nt_h5", "group")
write_panel(con, "robust_units_nt_h5", PANEL_NT_H5_PARQUET, "never_target_h5")

banner("g+7 panel")
make_analysis_units(con, P4_WEIGHTS_PARQUET, "robust_units_g7", "future_deal")
write_panel(con, "robust_units_g7", PANEL_G7_PARQUET, "g7")

panel_checks <- rbind(
  validate_panel(con, PANEL_NT_H5_PARQUET, "never_target_h5"),
  validate_panel(con, PANEL_G7_PARQUET, "g7")
)
write_audit(panel_checks, "main_robustness_panel_row_validation.csv")

join_audit <- weight_join_audit(con)
write_audit(join_audit, "main_robustness_panel_weight_join_audit.csv")
bad_join <- join_audit$weights_not_in_panel > 0 | join_audit$duplicate_weight_keys > 0
if (any(bad_join)) stop("Invalid robustness panel-weight joins.")

ca <- citation_audits(con, citation_stack_cutoff)
write_audit(ca$coverage, "main_robustness_citation_coverage_by_year_event_treated.csv")
write_audit(ca$missing, "main_robustness_citation_missingness_by_spec_treatment.csv")

citation_balance <- write_restricted_citation_balance(con, citation_stack_cutoff)
print(aggregate(abs_smd_weighted ~ spec, citation_balance, max))

banner("11k DONE")
message("Panels: ", PANEL_NT_H5_PARQUET, " | ", PANEL_G7_PARQUET)
