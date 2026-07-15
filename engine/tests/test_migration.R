# ==========================================================================
# TESTS: legacy project -> settings.yaml migration
# ==========================================================================
#
# Run from the repo root:  Rscript tests/test_migration.R

suppressMessages({ library(cli); library(yaml); library(here) })
source(here::here("engine", "R", "functions", "settings_helpers.R"))
source(here::here("engine", "R", "functions", "project_helpers.R"))
source(here::here("engine", "R", "functions", "migration_helpers.R"))

passed <- 0L
check <- function(label, ...) { stopifnot(...); passed <<- passed + 1L; cat("ok  ", label, "\n") }
check_error <- function(label, expr, pattern) {
  msg <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  if (is.null(msg)) stop("expected an error for: ", label)
  flat <- gsub("\\s+", " ", paste(msg, collapse = " "))
  if (!grepl(pattern, flat)) stop("wrong error for ", label, ": ", flat)
  passed <<- passed + 1L; cat("ok  ", label, "\n")
}

make_project <- function(pc_lines, saved = NULL, dict = NULL, derived = NULL) {
  proj <- file.path(tempdir(), paste0("mig_", as.integer(Sys.time()), sample(1e6, 1)))
  dir.create(file.path(proj, "data", "raw"), recursive = TRUE)
  dir.create(file.path(proj, "data", "dictionary"), recursive = TRUE)
  writeLines("user,product,sweet_a\na,P1,1", file.path(proj, "data", "raw", "d.csv"))
  writeLines(pc_lines, file.path(proj, "project_config.R"))
  if (!is.null(saved)) yaml::write_yaml(saved, file.path(proj, "data", "dictionary", "analysis_config.yaml"))
  if (!is.null(dict)) yaml::write_yaml(dict, file.path(proj, "data", "dictionary", "renaming_dictionary.yaml"))
  if (!is.null(derived)) yaml::write_yaml(derived, file.path(proj, "data", "dictionary", "derived_attributes.yaml"))
  proj
}

basic_pc <- c(
  "project_config <- list(",
  "  toggles = list(interactive_setup = TRUE, run_posthoc = TRUE),",
  "  paths = list(raw_data = NULL),",
  "  analysis = list(dependent_variables = c('sweet_a','sour_a'),",
  "                  factors = c('product'), subject_id = 'user',",
  "                  model_type = 'two_way_anova', hcpc_n_clusters = 4,",
  "                  posthoc_method = 'lsd'),",
  "  product_subsets = list(without_control = list(exclude = c('Control'))),",
  "  fig_options = list(width = 8)",
  ")",
  "project_config"
)

# ── Explicit project_config.R wins ────────────────────────────────────────
proj <- make_project(basic_pc)
sensanalyser_migrate_project(proj)
s <- sensanalyser_load_settings(proj)
check("model, factors and subject come from project_config.R",
      identical(s$model$type, "two_way_anova"),
      identical(unlist(s$variables$attributes), c("sweet_a", "sour_a")),
      identical(s$variables$product, "product"),
      identical(s$variables$panelist, "user"))
check("hcpc integer and posthoc are carried over",
      identical(s$multivariate$hcpc$clusters, 4L),
      isTRUE(s$model$posthoc$run),
      identical(s$model$posthoc$method, "lsd"))
check("interactive_setup is switched off",
      isFALSE(s$advanced$interactive_setup))
check("subsets and figure options carry over",
      identical(unlist(s$subsets$without_control$exclude), "Control"),
      identical(s$outputs$figure$width, 8))
check("legacy files are retired to *.migrated, not deleted",
      !file.exists(file.path(proj, "project_config.R")),
      file.exists(file.path(proj, "project_config.R.migrated")))
check_error("re-migrating without overwrite is refused",
            sensanalyser_migrate_project(proj), "already exists")
# overwrite = TRUE replaces an existing settings.yaml (fresh project, since a
# migrated project's legacy sources are already retired).
proj_ow <- make_project(basic_pc)
writeLines("project: {name: stale}", file.path(proj_ow, "settings.yaml"))
check("overwrite = TRUE replaces an existing settings.yaml",
      is.character(sensanalyser_migrate_project(proj_ow, overwrite = TRUE)),
      identical(sensanalyser_load_settings(proj_ow)$model$type, "two_way_anova"))

