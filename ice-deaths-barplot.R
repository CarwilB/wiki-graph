library(tibble)

annual_deaths <- tribble(
  ~year, ~number_of_deaths,
  2004, 32,
  2005, 20,
  2006, 18,
  2007, 8,
  2008, 16,
  2009, 10,
  2010, 9,
  2011, 11,
  2012, 5,
  2013, 9,
  2014, 6,
  2015, 7,
  2016, 12,
  2017,  10,
  2018,  12,
  2019,  10,
  2020,  20,
  2021,  5,
  2022,  3,
  2023,  7,
  2024,  11,
  2025,  32,
  2026,  18
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
    subtitle = "2004 through April 2026",
    x = NULL,
    y = NULL
  ) +
  annotate("segment", x = 0.5, xend = 23.5, y =(5 * 1:6)+0.5, linewidth = 0.3, color = "grey50") +
  annotate("segment", x = 0.5, xend = 23.5, y = .3, yend = 0.3, linewidth = 0.75) +
  scale_x_discrete(expand = expansion(add = c(0, 8))) +
  scale_y_continuous(breaks = c(10, 20, 30), expand = c(0, 0.1), limits = c(0, 34)) +
  annotate("text", x = 23.7, y = 18, label = "18 deaths in\nfirst 4 months\n(33%) of 2026",
           size = 3, hjust = 0) +
  theme(
    text = element_text(family = "ITC Franklin Gothic Std"),  # font preference
    panel.grid = element_blank(),
    plot.title = element_text(family = "ITC Franklin Gothic Std Demi"),
    axis.text.x = element_text(angle = 90, size = 10, vjust = 0.5, family = "ITC Franklin Gothic Std Demi"),
    axis.line.x = element_blank()
  )

