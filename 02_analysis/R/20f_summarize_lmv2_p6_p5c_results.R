# Consolidate the frozen P5a/P5c P6 estimates without selecting among them.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
if (!requireNamespace("digest", quietly = TRUE)) {
  stop("Missing package: digest")
}

audit <- file.path(BASE, "output", "audit", "local_match_v2")
design_dirs <- c(
  p5a_original = "P6_ESTIMATION_CORE_V2",
  count_active = "P6_P5C_ESTIMATION_COUNT_ACTIVE",
  loyo_m3 = "P6_P5C_ESTIMATION_LOYO_M3",
  loyo_m4 = "P6_P5C_ESTIMATION_LOYO_M4"
)
paths <- file.path(audit, unname(design_dirs))
names(paths) <- names(design_dirs)
required <- c(
  "p6_headline_post_att.csv",
  "p6_event_study_dynamic.csv",
  "p6_estimation_manifest.csv",
  "p6_estimation_certification_manifest.csv"
)
for (design in names(paths)) {
  missing <- required[!file.exists(file.path(paths[[design]], required))]
  if (length(missing)) {
    stop("Missing certified result files for ", design, ": ",
         paste(missing, collapse = ", "))
  }
  cert <- utils::read.csv(
    file.path(paths[[design]], "p6_estimation_certification_manifest.csv"),
    stringsAsFactors = FALSE
  )
  if (nrow(cert) != 1L || cert$n_failed[[1]] != 0) {
    stop("Failed or malformed estimation certification for ", design)
  }
}

read_with_design <- function(file) {
  pieces <- lapply(names(paths), function(design) {
    x <- utils::read.csv(file.path(paths[[design]], file),
                        stringsAsFactors = FALSE)
    x$design <- design
    x
  })
  all_names <- unique(unlist(lapply(pieces, names), use.names = FALSE))
  pieces <- lapply(pieces, function(x) {
    for (name in setdiff(all_names, names(x))) x[[name]] <- NA
    x[, all_names, drop = FALSE]
  })
  do.call(rbind, pieces)
}
headline <- read_with_design("p6_headline_post_att.csv")
dynamic <- read_with_design("p6_event_study_dynamic.csv")

headline_comparison <- headline[
  headline$summary == "average_annual_t1_to_t5" & headline$governing,
]
headline_comparison <- headline_comparison[
  , c("design", "sample", "outcome", "estimate", "ci_low", "ci_high",
      "p_value", "inference", "ci_method", "inference_sensitive")
]

patent_dynamic <- dynamic[
  dynamic$outcome == "patent_count",
  c("design", "sample", "event_time", "estimate", "se", "ci_low", "ci_high",
    "inference")
]

placebo_specs <- data.frame(
  design = c("loyo_m3", "loyo_m4"),
  held_out_event_time = c(-3L, -4L),
  stringsAsFactors = FALSE
)
placebo <- do.call(rbind, lapply(seq_len(nrow(placebo_specs)), function(i) {
  spec <- placebo_specs[i, ]
  x <- patent_dynamic[
    patent_dynamic$design == spec$design &
      patent_dynamic$event_time == spec$held_out_event_time,
  ]
  x$held_out_event_time <- spec$held_out_event_time
  x$ci_includes_zero <- x$ci_low <= 0 & x$ci_high >= 0
  x$abs_estimate_below_005 <- abs(x$estimate) < 0.05
  x$predeclared_pass <-
    x$ci_includes_zero & x$abs_estimate_below_005
  x
}))

main_leads <- patent_dynamic[
  patent_dynamic$design == "count_active" &
    patent_dynamic$event_time %in% -5:-2,
]
main_lead_check <- data.frame(
  sample = unique(main_leads$sample),
  max_abs_balanced_lead = vapply(
    unique(main_leads$sample),
    function(sample) max(abs(main_leads$estimate[
      main_leads$sample == sample
    ])),
    numeric(1)
  ),
  stringsAsFactors = FALSE
)

out_dir <- file.path(audit, "P6_P5C_COMPARISON")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  headline_comparison,
  file.path(out_dir, "p6_p5c_headline_comparison.csv"),
  row.names = FALSE
)
utils::write.csv(
  patent_dynamic,
  file.path(out_dir, "p6_p5c_patent_dynamic_comparison.csv"),
  row.names = FALSE
)
utils::write.csv(
  placebo,
  file.path(out_dir, "p6_p5c_held_out_placebo_assessment.csv"),
  row.names = FALSE
)
utils::write.csv(
  main_lead_check,
  file.path(out_dir, "p6_p5c_balanced_lead_check.csv"),
  row.names = FALSE
)

input_files <- unlist(lapply(paths, function(path) {
  file.path(path, required)
}), use.names = FALSE)
manifest <- data.frame(
  comparison_version = "lmv2_p6_p5c_comparison_v1",
  designs = paste(names(paths), collapse = ";"),
  n_headline_rows = nrow(headline_comparison),
  n_patent_dynamic_rows = nrow(patent_dynamic),
  n_placebo_rows = nrow(placebo),
  n_placebo_pass = sum(placebo$predeclared_pass),
  input_bundle_sha256 = digest::digest(
    vapply(input_files, digest::digest, character(1),
           file = TRUE, algo = "sha256"),
    algo = "sha256", serialize = TRUE
  ),
  completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "p6_p5c_comparison_manifest.csv"),
  row.names = FALSE
)
message(
  "P6 P5c comparison complete: ", nrow(headline_comparison),
  " governing headline rows; ", sum(placebo$predeclared_pass),
  "/", nrow(placebo), " held-out sample checks pass"
)
