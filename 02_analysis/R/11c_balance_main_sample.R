# ============================================================================
# 11c_balance_main_sample.R -- Main DiD v1: two-stage hierarchical entropy
# balancing (firm then inventor). Writes final weights back to the units
# parquet + balance/love-plot/weight diagnostics. [R1/A1] weighting mechanics.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
for (pkg in c("DBI", "duckdb", "WeightIt", "cobalt", "ggplot2"))
  if (!requireNamespace(pkg, quietly = TRUE))
    stop("Missing package: ", pkg, " -- install into .r_libs before running 11c.")
suppressMessages({library(DBI); library(duckdb); library(WeightIt); library(cobalt); library(ggplot2)})
set.seed(SEED)

banner("MAIN DiD v1 -- TWO-STAGE ENTROPY BALANCING")

# ---------------------------------------------------------------------------
# Core two-stage routine. Returns final weights (constant per inventor-stack)
# with firm size entering EXACTLY once (base.weights = firm multiplier).
# ---------------------------------------------------------------------------
# two_stage_ebal() now lives in 11_main_design_utils.R (shared with 11h).

# ===========================================================================
# [A1] SYNTHETIC SELF-TEST -- run BEFORE touching real data
# ===========================================================================
banner("[A1] weighting self-test (synthetic)")
selftest <- function() {
  set.seed(1)
  # T (x=0,size4); C1 (x=0,size2), C2 (x=0,size4) identical covar -> N-vs-N^2 probe;
  # C3 (x=1,size3) off-covar forces nontrivial balancing. cont_covars empty (keep x raw).
  fk <- data.frame(
    focal_deal_id = 1:4, analysis_target_group_id = 1:4, stack = 2000L,
    arm = c("treated","control","control","control"), treated = c(1L,0L,0L,0L),
    x = c(0, 0, 0, 1), n_qualifying_inventors = c(4L, 2L, 4L, 3L))
  units <- do.call(rbind, lapply(seq_len(nrow(fk)), function(i)
    data.frame(fk[i, ], codinv = paste0(i, "_", seq_len(fk$n_qualifying_inventors[i])))))
  units$y <- 1  # dummy inventor covar (constant -> already balanced)
  res <- tryCatch(
    two_stage_ebal(units, c("focal_deal_id","analysis_target_group_id","stack","arm"),
                   firm_covars = "x", inv_covars = "y", inv_factors = character(0),
                   cont_covars = character(0)),
    error = function(e) { message("selftest ebal error: ", conditionMessage(e)); NULL })
  if (is.null(res)) return(data.frame(check = "selftest", pass = FALSE, detail = "ebal_error"))
  u <- res$units; fw <- u$final_weight
  t1 <- max(abs(fw[u$treated == 1L] - 1)) < 1e-8                                    # treated == 1
  t2 <- abs(sum(fw[u$treated == 0L]) - sum(fw[u$treated == 1L])) / sum(fw[u$treated == 1L]) < 1e-4
  mt <- weighted.mean(u$x[u$treated==1L], fw[u$treated==1L])
  mc <- weighted.mean(u$x[u$treated==0L], fw[u$treated==0L])
  t4 <- abs(mt - mc) < 1e-4                                                         # covariate match
  # [C5] N-vs-N^2: C1(size2,x=0) & C2(size4,x=0) identical covar -> mass ratio ~ 2, NOT 4
  m1 <- sum(fw[u$focal_deal_id == 2]); m2 <- sum(fw[u$focal_deal_id == 3])
  ratio <- m2 / m1
  t5 <- abs(ratio - 2) < 0.05
  data.frame(
    check = c("treated_weights_1","control_mass_eq_treated","cov_mean_match","N_not_Nsquared"),
    pass = c(t1, t2, t4, t5),
    detail = c(sprintf("max|w_t-1|=%.2e", max(abs(fw[u$treated==1L]-1))),
               sprintf("rel_mass_diff=%.2e", abs(sum(fw[u$treated==0L])-sum(fw[u$treated==1L]))/sum(fw[u$treated==1L])),
               sprintf("mt=%.4f mc=%.4f", mt, mc),
               sprintf("mass2/mass1=%.3f (expect 2, N^2 would be 4)", ratio)))
}
st <- selftest()
write_audit(st, "weighting_selftest.csv"); print(st)
if (!all(st$pass)) stop("[A1] weighting self-test FAILED -- fix before running on real data.")
message("[A1] self-test PASSED")

