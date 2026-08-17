# Jointly calibrate P5c original moments and symmetric recruitment-entry bins.

.libPaths(c(normalizePath(".r_libs", mustWork = TRUE), .libPaths()))
suppressPackageStartupMessages({
  library(DBI); library(duckdb); library(nleqslv); library(digest)
})
source(file.path("02_analysis", "R", "50a_lmv2_recruitment_composition_config.R"))

sql_quote <- function(x) paste0("'", gsub("'", "''", normalizePath(x, winslash="/", mustWork=FALSE)), "'")
root <- file.path(LMV2_RECRUIT_PATHS$output, "calibrated_weights")
dir.create(root, recursive=TRUE, showWarnings=FALSE)
history <- file.path(LMV2_RECRUIT_PATHS$output,"data","recruitment_history.parquet")

count_vars <- paste0("patent_count_m",5:1)
active_vars <- paste0("active_patenting_m",5:1)
other_vars <- c("career_age","focal_group_exclusivity",
                "firm_log_patent_stock_5y","firm_log_inventor_count_5y",
                "firm_patent_trajectory")
vars_for <- function(spec) {
  x <- c(count_vars,active_vars,other_vars)
  if (spec=="loyo_m3") x <- setdiff(x,c("patent_count_m3","active_patenting_m3"))
  x
}
entry_levels <- setdiff(LMV2_RECRUIT$entry_levels,"pre_g5")

tilt <- function(beta,X,prior) {
  eta <- drop(X%*%beta); eta <- eta-max(eta); prior*exp(eta)
}
moments <- function(beta,X,prior,target) {
  q <- tilt(beta,X,prior); drop(crossprod(X,q)/sum(q))-target
}
jacobian <- function(beta,X,prior,target) {
  q <- tilt(beta,X,prior); mu <- drop(crossprod(X,q)/sum(q))
  crossprod(X,X*as.numeric(q/sum(q)))-tcrossprod(mu)
}
dual_value <- function(beta,X,prior,target) {
  eta <- drop(X%*%beta); m <- max(eta)
  log(sum(prior*exp(eta-m)))+m-sum(target*beta)
}
dual_gradient <- function(beta,X,prior,target) moments(beta,X,prior,target)

