# ============================================================================
# Package 1: solve all four P5c leave-one-pre-year-out weight arms
# ============================================================================
# The terminal t=-1 period remains balanced and is not a placebo under the
# no-anticipation design.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))
lmv2_install_p5_newton_solver()

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}

if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Missing package: digest")
}

AUDIT_ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
SOURCE_DIR <- file.path(AUDIT_ROOT, "P5C_ANNUAL_TRAJECTORY", "production")
OUTPUT_DIR <- file.path(
  AUDIT_ROOT, "ROBUSTNESS_RELEASE_1993", "P5C_LOYO_GRID")
output_override <- get_arg("--output-dir")
if (!is.na(output_override)) OUTPUT_DIR <- output_override
dir.create(file.path(OUTPUT_DIR, "weights"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "balance"), recursive = TRUE, showWarnings = FALSE)

FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_package1_preperiod_freeze.md")
SOURCE_CERT_PATH <- file.path(SOURCE_DIR, "p5c_certification.csv")
SOURCE_DIAGNOSTICS_PATH <- file.path(
  SOURCE_DIR, "p5c_cell_diagnostics.csv")
BASE_HANDOFF_DIR <- file.path(
  AUDIT_ROOT, "P5C_P6_HANDOFF")
BASE_HANDOFF_PATH <- file.path(
  BASE_HANDOFF_DIR, "p5c_p6_primary_weighted_roster.parquet")
BASE_HANDOFF_MANIFEST_PATH <- file.path(
  BASE_HANDOFF_DIR, "p5c_p6_roster_manifest.csv")

source_paths <- c(
  runner = file.path(BASE, "R", "22a_run_lmv2_package1_loyo_grid.R"),
  freeze = FREEZE_PATH,
  source_certification = SOURCE_CERT_PATH,
  source_diagnostics = SOURCE_DIAGNOSTICS_PATH,
  base_handoff_manifest = BASE_HANDOFF_MANIFEST_PATH,
  cohort_core = file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"),
  newton_solver = file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))
missing <- source_paths[!file.exists(source_paths)]
if (length(missing)) {
  stop("Package 1 source missing: ", paste(names(missing), collapse = ", "))
}
if (!file.exists(BASE_HANDOFF_PATH)) stop("Base P5c handoff roster is missing")

source_sha <- vapply(
  source_paths, digest::digest, character(1), file = TRUE, algo = "sha256")
settings <- list(
  version = "lmv2_package1_loyo_grid_1993_amendment_v1",
  cohorts = 1993:2010,
  variants = c("loyo_m2", "loyo_m3", "loyo_m4", "loyo_m5"),
  count_variables = paste0("patent_count_m", 5:1),
  active_variables = paste0("active_patenting_m", 5:1),
  retained_inventor_variables = c("career_age", "focal_group_exclusivity"),
  firm_variables = c(
    "firm_log_patent_stock_5y",
    "firm_log_inventor_count_5y",
    "firm_patent_trajectory"))
variants_override <- get_arg("--variants")
if (!is.na(variants_override)) {
  settings$variants <- strsplit(variants_override, ",", fixed = TRUE)[[1]]
}
if (!length(settings$variants) ||
    any(!settings$variants %in% paste0("loyo_m", 1:5)) ||
    anyDuplicated(settings$variants)) {
  stop("--variants must be a unique comma-separated subset of loyo_m1..loyo_m5")
}
execution_hash <- digest::digest(
  list(settings = settings, source_sha256 = source_sha),
  algo = "sha256")

atomic_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temp <- paste0(path, ".tmp")
  utils::write.csv(x, temp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temp, path)) stop("Could not publish ", path)
  invisible(path)
}

atomic_parquet <- function(con, x, path, order_by) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temp <- paste0(path, ".tmp.parquet")
  if (file.exists(temp)) file.remove(temp)
  duckdb::duckdb_register(con, "package1_write_rows", x)
  on.exit(try(
    duckdb::duckdb_unregister(con, "package1_write_rows"),
    silent = TRUE), add = TRUE)
  DBI::dbExecute(con, sprintf(
    "COPY (
       SELECT * FROM package1_write_rows ORDER BY %s
     ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    order_by, DBI::dbQuoteString(con, temp)))
  duckdb::duckdb_unregister(con, "package1_write_rows")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temp, path)) stop("Could not publish ", path)
  invisible(path)
}

