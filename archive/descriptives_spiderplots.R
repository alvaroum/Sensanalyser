library(tidyverse)
library(rstatix)
library(plotrix)
library(fmsb)

###### Compute arithmetic mean per product
data.means <- data %>%
  group_by(!!!syms(iv)) %>%
  select(!!!syms(iv), !!!syms(dvs)) %>%
  summarise(across(where(is.numeric), ~ mean(.x, na.rm = TRUE)))

write.csv(data.means, file = "03. results/data_means.csv")

##### Spiderplots per product and selecting only the 10 most intense attributes

# First make a variable with the list of products
products <- data.means[[iv]]
p <- c("Bocker_Barley 105 6.3% ")
data.prod <- data.means %>%
  filter(.[[iv]] == p)

data.prod <- data.prod %>%
  pivot_longer(!{{iv}}, names_to = "Attributes", values_to = "Intensity") %>%
  arrange(desc(Intensity)) %>%
  slice(10:nrow(data.prod)) %>%
  pivot_wider(names_from = Attributes, values_from = Intensity)
minrow <- data.frame(matrix(rep(0, (ncol(data.prod) - 1)), nrow = 1))
minrow <- add_column(minrow, "Min", .before = 1)
colnames(minrow) <- colnames(data.prod)
data.prod <- rbind(minrow, data.prod)
maxrow <- data.frame(matrix(rep(100, (ncol(data.prod) - 1)), nrow = 1))
maxrow <- add_column(maxrow, "Max", .before = 1)
colnames(maxrow) <- colnames(data.prod)
data.prod <- rbind(maxrow, data.prod)
data.prod <- column_to_rownames(data.prod, {{iv}})

for (p in products) {
  data.prod <- data.means %>%
    filter(.[[iv]] == p)%>%
    pivot_longer(!{{iv}}, names_to = "Attributes", values_to = "Intensity") %>%
    arrange(desc(Intensity)) %>%
    slice(10:nrow(data.prod)) %>%
    pivot_wider(names_from = Attributes, values_from = Intensity)
  minrow <- data.frame(matrix(rep(0, (ncol(data.prod) - 1)), nrow = 1))
  minrow <- add_column(minrow, "Min", .before = 1)
  colnames(minrow) <- colnames(data.prod)
  data.prod <- rbind(minrow, data.prod)
  maxrow <- data.frame(matrix(rep(50, (ncol(data.prod) - 1)), nrow = 1))
  maxrow <- add_column(maxrow, "Max", .before = 1)
  colnames(maxrow) <- colnames(data.prod)
  data.prod <- rbind(maxrow, data.prod)
  data.prod <- column_to_rownames(data.prod, {{iv}})
  # Reduce plot margin using par()
  op <- par(mar = c(1, 2, 2, 2))
  # Create the radar charts
  create_beautiful_radarchart(
    data = data.prod, caxislabels = c(0, 12.5, 25, 37.5, 50),
    color = c("#00AFBB", "#E7B800", "#FC4E07", "#00B1FF")
  )
  # Add an horizontal legend
 legend(
   x = "bottom", legend = rownames(data.prod[-c(1,2),]), horiz = TRUE,
   bty = "n", pch = 20 , col = c("#00AFBB", "#E7B800", "#FC4E07", "#00B1FF"),
   text.col = "black", cex = 1, pt.cex = 1.5
  )
  par(op)
}

newrow <- data.frame(matrix(rep(0, (ncol(data.means) - 1)), nrow = 1))
newrow <- add_column(newrow, "Min", .before = 1)
colnames(newrow) <- colnames(data.means)
data.means <- rbind(newrow, data.means)

newrow <- data.frame(matrix(rep(9, (ncol(data.means) - 1)), nrow = 1))
newrow <- add_column(newrow, "Max", .before = 1)
colnames(newrow) <- colnames(data.means)
data.means <- rbind(newrow, data.means)

data.means <- column_to_rownames(data.means, "Sample")

data.appearance <- data.means %>%
  select(starts_with("Appearance"))

data.aroma <- data.means %>%
  select(starts_with("Aroma"))

data.flavour <- data.means %>%
  select(starts_with("Flavour"))

data.texture <- data.means %>%
  select(starts_with("Texture"))

# Reduce plot margin using par()
op <- par(mar = c(1, 2, 2, 2))
# Create the radar charts
create_beautiful_radarchart(
  data = data.texture, caxislabels = c(0, 2.25, 4.5, 6.75, 9),
  color = c("#00AFBB", "#E7B800", "#FC4E07", "#00B1FF")
)
# Add an horizontal legend
legend(
  x = "bottom", legend = rownames(df[-c(1,2),]), horiz = TRUE,
  bty = "n", pch = 20 , col = c("#00AFBB", "#E7B800", "#FC4E07", "#00B1FF"),
  text.col = "black", cex = 1, pt.cex = 1.5
)
par(op)







create_beautiful_radarchart <- function(data, color = "#00AFBB", 
                                        vlabels = colnames(data), vlcex = 0.7,
                                        caxislabels = NULL, title = NULL, ...){
  radarchart(
    data, axistype = 1,
    # Customize the polygon
    pcol = color, pfcol = scales::alpha(color, 0.5), plwd = 2, plty = 1,
    # Customize the grid
    cglcol = "grey", cglty = 1, cglwd = 0.8,
    # Customize the axis
    axislabcol = "grey", 
    # Variable labels
    vlcex = vlcex, vlabels = vlabels,
    caxislabels = caxislabels, title = title, ...
  )
}
