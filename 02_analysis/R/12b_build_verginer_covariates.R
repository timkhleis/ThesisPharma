# ============================================================================
# 12b_build_verginer_covariates.R -- Build Verginer covariates + audits
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "12a_verginer_ebal_config.R"))
required_packages_12(c("DBI", "duckdb"))

banner_12("12b: Build Verginer covariates")

con <- connect_thesis_readonly()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

cov_sql <- sprintf("
COPY (
WITH deal_flags AS (
  SELECT
    CAST(s.deal_id AS INTEGER) AS deal_id,
    CAST(dm.target_year AS INTEGER) AS treatment_year,
    CAST(s.target_group AS DOUBLE) AS target_group,
    CAST(s.acquirer_group AS DOUBLE) AS acquirer_group,
    COALESCE(CAST(s.acquirer_group AS VARCHAR) NOT LIKE '999%%', FALSE)
      AS acquirer_resolved,
    COALESCE(CAST(s.acquirer_group AS VARCHAR) NOT LIKE '999%%', FALSE) AND EXISTS (
      SELECT 1
      FROM group_ipc_year giy
      WHERE giy.id_group IN (s.target_group, s.acquirer_group)
        AND giy.year > s.deal_year
    ) AS merged_entity_survival
  FROM cassi_deal_group_spine s
  JOIN deal_map dm
    ON CAST(dm.deal_id AS INTEGER) = CAST(s.deal_id AS INTEGER)
),
base_units AS (
  SELECT DISTINCT
    CAST(x.codinv AS BIGINT) AS codinv,
    CAST(x.deal_id AS INTEGER) AS deal_id,
    CAST(df.treatment_year AS INTEGER) AS treatment_year,
    CAST(df.target_group AS DOUBLE) AS target_group,
    CAST(df.acquirer_group AS DOUBLE) AS acquirer_group,
    df.acquirer_resolved,
    CAST(x.career_age_at_deal AS DOUBLE) AS existing_career_age_at_deal,
    CAST(x.observed_target_patent_tenure AS DOUBLE) AS existing_observed_target_patent_tenure
  FROM cs2021_estimation_panel x
  JOIN deal_flags df
    ON df.deal_id = CAST(x.deal_id AS INTEGER)
   AND df.merged_entity_survival
),
career AS (
  SELECT
    CAST(codinv AS BIGINT) AS codinv,
    MIN(year) FILTER (WHERE patent_count > 0) AS first_patent_year
  FROM inventor_year
  GROUP BY codinv
),
target_history AS (
  SELECT
    u.codinv,
    u.deal_id,
    MIN(ia.year) FILTER (
      WHERE ia.resolved_group = u.target_group
         OR COALESCE(
              list_contains(
                string_split(ia.candidate_group_list, ';'),
                CAST(CAST(u.target_group AS BIGINT) AS VARCHAR)
              ),
              FALSE
            )
    ) AS first_target_patent_year
  FROM base_units u
  LEFT JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = u.codinv
   AND ia.year < u.treatment_year
  GROUP BY u.codinv, u.deal_id
),
inventor_window_patents AS (
  SELECT DISTINCT
    u.codinv,
    u.deal_id,
    pie.appln_id,
    pie.id_group_list,
    CAST(u.target_group AS VARCHAR) AS target_group_chr
  FROM base_units u
  JOIN patent_inventor_enriched pie
    ON CAST(pie.codinv AS BIGINT) = u.codinv
   AND pie.year BETWEEN u.treatment_year - 5 AND u.treatment_year - 1
),
exclusivity AS (
  SELECT
    codinv,
    deal_id,
    COUNT(DISTINCT appln_id) AS exclusivity_denominator,
    COUNT(DISTINCT CASE
      WHEN COALESCE(list_contains(string_split(id_group_list, ';'), target_group_chr), FALSE)
      THEN appln_id END) AS exclusivity_numerator
  FROM inventor_window_patents
  GROUP BY codinv, deal_id
),
inventor_pre_ipc AS (
  SELECT DISTINCT
    u.codinv,
    u.deal_id,
    SUBSTR(REGEXP_REPLACE(UPPER(TRIM(iiy.ipc_code)), '[^A-Z0-9]', '', 'g'), 1, 4)
      AS ipc_subclass
  FROM base_units u
  JOIN inventor_ipc_year iiy
    ON CAST(iiy.codinv AS BIGINT) = u.codinv
   AND iiy.year < u.treatment_year
  WHERE iiy.ipc_code IS NOT NULL
    AND LENGTH(REGEXP_REPLACE(UPPER(TRIM(iiy.ipc_code)), '[^A-Z0-9]', '', 'g')) >= 4
),
inventor_ipc_obs AS (
  SELECT codinv, deal_id, COUNT(DISTINCT ipc_subclass) AS n_inventor_preipc
  FROM inventor_pre_ipc
  GROUP BY codinv, deal_id
),
acquirer_portfolio_obs AS (
  SELECT
    u.codinv,
    u.deal_id,
    SUM(COALESCE(gys.helper_group_patent, 0)) AS n_acquirer_pre_patents
  FROM base_units u
  LEFT JOIN group_year_status gys
    ON gys.id_group = u.acquirer_group
   AND gys.year < u.treatment_year
  WHERE u.acquirer_resolved
  GROUP BY u.codinv, u.deal_id
),
acquirer_pre_ipc AS (
  SELECT DISTINCT
    u.codinv,
    u.deal_id,
    SUBSTR(REGEXP_REPLACE(UPPER(TRIM(giy.ipc_code)), '[^A-Z0-9]', '', 'g'), 1, 4)
      AS ipc_subclass
  FROM base_units u
  JOIN group_ipc_year giy
    ON giy.id_group = u.acquirer_group
   AND giy.year < u.treatment_year
  WHERE u.acquirer_resolved
    AND giy.ipc_code IS NOT NULL
    AND LENGTH(REGEXP_REPLACE(UPPER(TRIM(giy.ipc_code)), '[^A-Z0-9]', '', 'g')) >= 4
),
acquirer_ipc_obs AS (
  SELECT codinv, deal_id, COUNT(DISTINCT ipc_subclass) AS n_acquirer_preipc
  FROM acquirer_pre_ipc
  GROUP BY codinv, deal_id
),
common_ipc AS (
  SELECT
    i.codinv,
    i.deal_id,
    COUNT(DISTINCT i.ipc_subclass) AS n_common_ipc
  FROM inventor_pre_ipc i
  JOIN acquirer_pre_ipc a
    ON a.codinv = i.codinv
   AND a.deal_id = i.deal_id
   AND a.ipc_subclass = i.ipc_subclass
  GROUP BY i.codinv, i.deal_id
)
SELECT
  u.codinv,
  u.deal_id,
  u.treatment_year,
  u.target_group,
  u.acquirer_group,
  u.acquirer_resolved,
  c.first_patent_year,
  th.first_target_patent_year,
  CAST(u.treatment_year - c.first_patent_year AS DOUBLE) AS vr_age,
  CAST(u.treatment_year - th.first_target_patent_year AS DOUBLE) AS vr_tenure,
  CASE
    WHEN ex.exclusivity_denominator > 0
    THEN CAST(ex.exclusivity_numerator AS DOUBLE) / ex.exclusivity_denominator
    ELSE NULL
  END AS vr_exclusivity,
  ex.exclusivity_numerator,
  ex.exclusivity_denominator,
  COALESCE(apo.n_acquirer_pre_patents, 0) > 0 AS acquirer_preportfolio_observed,
  COALESCE(iio.n_inventor_preipc, 0) > 0 AS inventor_preipc_observed,
  COALESCE(aio.n_acquirer_preipc, 0) > 0 AS acquirer_preipc_observed,
  CASE
    WHEN u.acquirer_resolved
     AND COALESCE(apo.n_acquirer_pre_patents, 0) > 0
     AND COALESCE(iio.n_inventor_preipc, 0) > 0
     AND COALESCE(aio.n_acquirer_preipc, 0) > 0
    THEN TRUE ELSE FALSE
  END AS vr_common_ipc_observed,
  CASE
    WHEN NOT u.acquirer_resolved THEN NULL
    WHEN COALESCE(apo.n_acquirer_pre_patents, 0) = 0 THEN NULL
    WHEN COALESCE(aio.n_acquirer_preipc, 0) = 0 THEN NULL
    WHEN COALESCE(iio.n_inventor_preipc, 0) = 0 THEN NULL
    ELSE COALESCE(ci.n_common_ipc, 0)
  END AS vr_common_ipc,
  CASE
    WHEN NOT u.acquirer_resolved THEN 'unresolved_acquirer'
    WHEN COALESCE(apo.n_acquirer_pre_patents, 0) = 0 THEN 'no_observed_pre_g_acquirer_patents'
    WHEN COALESCE(aio.n_acquirer_preipc, 0) = 0 THEN 'no_usable_acquirer_ipc_codes'
    WHEN COALESCE(iio.n_inventor_preipc, 0) = 0 THEN 'no_usable_pre_g_inventor_ipc_codes'
    ELSE 'observed'
  END AS vr_common_ipc_missing_reason,
  u.existing_career_age_at_deal,
  u.existing_observed_target_patent_tenure
FROM base_units u
LEFT JOIN career c
  ON c.codinv = u.codinv
LEFT JOIN target_history th
  ON th.codinv = u.codinv
 AND th.deal_id = u.deal_id
LEFT JOIN exclusivity ex
  ON ex.codinv = u.codinv
 AND ex.deal_id = u.deal_id
LEFT JOIN inventor_ipc_obs iio
  ON iio.codinv = u.codinv
 AND iio.deal_id = u.deal_id
LEFT JOIN acquirer_portfolio_obs apo
  ON apo.codinv = u.codinv
 AND apo.deal_id = u.deal_id
LEFT JOIN acquirer_ipc_obs aio
  ON aio.codinv = u.codinv
 AND aio.deal_id = u.deal_id
LEFT JOIN common_ipc ci
  ON ci.codinv = u.codinv
 AND ci.deal_id = u.deal_id
ORDER BY u.deal_id, u.codinv
) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)
", sql_path_12(COVARIATES_PARQUET))

