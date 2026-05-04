# Point to Municipality Lookup Functions
# ═══════════════════════════════════════
# 
# Uses GADM municipality boundaries to determine which municipality
# a geographic point falls within.
#
# Source this file after loading mun_sf:
#   source("src/point_municipality_lookup.R")
#
# Functions:
#   - point_to_municipality()      — Single point lookup
#   - point_to_municipalities()    — Vectorized on data frame

library(sf)
library(dplyr)
library(ggplot2)

#' Find municipality containing a single point
#'
#' @param lon Longitude (numeric)
#' @param lat Latitude (numeric)
#' @param mun_sf_obj sf object with municipality boundaries (default: mun_sf from calling env)
#'
#' @return List with cod.mun, department, municipality; returns NAs if point is outside all polygons
#'
#' @examples
#' point_to_municipality(-66.15, -17.39)  # Cochabamba
#'
point_to_municipality <- function(lon, lat, mun_sf_obj = mun_sf) {
  
  pt_sf <- st_sf(
    geometry = st_sfc(st_point(c(lon, lat)), crs = st_crs(mun_sf_obj))
  )
  
  result <- st_join(
    pt_sf,
    mun_sf_obj |> select(cod.mun, department, municipality),
    join = st_within
  )
  
  if (nrow(result) == 0 || is.na(result$municipality[1])) {
    return(list(cod.mun = NA, department = NA, municipality = NA))
  }
  
  list(
    cod.mun = result$cod.mun[1],
    department = result$department[1],
    municipality = result$municipality[1]
  )
}


#' Find municipality for multiple points
#'
#' Adds municipality information to a data frame with lon/lat columns.
#' Points outside all municipality boundaries will have NA municipality values.
#'
#' @param df Data frame with coordinate columns
#' @param lon_col Name of longitude column (default: "lon")
#' @param lat_col Name of latitude column (default: "lat")
#' @param mun_sf_obj sf object with municipality boundaries (default: mun_sf from calling env)
#'
#' @return Original data frame with cod.mun, department, municipality columns added
#'
#' @examples
#' test_points <- tibble(
#'   id = c("pt1", "pt2"),
#'   lon = c(-66.15, -68.15),
#'   lat = c(-17.39, -16.50)
#' )
#' point_to_municipalities(test_points)
#'
point_to_municipalities <- function(df, lon_col = "lon", lat_col = "lat",
                                     mun_sf_obj = mun_sf) {
  
  # Create sf object from coordinates
  pts_sf <- st_as_sf(
    df |> select(all_of(c(lon_col, lat_col))),
    coords = c(lon_col, lat_col),
    crs = st_crs(mun_sf_obj)
  )
  
  # Spatial join (st_within finds points inside polygons)
  result <- st_join(
    pts_sf,
    mun_sf_obj |> select(cod.mun, department, municipality),
    join = st_within
  )
  
  # Return original data with municipality info added
  st_drop_geometry(result) |>
    bind_cols(df)
}


