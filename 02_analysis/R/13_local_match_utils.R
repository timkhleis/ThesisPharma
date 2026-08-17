# ============================================================================
# 13_local_match_utils.R  -- functions only (safe to source; no top-level exec)
# ----------------------------------------------------------------------------
# Small utilities for the local two-stage nearest-neighbour matching pilot
# (design version local_match_v1). Reuses certified helpers from
# 11_main_design_utils.R (smd_weighted, ess) which the caller must have sourced.
# ============================================================================

suppressWarnings(suppressMessages({
  library(DBI); library(duckdb); library(data.table)
}))

# --- logging ----------------------------------------------------------------
lm_banner  <- function(msg) cat("\n========== ", msg, " ==========\n", sep = "")
lm_section <- function(msg) cat("---- ", msg, "\n", sep = "")
lm_assert  <- function(cond, msg) {
  if (!isTRUE(cond)) stop("[ASSERT FAILED] ", msg, call. = FALSE)
  cat("  [ok] ", msg, "\n", sep = "")
}

# --- DuckDB (inline; explicit 02_analysis path -- connect_duckdb() is stale) --
lm_connect <- function(duckdb_path = DUCKDB, mem = "9GB", threads = 4L,
                       tmp = DUCKDB_TMP) {
  con <- dbConnect(duckdb::duckdb(), duckdb_path, read_only = TRUE)
  dbExecute(con, sprintf("PRAGMA memory_limit='%s'", mem))
  dbExecute(con, sprintf("PRAGMA threads=%d", threads))
  if (!is.null(tmp)) dbExecute(con, sprintf("PRAGMA temp_directory='%s'",
                                            gsub("\\\\", "/", tmp)))
  con
}

# --- IO ---------------------------------------------------------------------
sql_path <- function(p) gsub("\\\\", "/", p)

# Write an R data.frame to parquet via a (read-only-DB) connection using an
# in-registered view. Works on read_only connections because COPY targets a file.
lm_write_parquet <- function(con, df, path, view = "lm_out") {
  df <- cbind(design_hash = rep(LM_DESIGN_HASH, nrow(df)), df)  # always stamp (schema-stable)
  duckdb::duckdb_register(con, view, df)
  on.exit(duckdb::duckdb_unregister(con, view), add = TRUE)
  tmp <- paste0(path, ".tmp")                                    # atomic: write temp then rename
  dbExecute(con, sprintf("COPY (SELECT * FROM %s) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)",
                         view, sql_path(tmp)))
  if (file.exists(path)) file.remove(path)
  file.rename(tmp, path)
  invisible(path)
}

# Read a parquet file into R via DuckDB (arrow may be absent in the project lib).
arrow_or_duck <- function(con, path) {
  dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", sql_path(path)))
}

# Stamp design_version + design_hash and write a CSV atomically to a directory.
lm_write_csv <- function(df, dir, name) {
  df <- cbind(design_version = DESIGN_VERSION_LM, design_hash = LM_DESIGN_HASH, df)
  p   <- file.path(dir, paste0(name, ".csv"))
  tmp <- paste0(p, ".tmp")
  utils::write.csv(df, tmp, row.names = FALSE)
  if (file.exists(p)) file.remove(p)
  file.rename(tmp, p)
  invisible(p)
}

# --- numeric helpers --------------------------------------------------------
pooled_sd <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 2L) return(NA_real_)
  s <- stats::sd(x)
  if (!is.finite(s) || s == 0) return(NA_real_)
  s
}

# pooled SDs of a set of columns over a data.frame (used to standardize gaps).
pooled_sds <- function(df, cols) {
  s <- vapply(cols, function(cc) pooled_sd(df[[cc]]), numeric(1))
  names(s) <- cols
  s
}

# 4-family transparent indicator columns from a modal_family vector.
family_dummies <- function(fam) {
  fam <- as.character(fam)
  data.frame(
    fam_small_molecule = as.integer(fam == "small_molecule"),
    fam_biotech        = as.integer(fam == "biotech"),
    fam_formulation    = as.integer(fam == "formulation")
  )
}

