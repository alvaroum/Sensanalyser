library(tidyverse)
library(rstatix)
library(emmeans)

data <- read.table(file = "DATA set pasta.csv", header=TRUE, 
                  sep = ",", dec = ".")
# data <- rowid_to_column(data, "id")

# Create an object with the dependent variables to analyse
dvs <- c(colnames(data[6:ncol(data)]))

# Create list to append the results based on the number of dependent variables
aov.res <- vector(mode = "list", length = length(dvs))

# Start a counter
i <- 1

#rm(list = c('sig.dif.v1', 'sig.dif.v2'))

# ANOVA loop
for (each_dv in dvs) {
  if (i == 1){
    rm(nfactors, each, each_factor, formula, len)
  }
  formula <- as.formula(paste0(each_dv, " ~ Participant + Sample"))
  res.aov <- anova_test(data, formula)
  #print(each_dv)
  #print(res.aov)
  aov.res[[i]] <- add_column(res.aov,
                             dv = each_dv,
                             .before = 1)
  # When there is a significant difference, store the dependent variable for 
  # post-hoc analyses
  if (!exists("nfactors")){
    nfactors <- length(res.aov$p)
    sig.dif <- vector(mode = "list", length = nfactors)
    for (each in seq_along(1:nfactors)){
      sig.dif[[each]] <- vector(mode = "list")
    }
  }
  for (each_factor in seq_along(1:nfactors)){ # The use of seq_along is the key to be able to use the reference number in other parts
    if (res.aov$p[each_factor] < 0.05) {
      len <- as.numeric(length(sig.dif[[each_factor]]))
      sig.dif[[each_factor]][[len + 1]] <- c(each_dv)
    }
  }
  i <- i + 1
}

anova.table <- do.call(rbind, aov.res)

write.csv(anova.table, file = "anova.csv")

# Post-hocs Fisher LSD
included_attributes <- sig.dif[[1]]

options(contrasts=c("contr.sum", "contr.sum"))
for (attribute in included_attributes) {
  formula <- as.formula(paste0(attribute, "~ product + user"))
  model <- aov(formula, data)
  res.LSD <- LSD.test(model,"product", p.adj="none", group=TRUE, main="Results of the Fisher LSD")
  temp.df <- res.LSD$groups
  if (exists("final.df")) {
    final.df <- merge(final.df, temp.df, by = 0)
    rownames(final.df) <- final.df[,1]
    final.df[,1] <- NULL
  } else {
    final.df <- temp.df
  }
  # Remove temporary objects for LSD
  rm(temp.df, model, res.LSD, attribute, formula)
}
write.csv(final.df, file = "posthocs.breads.csv")