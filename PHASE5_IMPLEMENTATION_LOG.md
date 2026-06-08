# Sensanalyser Phase 5 Implementation Log

Date: 2026-06-08  
Phase: 5 — Statistical Model Engine  
Status: Completed — reviewed, corrected, and retested

## Objective
Implement a reusable model engine that supports:
- Between-subject ANOVA families
- Linear mixed models
- Formula construction from configuration
- Per-outcome robust error handling
- Diagnostics and warning exports

## Files Added
- R/functions/model_helpers.R
- R/test_phase5.R
- PHASE5_IMPLEMENTATION_LOG.md

## Files Updated
- R/core_engine.R
- mission_control.R
- R/functions/variable_selection_helpers.R
- data/dictionary/analysis_config.yaml

## Implemented Components

### 1) Model helper module
File: R/functions/model_helpers.R

Functions implemented:
- resolve_model_settings(config)
  - Loads model_type settings from config
  - Reads model presets YAML when available
  - Applies explicit mission_control overrides for:
    - model_fixed_effects
    - random_effects

- build_model_formula(outcome, settings, selections)
  - Builds ANOVA formula (fixed effects with optional interactions)
  - Builds mixed model formula with random intercept terms

- run_model_for_outcome(data, outcome, settings, selections)
  - Runs one model per outcome
  - Engines:
    - rstatix::anova_test for ANOVA-like presets
    - lmerTest::lmer + anova for mixed model
  - Collects warnings without stopping pipeline

- run_model_suite(data, selections, config)
  - Iterates across all selected DVs
  - Handles per-DV failures gracefully
  - Returns results table, warnings table, failure table

- save_model_diagnostics(model_result, config)
  - Writes:
    - outputs/tables/results_model.csv
    - outputs/diagnostics/model_warnings.csv

- run_model_phase(data, selections, config)
  - End-to-end orchestrator for Phase 5

### 2) Core pipeline integration
File: R/core_engine.R

Changes:
- Replaced Phase 5 placeholder with real execution
- Added .phase5_models(pipeline_state)
- Stores outputs under:
  - pipeline_state$results$models

### 3) Config support and YAML persistence
Files:
- mission_control.R
- R/functions/variable_selection_helpers.R
- data/dictionary/analysis_config.yaml

Added analysis setting:
- model_fixed_effects

Behavior:
- User may explicitly set model_fixed_effects in mission_control
- This overrides preset fixed effects if provided
- YAML read/write now persists model_fixed_effects

## Key Bug Fixes During Implementation

1) ANOVA output conversion bug
- Symptom: results_model table empty for ANOVA runs
- Cause: mutate applied directly to anova_test object
- Fix: convert with tibble::as_tibble(aov_tbl) before mutate

2) Preset override precedence bug
- Symptom: mixed model attempted to use absent preset variable (age)
- Cause: preset fixed_effects overwrote explicit mission_control model_fixed_effects
- Fix: enforce explicit model_fixed_effects and random_effects precedence after preset merge

## Review Corrections Applied

After review, the following issues were corrected:

1. **Repeated-measures presets were labelled but not actually run as repeated models**  
   Presets with `engine: afex_aov_car` now run through `afex::aov_car()` using an `Error(subject/(within_factors))` formula.

2. **Three-factor formula construction ignored `three_way_interactions`**  
   Formula construction now uses `(a + b + c)^2` when interactions are requested but three-way interactions are disabled.

3. **ANOVA output schema was inconsistent across engines**  
   The repeated-measures route now exports numeric `p`, `DFn`, and `DFd` columns from `model_obj$anova_table` rather than formatted strings from `afex::nice()`.

4. **Model setting validation was added**  
   Phase 5 now checks missing fixed effects, missing repeated-measures factors, missing subject IDs, and missing random-effect columns before running the model suite.

5. **Design columns supplied only through `model_fixed_effects` are coerced locally**  
   The model suite now treats fixed effects, repeated-measures factors, random effects, and subject ID columns as factors even if they were not included in Phase 2 `factors`.

6. **Regression tests were expanded**  
   `R/test_phase5.R` now tests the repeated-measures `afex` route and formula construction for disabled three-way interactions.

## Tests Implemented

### Test script
File: R/test_phase5.R
Run command:
- Rscript R/test_phase5.R

### Test coverage
1) One-way ANOVA path
- run_anova_models = TRUE
- model_type = one_way_anova
- Checks results table exists and has rows
- Checks required columns present

2) Repeated-measures ANOVA path
- model_type = one_way_repeated
- engine = afex_aov_car
- repeated_measures_factors = product
- Checks numeric `p` column and `afex_aov_car` engine route

3) Linear mixed model path
- run_mixed_models = TRUE
- model_type = linear_mixed_model
- random_effects = user
- Checks results table schema

4) Formula construction
- Confirms three fixed effects with `three_way_interactions = FALSE` produce `(a + b + c)^2`

