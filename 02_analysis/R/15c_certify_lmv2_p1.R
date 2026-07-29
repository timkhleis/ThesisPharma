# ============================================================================
# 15c_certify_lmv2_p1.R -- P1 foundation certification
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
load_packages()
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))

label <- commandArgs(trailingOnly = TRUE)
label <- if (length(label)) label[[1]] else "current"
if (!grepl("^[A-Za-z0-9_-]+$", label)) stop("Unsafe certification label: ", label)

audit_dir <- file.path(BASE, "output", "audit", "local_match_v2", "p1")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

con <- connect_duckdb(read_only = TRUE)
on.exit(disconnect_duckdb(con), add = TRUE)

q <- function(sql) DBI::dbGetQuery(con, sql)
one <- function(sql, column) q(sql)[[column]][[1]]
checks <- list()
add_check <- function(metric, value, target, pass, detail = "") {
  checks[[length(checks) + 1L]] <<- data.frame(
    metric = metric,
    value = as.character(value),
    target = as.character(target),
    pass = isTRUE(pass),
    detail = detail,
    stringsAsFactors = FALSE
  )
}

required_tables <- c(
  "inventor_lookup", "patent_application", "patent_inventor_enriched",
  "inventor_group_year", "inventor_year"
)
missing_tables <- setdiff(required_tables, DBI::dbListTables(con))
add_check(
  "required_tables_present", length(missing_tables), 0L,
  length(missing_tables) == 0L,
  paste(missing_tables, collapse = ";")
)
if (length(missing_tables)) stop("P1 tables missing: ", paste(missing_tables, collapse = ", "))

