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

unlink(file.path(proj, "data", "raw", "d.csv"))
settings_yaml("")
check_error("an empty data/raw folder is reported", config(), "No data files found")

cat(sprintf("\nAll %d settings checks passed.\n", passed))