5) Output artifacts
- Verifies files exist:
  - outputs/tables/results_model.csv
  - outputs/diagnostics/model_warnings.csv

## Final Test Outcome
- All Phase 5 tests passed
- Command result: Exit Code 0

## Artifacts Generated
- outputs/tables/results_model.csv
- outputs/diagnostics/model_warnings.csv

## Notes
- Model failures are captured per DV and exported in model_warnings.csv as ERROR rows.
- Pipeline remains resilient: one failed DV does not stop other DVs.

## Phase 5 Completion Summary
Phase 5 is fully implemented and integrated.
The project now has a robust, configurable model engine with diagnostics export and automated tests.

---

## Phase 5 — Patch 1: Model Preset Column-Name Overwrite Bug

**Date**: 2026-06-08  
**Status**: ✅ Fixed

### Problem

Running the pipeline with `model_type = "linear_mixed_model"` raised:

```
Error in validate_model_settings():
✖ Fixed effect column(s) missing: age
✖ Random-effect column(s) missing: assessor
```

`age` and `assessor` do not exist in the user's dataset. They are placeholder column names used as examples in `model_presets.yaml`.

### Root cause

`resolve_model_settings()` built `settings` from user selections (`factors = [product]`, `random_effects = [user]`), then called `utils::modifyList(settings, preset)`. This overwrote the user-selected column names with the preset's placeholders (`fixed_effects: [product, age]`, `random_effects: [assessor]`).

The post-merge override only checked `config$analysis$model_fixed_effects` (which is NULL unless explicitly set), so the placeholder column names were never replaced with the user's actual selections.

### Changes

**`R/functions/model_helpers.R` — `resolve_model_settings()`**

Rewrote the function to separate "structure" (from preset) from "column names" (from user selections):

1. User column names are captured before any preset loading: `user_fixed`, `user_random`, `user_rm`.
2. Only structural keys are merged from the preset: `engine`, `interactions`, `three_way_interactions`, `repeated_measures`.
3. After the structural merge, user column names are unconditionally re-applied.
4. `repeated_measures_factors` defaults to `fixed_effects` for all-within designs when the user did not specify them explicitly.

**`data/dictionary/model_presets.yaml`**

Removed all `fixed_effects`, `random_effects`, and `repeated_measures_factors` entries from every preset. The YAML now contains only structural fields (`engine`, `interactions`, `three_way_interactions`, `repeated_measures`) plus a `description`. Comments explain why column names are absent.

---

## Phase 5 — Patch 2: Fixed-effect NULL propagation from interactive setup

**Date**: 2026-06-08  
**Status**: ✅ Fixed

### Problem

All outcomes failed with `ERROR [model_fit]: Model requires at least one fixed effect.` after an interactive run. The model results CSV was empty.

### Root cause

When the user sets `factors = NULL` in `mission_control.R` (to trigger interactive selection), Phase 2 correctly prompts for and stores the chosen factor (`product`) in `pipeline_state$selections$factors`. However, `pipeline_state$config$analysis$factors` was **never updated** — it remained NULL throughout the pipeline.

Phase 5 calls `resolve_model_settings(config)`, which reads `config$analysis$factors`. Since that is still NULL, `user_fixed` resolves to NULL, `settings$fixed_effects` is NULL, and `.build_fixed_rhs()` aborts on every outcome.

The same gap affected `random_effects`, `subject_id`, `repeated_measures_factors`, and `dependent_variables`.

### Changes

**`R/core_engine.R` — `.phase2_variable_selection()`**

Added a sync block immediately after `pipeline_state$selections <- selections` that writes all resolved selections back into `pipeline_state$config$analysis`:

```r
pipeline_state$config$analysis$dependent_variables       <- selections$dependent_variables
pipeline_state$config$analysis$factors                   <- selections$factors
pipeline_state$config$analysis$subject_id                <- selections$subject_id
pipeline_state$config$analysis$repeated_measures_factors <- selections$repeated_measures_factors
pipeline_state$config$analysis$random_effects            <- selections$random_effects
pipeline_state$config$analysis$blocking_factors          <- selections$blocking_factors
```

This makes `config$analysis` the single authoritative source for column names in all downstream phases, regardless of whether values came from explicit settings, interactive prompts, or `"auto"` detection.

**`R/functions/model_helpers.R` — `resolve_model_settings()`**

Added a `selections = NULL` parameter as a belt-and-suspenders fallback. Column name resolution now tries three sources in order:
1. `config$analysis$model_fixed_effects` / `config$analysis$factors` (synced from core engine)
2. `selections$factors` / `selections$random_effects` / `selections$repeated_measures_factors` (direct fallback)
3. NULL (results in a clear abort at formula build time)

Updated `run_model_suite()` to pass `selections` when calling `resolve_model_settings(config, selections)`.

**`R/functions/posthoc_helpers.R` — `run_posthoc_suite()`**

Updated the call `resolve_model_settings(config)` → `resolve_model_settings(config, selections)` to apply the same fallback.
