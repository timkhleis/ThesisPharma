# Reconcile Cassi--Ornaghi Table 9 with the thesis retained-inventor estimate.
#
# The script ports the published kmatch design to R/DuckDB, saves match IDs,
# then changes the outcome clock, cohort, treated population, patent-count
# source, and estimator. It also reports a four-factor Shapley decomposition
# at fixed 1994--2010 cohort coverage.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()

required <- c("DBI", "duckdb")
for (pkg in required) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}

ROOT <- normalizePath(file.path(BASE, ".."), winslash = "/", mustWork = TRUE)
FOUNDATION <- normalizePath(
  file.path(ROOT, "02_analysis"),
  winslash = "/", mustWork = TRUE)
OUT <- file.path(BASE, "output", "results", "cassi_ornaghi_bridge")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

paths <- list(
  status = file.path(
    BASE, "output", "parquet", "reference",
    "inventor_status_reference.parquet"),
  inventor_production = file.path(
    BASE, "output", "parquet", "helper", "inventor_production.parquet"),
  group_production = file.path(
    BASE, "output", "parquet", "helper", "group_production.parquet"),
  deal_assignment = file.path(
    FOUNDATION, "output", "parquet", "helper", "deal_assignment.parquet"),
  treated_primary = file.path(
    FOUNDATION, "output", "parquet", "derived",
    "lmv2_treated_primary.parquet"),
  inventor_year = file.path(
    FOUNDATION, "output", "parquet", "derived", "inventor_year.parquet"),
  stayer_weights = file.path(
    BASE, "output", "audit", "local_match_v2", "P5B_STAYER_S3",
    "s3_production_weights.parquet"),
  thesis_inventory = file.path(
    BASE, "output", "results", "local_match_v2", "C2_CURRENT_RELEASE",
    "CURRENT_LOCAL_MATCH_V2_STAGING", "04_Results", "results_inventory",
    "master_results_inventory.csv")
)
missing <- names(paths)[!file.exists(unlist(paths))]
if (length(missing)) {
  stop("Missing inputs: ", paste(missing, collapse = ", "))
}
sql_path <- function(x) {
  gsub("'", "''", normalizePath(x, winslash = "/", mustWork = TRUE))
}
p <- lapply(paths, sql_path)

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=8")
DBI::dbExecute(con, "SET memory_limit='6GB'")
DBI::dbExecute(con, sprintf(
  "SET temp_directory='%s'",
  gsub("'", "''", file.path(BASE, "output", "duckdb_tmp_cassi_bridge"))))

