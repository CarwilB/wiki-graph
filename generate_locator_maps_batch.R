# Bolivia Municipal Locator Maps — Batch Generation Script
# Wikipedia 2012 locator map colour scheme
# Validated against: samples_v5 (March 9 2026)
#
# KEY DESIGN NOTES:
# 1. ne_neighbors is drawn DIRECTLY (no union, no buffer).
#    Buffering a complex union polygon with dist=0.02 triggers GEOS snap
#    rounding that collapses ~50k coast coords to ~500, creating a triangle.
# 2. bolivia_cream = st_buffer(bolivia_outline, 0.02) closes the NE/GADM
#    sliver gap without touching coast geometry (simpler polygon survives).
# 3. Municipalities simplified with ms_simplify(keep=0.05): 11 MB → 0.6 MB.
#    Coast layers (ne_neighbors, titicaca_full) kept at full NE resolution.
# 4. Bolivia's international border drawn from GADM outline (high resolution).
#    Neighbor borders drawn from NE with Bolivia-facing segments removed.

library(sf)
library(dplyr)
library(ggplot2)
library(rmapshaper)

# ==============================================================================
# SETUP: load data
# ==============================================================================

gadm <- st_read("data/gadm41_BOL_3.gpkg", layer = "ADM_ADM_3", quiet = TRUE)

# Natural Earth 10m countries
ne_countries_path <- file.path(tempdir(), "ne_10m_admin_0_countries.shp")
if (!file.exists(ne_countries_path)) {
  tmp <- tempfile(fileext = ".zip")
  download.file("https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip",
                tmp, quiet = TRUE, mode = "wb")
  unzip(tmp, exdir = tempdir())
}
ne_countries_10m <- st_read(ne_countries_path, quiet = TRUE)

# Natural Earth 10m lakes (for full Lake Titicaca incl. Peruvian waters)
ne_lakes_path <- file.path(tempdir(), "ne_10m_lakes.shp")
if (!file.exists(ne_lakes_path)) {
  tmp <- tempfile(fileext = ".zip")
  download.file("https://naciscdn.org/naturalearth/10m/physical/ne_10m_lakes.zip",
                tmp, quiet = TRUE, mode = "wb")
  unzip(tmp, exdir = tempdir())
}
ne_lakes_10m <- st_read(ne_lakes_path, quiet = TRUE)

# ==============================================================================
# SHARED LAYERS
# ==============================================================================

# Neighbouring countries — used DIRECTLY, no union, no buffer
# (buffering a complex union triggers GEOS snap rounding that destroys the coast)
ne_neighbors <- ne_countries_10m |>
  filter(ADMIN %in% c("Peru", "Brazil", "Argentina", "Paraguay", "Chile")) |>
  select(ADMIN, geometry) |>
  st_make_valid()

# Full Lake Titicaca from Natural Earth (includes Peruvian waters)
titicaca_full <- ne_lakes_10m |>
  filter(grepl("Titicaca", name, ignore.case = TRUE)) |>
  st_make_valid()

# Bolivia outline from GADM (high-resolution) — used for cream fill and border
bolivia_outline <- gadm |>
  st_union() |>
  st_as_sf() |>
  st_set_crs(st_crs(gadm))

# Simplify municipality and Bolivia outline layers only
# (coast layers already ≤ 1 MB; municipalities were 11 MB → 0.6 MB)
mun_titicaca    <- ms_simplify(gadm |> filter(NAME_3 == "Lago Titicaca"),
                                keep = 0.05, keep_shapes = TRUE)
mun_regular     <- ms_simplify(gadm |> filter(NAME_3 != "Lago Titicaca"),
                                keep = 0.05, keep_shapes = TRUE)
bolivia_outline <- ms_simplify(bolivia_outline, keep = 0.05, keep_shapes = TRUE)

# Bolivia cream fill: buffered 0.02° to close micro-gap between NE and GADM
# at Bolivia's international border. Simpler polygon (~1600 coords) survives
# the buffer without destructive snap rounding.
bolivia_cream <- st_buffer(bolivia_outline, dist = 0.02)

# Neighbor border lines with Bolivia-facing segments removed.
# e.g. Peru/Chile border is drawn; Peru/Bolivia border is not.
# Bolivia's side is drawn from the GADM outline (step 8).
bolivia_buf      <- st_buffer(bolivia_outline, dist = 0.04)
neighbor_borders <- ne_neighbors |>
  st_boundary() |>
  st_difference(bolivia_buf)