# ── Saved analysis_config.yaml fills in when DVs are NULL ──────────────────
pc_null <- c(
  "project_config <- list(",
  "  toggles = list(interactive_setup = TRUE),",
  "  paths = list(raw_data = NULL),",
  "  analysis = list(dependent_variables = NULL, factors = NULL),",
  "  fig_options = list()",
  ")",
  "project_config"
)
saved <- list(
  meta = list(data_file = "irrelevant.csv"),
  analysis = list(dependent_variables = c("sweet_a", "sour_a"),
                  factors = "product", subject_id = "user",
                  model_type = "linear_mixed_model",
                  random_effects = "user"),
  toggles = list(run_pca = FALSE, run_hcpc = TRUE, run_mixed_models = TRUE)
)
proj <- make_project(pc_null, saved = saved)
sensanalyser_migrate_project(proj)
s <- sensanalyser_load_settings(proj)
check("saved selections fill in when project_config leaves DVs null",
      identical(unlist(s$variables$attributes), c("sweet_a", "sour_a")),
      identical(s$variables$product, "product"),
      identical(unlist(s$model$random_effects), "user"),
      isFALSE(s$multivariate$pca$run),
      isTRUE(s$multivariate$hcpc$run))

# ── The template analysis_config.yaml is ignored ──────────────────────────
proj <- make_project(pc_null, saved = list(
  meta = list(data_file = "x"),
  analysis = list(dependent_variables = c("attribute_1", "attribute_2", "attribute_3"))
))
sensanalyser_migrate_project(proj)
s <- sensanalyser_load_settings(proj)
check("placeholder template selections do not migrate as attributes",
      identical(s$variables$attributes, "auto"))

# ── A panelist wrongly listed as a factor is dropped, with a warning ──────
proj <- make_project(pc_null, saved = list(
  meta = list(data_file = "x"),
  analysis = list(dependent_variables = c("sweet_a", "sour_a"),
                  factors = c("user", "product"), subject_id = "user")
))
suppressMessages(sensanalyser_migrate_project(proj))
s <- sensanalyser_load_settings(proj)
check("a panelist listed as a factor is removed from the factors",
      identical(s$variables$product, "product"),
      !("user" %in% unlist(s$variables$extra_factors)))

# ── Labels and derived attributes are absorbed ────────────────────────────
proj <- make_project(
  basic_pc,
  dict = list(variables = list(product = "Product"),
              outcomes = list(sweet_a = "Sweetness"),
              aliases = list(product = list(p1 = "P1"))),
  derived = list(derived_attributes = list(
    overall = list(label = "Overall", method = "mean",
                   source_variables = c("sweet_a", "sour_a"))))
)
sensanalyser_migrate_project(proj)
s <- sensanalyser_load_settings(proj)
check("dictionary labels move into settings.labels",
      identical(s$labels$variables$product, "Product"),
      identical(s$labels$attributes$sweet_a, "Sweetness"),
      identical(s$labels$aliases$product$p1, "P1"))
check("derived definitions move into settings.derived_attributes",
      identical(s$derived_attributes$overall$label, "Overall"),
      identical(unlist(s$derived_attributes$overall$source_variables),
                c("sweet_a", "sour_a")))
check("the dictionary files are retired",
      file.exists(file.path(proj, "data/dictionary/renaming_dictionary.yaml.migrated")),
      file.exists(file.path(proj, "data/dictionary/derived_attributes.yaml.migrated")))

# ── Nothing to migrate ────────────────────────────────────────────────────
empty <- file.path(tempdir(), paste0("mig_empty_", as.integer(Sys.time())))
dir.create(empty, recursive = TRUE)
check_error("an empty folder reports nothing to migrate",
            sensanalyser_migrate_project(empty), "Nothing to migrate")

cat(sprintf("\nAll %d migration checks passed.\n", passed))