# Port the published sample construction. The row ID reproduces Stata's
# idcnt, which is generated after sorting the eligible sample by inventor-year.
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE eligible0 AS
  WITH status_raw AS (
    SELECT *,
      COUNT(*) OVER (PARTITION BY codinv) AS n_status,
      COUNT(*) FILTER (WHERE type = 'N_LEAVER')
        OVER (PARTITION BY codinv) AS n_nleave,
      COUNT(DISTINCT COALESCE(CAST(id_group AS VARCHAR), 'MISSING'))
        OVER (PARTITION BY codinv) AS n_groups
    FROM read_parquet('%s')
  ), prod AS (
    SELECT *,
      SUM(patent) OVER (
        PARTITION BY codinv ORDER BY year
        RANGE BETWEEN 4 PRECEDING AND CURRENT ROW
      ) AS cm5patent,
      SUM(patent) OVER (
        PARTITION BY codinv ORDER BY year
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS cmpatent
    FROM read_parquet('%s')
  ), joined AS (
    SELECT
      CAST(s.codinv AS BIGINT) AS codinv,
      CAST(s.year AS INTEGER) AS status_year,
      CAST(s.id_group AS BIGINT) AS id_group,
      s.type,
      CAST(s.target_year AS INTEGER) AS target_year,
      s.target_value,
      CAST(prod.firstpatent AS INTEGER) AS firstpatent,
      CAST(prod.cmpatent AS DOUBLE) AS cmpatent,
      CAST(prod.cm5patent AS DOUBLE) AS cm5patent,
      CAST(gp.patent AS DOUBLE) AS grpatent
    FROM status_raw s
    JOIN prod
      ON s.codinv = prod.codinv AND CAST(s.year AS INTEGER) = prod.year
    JOIN read_parquet('%s') gp
      ON s.id_group = gp.id_group AND CAST(s.year AS INTEGER) = gp.year
    WHERE s.n_status > 1
      AND s.n_nleave * 1.0 / s.n_groups <= 1
      AND s.type <> 'last year'
  ), marked AS (
    SELECT *,
      MAX(type = 'T_STAYER') OVER (PARTITION BY codinv) AS any_tstayer
    FROM joined
  ), pruned AS (
    SELECT *,
      CASE
        WHEN type = 'T_STAYER' THEN 1
        WHEN BOOL_AND(type IN ('N_STAYER', 'A_STAYER'))
          OVER (PARTITION BY codinv) THEN 0
      END AS treated
    FROM marked
    WHERE NOT (any_tstayer AND type <> 'T_STAYER')
  ), deal_bridge AS (
    SELECT DISTINCT
      CAST(deal_id AS BIGINT) AS deal_id,
      CAST(target_year AS INTEGER) AS target_year,
      target_value
    FROM read_parquet('%s')
  )
  SELECT p.*,
    p.status_year - p.firstpatent + 1 AS experience,
    d.deal_id
  FROM pruned p
  LEFT JOIN deal_bridge d
    ON p.target_year = d.target_year
   AND p.target_value = d.target_value
  WHERE p.treated IS NOT NULL
", p$status, p$inventor_production, p$group_production,
   p$deal_assignment))

DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE eligible1 AS
  SELECT e.*,
    CASE WHEN tp.codinv IS NOT NULL THEN TRUE ELSE FALSE END
      AS thesis_initially_retained,
    CASE WHEN sw.codinv IS NOT NULL THEN TRUE ELSE FALSE END
      AS thesis_selected_sample,
    ROW_NUMBER() OVER (ORDER BY e.codinv, e.status_year) AS row_id
  FROM eligible0 e
  LEFT JOIN (
    SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv,
           CAST(deal_id AS BIGINT) AS deal_id
    FROM read_parquet('%s')
    WHERE status_eligible_stayer_first_post_t0_t5
  ) tp
    ON e.treated = 1
   AND e.codinv = tp.codinv
   AND e.deal_id = tp.deal_id
  LEFT JOIN (
    SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv,
           CAST(deal_id AS BIGINT) AS deal_id
    FROM read_parquet('%s')
    WHERE treated = 1
      AND spec = 'primary_count_active_scale'
      AND support_variant = 'primary_resolved_t1'
  ) sw
    ON e.treated = 1
   AND e.codinv = sw.codinv
   AND e.deal_id = sw.deal_id
", p$treated_primary, p$stayer_weights))

