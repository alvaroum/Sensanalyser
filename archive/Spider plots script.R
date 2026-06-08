library(tidyverse)
library(rstatix)
library(emmeans)
library(agricolae)
library(factoextra)
library(FactoMineR)
library(fmsb)

min <- 0 # Lowest value on intensity scale to be plotted
max <- 100 # Highest value on intensity scale to be plotted
noaxis <- 6 # Number of sections in the spider splot
scale <- c(0, 20, 40, 60, 80, 100) # Labels for each section of the spiderplot
                                   # These labels must correspond with the number
                                   # of axis/sections from the value above




allied.bread <- read.table(file = "spider plot allied bakery.csv", header=TRUE, 
                        sep = ",", dec = ".")


newrow <- data.frame(matrix(rep(min, (ncol(allied.bread) - 1)), nrow = 1))
newrow <- add_column(newrow, "Min", .before = 1)
colnames(newrow) <- colnames(allied.bread)
allied.bread <- rbind(newrow, allied.bread)

newrow <- data.frame(matrix(rep(max, (ncol(allied.bread) - 1)), nrow = 1))
newrow <- add_column(newrow, "Max", .before = 1)
colnames(newrow) <- colnames(allied.bread)
allied.bread <- rbind(newrow, allied.bread)

allied.bread <- column_to_rownames(allied.bread, "product")

# Reduce plot margin using par()
op <- par(mar = c(1, 2, 2, 2))

# Select the products you want to include, you need to add the rows
# of the products you want to graph from the data.
# Rows 1 and 2 are "min" and "max"
products <- c(3)

# to create the radar charts
create_beautiful_radarchart(
  data = allied.bread[c(1,2, products),], caxislabels = scale,
  color = c("#00B1FF","#E7B800","#FC4E07", "#D706FF","#00F0A1"),
  noaxis = noaxis
)
# Add an horizontal legend
legend(
  x = "bottom", legend = rownames(allied.bread[products,]), horiz = TRUE,
  bty = "n", pch = 20 , 
  col = c( "#00B1FF","#E7B800","#FC4E07", "#D706FF","#00F0A1"),
  text.col = "black", cex = 0.5, pt.cex = 1.5
)
par(op)

#function to be loaded only once

create_beautiful_radarchart <- function(data, color = "#00AFBB", 
                                        vlabels = colnames(data), vlcex = 0.7,
                                        noaxis = 5,
                                        caxislabels = NULL, title = NULL, ...){
  radarchart(
    data, axistype = 1, seg = noaxis - 1,
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
