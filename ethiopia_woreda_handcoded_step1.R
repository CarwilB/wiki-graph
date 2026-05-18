library(ggplot2)
library(sf)
library(here)

colors_2012 <- list(
  territory_of_interest = "#C12838",
  surrounding_internal  = "#FDFBEA",
  surrounding_external  = "#DFDFDF",
  borders               = "#656565",
  water_bodies          = "#C7E7FB"
)

ethiopia_layers <- here::here("maps", "eth_admin_boundaries.shp") |>
  st_layers()
ethiopia_borders <- here::here("maps", "eth_admin_boundaries.shp") |>
  st_read(layer="eth_admin0")
ethiopia_regions <- here::here("maps", "eth_admin_boundaries.shp") |>
  st_read(layer="eth_admin1")
ethiopia_zones <- here::here("maps", "eth_admin_boundaries.shp") |>
  st_read(layer="eth_admin2")
ethiopia_woredas <- here::here("maps", "eth_admin_boundaries.shp") |>
  st_read(layer="eth_admin3")
chosen_woreda <- ethiopia_woredas |> filter(adm3_name == "Quara")

natural_earth_countries <-  here::here("maps", "ne_10m_admin_0_countries") |>
  st_read()
ne_neighboring <- natural_earth_countries |>
  filter(NAME_EN %in% c("Eritrea", "Djibouti", "Sudan", "Somalia", "Kenya",
                        "Uganda", "South Sudan", "Somaliland", "Yemen", "Saudi Arabia"))

# Initial iteration of the map (just internal)
map <- ggplot() +
  geom_sf(data = ethiopia_borders, linewidth=1) +
  geom_sf(data = ethiopia_woredas, linewidth=0.1, fill = colors_2012$surrounding_internal) +
  geom_sf(data = chosen_woreda, fill=colors_2012$territory_of_interest)

map
# Before adding neighboring countries, I want to constrain the map to this
# bounding box, so I extract its coordinates:
country_bbox <- st_bbox(ethiopia_borders)
x_exp <- 0.5
y_exp <- 0.25

# Future iterations will use saved_bbox as outline
map2 <- ggplot() +
  geom_sf(data = ne_neighboring, linewidth=0.75, fill = colors_2012$surrounding_external ) +
  geom_sf(data = ethiopia_borders, linewidth=1) +
  geom_sf(data = ethiopia_woredas, linewidth=0.1, fill = colors_2012$surrounding_internal) +
  geom_sf(data = chosen_woreda, fill=colors_2012$territory_of_interest) +
  coord_sf(xlim = c(country_bbox$xmin - x_exp, country_bbox$xmax + x_exp),
           ylim = c(country_bbox$ymin - y_exp, country_bbox$ymax + y_exp),
           expand = FALSE)
map2

# Elements are now there. Fine-tuning design…
map3 <- ggplot() +
  geom_sf(data = ne_neighboring, linewidth=0.6,
          color = colors_2012$borders,
          fill = colors_2012$surrounding_external ) +
  geom_sf(data = ethiopia_borders, linewidth=1) +
  geom_sf(data = ethiopia_woredas, linewidth=0.15,
          color = colors_2012$borders,
          fill = colors_2012$surrounding_internal) +
  geom_sf(data = ethiopia_regions, linewidth=0.5,
          color = colors_2012$borders,
          fill = "transparent") +
  geom_sf(data = ethiopia_zones, linewidth=0.3,
          color = colors_2012$borders,
          fill = "transparent") +
  geom_sf(data = chosen_woreda,
          color = "#000000", # black border for the chosen territory
          fill=colors_2012$territory_of_interest) +
  coord_sf(xlim = c(country_bbox$xmin - x_exp, country_bbox$xmax + x_exp/10),
           ylim = c(country_bbox$ymin - y_exp, country_bbox$ymax + y_exp),
           expand = FALSE) +
  theme(
    panel.background = element_rect(fill = colors_2012$water_bodies, color = NA), # Water
    panel.grid = element_blank() # Removes grid lines
    )
map3

ggsave("quara_woreda_locator_map.svg", plot = map3, height = 10, units ="in")

# This file is enormous (18.5MB) because of unsimplified map details.

# (This code sequencing is sloppy, but I want to illustrate the changing way of
# doing it, so i'm just gonna reload and simplify using the same variable names)

library(rmapshaper)

simpler <- function(map_object){
  ms_simplify(map_object,keep = 0.05, keep_shapes = TRUE)
}

# --- I've run this once; commenting it out so I don't run it again this session
# ne_neighboring <- simpler(ne_neighboring)
# ethiopia_borders <- simpler(ethiopia_borders)
# ethiopia_regions <- simpler(ethiopia_regions)
# ethiopia_zones <- simpler(ethiopia_zones)
# ethiopia_woredas <- simpler(ethiopia_woredas)
# chosen_woreda <- ethiopia_woredas |> filter(adm3_name == "Quara")

# Elements are now there. Fine-tuning design…
map4 <- ggplot() +
  geom_sf(data = ne_neighboring, linewidth=0.6,
          color = colors_2012$borders,
          fill = colors_2012$surrounding_external ) +
  geom_sf(data = ethiopia_borders, linewidth=1) +
  geom_sf(data = ethiopia_woredas, linewidth=0.15,
          color = colors_2012$borders,
          fill = colors_2012$surrounding_internal) +
  geom_sf(data = ethiopia_regions, linewidth=0.5,
          color = colors_2012$borders,
          fill = "transparent") +
  geom_sf(data = ethiopia_zones, linewidth=0.3,
          color = colors_2012$borders,
          fill = "transparent") +
  geom_sf(data = chosen_woreda,
          color = "#000000", # black border for the chosen territory
          fill=colors_2012$territory_of_interest) +
  coord_sf(xlim = c(country_bbox$xmin - x_exp, country_bbox$xmax + x_exp/10),
           ylim = c(country_bbox$ymin - y_exp, country_bbox$ymax + y_exp),
           expand = FALSE) +
  theme(
    panel.background = element_rect(fill = colors_2012$water_bodies, color = NA), # Water
    panel.grid = element_blank() # Removes grid lines
  )
map4

ggsave("quara_woreda_locator_map_4.svg", plot = map4)
