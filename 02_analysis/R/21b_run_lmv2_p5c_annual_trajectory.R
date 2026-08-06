# ============================================================================
# P5c annual-trajectory probe and production runner
# ============================================================================
# Reweights the finalized P5a support roster. It never rebuilds or changes
# donor admissibility and never reads post-treatment outcomes.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, required = TRUE, default = NA_character_) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) {
    if (required) stop("Missing --", name, "=...")
    return(default)
  }
  sub(paste0("^--", name, "="), "", hit[[1]])
}

mode <- read_arg("mode")
if (!mode %in% c(
    "probe", "production", "placebo", "equal-deal", "certify")) {
  stop(
    "--mode= must be probe, production, placebo, equal-deal, or certify")
}
db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
source_manifest_path <- normalizePath(
  read_arg("weight-manifest"), winslash = "/", mustWork = TRUE)
audit_root <- normalizePath(
  read_arg("audit-root"), winslash = "/", mustWork = FALSE)
p6_panel_dir <- read_arg(
  "p6-panel-dir", required = FALSE, default = NA_character_)
if (!is.na(p6_panel_dir)) {
  p6_panel_dir <- normalizePath(
    p6_panel_dir, winslash = "/", mustWork = TRUE)
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(
  BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path(BASE, "R", "18j_lmv2_p5_newton_solver.R"))
source(file.path(
  BASE, "R", "21a_lmv2_p5c_annual_trajectory_config.R"))
source(file.path(
  BASE, "R", "21d_lmv2_p5c_provenance_lock.R"))
lmv2_install_p5_newton_solver()
`%||%` <- function(a, b) if (is.null(a)) b else a

if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Package digest is required")
}
dir.create(audit_root, recursive = TRUE, showWarnings = FALSE)
lmv2_p5c_assert_provenance(source_manifest_path)
execution_hash <- lmv2_p5c_execution_hash(source_manifest_path)

atomic_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  utils::write.csv(x, tmp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) {
    stop("Could not atomically publish ", path)
  }
  invisible(path)
}

atomic_write_parquet <- function(con, x, path, order_by) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.parquet")
  if (file.exists(tmp)) file.remove(tmp)
  duckdb::duckdb_register(con, "lmv2_p5c_write_rows", x)
  on.exit(try(
    duckdb::duckdb_unregister(con, "lmv2_p5c_write_rows"),
    silent = TRUE), add = TRUE)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY (SELECT * FROM lmv2_p5c_write_rows ORDER BY %s)
       TO %s (FORMAT PARQUET, COMPRESSION ZSTD)",
      order_by, DBI::dbQuoteString(con, tmp)))
  duckdb::duckdb_unregister(con, "lmv2_p5c_write_rows")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) {
    stop("Could not atomically publish ", path)
  }
  invisible(path)
}

append_checkpoint <- function(row, path, keys) {
  old <- if (file.exists(path)) {
    utils::read.csv(path, stringsAsFactors = FALSE)
  } else {
    row[FALSE, , drop = FALSE]
  }
  if (nrow(old)) {
    old_key <- do.call(
      paste, c(old[keys], sep = "\r"))
    row_key <- do.call(
      paste, c(row[keys], sep = "\r"))
    old <- old[old_key != row_key, , drop = FALSE]
  }
  atomic_write_csv(rbind(old, row), path)
}

source_manifest <- utils::read.csv(
  source_manifest_path, stringsAsFactors = FALSE)
required_manifest <- c(
  "cohort", "scheme", "analysis_scope", "path", "checksum")
if (!all(required_manifest %in% names(source_manifest))) {
  stop("Source P5a manifest schema is incomplete")
}
source_primary <- source_manifest[
  source_manifest$scheme == "primary" &
    source_manifest$analysis_scope == "main" &
    source_manifest$estimand == "primary_full_supported", ,
  drop = FALSE]
if (anyDuplicated(source_primary$cohort)) {
  stop("Source P5a manifest has duplicate primary cohort rows")
}

