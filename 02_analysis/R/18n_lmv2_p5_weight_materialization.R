# ============================================================================
# P5 row-level final-weight materialization
# ============================================================================

LMV2_P5_WEIGHT_VERSION <- "lmv2_p5_weight_materialization_v1"

lmv2_p5_weight_profile_hash <- function(
    roster, cohort, caliper, profile, universe, scheme, analysis_scope,
    dealsim_tercile, execution_hash) {
  keys <- data.frame(
    D = roster$D,
    deal_id = roster$deal_id,
    treated_codinv = roster$treated_codinv,
    control_codinv = roster$control_codinv,
    control_group = roster$control_group)
  digest::digest(
    list(
      version = LMV2_P5_WEIGHT_VERSION,
      cohort = cohort,
      caliper = caliper,
      profile = profile,
      universe = universe,
      scheme = scheme,
      analysis_scope = analysis_scope,
      dealsim_tercile = dealsim_tercile,
      execution_hash = execution_hash,
      keys = keys),
    algo = "sha256")
}

lmv2_p5_weight_path <- function(
    audit_dir, cohort, scheme, analysis_scope, dealsim_tercile,
    profile_hash) {
  scope_dir <- if (identical(analysis_scope, "main")) {
    file.path(audit_dir, "weights", "main")
  } else {
    file.path(
      audit_dir, "weights", "dealsim",
      sprintf("tercile_%d", as.integer(dealsim_tercile)))
  }
  file.path(
    scope_dir,
    sprintf(
      "weights_%d_%s_%s.parquet",
      as.integer(cohort), scheme, substr(profile_hash, 1, 12)))
}

