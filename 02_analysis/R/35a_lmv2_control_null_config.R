# ============================================================================
# P6 configuration for the control-only pseudo-treatment validation
# ============================================================================

LMV2_CONTROL_NULL_P6_VERSION <- "lmv2_control_null_p6_v3"

LMV2_CONTROL_NULL_P6 <- list(
  outcome = "patent_count",
  bootstrap_replications = 999L,
  real_supported_treated_inventors = c(
    full_1994_2010 = 27078L,
    buffered_1994_2008 = 22598L),
  volume_comparability_bounds = c(0.90, 1.10),
  real_nominal_treated_deals = c(
    full_1994_2010 = 341L,
    buffered_1994_2008 = 291L),
  real_effective_treated_deals = c(
    full_1994_2010 = 36.936878084609155,
    buffered_1994_2008 = 29.753059031904726),
  real_max_treated_deal_weight_share = c(
    full_1994_2010 = 0.0760395893345151,
    buffered_1994_2008 = 0.0911142578989291),
  nominal_cluster_ratio_bounds = c(0.50, 2.00),
  effective_cluster_ratio_bounds = c(0.50, 2.00),
  minimum_production_draw_id = 1001L,
  roster_mode = "control_null",
  ingredient_schema = "p6",
  execution = list(
    threads = 2L,
    memory_limit = "6GB")
)
