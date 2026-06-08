# Phase 5 regression test script
# Run with:
#   Rscript R/test_phase5.R

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(readxl)
  library(janitor)
  library(yaml)
  library(rstatix)
  library(lmerTest)
})

source(here("R", "core_engine.R"))

make_base_config <- function() {
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
      run_posthoc = FALSE,
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
      posthoc_method = "tukey",
      posthoc_focal_terms = NULL,
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

cat("Running Phase 5 tests...\n")

# Test 1: one-way ANOVA model suite
cfg_anova <- make_base_config()
state_anova <- run_sensanalyser_pipeline(cfg_anova)

stopifnot(!is.null(state_anova$results$models))
stopifnot(is.data.frame(state_anova$results$models$results_model))
stopifnot(nrow(state_anova$results$models$results_model) > 0)

required_cols_anova <- c("outcome", "model_type", "engine", "formula")
stopifnot(all(required_cols_anova %in% names(state_anova$results$models$results_model)))

# Test 2: repeated-measures ANOVA path through afex
cfg_rep <- make_base_config()
cfg_rep$analysis$model_type <- "one_way_repeated"
cfg_rep$analysis$model_fixed_effects <- c("product")
cfg_rep$analysis$repeated_measures_factors <- c("product")
state_rep <- run_sensanalyser_pipeline(cfg_rep)
stopifnot(!is.null(state_rep$results$models))
stopifnot(is.data.frame(state_rep$results$models$results_model))
stopifnot(nrow(state_rep$results$models$results_model) > 0)
stopifnot(all(state_rep$results$models$results_model$engine == "afex_aov_car"))
stopifnot("p" %in% names(state_rep$results$models$results_model))
stopifnot(is.numeric(state_rep$results$models$results_model$p))

# Test 3: linear mixed model path
cfg_lmm <- make_base_config()
cfg_lmm$toggles$run_anova_models <- FALSE
cfg_lmm$toggles$run_mixed_models <- TRUE
cfg_lmm$analysis$model_type <- "linear_mixed_model"
cfg_lmm$analysis$model_fixed_effects <- c("product")
cfg_lmm$analysis$random_effects <- c("user")

state_lmm <- run_sensanalyser_pipeline(cfg_lmm)
stopifnot(!is.null(state_lmm$results$models))
stopifnot(is.data.frame(state_lmm$results$models$results_model))
stopifnot(all(c("outcome", "engine", "formula") %in% names(state_lmm$results$models$results_model)))

# Formula helper check: three fixed effects without three-way interaction should use ^2
settings_formula <- list(
  fixed_effects = c("a", "b", "c"),
  interactions = TRUE,
  three_way_interactions = FALSE,
  engine = "rstatix_anova_test"
)
formula_check <- build_model_formula("y", settings_formula, selections = list())
stopifnot(identical(as.character(formula_check)[3], "(a + b + c)^2"))

# Output files check
expected_files <- c(
  here("outputs", "tables", "results_model.csv"),
  here("outputs", "diagnostics", "model_warnings.csv")
)
stopifnot(all(file.exists(expected_files)))

cat("All Phase 5 tests passed.\n")
