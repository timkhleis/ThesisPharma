# Phase 3a — Build own inventor affiliation resolution
#
# Goal:
#   Create one resolved employer group per inventor-year, approximating the
#   Cassi-Ornaghi Step IV affiliation resolution.
#
# Run from project root:
#   Rscript 02_analysis/R/04a_build_inventor_affiliation.R
#
# Outputs:
#   DuckDB table : inventor_affiliation_own
#   Parquet      : 02_analysis/output/parquet/derived/inventor_affiliation_own.parquet
#   Audit CSVs   : 02_analysis/output/audit/inventor_affiliation_own/

BASE <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
PARQUET <- file.path(BASE, "output", "parquet", "derived")
AUDIT <- file.path(BASE, "output", "audit", "inventor_affiliation_own")

source(file.path(BASE, "R", "00_utils.R"))
load_packages()
library(data.table)
library(duckdb)
dir.create(PARQUET, recursive = TRUE, showWarnings = FALSE)
dir.create(AUDIT, recursive = TRUE, showWarnings = FALSE)

banner <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB)
on.exit({ DBI::dbDisconnect(con, shutdown = TRUE) }, add = TRUE)

banner("PHASE 3a — INVENTOR AFFILIATION RESOLUTION")


# ── 1. Candidate inventor-year-group rows ─────────────────────────────────
section("Building candidate inventor-year-group rows")

candidate_sql <- "
SELECT
  pi.codinv,
  pcl.year,
  pcl.id_group,
  COUNT(DISTINCT pi.appln_id) AS group_patent_count
FROM patent_inventor AS pi
JOIN patent_company_link AS pcl
  ON pi.appln_id = pcl.appln_id
WHERE pcl.id_group IS NOT NULL
  AND pcl.year IS NOT NULL
GROUP BY pi.codinv, pcl.year, pcl.id_group
"

candidates <- data.table::as.data.table(DBI::dbGetQuery(con, candidate_sql))
data.table::setorder(candidates, codinv, year, id_group)

message("Candidate rows: ", format(nrow(candidates), big.mark = ","))
message("Candidate inventor-years: ",
        format(uniqueN(candidates, by = c("codinv", "year")), big.mark = ","))


# ── 2. Inventor modal career group ────────────────────────────────────────
section("Computing modal career group")

career_modal <- candidates[
  ,
  .(
    career_group_patent_count = sum(group_patent_count),
    career_group_year_count = uniqueN(year)
  ),
  by = .(codinv, id_group)
]

data.table::setorder(
  career_modal,
  codinv,
  -career_group_patent_count,
  -career_group_year_count,
  id_group
)

career_modal <- career_modal[
  ,
  .SD[1],
  by = codinv
][
  ,
  .(
    codinv,
    modal_career_group = id_group,
    modal_career_group_patent_count = career_group_patent_count,
    modal_career_group_year_count = career_group_year_count
  )
]


# ── 3. Collapse to inventor-year candidates ───────────────────────────────
section("Collapsing candidates to inventor-year grain")

candidate_year <- candidates[
  ,
  {
    ord <- order(id_group)
    .(
      candidate_group_count = .N,
      candidate_group_list = paste(id_group[ord], collapse = ";"),
      candidate_groups = list(id_group[ord]),
      candidate_counts = list(group_patent_count[ord]),
      candidate_patent_count = sum(group_patent_count),
      max_group_patent_count = max(group_patent_count),
      n_groups_at_max_count = sum(group_patent_count == max(group_patent_count))
    )
  },
  by = .(codinv, year)
]

candidate_year <- merge(candidate_year, career_modal, by = "codinv", all.x = TRUE)
data.table::setorder(candidate_year, codinv, year)


# ── 4. Resolve affiliation by inventor career ─────────────────────────────
section("Resolving affiliation with career-continuity rules")

