# Phase 7 regression test script
# Run with:
#   Rscript R/test_phase7.R

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

make_config <- function() {
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
      run_descriptives = TRUE,
      run_anova_models = TRUE,
      run_mixed_models = FALSE,
      run_posthoc = TRUE,
      run_pca = FALSE,
      run_mfa = FALSE,
      create_tables = TRUE,
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
      posthoc_focal_terms = c("product"),
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

cat("Running Phase 7 tests...\n")

# Full pipeline: Phases 1–7
state <- run_sensanalyser_pipeline(make_config())

# Check Phase 7 results object
stopifnot(!is.null(state$results$tables))
stopifnot(!is.null(state$results$tables$report_format_wide))
stopifnot(!is.null(state$results$tables$run_configuration_summary))
stopifnot(is.data.frame(state$results$tables$report_format_wide))
stopifnot(is.data.frame(state$results$tables$run_configuration_summary))

# Check report_format_wide table
# Correct format: rows = outcomes, columns = "outcome" + factor levels
report_wide <- state$results$tables$report_format_wide
stopifnot(nrow(report_wide) > 0)
# "outcome" column holds display names for each sensory attribute
stopifnot("outcome" %in% names(report_wide))
# Must have at least one factor-level column (Product A, Product B, …)
stopifnot(ncol(report_wide) >= 2)
# Number of rows must equal number of DVs analyzed
stopifnot(nrow(report_wide) == length(make_config()$analysis$dependent_variables))

# Check configuration summary
config_summary <- state$results$tables$run_configuration_summary
stopifnot(nrow(config_summary) == 1)
required_config_cols <- c("run_date", "data_file", "model_type", "posthoc_method", "alpha")
stopifnot(all(required_config_cols %in% names(config_summary)))

# Check output files exist
expected_files <- c(
  here("outputs", "tables", "report_format_wide.csv"),
  here("outputs", "tables", "run_configuration_summary.csv")
)
stopifnot(all(file.exists(expected_files)))

# Verify configuration values are correctly recorded
stopifnot(config_summary$model_type == "one_way_anova")
stopifnot(config_summary$posthoc_method == "tukey")
stopifnot(config_summary$alpha == 0.05)

cat("All Phase 7 tests passed.\n")
