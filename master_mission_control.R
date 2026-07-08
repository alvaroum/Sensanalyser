# ==========================================================================
# MASTER MISSION CONTROL (The Hub)
# ==========================================================================
#
# Purpose:
#   This is the central command script for Sensanalyser. It allows you to
#   run one or multiple projects sequentially.
#
# How to run:
#   1. Press Ctrl+Shift+Enter (or Run All). Missing packages are installed
#      automatically before anything else runs.
#   2. Set the active projects you want to run in `active_projects`.
#   3. Adjust `global_toggles` if you want to override default behavior
#      across all projects.
#   4. To RENAME variables or factor levels, edit the `data/dictionary/renaming_dictionary.yaml`
#      inside the specific project's folder.
#
# ==========================================================================

# ─── 0. INSTALL / CHECK PACKAGES ─────────────────────────────────────────────
# source(file.path("R", "00_install_dependencies.R"))
# sensanalyser_install_dependencies(ask_user = FALSE)

library(here)

# ─── 1. CREATE NEW PROJECT ──────────────────────────────────────────────────
# To create a brand new project workspace, uncomment the two lines below, 
# set your desired project name, and run them.
#
# source(here::here("R", "functions", "project_helpers.R"))
# sensanalyser_create_project("projects/example_study")


# ─── 2. ACTIVE PROJECTS ───────────────────────────────────────────────────
# List the paths to the project folders you want to analyze.
# You can list just one, or multiple for a batch run.
active_projects <- c(
  "projects/example_study"
)

# ─── 3. GLOBAL TOGGLES ────────────────────────────────────────────────────
# These toggles apply to all projects in the run loop unless explicitly
# overridden in the specific project_config.R.
global_toggles <- list(
  
  # Outlier handling
  run_outlier_detection = TRUE,
  apply_outlier_policy  = TRUE,
  
  # Descriptives and models
  run_descriptives = TRUE,
  run_anova_models = FALSE,
  run_mixed_models = TRUE,
  run_posthoc      = FALSE,
  
  # Multivariate analyses
  run_pca  = TRUE,
  run_mfa  = FALSE,
  run_hcpc = TRUE,
  
  # Output generation
  create_tables  = TRUE,
  create_figures = TRUE,
  render_quarto_report = FALSE
)

# ─── 4. EXECUTION LOOP ────────────────────────────────────────────────────
# Do not edit below this line.

source(here::here("R", "core_engine.R"))
source(here::here("R", "functions", "project_helpers.R"))

for (project_dir in active_projects) {

  message("\n==========================================================================")
  message(sprintf("🚀 LAUNCHING SENSANALYSER FOR: %s", project_dir))
  message("==========================================================================\n")

  sensanalyser_run_project(
    project_dir = project_dir,
    global_toggles = global_toggles
  )
}
