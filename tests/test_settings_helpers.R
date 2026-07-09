# ==========================================================================
# TESTS: settings.yaml schema, validation and adapter
# ==========================================================================
#
# Run from the repo root:  Rscript tests/test_settings_helpers.R
#
# No testthat/package machinery: main is a script-based project, so these are
# plain assertions that fail loudly.

suppressMessages({ library(cli); library(yaml) })
source(file.path("R", "functions", "settings_helpers.R"))

passed <- 0L
check <- function(label, ...) {
  stopifnot(...)
  passed <<- passed + 1L
  cat("ok  ", label, "\n")
}
check_error <- function(label, expr, pattern) {
  msg <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  if (is.null(msg)) stop("expected an error for: ", label)
  flat <- gsub("\\s+", " ", paste(msg, collapse = " "))  # cli hard-wraps
  if (!grepl(pattern, flat)) stop("wrong error for ", label, ": ", flat)
  passed <<- passed + 1L
  cat("ok  ", label, "\n")
}

proj <- file.path(tempdir(), paste0("sens_settings_test_", Sys.getpid()))
dir.create(file.path(proj, "data", "raw"), recursive = TRUE, showWarnings = FALSE)
writeLines("user,product,sweet", file.path(proj, "data", "raw", "d.csv"))
on.exit(unlink(proj, recursive = TRUE), add = TRUE)

settings_yaml <- function(...) {
  writeLines(c(...), file.path(proj, "settings.yaml"))
  invisible(NULL)
}
load <- function() sensanalyser_load_settings(proj)
config <- function() sensanalyser_settings_to_config(load())

# ── Defaults and merging ──────────────────────────────────────────────────
settings_yaml("")
s <- load()
check("an empty settings.yaml yields the defaults",
      identical(s$model$type, "linear_mixed_model"),
      identical(s$variables$attributes, "auto"),
      identical(s$project$name, basename(proj)),
      isTRUE(s$outputs$tables))

settings_yaml("model:", "  type: two_way_anova", "  posthoc:", "    run: true")
s <- load()
check("a partial file keeps every untouched default",
      identical(s$model$type, "two_way_anova"),
      isTRUE(s$model$posthoc$run),
      identical(s$model$posthoc$method, "tukey"),
      identical(s$model$alpha, 0.05))

# ── Validation ────────────────────────────────────────────────────────────
settings_yaml("model:", "  typ: two_way_anova")
check_error("a typo'd key suggests the right one", load(), "did you mean 'type'")

settings_yaml("model:", "  type: two_way_anva")
check_error("a typo'd model type suggests the right one", load(), "did you mean 'two_way_anova'")

settings_yaml("outliers:", "  policy: remove_everything")
check_error("an invalid enum is rejected", load(), "outliers.policy")

settings_yaml("model:", "  alpha: 1.5")
check_error("alpha outside (0, 1) is rejected", load(), "between 0 and 1")

settings_yaml("multivariate:", "  hcpc:", "    clusters: 1")
check_error("fewer than 2 clusters is rejected", load(), "clusters must be")

settings_yaml("outputs:", "  tables: maybe")
check_error("a non-logical toggle is rejected", load(), "must be true or false")

settings_yaml("subsets:", "  bad:", "    keep: [A]")
check_error("a subset needs include or exclude", load(), "include.*exclude")

settings_yaml("subsets:", "  bad:", "    include: [A]", "    exclude: [B]")
check_error("a subset cannot have both", load(), "only one")

settings_yaml("subsets:", "  without_control:", "    exclude: [Control]",
              "outputs:", "  spider:", "    comparisons:", "      a_vs_b: [A, B]")
s <- load()
check("free-form sections accept user-invented names",
      identical(s$subsets$without_control$exclude, "Control"),
      identical(s$outputs$spider$comparisons$a_vs_b, c("A", "B")))

# ── Adapter ───────────────────────────────────────────────────────────────
for (pair in list(c("auto", "-1"), c("click", "0"))) {
  settings_yaml("multivariate:", "  hcpc:", paste0("    clusters: ", pair[[1]]))
  check(sprintf("hcpc clusters '%s' maps to %s", pair[[1]], pair[[2]]),
        identical(as.character(config()$analysis$hcpc_n_clusters), pair[[2]]))
}
settings_yaml("multivariate:", "  hcpc:", "    clusters: 4")
check("a fixed cluster count passes through",
      identical(config()$analysis$hcpc_n_clusters, 4L))

settings_yaml("variables:", "  exclude: [hay_a, rancid_a]",
              "model:", "  run_mixed: false", "  run_anova: true",
              "multivariate:", "  mfa:", "    run: true")
