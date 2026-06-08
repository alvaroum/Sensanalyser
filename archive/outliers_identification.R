library(svDialogs)
library(tidyverse)
library(rstatix)

####################### Select file with the data #######################
data <- read.table(file = file.choose(),
                   header = TRUE,
                   sep = ",",
                   dec = ".")

# Create an object with the dependent variables to analyse
# Required: library(svDialogs)
if (!exists("iv")){
  iv <- dlg_list(colnames(data), title = "Select the independent variable")
  iv <- grep(iv$res, colnames(data))
  iv <- c(colnames(data[iv]))
}

# Create an object with the dependent variables to analyse
# Required: library(svDialogs)
if (!exists("dvs")){
  dvs <- dlg_list(colnames(data), title = "Select the first dependent variable")
  dvs <- grep(dvs$res, colnames(data))
  dvs <- c(colnames(data[dvs:ncol(data)]))
}

# Identify outliers looping through the dependent variables
for (each_dv in dvs) {
  if (each_dv == dvs[1]) {
    # Create list to append the results based on the number of dependent variables
    list_outliers <- list()
  }
  outliers <- data %>%
    group_by(!!!syms(iv)) %>%
    select(!!!syms(iv), all_of(each_dv)) %>%
    identify_outliers(each_dv) %>%
    rename(intensity = each_dv)
  list_outliers[[each_dv]] <- add_column(outliers,
                                         dv = each_dv,
                                         .before = 1)
}
# Save only extreme outliers to be filtered from the original data
extreme_outliers <- do.call(rbind, list_outliers) %>%
  filter(is.extreme == TRUE)
# List the products that contain outliers
products_with_outliers <- unique(extreme_outliers$Product)
for (each_product in products_with_outliers) {
  # Start the loop by making a dataframe per product with outliers
  products <- extreme_outliers %>%
    filter(!!!syms(iv) == each_product)
  # From that product, make a list of the attributes with outliers
  attributes_with_outliers <- unique(products$dv)
  for (each_attribute in attributes_with_outliers) {
    # Start this loop making a dataframe per attribute for a the current product
    # with outliers
    attributes <- products %>%
      filter(dv == each_attribute)
    for (each in seq_len(nrow(attributes))) {
      # Then this loop will first look in the dataframe 'attributes' for the
      # value of the intensity of the first attribute with outliers for a
      # specific product. That value will be search in the original data in the
      # column of the current attribute. The function which() will return the
      # row number when the match is TRUE
      rowno <- which(grepl(attributes[each, "intensity"],
                           data[, each_attribute]))
      # Then with the row number, in the original data we change the specific
      # value of the outlier with NA
      data[rowno, each_attribute] <- NA
    }
  }
}
