# Build the descriptive-statistics tables used in the Data section.
# The inventor table uses the status-classified treated cohort and defines
# post-acquisition status from g+1 through g+5, matching the thesis text.
# The target-firm table uses all 345 treated acquisitions in 1993--2010.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
ROOT <- normalizePath(".", mustWork = TRUE)
FOUNDATION <- normalizePath(file.path(".worktrees", "lmv2-1993-amendment", "02_analysis"),
                            mustWork = TRUE)
DB <- normalizePath(file.path(BASE, "output", "thesis_foundation.duckdb"),
                    mustWork = TRUE)
TREATED <- normalizePath(file.path(
  FOUNDATION, "output", "parquet", "derived", "lmv2_treated_primary.parquet"
), mustWork = TRUE)
INV_COV <- normalizePath(file.path(
  FOUNDATION, "output", "parquet", "derived", "lmv2_p3_treated_inventor_units.parquet"
), mustWork = TRUE)
FIRM_COV <- normalizePath(file.path(
  FOUNDATION, "output", "parquet", "derived", "lmv2_p3_firm_units.parquet"
), mustWork = TRUE)
GROUP_YEAR <- normalizePath(file.path(
  FOUNDATION, "output", "parquet", "derived", "lmv2_p3_group_year_patents.parquet"
), mustWork = TRUE)

RESULTS <- file.path(BASE, "output", "results", "data_section")
TABLES <- file.path(ROOT, "thesis_template", "assets", "tables")
dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(TABLES, recursive = TRUE, showWarnings = FALSE)

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

sql_path <- function(x) gsub("'", "''", gsub("\\\\", "/", x))
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = DB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=2")

p_treated <- sql_path(TREATED)
p_inv_cov <- sql_path(INV_COV)
p_firm_cov <- sql_path(FIRM_COV)
p_group_year <- sql_path(GROUP_YEAR)

DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE descriptive_inventor_units AS
WITH b AS (
  SELECT
    CAST(t.codinv AS BIGINT) AS codinv,
    CAST(t.deal_id AS BIGINT) AS deal_id,
    CAST(t.cohort AS INTEGER) AS cohort,
    t.target_group,
    t.acquirer_group,
    t.status_eligible,
    x.patent_count_5y,
    x.active_pre_years,
    x.career_age,
    x.focal_group_tenure - 1 AS focal_group_tenure
  FROM read_parquet('%s') t
  JOIN read_parquet('%s') x USING(codinv, deal_id)
), first_post AS (
  SELECT b.codinv, b.deal_id, MIN(CAST(ia.year AS INTEGER)) AS first_post_year
  FROM b
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = b.codinv
   AND ia.year BETWEEN b.cohort + 1 AND b.cohort + 5
  GROUP BY b.codinv, b.deal_id
), group_stayer AS (
  SELECT DISTINCT b.codinv, b.deal_id
  FROM b
  JOIN first_post fp USING(codinv, deal_id)
  JOIN inventor_affiliation_own ia
    ON CAST(ia.codinv AS BIGINT) = b.codinv
   AND ia.year = fp.first_post_year
   AND ia.resolved_group IN (b.target_group, b.acquirer_group)
), target_company_stayer AS (
  SELECT DISTINCT b.codinv, b.deal_id
  FROM b
  JOIN first_post fp USING(codinv, deal_id)
  JOIN deal_target_company_strict dtc ON dtc.deal_id = b.deal_id
  JOIN patent_company_link pcl
    ON CAST(pcl.compcod AS BIGINT) = dtc.target_compcod
   AND pcl.year = fp.first_post_year
  JOIN patent_inventor pi
    ON pi.appln_id = pcl.appln_id
   AND CAST(pi.codinv AS BIGINT) = b.codinv
), pre_apps AS (
  SELECT DISTINCT
    b.codinv, b.deal_id, b.cohort,
    CAST(pe.appln_id AS BIGINT) AS appln_id,
    pe.patent_year,
    pe.fwd_cits5,
    pe.quality_index_4
  FROM b
  JOIN patent_inventor_enriched pie
    ON CAST(pie.codinv AS BIGINT) = b.codinv
   AND pie.year BETWEEN b.cohort - 5 AND b.cohort - 1
  JOIN patent_enriched pe ON pe.appln_id = pie.appln_id
), quality_year AS (
  SELECT
    codinv, deal_id, patent_year,
    COUNT(*) AS patents_in_year,
    COUNT(fwd_cits5) AS citations_covered,
    SUM(fwd_cits5) AS citations_total_year,
    COUNT(quality_index_4) AS pqii_covered,
    CASE WHEN COUNT(quality_index_4) > 0
      THEN SUM(quality_index_4) * COUNT(*) / COUNT(quality_index_4)
    END AS pqii_scaled_total_year
  FROM pre_apps
  GROUP BY codinv, deal_id, patent_year
), quality_patent_agg AS (
  SELECT
    pa.codinv, pa.deal_id,
    COUNT(DISTINCT pa.appln_id) AS patent_applications_check,
    SUM(pa.fwd_cits5) AS citations_total,
    AVG(pa.fwd_cits5) AS citations_per_patent,
    AVG(pa.quality_index_4) AS pqii_per_patent
  FROM pre_apps pa
  GROUP BY pa.codinv, pa.deal_id
), quality_scaled_agg AS (
  SELECT codinv, deal_id,
         SUM(pqii_scaled_total_year) AS pqii_scaled_total
  FROM quality_year
  GROUP BY codinv, deal_id
), quality_agg AS (
  SELECT p.*, s.pqii_scaled_total
  FROM quality_patent_agg p
  LEFT JOIN quality_scaled_agg s USING(codinv, deal_id)
), pre_coinventors AS (
  SELECT
    pa.codinv, pa.deal_id,
    COUNT(DISTINCT CAST(pi.codinv AS BIGINT)) FILTER (
      WHERE CAST(pi.codinv AS BIGINT) <> pa.codinv
    ) AS distinct_coinventors
  FROM pre_apps pa
  JOIN patent_inventor pi ON pi.appln_id = pa.appln_id
  GROUP BY pa.codinv, pa.deal_id
)
SELECT
  b.*,
  CASE
    WHEN NOT b.status_eligible THEN 'NOT_STATUS_ELIGIBLE'
    WHEN fp.first_post_year IS NULL THEN 'NO_POST_ACQUISITION_PATENT'
    WHEN gs.codinv IS NOT NULL OR ts.codinv IS NOT NULL THEN 'INITIALLY_RETAINED'
    ELSE 'LEAVER'
  END AS status_type,
  qa.patent_applications_check,
  qa.citations_total,
  qa.citations_per_patent,
  qa.pqii_scaled_total,
  qa.pqii_per_patent,
  COALESCE(pc.distinct_coinventors, 0) AS distinct_coinventors
