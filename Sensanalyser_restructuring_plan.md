# Sensanalyser restructuring plan

## Purpose

This note defines a phased plan to turn the current Sensanalyser template scripts into a reusable analysis project. The target is a structure similar to `../2026-024`, with a central `mission_control.R`, modular helper functions, configurable raw-data selection, selectable statistical models, outlier handling options, post-hoc options, manuscript-style tables, and a Quarto report that can later support AI-assisted interpretation.

The current Sensanalyser folder contains several useful but dataset-specific scripts:

- `ANOVA.R`
- `Descriptive.R`
- `Spider plots script.R`
- `descriptives_spiderplots.R`
- `outliers_identification.R`
- `pca.R`
- `mfa.R`
- `01. raw_data/Raw.data.sting.csv`
- `01. raw_data/Raw.data.sting.xlsx`

The goal is not to discard these scripts, but to extract their reusable logic into documented functions and keep the old versions as archived references.

---

## Target principles

1. **One main entry point**  
   The user should normally run only `mission_control.R`.

2. **Reusable across datasets**  
   Raw data, dependent variables, factors, subject/panelist columns, model type, post-hoc method, and outlier policy should be configurable without editing core functions.

3. **Project structure modelled on `2026-024`**  
   Use separate folders for raw data, processed data, dictionaries/configuration, functions, outputs, and reports.

4. **Fully commented and explained code**  
   Every function must include roxygen-style comments explaining purpose, inputs, outputs, assumptions, and examples where useful. Important processing blocks must include plain-language inline comments.

5. **Interactive and reproducible modes**  
   The pipeline should support both:
   - interactive selection using dialogs or console prompts;
   - reproducible non-interactive runs using configuration files.

6. **Analysis transparency**  
   Every run should save its selected data file, variables, factors, model choices, outlier policy, post-hoc settings, and package versions.

7. **Report-ready outputs**  
   Tables should be created in the same spirit as the `2026-024` outputs, especially long descriptives, wide manuscript tables, ANOVA tables, post-hoc tables, and detailed cell-means tables.

8. **AI-ready reporting**  
   The Quarto report should include structured sections and machine-readable result tables so that an AI agent can generate or revise interpretation text without touching the statistical code.

---

## Proposed folder structure

```text
Sensanalyser/
├── Sensanalyser.Rproj
├── mission_control.R
├── README.md
├── Sensanalyser_restructuring_plan.md
├── .gitignore
│
├── R/
│   ├── 00_initialise_project_structure.R
│   ├── 00_install_dependencies.R
│   ├── 00_setup.R
│   ├── core_engine.R
│   └── functions/
│       ├── package_list.R
│       ├── project_helpers.R
│       ├── data_import_helpers.R
│       ├── variable_selection_helpers.R
│       ├── outlier_helpers.R
│       ├── descriptive_helpers.R
│       ├── model_helpers.R
│       ├── posthoc_helpers.R
│       ├── table_helpers.R
│       ├── figure_helpers.R
│       ├── pca_helpers.R
│       ├── mfa_helpers.R
│       └── report_helpers.R
│
├── data/
│   ├── raw/
│   ├── processed/
│   └── dictionary/
│       ├── analysis_config.yaml
│       ├── renaming_dictionary.yaml
│       └── model_presets.yaml
│
├── outputs/
│   ├── tables/
│   ├── figures/
│   ├── diagnostics/
│   └── logs/
│
├── reports/
│   ├── sensanalyser_results_report.qmd
│   └── ai_summary_prompt.md
│
└── archive/
    ├── ANOVA.R
    ├── Descriptive.R
    ├── Spider plots script.R
    ├── descriptives_spiderplots.R
    ├── outliers_identification.R
    ├── pca.R
    └── mfa.R
```

---

## Proposed `mission_control.R` design

The mission control file should mirror the logic of `../2026-024/mission_control.R`, but be more general because Sensanalyser will be a reusable template rather than a single fixed project.

Example structure:

