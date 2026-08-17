# Run the frozen recruitment-composition diagnostics B0-B2.

.libPaths(c(normalizePath(".r_libs", mustWork = TRUE), .libPaths()))
suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(fixest)
  library(fwildclusterboot)
  library(digest)
})
source(file.path("02_analysis", "R", "50a_lmv2_recruitment_composition_config.R"))

sql_quote <- function(x) paste0("'", gsub("'", "''", normalizePath(x, winslash = "/", mustWork = FALSE)), "'")
out_dir <- LMV2_RECRUIT_PATHS$output
dir.create(file.path(out_dir, "results"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "manifests"), recursive = TRUE, showWarnings = FALSE)

history_path <- file.path(out_dir, "data", "recruitment_history.parquet")
if (!file.exists(history_path)) stop("Run 50b before 50c")

panel_glob <- function(spec) {
  root <- switch(spec,
    p5a = LMV2_RECRUIT_PATHS$p5a_panels,
    loyo_m3 = file.path(LMV2_RECRUIT_PATHS$loyo_m3_panels, "panel_matched"),
    count_active = file.path(LMV2_RECRUIT_PATHS$count_active_panels, "panel_matched"))
  file.path(root, "*.parquet")
}

con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "SET threads=4")
dbExecute(con, "SET memory_limit='9GB'")

dbExecute(con, sprintf("CREATE TEMP TABLE hist AS SELECT * FROM read_parquet(%s)", sql_quote(history_path)))

