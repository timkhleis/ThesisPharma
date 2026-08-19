# Build, balance, and certify the initially-outside S3 design.

if (!exists("lmv2_io_config")) {
  source(file.path("02_analysis", "R",
                   "71a_lmv2_initially_outside_config.R"))
}

lmv2_io_read_parquet <- function(path, where = NULL) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  query <- paste0("SELECT * FROM read_parquet(",
                  lmv2_io_sql_string(path), ")")
  if (!is.null(where)) query <- paste(query, "WHERE", where)
  DBI::dbGetQuery(con, query)
}

lmv2_io_write_parquet <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "io_output", x, overwrite = TRUE)
  DBI::dbExecute(con, paste0(
    "COPY io_output TO ", lmv2_io_sql_string(path),
    " (FORMAT PARQUET, COMPRESSION ZSTD)"))
  invisible(path)
}

lmv2_io_effective_count <- function(w) {
  w <- w[is.finite(w) & w > 0]
  if (!length(w)) return(0)
  sum(w)^2 / sum(w^2)
}

lmv2_io_prepare_support <- function(x) {
  key <- paste(x$cohort, x$deal_id, sep = ":")
  tab <- aggregate(
    treated ~ cohort + deal_id, x,
    function(z) c(n_treated = sum(z == 1L), n_control = sum(z == 0L)))
  counts <- data.frame(
    cohort = tab$cohort, deal_id = tab$deal_id,
    n_treated = tab$treated[, "n_treated"],
    n_control = tab$treated[, "n_control"])
  keep <- paste(counts$cohort[counts$n_treated > 0 & counts$n_control > 0],
                counts$deal_id[counts$n_treated > 0 & counts$n_control > 0],
                sep = ":")
  x[key %in% keep, , drop = FALSE]
}

lmv2_io_tier_vars <- function(config, tier, cell_cohorts, data) {
  full <- tier %in% c("A_cohort_count_active_scale",
                      "C_era_count_active_scale")
  vars <- c(paste0("patent_count_m", 5:1),
            if (full) paste0("active_patenting_m", 5:1) else character(),
            "career_age", "focal_group_exclusivity",
            config$firm_vars)
  dummy_vars <- character()
  if (tier %in% c("C_era_count_active_scale", "D_era_count_scale")) {
    for (cohort in tail(sort(cell_cohorts), -1L)) {
      nm <- paste0("cohort_", cohort)
      data[[nm]] <- as.integer(data$cohort == cohort)
      dummy_vars <- c(dummy_vars, nm)
    }
  }
  list(data = data, inv_vars = c(setdiff(vars, config$firm_vars), dummy_vars),
       firm_vars = config$firm_vars, balance_vars = c(vars, dummy_vars))
}

