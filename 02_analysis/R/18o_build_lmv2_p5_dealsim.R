# ============================================================================
# P5 outcome-blind DealSim construction and tercile freeze
# ============================================================================

args <- commandArgs(trailingOnly = TRUE)
read_dealsim_arg <- function(name, required = TRUE, default = NA_character_) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(default)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "17o_run_lmv2_p4_cohort_hybrid_pilot.R"))
source(file.path(BASE, "R", "18m_lmv2_p5_final_config.R"))

LMV2_P5_DEALSIM_VERSION <- "lmv2_p5_dealsim_v1"

lmv2_p5_write_atomic_csv <- function(data, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  utils::write.csv(data, tmp, row.names = FALSE, na = "")
  checksum <- lmv2_p3_file_hash(tmp)
  if (file.exists(path)) {
    stop("Refusing to replace existing DealSim artifact: ", path)
  }
  if (!file.rename(tmp, path)) {
    file.remove(tmp)
    stop("Could not atomically commit DealSim artifact: ", path)
  }
  list(path = path, rows = nrow(data), checksum = checksum)
}

lmv2_p5_build_dealsim <- function(
    db_path, output_dir, p3_manifest_path) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  db_path <- normalizePath(db_path, winslash = "/", mustWork = TRUE)
  p3_manifest_path <- normalizePath(
    p3_manifest_path, winslash = "/", mustWork = TRUE)
  execution_hash <- digest::digest(
    c(
      version = LMV2_P5_DEALSIM_VERSION,
      script = lmv2_p3_file_hash(
        file.path(BASE, "R", "18o_build_lmv2_p5_dealsim.R")),
      config = lmv2_p3_file_hash(
        file.path(BASE, "R", "18m_lmv2_p5_final_config.R")),
      amendment = LMV2_P5_FINAL_AMENDMENT_SHA256,
      p3_manifest = lmv2_p3_file_hash(p3_manifest_path)),
    algo = "sha256")
  manifest_path <- file.path(output_dir, "dealsim_manifest.csv")
  if (file.exists(manifest_path)) {
    prior <- utils::read.csv(
      manifest_path, stringsAsFactors = FALSE)
    if (nrow(prior) &&
        identical(tail(prior$execution_hash, 1), execution_hash) &&
        all(file.exists(
          c(
            tail(prior$parquet_path, 1),
            tail(prior$map_path, 1),
            tail(prior$cutpoint_path, 1)))) &&
        identical(
          lmv2_p3_file_hash(tail(prior$parquet_path, 1)),
          tail(prior$parquet_checksum, 1)) &&
        identical(
          lmv2_p3_file_hash(tail(prior$map_path, 1)),
          tail(prior$map_checksum, 1)) &&
        identical(
          lmv2_p3_file_hash(tail(prior$cutpoint_path, 1)),
          tail(prior$cutpoint_checksum, 1))) {
      message("Reusing checksum-verified DealSim artifacts")
      return(invisible(prior[nrow(prior), ]))
    }
    stop("DealSim manifest exists but does not match live artifacts")
  }

  drv <- duckdb::duckdb()
  con <- DBI::dbConnect(drv, db_path, read_only = TRUE)
  on.exit(
    try(DBI::dbDisconnect(con, shutdown = TRUE), silent = TRUE),
    add = TRUE)
  deals <- DBI::dbGetQuery(con, "
    WITH treated_deals AS (
      SELECT DISTINCT
        CAST(cohort AS INTEGER) AS cohort,
        CAST(deal_id AS INTEGER) AS deal_id
      FROM lmv2_p3_treated_inventor_units
    ),
    deal_spine AS (
      SELECT
        t.cohort,t.deal_id,
        CAST(d.target_year AS INTEGER) AS target_year,
        CAST(d.target_group AS BIGINT) AS target_group,
        CAST(d.acquirer_group AS BIGINT) AS acquirer_group,
        d.acquirer_group_source,
        CASE
          WHEN d.acquirer_group_source='unresolved_placeholder_post_group'
            OR (
              d.acquirer_group IS NOT NULL
              AND CAST(CAST(d.acquirer_group AS BIGINT) AS VARCHAR)
                  LIKE '999%'
            )
          THEN TRUE ELSE FALSE
        END AS placeholder_acquirer
      FROM treated_deals t
      LEFT JOIN deal_assignment d USING (deal_id)
    ),
    deal_groups AS (
      SELECT
        cohort,deal_id,'target' AS side,target_group AS id_group
      FROM deal_spine WHERE target_group IS NOT NULL
      UNION ALL
      SELECT
        cohort,deal_id,'acquirer' AS side,acquirer_group AS id_group
      FROM deal_spine
      WHERE acquirer_group IS NOT NULL AND NOT placeholder_acquirer
    ),
    group_feature_counts AS (
      SELECT
        d.cohort,d.deal_id,d.side,m.ipc_feature,
        SUM(g.patent_count)::DOUBLE AS feature_count
      FROM deal_groups d
      JOIN group_ipc_year g
        ON CAST(g.id_group AS BIGINT)=d.id_group
       AND g.year BETWEEN d.cohort-5 AND d.cohort-1
      JOIN lmv2_p3_ipc_code_map m
        ON m.ipc_code=g.ipc_code AND m.resolution='ipc4'
      GROUP BY d.cohort,d.deal_id,d.side,m.ipc_feature
    ),
    group_vectors AS (
      SELECT
        cohort,deal_id,side,ipc_feature,
        feature_count/
          SUM(feature_count) OVER (PARTITION BY cohort,deal_id,side)
          AS frequency
      FROM group_feature_counts
    ),
    target_vectors AS (
      SELECT cohort,deal_id,ipc_feature,frequency
      FROM group_vectors WHERE side='target'
    ),
    acquirer_vectors AS (
      SELECT cohort,deal_id,ipc_feature,frequency
      FROM group_vectors WHERE side='acquirer'
    ),
    dots AS (
      SELECT
        t.cohort,t.deal_id,
        SUM(t.frequency*a.frequency) AS dot
      FROM target_vectors t
      JOIN acquirer_vectors a
        USING (cohort,deal_id,ipc_feature)
      GROUP BY t.cohort,t.deal_id
    ),
    target_norms AS (
      SELECT cohort,deal_id,
             SQRT(SUM(frequency*frequency)) AS target_norm
      FROM target_vectors GROUP BY cohort,deal_id
    ),
    acquirer_norms AS (
      SELECT cohort,deal_id,
             SQRT(SUM(frequency*frequency)) AS acquirer_norm
      FROM acquirer_vectors GROUP BY cohort,deal_id
    )
    SELECT
      d.*,
      tn.target_norm,
      an.acquirer_norm,
      CASE
        WHEN tn.target_norm > 0 AND an.acquirer_norm > 0
        THEN COALESCE(x.dot,0)/(tn.target_norm*an.acquirer_norm)
        ELSE NULL
      END AS dealsim
    FROM deal_spine d
    LEFT JOIN target_norms tn USING (cohort,deal_id)
    LEFT JOIN acquirer_norms an USING (cohort,deal_id)
    LEFT JOIN dots x USING (cohort,deal_id)
    ORDER BY d.cohort,d.deal_id")

  if (anyDuplicated(deals$deal_id)) {
    stop("DealSim input has duplicate deal IDs")
  }
  if (any(is.na(deals$target_year)) ||
      any(deals$cohort != deals$target_year)) {
    stop("DealSim cohort disagrees with deal target_year")
  }
  deals$exclusion_reason <- ifelse(
    deals$placeholder_acquirer, "placeholder_acquirer",
    ifelse(
      is.na(deals$acquirer_group), "missing_acquirer",
      ifelse(
        is.na(deals$target_norm), "missing_target_ipc4",
        ifelse(
          is.na(deals$acquirer_norm), "missing_acquirer_ipc4",
          NA_character_))))
  valid <- is.na(deals$exclusion_reason) & is.finite(deals$dealsim)
  if (!any(valid)) stop("No valid DealSim deals")
  if (any(deals$dealsim[valid] < -1e-12) ||
      any(deals$dealsim[valid] > 1 + 1e-12)) {
    stop("DealSim lies outside cosine bounds")
  }
  deals$dealsim[valid] <- pmin(1, pmax(0, deals$dealsim[valid]))

  cutpoints <- stats::quantile(
    deals$dealsim[valid],
    probs = LMV2_P5_FINAL$dealsim$probs,
    type = LMV2_P5_FINAL$dealsim$quantile_type,
    names = FALSE)
  if (!all(is.finite(cutpoints)) || cutpoints[1] >= cutpoints[2]) {
    stop("DealSim tercile cutpoints are not strictly ordered")
  }
  deals$dealsim_tercile <- NA_integer_
  deals$dealsim_tercile[valid & deals$dealsim <= cutpoints[1]] <- 1L
  deals$dealsim_tercile[
    valid & deals$dealsim > cutpoints[1] &
      deals$dealsim <= cutpoints[2]] <- 2L
  deals$dealsim_tercile[valid & deals$dealsim > cutpoints[2]] <- 3L
  if (any(is.na(deals$dealsim_tercile[valid]))) {
    stop("Valid DealSim deal lacks a tercile")
  }

  deals$definition_hash <- execution_hash
  map <- deals[c(
    "cohort", "deal_id", "target_group", "acquirer_group",
    "acquirer_group_source", "placeholder_acquirer",
    "target_norm", "acquirer_norm", "dealsim",
    "dealsim_tercile", "exclusion_reason", "definition_hash")]
  cutpoint_table <- data.frame(
    lower_upper_boundary = c("tercile_1_upper", "tercile_2_upper"),
    value = as.numeric(cutpoints),
    quantile_probability = LMV2_P5_FINAL$dealsim$probs,
    quantile_type = LMV2_P5_FINAL$dealsim$quantile_type,
    lower_boundary_included =
      LMV2_P5_FINAL$dealsim$lower_boundary_included,
    n_analysis_spine_deals = nrow(map),
    n_valid_deals = sum(valid),
    definition_hash = execution_hash,
    stringsAsFactors = FALSE)

  tag <- substr(execution_hash, 1, 12)
  parquet_path <- file.path(
    output_dir, sprintf("dealsim_by_deal_%s.parquet", tag))
  map_path <- file.path(
    output_dir, sprintf("dealsim_tercile_map_%s.csv", tag))
  cutpoint_path <- file.path(
    output_dir, sprintf("dealsim_cutpoints_%s.csv", tag))

  duckdb::duckdb_register(con, "lmv2_p5_dealsim_map", map)
  parquet_result <- lmv2_write_atomic_parquet(
    con,
    "SELECT * FROM lmv2_p5_dealsim_map ORDER BY cohort,deal_id",
    parquet_path,
    "deal_id")
  duckdb::duckdb_unregister(con, "lmv2_p5_dealsim_map")
  map_result <- lmv2_p5_write_atomic_csv(map, map_path)
  cutpoint_result <- lmv2_p5_write_atomic_csv(
    cutpoint_table, cutpoint_path)

  counts <- table(
    factor(map$dealsim_tercile, levels = 1:3),
    useNA = "no")
  manifest <- data.frame(
    version = LMV2_P5_DEALSIM_VERSION,
    execution_hash = execution_hash,
    amendment_hash = LMV2_P5_FINAL_AMENDMENT_SHA256,
    p3_manifest_hash = lmv2_p3_file_hash(p3_manifest_path),
    n_analysis_spine_deals = nrow(map),
    n_valid_deals = sum(valid),
    n_placeholder_acquirer = sum(map$placeholder_acquirer),
    n_tercile_1 = counts[1],
    n_tercile_2 = counts[2],
    n_tercile_3 = counts[3],
    cutpoint_1 = cutpoints[1],
    cutpoint_2 = cutpoints[2],
    parquet_path = parquet_result$path,
    parquet_checksum = parquet_result$checksum,
    map_path = map_result$path,
    map_checksum = map_result$checksum,
    cutpoint_path = cutpoint_result$path,
    cutpoint_checksum = cutpoint_result$checksum,
    status = "complete",
    timestamp = as.character(Sys.time()),
    stringsAsFactors = FALSE)
  utils::write.csv(manifest, manifest_path, row.names = FALSE)

  checks <- data.frame(
    check = c(
      "one_row_per_deal", "cohort_equals_target_year",
      "valid_cosine_bounds", "placeholder_excluded",
      "valid_deals_have_tercile", "three_nonempty_terciles"),
    pass = c(
      !anyDuplicated(map$deal_id),
      all(deals$cohort == deals$target_year),
      all(map$dealsim[valid] >= 0 & map$dealsim[valid] <= 1),
      all(is.na(map$dealsim_tercile[map$placeholder_acquirer])),
      all(!is.na(map$dealsim_tercile[valid])),
      all(counts > 0)),
    stringsAsFactors = FALSE)
  utils::write.csv(
    checks,
    file.path(output_dir, "dealsim_certification.csv"),
    row.names = FALSE)
  if (any(!checks$pass)) {
    stop(
      "DealSim certification failed: ",
      paste(checks$check[!checks$pass], collapse = ", "))
  }
  message(
    "DealSim certified: ", sum(valid), "/", nrow(map),
    " deals valid; terciles ", paste(counts, collapse = "/"))
  invisible(manifest)
}

if (any(startsWith(args, "--dealsim-mode="))) {
  mode <- read_dealsim_arg("dealsim-mode")
  if (!identical(mode, "production")) {
    stop("--dealsim-mode= currently supports production only")
  }
  lmv2_p5_build_dealsim(
    db_path = read_dealsim_arg("db"),
    output_dir = read_dealsim_arg("output-dir"),
    p3_manifest_path = read_dealsim_arg("p3-manifest"))
}
