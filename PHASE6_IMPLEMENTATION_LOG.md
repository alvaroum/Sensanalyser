# Sensanalyser Phase 6 Implementation Log

Date: 2026-06-08  
Phase: 6 — Post-hoc Analysis Engine  
Status: Completed — reviewed, corrected, and retested

## Objective
Implement a configurable post-hoc engine that supports:
- Tukey-adjusted pairwise comparisons
- Bonferroni-adjusted pairwise comparisons
- Fisher LSD style comparisons
- Compact letter displays
- Suppression or flagging of letters when omnibus tests are non-significant
- Conditional post-hoc comparisons within levels of another factor for interaction terms

## Files Added
- R/functions/posthoc_helpers.R
- R/test_phase6.R
- PHASE6_IMPLEMENTATION_LOG.md

## Files Updated
- R/core_engine.R
- R/functions/model_helpers.R
- R/functions/package_list.R

## Implemented Components

### 1) Post-hoc helper module
File: R/functions/posthoc_helpers.R

Functions implemented:
- .parse_posthoc_term(term)
  - Supports:
    - main effects: product
    - explicit by-spec terms: product|age
    - interaction shorthand: product:age
  - Interaction shorthand expands into within-level post-hoc requests for both directions.

- .derive_focal_terms(results_model, alpha)
  - If posthoc_focal_terms is NULL, derives candidate terms from significant omnibus results.

- .get_omnibus_p(results_model, outcome, omnibus_term)
  - Retrieves the matching omnibus p-value for a given outcome and term.

- create_compact_letter_display(emm_grid, pairwise_tbl, spec, by)
  - Generates compact letter displays using multcompView::multcompLetters.
  - Uses emmeans estimated means plus pairwise p-values.
  - Supports both global letters and by-level letters.

- suppress_non_significant_letters(letters_tbl, omnibus_p, alpha)
  - Applies the cautious rule: if the omnibus term is non-significant or unavailable,
    letters are suppressed and flagged.

- run_emmeans_posthoc(...)
  - Tukey and Bonferroni through emmeans::contrast(..., method = "pairwise")
  - LSD via emmeans with adjust = "none"
  - Produces:
    - pairwise table
    - letter table
    - method summary row

- run_lsd_posthoc(...)
  - Thin wrapper over run_emmeans_posthoc(..., method = "lsd")

- run_posthoc_suite(data, selections, config, model_result)
  - Runs across all requested outcomes and terms
  - Refits the per-outcome model using Phase 5 settings to obtain model objects suitable for emmeans
  - Handles failures without stopping the rest of the suite

- save_posthoc_outputs(posthoc_result, config)
  - Writes:
    - outputs/tables/posthoc_pairwise.csv
    - outputs/tables/posthoc_letters.csv
    - outputs/tables/posthoc_method_summary.csv

- run_posthoc_phase(data, selections, config, model_result)
  - End-to-end Phase 6 orchestrator

### 2) Core pipeline integration
File: R/core_engine.R

Changes:
- Replaced the Phase 6 placeholder with real execution
- Added .phase6_posthoc(pipeline_state)
- Reuses Phase 5 model results when available
- If models were not run earlier, Phase 6 can trigger model fitting internally
- Stores outputs under:
  - pipeline_state$results$posthoc

### 3) Dependency update
File: R/functions/package_list.R

Added:
- multcompView

Reason:
- Compact letter displays are now generated from pairwise p-values via multcompView::multcompLetters.

### 4) Phase 5 compatibility update
File: R/functions/model_helpers.R

Change:
- ANOVA path now also returns a fitted stats::aov object in run_model_for_outcome()

Reason:
- Phase 6 needs a model object usable by emmeans for post-hoc estimation.

## Design Notes

### Method routing
- Tukey: adjust = "tukey"
- Bonferroni: adjust = "bonferroni"
- LSD: adjust = "none"

### Interaction support
The engine supports two styles:
- Explicit: product|replica
- Shorthand: product:replica

For product:replica, the engine expands into:
- compare product within each replica
- compare replica within each product

### Omnibus suppression rule
Letters are suppressed when:
- omnibus p-value is not available, or
- omnibus p-value >= alpha

This is recorded in:
- letters_suppressed
- suppression_reason
- omnibus_significant

## Review Corrections Applied

After review, the following corrections were applied:

1. **Post-hoc method validation**  
   `run_posthoc_suite()` now validates `posthoc_method` and fails early for unsupported methods instead of silently defaulting to Tukey.

2. **Alpha-aware compact letters**  
   `create_compact_letter_display()` now passes the configured `alpha` value to `multcompView::multcompLetters()` rather than using the default threshold implicitly.

3. **Factor coercion for post-hoc refits**  
   The post-hoc refit now coerces fixed effects, repeated-measures factors, random effects, and subject IDs to factors locally. This mirrors Phase 5 and prevents coded factors supplied only via `model_fixed_effects` from being treated as numeric covariates by `emmeans`.

4. **Expanded regression tests**  
   `R/test_phase6.R` now checks invalid method failure and repeated-measures `afex` model compatibility with `emmeans` post-hocs.

5. **README update**  
   `README.md` now reflects Phase 1–6 status and documents Phase 6 configuration and outputs.

