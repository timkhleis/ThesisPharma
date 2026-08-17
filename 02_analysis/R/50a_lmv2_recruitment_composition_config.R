# Frozen configuration for the local-match-v2 recruitment-composition audit.

LMV2_RECRUIT_VERSION <- "lmv2_recruitment_composition_v1"

LMV2_RECRUIT <- list(
  cohorts = 1994:2010,
  event_times = -5:5,
  reference_event = -1L,
  post_events = 1:5,
  entry_levels = c("pre_g5", "m5", "m4", "m3", "m2", "m1", "unresolved"),
  end_levels = c("pre_g5", "m5", "m4", "m3", "m2", "m1", "unresolved"),
  length_levels = c("1", "2", "3_5", "6_plus", "unresolved"),
  primary_entry_level = "m3",
  materiality_patents = 0.010,
  p5a_tminus3_level_benchmark = 0.0414,
  approximate_smd = 0.05,
  minimum_ess_ratio = 0.50,
  maximum_ess_ratio_loss = 0.10,
  maximum_parent_share_multiplier = 1.25,
  bootstrap_repetitions = 9999L,
  bootstrap_seed = 20260808L,
  source_start_year = 1988L
)

LMV2_RECRUIT_PATHS <- list(
  database = file.path("02_analysis", "output", "thesis_foundation.duckdb"),
  p5a_roster = file.path(
    ".worktrees", "lmv2-p4-ebal", "02_analysis", "output", "audit",
    "local_match_v2", "P5_P6_HANDOFF", "p5_p6_primary_weighted_roster.parquet"),
  loyo_m3_roster = file.path(
    ".worktrees", "lmv2-p4-ebal", "02_analysis", "output", "audit",
    "local_match_v2", "P5C_P6_HANDOFF_V2_LOYO_M3",
    "p5c_p6_primary_weighted_roster.parquet"),
  count_active_roster = file.path(
    ".worktrees", "lmv2-p4-ebal", "02_analysis", "output", "audit",
    "local_match_v2", "P5C_P6_HANDOFF_V2_COUNT_ACTIVE",
    "p5c_p6_primary_weighted_roster.parquet"),
  p5a_panels = file.path(
    ".worktrees", "lmv2-p6-outcomes", "02_analysis", "output", "audit",
    "local_match_v2", "P6_V3_PRODUCTION", "panel_matched"),
  loyo_m3_panels = file.path(
    ".worktrees", "lmv2-p6-outcomes", "02_analysis", "output", "audit",
    "local_match_v2", "P6_P5C_PANEL_LOYO_M3"),
  count_active_panels = file.path(
    ".worktrees", "lmv2-p6-outcomes", "02_analysis", "output", "audit",
    "local_match_v2", "P6_P5C_PANEL_COUNT_ACTIVE"),
  output = file.path(
    "02_analysis", "output", "audit", "local_match_v2",
    "P9_RECRUITMENT_COMPOSITION")
)

LMV2_RECRUIT_HASHES <- c(
  p5a_roster = "458036894BE7AE16648AB41DE7D6A4E6F3FD489D11373F9E6A18E7686D268AB0",
  loyo_m3_roster = "7F8F3EF1728CA5638843B0EE395E105C06A48ABFFE7D231C0F91E32B1B933356",
  count_active_roster = "3184AEE524BB2DAC5A42D83FD86F1B7A80D8D24566787C5A95536DDC2DA71315",
  database = "F2C4238B37C78B52DA8591F882EB08A091DCC2099A57B160A4EC1E5566134053"
)