read_source_roster <- function(con, cohort) {
  row <- source_primary[source_primary$cohort == cohort, , drop = FALSE]
  if (nrow(row) != 1L || !file.exists(row$path)) {
    stop("Missing finalized P5a primary roster for cohort ", cohort)
  }
  x <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT * FROM read_parquet(%s) ORDER BY roster_row_id",
      DBI::dbQuoteString(con, normalizePath(
        row$path, winslash = "/", mustWork = TRUE))))
  if (anyDuplicated(x$roster_row_id) ||
      any(!x$treated %in% c(0L, 1L))) {
    stop("Invalid P5a roster for cohort ", cohort)
  }
  list(rows = x, manifest = row)
}

recompute_base_weights <- function(x, scheme) {
  if (!scheme %in% LMV2_P5C$schemes) {
    stop("Unknown scheme: ", scheme)
  }
  n_t <- stats::aggregate(
    treated ~ cohort + deal_id,
    data = x[x$treated == 1L, ], FUN = length)
  names(n_t)[3] <- "n_treated"
  n_c <- stats::aggregate(
    treated ~ cohort + deal_id,
    data = x[x$treated == 0L, ], FUN = length)
  names(n_c)[3] <- "n_control"
  deal_counts <- merge(
    n_t, n_c, by = c("cohort", "deal_id"), all = TRUE)
  if (anyNA(deal_counts) ||
      any(deal_counts$n_treated <= 0) ||
      any(deal_counts$n_control <= 0)) {
    stop("Treated/control deal sets differ in source roster")
  }
  idx <- match(
    paste(x$cohort, x$deal_id),
    paste(deal_counts$cohort, deal_counts$deal_id))
  if (identical(scheme, "primary")) {
    ifelse(
      x$treated == 1L, 1,
      deal_counts$n_treated[idx] / deal_counts$n_control[idx])
  } else {
    ifelse(
      x$treated == 1L,
      1 / deal_counts$n_treated[idx],
      1 / deal_counts$n_control[idx])
  }
}

