# Load necessary libraries
library(tidyverse)
library(usmap)
library(colorspace) # For sophisticated color manipulation
library(ggplot2)

# Define Regional Base Colors
division_bases_bright <- c(
  "New England"        = "#191970", # Midnight Blue
  "Mid-Atlantic"       = "#4682B4", # Steel Blue
  "East North Central" = "#006400", # Dark Green
  "West North Central" = "#98FB98", # Sage/Mint
  "South Atlantic"     = "#800000", # Maroon
  "East South Central" = "#DC143C", # Crimson
  "West South Central" = "#CC5500", # Burnt Orange
  "Mountain"           = "#673147", # Deep Plum
  "Pacific"            = "#DA70D6"  # Vivid Orchid
)

division_bases <- c(
  "New England"        = "#3E5B94", # Muted Royal Blue
  "Mid-Atlantic"       = "#006B95", # Deep Teal/Blue
  "East North Central" = "#3C6E47", # Medium Forest Green
  "West North Central" = "#626B33", # Olive/Moss Green
  "South Atlantic"     = "#9C4A45", # Muted Terracotta
  "East South Central" = "#A83E5D", # Raspberry Red
  "West South Central" = "#9E561F", # Dark Ochre/Orange
  "Mountain"           = "#7D5283", # Muted Purple
  "Pacific"            = "#A2418B"  # Dark Orchid/Magenta
)

# Mapping states to divisions
census_divisions <- tibble(state = state.abb) %>%
  add_row(state = "DC") %>%
  mutate(division = case_when(
    state %in% c("CT", "ME", "MA", "NH", "RI", "VT") ~ "New England",
    state %in% c("NJ", "NY", "PA") ~ "Mid-Atlantic",
    state %in% c("IL", "IN", "MI", "OH", "WI") ~ "East North Central",
    state %in% c("IA", "KS", "MN", "MO", "NE", "ND", "SD") ~ "West North Central",
    state %in% c("DE", "FL", "GA", "MD", "NC", "SC", "VA", "WV", "DC") ~ "South Atlantic",
    state %in% c("AL", "KY", "MS", "TN") ~ "East South Central",
    state %in% c("AR", "LA", "OK", "TX") ~ "West South Central",
    state %in% c("AZ", "CO", "ID", "MT", "NV", "NM", "UT", "WY") ~ "Mountain",
    state %in% c("AK", "CA", "HI", "OR", "WA") ~ "Pacific"
  ))

census_divisions_names <- census_divisions %>%
  mutate(state_name = state.name[match(state, state.abb)]) %>%
  mutate(state_name = ifelse(state == "DC", "District of Columbia", state_name)) %>%
  arrange(state_name) %>%
  relocate(state_name)

# Corrected Shading Logic (Equal Total Variation)
# We calculate a 'shift' that spans from -0.6 to 0.6 regardless of N
state_colors <- census_divisions %>%
  group_by(division) %>%
  mutate(
    state_name = state.name[match(state, state.abb)],
    n = n(),
    rank = row_number(),
    # Normalized range: -0.6 (darker) to 0.6 (lighter)
    # The smallest group (Mid-Atlantic, N=3) will stretch just as far as the largest.
    shift_val = if_else(n > 1, -0.6 + (rank - 1)/(n - 1) * 1.2, 0),
    color_hex = map2_chr(division, shift_val, ~{
      base <- division_bases[.x]
      # lighten() uses a numeric scale where negative values darken.
      # This is robust and avoids HCL class coercion errors.
      as.character(lighten(base, amount = .y))
    })
  ) %>%
  ungroup()

# --- 3. CREATE THE MAP ---

plot_usmap(data = state_colors, values = "color_hex", color = "white") +
  scale_fill_identity() +
  labs(title = "U.S. Census Divisions: High-Contrast Regional Family Map",
       subtitle = "Shading spans full 30%-85% lightness range for every division.") +
  theme(legend.position = "none")

# Pivot and aggregate by division
us_census_by_state <- us_census_by_state %>%
  mutate(division = census_divisions_names$division[match(state, census_divisions_names$state_name)])
  

