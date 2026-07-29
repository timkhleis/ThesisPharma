# ============================================================================
# Prospective partially pooled synthetic-control triangulation
# ============================================================================
# The script queries post-treatment outcomes only after the frozen validation
# gates pass. Run with --estimate to permit that gated second stage.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "data.table", "Matrix", "osqp", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_ppscm_freeze.md")
DB_PATH <- file.path(BASE, "output", "thesis_foundation.duckdb")
OUT_DIR <- file.path(
  BASE, "output", "audit", "local_match_v2", "P6_PPSCM_PROSPECTIVE")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

COHORTS <- 1995:2010
FIRM_K <- 5L
MIN_DONORS <- 3L
TRAIN_TIMES <- -7:-4
VALID_TIMES <- -3:-1
POST_TIMES <- 0:5
PRIMARY_POST_TIMES <- 1:5
RIDGE <- 1e-4
EQUIVALENCE_BAND <- 0.05
MIN_DEALS <- 100L
MIN_COVERAGE <- 0.80
MIN_MEDIAN_ESS <- 2
MIN_P10_ESS <- 1.25
MAX_DONOR_WEIGHT <- 0.90
ALLOW_POST <- "--estimate" %in% commandArgs(trailingOnly = TRUE)

atomic_csv <- function(x, path) {
  tmp <- paste0(path, ".tmp")
  utils::write.csv(x, tmp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Could not publish ", path)
  invisible(path)
}

standardize_by_cohort <- function(x, variables) {
  out <- data.table::copy(x)
  for (v in variables) {
    out[, paste0("z_", v) := {
      s <- stats::sd(get(v), na.rm = TRUE)
      m <- mean(get(v), na.rm = TRUE)
      if (!is.finite(s) || s < 1e-10) rep(0, .N) else (get(v) - m) / s
    }, by = cohort]
  }
  out
}

solve_simplex_qp <- function(h, f, block_sizes) {
  p <- nrow(h)
  equality <- Matrix::sparseMatrix(
    i = rep(seq_along(block_sizes), block_sizes),
    j = seq_len(p), x = 1,
    dims = c(length(block_sizes), p))
  a <- rbind(equality, Matrix::Diagonal(p))
  lower <- c(rep(1, length(block_sizes)), rep(0, p))
  upper <- c(rep(1, length(block_sizes)), rep(Inf, p))
  fit <- osqp::solve_osqp(
    P = Matrix::forceSymmetric(Matrix::Matrix(2 * h, sparse = TRUE)),
    q = as.numeric(2 * f), A = a, l = lower, u = upper,
    pars = osqp::osqpSettings(
      verbose = FALSE, eps_abs = 1e-8, eps_rel = 1e-8,
      max_iter = 200000L, polish = TRUE))
  if (!grepl("solved", fit$info$status, ignore.case = TRUE)) {
    stop("OSQP failed: ", fit$info$status)
  }
  w <- pmax(as.numeric(fit$x), 0)
  starts <- cumsum(c(1L, head(block_sizes, -1L)))
  for (j in seq_along(block_sizes)) {
    idx <- starts[[j]]:(starts[[j]] + block_sizes[[j]] - 1L)
    w[idx] <- w[idx] / sum(w[idx])
  }
  list(weight = w, status = fit$info$status, objective = fit$info$obj_val)
}

design_matrices <- function(panel, deal_weights, times) {
  deals <- sort(unique(panel$deal_id))
  block_sizes <- integer(length(deals))
  donor_keys <- vector("list", length(deals))
  y_rows <- vector("list", length(deals))
  x_rows <- vector("list", length(deals))
  col_start <- 1L
  total_cols <- sum(panel[, data.table::uniqueN(donor_group), by = deal_id]$V1)
  x_sep <- Matrix::Matrix(
    0, nrow = length(deals) * length(times), ncol = total_cols, sparse = TRUE)
  y_sep <- numeric(nrow(x_sep))
  row_weight <- numeric(nrow(x_sep))
  x_pool <- Matrix::Matrix(
    0, nrow = length(times), ncol = total_cols, sparse = TRUE)
  y_pool <- numeric(length(times))

  for (j in seq_along(deals)) {
    d <- deals[[j]]
    z <- panel[deal_id == d]
    donors <- sort(unique(z$donor_group))
    block_sizes[[j]] <- length(donors)
    cols <- col_start:(col_start + length(donors) - 1L)
    rows <- ((j - 1L) * length(times) + 1L):(j * length(times))
    ty <- z[match(times, event_time), treated_demeaned]
    dx <- vapply(donors, function(g) {
      z[donor_group == g][match(times, event_time), donor_demeaned]
    }, numeric(length(times)))
    if (is.null(dim(dx))) dx <- matrix(dx, ncol = 1L)
    x_sep[rows, cols] <- dx
    y_sep[rows] <- ty
    row_weight[rows] <- deal_weights[as.character(d)] / length(times)
    x_pool[, cols] <- deal_weights[as.character(d)] * dx
    y_pool <- y_pool + deal_weights[as.character(d)] * ty
    donor_keys[[j]] <- data.table::data.table(
      deal_id = d, donor_group = donors, column = cols)
    col_start <- max(cols) + 1L
  }
  list(
    deals = deals, block_sizes = block_sizes,
    donor_keys = data.table::rbindlist(donor_keys),
    x_sep = x_sep, y_sep = y_sep, row_weight = row_weight,
    x_pool = x_pool, y_pool = y_pool)
}

quadratic_parts <- function(dm, nu, sep_denom, pool_denom, ridge) {
  ws <- Matrix::Diagonal(x = sqrt(dm$row_weight))
  xs <- ws %*% dm$x_sep
  ys <- as.numeric(ws %*% dm$y_sep)
  xp <- dm$x_pool / sqrt(nrow(dm$x_pool))
  yp <- dm$y_pool / sqrt(length(dm$y_pool))
  sep_scale <- (1 - nu) / max(sep_denom, 1e-10)
  pool_scale <- nu / max(pool_denom, 1e-10)
  h <- sep_scale * crossprod(xs) +
    pool_scale * crossprod(xp) +
    ridge * Matrix::Diagonal(ncol(dm$x_sep))
  f <- -sep_scale * as.numeric(crossprod(xs, ys)) -
    pool_scale * as.numeric(crossprod(xp, yp))
  list(h = h, f = f)
}

imbalance <- function(dm, w) {
  r_sep <- dm$y_sep - as.numeric(dm$x_sep %*% w)
  r_pool <- dm$y_pool - as.numeric(dm$x_pool %*% w)
  list(
    sep_mse = sum(dm$row_weight * r_sep^2),
    pool_mse = mean(r_pool^2),
    sep_rmse = sqrt(sum(dm$row_weight * r_sep^2)),
    pool_rmse = sqrt(mean(r_pool^2)))
}

fit_separate <- function(dm, ridge) {
  weights <- numeric(ncol(dm$x_sep))
  starts <- cumsum(c(1L, head(dm$block_sizes, -1L)))
  l <- nrow(dm$x_pool)
  for (j in seq_along(dm$deals)) {
    rows <- ((j - 1L) * l + 1L):(j * l)
    cols <- starts[[j]]:(starts[[j]] + dm$block_sizes[[j]] - 1L)
    x <- as.matrix(dm$x_sep[rows, cols, drop = FALSE])
    y <- dm$y_sep[rows]
    h <- crossprod(x) / l + ridge * diag(length(cols))
    f <- -as.numeric(crossprod(x, y)) / l
    weights[cols] <- solve_simplex_qp(
      h, f, block_sizes = length(cols))$weight
  }
  weights
}

evaluate_weights <- function(panel, weight_table, times, deal_weights) {
  z <- merge(panel[event_time %in% times], weight_table,
             by = c("deal_id", "donor_group"), sort = FALSE)
  synth <- z[, .(
    treated = unique(treated_demeaned),
    synthetic = sum(scm_weight * donor_demeaned)),
    by = .(deal_id, event_time)]
  synth[, gap := treated - synthetic]
  synth[, aggregation_weight := deal_weights[as.character(deal_id)]]
  pooled <- synth[, .(
    gap = sum(aggregation_weight * gap),
    treated = sum(aggregation_weight * treated),
    synthetic = sum(aggregation_weight * synthetic)),
    by = event_time]
  list(
    deal = synth,
    pooled = pooled,
    pooled_rmse = sqrt(mean(pooled$gap^2)),
    separate_rmse = sqrt(sum(
      synth$aggregation_weight * synth$gap^2) / length(times)))
}

weighted_joint_test <- function(deal_gaps, times, deal_weights) {
  wide <- data.table::dcast(
    deal_gaps[event_time %in% times],
    deal_id ~ event_time, value.var = "gap")
  ids <- wide$deal_id
  x <- as.matrix(wide[, -1])
  w <- deal_weights[as.character(ids)]
  w <- w / sum(w)
  mu <- colSums(x * w)
  centered <- sweep(x, 2, mu, "-")
  v <- crossprod(centered * w)
  correction <- 1 / max(1 - sum(w^2), 1e-10)
  v <- correction * v
  stat <- tryCatch(
    drop(mu %*% solve(v, mu)),
    error = function(e) drop(mu %*% MASS::ginv(v) %*% mu))
  data.frame(
    statistic = stat, df = length(times),
    p_value = stats::pchisq(stat, df = length(times), lower.tail = FALSE))
}

source_hash <- digest::digest(
  file = file.path(BASE, "R", "37_run_lmv2_partially_pooled_scm.R"),
  algo = "sha256", serialize = FALSE)
freeze_hash <- digest::digest(
  file = FREEZE_PATH, algo = "sha256", serialize = FALSE)
execution_hash <- digest::digest(list(
  version = "lmv2_ppscm_prospective_v1",
  source_sha256 = source_hash, freeze_sha256 = freeze_hash,
  cohorts = COHORTS, firm_k = FIRM_K, training = TRAIN_TIMES,
  validation = VALID_TIMES, ridge = RIDGE,
  equivalence_band = EQUIVALENCE_BAND), algo = "sha256")

con <- DBI::dbConnect(
  duckdb::duckdb(), dbdir = DB_PATH, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=1")
DBI::dbExecute(con, "PRAGMA memory_limit='10GB'")

required_tables <- c(
  "lmv2_treated_primary", "deal_assignment",
  "deal_target_company_expanded", "firm_group",
  "lmv2_p3_group_year_patents", "lmv2_p3_ipc_code_map",
  "group_ipc_year")
missing <- required_tables[
  !vapply(required_tables, DBI::dbExistsTable, logical(1), conn = con)]
if (length(missing)) stop("Missing required tables: ", paste(missing, collapse = ", "))
for (tbl in c("lmv2_inventor_group_patent_year",
              "lmv2_inventor_target_company_patent_year",
              "lmv2_outcome_inventor_year")) {
  if (!DBI::dbExistsTable(con, DBI::Id(schema = "p6", table = tbl))) {
    stop("Missing p6.", tbl)
  }
}

message("PPSCM: build prospective early-recruited firm donor pool")
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_target_events AS
SELECT DISTINCT CAST(target_group AS BIGINT) id_group,
       CAST(target_year AS INTEGER) event_year
FROM deal_assignment WHERE target_group IS NOT NULL
UNION
SELECT DISTINCT CAST(fg.id_group AS BIGINT),CAST(da.target_year AS INTEGER)
FROM deal_assignment da
JOIN deal_target_company_expanded dtc USING(deal_id)
JOIN firm_group fg
  ON CAST(fg.compcod AS BIGINT)=dtc.target_compcod
 AND fg.year=CAST(da.target_year AS INTEGER)-1
WHERE fg.id_group IS NOT NULL")
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_acquirer_events AS
SELECT DISTINCT CAST(acquirer_group AS BIGINT) id_group,
       CAST(target_year AS INTEGER) event_year
FROM deal_assignment WHERE acquirer_group IS NOT NULL")
DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE pp_treated AS
SELECT DISTINCT t.cohort,t.deal_id,t.codinv,
       CAST(t.target_group AS BIGINT) group_id
FROM lmv2_treated_primary t
WHERE t.cohort BETWEEN %d AND %d
  AND (EXISTS (
    SELECT 1 FROM p6.lmv2_inventor_group_patent_year g
    WHERE g.codinv=t.codinv AND g.id_group=CAST(t.target_group AS BIGINT)
      AND g.year IN (t.cohort-7,t.cohort-6))
  OR EXISTS (
    SELECT 1 FROM p6.lmv2_inventor_target_company_patent_year c
    WHERE c.codinv=t.codinv AND c.deal_id=t.deal_id
      AND c.year IN (t.cohort-7,t.cohort-6)))",
  min(COHORTS), max(COHORTS)))
