# ============================================================================
# 16c_lmv2_matching_utils.R -- pure matching and IPC utilities for P3
# ============================================================================

lmv2_ipc_feature <- function(ipc_code, resolution) {
  resolution <- match.arg(resolution, c("ipc4", "ipc_main_group", "ipc7"))
  raw <- toupper(gsub("\\s+", "", as.character(ipc_code)))
  raw[is.na(ipc_code) | nchar(raw) < 4L] <- NA_character_
  subclass <- substr(raw, 1L, 4L)
  rest <- ifelse(nchar(raw) > 4L, substr(raw, 5L, nchar(raw)), "")
  slash <- regexpr("/", rest, fixed = TRUE)
  main_raw <- ifelse(slash > 0L, substr(rest, 1L, slash - 1L), rest)
  sub_raw <- ifelse(slash > 0L, substr(rest, slash + 1L, nchar(rest)), "")
  strip_zero <- function(x) {
    y <- sub("^0+", "", x)
    y[y == "" & x != ""] <- "0"
    y
  }
  main <- strip_zero(main_raw)
  # Main groups are stored zero-padded (031 -> 31).  Subgroup digits retain
  # their canonical representation (/00 remains /00 rather than /0).
  subgroup <- sub_raw
  main_key <- ifelse(main == "", subclass, paste0(subclass, main))
  full_key <- ifelse(
    slash > 0L,
    paste0(main_key, "/", subgroup),
    main_key
  )
  out <- switch(
    resolution,
    ipc4 = subclass,
    ipc_main_group = main_key,
    ipc7 = full_key
  )
  out[is.na(raw)] <- NA_character_
  out
}

lmv2_safe_sd <- function(x, epsilon = LMV2_P3_DISTANCE_EPSILON) {
  value <- stats::sd(x[is.finite(x)])
  degenerate <- !is.finite(value) || value < epsilon
  list(sd = if (degenerate) NA_real_ else value, degenerate = degenerate)
}

lmv2_scale_gap <- function(gap, scale) {
  if (!is.finite(scale) || scale < LMV2_P3_DISTANCE_EPSILON) return(rep(0, length(gap)))
  gap / scale
}

lmv2_apply_total_caliper <- function(distance, caliper) {
  is.finite(distance) & (is.infinite(caliper) | distance <= caliper)
}

lmv2_select_stage1 <- function(edges, caliper, n_controls = 5L,
                               required_resolution = "ipc4") {
  required <- c("cohort", "deal_id", "control_group", "distance")
  if (!all(required %in% names(edges))) stop("Stage-1 edge schema invalid")
  units <- unique(edges[c("cohort", "deal_id")])
  if ("resolution" %in% names(edges)) {
    edges <- edges[edges$resolution == required_resolution, , drop = FALSE]
  }
  keep <- lmv2_apply_total_caliper(edges$distance, caliper)
  x <- edges[keep, , drop = FALSE]
  x <- x[order(x$cohort, x$deal_id, x$distance, x$control_group), , drop = FALSE]
  key <- interaction(x$cohort, x$deal_id, drop = TRUE, lex.order = TRUE)
  rank <- ave(seq_len(nrow(x)), key, FUN = seq_along)
  out <- x[rank <= n_controls, , drop = FALSE]
  out$rank <- rank[rank <= n_controls]
  counts <- table(interaction(out$cohort, out$deal_id, drop = TRUE, lex.order = TRUE))
  good <- names(counts[counts == n_controls])
  out <- out[interaction(out$cohort, out$deal_id, drop = TRUE, lex.order = TRUE) %in% good, , drop = FALSE]
  supported <- unique(out[c("cohort", "deal_id")])
  supported$.supported <- rep(TRUE, nrow(supported))
  unsupported <- merge(units, supported, by = c("cohort", "deal_id"),
                       all.x = TRUE, sort = FALSE)
  unsupported <- unsupported[is.na(unsupported$.supported), c("cohort", "deal_id"),
                             drop = FALSE]
  if (nrow(unsupported)) unsupported$reason <- "fewer_than_five_within_total_distance_caliper"
  attr(out, "unsupported") <- unsupported
  out
}