# --- nearest-neighbour core -------------------------------------------------
# One treated unit vs a candidate matrix.
#   tvec    : named numeric length p (treated values, aligned to names(sds))
#   Cmat    : n x p numeric matrix (candidate values, columns aligned to names(sds))
#   sds     : named numeric length p (pooled SDs; NA/0 -> that component contributes 0)
#   k       : number of neighbours required (EXACTLY k or unsupported)
#   caliper : max abs standardized component gap allowed (Inf = none)
# Returns NULL if fewer than k candidates survive the caliper; else a list with
# idx (row indices into Cmat), dist (euclidean over standardized gaps),
# maxabs (max abs standardized gap per chosen match), and gaps (k x p std gaps).
# knn_rank: ALL candidates surviving the caliper, ordered by euclidean distance.
# Returns a list (idx/dist/maxabs/gaps) which may have 0..nrow rows.
# caliper_cols selects which columns count toward the caliper max-abs-gap test.
# Distance is ALWAYS over all columns (so family indicators penalise distance but
# do NOT act as a hard block); default caliper_cols = all columns.
knn_rank <- function(tvec, Cmat, sds, caliper, caliper_cols = seq_len(ncol(Cmat))) {
  if (is.null(Cmat) || nrow(Cmat) == 0L)
    return(list(idx = integer(0), dist = numeric(0), maxabs = numeric(0),
                gaps = Cmat[0, , drop = FALSE]))
  sd_use <- sds
  sd_use[!is.finite(sd_use) | sd_use == 0] <- Inf   # divide -> 0 contribution
  G <- sweep(Cmat, 2L, tvec, `-`)
  G <- sweep(G, 2L, sd_use, `/`)
  G[!is.finite(G)] <- 0
  maxabs <- matrixStats_rowMaxAbs(G[, caliper_cols, drop = FALSE])  # caliper: selected cols
  dist   <- sqrt(rowSums(G * G))                                    # distance: all cols
  surv   <- which(maxabs <= caliper)
  ord    <- surv[order(dist[surv])]
  list(idx = ord, dist = dist[ord], maxabs = maxabs[ord], gaps = G[ord, , drop = FALSE])
}

# knn_one: EXACTLY k nearest survivors, or NULL if fewer than k survive.
knn_one <- function(tvec, Cmat, sds, k, caliper, caliper_cols = seq_len(ncol(Cmat))) {
  r <- knn_rank(tvec, Cmat, sds, caliper, caliper_cols)
  if (length(r$idx) < k) return(NULL)
  sel <- seq_len(k)
  list(idx = r$idx[sel], dist = r$dist[sel], maxabs = r$maxabs[sel],
       gaps = r$gaps[sel, , drop = FALSE])
}

# base-R row max of abs (avoid matrixStats dependency)
matrixStats_rowMaxAbs <- function(M) {
  do.call(pmax, c(lapply(seq_len(ncol(M)), function(j) abs(M[, j])), list(na.rm = TRUE)))
}

# --- reuse / concentration diagnostics --------------------------------------
# matched: data.table with columns control_id (character/num) and weight (numeric).
# Aggregates weight per control, returns a one-row summary data.frame.
reuse_concentration <- function(matched, id_col = "control_id", w_col = "weight",
                                label = "") {
  dt <- as.data.table(matched)
  agg <- dt[, .(w = sum(get(w_col)), times = .N), by = id_col]
  tot <- sum(agg$w)
  agg[, share := w / tot]
  setorder(agg, -share)
  top5 <- head(agg$share, 5L)
  used <- agg$times
  data.frame(
    label                 = label,
    n_matches             = nrow(dt),
    n_unique_controls     = nrow(agg),
    max_weight_share      = if (nrow(agg)) agg$share[1] else NA_real_,
    top5_weight_share     = sum(top5),
    ess_weight            = ess(agg$w),
    share_used_once       = mean(used == 1L),
    share_used_twice      = mean(used == 2L),
    share_used_gt5        = mean(used > 5L),
    max_times_used        = if (length(used)) max(used) else 0L,
    stringsAsFactors      = FALSE
  )
}

