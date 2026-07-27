# ============================================================================
# Package 1D certification: mean-reversion diagnostic package
# ============================================================================

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
if (!requireNamespace("digest", quietly = TRUE)) stop("Missing package: digest")

AUDIT <- file.path(BASE, "output", "audit", "local_match_v2")
OUT_DIR <- file.path(AUDIT, "P6_PACKAGE1D_MEAN_REVERSION")
P6_ROOT <- normalizePath(file.path(BASE, ".."), winslash = "/", mustWork = TRUE)
P4_ROOT <- normalizePath(
  file.path(P6_ROOT, "..", "lmv2-p4-ebal"),
  winslash = "/", mustWork = TRUE)
P4_CERT <- file.path(
  P4_ROOT, "02_analysis", "output", "audit", "local_match_v2",
  "P5C_PACKAGE1D_LOYO_M1", "package1d_loyo_m1_certification.csv")

paths <- c(
  certifier = file.path(
    BASE, "R", "23c_certify_lmv2_package1d_mean_reversion.R"),
  p4_cert = P4_CERT,
  p6_run = file.path(OUT_DIR, "package1d_p6_run_manifest.csv"),
  heldout = file.path(OUT_DIR, "package1d_loyo_m1_heldout.csv"),
  reference_post = file.path(OUT_DIR, "package1d_reference_post_att.csv"),
  reference_dynamic = file.path(OUT_DIR, "package1d_reference_dynamic.csv"),
  paths = file.path(OUT_DIR, "package1d_raw_vs_matched_paths.csv"),
  decomposition = file.path(
    OUT_DIR, "package1d_heldout_source_decomposition.csv"),
  deal_concentration = file.path(
    OUT_DIR, "package1d_heldout_deal_concentration.csv"),
  deal_detail = file.path(
    OUT_DIR, "package1d_heldout_deal_contributions.csv"),
  peaks = file.path(OUT_DIR, "package1d_treated_deal_peak_summary.csv"),
  raw_pretrend = file.path(
    OUT_DIR, "package1d_raw_did_pretrend_snapshot.csv"),
  raw_post = file.path(OUT_DIR, "package1d_raw_did_post_snapshot.csv"),
  source_manifest = file.path(OUT_DIR, "package1d_source_manifest.csv"),
  plot_png = file.path(OUT_DIR, "package1d_raw_vs_matched_paths.png"),
  plot_pdf = file.path(OUT_DIR, "package1d_raw_vs_matched_paths.pdf"))
missing <- paths[!file.exists(paths)]
if (length(missing)) {
  stop("Package 1D certification input missing: ",
       paste(names(missing), collapse = ", "))
}

read_csv <- function(name) {
  utils::read.csv(paths[[name]], stringsAsFactors = FALSE)
}
p4 <- read_csv("p4_cert")
p6 <- read_csv("p6_run")
heldout <- read_csv("heldout")
post <- read_csv("reference_post")
dynamic <- read_csv("reference_dynamic")
path_data <- read_csv("paths")
decomposition <- read_csv("decomposition")
deal_summary <- read_csv("deal_concentration")
deal_detail <- read_csv("deal_detail")
peaks <- read_csv("peaks")
raw_pre <- read_csv("raw_pretrend")
raw_post <- read_csv("raw_post")
source_manifest <- read_csv("source_manifest")

expected_reference <- data.frame(
  design = c("loyo_m4", "loyo_m5", "loyo_m1"),
  reference_event_time = c(-4L, -5L, -4L),
  stringsAsFactors = FALSE)
expected_samples <- c("full_1994_2010", "buffered_1994_2008")
expected_categories <- c(
  "career_entry_heldout", "focal_entry_later",
  "focal_incumbent", "focal_recruit_heldout")

