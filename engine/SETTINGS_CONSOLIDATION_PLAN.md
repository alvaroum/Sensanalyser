# Sensanalyser (main branch) — Settings Consolidation & Usability Plan

Goal: keep Sensanalyser a script-based tool run from Positron/RStudio (no
app), but consolidate everything a user edits into **one project file**
(plus one tiny launcher), make the effective configuration visible and
validated, and stop the pipeline from writing hidden state the user has to
remember.

---

## 1. Where settings live today (the problem)

A user configuring one analysis currently touches up to **seven files in
four formats**, three of which are also written *by* the pipeline:

| File | Format | Edited by | What it holds |
|---|---|---|---|
| `master_mission_control.R` | R | user | `active_projects`, 12 `global_toggles` (run_pca, run_posthoc, ...) |
| `projects/<p>/project_config.R` | R | user | toggle overrides, `raw_data`, `analysis` (DVs, factors, subject, model_type, hcpc_n_clusters), `product_subsets`, `derived_attribute_options`, `fig_options` |
| `data/dictionary/analysis_config.yaml` | YAML | **pipeline** (after interactive setup) | data file list, saved variable selections — silently becomes the source of truth when `dependent_variables = NULL` |
| `data/dictionary/renaming_dictionary.yaml` | YAML | user | aliases, variable/level/outcome display labels |
| `data/dictionary/derived_attributes.yaml` | YAML | user | derived attribute definitions |
| `data/dictionary/factor_splits.yaml` | YAML | pipeline (+ user corrections) | product "+" split decisions |
| `data/dictionary/model_presets.yaml` | YAML | nobody (engine asset) | structural model definitions — ships per project but should never be edited |

Concrete pain points this creates:

1. **Two sources of truth for the analysis.** `project_config.R$analysis`
   *and* the auto-written `analysis_config.yaml` both define
   DVs/factors/data files. Which one wins depends on `interactive_setup`
   and on whether fields are NULL — the user cannot tell what the next run
   will actually do without reading `core_engine.R`.
2. **Global vs project toggles split.** Enabling post-hoc for one project
   means editing a file *outside* the project (`master_mission_control.R`),
   or knowing that `toggles` inside `project_config.R` overrides it.
   Projects are not self-contained or portable.
3. **No record of "what did I change?"** Defaults live in three places
   (engine hard-codes, mission control, template comments). After a month,
   the user can't see which settings deviate from defaults.
4. **Hidden state drives prompts.** With `interactive_setup = TRUE` the
   file pickers and console prompts appear every run (the osascript dialog),
   and their answers land in a YAML the user never opens.
5. **Engine assets masquerade as user config.** `model_presets.yaml` and
   the report `.qmd` are copied into every project, inviting edits and
   drifting from the engine.

## 2. Target design

### 2.1 One user file per project: `projects/<p>/settings.yaml`

A single commented YAML, organised in the order a user thinks, replacing
`project_config.R`, the user-relevant half of `analysis_config.yaml`,
`renaming_dictionary.yaml`, and `derived_attributes.yaml`. Draft schema:

```yaml
# ── Sensanalyser project settings ── everything you edit lives here. ──
project:
  name: example_study

data:
  files: auto            # auto = every csv/xlsx in data/raw; or an explicit list
  # files:
  #   - data/raw/QDA 1.xlsx

variables:
  attributes: auto       # auto-detect numeric columns, or explicit list
  exclude: []            # attributes to leave out of everything
  product: product
  panelist: user
  extra_factors: []

model:
  type: linear_mixed_model   # see run summary for options
  random_effects: [assessor]
  alpha: 0.05
  posthoc: {run: false, method: tukey}

outliers:
  detect: true
  apply_policy: true         # action/grouping under `advanced:` if needed

multivariate:
  pca:  {run: true, significant_only: false}
  hcpc: {run: true, clusters: auto}   # auto | integer | click
  mfa:  {run: false}

outputs:
  tables: true
  figures: true
  report: false              # render Quarto report
  figure: {width: 9, height: 6, dpi: 300}

labels:                      # ← absorbs renaming_dictionary.yaml
  aliases:      {product: {}}
  variables:    {product: Product, user: Panelist}
  levels:       {}
  attributes:   {}           # was `outcomes`

derived_attributes: {}       # ← absorbs derived_attributes.yaml

subsets:                     # ← absorbs product_subsets
  without_control:
    exclude: [Control commercial sample]
```

Design rules:

- **Everything defaultable is optional.** A new project's file can be 15
  lines; the template ships fully commented. `auto` markers make the
  automatic behaviour explicit instead of "NULL means prompt".