DBI::dbExecute(con, sprintf("
CREATE TEMP TABLE pp_control_early AS
WITH cohorts AS (SELECT UNNEST(range(%d,%d))::INTEGER cohort),
pairs AS (
  SELECT DISTINCT c.cohort,g.codinv,g.id_group
  FROM cohorts c JOIN p6.lmv2_inventor_group_patent_year g
    ON g.year IN (c.cohort-7,c.cohort-6)),
unique_group AS (
  SELECT cohort,codinv,MIN(id_group) id_group FROM pairs
  GROUP BY cohort,codinv HAVING COUNT(DISTINCT id_group)=1)
SELECT u.* FROM unique_group u
WHERE NOT EXISTS (
  SELECT 1 FROM pp_target_events te
  WHERE te.id_group=u.id_group AND te.event_year<=u.cohort+5)
AND NOT EXISTS (
  SELECT 1 FROM pp_acquirer_events ae
  WHERE ae.id_group=u.id_group
    AND ae.event_year BETWEEN u.cohort-5 AND u.cohort+5)",
  min(COHORTS), max(COHORTS) + 1L))
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_firm_roster AS
SELECT DISTINCT cohort,'treated' arm,deal_id,group_id FROM pp_treated
UNION ALL
SELECT DISTINCT cohort,'control' arm,NULL::BIGINT,id_group
FROM pp_control_early")
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_group_year_inventors AS
SELECT id_group,year,COUNT(DISTINCT codinv) inventor_count
FROM p6.lmv2_inventor_group_patent_year GROUP BY id_group,year")
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_firm_units AS
SELECT r.*,
 LN(1+COALESCE(p5.patent_count,0)) log_firm_patent_m5,
 LN(1+COALESCE(p4.patent_count,0)) log_firm_patent_m4,
 LN(1+COALESCE(i5.inventor_count,0)) log_firm_inventors_m5,
 LN(1+COALESCE(i4.inventor_count,0)) log_firm_inventors_m4
