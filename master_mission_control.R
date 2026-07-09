# ==========================================================================
# MASTER MISSION CONTROL  (deprecated - use run_sensanalyser.R)
# ==========================================================================
#
# Sensanalyser no longer keeps run settings in this file. Everything a
# project needs now lives in that project's own settings.yaml, and projects
# are launched from run_sensanalyser.R:
#
#   source(here::here("R", "load_sensanalyser.R"))
#   run_project("projects/example_study")
#
# If you have an older project that still uses project_config.R, convert it
# once with:
#
#   source(here::here("R", "load_sensanalyser.R"))
#   migrate_project("projects/your_project")   # writes settings.yaml
#
# This shim keeps existing muscle memory working: running it just forwards to
# run_sensanalyser.R. It will be removed in a future version.
# ==========================================================================

message("master_mission_control.R is deprecated - use run_sensanalyser.R. Forwarding...")
source(here::here("run_sensanalyser.R"))
