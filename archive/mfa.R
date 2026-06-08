####PCA

#load library
library(tidyverse)
library(factoextra)
library(FactoMineR)
library(SensoMineR)
install.packages("factoextra")

#Description of each bread 


#load data for PCA
##load data
data <- read.table(file = "White bread profiling raw data.csv", header = TRUE, sep = ",", dec = ".")


####################### PCA using all products ######################

#check that panellist and products are factors
summary(data)
#if factors are not identified as such convert the to factors
data$product <- as.factor(data$product)


####statistical model for analysis with all products together
res.decat <- decat(data, formul = "~ product", firstvar = 5,
                   lastvar = 51, graph = FALSE)
res.pvalue <- res.decat$resF
res.adjmean <- res.decat$adjmean

res.pca <- PCA(res.adjmean,scale.unit = TRUE)

dimdesc(res.pca)



#save results from pvalue and means in csv tables
write.csv(res.adjmean, file = "res.adjmean.attributes.csv")
write.csv(res.pvalue, file = "res.pvalue.attributes.csv")

write.csv(res.ajmean, file = "res.mean.aritmetic.csv")


#SCREE PLOT
fviz_eig(res.pca, addlabels = TRUE, ylim = c(0, 50))

# CHARACTERISTICS OF EACH PRODUCT

res.decat$resT$`Albert Heijn`
res.decat$resT$`Aldi`
res.decat$resT$`Lidl`
res.decat$resT$`Jumbo`
res.decat$resT$`Plus`


#EIGEN VALUES PER COMPONENT
get_eigenvalue(res.pca)

#cluster analysis
res.hcpc <- HCPC(res.pca)

res.hcpc$desc.var$quanti$`1`
res.hcpc$desc.var$quanti$`2`
res.hcpc$desc.var$quanti$`3`


# MFA with means table
data.mfa <- read.table(file = "res.adjmean.attributes.sig.csv", header=TRUE, 
                       sep = ",", dec = ".")

data.mfa <- column_to_rownames(data.mfa, var = "product")

res.mfa.all <- MFA(data.mfa, group = c(12, 1),
                   type = c("s", "s"),
                   name.group = c("Sensory attributes", "liking"))
plot.MFA(res.mfa.all)

#only sig attributes
data.mfa.sig <- data.mfa %>%
  select(unlist(included_attributes), 50:57)

res.mfa.sig <- MFA(data.mfa.sig, group = c(13, 5, 4),
                   type = c("s", "s", "s"),
                   name.group = c("Sensory attributes", "liking"))
plot.MFA(res.mfa.sig)