FROM pp_firm_roster r
LEFT JOIN lmv2_p3_group_year_patents p5
 ON p5.id_group=r.group_id AND p5.year=r.cohort-5
LEFT JOIN lmv2_p3_group_year_patents p4
 ON p4.id_group=r.group_id AND p4.year=r.cohort-4
LEFT JOIN pp_group_year_inventors i5
 ON i5.id_group=r.group_id AND i5.year=r.cohort-5
LEFT JOIN pp_group_year_inventors i4
 ON i4.id_group=r.group_id AND i4.year=r.cohort-4")
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_firm_ipc AS
WITH weighted AS (
 SELECT r.cohort,r.arm,r.deal_id,r.group_id,m.ipc_feature,
        SUM(g.patent_count)::DOUBLE weight
 FROM pp_firm_roster r JOIN group_ipc_year g
  ON CAST(g.id_group AS BIGINT)=r.group_id
 AND g.year BETWEEN r.cohort-7 AND r.cohort-4
 JOIN lmv2_p3_ipc_code_map m
  ON m.ipc_code=g.ipc_code AND m.resolution='ipc4'
 GROUP BY r.cohort,r.arm,r.deal_id,r.group_id,m.ipc_feature)
SELECT *,weight/SUM(weight) OVER
 (PARTITION BY cohort,arm,deal_id,group_id) frequency FROM weighted")
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_firm_cosine AS
WITH numer AS (
 SELECT t.cohort,t.deal_id,t.group_id treated_group,
        c.group_id control_group,SUM(t.frequency*c.frequency) numerator
 FROM pp_firm_ipc t JOIN pp_firm_ipc c
  ON c.cohort=t.cohort AND c.arm='control'
 AND c.ipc_feature=t.ipc_feature
 WHERE t.arm='treated'
 GROUP BY t.cohort,t.deal_id,t.group_id,c.group_id),