plot_data_div <- us_census_by_state %>%
  pivot_longer(cols = starts_with("1"), names_to = "year", values_to = "pop") %>%
  mutate(year = as.numeric(year)) %>%
  group_by(division, year) %>%
  summarize(total_pop = sum(pop, na.rm = TRUE), .groups = "drop")

# Define division order from East to West
division_order <- c(
  "New England", "Mid-Atlantic", "South Atlantic", 
  "East North Central", "East South Central", 
  "West North Central", "West South Central", 
  "Mountain", "Pacific"
)

# Apply to plot_data_div
plot_data_div <- plot_data_div %>%
  mutate(division = factor(division, levels = division_order))

# Plot using division colors
ggplot(plot_data_div, aes(x = year, y = total_pop, fill = division)) +
  geom_area(color = "white", linewidth = 0.1) +
  scale_fill_manual(values = division_bases_bright) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "U.S. Population Growth by Census Division (1790-1990)",
       x = "Year", y = "Total Population", fill = "Division") +
  theme_minimal()

# Easternmost (first factor levels) at the bottom
div_label_pos <- plot_data_div %>%
  filter(year == 1990) %>%
  arrange(division) %>% 
  mutate(
    cp_top = cumsum(total_pop),
    cp_base = lag(cp_top, default = 0),
    label_y = (cp_top + cp_base) / 2
  )

# Add to your ggplot code
ggplot(plot_data_div, aes(x = year, y = total_pop, fill = division)) +
  geom_area(color = "white", linewidth = 0.1) +
  # geom_text(data = div_label_pos, 
  #           aes(x = 1990, y = label_y, label = division), 
  #           hjust = -0.1, size = 3.5) + # Places labels just outside the plot boundary
  scale_fill_manual(values = division_bases_bright) +
  scale_y_continuous(labels = scales::comma) +
  coord_cartesian(clip = 'off') + # Prevents labels from being cut off
  theme_minimal() +
  theme(plot.margin = margin(r = 50)) # Extra space for labels on the right


# Pivot for individual states
plot_data_state <- us_census_by_state %>%
  pivot_longer(cols = starts_with("1"), names_to = "year", values_to = "pop") %>%
  mutate(pop = replace_na(pop, 0)) %>%
  mutate(year = as.numeric(year))

# Define the state order
# This assumes state names are full names (e.g., "New York") as per the CSV
state_order <- us_census_by_state %>%
  mutate(division = factor(division, levels = division_order)) %>%
  # Arrange by the division order first, then by the state's internal order (shading rank)
  arrange(division, state) %>% 
  pull(state)

# Apply to plot_data_state
plot_data_state <- plot_data_state %>%
  mutate(state = factor(state, levels = state_order)) %>%
  mutate(division = factor(division, levels = division_order))

state_colors_2 <- state_colors$color_hex
names(state_colors_2) <- state_colors$state_name
  

# Plot using individual state shades
ggplot(plot_data_state, aes(x = year, y = pop, fill = state)) +
  geom_area(color = "white", linewidth = 0.05) +
  scale_fill_manual(values = state_colors_2) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "U.S. Population Growth by State (1790-1990)",
       x = "Year", y = "Total Population") +
  theme_minimal() +
  theme(legend.position = "none") # Legend hidden due to number of states

# Calculate label positions for states at 1990
state_label_pos <- plot_data_state %>%
  filter(year == 1990) %>%
  # Reverse the order so cumsum matches the bottom-to-top factor stack
  arrange(desc(state)) %>% 
  mutate(
    cp_top = cumsum(pop),
    cp_base = lag(cp_top, default = 0),
    label_y = (cp_top + cp_base) / 2
  )

# Add to your ggplot code
ggplot(plot_data_state, aes(x = year, y = pop, fill = state)) +
  geom_area(color = "white", linewidth = 0.05) +
  geom_text(data = state_label_pos, 
            aes(x = 1990, y = label_y, label = state), 
            hjust = -0.2, size = 2) + # Very small text for 51 items
  scale_fill_manual(values = state_colors_2) +
  scale_y_continuous(labels = scales::comma) +
  coord_cartesian(clip = 'off') +
  theme_minimal() +
  theme(legend.position = "none",
        plot.margin = margin(r = 60))
