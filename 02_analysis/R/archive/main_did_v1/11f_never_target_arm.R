# ============================================================================
# 11f_never_target_arm.R -- Main DiD v1: never-(observed-)target control arm.
# Builds the never-target control units, firm covariates per group x stack cell,
# and the required audits. Inventor covariates are computed in the two-stage
# balance (11g) for gate-passing specs only (2.9M control units -> deferred).
# Read-only DuckDB; writes parquet + audit CSVs. Does NOT touch g+7 outputs.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
for (pkg in c("DBI", "duckdb"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({library(DBI); library(duckdb)})
set.seed(SEED)

NT_UNITS_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_never_target_units.parquet")

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='8GB'"); dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", gsub("\\\\", "/", DUCKDB_TMP)))

banner("NEVER-OBSERVED-TARGET CONTROL ARM")

res <- build_never_target_arm(con)
units <- res$units
message("Never-target universe: pharma=", res$n_pharma_groups, " ever_target=", res$n_ever_target,
        " never_target=", res$n_never_target)
message("Assigned=", res$n_assigned, " retained=", nrow(units),
        " | unique groups used=", length(unique(units$underlying_group_id)),
        " | group x stack cells=", length(unique(units$firm_stack_key)))

# --- assertion: one row per (codinv, stack) ---
if (anyDuplicated(units[, c("codinv", "stack")]))
  stop("Never-target: duplicate (codinv, stack) rows -- assignment dedup failed.")

# ===========================================================================
# AUDITS
# ===========================================================================
# universe waterfall
write_audit(data.frame(
  step = c("pharma_patenting_groups","minus_ever_target","assigned_inventor_stack",
           "after_cleanliness"),
  n = c(res$n_pharma_groups, res$n_never_target, res$n_assigned, nrow(units))),
  "never_target_universe_waterfall.csv")

# target-history audit (why groups are in / out)
write_audit(data.frame(
  metric = c("pharma_patenting_groups","ever_target_groups_excluded",
             "never_observed_target_groups","never_target_groups_used_in_assignment"),
  value = c(res$n_pharma_groups, res$n_ever_target, res$n_never_target,
            length(unique(units$underlying_group_id))),
  note = c(">=1 pharma-family patent 1988-2015",
           "target-side only: target_group/pre/post + target-compcod->group +/-2y [C4]",
           "pharma minus ever-target",
           "groups an inventor's latest [g-5,g-1] affiliation resolved to")),
  "never_target_target_history_audit.csv")

# acquirer flags (diagnostic, non-excluding) [C2]
a <- res$all_assigned
write_audit(data.frame(
  scope = c("assigned_units","retained_units","retained_units","retained_units"),
  flag  = c("cleanliness_dropped","ever_acquirer","acquirer_event_in_window","acquirer_only_est"),
  n = c(sum(a$any_exclusion), sum(units$ever_acquirer), sum(units$acquirer_event_in_window),
        sum(units$ever_acquirer))),
  "never_target_acquirer_flags.csv")

# risk set by stack
write_audit(as.data.frame(table(stack = units$stack)), "never_target_risk_set_by_stack.csv")

# duplicate-assignment audit (source of assignment)
write_audit(as.data.frame(table(source = units$source)), "never_target_duplicate_assignment_audit.csv")

# ===========================================================================
# FIRM COVARIATES per (underlying_group_id, stack) cell
# ===========================================================================
banner("Firm covariates per group x stack cell")
firm_keys <- unique(units[, c("underlying_group_id", "stack")])
firm_keys$fk_id <- seq_len(nrow(firm_keys))
firm_keys$id_group <- firm_keys$underlying_group_id
firm_keys$g <- firm_keys$stack
firm_cov <- compute_firm_covariates(con, firm_keys)
firm_cov <- merge(firm_keys[, c("fk_id","underlying_group_id","stack")],
                  firm_cov[, c("fk_id", FIRM_COVARS)], by = "fk_id")
message("Firm cells: ", nrow(firm_cov))