lmv2_select_stage2 <- function(edges, caliper, n_controls = 3L,
                               minimum_firms = 2L, weight = 1 / 3) {
  required <- c("cohort", "deal_id", "treated_codinv", "control_codinv",
                "control_group", "distance")
  if (!all(required %in% names(edges))) stop("Stage-2 edge schema invalid")
  unit_cols <- c("cohort", "deal_id", "treated_codinv")
  units <- unique(edges[unit_cols])
  x <- edges[lmv2_apply_total_caliper(edges$distance, caliper), , drop = FALSE]
  x <- x[order(x$cohort, x$deal_id, x$treated_codinv, x$distance,
               x$control_codinv, x$control_group), , drop = FALSE]
  key <- function(z) paste(z$cohort, z$deal_id, z$treated_codinv, sep = "\r")
  groups <- split(seq_len(nrow(x)), key(x))
  unit_keys <- key(units)
  unsupported_rows <- list()
  selected <- vector("list", nrow(units))
  for (i in seq_len(nrow(units))) {
    idx <- groups[[unit_keys[i]]]
    if (is.null(idx)) {
      unsupported_rows[[length(unsupported_rows) + 1L]] <- data.frame(
        units[i, unit_cols, drop = FALSE],
        reason = "no_candidates_within_total_distance_caliper"
      )
      next
    }
    z <- x[idx, , drop = FALSE]
    z <- z[!duplicated(z$control_codinv), , drop = FALSE]
    if (nrow(z) < n_controls) {
      unsupported_rows[[length(unsupported_rows) + 1L]] <- data.frame(
        z[1L, unit_cols, drop = FALSE], reason = "fewer_than_three_within_total_distance_caliper"
      )
      next
    }
    if (length(unique(z$control_group)) < minimum_firms) {
      unsupported_rows[[length(unsupported_rows) + 1L]] <- data.frame(
        z[1L, unit_cols, drop = FALSE], reason = "no_second_eligible_control_firm"
      )
      next
    }
    take <- seq_len(n_controls)
    if (length(unique(z$control_group[take])) < minimum_firms) {
      alternative <- which(z$control_group != z$control_group[1L])[1L]
      if (is.na(alternative)) stop("Internal Stage-2 diversification inconsistency")
      take[n_controls] <- alternative
      take <- take[order(z$distance[take], z$control_codinv[take], z$control_group[take])]
    }
    ans <- z[take, , drop = FALSE]
    ans$rank <- seq_len(n_controls)
    ans$weight <- weight
    selected[[i]] <- ans
  }
  selected <- Filter(Negate(is.null), selected)
  if (!length(selected)) {
    out <- x[FALSE, , drop = FALSE]
    out$rank <- integer(0)
    out$weight <- numeric(0)
    unsupported <- do.call(rbind, unsupported_rows)
    attr(out, "unsupported") <- unsupported
    return(out)
  }
  out <- do.call(rbind, selected)
  recorded <- if (length(unsupported_rows)) do.call(rbind, unsupported_rows) else
    data.frame(cohort=integer(),deal_id=integer(),treated_codinv=numeric(),reason=character())
  attr(out, "unsupported") <- recorded
  out
}

lmv2_control_reuse_counts <- function(matches) {
  required <- c("cohort", "control_codinv", "control_group")
  if (!all(required %in% names(matches))) stop("Reuse interface lacks control identifiers")
  if (!nrow(matches)) return(data.frame(
    cohort = integer(), control_codinv = numeric(), control_group = numeric(), reuse_count = integer()
  ))
  out <- stats::aggregate(
    rep.int(1L, nrow(matches)), matches[required], sum
  )
  names(out)[ncol(out)] <- "reuse_count"
  out[order(out$cohort, -out$reuse_count, out$control_codinv), ]
}

