# Solve the six frozen P5b S3 cohort-level entropy-weighting specifications.

if (!exists("lmv2_p5b_s3_config")) {
  source(file.path("02_analysis", "R", "27a_lmv2_p5b_s3_config.R"))
}

lmv2_p5b_load_solver <- function(config) {
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(config$p4_root)
  source(file.path("02_analysis", "R",
                   "17m_lmv2_p4_cohort_hybrid_core.R"),
         local = .GlobalEnv)
  source(file.path("02_analysis", "R", "18j_lmv2_p5_newton_solver.R"),
         local = .GlobalEnv)
  lmv2_install_p5_newton_solver()
  invisible(TRUE)
}

lmv2_p5b_fit_cohort_warmstart <- function(
    vars, data, D_col = "D", s_weights,
    estimand = "ATT", moments = 1,
    maxit = LMV2_P4_EBAL$tolerances$maxit) {
  warm <- suppressWarnings(lmv2_p5_weightit_fit_cohort(
    vars, data, D_col, s_weights, estimand, moments, maxit))
  if (inherits(warm$fit, "condition") ||
      !identical(estimand, "ATT") || !identical(moments, 1)) {
    return(warm)
  }

  D <- data[[D_col]]
  treated <- which(D == 1L & is.finite(s_weights) & s_weights > 0)
  control <- which(D == 0L & is.finite(s_weights) & s_weights > 0)
  use_vars <- warm$formula_vars
  X_all <- as.matrix(warm$standardized_data[use_vars])
  qr_x <- qr(X_all[control, , drop = FALSE])
  solver_vars <- use_vars[qr_x$pivot[seq_len(qr_x$rank)]]
  X_control <- X_all[control, solver_vars, drop = FALSE]
  X_treated <- X_all[treated, solver_vars, drop = FALSE]

  multiplier <- warm$fit$weights[control]
  if (any(!is.finite(multiplier) | multiplier <= 0)) {
    return(warm)
  }
  initial <- stats::lm.fit(
    cbind(intercept = 1, X_control), log(multiplier))$coefficients[-1L]
  initial[!is.finite(initial)] <- 0
  target <- drop(crossprod(
    X_treated, s_weights[treated]) / sum(s_weights[treated]))
  solved <- tryCatch(
    nleqslv::nleqslv(
      x = initial,
      fn = lmv2_p5_newton_moments,
      jac = lmv2_p5_newton_jacobian,
      X = X_control,
      prior = s_weights[control],
      target = target,
      method = "Newton",
      global = "dbldog",
      control = list(
        ftol = LMV2_P4_EBAL$tolerances$exact_tol / 10,
        xtol = 1e-10,
        maxit = min(as.integer(maxit), 5000L))),
    error = function(e) e)
  if (inherits(solved, "condition") ||
      !solved$termcd %in% c(1L, 2L) ||
      !all(is.finite(solved$x))) {
    return(warm)
  }

  raw <- rep(1, nrow(data))
  raw[control] <- lmv2_p5_newton_tilt(
    solved$x, X_control, rep(1, length(control)))
  warm$fit <- list(
    weights = raw,
    fit.obj = list(
      solver = "weightit_warmstart_newton",
      coefficients = stats::setNames(solved$x, solver_vars),
      termcd = solved$termcd,
      message = solved$message,
      iterations = solved$iter,
      residual = max(abs(solved$fvec))))
  warm
}

lmv2_p5b_cell_paths <- function(config, spec, cohort) {
  stem <- sprintf("%s_c%d", spec, cohort)
  list(
    weights = file.path(config$weight_dir, paste0(stem, ".csv")),
    balance = file.path(config$balance_dir, paste0(stem, ".csv"))
  )
}

