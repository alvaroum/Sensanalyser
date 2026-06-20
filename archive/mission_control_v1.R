# ==========================================================================
# SENSANALYSER — MISSION CONTROL
# ==========================================================================
#
# Purpose:
#   This is the ONLY file you need to edit to control the full analysis
#   pipeline. Set paths, enable/disable pipeline phases, configure the
#   statistical model, outlier handling, and table options here.
#
# How to run:
#   1. Open this project in RStudio (Sensanalyser.Rproj).
#   2. Edit the config sections below.
#   3. Press Ctrl+Shift+Enter (or Run All) to execute.
#
# First-time setup:
#   - Set config$paths$raw_data to your data file, OR
#     leave it NULL to select the file interactively.
#   - Set config$toggles$interactive_setup = TRUE for guided setup.
#   - Set config$toggles$discover_variables = TRUE to preview the data
#     structure before analysis begins.
#
# Reproducible runs:
#   - After a first interactive run, analysis_config.yaml is saved to
#     data/dictionary/. On subsequent runs, set interactive_setup = FALSE
#     and the pipeline will read from that file.
#
# ==========================================================================

library(here)

config <- list(

  # ─── 1. PATHS ────────────────────────────────────────────────────────────
  paths = list(

    # Path to the raw data file.
    # Set to NULL to select the file interactively.
    # Supported formats: .csv, .tsv, .txt, .xlsx, .xls
    raw_data = NULL,
    # raw_data = "data/raw/Raw.data.sting.csv",   # Example

    # Path to the saved analysis configuration (variable selections, model
    # settings). Generated automatically after an interactive setup run.
    analysis_config = "data/dictionary/analysis_config.yaml",

    # Path to the display-name renaming dictionary.
    renaming_dictionary = "data/dictionary/renaming_dictionary.yaml",

    # Path to the model preset definitions.
    model_presets = "data/dictionary/model_presets.yaml",

    # Optional project-specific derived-attribute definitions.
    # When toggles$create_derived_attributes is TRUE, these definitions add
    # derived variables to the working dataset before variable selection.
    derived_attributes = "data/dictionary/derived_attributes.yaml",
    derived_data       = "data/processed/derived_attribute_dataset.csv",

    # Output directories (created automatically if missing).
    table_root       = "outputs/tables",
    figure_root      = "outputs/figures",
    diagnostics_root = "outputs/diagnostics",
    logs_root        = "outputs/logs",

    # Quarto report template path.
    report_template = "reports/sensanalyser_results_report.qmd"
  ),

  # ─── 2. EXECUTION TOGGLES ────────────────────────────────────────────────
  # TRUE = run this phase. FALSE = skip.
  toggles = list(

    # First-time / interactive setup.
    # When TRUE, a dialog or console prompt asks you to choose a file and
    # select variables. The selections are saved to analysis_config.yaml.
    interactive_setup = FALSE,

    # Discovery mode: if TRUE, prints a full data structure overview and
    # stops the pipeline before any analysis runs.
    discover_variables = FALSE,

    # Project-specific derived attributes.
    # Keep FALSE for the standard detailed-attribute analysis. Use TRUE for
    # project-specific reruns such as the overall_fruity analysis.
    create_derived_attributes = FALSE,

    # Outlier detection and handling.
    run_outlier_detection = TRUE,
    apply_outlier_policy  = TRUE,

    # Descriptive statistics.
    run_descriptives = TRUE,

    # Model engines.
    run_anova_models  = FALSE,
    run_mixed_models  = TRUE,   # Set TRUE to use linear mixed models instead

    # Post-hoc tests.
    run_posthoc = TRUE,

    # Multivariate analyses.
    run_pca = TRUE,
    run_mfa = FALSE,
    run_hcpc = TRUE,

    # Output generation.
    create_tables  = TRUE,
    create_figures = TRUE,

    # Quarto report rendering. When TRUE, renders reports/sensanalyser_results_report.qmd
    # from already-generated outputs without rerunning analyses inside the report.
    render_quarto_report = FALSE
  ),

  # ─── 3. ANALYSIS SETTINGS ────────────────────────────────────────────────
  analysis = list(

    # Dependent variables (sensory attributes to analyse).
    # Options:
    #   NULL              → opens an interactive selection dialog
    #   "auto"            → auto-detects all numeric columns not used as factors/IDs
    #   "5:20"  or "5-20" → uses columns 5 through 20 by index (run discover_variables
    #                        first to see column numbers)
    #   c("sweetness_m", "sourness_m", ...)  → explicit column names
    dependent_variables = NULL,

    # Fixed factors (independent variables, e.g. product, treatment).
    # Set to NULL to select interactively.
    factors = NULL,

    # Panelist / assessor / subject column name.
    # Set to NULL if not applicable (purely between-subjects designs).
    subject_id = NULL,

    # Repeated-measures factors: list the factor column name(s) that are
    # repeated within each subject.
    repeated_measures_factors = NULL,

    # Random effects: relevant for linear mixed models only.
    random_effects = NULL,

    # Blocking factors: included in the model but not of primary interest.
    blocking_factors = NULL,

    # Model type. Options (see data/dictionary/model_presets.yaml):
    #   one_way_anova, two_way_anova, three_way_anova
    #   one_way_repeated, two_way_repeated, two_way_mixed, three_way_repeated
    #   linear_mixed_model
    model_type = "linear_mixed_model",

    # Optional explicit fixed effects for model formulas.
    # If NULL, model presets (or selected factors) are used.
    model_fixed_effects = NULL,

    # Post-hoc method. Options: tukey, bonferroni, lsd
    posthoc_method = "lsd",

    # Post-hoc focal terms. NULL = run post-hoc on all significant effects.
    posthoc_focal_terms = NULL,

    # Outlier policy. Options:
    #   keep_all       — detect and report but do not modify data
    #   remove_extreme — remove only extreme outliers (recommended default)
    #   remove_all     — remove all identified outliers
    outlier_policy = "remove_extreme",

    # Outlier removal action. Options:
    #   set_na   — set only the outlying DV value to NA
    #   drop_row — remove the full row when targeted by policy
    outlier_removal_action = "set_na",

    # Optional grouping factors for outlier detection. If NULL, the pipeline
    # defaults to selected fixed factors.
    outlier_grouping_factors = NULL,

    # Optional grouping factors for descriptives (Phase 4). If NULL,
    # descriptives use selected fixed factors.
    descriptive_grouping_factors = NULL,

    # PCA attribute selection. TRUE = PCA uses only attributes with significant
    # product effects in the current post-hoc/model output.
    pca_significant_only = TRUE,

    # HCPC / hierarchical clustering. Use NULL or -1 for automatic cluster choice.
    hcpc_n_clusters = 4,

    # Significance level
    alpha = 0.05
  ),

  # ─── 4. DERIVED ATTRIBUTE OPTIONS ────────────────────────────────────────
  derived_attribute_options = list(
    digits = NULL       # NULL = do not round derived values before analysis
  ),

  # ─── 5. TABLE OPTIONS ────────────────────────────────────────────────────
  table_options = list(
    digits         = 1,      # Decimal places for means and SE in output tables
    include_mean_se = TRUE,  # If TRUE, format cells as "mean ± SE"
    include_letters = TRUE   # If TRUE, add compact post-hoc letters to tables
  ),

  # ─── 6. FIGURE OPTIONS ───────────────────────────────────────────────────
  fig_options = list(

    # Plot dimensions and resolution
    width  = 9,
    height = 7,
    dpi    = 300,

    # RColorBrewer palette name for spider plot group colours.
    # See RColorBrewer::display.brewer.all() for available palettes.
    palette = "Set1",

    # Spider plot — attribute selection
    # -------------------------------------------------------------------------
    # Limit spider plots to the top-N attributes ranked by global mean.
    # NULL = include all attributes (subject to other filters below).
    top_n_attributes = NULL,

    # When TRUE, restrict spider plots to attributes with a significant
    # omnibus test (i.e. omnibus_significant = TRUE in posthoc_letters.csv).
    # Requires run_posthoc = TRUE and run_posthoc to have already run.
    spider_significant_only = TRUE,

    # Explicit list of attribute column names to include on spider plots.
    # NULL = use all selected DVs (filtered by the options above).
    # Example: c("tropical_a", "honey_a", "confectionary_a", "leathery_a")
    spider_outcomes = NULL,

    # Spider plot — group comparisons
    # -------------------------------------------------------------------------
    # Each named entry generates a separate spider plot file.
    #   NULL value   → include all product groups
    #   character vector → include only those display-name groups
    #
    # Examples:
    #   all_products     = NULL
    #   trial1_vs_trial2 = c("Trial 1", "Trial 2")
    #   each_vs_control  = c("Trial 1", "Trial 2", "Trial 3",
    #                        "Trial 4", "Trial 5", "Trial 6", "Control")
    spider_comparisons = list(
      control_vs_trial1 = c("Control", "Trial 1"),
      control_vs_trial2 = c("Control", "Trial 2"),
      control_vs_trial3 = c("Control", "Trial 3"),
      control_vs_trial4 = c("Control", "Trial 4"),
      control_vs_trial5 = c("Control", "Trial 5"),
      control_vs_trial6 = c("Control", "Trial 6")
    )
  ),

  # ─── 7. REPORT OPTIONS ───────────────────────────────────────────────────
  report_options = list(

    # Output formats for the Quarto report.
    # Options: "html", "docx", "pdf"
    # Note: "pdf" requires LaTeX / TinyTeX (install with tinytex::install_tinytex()).
    output_formats = c("html", "docx")
  )
)

# ==========================================================================
# LAUNCH — do not edit below this line
# ==========================================================================

source(here::here("R", "core_engine.R"))
run_sensanalyser_pipeline(config)