# Build a long normalized inventor vector table for an explicitly supplied
# roster.  The roster is intentionally narrow: P4/P5 pass only inventors from
# the already frozen Stage-1 firms, never the full 3.9m control-cohort universe.
lmv2_build_inventor_vectors <- function(con, roster, resolution) {
  resolution <- match.arg(resolution, LMV2_P3$technology$resolutions)
  keys <- c("cohort", "codinv")
  if (!all(keys %in% names(roster))) stop("Roster requires cohort and codinv")
  roster <- unique(roster[keys])
  roster$cohort <- as.integer(roster$cohort)
  roster$codinv <- as.numeric(roster$codinv)
  duckdb::duckdb_register(con, "lmv2_p3_runtime_roster", roster)
  on.exit(try(duckdb::duckdb_unregister(con, "lmv2_p3_runtime_roster"), silent = TRUE), add = TRUE)
  DBI::dbGetQuery(con, sprintf("
    WITH weighted AS (
      SELECT CAST(r.cohort AS INTEGER) AS cohort,
             CAST(r.codinv AS BIGINT) AS codinv,
             m.ipc_feature,
             SUM(i.patent_count)::DOUBLE AS weight
      FROM lmv2_p3_runtime_roster r
      JOIN inventor_ipc_year i ON CAST(i.codinv AS BIGINT)=CAST(r.codinv AS BIGINT)
       AND i.year BETWEEN r.cohort-5 AND r.cohort-1
      JOIN lmv2_p3_ipc_code_map m ON m.ipc_code=i.ipc_code
       AND m.resolution=%s
      GROUP BY r.cohort,r.codinv,m.ipc_feature
    )
    SELECT cohort,codinv,ipc_feature,
           weight/SUM(weight) OVER (PARTITION BY cohort,codinv) AS frequency
    FROM weighted",
    DBI::dbQuoteString(con, resolution)))
}