attach_annual_and_retained_covariates <- function(con, source_rows) {
  keys <- source_rows[c(
    "roster_row_id", "cohort", "deal_id", "codinv", "treated",
    "group_id")]
  duckdb::duckdb_register(con, "lmv2_p5c_roster_keys", keys)
  on.exit(try(
    duckdb::duckdb_unregister(con, "lmv2_p5c_roster_keys"),
    silent = TRUE), add = TRUE)

  annual_terms <- unlist(lapply(5:1, function(k) c(
    sprintf(
      "COALESCE(MAX(CASE WHEN iy.year=r.cohort-%d
       THEN iy.patent_count END),0)::DOUBLE AS patent_count_m%d",
      k, k),
    sprintf(
      "CASE WHEN COALESCE(MAX(CASE WHEN iy.year=r.cohort-%d
       THEN iy.patent_count END),0)>0 THEN 1.0 ELSE 0.0 END
       AS active_patenting_m%d",
      k, k))))
  annual <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT r.roster_row_id,
              %s,
              MAX(s.patent_count_5y)::DOUBLE AS patent_count_5y_check,
              MAX(s.cohort-1-s.career_first_year)::DOUBLE AS career_age
       FROM lmv2_p5c_roster_keys r
       LEFT JOIN lmv2_p3_inventor_year_typed iy
         ON iy.codinv=CAST(r.codinv AS BIGINT)
        AND iy.year BETWEEN r.cohort-5 AND r.cohort-1
       LEFT JOIN lmv2_p3_inventor_cohort_stats s
         ON s.cohort=r.cohort
        AND s.codinv=CAST(r.codinv AS BIGINT)
       GROUP BY r.roster_row_id",
      paste(annual_terms, collapse = ",\n")))
  if (nrow(annual) != nrow(source_rows) ||
      anyDuplicated(annual$roster_row_id)) {
    stop("Annual covariate attachment changed roster grain")
  }
  annual_sum <- rowSums(annual[LMV2_P5C$count_variables])
  if (any(abs(annual_sum - annual$patent_count_5y_check) > 1e-8)) {
    stop("Annual patent counts do not reconstruct certified five-year stock")
  }

  treated_extra <- DBI::dbGetQuery(
    con,
    "SELECT r.roster_row_id,
            t.focal_group_exclusivity::DOUBLE
              AS focal_group_exclusivity
     FROM lmv2_p5c_roster_keys r
     JOIN lmv2_p3_treated_inventor_units t
       ON t.cohort=r.cohort
      AND t.deal_id=r.deal_id
      AND t.codinv=CAST(r.codinv AS BIGINT)
     WHERE r.treated=1")
  control_keys <- unique(data.frame(
    cohort = keys$cohort[keys$treated == 0L],
    codinv = keys$codinv[keys$treated == 0L],
    focal_group = keys$group_id[keys$treated == 0L]))
  control_extra <- lmv2_build_control_focal_covariates(
    con, control_keys)
  control_map <- merge(
    keys[keys$treated == 0L,
         c("roster_row_id", "cohort", "codinv", "group_id")],
    control_extra,
    by.x = c("cohort", "codinv", "group_id"),
    by.y = c("cohort", "codinv", "focal_group"),
    all.x = TRUE, sort = FALSE)
  focal <- rbind(
    treated_extra[c(
      "roster_row_id", "focal_group_exclusivity")],
    control_map[c(
      "roster_row_id", "focal_group_exclusivity")])
  if (nrow(focal) != nrow(source_rows) ||
      anyDuplicated(focal$roster_row_id) ||
      any(!is.finite(focal$focal_group_exclusivity))) {
    stop("Focal-group exclusivity attachment is incomplete")
  }

  firm <- DBI::dbGetQuery(
    con,
    "SELECT r.roster_row_id,
            MAX(f.log_patent_stock_5y)::DOUBLE
              AS firm_log_patent_stock_5y,
            MAX(f.log_inventor_count_5y)::DOUBLE
              AS firm_log_inventor_count_5y,
            MAX(f.patent_trajectory)::DOUBLE
              AS firm_patent_trajectory,
            COUNT(*)::INTEGER AS firm_match_count
     FROM lmv2_p5c_roster_keys r
     JOIN lmv2_p3_firm_units f
       ON f.cohort=r.cohort
      AND f.id_group=CAST(r.group_id AS BIGINT)
      AND (
        (r.treated=1 AND f.role='treated' AND f.deal_id=r.deal_id)
        OR
        (r.treated=0 AND f.role='control')
      )
     GROUP BY r.roster_row_id")
  if (nrow(firm) != nrow(source_rows) ||
      anyDuplicated(firm$roster_row_id) ||
      any(firm$firm_match_count != 1L)) {
    stop("Firm covariate attachment is not one-to-one")
  }

  out <- source_rows
  annual <- annual[match(out$roster_row_id, annual$roster_row_id), ]
  focal <- focal[match(out$roster_row_id, focal$roster_row_id), ]
  firm <- firm[match(out$roster_row_id, firm$roster_row_id), ]
  for (v in c(
    LMV2_P5C$count_variables,
    LMV2_P5C$active_variables,
    "career_age")) {
    out[[v]] <- annual[[v]]
  }
  out$focal_group_exclusivity <- focal$focal_group_exclusivity
  for (v in LMV2_P5C$firm_variables) out[[v]] <- firm[[v]]
  valid_variants <- c(
    LMV2_P5C$probe_variants,
    LMV2_P5C$placebo_variants)
  all_vars <- unique(unlist(lapply(
    valid_variants, lmv2_p5c_balance_variables)))
  if (any(vapply(
    out[all_vars], function(z) any(!is.finite(z)), logical(1)))) {
    stop("P5c roster has non-finite balance variables")
  }
  out
}

certify_against_p6_panel <- function(con, roster, cohort) {
  if (is.na(p6_panel_dir)) return(invisible(TRUE))
  path <- file.path(
    p6_panel_dir,
    sprintf("lmv2_event_panel_c%d.parquet", cohort))
  if (!file.exists(path)) {
    stop("Certified P6 panel is missing for cohort ", cohort)
  }
  p6 <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT roster_row_id,event_time,
              patent_count::DOUBLE AS patent_count,
              active_patenting::DOUBLE AS active_patenting
       FROM read_parquet(%s)
       WHERE event_time BETWEEN -5 AND -1",
      DBI::dbQuoteString(
        con, normalizePath(path, winslash = "/", mustWork = TRUE))))
  if (nrow(p6) != nrow(roster) * 5L ||
      anyDuplicated(p6[c("roster_row_id", "event_time")])) {
    stop("P6 five-period panel grain mismatch for cohort ", cohort)
  }
  for (k in 5:1) {
    z <- p6[p6$event_time == -k, ]
    z <- z[match(roster$roster_row_id, z$roster_row_id), ]
    if (any(z$patent_count != roster[[paste0("patent_count_m", k)]]) ||
        any(z$active_patenting !=
              roster[[paste0("active_patenting_m", k)]])) {
      stop("P3/P6 annual outcome mismatch at t=-", k,
           " for cohort ", cohort)
    }
  }
  invisible(TRUE)
}