make_weight_table <- function(spec, reweight = FALSE) {
  nm <- paste0("w_", spec, if (reweight) "_entry" else "_parent")
  dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", nm))
  if (!reweight) {
    dbExecute(con, sprintf("
      CREATE TEMP TABLE %s AS
      SELECT *, weight AS analysis_weight, 1.0 AS entry_tilt
      FROM hist WHERE specification='%s'", nm, spec))
    return(nm)
  }
  dbExecute(con, sprintf("
    CREATE TEMP TABLE %1$s AS
    WITH mass AS (
      SELECT cohort, arm, sum(weight) AS arm_mass
      FROM hist WHERE specification='%2$s' GROUP BY ALL
    ), shares AS (
      SELECT h.cohort, h.arm, h.symmetric_entry_bin,
             sum(h.weight)/max(m.arm_mass) AS share
      FROM hist h JOIN mass m USING (cohort,arm)
      WHERE h.specification='%2$s'
      GROUP BY h.cohort,h.arm,h.symmetric_entry_bin
    ), factors AS (
      SELECT t.cohort, t.symmetric_entry_bin,
             t.share/c.share AS entry_tilt
      FROM shares t JOIN shares c USING (cohort,symmetric_entry_bin)
      WHERE t.arm='treated' AND c.arm='control' AND c.share>0
    )
    SELECT h.*, CASE WHEN h.arm='treated' THEN h.weight
                     ELSE h.weight*f.entry_tilt END AS analysis_weight,
           CASE WHEN h.arm='treated' THEN 1.0 ELSE f.entry_tilt END AS entry_tilt
    FROM hist h LEFT JOIN factors f USING (cohort,symmetric_entry_bin)
    WHERE h.specification='%2$s'", nm, spec))
  bad <- dbGetQuery(con, sprintf("
    SELECT count(*) AS n FROM %s
    WHERE analysis_weight IS NULL OR NOT isfinite(analysis_weight) OR analysis_weight<=0", nm))$n
  if (bad != 0) stop("Entry calibration is infeasible for ", spec)
  nm
}

make_pair_table <- function(spec, weights, adjustment = "none") {
  nm <- paste0("pairs_", spec, "_", adjustment, "_", sub("^w_[^_]+_?", "", weights))
  panel <- sql_quote(panel_glob(spec))
  adjust_e <- if (adjustment == "entry_subtract")
    "CAST(e.patent_count AS DOUBLE)-CAST(e.event_time=h.symmetric_entry_event AS INTEGER)" else
    "CAST(e.patent_count AS DOUBLE)"
  adjust_r <- if (adjustment == "entry_subtract")
    "CAST(r.patent_count AS DOUBLE)-CAST(r.event_time=h.symmetric_entry_event AS INTEGER)" else
    "CAST(r.patent_count AS DOUBLE)"
  dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", nm))
  dbExecute(con, sprintf("
    CREATE TEMP TABLE %1$s AS
    SELECT e.deal_id::INTEGER AS deal_id, e.cohort::INTEGER AS cohort,
           e.arm, e.codinv::BIGINT AS codinv, e.event_time::INTEGER AS event_time,
           w.analysis_weight AS weight, h.symmetric_entry_bin,
           (%2$s)-(%3$s) AS dy
    FROM read_parquet(%4$s) e
    JOIN read_parquet(%4$s) r
      ON r.cohort=e.cohort AND r.deal_id=e.deal_id AND r.arm=e.arm
     AND r.codinv=e.codinv AND r.event_time=-1
    JOIN %5$s w
      ON w.cohort=e.cohort AND w.deal_id=e.deal_id AND w.arm=e.arm AND w.codinv=e.codinv
    JOIN hist h
      ON h.specification='%6$s' AND h.cohort=e.cohort AND h.deal_id=e.deal_id
     AND h.arm=e.arm AND h.codinv=e.codinv
    WHERE e.event_time<>-1 AND e.patent_count IS NOT NULL AND r.patent_count IS NOT NULL",
    nm, adjust_e, adjust_r, panel, weights, spec))
  nm
}

estimate_path <- function(pair_table, label) {
  stats_name <- paste0(pair_table, "_stats")
  dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE %1$s AS
    WITH dm AS (
      SELECT cohort,sum(weight) AS m FROM %2$s WHERE arm='treated' GROUP BY cohort
    ), q AS (SELECT cohort,m/sum(m) OVER() AS q FROM dm),
    a AS (
      SELECT cohort,event_time,arm,sum(weight) AS mass,
             sum(weight*dy)/sum(weight) AS mu FROM %2$s GROUP BY ALL
    )
    SELECT a.*,q.q FROM a JOIN q USING(cohort)", stats_name, pair_table))
  est <- dbGetQuery(con, sprintf("
    SELECT event_time,sum(q*(CASE WHEN arm='treated' THEN mu ELSE -mu END)) AS estimate
    FROM %s GROUP BY event_time ORDER BY event_time", stats_name))
  infl <- dbGetQuery(con, sprintf("
    SELECT p.deal_id,p.event_time,
      sum((CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END)*s.q*p.weight/s.mass*(p.dy-s.mu)) AS influence
    FROM %1$s p JOIN %2$s s USING(cohort,event_time,arm)
    GROUP BY p.deal_id,p.event_time ORDER BY p.deal_id,p.event_time", pair_table, stats_name))
  periods <- est$event_time
  deals <- sort(unique(infl$deal_id))
  M <- matrix(0, length(deals), length(periods), dimnames=list(deals,periods))
  M[cbind(match(infl$deal_id,deals),match(infl$event_time,periods))] <- infl$influence
  M <- sweep(M,2,colMeans(M),"-")
  V <- nrow(M)/(nrow(M)-1)*crossprod(M)
  est$se_deal <- sqrt(diag(V))
  est$ci_low <- est$estimate-qt(.975,nrow(M)-1)*est$se_deal
  est$ci_high <- est$estimate+qt(.975,nrow(M)-1)*est$se_deal
  est$analysis <- label
  ref <- data.frame(event_time=-1L,estimate=0,se_deal=0,ci_low=0,ci_high=0,analysis=label)
  est <- rbind(est,ref)
  est[order(est$event_time),]
}

wild_tminus3 <- function(pair_table, label) {
  dat <- dbGetQuery(con, sprintf("
    WITH dm AS (
      SELECT cohort,sum(weight) AS m FROM %1$s WHERE arm='treated' GROUP BY cohort
    ), q AS (SELECT cohort,m/sum(m) OVER() AS q FROM dm),
    arm AS (
      SELECT cohort,arm,sum(weight) AS mass FROM %1$s WHERE event_time=-3 GROUP BY ALL
    ), cell AS (
      SELECT deal_id,cohort,arm,sum(weight) AS cell_mass,
             sum(weight*dy)/sum(weight) AS dy_mean
      FROM %1$s WHERE event_time=-3 GROUP BY ALL
    )
    SELECT c.*,CAST(arm='treated' AS INTEGER) AS treated,
           c.cell_mass/a.mass*q.q AS analysis_weight
    FROM cell c JOIN arm a USING(cohort,arm) JOIN q USING(cohort)", pair_table))
  mod <- feols(dy_mean~treated|cohort,data=dat,weights=~analysis_weight,
               cluster=~deal_id,fixef.rm="none",notes=FALSE)
  set.seed(LMV2_RECRUIT$bootstrap_seed)
  boot <- boottest(mod,param="treated",B=LMV2_RECRUIT$bootstrap_repetitions,
                   clustid=~deal_id,type="webb",impose_null=TRUE,
                   conf_int=TRUE,engine="R",nthreads=4)
  ci <- tryCatch(as.numeric(confint(boot)),error=function(e)c(NA_real_,NA_real_))
  data.frame(analysis=label,estimate=as.numeric(boot$point_estimate),
             ci_low=ci[1],ci_high=ci[2],p_value=as.numeric(pval(boot)),
             repetitions=LMV2_RECRUIT$bootstrap_repetitions)
}

weight_diagnostics <- function(spec, parent, reweighted) {
  dbGetQuery(con, sprintf("
    WITH x AS (
      SELECT p.cohort,p.arm,p.deal_id,p.codinv,p.analysis_weight AS parent_weight,
             r.analysis_weight AS new_weight
      FROM %1$s p JOIN %2$s r USING(cohort,deal_id,arm,codinv)
    ), d AS (
      SELECT cohort,arm,
        sum(parent_weight)^2/sum(parent_weight^2) AS parent_ess,
        sum(new_weight)^2/sum(new_weight^2) AS new_ess,
        max(parent_weight)/sum(parent_weight) AS parent_max_share,
        max(new_weight)/sum(new_weight) AS new_max_share
      FROM x GROUP BY ALL
    )
    SELECT '%3$s' AS specification,*,new_ess/parent_ess AS ess_ratio,
      (parent_ess-new_ess)/parent_ess AS relative_ess_loss,
      new_max_share/parent_max_share AS max_share_multiplier
    FROM d ORDER BY cohort,arm", parent,reweighted,spec))
}

entry_balance <- function(spec, weights, stage) {
  dbGetQuery(con, sprintf("
    WITH m AS (SELECT cohort,arm,sum(analysis_weight) mass FROM %1$s GROUP BY ALL),
    s AS (
      SELECT w.cohort,w.arm,w.symmetric_entry_bin,
             sum(w.analysis_weight)/max(m.mass) AS share_value
      FROM %1$s w JOIN m USING(cohort,arm) GROUP BY ALL
    )
    SELECT '%2$s' specification,'%3$s' stage,t.cohort,t.symmetric_entry_bin,
           t.share_value AS treated_share,c.share_value AS control_share,
           t.share_value-c.share_value AS gap
    FROM s t JOIN s c USING(cohort,symmetric_entry_bin)
    WHERE t.arm='treated' AND c.arm='control' ORDER BY t.cohort,t.symmetric_entry_bin",
    weights,spec,stage))
}

shift_share <- function(spec, weights) {
  panel <- sql_quote(panel_glob(spec))
  dbGetQuery(con, sprintf("
    WITH m AS (SELECT cohort,arm,sum(analysis_weight) mass FROM %1$s GROUP BY ALL),
    s AS (
      SELECT w.cohort,w.arm,w.symmetric_entry_bin,
             sum(w.analysis_weight)/max(m.mass) AS share_value
      FROM %1$s w JOIN m USING(cohort,arm) GROUP BY ALL
    ), y AS (
      SELECT h.cohort,h.arm,h.symmetric_entry_bin,
             sum(w.analysis_weight*p.patent_count)/sum(w.analysis_weight) mu
      FROM read_parquet(%2$s) p
      JOIN %1$s w USING(cohort,deal_id,arm,codinv)
      JOIN hist h ON h.specification='%3$s' AND h.cohort=p.cohort AND h.deal_id=p.deal_id
                 AND h.arm=p.arm AND h.codinv=p.codinv
      WHERE p.event_time=-3 GROUP BY ALL
    ), q0 AS (SELECT cohort,sum(analysis_weight) m FROM %1$s WHERE arm='treated' GROUP BY cohort),
    q AS (SELECT cohort,m/sum(m) OVER() q FROM q0), bins AS (
      SELECT t.cohort,t.symmetric_entry_bin,q.q,
             (t.share_value-c.share_value) AS gap,
             yc.mu control_mu,yt.mu treated_mu
      FROM s t JOIN s c USING(cohort,symmetric_entry_bin)
      JOIN y yt ON yt.cohort=t.cohort AND yt.arm='treated' AND yt.symmetric_entry_bin=t.symmetric_entry_bin
      JOIN y yc ON yc.cohort=t.cohort AND yc.arm='control' AND yc.symmetric_entry_bin=t.symmetric_entry_bin
      JOIN q ON q.cohort=t.cohort WHERE t.arm='treated' AND c.arm='control'
    )
    SELECT '%3$s' specification,sum(q*gap*control_mu) control_path,
           sum(q*gap*treated_mu) treated_path FROM bins", weights,panel,spec))
}

all_paths <- list(); all_wild <- list(); all_balance <- list(); all_diag <- list(); all_shift <- list()
for (spec in c("p5a","loyo_m3")) {
  wp <- make_weight_table(spec,FALSE)
  wr <- make_weight_table(spec,TRUE)
  pp <- make_pair_table(spec,wp,"none")
  pr <- make_pair_table(spec,wr,"none")
  pa <- make_pair_table(spec,wp,"entry_subtract")
  all_paths[[paste0(spec,"_parent")]] <- estimate_path(pp,paste0(spec,"_parent"))
  all_paths[[paste0(spec,"_entry_balanced")]] <- estimate_path(pr,paste0(spec,"_entry_balanced"))
  all_paths[[paste0(spec,"_entry_subtracted")]] <- estimate_path(pa,paste0(spec,"_entry_subtracted"))
  all_wild[[paste0(spec,"_entry_balanced")]] <- wild_tminus3(pr,paste0(spec,"_entry_balanced"))
  all_wild[[paste0(spec,"_entry_subtracted")]] <- wild_tminus3(pa,paste0(spec,"_entry_subtracted"))
  all_balance[[paste0(spec,"_before")]] <- entry_balance(spec,wp,"parent")
  all_balance[[paste0(spec,"_after")]] <- entry_balance(spec,wr,"entry_balanced")
  all_diag[[spec]] <- weight_diagnostics(spec,wp,wr)
  all_shift[[spec]] <- shift_share(spec,wp)
}

paths <- do.call(rbind,all_paths); wild <- do.call(rbind,all_wild)
balance <- do.call(rbind,all_balance); diagnostics <- do.call(rbind,all_diag)
shift <- do.call(rbind,all_shift)
write.csv(paths,file.path(out_dir,"results","event_paths_b0_b2.csv"),row.names=FALSE)
write.csv(wild,file.path(out_dir,"results","wild_bootstrap_tminus3.csv"),row.names=FALSE)
write.csv(balance,file.path(out_dir,"results","entry_balance.csv"),row.names=FALSE)
write.csv(diagnostics,file.path(out_dir,"results","weight_diagnostics.csv"),row.names=FALSE)
write.csv(shift,file.path(out_dir,"results","shift_share_tminus3.csv"),row.names=FALSE)

t3 <- paths[paths$event_time==-3,c("analysis","estimate")]
parent <- setNames(t3$estimate,t3$analysis)
materiality <- data.frame(
  diagnostic=c("B0_p5a","B0_loyo_m3","B2_p5a","B1_loyo_m3",
               "shift_control_p5a","shift_control_loyo_m3"),
  explained_patents=c(
    parent[["p5a_parent"]]-parent[["p5a_entry_subtracted"]],
    parent[["loyo_m3_parent"]]-parent[["loyo_m3_entry_subtracted"]],
    parent[["p5a_parent"]]-parent[["p5a_entry_balanced"]],
    parent[["loyo_m3_parent"]]-parent[["loyo_m3_entry_balanced"]],
    shift$control_path[shift$specification=="p5a"],
    shift$control_path[shift$specification=="loyo_m3"]),
  stringsAsFactors=FALSE)
materiality$correct_sign <- materiality$explained_patents>0
materiality$material <- materiality$correct_sign & materiality$explained_patents>=LMV2_RECRUIT$materiality_patents
write.csv(materiality,file.path(out_dir,"results","materiality_gate.csv"),row.names=FALSE)

source_files <- c(file.path("02_analysis","R","50a_lmv2_recruitment_composition_config.R"),
                  file.path("02_analysis","R","50b_build_lmv2_recruitment_composition.R"),
                  file.path("02_analysis","R","50c_run_lmv2_recruitment_composition.R"),
                  file.path("02_analysis","notes","local_match_v2_recruitment_composition_freeze.md"))
manifest <- data.frame(path=source_files,sha256=vapply(source_files,function(x)
  toupper(digest(file=x,algo="sha256",serialize=FALSE)),character(1)),
  run_at=as.character(Sys.time()))
write.csv(manifest,file.path(out_dir,"manifests","analysis_manifest.csv"),row.names=FALSE)
cat("B0-B2 complete. B3 gate:",any(materiality$material),"\n")