# Stage 2 calls this only after Stage 1 freezes its five-firm pools.  Computing
# focal tenure/exclusivity for the full 3.9m eligible control-cohort rows would
# be wasteful and would couple the stages that the design deliberately separates.
lmv2_build_control_focal_covariates <- function(con, roster) {
  keys <- c("cohort", "codinv", "focal_group")
  if (!all(keys %in% names(roster))) stop("Control roster requires cohort, codinv, focal_group")
  x <- unique(roster[keys])
  x$cohort <- as.integer(x$cohort)
  x$codinv <- as.numeric(x$codinv)
  x$focal_group <- as.numeric(x$focal_group)
  duckdb::duckdb_register(con, "lmv2_p3_runtime_control_roster", x)
  on.exit(try(duckdb::duckdb_unregister(con, "lmv2_p3_runtime_control_roster"), silent = TRUE), add = TRUE)
  DBI::dbGetQuery(con, "
    WITH focal AS (
      SELECT CAST(r.cohort AS INTEGER) cohort,CAST(r.codinv AS BIGINT) codinv,
             CAST(r.focal_group AS BIGINT) focal_group,
             MIN(pcl.year) AS focal_first_year,
             COUNT(DISTINCT CASE WHEN pcl.year BETWEEN r.cohort-5 AND r.cohort-1
                                 THEN pi.appln_id END) AS focal_patent_count_5y
      FROM lmv2_p3_runtime_control_roster r
      JOIN patent_inventor pi ON CAST(pi.codinv AS BIGINT)=CAST(r.codinv AS BIGINT)
      JOIN patent_company_link pcl ON pcl.appln_id=pi.appln_id
       AND CAST(pcl.id_group AS BIGINT)=CAST(r.focal_group AS BIGINT)
       AND pcl.year<=r.cohort-1
      GROUP BY r.cohort,r.codinv,r.focal_group
    )
    SELECT CAST(r.cohort AS INTEGER) cohort,CAST(r.codinv AS BIGINT) codinv,
           CAST(r.focal_group AS BIGINT) focal_group,
           r.cohort-f.focal_first_year AS focal_group_tenure,
           f.focal_patent_count_5y::DOUBLE/NULLIF(g.patent_count_5y,0)
             AS focal_group_exclusivity
    FROM lmv2_p3_runtime_control_roster r
    LEFT JOIN focal f ON f.cohort=r.cohort AND f.codinv=r.codinv
                     AND f.focal_group=r.focal_group
    LEFT JOIN lmv2_p3_inventor_general_units g
      ON g.cohort=r.cohort AND g.codinv=r.codinv AND g.focal_group=r.focal_group
     AND g.role='control'
    ORDER BY cohort,codinv,focal_group
  ")
}

# Expose a technology-similarity matrix for an explicit set of admissible
# inventor pairs.  This makes IPC4, main-group, and full-subgroup resolutions
# interchangeable through one interface without materializing global pairs.
lmv2_inventor_similarity_matrix <- function(con, pair_map, resolution) {
  resolution <- match.arg(resolution, LMV2_P3$technology$resolutions)
  similarity <- lmv2_stage2_technology_cache(con, pair_map)$similarity
  similarity <- similarity[similarity$resolution == resolution, , drop = FALSE]
  similarity$resolution <- NULL
  similarity
}

lmv2_shared_ipc4_matrix <- function(con, pair_map) {
  keys <- c("cohort", "treated_codinv", "control_codinv")
  pairs <- unique(pair_map[keys])
  duckdb::duckdb_register(con, "lmv2_p3_runtime_ipc4_pairs", pairs)
  on.exit(try(duckdb::duckdb_unregister(con, "lmv2_p3_runtime_ipc4_pairs"), silent = TRUE), add = TRUE)
  DBI::dbGetQuery(con, "
    WITH treated_features AS (
      SELECT DISTINCT p.cohort,p.treated_codinv,m.ipc_feature
      FROM lmv2_p3_runtime_ipc4_pairs p
      JOIN inventor_ipc_year i ON CAST(i.codinv AS BIGINT)=p.treated_codinv
       AND i.year BETWEEN p.cohort-5 AND p.cohort-1
      JOIN lmv2_p3_ipc_code_map m ON m.ipc_code=i.ipc_code AND m.resolution='ipc4'
    ), control_features AS (
      SELECT DISTINCT p.cohort,p.control_codinv,m.ipc_feature
      FROM lmv2_p3_runtime_ipc4_pairs p
      JOIN inventor_ipc_year i ON CAST(i.codinv AS BIGINT)=p.control_codinv
       AND i.year BETWEEN p.cohort-5 AND p.cohort-1
      JOIN lmv2_p3_ipc_code_map m ON m.ipc_code=i.ipc_code AND m.resolution='ipc4'
    ), shared AS (
      SELECT DISTINCT p.cohort,p.treated_codinv,p.control_codinv
      FROM lmv2_p3_runtime_ipc4_pairs p
      JOIN treated_features t USING(cohort,treated_codinv)
      JOIN control_features c USING(cohort,control_codinv,ipc_feature)
    )
    SELECT p.cohort,p.treated_codinv,p.control_codinv,
           (s.treated_codinv IS NOT NULL) AS shared_ipc4
    FROM lmv2_p3_runtime_ipc4_pairs p
    LEFT JOIN shared s USING(cohort,treated_codinv,control_codinv)
    ORDER BY cohort,treated_codinv,control_codinv
  ")
}

lmv2_stage2_technology_cache <- function(con, pair_map) {
  keys <- c("cohort", "treated_codinv", "control_codinv")
  if (!all(keys %in% names(pair_map))) stop("Pair map lacks technology-cache identifiers")
  pairs <- unique(pair_map[keys])
  duckdb::duckdb_register(con, "lmv2_p3_runtime_cache_pairs", pairs)
  on.exit(try(duckdb::duckdb_unregister(con, "lmv2_p3_runtime_cache_pairs"), silent = TRUE), add = TRUE)
  similarity <- DBI::dbGetQuery(con, "
    WITH roster AS (
      SELECT cohort,treated_codinv AS codinv FROM lmv2_p3_runtime_cache_pairs
      UNION SELECT cohort,control_codinv AS codinv FROM lmv2_p3_runtime_cache_pairs
    ), weighted AS (
      SELECT r.cohort,CAST(r.codinv AS BIGINT) codinv,m.resolution,m.ipc_feature,
             SUM(i.patent_count)::DOUBLE weight
      FROM roster r
      JOIN inventor_ipc_year i ON CAST(i.codinv AS BIGINT)=r.codinv
       AND i.year BETWEEN r.cohort-5 AND r.cohort-1
      JOIN lmv2_p3_ipc_code_map m USING(ipc_code)
      GROUP BY r.cohort,r.codinv,m.resolution,m.ipc_feature
    ), vectors AS (
      SELECT *,weight/SUM(weight) OVER(PARTITION BY cohort,codinv,resolution) frequency
      FROM weighted
    ), norms AS (
      SELECT cohort,codinv,resolution,SQRT(SUM(frequency*frequency)) norm
      FROM vectors GROUP BY cohort,codinv,resolution
    ), dots AS (
      SELECT p.cohort,p.treated_codinv,p.control_codinv,t.resolution,
             SUM(t.frequency*c.frequency) dot
      FROM lmv2_p3_runtime_cache_pairs p
      JOIN vectors t ON t.cohort=p.cohort AND t.codinv=p.treated_codinv
      JOIN vectors c ON c.cohort=p.cohort AND c.codinv=p.control_codinv
                    AND c.resolution=t.resolution AND c.ipc_feature=t.ipc_feature
      GROUP BY p.cohort,p.treated_codinv,p.control_codinv,t.resolution
    ), matrix AS (
      SELECT p.*,r.resolution
      FROM lmv2_p3_runtime_cache_pairs p
      CROSS JOIN (SELECT DISTINCT resolution FROM lmv2_p3_ipc_code_map) r
    )
    SELECT m.cohort,m.treated_codinv,m.control_codinv,m.resolution,
           CASE WHEN tn.norm>0 AND cn.norm>0
                THEN LEAST(1.0,GREATEST(0.0,COALESCE(d.dot,0)/(tn.norm*cn.norm)))
                ELSE NULL END cosine
    FROM matrix m
    LEFT JOIN dots d USING(cohort,treated_codinv,control_codinv,resolution)
    LEFT JOIN norms tn ON tn.cohort=m.cohort AND tn.codinv=m.treated_codinv
                      AND tn.resolution=m.resolution
    LEFT JOIN norms cn ON cn.cohort=m.cohort AND cn.codinv=m.control_codinv
                      AND cn.resolution=m.resolution
    ORDER BY cohort,treated_codinv,control_codinv,resolution
  ")
  list(similarity = similarity, shared_ipc4 = lmv2_shared_ipc4_matrix(con, pairs))
}

lmv2_inventor_ipc_diagnostics <- function(pair_map, similarity) {
  needed <- c("cohort", "treated_codinv", "control_codinv", "control_group")
  if (!all(needed %in% names(pair_map))) stop("Diagnostic pair map lacks control groups")
  x <- merge(similarity, unique(pair_map[needed]),
             by = c("cohort", "treated_codinv", "control_codinv"), sort = FALSE)
  if (!nrow(x)) return(list(
    unit = data.frame(), cohort = data.frame()
  ))
  split_key <- interaction(x[c("cohort", "treated_codinv", "resolution")],
                           drop = TRUE, lex.order = TRUE)
  unit <- do.call(rbind, lapply(split(seq_len(nrow(x)), split_key), function(idx) {
    z <- x[idx, , drop = FALSE]
    finite <- z[is.finite(z$cosine), , drop = FALSE]
    positive <- finite[finite$cosine > 0, , drop = FALSE]
    distinct_positive <- length(unique(round(positive$cosine, 12)))
    max_cos <- if (any(is.finite(z$cosine))) max(z$cosine, na.rm = TRUE) else NA_real_
    data.frame(
      cohort=z$cohort[1],treated_codinv=z$treated_codinv[1],resolution=z$resolution[1],
      candidate_count=nrow(z),positive_control_count=nrow(positive),
      positive_control_firms=length(unique(positive$control_group)),
      zero_cosine_share=if (nrow(finite)) mean(finite$cosine==0) else NA_real_,
      distinct_positive_values=distinct_positive,
      nearest_tied=if (is.finite(max_cos)) sum(abs(z$cosine-max_cos)<1e-12,na.rm=TRUE)>1 else NA,
      feasible_three_controls_two_firms=nrow(positive)>=3 && length(unique(positive$control_group))>=2
    )
  }))
  cohort_key <- interaction(unit[c("cohort", "resolution")], drop=TRUE, lex.order=TRUE)
  cohort <- do.call(rbind, lapply(split(seq_len(nrow(unit)), cohort_key), function(idx) {
    z <- unit[idx, , drop=FALSE]
    data.frame(
      cohort=z$cohort[1],resolution=z$resolution[1],
      median_candidate_count=stats::median(z$candidate_count,na.rm=TRUE),
      median_positive_control_count=stats::median(z$positive_control_count,na.rm=TRUE),
      median_zero_cosine_share=stats::median(z$zero_cosine_share,na.rm=TRUE),
      median_distinct_positive_values=stats::median(z$distinct_positive_values,na.rm=TRUE),
      share_nearest_tied=mean(z$nearest_tied,na.rm=TRUE),
      share_feasible_three_controls_two_firms=mean(z$feasible_three_controls_two_firms,na.rm=TRUE)
    )
  }))
  list(unit = unit, cohort = cohort)
}

lmv2_prepare_stage2_edges <- function(treated, controls, pair_map, similarity,
                                      shared_ipc4, resolution) {
  resolution <- match.arg(resolution, LMV2_P3$technology$resolutions)
  vars <- LMV2_P3$stage_2$scalar_variables
  t_required <- c("cohort", "deal_id", "codinv", "recency_bin", vars)
  c_required <- c("cohort", "codinv", "focal_group", "recency_bin", vars)
  p_required <- c("cohort", "deal_id", "treated_codinv", "control_codinv")
  if (!all(t_required %in% names(treated))) stop("Treated Stage-2 schema invalid")
  if (!all(c_required %in% names(controls))) stop("Control Stage-2 schema invalid")
  if (!all(p_required %in% names(pair_map))) stop("Stage-2 pair schema invalid")

  treated_scale_units <- unique(treated[c("cohort", "deal_id", "codinv", vars)])
  control_scale_units <- unique(controls[c("cohort", "codinv", "focal_group", vars)])
  t <- treated[t_required]
  names(t)[names(t) == "codinv"] <- "treated_codinv"
  names(t)[names(t) %in% vars] <- paste0(names(t)[names(t) %in% vars], "_treated")
  names(t)[names(t) == "recency_bin"] <- "recency_bin_treated"
  c <- controls[c_required]
  names(c)[names(c) == "codinv"] <- "control_codinv"
  names(c)[names(c) == "focal_group"] <- "control_group"
  names(c)[names(c) %in% vars] <- paste0(names(c)[names(c) %in% vars], "_control")
  names(c)[names(c) == "recency_bin"] <- "recency_bin_control"

  if ("resolution" %in% names(similarity)) {
    similarity <- similarity[similarity$resolution == resolution, , drop = FALSE]
    similarity$resolution <- NULL
  }
  sim_key <- c("cohort", "treated_codinv", "control_codinv")
  if (anyDuplicated(similarity[sim_key])) stop("Stage-2 similarity matrix is not pair-unique")
  e <- merge(pair_map, t, by = c("cohort", "deal_id", "treated_codinv"), sort = FALSE)
  e <- merge(e, c, by = c("cohort", "control_codinv"), sort = FALSE)
  e <- merge(e, similarity, by = c("cohort", "treated_codinv", "control_codinv"), sort = FALSE)
  e <- merge(e, shared_ipc4, by = c("cohort", "treated_codinv", "control_codinv"), sort = FALSE)
  e <- e[!is.na(e$shared_ipc4) & e$shared_ipc4, , drop = FALSE]
  e <- e[!is.na(e$recency_bin_treated) & !is.na(e$recency_bin_control) &
           abs(e$recency_bin_treated - e$recency_bin_control) <=
             LMV2_P3$stage_2$maximum_recency_bin_gap, , drop = FALSE]
  e$tech_distance <- 1 - e$cosine

  scaler_rows <- list()
  scaler_cohorts <- sort(intersect(unique(treated$cohort), unique(controls$cohort)))
  for (g in scaler_cohorts) {
    eg <- e[e$cohort == g, , drop = FALSE]
    for (v in vars) {
      values <- c(
        treated_scale_units[[v]][treated_scale_units$cohort == g],
        control_scale_units[[v]][control_scale_units$cohort == g]
      )
      s <- lmv2_safe_sd(values)
      scaler_rows[[length(scaler_rows) + 1L]] <- data.frame(
        cohort = g, component = v, component_sd = s$sd,
        degenerate = s$degenerate, stringsAsFactors = FALSE
      )
    }
    s <- lmv2_safe_sd(eg$tech_distance)
    scaler_rows[[length(scaler_rows) + 1L]] <- data.frame(
      cohort = g, component = "tech_distance", component_sd = s$sd,
      degenerate = s$degenerate, stringsAsFactors = FALSE
    )
  }
  scalers <- if (length(scaler_rows)) do.call(rbind, scaler_rows) else
    data.frame(cohort = integer(), component = character(), component_sd = numeric(), degenerate = logical())

  e$distance <- NA_real_
  for (v in vars) e[[paste0("gap_", v)]] <- NA_real_
  for (g in unique(e$cohort)) {
    idx <- which(e$cohort == g)
    sg <- scalers[scalers$cohort == g, ]
    squares <- rep(0, length(idx))
    for (v in vars) {
      gap <- e[[paste0(v, "_control")]][idx] - e[[paste0(v, "_treated")]][idx]
      scale <- sg$component_sd[sg$component == v]
      squares <- squares + lmv2_scale_gap(gap, scale)^2
      e[[paste0("gap_", v)]][idx] <- gap
    }
    tech_sd <- sg$component_sd[sg$component == "tech_distance"]
    squares <- squares + lmv2_scale_gap(e$tech_distance[idx], tech_sd)^2
    e$distance[idx] <- sqrt(squares)
  }
  eligibility <- unique(treated[c("cohort", "deal_id", "codinv")])
  names(eligibility)[names(eligibility) == "codinv"] <- "treated_codinv"
  if (nrow(e)) {
    candidate_counts <- stats::aggregate(
      e$control_codinv,
      e[c("cohort", "deal_id", "treated_codinv")],
      function(x) length(unique(x))
    )
    names(candidate_counts)[ncol(candidate_counts)] <- "eligible_control_inventors"
    firm_counts <- stats::aggregate(
      e$control_group,
      e[c("cohort", "deal_id", "treated_codinv")],
      function(x) length(unique(x))
    )
    names(firm_counts)[ncol(firm_counts)] <- "eligible_control_firms"
    eligibility <- merge(eligibility, candidate_counts, all.x = TRUE, sort = FALSE)
    eligibility <- merge(eligibility, firm_counts, all.x = TRUE, sort = FALSE)
  } else {
    eligibility$eligible_control_inventors <- 0L
    eligibility$eligible_control_firms <- 0L
  }
  eligibility$eligible_control_inventors[is.na(eligibility$eligible_control_inventors)] <- 0L
  eligibility$eligible_control_firms[is.na(eligibility$eligible_control_firms)] <- 0L
  eligibility$support_reason <- ifelse(
    eligibility$eligible_control_inventors < 3L, "fewer_than_three_after_ipc4_and_recency",
    ifelse(eligibility$eligible_control_firms < 2L, "no_second_firm_after_ipc4_and_recency", "eligible")
  )
  list(edges = e, scalers = scalers, eligibility = eligibility)
}
