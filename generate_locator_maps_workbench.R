# generate_locator_maps_workbench.R
# Bolivia Municipal Locator Maps — Experimentation & Batch Script
#
# This script consolidates all map generation into one place with tuneable
# parameters. Use it to iterate on a handful of test municipalities, then
# flip to batch mode when satisfied.
#
# Wikipedia 2012 locator map colour scheme.

library(sf)
library(dplyr)
library(ggplot2)
library(rmapshaper)

# ==============================================================================
# §1 — PARAMETERS YOU WILL WANT TO TUNE
# ==============================================================================

params <- list(

  # --- Simplification ---
  # ms_simplify `keep` for each layer. Lower = simpler = smaller SVG.
  # Range roughly 0.01 (very coarse) to 1.0 (no simplification).
  # Different maps may need different values; override per-municipality below.
  simp_municipalities  = 0.05,
  simp_bolivia_outline = 0.05,
  simp_neighbors       = 0.03,
  simp_titicaca        = 0.10,


  # --- Bounding box (WGS84 degrees) ---
  # Controls the geographic extent of the rendered map.
  bbox_xmin = -71.0,
  bbox_xmax = -56.8,
  bbox_ymin = -24.0,
  bbox_ymax =  -9.0,

  # --- Line widths ---
  lw_mun_borders       = 0.15,   # internal municipality boundaries
  lw_target_border     = 0.40,   # highlighted municipality border
  lw_neighbor_borders  = 0.45,   # international borders (non-Bolivia side)
  lw_bolivia_outline   = 0.55,   # Bolivia's own international border

  # --- Bolivia cream buffer ---
  # Buffering the Bolivia outline by this many degrees closes the micro-gap

  # between NE country boundaries and GADM. Increase if you see slivers of
  # blue ocean between Bolivia and neighbours; decrease if it bleeds over.
  bolivia_cream_buffer = 0.02,

  # --- Output ---
  output_dir = "output/locator_maps/workbench",
  map_height = 10   # inches; width auto-calculated from aspect ratio
)


# ==============================================================================
# §2 — MUNICIPALITY SELECTION
# ==============================================================================
# Option A: Test a handful of municipalities (use GADM NAME_3 values).
#           These are intentionally diverse: big city, small highland,
#           lowland, border, lake-adjacent.
# Option B: Set run_all = TRUE to generate all ~339 maps.

run_all <- FALSE

test_municipalities <- c(
  "Nuestra Señora de La Paz",
  "Santa Cruz de la Sierra",
  "Sucre",
  "Cobija",
  "Oruro",
  "Cochabamba",
  "Trinidad",
  "Tarija",
  "Potosí"
)

# Per-municipality parameter overrides. Use this to experiment with different
# simplification levels or line widths for specific municipalities.
# Keys are GADM NAME_3 values; values are named lists that override `params`.
# Example:
#   per_muni_overrides <- list(
#     "Cobija" = list(simp_municipalities = 0.10, lw_target_border = 0.6),
#     "Nuestra Señora de La Paz" = list(simp_municipalities = 0.02)
#   )
per_muni_overrides <- list()


# ==============================================================================
# §3 — COLOUR SCHEME (Wikipedia 2012)
# ==============================================================================

colors_2012 <- list(
  territory_of_interest = "#C12838",
  surrounding_internal  = "#FDFBEA",
  surrounding_external  = "#DFDFDF",
  borders               = "#656565",
  water_bodies          = "#C7E7FB"
)


# ==============================================================================
# §4 — LOAD SOURCE DATA
# ==============================================================================

cat("Loading GADM...\n")
gadm <- st_read("data/gadm41_BOL_3.gpkg", layer = "ADM_ADM_3", quiet = TRUE)

cat("Loading Natural Earth countries (10m)...\n")
ne_countries_path <- file.path(tempdir(), "ne_10m_admin_0_countries.shp")
if (!file.exists(ne_countries_path)) {
  tmp <- tempfile(fileext = ".zip")
  download.file("https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip",
                tmp, quiet = TRUE, mode = "wb")
  unzip(tmp, exdir = tempdir())
}
ne_countries_10m <- st_read(ne_countries_path, quiet = TRUE)