resolve_one_inventor <- function(dt) {
  dt <- data.table::copy(dt)
  data.table::setorder(dt, year)
  n <- nrow(dt)
  resolved <- rep(NA_real_, n)
  resolved_by <- rep(NA_character_, n)

  # Direct assignment for non-ambiguous years.
  unique_idx <- which(dt$candidate_group_count == 1)
  if (length(unique_idx) > 0) {
    resolved[unique_idx] <- vapply(dt$candidate_groups[unique_idx], `[`, numeric(1), 1)
    resolved_by[unique_idx] <- "unique"
  }

  # Forward pass: prefer previous resolved group when present.
  if (n > 0) {
    for (i in seq_len(n)) {
      if (!is.na(resolved[i])) next
      if (i > 1 && !is.na(resolved[i - 1]) &&
          resolved[i - 1] %in% dt$candidate_groups[[i]]) {
        resolved[i] <- resolved[i - 1]
        resolved_by[i] <- "previous_year"
      }
    }
  }

  # Backward pass: prefer next resolved group for remaining years.
  if (n > 1) {
    for (i in seq(from = n, to = 1)) {
      if (!is.na(resolved[i])) next
      if (i < n && !is.na(resolved[i + 1]) &&
          resolved[i + 1] %in% dt$candidate_groups[[i]]) {
        resolved[i] <- resolved[i + 1]
        resolved_by[i] <- "next_year"
      }
    }
  }

  # Modal career group.
  modal_idx <- which(is.na(resolved))
  if (length(modal_idx) > 0) {
    for (i in modal_idx) {
      modal_group <- dt$modal_career_group[i]
      if (!is.na(modal_group) && modal_group %in% dt$candidate_groups[[i]]) {
        resolved[i] <- modal_group
        resolved_by[i] <- "modal_career"
      }
    }
  }

  # Highest patent count in inventor-year, only if unique maximum.
  count_idx <- which(is.na(resolved) & dt$n_groups_at_max_count == 1)
  if (length(count_idx) > 0) {
    for (i in count_idx) {
      max_pos <- which.max(dt$candidate_counts[[i]])
      resolved[i] <- dt$candidate_groups[[i]][max_pos]
      resolved_by[i] <- "year_patent_count"
    }
  }

  # Deterministic final tie-breaker.
  tie_idx <- which(is.na(resolved))
  if (length(tie_idx) > 0) {
    resolved[tie_idx] <- vapply(dt$candidate_groups[tie_idx], min, numeric(1), na.rm = TRUE)
    resolved_by[tie_idx] <- "numeric_tiebreak"
  }

  dt[
    ,
    `:=`(
      resolved_group = resolved,
      resolved_by = resolved_by
    )
  ]
  dt
}

ambiguous_inventors <- candidate_year[
  candidate_group_count > 1,
  unique(codinv)
]

message("Inventors with at least one ambiguous year: ",
        format(length(ambiguous_inventors), big.mark = ","))

unambiguous_affiliation <- candidate_year[
  !codinv %in% ambiguous_inventors
]

if (nrow(unambiguous_affiliation) > 0) {
  unambiguous_affiliation[
    ,
    `:=`(
      resolved_group = vapply(candidate_groups, `[`, numeric(1), 1),
      resolved_by = "unique"
    )
  ]
}

ambiguous_affiliation <- candidate_year[
  codinv %in% ambiguous_inventors,
  resolve_one_inventor(.SD),
  by = codinv
]

affiliation <- data.table::rbindlist(
  list(unambiguous_affiliation, ambiguous_affiliation),
  use.names = TRUE
)


# ── 5. Add resolved-group patent count and final columns ──────────────────
section("Finalising resolved affiliation table")

resolved_counts <- candidates[
  ,
  .(
    codinv,
    year,
    resolved_group = id_group,
    resolved_group_patent_count = group_patent_count
  )
]

affiliation <- merge(
  affiliation,
  resolved_counts,
  by = c("codinv", "year", "resolved_group"),
  all.x = TRUE
)

affiliation[
  ,
  affiliation_ambiguous := candidate_group_count > 1
]

affiliation_out <- affiliation[
  ,
  .(
    codinv,
    year,
    candidate_group_count,
    candidate_group_list,
    resolved_group,
    resolved_by,
    affiliation_ambiguous,
    candidate_patent_count,
    resolved_group_patent_count
  )
]

data.table::setorder(affiliation_out, codinv, year)


# ── 6. Acceptance checks ─────────────────────────────────────────────────
section("Acceptance checks")