cfg <- config()
check("settings map onto the engine's config",
      length(cfg$paths$raw_data) == 1L,
      basename(cfg$paths$raw_data) == "d.csv",
      isTRUE(cfg$toggles$run_anova_models),
      isFALSE(cfg$toggles$run_mixed_models),
      isTRUE(cfg$toggles$run_mfa),
      isTRUE(cfg$settings_driven),
      identical(cfg$analysis$exclude_attributes, c("hay_a", "rancid_a")),
      identical(cfg$analysis$dependent_variables, "auto"),
      identical(cfg$analysis$factors, "product"),
      identical(cfg$analysis$subject_id, "user"))

settings_yaml("variables:", "  attributes: [sweet, sour, bitter]", "  exclude: [sour]")
check("an explicit attribute list honours exclude",
      identical(config()$analysis$dependent_variables, c("sweet", "bitter")))

settings_yaml("data:", "  files: [data/raw/nope.csv]")
check_error("a missing data file is reported", config(), "not found")

# ── Figures, per analysis ─────────────────────────────────────────────────
settings_yaml("")
check("all figures are on by default",
      identical(load()$outputs$figures,
                list(spider = TRUE, pca = TRUE, hcpc = TRUE, mfa = TRUE)))

settings_yaml("outputs:", "  figures: false")
s <- load()
check("`figures: false` switches every figure off",
      all(!unlist(s$outputs$figures)),
      isFALSE(sensanalyser_save_figures(sensanalyser_settings_to_config(s), "pca")))

settings_yaml("outputs:", "  figures: true")
check("`figures: true` switches every figure on",
      all(unlist(load()$outputs$figures)))

settings_yaml("outputs:", "  figures:", "    pca: false", "    mfa: false")
s <- load(); cfg <- sensanalyser_settings_to_config(s)
check("figures can be chosen per analysis",
      isTRUE(s$outputs$figures$spider), isFALSE(s$outputs$figures$pca),
      isTRUE(s$outputs$figures$hcpc),   isFALSE(s$outputs$figures$mfa),
      isTRUE(cfg$toggles$create_figures),                 # spider module on
      isTRUE(sensanalyser_save_figures(cfg, "hcpc")),
      isFALSE(sensanalyser_save_figures(cfg, "pca")),
      isFALSE(sensanalyser_save_figures(cfg, "mfa")))

settings_yaml("outputs:", "  figures:", "    spider: false")
check("spider figures off means create_figures is off",
      isFALSE(sensanalyser_settings_to_config(load())$toggles$create_figures))

settings_yaml("outputs:", "  figures:", "    pcaa: false")
check_error("a typo'd figure kind is caught", load(), "did you mean 'pca'")

check("legacy configs without figure_toggles still save figures",
      isTRUE(sensanalyser_save_figures(list(), "pca")))

# ── Labels and derived attributes are materialised into state/ ────────────
settings_yaml(
  "labels:",
  "  variables:",
  "    product: Product",
  "  attributes:",
  "    sweet_a: Sweetness (Aroma)",
  "  aliases:",
  "    product:",
  "      bread_a: Bread A",
  "derived_attributes:",
  "  overall_fruity:",
  "    label: Overall Fruity",
  "    method: mean",
  "    source_variables: [stone_fruits_a, tropical_a]"
)
cfg <- config()
# The loader normalises the project root (on macOS /var -> /private/var).
proj_norm <- normalizePath(proj)
state_dir <- file.path(proj_norm, "data", "dictionary", "state")
check("state/ holds the resolved dictionary and derived attributes",
      identical(cfg$paths$renaming_dictionary,
                file.path(state_dir, "renaming_dictionary.yaml")),
      identical(cfg$paths$derived_attributes,
                file.path(state_dir, "derived_attributes.yaml")),
      file.exists(cfg$paths$renaming_dictionary),
      file.exists(cfg$paths$derived_attributes))

dict <- yaml::read_yaml(cfg$paths$renaming_dictionary)
check("labels.attributes is written as the engine's outcomes",
      identical(dict$outcomes$sweet_a, "Sweetness (Aroma)"),
      identical(dict$variables$product, "Product"),
      identical(dict$aliases$product$bread_a, "Bread A"))

derived <- yaml::read_yaml(cfg$paths$derived_attributes)
check("derived attribute definitions round-trip",
      identical(derived$derived_attributes$overall_fruity$label, "Overall Fruity"),
      identical(derived$derived_attributes$overall_fruity$source_variables,
                c("stone_fruits_a", "tropical_a")))

check_error("a derived attribute needs two sources",
            { settings_yaml("derived_attributes:", "  x:", "    source_variables: [a]"); load() },
            "at least two attributes")

