# Regression tests for two-product comparison handling.
# Run with: Rscript engine/tests/test_two_product_comparison.R
suppressMessages({ library(here); library(tibble) })
source(here::here("engine", "R", "load_sensanalyser.R"))
source(here::here("engine", "R", "functions", "posthoc_helpers.R"))
source(here::here("engine", "R", "functions", "table_helpers.R"))

passed <- 0L
check <- function(label, ...) {
  stopifnot(...)
  passed <<- passed + 1L
  cat("ok  ", label, "\n")
}

selections <- list(factors = "product", dependent_variables = c("chewiness_m", "firmness_m"))
two_products <- data.frame(product = c("Control", "Trial"), chewiness_m = c(1, 2))
three_products <- data.frame(product = c("Control", "Trial A", "Trial B"), chewiness_m = 1:3)
check("detects exactly two product levels", .is_two_product_comparison(two_products, selections))
check("does not classify three products as a two-product comparison",
      !.is_two_product_comparison(three_products, selections))

desc <- tibble(
  outcome = rep(c("chewiness_m", "firmness_m"), each = 2),
  outcome_display = rep(c("Chewiness (Mouthfeel)", "Firmness (Mouthfeel)"), each = 2),
  product = rep(c("Control", "Trial"), 2),
  mean_se = "3.0 ± 0.2"
)
models <- tibble(
  outcome = c("chewiness_m", "firmness_m"),
  term = c("product", "product"),
  p = c(0.01, 0.12)
)
marked <- .mark_two_product_significance(desc, models, "product")
check("adds a star to significant two-product attribute labels",
      all(marked$outcome_display[marked$outcome == "chewiness_m"] == "Chewiness (Mouthfeel)*"))
check("does not mark non-significant attributes",
      all(marked$outcome_display[marked$outcome == "firmness_m"] == "Firmness (Mouthfeel)"))

run_posthoc_phase <- function(...) stop("post-hoc phase should not be called")
state <- list(
  data = two_products,
  selections = selections,
  config = list(),
  results = list(models = list(results_model = models))
)
skipped <- .phase6_posthoc(state)
check("two-product scopes skip the post-hoc phase",
      isTRUE(skipped$results$posthoc$skipped_two_product_comparison))

cat(sprintf("\nAll %d two-product comparison checks passed.\n", passed))