```r
config <- list(
  paths = list(
    raw_data = NULL,                         # NULL means ask user to choose file
    analysis_config = "data/dictionary/analysis_config.yaml",
    renaming_dictionary = "data/dictionary/renaming_dictionary.yaml",
    model_presets = "data/dictionary/model_presets.yaml",
    table_root = "outputs/tables",
    figure_root = "outputs/figures",
    diagnostics_root = "outputs/diagnostics",
    report_template = "reports/sensanalyser_results_report.qmd"
  ),

  toggles = list(
    interactive_setup = TRUE,
    discover_variables = TRUE,
    run_outlier_detection = TRUE,
    apply_outlier_policy = TRUE,
    run_descriptives = TRUE,
    run_anova_models = TRUE,
    run_mixed_models = FALSE,
    run_posthoc = TRUE,
    run_pca = FALSE,
    run_mfa = FALSE,
    create_tables = TRUE,
    create_figures = TRUE,
    render_quarto_report = FALSE
  ),

  analysis = list(
    dependent_variables = NULL,              # NULL means select interactively or infer from config
    factors = NULL,
    subject_id = NULL,
    repeated_measures_factors = NULL,
    random_effects = NULL,
    model_type = "two_way_anova",
    posthoc_method = "tukey",
    posthoc_focal_terms = NULL,
    outlier_policy = "remove_extreme",       # keep_all, remove_extreme, remove_all
    alpha = 0.05
  ),

  table_options = list(
    digits = 1,
    include_mean_se = TRUE,
    include_letters = TRUE
  )
)

source(here::here("R", "core_engine.R"))
run_sensanalyser_pipeline(config)
```

---

## Phase 1 — Project setup and safe archiving

### Objective
Create the new project skeleton without breaking the existing template scripts.

### Tasks

1. Create the new folder structure shown above.
2. Move existing scripts into `archive/` after confirming they are copied safely.
3. Create `Sensanalyser.Rproj` if it does not yet exist.
4. Create `.gitignore` for common R, Quarto, cache, and output artefacts.
5. Create `R/00_initialise_project_structure.R` to recreate missing folders.
6. Create `R/functions/package_list.R` with required packages.
7. Create `R/00_install_dependencies.R` and `R/00_setup.R`.

### Required packages to consider

Core packages:

- `tidyverse`
- `here`
- `cli`
- `yaml`
- `readr`
- `readxl`
- `writexl`
- `janitor`
- `rlang`
- `glue`

Statistics:

- `rstatix`
- `emmeans`
- `multcomp`
- `agricolae`
- `lme4`
- `lmerTest`
- `afex`
- `performance`
- `broom`
- `broom.mixed`

Sensory and multivariate analysis:

- `FactoMineR`
- `factoextra`
- `SensoMineR`
- `fmsb`

Interaction/reporting:

- `svDialogs` or an alternative file/dialog package
- `quarto`
- `knitr`
- `gt` or `flextable`

### Deliverables

- New Sensanalyser structure.
- Archived legacy scripts.
- Setup scripts that can load all required packages.

### Validation

- Running `source("R/00_setup.R")` loads packages without errors.
- Folder creation script can be rerun safely.

---

## Phase 2 — Data import and variable selection

### Objective
Replace hardcoded filenames and column ranges with reusable data import and variable selection functions.

### Tasks

1. Create `data_import_helpers.R`.
2. Support at least `.csv`, `.tsv`, `.xlsx`, and `.xls` files.
3. Support importing and binding multiple raw data files that share the same column structure, so they can be analysed together when necessary.
4. Add interactive file selection when `config$paths$raw_data` is `NULL` (supporting single or multiple file selection).
5. Save the selected raw-data path(s) into a run log.
5. Create `variable_selection_helpers.R`.
6. Allow the user to select:
   - dependent variables;
   - fixed factors;
   - subject/panelist column;
   - repeated-measures factors;
   - optional blocking factors;
   - optional covariates.
7. Save selections to `data/dictionary/analysis_config.yaml` so the next run can be reproduced without dialog selection.
8. Add a `discover_variables` mode that prints:
   - all column names;
   - detected numeric variables;
   - detected categorical variables;
   - unique levels per factor;
   - missing-value counts.

### Design decisions

- Interactive selection should be useful for first-time setup.
- YAML configuration should be the default for final, reproducible analyses.
- The code should never assume that dependent variables begin at a fixed column index.

### Deliverables

- `load_sensanalyser_data()`
- `select_analysis_variables()`
- `write_analysis_config()`
- `read_analysis_config()`
- `discover_dataset_structure()`

### Validation

- The current `Raw.data.sting.csv` can be selected interactively.
- The same run can be repeated from the saved YAML config without dialogs.

---

## Phase 3 — Outlier detection and outlier policy

