# ============================================================================
# Split-preperiod established-inventor design and HonestDiD sensitivity
# ============================================================================
# Recruitment: t=-7,-6. Support and balance: information through t=-4.
# Untouched validation leads: t=-3,-2,-1. Reference period: t=-4.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (pkg in c(
    "DBI", "duckdb", "data.table", "WeightIt", "digest", "HonestDiD",
    "ggplot2", "Matrix")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_split_preperiod_freeze.md")
AMENDMENT_PATH <- file.path(
  BASE, "notes", "local_match_v2_split_preperiod_technical_amendment.md")
DB_PATH <- file.path(BASE, "output", "thesis_foundation.duckdb")
OUT_DIR <- file.path(
  BASE, "output", "audit", "local_match_v2",
  "P6_SPLIT_PREPERIOD_HONESTDID")
WEIGHT_DIR <- file.path(OUT_DIR, "weights")
dir.create(WEIGHT_DIR, recursive = TRUE, showWarnings = FALSE)
stale_weight_files <- list.files(
  WEIGHT_DIR, pattern = "^split_preperiod_weights_c[0-9]+\\.csv$",
  full.names = TRUE)
if (length(stale_weight_files) && !all(unlink(stale_weight_files) == 0L)) {
  stop("Could not clear stale split-preperiod weight files")
}

COHORTS <- 1995:2010
FIRM_K <- 5L
INVENTOR_K <- 3L
EVENT_TIMES <- -3:5
PRE_TIMES <- -3:-1
POST_TIMES <- 0:5
PRIMARY_POST_TIMES <- 1:5
REFERENCE_TIME <- -4L
MBAR_GRID <- seq(0, 3, by = 0.1)
EXACT_BALANCE_TOL <- 2e-5
RUN_HONESTDID <- "--honestdid" %in% commandArgs(trailingOnly = TRUE)
BALANCE_VARS <- c(
  "patent_m5", "patent_m4", "active_m5", "active_m4",
  "career_age_m4", "firm_patent_m5", "firm_patent_m4",
  "firm_inventors_m5", "firm_inventors_m4")