- **The pipeline never writes this file** (one exception: an explicit
  `sensanalyser_save_choices()` — see 2.4).
- **Validated on load** with friendly, line-level messages (backport the
  v2.0 `sens_validate_analysis_spec()` approach: unknown keys, bad model
  types, attributes not in the data, subset products that don't exist).

### 2.2 One launcher at the repo root: `run_sensanalyser.R`

`master_mission_control.R` shrinks to a 10-line launcher with **no
settings in it**:

```r
source(here::here("engine", "R", "load_sensanalyser.R"))
run_project("projects/example_study")
# run_projects(c("projects/a", "projects/b"))   # batch runs
```

Global toggles disappear: every switch lives in the project's
`settings.yaml`, so a project folder is fully self-contained and can be
zipped/moved. (Batch-wide overrides, if ever needed, become an explicit
argument: `run_projects(..., override = list(outputs = list(report = TRUE)))`.)

### 2.3 Machine state moves out of sight: `data/dictionary/state/`

Files the *pipeline* owns move to a clearly-named location the user never
edits:

- `state/resolved_run.yaml` — the fully-resolved effective config of the
  last run (audit trail, replaces `analysis_config.yaml`'s role).
- `state/factor_splits.yaml` — unchanged behaviour, relocated.
- `model_presets.yaml` — **removed from projects entirely**; loaded from
  `templates/` (engine asset). Same for the report `.qmd` unless the user
  explicitly copies it in to customise (project copy wins if present).

### 2.4 Interactive setup that writes the *user's* file

First run with `attributes: auto` keeps the guided console flow
(picker/prompts), but the answers are written **into `settings.yaml`
itself** (attributes list, factors, data files) with a `# chosen
interactively on <date>` comment — via `sensanalyser_save_choices()`. After
that, the file is the single truth and no prompts appear. The osascript
picker becomes a rare first-run convenience instead of an every-run ritual.

### 2.5 Visibility: "what did I change?"

Two small functions, printed nicely with cli:

- `settings_summary("projects/example_study")` — the effective
  configuration for the next run **with non-default values highlighted**
  (`model.type: linear_mixed_model  [default: one_way_anova]`), plus data
  files found, attribute count, active subsets, label counts.
- Run header: every pipeline run starts by printing that same summary and
  saving it to `state/resolved_run.yaml`, so outputs are always traceable
  to settings.

## 3. Implementation phases

### Phase A — Config loader + schema (the core) — **DONE**
1. ✅ Schema + defaults in one place (`R/functions/settings_helpers.R`):
   `sensanalyser_default_settings()`, `sensanalyser_load_settings()` (read
   YAML, deep-merge over defaults, validate), `sensanalyser_settings_summary()`.
2. ✅ Adapter `sensanalyser_settings_to_config()` maps the schema onto the
   `final_config` structure `run_sensanalyser_pipeline()` already consumes.
3. ✅ `sensanalyser_run_project()` prefers `settings.yaml`, else falls back to
   `project_config.R` (subset execution shared by both via
   `.sensanalyser_run_config()`).
4. ✅ Also landed: `templates/settings.yaml` (fully commented),
   `run_sensanalyser.R` + `R/load_sensanalyser.R` (thin launcher, item 8),
   `variables.exclude` support in `select_analysis_variables()`, and
   `tests/test_settings_helpers.R` (18 checks).
5. ✅ **Two-sources-of-truth closed**: `config$settings_driven` stops a stale
   `analysis_config.yaml` from overriding settings.yaml in
   `.phase2_data_import()`, and subsets no longer need the saved YAML.

Known quirk found while verifying (pre-existing, unrelated to this work):
`outputs.figures: false` only suppressed the figure module (spider plots);
the PCA and HCPC modules always wrote their own figures. **Fixed in Phase B**
by the per-analysis figure toggles.

### Phase B — Absorb the dictionary files — **DONE**
4. ✅ `labels:` (aliases/variables/levels/attributes) and
   `derived_attributes:` live in settings.yaml. `.sens_materialise_state()`
   resolves them into `data/dictionary/state/`, which the analysis modules
   read by path — so no module had to change. Legacy
   `renaming_dictionary.yaml` / `derived_attributes.yaml` are still honoured
   when the settings sections are empty; settings win when both exist.
5. ✅ `factor_splits.yaml` moves to `state/` on first run (`.dict_path()` in
   `data_cleaning_helpers.R` reads state-first, falls back to the legacy
   location). `model_presets.yaml` and the report `.qmd` are no longer copied
   into new projects: `.sens_engine_asset()` resolves them from `templates/`,
   and a project copy still wins if you want to customise one.
6. ✅ `sensanalyser_create_project()` now writes exactly one file to edit
   (`settings.yaml`, with the project name filled in).

**Per-analysis figure control** (requested during Phase B): `outputs.figures`
accepts `true` / `false` (all figures) or a map with `spider`, `pca`, `hcpc`,
`mfa`. Analyses always compute and write their tables; only the image files
are gated, via `sensanalyser_save_figures(config, kind)`. This also resolves
the quirk noted under Phase A — `figures` is no longer a single flag that
only really affected spider plots.

### Phase C — Migration + new-project flow — **DONE**
6. ✅ `sensanalyser_migrate_project(dir)` (`R/functions/migration_helpers.R`)
   reads `project_config.R` + `analysis_config.yaml` + the dictionary YAMLs
   and writes one `settings.yaml`, retiring superseded files to `*.migrated`
   (gitignored; nothing deleted). It reproduces the engine's own precedence
   (saved selections fill in only when project_config left DVs unset), makes
   data paths project-relative, and warns on obviously-broken saved
   selections (a panelist listed as a factor is dropped; a single-attribute
   DV list is flagged). Item 7 (create_project) landed in Phase B.
7. ✅ `master_mission_control.R` is now a deprecation shim that forwards to
   `run_sensanalyser.R` (kept for one release).
8. ✅ Migrated `example_study` and `example_study_b`. **Acceptance test passed**:
   `example_study` produces byte-identical `outputs/tables/` before and after
   migration (15 files; `run_configuration_summary.csv` excluded as it records
   paths/timestamps). `example_study_b`'s saved selections were genuinely broken (a
   single non-sensory attribute `code`, panelist among the factors) - the
   migration warned and its `attributes:` was set to `auto`.
9. ✅ `tests/test_migration.R` (14 checks).

### Phase D — Interactive setup rewrite + polish — **DONE**
9. ✅ Prompt answers write back into `settings.yaml` via `.sens_write_choices()`:
   after an interactive run the resolved attributes, product/panelist and
   design factors become explicit and `interactive_setup` is turned off, so
   the next run reproduces the choices without prompting. The old
   `analysis_config.yaml` is no longer authoritative — for settings-driven
   runs it is written only into `data/dictionary/state/resolved_run.yaml` as
   an audit record.
10. ✅ `settings_summary()` runs in the launcher header before every run, with
    non-default highlighting (landed in Phase A, used throughout).
11. ✅ Validation polish: nearest-match suggestions for typo'd keys, model
    types and enums (Phase A); plus product == panelist, product repeated as an
    extra factor, and unsupported report formats.
12. ✅ README quick-start rewritten: create a project, edit one file, run one
    line, with a `migrate_project()` note for old projects.

Interactive-setup note: in settings mode the data-file picker never fires (the
adapter always resolves `data.files` to concrete paths), so only variable
selection prompts, and `data.files: auto` is preserved rather than frozen into
an explicit list.

---

## Status: all four phases complete

Both real projects (`example_study`, `example_study_b`) run from `settings.yaml`.
Test suites: `Rscript tests/test_settings_helpers.R` (39 checks) and
`Rscript tests/test_migration.R` (14 checks). example_study output tables are
byte-identical before/after migration.

## 4. Migration & compatibility

- Both config styles coexist until Phase C lands; `settings.yaml` wins if
  both exist (with a warning).
- `.migrated` suffix keeps every old file recoverable; git history covers
  the rest.
- Subset/derived/label semantics are unchanged — only *where* they are
  declared moves — so outputs stay byte-comparable (acceptance check:
  re-run example_study before/after migration, diff `outputs/tables`).

## 5. Explicitly out of scope

- No Shiny/GUI (that's the v2.0 branch).
- No renaming of output folders or table formats.
- No change to statistical behaviour, model presets content, or the report
  template itself.
- No package conversion on main (functions stay `source()`d).

## 6. Risks

| Risk | Mitigation |
|---|---|
| YAML indentation trips users | validator catches unknown/misplaced keys with line numbers; template has copy-paste examples for every section |
| Hidden dependency on `analysis_config.yaml` somewhere in the engine | grep audit done: only `core_engine.R` (load/save) and subsets path read it; both go through the new adapter |
| Comments lost when `sensanalyser_save_choices()` rewrites settings.yaml | write only the `variables:`/`data:` keys via targeted text edit (or keep choices in a clearly-marked block at the bottom) |
| Long-time user muscle memory | old entry points keep working for one release and print where things moved |

Total effort: roughly **5–8 working days**, sequential phases, each leaving
the repo in a runnable state.