build_solver_roster <- function(x, scheme) {
  base_weight <- recompute_base_weights(x, scheme)
  if (identical(scheme, "primary") &&
      max(abs(base_weight - x$base_weight)) > 1e-10) {
    stop("Recomputed primary base weights disagree with P5a")
  }
  data.frame(
    D = as.integer(x$treated),
    cohort = as.integer(x$cohort),
    deal_id = as.integer(x$deal_id),
    treated_codinv = ifelse(
      x$treated == 1L, x$codinv, NA_real_),
    control_codinv = ifelse(
      x$treated == 0L, x$codinv, NA_real_),
    control_group = ifelse(
      x$treated == 0L, x$group_id, NA_real_),
    base_weight = base_weight,
    x[unique(unlist(lapply(
      c(
        LMV2_P5C$probe_variants,
        LMV2_P5C$placebo_variants),
      lmv2_p5c_balance_variables)))],
    check.names = FALSE)
}

balance_table_for <- function(roster, weight, variables, stage) {
  std <- lmv2_ebal_standardize_cohort(variables, roster)
  use_vars <- setdiff(variables, std$zero_variance)
  x <- if (length(use_vars)) {
    lmv2_ebal_covariate_balance(
      use_vars, std$data, roster$D, weight)
  } else {
    data.frame(
      variable = character(), treated_mean = numeric(),
      control_mean = numeric(), difference = numeric(),
      abs_difference = numeric())
  }
  x$stage <- stage
  x
}