append_checkpoint <- function(row, path) {
  old <- if (file.exists(path)) {
    utils::read.csv(path, stringsAsFactors = FALSE)
  } else {
    row[FALSE, , drop = FALSE]
  }
  if (nrow(old)) {
    same <- old$execution_hash == row$execution_hash &
      old$cohort == row$cohort & old$variant == row$variant
    old <- old[!same, , drop = FALSE]
  }
  atomic_csv(rbind(old, row), path)
}

balance_variables <- function(variant) {
  held_out <- as.integer(sub("^loyo_m", "", variant))
  if (!held_out %in% 1:5) stop("Invalid LOYO variant: ", variant)
  c(
    setdiff(settings$count_variables, paste0("patent_count_m", held_out)),
    setdiff(settings$active_variables, paste0("active_patenting_m", held_out)),
    settings$retained_inventor_variables,
    settings$firm_variables)
}

balance_table <- function(roster, weight, variables, stage) {
  standardized <- lmv2_ebal_standardize_cohort(variables, roster)
  use <- setdiff(variables, standardized$zero_variance)
  out <- if (length(use)) {
    lmv2_ebal_covariate_balance(
      use, standardized$data, roster$D, weight)
  } else {
    data.frame(
      variable = character(), treated_mean = numeric(),
      control_mean = numeric(), difference = numeric(),
      abs_difference = numeric())
  }
  out$stage <- stage
  out
}

source_cert <- utils::read.csv(
  SOURCE_CERT_PATH, stringsAsFactors = FALSE)
if (nrow(source_cert) != 1L || !isTRUE(source_cert$all_pass)) {
  stop("Certified P5c production source did not pass")
}
source_diagnostics <- utils::read.csv(
  SOURCE_DIAGNOSTICS_PATH, stringsAsFactors = FALSE)
source_rows <- source_diagnostics[
  source_diagnostics$execution_hash == source_cert$execution_hash &
    source_diagnostics$scheme == "primary" &
    source_diagnostics$variant == "count_active", ,
  drop = FALSE]
if (nrow(source_rows) != 18L ||
    !identical(sort(as.integer(source_rows$cohort)), 1993:2010) ||
    any(!source_rows$feasible)) {
  stop("Current certified P5c source does not contain 18 feasible cohorts")
}
valid_source_artifacts <- vapply(seq_len(nrow(source_rows)), function(i) {
  file.exists(source_rows$weight_path[[i]]) &&
    identical(
      digest::digest(
        file = source_rows$weight_path[[i]], algo = "sha256"),
      source_rows$weight_sha256[[i]])
}, logical(1))
if (!all(valid_source_artifacts)) {
  stop("Current P5c source weight artifact is missing or has drifted")
}

base_handoff_manifest <- utils::read.csv(
  BASE_HANDOFF_MANIFEST_PATH, stringsAsFactors = FALSE)