# n_qualifying_inventors per cell (firm-stage sampling weight)
fk_n <- as.data.frame(table(firm_stack_key = units$firm_stack_key))
fk_n$underlying_group_id <- as.numeric(sub("\\|.*$", "", fk_n$firm_stack_key))
fk_n$stack <- as.integer(sub("^.*\\|", "", fk_n$firm_stack_key))
names(fk_n)[names(fk_n) == "Freq"] <- "n_qualifying_inventors"

# firm covariate missingness (should be zero given no-history indicators)
miss <- do.call(rbind, lapply(FIRM_COVARS, function(v)
  data.frame(covariate = v, level = "firm", n_missing = sum(is.na(firm_cov[[v]])))))
write_audit(miss, "never_target_covariate_missingness.csv")
if (any(miss$n_missing > 0)) stop("Never-target firm covariate missingness: ",
  paste(miss$covariate[miss$n_missing > 0], collapse = ", "))

# ---- [audit] pharma-relevance: never-target tech shares vs treated ----
treated_fs <- dbGetQuery(con, sprintf(
  "SELECT share_small_molecule, share_biotech, share_formulation, n_qualifying_inventors, treated
   FROM read_parquet('%s') WHERE treated = 1", gsub("\\\\","/", UNITS_PARQUET)))
nt_cell <- merge(firm_cov, fk_n[, c("underlying_group_id","stack","n_qualifying_inventors")],
                 by = c("underlying_group_id","stack"))
wmean <- function(x, w) sum(x * w) / sum(w)
tech_rel <- data.frame(
  pool = c("treated","never_target"),
  share_small_molecule = c(wmean(treated_fs$share_small_molecule, treated_fs$n_qualifying_inventors),
                           wmean(nt_cell$share_small_molecule, nt_cell$n_qualifying_inventors)),
  share_biotech = c(wmean(treated_fs$share_biotech, treated_fs$n_qualifying_inventors),
                    wmean(nt_cell$share_biotech, nt_cell$n_qualifying_inventors)),
  share_formulation = c(wmean(treated_fs$share_formulation, treated_fs$n_qualifying_inventors),
                        wmean(nt_cell$share_formulation, nt_cell$n_qualifying_inventors)))
tech_rel$share_pharma_core <- tech_rel$share_small_molecule + tech_rel$share_biotech +
  tech_rel$share_formulation
# share of never-target inventor mass in cells with < 5% pharma-core share (distant giants)
nt_cell$pharma_core <- nt_cell$share_small_molecule + nt_cell$share_biotech + nt_cell$share_formulation
low_pharma_mass <- sum(nt_cell$n_qualifying_inventors[nt_cell$pharma_core < 0.05]) /
  sum(nt_cell$n_qualifying_inventors)
tech_rel$never_target_mass_below_5pct_pharma <- c(NA, round(low_pharma_mass, 3))
write_audit(tech_rel, "never_target_tech_relevance_audit.csv")
print(tech_rel)

# ===========================================================================
# ATTACH firm covariates + write units (inventor covariates deferred to 11g)
# ===========================================================================
units <- merge(units, firm_cov[, c("underlying_group_id","stack", FIRM_COVARS)],
               by = c("underlying_group_id","stack"), all.x = TRUE)
units <- merge(units, fk_n[, c("underlying_group_id","stack","n_qualifying_inventors")],
               by = c("underlying_group_id","stack"), all.x = TRUE)
units$treated <- 0L
units$arm <- "never_observed_target"

banner("Writing never-target units parquet")
duckdb::duckdb_register(con, "nt_out", units)
dbExecute(con, sprintf("COPY (SELECT * FROM nt_out) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
  gsub("\\\\","/", NT_UNITS_PARQUET)))
duckdb::duckdb_unregister(con, "nt_out")
message("Wrote ", NT_UNITS_PARQUET, " (", nrow(units), " rows, ",
        length(unique(units$firm_stack_key)), " cells)")
banner("11f DONE")
