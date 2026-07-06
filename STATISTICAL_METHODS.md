# Sensanalyser Statistical Methods

This document details the statistical methodologies, models, and formulas implemented within the Sensanalyser pipeline. It covers both descriptive and comparative (inferential) analyses, lists the R packages used, and points to the specific code modules where they are executed.

---

## 1. Descriptive Statistics

**File:** `R/functions/descriptive_helpers.R`
**Packages Used:** `dplyr`, `tidyr`, `purrr`

For each numeric dependent variable (sensory attribute), the pipeline computes descriptive summaries grouped by the selected fixed factors (e.g., `product`).

**Metrics Calculated:**
*   **Mean ($\bar{x}$):** The arithmetic average of the scores.
*   **Standard Deviation (SD):** The measure of dispersion/variation within the group.
*   **Standard Error of the Mean (SE):** Calculated as $SE = \frac{SD}{\sqrt{n}}$, where $n$ is the number of valid (non-missing) observations.

The pipeline automatically generates both long-format outputs (useful for programmatic plotting) and wide-format tables (means only, or means ± SE, useful for direct insertion into reports).

---

## 2. Statistical Models (Comparative Analysis)

**File:** `R/functions/model_helpers.R`

The pipeline supports three distinct modeling routes for evaluating differences in sensory attributes across products. The model used is determined by the `model_type` setting in `project_config.R`.

### A. One-Way ANOVA
*   **Best for:** Independent observations (e.g., consumer tests where each consumer evaluates only one product).
*   **Model Formula:** $Y_{ij} = \mu + \alpha_i + \epsilon_{ij}$
    *   $Y_{ij}$: The sensory score for the $j$-th observation of the $i$-th product.
    *   $\mu$: The grand mean.
    *   $\alpha_i$: The fixed effect of the $i$-th product.
    *   $\epsilon_{ij}$: The residual error.
*   **Implementation:** Handled via `rstatix::anova_test(dv ~ factor, data = data)`. It computes Type II/III Sums of Squares and returns the standard $F$-statistic and $p$-value.

### B. Repeated-Measures ANOVA
*   **Best for:** Balanced trained panel data where every assessor evaluates every product (complete block design).
*   **Model Formula:** $Y_{ijk} = \mu + \alpha_i + \pi_j + \epsilon_{ijk}$
    *   $\pi_j$: The systematic effect (or within-subject correlation) of the $j$-th assessor.
*   **Implementation:** Handled via `afex::aov_car(dv ~ factor + Error(subject / factor), data = data)`. This automatically applies the Greenhouse-Geisser correction to the degrees of freedom if the sphericity assumption is violated.

### C. Linear Mixed Models (LMM)
*   **Best for:** Sensory panel data, especially when there are missing values, incomplete blocks, or complex nested structures (e.g., sessions and replicates).
*   **Model Formula:** $Y_{ijk} = \mu + \alpha_i + b_j + \epsilon_{ijk}$
    *   $\alpha_i$: Fixed effect of the product.
    *   $b_j$: Random intercept for the assessor, assumed to be normally distributed: $b_j \sim N(0, \sigma^2_b)$.
*   **Implementation:** Handled via `lmerTest::lmer(dv ~ factor + (1 | subject), data = data)`. The pipeline extracts the ANOVA table using Satterthwaite's approximation for degrees of freedom, which yields highly robust $p$-values even with unbalanced sensory data.

---

## 3. Post-Hoc Pairwise Comparisons

**File:** `R/functions/posthoc_helpers.R`
**Packages Used:** `emmeans`, `multcompView`

When an omnibus model (from Section 2) shows a significant main effect or interaction, the pipeline automatically runs post-hoc tests to determine *which specific products* differ from each other.

**Methodology:**
1.  **Estimated Marginal Means (EMMs):** The pipeline uses `emmeans::emmeans()` to calculate the predicted means for each product, adjusted for the model structure (e.g., accounting for assessor variance in mixed models).
2.  **Pairwise Differences:** It computes the contrasts (differences) between all possible pairs of products.
3.  **P-value Adjustment:** The user specifies the `posthoc_method` in `project_config.R`:
    *   **Tukey HSD:** Controls the family-wise error rate across all pairwise comparisons.
    *   **Bonferroni:** A more conservative correction ($p_{adj} = p \times m$).
    *   **LSD (None):** Unadjusted Fisher's Least Significant Difference.
4.  **Compact Letter Display:** Uses `multcompView::multcompLetters()` to assign significance letters (e.g., "a", "ab", "b"). Products sharing a letter are not significantly different at the chosen $\alpha$ level (default: 0.05).

---

## 4. Multivariate Analysis

### A. Principal Component Analysis (PCA)
**File:** `R/functions/pca_helpers.R`
**Packages Used:** `FactoMineR`, `factoextra`

*   **Methodology:** The pipeline averages the dataset by product, scaling the variables to unit variance ($z$-scores). It computes the correlation matrix and extracts eigenvalues and eigenvectors.
*   **Outputs:** 
    *   **Scores:** Product coordinates in the new PC space (Dimension 1, 2, etc.).
    *   **Loadings:** Variable correlations with the principal components (visualized as a Correlation Circle).
*   **Implementation:** Handled via `FactoMineR::PCA(X, scale.unit = TRUE)`.

### B. Hierarchical Clustering on Principal Components (HCPC)
**File:** `R/functions/hcpc_helpers.R`
**Packages Used:** `FactoMineR`, `stats`

*   **Methodology:** Using the product scores generated by the PCA, the pipeline builds a hierarchical tree (dendrogram) using **Ward's minimum variance method**. Ward's method minimizes the total within-cluster variance.
*   **Cluster Cut:** The tree can be cut automatically (based on inertia gain), manually at a specific $k$ value, or interactively by clicking the dendrogram plot.
*   **Implementation:** Handled via `FactoMineR::HCPC(pca_fit, nb.clust, consol = FALSE)`. The base dendrogram is drawn using `stats::hclust(dist(coord), method = "ward.D2")`.
