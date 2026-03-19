# generate_locator_maps.R
# Produce Wikipedia-style locator maps for all Bolivia municipalities
# Output: SVG files named "{Municipality} Municipality ({Department}) locator map.svg"
#
# Requires: sf, ggplot2, dplyr, rmapshaper, rnaturalearth, rnaturalearthdata

library(sf)
library(ggplot2)
library(dplyr)
library(rmapshaper)

# ---------------------------------------------------------------------------
# 1. Load and prepare geometry layers
# ---------------------------------------------------------------------------

mun_raw <- st_read("data/gadm41_BOL_3.gpkg", layer = "ADM_ADM_3", quiet = TRUE)
mun_raw <- mun_raw |> filter(NAME_3 != "Lago Titicaca")

bolivia_outline <- mun_raw |> st_union() |> st_sf()

dept_boundaries <- mun_raw |>
  group_by(NAME_1) |>
  summarise(geometry = st_union(geom), .groups = "drop")

# Neighboring countries (Natural Earth 1:10m)
ne_countries <- rnaturalearth::ne_countries(scale = 10, returnclass = "sf")
neighbors <- ne_countries |>
  filter(ADMIN %in% c("Argentina", "Brazil", "Chile", "Paraguay", "Peru")) |>
  select(ADMIN, geometry)

# Lake Titicaca
ne_lakes <- rnaturalearth::ne_download(
  scale = 10, type = "lakes", category = "physical", returnclass = "sf"
)
titicaca <- ne_lakes |> filter(name == "Lake Titicaca")

# Clip neighbors to padded Bolivia bounding box
bol_bbox <- st_bbox(bolivia_outline)
pad <- 4
clip_box <- st_bbox(c(
  xmin = unname(bol_bbox["xmin"]) - pad,
  ymin = unname(bol_bbox["ymin"]) - pad,
  xmax = unname(bol_bbox["xmax"]) + pad,
  ymax = unname(bol_bbox["ymax"]) - 1
), crs = st_crs(bolivia_outline))

neighbors_clipped <- st_intersection(neighbors, st_as_sfc(clip_box))

# ---------------------------------------------------------------------------
# 2. Simplify geometries (topology-preserving) for reasonable SVG sizes
# ---------------------------------------------------------------------------

mun_simp        <- ms_simplify(mun_raw,           keep = 0.05, keep_shapes = TRUE)
dept_simp       <- ms_simplify(dept_boundaries,    keep = 0.05, keep_shapes = TRUE)
bol_simp        <- ms_simplify(bolivia_outline,    keep = 0.05, keep_shapes = TRUE)
neighbors_simp  <- ms_simplify(neighbors_clipped,  keep = 0.03, keep_shapes = TRUE)
titicaca_simp   <- ms_simplify(titicaca,           keep = 0.10, keep_shapes = TRUE)

# ---------------------------------------------------------------------------
# 3. Color scheme (Wikipedia 2012 convention)
# ---------------------------------------------------------------------------

col_target     <- "#C12838"
col_internal   <- "#FDFBEA"
col_external   <- "#DFDFDF"
col_water      <- "#C7E7FB"
col_border_dep <- "#646464"
col_border_mun <- "#9E9E9E"
col_coastline  <- "#1278AB"

# ---------------------------------------------------------------------------
# 4. Map generation function
# ---------------------------------------------------------------------------

generate_locator_map <- function(target_name_3, target_name_1, output_dir) {

  target <- mun_simp |> filter(NAME_3 == target_name_3, NAME_1 == target_name_1)
  others <- mun_simp |> filter(!(NAME_3 == target_name_3 & NAME_1 == target_name_1))

  fname <- paste0(target_name_3, " Municipality (", target_name_1, ") locator map.svg")
  fpath <- file.path(output_dir, fname)

  p <- ggplot() +
    geom_sf(data = st_as_sfc(clip_box), fill = col_water, color = NA) +
    geom_sf(data = neighbors_simp, fill = col_external, color = col_border_dep, linewidth = 0.15) +
    geom_sf(data = others, fill = col_internal, color = col_border_mun, linewidth = 0.08) +
    geom_sf(data = target, fill = col_target, color = col_border_mun, linewidth = 0.08) +
    geom_sf(data = dept_simp, fill = NA, color = col_border_dep, linewidth = 0.25) +
    geom_sf(data = bol_simp, fill = NA, color = col_border_dep, linewidth = 0.4) +
    geom_sf(data = titicaca_simp, fill = col_water, color = col_coastline, linewidth = 0.2) +
    coord_sf(
      xlim = c(clip_box["xmin"], clip_box["xmax"]),
      ylim = c(clip_box["ymin"], clip_box["ymax"]),
      expand = FALSE
    ) +
    theme_void() +
    theme(
      plot.background = element_rect(fill = col_water, color = NA),
      panel.background = element_rect(fill = col_water, color = NA)
    )

  ggsave(fpath, plot = p, device = "svg", width = 5.5, height = 6, bg = col_water)
  invisible(fpath)
}

# ---------------------------------------------------------------------------
# 5. Generate all maps
# ---------------------------------------------------------------------------

output_dir <- "output/locator_maps"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

mun_list <- mun_simp |>
  st_drop_geometry() |>
  distinct(NAME_1, NAME_3) |>
  arrange(NAME_1, NAME_3)

cat("Generating", nrow(mun_list), "locator maps...\n")

for (i in seq_len(nrow(mun_list))) {
  row <- mun_list[i, ]
  if (i %% 25 == 0 || i == 1) {
    cat(sprintf("[%3d/%d] %s (%s)\n", i, nrow(mun_list), row$NAME_3, row$NAME_1))
  }
  generate_locator_map(row$NAME_3, row$NAME_1, output_dir)
}

cat("Done.", nrow(mun_list), "maps saved to:", output_dir, "\n")
