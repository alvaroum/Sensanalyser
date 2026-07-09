# Sensanalyser

Sensanalyser is a reusable R workflow for sensory data analysis. It uses a **Hub and Spoke** architecture, allowing you to manage multiple distinct client datasets and analysis pipelines from a single central engine, without mixing data or outputs.

## Architecture

*   **The Hub (Root Directory):** Contains the core engine (`R/`), standard templates (`templates/`), and the launcher (`run_sensanalyser.R`).
*   **The Spokes (`projects/`):** Each dataset gets its own isolated folder. All raw data, outputs, diagnostics, and reports for a project stay within it, and **everything you configure lives in that project's single `settings.yaml`**. A project folder is self-contained: you can copy or move it and it still runs.

## Quick start

Everything a project needs is one file — `settings.yaml` — and you launch it with one line. Works in Positron or RStudio; no app to install.

### 1. Create a project

```r
source("R/load_sensanalyser.R")
create_project("projects/my_study")
```

This builds the project folders and drops in a fully commented `settings.yaml`.

### 2. Add your data and edit `settings.yaml`

Copy your data files (`.csv`, `.tsv`, `.xlsx`, ...) into `projects/my_study/data/raw/`, then open `projects/my_study/settings.yaml`. Every option is documented inline; an empty file already runs a sensible analysis. A minimal example:

```yaml
data:
  files: auto            # every file in data/raw, or list them explicitly
variables:
  attributes: auto       # auto-detect the numeric attribute columns
  product: product
  panelist: user
model:
  type: linear_mixed_model
  random_effects: [assessor]
multivariate:
  hcpc:
    clusters: click      # auto | click (cut the dendrogram) | a number
outputs:
  figures:               # choose which figures to save, per analysis
    spider: true
    pca: true
    hcpc: true
    mfa: false
subsets:
  without_control:
    exclude: [Control]   # re-runs the whole analysis without these products
```

Before running, see exactly what a project will do — with every value that differs from the defaults highlighted:

```r
settings_summary("projects/my_study")
```

### 3. Run it

Open `run_sensanalyser.R`, point it at your project, and press **Run All** (Ctrl+Shift+Enter):

```r
source("R/load_sensanalyser.R")
run_project("projects/my_study")
# run_projects(c("projects/a", "projects/b"))   # several, in sequence
```

That's it. Outputs land in `projects/my_study/outputs/` and never overwrite another project's.

### Starting a project over

To wipe a project's results and set it up again from scratch — re-selecting the raw data files and variables as if it were brand new:

```r
source("R/load_sensanalyser.R")
reset_project("projects/my_study")           # keeps your model, labels, subsets
reset_project("projects/my_study", full = TRUE)   # also resets every setting
```

This deletes all outputs, cleaned data and rendered reports, then makes the next `run_project()` prompt you for the files and variables again. Your raw data in `data/raw/` is never touched.

### Coming from an older project?

Projects that still use `project_config.R` and scattered dictionary YAMLs can be converted to a single `settings.yaml` in one call (originals are kept as `*.migrated`, nothing is deleted):

```r
source("R/load_sensanalyser.R")
migrate_project("projects/my_old_project")
```

> **What lives where.** You edit only `settings.yaml`. Files Sensanalyser maintains itself (resolved run record, product-split decisions) live in `data/dictionary/state/` — you never touch them. The statistical model presets and the report template are engine assets read from `templates/`; drop your own copy into the project only if you want to customise one.

---

## Phase Breakdown

Sensanalyser executes a sequential, deterministic pipeline. For a detailed breakdown of the models, mathematical formulas, and specific R packages powering these analytical phases, please refer to the **[Statistical Methods Documentation](STATISTICAL_METHODS.md)**.

The major phases currently implemented are:

### Phase 2: Data Import & Variable Selection
Data import supports `.csv`, `.tsv`, `.txt`, `.xlsx`, and `.xls` files. Multiple files with the same structure are automatically combined using `dplyr::bind_rows`, keeping a trace of their origin. Variables are validated and assigned appropriate types based on the project configuration.

### Phase 3: Outlier Detection
Outlier detection and policy application are managed via global toggles and dictionary presets.
Diagnostics are written to `outputs/diagnostics/`. If `apply_outlier_policy = FALSE`, the pipeline detects outliers but leaves the dataset intact.

### Phase 4: Descriptives
Generates formatted long and wide tables (including mean ± SE) written directly to your project's `outputs/tables/` folder. Display labels come from the `labels:` section of `settings.yaml`.

### Phase 5: Statistical Models
Supported model routes include:
- Between-subject ANOVA (`rstatix::anova_test`)
- Repeated-measures ANOVA (`afex::aov_car`)
- Linear mixed models (`lmerTest::lmer`)

### Phase 6: Post-hoc Analyses
Post-hoc comparisons (e.g., Tukey, Bonferroni) are generated based on significant terms from the models. Interaction terms (like `product|replica`) are fully supported. Outputs include pairwise test tables and compact significance letters ready for reporting.

### Phase 8 & 9: Multivariate Analysis and Reporting
Phase 8 covers multivariate outputs (PCA, HCPC, MFA) and figure generation. **Hierarchical Clustering (HCPC)** now fully supports *interactive mode*, where you can click directly on the generated dendrogram to slice your product clusters. Phase 9 binds all outputs into a structured Quarto manuscript report within your project's `reports/` folder.

---

## Installing dependencies

If the engine complains about missing packages, run:

```r
source("R/00_install_dependencies.R")
sensanalyser_install_dependencies(categories = "all")
```

## Legacy Files

`master_mission_control.R` and the older per-project `project_config.R` still work but are deprecated: `master_mission_control.R` now just forwards to `run_sensanalyser.R`, and any project without a `settings.yaml` falls back to its `project_config.R`. Convert old projects with `migrate_project()` (see Quick start). Older single-folder scripts are kept for reference in `archive/`.