cat("Loading Natural Earth lakes (10m)...\n")
ne_lakes_path <- file.path(tempdir(), "ne_10m_lakes.shp")
if (!file.exists(ne_lakes_path)) {
  tmp <- tempfile(fileext = ".zip")
  download.file("https://naciscdn.org/naturalearth/10m/physical/ne_10m_lakes.zip",
                tmp, quiet = TRUE, mode = "wb")
  unzip(tmp, exdir = tempdir())
}
ne_lakes_10m <- st_read(ne_lakes_path, quiet = TRUE)


# ==============================================================================
# §5 — PREPARE SHARED LAYERS (uses current `params`)
# ==============================================================================

prepare_shared_layers <- function(p = params) {
  cat("Preparing shared layers (simp_mun =", p$simp_municipalities,
      ", simp_bol =", p$simp_bolivia_outline, ")...\n")

  ne_neighbors <- ne_countries_10m |>
    filter(ADMIN %in% c("Peru", "Brazil", "Argentina", "Paraguay", "Chile")) |>
    select(ADMIN, geometry) |>
    st_make_valid()

  titicaca_full <- ne_lakes_10m |>
    filter(grepl("Titicaca", name, ignore.case = TRUE)) |>
    st_make_valid()

  bol_outline_raw <- gadm |> st_union() |> st_as_sf() |> st_set_crs(st_crs(gadm))

  mun_lake    <- gadm |> filter(NAME_3 == "Lago Titicaca")
  mun_regular <- gadm |> filter(NAME_3 != "Lago Titicaca")

  # Simplify
  mun_regular_s <- ms_simplify(mun_regular, keep = p$simp_municipalities,
                                keep_shapes = TRUE)
  mun_lake_s    <- ms_simplify(mun_lake, keep = p$simp_municipalities,
                                keep_shapes = TRUE)
  bol_outline_s <- ms_simplify(bol_outline_raw, keep = p$simp_bolivia_outline,
                                keep_shapes = TRUE)

  # Bolivia cream fill (buffered to close NE/GADM gap)
  bol_cream <- st_buffer(bol_outline_s, dist = p$bolivia_cream_buffer)

  # Neighbour borders with Bolivia-facing segments removed
  bol_buf <- st_buffer(bol_outline_s, dist = p$bolivia_cream_buffer * 2)
  nb_borders <- ne_neighbors |>
    st_boundary() |>
    st_difference(bol_buf)

  list(
    ne_neighbors    = ne_neighbors,
    titicaca_full   = titicaca_full,
    mun_regular     = mun_regular_s,
    mun_lake        = mun_lake_s,
    bol_outline     = bol_outline_s,
    bol_cream       = bol_cream,
    neighbor_borders = nb_borders
  )
}


# ==============================================================================
# §6 — MAP GENERATION FUNCTION
# ==============================================================================

