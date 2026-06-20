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
    # e.g., run_mfa = TRUE
  ),

  # ─── 2. DATA FILES ────────────────────────────────────────────────────────
  paths = list(
    # You can specify a single file, multiple files, or leave NULL to select interactively.
    # To analyse multiple files together, use a vector:
    # raw_data = c("data/raw/batch1.csv", "data/raw/batch2.csv")
    raw_data = NULL
  ),

  # ─── 3. ANALYSIS SETTINGS ────────────────────────────────────────────────
  analysis = list(
    # Dependent variables (sensory attributes to analyse).
    # "auto" detects all numeric columns not used as factors.
    # Set to NULL to be prompted interactively.
    dependent_variables = "auto",

    # Fixed factors (independent variables, e.g. product, treatment).
    # Set to NULL to be prompted interactively.
    factors = c("product"),

    # Panelist / assessor / subject column name.
    # Set to NULL to be prompted interactively.
    subject_id = "assessor",

    # Repeated-measures factors.
    # Set to NULL to be prompted interactively.
    repeated_measures_factors = c("product"),

    # Random effects (for mixed models).
    # Set to NULL to be prompted interactively.
    random_effects = c("assessor"),

    # Model type. Options: 
    # one_way_anova, two_way_anova, three_way_anova, linear_mixed_model, etc.
    model_type = "linear_mixed_model"
  ),

  # ─── 4. FIGURE OPTIONS ───────────────────────────────────────────────────
  fig_options = list(
    # Spider plot comparisons
    spider_comparisons = list(
      # all_products = NULL
    )
  )
)

# Return the list so it can be captured by source()
project_config
