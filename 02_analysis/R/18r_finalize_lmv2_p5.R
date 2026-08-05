# Outcome-blind P5 artifact finalizer and design audit.
#
# Reads only P3 design inputs, P5 diagnostics, DealSim, and P5 weights. It
# never opens an outcome table and never estimates a treatment effect.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE, default = NA_character_) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(default)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

if (!requireNamespace("DBI", quietly = TRUE) ||
    !requireNamespace("duckdb", quietly = TRUE) ||
    !requireNamespace("digest", quietly = TRUE)) {
  stop("DBI, duckdb, and digest are required")
}

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "18m_lmv2_p5_final_config.R"))

p5_root <- normalizePath(
  read_arg("p5-root"), winslash = "/", mustWork = TRUE)
db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
dealsim_map_path <- normalizePath(
  read_arg("dealsim-map"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg(
  "output-dir", required = FALSE,
  default = file.path(p5_root, "finalized"))
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)

sql_string <- function(x) {
  paste0("'", gsub("'", "''", normalizePath(
    x, winslash = "/", mustWork = TRUE), fixed = TRUE), "'")
}

atomic_csv <- function(x, path) {
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  utils::write.csv(x, tmp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Could not finalize ", path)
  invisible(path)
}

atomic_copy_parquet <- function(con, paths, path, order_by) {
  if (!length(paths)) return(NA_character_)
  tmp <- paste0(path, ".tmp_", Sys.getpid(), ".parquet")
  path_sql <- paste(vapply(paths, sql_string, character(1)), collapse = ",")
  DBI::dbExecute(con, sprintf(
    "COPY (
       SELECT * FROM read_parquet([%s], union_by_name=true)
       ORDER BY %s
     ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    path_sql, order_by,
    paste0("'", gsub("'", "''", tmp, fixed = TRUE), "'")))
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Could not finalize ", path)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

collect_branch <- function(root, scope, tercile = NA_integer_) {
  if (!dir.exists(root)) stop("Missing P5 branch: ", root)
  status_path <- file.path(root, "scheduler_status.csv")
  if (!file.exists(status_path)) stop("Missing scheduler status: ", root)
  scheduler <- utils::read.csv(status_path, stringsAsFactors = FALSE)
  if (any(scheduler$status != "complete")) {
    stop("Incomplete scheduler cells in ", root)
  }
  cohort_dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  cohort_dirs <- cohort_dirs[grepl("cohort_[0-9]{4}$", cohort_dirs)]
  diagnostics <- do.call(rbind, lapply(cohort_dirs, function(d) {
    p <- list.files(
      d, pattern = "^cohort_hybrid_diagnostics_[0-9]{4}\\.csv$",
      full.names = TRUE)
    if (length(p) != 1L) stop("Expected one diagnostic shard in ", d)
    utils::read.csv(p, stringsAsFactors = FALSE)
  }))
  diagnostics$analysis_scope <- scope
  diagnostics$dealsim_tercile <- tercile

  manifests <- do.call(rbind, lapply(cohort_dirs, function(d) {
    p <- file.path(d, "weights", "manifest.csv")
    if (!file.exists(p)) return(NULL)
    utils::read.csv(p, stringsAsFactors = FALSE)
  }))
  if (is.null(manifests)) manifests <- data.frame()
  if (nrow(manifests)) {
    if (anyDuplicated(manifests[c(
        "analysis_scope", "cohort", "dealsim_tercile_key", "scheme")])) {
      stop("Duplicate completed weight cell in ", root)
    }
    if (any(manifests$analysis_scope != scope)) {
      stop("Scope mismatch in ", root)
    }
    if (!is.na(tercile) &&
        any(as.integer(manifests$dealsim_tercile_key) != tercile)) {
      stop("DealSim tercile mismatch in ", root)
    }
  }
  list(
    root = root, scheduler = scheduler,
    diagnostics = diagnostics, manifests = manifests)
}

branches <- list(
  collect_branch(file.path(p5_root, "main"), "main"),
  collect_branch(
    file.path(p5_root, "dealsim", "tercile_1"),
    "dealsim_tercile", 1L),
  collect_branch(
    file.path(p5_root, "dealsim", "tercile_2"),
    "dealsim_tercile", 2L),
  collect_branch(
    file.path(p5_root, "dealsim", "tercile_3"),
    "dealsim_tercile", 3L))

diagnostics <- do.call(rbind, lapply(branches, `[[`, "diagnostics"))
manifests <- do.call(rbind, lapply(branches, `[[`, "manifests"))

if (!nrow(manifests)) stop("No completed P5 weight artifacts found")
if (any(manifests$caliper != LMV2_P5_FINAL$selected$stage1_caliper) ||
    any(manifests$profile != LMV2_P5_FINAL$selected$profile) ||
    any(manifests$universe != LMV2_P5_FINAL$selected$universe) ||
    any(!manifests$scheme %in% LMV2_P5_FINAL$selected$schemes)) {
  stop("Completed artifact violates the frozen P5 specification")
}

con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=2")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
DBI::dbExecute(con, "PRAGMA preserve_insertion_order=false")

audit_rows <- vector("list", nrow(manifests))
for (i in seq_len(nrow(manifests))) {
  m <- manifests[i, ]
  if (!file.exists(m$path) || !file.exists(m$deal_balance_path)) {
    stop("Manifested artifact missing for cohort ", m$cohort)
  }
  weight_hash <- digest::digest(
    file = m$path, algo = "sha256", serialize = FALSE)
  balance_hash <- digest::digest(
    file = m$deal_balance_path, algo = "sha256", serialize = FALSE)
  if (!identical(weight_hash, m$checksum) ||
      !identical(balance_hash, m$deal_balance_checksum)) {
    stop("Checksum mismatch for cohort ", m$cohort, " ", m$scheme)
  }
  q <- DBI::dbGetQuery(con, sprintf(
    "SELECT
       COUNT(*)::BIGINT AS row_count,
       SUM(CASE WHEN treated=1 THEN 1 ELSE 0 END)::BIGINT AS treated_rows,
       SUM(CASE WHEN treated=0 THEN 1 ELSE 0 END)::BIGINT AS control_rows,
       SUM(CASE WHEN treated=1 THEN final_weight ELSE 0 END) AS treated_mass,
       SUM(CASE WHEN treated=0 THEN final_weight ELSE 0 END) AS control_mass,
       COUNT(DISTINCT CASE WHEN treated=1 THEN deal_id END)::BIGINT
         AS treated_deals,
       SUM(CASE WHEN NOT isfinite(final_weight) OR final_weight < 0
                THEN 1 ELSE 0 END)::BIGINT AS invalid_weights
     FROM read_parquet(%s)",
    sql_string(m$path)))
  b <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*)::BIGINT AS balance_rows
     FROM read_parquet(%s)", sql_string(m$deal_balance_path)))
  if (q$row_count != as.numeric(m$row_count) ||
      q$treated_rows != as.numeric(m$treated_rows) ||
      q$control_rows != as.numeric(m$control_rows) ||
      abs(q$treated_mass - as.numeric(m$treated_mass)) > 1e-6 ||
      abs(q$control_mass - as.numeric(m$control_mass)) > 1e-6 ||
      abs(q$treated_mass - q$control_mass) > 1e-6 ||
      q$invalid_weights != 0 ||
      b$balance_rows != as.numeric(m$deal_balance_rows)) {
    stop("Row/mass validation failed for cohort ", m$cohort, " ", m$scheme)
  }
  audit_rows[[i]] <- data.frame(
    analysis_scope = m$analysis_scope,
    dealsim_tercile = if (m$dealsim_tercile_key == "__none__") {
      NA_integer_
    } else {
      as.integer(m$dealsim_tercile_key)
    },
    cohort = as.integer(m$cohort),
    scheme = m$scheme,
    row_count = as.numeric(q$row_count),
    treated_rows = as.numeric(q$treated_rows),
    control_rows = as.numeric(q$control_rows),
    treated_deals = as.numeric(q$treated_deals),
    treated_mass = q$treated_mass,
    control_mass = q$control_mass,
    balance_rows = as.numeric(b$balance_rows),
    weight_checksum_valid = TRUE,
    balance_checksum_valid = TRUE,
    stringsAsFactors = FALSE)
}
artifact_audit <- do.call(rbind, audit_rows)

dealsim_map <- utils::read.csv(
  dealsim_map_path, stringsAsFactors = FALSE)
if (anyDuplicated(dealsim_map[c("cohort", "deal_id")]) ||
    length(unique(dealsim_map$definition_hash)) != 1L) {
  stop("DealSim map key or definition hash is invalid")
}
DBI::dbWriteTable(con, "p5_finalize_dealsim_map", dealsim_map, temporary = TRUE)

dealsim_denominator <- DBI::dbGetQuery(con, "
  SELECT
    CAST(m.dealsim_tercile AS INTEGER) AS dealsim_tercile,
    COUNT(*)::BIGINT AS eligible_treated_inventors,
    COUNT(DISTINCT t.deal_id)::BIGINT AS eligible_deals
  FROM lmv2_p3_treated_inventor_units t
  JOIN p5_finalize_dealsim_map m
    ON m.cohort=t.cohort AND m.deal_id=t.deal_id
  WHERE m.dealsim_tercile IS NOT NULL
  GROUP BY m.dealsim_tercile
  ORDER BY m.dealsim_tercile")

main_diag <- diagnostics[
  diagnostics$analysis_scope == "main" &
    diagnostics$scheme == "primary", ]
main_num <- artifact_audit[
  artifact_audit$analysis_scope == "main" &
    artifact_audit$scheme == "primary", ]
coverage <- data.frame(
  analysis = "main",
  dealsim_tercile = NA_integer_,
  eligible_treated_inventors = sum(main_diag$n_treated_full_spine),
  supported_treated_inventors = sum(main_num$treated_rows),
  eligible_deals = sum(main_diag$n_deals_full_spine),
  supported_deals = sum(main_num$treated_deals),
  inventor_floor = 0.80,
  deal_floor = NA_real_,
  stringsAsFactors = FALSE)

for (tt in 1:3) {
  den_index <- match(
    as.integer(tt),
    as.integer(dealsim_denominator$dealsim_tercile))
  if (is.na(den_index)) {
    stop("Missing DealSim denominator for tercile ", tt)
  }
  den <- dealsim_denominator[den_index, , drop = FALSE]
  num <- artifact_audit[
    artifact_audit$analysis_scope == "dealsim_tercile" &
      artifact_audit$dealsim_tercile == tt &
      artifact_audit$scheme == "primary", ]
  coverage <- rbind(coverage, data.frame(
    analysis = paste0("dealsim_tercile_", tt),
    dealsim_tercile = tt,
    eligible_treated_inventors = den$eligible_treated_inventors,
    supported_treated_inventors = sum(num$treated_rows),
    eligible_deals = den$eligible_deals,
    supported_deals = sum(num$treated_deals),
    inventor_floor = LMV2_P5_FINAL$dealsim$minimum_inventor_retention,
    deal_floor = LMV2_P5_FINAL$dealsim$minimum_deal_retention,
    stringsAsFactors = FALSE))
}
coverage$inventor_coverage <- with(
  coverage, supported_treated_inventors / eligible_treated_inventors)
coverage$deal_coverage <- with(
  coverage, supported_deals / eligible_deals)
coverage$inventor_gate_pass <- with(
  coverage, inventor_coverage >= inventor_floor)
coverage$deal_gate_pass <- with(
  coverage, is.na(deal_floor) | deal_coverage >= deal_floor)
coverage$reportable <- coverage$inventor_gate_pass & coverage$deal_gate_pass

combined_manifest <- list()
combined_index <- 0L
for (scope in c("main", "dealsim_tercile")) {
  terciles <- if (scope == "main") NA_integer_ else 1:3
  for (tt in terciles) {
    for (scheme in LMV2_P5_FINAL$selected$schemes) {
      pick <- manifests$analysis_scope == scope &
        manifests$scheme == scheme
      label <- "main"
      if (scope == "dealsim_tercile") {
        pick <- pick &
          manifests$dealsim_tercile_key == as.character(tt)
        label <- paste0("dealsim_tercile_", tt)
      }
      mm <- manifests[pick, ]
      if (!nrow(mm)) next
      weight_path <- file.path(
        output_dir, paste0("p5_", label, "_", scheme, "_weights.parquet"))
      balance_path <- file.path(
        output_dir,
        paste0("p5_", label, "_", scheme, "_deal_balance.parquet"))
      atomic_copy_parquet(
        con, mm$path, weight_path,
        "cohort, deal_id, treated DESC, roster_row_id")
      atomic_copy_parquet(
        con, mm$deal_balance_path, balance_path,
        "cohort, deal_id")
      combined_index <- combined_index + 1L
      combined_manifest[[combined_index]] <- data.frame(
        analysis = label,
        scheme = scheme,
        weight_path = weight_path,
        weight_checksum = digest::digest(
          file = weight_path, algo = "sha256", serialize = FALSE),
        deal_balance_path = balance_path,
        deal_balance_checksum = digest::digest(
          file = balance_path, algo = "sha256", serialize = FALSE),
        source_cells = nrow(mm),
        timestamp = as.character(Sys.time()),
        stringsAsFactors = FALSE)
    }
  }
}
combined_manifest <- do.call(rbind, combined_manifest)

# Retained-versus-unsupported treated characteristics for the main primary
# weights. These are pre-treatment design variables only.
main_primary_paths <- manifests$path[
  manifests$analysis_scope == "main" &
    manifests$scheme == "primary"]
DBI::dbExecute(con, sprintf(
  "CREATE OR REPLACE TEMP TABLE p5_main_supported AS
   SELECT DISTINCT cohort, deal_id, CAST(codinv AS BIGINT) AS codinv
   FROM read_parquet([%s], union_by_name=true)
   WHERE treated=1",
  paste(vapply(main_primary_paths, sql_string, character(1)), collapse = ",")))
selection_long <- DBI::dbGetQuery(con, "
  WITH x AS (
    SELECT
      t.*,
      CASE WHEN s.codinv IS NULL THEN 'unsupported' ELSE 'supported' END
        AS support_status
    FROM lmv2_p3_treated_inventor_units t
    LEFT JOIN p5_main_supported s
      ON s.cohort=t.cohort AND s.deal_id=t.deal_id AND s.codinv=t.codinv
  )
  SELECT support_status, variable, n, mean, sd
  FROM (
    SELECT support_status, 'log_patent_count_5y' AS variable,
      COUNT(*)::BIGINT AS n,
      AVG(log_patent_count_5y) AS mean,
      STDDEV_SAMP(log_patent_count_5y) AS sd
    FROM x GROUP BY support_status
    UNION ALL
    SELECT support_status, 'patent_trajectory',
      COUNT(*)::BIGINT, AVG(patent_trajectory),
      STDDEV_SAMP(patent_trajectory)
    FROM x GROUP BY support_status
    UNION ALL
    SELECT support_status, 'career_age',
      COUNT(*)::BIGINT, AVG(career_age), STDDEV_SAMP(career_age)
    FROM x GROUP BY support_status
    UNION ALL
    SELECT support_status, 'focal_group_tenure',
      COUNT(*)::BIGINT, AVG(focal_group_tenure),
      STDDEV_SAMP(focal_group_tenure)
    FROM x GROUP BY support_status
    UNION ALL
    SELECT support_status, 'focal_group_exclusivity',
      COUNT(*)::BIGINT, AVG(focal_group_exclusivity),
      STDDEV_SAMP(focal_group_exclusivity)
    FROM x GROUP BY support_status
  ) q
  ORDER BY variable, support_status")
selection_wide <- reshape(
  selection_long, idvar = "variable", timevar = "support_status",
  direction = "wide")
selection_wide$smd_supported_minus_unsupported <- with(
  selection_wide,
  (mean.supported - mean.unsupported) /
    sqrt((sd.supported^2 + sd.unsupported^2) / 2))

# Test whether DealSim is associated with remaining deal-level imbalance in
# successful main primary cells. These are design diagnostics, not outcomes.
main_balance_paths <- manifests$deal_balance_path[
  manifests$analysis_scope == "main" &
    manifests$scheme == "primary"]
balance <- DBI::dbGetQuery(con, sprintf(
  "SELECT * FROM read_parquet([%s], union_by_name=true)",
  paste(vapply(
    main_balance_paths, sql_string, character(1)), collapse = ",")))
balance <- merge(
  balance,
  dealsim_map[c("cohort", "deal_id", "dealsim", "dealsim_tercile")],
  by = c("cohort", "deal_id"))
smd_cols <- grep("^signed_smd_", names(balance), value = TRUE)
association <- do.call(rbind, lapply(
  c("max_abs_smd", smd_cols), function(v) {
    ok <- is.finite(balance[[v]]) & is.finite(balance$dealsim)
    pearson <- stats::cor.test(
      balance[[v]][ok], balance$dealsim[ok], method = "pearson")
    spearman <- suppressWarnings(stats::cor.test(
      balance[[v]][ok], balance$dealsim[ok],
      method = "spearman", exact = FALSE))
    data.frame(
      balance_metric = v,
      n = sum(ok),
      pearson = unname(pearson$estimate),
      pearson_p = pearson$p.value,
      spearman = unname(spearman$estimate),
      spearman_p = spearman$p.value,
      stringsAsFactors = FALSE)
  }))
association$pearson_p_holm <- stats::p.adjust(
  association$pearson_p, method = "holm")
association$spearman_p_holm <- stats::p.adjust(
  association$spearman_p, method = "holm")

atomic_csv(diagnostics, file.path(output_dir, "p5_cell_diagnostics.csv"))
atomic_csv(artifact_audit, file.path(
  output_dir, "p5_weight_manifest_audit.csv"))
atomic_csv(coverage, file.path(output_dir, "p5_coverage_summary.csv"))
atomic_csv(selection_wide, file.path(
  output_dir, "p5_main_retained_vs_unsupported.csv"))
atomic_csv(association, file.path(
  output_dir, "p5_dealsim_balance_association.csv"))
atomic_csv(combined_manifest, file.path(
  output_dir, "p5_combined_artifact_manifest.csv"))

summary_path <- file.path(output_dir, "p5_outcome_blind_audit_summary.md")
summary_lines <- c(
  "# P5 outcome-blind final audit",
  "",
  paste0("- Amendment SHA-256: `", LMV2_P5_FINAL_AMENDMENT_SHA256, "`"),
  paste0("- Validated completed weight cells: ", nrow(artifact_audit)),
  paste0("- Validated combined artifacts: ", nrow(combined_manifest)),
  "- Weight/deal-balance checksums, row counts, nonnegative finite weights,",
  "  and treated/control mass equality all pass.",
  "- No outcome table was read and no treatment effect was estimated.",
  "",
  "## Coverage gates",
  "",
  "| Analysis | Inventors | Inventor coverage | Deals | Deal coverage | Reportable |",
  "|---|---:|---:|---:|---:|:---:|",
  vapply(seq_len(nrow(coverage)), function(i) {
    sprintf(
      "| %s | %d/%d | %.2f%% | %d/%d | %.2f%% | %s |",
      coverage$analysis[i],
      coverage$supported_treated_inventors[i],
      coverage$eligible_treated_inventors[i],
      100 * coverage$inventor_coverage[i],
      coverage$supported_deals[i],
      coverage$eligible_deals[i],
      100 * coverage$deal_coverage[i],
      if (coverage$reportable[i]) "yes" else "no")
  }, character(1)))
writeLines(summary_lines, summary_path, useBytes = TRUE)

cat("P5 outcome-blind finalization complete\n")
print(coverage)
