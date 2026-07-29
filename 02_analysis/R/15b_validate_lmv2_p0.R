# ============================================================================
# 15b_validate_lmv2_p0.R -- validate prospective lock and inference fixture
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()

required <- c("digest", "fixest", "fwildclusterboot", "dqrng")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Missing P0 dependencies: ", paste(missing, collapse = ", "))

read_lock <- function() {
  e <- new.env(parent = baseenv())
  sys.source(file.path(BASE, "R", "15a_lmv2_design_lock.R"), envir = e)
  list(
    version = e$LMV2_DESIGN_VERSION,
    lock = e$LMV2_LOCK,
    hash = e$LMV2_DESIGN_HASH,
    frozen = e$LMV2_LOCK_FROZEN
  )
}

a <- read_lock()
b <- read_lock()
stopifnot(isTRUE(a$frozen), identical(a$hash, b$hash), identical(a$lock, b$lock))
stopifnot(as.character(utils::packageVersion("fwildclusterboot")) == a$lock$inference$package_version)

# Fixed small-sample fixture: the same Webb-weight, null-imposed call used for
# headline inference must return identical p-values and confidence intervals
# after resetting the locked dqrng seed.
set.seed(1904)
n_deals <- 18L
n_per_deal <- 10L
fixture <- data.frame(
  deal = rep(seq_len(n_deals), each = n_per_deal),
  year = rep(rep(1:5, length.out = n_per_deal), n_deals)
)
fixture$x <- rnorm(nrow(fixture))
fixture$treated <- as.integer(fixture$year >= 3 & fixture$deal <= 8)
deal_shock <- rep(rnorm(n_deals), each = n_per_deal)
fixture$y <- 0.25 * fixture$treated + 0.20 * fixture$x + deal_shock + rnorm(nrow(fixture))

fit <- fixest::feols(y ~ treated + x | year, data = fixture)
run_fixture <- function() {
  set.seed(a$lock$inference$seed)
  dqrng::dqset.seed(a$lock$inference$seed)
  out <- fwildclusterboot::boottest(
    fit,
    param = "treated",
    B = a$lock$inference$replications,
    clustid = ~deal,
    type = a$lock$inference$weights,
    impose_null = a$lock$inference$impose_null,
    conf_int = TRUE,
    engine = "R"
  )
  c(
    p_value = as.numeric(fwildclusterboot::pval(out)),
    ci_low = as.numeric(stats::confint(out)[1]),
    ci_high = as.numeric(stats::confint(out)[2])
  )
}

fixture_1 <- run_fixture()
fixture_2 <- run_fixture()
stopifnot(all(is.finite(fixture_1)), identical(fixture_1, fixture_2))

audit_dir <- file.path(BASE, "output", "audit", "local_match_v2", "p0")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
write.csv(
  data.frame(
    design_version = a$version,
    design_hash = a$hash,
    lock_frozen = a$frozen,
    fwildclusterboot_version = as.character(utils::packageVersion("fwildclusterboot")),
    webb_replications = a$lock$inference$replications,
    impose_null = a$lock$inference$impose_null,
    fixture_p_value = fixture_1[["p_value"]],
    fixture_ci_low = fixture_1[["ci_low"]],
    fixture_ci_high = fixture_1[["ci_high"]],
    fixture_reproducible = identical(fixture_1, fixture_2),
    stringsAsFactors = FALSE
  ),
  file.path(audit_dir, "p0_lock_validation.csv"),
  row.names = FALSE,
  na = ""
)

message("P0 PASS | design_hash=", a$hash,
        " | fwildclusterboot=", utils::packageVersion("fwildclusterboot"))