# ===========================================================================
# REAL DATA
# ===========================================================================
banner("Loading units + preparing covariates")
con <- dbConnect(duckdb::duckdb(), ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
units <- dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", gsub("\\\\","/",UNITS_PARQUET)))
units$stack <- as.integer(units$stack)
units$qualifying_gap_cat <- droplevels(factor(units$qualifying_gap_cat))   # drop empty gap0
units$modal_family <- droplevels(factor(units$modal_family))

firm_key_cols <- c("focal_deal_id","analysis_target_group_id","stack","arm")

# model-matrix hygiene [A6]: zero-variance / single-arm checks
mm_check <- inspect_model_matrix(units, c(FIRM_COVARS, INV_COVARS))
write_audit(mm_check, "model_matrix_checks.csv")
print(mm_check)
zv <- mm_check$covariate[mm_check$zero_variance]
if (length(zv) > 0) stop("Zero-variance covariate(s): ", paste(zv, collapse=", "))

CONT_COVARS <- c("log_firm_patent_stock","log_firm_inventor_count","observed_firm_patent_age",
                 "log_patents_early","log_patents_recent","observed_inventor_career_age",
                 "observed_target_patent_tenure","log_inventor_patent_stock","target_exclusivity")
banner("Two-stage entropy balancing (real data)")
fit <- tryCatch(
  two_stage_ebal(units, firm_key_cols, FIRM_COVARS, INV_COVARS, INV_FACTOR_COVARS,
                 cont_covars = CONT_COVARS),
  error = function(e) { write_audit(data.frame(stage="ebal", error=conditionMessage(e)),
    "ebal_failure.csv"); stop("Entropy balancing FAILED: ", conditionMessage(e)) })
units <- fit$units
fw <- units$final_weight

# ---- Hard-stop gates [R5/A1/C5] ----
# [C5] convergence = max abs WEIGHTED model-matrix column mean diff <= EBAL_CONSTRAINT_TOL
firm_mass <- fit$firm_data$n_qualifying_inventors * fit$firm_data$firm_multiplier
firm_meandiff <- ebal_max_meandiff(model_matrix_cols(fit$firm_form, fit$firm_data),
                                   fit$firm_data$treated, firm_mass)
inv_meandiff  <- ebal_max_meandiff(model_matrix_cols(fit$inv_form, units), units$treated, fw)
gate <- data.frame(
  treated_weights_1 = max(abs(fw[units$treated==1L] - 1)) < 1e-8,
  weights_finite    = all(is.finite(fw)),
  weights_positive  = all(fw > 0),
  firm_meandiff = firm_meandiff, firm_converged = firm_meandiff <= EBAL_CONSTRAINT_TOL,
  inv_meandiff  = inv_meandiff,  inv_converged  = inv_meandiff  <= EBAL_CONSTRAINT_TOL,
  control_ess = ess(fw[units$treated==0L]), max_ctrl_weight = max(fw[units$treated==0L]))
write_audit(gate, "ebal_gates.csv"); print(gate)
if (!gate$treated_weights_1) stop("[A1] treated final weights != 1 -- inspect W_inv, do not patch.")
if (!gate$weights_finite || !gate$weights_positive) stop("Non-finite/non-positive final weights.")
if (!gate$firm_converged || !gate$inv_converged)
  stop(sprintf("[C5] ebal did NOT converge (firm meandiff=%.2e, inv meandiff=%.2e > tol=%.1e); ",
               firm_meandiff, inv_meandiff, EBAL_CONSTRAINT_TOL),
       "the current spec (inventor-weighted g+7) is expected to fail here -- see 11g comparison.")

# ---- Balance tables (cobalt) firm + final ----
banner("Balance diagnostics")
bt_firm <- cobalt::bal.tab(fit$W_firm, un = TRUE, disp = c("means"), stats = "mean.diffs")
bt_inv  <- cobalt::bal.tab(fit$W_inv,  un = TRUE, disp = c("means"), stats = "mean.diffs")
firm_bal <- bt_firm$Balance; firm_bal$covariate <- rownames(firm_bal)
inv_bal  <- bt_inv$Balance;  inv_bal$covariate  <- rownames(inv_bal)
write_audit(firm_bal, "firm_balance.csv")
write_audit(inv_bal,  "inventor_balance.csv")
smd_un  <- abs(inv_bal$Diff.Un[is.finite(inv_bal$Diff.Un)])
smd_adj <- abs(inv_bal$Diff.Adj[is.finite(inv_bal$Diff.Adj)])
message(sprintf("Inventor SMD max: un=%.3f adj=%.3f | %% adj<0.05=%.0f | %% adj<0.10=%.0f",
  max(smd_un), max(smd_adj), 100*mean(smd_adj<0.05), 100*mean(smd_adj<0.10)))

# ---- Love plots ----
lp_firm <- cobalt::love.plot(fit$W_firm, stats = "mean.diffs", abs = TRUE,
  thresholds = c(m = SMD_ACCEPTABLE), title = "Firm-stage balance (inventor-weighted)")
lp_inv  <- cobalt::love.plot(fit$W_inv,  stats = "mean.diffs", abs = TRUE,
  thresholds = c(m = SMD_ACCEPTABLE), title = "Final inventor-stage balance")
ggsave(file.path(AUDIT_DIR, "love_plot_firm.png"),  lp_firm, width = 8, height = 6, dpi = 300, bg = "white")
ggsave(file.path(AUDIT_DIR, "love_plot_final.png"), lp_inv,  width = 8, height = 7, dpi = 300, bg = "white")

# ---- Weight + support diagnostics [R5] ----
banner("Weight & support diagnostics")
ctlw <- fw[units$treated == 0L]
wd <- weight_quantile_diag(ctlw); wd$arm <- "control"
# top-deal concentration + near-zero
deal_mass <- tapply(ctlw, units$focal_deal_id[units$treated==0L], sum)
wd$top_deal_share <- max(deal_mass) / sum(deal_mass)
wd$n_near_zero    <- sum(ctlw < NEAR_ZERO_WEIGHT)
wd$control_ess    <- ess(ctlw)
wd$firm_ess_stage1 <- ess(fit$firm_data$firm_multiplier[fit$firm_data$treated==0L] *
                          fit$firm_data$n_qualifying_inventors[fit$firm_data$treated==0L])
wd$control_mass   <- sum(ctlw); wd$treated_mass <- sum(fw[units$treated==1L])
write_audit(wd, "weight_diagnostics.csv"); print(wd)

# mass by stack (weighted)
mass_stack <- aggregate(final_weight ~ stack + arm, data = units, FUN = sum)
write_audit(mass_stack, "weighted_mass_by_stack.csv")

# ---- Era- and stack-level balance [R6] on continuous covars ----
cont_covars <- c("log_firm_patent_stock","log_firm_inventor_count","observed_firm_patent_age",
                 "log_patents_early","log_patents_recent","observed_inventor_career_age",
                 "observed_target_patent_tenure","log_inventor_patent_stock","target_exclusivity")
era_smd <- do.call(rbind, lapply(BALANCE_ERAS, function(er) {
  idx <- units$stack >= er[1] & units$stack <= er[2]
  if (sum(units$treated[idx]==1)==0 || sum(units$treated[idx]==0)==0) return(NULL)
  s <- sapply(cont_covars, function(v) abs(smd_weighted(units[[v]][idx], units$treated[idx], fw[idx])))
  data.frame(era = paste(er, collapse="-"), max_abs_smd = max(s), median_abs_smd = median(s))
}))
write_audit(era_smd, "era_balance.csv"); print(era_smd)
stack_smd <- do.call(rbind, lapply(sort(unique(units$stack)), function(g) {
  idx <- units$stack == g
  if (sum(units$treated[idx]==1)==0 || sum(units$treated[idx]==0)==0) return(NULL)
  s <- sapply(cont_covars, function(v) abs(smd_weighted(units[[v]][idx], units$treated[idx], fw[idx])))
  data.frame(stack = g, max_abs_smd = max(s), median_abs_smd = median(s))
}))
write_audit(stack_smd, "stack_balance.csv")
message(sprintf("Per-stack |SMD|: max across stacks=%.3f, median=%.3f",
  max(stack_smd$max_abs_smd), median(stack_smd$max_abs_smd)))

# ---- Hierarchical preservation [R7]: final vs stage-1 firm weights ----
final_firm_mass <- tapply(fw[units$treated==0L], units$.fk[units$treated==0L], sum)
fd <- fit$firm_data[fit$firm_data$treated==0L, ]
fd$stage1_mass <- fd$firm_multiplier * fd$n_qualifying_inventors
fd$final_mass  <- final_firm_mass[fd$.fk]
hp <- data.frame(
  corr_stage1_final_mass = stats::cor(fd$stage1_mass, fd$final_mass, use="complete.obs"),
  firm_ess_stage1 = ess(fd$stage1_mass), firm_ess_final = ess(fd$final_mass),
  max_abs_log_ratio = max(abs(log(fd$final_mass / fd$stage1_mass)), na.rm = TRUE))
write_audit(hp, "hierarchical_preservation.csv"); print(hp)

# ===========================================================================
# WRITE AUGMENTED UNITS (with weights) back to parquet [A1]
# ===========================================================================
banner("Writing units + final weights")
out_cols <- c(names(units)[!names(units) %in% c(".fk")])
units_out <- units[, out_cols]
duckdb::duckdb_register(con, "uo", units_out)
dbExecute(con, sprintf("COPY (SELECT * FROM uo) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  gsub("\\\\","/", UNITS_PARQUET)))
duckdb::duckdb_unregister(con, "uo")
message("Wrote weights to ", UNITS_PARQUET)
banner("11c DONE")
