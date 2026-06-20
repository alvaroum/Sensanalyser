# Sensanalyser

Sensanalyser is a reusable R workflow for sensory data analysis. It uses a **Hub and Spoke** architecture, allowing you to manage multiple distinct client datasets and analysis pipelines from a single central engine, without mixing data or outputs.

## Architecture

*   **The Hub (Root Directory):** Contains the core engine (`R/`), standard templates (`templates/`), and the batch execution script (`master_mission_control.R`).
*   **The Spokes (`projects/`):** Each dataset or client gets its own isolated folder. All raw data, outputs, diagnostic logs, and report documents for a project stay within its folder.

## How to run

### 1. Create a New Project

You can create a new project workspace by running the helper function in the R console:

```r
source("R/functions/project_helpers.R")
sensanalyser_create_project("projects/my_new_project")
```

This will safely build out the required subdirectories (`data/`, `outputs/`, `reports/`) and copy the baseline templates (like `project_config.R` and the dictionaries) into the new folder.

### 2. Configure Your Project

Navigate into your new project folder (`projects/my_new_project/`) and open `project_config.R`. 
Here, you can specify your raw data files and analysis parameters.

**Multi-file Data Loading:** You can provide a vector of files if you want them combined automatically before analysis.
```r
project_config <- list(
  paths = list(
    raw_data = c("data/raw/batch_1.csv", "data/raw/batch_2.csv")
  ),
  analysis = list(
    dependent_variables = "auto",
    factors = c("product"),
    subject_id = "assessor",
    model_type = "linear_mixed_model"
  )
)
```
*(If `raw_data = NULL`, Sensanalyser will prompt you to select the files interactively).*

### 3. Launch from Master Mission Control

Open `master_mission_control.R` at the root of the repository.
Add your project to the `active_projects` list:

```r
active_projects <- c(
  "projects/my_new_project"
  # You can list multiple projects here to run them sequentially!
)
```

You can toggle which analysis phases run globally inside `master_mission_control.R`.
Press **Run All** (Ctrl+Shift+Enter) to execute the pipeline.

---

## Phase Breakdown

Sensanalyser executes a sequential, deterministic pipeline. The major phases currently implemented are:

### Phase 2: Data Import & Variable Selection
Data import supports `.csv`, `.tsv`, `.txt`, `.xlsx`, and `.xls` files. Multiple files with the same structure are automatically combined using `dplyr::bind_rows`, keeping a trace of their origin. Variables are validated and assigned appropriate types based on the project configuration.

### Phase 3: Outlier Detection
Outlier detection and policy application are managed via global toggles and dictionary presets.
Diagnostics are written to `outputs/diagnostics/`. If `apply_outlier_policy = FALSE`, the pipeline detects outliers but leaves the dataset intact.

### Phase 4: Descriptives
Generates formatted long and wide tables (including mean ± SE) written directly to your project's `outputs/tables/` folder. Display labels are automatically resolved using `data/dictionary/renaming_dictionary.yaml`.

### Phase 5: Statistical Models
Supported model routes include:
- Between-subject ANOVA (`rstatix::anova_test`)
- Repeated-measures ANOVA (`afex::aov_car`)
- Linear mixed models (`lmerTest::lmer`)

### Phase 6: Post-hoc Analyses
Post-hoc comparisons (e.g., Tukey, Bonferroni) are generated based on significant terms from the models. Interaction terms (like `product|replica`) are fully supported. Outputs include pairwise test tables and compact significance letters ready for reporting.

### Phase 8 & 9: (Under ongoing refinement)
Phase 8 covers multivariate outputs (PCA, HCPC, MFA) and figure generation. Phase 9 binds all outputs into a structured Quarto manuscript report within your project's `reports/` folder.

---

## Installing dependencies

If the engine complains about missing packages, run:

```r
source("R/00_install_dependencies.R")
sensanalyser_install_dependencies(categories = "all")
```

## Legacy Files

Old scripts from the single-folder architecture have been retained for reference in the `archive/` folder, but are no longer executed by the main pipeline.