# --- balance ----------------------------------------------------------------
# Long-format ATT-standardized mean differences (smd_weighted denom = treated SD)
# for a set of variables, before (w=1) and after (analysis weights) matching.
# treated_df: covariate columns; control_df: same columns + a weight column.
balance_long <- function(treated_df, control_df, vars, control_w,
                         group_label = "pooled") {
  out <- vector("list", length(vars))
  for (i in seq_along(vars)) {
    v  <- vars[i]
    x  <- c(treated_df[[v]], control_df[[v]])
    tr <- c(rep(1L, nrow(treated_df)), rep(0L, nrow(control_df)))
    w1 <- rep(1, length(x))
    wA <- c(rep(1, nrow(treated_df)), control_w)
    ok <- is.finite(x)
    smd_before <- smd_weighted(x[ok], tr[ok], w1[ok])
    smd_after  <- smd_weighted(x[ok], tr[ok], wA[ok])
    out[[i]] <- data.frame(group = group_label, variable = v,
                           smd_before = smd_before, smd_after = smd_after,
                           abs_smd_after = abs(smd_after), stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# --- shard manifest ---------------------------------------------------------
shard_file <- function(cohort, stage, profile = NULL) {
  base <- if (is.null(profile)) sprintf("cohort_%d_%s.parquet", cohort, stage)
          else sprintf("cohort_%d_%s_%s.parquet", cohort, stage, profile)
  file.path(SHARD_DIR, base)
}

validate_shard_keys <- function(df, key_cols) {
  n  <- nrow(df)
  ks <- if (n == 0L) 0L else nrow(unique(df[, key_cols, drop = FALSE]))
  list(n_rows = n, n_unique_keys = ks, key_ok = (n == ks))
}

manifest_path <- function() file.path(SHARD_DIR, "shard_manifest.csv")

# manifest identity tuple for upsert
.man_key <- function(cohort, stage, profile, sample_def, dhash) {
  paste(cohort, stage, ifelse(is.na(profile) | profile == "", "NA", profile),
        sample_def, dhash, sep = "|")
}

# Upsert a manifest row keyed by (cohort, stage, profile, sample_definition,
# design_hash): replaces any existing matching row (no duplicate append). Atomic.
manifest_append <- function(cohort, stage, profile, path, n_rows, n_unique_keys,
                            key_ok, status) {
  prof <- ifelse(is.null(profile), NA_character_, profile)
  row <- data.frame(
    design_version = DESIGN_VERSION_LM, design_hash = LM_DESIGN_HASH,
    sample_definition = LM_SAMPLE, cohort = cohort, stage = stage, profile = prof,
    shard = basename(path), n_rows = n_rows, n_unique_keys = n_unique_keys,
    key_ok = key_ok, status = status,
    written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), stringsAsFactors = FALSE)
  mp  <- manifest_path()
  man <- if (file.exists(mp)) utils::read.csv(mp, stringsAsFactors = FALSE) else NULL
  if (!is.null(man) && nrow(man) && identical(sort(names(man)), sort(names(row)))) {
    keep <- .man_key(man$cohort, man$stage, man$profile, man$sample_definition, man$design_hash) !=
            .man_key(row$cohort, row$stage, row$profile, row$sample_definition, row$design_hash)
    man <- rbind(man[keep, names(row), drop = FALSE], row)
  } else man <- row
  tmp <- paste0(mp, ".tmp"); utils::write.csv(man, tmp, row.names = FALSE)
  if (file.exists(mp)) file.remove(mp); file.rename(tmp, mp)
  invisible(mp)
}

# Full restart validation: a cohort may be SKIPPED only if every expected shard
# passes against LM_SAMPLE, the current design_hash, manifest completion, unique
# keys, row count, and (inv) weight sums. Returns list(ok, reason).
verify_cohort_shards <- function(con, g, profile_names) {
  mp <- manifest_path()
  if (!file.exists(mp)) return(list(ok = FALSE, reason = "no manifest"))
  man <- utils::read.csv(mp, stringsAsFactors = FALSE)
  expect <- c(list(list(stage = "donorpool", profile = NA_character_)),
              lapply(profile_names, function(p) list(stage = "firm", profile = p)),
              lapply(profile_names, function(p) list(stage = "inv",  profile = p)))
  keycols <- list(firm = c("deal_id","control_group"),
                  inv = c("treated_codinv","control_codinv"),
                  donorpool = c("codinv","grp"))
  for (e in expect) {
    stage <- e$stage; prof <- e$profile
    path  <- if (is.na(prof)) shard_file(g, stage) else shard_file(g, stage, prof)
    bn <- basename(path)
    if (!file.exists(path)) return(list(ok = FALSE, reason = paste("missing", bn)))
    prof_match <- if (is.na(prof)) (is.na(man$profile) | man$profile == "") else
                  (!is.na(man$profile) & man$profile == prof)
    r <- man[man$cohort == g & man$stage == stage & prof_match &
             man$sample_definition == LM_SAMPLE & man$design_hash == LM_DESIGN_HASH, ]
    if (nrow(r) == 0) return(list(ok = FALSE, reason = paste("no manifest row", bn)))
    if (nrow(r) > 1)  return(list(ok = FALSE, reason = paste("duplicate manifest rows", bn)))
    if (tolower(r$status) != "complete" || !isTRUE(as.logical(r$key_ok)))
      return(list(ok = FALSE, reason = paste("manifest not complete/key_ok", bn)))
    hh <- tryCatch(dbGetQuery(con, sprintf("SELECT DISTINCT design_hash FROM read_parquet('%s')",
                              sql_path(path)))$design_hash, error = function(x) NA_character_)
    if (length(hh) >= 1 && !all(is.na(hh)) && !all(hh == LM_DESIGN_HASH))
      return(list(ok = FALSE, reason = paste("parquet design_hash mismatch", bn)))
    if (as.numeric(r$n_rows) > 0) {                       # non-empty: re-check keys/rows/weights
      kc <- keycols[[stage]]
      nr <- dbGetQuery(con, sprintf("SELECT COUNT(*) n FROM read_parquet('%s')", sql_path(path)))$n
      nu <- dbGetQuery(con, sprintf("SELECT COUNT(*) n FROM (SELECT DISTINCT %s FROM read_parquet('%s'))",
                                    paste(kc, collapse = ","), sql_path(path)))$n
      if (nr != as.numeric(r$n_rows)) return(list(ok = FALSE, reason = paste("row-count drift", bn)))
      if (nr != nu)                   return(list(ok = FALSE, reason = paste("duplicate keys", bn)))
      if (stage == "inv") {
        ws <- dbGetQuery(con, sprintf("SELECT MAX(ABS(w-1)) m FROM (SELECT treated_codinv, SUM(weight) w FROM read_parquet('%s') GROUP BY treated_codinv)",
                                      sql_path(path)))$m
        if (!is.finite(ws) || ws > 1e-9) return(list(ok = FALSE, reason = paste("weight sums != 1", bn)))
      }
    }
  }
  list(ok = TRUE, reason = "all shards valid")
}