norms AS (
 SELECT cohort,arm,deal_id,group_id,SQRT(SUM(frequency*frequency)) norm
 FROM pp_firm_ipc GROUP BY cohort,arm,deal_id,group_id)
SELECT n.*,n.numerator/NULLIF(nt.norm*nc.norm,0) cosine
FROM numer n
JOIN norms nt ON nt.cohort=n.cohort AND nt.arm='treated'
 AND nt.deal_id=n.deal_id AND nt.group_id=n.treated_group
JOIN norms nc ON nc.cohort=n.cohort AND nc.arm='control'
 AND nc.group_id=n.control_group")

firm_units <- data.table::as.data.table(DBI::dbGetQuery(
  con, "SELECT * FROM pp_firm_units"))
firm_units <- standardize_by_cohort(firm_units, c(
  "log_firm_patent_m5", "log_firm_patent_m4",
  "log_firm_inventors_m5", "log_firm_inventors_m4"))
firm_cosine <- data.table::as.data.table(DBI::dbGetQuery(
  con, "SELECT * FROM pp_firm_cosine WHERE cosine>0"))
ft <- firm_units[arm == "treated", .(
  cohort, deal_id, treated_group = group_id,
  t_p5 = z_log_firm_patent_m5, t_p4 = z_log_firm_patent_m4,
  t_i5 = z_log_firm_inventors_m5, t_i4 = z_log_firm_inventors_m4)]