lmv2_p5_materialize_weight_context <- function(
    context, audit_dir, execution_hash, analysis_scope = "main",
    dealsim_tercile = NA_integer_) {
  required <- c(
    "con", "roster", "result", "diagnostic", "deal_balance",
    "cohort", "caliper",
    "profile", "universe", "scheme", "target_group_by_deal")
  missing <- setdiff(required, names(context))
  if (length(missing)) {
    stop(
      "P5 weight callback is missing context fields: ",
      paste(missing, collapse = ", "))
  }

  roster <- context$roster
  result <- context$result
  diagnostic <- context$diagnostic
  if (nrow(roster) != length(result$weight)) {
    stop("P5 weight materialization: roster and final weights differ in length")
  }
  if (any(!is.finite(result$weight)) || any(result$weight <= 0)) {
    stop("P5 weight materialization: final weights must be finite and positive")
  }
  if (any(!is.finite(roster$base_weight)) ||
      any(roster$base_weight <= 0)) {
    stop("P5 weight materialization: base weights must be finite and positive")
  }

  target_map <- unique(
    context$target_group_by_deal[c("cohort", "deal_id", "target_group")])
  if (anyDuplicated(target_map[c("cohort", "deal_id")])) {
    stop("P5 weight materialization: target-group map is not unique by deal")
  }
  target_group <- target_map$target_group[
    match(
      paste(roster$cohort, roster$deal_id),
      paste(target_map$cohort, target_map$deal_id))]
  if (any(roster$D == 1L & is.na(target_group))) {
    stop("P5 weight materialization: treated row lacks target group")
  }

  codinv <- ifelse(
    roster$D == 1L, roster$treated_codinv, roster$control_codinv)
  group_id <- ifelse(
    roster$D == 1L, target_group, roster$control_group)
  row_id <- ifelse(
    roster$D == 1L,
    sprintf(
      "T:%d:%d:%s",
      as.integer(roster$cohort), as.integer(roster$deal_id),
      format(codinv, scientific = FALSE, trim = TRUE)),
    sprintf(
      "C:%d:%d:%s:%s",
      as.integer(roster$cohort), as.integer(roster$deal_id),
      format(codinv, scientific = FALSE, trim = TRUE),
      format(group_id, scientific = FALSE, trim = TRUE)))
  if (anyDuplicated(row_id)) {
    stop("P5 weight materialization: duplicate roster row IDs")
  }

  profile_hash <- lmv2_p5_weight_profile_hash(
    roster = roster,
    cohort = context$cohort,
    caliper = context$caliper,
    profile = context$profile,
    universe = context$universe,
    scheme = context$scheme,
    analysis_scope = analysis_scope,
    dealsim_tercile = dealsim_tercile,
    execution_hash = execution_hash)
  final_path <- lmv2_p5_weight_path(
    audit_dir, context$cohort, context$scheme, analysis_scope,
    dealsim_tercile, profile_hash)
  manifest_path <- file.path(audit_dir, "weights", "manifest.csv")
  match_cols <- c(
    "analysis_scope", "cohort", "dealsim_tercile_key", "scheme",
    "profile_hash", "execution_hash")
  tercile_key <- if (is.na(dealsim_tercile)) "__none__" else
    as.character(as.integer(dealsim_tercile))
  match_vals <- c(
    analysis_scope, context$cohort, tercile_key, context$scheme,
    profile_hash, execution_hash)
  weight_ready <- lmv2_manifest_has_valid_row(
    manifest_path, match_cols, match_vals, path_col = "path")
  deal_balance_ready <- lmv2_manifest_has_valid_row(
    manifest_path, match_cols, match_vals,
    path_col = "deal_balance_path",
    checksum_col = "deal_balance_checksum")
  if (weight_ready && deal_balance_ready) {
    return(invisible(final_path))
  }
  if (file.exists(final_path)) {
    stop(
      "P5 weight artifact exists without a matching valid manifest row: ",
      final_path)
  }

  weight_rows <- data.frame(
    roster_row_id = row_id,
    analysis_scope = analysis_scope,
    cohort = as.integer(roster$cohort),
    dealsim_tercile = if (is.na(dealsim_tercile)) {
      rep(NA_integer_, nrow(roster))
    } else {
      rep(as.integer(dealsim_tercile), nrow(roster))
    },
    deal_id = as.integer(roster$deal_id),
    codinv = as.numeric(codinv),
    treated = as.integer(roster$D),
    group_id = as.numeric(group_id),
    target_group = as.numeric(target_group),
    control_group = as.numeric(roster$control_group),
    scheme = context$scheme,
    base_weight = as.numeric(roster$base_weight),
    entropy_tilt_normalized = as.numeric(
      result$weight / roster$base_weight),
    final_weight = as.numeric(result$weight),
    solver = LMV2_P5_FINAL$selected$solver,
    feasibility_mode = as.character(diagnostic$mode),
    feasibility_tier = as.character(diagnostic$tier),
    universe = context$universe,
    profile = context$profile,
    stage1_caliper = as.numeric(context$caliper),
    stage2_caliper = as.numeric(STAGE2_CALIPER),
    technology_resolution =
      LMV2_P4_EBAL$stage_2$technology_resolution,
    support_profile_hash = profile_hash,
    execution_hash = execution_hash,
    stringsAsFactors = FALSE)

  treated_mass <- sum(weight_rows$final_weight[weight_rows$treated == 1L])
  control_mass <- sum(weight_rows$final_weight[weight_rows$treated == 0L])
  if (abs(treated_mass - control_mass) > 1e-6) {
    stop("P5 weight materialization: treated/control mass mismatch")
  }

  duckdb::duckdb_register(
    context$con, "lmv2_p5_weight_rows", weight_rows)
  on.exit(
    try(
      duckdb::duckdb_unregister(
        context$con, "lmv2_p5_weight_rows"),
      silent = TRUE),
    add = TRUE)
  write_result <- lmv2_write_atomic_parquet(
    context$con,
    "SELECT * FROM lmv2_p5_weight_rows ORDER BY roster_row_id",
    final_path,
    "roster_row_id")
  duckdb::duckdb_unregister(
    context$con, "lmv2_p5_weight_rows")

  deal_balance <- context$deal_balance
  if (anyDuplicated(deal_balance[c("cohort", "deal_id")])) {
    stop("P5 deal-balance materialization: duplicate deal key")
  }
  deal_balance$analysis_scope <- analysis_scope
  deal_balance$dealsim_tercile <- if (is.na(dealsim_tercile)) {
    NA_integer_
  } else {
    as.integer(dealsim_tercile)
  }
  deal_balance$scheme <- context$scheme
  deal_balance$universe <- context$universe
  deal_balance$profile <- context$profile
  deal_balance$stage1_caliper <- as.numeric(context$caliper)
  deal_balance$support_profile_hash <- profile_hash
  deal_balance$execution_hash <- execution_hash
  deal_balance_path <- file.path(
    dirname(final_path),
    sprintf(
      "deal_balance_%d_%s_%s.parquet",
      as.integer(context$cohort), context$scheme,
      substr(profile_hash, 1, 12)))
  if (file.exists(deal_balance_path)) {
    stop(
      "P5 deal-balance artifact exists without a matching valid manifest: ",
      deal_balance_path)
  }
  duckdb::duckdb_register(
    context$con, "lmv2_p5_deal_balance", deal_balance)
  deal_balance_result <- lmv2_write_atomic_parquet(
    context$con,
    "SELECT * FROM lmv2_p5_deal_balance ORDER BY cohort,deal_id",
    deal_balance_path,
    c("cohort", "deal_id"))
  duckdb::duckdb_unregister(
    context$con, "lmv2_p5_deal_balance")

  lmv2_append_manifest_row(
    manifest_path,
    data.frame(
      version = LMV2_P5_WEIGHT_VERSION,
      analysis_scope = analysis_scope,
      cohort = as.integer(context$cohort),
      dealsim_tercile_key = tercile_key,
      scheme = context$scheme,
      caliper = as.numeric(context$caliper),
      profile = context$profile,
      universe = context$universe,
      profile_hash = profile_hash,
      execution_hash = execution_hash,
      path = final_path,
      row_count = write_result$row_count,
      treated_rows = sum(weight_rows$treated == 1L),
      control_rows = sum(weight_rows$treated == 0L),
      treated_mass = treated_mass,
      control_mass = control_mass,
      checksum = write_result$checksum,
      deal_balance_path = deal_balance_result$path,
      deal_balance_rows = deal_balance_result$row_count,
      deal_balance_checksum = deal_balance_result$checksum,
      status = "complete",
      timestamp = as.character(Sys.time()),
      stringsAsFactors = FALSE))
  invisible(final_path)
}