lmv2_io_fit_exact_cell <- function(config, data, tier, cell_label,
                                   loyo = NA_integer_) {
  cell_cohorts <- sort(unique(data$cohort))
  setup <- lmv2_io_tier_vars(config, tier, cell_cohorts, data)
  x <- setup$data
  inv_vars <- setup$inv_vars
  firm_vars <- setup$firm_vars
  if (is.finite(loyo)) {
    inv_vars <- setdiff(inv_vars,
                        c(paste0("patent_count_m", loyo),
                          paste0("active_patenting_m", loyo)))
  }
  balance_vars <- c(inv_vars, firm_vars)

  treated <- x[x$treated == 1L, , drop = FALSE]
  control <- x[x$treated == 0L, , drop = FALSE]
  if (!nrow(treated) || !nrow(control)) {
    return(list(pass = FALSE, diagnostics = data.frame(
      cell = cell_label, status = "empty_arm", n_treated = nrow(treated),
      n_control_rows = nrow(control), reuse_ess = NA_real_,
      ess_ratio = NA_real_, max_smd = NA_real_, stringsAsFactors = FALSE)))
  }

  treated_rows <- data.frame(
    cohort = as.integer(treated$cohort), deal_id = treated$deal_id,
    treated_codinv = treated$codinv, treated[balance_vars],
    check.names = FALSE)
  control_rows <- data.frame(
    cohort = as.integer(control$cohort), deal_id = control$deal_id,
    control_codinv = control$codinv, control_group = control$control_group,
    control[balance_vars], check.names = FALSE)

  attempted <- tryCatch({
    base <- lmv2_ebal_allocate_deal_base_weights(
      treated_rows, control_rows, scheme = "primary")
    roster <- lmv2_ebal_build_cohort_roster(
      treated_rows, control_rows, base,
      inv_vars = inv_vars, firm_vars = firm_vars)
    exact <- lmv2_ebal_cohort_exact_solve(
      roster, inv_vars = inv_vars, firm_vars = firm_vars)
    if (!identical(exact$eb$status, "pass")) {
      old_solver <- get("lmv2_ebal_fit_cohort", envir = .GlobalEnv)
      assign("lmv2_ebal_fit_cohort", lmv2_p5b_fit_cohort_warmstart,
             envir = .GlobalEnv)
      on.exit(assign("lmv2_ebal_fit_cohort", old_solver,
                     envir = .GlobalEnv), add = TRUE)
      exact_warm <- lmv2_ebal_cohort_exact_solve(
        roster, inv_vars = inv_vars, firm_vars = firm_vars)
      if (identical(exact_warm$eb$status, "pass")) exact <- exact_warm
    }
    list(roster = roster, exact = exact)
  }, error = function(e) e)

  if (inherits(attempted, "condition")) {
    return(list(pass = FALSE, diagnostics = data.frame(
      cell = cell_label, status = paste0("error: ", conditionMessage(attempted)),
      n_treated = nrow(treated), n_control_rows = nrow(control),
      reuse_ess = NA_real_, ess_ratio = NA_real_, max_smd = NA_real_,
      stringsAsFactors = FALSE)))
  }

  roster <- attempted$roster
  eb <- attempted$exact$eb
  status <- eb$status
  if (!identical(status, "pass")) {
    return(list(pass = FALSE, diagnostics = data.frame(
      cell = cell_label, status = status, n_treated = sum(roster$D == 1L),
      n_control_rows = sum(roster$D == 0L), reuse_ess = NA_real_,
      ess_ratio = NA_real_, max_smd = eb$maxdiff %||% NA_real_,
      stringsAsFactors = FALSE)))
  }

  control_index <- roster$D == 0L
  reuse_ess <- lmv2_ebal_effective_inventor_count(
    eb$weight[control_index], roster$control_codinv[control_index])
  ess_ratio <- reuse_ess / sum(roster$D == 1L)
  max_smd <- max(eb$balance$abs_difference, na.rm = TRUE)
  pass <- is.finite(max_smd) &&
    max_smd <= config$gates$maximum_exact_smd &&
    is.finite(ess_ratio) &&
    ess_ratio >= config$gates$minimum_reuse_adjusted_ess_ratio

  weights <- data.frame(
    cohort = roster$cohort, deal_id = roster$deal_id,
    codinv = ifelse(roster$D == 1L, roster$treated_codinv,
                    roster$control_codinv),
    treated = roster$D, control_group = roster$control_group,
    base_weight = roster$base_weight, final_weight = eb$weight,
    stringsAsFactors = FALSE)
  attach <- unique(x[c("cohort", "deal_id", "codinv", "treated",
                       "first_post_year", "first_post_group")])
  weights <- merge(weights, attach,
                   by = c("cohort", "deal_id", "codinv", "treated"),
                   all.x = TRUE, sort = FALSE)
  pre <- unique(x[c("cohort", "deal_id", "codinv", "treated",
                    paste0("patent_count_m", 5:1),
                    paste0("active_patenting_m", 5:1))])
  weights <- merge(weights, pre,
                   by = c("cohort", "deal_id", "codinv", "treated"),
                   all.x = TRUE, sort = FALSE)
  balance <- eb$balance
  balance$cell <- cell_label
  diagnostics <- data.frame(
    cell = cell_label, status = if (pass) "pass" else "gate_failed",
    n_treated = sum(roster$D == 1L),
    n_control_rows = sum(roster$D == 0L), reuse_ess = reuse_ess,
    ess_ratio = ess_ratio, max_smd = max_smd,
    stringsAsFactors = FALSE)
  list(pass = pass, weights = weights, balance = balance,
       diagnostics = diagnostics)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

lmv2_io_run_design <- function(config, data, tier, label, loyo = NA_integer_) {
  cohort_specific <- tier %in% c("A_cohort_count_active_scale",
                                 "B_cohort_count_scale")
  cells <- if (cohort_specific) {
    stats::setNames(lapply(sort(unique(data$cohort)), function(g) g),
                    sort(unique(data$cohort)))
  } else {
    Filter(length, lapply(config$eras, function(g) intersect(g, data$cohort)))
  }
  results <- lapply(names(cells), function(nm) {
    g <- cells[[nm]]
    lmv2_io_fit_exact_cell(
      config, data[data$cohort %in% g, , drop = FALSE], tier,
      cell_label = nm, loyo = loyo)
  })
  diagnostics <- do.call(rbind, lapply(results, `[[`, "diagnostics"))
  pass <- all(vapply(results, function(z) isTRUE(z$pass), logical(1)))
  list(
    pass = pass,
    diagnostics = transform(diagnostics, tier = tier, specification = label),
    weights = if (pass) do.call(rbind, lapply(results, `[[`, "weights")) else NULL,
    balance = if (pass) do.call(rbind, lapply(results, `[[`, "balance")) else NULL)
}

lmv2_io_heldout <- function(weights, event_time) {
  outcome <- weights[[paste0("patent_count_m", abs(event_time))]] -
    weights$patent_count_m1
  w <- weights$final_weight
  d <- weights$treated == 1L
  mu_t <- weighted.mean(outcome[d], w[d])
  mu_c <- weighted.mean(outcome[!d], w[!d])
  co <- mu_t - mu_c
  score <- numeric(length(outcome))
  score[d] <- w[d] * (outcome[d] - mu_t) / sum(w[d])
  score[!d] <- -w[!d] * (outcome[!d] - mu_c) / sum(w[!d])
  cluster_meat <- function(id) {
    sums <- rowsum(score, group = id, reorder = FALSE)
    g <- nrow(sums)
    if (g <= 1L) return(NA_real_)
    g / (g - 1) * sum(sums^2)
  }
  intersection <- paste(weights$deal_id, weights$codinv, sep = ":")
  variance <- cluster_meat(weights$deal_id) +
    cluster_meat(weights$codinv) - cluster_meat(intersection)
  se <- sqrt(max(variance, 0))
  list(
    summary = data.frame(
      event_time = event_time, estimate = co, std_error = se,
      conf_low = co - 1.96 * se, conf_high = co + 1.96 * se,
      stringsAsFactors = FALSE),
    score = data.frame(
      deal_id = weights$deal_id, codinv = weights$codinv,
      treated = weights$treated, score = score,
      stringsAsFactors = FALSE))
}

lmv2_io_heldout_joint_test <- function(heldout_objects) {
  score_frames <- lapply(seq_along(heldout_objects), function(j) {
    x <- heldout_objects[[j]]$score
    names(x)[names(x) == "score"] <- paste0("score_", j)
    x
  })
  scores <- Reduce(function(x, y) merge(
    x, y, by = c("deal_id", "codinv", "treated"), all = TRUE),
    score_frames)
  score_names <- grep("^score_", names(scores), value = TRUE)
  scores[score_names] <- lapply(scores[score_names], function(x) {
    x[is.na(x)] <- 0
    x
  })
  s <- as.matrix(scores[score_names])
  cluster_meat <- function(id) {
    sums <- rowsum(s, id, reorder = FALSE)
    g <- nrow(sums)
    g / (g - 1) * crossprod(sums)
  }
  intersection <- paste(scores$deal_id, scores$codinv, sep = ":")
  vcov <- cluster_meat(scores$deal_id) + cluster_meat(scores$codinv) -
    cluster_meat(intersection)
  estimates <- vapply(heldout_objects, function(x) x$summary$estimate,
                      numeric(1))
  statistic <- drop(crossprod(estimates, solve(vcov, estimates)))
  data.frame(
    statistic = statistic, degrees_freedom = length(estimates),
    p_value = stats::pchisq(statistic, df = length(estimates),
                            lower.tail = FALSE),
    stringsAsFactors = FALSE)
}

lmv2_build_initially_outside_s3 <- function(config = lmv2_io_config()) {
  source(file.path("02_analysis", "R", "00_utils.R"))
  use_project_library()
  required <- c("DBI", "duckdb", "data.table", "WeightIt", "nleqslv",
                "digest")
  missing <- required[!vapply(required, requireNamespace, logical(1),
                             quietly = TRUE)]
  if (length(missing)) stop("Missing R packages: ", paste(missing, collapse = ", "))

  source(file.path("02_analysis", "R", "27c_run_lmv2_p5b_s3_weights.R"))
  lmv2_p5b_load_solver(list(p4_root = config$source_root))
  dir.create(config$s3_dir, recursive = TRUE, showWarnings = FALSE)

  nested_path <- file.path(config$s0_dir,
                           "p5c_nested_initially_outside_roster.parquet")
  if (!file.exists(nested_path)) stop("Run and certify S0-S2 first")
  all_nested <- lmv2_io_read_parquet(nested_path)
  variants <- split(all_nested, all_nested$support_variant)
  variants <- lapply(variants, lmv2_io_prepare_support)
  support <- do.call(rbind, variants)
  lmv2_io_write_parquet(
    support, file.path(config$s3_dir, "s3_support_roster.parquet"))

  broad <- read.csv(file.path(config$s0_dir, "p5c_nesting_audit.csv"),
                    stringsAsFactors = FALSE)
  primary_broad <- broad[
    broad$support_variant == "primary_initially_outside_t1_t5" &
      broad$arm == "treated", ]
  p5c_retention <- sum(primary_broad$nested_inventors) /
    sum(primary_broad$broad_inventors)
  primary <- variants[["primary_initially_outside_t1_t5"]]
  support_retention <- length(unique(paste(
    primary$cohort[primary$treated == 1L],
    primary$deal_id[primary$treated == 1L],
    primary$codinv[primary$treated == 1L]))) /
    sum(primary_broad$broad_inventors)

  ladder <- list()
  selected <- NULL
  for (tier in config$balance_tiers) {
    message("Attempting initially-outside balance tier: ", tier)
    attempt <- lmv2_io_run_design(config, primary, tier,
                                  "primary_initially_outside_t1_t5")
    ladder[[tier]] <- attempt
    if (isTRUE(attempt$pass)) {
      selected <- attempt
      selected_tier <- tier
      break
    }
  }
  ladder_diag <- do.call(rbind, lapply(ladder, `[[`, "diagnostics"))
  lmv2_io_write_csv(ladder_diag,
                    file.path(config$s3_dir, "balance_ladder_diagnostics.csv"))
  if (is.null(selected)) {
    lmv2_io_write_csv(data.frame(
      selected_tier = NA_character_, p5c_retention = p5c_retention,
      support_retention = support_retention, status = "all_tiers_failed"),
      file.path(config$s3_dir, "s3_gate_summary.csv"))
    stop("All prospectively frozen exact-balance tiers failed")
  }

  selected$weights$support_variant <- "primary_initially_outside_t1_t5"
  selected$weights$balance_tier <- selected_tier
  weights_list <- list(primary_initially_outside_t1_t5 = selected$weights)
  balance_list <- list(primary_initially_outside_t1_t5 = selected$balance)
  sensitivity_diag <- list(selected$diagnostics)

  for (variant in setdiff(config$support_variants,
                          "primary_initially_outside_t1_t5")) {
    message("Balancing approved sensitivity: ", variant)
    attempt <- lmv2_io_run_design(config, variants[[variant]], selected_tier,
                                  variant)
    sensitivity_diag[[length(sensitivity_diag) + 1L]] <- attempt$diagnostics
    if (isTRUE(attempt$pass)) {
      attempt$weights$support_variant <- variant
      attempt$weights$balance_tier <- selected_tier
      weights_list[[variant]] <- attempt$weights
      balance_list[[variant]] <- attempt$balance
    }
  }

  production_weights <- do.call(rbind, weights_list)
  lmv2_io_write_parquet(
    production_weights,
    file.path(config$s3_dir, "s3_production_weights.parquet"))
  lmv2_io_write_csv(
    do.call(rbind, sensitivity_diag),
    file.path(config$s3_dir, "sensitivity_weight_diagnostics.csv"))
  lmv2_io_write_csv(
    do.call(rbind, balance_list),
    file.path(config$s3_dir, "s3_balance.csv"))

  loyo_results <- list()
  heldout_objects <- list()
  for (m in c(3L, 2L)) {
    message("Balancing held-out pretreatment specification m", m)
    attempt <- lmv2_io_run_design(
      config, primary, selected_tier,
      paste0("primary_loyo_m", m), loyo = m)
    loyo_results[[paste0("m", m)]] <- attempt
    if (!attempt$pass) stop("Selected tier failed LOYO m", m)
    message("Estimating held-out pretreatment contrast m", m)
    heldout_objects[[paste0("m", m)]] <-
      lmv2_io_heldout(attempt$weights, -m)
  }
  heldout <- do.call(rbind, lapply(heldout_objects, `[[`, "summary"))
  heldout_joint <- lmv2_io_heldout_joint_test(heldout_objects)
  lmv2_io_write_csv(heldout,
                    file.path(config$s3_dir, "heldout_preperiod.csv"))
  lmv2_io_write_csv(
    heldout_joint,
    file.path(config$s3_dir, "heldout_preperiod_joint_test.csv"))
  lmv2_io_write_csv(
    do.call(rbind, lapply(loyo_results, `[[`, "diagnostics")),
    file.path(config$s3_dir, "loyo_weight_diagnostics.csv"))

  design_se <- max(heldout$std_error)
  mde <- (1.96 + 0.84) * design_se
  control <- selected$weights[selected$weights$treated == 0L, ]
  pre_mean_i <- rowMeans(control[paste0("patent_count_m", 5:1)])
  control_pre_mean <- weighted.mean(pre_mean_i, control$final_weight)
  mde_table <- data.frame(
    design_se = design_se, mde_80 = mde,
    weighted_control_pre_mean = control_pre_mean,
    mde_percent_control_pre = 100 * mde / control_pre_mean,
    equivalence_percent = config$gates$equivalence_percent,
    stringsAsFactors = FALSE)
  lmv2_io_write_csv(mde_table,
                    file.path(config$s3_dir, "preperiod_mde.csv"))

  treated <- selected$weights[selected$weights$treated == 1L, ]
  deal_mass <- aggregate(final_weight ~ cohort + deal_id, treated, sum)
  effective_deals <- lmv2_io_effective_count(deal_mass$final_weight)
  gate <- data.frame(
    selected_tier = selected_tier,
    p5c_retention = p5c_retention,
    support_retention = support_retention,
    effective_treated_deals = effective_deals,
    max_smd = max(selected$diagnostics$max_smd),
    min_ess_ratio = min(selected$diagnostics$ess_ratio),
    pass_retention = support_retention >=
      config$gates$minimum_treated_retention,
    pass_effective_deals = effective_deals >=
      config$gates$minimum_effective_treated_deals,
    pass_exact_balance = max(selected$diagnostics$max_smd) <=
      config$gates$maximum_exact_smd,
    pass_ess = min(selected$diagnostics$ess_ratio) >=
      config$gates$minimum_reuse_adjusted_ess_ratio,
    stringsAsFactors = FALSE)
  gate$all_pass <- with(gate, pass_retention & pass_effective_deals &
                          pass_exact_balance & pass_ess)
  lmv2_io_write_csv(gate, file.path(config$s3_dir, "s3_gate_summary.csv"))

  manifest_paths <- c(
    config$plan_files,
    file.path(config$base, "02_analysis", "R",
              c("71a_lmv2_initially_outside_config.R",
                "72_build_lmv2_initially_outside_s3.R")),
    nested_path, config$p5c_diagnostics)
  manifest_paths <- manifest_paths[file.exists(manifest_paths)]
  manifest <- data.frame(
    path = normalizePath(manifest_paths, winslash = "/", mustWork = TRUE),
    sha256 = vapply(manifest_paths, lmv2_io_sha256, character(1)),
    stringsAsFactors = FALSE)
  lmv2_io_write_csv(manifest, file.path(config$s3_dir, "s3_manifest.csv"))

  if (!isTRUE(gate$all_pass)) {
    stop("Initially-outside S3 governing gate failed")
  }
  invisible(gate)
}
