# Phase 9 regression test script
# Run with:
#   Rscript R/test_phase9.R

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(readxl)
  library(janitor)
  library(yaml)
  library(quarto)
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
      run_outlier_detection = TRUE,
      apply_outlier_policy = FALSE,
      run_descriptives = TRUE,
      run_anova_models = TRUE,
      run_mixed_models = FALSE,
      run_posthoc = TRUE,
      run_pca = TRUE,
      run_mfa = TRUE,
      create_tables = TRUE,
      create_figures = TRUE,
      render_quarto_report = TRUE
    ),
    report_options = list(output_formats = c("html", "docx")),
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
      mfa_groups = list(
        Sensory_primary = c("viscosity_ap", "sweetness_m"),
        Sensory_secondary = c("body_m")
      ),
      alpha = 0.05
    ),
    table_options = list(digits = 1, include_mean_se = TRUE, include_letters = TRUE),
    fig_options = list(width = 9, height = 5, dpi = 300, palette = "Set1", top_n_attributes = 3)
  )
}

cat("Running Phase 9 tests...\n")

state <- run_sensanalyser_pipeline(make_config())

stopifnot(!is.null(state$results$report))
stopifnot(!is.null(state$results$report$report$rendered_paths))
stopifnot(all(c("html", "docx") %in% names(state$results$report$report$rendered_paths)))
stopifnot(all(file.exists(unlist(state$results$report$report$rendered_paths, use.names = FALSE))))
stopifnot(file.exists(here("reports", "ai_summary_prompt.md")))

report_html <- state$results$report$report$rendered_paths[["html"]]
report_text <- paste(readLines(report_html, warn = FALSE), collapse = "\n")

report_docx <- state$results$report$report$rendered_paths[["docx"]]

stopifnot(grepl("Sensanalyser Results Report", report_text, fixed = TRUE))
stopifnot(grepl("Manuscript-Ready Product Means", report_text, fixed = TRUE))
stopifnot(grepl("Statistical Model Results", report_text, fixed = TRUE))
stopifnot(file.info(report_docx)$size > 0)

cat("All Phase 9 tests passed.\n")