generate_locator_map <- function(gadm_name_3, layers, p = params) {

  target <- layers$mun_regular |> filter(NAME_3 == gadm_name_3)
  if (nrow(target) == 0) {
    warning("Municipality not found in GADM: ", gadm_name_3)
    return(invisible(NULL))
  }

  others <- layers$mun_regular |> filter(NAME_3 != gadm_name_3)

  # Map dimensions
  map_w <- (p$bbox_xmax - p$bbox_xmin) *
    cos(((p$bbox_ymin + p$bbox_ymax) / 2) * pi / 180) /
    (p$bbox_ymax - p$bbox_ymin) * p$map_height

  plot <- ggplot() +
    # 1. Neighbouring countries (full NE resolution — no simplification on coasts)
    geom_sf(data = layers$ne_neighbors,
            fill = colors_2012$surrounding_external, color = NA) +
    # 2. Lake Titicaca incl. Peruvian waters (NE)
    geom_sf(data = layers$titicaca_full,
            fill = colors_2012$water_bodies, color = NA) +
    # 3. Bolivia cream fill (buffered to hide NE/GADM gap)
    geom_sf(data = layers$bol_cream,
            fill = colors_2012$surrounding_internal, color = NA) +
    # 4. Other municipalities
    geom_sf(data = others,
            fill = colors_2012$surrounding_internal,
            color = colors_2012$borders, linewidth = p$lw_mun_borders) +
    # 5. Lake Titicaca GADM polygons (water blue)
    geom_sf(data = layers$mun_lake,
            fill = colors_2012$water_bodies, color = NA) +
    # 6. Target municipality
    geom_sf(data = target,
            fill = colors_2012$territory_of_interest,
            color = colors_2012$borders, linewidth = p$lw_target_border) +
    # 7. Neighbour borders (Bolivia side removed)
    geom_sf(data = layers$neighbor_borders,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_neighbor_borders) +
    # 8. Bolivia international border (GADM)
    geom_sf(data = layers$bol_outline,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_bolivia_outline) +
    coord_sf(xlim   = c(p$bbox_xmin, p$bbox_xmax),
             ylim   = c(p$bbox_ymin, p$bbox_ymax),
             expand = FALSE, datum = NA) +
    theme_void() +
    theme(
      plot.background  = element_rect(fill = colors_2012$water_bodies, color = NA),
      panel.background = element_rect(fill = colors_2012$water_bodies, color = NA),
      plot.margin      = unit(c(0, 0, 0, 0), "mm")
    )

  dir.create(p$output_dir, recursive = TRUE, showWarnings = FALSE)
  safe_name <- gsub("[^a-zA-Z0-9_-]", "_", gadm_name_3)
  out_path  <- file.path(p$output_dir, paste0(safe_name, "_locator_map.svg"))
  ggsave(out_path, plot, device = "svg",
         width = map_w, height = p$map_height, units = "in")

  list(gadm_name = gadm_name_3, file = out_path,
       size_kb = round(file.size(out_path) / 1024, 1))
}


# ==============================================================================
# §7 — RUN
# ==============================================================================

# Build the municipality list
if (run_all) {
  muni_list <- gadm |>
    st_drop_geometry() |>
    filter(NAME_3 != "Lago Titicaca") |>
    distinct(NAME_3) |>
    arrange(NAME_3) |>
    pull(NAME_3)
  cat("BATCH MODE:", length(muni_list), "municipalities\n")
} else {
  muni_list <- test_municipalities
  cat("TEST MODE:", length(muni_list), "municipalities\n")
}

# Prepare shared layers with default params
shared_layers <- prepare_shared_layers(params)

# Generate maps
results <- vector("list", length(muni_list))
t0 <- Sys.time()

for (i in seq_along(muni_list)) {
  mun_name <- muni_list[i]

  # Merge per-municipality overrides into params
  p_this <- params
  if (mun_name %in% names(per_muni_overrides)) {
    overrides <- per_muni_overrides[[mun_name]]
    for (nm in names(overrides)) p_this[[nm]] <- overrides[[nm]]

    # If simplification changed, re-prepare layers for this municipality
    simp_changed <- any(c("simp_municipalities", "simp_bolivia_outline") %in%
                          names(overrides))
    if (simp_changed) {
      cat("  [override] Re-simplifying layers for", mun_name, "\n")
      layers_this <- prepare_shared_layers(p_this)
    } else {
      layers_this <- shared_layers
    }
  } else {
    layers_this <- shared_layers
  }

  results[[i]] <- generate_locator_map(mun_name, layers_this, p_this)

  # Progress
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  rate    <- elapsed / i
  eta     <- rate * (length(muni_list) - i)
  cat(sprintf("[%3d/%d] %-40s  %5.1f KB  (ETA %s)\n",
              i, length(muni_list), mun_name,
              results[[i]]$size_kb %||% NA,
              if (eta > 60) sprintf("%.0f min", eta / 60) else sprintf("%.0f s", eta)))
}

# Summary
results_df <- do.call(rbind, lapply(Filter(Negate(is.null), results), as.data.frame))
cat("\n",
    nrow(results_df), "maps generated |",
    "avg", round(mean(results_df$size_kb), 0), "KB |",
    "total", round(sum(results_df$size_kb) / 1024, 1), "MB |",
    round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 0), "sec\n")

log_path <- file.path(params$output_dir, "batch_log.csv")
write.csv(results_df, log_path, row.names = FALSE)
cat("Log written to", log_path, "\n")
