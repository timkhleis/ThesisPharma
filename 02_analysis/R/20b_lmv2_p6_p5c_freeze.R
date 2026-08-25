# Frozen P6/P5c provenance checks. Requires digest.

LMV2_P6_P5C_FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_p6_p5c_reweight_freeze.md")
LMV2_P6_P5C_FREEZE_SHA256 <-
  "dc6d121162296456f2f22d9d2b1f6ea10f92b0606d232a64a651f3e5c2be7850"

p4_base <- normalizePath(
  file.path(BASE, "..", "..", "lmv2-p4-ebal"),
  winslash = "/", mustWork = TRUE)
LMV2_P6_P5C_INPUTS <- list(
  base_p6_manifest = list(
    path = file.path(
      BASE, "output", "audit", "local_match_v2",
      "P6_V3_PRODUCTION_FREEZE_1ED", "p6_manifest.csv"),
    sha256 =
      "f5500e513565964f8b0fc1c3cd0a557c9804f8f079402fcc13f4b4d6b0dc741b"),
  estimation_config = list(
    path = file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"),
    sha256 =
      "c4b5cec45a6291761b8428317371096a2c4e1f26d5c2a25322ac2d467e490d88"),
  estimation_core = list(
    path = file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"),
    sha256 =
      "7e09ca4d5d15b242b5e2d511222b4147d3339bbe0067f190dda3b52afa7a639f"),
  estimation_runner = list(
    path = file.path(
      BASE, "R", "final_thesis", "19c_run_lmv2_p6_estimation.R"),
    sha256 =
      "7277e8d07ecc1bcb945c8e1e6e0ae4c933f21dbc0bece9d561785f726507c46c"),
  panel_reweighter = list(
    path = file.path(BASE, "R", "20a_reweight_lmv2_p6_panel.R"),
    sha256 =
      "425e20aa5d018fa342b9f5df26691549d06db5cadc67caa5842ced3c96431462"),
  count_active_roster_manifest = list(
    path = file.path(
      p4_base, "02_analysis", "output", "audit", "local_match_v2",
      "P5C_P6_HANDOFF_V2_COUNT_ACTIVE", "p5c_p6_roster_manifest.csv"),
    sha256 =
      "e0baa64bf5aa19ef51217f6cb4f984a8571abc1594823aedbd5c3790ce085fe9"),
  loyo_m3_roster_manifest = list(
    path = file.path(
      p4_base, "02_analysis", "output", "audit", "local_match_v2",
      "P5C_P6_HANDOFF_V2_LOYO_M3", "p5c_p6_roster_manifest.csv"),
    sha256 =
      "4a35058474089c894cc318a7f5368b037b3a108e7fd6af923831fa00e56e1054"),
  loyo_m4_roster_manifest = list(
    path = file.path(
      p4_base, "02_analysis", "output", "audit", "local_match_v2",
      "P5C_P6_HANDOFF_V2_LOYO_M4", "p5c_p6_roster_manifest.csv"),
    sha256 =
      "9eb610f44fcb331f1ce9a6cd70684ceeeaaddb032537e08521395e9cfbb85116"),
  count_active_panel_manifest = list(
    path = file.path(
      BASE, "output", "audit", "local_match_v2",
      "P6_P5C_PANEL_COUNT_ACTIVE", "p6_manifest.csv"),
    sha256 =
      "d734335fa4b780cbee36514c4d8647745bcdedd4c4e077a3c931228aa38e5d50"),
  loyo_m3_panel_manifest = list(
    path = file.path(
      BASE, "output", "audit", "local_match_v2",
      "P6_P5C_PANEL_LOYO_M3", "p6_manifest.csv"),
    sha256 =
      "f13667a71c065f5ee8cc941fcd5c1fbba7695c9d9bb98fd979fb667b6b740243"),
  loyo_m4_panel_manifest = list(
    path = file.path(
      BASE, "output", "audit", "local_match_v2",
      "P6_P5C_PANEL_LOYO_M4", "p6_manifest.csv"),
    sha256 =
      "92c4d0914d7661cb9d012e5936be6fc456c6be77a42d653f207625a77ff261a8")
)

lmv2_p6_p5c_assert_hash <- function(path, expected, label) {
  if (!file.exists(path)) stop("Missing frozen P6/P5c input: ", label)
  observed <- digest::digest(
    file = path, algo = "sha256")
  if (!identical(observed, expected)) {
    stop(
      "P6/P5c provenance drift in ", label,
      ": expected ", expected, ", observed ", observed)
  }
  invisible(TRUE)
}

lmv2_p6_p5c_assert_freeze <- function(design, panel_manifest_path) {
  if (!design %in% c("count_active", "loyo_m3", "loyo_m4")) {
    stop("Unknown P6/P5c design: ", design)
  }
  lmv2_p6_p5c_assert_hash(
    LMV2_P6_P5C_FREEZE_PATH,
    LMV2_P6_P5C_FREEZE_SHA256, "freeze")
  for (label in names(LMV2_P6_P5C_INPUTS)) {
    item <- LMV2_P6_P5C_INPUTS[[label]]
    lmv2_p6_p5c_assert_hash(item$path, item$sha256, label)
  }
  expected <- LMV2_P6_P5C_INPUTS[[
    paste0(design, "_panel_manifest")]]
  supplied <- normalizePath(
    panel_manifest_path, winslash = "/", mustWork = TRUE)
  if (!identical(
      supplied,
      normalizePath(
        expected$path, winslash = "/", mustWork = TRUE))) {
    stop("Supplied panel manifest is not the frozen ", design, " manifest")
  }
  invisible(TRUE)
}