if (nrow(base_handoff_manifest) != 1L ||
    !isTRUE(base_handoff_manifest$certification_pass) ||
    !identical(
      digest::digest(file = BASE_HANDOFF_PATH, algo = "sha256"),
      base_handoff_manifest$roster_sha256)) {
  stop("Certified count-active handoff is invalid")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=4")
DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")

diagnostics_path <- file.path(
  OUTPUT_DIR, "package1_loyo_cell_diagnostics.csv")
for (cohort in settings$cohorts) {
  source_row <- source_rows[source_rows$cohort == cohort, , drop = FALSE]
  x <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM read_parquet(%s) ORDER BY roster_row_id",
    DBI::dbQuoteString(con, normalizePath(
      source_row$weight_path, winslash = "/", mustWork = TRUE))))
  if (anyDuplicated(x$roster_row_id) ||
      any(!x$treated %in% c(0L, 1L)) ||
      max(abs(x$base_weight - ifelse(
        x$treated == 1L, 1,
        ave(x$treated, x$deal_id, FUN = function(z) {
          sum(z == 1L) / sum(z == 0L)
        })))) > 1e-10) {
    stop("Source roster/base-weight invariant failed for cohort ", cohort)
  }

  all_variables <- unique(c(
    settings$count_variables, settings$active_variables,
    settings$retained_inventor_variables, settings$firm_variables))
  if (any(vapply(
      x[all_variables], function(z) any(!is.finite(z)), logical(1)))) {
    stop("Non-finite Package 1 covariate in cohort ", cohort)
  }

  for (variant in settings$variants) {
    existing <- if (file.exists(diagnostics_path)) {
      utils::read.csv(diagnostics_path, stringsAsFactors = FALSE)
    } else NULL
    ready <- !is.null(existing) && any(
      existing$execution_hash == execution_hash &
        existing$cohort == cohort &
        existing$variant == variant &
        existing$feasible &
        file.exists(existing$weight_path))
    if (ready) {
      message("Package 1 cohort ", cohort, ": reuse ", variant)
      next
    }

    message("Package 1 cohort ", cohort, ": solve ", variant)
    started <- Sys.time()
    variables <- balance_variables(variant)
    held_out <- as.integer(sub("^loyo_m", "", variant))
    roster <- data.frame(
      D = as.integer(x$treated),
      cohort = as.integer(x$cohort),
      deal_id = as.integer(x$deal_id),
      treated_codinv = ifelse(x$treated == 1L, x$codinv, NA_real_),
      control_codinv = ifelse(x$treated == 0L, x$codinv, NA_real_),
      control_group = ifelse(x$treated == 0L, x$group_id, NA_real_),
      base_weight = x$base_weight,
      x[all_variables],
      check.names = FALSE)
    hierarchy <- lmv2_ebal_cohort_feasibility_hierarchy(
      roster = roster,
      n_eligible_treated = sum(roster$D == 1L),
      inv_vars = setdiff(variables, settings$firm_variables),
      firm_vars = settings$firm_variables)
    feasible <- hierarchy$mode %in% c(
      "exact_ebal", "optweight_0.05", "optweight_0.10") &&
      !is.null(hierarchy$result)
    if (!feasible) stop("LOYO solve infeasible: ", cohort, " / ", variant)
    final_weight <- hierarchy$result$weight

    lmv2_ebal_assert_final_treated_weights_equal_base(
      final_weight[roster$D == 1L],
      roster$base_weight[roster$D == 1L])
    lmv2_ebal_assert_masses_agree(
      final_weight[roster$D == 1L],
      final_weight[roster$D == 0L],
      scheme = "primary",
      n_retained_deals = length(unique(
        roster$deal_id[roster$D == 1L])))

    before <- balance_table(
      roster, roster$base_weight, variables, "before")
    after <- balance_table(roster, final_weight, variables, "after")
    held_out_balance <- balance_table(
      roster, final_weight,
      c(paste0("patent_count_m", held_out),
        paste0("active_patenting_m", held_out)),
      "held_out_diagnostic_after")
    balance <- rbind(before, after, held_out_balance)
    balance$cohort <- cohort
    balance$variant <- variant
    cell_stub <- sprintf(
      "c%d_%s_%s", cohort, variant, substr(execution_hash, 1, 12))
    balance_path <- file.path(
      OUTPUT_DIR, "balance", paste0(cell_stub, ".csv"))
    atomic_csv(balance, balance_path)

    weights <- x
    weights$variant <- variant
    weights$final_weight <- final_weight
    weights$package1_execution_hash <- execution_hash
    weights$source_count_active_sha256 <- source_row$weight_sha256
    weight_path <- file.path(
      OUTPUT_DIR, "weights", paste0(cell_stub, ".parquet"))
    atomic_parquet(con, weights, weight_path, "roster_row_id")

    count_held <- held_out_balance[
      held_out_balance$variable == paste0("patent_count_m", held_out), ,
      drop = FALSE]
    active_held <- held_out_balance[
      held_out_balance$variable == paste0("active_patenting_m", held_out), ,
      drop = FALSE]
    row <- data.frame(
      version = settings$version,
      execution_hash = execution_hash,
      cohort = cohort,
      variant = variant,
      held_out_event_time = -held_out,
      feasible = feasible,
      mode = hierarchy$mode,
      tier = if (is.null(hierarchy$tier)) NA_character_ else hierarchy$tier,
      n_rows = nrow(roster),
      n_treated = sum(roster$D == 1L),
      reuse_adjusted_ess = hierarchy$ess_info$reuse_adjusted_ess,
      reuse_adjusted_ess_ratio = hierarchy$ess_gate$ess_ratio,
      reuse_adjusted_max_share =
        hierarchy$ess_info$reuse_adjusted_concentration$max_share,
      max_balanced_smd = max(after$abs_difference),
      held_out_count_smd = count_held$difference,
      held_out_active_smd = active_held$difference,
      weight_path = normalizePath(
        weight_path, winslash = "/", mustWork = TRUE),
      weight_sha256 = digest::digest(
        file = weight_path, algo = "sha256"),
      balance_path = normalizePath(
        balance_path, winslash = "/", mustWork = TRUE),
      source_count_active_sha256 = source_row$weight_sha256,
      elapsed_seconds = as.numeric(difftime(
        Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE)
    append_checkpoint(row, diagnostics_path)
  }
  rm(x)
  gc(FALSE)
}

diagnostics <- utils::read.csv(
  diagnostics_path, stringsAsFactors = FALSE)
current <- diagnostics[
  diagnostics$execution_hash == execution_hash &
    diagnostics$cohort %in% settings$cohorts &
    diagnostics$variant %in% settings$variants, ,
  drop = FALSE]
expected <- expand.grid(
  cohort = settings$cohorts,
  variant = settings$variants,
  stringsAsFactors = FALSE)
complete <- nrow(current) == nrow(expected) &&
  all(paste(expected$cohort, expected$variant) %in%
      paste(current$cohort, current$variant))
artifact_ok <- all(file.exists(current$weight_path)) &&
  all(vapply(seq_len(nrow(current)), function(i) {
    identical(
      digest::digest(file = current$weight_path[[i]], algo = "sha256"),
      current$weight_sha256[[i]])
  }, logical(1)))
balance_ok <- all(current$max_balanced_smd <= 0.10 + 1e-8)

quote_paths <- function(paths) {
  paste(vapply(
    normalizePath(paths, winslash = "/", mustWork = TRUE),
    function(path) as.character(DBI::dbQuoteString(con, path)),
    character(1)), collapse = ",")
}
base_sql <- sprintf(
  "read_parquet(%s)",
  DBI::dbQuoteString(con, normalizePath(
    BASE_HANDOFF_PATH, winslash = "/", mustWork = TRUE)))

handoff_rows <- list()
for (variant in settings$variants) {
  variant_rows <- current[current$variant == variant, , drop = FALSE]
  raw_sql <- sprintf(
    "read_parquet([%s])", quote_paths(variant_rows$weight_path))
  handoff_dir <- file.path(
    AUDIT_ROOT, "ROBUSTNESS_RELEASE_1993", paste0(
      "P5C_P6_HANDOFF_", toupper(variant)))
  dir.create(handoff_dir, recursive = TRUE, showWarnings = FALSE)
  handoff_path <- file.path(
    handoff_dir, "p5c_p6_primary_weighted_roster.parquet")
  temp <- paste0(handoff_path, ".tmp.parquet")
  if (file.exists(temp)) file.remove(temp)
  DBI::dbExecute(con, sprintf(
    "COPY (
       SELECT b.* REPLACE (CAST(w.final_weight AS DOUBLE) AS weight)
       FROM %s b
       JOIN %s w USING (roster_row_id)
       ORDER BY b.cohort,b.deal_id,b.arm,b.codinv,b.roster_row_id
     ) TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
    base_sql, raw_sql, DBI::dbQuoteString(con, temp)))
  if (file.exists(handoff_path)) file.remove(handoff_path)
  if (!file.rename(temp, handoff_path)) {
    stop("Could not publish Package 1 handoff for ", variant)
  }

  handoff_sql <- sprintf(
    "read_parquet(%s)", DBI::dbQuoteString(con, normalizePath(
      handoff_path, winslash = "/", mustWork = TRUE)))
  checks <- DBI::dbGetQuery(con, sprintf(
    "WITH b AS (SELECT * FROM %s),
          h AS (SELECT * FROM %s),
          mass AS (
            SELECT cohort,
              ABS(SUM(weight) FILTER (WHERE arm='treated') -
                  SUM(weight) FILTER (WHERE arm='control')) AS gap
            FROM h GROUP BY cohort
          )
     SELECT
       (SELECT COUNT(*) FROM h) AS roster_rows,
       (SELECT COUNT(*)-COUNT(DISTINCT roster_row_id) FROM h)
         AS duplicate_ids,
       (SELECT COUNT(*) FROM b ANTI JOIN h USING(roster_row_id))
         AS base_only,
       (SELECT COUNT(*) FROM h ANTI JOIN b USING(roster_row_id))
         AS handoff_only,
       (SELECT COUNT(*) FROM h
        WHERE NOT isfinite(weight) OR weight<=0) AS invalid_weights,
       (SELECT COUNT(*) FROM h JOIN b USING(roster_row_id)
        WHERE h.arm='treated' AND ABS(h.weight-b.weight)>1e-10)
         AS changed_treated_weights,
       (SELECT MAX(gap) FROM mass) AS max_mass_gap",
    base_sql, handoff_sql))
  handoff_pass <- checks$roster_rows == 512625 &&
    checks$duplicate_ids == 0 && checks$base_only == 0 &&
    checks$handoff_only == 0 && checks$invalid_weights == 0 &&
    checks$changed_treated_weights == 0 &&
    checks$max_mass_gap <= 1e-8
  certification <- data.frame(
    check = c(
      "roster_rows", "duplicate_ids", "base_only", "handoff_only",
      "invalid_weights", "changed_treated_weights", "max_mass_gap"),
    observed = as.character(unlist(checks[1, ])),
    expected = c("512625", "0", "0", "0", "0", "0", "<=1e-8"),
    pass = c(
      checks$roster_rows == 512625,
      checks$duplicate_ids == 0,
      checks$base_only == 0,
      checks$handoff_only == 0,
      checks$invalid_weights == 0,
      checks$changed_treated_weights == 0,
      checks$max_mass_gap <= 1e-8),
    stringsAsFactors = FALSE)
  atomic_csv(
    certification,
    file.path(handoff_dir, "p5c_p6_roster_certification.csv"))
  manifest <- data.frame(
    roster_sha256 = digest::digest(
      file = handoff_path, algo = "sha256"),
    roster_rows = checks$roster_rows,
    p5a_design_hash = base_handoff_manifest$p5a_design_hash,
    certification_pass = handoff_pass,
    production_freeze_hash = source_sha[["freeze"]],
    handoff_source_sha256 = source_sha[["runner"]],
    p5c_execution_hash = execution_hash,
    p5c_variant = variant,
    source_p5a_roster_sha256 =
      base_handoff_manifest$source_p5a_roster_sha256,
    stringsAsFactors = FALSE)
  atomic_csv(
    manifest,
    file.path(handoff_dir, "p5c_p6_roster_manifest.csv"))
  handoff_rows[[variant]] <- data.frame(
    variant = variant,
    path = normalizePath(
      handoff_path, winslash = "/", mustWork = TRUE),
    manifest_path = normalizePath(
      file.path(handoff_dir, "p5c_p6_roster_manifest.csv"),
      winslash = "/", mustWork = TRUE),
    roster_sha256 = manifest$roster_sha256,
    certification_pass = handoff_pass,
    stringsAsFactors = FALSE)
}

