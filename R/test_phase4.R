# Phase 4 regression test script
# Run with:
#   Rscript R/test_phase4.R

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(readxl)
  library(janitor)
  library(yaml)
  library(rstatix)
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
      run_anova_models = FALSE,
      run_mixed_models = FALSE,
      run_posthoc = FALSE,
      run_pca = FALSE,
      run_mfa = FALSE,
      create_tables = FALSE,
      create_figures = FALSE,
      render_quarto_report = FALSE
    ),
    analysis = list(
      dependent_variables = c("viscosity_ap", "sweetness_m", "body_m", "burn_m"),
      factors = c("product"),
      subject_id = "user",
      repeated_measures_factors = c("product"),
      random_effects = NULL,
      blocking_factors = NULL,
      model_type = "one_way_repeated",
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

cat("Running Phase 4 tests...\n")

state <- run_sensanalyser_pipeline(make_config())

# Check pipeline results object
stopifnot(!is.null(state$results$descriptives))
stopifnot(is.data.frame(state$results$descriptives$descriptives_long))
stopifnot(is.data.frame(state$results$descriptives$descriptives_wide_mean_se))
stopifnot(is.data.frame(state$results$descriptives$descriptives_wide_means_only))

# Check minimum expected rows and columns
long_tbl <- state$results$descriptives$descriptives_long
stopifnot(nrow(long_tbl) > 0)
required_long_cols <- c("product", "outcome", "n", "mean", "sd", "se", "mean_se", "outcome_display")
stopifnot(all(required_long_cols %in% names(long_tbl)))

# Check output files exist
expected_files <- c(
  here("outputs", "tables", "descriptives_long.csv"),
  here("outputs", "tables", "descriptives_wide_mean_se.csv"),
  here("outputs", "tables", "descriptives_wide_means_only.csv"),
  here("outputs", "tables", "profile_table.csv")
)
stopifnot(all(file.exists(expected_files)))

# Validate one known display label mapping is present
stopifnot(any(long_tbl$outcome_display == "Viscosity (Appearance)"))

# Check global/no-grouping mode
source(here("R", "functions", "data_import_helpers.R"))
source(here("R", "functions", "descriptive_helpers.R"))
data_raw <- load_sensanalyser_data(here("data", "raw", "Raw.data.sting.csv"), verbose = FALSE)
dict <- load_renaming_dictionary(here("data", "dictionary", "renaming_dictionary.yaml"))
global_long <- create_descriptives_long(
  data_raw,
  dependent_variables = c("viscosity_ap", "sweetness_m"),
  grouping_factors = character(0),
  digits = 2,
  renaming_dictionary = dict
)
stopifnot(nrow(global_long) == 2)
global_wide <- create_descriptives_wide_outcomes(global_long, character(0))
stopifnot(nrow(global_wide) == 1)

# Check validation catches invalid role overlap
validation_failed <- tryCatch(
  {
    create_descriptives_long(data_raw, dependent_variables = "product", grouping_factors = "product")
    FALSE
  },
  error = function(e) TRUE
)
stopifnot(validation_failed)

# Check n = 1 produces an explicit NA SE rather than NaN text
one_row <- tibble::tibble(group = "a", x = 1)
one_row_desc <- create_descriptives_long(one_row, dependent_variables = "x", grouping_factors = "group")
stopifnot(grepl("NA", one_row_desc$mean_se), !grepl("NaN", one_row_desc$mean_se))

cat("All Phase 4 tests passed.\n")
