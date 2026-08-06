# ============================================================================
# P5.1 rescue dependence diagnostics
# ============================================================================

LMV2_P5_RESCUE_DEPENDENCE_VERSION <-
  "local_match_v2_p5_rescue_dependence_v1"

lmv2_p5_rescue_weighted_mean <- function(x, w) {
  if (!length(x) || length(x) != length(w) ||
      any(!is.finite(x)) || any(!is.finite(w)) ||
      any(w < 0) || sum(w) <= 0) {
    stop("Invalid inputs to rescue weighted mean")
  }
  sum(x * w) / sum(w)
}

lmv2_p5_rescue_effective_count <- function(w) {
  if (!length(w) || any(!is.finite(w)) || any(w < 0) ||
      sum(w) <= 0) {
    return(NA_real_)
  }
  sum(w)^2 / sum(w^2)
}

lmv2_p5_rescue_compute_dependence <- function(context) {
  roster <- context$roster
  weight <- as.numeric(context$result$weight)
  if (nrow(roster) != length(weight) ||
      any(!is.finite(weight)) || any(weight <= 0)) {
    stop("Rescue dependence diagnostics received invalid final weights")
  }
  controls <- roster[roster$D == 0L, , drop = FALSE]
  controls$final_weight <- weight[roster$D == 0L]
  if (!nrow(controls)) {
    stop("Rescue dependence diagnostics received no controls")
  }

  by_deal <- split(controls, controls$deal_id)
  dependence <- do.call(rbind, lapply(by_deal, function(z) {
    firm_weight <- stats::aggregate(
      z$final_weight,
      list(control_group = z$control_group),
      sum)
    inventor_weight <- stats::aggregate(
      z$final_weight,
      list(control_codinv = z$control_codinv),
      sum)
    data.frame(
      cohort = as.integer(context$cohort),
      deal_id = as.integer(z$deal_id[[1]]),
      scheme = context$scheme,
      n_control_firms = nrow(firm_weight),
      n_distinct_control_inventors = nrow(inventor_weight),
      effective_firm_count =
        lmv2_p5_rescue_effective_count(firm_weight$x),
      maximum_firm_weight_share =
        max(firm_weight$x) / sum(firm_weight$x),
      reuse_adjusted_control_ess =
        lmv2_p5_rescue_effective_count(inventor_weight$x),
      stringsAsFactors = FALSE)
  }))
  rownames(dependence) <- NULL
  dependence$effective_firm_review_trigger <-
    dependence$cohort == 2000L &
    dependence$deal_id == 70L &
    dependence$effective_firm_count <
      LMV2_P5_RESCUE$gates$deal_70_effective_firm_review

  balance_variables <- unique(c(
    LMV2_HYBRID_INV_VARS, LMV2_HYBRID_FIRM_VARS))
  missing_variables <- setdiff(balance_variables, names(roster))
  if (length(missing_variables)) {
    stop(
      "Rescue leave-one-firm-out variables are absent from the roster: ",
      paste(missing_variables, collapse = ", "))
  }
  deal_70 <- roster[
    roster$cohort == 2000L & roster$deal_id == 70L,
    , drop = FALSE]
  deal_70$final_weight <- weight[
    roster$cohort == 2000L & roster$deal_id == 70L]
  loo <- data.frame(
    cohort = integer(), deal_id = integer(), scheme = character(),
    omitted_control_group = numeric(), variable = character(),
    full_control_mean = numeric(), leave_one_firm_out_mean = numeric(),
    pooled_unweighted_sd = numeric(), absolute_shift_sd = numeric(),
    threshold = numeric(), pass = logical(),
    stringsAsFactors = FALSE)
  if (nrow(deal_70)) {
    treated_70 <- deal_70[deal_70$D == 1L, , drop = FALSE]
    controls_70 <- deal_70[deal_70$D == 0L, , drop = FALSE]
    donor_firms <- sort(unique(controls_70$control_group))
    loo_rows <- vector("list", length(donor_firms) * length(balance_variables))
    at <- 0L
    for (firm in donor_firms) {
      retained <- controls_70$control_group != firm
      if (!any(retained)) {
        stop("Deal 70 has no control mass after a leave-one-firm-out check")
      }
      for (variable in balance_variables) {
        at <- at + 1L
        pooled <- c(treated_70[[variable]], controls_70[[variable]])
        pooled_sd <- stats::sd(pooled)
        full_mean <- lmv2_p5_rescue_weighted_mean(
          controls_70[[variable]], controls_70$final_weight)
        loo_mean <- lmv2_p5_rescue_weighted_mean(
          controls_70[[variable]][retained],
          controls_70$final_weight[retained])
        shift <- if (is.finite(pooled_sd) && pooled_sd > 0) {
          abs(loo_mean - full_mean) / pooled_sd
        } else if (isTRUE(all.equal(loo_mean, full_mean))) {
          0
        } else {
          Inf
        }
        threshold <-
          LMV2_P5_RESCUE$gates$
            deal_70_leave_one_firm_out_max_shift_sd
        loo_rows[[at]] <- data.frame(
          cohort = 2000L,
          deal_id = 70L,
          scheme = context$scheme,
          omitted_control_group = as.numeric(firm),
          variable = variable,
          full_control_mean = full_mean,
          leave_one_firm_out_mean = loo_mean,
          pooled_unweighted_sd = pooled_sd,
          absolute_shift_sd = shift,
          threshold = threshold,
          pass = is.finite(shift) && shift < threshold,
          stringsAsFactors = FALSE)
      }
    }
    loo <- do.call(rbind, loo_rows)
    rownames(loo) <- NULL
  }
  list(dependence = dependence, leave_one_firm_out = loo)
}