# ==============================================================================
# COLOUR SCHEME — Wikipedia 2012 Convention for locator maps
# ==============================================================================
colors_2012 <- list(
  territory_of_interest = "#C12838",   # Target municipality (dark red)
  surrounding_internal  = "#FDFBEA",   # Other Bolivian municipalities (pale cream)
  surrounding_external  = "#DFDFDF",   # Neighbouring countries (light grey)
  borders               = "#656565",   # Political boundaries (dark grey)
  water_bodies          = "#C7E7FB"    # Water bodies (light blue)
)

# ==============================================================================
# MAP EXTENT AND ASPECT RATIO
# ==============================================================================
map_xmin <- -71.0; map_xmax <- -56.8
map_ymin <- -24.0; map_ymax <-  -9.0
map_h    <- 10
map_w    <- (map_xmax - map_xmin) *
            cos(((map_ymin + map_ymax) / 2) * pi / 180) /
            (map_ymax - map_ymin) * map_h

# ==============================================================================
# FUNCTION: generate one locator map
# ==============================================================================
generate_locator_map <- function(gadm_name_3,
                                 output_dir = "output/locator_maps") {
  target <- mun_regular |> filter(NAME_3 == gadm_name_3)
  if (nrow(target) == 0) {
    warning("Municipality not found in GADM: ", gadm_name_3)
    return(invisible(NULL))
  }

  p <- ggplot() +
    # 1. Neighbour countries — direct NE data, no union/buffer → coast intact
    geom_sf(data = ne_neighbors,
            fill  = colors_2012$surrounding_external, color = NA) +
    # 2. Full Lake Titicaca (NE) — over Peru so Peruvian waters read as lake
    geom_sf(data = titicaca_full,
            fill  = colors_2012$water_bodies, color = NA) +
    # 3. Bolivia cream fill (buffered 0.02° to close NE/GADM gap)
    geom_sf(data = bolivia_cream,
            fill  = colors_2012$surrounding_internal, color = NA) +
    # 4. All other municipalities — cream + thin grey border
    geom_sf(data = mun_regular |> filter(NAME_3 != gadm_name_3),
            fill      = colors_2012$surrounding_internal,
            color     = colors_2012$borders, linewidth = 0.15) +
    # 5. Lake Titicaca GADM municipalities — water blue, no border
    geom_sf(data = mun_titicaca,
            fill  = colors_2012$water_bodies, color = NA) +
    # 6. Target municipality — dark red
    geom_sf(data = target,
            fill      = colors_2012$territory_of_interest,
            color     = colors_2012$borders, linewidth = 0.4) +
    # 7. Neighbour borders (Bolivia-facing segments removed)
    geom_sf(data = neighbor_borders,
            fill  = NA, color = colors_2012$borders, linewidth = 0.45) +
    # 8. Bolivia border at GADM resolution (overwrites any NE line on this side)
    geom_sf(data = bolivia_outline,
            fill  = NA, color = colors_2012$borders, linewidth = 0.55) +
    coord_sf(xlim   = c(map_xmin, map_xmax),
             ylim   = c(map_ymin, map_ymax),
             expand = FALSE, datum = NA) +
    theme_void() +
    theme(
      plot.background  = element_rect(fill = colors_2012$water_bodies, color = NA),
      panel.background = element_rect(fill = colors_2012$water_bodies, color = NA),
      plot.margin      = unit(c(0, 0, 0, 0), "mm")
    )

  safe_name <- gsub("[^a-zA-Z0-9_-]", "_", gadm_name_3)
  out_path  <- file.path(output_dir, paste0(safe_name, "_locator_map.svg"))
  ggsave(out_path, p, device = "svg", width = map_w, height = map_h, units = "in")

  invisible(list(gadm_name = gadm_name_3, file = out_path,
                 size_kb = round(file.size(out_path) / 1024, 1)))
}

# ==============================================================================
# BATCH RUN
# ==============================================================================
output_dir <- "output/locator_maps"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

unique_munis <- mun_regular |>
  st_drop_geometry() |>
  distinct(NAME_3) |>
  arrange(NAME_3) |>
  pull(NAME_3)

cat("Generating", length(unique_munis), "locator maps...\n")
log <- vector("list", length(unique_munis))
for (i in seq_along(unique_munis)) {
  log[[i]] <- generate_locator_map(unique_munis[i], output_dir)
  if (i %% 20 == 0)
    cat(sprintf("[%3d/%d] %s\n", i, length(unique_munis), unique_munis[i]))
}

results <- do.call(rbind, lapply(log, as.data.frame))
cat("\nDone.", nrow(results), "maps | avg", round(mean(results$size_kb), 0),
    "KB | total", round(sum(results$size_kb) / 1024, 0), "MB\n")
write.csv(results, file.path(output_dir, "batch_log.csv"), row.names = FALSE)