grid_certification <- data.frame(
  version = settings$version,
  execution_hash = execution_hash,
  expected_new_cells = nrow(expected),
  observed_new_cells = nrow(current),
  complete = complete,
  all_feasible = all(current$feasible),
  artifacts_valid = artifact_ok,
  balance_valid = balance_ok,
  all_handoffs_pass = all(vapply(
    handoff_rows, function(x) x$certification_pass, logical(1))),
  all_pass = complete && all(current$feasible) &&
    artifact_ok && balance_ok &&
    all(vapply(handoff_rows, function(x) x$certification_pass, logical(1))),
  freeze_sha256 = source_sha[["freeze"]],
  runner_sha256 = source_sha[["runner"]],
  certified_at = as.character(Sys.time()),
  stringsAsFactors = FALSE)
atomic_csv(
  grid_certification,
  file.path(OUTPUT_DIR, "package1_loyo_grid_certification.csv"))
atomic_csv(
  do.call(rbind, handoff_rows),
  file.path(OUTPUT_DIR, "package1_loyo_handoff_manifest.csv"))
atomic_csv(
  data.frame(
    source = names(source_paths),
    path = unname(normalizePath(
      source_paths, winslash = "/", mustWork = TRUE)),
    sha256 = unname(source_sha),
    stringsAsFactors = FALSE),
  file.path(OUTPUT_DIR, "package1_loyo_source_manifest.csv"))

print(grid_certification)
if (!grid_certification$all_pass) {
  stop("Package 1 LOYO grid certification failed")
}
