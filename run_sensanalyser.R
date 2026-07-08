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

# Batch run:
# run_projects(c("projects/example_study", "projects/example_study_b"))
