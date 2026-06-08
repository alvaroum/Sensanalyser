# Sensanalyser Phase 7 Implementation Log

Date: 2026-06-08  
Phase: 7 — Table System  
Status: Completed

## Objective
Implement a table system that combines Phase 4 (descriptives), Phase 5 (model results), and Phase 6 (post-hoc results) into manuscript-ready output tables with optional display-name conversion.

## Files Added
- R/functions/table_helpers.R
- R/test_phase7.R
- PHASE7_IMPLEMENTATION_LOG.md

## Files Updated
- R/core_engine.R

## Implemented Components

### 1) Table helper module
File: R/functions/table_helpers.R

Functions implemented:
- .prepare_manuscript_metadata(config)
  - Extracts model type, post-hoc method, alpha, outlier policy for logging.

- .append_letters_to_descriptives(desc_wide, letters_tbl, grouping_factors)
  - Joins post-hoc letter columns to descriptives wide table.
  - Creates new columns like "outcome_letters" per outcome.

- create_report_wide(desc_long, letters_tbl, grouping_factors, include_letters)
  - Pivots descriptives long to wide with outcomes as columns.
  - Outcomes formatted as "mean ± SE".
  - Optionally appends post-hoc letters as suffixes or separate columns.
  - Output: manuscript-ready wide table.

- create_manuscript_table_long(desc_long, results_model)
  - Keeps descriptives long format and adds model p-values per outcome.
  - Used for detailed reporting workflows.

- create_run_configuration_summary(selections, config, model_result, posthoc_result)
  - Single-row tibble with full audit trail:
    - run_date, data_file, dependent_variables, fixed_factors, subject_id
    - model_type, posthoc_method, alpha
    - outlier_policy, outlier_removal_action
    - posthoc_focal_terms
    - all enabled toggles
    - n_outcomes_analyzed, n_posthoc_comparisons

- save_analysis_tables(config, desc_long, results_model, posthoc_result, selections)
  - Writes:
    - outputs/tables/report_format_wide.csv
    - outputs/tables/run_configuration_summary.csv
  - Returns named list of file paths.

- run_table_phase(pipeline_state)
  - End-to-end Phase 7 orchestrator.
  - Reuses Phase 4, 5, 6 results from pipeline_state.

### 2) Core pipeline integration
File: R/core_engine.R

Changes:
- Replaced Phase 7 placeholder with real execution
- Added .phase7_tables(pipeline_state)
- Stores outputs under:
  - pipeline_state$results$tables

## Design Notes

### Manuscript table structure
The report_format_wide table has:
- Grouping factor column(s) as row identifiers (e.g., product)
- One column per outcome with "mean ± SE" formatting
- Optional post-hoc letter column per outcome (e.g., "outcome_letters")

### Configuration summary purpose
Captures the full reproducible run settings so that:
- When the file is opened later, the user knows exactly what settings were used
- The table can be included in an appendix or supplementary materials
- All toggles and parameter choices are documented

### Dependency on earlier phases
- Phase 7 only runs if create_tables toggle is TRUE
- It requires Phase 4 descriptives to be available
- It optionally uses Phase 5 models and Phase 6 post-hoc results if those phases ran

## Tests Added
File: R/test_phase7.R

### Single test scenario: Full pipeline (Phases 1–7)
- Enables: descriptives, ANOVA models, post-hoc, and table creation
- Validates:
  - pipeline_state$results$tables exists
  - report_format_wide is a data frame with rows > 0
  - run_configuration_summary is a data frame with nrow = 1
  - Output files exist:
    - outputs/tables/report_format_wide.csv
    - outputs/tables/run_configuration_summary.csv
  - Configuration values are correctly recorded

## Test Command Run
- Rscript R/test_phase7.R

## Final Test Outcome
- All Phase 7 tests passed
- Exit code: 0

## Output Artifacts Produced
- outputs/tables/report_format_wide.csv
- outputs/tables/run_configuration_summary.csv

## Sample Output Content
### report_format_wide.csv
Example row:
```
product,Body (Mouthfeel),Sweetness (Mouthfeel),Viscosity (Appearance)
Product A,41.2 ± 4.9,34.4 ± 5.8,54.7 ± 5.2
```

### run_configuration_summary.csv
Columns:
```
run_date, data_file, dependent_variables, fixed_factors, subject_id,
repeated_measures_factors, model_type, outlier_policy, outlier_removal_action,
posthoc_method, posthoc_focal_terms, alpha, run_outlier_detection,
apply_outlier_policy, run_descriptives, run_anova_models, run_mixed_models,
run_posthoc, n_outcomes_analyzed, n_posthoc_comparisons
```

## Implementation Notes

- The %||% operator is used as fallback coalescing for NULL values in the configuration summary.
- Phase 7 gracefully handles the case where Phase 6 post-hoc results are not available.
- Table column names use display-name conversions when the renaming_dictionary is loaded.
- The report_format_wide table is ready for direct inclusion in reports or manuscripts.

## Phase 7 Completion Summary
Phase 7 is fully implemented and integrated.
The project now combines descriptive statistics, model results, and post-hoc comparisons into manuscript-ready tables with complete configuration audit trails.

---

## Patch 1 — Table orientation and letter integration fix (2026-06-08)

### Problem
`report_format_wide.csv` had the wrong orientation: factor levels were rows and
outcomes were columns.  The reference project uses the opposite layout (outcomes
as rows, factor levels as columns) with post-hoc letters integrated into the
cell value itself (e.g., `"41.2 ± 4.9a"`), not appended as separate columns.