### Objective
Generalise `outliers_identification.R` so outliers can be detected and then either kept, removed only if extreme, or removed if any outlier.

### Tasks

1. Create `outlier_helpers.R`.
2. Use `rstatix::identify_outliers()` or a wrapper around it.
3. Detect outliers per dependent variable and grouping factor combination.
4. Store all outlier information in a long table.
5. Implement three outlier policies:
   - `keep_all`: detect and report outliers but do not modify data;
   - `remove_extreme`: set only extreme outliers to `NA` or remove rows, depending on config;
   - `remove_all`: set all detected outliers to `NA` or remove rows, depending on config.
6. Add an explicit option for how to remove values:
   - `set_na`: replace only the specific outlying DV value with `NA`;
   - `drop_row`: remove the full row if any selected DV is an outlier.
7. Save both:
   - `outputs/diagnostics/outliers_all.csv`;
   - `outputs/diagnostics/outlier_policy_applied.csv`.

### Deliverables

- `identify_sensory_outliers()`
- `apply_outlier_policy()`
- `summarise_outlier_decisions()`

### Validation

- The new function should reproduce the logic of the old script when using `remove_extreme` and grouping by the same independent variable.
- Output tables should clearly show which values were kept or removed.

---

## Phase 4 — Descriptives and sensory profile tables

### Objective
Generalise the descriptive tables currently created in `Descriptive.R` and `descriptives_spiderplots.R`.

### Tasks

1. Create `descriptive_helpers.R`.
2. Create long descriptives for each dependent variable by selected grouping factors.
3. Create wide descriptives with outcomes as columns.
4. Create manuscript-style tables using formatted `mean ± SE`.
5. Allow grouping by one or more factors.
6. Allow optional display-name conversion using `renaming_dictionary.yaml`.

### Deliverables

- `create_descriptives_long()`
- `create_descriptives_wide_outcomes()`
- `create_descriptives_wide_outcomes_means()`
- `create_profile_table()`

### Output files

- `outputs/tables/descriptives_long.csv`
- `outputs/tables/descriptives_wide_mean_se.csv`
- `outputs/tables/descriptives_wide_means_only.csv`

### Validation

- The output should match the intent of the existing descriptive scripts but work with any selected grouping factors and DVs.

---

## Phase 5 — Statistical model engine

### Objective
Create a model engine that supports one-way, two-way, three-way ANOVAs, repeated-measures ANOVAs, and linear mixed models.

### Tasks

1. Create `model_helpers.R`.
2. Create model formula builders instead of manually typing formulas for every DV.
3. Support these model families:
   - one-way between-subjects ANOVA;
   - two-way between-subjects ANOVA;
   - three-way between-subjects ANOVA;
   - one-way repeated-measures ANOVA;
   - two-way repeated-measures ANOVA;
   - three-way repeated-measures ANOVA;
   - linear mixed model with configurable fixed and random effects.
4. Add model presets in `model_presets.yaml`.
5. Run the selected model for all selected dependent variables.
6. Save a standard ANOVA/model summary table.
7. Add error handling so one failed dependent variable does not stop the full pipeline.
8. Save model warnings and failed models to `outputs/diagnostics/model_warnings.csv`.

### Proposed model configuration examples

```yaml
one_way_anova:
  fixed_effects: [product]
  interactions: false
  repeated_measures: false
  engine: rstatix_anova_test

two_way_anova:
  fixed_effects: [product, age]
  interactions: true
  repeated_measures: false
  engine: rstatix_anova_test

three_way_anova:
  fixed_effects: [product, age, session]
  interactions: true
  repeated_measures: false
  engine: rstatix_anova_test

one_way_repeated:
  fixed_effects: [product]
  subject_id: assessor
  repeated_measures_factors: [product]
  engine: afex_aov_car

linear_mixed_model:
  fixed_effects: [product, age]
  interactions: true
  random_effects: [assessor]
  engine: lmerTest_lmer
```

### Deliverables

- `build_model_formula()`
- `run_model_for_outcome()`
- `run_model_suite()`
- `extract_model_summary()`
- `save_model_diagnostics()`

### Validation

- One-way, two-way, and three-way ANOVA examples should run on test data.
- Repeated-measures examples should correctly require a subject/panelist column.
- Mixed models should fail gracefully if random-effect columns are missing.

---

## Phase 6 — Post-hoc analysis engine

### Objective
Replace the fixed Fisher LSD workflow with selectable post-hoc methods.