fc <- firm_units[arm == "control", .(
  cohort, control_group = group_id,
  c_p5 = z_log_firm_patent_m5, c_p4 = z_log_firm_patent_m4,
  c_i5 = z_log_firm_inventors_m5, c_i4 = z_log_firm_inventors_m4)]
edges <- merge(firm_cosine, ft,
               by = c("cohort", "deal_id", "treated_group"))
edges <- merge(edges, fc, by = c("cohort", "control_group"))
edges[, distance := sqrt(
  (t_p5-c_p5)^2 + (t_p4-c_p4)^2 + (t_i5-c_i5)^2 +
  (t_i4-c_i4)^2 + (1-cosine)^2)]
selected <- edges[
  order(cohort, deal_id, distance, control_group),
  head(.SD, FIRM_K), by = .(cohort, deal_id)]
eligible_deals <- selected[, .N, by = .(cohort, deal_id)][
  N >= MIN_DONORS, .(cohort, deal_id)]
selected <- merge(selected, eligible_deals,
                  by = c("cohort", "deal_id"), sort = FALSE)
if (!nrow(selected)) stop("No deal has the minimum donor count")
DBI::dbWriteTable(
  con, "pp_selected_firms",
  as.data.frame(selected[, .(cohort, deal_id,
                              donor_group = control_group)]),
  temporary = TRUE, overwrite = TRUE)

