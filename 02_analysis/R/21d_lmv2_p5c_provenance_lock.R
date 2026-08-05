# ============================================================================
# P5c provenance lock
# ============================================================================
# This file deliberately does not hash itself, avoiding a circular lock.

LMV2_P5C_APPROVED_PROVENANCE <- c(
  config =
    "74534305df708a57594b78b1bd6574a6ffb8e9c3e886819968ffe7d6bd0fe589",
  runner =
    "93aa03608e6dc4c2811fbeb02d10c077a4956e636359c250583825879ffaa2fd",
  freeze =
    "6ace3cdc2771ff85ab38a2b19be7b8e7e51204ea5a3090451df78f3f8bf283ec",
  source_manifest =
    "b279ac11e01a565a1792aa1712c539dc067d0ddda68fae32dc350bdd1fe4783e",
  matching_config =
    "582c7fd78a68baf685a81df8dd6aefaea82620e3e5ddf560dc5ce587a49f7ab2",
  matching_utils =
    "4496afecd8bb7324eb2d1f5dfd98cf6c6ba0dcd54750fbcc3a4d0e8bcc39e6f7",
  ebal_config =
    "583765725a6dcf8b290fbd8209341827dc2a486f89a2561c510f1da237e3ccf5",
  ebal_utils =
    "67cf605fee5a53c8549b57fce94863b8c76d9637db07c967bda45c54e2266549",
  hybrid_core =
    "bfb575af3d800ca8aa44437124863b8bd2e8bc5452cd81f3079cc230f78b89b4",
  cohort_core =
    "758e47d45c713cceb79da9c9f89c6a7de68c588abe2f7f866ac8625b42212d8a",
  newton_solver =
    "f63bc001bc05c8188f00683aa231e039f6c56a465cb1cc2bc3ad80413cb22a73"
)

lmv2_p5c_assert_hash <- function(path, expected, label) {
  observed <- digest::digest(
    file = path, algo = "sha256")
  if (!identical(observed, expected)) {
    stop(
      "P5c provenance drift in ", label,
      ": expected ", expected, ", observed ", observed)
  }
  invisible(TRUE)
}

lmv2_p5c_assert_provenance <- function(source_manifest_path) {
  observed <- lmv2_p5c_provenance(source_manifest_path)
  if (!identical(
      names(observed), names(LMV2_P5C_APPROVED_PROVENANCE))) {
    stop("P5c provenance schema differs from the approved lock")
  }
  bad <- names(observed)[
    observed != LMV2_P5C_APPROVED_PROVENANCE]
  if (length(bad)) {
    stop(
      "P5c provenance drift in: ",
      paste(bad, collapse = ", "))
  }
  invisible(TRUE)
}