### Tasks

1. Create `posthoc_helpers.R`.
2. Support at least:
   - Tukey;
   - Bonferroni;
   - Fisher LSD.
3. Decide implementation route:
   - Tukey and Bonferroni through `emmeans` where possible;
   - LSD through either `emmeans` with `adjust = "none"` or `agricolae::LSD.test()` when compact-letter output is needed.
4. Allow the user to select which model terms receive post-hoc tests.
5. Support post-hocs within levels of another factor when interactions are selected.
6. Save compact-letter tables and pairwise-comparison tables.
7. Suppress or flag post-hoc letters when the corresponding omnibus test is non-significant, following the cautious approach used in `2026-024`.

### Deliverables

- `run_posthoc_suite()`
- `run_emmeans_posthoc()`
- `run_lsd_posthoc()`
- `create_compact_letter_display()`
- `suppress_non_significant_letters()`

### Output files

- `outputs/tables/posthoc_pairwise.csv`
- `outputs/tables/posthoc_letters.csv`
- `outputs/tables/posthoc_method_summary.csv`

### Validation

- Tukey, Bonferroni, and LSD options produce distinguishable output.
- The selected post-hoc method is recorded in the run log and report.

---

## Phase 7 — Table system modelled on `2026-024`

### Objective
Create clean, report-ready output tables similar to those already generated in the `2026-024` project.

### Tasks

1. Create `table_helpers.R`.
2. Combine descriptives and post-hoc letters into manuscript-style tables.
3. Produce both long and wide tables.
4. Add optional display-name conversion through `renaming_dictionary.yaml`.
5. Include table names that are self-explanatory.
6. Avoid redundant outputs unless each table has a clear purpose.

### Core output tables

- `results_model.csv`  
  Full model/ANOVA results for every dependent variable.

- `results_posthoc_pairwise.csv`  
  Pairwise comparisons for selected terms.

- `results_posthoc_letters.csv`  
  Compact-letter displays.

- `descriptives_long.csv`  
  Raw means, SD, SE, and n for every selected grouping combination.

- `report_format_wide.csv`  
  Manuscript-style table with `mean ± SE` and optional compact letters.

- `run_configuration_summary.csv`  
  Data file, selected variables, factors, model type, outlier policy, and post-hoc method.

### Deliverables

- `create_manuscript_table_long()`
- `create_report_wide()`
- `write_analysis_tables()`
- `write_run_configuration_summary()`

### Validation

- Output tables should be usable directly in a report without manual reshaping.
- Tables should remain valid when there is one factor, two factors, or three factors.

---

## Phase 8 — Figures, spider plots, PCA, and MFA

### Objective
Modularise the plotting and multivariate-analysis scripts so they can be switched on or off from mission control.

### Tasks

1. Create `figure_helpers.R` for general figures and spider plots.
2. Create `pca_helpers.R` from reusable parts of `pca.R`.
3. Create `mfa_helpers.R` from reusable parts of `mfa.R`.
4. Generalise spider plots:
   - selectable product/sample factor;
   - selectable attributes;
   - top-n attributes option;
   - configurable scale minimum, maximum, and axis labels;
   - configurable colour palette.
5. Generalise PCA:
   - selectable grouping/product factor;
   - selectable DVs;
   - output eigenvalues, coordinates, plots, and product descriptions.
6. Generalise MFA:
   - configurable variable groups;
   - group names stored in YAML;
   - output plots and tables.

### Deliverables

- `create_spider_plot_data()`
- `plot_spider_profiles()`
- `run_sensory_pca()`
- `run_sensory_mfa()`

### Output folders

- `outputs/figures/spiderplots/`
- `outputs/figures/pca/`
- `outputs/figures/mfa/`
- `outputs/tables/pca/`
- `outputs/tables/mfa/`

### Validation

- Existing spider plot, PCA, and MFA examples should be reproducible using configuration rather than hardcoded file and column names.

---

## Phase 9 — Quarto report and AI summary workflow

### Objective
Create a reusable Quarto report similar to `2026-024/reports/2026-024_subset_results_report.qmd`, but adapted to Sensanalyser as a general analysis template.

### Tasks

1. Create `reports/sensanalyser_results_report.qmd`.
2. The report should read output tables from `outputs/tables/` rather than rerunning statistics.
3. Include sections for:
   - project and dataset information;
   - run configuration;
   - outlier summary;
   - descriptive summary;
   - model results;
   - post-hoc results;
   - manuscript-ready tables;
   - figures;
   - AI-assisted interpretation draft.