DBI::dbExecute(con, cov_sql)
cov <- read_parquet_12(COVARIATES_PARQUET)
cov$vr_common_ipc_cat <- cut(
  cov$vr_common_ipc,
  breaks = c(-Inf, 0, 3, Inf),
  labels = c("0", "1-3", "4+")
)
cov$log_vr_age <- log(cov$vr_age)
cov$log_vr_tenure <- log(cov$vr_tenure)
write_parquet_12(cov, COVARIATES_PARQUET)

sample_flow <- data.frame(
  stage = c("merged_sample_start", "complete_vr_age", "complete_vr_tenure",
            "complete_vr_exclusivity", "complete_vr_common_ipc", "complete_all_four"),
  n_inventors = c(
    length(unique(cov$codinv)),
    length(unique(cov$codinv[!is.na(cov$vr_age)])),
    length(unique(cov$codinv[!is.na(cov$vr_tenure)])),
    length(unique(cov$codinv[!is.na(cov$vr_exclusivity)])),
    length(unique(cov$codinv[!is.na(cov$vr_common_ipc)])),
    length(unique(cov$codinv[stats::complete.cases(cov[, VR_RAW_COVARS])]))
  ),
  n_deals = c(
    length(unique(cov$deal_id)),
    length(unique(cov$deal_id[!is.na(cov$vr_age)])),
    length(unique(cov$deal_id[!is.na(cov$vr_tenure)])),
    length(unique(cov$deal_id[!is.na(cov$vr_exclusivity)])),
    length(unique(cov$deal_id[!is.na(cov$vr_common_ipc)])),
    length(unique(cov$deal_id[stats::complete.cases(cov[, VR_RAW_COVARS])]))
  )
)
sample_flow$excluded_share_from_start <- 1 - sample_flow$n_inventors / sample_flow$n_inventors[1]
write_audit_12(sample_flow, "sample_flow.csv")