## Tests Added
File: R/test_phase6.R

### Test 1: Tukey path
- posthoc_method = tukey
- focal term = product
- Validates pairwise rows, letters rows, and method label

### Test 2: Bonferroni path
- posthoc_method = bonferroni
- Validates adjust column = bonferroni

### Test 3: LSD path
- posthoc_method = lsd
- Validates adjust column = none

### Test 4: Output file existence
Checks:
- outputs/tables/posthoc_pairwise.csv
- outputs/tables/posthoc_letters.csv
- outputs/tables/posthoc_method_summary.csv

### Test 5: Interaction/by-level support
- focal term = product:replica
- model_type = two_way_anova
- fixed effects = product + replica
- Validates:
  - pairwise rows exist
  - by column contains values
  - requested_term includes product:replica

## Test Command Run
- Rscript R/test_phase6.R

## Final Test Outcome
- All Phase 6 tests passed after review corrections
- Regression checks for Phases 3–5 also passed
- Exit code: 0

## Output Artifacts Produced
- outputs/tables/posthoc_pairwise.csv
- outputs/tables/posthoc_letters.csv
- outputs/tables/posthoc_method_summary.csv

## Notes on Implementation Choices
- emmeans::cld was not exported in the current environment, so compact letters were implemented directly from pairwise p-values using multcompView.
- The post-hoc suite reuses Phase 5 settings and refits per-outcome models to get emmeans-compatible objects.
- Phase 6 depends on Phase 5 logic, but can bootstrap model fitting if Phase 5 results are not already present in pipeline state.

## Phase 6 Completion Summary
Phase 6 is fully implemented and integrated.
The project now supports configurable post-hoc workflows with selectable adjustment methods, compact-letter displays, omnibus-aware suppression, interaction-level post-hoc requests, and automated tests.

---

## Patch 2 — Compact letter display key mismatch fix (2026-06-08)

### Problem
Post-hoc letters were always NA in the output even when the omnibus test was
significant and `letters_suppressed = FALSE`.

### Root cause
`create_compact_letter_display()` → `build_letters_for_slice()` uses
`multcompView::multcompLetters()` to assign a letter to each factor level.
The input names are the contrast labels from `emmeans::contrast()` (e.g.
`"product1 - product2"` → after gsub → `"product1-product2"`).
`multcompLetters` extracts group names by splitting on `"-"`, so the resulting
`$Letters` vector has keys `"product1"`, `"product2"`, …, `"product7"`.

The lookup `letter_map[as.character(emm_tbl[[spec]])]` uses the bare factor
level values (`"1"`, `"2"`, …, `"7"`). These never matched the prefixed keys
(`"product1"`, …) → every `.group` value was silently set to `NA`.

### Fix — R/functions/posthoc_helpers.R

Inside `build_letters_for_slice()` (lines within
`create_compact_letter_display()`), after calling `multcompLetters`, the spec
prefix is stripped from the letter-map names so they match the bare level
values in `emm_tbl`:

```r
letter_result <- multcompView::multcompLetters(cmp_vec, threshold = alpha)$Letters
# emmeans prepends the factor name to numeric level values in contrast labels
# (e.g. "product1 - product2" → key "product1" in the letter map).
# Strip the prefix so keys match the bare level values in emm_tbl.
names(letter_result) <- sub(paste0("^", spec), "", names(letter_result))
```

The `sub(paste0("^", spec), ...)` pattern removes only a leading occurrence of
the spec name, so character-level factors (e.g. "young", "middle") that do not
carry a prefix are unaffected.

### Verified output (tropical_a, 7 products)
```
product   1     2     3     4     5     6     7
.group    a     a     a     a     b     a     a
```
Product 5 is correctly identified as significantly different from the others.

---

## Patch 3 — `.get_omnibus_p()` dplyr data-mask ambiguity fix (2026-06-08)

### Problem
All outcomes in `posthoc_letters.csv` and `posthoc_pairwise.csv` had the same
`omnibus_p` (the p-value of the first DV in the list), and `omnibus_significant`
was `FALSE` for every row — meaning letters were suppressed for all outcomes.

### Root cause
In `.get_omnibus_p()`:
```r
dplyr::filter(.data$outcome == outcome, .data$term == omnibus_term)
```
Inside dplyr's data mask, bare `outcome` on the right-hand side resolves to the
**column** named `outcome` rather than the function parameter. The filter
became `col$outcome == col$outcome` (always `TRUE`) so all 53 rows matched
and `hit$p[[1]]` returned the first row's p-value (transparancy_ap = 0.2096)
for every call.

### Fix — R/functions/posthoc_helpers.R
Use the `.env$` pronoun to force right-hand-side lookup in the calling
environment, not the data mask:
```r
dplyr::filter(.data$outcome == .env$outcome, .data$term == .env$omnibus_term)
```

### Verified
- `tropical_a` → 0.0001057 ✓ (was 0.2096)
- `transparancy_ap` → 0.2096 ✓ (non-significant, correct)
- `confectionary_a` → 1.04e-5 ✓ (highly significant, correct)
- All 105 posthoc letter rows: `omnibus_significant = TRUE`, `letters_suppressed = FALSE`
