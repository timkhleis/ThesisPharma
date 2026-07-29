# Build the four frozen P5b S3 roster restrictions from certified P5c inputs.
#
# S3 balances cohort/deal-stacked rosters. It therefore restricts the
# certified P5 roster symmetrically to initially retained treated and control
# inventors. Control-firm concentration is reported at the treated-deal level;
# it is not used as a hard support gate and is not a per-inventor
# nearest-neighbour requirement.

if (!exists("lmv2_p5b_s3_config")) {
  source(file.path("02_analysis", "R", "27a_lmv2_p5b_s3_config.R"))
}

lmv2_p5b_sha256 <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("digest is required")
  digest::digest(path, algo = "sha256", file = TRUE, serialize = FALSE)
}

lmv2_p5b_sql_path_list <- function(paths) {
  paste0("[", paste(vapply(paths, lmv2_sql_string, character(1)),
                     collapse = ", "), "]")
}

lmv2_build_p5b_s3_support <- function(config = lmv2_p5b_s3_config()) {
  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(config$source_dir, recursive = TRUE, showWarnings = FALSE)

  p5c <- lmv2_p5b_s3_selected_p5c(config)
  observed_p5c <- vapply(p5c$weight_path, lmv2_p5b_sha256, character(1))
  if (!all(observed_p5c == p5c$weight_sha256)) {
    stop("At least one certified P5c source checksum failed")
  }

  treated_path <- file.path(
    config$s2_dir, "treated_retention_partition.parquet")
  control_path <- file.path(
    config$s2_dir, "control_retained_candidates.parquet")
  raw_path <- file.path(
    config$s2_dir, "raw_first_post_affiliation_audit.parquet")
  required_inputs <- c(treated_path, control_path, raw_path)
  if (!all(file.exists(required_inputs))) {
    stop("Missing S2 inputs: ", paste(required_inputs[!file.exists(required_inputs)],
                                      collapse = ", "))
  }

  output_parquet <- file.path(config$output_dir, "s3_support_roster.parquet")
  diagnostics_path <- file.path(config$output_dir, "s3_support_diagnostics.csv")
  deal_path <- file.path(config$output_dir, "s3_deal_support_diagnostics.csv")
  exclusion_path <- file.path(
    config$output_dir, "s3_treated_support_exclusions.csv")
  provenance_path <- file.path(config$output_dir, "s3_input_provenance.csv")
  unlink(c(
    output_parquet, diagnostics_path, deal_path, exclusion_path,
    provenance_path),
         force = TRUE)
  old_csv <- list.files(config$source_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(old_csv)) unlink(old_csv, force = TRUE)

  copy_statements <- unlist(lapply(config$support_variants, function(v) {
    vapply(1994:2010, function(g) {
      path <- file.path(config$source_dir, sprintf("%s_c%d.csv", v, g))
      sprintf(
        paste0(
          "COPY (SELECT * FROM support_roster ",
          "WHERE support_variant=%s AND cohort=%d ",
          "ORDER BY treated DESC,deal_id,codinv,control_group) ",
          "TO %s (HEADER,DELIMITER ',');"),
        lmv2_sql_string(v), g, lmv2_sql_string(path))
    }, character(1))
  }))
  excluded <- config$treated_support_exclusions
  exclusion_predicate <- paste(sprintf(
    "(p.cohort=%d AND CAST(p.codinv AS BIGINT)=%.0f)",
    excluded$cohort, excluded$codinv), collapse = " OR ")

  sql <- paste0(
    "SET threads=4;\n",
    "SET memory_limit='4GB';\n",
    "ATTACH ", lmv2_sql_string(config$foundation_db),
    " AS foundation (READ_ONLY);\n",
    "CREATE TEMP TABLE p5c AS SELECT * FROM read_parquet(",
    lmv2_p5b_sql_path_list(p5c$weight_path), ");\n",
    "CREATE TEMP TABLE treated_s2 AS SELECT * FROM read_parquet(",
    lmv2_sql_string(treated_path), ");\n",
    "CREATE TEMP TABLE control_s2 AS SELECT * FROM read_parquet(",
    lmv2_sql_string(control_path), ");\n",
    "CREATE TEMP TABLE raw_audit AS SELECT * FROM read_parquet(",
    lmv2_sql_string(raw_path), ");\n",
    "CREATE TEMP TABLE variant_treated AS\n",
    "SELECT 'primary_resolved_t1' support_variant,cohort,deal_id,codinv\n",
    " FROM treated_s2 WHERE retention_window='t1_t5_primary'\n",
    " AND retention_status='initially_retained'\n",
    "UNION ALL SELECT 'route_consistent_t1',cohort,deal_id,codinv\n",
    " FROM treated_s2 WHERE retention_window='t1_t5_primary'\n",
    " AND retention_status='initially_retained' AND NOT route_disagreement\n",
    "UNION ALL SELECT 'raw_unmixed_t1',t.cohort,t.deal_id,t.codinv\n",
    " FROM treated_s2 t JOIN raw_audit r\n",
    " USING(retention_window,cohort,deal_id,codinv)\n",
    " WHERE t.retention_window='t1_t5_primary'\n",
    " AND t.retention_status='initially_retained' AND r.arm='treated'\n",
    " AND NOT r.any_focal_route_mixed\n",
    "UNION ALL SELECT 'timing_resolved_t2',cohort,deal_id,codinv\n",
    " FROM treated_s2 WHERE retention_window='t2_t5_sensitivity'\n",
    " AND retention_status='initially_retained';\n",
    "CREATE TEMP TABLE variant_control AS\n",
    "SELECT 'primary_resolved_t1' support_variant,cohort,codinv,control_group\n",
    " FROM control_s2 WHERE retention_window='t1_t5_primary'\n",
    "UNION ALL SELECT 'route_consistent_t1',cohort,codinv,control_group\n",
    " FROM control_s2 WHERE retention_window='t1_t5_primary'\n",
    "UNION ALL SELECT 'raw_unmixed_t1',c.cohort,c.codinv,c.control_group\n",
    " FROM control_s2 c JOIN raw_audit r\n",
    " ON r.arm='control' AND r.retention_window=c.retention_window\n",
    " AND r.cohort=c.cohort AND r.codinv=c.codinv\n",
    " AND r.focal_group_1=c.control_group\n",
    " WHERE c.retention_window='t1_t5_primary' AND NOT r.raw_group_mixed\n",
    "UNION ALL SELECT 'timing_resolved_t2',cohort,codinv,control_group\n",
    " FROM control_s2 WHERE retention_window='t2_t5_sensitivity';\n",
    "CREATE TEMP TABLE source_treated AS\n",
    "SELECT v.support_variant,p.* FROM variant_treated v JOIN p5c p\n",
    " ON p.treated=1 AND p.cohort=v.cohort\n",
    " AND CAST(p.deal_id AS BIGINT)=v.deal_id\n",
    " AND CAST(p.codinv AS BIGINT)=v.codinv\n",
    " WHERE NOT (", exclusion_predicate, ");\n",
    "CREATE TEMP TABLE source_control AS\n",
    "SELECT v.support_variant,p.* FROM variant_control v JOIN p5c p\n",
    " ON p.treated=0 AND p.cohort=v.cohort\n",
    " AND CAST(p.codinv AS BIGINT)=v.codinv\n",
    " AND CAST(p.control_group AS BIGINT)=v.control_group;\n",
    "CREATE TEMP TABLE deal_support_candidates AS\n",
    "WITH t AS (SELECT support_variant,cohort,CAST(deal_id AS BIGINT) deal_id,\n",
    " COUNT(*) n_treated FROM source_treated GROUP BY ALL),\n",
    "c AS (SELECT support_variant,cohort,CAST(deal_id AS BIGINT) deal_id,\n",
    " COUNT(*) n_control_rows,COUNT(DISTINCT codinv) n_control_inventors,\n",
    " COUNT(DISTINCT control_group) n_control_firms\n",
    " FROM source_control GROUP BY ALL)\n",
    "SELECT t.*,c.n_control_rows,c.n_control_inventors,c.n_control_firms\n",
    " FROM t JOIN c USING(support_variant,cohort,deal_id)\n",
    " WHERE t.n_treated>0 AND c.n_control_rows>0;\n",
    "CREATE TEMP TABLE deal_support AS\n",
    "SELECT * FROM deal_support_candidates\n",
    " WHERE n_control_firms>=", config$support$minimum_deal_control_firms,
    ";\n",
    "CREATE TEMP TABLE support_roster_base AS\n",
    "SELECT s.* FROM source_treated s JOIN deal_support d\n",
    " ON d.support_variant=s.support_variant AND d.cohort=s.cohort\n",
    " AND d.deal_id=CAST(s.deal_id AS BIGINT)\n",
    "UNION ALL SELECT s.* FROM source_control s JOIN deal_support d\n",
    " ON d.support_variant=s.support_variant AND d.cohort=s.cohort\n",
    " AND d.deal_id=CAST(s.deal_id AS BIGINT);\n",
    "CREATE TEMP TABLE support_keys AS\n",
    "SELECT DISTINCT support_variant,cohort,CAST(deal_id AS BIGINT) deal_id,\n",
    " CAST(codinv AS BIGINT) codinv,treated,CAST(group_id AS BIGINT) group_id\n",
    " FROM support_roster_base;\n",
    "CREATE TEMP TABLE early_group AS\n",
    "SELECT DISTINCT k.support_variant,k.cohort,k.deal_id,k.codinv,k.treated\n",
    " FROM support_keys k JOIN foundation.patent_inventor pi\n",
    " ON CAST(pi.codinv AS BIGINT)=k.codinv\n",
    " JOIN foundation.patent_company_link pcl ON pcl.appln_id=pi.appln_id\n",
    " AND pcl.year IN (k.cohort-7,k.cohort-6)\n",
    " AND CAST(pcl.id_group AS BIGINT)=k.group_id;\n",
    "CREATE TEMP TABLE early_target_company AS\n",
    "SELECT DISTINCT k.support_variant,k.cohort,k.deal_id,k.codinv,k.treated\n",
    " FROM support_keys k JOIN foundation.deal_target_company_strict d\n",
    " ON k.treated=1 AND d.deal_id=k.deal_id\n",
    " JOIN foundation.patent_company_link pcl\n",
    " ON CAST(pcl.compcod AS BIGINT)=d.target_compcod\n",
    " AND pcl.year IN (k.cohort-7,k.cohort-6)\n",
    " JOIN foundation.patent_inventor pi ON pi.appln_id=pcl.appln_id\n",
    " AND CAST(pi.codinv AS BIGINT)=k.codinv;\n",
    "CREATE TEMP TABLE support_roster AS\n",
    "SELECT b.*,\n",
    " (eg.codinv IS NOT NULL OR ec.codinv IS NOT NULL)\n",
    " AS established_early_recruitment\n",
    " FROM support_roster_base b\n",
    " LEFT JOIN early_group eg ON eg.support_variant=b.support_variant\n",
    " AND eg.cohort=b.cohort AND eg.deal_id=CAST(b.deal_id AS BIGINT)\n",
    " AND eg.codinv=CAST(b.codinv AS BIGINT) AND eg.treated=b.treated\n",
    " LEFT JOIN early_target_company ec ON ec.support_variant=b.support_variant\n",
    " AND ec.cohort=b.cohort AND ec.deal_id=CAST(b.deal_id AS BIGINT)\n",
    " AND ec.codinv=CAST(b.codinv AS BIGINT) AND ec.treated=b.treated;\n",
    "COPY (SELECT * FROM support_roster ORDER BY support_variant,cohort,\n",
    " treated DESC,deal_id,codinv,control_group) TO ",
    lmv2_sql_string(output_parquet), " (FORMAT PARQUET,COMPRESSION ZSTD);\n",
    "COPY (SELECT *,n_control_firms>=",
    config$support$diagnostic_deal_control_firms,
    " AS deal_clears_two_firm_diagnostic\n",
    " FROM deal_support_candidates ORDER BY support_variant,cohort,deal_id) TO ",
    lmv2_sql_string(deal_path), " (HEADER,DELIMITER ',');\n",
    "COPY (\n",
    "WITH eligible AS (SELECT support_variant,cohort,COUNT(*) n_eligible_treated,\n",
    " COUNT(DISTINCT deal_id) n_eligible_deals FROM variant_treated GROUP BY ALL),\n",
    "src AS (SELECT support_variant,cohort,COUNT(*) n_source_treated\n",
    " FROM source_treated GROUP BY ALL),\n",
    "supported AS (SELECT support_variant,cohort,COUNT(*) n_supported_treated,\n",
    " COUNT(DISTINCT deal_id) n_supported_deals FROM support_roster\n",
    " WHERE treated=1 GROUP BY ALL),\n",
    "ctrl AS (SELECT support_variant,cohort,COUNT(*) n_control_rows,\n",
    " COUNT(DISTINCT codinv) n_control_inventors,\n",
    " COUNT(DISTINCT control_group) n_control_firms FROM support_roster\n",
    " WHERE treated=0 GROUP BY ALL)\n",
    "SELECT e.*,COALESCE(src.n_source_treated,0) n_source_treated,\n",
    " COALESCE(s.n_supported_treated,0) n_supported_treated,\n",
    " COALESCE(s.n_supported_deals,0) n_supported_deals,\n",
    " COALESCE(c.n_control_rows,0) n_control_rows,\n",
    " COALESCE(c.n_control_inventors,0) n_control_inventors,\n",
    " COALESCE(c.n_control_firms,0) n_control_firms,\n",
    " COALESCE(s.n_supported_treated,0)::DOUBLE/e.n_eligible_treated retention\n",
    " FROM eligible e LEFT JOIN src USING(support_variant,cohort)\n",
    " LEFT JOIN supported s USING(support_variant,cohort)\n",
    " LEFT JOIN ctrl c USING(support_variant,cohort)\n",
    " ORDER BY support_variant,cohort) TO ",
    lmv2_sql_string(diagnostics_path), " (HEADER,DELIMITER ',');\n",
    paste(copy_statements, collapse = "\n"), "\n"
  )

  sql_file <- tempfile(fileext = ".sql")
  on.exit(unlink(sql_file), add = TRUE)
  writeLines(sql, sql_file, useBytes = TRUE)
  duckdb_bin <- Sys.which("duckdb")
  if (!nzchar(duckdb_bin)) stop("DuckDB CLI is not on PATH")
  command <- sprintf(".read %s", lmv2_sql_string(normalizePath(
    sql_file, winslash = "/", mustWork = TRUE)))
  log <- system2(duckdb_bin, c(":memory:", "-c", shQuote(command)),
                 stdout = TRUE, stderr = TRUE)
  writeLines(log, file.path(config$output_dir, "build_s3_support.log"),
             useBytes = TRUE)
  status <- attr(log, "status")
  if (!is.null(status) && status != 0L) {
    stop("DuckDB S3 roster build failed; see build_s3_support.log")
  }

  provenance <- rbind(
    data.frame(kind = "p5c_weight", cohort = p5c$cohort,
               path = p5c$weight_path, expected_sha256 = p5c$weight_sha256,
               observed_sha256 = observed_p5c),
    data.frame(kind = "s2_interface", cohort = NA_integer_,
               path = required_inputs,
               expected_sha256 = vapply(required_inputs, lmv2_p5b_sha256,
                                        character(1)),
               observed_sha256 = vapply(required_inputs, lmv2_p5b_sha256,
                                        character(1)))
  )
  lmv2_write_csv(provenance, provenance_path)
  lmv2_write_csv(excluded, exclusion_path)

  expected_csv <- unlist(lapply(config$support_variants, function(v) {
    file.path(config$source_dir, sprintf("%s_c%d.csv", v, 1994:2010))
  }))
  required <- c(
    output_parquet, diagnostics_path, deal_path, exclusion_path,
    provenance_path, expected_csv)
  missing <- required[!file.exists(required)]
  if (length(missing)) {
    stop("S3 roster build did not create: ", paste(missing, collapse = ", "))
  }
  invisible(required)
}
