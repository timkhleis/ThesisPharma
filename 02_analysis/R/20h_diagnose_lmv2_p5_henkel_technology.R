# Outcome-blind technology-resolution diagnostic for deal 70 and Henkel.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit)
}

for (package in c("DBI", "duckdb")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}
db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cohort <- 2000L
deal_id <- 70L
target_group <- 112513L
henkel_group <- 303292L
con <- DBI::dbConnect(
  duckdb::duckdb(), db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

similarity <- DBI::dbGetQuery(con, sprintf("
WITH weighted AS (
  SELECT CAST(g.id_group AS BIGINT) AS id_group,
         m.resolution, m.ipc_feature,
         SUM(g.patent_count)::DOUBLE AS weight
  FROM group_ipc_year g
  JOIN lmv2_p3_ipc_code_map m USING (ipc_code)
  WHERE g.year BETWEEN %d AND %d
    AND CAST(g.id_group AS BIGINT) IN (%d,%d)
  GROUP BY 1,2,3
), vectors AS (
  SELECT *,
    weight / SUM(weight) OVER (PARTITION BY id_group,resolution)
      AS frequency
  FROM weighted
), norms AS (
  SELECT id_group,resolution,
         SQRT(SUM(frequency*frequency)) AS norm
  FROM vectors GROUP BY 1,2
), dots AS (
  SELECT t.resolution,SUM(t.frequency*c.frequency) AS dot
  FROM vectors t
  JOIN vectors c
    ON c.resolution=t.resolution
   AND c.ipc_feature=t.ipc_feature
   AND c.id_group=%d
  WHERE t.id_group=%d
  GROUP BY 1
)
SELECT %d AS cohort,%d AS deal_id,%d AS target_group,
       %d AS control_group,d.resolution,
       d.dot/(tn.norm*cn.norm) AS cosine,
       1-d.dot/(tn.norm*cn.norm) AS technology_distance
FROM dots d
JOIN norms tn
  ON tn.id_group=%d AND tn.resolution=d.resolution
JOIN norms cn
  ON cn.id_group=%d AND cn.resolution=d.resolution
ORDER BY CASE d.resolution
  WHEN 'ipc4' THEN 1 WHEN 'ipc_main_group' THEN 2 ELSE 3 END",
  cohort - 5L, cohort - 1L, target_group, henkel_group,
  henkel_group, target_group, cohort, deal_id, target_group,
  henkel_group, target_group, henkel_group))

reference <- DBI::dbGetQuery(con, sprintf("
SELECT cosine FROM lmv2_p3_stage1_similarity
WHERE cohort=%d AND deal_id=%d AND target_group=%d
  AND control_group=%d AND resolution='ipc4'",
  cohort, deal_id, target_group, henkel_group))$cosine
computed_ipc4 <- similarity$cosine[
  similarity$resolution == "ipc4"]
if (length(reference) != 1L ||
    abs(reference - computed_ipc4) > 1e-12) {
  stop("Recomputed IPC4 cosine does not match the frozen P3 value")
}

composition <- DBI::dbGetQuery(con, sprintf("
WITH weighted AS (
  SELECT CAST(g.id_group AS BIGINT) AS id_group,
         m.resolution,m.ipc_feature,
         SUM(g.patent_count)::DOUBLE AS weight
  FROM group_ipc_year g
  JOIN lmv2_p3_ipc_code_map m USING (ipc_code)
  WHERE g.year BETWEEN %d AND %d
    AND CAST(g.id_group AS BIGINT) IN (%d,%d)
    AND m.resolution IN ('ipc4','ipc_main_group')
  GROUP BY 1,2,3
)
SELECT id_group,
       CASE id_group WHEN %d THEN 'SmithKline Beecham'
                     WHEN %d THEN 'Henkel' END AS group_name,
       resolution,ipc_feature,weight,
       weight/SUM(weight) OVER
         (PARTITION BY id_group,resolution) AS overall_share,
       ROW_NUMBER() OVER
         (PARTITION BY id_group,resolution ORDER BY weight DESC,ipc_feature)
         AS portfolio_rank
FROM weighted
ORDER BY id_group,resolution,portfolio_rank",
  cohort - 5L, cohort - 1L, target_group, henkel_group,
  target_group, henkel_group))

a61k <- DBI::dbGetQuery(con, sprintf("
WITH weighted AS (
  SELECT CAST(g.id_group AS BIGINT) AS id_group,
         m.ipc_feature,
         SUM(g.patent_count)::DOUBLE AS weight
  FROM group_ipc_year g
  JOIN lmv2_p3_ipc_code_map m USING (ipc_code)
  WHERE g.year BETWEEN %d AND %d
    AND CAST(g.id_group AS BIGINT) IN (%d,%d)
    AND m.resolution='ipc_main_group'
  GROUP BY 1,2
), totals AS (
  SELECT id_group,
         SUM(weight) AS total_weight,
         SUM(weight) FILTER (WHERE ipc_feature LIKE 'A61K%%')
           AS a61k_weight
  FROM weighted GROUP BY id_group
)
SELECT w.id_group,
       CASE w.id_group WHEN %d THEN 'SmithKline Beecham'
                       WHEN %d THEN 'Henkel' END AS group_name,
       w.ipc_feature,w.weight,
       w.weight/t.total_weight AS overall_share,
       w.weight/t.a61k_weight AS within_a61k_share
FROM weighted w JOIN totals t USING(id_group)
WHERE w.ipc_feature LIKE 'A61K%%'
ORDER BY w.id_group,w.weight DESC,w.ipc_feature",
  cohort - 5L, cohort - 1L, target_group, henkel_group,
  target_group, henkel_group))

contributions <- DBI::dbGetQuery(con, sprintf("
WITH weighted AS (
  SELECT CAST(g.id_group AS BIGINT) AS id_group,
         m.resolution,m.ipc_feature,
         SUM(g.patent_count)::DOUBLE AS weight
  FROM group_ipc_year g
  JOIN lmv2_p3_ipc_code_map m USING (ipc_code)
  WHERE g.year BETWEEN %d AND %d
    AND CAST(g.id_group AS BIGINT) IN (%d,%d)
    AND m.resolution IN ('ipc4','ipc_main_group')
  GROUP BY 1,2,3
), vectors AS (
  SELECT *,weight/SUM(weight) OVER
    (PARTITION BY id_group,resolution) AS frequency
  FROM weighted
), shared AS (
  SELECT t.resolution,t.ipc_feature,
         t.frequency AS target_frequency,
         c.frequency AS henkel_frequency,
         t.frequency*c.frequency AS dot_contribution
  FROM vectors t JOIN vectors c
    ON c.resolution=t.resolution
   AND c.ipc_feature=t.ipc_feature
   AND c.id_group=%d
  WHERE t.id_group=%d
)
SELECT *,
       dot_contribution/SUM(dot_contribution) OVER
         (PARTITION BY resolution) AS share_of_shared_dot
FROM shared
ORDER BY resolution,dot_contribution DESC,ipc_feature",
  cohort - 5L, cohort - 1L, target_group, henkel_group,
  henkel_group, target_group))

utils::write.csv(
  similarity, file.path(output_dir, "henkel_skb_similarity_by_resolution.csv"),
  row.names = FALSE)
utils::write.csv(
  composition, file.path(output_dir, "henkel_skb_portfolio_composition.csv"),
  row.names = FALSE)
utils::write.csv(
  a61k, file.path(output_dir, "henkel_skb_a61k_main_groups.csv"),
  row.names = FALSE)
utils::write.csv(
  contributions,
  file.path(output_dir, "henkel_skb_shared_technology_contributions.csv"),
  row.names = FALSE)

message(
  "Henkel diagnostic complete | IPC4=", sprintf("%.4f", computed_ipc4),
  " | main-group=", sprintf(
    "%.4f", similarity$cosine[
      similarity$resolution == "ipc_main_group"]),
  " | IPC7=", sprintf(
    "%.4f", similarity$cosine[
      similarity$resolution == "ipc7"]))
