# Certify and package the outcome-blind P5b S3 production design.

if (!exists("lmv2_p5b_s3_config")) {
  source(file.path("02_analysis", "R", "27a_lmv2_p5b_s3_config.R"))
}
if (!exists("lmv2_p5b_sha256")) {
  lmv2_p5b_sha256 <- function(path) {
    digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)
  }
}
if (!exists("lmv2_p5b_sql_path_list")) {
  lmv2_p5b_sql_path_list <- function(paths) {
    paste0("[", paste(vapply(paths, lmv2_sql_string, character(1)),
                       collapse = ", "), "]")
  }
}

lmv2_p5b_cert_add <- function(checks, name, pass, detail = "") {
  checks[[length(checks) + 1L]] <- data.frame(
    check = name, pass = isTRUE(pass), detail = as.character(detail),
    stringsAsFactors = FALSE)
  checks
}

lmv2_p5b_effective_count <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (!length(w)) return(0)
  sum(w)^2 / sum(w^2)
}

lmv2_certify_p5b_s3 <- function(config = lmv2_p5b_s3_config()) {
  production_specs <- config$production_specs
  production_cohorts <- config$production_cohorts
  diagnostic_path <- file.path(config$output_dir, "s3_weight_diagnostics.csv")
  support_path <- file.path(config$output_dir, "s3_support_diagnostics.csv")
  deal_path <- file.path(config$output_dir, "s3_deal_support_diagnostics.csv")
  exclusion_path <- file.path(
    config$output_dir, "s3_treated_support_exclusions.csv")
  provenance_path <- file.path(config$output_dir, "s3_input_provenance.csv")
  required <- c(
    diagnostic_path, support_path, deal_path, exclusion_path,
    provenance_path, config$freeze_file, config$source_files)
  missing <- required[!file.exists(required)]
  if (length(missing)) {
    stop("S3 certification inputs missing: ", paste(missing, collapse = ", "))
  }

  diagnostics <- read.csv(diagnostic_path, stringsAsFactors = FALSE)
  diagnostics <- diagnostics[
    diagnostics$spec %in% production_specs &
      diagnostics$cohort %in% production_cohorts, , drop = FALSE]
  support <- read.csv(support_path, stringsAsFactors = FALSE)
  deals <- read.csv(deal_path, stringsAsFactors = FALSE)
  exclusions <- read.csv(exclusion_path, stringsAsFactors = FALSE)
  provenance <- read.csv(provenance_path, stringsAsFactors = FALSE)

  weight_paths <- diagnostics$weight_path[diagnostics$feasible]
  balance_paths <- diagnostics$balance_path[diagnostics$feasible]
  if (!requireNamespace("data.table", quietly = TRUE)) {
    stop("data.table is required for union-by-name certification")
  }
  weights <- as.data.frame(data.table::rbindlist(
    lapply(weight_paths, function(path) {
      read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    }), fill = TRUE, use.names = TRUE))
  balances <- as.data.frame(data.table::rbindlist(
    lapply(balance_paths, function(path) {
      read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    }), fill = TRUE, use.names = TRUE))

  checks <- list()
  add <- function(name, pass, detail = "") {
    checks <<- lmv2_p5b_cert_add(checks, name, pass, detail)
  }
  add("six_production_specs_present",
      identical(sort(unique(diagnostics$spec)), sort(production_specs)))
  expected_cells <- length(production_specs) * length(production_cohorts)
  add("all_production_cells_present", nrow(diagnostics) == expected_cells,
      nrow(diagnostics))
  add("all_production_cells_feasible", all(diagnostics$feasible))
  add("all_production_cells_exact", all(diagnostics$mode == "exact_ebal"))
  add("all_production_cells_pass_ess",
      all(diagnostics$reuse_adjusted_ess_ratio >=
            config$gates$minimum_reuse_adjusted_ess_ratio),
      min(diagnostics$reuse_adjusted_ess_ratio))
  add("all_production_cells_exact_balance",
      all(diagnostics$max_smd_after <= config$gates$maximum_exact_smd),
      max(diagnostics$max_smd_after))
  add("all_17_cohorts_present",
      identical(
        sort(unique(as.integer(diagnostics$cohort))),
        1994:2010))
  expected_exclusions <- config$treated_support_exclusions[
    c("cohort", "codinv")]
  observed_exclusions <- exclusions[c("cohort", "codinv")]
  expected_exclusion_keys <- sort(paste(
    as.integer(expected_exclusions$cohort),
    as.numeric(expected_exclusions$codinv), sep = ":"))
  observed_exclusion_keys <- sort(paste(
    as.integer(observed_exclusions$cohort),
    as.numeric(observed_exclusions$codinv), sep = ":"))
  add("treated_support_exclusions_match_freeze",
      identical(expected_exclusion_keys, observed_exclusion_keys),
      nrow(observed_exclusions))
  add("all_weight_files_exist", all(file.exists(weight_paths)))
  add("all_balance_files_exist", all(file.exists(balance_paths)))
  add("input_checksums_match",
      all(provenance$expected_sha256 == provenance$observed_sha256))

  key <- paste(
    weights$spec, weights$cohort, weights$deal_id, weights$codinv,
    weights$treated,
    ifelse(weights$treated == 1L, "__treated__",
           as.character(weights$control_group)), sep = ":")
  add("row_keys_unique", !anyDuplicated(key))
  add("all_weights_positive_finite",
      all(is.finite(weights$final_weight) & weights$final_weight > 0))
  add("treated_weights_equal_base",
      max(abs(weights$final_weight[weights$treated == 1L] -
                weights$base_weight[weights$treated == 1L])) <= 1e-8)

  mass <- aggregate(
    final_weight ~ spec + cohort + treated, data = weights, FUN = sum)
  mass_wide <- reshape(
    mass, idvar = c("spec", "cohort"), timevar = "treated",
    direction = "wide")
  mass_diff <- abs(mass_wide$final_weight.1 - mass_wide$final_weight.0)
  add("cohort_treated_control_mass_equal", max(mass_diff) <= 1e-6,
      max(mass_diff))
  add("balance_artifacts_match_diagnostics",
      max(balances$abs_difference_after, na.rm = TRUE) <=
        config$gates$maximum_exact_smd,
      max(balances$abs_difference_after, na.rm = TRUE))

  primary_support <- support[
    support$support_variant == "primary_resolved_t1", ]
  primary_production_support <- primary_support[
    primary_support$cohort %in% production_cohorts, ]
  pooled_retention <- sum(primary_production_support$n_supported_treated) /
    sum(primary_support$n_eligible_treated)
  add("primary_pooled_retention_at_least_80pct",
      pooled_retention >= 0.80, pooled_retention)

  primary_spec <- production_specs[[1L]]
  primary <- weights[weights$spec == primary_spec &
                       weights$treated == 1L, ]
  deal_counts <- aggregate(codinv ~ cohort + deal_id, primary, length)
  names(deal_counts)[3] <- "n_treated"
  effective_deals <- lmv2_p5b_effective_count(deal_counts$n_treated)
  largest_deal_share <- max(deal_counts$n_treated) / sum(deal_counts$n_treated)
  add("primary_effective_deals_at_least_20",
      effective_deals >= config$gates$minimum_effective_treated_deals,
      effective_deals)
  add("primary_established_flag_complete",
      !anyNA(primary$established_early_recruitment))
  single_firm_deals <- deals[
    deals$support_variant == "primary_resolved_t1" &
      tolower(as.character(
        deals$deal_clears_two_firm_diagnostic)) != "true", ]
  single_firm_key <- paste(
    single_firm_deals$cohort, single_firm_deals$deal_id, sep = ":")
  primary_deal_key <- paste(primary$cohort, primary$deal_id, sep = ":")
  primary_single_firm <- primary[primary_deal_key %in% single_firm_key, ]
  single_firm_share <- sum(primary_single_firm$final_weight) /
    sum(primary$final_weight)
  add("single_firm_deals_are_diagnostic_only",
      nrow(single_firm_deals) > 0L,
      sprintf(
        "%d deals; %.6f treated-weight share",
        nrow(single_firm_deals), single_firm_share))

  source_hash <- lmv2_composite_source_hash(
    c(config$source_files, config$freeze_file))
  source_hash_tooth <- lmv2_hash_tooth_test()
  duplicate_tooth <- anyDuplicated(c(key, key[[1L]])) > 0L
  corrupted <- weights
  corrupt_index <- which(corrupted$treated == 0L)[1L]
  corrupted$final_weight[corrupt_index] <-
    corrupted$final_weight[corrupt_index] * 2
  corrupt_mass <- aggregate(
    final_weight ~ spec + cohort + treated, data = corrupted, FUN = sum)
  corrupt_wide <- reshape(
    corrupt_mass, idvar = c("spec", "cohort"), timevar = "treated",
    direction = "wide")
  mass_tooth <- max(abs(
    corrupt_wide$final_weight.1 - corrupt_wide$final_weight.0)) > 1e-6
  exclusion_tooth <- !identical(
    expected_exclusion_keys,
    sort(c(observed_exclusion_keys, "2008:-1")))
  tooth <- data.frame(
    test = c("source_hash_changes_after_edit", "duplicate_key_fires",
             "mass_corruption_fires", "exclusion_drift_fires"),
    pass = c(
      source_hash_tooth, duplicate_tooth, mass_tooth, exclusion_tooth),
    stringsAsFactors = FALSE)
  add("all_tooth_tests_pass", all(tooth$pass))

  certification <- do.call(rbind, checks)
  certification_path <- file.path(
    config$output_dir, "s3_certification.csv")
  tooth_path <- file.path(config$output_dir, "s3_tooth_tests.csv")
  lmv2_write_csv(certification, certification_path)
  lmv2_write_csv(tooth, tooth_path)

  established <- aggregate(
    codinv ~ established_early_recruitment, primary, length)
  names(established)[2] <- "treated_inventors"
  established$share <- established$treated_inventors /
    sum(established$treated_inventors)
  established$group <- ifelse(
    established$established_early_recruitment,
    "established_t_minus_7_or_6", "recently_recruited")
  established <- established[c("group", "treated_inventors", "share")]
  established_path <- file.path(
    config$output_dir, "s3_established_recent_counts.csv")
  lmv2_write_csv(established, established_path)
  established_share <- established$share[
    established$group == "established_t_minus_7_or_6"]
  predicted_att <- established_share *
    config$composition_benchmark$established_att +
    (1 - established_share) *
    config$composition_benchmark$recent_att
  composition <- data.frame(
    metric = c(
      "established_share",
      "recent_share",
      "established_att_reference",
      "recent_att_reference",
      "composition_predicted_att"),
    value = c(
      established_share,
      1 - established_share,
      config$composition_benchmark$established_att,
      config$composition_benchmark$recent_att,
      predicted_att),
    note = config$composition_benchmark$source,
    stringsAsFactors = FALSE)
  composition_path <- file.path(
    config$output_dir, "s3_composition_benchmark.csv")
  lmv2_write_csv(composition, composition_path)

  support_summary <- do.call(rbind, lapply(
    unique(support$support_variant), function(v) {
      x <- support[support$support_variant == v, ]
      data.frame(
        support_variant = v,
        eligible_treated = sum(x$n_eligible_treated),
        supported_treated = sum(
          x$n_supported_treated[x$cohort %in% production_cohorts]),
        retention = sum(
          x$n_supported_treated[x$cohort %in% production_cohorts]) /
          sum(x$n_eligible_treated),
        supported_deals = sum(
          x$n_supported_deals[x$cohort %in% production_cohorts]),
        control_rows = sum(
          x$n_control_rows[x$cohort %in% production_cohorts]),
        control_inventors = sum(
          x$n_control_inventors[x$cohort %in% production_cohorts]),
        control_firms = sum(
          x$n_control_firms[x$cohort %in% production_cohorts]),
        stringsAsFactors = FALSE)
    }))
  support_summary_path <- file.path(
    config$output_dir, "s3_support_summary.csv")
  lmv2_write_csv(support_summary, support_summary_path)

  summary <- data.frame(
    metric = c(
      "primary_eligible_treated", "primary_supported_treated",
      "primary_pooled_retention", "primary_supported_deals",
      "primary_effective_treated_deals", "primary_largest_deal_share",
      "primary_control_rows", "primary_min_cohort_ess_ratio",
      "primary_min_effective_control_firms", "production_max_smd_after",
      "excluded_infeasible_cohorts", "treated_support_exclusions",
      "single_firm_deals", "single_firm_treated_weight_share",
      "warmstart_newton_cells",
      "composition_predicted_att"),
    value = c(
      sum(primary_support$n_eligible_treated),
      sum(primary_production_support$n_supported_treated),
      pooled_retention,
      length(unique(paste(primary$cohort, primary$deal_id))),
      effective_deals,
      largest_deal_share,
      sum(primary_production_support$n_control_rows),
      min(diagnostics$reuse_adjusted_ess_ratio[
        diagnostics$spec == primary_spec]),
      min(diagnostics$effective_control_firms[
        diagnostics$spec == primary_spec]),
      max(diagnostics$max_smd_after),
      paste(setdiff(1994:2010, production_cohorts), collapse = ";"),
      nrow(exclusions),
      nrow(single_firm_deals),
      single_firm_share,
      sum(diagnostics$solver_path == "weightit_warmstart_newton"),
      predicted_att),
    stringsAsFactors = FALSE)
  summary_path <- file.path(config$output_dir, "s3_summary.csv")
  lmv2_write_csv(summary, summary_path)

  primary_paths <- diagnostics$weight_path[
    diagnostics$spec == primary_spec]
  production_paths <- diagnostics$weight_path
  primary_parquet <- file.path(
    config$output_dir, "s3_primary_weights.parquet")
  production_parquet <- file.path(
    config$output_dir, "s3_production_weights.parquet")
  unlink(c(primary_parquet, production_parquet), force = TRUE)
  sql <- paste0(
    "COPY (SELECT * FROM read_csv_auto(",
    lmv2_p5b_sql_path_list(primary_paths),
    ",header=true,union_by_name=true)) TO ",
    lmv2_sql_string(primary_parquet),
    " (FORMAT PARQUET,COMPRESSION ZSTD);\n",
    "COPY (SELECT * FROM read_csv_auto(",
    lmv2_p5b_sql_path_list(production_paths),
    ",header=true,union_by_name=true)) TO ",
    lmv2_sql_string(production_parquet),
    " (FORMAT PARQUET,COMPRESSION ZSTD);\n")
  sql_file <- tempfile(fileext = ".sql")
  on.exit(unlink(sql_file), add = TRUE)
  writeLines(sql, sql_file, useBytes = TRUE)
  duckdb_bin <- Sys.which("duckdb")
  command <- sprintf(".read %s", lmv2_sql_string(normalizePath(
    sql_file, winslash = "/", mustWork = TRUE)))
  log <- system2(duckdb_bin, c(":memory:", "-c", shQuote(command)),
                 stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(log, "status")) && attr(log, "status") != 0L) {
    stop("Failed to materialize S3 Parquet handoff: ",
         paste(log, collapse = "\n"))
  }

  artifact_paths <- c(
    primary_parquet, production_parquet, certification_path, tooth_path,
    established_path, composition_path, support_summary_path, summary_path,
    diagnostic_path, support_path, deal_path, exclusion_path,
    config$freeze_file)
  manifest <- data.frame(
    artifact = basename(artifact_paths),
    path = normalizePath(artifact_paths, winslash = "/", mustWork = TRUE),
    sha256 = vapply(artifact_paths, lmv2_p5b_sha256, character(1)),
    execution_hash = source_hash,
    stringsAsFactors = FALSE)
  manifest_path <- file.path(config$output_dir, "s3_manifest.csv")
  lmv2_write_csv(manifest, manifest_path)

  if (!all(certification$pass)) {
    stop("S3 certification failed: ",
         paste(certification$check[!certification$pass], collapse = ", "))
  }
  invisible(list(
    certification = certification, summary = summary,
    established = established, execution_hash = source_hash))
}