grain <- q("
  SELECT
    COUNT(*) AS n_rows,
    COUNT(DISTINCT (codinv, year)) AS n_keys
  FROM inventor_year
")
add_check("inventor_year_duplicate_rows", grain$n_rows - grain$n_keys, 0L,
          grain$n_rows == grain$n_keys)

group_year_grain <- q("
  SELECT COUNT(*) AS n_rows, COUNT(DISTINCT (codinv, year)) AS n_keys
  FROM inventor_group_year
")
add_check("inventor_group_year_duplicate_rows",
          group_year_grain$n_rows - group_year_grain$n_keys, 0L,
          group_year_grain$n_rows == group_year_grain$n_keys)

pair_grain <- q("
  SELECT
    COUNT(*) AS source_rows,
    COUNT(DISTINCT (codinv, appln_id)) AS distinct_pairs
  FROM patent_inventor
")
add_check("patent_inventor_duplicate_pairs",
          pair_grain$source_rows - pair_grain$distinct_pairs, 0L,
          pair_grain$source_rows == pair_grain$distinct_pairs)

application_clock <- one("
  SELECT COUNT(*) AS n
  FROM (
    SELECT appln_id
    FROM patent
    GROUP BY appln_id
    HAVING MIN(year) <> MAX(year)
  )
", "n")
add_check("applications_with_conflicting_application_year", application_clock, 0L,
          application_clock == 0L)

count_comparison <- q("
  WITH pairs AS (
    SELECT DISTINCT appln_id, codinv FROM patent_inventor
  ),
  inventor_counts AS (
    SELECT appln_id, COUNT(*) AS n_inventors
    FROM pairs
    GROUP BY appln_id
  ),
  direct AS (
    SELECT
      p.codinv,
      pa.patent_year AS year,
      COUNT(*) AS patent_count,
      SUM(1.0 / ic.n_inventors) AS fractional_patent_count
    FROM pairs p
    JOIN patent_application pa USING (appln_id)
    JOIN inventor_counts ic USING (appln_id)
    GROUP BY p.codinv, pa.patent_year
  )
  SELECT
    COUNT(*) FILTER (
      WHERE d.codinv IS NULL OR iy.codinv IS NULL
         OR d.patent_count <> iy.patent_count
         OR ABS(d.fractional_patent_count - iy.fractional_patent_count) > 1e-12
    ) AS mismatch_rows,
    COUNT(*) AS compared_rows,
    MAX(ABS(COALESCE(d.fractional_patent_count, 0) -
            COALESCE(iy.fractional_patent_count, 0))) AS max_fractional_gap
  FROM direct d
  FULL OUTER JOIN inventor_year iy USING (codinv, year)
")
add_check("direct_patent_count_mismatches", count_comparison$mismatch_rows, 0L,
          count_comparison$mismatch_rows == 0L,
          paste0("compared_rows=", count_comparison$compared_rows))
add_check("max_fractional_patent_count_gap", count_comparison$max_fractional_gap, "<=1e-12",
          is.finite(count_comparison$max_fractional_gap) &&
            count_comparison$max_fractional_gap <= 1e-12)

career_mismatches <- one("
  WITH pairs AS (
    SELECT DISTINCT appln_id, codinv FROM patent_inventor
  ),
  direct AS (
    SELECT p.codinv, MIN(pa.patent_year) AS first_year, MAX(pa.patent_year) AS last_year
    FROM pairs p
    JOIN patent_application pa USING (appln_id)
    GROUP BY p.codinv
  ),
  panel AS (
    SELECT
      codinv,
      MIN(career_first_year) AS first_year,
      MAX(career_last_year) AS last_year,
      COUNT(DISTINCT career_first_year) AS n_first,
      COUNT(DISTINCT career_last_year) AS n_last
    FROM inventor_year
    GROUP BY codinv
  )
  SELECT COUNT(*) AS n
  FROM direct d
  FULL OUTER JOIN panel p USING (codinv)
  WHERE d.codinv IS NULL OR p.codinv IS NULL
     OR d.first_year <> p.first_year OR d.last_year <> p.last_year
     OR p.n_first <> 1 OR p.n_last <> 1
", "n")
add_check("career_endpoint_mismatches", career_mismatches, 0L, career_mismatches == 0L)

affiliation_mismatches <- one("
  WITH pairs AS (
    SELECT DISTINCT appln_id, codinv FROM patent_inventor
  ),
  direct AS (
    SELECT
      p.codinv,
      pa.patent_year AS year,
      COUNT(DISTINCT pcl.compcod) AS firm_count,
      COUNT(DISTINCT pcl.id_group) AS group_count
    FROM pairs p
    JOIN patent_application pa USING (appln_id)
    LEFT JOIN patent_company_link pcl USING (appln_id)
    GROUP BY p.codinv, pa.patent_year
  )
  SELECT COUNT(*) AS n
  FROM direct d
  FULL OUTER JOIN inventor_year iy USING (codinv, year)
  WHERE d.codinv IS NULL OR iy.codinv IS NULL
     OR d.firm_count <> iy.distinct_firm_count
     OR d.group_count <> iy.distinct_group_count
", "n")
add_check("direct_affiliation_count_mismatches", affiliation_mismatches, 0L,
          affiliation_mismatches == 0L)

lookup <- q("
  SELECT
    (SELECT COUNT(*) FROM inventor_lookup) AS lookup_rows,
    (SELECT COUNT(DISTINCT codinv) FROM inventor_lookup) AS lookup_keys,
    (SELECT COUNT(DISTINCT codinv) FROM inventor) AS source_keys,
    (SELECT SUM((inventor_name_value_count > 1)::INTEGER) FROM inventor_lookup) AS name_conflicts,
    (SELECT SUM((inventor_country_value_count > 1)::INTEGER) FROM inventor_lookup) AS country_conflicts,
    (SELECT SUM((codinv2_value_count > 1)::INTEGER) FROM inventor_lookup) AS codinv2_conflicts
")
add_check("inventor_lookup_duplicate_rows", lookup$lookup_rows - lookup$lookup_keys, 0L,
          lookup$lookup_rows == lookup$lookup_keys)
add_check("inventor_lookup_missing_keys", lookup$source_keys - lookup$lookup_keys, 0L,
          lookup$source_keys == lookup$lookup_keys)

enriched_grain <- q("
  SELECT
    (SELECT COUNT(*) FROM patent_inventor_enriched) AS enriched_rows,
    (SELECT COUNT(DISTINCT (codinv, appln_id)) FROM patent_inventor_enriched) AS enriched_keys,
    (SELECT COUNT(DISTINCT (codinv, appln_id)) FROM patent_inventor) AS source_keys
")
add_check("patent_inventor_enriched_duplicate_rows",
          enriched_grain$enriched_rows - enriched_grain$enriched_keys, 0L,
          enriched_grain$enriched_rows == enriched_grain$enriched_keys)
add_check("patent_inventor_enriched_missing_pairs",
          enriched_grain$source_keys - enriched_grain$enriched_keys, 0L,
          enriched_grain$source_keys == enriched_grain$enriched_keys)

covariate_mismatches <- one("
  WITH cohort AS (
    SELECT CAST(codinv AS BIGINT) AS codinv, CAST(deal_year AS INTEGER) AS g
    FROM target_cohort_own
    WHERE exposure_rank = 1
      AND deal_year BETWEEN 1994 AND 2010
      AND (target_resolved_latest OR target_to_acquirer_transition_strict)
  ),
  pairs AS (
    SELECT DISTINCT CAST(codinv AS BIGINT) AS codinv, appln_id FROM patent_inventor
  ),
  direct AS (
    SELECT
      c.codinv,
      c.g,
      COUNT(p.appln_id) FILTER (WHERE pa.patent_year BETWEEN c.g - 5 AND c.g - 1) AS stock_5y,
      COUNT(p.appln_id) FILTER (WHERE pa.patent_year BETWEEN c.g - 5 AND c.g - 3) AS early,
      COUNT(p.appln_id) FILTER (WHERE pa.patent_year BETWEEN c.g - 2 AND c.g - 1) AS recent,
      MAX(pa.patent_year) FILTER (WHERE pa.patent_year BETWEEN c.g - 5 AND c.g - 1) AS last_pre_year
    FROM cohort c
    LEFT JOIN pairs p ON p.codinv = c.codinv
    LEFT JOIN patent_application pa ON pa.appln_id = p.appln_id
    GROUP BY c.codinv, c.g
  ),
  panel AS (
    SELECT
      c.codinv,
      c.g,
      COALESCE(SUM(iy.patent_count) FILTER (WHERE iy.year BETWEEN c.g - 5 AND c.g - 1), 0) AS stock_5y,
      COALESCE(SUM(iy.patent_count) FILTER (WHERE iy.year BETWEEN c.g - 5 AND c.g - 3), 0) AS early,
      COALESCE(SUM(iy.patent_count) FILTER (WHERE iy.year BETWEEN c.g - 2 AND c.g - 1), 0) AS recent,
      MAX(iy.year) FILTER (WHERE iy.year BETWEEN c.g - 5 AND c.g - 1) AS last_pre_year
    FROM cohort c
    LEFT JOIN inventor_year iy ON CAST(iy.codinv AS BIGINT) = c.codinv
    GROUP BY c.codinv, c.g
  )
  SELECT COUNT(*) AS n
  FROM direct d
  JOIN panel p USING (codinv, g)
  WHERE d.stock_5y <> p.stock_5y
     OR d.early <> p.early
     OR d.recent <> p.recent
     OR d.last_pre_year IS DISTINCT FROM p.last_pre_year
", "n")
add_check("matching_covariate_mismatches", covariate_mismatches, 0L,
          covariate_mismatches == 0L)

logical_checksums <- q("
  SELECT
    'inventor_year' AS table_name,
    COUNT(*) AS n_rows,
    CAST(SUM(CAST(hash(codinv, year, patent_count, fractional_patent_count,
                       distinct_firm_count, distinct_group_count,
                       career_first_year, career_last_year, career_year_index)
                     AS HUGEINT)) AS VARCHAR) AS hash_sum,
    CAST(bit_xor(hash(codinv, year, patent_count, fractional_patent_count,
                      distinct_firm_count, distinct_group_count,
                      career_first_year, career_last_year, career_year_index))
         AS VARCHAR) AS hash_xor
  FROM inventor_year
  UNION ALL
  SELECT
    'inventor_lookup', COUNT(*),
    CAST(SUM(CAST(hash(codinv, codinv2, inventor_name, inventor_country,
                       source_row_count, codinv2_value_count,
                       inventor_name_value_count, inventor_country_value_count)
                     AS HUGEINT)) AS VARCHAR),
    CAST(bit_xor(hash(codinv, codinv2, inventor_name, inventor_country,
                      source_row_count, codinv2_value_count,
                      inventor_name_value_count, inventor_country_value_count))
         AS VARCHAR)
  FROM inventor_lookup
  UNION ALL
  SELECT
    'patent_inventor_enriched', COUNT(*),
    CAST(SUM(CAST(hash(appln_id, codinv, year, inventor_count, ipc_code_count,
                       group_count, compcod_count, id_group_list,
                       merger_status_values, codinv2, inname, incy)
                     AS HUGEINT)) AS VARCHAR),
    CAST(bit_xor(hash(appln_id, codinv, year, inventor_count, ipc_code_count,
                      group_count, compcod_count, id_group_list,
                      merger_status_values, codinv2, inname, incy))
         AS VARCHAR)
  FROM patent_inventor_enriched
  ORDER BY table_name
")

parquet_paths <- file.path(BASE, "output", "parquet", "derived",
                           paste0(logical_checksums$table_name, ".parquet"))
logical_checksums$parquet_md5 <- unname(tools::md5sum(parquet_paths))
logical_checksums$design_hash <- LMV2_DESIGN_HASH
logical_checksums$certification_label <- label

check_df <- do.call(rbind, checks)
check_df$design_hash <- LMV2_DESIGN_HASH
check_df$certification_label <- label

metadata_conflicts <- data.frame(
  metric = c("inventor_name_conflict_ids", "inventor_country_conflict_ids", "codinv2_conflict_ids"),
  value = c(lookup$name_conflicts, lookup$country_conflicts, lookup$codinv2_conflicts),
  treatment = "preserved_as_lookup_diagnostic_not_analysis_covariate",
  design_hash = LMV2_DESIGN_HASH,
  stringsAsFactors = FALSE
)

write.csv(check_df, file.path(audit_dir, paste0("p1_checks_", label, ".csv")),
          row.names = FALSE, na = "")
write.csv(logical_checksums,
          file.path(audit_dir, paste0("p1_logical_checksums_", label, ".csv")),
          row.names = FALSE, na = "")
write.csv(metadata_conflicts,
          file.path(audit_dir, paste0("p1_metadata_conflicts_", label, ".csv")),
          row.names = FALSE, na = "")

failed <- check_df$metric[!check_df$pass]
if (length(failed)) stop("P1 certification failed: ", paste(failed, collapse = ", "))
message("P1 certification PASS [", label, "] | design_hash=", LMV2_DESIGN_HASH)