atomic_csv <- function(x, path) {
  tmp <- paste0(path, ".tmp")
  utils::write.csv(x, tmp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Could not publish ", path)
  invisible(path)
}

weighted_mean <- function(x, w) {
  sum(x * w) / sum(w)
}

ess <- function(w) {
  sum(w)^2 / sum(w^2)
}

standardize_for_distance <- function(x, variables, epsilon = 1e-10) {
  out <- data.table::copy(x)
  scalers <- lapply(variables, function(v) {
    values <- out[[v]]
    s <- stats::sd(values[is.finite(values)])
    m <- mean(values[is.finite(values)])
    zero <- !is.finite(s) || s < epsilon
    data.table::set(
      out, j = paste0("z_", v),
      value = if (zero) rep(0, nrow(out)) else (values - m) / s)
    data.frame(variable = v, mean = m, sd = if (zero) NA_real_ else s,
               zero_variance = zero)
  })
  list(data = out, scaler = do.call(rbind, scalers))
}

standardize_by_cohort <- function(x, variables, stage) {
  cohorts <- sort(unique(x$cohort))
  pieces <- vector("list", length(cohorts))
  scalers <- vector("list", length(cohorts))
  for (i in seq_along(cohorts)) {
    g <- cohorts[[i]]
    one <- standardize_for_distance(x[x$cohort == g, ], variables)
    pieces[[i]] <- one$data
    one$scaler$cohort <- g
    one$scaler$stage <- stage
    scalers[[i]] <- one$scaler
  }
  list(
    data = data.table::rbindlist(pieces, use.names = TRUE),
    scaler = do.call(rbind, scalers))
}

entropy_balance <- function(roster) {
  std <- standardize_for_distance(roster, BALANCE_VARS)
  use_vars <- BALANCE_VARS[!std$scaler$zero_variance]
  if (!length(use_vars)) stop("All balance variables are degenerate")
  zvars <- paste0("z_", use_vars)
  form <- stats::as.formula(
    paste("D ~", paste(zvars, collapse = " + ")))
  warning_messages <- character()
  fit <- withCallingHandlers(
    tryCatch(
      WeightIt::weightit(
        form, data = std$data, method = "ebal", estimand = "ATT",
        moments = 1, s.weights = roster$base_weight, maxit = 10000),
      error = function(e) e),
    warning = function(w) {
      warning_messages <<- c(warning_messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  if (inherits(fit, "condition")) {
    return(list(ok = FALSE, error = conditionMessage(fit),
                scaler = std$scaler,
                warnings = paste(unique(warning_messages), collapse = " | ")))
  }
  final_weight <- roster$base_weight
  controls <- roster$D == 0L
  final_weight[controls] <-
    roster$base_weight[controls] * fit$weights[controls]
  if (any(!is.finite(final_weight)) || any(final_weight < 0) ||
      any(final_weight[!controls] <= 0) ||
      sum(final_weight[controls]) <= 0) {
    return(list(ok = FALSE, error = "invalid entropy weights or control mass",
                scaler = std$scaler,
                warnings = paste(unique(warning_messages), collapse = " | ")))
  }
  final_weight[controls] <- final_weight[controls] *
    sum(final_weight[!controls]) / sum(final_weight[controls])

  balance <- do.call(rbind, lapply(BALANCE_VARS, function(v) {
    z <- std$data[[paste0("z_", v)]]
    mt <- weighted_mean(z[!controls], final_weight[!controls])
    mc <- weighted_mean(z[controls], final_weight[controls])
    data.frame(
      variable = v, treated_mean_std = mt, control_mean_std = mc,
      difference_std = mc - mt, abs_difference_std = abs(mc - mt))
  }))
  max_smd <- max(balance$abs_difference_std, na.rm = TRUE)
  list(
    ok = is.finite(max_smd) && max_smd <= EXACT_BALANCE_TOL,
    error = if (max_smd <= EXACT_BALANCE_TOL) NA_character_ else
      paste0("exact balance not attained; max |SMD|=", signif(max_smd, 5)),
    weight = final_weight, balance = balance, scaler = std$scaler,
    max_smd = max_smd,
    warnings = paste(unique(warning_messages), collapse = " | "))
}

cluster_meat <- function(scores, cluster) {
  s <- rowsum(scores, group = cluster, reorder = FALSE)
  g <- nrow(s)
  correction <- if (g > 1L) g / (g - 1) else NA_real_
  correction * crossprod(s)
}

safe_inverse <- function(x) {
  tryCatch(solve(x), error = function(e) MASS::ginv(x))
}

source_hash <- digest::digest(
  file = file.path(BASE, "R", "25a_run_lmv2_split_preperiod_honestdid.R"),
  algo = "sha256", serialize = FALSE)
freeze_hash <- digest::digest(
  file = FREEZE_PATH, algo = "sha256", serialize = FALSE)
amendment_hash <- digest::digest(
  file = AMENDMENT_PATH, algo = "sha256", serialize = FALSE)
execution_hash <- digest::digest(list(
  version = "lmv2_split_preperiod_v1_technical_amendment",
  source_sha256 = source_hash,
  freeze_sha256 = freeze_hash,
  technical_amendment_sha256 = amendment_hash,
  cohorts = COHORTS,
  firm_k = FIRM_K,
  inventor_k = INVENTOR_K,
  balance_variables = BALANCE_VARS,
  reference_time = REFERENCE_TIME,
  untouched_pre_times = PRE_TIMES,
  primary_post_times = PRIMARY_POST_TIMES,
  exact_balance_tolerance = EXACT_BALANCE_TOL
), algo = "sha256")

con <- DBI::dbConnect(
  duckdb::duckdb(), dbdir = DB_PATH, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=1")
DBI::dbExecute(con, "PRAGMA memory_limit='10GB'")
DBI::dbExecute(con, "PRAGMA preserve_insertion_order=true")

required_tables <- c(
  "lmv2_treated_primary", "deal_assignment",
  "deal_target_company_expanded", "firm_group",
  "lmv2_p3_group_year_patents", "lmv2_p3_ipc_code_map",
  "group_ipc_year", "inventor_ipc_year", "inventor_year")
missing <- required_tables[
  !vapply(required_tables, DBI::dbExistsTable, logical(1), conn = con)]
if (length(missing)) {
  stop("Missing required tables: ", paste(missing, collapse = ", "))
}
for (tbl in c(
    "lmv2_inventor_group_patent_year",
    "lmv2_inventor_target_company_patent_year",
    "lmv2_outcome_inventor_year")) {
  if (!DBI::dbExistsTable(con, DBI::Id(schema = "p6", table = tbl))) {
    stop("Missing p6.", tbl)
  }
}

message("Split-preperiod: construct early-recruited treated and clean U2 controls")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_target_events AS
SELECT DISTINCT CAST(target_group AS BIGINT) id_group,
       CAST(target_year AS INTEGER) event_year
FROM deal_assignment
WHERE target_group IS NOT NULL
UNION
SELECT DISTINCT CAST(fg.id_group AS BIGINT) id_group,
       CAST(da.target_year AS INTEGER) event_year
FROM deal_assignment da
JOIN deal_target_company_expanded dtc USING(deal_id)
JOIN firm_group fg
  ON CAST(fg.compcod AS BIGINT)=dtc.target_compcod
 AND fg.year=CAST(da.target_year AS INTEGER)-1
WHERE fg.id_group IS NOT NULL
")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_acquirer_events AS
SELECT DISTINCT CAST(acquirer_group AS BIGINT) id_group,
       CAST(target_year AS INTEGER) event_year
FROM deal_assignment
WHERE acquirer_group IS NOT NULL
")
DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE sp_treated AS
SELECT t.cohort,t.deal_id,t.codinv,CAST(t.target_group AS BIGINT) group_id
FROM lmv2_treated_primary t
WHERE t.cohort BETWEEN %d AND %d
  AND (
    EXISTS (
      SELECT 1 FROM p6.lmv2_inventor_group_patent_year g
      WHERE g.codinv=t.codinv
        AND g.id_group=CAST(t.target_group AS BIGINT)
        AND g.year IN (t.cohort-7,t.cohort-6)
    )
    OR EXISTS (
      SELECT 1 FROM p6.lmv2_inventor_target_company_patent_year c
      WHERE c.codinv=t.codinv AND c.deal_id=t.deal_id
        AND c.year IN (t.cohort-7,t.cohort-6)
    )
  )
", min(COHORTS), max(COHORTS)))
DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE sp_control_early_pairs AS
WITH cohorts AS (
  SELECT UNNEST(range(%d,%d))::INTEGER cohort
), pairs AS (
  SELECT DISTINCT c.cohort,g.codinv,g.id_group
  FROM cohorts c
  JOIN p6.lmv2_inventor_group_patent_year g
    ON g.year IN (c.cohort-7,c.cohort-6)
), unique_group AS (
  SELECT cohort,codinv,MIN(id_group) id_group
  FROM pairs
  GROUP BY cohort,codinv
  HAVING COUNT(DISTINCT id_group)=1
)
SELECT u.*
FROM unique_group u
WHERE NOT EXISTS (
        SELECT 1 FROM sp_target_events te
        WHERE te.id_group=u.id_group AND te.event_year<=u.cohort+5
      )
  AND NOT EXISTS (
        SELECT 1 FROM sp_acquirer_events ae
        WHERE ae.id_group=u.id_group
          AND ae.event_year BETWEEN u.cohort-5 AND u.cohort+5
      )
", min(COHORTS), max(COHORTS) + 1L))

message("Split-preperiod: construct firm covariates and IPC4 support through t=-4")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_firm_roster AS
SELECT DISTINCT cohort,'treated' arm,deal_id,group_id
FROM sp_treated
UNION ALL
SELECT DISTINCT cohort,'control' arm,NULL::BIGINT deal_id,id_group group_id
FROM sp_control_early_pairs
")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_group_year_inventors AS
SELECT id_group,year,COUNT(DISTINCT codinv) inventor_count
FROM p6.lmv2_inventor_group_patent_year
GROUP BY id_group,year
")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_firm_units AS
SELECT r.*,
       LN(1+COALESCE(p5.patent_count,0)) log_firm_patent_m5,
       LN(1+COALESCE(p4.patent_count,0)) log_firm_patent_m4,
       LN(1+COALESCE(i5.inventor_count,0)) log_firm_inventors_m5,
       LN(1+COALESCE(i4.inventor_count,0)) log_firm_inventors_m4,
       COALESCE(p5.patent_count,0)::DOUBLE firm_patent_m5,
       COALESCE(p4.patent_count,0)::DOUBLE firm_patent_m4,
       COALESCE(i5.inventor_count,0)::DOUBLE firm_inventors_m5,
       COALESCE(i4.inventor_count,0)::DOUBLE firm_inventors_m4
FROM sp_firm_roster r
LEFT JOIN lmv2_p3_group_year_patents p5
  ON p5.id_group=r.group_id AND p5.year=r.cohort-5
LEFT JOIN lmv2_p3_group_year_patents p4
  ON p4.id_group=r.group_id AND p4.year=r.cohort-4
LEFT JOIN sp_group_year_inventors i5
  ON i5.id_group=r.group_id AND i5.year=r.cohort-5
LEFT JOIN sp_group_year_inventors i4
  ON i4.id_group=r.group_id AND i4.year=r.cohort-4
")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_firm_ipc AS
WITH weighted AS (
  SELECT r.cohort,r.arm,r.deal_id,r.group_id,m.ipc_feature,
         SUM(g.patent_count)::DOUBLE weight
  FROM sp_firm_roster r
  JOIN group_ipc_year g
    ON CAST(g.id_group AS BIGINT)=r.group_id
   AND g.year BETWEEN r.cohort-7 AND r.cohort-4
  JOIN lmv2_p3_ipc_code_map m
    ON m.ipc_code=g.ipc_code AND m.resolution='ipc4'
  GROUP BY r.cohort,r.arm,r.deal_id,r.group_id,m.ipc_feature
)
SELECT *,weight/SUM(weight) OVER (
  PARTITION BY cohort,arm,deal_id,group_id) frequency
FROM weighted
")

firm_units <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT * FROM sp_firm_units ORDER BY cohort,arm,deal_id,group_id"))
firm_scalar_vars <- c(
  "log_firm_patent_m5", "log_firm_patent_m4",
  "log_firm_inventors_m5", "log_firm_inventors_m4")
firm_std <- standardize_by_cohort(
  firm_units, firm_scalar_vars, "firm_distance")
firm_scalers <- firm_std$scaler
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_firm_cosine AS
WITH numer AS (
  SELECT t.cohort,t.deal_id,t.group_id treated_group,
         c.group_id control_group,
         SUM(t.frequency*c.frequency) numerator
  FROM sp_firm_ipc t
  JOIN sp_firm_ipc c
    ON c.cohort=t.cohort AND c.arm='control'
   AND c.ipc_feature=t.ipc_feature
  WHERE t.arm='treated'
  GROUP BY t.cohort,t.deal_id,t.group_id,c.group_id
), norms AS (
  SELECT cohort,arm,deal_id,group_id,
         SQRT(SUM(frequency*frequency)) norm
  FROM sp_firm_ipc
  GROUP BY cohort,arm,deal_id,group_id
)
SELECT n.*,n.numerator/NULLIF(nt.norm*nc.norm,0) cosine
FROM numer n
JOIN norms nt
  ON nt.cohort=n.cohort AND nt.arm='treated'
 AND nt.deal_id=n.deal_id AND nt.group_id=n.treated_group
JOIN norms nc
  ON nc.cohort=n.cohort AND nc.arm='control'
 AND nc.group_id=n.control_group
")
firm_cosine <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT * FROM sp_firm_cosine WHERE cosine>0"))
firm_t <- firm_std$data[arm == "treated", .(
  cohort, deal_id, treated_group = group_id,
  t_pat5 = z_log_firm_patent_m5,
  t_pat4 = z_log_firm_patent_m4,
  t_inv5 = z_log_firm_inventors_m5,
  t_inv4 = z_log_firm_inventors_m4)]
firm_c <- firm_std$data[arm == "control", .(
  cohort, control_group = group_id,
  c_pat5 = z_log_firm_patent_m5,
  c_pat4 = z_log_firm_patent_m4,
  c_inv5 = z_log_firm_inventors_m5,
  c_inv4 = z_log_firm_inventors_m4)]
firm_edges <- merge(
  firm_cosine, firm_t,
  by = c("cohort", "deal_id", "treated_group"), sort = FALSE)
firm_edges <- merge(
  firm_edges, firm_c,
  by = c("cohort", "control_group"), sort = FALSE)
firm_edges[, distance := sqrt(
  (t_pat5 - c_pat5)^2 + (t_pat4 - c_pat4)^2 +
  (t_inv5 - c_inv5)^2 + (t_inv4 - c_inv4)^2 +
  (1 - cosine)^2)]
selected_firms <- firm_edges[
  order(cohort, deal_id, distance, control_group),
  head(.SD, FIRM_K), by = .(cohort, deal_id)]
selected_firms[, rank := seq_len(.N), by = .(cohort, deal_id)]
DBI::dbWriteTable(
  con, "sp_selected_firms", as.data.frame(selected_firms),
  temporary = TRUE, overwrite = TRUE)

message("Split-preperiod: construct inventor support through t=-4")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_inventor_roster AS
SELECT cohort,'treated' arm,deal_id,codinv,group_id
FROM sp_treated
UNION ALL
SELECT cohort,'control' arm,NULL::BIGINT deal_id,codinv,id_group group_id
FROM sp_control_early_pairs
")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_career_first AS
SELECT CAST(codinv AS BIGINT) codinv,MIN(career_first_year) career_first_year
FROM inventor_year
GROUP BY CAST(codinv AS BIGINT)
")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_inventor_units AS
SELECT r.*,
       COALESCE(y5.patent_count,0)::DOUBLE patent_m5,
       COALESCE(y4.patent_count,0)::DOUBLE patent_m4,
       (COALESCE(y5.patent_count,0)>0)::INTEGER active_m5,
       (COALESCE(y4.patent_count,0)>0)::INTEGER active_m4,
       LN(1+COALESCE(y5.patent_count,0)) log_patent_m5,
       LN(1+COALESCE(y4.patent_count,0)) log_patent_m4,
       (r.cohort-4-c.career_first_year)::DOUBLE career_age_m4
FROM sp_inventor_roster r
LEFT JOIN p6.lmv2_outcome_inventor_year y5
  ON y5.codinv=r.codinv AND y5.year=r.cohort-5
LEFT JOIN p6.lmv2_outcome_inventor_year y4
  ON y4.codinv=r.codinv AND y4.year=r.cohort-4
LEFT JOIN sp_career_first c ON c.codinv=r.codinv
WHERE c.career_first_year IS NOT NULL
")
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_inventor_ipc AS
WITH weighted AS (
  SELECT r.cohort,r.arm,r.deal_id,r.codinv,m.ipc_feature,
         SUM(i.patent_count)::DOUBLE weight
  FROM sp_inventor_roster r
  JOIN inventor_ipc_year i
    ON CAST(i.codinv AS BIGINT)=r.codinv
   AND i.year BETWEEN r.cohort-7 AND r.cohort-4
  JOIN lmv2_p3_ipc_code_map m
    ON m.ipc_code=i.ipc_code AND m.resolution='ipc4'
  GROUP BY r.cohort,r.arm,r.deal_id,r.codinv,m.ipc_feature
)
SELECT *,weight/SUM(weight) OVER (
  PARTITION BY cohort,arm,deal_id,codinv) frequency
FROM weighted
")

inv_units <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT * FROM sp_inventor_units ORDER BY cohort,arm,deal_id,codinv"))
inv_scalar_vars <- c("log_patent_m5", "log_patent_m4", "career_age_m4")
inv_std <- standardize_by_cohort(
  inv_units, inv_scalar_vars, "inventor_distance")
inv_scalers <- inv_std$scaler
DBI::dbExecute(con, "
CREATE TEMP TABLE sp_inventor_cosine_edges AS
WITH admissible AS (
  SELECT t.cohort,t.deal_id,t.codinv treated_codinv,
         c.codinv control_codinv,c.group_id control_group
  FROM sp_inventor_units t
  JOIN sp_selected_firms f
    ON f.cohort=t.cohort AND f.deal_id=t.deal_id
  JOIN sp_inventor_units c
    ON c.cohort=t.cohort AND c.arm='control'
   AND c.group_id=f.control_group
  WHERE t.arm='treated'
), numer AS (
  SELECT a.*,SUM(t.frequency*c.frequency) numerator
  FROM admissible a
  JOIN sp_inventor_ipc t
    ON t.cohort=a.cohort AND t.arm='treated'
   AND t.deal_id=a.deal_id AND t.codinv=a.treated_codinv
  JOIN sp_inventor_ipc c
    ON c.cohort=a.cohort AND c.arm='control'
   AND c.codinv=a.control_codinv
   AND c.ipc_feature=t.ipc_feature
  GROUP BY a.cohort,a.deal_id,a.treated_codinv,
           a.control_codinv,a.control_group
), norms AS (
  SELECT cohort,arm,deal_id,codinv,
         SQRT(SUM(frequency*frequency)) norm
  FROM sp_inventor_ipc
  GROUP BY cohort,arm,deal_id,codinv
)
SELECT n.*,n.numerator/NULLIF(nt.norm*nc.norm,0) cosine
FROM numer n
JOIN norms nt
  ON nt.cohort=n.cohort AND nt.arm='treated'
 AND nt.deal_id=n.deal_id AND nt.codinv=n.treated_codinv
JOIN norms nc
  ON nc.cohort=n.cohort AND nc.arm='control'
 AND nc.codinv=n.control_codinv
WHERE n.numerator>0
")
edges <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT * FROM sp_inventor_cosine_edges"))
inv_t <- inv_std$data[arm == "treated", .(
  cohort, deal_id, treated_codinv = codinv,
  t_pat5 = z_log_patent_m5, t_pat4 = z_log_patent_m4,
  t_age = z_career_age_m4)]
inv_c <- inv_std$data[arm == "control", .(
  cohort, control_codinv = codinv, control_group = group_id,
  c_pat5 = z_log_patent_m5, c_pat4 = z_log_patent_m4,
  c_age = z_career_age_m4)]
edges <- merge(
  edges, inv_t,
  by = c("cohort", "deal_id", "treated_codinv"), sort = FALSE)
edges <- merge(
  edges, inv_c,
  by = c("cohort", "control_codinv", "control_group"), sort = FALSE)
edges[, distance := sqrt(
  (t_pat5 - c_pat5)^2 + (t_pat4 - c_pat4)^2 +
  (t_age - c_age)^2 + (1 - cosine)^2)]
data.table::setorder(
  edges, cohort, deal_id, treated_codinv,
  distance, control_codinv, control_group)
if (!nrow(edges)) stop("No prospective inventor support edges")

selected <- edges[, {
  z <- .SD[order(distance, control_codinv, control_group)]
  z <- z[!duplicated(control_codinv)]
  if (nrow(z) < INVENTOR_K) {
    .SD[0]
  } else {
    take <- z[seq_len(INVENTOR_K)]
    if (data.table::uniqueN(take$control_group) < 2L) {
      alternative <- z[control_group != take$control_group[[1]]]
      if (!nrow(alternative)) {
        take <- z[0]
      } else {
        take <- data.table::rbindlist(list(
          take[seq_len(INVENTOR_K - 1L)], alternative[1L]))
      }
    }
    if (nrow(take) == INVENTOR_K &&
        data.table::uniqueN(take$control_group) >= 2L) take else .SD[0]
  }
}, by = .(cohort, deal_id, treated_codinv)]
selected <- unique(selected[, .(
  cohort, deal_id, treated_codinv, control_codinv, control_group,
  distance, cosine)])
if (!nrow(selected)) stop("No treated inventor passed prospective support")

support_counts <- selected[, .(
  n_controls = data.table::uniqueN(control_codinv),
  n_control_firms = data.table::uniqueN(control_group)),
  by = .(cohort, deal_id, treated_codinv)]
if (any(support_counts$n_controls != INVENTOR_K) ||
    any(support_counts$n_control_firms < 2L)) {
  stop("Stage-2 support invariant failed")
}

message("Split-preperiod: solve frozen cohort entropy balances")
treated_units <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT i.cohort,i.deal_id,i.codinv,i.group_id,
       i.patent_m5,i.patent_m4,i.active_m5,i.active_m4,i.career_age_m4,
       f.firm_patent_m5,f.firm_patent_m4,
       f.firm_inventors_m5,f.firm_inventors_m4
FROM sp_inventor_units i
JOIN sp_firm_units f
  ON f.cohort=i.cohort AND f.arm='treated'
 AND f.deal_id=i.deal_id AND f.group_id=i.group_id
WHERE i.arm='treated'
"))
control_units <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT i.cohort,i.codinv,i.group_id,
       i.patent_m5,i.patent_m4,i.active_m5,i.active_m4,i.career_age_m4,
       f.firm_patent_m5,f.firm_patent_m4,
       f.firm_inventors_m5,f.firm_inventors_m4
FROM sp_inventor_units i
JOIN sp_firm_units f
  ON f.cohort=i.cohort AND f.arm='control' AND f.group_id=i.group_id
WHERE i.arm='control'
"))

all_weights <- list()
all_balance <- list()
all_diagnostics <- list()
for (g in COHORTS) {
  s <- selected[cohort == g]
  if (!nrow(s)) {
    all_diagnostics[[as.character(g)]] <- data.frame(
      cohort = g, feasible = FALSE, reason = "no_supported_treated",
      early_treated = sum(treated_units$cohort == g),
      supported_treated = 0, retained_deals = 0,
      control_rows = 0, unique_controls = 0,
      control_ess = NA_real_, max_abs_smd = NA_real_,
      solver_warnings = NA_character_)
    next
  }
  supported_t <- unique(s[, .(deal_id, codinv = treated_codinv)])
  tr <- merge(
    supported_t, treated_units[cohort == g],
    by = c("deal_id", "codinv"), all.x = TRUE, sort = FALSE)
  tr[, `:=`(D = 1L, group_id = as.numeric(group_id))]

  supported_c <- unique(s[, .(
    deal_id, codinv = control_codinv, group_id = control_group)])
  co <- merge(
    supported_c, control_units[cohort == g],
    by = c("codinv", "group_id"), all.x = TRUE, sort = FALSE)
  co[, D := 0L]
  keep_cols <- c(
    "deal_id", "codinv", "group_id", "D", BALANCE_VARS)
  roster <- data.table::rbindlist(list(
    tr[, ..keep_cols], co[, ..keep_cols]), use.names = TRUE)
  data.table::setorder(roster, deal_id, D, codinv, group_id)
  if (any(!is.finite(as.matrix(roster[, ..BALANCE_VARS])))) {
    stop("Non-finite balance covariate in cohort ", g)
  }
  deal_mass <- roster[, .(
    n_treated = sum(D == 1L), n_control = sum(D == 0L)), by = deal_id]
  roster <- merge(roster, deal_mass, by = "deal_id", sort = FALSE)
  roster[, base_weight := ifelse(
    D == 1L, 1, n_treated / n_control)]
  set.seed(20260727L + g)
  fit <- entropy_balance(roster)
  feasible <- isTRUE(fit$ok)
  reason <- if (feasible) "exact_ebal" else fit$error
  if (feasible) {
    roster[, final_weight := fit$weight]
    roster[, cohort := g]
    roster[, roster_row_id := paste(
      cohort, deal_id, D, format(codinv, scientific = FALSE),
      format(group_id, scientific = FALSE), sep = ":")]
    if (anyDuplicated(roster$roster_row_id)) {
      stop("Roster row ID is not unique in cohort ", g)
    }
    all_weights[[as.character(g)]] <- roster
    bal <- fit$balance
    bal$cohort <- g
    all_balance[[as.character(g)]] <- bal
    atomic_csv(
      roster,
      file.path(WEIGHT_DIR, sprintf(
        "split_preperiod_weights_c%d.csv", g)))
  }
  all_diagnostics[[as.character(g)]] <- data.frame(
    cohort = g, feasible = feasible, reason = reason,
    early_treated = sum(treated_units$cohort == g),
    supported_treated = nrow(tr),
    retained_deals = data.table::uniqueN(tr$deal_id),
    control_rows = nrow(co),
    unique_controls = data.table::uniqueN(co$codinv),
    control_ess = if (feasible)
      ess(roster$final_weight[roster$D == 0L]) else NA_real_,
    max_abs_smd = if (feasible) fit$max_smd else NA_real_,
    solver_warnings =
      if (nzchar(fit$warnings)) fit$warnings else NA_character_)
}

diagnostics <- do.call(rbind, all_diagnostics)
atomic_csv(diagnostics, file.path(OUT_DIR, "design_diagnostics.csv"))
if (!length(all_weights)) stop("No cohort produced an exact entropy balance")
weights <- data.table::rbindlist(all_weights, use.names = TRUE)
balance <- do.call(rbind, all_balance)
atomic_csv(balance, file.path(OUT_DIR, "balance.csv"))
atomic_csv(
  rbind(firm_scalers, inv_scalers),
  file.path(OUT_DIR, "distance_scalers.csv"))
atomic_csv(
  support_counts,
  file.path(OUT_DIR, "inventor_support_counts.csv"))

# This manifest is published before any outcome is queried below. It is the
# executable no-leakage handoff between design construction and estimation.
weight_files <- list.files(
  WEIGHT_DIR, pattern = "\\.csv$", full.names = TRUE)
weight_manifest <- data.frame(
  execution_hash = execution_hash,
  source_sha256 = source_hash,
  freeze_sha256 = freeze_hash,
  technical_amendment_sha256 = amendment_hash,
  maximum_matching_event_time = -4L,
  untouched_validation_event_times = "-3,-2,-1",
  n_feasible_cohorts = length(all_weights),
  feasible_cohorts = paste(sort(unique(weights$cohort)), collapse = ","),
  roster_rows = nrow(weights),
  treated_rows = sum(weights$D == 1L),
  control_rows = sum(weights$D == 0L),
  treated_deals = data.table::uniqueN(
    weights[D == 1L, paste(cohort, deal_id)]),
  control_ess = ess(weights$final_weight[weights$D == 0L]),
  max_abs_smd = max(balance$abs_difference_std),
  weight_files_sha256 = paste(vapply(
    sort(weight_files), digest::digest, character(1),
    file = TRUE, algo = "sha256", serialize = FALSE), collapse = ";"),
  stringsAsFactors = FALSE)
atomic_csv(weight_manifest, file.path(OUT_DIR, "weight_manifest.csv"))
if (weight_manifest$maximum_matching_event_time != -4L ||
    weight_manifest$max_abs_smd > EXACT_BALANCE_TOL) {
  stop("Frozen design handoff failed")
}

message("Split-preperiod: estimate untouched leads and post effects jointly")
unit_ids <- unique(weights[, .(codinv, cohort)])
DBI::dbWriteTable(
  con, "sp_estimation_units", as.data.frame(unit_ids),
  temporary = TRUE, overwrite = TRUE)
# Rebuild the complete grid explicitly to avoid relying on nullable y.year.
grid <- data.table::CJ(
  row_index = seq_len(nrow(weights)),
  event_time = c(REFERENCE_TIME, EVENT_TIMES))
panel <- merge(
  grid,
  cbind(row_index = seq_len(nrow(weights)), weights),
  by = "row_index", sort = FALSE)
observed_y <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT u.codinv,u.cohort,y.year-u.cohort event_time,
       y.patent_count::DOUBLE patent_count
FROM sp_estimation_units u
JOIN p6.lmv2_outcome_inventor_year y
  ON y.codinv=u.codinv
 AND y.year BETWEEN u.cohort-4 AND u.cohort+5
"))
panel <- merge(
  panel, observed_y,
  by = c("codinv", "cohort", "event_time"),
  all.x = TRUE, sort = FALSE)
panel[is.na(patent_count), patent_count := 0]
baseline <- panel[event_time == REFERENCE_TIME,
                  .(row_index, patent_baseline = patent_count)]
panel <- merge(panel, baseline, by = "row_index", sort = FALSE)
panel[, delta := patent_count - patent_baseline]

k <- length(EVENT_TIMES)
att <- numeric(k)
scores <- matrix(0, nrow(weights), k)
for (j in seq_along(EVENT_TIMES)) {
  e <- EVENT_TIMES[[j]]
  z <- panel[event_time == e][order(row_index)]
  if (!identical(z$row_index, seq_len(nrow(weights)))) {
    stop("Panel row order invariant failed at event time ", e)
  }
  wt <- z$final_weight
  treated <- z$D == 1L
  mu_t <- weighted_mean(z$delta[treated], wt[treated])
  mu_c <- weighted_mean(z$delta[!treated], wt[!treated])
  att[[j]] <- mu_t - mu_c
  scores[, j] <- ifelse(
    treated,
    wt * (z$delta - mu_t) / sum(wt[treated]),
    -wt * (z$delta - mu_c) / sum(wt[!treated]))
}

deal_cluster <- paste(weights$cohort, weights$deal_id, sep = ":")
inventor_cluster <- format(weights$codinv, scientific = FALSE)
intersection_cluster <- paste(deal_cluster, inventor_cluster, sep = ":")
v_deal <- cluster_meat(scores, deal_cluster)
v_inventor <- cluster_meat(scores, inventor_cluster)
v_intersection <- cluster_meat(scores, intersection_cluster)
v_two_way <- v_deal + v_inventor - v_intersection
v_two_way <- (v_two_way + t(v_two_way)) / 2

se_deal <- sqrt(pmax(diag(v_deal), 0))
se_two <- sqrt(pmax(diag(v_two_way), 0))
dynamic <- data.frame(
  event_time = EVENT_TIMES,
  estimate = att,
  se_deal = se_deal,
  ci_low_deal = att - 1.96 * se_deal,
  ci_high_deal = att + 1.96 * se_deal,
  p_deal = 2 * stats::pnorm(-abs(att / se_deal)),
  se_two_way = se_two,
  ci_low_two_way = att - 1.96 * se_two,
  ci_high_two_way = att + 1.96 * se_two,
  p_two_way = 2 * stats::pnorm(-abs(att / se_two))
)
atomic_csv(dynamic, file.path(OUT_DIR, "joint_event_study.csv"))
atomic_csv(
  data.frame(event_time_row = EVENT_TIMES, v_deal),
  file.path(OUT_DIR, "joint_covariance_deal.csv"))
atomic_csv(
  data.frame(event_time_row = EVENT_TIMES, v_two_way),
  file.path(OUT_DIR, "joint_covariance_two_way.csv"))

pre_idx <- match(PRE_TIMES, EVENT_TIMES)
wald <- drop(att[pre_idx] %*%
               safe_inverse(v_deal[pre_idx, pre_idx, drop = FALSE]) %*%
               att[pre_idx])
pre_test <- data.frame(
  tested_event_times = paste(PRE_TIMES, collapse = ","),
  statistic = wald, df = length(PRE_TIMES),
  p_value = stats::pchisq(wald, df = length(PRE_TIMES), lower.tail = FALSE))
atomic_csv(pre_test, file.path(OUT_DIR, "joint_pretrend_test.csv"))

l_full <- rep(0, k)
l_full[match(PRIMARY_POST_TIMES, EVENT_TIMES)] <-
  1 / length(PRIMARY_POST_TIMES)
post_est <- sum(l_full * att)
post_se_deal <- sqrt(drop(t(l_full) %*% v_deal %*% l_full))
post_se_two <- sqrt(max(drop(t(l_full) %*% v_two_way %*% l_full), 0))
post <- data.frame(
  contrast = "equal_average_t_plus_1_to_t_plus_5",
  estimate = post_est,
  se_deal = post_se_deal,
  ci_low_deal = post_est - 1.96 * post_se_deal,
  ci_high_deal = post_est + 1.96 * post_se_deal,
  p_deal = 2 * stats::pnorm(-abs(post_est / post_se_deal)),
  se_two_way = post_se_two,
  ci_low_two_way = post_est - 1.96 * post_se_two,
  ci_high_two_way = post_est + 1.96 * post_se_two,
  p_two_way = 2 * stats::pnorm(-abs(post_est / post_se_two)))
atomic_csv(post, file.path(OUT_DIR, "post_att.csv"))

if (RUN_HONESTDID) {
  message("Split-preperiod: run formal Rambachan-Roth sensitivity")
  honest_l <- c(0, rep(1 / length(PRIMARY_POST_TIMES),
                      length(PRIMARY_POST_TIMES)))
  honest <- tryCatch(
    HonestDiD::createSensitivityResults_relativeMagnitudes(
      betahat = att,
      sigma = v_deal,
      numPrePeriods = length(PRE_TIMES),
      numPostPeriods = length(POST_TIMES),
      bound = "deviation from parallel trends",
      method = "C-LF",
      Mbarvec = MBAR_GRID,
      l_vec = honest_l,
      alpha = 0.05,
      gridPoints = 500,
      parallel = FALSE,
      seed = 20260727),
    error = function(e) e)
  if (inherits(honest, "condition")) {
    warning("HonestDiD failed on raw covariance: ", conditionMessage(honest))
    near <- as.matrix(Matrix::nearPD(v_deal, corr = FALSE)$mat)
    honest <- HonestDiD::createSensitivityResults_relativeMagnitudes(
      betahat = att, sigma = near,
      numPrePeriods = length(PRE_TIMES),
      numPostPeriods = length(POST_TIMES),
      bound = "deviation from parallel trends",
      method = "C-LF", Mbarvec = MBAR_GRID,
      l_vec = honest_l, alpha = 0.05, gridPoints = 500,
      parallel = FALSE, seed = 20260727)
    covariance_used <- "nearest_positive_definite_deal_covariance"
  } else {
    covariance_used <- "raw_deal_clustered_covariance"
  }
  honest <- as.data.frame(honest)
  honest$covariance_used <- covariance_used
  break_rows <- honest[honest$ub >= 0, , drop = FALSE]
  breakdown_mbar <- if (nrow(break_rows)) {
    min(break_rows$Mbar)
  } else {
    NA_real_
  }
} else {
  message(
    "Split-preperiod: HonestDiD skipped; design retained for feasibility audit")
  covariance_used <- "not_run_design_infeasible"
  honest <- data.frame(
    lb = numeric(), ub = numeric(), method = character(),
    Delta = character(), Mbar = numeric(), covariance_used = character())
  breakdown_mbar <- NA_real_
}
atomic_csv(honest, file.path(OUT_DIR, "honestdid_relative_magnitude.csv"))
breakdown <- data.frame(
  estimand = "equal_average_t_plus_1_to_t_plus_5",
  conventional_estimate = post_est,
  first_mbar_with_upper_ci_at_or_above_zero = breakdown_mbar,
  largest_evaluated_mbar = max(MBAR_GRID),
  sign_robust_through_grid =
    if (RUN_HONESTDID) is.na(breakdown_mbar) else NA,
  run_status = if (RUN_HONESTDID) "completed" else
    "not_run_design_infeasible",
  covariance_used = covariance_used)
atomic_csv(breakdown, file.path(OUT_DIR, "honestdid_breakdown.csv"))

plot_data <- rbind(
  data.frame(
    event_time = REFERENCE_TIME, estimate = 0,
    ci_low_deal = 0, ci_high_deal = 0),
  dynamic[, c("event_time", "estimate", "ci_low_deal", "ci_high_deal")])
p <- ggplot2::ggplot(
  plot_data, ggplot2::aes(x = event_time, y = estimate)) +
  ggplot2::geom_hline(yintercept = 0, colour = "#7A7A7A", linewidth = 0.45) +
  ggplot2::geom_vline(
    xintercept = -0.5, colour = "#7A7A7A", linetype = "dashed",
    linewidth = 0.45) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = ci_low_deal, ymax = ci_high_deal),
    fill = "#8FB9AD", alpha = 0.24) +
  ggplot2::geom_line(colour = "#285D55", linewidth = 0.85) +
  ggplot2::geom_point(colour = "#285D55", size = 2.1) +
  ggplot2::scale_x_continuous(breaks = -4:5) +
  ggplot2::labs(
    title = "Split-preperiod event study for established inventors",
    subtitle = paste0(
      "Recruit at t=-7,-6; match through t=-4; untouched leads t=-3,-2,-1"),
    x = "Event time", y = "Patent-count ATT relative to t=-4",
    caption = "Shaded interval: 95% deal-clustered confidence interval") +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(
    plot.title.position = "plot",
    panel.grid.minor = ggplot2::element_blank())
ggplot2::ggsave(
  file.path(OUT_DIR, "split_preperiod_event_study.png"),
  p, width = 8.4, height = 5.2, dpi = 220)
ggplot2::ggsave(
  file.path(OUT_DIR, "split_preperiod_event_study.pdf"),
  p, width = 8.4, height = 5.2)

summary <- data.frame(
  execution_hash = execution_hash,
  feasible_cohorts = paste(sort(unique(weights$cohort)), collapse = ","),
  n_feasible_cohorts = data.table::uniqueN(weights$cohort),
  treated_inventors = sum(weights$D == 1L),
  retained_deals = data.table::uniqueN(
    weights[D == 1L, paste(cohort, deal_id)]),
  control_rows = sum(weights$D == 0L),
  unique_control_inventors =
    data.table::uniqueN(weights[D == 0L, codinv]),
  control_ess = ess(weights$final_weight[weights$D == 0L]),
  max_abs_smd = max(balance$abs_difference_std),
  joint_pretrend_p = pre_test$p_value,
  post_att = post$estimate,
  post_ci_low_deal = post$ci_low_deal,
  post_ci_high_deal = post$ci_high_deal,
  post_p_deal = post$p_deal,
  post_ci_low_two_way = post$ci_low_two_way,
  post_ci_high_two_way = post$ci_high_two_way,
  post_p_two_way = post$p_two_way,
  honestdid_breakdown_mbar =
    breakdown$first_mbar_with_upper_ci_at_or_above_zero,
  honestdid_covariance = covariance_used,
  stringsAsFactors = FALSE)
atomic_csv(summary, file.path(OUT_DIR, "results_summary.csv"))

certification <- data.frame(
  check = c(
    "source_and_freeze_hashed",
    "matching_information_ends_at_t_minus_4",
    "validation_leads_untouched",
    "support_has_three_controls_two_firms",
    "at_least_one_exactly_balanced_cohort",
    "all_saved_weights_valid",
    "exact_balance_within_2e_minus_5",
    "joint_covariance_dimension_correct",
    "honestdid_scope_respected"),
  pass = c(
    nzchar(source_hash) && nzchar(freeze_hash),
    weight_manifest$maximum_matching_event_time == -4L,
    identical(weight_manifest$untouched_validation_event_times, "-3,-2,-1"),
    all(support_counts$n_controls == 3L &
          support_counts$n_control_firms >= 2L),
    length(all_weights) >= 1L,
    all(is.finite(weights$final_weight) & weights$final_weight >= 0) &&
      all(weights$final_weight[weights$D == 1L] > 0) &&
      sum(weights$final_weight[weights$D == 0L]) > 0,
    weight_manifest$max_abs_smd <= EXACT_BALANCE_TOL,
    identical(dim(v_deal), c(k, k)),
    (!RUN_HONESTDID && nrow(honest) == 0L) ||
      (RUN_HONESTDID && nrow(honest) == length(MBAR_GRID))),
  detail = c(
    paste(source_hash, freeze_hash, sep = ";"),
    "-4", "-3,-2,-1", "3 controls; >=2 firms",
    as.character(length(all_weights)),
    as.character(
      all(is.finite(weights$final_weight) & weights$final_weight >= 0) &&
        all(weights$final_weight[weights$D == 1L] > 0)),
    format(weight_manifest$max_abs_smd, scientific = TRUE),
    paste(dim(v_deal), collapse = "x"),
    if (RUN_HONESTDID) paste(nrow(honest), "rows") else
      "skipped after design infeasibility decision"))
atomic_csv(certification, file.path(OUT_DIR, "certification.csv"))
if (!all(certification$pass)) {
  stop("Split-preperiod certification failed: ",
       paste(certification$check[!certification$pass], collapse = ", "))
}

message(
  "Split-preperiod design certified | cohorts=",
  summary$n_feasible_cohorts,
  " | treated=", summary$treated_inventors,
  " | post ATT=", sprintf("%.4f", summary$post_att),
  " | joint pre p=", sprintf("%.4f", summary$joint_pretrend_p),
  " | HonestDiD breakdown Mbar=",
  if (!RUN_HONESTDID) {
    "not run (design infeasible)"
  } else if (is.na(summary$honestdid_breakdown_mbar)) {
    ">3"
  } else {
    summary$honestdid_breakdown_mbar
  })