check_error("an unsupported derived method is caught",
            { settings_yaml("derived_attributes:", "  x:", "    method: median",
                            "    source_variables: [a, b]"); load() },
            "only 'mean'")

# Legacy dictionary files are still honoured when settings define no labels.
writeLines(c("outcomes:", "  sweet_a: Legacy Label"),
           file.path(proj, "data", "dictionary", "renaming_dictionary.yaml"))
settings_yaml("")
dict <- yaml::read_yaml(config()$paths$renaming_dictionary)
check("a legacy renaming_dictionary.yaml is still used",
      identical(dict$outcomes$sweet_a, "Legacy Label"))

# Settings win over the legacy file.
settings_yaml("labels:", "  attributes:", "    sweet_a: New Label")
dict <- yaml::read_yaml(config()$paths$renaming_dictionary)
check("settings.yaml labels override the legacy file",
      identical(dict$outcomes$sweet_a, "New Label"))

# factor_splits.yaml is pipeline-owned and moves into state/
writeLines(c("product: {}"), file.path(proj, "data", "dictionary", "factor_splits.yaml"))
invisible(config())
check("factor_splits.yaml is relocated into state/",
      file.exists(file.path(state_dir, "factor_splits.yaml")),
      !file.exists(file.path(proj, "data", "dictionary", "factor_splits.yaml")))

# Engine assets resolve from templates/ unless the project overrides them
cfg <- config()
check("model presets and report template come from templates/",
      grepl("templates", cfg$paths$model_presets, fixed = TRUE),
      grepl("templates", cfg$paths$report_template, fixed = TRUE))

dir.create(file.path(proj, "reports"), showWarnings = FALSE)
writeLines("---", file.path(proj, "reports", "sensanalyser_results_report.qmd"))
check("a project copy of the report template wins",
      identical(config()$paths$report_template,
                file.path(proj_norm, "reports", "sensanalyser_results_report.qmd")))

# ── Validation polish ─────────────────────────────────────────────────────
settings_yaml("variables:", "  product: user", "  panelist: user")
check_error("product == panelist is rejected", load(), "must be different columns")

settings_yaml("variables:", "  product: product", "  extra_factors: [product]")
check_error("product repeated as an extra factor is rejected", load(), "only as the product")

settings_yaml("outputs:", "  report_formats: [html, pptx]")
check_error("an unsupported report format is rejected", load(), "not supported")

# ── Write choices back (interactive run -> explicit settings.yaml) ─────────
settings_yaml(
  "project:", "  name: demo",
  "variables:", "  attributes: auto", "  product: product", "  panelist: user",
  "model:", "  type: two_way_mixed",
  "outputs:", "  figures:", "    pca: false",
  "advanced:", "  interactive_setup: true"
)
resolved <- list(
  dependent_variables = c("sweet_a", "sour_a"),
  factors = c("product", "session"),
  subject_id = "assessor",
  repeated_measures_factors = "product",
  random_effects = "assessor",
  blocking_factors = character(0)
)
.sens_write_choices(proj, resolved)
s <- load()
check("interactive choices are written back into settings.yaml",
      identical(unlist(s$variables$attributes), c("sweet_a", "sour_a")),
      identical(s$variables$product, "product"),
      identical(unlist(s$variables$extra_factors), "session"),
      identical(s$variables$panelist, "assessor"),
      identical(unlist(s$model$random_effects), "assessor"),
      identical(unlist(s$model$repeated_measures), "product"),
      isFALSE(s$advanced$interactive_setup),
      identical(s$model$type, "two_way_mixed"),   # untouched setting kept
      isFALSE(s$outputs$figures$pca))             # untouched setting kept

# ── The 'ask' sentinel maps to NULL so the engine prompts ─────────────────
settings_yaml(
  "data:", "  files: ask",
  "variables:", "  attributes: ask", "  product: ask", "  panelist: ask"
)
cfg <- config()
check("ask on data/variables becomes NULL (engine will prompt)",
      is.null(cfg$paths$raw_data),
      is.null(cfg$analysis$dependent_variables),
      is.null(cfg$analysis$factors),
      is.null(cfg$analysis$subject_id))

settings_yaml("variables:", "  product: ask", "  panelist: ask")
check("two ask sentinels do not trip the product == panelist check",
      is.list(sensanalyser_settings_to_config(load())))

unlink(file.path(proj, "data", "raw", "d.csv"))
settings_yaml("")
check_error("an empty data/raw folder is reported", config(), "No data files found")

cat(sprintf("\nAll %d settings checks passed.\n", passed))