if (sample_flow$n_inventors[1] != EXPECTED_N_INVENTORS ||
    sample_flow$n_deals[1] != EXPECTED_N_DEALS) {
  warning("Starting merged-sample counts differ from expected diagnostics: inventors=",
          sample_flow$n_inventors[1], " deals=", sample_flow$n_deals[1])
}

invariants <- data.frame(
  check = c("one_row_per_codinv_deal", "vr_age_positive", "vr_tenure_positive",
            "vr_exclusivity_in_unit_interval", "common_ipc_nonnegative_integer",
            "exclusivity_denominator_positive_when_observed",
            "unobserved_common_ipc_missing", "existing_age_equivalence",
            "existing_tenure_equivalence"),
  violations = c(
    anyDuplicated(cov[, c("codinv", "deal_id")]),
    sum(!is.na(cov$vr_age) & cov$vr_age <= 0),
    sum(!is.na(cov$vr_tenure) & cov$vr_tenure <= 0),
    sum(!is.na(cov$vr_exclusivity) &
          (cov$vr_exclusivity < 0 | cov$vr_exclusivity > 1)),
    sum(!is.na(cov$vr_common_ipc) &
          (cov$vr_common_ipc < 0 | cov$vr_common_ipc != floor(cov$vr_common_ipc))),
    sum(!is.na(cov$vr_exclusivity) &
          (is.na(cov$exclusivity_denominator) | cov$exclusivity_denominator <= 0)),
    sum(!cov$vr_common_ipc_observed & !is.na(cov$vr_common_ipc)),
    sum(!is.na(cov$vr_age) & !is.na(cov$existing_career_age_at_deal) &
          abs(cov$vr_age - cov$existing_career_age_at_deal) > 0),
    sum(!is.na(cov$vr_tenure) & !is.na(cov$existing_observed_target_patent_tenure) &
          abs(cov$vr_tenure - cov$existing_observed_target_patent_tenure) > 0)
  )
)
invariants$pass <- invariants$violations == 0
write_audit_12(invariants, "covariate_invariants.csv")
if (!all(invariants$pass[1:7])) {
  stop("Hard covariate invariant failed; inspect covariate_invariants.csv")
}