4. Create `reports/ai_summary_prompt.md` with instructions for an AI agent.
5. The AI prompt should ask the agent to interpret the already-generated tables, not invent results.
6. Add a placeholder section in the report where AI-generated interpretation can be pasted or updated.
7. Add rendering toggle in `mission_control.R`.

### Suggested AI-agent instruction

```markdown
You are helping interpret a sensory analysis report. Use only the result tables
stored in `outputs/tables/` and the figures in `outputs/figures/`. Do not infer
results that are not present in the tables. Write a concise results narrative
covering the strongest main effects, relevant interactions, outlier handling,
and practical sensory/product interpretation.
```

### Deliverables

- `reports/sensanalyser_results_report.qmd`
- `reports/ai_summary_prompt.md`
- Report render function in `report_helpers.R`

### Validation

- The report renders to HTML.
- Later, optional DOCX and PDF rendering can be added.

---

## Phase 10 — Project isolation and reusable workflow

### Objective
Turn Sensanalyser from a single working analysis folder into a reusable **pipeline/template** that can be applied to many independent client/project folders without mixing raw data, outputs, tables, figures, diagnostics, or rendered reports.

The key design decision is to keep one reusable Sensanalyser engine ("The Hub") and create a separate project workspace for every study ("The Spokes"). A central `master_mission_control.R` will act as a single command center, allowing you to run multiple projects in batch or individually.

```text
Sensanalyser/                         # reusable engine and templates (The Hub)
├── R/
│   ├── core_engine.R
│   └── functions/
├── templates/
│   ├── project_config.R
│   ├── data/dictionary/analysis_config.yaml
│   ├── data/dictionary/renaming_dictionary.yaml
│   ├── data/dictionary/model_presets.yaml
│   └── reports/sensanalyser_results_report.qmd
├── master_mission_control.R          # The single command center
└── README.md

projects/                             # isolated client/project workspaces (The Spokes)
├── 2026-025-client-project-a/        
│   ├── data/
│   ├── outputs/
│   ├── reports/
│   ├── project_config.R              # tiny file with project-specific variables/models
│   └── project_manifest.yaml
└── 2026-026-client-project-b/
    └── ...
```

Each project workspace must be self-contained for analysis inputs and outputs. The `master_mission_control.R` will iterate over a list of active projects, load their small `project_config.R` files, merge them with global toggles, and execute the core engine. The engine should provide functions, templates, and defaults, but it should never write project data into the engine folder.

### Design principles

1. **Engine/project separation**
   - `R/core_engine.R` and reusable helpers live in the Sensanalyser engine.
   - Raw data, project-specific dictionaries, outputs, figures, diagnostics, reports, and rendered files live in the active client/project folder.

2. **One project root per run**
   - Every run must resolve a single `project_root` before loading data or writing outputs.
   - All paths should be built from that root.
   - No helper should call `here("outputs", ...)` or write to a hardcoded root unless that root has been explicitly set.

3. **Template-based project creation**
   - A new project should be created from templates rather than by manually copying the current working folder.
   - Templates should include `mission_control.R`, dictionary YAML files, report templates, and empty folder scaffolding.

4. **Safe outputs by default**
   - The pipeline should refuse to write outputs if the project root cannot be identified.
   - The pipeline should create a run manifest and save all generated tables, figures, diagnostics, and reports under the active project folder.
   - Existing outputs should be either overwritten only with explicit permission or archived into timestamped run folders.

5. **Reusable reports**
   - `reports/sensanalyser_results_report.qmd` should become a parameterised template that reads from the active project folder.
   - Reports should support current executive outputs, including means-only tables, PCA correlation/individual graphs, and internal R&D client interpretation.
   - Rendering should create project-local outputs such as `reports/sensanalyser_results_report.html` and `reports/sensanalyser_results_report.docx`.

### Tasks

#### 10.1 Create project helper functions

Create `R/functions/project_helpers.R` with roxygen-documented functions:

- `sensanalyser_create_project(project_dir, project_id = NULL, project_name = NULL, client = NULL, template_root = NULL, overwrite = FALSE)`
  - Creates a new isolated project folder.
  - Creates standard subfolders: `data/raw`, `data/processed`, `data/dictionary`, `outputs/tables`, `outputs/figures`, `outputs/diagnostics`, `outputs/logs`, and `reports`.
  - Copies template config files and report files.
  - Writes `project_manifest.yaml`.
  - Refuses to overwrite an existing non-empty project unless `overwrite = TRUE`.