FROM b
LEFT JOIN first_post fp USING(codinv, deal_id)
LEFT JOIN group_stayer gs USING(codinv, deal_id)
LEFT JOIN target_company_stayer ts USING(codinv, deal_id)
LEFT JOIN quality_agg qa USING(codinv, deal_id)
LEFT JOIN pre_coinventors pc USING(codinv, deal_id)
", p_treated, p_inv_cov))

status_check <- DBI::dbGetQuery(con, "
  SELECT status_type, COUNT(*) AS n
  FROM descriptive_inventor_units
  GROUP BY status_type ORDER BY status_type
")
expected <- c(
  INITIALLY_RETAINED = 3220L,
  LEAVER = 1191L,
  NO_POST_ACQUISITION_PATENT = 24596L,
  NOT_STATUS_ELIGIBLE = 687L
)
observed <- setNames(status_check$n, status_check$status_type)
if (!identical(as.integer(observed[names(expected)]), as.integer(expected))) {
  stop("Post-acquisition status counts do not match the thesis sample.")
}
patent_count_mismatch <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS n
  FROM descriptive_inventor_units
  WHERE patent_applications_check IS DISTINCT FROM patent_count_5y
")$n
if (patent_count_mismatch != 0L) {
  stop("Patent-level quality linkage does not reproduce the certified pre-deal patent count.")
}

inventor_variables <- data.frame(
  variable = c(
    "patent_count_5y", "active_pre_years", "citations_total",
    "citations_per_patent", "pqii_scaled_total", "pqii_per_patent",
    "career_age", "focal_group_tenure", "distinct_coinventors"
  ),
  label = c(
    "Patent applications", "Active patenting years",
    "Five-year forward citations", "Forward citations per patent",
    "OECD PQII total", "OECD PQII per patent",
    "Career age (years)", "Target-affiliation tenure (years)",
    "Distinct co-inventors"
  ),
  section = c(
    "Patenting output", "Patenting output",
    "Patent quality", "Patent quality", "Patent quality", "Patent quality",
    "Experience and collaboration", "Experience and collaboration",
    "Experience and collaboration"
  ),
  digits = c(2L, 2L, 2L, 2L, 3L, 3L, 2L, 2L, 2L),
  stringsAsFactors = FALSE
)

summarise_one <- function(x) {
  x <- x[is.finite(x)]
  data.frame(
    n = length(x), mean = mean(x), sd = stats::sd(x),
    median = stats::median(x), p90 = unname(stats::quantile(x, 0.90)),
    max = max(x)
  )
}

inv_data <- DBI::dbGetQuery(con, "
  SELECT * FROM descriptive_inventor_units WHERE status_eligible
")
if (any(inv_data$focal_group_tenure < 0, na.rm = TRUE) ||
    any(inv_data$focal_group_tenure > inv_data$career_age, na.rm = TRUE)) {
  stop("Target-affiliation tenure is not aligned with career age at g-1.")
}
inv_overall <- do.call(rbind, lapply(seq_len(nrow(inventor_variables)), function(i) {
  v <- inventor_variables$variable[i]
  cbind(inventor_variables[i, ], summarise_one(inv_data[[v]]))
}))
rownames(inv_overall) <- NULL

status_order <- c("INITIALLY_RETAINED", "LEAVER", "NO_POST_ACQUISITION_PATENT")
inv_by_status <- do.call(rbind, lapply(seq_len(nrow(inventor_variables)), function(i) {
  v <- inventor_variables$variable[i]
  do.call(rbind, lapply(status_order, function(s) {
    z <- inv_data[inv_data$status_type == s, v]
    cbind(inventor_variables[i, ], status_type = s, summarise_one(z))
  }))
}))
rownames(inv_by_status) <- NULL

utils::write.csv(inv_overall,
                 file.path(RESULTS, "inventor_descriptive_statistics.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(inv_by_status,
                 file.path(RESULTS, "inventor_descriptive_statistics_by_status.csv"),
                 row.names = FALSE, na = "")

deals <- DBI::dbGetQuery(con, sprintf("
  WITH t AS (
    SELECT
      CAST(deal_id AS BIGINT) AS deal_id,
      CAST(cohort AS INTEGER) AS acquisition_year,
      MAX(deal_value) / 1000000.0 AS deal_value_billions,
      COUNT(*) AS affected_inventors
    FROM read_parquet('%s')
    GROUP BY deal_id, cohort
  ), f AS (
    SELECT CAST(deal_id AS BIGINT) AS deal_id,
           CAST(id_group AS BIGINT) AS target_group,
           patent_stock_5y, inventor_count_5y
    FROM read_parquet('%s')
    WHERE role = 'treated'
  ), first_patent AS (
    SELECT CAST(id_group AS BIGINT) AS target_group,
           MIN(year) AS first_observed_patent_year
    FROM read_parquet('%s')
    WHERE patent_count > 0
    GROUP BY id_group
  )
  SELECT
    t.*,
    f.patent_stock_5y AS target_patents_pre5,
    f.inventor_count_5y AS target_inventors_pre5,
    CAST(f.patent_stock_5y AS DOUBLE) / NULLIF(f.inventor_count_5y, 0)
      AS patents_per_target_inventor,
    t.acquisition_year - fp.first_observed_patent_year
      AS observed_target_patenting_age
  FROM t JOIN f USING(deal_id)
  LEFT JOIN first_patent fp USING(target_group)
  ORDER BY acquisition_year, deal_id
", p_treated, p_firm_cov, p_group_year))
if (nrow(deals) != 345L || sum(deals$affected_inventors) != 29694L) {
  stop("Target-firm sample does not match the certified treated cohort.")
}

firm_variables <- data.frame(
  variable = c(
    "target_inventors_pre5", "target_patents_pre5",
    "patents_per_target_inventor", "observed_target_patenting_age"
  ),
  label = c(
    "Target-group inventors",
    "Target patent applications",
    "Patent applications per inventor",
    "Observed patenting age"
  ),
  digits = c(1L, 1L, 2L, 1L),
  stringsAsFactors = FALSE
)
firm_stats <- do.call(rbind, lapply(seq_len(nrow(firm_variables)), function(i) {
  v <- firm_variables$variable[i]
  cbind(firm_variables[i, ], summarise_one(deals[[v]]))
}))
rownames(firm_stats) <- NULL

shares <- sort(deals$affected_inventors / sum(deals$affected_inventors),
               decreasing = TRUE)
hhi <- sum(shares^2)
concentration <- data.frame(
  measure = c(
    "Inventor-share HHI", "Effective number of equally sized deals",
    "Largest deal share", "Top-five deal share", "Top-ten deal share"
  ),
  value = c(hhi, 1 / hhi, shares[1], sum(shares[1:5]), sum(shares[1:10])),
  stringsAsFactors = FALSE
)

utils::write.csv(firm_stats,
                 file.path(RESULTS, "target_firm_descriptive_statistics.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(concentration,
                 file.path(RESULTS, "target_firm_inventor_concentration.csv"),
                 row.names = FALSE, na = "")

fmt <- function(x, digits) {
  formatC(x, digits = digits, format = "f", big.mark = ",")
}
fmt_n <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)

inventor_tex <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Pre-Acquisition Characteristics of Target Inventors}",
  "    \\label{tab:inventor_descriptives}",
  "    \\begin{threeparttable}",
  "        \\small",
  "        \\renewcommand{\\arraystretch}{1.12}",
  "        \\begin{tabular*}{0.90\\textwidth}{@{\\extracolsep{\\fill}}lrrrr@{}}",
  "            \\toprule",
  "            Variable & $N$ & Mean & SD & Median \\\\",
  "            \\midrule"
)
last_section <- ""
for (i in seq_len(nrow(inv_overall))) {
  r <- inv_overall[i, ]
  if (r$section != last_section) {
    if (last_section != "") inventor_tex <- c(inventor_tex, "            \\addlinespace[0.45em]")
    inventor_tex <- c(inventor_tex, sprintf(
      "            \\multicolumn{5}{@{}l}{\\itshape %s} \\\\", r$section
    ))
    last_section <- r$section
  }
  inventor_tex <- c(inventor_tex, sprintf(
    "            \\quad %s & %s & %s & %s & %s \\\\",
    r$label, fmt_n(r$n), fmt(r$mean, r$digits), fmt(r$sd, r$digits),
    fmt(r$median, r$digits)
  ))
}
inventor_tex <- c(
  inventor_tex,
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\footnotesize",
  paste0(
    "            \\item \\textit{Notes:} The table covers the 29{,}007 status-classified target inventors. ",
    "Except for career age and target-affiliation tenure, all variables are measured over $g-5,\\ldots,g-1$. ",
    "Target-affiliation tenure is the number of years between the inventor's first observed target-linked patent and year $g-1$; it measures observed patent affiliation rather than employment tenure. Citation and PQII statistics use available quality records. ",
    "The PQII total scales partially covered patenting years by the share of patents with a valid Index~4 score."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
writeLines(inventor_tex,
           file.path(TABLES, "inventor_descriptive_statistics.tex"),
           useBytes = TRUE)

panel_b_vars <- c(
  "patent_count_5y", "active_pre_years", "citations_per_patent",
  "pqii_per_patent", "career_age", "focal_group_tenure"
)
status_tex <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Pre-Acquisition Inventor Characteristics by Post-Acquisition Status}",
  "    \\label{tab:inventor_descriptives_by_status}",
  "    \\begin{threeparttable}",
  "        \\small",
  "        \\renewcommand{\\arraystretch}{1.05}",
  "        \\begin{tabular*}{0.94\\textwidth}{@{\\extracolsep{\\fill}}l*{3}{>{\\centering\\arraybackslash}p{2.4cm}}@{}}",
  "            \\toprule",
  "            & \\multicolumn{3}{c}{Post-acquisition status} \\\\",
  "            \\cmidrule(l){2-4}",
  "            Variable & Initially retained & Leavers & No post-deal patent \\\\",
  "            \\midrule"
)
last_section <- ""
for (v in panel_b_vars) {
  meta <- inventor_variables[inventor_variables$variable == v, ]
  rows <- lapply(status_order, function(s) {
    inv_by_status[inv_by_status$variable == v & inv_by_status$status_type == s, ]
  })
  if (meta$section != last_section) {
    if (last_section != "") status_tex <- c(status_tex, "            \\addlinespace[0.40em]")
    status_tex <- c(status_tex, sprintf(
      "            \\multicolumn{4}{@{}l}{\\itshape %s} \\\\", meta$section
    ))
    last_section <- meta$section
  }
  status_tex <- c(status_tex, sprintf(
    "            \\quad %s & %s & %s & %s \\\\",
    meta$label,
    fmt(rows[[1]]$mean, meta$digits), fmt(rows[[2]]$mean, meta$digits),
    fmt(rows[[3]]$mean, meta$digits)
  ), sprintf(
    "            & {\\scriptsize (%s)} & {\\scriptsize (%s)} & {\\scriptsize (%s)} \\\\",
    fmt(rows[[1]]$sd, meta$digits), fmt(rows[[2]]$sd, meta$digits),
    fmt(rows[[3]]$sd, meta$digits)
  ))
}
status_tex <- c(
  status_tex,
  "            \\addlinespace[0.25em]",
  "            Inventors & 3{,}220 & 1{,}191 & 24{,}596 \\\\",
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\footnotesize",
  paste0(
    "            \\item \\textit{Notes:} Entries report means with standard deviations in parentheses. ",
    "All variables are measured before the acquisition over $g-5,\\ldots,g-1$, except for career age and target-affiliation tenure. ",
    "Target-affiliation tenure is the number of years between the inventor's first observed target-linked patent and year $g-1$; it measures observed patent affiliation rather than employment tenure. ",
    "The columns classify inventors from their first observed patent during $g+1,\\ldots,g+5$; the table therefore describes pre-acquisition selection into post-acquisition status. ",
    "Citation and PQII statistics use the available quality records and have smaller variable-specific sample sizes."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
writeLines(status_tex,
           file.path(TABLES, "inventor_descriptive_statistics_by_status.tex"),
           useBytes = TRUE)

firm_tex <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Pre-Acquisition Characteristics of Target Firms}",
  "    \\label{tab:target_firm_descriptives}",
  "    \\begin{threeparttable}",
  "        \\small",
  "        \\renewcommand{\\arraystretch}{1.10}",
  "        \\begin{tabular*}{0.94\\textwidth}{@{\\extracolsep{\\fill}}lrrrrrr@{}}",
  "            \\toprule",
  "            Variable & $N$ & Mean & SD & Median & P90 & Maximum \\\\",
  "            \\midrule"
)
for (i in seq_len(nrow(firm_stats))) {
  r <- firm_stats[i, ]
  decimal_variable <- r$variable == "patents_per_target_inventor"
  median_digits <- if (decimal_variable) r$digits else 0L
  max_digits <- if (decimal_variable) r$digits else 0L
  firm_tex <- c(firm_tex, sprintf(
    "            %s & %s & %s & %s & %s & %s & %s \\\\",
    r$label, fmt_n(r$n), fmt(r$mean, r$digits), fmt(r$sd, r$digits),
    fmt(r$median, median_digits), fmt(r$p90, r$digits), fmt(r$max, max_digits)
  ))
}
firm_tex <- c(
  firm_tex,
  "            \\bottomrule",
  "        \\end{tabular*}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\footnotesize",
  paste0(
    "            \\item \\textit{Notes:} The table contains one target-firm observation for each of the 345 acquisitions. ",
    "Target-group inventors and distinct EPO patent applications are measured over $g-5,\\ldots,g-1$. ",
    "Observed patenting age is the number of years between the target group's first patent in the 1988--2015 panel and the acquisition year. ",
    "It is therefore left-censored for targets that patented before 1988 and should not be interpreted as corporate age."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
writeLines(firm_tex,
           file.path(TABLES, "deal_descriptive_statistics.tex"),
           useBytes = TRUE)

concentration_tex <- c(
  "\\begin{table}[!htbp]",
  "    \\centering",
  "    \\caption{Concentration of Target Inventors Across Acquisition Deals}",
  "    \\label{tab:deal_concentration_appendix}",
  "    \\begin{threeparttable}",
  "        \\small",
  "        \\begin{tabular}{lr}",
  "            \\toprule",
  "            Measure & Value \\\\",
  "            \\midrule",
  sprintf("            Inventor-share HHI (points) & %.0f \\\\", 10000 * hhi),
  sprintf("            Effective number of equally sized deals & %.1f \\\\", 1 / hhi),
  sprintf("            Largest deal share & %.1f\\%% \\\\", 100 * shares[1]),
  sprintf("            Top-five deal share & %.1f\\%% \\\\", 100 * sum(shares[1:5])),
  sprintf("            Top-ten deal share & %.1f\\%% \\\\", 100 * sum(shares[1:10])),
  "            \\bottomrule",
  "        \\end{tabular}",
  "        \\begin{tablenotes}[flushleft]",
  "            \\footnotesize",
  paste0(
    "            \\item \\textit{Notes:} Concentration is calculated from each deal's share of the 29{,}694 recruited target inventors. ",
    "The HHI is reported on the conventional 0--10{,}000-point scale."
  ),
  "        \\end{tablenotes}",
  "    \\end{threeparttable}",
  "\\end{table}"
)
writeLines(concentration_tex,
           file.path(TABLES, "deal_concentration_appendix.tex"),
           useBytes = TRUE)

message("Descriptive-statistics tables written to: ", TABLES)