solve_cell <- function(d,spec,cohort) {
  original <- vars_for(spec)
  for (lev in entry_levels) d[[paste0("entry_",lev)]] <- as.numeric(d$symmetric_entry_bin==lev)
  all_vars <- c(original,paste0("entry_",entry_levels))
  D <- d$treated==1L
  if (any(!is.finite(as.matrix(d[all_vars])))) stop("Non-finite covariate")
  mu0 <- vapply(d[all_vars],mean,numeric(1)); sd0 <- vapply(d[all_vars],sd,numeric(1))
  use <- all_vars[is.finite(sd0)&sd0>1e-12]
  X <- sweep(sweep(as.matrix(d[use]),2,mu0[use],"-"),2,sd0[use],"/")
  qr0 <- qr(X[!D,,drop=FALSE]); use_rank <- qr0$pivot[seq_len(qr0$rank)]
  X <- X[,use_rank,drop=FALSE]; use <- use[use_rank]
  prior_c <- d$base_weight[!D]; prior_t <- d$base_weight[D]
  target <- drop(crossprod(X[D,,drop=FALSE],prior_t)/sum(prior_t))
  opt <- optim(rep(0,length(use)),dual_value,dual_gradient,
               X=X[!D,,drop=FALSE],prior=prior_c,target=target,
               method="BFGS",control=list(maxit=2000,reltol=1e-12))
  sol <- nleqslv(opt$par,moments,jac=jacobian,X=X[!D,,drop=FALSE],
                 prior=prior_c,target=target,method="Newton",global="dbldog",
                 control=list(ftol=1e-11,xtol=1e-11,maxit=1000))
  exact <- sol$termcd %in% c(1L,2L) && max(abs(sol$fvec))<=1e-7
  beta <- if (exact) sol$x else opt$par
  w <- d$base_weight
  q <- tilt(beta,X[!D,,drop=FALSE],prior_c)
  w[!D] <- q/sum(q)*sum(prior_t)
  w[D] <- prior_t
  standardized_gap <- function(v) {
    z <- (d[[v]]-mean(d[[v]]))/sd(d[[v]])
    abs(weighted.mean(z[D],w[D])-weighted.mean(z[!D],w[!D]))
  }
  original_nondegenerate <- original[vapply(d[original],sd,numeric(1))>1e-12]
  entry_names <- paste0("entry_",entry_levels)
  entry_nondegenerate <- entry_names[vapply(d[entry_names],sd,numeric(1))>1e-12]
  orig_gap <- max(vapply(original_nondegenerate,standardized_gap,numeric(1)),0)
  entry_gap <- max(vapply(entry_nondegenerate,standardized_gap,numeric(1)),0)
  parent_ess <- sum(d$final_weight[!D])^2/sum(d$final_weight[!D]^2)
  new_ess <- sum(w[!D])^2/sum(w[!D]^2)
  parent_share <- max(d$final_weight[!D])/sum(d$final_weight[!D])
  new_share <- max(w[!D])/sum(w[!D])
  diag <- data.frame(specification=spec,cohort=cohort,
    feasibility_tier=if (exact) "exact" else "approximate_or_infeasible",
    solver_term=sol$termcd, solver_residual=max(abs(moments(beta,X[!D,,drop=FALSE],prior_c,target))),
    max_original_abs_smd=orig_gap,
    max_entry_abs_smd=entry_gap,parent_ess=parent_ess,new_ess=new_ess,
    ess_ratio=new_ess/parent_ess,ess_ratio_loss=(parent_ess-new_ess)/parent_ess,
    parent_max_share=parent_share,new_max_share=new_share,
    max_share_multiplier=new_share/parent_share,
    pass=(new_ess/parent_ess>=LMV2_RECRUIT$minimum_ess_ratio &&
          (parent_ess-new_ess)/parent_ess<=LMV2_RECRUIT$maximum_ess_ratio_loss &&
          new_share/parent_share<=LMV2_RECRUIT$maximum_parent_share_multiplier &&
          orig_gap<=LMV2_RECRUIT$approximate_smd &&
          entry_gap<=LMV2_RECRUIT$approximate_smd))
  diag$feasibility_tier <- if (exact && diag$pass) "exact" else
    if (diag$pass) "approximate" else "infeasible"
  d$new_weight <- w
  list(data=d[c("roster_row_id","cohort","deal_id","codinv","treated",
                "symmetric_entry_bin","base_weight","final_weight","new_weight")],
       diagnostics=diag)
}

con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con,shutdown=TRUE),add=TRUE)
dbExecute(con,"SET threads=4"); dbExecute(con,"SET memory_limit='9GB'")
diagnostics <- list(); k <- 0L
for (spec in c("loyo_m3","count_active")) {
  subdir <- file.path(root,spec); dir.create(subdir,showWarnings=FALSE)
  source_dir <- if (spec=="loyo_m3")
    file.path(".worktrees","lmv2-p4-ebal","02_analysis","output","audit",
              "local_match_v2","P5C_ANNUAL_TRAJECTORY","placebo","weights") else
    file.path(".worktrees","lmv2-p4-ebal","02_analysis","output","audit",
              "local_match_v2","P5C_ANNUAL_TRAJECTORY","production","weights")
  for (cohort in LMV2_RECRUIT$cohorts) {
    pattern <- file.path(source_dir,sprintf("c%d_primary_%s_b64ecb850b84.parquet",cohort,spec))
    q <- sprintf("SELECT s.*,h.symmetric_entry_bin FROM read_parquet(%s) s
      JOIN read_parquet(%s) h USING(roster_row_id)
      WHERE h.specification='%s'",sql_quote(pattern),sql_quote(history),spec)
    d <- dbGetQuery(con,q)
    ans <- solve_cell(d,spec,cohort)
    k <- k+1L; diagnostics[[k]] <- ans$diagnostics
    duckdb_register(con,"cell_out",ans$data)
    dest <- file.path(subdir,sprintf("c%d_%s_entry_joint.parquet",cohort,spec))
    dbExecute(con,sprintf("COPY cell_out TO %s (FORMAT PARQUET,COMPRESSION ZSTD)",sql_quote(dest)))
    duckdb_unregister(con,"cell_out")
    cat(spec,cohort,"pass=",ans$diagnostics$pass,"\n")
  }
}
diagnostics <- do.call(rbind,diagnostics)
write.csv(diagnostics,file.path(LMV2_RECRUIT_PATHS$output,"results","joint_calibration_diagnostics.csv"),row.names=FALSE)
cat("Joint calibration complete; all cells pass:",all(diagnostics$pass),"\n")