- `sensanalyser_resolve_project_root(project_dir = NULL, config = NULL)`
  - Finds the active project root from an explicit argument, config, `project_manifest.yaml`, or current working directory.
  - Fails with a clear error if no valid project root can be found.

- `sensanalyser_project_paths(project_root)`
  - Returns a named list of project-local paths for raw data, dictionaries, tables, figures, diagnostics, logs, and reports.

- `sensanalyser_validate_project(project_root)`
  - Checks that required folders and files exist.
  - Reports missing components with actionable messages.

- `sensanalyser_archive_existing_outputs(project_root, run_id = NULL)`
  - Optional helper to move existing `outputs/` and rendered reports into a timestamped archive before a new run.

#### 10.2 Add a project manifest

Every project should include `project_manifest.yaml`:

```yaml
project_id: 2026-025
project_name: New sensory project
client: Internal R&D client
created_at: 2026-06-09
sensanalyser_version: 0.10.0
status: draft
paths:
  raw_data: data/raw
  dictionaries: data/dictionary
  outputs: outputs
  reports: reports
notes:
  trial_identities: unknown
  target_profile: unknown
```

The manifest should be used for metadata and safety checks, not as a replacement for `analysis_config.yaml`.

#### 10.3 Move defaults into templates

Create a `templates/` folder containing clean starting versions of:

- `templates/project_config.R`
- `templates/data/dictionary/analysis_config.yaml`
- `templates/data/dictionary/renaming_dictionary.yaml`
- `templates/data/dictionary/model_presets.yaml`
- `templates/reports/sensanalyser_results_report.qmd`
- `templates/reports/ai_summary_prompt.md`

The current files may remain in the prototype project, but new projects should be created from `templates/`.

#### 10.4 Refactor path handling in the engine

Update `mission_control.R`, `R/core_engine.R`, and helper functions so that:

- `config$paths$project_root` is mandatory after initial resolution.
- All data input and output paths are generated through `sensanalyser_project_paths(project_root)`.
- Tables are written to `file.path(project_root, "outputs", "tables")`.
- Figures are written to `file.path(project_root, "outputs", "figures")`.
- Diagnostics are written to `file.path(project_root, "outputs", "diagnostics")`.
- Logs are written to `file.path(project_root, "outputs", "logs")`.
- Rendered reports are written to `file.path(project_root, "reports")`.

This is the most important technical safeguard against mixing results across projects.

#### 10.5 Parameterise Quarto reporting

Update `reports/sensanalyser_results_report.qmd` so it can be rendered with a project root parameter:

```yaml
params:
  project_root: null
  audience: "Internal R&D client"
  table_style: "means-only"
```

The report should:

- read tables from `params$project_root/outputs/tables`;
- read figures from `params$project_root/outputs/figures`;
- write HTML/DOCX into `params$project_root/reports`;
- avoid hardcoded references to the engine folder;
- preserve the current means-only executive table approach unless configured otherwise.

#### 10.6 Add project run wrapper

Create a high-level wrapper:

```r
sensanalyser_run_project <- function(project_dir, global_config = list()) {
  project_root <- sensanalyser_resolve_project_root(project_dir)
  sensanalyser_validate_project(project_root)
  # load project-local project_config.R
  # merge with global_config from master_mission_control.R
  # run_sensanalyser_pipeline(final_config)
}
```

This should become the engine used by `master_mission_control.R` to run specific projects.

#### 10.7 Add safety checks

Before running the pipeline, check that:

- the raw data file is inside the active project folder, or the user explicitly accepts an external path;
- output paths are inside the active project folder;
- the report template being rendered is either project-local or explicitly selected from the engine template folder;
- no previous project outputs are present unless this is an intentional rerun;
- the project manifest ID matches the configured project ID, if both exist.

#### 10.8 Add tests or validation scripts

Create a validation script such as `R/test_phase10.R` that checks:

1. A temporary project can be created from templates.
2. Required folders and files exist.
3. The project manifest is written and readable.
4. Project paths resolve inside the temporary project root.
5. The pipeline can run on a copied example dataset without writing into the engine folder.
6. The Quarto report renders into the temporary project `reports/` folder.
7. Re-running the same project either archives or safely overwrites outputs according to the configured policy.

