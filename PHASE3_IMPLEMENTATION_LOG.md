# Sensanalyser Phase 3 Implementation Log

Date: 2026-06-08  
Phase: 3 — Outlier Detection and Outlier Policy  
Status: Completed — reviewed, corrected, and retested

## Scope
Phase 3 was implemented according to the restructuring plan:
1. Detect outliers per dependent variable and grouping-factor combination.
2. Apply policy modes: keep_all, remove_extreme, remove_all.
3. Apply removal actions: set_na and drop_row.
4. Save diagnostics outputs.
5. Integrate the phase into the pipeline engine.
6. Test helper-level behavior and full pipeline behavior.

## Files Added
- R/functions/outlier_helpers.R
- PHASE3_IMPLEMENTATION_LOG.md

## Files Updated
- R/core_engine.R
- R/functions/variable_selection_helpers.R
- mission_control.R
- data/dictionary/analysis_config.yaml

## Implemented Functions

### In R/functions/outlier_helpers.R
- identify_sensory_outliers(data, dvs, group_factors)
  - Validates input columns and numeric DVs.
  - Uses rstatix::identify_outliers per DV.
  - Supports grouped or global detection.
  - Returns long-format table with dv, .row_id, value, is.outlier, is.extreme.

- apply_outlier_policy(data, outlier_table, outlier_policy, removal_action)
  - Policies:
    - keep_all: no data change
    - remove_extreme: target only is.extreme == TRUE
    - remove_all: target all is.outlier == TRUE
  - Actions:
    - set_na: only targeted DV cells become NA
    - drop_row: rows with targeted outliers are removed
  - Returns updated data and policy decision table.

- summarise_outlier_decisions(policy_table)
  - Produces overall + per-DV counts:
    - total_flagged
    - total_outliers
    - total_extreme
    - targeted_for_removal
    - kept
    - removed

- run_outlier_phase(data, selections, config)
  - Orchestrates detection + policy + summary.
  - Auto-injects .row_id if missing.
  - Uses config$analysis$outlier_grouping_factors when provided, else selections$factors.
  - Writes outputs:
    - outputs/diagnostics/outliers_all.csv
    - outputs/diagnostics/outlier_policy_applied.csv
    - outputs/diagnostics/outlier_decision_summary.csv

## Pipeline Integration

### R/core_engine.R
- Replaced Phase 3 placeholder with real execution.
- Added internal phase handler:
  - .phase3_outliers(pipeline_state)
- Behavior:
  - Always runs detection when toggles$run_outlier_detection == TRUE.
  - Applies transformed data only when toggles$apply_outlier_policy == TRUE.
  - Stores Phase 3 results in:
    - pipeline_state$results$outliers$outliers_all
    - pipeline_state$results$outliers$policy_table
    - pipeline_state$results$outliers$summary

## Config Extensions

### mission_control.R
Added analysis settings:
- outlier_removal_action = "set_na"
- outlier_grouping_factors = NULL

### data/dictionary/analysis_config.yaml
Added template fields:
- outlier_removal_action
- outlier_grouping_factors

### R/functions/variable_selection_helpers.R
YAML write/read extended to persist and restore:
- analysis$outlier_removal_action
- analysis$outlier_grouping_factors

## Review corrections applied

After review, one semantic issue was corrected:

- When `toggles$apply_outlier_policy = FALSE`, diagnostics previously marked targeted outliers as `removed` even though the working data was unchanged. `apply_outlier_policy()` now has an `apply_policy` argument. In this mode, it records the requested policy and which cells/rows would have been targeted, but marks decisions as `kept_not_applied` and sets `applied_to_data = FALSE`.

The diagnostics now include additional columns:

- `applied_to_data`
- `requested_outlier_policy`

The summary now includes:

- `applied_to_data`
- `kept_not_applied`

This makes `outlier_policy_applied.csv` and `outlier_decision_summary.csv` consistent with the actual state of the working dataset.

## Tests Run

All tests executed successfully in the project root using Rscript.

### Test 1: Helper-level validation
- Loaded raw data.
- Selected 4 DVs: viscosity_ap, sweetness_m, body_m, burn_m.
- Ran identify_sensory_outliers grouped by product.
- Ran apply_outlier_policy (remove_extreme + set_na).
- Ran summarise_outlier_decisions.
- Ran run_outlier_phase orchestrator.
- Result: PASS.

### Test 2: Full pipeline with set_na
Config:
- outlier_policy = remove_extreme
- outlier_removal_action = set_na
- apply_outlier_policy = TRUE

Observed:
- Rows before: 133
- Rows after: 133
- Diagnostics files written.
- Result: PASS.

### Test 3: Full pipeline with drop_row
Config:
- outlier_policy = remove_all
- outlier_removal_action = drop_row
- apply_outlier_policy = TRUE

Observed:
- Rows before: 133
- Rows after: 129
- Diagnostics files written.
- Result: PASS.

### Test 4: apply_outlier_policy toggle behavior
Config:
- outlier_policy = remove_all
- outlier_removal_action = drop_row
- apply_outlier_policy = FALSE

Observed:
- Rows before: 133
- Rows after: 133
- Detection still runs and diagnostics still written.
- Working dataset remains unchanged by policy.
- Result: PASS.

### Test 5: set_na proof with remove_all
Config:
- outlier_policy = remove_all
- outlier_removal_action = set_na

Observed:
- NA before (selected 4 DVs): 0
- NA after (selected 4 DVs): 4
- NA increase: 4
- Result: PASS.

### Test 6: Diagnostics files existence
Verified files exist:
- outputs/diagnostics/outliers_all.csv
- outputs/diagnostics/outlier_policy_applied.csv
- outputs/diagnostics/outlier_decision_summary.csv

Result: PASS.

## Output Artifacts Produced
- outputs/diagnostics/outliers_all.csv
- outputs/diagnostics/outlier_policy_applied.csv
- outputs/diagnostics/outlier_decision_summary.csv
- outputs/logs/data_load_log.csv (updated during test runs)

## Notes
- Workspace is not a git repository, so git diff could not be used for change auditing.
- Static analyzer warnings from get_errors are mostly non-runtime lint messages for NSE/tidy-eval usage and sourced helper visibility; runtime tests confirmed correct execution.

### Additional review tests

Additional checks were run after correction:

- Syntax parsing for `R/functions/outlier_helpers.R` and `R/core_engine.R`.
- `apply_outlier_policy = FALSE` with `remove_all + drop_row`:
  - row count remained unchanged;
  - all `applied_to_data` values were `FALSE`;
  - targeted rows were marked `kept_not_applied`.
- `keep_all` with `apply_outlier_policy = TRUE`:
  - no rows/cells were targeted;
  - row count remained unchanged.

Result: PASS.

## Phase 3 Completion Summary
Phase 3 is fully implemented, integrated, tested, corrected, and documented.
The pipeline now supports configurable outlier detection and policy application with reproducible diagnostics output.