run_cell <- function(
    con, enriched, source_info, cohort, scheme, variant, output_dir) {
  cell_start <- Sys.time()
  roster <- build_solver_roster(enriched, scheme)
  variables <- lmv2_p5c_balance_variables(variant)
  inv_vars <- setdiff(variables, LMV2_P5C$firm_variables)
  hierarchy <- lmv2_ebal_cohort_feasibility_hierarchy(
    roster = roster,
    n_eligible_treated = sum(roster$D == 1L),
    inv_vars = inv_vars,
    firm_vars = LMV2_P5C$firm_variables)
  feasible <- hierarchy$mode %in% c(
    "exact_ebal", "optweight_0.05", "optweight_0.10") &&
    !is.null(hierarchy$result)

  before <- balance_table_for(
    roster, roster$base_weight, variables, "before")
  final_weight <- if (feasible) {
    hierarchy$result$weight
  } else {
    rep(NA_real_, nrow(roster))
  }
  after <- if (feasible) {
    balance_table_for(roster, final_weight, variables, "after")
  } else {
    transform(before, stage = "after", treated_mean = NA_real_,
              control_mean = NA_real_, difference = NA_real_,
              abs_difference = NA_real_)
  }
  active_after <- if (feasible) {
    balance_table_for(
      roster, final_weight, LMV2_P5C$active_variables,
      "active_diagnostic_after")
  } else {
    NULL
  }
  balance <- rbind(before, after, active_after)
  balance$cohort <- cohort
  balance$scheme <- scheme
  balance$variant <- variant

  cell_stub <- sprintf(
    "c%d_%s_%s_%s",
    cohort, scheme, variant, substr(execution_hash, 1, 12))
  balance_path <- file.path(
    output_dir, "balance", paste0(cell_stub, ".csv"))
  atomic_write_csv(balance, balance_path)

  weight_path <- NA_character_
  if (feasible) {
    treated_idx <- roster$D == 1L
    control_idx <- !treated_idx
    lmv2_ebal_assert_final_treated_weights_equal_base(
      final_weight[treated_idx], roster$base_weight[treated_idx])
    lmv2_ebal_assert_masses_agree(
      final_weight[treated_idx], final_weight[control_idx],
      scheme = scheme,
      n_retained_deals = length(unique(roster$deal_id[treated_idx])))
    weight_rows <- enriched
    weight_rows$scheme <- scheme
    weight_rows$variant <- variant
    weight_rows$p5a_final_weight <- enriched$final_weight
    weight_rows$base_weight <- roster$base_weight
    weight_rows$entropy_tilt_normalized <-
      final_weight / roster$base_weight
    weight_rows$final_weight <- final_weight
    weight_rows$feasibility_mode <- hierarchy$mode
    weight_rows$feasibility_tier <- hierarchy$tier
    weight_rows$p5c_execution_hash <- execution_hash
    weight_rows$source_p5a_checksum <- source_info$checksum
    keep <- c(
      "roster_row_id", "cohort", "deal_id", "codinv", "treated",
      "group_id", "target_group", "control_group", "scheme", "variant",
      "base_weight", "entropy_tilt_normalized", "final_weight",
      "p5a_final_weight", LMV2_P5C$count_variables,
      LMV2_P5C$active_variables,
      LMV2_P5C$retained_inventor_variables,
      LMV2_P5C$firm_variables,
      "feasibility_mode", "feasibility_tier",
      "p5c_execution_hash", "source_p5a_checksum")
    weight_rows <- weight_rows[keep]
    weight_path <- file.path(
      output_dir, "weights", paste0(cell_stub, ".parquet"))
    atomic_write_parquet(
      con, weight_rows, weight_path, "roster_row_id")
  }

  count_after <- after[
    after$variable %in% LMV2_P5C$count_variables, ,
    drop = FALSE]
  active_diag <- if (feasible) active_after else
    data.frame(abs_difference = NA_real_)
  ess_ratio <- if (feasible) hierarchy$ess_gate$ess_ratio else NA_real_
  ess_info <- if (feasible) hierarchy$ess_info else NULL
  data.frame(
    version = LMV2_P5C_VERSION,
    execution_hash = execution_hash,
    cohort = cohort,
    scheme = scheme,
    variant = variant,
    feasible = feasible,
    mode = hierarchy$mode,
    tier = hierarchy$tier %||% NA_character_,
    n_treated = sum(roster$D == 1L),
    n_control_rows = sum(roster$D == 0L),
    n_unique_control_inventors =
      length(unique(roster$control_codinv[roster$D == 0L])),
    reuse_adjusted_ess = if (feasible) {
      ess_info$reuse_adjusted_ess
    } else NA_real_,
    reuse_adjusted_ess_ratio = ess_ratio,
    stack_row_ess = if (feasible) ess_info$stack_row_ess else NA_real_,
    reuse_adjusted_max_share = if (feasible) {
      ess_info$reuse_adjusted_concentration$max_share
    } else NA_real_,
    reuse_adjusted_top5_share = if (feasible) {
      ess_info$reuse_adjusted_concentration$top5_share
    } else NA_real_,
    max_count_smd_after = if (feasible && nrow(count_after)) {
      max(count_after$abs_difference)
    } else NA_real_,
    max_active_smd_after = if (feasible && nrow(active_diag)) {
      max(active_diag$abs_difference)
    } else NA_real_,
    max_all_balanced_smd_after = if (feasible && nrow(after)) {
      max(after$abs_difference)
    } else NA_real_,
    weight_path = weight_path,
    weight_sha256 = if (feasible) {
      digest::digest(file = weight_path, algo = "sha256")
    } else NA_character_,
    balance_path = balance_path,
    source_p5a_path = source_info$path,
    source_p5a_checksum = source_info$checksum,
    elapsed_seconds = as.numeric(
      difftime(Sys.time(), cell_start, units = "secs")),
    completed_at = as.character(Sys.time()),
    stringsAsFactors = FALSE)
}