lmv2_install_p5_weight_materializer <- function(
    audit_dir, execution_hash, analysis_scope = "main",
    dealsim_tercile = NA_integer_) {
  callback <- function(context) {
    lmv2_p5_materialize_weight_context(
      context = context,
      audit_dir = audit_dir,
      execution_hash = execution_hash,
      analysis_scope = analysis_scope,
      dealsim_tercile = dealsim_tercile)
  }
  assign(
    "LMV2_P5_WEIGHT_CALLBACK", callback,
    envir = .GlobalEnv)
  ready <- function(
      cohort, caliper, profile, universe, scheme, live_execution_hash) {
    manifest_path <- file.path(audit_dir, "weights", "manifest.csv")
    tercile_key <- if (is.na(dealsim_tercile)) "__none__" else
      as.character(as.integer(dealsim_tercile))
    weight_valid <- lmv2_manifest_has_valid_row(
      manifest_path,
      c(
        "analysis_scope", "cohort", "dealsim_tercile_key", "scheme",
        "caliper", "profile", "universe", "execution_hash"),
      c(
        analysis_scope, cohort, tercile_key, scheme, caliper, profile,
        universe, live_execution_hash),
      path_col = "path")
    deal_valid <- lmv2_manifest_has_valid_row(
      manifest_path,
      c(
        "analysis_scope", "cohort", "dealsim_tercile_key", "scheme",
        "caliper", "profile", "universe", "execution_hash"),
      c(
        analysis_scope, cohort, tercile_key, scheme, caliper, profile,
        universe, live_execution_hash),
      path_col = "deal_balance_path",
      checksum_col = "deal_balance_checksum")
    weight_valid && deal_valid
  }
  assign(
    "LMV2_P5_WEIGHT_READY", ready,
    envir = .GlobalEnv)
  invisible(TRUE)
}