message("PPSCM: query training and untouched validation outcomes only")
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_treated_kept AS
SELECT t.* FROM pp_treated t
JOIN (SELECT DISTINCT cohort,deal_id FROM pp_selected_firms) d
USING(cohort,deal_id)")
DBI::dbExecute(con, "
CREATE TEMP TABLE pp_donor_roster AS
SELECT DISTINCT s.cohort,s.deal_id,s.donor_group,c.codinv
FROM pp_selected_firms s JOIN pp_control_early c
 ON c.cohort=s.cohort AND c.id_group=s.donor_group")

pre_panel <- data.table::as.data.table(DBI::dbGetQuery(con, "
WITH times AS (SELECT UNNEST(range(-7,0))::INTEGER event_time),
treat AS (
 SELECT r.cohort,r.deal_id,t.event_time,
        AVG(COALESCE(y.patent_count,0))::DOUBLE treated_outcome,
        COUNT(DISTINCT r.codinv)::INTEGER n_treated
 FROM pp_treated_kept r CROSS JOIN times t
 LEFT JOIN p6.lmv2_outcome_inventor_year y
  ON y.codinv=r.codinv AND y.year=r.cohort+t.event_time
 GROUP BY r.cohort,r.deal_id,t.event_time),
donor AS (
 SELECT r.cohort,r.deal_id,r.donor_group,t.event_time,
        AVG(COALESCE(y.patent_count,0))::DOUBLE donor_outcome,
        COUNT(DISTINCT r.codinv)::INTEGER n_donor_inventors
 FROM pp_donor_roster r CROSS JOIN times t
 LEFT JOIN p6.lmv2_outcome_inventor_year y
  ON y.codinv=r.codinv AND y.year=r.cohort+t.event_time
 GROUP BY r.cohort,r.deal_id,r.donor_group,t.event_time)
SELECT d.*,t.treated_outcome,t.n_treated
FROM donor d JOIN treat t USING(cohort,deal_id,event_time)
ORDER BY d.deal_id,d.donor_group,d.event_time"))

train_means <- pre_panel[event_time %in% TRAIN_TIMES, .(
  treated_train_mean = mean(treated_outcome),
  donor_train_mean = mean(donor_outcome)),
  by = .(deal_id, donor_group)]
pre_panel <- merge(pre_panel, train_means,
                   by = c("deal_id", "donor_group"))
pre_panel[, `:=`(
  treated_demeaned = treated_outcome - treated_train_mean,
  donor_demeaned = donor_outcome - donor_train_mean)]

deal_info <- unique(pre_panel[, .(deal_id, cohort, n_treated)])
early_total <- DBI::dbGetQuery(
  con, "SELECT COUNT(DISTINCT CAST(deal_id AS VARCHAR)||':'||
       CAST(codinv AS VARCHAR)) n FROM pp_treated")$n[[1]]
retained_total <- sum(deal_info$n_treated)
coverage <- retained_total / early_total

fit_one_aggregation <- function(label, deal_weight_vector) {
  deal_weight_vector <- deal_weight_vector / sum(deal_weight_vector)
  names(deal_weight_vector) <- as.character(deal_info$deal_id)
  dm <- design_matrices(pre_panel, deal_weight_vector, TRAIN_TIMES)
  separate_w <- fit_separate(dm, RIDGE)
  separate_fit <- imbalance(dm, separate_w)
  nu <- min(1, max(0, separate_fit$pool_rmse /
                     max(separate_fit$sep_rmse, 1e-10)))
  uniform_w <- unlist(lapply(dm$block_sizes, function(n) rep(1/n, n)))
  uniform_fit <- imbalance(dm, uniform_w)
  frontier <- vector("list", 3L)
  weights <- vector("list", 3L)
  nus <- unique(c(0, nu, 1))
  for (i in seq_along(nus)) {
    parts <- quadratic_parts(
      dm, nus[[i]], separate_fit$sep_mse, separate_fit$pool_mse, RIDGE)
    solution <- solve_simplex_qp(parts$h, parts$f, dm$block_sizes)
    fit <- imbalance(dm, solution$weight)
    frontier[[i]] <- data.frame(
      aggregation = label, nu = nus[[i]],
      sep_rmse = fit$sep_rmse, pool_rmse = fit$pool_rmse,
      solver_status = solution$status)
    weights[[i]] <- solution$weight
  }
  primary_index <- which.min(abs(nus - nu))
  primary_w <- weights[[primary_index]]
  wt <- data.table::copy(dm$donor_keys)
  wt[, scm_weight := primary_w[column]]
  wt[, aggregation := label]
  uniform_table <- data.table::copy(dm$donor_keys)
  uniform_table[, scm_weight := uniform_w[column]]
  validation <- evaluate_weights(
    pre_panel, wt, VALID_TIMES, deal_weight_vector)
  validation_uniform <- evaluate_weights(
    pre_panel, uniform_table, VALID_TIMES, deal_weight_vector)
  joint <- weighted_joint_test(
    validation$deal, VALID_TIMES, deal_weight_vector)
  ess_table <- wt[, .(
    donor_ess = 1/sum(scm_weight^2),
    max_weight = max(scm_weight)), by = deal_id]
  list(
    label = label, nu = nu, weights = wt,
    frontier = data.table::rbindlist(frontier),
    train = imbalance(dm, primary_w), uniform_train = uniform_fit,
    validation = validation, validation_uniform = validation_uniform,
    joint = joint, ess = ess_table, deal_weights = deal_weight_vector)
}

primary <- fit_one_aggregation("inventor_weighted", deal_info$n_treated)
secondary <- fit_one_aggregation("equal_deal", rep(1, nrow(deal_info)))
all_weights <- rbind(primary$weights, secondary$weights)
atomic_csv(all_weights, file.path(OUT_DIR, "synthetic_weights.csv"))
atomic_csv(rbind(primary$frontier, secondary$frontier),
           file.path(OUT_DIR, "training_fit_frontier.csv"))
atomic_csv(rbind(
  transform(primary$validation$pooled, aggregation = primary$label),
  transform(secondary$validation$pooled, aggregation = secondary$label)),
  file.path(OUT_DIR, "validation_pooled_gaps.csv"))
atomic_csv(rbind(
  transform(primary$validation$deal, aggregation = primary$label),
  transform(secondary$validation$deal, aggregation = secondary$label)),
  file.path(OUT_DIR, "validation_deal_gaps.csv"))
atomic_csv(rbind(
  transform(primary$ess, aggregation = primary$label),
  transform(secondary$ess, aggregation = secondary$label)),
  file.path(OUT_DIR, "weight_concentration.csv"))

p10_ess <- as.numeric(stats::quantile(
  primary$ess$donor_ess, 0.10, names = FALSE))
gate <- data.frame(
  gate = c(
    "minimum_deals", "minimum_treated_coverage",
    "beats_uniform_validation_rmse", "validation_rmse_within_band",
    "each_validation_gap_within_band", "joint_validation_p_above_0_10",
    "median_donor_ess", "p10_donor_ess", "maximum_donor_weight",
    "training_objective_beats_uniform"),
  pass = c(
    nrow(deal_info) >= MIN_DEALS,
    coverage >= MIN_COVERAGE,
    primary$validation$pooled_rmse <=
      primary$validation_uniform$pooled_rmse,
    primary$validation$pooled_rmse <= EQUIVALENCE_BAND,
    all(abs(primary$validation$pooled$gap) <= EQUIVALENCE_BAND),
    primary$joint$p_value > 0.10,
    stats::median(primary$ess$donor_ess) >= MIN_MEDIAN_ESS,
    p10_ess >= MIN_P10_ESS,
    max(primary$ess$max_weight) <= MAX_DONOR_WEIGHT,
    primary$train$sep_mse + primary$train$pool_mse <=
      primary$uniform_train$sep_mse + primary$uniform_train$pool_mse),
  value = c(
    nrow(deal_info), coverage,
    primary$validation$pooled_rmse,
    primary$validation$pooled_rmse,
    max(abs(primary$validation$pooled$gap)),
    primary$joint$p_value,
    stats::median(primary$ess$donor_ess),
    p10_ess, max(primary$ess$max_weight),
    primary$train$sep_mse + primary$train$pool_mse),
  threshold = c(
    paste0(">=", MIN_DEALS), paste0(">=", MIN_COVERAGE),
    paste0("<=", signif(primary$validation_uniform$pooled_rmse, 5)),
    paste0("<=", EQUIVALENCE_BAND), paste0("<=", EQUIVALENCE_BAND),
    ">0.10", paste0(">=", MIN_MEDIAN_ESS), paste0(">=", MIN_P10_ESS),
    paste0("<=", MAX_DONOR_WEIGHT),
    paste0("<=", signif(
      primary$uniform_train$sep_mse + primary$uniform_train$pool_mse, 5))))
atomic_csv(gate, file.path(OUT_DIR, "validation_gate.csv"))

summary <- data.frame(
  execution_hash = execution_hash,
  source_sha256 = source_hash, freeze_sha256 = freeze_hash,
  retained_deals = nrow(deal_info),
  retained_treated_inventors = retained_total,
  early_treated_inventors = early_total,
  treated_coverage = coverage,
  primary_nu = primary$nu,
  primary_training_separate_rmse = primary$train$sep_rmse,
  primary_training_pooled_rmse = primary$train$pool_rmse,
  primary_validation_rmse = primary$validation$pooled_rmse,
  uniform_validation_rmse = primary$validation_uniform$pooled_rmse,
  primary_joint_validation_p = primary$joint$p_value,
  all_validation_gates_pass = all(gate$pass),
  post_outcomes_queried = FALSE)
atomic_csv(summary, file.path(OUT_DIR, "validation_summary.csv"))

if (!all(gate$pass)) {
  message("PPSCM validation FAILED; post outcomes remain unopened")
  print(gate)
  quit(save = "no", status = 2L)
}
if (!ALLOW_POST) {
  message("PPSCM validation passed; rerun with --estimate to open post outcomes")
  quit(save = "no", status = 0L)
}

message("PPSCM validation passed: query gated post-treatment outcomes")
post_panel <- data.table::as.data.table(DBI::dbGetQuery(con, "
WITH times AS (SELECT UNNEST(range(0,6))::INTEGER event_time),
treat AS (
 SELECT r.cohort,r.deal_id,t.event_time,
        AVG(COALESCE(y.patent_count,0))::DOUBLE treated_outcome
 FROM pp_treated_kept r CROSS JOIN times t
 LEFT JOIN p6.lmv2_outcome_inventor_year y
  ON y.codinv=r.codinv AND y.year=r.cohort+t.event_time
 GROUP BY r.cohort,r.deal_id,t.event_time),
donor AS (
 SELECT r.cohort,r.deal_id,r.donor_group,t.event_time,
        AVG(COALESCE(y.patent_count,0))::DOUBLE donor_outcome
 FROM pp_donor_roster r CROSS JOIN times t
 LEFT JOIN p6.lmv2_outcome_inventor_year y
  ON y.codinv=r.codinv AND y.year=r.cohort+t.event_time
 GROUP BY r.cohort,r.deal_id,r.donor_group,t.event_time)
SELECT d.*,t.treated_outcome FROM donor d JOIN treat t
USING(cohort,deal_id,event_time)
ORDER BY d.deal_id,d.donor_group,d.event_time"))
post_panel <- merge(post_panel, train_means,
                    by = c("deal_id", "donor_group"))
post_panel[, `:=`(
  treated_demeaned = treated_outcome - treated_train_mean,
  donor_demeaned = donor_outcome - donor_train_mean)]
post_primary <- evaluate_weights(
  post_panel, primary$weights, POST_TIMES, primary$deal_weights)
post_secondary <- evaluate_weights(
  post_panel, secondary$weights, POST_TIMES, secondary$deal_weights)
atomic_csv(rbind(
  transform(post_primary$pooled, aggregation = primary$label),
  transform(post_secondary$pooled, aggregation = secondary$label)),
  file.path(OUT_DIR, "post_event_study.csv"))
post_att <- rbind(
  post_primary$deal[event_time %in% PRIMARY_POST_TIMES, .(
    estimate = sum(primary$deal_weights[as.character(deal_id)] * gap) /
      length(PRIMARY_POST_TIMES))],
  post_secondary$deal[event_time %in% PRIMARY_POST_TIMES, .(
    estimate = sum(secondary$deal_weights[as.character(deal_id)] * gap) /
      length(PRIMARY_POST_TIMES))])
post_att[, aggregation := c(primary$label, secondary$label)]
atomic_csv(post_att, file.path(OUT_DIR, "post_att.csv"))
summary$post_outcomes_queried <- TRUE
summary$post_att_inventor_weighted <-
  post_att[aggregation == "inventor_weighted", estimate]
summary$post_att_equal_deal <-
  post_att[aggregation == "equal_deal", estimate]
atomic_csv(summary, file.path(OUT_DIR, "results_summary.csv"))
message("PPSCM completed | primary ATT=", sprintf(
  "%.4f", summary$post_att_inventor_weighted))
