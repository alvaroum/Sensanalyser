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
source(here::here("R", "load_sensanalyser.R"))
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

### Phase A — Config loader + schema (the core, ~2–3 days)
1. Define the schema + defaults in one place (`R/functions/settings_helpers.R`):
   `default_settings()`, `load_settings(project_dir)` (read YAML, deep-merge
   over defaults, validate, normalise paths), `settings_summary()`.
2. Internal adapter `settings_to_config()` mapping the new schema onto the
   existing `final_config` structure `run_sensanalyser_pipeline()` already
   consumes — **no engine module changes needed** in this phase.
3. `sensanalyser_run_project()` prefers `settings.yaml` when present, else
   falls back to `project_config.R` (backward compatible during migration).

### Phase B — Absorb the dictionary files (~1–2 days)
4. `labels:` and `derived_attributes:` sections feed the existing loaders
   (`load_renaming_dictionary()` gets a sibling that reads from settings).
   Old YAMLs still honoured if the section is absent, with a deprecation
   note in the run header.
5. Move `factor_splits.yaml` to `state/`; stop copying `model_presets.yaml`
   and the `.qmd` template into new projects (resolve from `templates/`,
   project copy overrides).

### Phase C — Migration + new-project flow (~1 day)
6. `sensanalyser_migrate_project(dir)` — reads existing
   `project_config.R` + dictionary YAMLs + `analysis_config.yaml` and
   writes a consolidated `settings.yaml`; renames superseded files to
   `*.migrated` (nothing deleted). Run it on `example_study` and
   `example_study_b` as the acceptance test.
7. `sensanalyser_create_project()` writes the new template
   (`settings.yaml` + folders only); its "Next steps" message becomes:
   *drop data in `data/raw`, open `settings.yaml`, run `run_project()`*.
8. Replace `master_mission_control.R` with the thin launcher (keep the old
   file for one release with a pointer message).

### Phase D — Interactive setup rewrite + polish (~1–2 days)
9. Prompt answers write into `settings.yaml` (2.4); kill the hidden
   `analysis_config.yaml` write path.
10. `settings_summary()` in the run header; non-default highlighting.
11. Friendly validation errors for the top 10 user mistakes (typo'd key,
    attribute not in data, subset product misspelled — suggest nearest
    match with `utils::adist`).
12. README quick-start rewrite: one page — create project, edit one file,
    run one line.

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
