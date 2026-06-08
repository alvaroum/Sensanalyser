# Sensanalyser Phase 1 — Quick Start Guide

Phase 1 creates the reusable Sensanalyser project scaffold. It does **not** yet run analyses; that starts in Phase 2 and later.

## What is included

- `Sensanalyser.Rproj`
- `.gitignore`
- `README.md`
- `R/00_initialise_project_structure.R`
- `R/00_install_dependencies.R`
- `R/00_setup.R`
- `R/functions/package_list.R`
- Standard folders for `data/`, `outputs/`, `reports/`, `archive/`, and modular R functions
- Legacy scripts moved out of the root and preserved in `archive/`
- Example raw files copied to `data/raw/` for local testing

## Run the setup check

From the Sensanalyser project root:

```r
source("R/00_setup.R")
```

Expected result after dependency installation:

- all required directories already exist;
- 32/32 dependencies are available;
- 32 packages load;
- `sensanalyser_setup_summary` is created.

## Install missing dependencies

If setup reports missing packages:

```r
source("R/00_install_dependencies.R")
sensanalyser_install_dependencies(categories = "all")
```

For a non-interactive run:

```r
source("R/00_install_dependencies.R")
sensanalyser_install_dependencies(categories = "all", ask_user = FALSE)
```

## Recreate missing folders

```r
source("R/00_initialise_project_structure.R")
sensanalyser_initialise_structure()
```

This function is idempotent: it can be rerun safely and will not overwrite existing files.

## Check package groups

```r
source("R/functions/package_list.R")
sensanalyser_get_package_list()
sensanalyser_get_packages_by_category("statistics")
sensanalyser_get_all_packages()
```

## Current validation results

The Phase 1 scaffold has been tested with:

```bash
Rscript -e 'parse("R/00_initialise_project_structure.R"); parse("R/00_install_dependencies.R"); parse("R/00_setup.R"); parse("R/functions/package_list.R")'
Rscript -e 'source("R/00_initialise_project_structure.R"); tmp <- tempfile("sens_"); dir.create(tmp); created <- sensanalyser_initialise_structure(root=tmp); stopifnot(length(created)==10); created2 <- sensanalyser_initialise_structure(root=tmp); stopifnot(length(created2)==0); unlink(tmp, recursive=TRUE)'
Rscript -e 'source("R/functions/package_list.R"); stopifnot(length(sensanalyser_get_package_list())==6); stopifnot(length(sensanalyser_get_all_packages())==32)'
Rscript -e 'source("R/00_setup.R"); stopifnot(length(sensanalyser_setup_summary$missing_packages)==0); stopifnot(length(sensanalyser_setup_summary$loaded_packages)==sensanalyser_setup_summary$dependency_count)'
```

All checks pass after dependency installation.

## Next phase

Phase 2 should add reusable data import and variable-selection helpers so the pipeline can select raw data, dependent variables, and factors without hardcoded filenames or column ranges.