lmv2_p5b_run_cell <- function(config, spec_name, cohort) {
  spec <- config$weight_specs[[spec_name]]
  input <- file.path(
    config$source_dir, sprintf("%s_c%d.csv", spec$support, cohort))
  if (!file.exists(input)) stop("Missing S3 support cell: ", input)
  x <- utils::read.csv(input, stringsAsFactors = FALSE, check.names = FALSE)
  if (!nrow(x)) {
    return(data.frame(
      spec = spec_name, support_variant = spec$support, cohort = cohort,
      feasible = FALSE, mode = "empty_cell", tier = NA_character_,
      solver_path = NA_character_,
      n_treated = 0L, n_control_rows = 0L,
      n_unique_control_inventors = 0L, n_deals = 0L,
      reuse_adjusted_ess = NA_real_, reuse_adjusted_ess_ratio = NA_real_,
      effective_control_firms = NA_real_, max_smd_before = NA_real_,
      max_smd_after = NA_real_, max_control_inventor_share = NA_real_,
      top5_control_inventor_share = NA_real_, elapsed_seconds = 0,
      weight_path = NA_character_, balance_path = NA_character_,
      stringsAsFactors = FALSE))
  }

  inv_vars <- setdiff(config$inv_vars, spec$omit)
  firm_vars <- setdiff(config$firm_vars, spec$omit)
  balance_vars <- c(inv_vars, firm_vars)
  required <- c(
    "cohort", "deal_id", "codinv", "treated", "control_group",
    "established_early_recruitment", balance_vars)
  if (!all(required %in% names(x))) {
    stop("S3 cell lacks: ", paste(setdiff(required, names(x)), collapse = ", "))
  }

  treated <- x[x$treated == 1L, ]
  control <- x[x$treated == 0L, ]
  treated_rows <- data.frame(
    cohort = as.integer(treated$cohort),
    deal_id = as.numeric(treated$deal_id),
    treated_codinv = as.numeric(treated$codinv),
    treated[balance_vars],
    check.names = FALSE)
  control_rows <- data.frame(
    cohort = as.integer(control$cohort),
    deal_id = as.numeric(control$deal_id),
    control_codinv = as.numeric(control$codinv),
    control_group = as.numeric(control$control_group),
    control[balance_vars],
    check.names = FALSE)

  start <- proc.time()[["elapsed"]]
  base <- lmv2_ebal_allocate_deal_base_weights(
    treated_rows, control_rows, scheme = "primary")
  roster <- lmv2_ebal_build_cohort_roster(
    treated_rows, control_rows, base,
    inv_vars = inv_vars, firm_vars = firm_vars)
  # S3 support restriction is already complete. The solver's retention gate
  # therefore receives the admitted S3 treated roster, while original-S2
  # retention is certified separately from s3_support_diagnostics.csv.
  fit <- lmv2_ebal_cohort_feasibility_hierarchy(
    roster, n_eligible_treated = sum(roster$D == 1L),
    inv_vars = inv_vars, firm_vars = firm_vars)
  solver_path <- "newton"
  if (!fit$mode %in% c(
      "exact_ebal", "optweight_0.05", "optweight_0.10")) {
    old_solver <- get("lmv2_ebal_fit_cohort", envir = .GlobalEnv)
    assign(
      "lmv2_ebal_fit_cohort",
      lmv2_p5b_fit_cohort_warmstart,
      envir = .GlobalEnv)
    fit_warm <- tryCatch(
      lmv2_ebal_cohort_feasibility_hierarchy(
        roster, n_eligible_treated = sum(roster$D == 1L),
        inv_vars = inv_vars, firm_vars = firm_vars),
      error = function(e) e)
    assign("lmv2_ebal_fit_cohort", old_solver, envir = .GlobalEnv)
    if (!inherits(fit_warm, "condition") &&
        fit_warm$mode %in% c(
          "exact_ebal", "optweight_0.05", "optweight_0.10")) {
      fit <- fit_warm
      solver_path <- "weightit_warmstart_newton"
    }
  }
  elapsed <- proc.time()[["elapsed"]] - start
  feasible <- fit$mode %in% c("exact_ebal", "optweight_0.05",
                              "optweight_0.10")

  if (!feasible) {
    return(data.frame(
      spec = spec_name, support_variant = spec$support, cohort = cohort,
      feasible = FALSE, mode = fit$mode, tier = fit$tier,
      solver_path = solver_path,
      n_treated = sum(roster$D == 1L),
      n_control_rows = sum(roster$D == 0L),
      n_unique_control_inventors =
        length(unique(roster$control_codinv[roster$D == 0L])),
      n_deals = length(unique(roster$deal_id)),
      reuse_adjusted_ess = NA_real_, reuse_adjusted_ess_ratio = NA_real_,
      effective_control_firms = NA_real_, max_smd_before = NA_real_,
      max_smd_after = NA_real_, max_control_inventor_share = NA_real_,
      top5_control_inventor_share = NA_real_, elapsed_seconds = elapsed,
      weight_path = NA_character_, balance_path = NA_character_,
      stringsAsFactors = FALSE))
  }

  final_weight <- fit$result$weight
  std <- lmv2_ebal_standardize_cohort(balance_vars, roster)
  use_vars <- setdiff(balance_vars, std$zero_variance)
  before <- lmv2_ebal_covariate_balance(
    use_vars, std$data, roster$D, roster$base_weight)
  after <- lmv2_ebal_covariate_balance(
    use_vars, std$data, roster$D, final_weight)
  names(before)[names(before) %in%
                  c("treated_mean", "control_mean", "difference",
                    "abs_difference")] <- paste0(
                      names(before)[names(before) %in%
                                      c("treated_mean", "control_mean",
                                        "difference", "abs_difference")],
                      "_before")
  names(after)[names(after) %in%
                 c("treated_mean", "control_mean", "difference",
                   "abs_difference")] <- paste0(
                     names(after)[names(after) %in%
                                    c("treated_mean", "control_mean",
                                      "difference", "abs_difference")],
                     "_after")
  balance <- merge(before, after, by = "variable", all = TRUE, sort = FALSE)
  balance$spec <- spec_name
  balance$support_variant <- spec$support
  balance$cohort <- cohort

  weights <- data.frame(
    spec = spec_name,
    support_variant = spec$support,
    cohort = roster$cohort,
    deal_id = roster$deal_id,
    codinv = ifelse(roster$D == 1L, roster$treated_codinv,
                    roster$control_codinv),
    treated = roster$D,
    control_group = roster$control_group,
    base_weight = roster$base_weight,
    final_weight = final_weight,
    roster[balance_vars],
    check.names = FALSE)
  status_key <- unique(x[c(
    "cohort", "deal_id", "codinv", "treated",
    "established_early_recruitment")])
  weights <- merge(
    weights, status_key,
    by = c("cohort", "deal_id", "codinv", "treated"),
    all.x = TRUE, sort = FALSE)
  if (anyNA(weights$established_early_recruitment)) {
    stop("Established/recent flag failed to attach in ", spec_name,
         " cohort ", cohort)
  }

  paths <- lmv2_p5b_cell_paths(config, spec_name, cohort)
  lmv2_write_csv(weights, paths$weights)
  lmv2_write_csv(balance, paths$balance)

  control_weight <- final_weight[roster$D == 0L]
  control_id <- roster$control_codinv[roster$D == 0L]
  control_group <- roster$control_group[roster$D == 0L]
  reuse_ess <- lmv2_ebal_effective_inventor_count(
    control_weight, control_id)
  concentration <- lmv2_ebal_reuse_adjusted_concentration(
    control_weight, control_id)
  data.frame(
    spec = spec_name, support_variant = spec$support, cohort = cohort,
    feasible = TRUE, mode = fit$mode, tier = fit$tier,
    solver_path = solver_path,
    n_treated = sum(roster$D == 1L),
    n_control_rows = sum(roster$D == 0L),
    n_unique_control_inventors = length(unique(control_id)),
    n_deals = length(unique(roster$deal_id)),
    reuse_adjusted_ess = reuse_ess,
    reuse_adjusted_ess_ratio = reuse_ess / sum(roster$D == 1L),
    effective_control_firms = lmv2_ebal_effective_firm_count(
      control_weight, control_group),
    max_smd_before = max(balance$abs_difference_before, na.rm = TRUE),
    max_smd_after = max(balance$abs_difference_after, na.rm = TRUE),
    max_control_inventor_share = concentration$max_share,
    top5_control_inventor_share = concentration$top5_share,
    elapsed_seconds = elapsed,
    weight_path = normalizePath(paths$weights, winslash = "/", mustWork = TRUE),
    balance_path = normalizePath(paths$balance, winslash = "/", mustWork = TRUE),
    stringsAsFactors = FALSE)
}