run_cells <- function(cohorts, schemes, variants, output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  diagnostics_path <- file.path(
    output_dir, "p5c_cell_diagnostics.csv")
  con <- DBI::dbConnect(
    duckdb::duckdb(), db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "PRAGMA threads=4")
  DBI::dbExecute(con, "PRAGMA memory_limit='8GB'")

  for (cohort in cohorts) {
    source <- read_source_roster(con, cohort)
    enriched <- attach_annual_and_retained_covariates(
      con, source$rows)
    certify_against_p6_panel(con, enriched, cohort)
    message(
      "P5c cohort ", cohort, ": ",
      nrow(enriched), " frozen roster rows")
    for (scheme in schemes) {
      for (variant in variants) {
        existing <- if (file.exists(diagnostics_path)) {
          utils::read.csv(
            diagnostics_path, stringsAsFactors = FALSE)
        } else NULL
        ready <- !is.null(existing) && any(
          existing$execution_hash == execution_hash &
            existing$cohort == cohort &
            existing$scheme == scheme &
            existing$variant == variant &
            (
              !existing$feasible |
                file.exists(existing$weight_path)
            ))
        if (ready) {
          message(
            "  reuse ", scheme, " / ", variant)
          next
        }
        message(
          "  solve ", scheme, " / ", variant)
        row <- run_cell(
          con, enriched, source$manifest,
          cohort, scheme, variant, output_dir)
        append_checkpoint(
          row, diagnostics_path,
          c("execution_hash", "cohort", "scheme", "variant"))
        message(
          "    ", row$mode,
          "; ESS ratio=",
          format(row$reuse_adjusted_ess_ratio, digits = 4),
          "; max count SMD=",
          format(row$max_count_smd_after, digits = 3))
      }
    }
    rm(source, enriched)
    gc(FALSE)
  }
  invisible(diagnostics_path)
}

certify_output <- function(output_dir, cohorts, schemes, variants) {
  diagnostics_path <- file.path(
    output_dir, "p5c_cell_diagnostics.csv")
  if (!file.exists(diagnostics_path)) {
    stop("P5c diagnostics do not exist: ", diagnostics_path)
  }
  diagnostics <- utils::read.csv(
    diagnostics_path, stringsAsFactors = FALSE)
  expected <- expand.grid(
    cohort = cohorts, scheme = schemes, variant = variants,
    stringsAsFactors = FALSE)
  expected$execution_hash <- execution_hash
  key <- function(x) paste(
    x$execution_hash, x$cohort, x$scheme, x$variant, sep = "\r")
  complete <- all(key(expected) %in% key(diagnostics))
  current <- diagnostics[
    diagnostics$execution_hash == execution_hash &
      diagnostics$cohort %in% cohorts &
      diagnostics$scheme %in% schemes &
    diagnostics$variant %in% variants, ,
    drop = FALSE]
  feasible_rows <- current[current$feasible, , drop = FALSE]
  artifact_ok <- !nrow(feasible_rows) || (
    all(file.exists(feasible_rows$weight_path)) &&
      all(vapply(
        feasible_rows$weight_path,
        function(p) digest::digest(
          file = p, algo = "sha256"),
        character(1)) == feasible_rows$weight_sha256))
  balance_ok <- all(
    !current$feasible |
      current$max_all_balanced_smd_after <= 0.10 + 1e-8)
  cert <- data.frame(
    version = LMV2_P5C_VERSION,
    execution_hash = execution_hash,
    config_sha256 = digest::digest(
      file = file.path(
        BASE, "R", "21a_lmv2_p5c_annual_trajectory_config.R"),
      algo = "sha256"),
    runner_sha256 = digest::digest(
      file = file.path(
        BASE, "R", "21b_run_lmv2_p5c_annual_trajectory.R"),
      algo = "sha256"),
    freeze_sha256 = digest::digest(
      file = LMV2_P5C$freeze_note, algo = "sha256"),
    source_manifest_sha256 = digest::digest(
      file = source_manifest_path, algo = "sha256"),
    expected_cells = nrow(expected),
    observed_cells = nrow(current),
    complete = complete,
    artifacts_valid = artifact_ok,
    realized_balance_valid = balance_ok,
    all_pass = complete && artifact_ok && balance_ok,
    certified_at = as.character(Sys.time()),
    stringsAsFactors = FALSE)
  atomic_write_csv(
    cert, file.path(output_dir, "p5c_certification.csv"))
  if (!cert$all_pass) stop("P5c certification failed")
  cert
}

probe_dir <- file.path(audit_root, "probe")
production_dir <- file.path(audit_root, "production")
placebo_dir <- file.path(audit_root, "placebo")
equal_deal_dir <- file.path(audit_root, "equal_deal_other_cohorts")