Additionally, the factor levels stored in `posthoc_letters.csv` are the raw
coded values (1, 2, 3…), while `descriptives_long.csv` already holds
display-mapped values ("Product A", "Product B"…).  Without remapping, the join
would silently produce all-NA letter columns.

### Root cause
`create_report_wide()` pivoted `names_from = "outcome_display"` (outcomes as
column headers) and used `.append_letters_to_descriptives()` which added letter
columns rather than integrating letters into cell strings.

### Fix — R/functions/table_helpers.R

**Removed** `.append_letters_to_descriptives()` (wrong approach).

**Rewrote** `create_report_wide()`:
- Added `renaming_dictionary` parameter.
- Applies `.apply_level_labels()` to the `factor_col` column of `letters_tbl`
  before joining, so raw codes map to display names matching `desc_long`.
- Filters letters to `spec == factor_col` to select the right comparisons.
- Builds `formatted_cell = paste0(mean_se, trimws(.group))` when
  `letters_suppressed == FALSE` and `.group` is not NA; otherwise just `mean_se`.
- Pivots `names_from = factor_col` (factor levels as column headers) and
  `values_from = "formatted_cell"`, renames `outcome_display` → `outcome`.
- Output: rows = one per sensory attribute, columns = product/factor levels.

**Updated** `save_analysis_tables()`:
- Loads the renaming dictionary from `config$paths$renaming_dictionary`.
- Passes `renaming_dictionary = dict` to `create_report_wide()`.
- Returns a named list (`report_format_wide`, `run_configuration_summary`,
  `file_paths`) so `run_table_phase()` does not need to recompute tables.

**Simplified** `run_table_phase()`:
- Delegates entirely to `save_analysis_tables()` and returns its result,
  eliminating a second independent call to `create_report_wide()` that lacked
  the renaming dictionary.

**Simplified** `create_manuscript_table_long()`:
- Removed the row-loop approach for joining model p-values; uses a single
  `left_join()` on outcome instead.

### Fix — R/test_phase7.R

Updated test assertions to expect the correct output format:
- `"outcome" %in% names(report_wide)` (was `"product" %in% names(report_wide)`)
- `ncol(report_wide) >= 2` (at least one factor-level column)
- `nrow(report_wide) == length(DVs)` (one row per dependent variable)

### Verified output
```
outcome,Product A,Product B,Product C,Product D,Product E,6,7
Body (Mouthfeel),41.2 ± 4.9,43.1 ± 3.9,42.3 ± 2.7,43.9 ± 3.7,39.6 ± 4.0,40.9 ± 4.2,39.8 ± 4.0
Sweetness (Mouthfeel),34.4 ± 5.8,28.8 ± 5.3,32.7 ± 5.4,34.2 ± 6.0,43.8 ± 6.6,36.8 ± 5.3,38.4 ± 5.5
Viscosity (Appearance),54.7 ± 5.2,49.9 ± 4.6,56.9 ± 4.0,50.6 ± 4.5,42.8 ± 5.2,53.4 ± 5.1,49.4 ± 6.2
```
(No letters here because all omnibus tests were non-significant for the test
dataset.  When significant, cells read e.g. `"41.2 ± 4.9a"`.)

All Phase 7 tests passed after the fix.

---

## Patch 2 — Mean-only table + Phase 4 digits null-safety (2026-06-08)

### Problems
1. When running the full pipeline from `analysis_config.yaml` (which has no
   `table_options` section), Phase 4 crashed with:
   `! invalid second argument of length 0` in `round(.data$mean, NULL)`.

2. Users requested a separate report table containing only the rounded mean
   (no ± SE, no letters).

### Fix 1 — R/functions/descriptive_helpers.R

In `run_descriptive_phase()`, added a null-safe default before passing `digits`
to `create_descriptives_long()`:
```r
digits <- config$table_options$digits
if (is.null(digits) || length(digits) == 0 || is.na(digits)) digits <- 1L
```

### Fix 2 — R/functions/table_helpers.R

**New function** `create_report_wide_means(desc_long, grouping_factors, digits)`:
- Same row/column orientation as `create_report_wide()`.
- Cell values contain only the rounded mean (no ± SE, no letter superscripts).
- Output column: `outcome` (display name), then one column per factor level.

**Updated `save_analysis_tables()`**:
- Computes `report_format_wide_means` alongside the existing `report_format_wide`.
- Writes `outputs/tables/report_format_wide_means.csv`.
- Returns both tables in the result list.

### Output files
| File | Content |
|------|---------|
| `report_format_wide.csv` | mean ± SE + letters (letters shown only when omnibus significant) |
| `report_format_wide_means.csv` | mean only (no SE, no letters) |

### Verified output
```
# report_format_wide.csv
outcome,Trial 1,...,Trial 5,...
Confectionary (Aroma),3.7 ± 1.1a,19.3 ± 5.9bc,...,28.3 ± 6.4c,...
Leathery (Aroma),22.9 ± 5.4a,18.8 ± 5.5ab,...,6.1 ± 2.0b,...

# report_format_wide_means.csv (mean + letters, no SE)
outcome,Trial 1,...,Trial 5,...
Confectionary (Aroma),3.7a,19.3bc,...,28.3c,...
Leathery (Aroma),22.9a,18.8ab,...,6.1b,...
```

`create_report_wide_means()` now accepts the same `letters_tbl` and
`renaming_dictionary` parameters as `create_report_wide()` and applies the same
letter-integration logic — only SE is omitted.