lmv2_p5_rescue_write_atomic_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(
    pattern = paste0(basename(path), "."),
    tmpdir = dirname(path), fileext = ".tmp")
  on.exit(unlink(temporary), add = TRUE)
  utils::write.csv(x, temporary, row.names = FALSE, na = "")
  temporary_hash <- lmv2_p3_file_hash(temporary)
  if (file.exists(path)) {
    if (!identical(lmv2_p3_file_hash(path), temporary_hash)) {
      stop("Rescue diagnostic artifact conflicts with existing file: ", path)
    }
    return(list(path = path, checksum = temporary_hash, rows = nrow(x)))
  }
  if (!file.rename(temporary, path)) {
    stop("Could not atomically commit rescue diagnostic artifact: ", path)
  }
  list(path = path, checksum = temporary_hash, rows = nrow(x))
}

lmv2_install_p5_rescue_dependence_diagnostics <- function(
    audit_dir, execution_hash) {
  if (!exists(
      "LMV2_P5_WEIGHT_CALLBACK", envir = .GlobalEnv, inherits = FALSE) ||
      !exists(
        "LMV2_P5_WEIGHT_READY", envir = .GlobalEnv, inherits = FALSE)) {
    stop("Install the P5 weight materializer before rescue diagnostics")
  }
  materialize <- get(
    "LMV2_P5_WEIGHT_CALLBACK", envir = .GlobalEnv, inherits = FALSE)
  materialized_ready <- get(
    "LMV2_P5_WEIGHT_READY", envir = .GlobalEnv, inherits = FALSE)
  manifest_path <- file.path(
    audit_dir, "dependence", "manifest.csv")

  diagnostic_key <- function(context) {
    lmv2_p5_weight_profile_hash(
      roster = context$roster,
      cohort = context$cohort,
      caliper = context$caliper,
      profile = context$profile,
      universe = context$universe,
      scheme = context$scheme,
      analysis_scope = "main",
      dealsim_tercile = NA_integer_,
      execution_hash = execution_hash)
  }
  callback <- function(context) {
    result <- lmv2_p5_rescue_compute_dependence(context)
    profile_hash <- diagnostic_key(context)
    dependence_path <- file.path(
      audit_dir, "dependence",
      sprintf(
        "dependence_%d_%s_%s.csv",
        as.integer(context$cohort), context$scheme,
        substr(profile_hash, 1, 12)))
    loo_path <- file.path(
      audit_dir, "dependence",
      sprintf(
        "leave_one_firm_out_%d_%s_%s.csv",
        as.integer(context$cohort), context$scheme,
        substr(profile_hash, 1, 12)))

    # Persist the certified weight artifact first. The ready predicate below
    # requires both diagnostics too, so a diagnostic write interruption is
    # restartable without accepting a weights-only profile.
    materialize(context)
    dependence_write <- lmv2_p5_rescue_write_atomic_csv(
      result$dependence, dependence_path)
    loo_write <- lmv2_p5_rescue_write_atomic_csv(
      result$leave_one_firm_out, loo_path)
    if (!lmv2_manifest_has_valid_row(
        manifest_path,
        c("cohort", "scheme", "profile_hash", "execution_hash"),
        c(
          context$cohort, context$scheme, profile_hash,
          execution_hash),
        path_col = "dependence_path",
        checksum_col = "dependence_checksum")) {
      lmv2_append_manifest_row(
        manifest_path,
        data.frame(
          version = LMV2_P5_RESCUE_DEPENDENCE_VERSION,
          cohort = as.integer(context$cohort),
          scheme = context$scheme,
          profile_hash = profile_hash,
          execution_hash = execution_hash,
          dependence_path = dependence_write$path,
          dependence_rows = dependence_write$rows,
          dependence_checksum = dependence_write$checksum,
          leave_one_firm_out_path = loo_write$path,
          leave_one_firm_out_rows = loo_write$rows,
          leave_one_firm_out_checksum = loo_write$checksum,
          status = "complete",
          timestamp = as.character(Sys.time()),
          stringsAsFactors = FALSE))
    }
    invisible(dependence_path)
  }
  ready <- function(
      cohort, caliper, profile, universe, scheme,
      live_execution_hash) {
    if (!materialized_ready(
        cohort, caliper, profile, universe, scheme,
        live_execution_hash)) {
      return(FALSE)
    }
    lmv2_manifest_has_valid_row(
      manifest_path,
      c(
        "cohort", "scheme", "execution_hash"),
      c(cohort, scheme, live_execution_hash),
      path_col = "dependence_path",
      checksum_col = "dependence_checksum") &&
      lmv2_manifest_has_valid_row(
        manifest_path,
        c(
          "cohort", "scheme", "execution_hash"),
        c(cohort, scheme, live_execution_hash),
        path_col = "leave_one_firm_out_path",
        checksum_col = "leave_one_firm_out_checksum")
  }
  assign(
    "LMV2_P5_WEIGHT_CALLBACK", callback,
    envir = .GlobalEnv)
  assign(
    "LMV2_P5_WEIGHT_READY", ready,
    envir = .GlobalEnv)
  invisible(TRUE)
}
