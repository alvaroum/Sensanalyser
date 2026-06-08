# ==========================================================================
# SENSANALYSER — PROJECT-SPECIFIC RERUN: OVERALL FRUITY
# ==========================================================================
#
# Purpose:
#   Creates one project-specific conceptual category, overall_fruity, by
#   averaging selected fruit-related aroma and flavour attributes. It then
#   reruns the standard Sensanalyser pipeline on this derived variable only.
#
# Outputs are written to outputs/derived_overall_fruity/ so the original
# detailed-attribute analysis is not overwritten.
#
# How to run:
#   source("mission_control_overall_fruity.R")
#
# ===========================================================================

library(here)

config <- list(

  paths = list(
    raw_data = "data/raw/Raw.data.sting.csv",
    analysis_config = "data/dictionary/analysis_config_overall_fruity.yaml",
    renaming_dictionary = "data/dictionary/renaming_dictionary.yaml",
    model_presets = "data/dictionary/model_presets.yaml",
    derived_attributes = "data/dictionary/derived_attributes.yaml",
    derived_data = "data/processed/derived_attribute_dataset_overall_fruity.csv",
    table_root = "outputs/derived_overall_fruity/tables",
    figure_root = "outputs/derived_overall_fruity/figures",
    diagnostics_root = "outputs/derived_overall_fruity/diagnostics",
    logs_root = "outputs/derived_overall_fruity/logs",
    report_template = "reports/sensanalyser_results_report.qmd"
  ),

  toggles = list(
    interactive_setup = FALSE,
    discover_variables = FALSE,
    create_derived_attributes = TRUE,
    run_outlier_detection = TRUE,
    apply_outlier_policy = TRUE,
    run_descriptives = TRUE,
    run_anova_models = FALSE,
    run_mixed_models = TRUE,
    run_posthoc = TRUE,
    run_pca = TRUE,
    run_mfa = FALSE,
    create_tables = TRUE,
    create_figures = TRUE,
    render_quarto_report = FALSE
  ),

  analysis = list(
    dependent_variables = c(
      "transparancy_ap",
      "viscosity_ap",
      "dried_fruits_a",
      "woody_a",
      "animalic_a",
      "medicinal_a",
      "solvent_a",
      "molasses_a",
      "honey_a",
      "leathery_a",
      "musty_a",
      "confectionary_a",
      "floral_a",
      "caramalized_sugar_a",
      "green_a",
      "cooked_vegetal_a",
      "vanilla_a",
      "baking_spices_a",
      "ethanol_a",
      "sweetness_m",
      "sourness_m",
      "bitterness_m",
      "saltiness_m",
      "dried_fruits_f",
      "woody_f",
      "animalic_f",
      "medicinal_f",
      "solvent_f",
      "molasses_f",
      "honey_f",
      "leathery_f",
      "musty_f",
      "confectionary_f",
      "floral_f",
      "caramalized_sugar_f",
      "green_f",
      "cooked_vegetal_f",
      "vanilla_f",
      "baking_spices_f",
      "ethanol_f",
      "tingeling_m",
      "silkiness_m",
      "body_m",
      "burn_m",
      "coating_m",
      "overall_fruity"
    ),
    factors = c("product"),
    subject_id = "user",
    repeated_measures_factors = NULL,
    random_effects = c("user"),
    blocking_factors = NULL,
    model_type = "linear_mixed_model",
    model_fixed_effects = NULL,
    posthoc_method = "lsd",
    posthoc_focal_terms = NULL,
    outlier_policy = "remove_extreme",
    outlier_removal_action = "set_na",
    outlier_grouping_factors = NULL,
    descriptive_grouping_factors = NULL,
    alpha = 0.05
  ),

  derived_attribute_options = list(
    digits = NULL
  ),

  table_options = list(
    digits = 1,
    include_mean_se = TRUE,
    include_letters = TRUE
  ),

  fig_options = list(
    width = 9,
    height = 7,
    dpi = 300,
    palette = "Set1",
    top_n_attributes = NULL,
    spider_significant_only = TRUE,
    spider_outcomes = NULL,
    spider_comparisons = list(
      all_products = NULL,
      control_vs_trial1 = c("Control", "Trial 1"),
      control_vs_trial2 = c("Control", "Trial 2"),
      control_vs_trial3 = c("Control", "Trial 3"),
      control_vs_trial4 = c("Control", "Trial 4"),
      control_vs_trial5 = c("Control", "Trial 5"),
      control_vs_trial6 = c("Control", "Trial 6")
    )
  ),

  report_options = list(
    output_formats = c("html", "docx")
  )
)

source(here::here("R", "core_engine.R"))
run_sensanalyser_pipeline(config)