lmv2_run_p5b_s3_weights <- function(
    config = lmv2_p5b_s3_config(),
    spec_names = names(config$weight_specs),
    cohorts = 1994:2010) {
  dir.create(config$weight_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(config$balance_dir, recursive = TRUE, showWarnings = FALSE)
  if (!length(spec_names) ||
      any(!spec_names %in% names(config$weight_specs))) {
    stop("Unknown or empty S3 weight specification selection")
  }
  if (!length(cohorts) || any(!cohorts %in% 1994:2010)) {
    stop("Unknown or empty S3 cohort selection")
  }
  lmv2_p5b_load_solver(config)

  diagnostics <- list()
  k <- 0L
  for (spec in spec_names) {
    for (cohort in cohorts) {
      k <- k + 1L
      message("S3 weighting ", spec, " cohort ", cohort)
      diagnostics[[k]] <- lmv2_p5b_run_cell(config, spec, cohort)
    }
  }
  diagnostics <- do.call(rbind, diagnostics)
  path <- file.path(config$output_dir, "s3_weight_diagnostics.csv")
  if (file.exists(path)) {
    prior <- read.csv(path, stringsAsFactors = FALSE)
    replace_key <- paste(
      rep(spec_names, each = length(cohorts)),
      rep(cohorts, times = length(spec_names)), sep = ":")
    prior_key <- paste(prior$spec, prior$cohort, sep = ":")
    prior <- prior[!prior_key %in% replace_key, , drop = FALSE]
    diagnostics <- as.data.frame(data.table::rbindlist(
      list(prior, diagnostics), fill = TRUE, use.names = TRUE))
  }
  diagnostics <- diagnostics[order(
    match(diagnostics$spec, names(config$weight_specs)),
    diagnostics$cohort), , drop = FALSE]
  lmv2_write_csv(diagnostics, path)
  invisible(diagnostics)
}
