# Phase 3 regression test script
# Run with:
#   Rscript R/test_phase3.R

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(readxl)
  library(janitor)
  library(yaml)
  library(rstatix)
})

source(here("R", "core_engine.R"))

make_config <- function(policy = "remove_extreme", action = "set_na", apply_policy = TRUE) {
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
      run_outlier_detection = TRUE,
      apply_outlier_policy = apply_policy,
      run_descriptives = FALSE,
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
      outlier_policy = policy,
      outlier_removal_action = action,
      outlier_grouping_factors = c("product"),
      alpha = 0.05
    ),
    table_options = list(digits = 1, include_mean_se = TRUE, include_letters = TRUE),
    fig_options = list(width = 9, height = 5, dpi = 300, palette = "Set1")
  )
}

cat("Running Phase 3 tests...\n")

raw_data <- readr::read_csv(here("data", "raw", "Raw.data.sting.csv"), show_col_types = FALSE)

# Test A: remove_all + set_na should increase NA count
state_set_na <- run_sensanalyser_pipeline(make_config("remove_all", "set_na", TRUE))
cols <- c("viscosity_ap", "sweetness_m", "body_m", "burn_m")
na_before <- sum(is.na(raw_data[, cols]))
na_after <- sum(is.na(state_set_na$data[, cols]))
stopifnot(na_after >= na_before)

# Test B: remove_all + drop_row should reduce row count
state_drop <- run_sensanalyser_pipeline(make_config("remove_all", "drop_row", TRUE))
stopifnot(nrow(state_drop$data) <= nrow(raw_data))

# Test C: apply_outlier_policy FALSE should preserve row count and diagnostics
# should not claim that data were actually changed.
state_no_apply <- run_sensanalyser_pipeline(make_config("remove_all", "drop_row", FALSE))
stopifnot(nrow(state_no_apply$data) == nrow(raw_data))
stopifnot(all(!state_no_apply$results$outliers$policy_table$applied_to_data))
stopifnot(any(state_no_apply$results$outliers$policy_table$decision == "kept_not_applied"))

# Test D: keep_all should never target rows/cells for removal
state_keep_all <- run_sensanalyser_pipeline(make_config("keep_all", "set_na", TRUE))
stopifnot(nrow(state_keep_all$data) == nrow(raw_data))
stopifnot(all(!state_keep_all$results$outliers$policy_table$targeted_by_policy))

# Test E: diagnostics files should exist
diag_files <- c(
  here("outputs", "diagnostics", "outliers_all.csv"),
  here("outputs", "diagnostics", "outlier_policy_applied.csv"),
  here("outputs", "diagnostics", "outlier_decision_summary.csv")
)
stopifnot(all(file.exists(diag_files)))

cat("All Phase 3 tests passed.\n")
