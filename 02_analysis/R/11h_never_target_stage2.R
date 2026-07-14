# ============================================================================
# 11h_never_target_stage2.R -- Full two-stage entropy balance for the
# never-observed-target control arm (inventor-weighted ATT). Computes inventor
# covariates for the ~3.7M never-target units (per-stack), runs the two-stage
# balance vs the certified treated cohort, and reports final inventor-stage ESS,
# concentration, balance, and per-stack support. Read-only DB; writes audit CSVs.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
for (pkg in c("DBI", "duckdb", "WeightIt"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({library(DBI); library(duckdb); library(WeightIt)})
set.seed(SEED)

CONT_COVARS <- c("log_firm_patent_stock","log_firm_inventor_count","observed_firm_patent_age",
                 "log_patents_early","log_patents_recent","observed_inventor_career_age",
                 "observed_target_patent_tenure","log_inventor_patent_stock","target_exclusivity")
NT_UNITS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_units.parquet")

banner("NEVER-TARGET STAGE-2 (full two-stage, inventor-weighted)")
con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", gsub("\\\\", "/", DUCKDB_TMP)))

# --- treated units (already carry firm + inventor covariates) ---
treated <- dbGetQuery(con, sprintf("SELECT codinv, analysis_target_group_id AS underlying_group_id,
  stack, qualifying_gap, modal_family, %s FROM read_parquet('%s') WHERE treated = 1",
  paste(c(FIRM_COVARS, INV_COVARS), collapse = ", "), gsub("\\\\","/", UNITS_PARQUET)))
treated$treated <- 1L
message("Treated units: ", nrow(treated))

# --- never-target units + firm covariates (inventor covariates computed below) ---
nt <- dbGetQuery(con, sprintf("SELECT codinv, underlying_group_id, stack, qualifying_gap, %s
  FROM read_parquet('%s')", paste(FIRM_COVARS, collapse = ", "), gsub("\\\\","/", NT_UNITS_PARQUET)))
message("Never-target units: ", nrow(nt))

# --- inventor covariates for never-target, per stack (bounds memory) ---
banner("Inventor covariates for never-target (per stack)")
stacks <- sort(unique(nt$stack))
ic_list <- vector("list", length(stacks))
for (i in seq_along(stacks)) {
  g <- stacks[i]
  keys <- unique(nt[nt$stack == g, c("codinv", "underlying_group_id")])
  keys <- data.frame(codinv = keys$codinv, g = g, grp = keys$underlying_group_id)
  t0 <- Sys.time()
  ic <- compute_inventor_covariates(con, keys)
  ic_list[[i]] <- ic
  message(sprintf("  stack %d: %d keys, %.1fs", g, nrow(keys),
                  as.numeric(Sys.time() - t0, units = "secs")))
}
ic_all <- do.call(rbind, ic_list)
nt <- merge(nt, ic_all, by.x = c("codinv","stack","underlying_group_id"),
            by.y = c("codinv","g","grp"), all.x = TRUE)
nt$treated <- 0L
message("Never-target inventor covariates attached; missing career age: ",
        sum(is.na(nt$observed_inventor_career_age)))

# --- assemble combined units ---
keep <- c("codinv","underlying_group_id","stack","treated","qualifying_gap","modal_family",
          FIRM_COVARS, INV_COVARS)
units <- rbind(treated[, keep], nt[, keep])
units$qualifying_gap_cat <- droplevels(factor(pmin(units$qualifying_gap, 3L),
  levels = 0:3, labels = c("gap0","gap1","gap2","gap3plus")))
units$modal_family <- droplevels(factor(units$modal_family, levels = TECH_FAMILIES))
# firm-stage sampling weight = qualifying inventors per (group, stack) cell
units$.cell <- paste(units$underlying_group_id, units$stack, sep = "|")
cell_n <- table(units$.cell)
units$n_qualifying_inventors <- as.integer(cell_n[units$.cell])
# drop any never-target rows with unconstructable inventor covariates (should be ~0)
miss <- rowSums(is.na(units[, INV_COVARS])) > 0
if (any(miss)) { message("Dropping ", sum(miss), " units with missing inventor covariates.")
                 units <- units[!miss, ] }
message("Combined units: ", nrow(units), " (treated=", sum(units$treated),
        ", control=", sum(1 - units$treated), ")")

# --- two-stage balance ---
banner("Two-stage entropy balance (Stage 1 firm cells, Stage 2 inventor rows)")
t0 <- Sys.time()
fit <- two_stage_ebal(units, c("underlying_group_id","stack"), FIRM_COVARS, INV_COVARS,
                      INV_FACTOR_COVARS, cont_covars = CONT_COVARS, maxit = 30000)
message("two-stage elapsed: ", round(as.numeric(Sys.time()-t0, units="mins"),1), " min")
u <- fit$units; fw <- u$final_weight; ctl <- u$treated == 0L

# --- convergence + treated-weight assertion ---
stopifnot(max(abs(fw[u$treated==1L] - 1)) < 1e-8)
firm_mass <- fit$firm_data$n_qualifying_inventors * fit$firm_data$firm_multiplier
firm_md <- ebal_max_meandiff(model_matrix_cols(fit$firm_form, fit$firm_data), fit$firm_data$treated, firm_mass)
inv_md  <- ebal_max_meandiff(model_matrix_cols(fit$inv_form, u), u$treated, fw)

# --- diagnostics ---
grp_mass <- tapply(fw[ctl], u$underlying_group_id[ctl], sum)
stack_ess <- tapply(seq_len(sum(ctl)), u$stack[ctl], function(ix) ess(fw[ctl][ix]))
smd_post <- max(sapply(c(FIRM_COVARS, INV_COVARS),
  function(v) abs(smd_weighted(u[[v]], u$treated, fw))))
diag <- data.frame(
  stage = "inventor_final",
  firm_converged = firm_md <= EBAL_CONSTRAINT_TOL, firm_meandiff = firm_md,
  inv_converged  = inv_md  <= EBAL_CONSTRAINT_TOL, inv_meandiff  = inv_md,
  max_smd_post = smd_post,
  control_inventor_ess = ess(fw[ctl]),
  unique_firm_ess = ess(grp_mass),
  max_group_weight_share = max(grp_mass)/sum(grp_mass),
  top5_group_weight_share = sum(head(sort(grp_mass, decreasing=TRUE),5))/sum(grp_mass),
  min_stack_ess = min(stack_ess), median_stack_ess = median(stack_ess),
  n_treated = sum(u$treated), n_control = sum(ctl),
  unique_control_groups = length(unique(u$underlying_group_id[ctl])))
write_audit(diag, "never_target_stage2_diagnostics.csv")
options(width = 200); print(t(diag))

write_audit(data.frame(stack = names(stack_ess), inventor_ess = as.numeric(stack_ess)),
            "never_target_stage2_stack_ess.csv")

# per-covariate final balance
bal <- data.frame(covariate = c(FIRM_COVARS, INV_COVARS),
  smd_unweighted = sapply(c(FIRM_COVARS, INV_COVARS),
    function(v) smd_weighted(u[[v]], u$treated, u$n_qualifying_inventors)),
  smd_final = sapply(c(FIRM_COVARS, INV_COVARS),
    function(v) smd_weighted(u[[v]], u$treated, fw)))
write_audit(bal, "never_target_stage2_balance.csv"); print(bal)

# save final weights (unit-level, constant per inventor-stack) for the panel step
out <- u[, c("codinv","underlying_group_id","stack","treated","final_weight","n_qualifying_inventors")]
duckdb::duckdb_register(con, "s2_out", out)
dbExecute(con, sprintf("COPY (SELECT * FROM s2_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  gsub("\\\\","/", file.path(DERIVED_PAR, "main_did_v1_never_target_weights.parquet"))))
duckdb::duckdb_unregister(con, "s2_out")
banner("11h DONE")
