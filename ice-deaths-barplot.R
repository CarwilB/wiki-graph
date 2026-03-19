library(tibble)

annual_deaths <- tribble(
  ~year, ~number_of_deaths,
  2017,  10,
  2018,  9,
  2019,  9,
  2020,  18,
  2021,  5,
  2022,  3,
  2023,  7,
  2024,  11,
  2025,  31,
  2026,  10
)

library(ggplot2)
library(dplyr)
library(tidyr)

# Expand the data for the waffle effect
plot_deaths <- annual_deaths |>
  uncount(number_of_deaths) |>
  group_by(year) |>
  mutate(unit_index = row_number()) |>
  ungroup()


ggplot(plot_deaths, aes(x = factor(year), y = unit_index)) +
  geom_tile(
    fill = "#8B0000",
    color = "white",
    size = 0.9,
    width = 0.9,
    height = 0.9
  ) +
  coord_fixed(ratio = 1) +
  theme_minimal() +
  labs(
    title = "Deaths in ICE Custody",
    subtitle = "2017 through early March 2026",
    x = NULL,
    y = NULL
  ) +
  annotate("segment", x = 0.5, xend = 10.5, y =(5 * 1:6)+0.5, linewidth = 0.3, color = "grey50") +
  annotate("segment", x = 0.5, xend = 10.5, y = .3, yend = 0.3, linewidth = 0.75) +
  scale_x_discrete(expand = expansion(add = c(0, 8))) +
  scale_y_continuous(breaks = c(10, 20, 30), expand = c(0, 0.1), limits = c(0, 32)) +
  annotate("text", x = 11, y = 10, label = "10 deaths in\nfirst 70 days\n(20%) of 2026",
           size = 3, hjust = 0) +
  theme(
    text = element_text(family = "ITC Franklin Gothic Std"),  # font preference
    panel.grid = element_blank(),
    plot.title = element_text(family = "ITC Franklin Gothic Std Demi"),
    axis.text.x = element_text(angle = 90, size = 9, vjust = 0.5, family = "ITC Franklin Gothic Std Demi"),
    axis.line.x = element_blank()
  )