### Deliverables

- `R/functions/project_helpers.R`
- `templates/` folder with reusable starter files
- Project-local `project_manifest.yaml` support
- Updated `mission_control.R`
- Updated `R/core_engine.R` path handling
- Parameterised `reports/sensanalyser_results_report.qmd`
- `sensanalyser_create_project()`
- `sensanalyser_run_project()`
- `R/test_phase10.R`
- Updated README draft notes explaining the new project-isolation workflow

### Validation

Phase 10 is complete when:

- a new project can be created with one function call;
- raw data, generated tables, figures, diagnostics, and reports are written only inside that project folder;
- two different projects can be run sequentially without shared outputs;
- the current example report can still be re-rendered successfully to `reports/sensanalyser_results_report.html` and `reports/sensanalyser_results_report.docx`;
- no project-specific paths remain hardcoded in `core_engine.R` or report helpers.

---

## Phase 11 — Documentation and README

### Objective
Write a thorough README after the code is implemented and tested, including the new project-isolation workflow introduced in Phase 10.

### README contents

The final `README.md` should include:

1. What Sensanalyser does.
2. Required engine and client/project folder structure.
3. Installation instructions.
4. How to create a new project using `sensanalyser_create_project()`.
5. How to run the first interactive analysis.
6. How to rerun a saved analysis configuration.
7. How to select raw data without mixing project files.
8. How to select dependent variables and factors.
9. Explanation of model types:
   - one-way ANOVA;
   - two-way ANOVA;
   - three-way ANOVA;
   - repeated-measures ANOVA;
   - linear mixed model.
10. Explanation of outlier policies:
   - keep all;
   - remove extreme only;
   - remove all outliers.
11. Explanation of post-hoc methods:
   - Tukey;
   - Bonferroni;
   - LSD.
12. Explanation of generated tables, including means-only executive tables.
13. Explanation of generated figures.
14. How to render the Quarto report.
15. How to use the AI summary prompt responsibly.
16. Troubleshooting section.
17. Example analysis workflows.
18. Notes on assumptions and limitations.

### Code documentation rule

Before the README is finalised, every function must be checked for:

- roxygen-style function header;
- clear parameter explanations;
- return-value explanation;
- inline comments for non-obvious logic;
- no hardcoded dataset names;
- no hardcoded column positions unless explicitly documented as an optional fallback;
- no hardcoded project-specific output paths.

### Deliverables

- Final `README.md`
- Optional `docs/` folder if the README becomes too long.

---

## Suggested implementation order

The safest order is:

1. Project structure and archiving.
2. Setup and package management.
3. Data import and variable selection.
4. Outlier engine.
5. Descriptives engine.
6. Model engine.
7. Post-hoc engine.
8. Table engine.
9. Figures, PCA, and MFA.
10. Quarto report.
11. Project isolation and reusable workflow.
12. README and final documentation.

This order ensures that each later component depends on already-tested earlier components.

---

## Testing strategy

Each phase should include a small validation script or test block. Minimum checks:

- selected raw data loads correctly;
- selected DVs are numeric;
- selected factors exist and are treated as factors;
- outlier policy changes only the intended values;
- model formulas are built correctly;
- ANOVA and mixed-model outputs contain expected columns;
- post-hoc method selection changes the adjustment method;
- tables are saved with stable filenames;
- Quarto report renders without re-running the full analysis;
- new client/project workspaces can be created and run without writing outputs into the engine folder.

A small example dataset should eventually be kept in `data/raw/` or `data/example/` so users can confirm the pipeline works after installation.

---

## Key design choices to confirm before implementation

1. Should outlier removal replace values with `NA` or remove full rows by default?
2. Should interactive dialogs use `svDialogs`, base `file.choose()`, or a console-only fallback?
3. Should the final report render to HTML only, or also DOCX/PDF by default?
4. Should PCA and MFA be part of the main pipeline or treated as optional advanced modules?
5. Should the default post-hoc engine use `emmeans` for all methods, with `agricolae::LSD.test()` only as an optional legacy-compatible route?
6. Should the project include a small example dataset for demonstrations and testing?

---

## Immediate next action

Start Phase 1 by creating the project skeleton, copying the current scripts into `archive/`, and adding setup files. After that, implement Phase 2 so the pipeline can load any raw data file and save the selected analysis configuration.
