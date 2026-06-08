# Phase 8 regression test script
# Run with:
#   Rscript R/test_phase8.R

suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(readxl)
  library(janitor)
  library(yaml)
  library(factoextra)
  library(FactoMineR)
  library(fmsb)
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
      run_descriptives = FALSE,
      run_anova_models = FALSE,
      run_mixed_models = FALSE,
      run_posthoc = FALSE,
      run_pca = TRUE,
      run_mfa = TRUE,
      create_tables = FALSE,
      create_figures = TRUE,
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

cat("Running Phase 8 tests...\n")

state <- run_sensanalyser_pipeline(make_config())

# Validate phase result exists
stopifnot(!is.null(state$results$phase8))
stopifnot(!is.null(state$results$phase8$figures))
stopifnot(!is.null(state$results$phase8$pca))
stopifnot(!is.null(state$results$phase8$mfa))

# Validate no skips
stopifnot(isFALSE(state$results$phase8$figures$skipped))
stopifnot(isFALSE(state$results$phase8$pca$skipped))
stopifnot(isFALSE(state$results$phase8$mfa$skipped))

# Validate generated files exist
expected_files <- c(
  # Spider plots — default "all_products" comparison (no spider_comparisons set)
  here("outputs", "figures", "spiderplots", "spider_all_products.png"),
  here("outputs", "tables",  "spiderplots", "spider_all_products_means.csv"),
  # PCA tables
  here("outputs", "tables", "pca", "pca_eigenvalues.csv"),
  here("outputs", "tables", "pca", "pca_group_scores.csv"),
  here("outputs", "tables", "pca", "pca_variable_coordinates.csv"),
  # PCA figures (individuals + correlation circle replace old biplot)
  here("outputs", "figures", "pca", "pca_scree_plot.png"),
  here("outputs", "figures", "pca", "pca_scores_plot.png"),
  here("outputs", "figures", "pca", "pca_correlation_circle.png"),
  # MFA tables
  here("outputs", "tables", "mfa", "mfa_eigenvalues.csv"),
  here("outputs", "tables", "mfa", "mfa_individual_coordinates.csv"),
  here("outputs", "tables", "mfa", "mfa_variable_coordinates.csv"),
  here("outputs", "tables", "mfa", "mfa_group_specification.csv"),
  # MFA figures (individuals + variables correlation circle)
  here("outputs", "figures", "mfa", "mfa_individuals.png"),
  here("outputs", "figures", "mfa", "mfa_variables.png")
)
stopifnot(all(file.exists(expected_files)))

# Validate key tables have rows
pca_eig <- readr::read_csv(here("outputs", "tables", "pca", "pca_eigenvalues.csv"), show_col_types = FALSE)
mfa_eig <- readr::read_csv(here("outputs", "tables", "mfa", "mfa_eigenvalues.csv"), show_col_types = FALSE)
spider_tbl <- readr::read_csv(here("outputs", "tables", "spiderplots", "spider_all_products_means.csv"), show_col_types = FALSE)

stopifnot(nrow(pca_eig) > 0)
stopifnot(nrow(mfa_eig) > 0)
stopifnot(nrow(spider_tbl) > 0)

# Validate expected columns
stopifnot(all(c("component", "variance_percent") %in% names(pca_eig)))
stopifnot(all(c("component", "variance_percent") %in% names(mfa_eig)))

cat("All Phase 8 tests passed.\n")