missingness <- do.call(rbind, lapply(
  c(VR_RAW_COVARS, "acquirer_resolved", "acquirer_preportfolio_observed",
    "inventor_preipc_observed", "vr_common_ipc_observed"),
  function(v) {
    data.frame(variable = v, n_missing = sum(is.na(cov[[v]])),
               share_missing = mean(is.na(cov[[v]])))
  }
))
write_audit_12(missingness, "covariate_missingness.csv")

common_missing <- as.data.frame(table(reason = cov$vr_common_ipc_missing_reason,
                                      useNA = "ifany"))
names(common_missing)[2] <- "n"
write_audit_12(common_missing, "common_ipc_missing_reasons.csv")

desc <- do.call(rbind, lapply(VR_RAW_COVARS, function(v) {
  x <- cov[[v]]
  data.frame(
    variable = v, n = sum(!is.na(x)), mean = mean(x, na.rm = TRUE),
    sd = stats::sd(x, na.rm = TRUE), min = min(x, na.rm = TRUE),
    max = max(x, na.rm = TRUE)
  )
}))
paper_means <- data.frame(
  variable = VR_RAW_COVARS,
  paper_mean = c(8.40, 5.32, 0.44, 3.24)
)
desc <- merge(desc, paper_means, by = "variable", all.x = TRUE)
desc$difference_from_paper_mean <- desc$mean - desc$paper_mean
write_audit_12(desc, "covariate_descriptives.csv")

manual_cases <- cov[order(cov$vr_common_ipc_missing_reason, cov$deal_id, cov$codinv),
                    c("codinv", "deal_id", "treatment_year", "acquirer_resolved",
                      "acquirer_preportfolio_observed", "acquirer_preipc_observed",
                      "inventor_preipc_observed", "vr_common_ipc_observed",
                      "vr_common_ipc", "vr_common_ipc_missing_reason")]
manual_cases <- manual_cases[seq_len(min(100L, nrow(manual_cases))), ]
write_audit_12(manual_cases, "common_ipc_manual_cases.csv")

banner_12("12b complete")
message("Covariates: ", COVARIATES_PARQUET)
