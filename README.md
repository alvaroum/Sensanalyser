# Sensanalyser

Sensanalyser is being restructured into a reusable R workflow for sensory data analysis. The current implementation covers **Phase 1–6**: project scaffolding, safe archiving of legacy scripts, dependency management, reusable data import, dataset discovery, variable selection, YAML-based run configuration, configurable outlier detection/removal, descriptive/profile tables, statistical models, and selectable post-hoc analyses.

For the full phased plan, see [`Sensanalyser_restructuring_plan.md`](Sensanalyser_restructuring_plan.md).

## Current status

Implemented:

- `Sensanalyser.Rproj`
- `.gitignore`
- `mission_control.R`
- `R/00_initialise_project_structure.R`
- `R/00_install_dependencies.R`
- `R/00_setup.R`
- `R/core_engine.R`
- `R/functions/package_list.R`
- `R/functions/data_import_helpers.R`
- `R/functions/variable_selection_helpers.R`
- `R/functions/outlier_helpers.R`
- `R/functions/descriptive_helpers.R`
- `R/functions/model_helpers.R`
- `R/functions/posthoc_helpers.R`
- Standard folders for data, outputs, diagnostics, reports, and modular functions
- Legacy template scripts archived in `archive/`
- `data/dictionary/analysis_config.yaml`
- `data/dictionary/model_presets.yaml`
- `data/dictionary/renaming_dictionary.yaml`

## How to check the setup

Open the project in RStudio/Positron or run from the Sensanalyser root:

```r
source("R/00_setup.R")
```

This checks the folder structure, reports missing packages, loads available packages, and creates a `sensanalyser_setup_summary` object.

## Installing dependencies

If setup reports missing packages, run:

```r
source("R/00_install_dependencies.R")
sensanalyser_install_dependencies(categories = "all")
```

For non-interactive installation:

```r
source("R/00_install_dependencies.R")
sensanalyser_install_dependencies(categories = "all", ask_user = FALSE)
```

## Phase 2 usage

Data import supports `.csv`, `.tsv`, `.txt`, `.xlsx`, and `.xls` files:

```r
source("R/functions/data_import_helpers.R")
data <- load_sensanalyser_data("data/raw/Raw.data.sting.csv")
```

Dataset discovery and variable selection:

```r
source("R/functions/variable_selection_helpers.R")
discover_dataset_structure(data)
selections <- select_analysis_variables(data, config)
validate_variable_selections(data, selections)
```

## Phase 3 usage

Outlier detection and policy application are configured in `mission_control.R`:

```r
config$toggles$run_outlier_detection <- TRUE
config$toggles$apply_outlier_policy <- TRUE
config$analysis$outlier_policy <- "remove_extreme"      # keep_all, remove_extreme, remove_all
config$analysis$outlier_removal_action <- "set_na"      # set_na, drop_row
config$analysis$outlier_grouping_factors <- NULL         # NULL defaults to selected factors
```

Diagnostics are written to:

- `outputs/diagnostics/outliers_all.csv`
- `outputs/diagnostics/outlier_policy_applied.csv`
- `outputs/diagnostics/outlier_decision_summary.csv`

If `apply_outlier_policy = FALSE`, the pipeline still detects outliers and records what would have been targeted, but leaves the working dataset unchanged.

## Phase 4 usage

Descriptive tables are configured in `mission_control.R`:

```r
config$toggles$run_descriptives <- TRUE
config$analysis$descriptive_grouping_factors <- NULL  # NULL defaults to selected factors
```

Generated tables:

- `outputs/tables/descriptives_long.csv`
- `outputs/tables/descriptives_wide_mean_se.csv`
- `outputs/tables/descriptives_wide_means_only.csv`
- `outputs/tables/profile_table.csv`

Display labels are read from `data/dictionary/renaming_dictionary.yaml` when available.

## Phase 5 usage

Statistical models are configured in `mission_control.R`:

```r
config$toggles$run_anova_models <- TRUE
config$toggles$run_mixed_models <- FALSE
config$analysis$model_type <- "one_way_anova"          # see data/dictionary/model_presets.yaml
config$analysis$model_fixed_effects <- NULL             # NULL uses selected factors/preset defaults
```

Supported model routes now include:

- between-subject ANOVA through `rstatix::anova_test`
- repeated-measures ANOVA through `afex::aov_car`
- linear mixed models through `lmerTest::lmer`

Generated outputs:

- `outputs/tables/results_model.csv`
- `outputs/diagnostics/model_warnings.csv`

## Phase 6 usage

Post-hoc analyses are configured in `mission_control.R`:

```r
config$toggles$run_posthoc <- TRUE
config$analysis$posthoc_method <- "tukey"        # tukey, bonferroni, lsd
config$analysis$posthoc_focal_terms <- NULL      # NULL derives significant terms; or use c("product")
```

Interaction-style terms are supported:

- `product|replica` means compare product levels within each replica level.
- `product:replica` expands both directions: product within replica and replica within product.

Generated outputs:

- `outputs/tables/posthoc_pairwise.csv`
- `outputs/tables/posthoc_letters.csv`
- `outputs/tables/posthoc_method_summary.csv`

Letters are suppressed when the corresponding omnibus term is non-significant or unavailable.

## Archived legacy scripts

The original template scripts are preserved in `archive/`:

- `ANOVA.R`
- `Descriptive.R`
- `Spider plots script.R`
- `descriptives_spiderplots.R`
- `outliers_identification.R`
- `pca.R`
- `mfa.R`

The old raw-data examples are also archived, and copies are available in `data/raw/` for local testing. Raw data files are ignored by git by default.

## Next phase

Phase 7 will implement the final table system and manuscript-style table consolidation.