DBI::dbExecute(con, "
  CREATE TEMP TABLE eligible AS
  SELECT *,
    CASE WHEN treated = 1 THEN
      SUM(treated) OVER (ORDER BY row_id)
    END::INTEGER AS t_index,
    CASE WHEN treated = 0 THEN
      SUM(1 - treated) OVER (ORDER BY row_id)
    END::INTEGER AS c_index
  FROM eligible1
")

source_counts <- DBI::dbGetQuery(con, "
  SELECT
    COUNT(*) FILTER (treated = 1)::INTEGER AS treated_rows,
    COUNT(*) FILTER (treated = 0)::INTEGER AS control_rows,
    COUNT(*) FILTER (
      treated = 1 AND target_year BETWEEN 1994 AND 2010
    )::INTEGER AS treated_1994_2010,
    COUNT(*) FILTER (
      treated = 1 AND target_year BETWEEN 1994 AND 2010
      AND thesis_initially_retained
    )::INTEGER AS raw_retained_1994_2010,
    COUNT(*) FILTER (
      treated = 1 AND target_year BETWEEN 1994 AND 2010
      AND thesis_selected_sample
    )::INTEGER AS common_selected_1994_2010
  FROM eligible
")
if (source_counts$treated_rows != 7104L) {
  stop("Published T_STAYER source count does not reproduce 7,104.")
}

cassi_greedy_chunk <- function(
    ti, ci, treated_count, control_used, match1, match2) {
  accepted <- 0L
  for (i in seq_along(ti)) {
    t <- ti[[i]]
    c <- ci[[i]]
    if (treated_count[[t]] >= 2L || control_used[[c]]) next
    if (treated_count[[t]] == 0L) match1[[t]] <- c
    else match2[[t]] <- c
    treated_count[[t]] <- treated_count[[t]] + 1L
    control_used[[c]] <- TRUE
    accepted <- accepted + 1L
  }
  list(
    accepted = accepted,
    treated_count = treated_count,
    control_used = control_used,
    match1 = match1,
    match2 = match2)
}

run_match <- function(spec_id, treated_where) {
  message("Matching ", spec_id)
  DBI::dbExecute(con, "DROP TABLE IF EXISTS match_treated")
  DBI::dbExecute(con, paste0("
    CREATE TEMP TABLE match_treated AS
    SELECT * FROM eligible
    WHERE treated = 1 AND (", treated_where, ")
  "))

  dims <- DBI::dbGetQuery(con, "
    SELECT
      (SELECT COUNT(*) FROM match_treated)::INTEGER AS nt,
      (SELECT MAX(t_index) FROM eligible WHERE treated = 1)::INTEGER AS nt_all,
      (SELECT MAX(c_index) FROM eligible WHERE treated = 0)::INTEGER AS nc
  ")
  if (dims$nt == 0L) stop("No treated rows for ", spec_id)
  cache_path <- file.path(OUT, paste0("matches_", spec_id, ".csv"))
  if (identical(Sys.getenv("CASSI_BRIDGE_REUSE_MATCHES"), "1") &&
      file.exists(cache_path)) {
    message("  reusing certified match-ID cache")
    candidate_count <- DBI::dbGetQuery(con, "
      SELECT COUNT(*)::BIGINT AS n
      FROM match_treated t
      JOIN eligible c
        ON c.treated = 0
       AND c.firstpatent = t.firstpatent
       AND c.experience = t.experience
       AND c.cm5patent = t.cm5patent
    ")$n
    return(list(
      spec_id = spec_id,
      matches = utils::read.csv(cache_path),
      candidate_edges = candidate_count,
      accepted_edges = NA_integer_,
      requested_treated = dims$nt,
      covariance = matrix(NA_real_, 2, 2)))
  }

  covariance <- DBI::dbGetQuery(con, "
    WITH sample AS (
      SELECT cmpatent, grpatent FROM eligible WHERE treated = 0
      UNION ALL
      SELECT cmpatent, grpatent FROM match_treated
    )
    SELECT
      COVAR_SAMP(cmpatent, cmpatent) AS v11,
      COVAR_SAMP(cmpatent, grpatent) AS v12,
      COVAR_SAMP(grpatent, grpatent) AS v22
    FROM sample
  ")
  V <- matrix(
    c(covariance$v11, covariance$v12,
      covariance$v12, covariance$v22),
    nrow = 2, byrow = TRUE)
  Vinv <- solve(V)

  distance_sql <- sprintf(
    "(%.17g * POWER(c.cmpatent - t.cmpatent, 2) +
       %.17g * (c.cmpatent - t.cmpatent) *
                (c.grpatent - t.grpatent) +
       %.17g * POWER(c.grpatent - t.grpatent, 2))",
    Vinv[1, 1], 2 * Vinv[1, 2], Vinv[2, 2])

  candidate_count <- DBI::dbGetQuery(con, "
    SELECT COUNT(*)::BIGINT AS n
    FROM match_treated t
    JOIN eligible c
      ON c.treated = 0
     AND c.firstpatent = t.firstpatent
     AND c.experience = t.experience
     AND c.cm5patent = t.cm5patent
  ")$n

  query <- paste0("
    SELECT
      t.t_index::INTEGER AS ti,
      c.c_index::INTEGER AS ci
    FROM match_treated t
    JOIN eligible c
      ON c.treated = 0
     AND c.firstpatent = t.firstpatent
     AND c.experience = t.experience
     AND c.cm5patent = t.cm5patent
    ORDER BY ", distance_sql, ",
      HASH(t.row_id, c.row_id, 10101010::BIGINT),
      t.row_id, c.row_id
  ")

  treated_count <- integer(dims$nt_all)
  control_used <- rep(FALSE, dims$nc)
  match1 <- integer(dims$nt_all)
  match2 <- integer(dims$nt_all)
  accepted <- 0L
  processed <- 0
  result <- DBI::dbSendQuery(con, query)
  repeat {
    chunk <- DBI::dbFetch(result, n = 250000)
    if (!nrow(chunk)) break
    update <- cassi_greedy_chunk(
      chunk$ti, chunk$ci, treated_count, control_used, match1, match2)
    accepted <- accepted + update$accepted
    treated_count <- update$treated_count
    control_used <- update$control_used
    match1 <- update$match1
    match2 <- update$match2
    processed <- processed + nrow(chunk)
    if (processed %% 5000000 < 250000) {
      message("  processed ", format(processed, big.mark = ","),
              " candidate edges")
    }
  }
  DBI::dbClearResult(result)

  tmap <- DBI::dbGetQuery(con, "
    SELECT t_index, row_id FROM match_treated ORDER BY t_index
  ")
  cmap <- DBI::dbGetQuery(con, "
    SELECT c_index, row_id FROM eligible
    WHERE treated = 0 ORDER BY c_index
  ")
  keep <- tmap$t_index[
    match1[tmap$t_index] > 0L & match2[tmap$t_index] > 0L]
  matches <- data.frame(
    match_id = seq_along(keep),
    treated_row_id = tmap$row_id[match(keep, tmap$t_index)],
    control1_row_id = cmap$row_id[
      match(match1[keep], cmap$c_index)],
    control2_row_id = cmap$row_id[
      match(match2[keep], cmap$c_index)],
    stringsAsFactors = FALSE)

  list(
    spec_id = spec_id,
    matches = matches,
    candidate_edges = candidate_count,
    accepted_edges = accepted,
    requested_treated = dims$nt,
    covariance = V)
}

paper_match <- run_match("paper_all_years", "TRUE")
cohort_match <- run_match(
  "cohort_1994_2010", "target_year BETWEEN 1994 AND 2010")
common_match <- run_match(
  "common_selected_1994_2010",
  "target_year BETWEEN 1994 AND 2010 AND thesis_selected_sample")

build_pair_outcomes <- function(match_result) {
  match_df <- match_result$matches
  DBI::dbExecute(con, "DROP TABLE IF EXISTS current_matches")
  DBI::dbWriteTable(
    con, "current_matches", match_df, temporary = TRUE, overwrite = TRUE)
  query <- sprintf("
    WITH long_matches AS (
      SELECT match_id, 'treated' AS role, treated_row_id AS row_id
      FROM current_matches
      UNION ALL
      SELECT match_id, 'control' AS role, control1_row_id AS row_id
      FROM current_matches
      UNION ALL
      SELECT match_id, 'control' AS role, control2_row_id AS row_id
      FROM current_matches
    ), pair_year AS (
      SELECT m.match_id,
             MAX(e.target_year) FILTER (m.role = 'treated') AS pair_target_year
      FROM long_matches m JOIN eligible e USING(row_id)
      GROUP BY m.match_id
    ), units AS (
      SELECT
        m.match_id, m.role, e.row_id, e.codinv, e.status_year,
        py.pair_target_year AS target_year,
        e.cm5patent AS helper_status_pre5
      FROM long_matches m
      JOIN eligible e USING(row_id)
      JOIN pair_year py USING(match_id)
    ), helper AS (
      SELECT
        u.*,
        COALESCE(SUM(ip.patent) FILTER (
          ip.year > u.status_year AND ip.year <= u.status_year + 5
        ), 0) AS helper_status_post5,
        COALESCE(MAX(ip.patent) FILTER (
          ip.year = u.status_year - 1
        ), 0) AS helper_status_baseline,
        COALESCE(SUM(ip.patent) FILTER (
          ip.year > u.target_year AND ip.year <= u.target_year + 5
        ), 0) AS helper_deal_post5,
        COALESCE(MAX(ip.patent) FILTER (
          ip.year = u.target_year - 1
        ), 0) AS helper_deal_baseline,
        COALESCE(SUM(ip.patent) FILTER (
          ip.year BETWEEN u.target_year - 5 AND u.target_year - 1
        ), 0) AS helper_deal_pre5
      FROM units u
      LEFT JOIN read_parquet('%s') ip
        ON u.codinv = ip.codinv
       AND ip.year BETWEEN LEAST(u.status_year - 1, u.target_year - 5)
                       AND GREATEST(u.status_year + 5, u.target_year + 5)
      GROUP BY ALL
    ), canonical AS (
      SELECT
        h.*,
        COALESCE(SUM(iy.patent_count) FILTER (
          iy.year > h.status_year AND iy.year <= h.status_year + 5
        ), 0) AS canonical_status_post5,
        COALESCE(MAX(iy.patent_count) FILTER (
          iy.year = h.status_year - 1
        ), 0) AS canonical_status_baseline,
        COALESCE(SUM(iy.patent_count) FILTER (
          iy.year > h.target_year AND iy.year <= h.target_year + 5
        ), 0) AS canonical_deal_post5,
        COALESCE(MAX(iy.patent_count) FILTER (
          iy.year = h.target_year - 1
        ), 0) AS canonical_deal_baseline,
        COALESCE(SUM(iy.patent_count) FILTER (
          iy.year BETWEEN h.target_year - 5 AND h.target_year - 1
        ), 0) AS canonical_deal_pre5
      FROM helper h
      LEFT JOIN read_parquet('%s') iy
        ON h.codinv = CAST(iy.codinv AS BIGINT)
       AND iy.year BETWEEN LEAST(h.status_year - 1, h.target_year - 5)
                       AND GREATEST(h.status_year + 5, h.target_year + 5)
      GROUP BY ALL
    )
    SELECT * FROM canonical
    ORDER BY match_id, role DESC, row_id
  ", p$inventor_production, p$inventor_year)
  units <- DBI::dbGetQuery(con, query)

  outcome_names <- c(
    "helper_status_post5", "helper_status_baseline",
    "helper_status_pre5", "helper_deal_post5",
    "helper_deal_baseline", "helper_deal_pre5",
    "canonical_status_post5", "canonical_status_baseline",
    "canonical_deal_post5", "canonical_deal_baseline",
    "canonical_deal_pre5")
  DBI::dbExecute(con, "DROP TABLE IF EXISTS current_units")
  DBI::dbWriteTable(
    con, "current_units", units, temporary = TRUE, overwrite = TRUE)
  expressions <- unlist(lapply(outcome_names, function(v) c(
    sprintf(
      "MAX(%s) FILTER (role='treated') AS treated_%s", v, v),
    sprintf(
      "AVG(%s) FILTER (role='control') AS control_%s", v, v),
    sprintf(
      "MAX(%s) FILTER (role='treated') -
       AVG(%s) FILTER (role='control') AS diff_%s", v, v, v))))
  pair <- DBI::dbGetQuery(con, paste0(
    "SELECT match_id, MAX(target_year) AS target_year, ",
    paste(expressions, collapse = ", "),
    " FROM current_units GROUP BY match_id ORDER BY match_id"))

  utils::write.csv(
    match_df, file.path(OUT, paste0("matches_", match_result$spec_id, ".csv")),
    row.names = FALSE)
  utils::write.csv(
    pair,
    file.path(OUT, paste0("pair_outcomes_", match_result$spec_id, ".csv")),
    row.names = FALSE)
  pair
}

paper_pair <- build_pair_outcomes(paper_match)
cohort_pair <- build_pair_outcomes(cohort_match)
common_pair <- build_pair_outcomes(common_match)

summarize_design <- function(
    pair, step, design, source, clock, estimator, note) {
  post <- pair[[paste0("diff_", source, "_", clock, "_post5")]]
  baseline <- pair[[paste0("diff_", source, "_", clock, "_baseline")]]
  treated_post <- pair[[paste0("treated_", source, "_", clock, "_post5")]]
  control_post <- pair[[paste0("control_", source, "_", clock, "_post5")]]
  effect <- if (estimator == "post-level") post else post - 5 * baseline
  data.frame(
    step = step,
    design = design,
    outcome_source = source,
    outcome_clock = clock,
    estimator = estimator,
    matched_treated = nrow(pair),
    treated_post5 = mean(treated_post),
    control_post5 = mean(control_post),
    effect_5y = mean(effect),
    loss_pct_counterfactual = -100 * mean(effect) / mean(control_post),
    note = note,
    stringsAsFactors = FALSE)
}

published <- data.frame(
  step = 0,
  design = "Published Table 9",
  outcome_source = "helper",
  outcome_clock = "status",
  estimator = "post-level",
  matched_treated = 6946L,
  treated_post5 = 3.23,
  control_post5 = 4.20,
  effect_5y = -0.97,
  loss_pct_counterfactual = 100 * 0.97 / 4.20,
  note = "Reported values",
  stringsAsFactors = FALSE)

bridge <- rbind(
  published,
  summarize_design(
    paper_pair, 1, "R port of published design", "helper", "status",
    "post-level", "Greedy 2-NN without replacement; deterministic tie draw"),
  summarize_design(
    paper_pair, 2, "Same published matches", "helper", "deal",
    "post-level", "Only the outcome clock changes"),
  summarize_design(
    cohort_pair, 3, "1994--2010, rematched", "helper", "deal",
    "post-level", "Thesis cohort coverage"),
  summarize_design(
    common_pair, 4, "Common treated population, rematched", "helper", "deal",
    "post-level",
    "Paper T_STAYER intersected with the frozen thesis selected-stayer sample"),
  summarize_design(
    common_pair, 5, "Common treated population, rematched", "canonical", "deal",
    "post-level", "Canonical distinct inventor-application counts"),
  summarize_design(
    common_pair, 6, "Common treated population, rematched", "canonical", "deal",
    "baseline-adjusted",
    "Subtracts five times the treated-control gap at event time -1"))

inventory <- utils::read.csv(paths$thesis_inventory, check.names = FALSE)
thesis_row <- inventory[
  inventory$population == "initially retained inventors" &
    inventory$outcome == "patent_count" &
    inventory$analysis ==
      "separately balanced selected-group ATT" &
    inventory$sample == "full_1994_2010", ]
if (nrow(thesis_row) != 1L) {
  stop("Could not identify the unique thesis retained-inventor endpoint.")
}
thesis <- data.frame(
  step = 7,
  design = "Thesis selected-group design",
  outcome_source = "canonical",
  outcome_clock = "deal",
  estimator = "weighted event-study DiD",
  matched_treated = NA_integer_,
  treated_post5 = 4.081,
  control_post5 = 4.617,
  effect_5y = thesis_row$five_year_effect,
  loss_pct_counterfactual =
    -100 * thesis_row$five_year_effect / 4.617,
  note = "Local support plus separate entropy balance; frozen endpoint",
  stringsAsFactors = FALSE)
bridge <- rbind(bridge, thesis)
utils::write.csv(
  bridge, file.path(OUT, "bridge_estimates.csv"), row.names = FALSE)

matching_diagnostics <- do.call(rbind, lapply(
  list(paper_match, cohort_match, common_match),
  function(x) data.frame(
    specification = x$spec_id,
    requested_treated = x$requested_treated,
    matched_treated = nrow(x$matches),
    matched_controls = 2L * nrow(x$matches),
    candidate_edges = x$candidate_edges,
    match_rate = nrow(x$matches) / x$requested_treated,
    stringsAsFactors = FALSE)))
utils::write.csv(
  matching_diagnostics,
  file.path(OUT, "matching_diagnostics.csv"), row.names = FALSE)

# Exact Shapley decomposition for clock, treated population, count source,
# and baseline adjustment, conditional on the thesis's 1994--2010 cohorts.
dimensions <- c("clock", "population", "outcome", "estimator")
states <- expand.grid(
  clock = 0:1, population = 0:1, outcome = 0:1, estimator = 0:1)
value_for_state <- function(row) {
  pair <- if (row[["population"]] == 0) cohort_pair else common_pair
  source <- if (row[["outcome"]] == 0) "helper" else "canonical"
  clock <- if (row[["clock"]] == 0) "status" else "deal"
  post <- pair[[paste0("diff_", source, "_", clock, "_post5")]]
  if (row[["estimator"]] == 0) return(mean(post))
  baseline <- pair[[paste0("diff_", source, "_", clock, "_baseline")]]
  mean(post - 5 * baseline)
}
states$value <- apply(states, 1, value_for_state)
state_key <- function(x) paste(x, collapse = "")
keys <- apply(states[, dimensions], 1, state_key)
state_values <- stats::setNames(states$value, keys)
n_dim <- length(dimensions)
shapley <- vapply(seq_along(dimensions), function(j) {
  others <- setdiff(seq_len(n_dim), j)
  total <- 0
  for (mask in 0:(2^length(others) - 1)) {
    s0 <- integer(n_dim)
    if (length(others)) {
      bits <- as.integer(intToBits(mask))[seq_along(others)]
      s0[others] <- bits
    }
    s1 <- s0
    s1[j] <- 1L
    k <- sum(s0)
    weight <- factorial(k) * factorial(n_dim - k - 1) / factorial(n_dim)
    total <- total + weight * (
      state_values[[state_key(s1)]] - state_values[[state_key(s0)]])
  }
  total
}, numeric(1))
shapley_table <- data.frame(
  component = c(
    "Cohort restriction to 1994--2010",
    "Outcome clock: status year to acquisition year",
    "Treated population: paper T_STAYER to common selected analysis sample",
    "Patent count: helper field to canonical distinct applications",
    "Estimator: post level to event-time -1 baseline adjustment",
    "Remaining gap to thesis local-support weighted event-study",
    "Total published-port to thesis difference"),
  contribution = c(
    mean(cohort_pair$diff_helper_status_post5) -
      mean(paper_pair$diff_helper_status_post5),
    shapley[[1]], shapley[[2]], shapley[[3]], shapley[[4]],
    thesis$effect_5y - state_values[["1111"]],
    thesis$effect_5y -
      mean(paper_pair$diff_helper_status_post5)),
  stringsAsFactors = FALSE)
utils::write.csv(
  shapley_table, file.path(OUT, "bridge_shapley_decomposition.csv"),
  row.names = FALSE)
utils::write.csv(
  states, file.path(OUT, "bridge_shapley_states.csv"), row.names = FALSE)

validation <- data.frame(
  check = c(
    "source_T_STAYER_count_is_7104",
    "common_selected_source_count_is_2326",
    "ported_match_count_is_6946",
    "common_selected_match_count_is_2302",
    "ported_effect_within_0.03_of_published",
    "all_matches_use_two_distinct_controls",
    "bridge_endpoint_equals_frozen_thesis_value",
    "shapley_adds_to_port_to_thesis_gap"),
  pass = c(
    source_counts$treated_rows == 7104L,
    source_counts$common_selected_1994_2010 == 2326L,
    nrow(paper_pair) == 6946L,
    nrow(common_pair) == 2302L,
    abs(mean(paper_pair$diff_helper_status_post5) - (-0.97)) <= 0.03,
    all(vapply(
      list(paper_match, cohort_match, common_match),
      function(x) all(
        x$matches$control1_row_id != x$matches$control2_row_id),
      logical(1))),
    abs(thesis$effect_5y - (-0.53615306935933)) < 1e-10,
    abs(sum(shapley_table$contribution[1:6]) -
          shapley_table$contribution[7]) < 1e-10),
  stringsAsFactors = FALSE)
utils::write.csv(
  validation, file.path(OUT, "bridge_validation.csv"), row.names = FALSE)
if (!all(validation$pass)) {
  stop(
    "Bridge validation failed: ",
    paste(validation$check[!validation$pass], collapse = ", "))
}

message("Cassi--Ornaghi bridge built and certified: ", OUT)