reference_cells_ok <- function(x) {
  cells <- unique(x[c("design", "sample", "reference_event_time")])
  expected <- merge(
    expected_reference,
    data.frame(sample = expected_samples, stringsAsFactors = FALSE))
  nrow(cells) == 6L &&
    all(paste(cells$design, cells$sample, cells$reference_event_time) %in%
        paste(expected$design, expected$sample, expected$reference_event_time))
}
bad_reference_fixture <- post[post$design != "loyo_m1", ]
if (reference_cells_ok(bad_reference_fixture)) {
  stop("Reference-cell certification tooth-test did not reject a missing arm")
}

decomposition_cells_ok <- function(x) {
  cells <- unique(x[c(
    "design", "sample", "held_out_event_time", "category", "arm")])
  nrow(cells) == 32L &&
    identical(sort(unique(cells$category)), sort(expected_categories)) &&
    identical(sort(unique(cells$arm)), c("control", "treated"))
}
bad_decomposition_fixture <- decomposition[
  decomposition$category != "focal_incumbent", ]
if (decomposition_cells_ok(bad_decomposition_fixture)) {
  stop("Decomposition certification tooth-test did not reject a missing class")
}

add <- local({
  rows <- list()
  function(check, observed, expected, pass) {
    rows[[length(rows) + 1L]] <<- data.frame(
      check = check, observed = as.character(observed),
      expected = expected, pass = isTRUE(pass),
      stringsAsFactors = FALSE)
    do.call(rbind, rows)
  }
})
cert <- NULL
record <- function(check, observed, expected, pass) {
  cert <<- add(check, observed, expected, pass)
}

record("p4_loyo_m1_certified", p4$all_pass, "TRUE",
       nrow(p4) == 1L && isTRUE(p4$all_pass))
record("p6_loyo_m1_certified", p6$pass, "TRUE",
       nrow(p6) == 1L && isTRUE(p6$pass))
record("heldout_m1_cells", nrow(heldout), "2",
       nrow(heldout) == 2L &&
         all(heldout$design == "loyo_m1") &&
         all(heldout$reference_event_time == -4L) &&
         all(heldout$event_time == -1L) &&
         all(is.finite(heldout$estimate)) &&
         all(heldout$ci_low <= heldout$estimate &
               heldout$estimate <= heldout$ci_high))
record("reference_post_cells", nrow(post), "18",
       nrow(post) == 18L && reference_cells_ok(post) &&
         identical(
           sort(unique(post$inference)),
           sort(c(
             "deal_cluster_robust", "deal_wild_bootstrap_t",
             "two_way_deal_inventor"))) &&
         all(is.finite(post$estimate)) &&
         all(post$ci_low <= post$estimate & post$estimate <= post$ci_high))
record("wild_bootstrap_replications",
       paste(unique(stats::na.omit(post$bootstrap_replications)), collapse = ","),
       "9999",
       identical(
         unique(stats::na.omit(post$bootstrap_replications)), 9999L))
record("reference_dynamic_cells", nrow(dynamic), "66",
       nrow(dynamic) == 66L && reference_cells_ok(dynamic) &&
         all(is.finite(dynamic$estimate)))
record("raw_matched_path_cells", nrow(path_data), "44",
       nrow(path_data) == 44L &&
         identical(sort(unique(path_data$design)),
                   c("count_active", "raw_unmatched")) &&
         identical(sort(unique(path_data$event_time)), -5:5))
matched_pre <- path_data[
  path_data$design == "count_active" &
    path_data$event_time %in% -5:-1, ]
matched_wide <- reshape(
  matched_pre, idvar = "event_time", timevar = "arm", direction = "wide")
max_pre_gap <- max(abs(
  matched_wide$mean_patent_count.treated -
    matched_wide$mean_patent_count.control))
record("matched_prepath_exact", max_pre_gap, "<=1e-7",
       is.finite(max_pre_gap) && max_pre_gap <= 1e-7)
record("decomposition_cells", nrow(decomposition), "32",
       decomposition_cells_ok(decomposition))

share_check <- aggregate(
  weighted_share ~ design + sample + arm,
  decomposition, sum)
total_check <- aggregate(
  signed_estimate_contribution ~ design + sample,
  decomposition, sum)
