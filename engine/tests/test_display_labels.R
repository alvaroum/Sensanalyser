# Regression tests for automatic sensory-attribute display labels.
# Run with: Rscript engine/tests/test_display_labels.R
suppressMessages({ library(here); library(yaml) })
source(here::here("engine", "R", "functions", "descriptive_helpers.R"))

passed <- 0L
check <- function(label, actual, expected) {
  stopifnot(identical(actual, expected))
  passed <<- passed + 1L
  cat("ok  ", label, "\n")
}

empty_dict <- list(outcomes = list())
check(
  "recognised modality suffixes become presentation labels",
  unname(.apply_outcome_labels(
    c("darkness_crumb_ap", "stickiness_m", "firmness_t", "overall_flavour_f", "offaroma_a", "residu_af"),
    empty_dict
  )), 
  c(
    "Darkness crumb (Appearance)", "Stickiness (Mouthfeel)",
    "Firmness (Texture)", "Overall flavour (Flavour)",
    "Offaroma (Aroma)", "Residu (Aftertaste)"
  )
)
check(
  "names without a modality suffix retain an underscore-free fallback",
  unname(.apply_outcome_labels("overall_liking", empty_dict)),
  "Overall liking"
)
check(
  "explicit attribute labels override automatic formatting",
  unname(.apply_outcome_labels(
    "darkness_crumb_ap",
    list(outcomes = list(darkness_crumb_ap = "Crumb darkness"))
  )), 
  "Crumb darkness"
)

cat(sprintf("\nAll %d display-label checks passed.\n", passed))
