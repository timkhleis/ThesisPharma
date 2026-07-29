# Tooth-test the explicit P6 wild-bootstrap confidence-interval fallback.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

set.seed(20260727)
fixture <- data.frame(
  y = stats::rnorm(400),
  treated = rep(0:1, each = 200)
)
mod <- stats::lm(y ~ treated, data = fixture)
boot <- list(
  point_estimate = unname(stats::coef(mod)[["treated"]]),
  t_boot = stats::rnorm(9999)
)
class(boot) <- "lmv2_missing_ci_fixture"

fallback <- lmv2_extract_wild_ci(boot, mod)
fallback_pass <-
  identical(fallback$ci_method, "bootstrap_t_quantile_fallback") &&
  all(is.finite(c(fallback$ci_low, fallback$ci_high))) &&
  fallback$ci_low < fallback$ci_high

boot$t_boot <- NA_real_
invalid_rejected <- inherits(
  try(lmv2_extract_wild_ci(boot, mod), silent = TRUE),
  "try-error"
)

checks <- data.frame(
  check = c(
    "missing_inversion_uses_labeled_finite_percentile_t",
    "invalid_fallback_inputs_are_rejected"
  ),
  pass = c(fallback_pass, invalid_rejected),
  stringsAsFactors = FALSE
)
out <- file.path(
  BASE, "output", "audit", "local_match_v2",
  "P6_P5C_WILD_CI_FALLBACK_TOOTH_TESTS.csv"
)
utils::write.csv(checks, out, row.names = FALSE)
if (!all(checks$pass)) {
  stop("P6 wild-bootstrap CI fallback tooth test failed")
}
message("P6 wild-bootstrap CI fallback tooth tests passed")