deal_total <- deal_summary[c("design", "sample", "total_estimate")]
total_join <- merge(total_check, deal_total, by = c("design", "sample"))
max_share_gap <- max(abs(share_check$weighted_share - 1))
max_total_gap <- max(abs(
  total_join$signed_estimate_contribution - total_join$total_estimate))
record("decomposition_arm_shares", max_share_gap, "<=1e-10",
       max_share_gap <= 1e-10)
record("decomposition_reconstructs_att", max_total_gap, "<=1e-10",
       max_total_gap <= 1e-10)
record("deal_concentration_cells", nrow(deal_summary), "4",
       nrow(deal_summary) == 4L &&
         all(deal_summary$n_deals %in% c(291L, 341L)) &&
         all(deal_summary$top1_absolute_share >= 0 &
               deal_summary$top1_absolute_share <= 1))
record("deal_detail_unique",
       nrow(deal_detail) - nrow(unique(
         deal_detail[c("design", "sample", "deal_id")])),
       "0",
       nrow(deal_detail) == nrow(unique(
         deal_detail[c("design", "sample", "deal_id")])))
record("target_peak_support", paste(peaks$peak_event_time, collapse = ","),
       "-5,-4,-3,-2,-1",
       nrow(peaks) == 5L &&
         identical(peaks$peak_event_time, -5:-1) &&
         sum(peaks$n_deals) == 341L &&
         abs(sum(peaks$share_deals) - 1) <= 1e-10 &&
         sum(peaks$treated_inventors) == 27078L &&
         abs(sum(peaks$share_treated_inventors) - 1) <= 1e-10)
record("raw_did_snapshot", paste(nrow(raw_pre), nrow(raw_post), sep = "/"),
       "at least 2/4 with required specifications",
       nrow(raw_pre) >= 2L && nrow(raw_post) >= 4L &&
         any(raw_pre$specification == "full_cohort_unmatched") &&
         any(raw_pre$specification == "focal_entity_stayer_unmatched") &&
         any(raw_post$specification == "full_cohort_unmatched") &&
         any(raw_post$specification == "focal_entity_stayer_unmatched"))
record("source_manifest_current",
       nrow(source_manifest), "7 current sources",
       nrow(source_manifest) == 7L &&
         all(vapply(seq_len(nrow(source_manifest)), function(i) {
           file.exists(source_manifest$path[[i]]) &&
             identical(
               digest::digest(
                 file = source_manifest$path[[i]], algo = "sha256"),
               source_manifest$sha256[[i]])
         }, logical(1))))
record("figures_nonempty",
       paste(file.info(paths[c("plot_png", "plot_pdf")])$size, collapse = ","),
       "both >1000 bytes",
       all(file.info(paths[c("plot_png", "plot_pdf")])$size > 1000))

if (any(!cert$pass)) {
  utils::write.csv(
    cert, file.path(OUT_DIR, "package1d_certification.csv"),
    row.names = FALSE, na = "")
  stop("Package 1D certification failed: ",
       paste(cert$check[!cert$pass], collapse = ", "))
}
utils::write.csv(
  cert, file.path(OUT_DIR, "package1d_certification.csv"),
  row.names = FALSE, na = "")
bundle_paths <- c(paths, certification = file.path(
  OUT_DIR, "package1d_certification.csv"))
manifest <- data.frame(
  checks = nrow(cert),
  failed = sum(!cert$pass),
  all_pass = all(cert$pass),
  certification_sha256 = digest::digest(
    file = bundle_paths[["certification"]], algo = "sha256"),
  bundle_sha256 = digest::digest(
    vapply(
      bundle_paths, digest::digest, character(1),
      file = TRUE, algo = "sha256"),
    algo = "sha256"),
  certified_at = as.character(Sys.time()),
  stringsAsFactors = FALSE)
utils::write.csv(
  manifest,
  file.path(OUT_DIR, "package1d_certification_manifest.csv"),
  row.names = FALSE, na = "")
print(manifest)
