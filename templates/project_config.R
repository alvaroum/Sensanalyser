# ==========================================================================
# PROJECT-SPECIFIC CONFIGURATION
# ==========================================================================
#
# Purpose:
#   This file contains the specific analysis settings for this dataset.
#   It is loaded by the `master_mission_control.R` script.
#
# ==========================================================================

project_config <- list(

  # ─── 1. OVERRIDE GLOBAL TOGGLES (Optional) ──────────────────────────────
  # You can override toggles from master_mission_control.R here.
  toggles = list(
    # Start in interactive setup mode so the pipeline asks you to select your
    # data files and configure the analysis on first run.
    # Once the project is configured, you can set this to FALSE (or remove it)
    # to re-run without prompts using the saved analysis_config.yaml.
    interactive_setup = TRUE
  ),

  # ─── 2. DATA FILES ────────────────────────────────────────────────────────
  paths = list(
    # You can specify a single file, multiple files, or leave NULL to select interactively.
    # To analyse multiple files together, use a vector:
    # raw_data = c("data/raw/batch1.csv", "data/raw/batch2.csv")
    raw_data = NULL
  ),

  # ─── 3. ANALYSIS SETTINGS ────────────────────────────────────────────────
  # 👉 To RENAME variables or factor levels in your final tables and plots,
  #    edit the `data/dictionary/renaming_dictionary.yaml` file in this project.
  # 👉 To REMOVE/EXCLUDE variables from the analysis, either list only the ones 
  #    you want to keep in `dependent_variables` below, or set it to NULL and 
  #    exclude them using the interactive prompt.
  analysis = list(
    # Dependent variables (sensory attributes to analyse).
    # "auto" detects all numeric columns not used as factors.
    # Set to NULL to be prompted interactively.
    dependent_variables = NULL,

    # Fixed factors (independent variables, e.g. product, treatment).
    # Set to NULL to be prompted interactively.
    factors = NULL,

    # Panelist / assessor / subject column name.
    # Set to NULL to be prompted interactively.
    subject_id = "assessor",

    # Repeated-measures factors.
    # Set to NULL to be prompted interactively.
    repeated_measures_factors = NULL,

    # Random effects (for mixed models).
    # Set to NULL to be prompted interactively.
    random_effects = c("assessor"),

    # Model type. Options: 
    # one_way_anova, two_way_anova, three_way_anova, linear_mixed_model, etc.
    model_type = "linear_mixed_model",

    # Number of clusters for Hierarchical Clustering (HCPC).
    # - "auto" (or -1) defaults to automatic selection by FactoMineR.
    # - an integer > 1 to force a specific number of clusters.
    # - 0 to interactively click on the dendrogram plot to cut the tree.
    hcpc_n_clusters = "auto"
  ),

  # ─── 4. PRODUCT SUBSETS ──────────────────────────────────────────────────
  # Define named product subsets to analyse separately. Each subset runs the
  # full pipeline on a filtered dataset and writes its outputs to a dedicated
  # subfolder (e.g. outputs/tables/without_control/) so results never
  # overwrite the main analysis. Requires the main analysis to have run first
  # (its analysis_config.yaml is used to keep variable selections consistent).
  #
  # Use `exclude` to drop specific products, or `include` to keep only those listed.
  # product_subsets = list(
  #   without_control = list(
  #     exclude = c("Control")
  #   ),
  #   treated_only = list(
  #     include = c("Treatment A", "Treatment B", "Treatment C")
  #   )
  # ),

  # ─── 5. DERIVED ATTRIBUTE OPTIONS ────────────────────────────────────────
  # Only relevant when toggles$create_derived_attributes = TRUE.
  # Define derived variables in data/dictionary/derived_attributes.yaml.
  # derived_attribute_options = list(
  #
  #   # Rounding precision for derived values. NULL = no rounding.
  #   digits = NULL,
  #
  #   # Subfolder name appended to outputs/tables/ and outputs/figures/ for this
  #   # run, so derived-attribute outputs do not overwrite regular analysis files.
  #   # Example: output_label = "derived_attributes"
  #   output_label = NULL
  # ),

  # ─── 6. FIGURE OPTIONS ───────────────────────────────────────────────────
  fig_options = list(
    # Spider plot comparisons
    spider_comparisons = list(
      # all_products = NULL
    )
  )
)

# Return the list so it can be captured by source()
project_config
