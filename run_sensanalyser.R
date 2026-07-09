# ==========================================================================
# RUN SENSANALYSER
# ==========================================================================
#
# The only file you run. Everything you configure lives in the project's
# own settings.yaml — nothing to edit here except which project(s) to run.
#
# How to use (Positron / RStudio):
#   1. Put your data files in  projects/<your project>/data/raw/
#   2. Open and edit          projects/<your project>/settings.yaml
#   3. Press Ctrl+Shift+Enter (Run All).
#
# Useful in the console:
#   settings_summary("projects/example_study")   # what will run, and what
#                                                # differs from the defaults
#   create_project("projects/my_new_study")      # new project folder
# ==========================================================================

source(here::here("R", "load_sensanalyser.R"))

run_project("projects/example_study")


# ── Other things you can do (uncomment and run a single line) ──────────────

# Run several projects one after another:
# run_projects(c("projects/example_study", "projects/example_study_b"))

# See what a project will do before running it (non-default values highlighted):
# settings_summary("projects/example_study")

# Create a new, empty project (just a settings.yaml to edit):
# create_project("projects/my_new_study")

# Start a project over from scratch: deletes all outputs, cleaned data and
# reports, then the next run asks for the raw files and variables again.
# Your data/raw and your tuned settings (model, labels, subsets) are kept.
# reset_project("projects/example_study")
# reset_project("projects/example_study", full = TRUE)   # also reset every setting

# Convert an old project (project_config.R) to settings.yaml, once:
# migrate_project("projects/your_project")
