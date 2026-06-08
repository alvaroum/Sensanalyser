# Phase 6 regression test script
# Run with:
#   Rscript R/test_phase6.R

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(readxl)
  library(janitor)
  library(yaml)
  library(rstatix)
  library(lmerTest)
  library(multcompView)
})

source(here("R", "core_engine.R"))

make_config <- function(method = "tukey", focal_terms = c("product")) {
  list(
    paths = list(
      raw_data = here("data", "raw", "Raw.data.sting.csv"),
      analysis_config = here("data", "dictionary", "analysis_config.yaml"),
      renaming_dictionary = here("data", "dictionary", "renaming_dictionary.yaml"),
      model_presets = here("data", "dictionary", "model_presets.yaml"),
      table_root = "outputs/tables",
      figure_root = "outputs/figures",
      diagnostics_root = "outputs/diagnostics",
      logs_root = "outputs/logs",
      report_template = "reports/sensanalyser_results_report.qmd"
    ),
    toggles = list(
      interactive_setup = FALSE,
      discover_variables = FALSE,
      run_outlier_detection = FALSE,
      apply_outlier_policy = FALSE,
      run_descriptives = FALSE,
      run_anova_models = TRUE,
      run_mixed_models = FALSE,
      run_posthoc = TRUE,
      run_pca = FALSE,
      run_mfa = FALSE,
      create_tables = FALSE,
      create_figures = FALSE,
      render_quarto_report = FALSE
    ),
    analysis = list(
      dependent_variables = c("viscosity_ap", "sweetness_m", "body_m"),
      factors = c("product"),
      subject_id = "user",
      repeated_measures_factors = c("product"),
      random_effects = c("user"),
      blocking_factors = NULL,
      model_type = "one_way_anova",
      model_fixed_effects = c("product"),
      posthoc_method = method,
      posthoc_focal_terms = focal_terms,
      outlier_policy = "remove_extreme",
      outlier_removal_action = "set_na",
      outlier_grouping_factors = c("product"),
      descriptive_grouping_factors = c("product"),
      alpha = 0.05
    ),
    table_options = list(digits = 1, include_mean_se = TRUE, include_letters = TRUE),
    fig_options = list(width = 9, height = 5, dpi = 300, palette = "Set1")
  )
}

cat("Running Phase 6 tests...\n")

# Test 1: Tukey post-hoc path
state_tukey <- run_sensanalyser_pipeline(make_config("tukey", c("product")))
stopifnot(!is.null(state_tukey$results$posthoc))
stopifnot(is.data.frame(state_tukey$results$posthoc$posthoc_pairwise))
stopifnot(is.data.frame(state_tukey$results$posthoc$posthoc_letters))
stopifnot(is.data.frame(state_tukey$results$posthoc$posthoc_method_summary))
stopifnot(nrow(state_tukey$results$posthoc$posthoc_pairwise) > 0)
stopifnot(nrow(state_tukey$results$posthoc$posthoc_letters) > 0)
stopifnot(all(state_tukey$results$posthoc$posthoc_pairwise$method == "tukey"))

# Test 2: Bonferroni produces distinguishable adjustment label
state_bonf <- run_sensanalyser_pipeline(make_config("bonferroni", c("product")))
stopifnot(nrow(state_bonf$results$posthoc$posthoc_pairwise) > 0)
stopifnot(all(state_bonf$results$posthoc$posthoc_pairwise$adjust == "bonferroni"))

# Test 3: LSD path uses adjust none
state_lsd <- run_sensanalyser_pipeline(make_config("lsd", c("product")))
stopifnot(nrow(state_lsd$results$posthoc$posthoc_pairwise) > 0)
stopifnot(all(state_lsd$results$posthoc$posthoc_pairwise$adjust == "none"))

# Test 4: invalid method should fail early with a clear error
invalid_failed <- tryCatch(
  {
    run_sensanalyser_pipeline(make_config("duncan", c("product")))
    FALSE
  },
  error = function(e) TRUE
)
stopifnot(invalid_failed)

# Test 5: summary + output files
expected_files <- c(
  here("outputs", "tables", "posthoc_pairwise.csv"),
  here("outputs", "tables", "posthoc_letters.csv"),
  here("outputs", "tables", "posthoc_method_summary.csv")
)
stopifnot(all(file.exists(expected_files)))

required_summary_cols <- c("outcome", "requested_term", "method", "adjust", "letters_suppressed")
stopifnot(all(required_summary_cols %in% names(state_tukey$results$posthoc$posthoc_method_summary)))

# Test 6: interaction-style focal term expands to by-level post-hoc requests
cfg_interaction <- make_config("tukey", c("product:replica"))
cfg_interaction$analysis$dependent_variables <- c("viscosity_ap")
cfg_interaction$analysis$factors <- c("product", "replica")
cfg_interaction$analysis$model_type <- "two_way_anova"
cfg_interaction$analysis$model_fixed_effects <- c("product", "replica")
state_interaction <- run_sensanalyser_pipeline(cfg_interaction)
stopifnot(nrow(state_interaction$results$posthoc$posthoc_pairwise) > 0)
stopifnot(any(!is.na(state_interaction$results$posthoc$posthoc_pairwise$by)))
stopifnot(any(state_interaction$results$posthoc$posthoc_pairwise$requested_term == "product:replica"))

# Test 7: repeated-measures afex model object works with emmeans post-hocs
cfg_rep <- make_config("tukey", c("product"))
cfg_rep$analysis$dependent_variables <- c("viscosity_ap")
cfg_rep$analysis$model_type <- "one_way_repeated"
cfg_rep$analysis$model_fixed_effects <- c("product")
cfg_rep$analysis$repeated_measures_factors <- c("product")
state_rep <- run_sensanalyser_pipeline(cfg_rep)
stopifnot(nrow(state_rep$results$posthoc$posthoc_pairwise) > 0)
stopifnot(all(state_rep$results$posthoc$posthoc_pairwise$method == "tukey"))

cat("All Phase 6 tests passed.\n")
