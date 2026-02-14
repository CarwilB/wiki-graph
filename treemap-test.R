library(ggplot2)
library(treemapify)
library(dplyr)

# 1. Prepare Data
data <- data.frame(
  parent = c(rep("Cluster", 4), rep("Graph", 3), rep("Util", 3)),
  child = c("Agglomerative", "Community", "Hierarchical", "Merge",
            "Betweenness", "Link", "ShortestPath",
            "Color", "Math", "Stats"),
  value = c(12, 15, 7, 8, 20, 10, 14, 5, 18, 9)
) %>%
  # Create a combined label: "Name\nValue"
  mutate(display_label = paste0(child, "\n", value))

# 2. Create the Plot
p <- ggplot(data, aes(area = value, fill = parent, label = display_label, subgroup = parent)) +
  geom_treemap(color = "white", size = 2) +
  geom_treemap_subgroup_border(color = "white", size = 4) +

  # Adjusted Text Settings
  geom_treemap_text(
    colour = "white",
    place = "topleft",    # Moves text to upper-left
    size = 10,            # Sets a smaller, fixed font size
    grow = FALSE,         # Prevents text from expanding to fill the box
    reflow = TRUE,        # Wraps text if the box is too narrow
    padding.x = unit(2, "mm"),
    padding.y = unit(2, "mm")
  ) +

  scale_fill_brewer(palette = "Set2") +
  theme_minimal() +
  theme(legend.position = "none") + # Cleaning up for a more "Bostock" feel
  labs(title = "Refined Treemap Layout")

# Display plot
print(p)
