# ============================================================================
# 11g_support_comparison.R -- Main DiD v1: does never-target (or hybrid) restore
# firm-stage support for the INVENTOR-WEIGHTED ATT? Runs the firm-stage entropy
# balance for future_g7 / never_target / hybrid against the same treated target,
# records pass/fail per spec (never terminating on g+7 failure [C5]), then a
# decision gate. Full two-stage for passers is handled downstream.
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

FIRM_CONT <- c("log_firm_patent_stock","log_firm_inventor_count","observed_firm_patent_age",
               "log_patents_early","log_patents_recent")
NT_UNITS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_units.parquet")

banner("SUPPORT COMPARISON: future_g7 / never_target / hybrid (firm stage)")
con <- dbConnect(duckdb::duckdb(), ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

# --- firm cells from each arm (one row per firm x stack, with n_qualifying_inventors) ---
mu <- dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", gsub("\\\\","/", UNITS_PARQUET)))
cell_cols <- c("underlying_group_id","stack","treated","source","n_qualifying_inventors", FIRM_COVARS)
treated_cells <- unique(transform(mu[mu$treated==1L, ],
  underlying_group_id = analysis_target_group_id, source = "treated")[, cell_cols])
g7_cells <- unique(transform(mu[mu$treated==0L, ],
  underlying_group_id = analysis_target_group_id, source = "future_g7")[, cell_cols])

nt <- dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", gsub("\\\\","/", NT_UNITS_PARQUET)))
nt$source <- "never_observed_target"
nt_cells <- unique(nt[, cell_cols])
nt_acq <- unique(nt[, c("underlying_group_id","stack","ever_acquirer")])

message("Firm cells: treated=", nrow(treated_cells), " g7=", nrow(g7_cells), " never_target=", nrow(nt_cells))

# --- firm-stage ebal for one control pool ---
run_firm_spec <- function(spec, control_cells) {
  fd <- rbind(treated_cells, control_cells)
  fd$fsk <- paste(fd$underlying_group_id, fd$stack, fd$source, sep = "|")
  # standardize continuous covariates (conditioning; SMD scale-invariant)
  for (v in FIRM_CONT) fd[[v]] <- standardize_continuous(fd[[v]])
  form <- stats::reformulate(c(FIRM_COVARS, "factor(stack)"), response = "treated")
  W <- tryCatch(WeightIt::weightit(form, data = fd, method = "ebal", estimand = "ATT",
          s.weights = fd$n_qualifying_inventors, maxit = 30000),
        error = function(e) { message(spec, " ebal ERROR: ", conditionMessage(e)); NULL })
  if (is.null(W)) return(list(row = data.frame(spec = spec, converged = FALSE, error = TRUE),
                              fd = fd, mult = NULL))
  mult <- as.numeric(W$weights)
  ctl <- fd$treated == 0L
  mass <- fd$n_qualifying_inventors * mult            # inventor analysis mass at firm level
  cmass <- mass[ctl]
  meandiff <- ebal_max_meandiff(model_matrix_cols(form, fd), fd$treated, mass)
  smd_pre  <- max(sapply(FIRM_COVARS, function(v) abs(smd_weighted(fd[[v]], fd$treated, fd$n_qualifying_inventors))))
  smd_post <- max(sapply(FIRM_COVARS, function(v) abs(smd_weighted(fd[[v]], fd$treated, mass))))
  grp_mass <- tapply(cmass, fd$underlying_group_id[ctl], sum)
  stack_ess <- tapply(seq_len(sum(ctl)), fd$stack[ctl], function(ix) ess(cmass[ix]))
  # weighted mass by source + acquirer-only share (never-target only)
  src_mass <- tapply(cmass, fd$source[ctl], sum)
  nt_ix <- fd$source[ctl] == "never_observed_target"
  acq_share <- NA_real_
  if (any(nt_ix)) {
    key <- paste(fd$underlying_group_id[ctl][nt_ix], fd$stack[ctl][nt_ix])
    nt_acq$key <- paste(nt_acq$underlying_group_id, nt_acq$stack)
    ea <- nt_acq$ever_acquirer[match(key, nt_acq$key)]
    acq_share <- sum(cmass[nt_ix][isTRUE_vec(ea)]) / sum(cmass)
  }
  row <- data.frame(
    spec = spec, converged = meandiff <= EBAL_CONSTRAINT_TOL, error = FALSE,
    firm_meandiff = meandiff, control_inventor_units = sum(fd$n_qualifying_inventors[ctl]),
    control_cells = sum(ctl), unique_control_groups = length(unique(fd$underlying_group_id[ctl])),
    largest_control_firm = max(fd$n_qualifying_inventors[ctl]),
    max_smd_pre = smd_pre, max_smd_post = smd_post,
    cell_ess = ess(cmass), unique_firm_ess = ess(grp_mass),
    min_stack_ess = min(stack_ess), median_stack_ess = median(stack_ess),
    max_group_weight_share = max(grp_mass) / sum(grp_mass),
    top5_group_weight_share = sum(head(sort(grp_mass, decreasing = TRUE), 5)) / sum(grp_mass),
    n_near_zero_mult = sum(mult[ctl] < NEAR_ZERO_WEIGHT),
    empty_stack = any(!(sort(unique(treated_cells$stack)) %in% fd$stack[ctl])),
    mass_future_g7 = ifelse("future_g7" %in% names(src_mass), src_mass[["future_g7"]], 0),
    mass_never_target = ifelse("never_observed_target" %in% names(src_mass), src_mass[["never_observed_target"]], 0),
    never_target_acquirer_mass_share = acq_share)
  list(row = row, fd = fd, mult = mult)
}

specs <- list(future_g7 = g7_cells, never_target = nt_cells,
              hybrid = rbind(g7_cells, nt_cells))
results <- lapply(names(specs), function(s) {
  message("\n>>> spec: ", s)
  t0 <- Sys.time(); r <- run_firm_spec(s, specs[[s]])
  message("   elapsed ", round(as.numeric(Sys.time()-t0, units="secs"),1), "s")
  r
})
names(results) <- names(specs)
comp <- do.call(rbind, lapply(results, function(r) {
  x <- r$row
  for (col in setdiff(c("spec","converged","error","firm_meandiff","control_inventor_units",
      "control_cells","unique_control_groups","largest_control_firm","max_smd_pre","max_smd_post",
      "cell_ess","unique_firm_ess","min_stack_ess","median_stack_ess","max_group_weight_share",
      "top5_group_weight_share","n_near_zero_mult","empty_stack","mass_future_g7","mass_never_target",
      "never_target_acquirer_mass_share"), names(x))) x[[col]] <- NA
  x
}))

# --- decision gate [reviewer]: convergence (1e-4) + SMD<0.10 + no empty stack.
#     ESS>=50 and max single-firm<=10% are WARNINGS, not immutable gates. ---
comp$warn_low_unique_firm_ess <- comp$unique_firm_ess < 50
comp$warn_concentration       <- comp$max_group_weight_share > 0.10
comp$pass_decision_gate <- with(comp, converged & !error & max_smd_post < 0.10 & !empty_stack)
write_audit(comp, "never_target_support_comparison.csv")
options(width = 220); print(comp)

passers <- comp$spec[isTRUE_vec(comp$pass_decision_gate)]
message("\nSpecs passing (converge+SMD+stack): ",
        if (length(passers)) paste(passers, collapse=", ") else "NONE",
        " | warn low unique-firm ESS: ", paste(comp$spec[comp$warn_low_unique_firm_ess], collapse=","),
        " | warn concentration: ", paste(comp$spec[comp$warn_concentration], collapse=","))

# --- weighted donor audits (never_target + hybrid) [reviewer] ---
treated_pc <- weighted.mean(
  treated_cells$share_small_molecule + treated_cells$share_biotech + treated_cells$share_formulation,
  treated_cells$n_qualifying_inventors)
for (s in c("never_target", "hybrid")) {
  r <- results[[s]]; if (is.null(r$mult)) next
  fd <- r$fd; mult <- r$mult; ctl <- fd$treated == 0L
  mass <- (fd$n_qualifying_inventors * mult)[ctl]
  d <- data.frame(grp = fd$underlying_group_id[ctl], stack = fd$stack[ctl], src = fd$source[ctl],
    n = fd$n_qualifying_inventors[ctl], mass = mass,
    pc = (fd$share_small_molecule + fd$share_biotech + fd$share_formulation)[ctl])
  agg <- aggregate(cbind(mass, n) ~ grp, d, sum)
  agg$weight_share <- agg$mass / sum(agg$mass)
  agg$n_stacks <- tapply(d$stack, d$grp, function(x) length(unique(x)))[as.character(agg$grp)]
  agg$pharma_core <- tapply(seq_along(d$pc), d$grp,
                            function(ix) weighted.mean(d$pc[ix], d$n[ix]))[as.character(agg$grp)]
  agg$ever_acquirer <- isTRUE_vec(nt_acq$ever_acquirer[match(agg$grp, nt_acq$underlying_group_id)])
  agg <- agg[order(-agg$mass), ]
  write_audit(cbind(spec = s, head(agg, 20)), sprintf("never_target_top_donors_%s.csv", s))
  w_pc <- weighted.mean(agg$pharma_core, agg$mass)
  low5_mass <- sum(agg$mass[agg$pharma_core < 0.05]) / sum(agg$mass)
  acq_share <- sum(agg$mass[agg$ever_acquirer]) / sum(agg$mass)
  message(sprintf("[%s donors] weighted pharma-core=%.3f (treated=%.3f) | mass <5%%-pharma=%.3f | top5=%.3f | acquirer mass=%.4f",
    s, w_pc, treated_pc, low5_mass, sum(head(agg$weight_share, 5)), acq_share))
  write_audit(data.frame(spec = s, weighted_pharma_core = w_pc, treated_pharma_core = treated_pc,
    mass_share_below_5pct_pharma = low5_mass, top5_weight_share = sum(head(agg$weight_share, 5)),
    acquirer_weight_share = acq_share), sprintf("never_target_weighted_relevance_%s.csv", s))
}
saveRDS(list(comp = comp, passers = passers), file.path(RESULTS_DIR, "support_comparison.rds"))
banner("11g (firm-stage comparison) DONE")