#' Inspect a shared IGM point: map + table of all INE codes that resolve to it
#'
#' For a given id_unico, shows which INE codes map to it, uses point_to_municipality()
#' to find the current GADM municipality, and builds a mapview map showing:
#'   - The IGM point (red dot)
#'   - Polygon outlines for each INE municipality referencing this point
#'   - The current GADM municipality (thick border), which may differ from the
#'     INE municipalities due to boundary shifts
#'
#' Note: Bolivia expanded from ~100 to ~340 municipalities; municipality names in the
#' crosswalk may reflect historical boundaries. No single answer is assumed correct.
#'
#' @param id_unico_val   Character. A single id_unico from the IGM dataset.
#' @param crosswalk      Data frame. Defaults to crosswalk_geo_ine.
#' @param geo_sf         sf object. IGM point dataset. Defaults to geo.
#' @param mun_sf_obj     sf object. GADM municipality polygons. Defaults to mun_sf.
#'
#' @return A named list with: id_unico, com_name, heading, current_municipality,
#'   current_department, unmatched_muns (historical names not in GADM), table, map.
#'
#' @examples
#' r <- inspect_shared_point("3548609828-D")  # VILUYO
#' r$table
#' r$map
#'
inspect_shared_point <- function(id_unico_val,
                                  crosswalk  = crosswalk_geo_ine,
                                  geo_sf     = geo,
                                  mun_sf_obj = mun_sf) {
  
  # All crosswalk rows for this IGM point
  codes <- crosswalk |>
    filter(id_unico == id_unico_val) |>
    select(Codigo, com_name, municipality, department, match_status) |>
    distinct() |>
    arrange(municipality, Codigo)
  
  # The IGM point
  point_sf <- geo_sf |> filter(id_unico == id_unico_val)
  coords   <- st_coordinates(point_sf)
  
  # Current GADM municipality for the point
  current <- point_to_municipality(coords[1, "X"], coords[1, "Y"], mun_sf_obj)
  
  current_mun_label <- if (!is.na(current$municipality))
    paste0(current$municipality, " (", current$department, ")")
  else
    "Outside GADM boundaries"
  
  # Municipality polygons for all INE municipalities referencing this point
  ine_muns       <- unique(codes$municipality)
  matched_polys  <- mun_sf_obj |> filter(municipality %in% ine_muns)
  unmatched_muns <- setdiff(ine_muns, mun_sf_obj$municipality)
  
  # Current municipality polygon (for highlighting)
  current_poly <- mun_sf_obj |>
    filter(!is.na(cod.mun), cod.mun == current$cod.mun)
  
  # Build table: one row per unique Codigo + municipality combo
  tbl <- codes |>
    mutate(
      `= Current GADM` = if_else(municipality == current$municipality, "\u2713", "")
    ) |>
    rename(
      `INE Code`        = Codigo,
      Name              = com_name,
      `INE Municipality` = municipality,
      Department        = department,
      `Match Status`    = match_status
    )
  
  # --- Static ggplot2 map ---
  
  # Bounding box from INE municipality polygons; fall back to current poly or point
  if (nrow(matched_polys) > 0) {
    bbox <- st_bbox(matched_polys)
  } else if (!is.na(current$municipality) && nrow(current_poly) > 0) {
    bbox <- st_bbox(current_poly)
  } else {
    bbox <- st_bbox(point_sf)
  }
  # Buffer: 10% of the wider extent, minimum 0.05 degrees
  buf <- max((bbox["xmax"] - bbox["xmin"]) * 0.1, 0.05)
  
  map_plot <- ggplot()
  
  # INE municipality polygons — filled and labeled
  if (nrow(matched_polys) > 0) {
    map_plot <- map_plot +
      geom_sf(data = matched_polys, aes(fill = municipality),
              alpha = 0.25, linewidth = 0.8, show.legend = FALSE) +
      geom_sf_label(data = matched_polys, aes(label = municipality),
                    size = 2.5, label.padding = unit(0.15, "lines"))
  }
  
  # Current GADM municipality — thick border, no fill
  if (!is.na(current$municipality) && nrow(current_poly) > 0) {
    map_plot <- map_plot +
      geom_sf(data = current_poly, fill = NA, color = "gray30", linewidth = 1.8)
  }
  
  # IGM point — red dot
  map_plot <- map_plot +
    geom_sf(data = point_sf, color = "red", size = 3, shape = 19) +
    coord_sf(
      xlim = c(bbox["xmin"] - buf, bbox["xmax"] + buf),
      ylim = c(bbox["ymin"] - buf, bbox["ymax"] + buf)
    ) +
    theme_void()
  
  list(
    id_unico             = id_unico_val,
    com_name             = codes$com_name[1],
    heading              = paste0(codes$com_name[1], " \u2014 ", id_unico_val),
    current_municipality = current$municipality,
    current_department   = current$department,
    current_mun_label    = current_mun_label,
    unmatched_muns       = unmatched_muns,
    table                = tbl,
    map                  = map_plot
  )
}
