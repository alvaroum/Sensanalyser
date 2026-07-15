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

# ── First run: install any missing packages (pure base R, no dependencies) ──
# Locate the engine bootstrap by walking up from the working directory, so this
# works even in a brand-new R install where `here` is not available yet.
local({
  root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  while (!file.exists(file.path(root, "engine", "R", "00_bootstrap.R")) &&
         !identical(dirname(root), root)) {
    root <- dirname(root)
  }
  bootstrap <- file.path(root, "engine", "R", "00_bootstrap.R")
  if (!file.exists(bootstrap)) {
    stop("Could not find engine/R/00_bootstrap.R. Open the Sensanalyser ",
         "project (its .Rproj) or setwd() to the project folder, then run again.",
         call. = FALSE)
  }
  source(bootstrap)
  if (!isTRUE(sensanalyser_install_all(root = root))) {
    stop("Required packages are missing, so Sensanalyser cannot start. ",
         "See the messages above.", call. = FALSE)
  }
})

# Packages are guaranteed present from here on.
source(here::here("engine", "R", "load_sensanalyser.R"))

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