if (identical(mode, "probe")) {
  diagnostics_path <- run_cells(
    LMV2_P5C$probe_cohorts,
    LMV2_P5C$probe_schemes,
    LMV2_P5C$probe_variants,
    probe_dir)
  certify_output(
    probe_dir, LMV2_P5C$probe_cohorts,
    LMV2_P5C$probe_schemes, LMV2_P5C$probe_variants)
  diagnostics <- utils::read.csv(
    diagnostics_path, stringsAsFactors = FALSE)
  primary <- diagnostics[
    diagnostics$execution_hash == execution_hash &
      diagnostics$scheme == "primary", ,
    drop = FALSE]
  count_only <- primary[
    primary$variant == "count_only", , drop = FALSE]
  count_active <- primary[
    primary$variant == "count_active", , drop = FALSE]
  key <- function(x) paste(x$cohort, x$scheme, sep = "\r")
  count_active <- count_active[
    match(key(count_only), key(count_active)), , drop = FALSE]
  gate <- data.frame(
    production_variant = LMV2_P5C$production_variant,
    active_all_cells_feasible = all(count_active$feasible),
    active_all_cells_pass_ess_floor = all(
      count_active$reuse_adjusted_ess_ratio >=
        LMV2_P5C$selection$minimum_reuse_adjusted_ess_ratio),
    active_all_cells_pass_ess_loss_rule = all(
      count_only$reuse_adjusted_ess_ratio -
        count_active$reuse_adjusted_ess_ratio <=
        LMV2_P5C$selection$maximum_absolute_ess_ratio_loss),
    active_all_cells_pass_concentration_rule = all(
      count_active$reuse_adjusted_max_share <=
        count_only$reuse_adjusted_max_share *
        (1 + LMV2_P5C$selection$
           maximum_relative_max_share_increase) + 1e-12),
    version = LMV2_P5C_VERSION,
    execution_hash = execution_hash,
    checked_at = as.character(Sys.time()),
    stringsAsFactors = FALSE)
  gate$all_pass <- with(
    gate,
    active_all_cells_feasible &
      active_all_cells_pass_ess_floor &
      active_all_cells_pass_ess_loss_rule &
      active_all_cells_pass_concentration_rule)
  atomic_write_csv(
    gate, file.path(probe_dir, "p5c_production_gate.csv"))
  if (!gate$all_pass) {
    stop("Fixed count_active production specification failed its gate")
  }
  print(gate)
} else if (identical(mode, "production")) {
  gate_path <- file.path(probe_dir, "p5c_production_gate.csv")
  if (!file.exists(gate_path)) {
    stop("Run --mode=probe before production")
  }
  gate <- utils::read.csv(
    gate_path, stringsAsFactors = FALSE)
  if (nrow(gate) != 1L ||
      gate$execution_hash != execution_hash ||
      gate$production_variant != LMV2_P5C$production_variant ||
      !isTRUE(gate$all_pass)) {
    stop("P5c production gate is invalid, failed, or stale")
  }
  run_cells(
    LMV2_P5C$cohorts, LMV2_P5C$production_schemes,
    LMV2_P5C$production_variant, production_dir)
  certify_output(
    production_dir, LMV2_P5C$cohorts,
    LMV2_P5C$production_schemes, LMV2_P5C$production_variant)
} else if (identical(mode, "placebo")) {
  run_cells(
    LMV2_P5C$cohorts, LMV2_P5C$production_schemes,
    LMV2_P5C$placebo_variants, placebo_dir)
  certify_output(
    placebo_dir, LMV2_P5C$cohorts,
    LMV2_P5C$production_schemes, LMV2_P5C$placebo_variants)
} else if (identical(mode, "equal-deal")) {
  cohorts <- setdiff(
    LMV2_P5C$cohorts, LMV2_P5C$probe_cohorts)
  run_cells(
    cohorts, "equal_deal",
    LMV2_P5C$production_variant, equal_deal_dir)
  certify_output(
    equal_deal_dir, cohorts, "equal_deal",
    LMV2_P5C$production_variant)
} else {
  certify_output(
    probe_dir, LMV2_P5C$probe_cohorts,
    LMV2_P5C$probe_schemes, LMV2_P5C$probe_variants)
  certify_output(
    production_dir, LMV2_P5C$cohorts,
    LMV2_P5C$production_schemes, LMV2_P5C$production_variant)
  certify_output(
    placebo_dir, LMV2_P5C$cohorts,
    LMV2_P5C$production_schemes, LMV2_P5C$placebo_variants)
  certify_output(
    equal_deal_dir,
    setdiff(LMV2_P5C$cohorts, LMV2_P5C$probe_cohorts),
    "equal_deal", LMV2_P5C$production_variant)
}