dup_keys <- affiliation_out[
  ,
  .N,
  by = .(codinv, year)
][N > 1]

missing_resolved <- affiliation_out[is.na(resolved_group), .N]

resolved_in_candidates <- affiliation[
  ,
  resolved_group %in% candidate_groups[[1]],
  by = .(codinv, year)
][V1 == FALSE]

message("Duplicate codinv-year rows: ", nrow(dup_keys))
message("Rows with missing resolved_group: ", missing_resolved)
message("Rows where resolved_group not in candidate list: ", nrow(resolved_in_candidates))

if (nrow(dup_keys) > 0 ||
    missing_resolved > 0 ||
    nrow(resolved_in_candidates) > 0) {
  stop("Affiliation acceptance checks failed.")
}


# ── 7. Audit outputs ─────────────────────────────────────────────────────
section("Writing audit CSVs")

candidate_group_summary <- affiliation_out[
  ,
  .(n_inventor_years = .N),
  by = candidate_group_count
][order(candidate_group_count)]

resolved_by_summary <- affiliation_out[
  ,
  .(n_inventor_years = .N),
  by = resolved_by
][order(-n_inventor_years)]

reference_overlap <- data.table::as.data.table(DBI::dbGetQuery(con, "
SELECT
  codinv,
  year,
  id_group AS reference_group,
  type
FROM inventor_status_reference
WHERE type <> 'last year'
"))

validation <- merge(
  reference_overlap,
  affiliation_out[, .(codinv, year, resolved_group, resolved_by,
                      candidate_group_count, candidate_group_list)],
  by = c("codinv", "year"),
  all.x = FALSE,
  all.y = FALSE
)

agreement_summary <- validation[
  ,
  .(
    n_rows = .N,
    n_match = sum(reference_group == resolved_group, na.rm = TRUE),
    match_rate = mean(reference_group == resolved_group, na.rm = TRUE)
  )
]

agreement_by_type <- validation[
  ,
  .(
    n_rows = .N,
    n_match = sum(reference_group == resolved_group, na.rm = TRUE),
    match_rate = mean(reference_group == resolved_group, na.rm = TRUE)
  ),
  by = type
][order(type)]

t_stayer_agreement <- validation[
  type == "T_STAYER",
  .(
    n_rows = .N,
    n_match = sum(reference_group == resolved_group, na.rm = TRUE),
    match_rate = mean(reference_group == resolved_group, na.rm = TRUE)
  )
]

disagreement_examples <- validation[
  reference_group != resolved_group
][
  order(type, codinv, year)
][
  1:min(.N, 500)
]

write_csv(candidate_group_summary, file.path(AUDIT, "candidate_group_count_summary.csv"))
write_csv(resolved_by_summary, file.path(AUDIT, "resolved_by_summary.csv"))
write_csv(agreement_summary, file.path(AUDIT, "reference_agreement_overall.csv"))
write_csv(agreement_by_type, file.path(AUDIT, "reference_agreement_by_type.csv"))
write_csv(t_stayer_agreement, file.path(AUDIT, "reference_agreement_t_stayer.csv"))
write_csv(disagreement_examples, file.path(AUDIT, "reference_disagreement_examples.csv"))

message("Candidate group summary:")
print(candidate_group_summary)
message("Resolved-by summary:")
print(resolved_by_summary)
message("Reference agreement overall:")
print(agreement_summary)
message("Reference agreement for T_STAYER:")
print(t_stayer_agreement)


# ── 8. Write output table and parquet ────────────────────────────────────
section("Writing inventor_affiliation_own to DuckDB and Parquet")

DBI::dbWriteTable(con, "inventor_affiliation_own", as.data.frame(affiliation_out), overwrite = TRUE)
parquet_file <- file.path(PARQUET, "inventor_affiliation_own.parquet")
parquet_sql <- gsub("\\\\", "/", parquet_file)
DBI::dbExecute(
  con,
  sprintf(
    "COPY inventor_affiliation_own TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
    parquet_sql
  )
)
message("Written: ", parquet_file)

message("\n", strrep("=", 60))
message("Phase 3a complete. inventor_affiliation_own is ready for status reconstruction.")
message(strrep("=", 60), "\n")
