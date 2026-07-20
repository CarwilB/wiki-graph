# generate_locator_maps_workbench_hd.R
# Bolivia Municipal Locator Maps — Experimentation & Batch Script
#
# This script consolidates all map generation into one place with tuneable
# parameters. Use it to iterate on a handful of test municipalities, then
# flip to batch mode when satisfied.
#
# Wikipedia 2012 locator map colour scheme.

library(sf)
library(dplyr)
library(tibble)
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
  lw_prov_borders      = 0.25,   # provincial boundaries
  lw_dept_borders      = 0.38,   # departmental boundaries
  lw_target_border     = 0.40,   # highlighted municipality border
  lw_neighbor_borders  = 0.45,   # international borders (non-Bolivia side)
  lw_bolivia_outline   = 0.55,   # Bolivia's own international border

  # --- Bolivia cream buffer ---
  # Buffering the Bolivia outline by this many degrees closes the micro-gap

  # between NE country boundaries and GADM. Increase if you see slivers of
  # blue ocean between Bolivia and neighbours; decrease if it bleeds over.
  bolivia_cream_buffer = 0,
  bolivia_grey_buffer = 0.55,

  # --- Tripoint gap fixes ---
  # The Bolivia-buffer clips a small tail off Chile-Peru and Peru-Brazil borders
  # near their tripoints with Bolivia. These buffers recover those tails by
  # widening the intersection search around each neighbour's boundary.
  # Tune independently: Peru-Brazil resolved at 0.20; Chile-Peru may need more.
  tripoint_buf_chile_peru  = 0.40,  # degrees; increase if gap persists
  tripoint_buf_peru_brazil = 0.20,  # degrees

  # --- Output ---
  output_dir = "output/locator_maps/workbench_hd_3",
  map_height = 10   # inches; width auto-calculated from aspect ratio
)


# ==============================================================================
# §2 — MUNICIPALITY SELECTION
# ==============================================================================
# Option A: Test a handful of municipalities.
#           These are intentionally diverse: big city, small highland,
#           lowland, border, lake-adjacent.
# Option B: Set run_all = TRUE to generate all ~339 maps.

run_all <- TRUE

test_municipalities_tbl <- tribble(
  ~municipality,                     ~department,
  "Trinidad",                  "Beni",
  "Sucre",                     "Chuquisaca",
  "Cochabamba",                "Cochabamba",
  "Nuestra Señora de La Paz",  "La Paz",
  "Oruro",                     "Oruro",
  "Cobija",                    "Pando",
  "Potosí",                    "Potosí",
  "Llica",                     "Potosí",
  "Tahua",                     "Potosí",
  "Santa Cruz de la Sierra",   "Santa Cruz",
  "Tarija",                    "Tarija",
  # Salar de Coipasa municipalities
  "Esmeralda",                 "Oruro",
  "Salinas de Garcí Mendoza",  "Oruro",
  "Sabaya",                    "Oruro",
  "Coipasa",                   "Oruro",
  "Chipaya",                   "Oruro",
  "Belén de Andamarca",        "Oruro"
)

# Per-municipality parameter overrides. Use this to experiment with different
# simplification levels or line widths for specific municipalities.
# Keys are "municipality|department" (e.g. "Cobija|Pando"); values are named
# lists that override `params`.
# Example:
#   per_muni_overrides <- list(
#     "Cobija|Pando"                = list(simp_municipalities = 0.10, lw_target_border = 0.6),
#     "Nuestra Señora de La Paz|La Paz" = list(simp_municipalities = 0.02)
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
  water_bodies          = "#C7E7FB",
  salars                = "#F0E6C0"   # slightly darker beige for salt flats / dry lakes
)


# ==============================================================================
# §4 — LOAD SOURCE DATA  (OCHA COD-AB-BOL)
# ==============================================================================
# Source: OCHA Common Operational Datasets – Bolivia Administrative Boundaries
# Downloaded from: humdata.org  (bol_admin_boundaries.shp/)
#
# Layers used:
#   bol_admin3  — 339 municipalities (ADM3); no Lago Titicaca row
#   bol_admin2  — 112 provinces (ADM2)
#   bol_admin1  —   9 departments (ADM1)
#
# OCHA uses adm3_name / adm2_name / adm1_name.  They are renamed at load
# time to NAME_3 / NAME_2 / NAME_1 so that all downstream code (§5–§7) is
# unchanged.  Because OCHA carries no "Lago Titicaca" municipality polygon,
# mun_lake in §5 will be an empty sf object; Lake Titicaca is rendered
# instead via the Natural Earth lakes layer (titicaca_full).

ocha_dir <- "../ultimate-consequences/maps/humdata.org_cod-ab-bol/bol_admin_boundaries.shp"

cat("Loading OCHA admin3 (municipalities)...\n")
gadm <- st_read(file.path(ocha_dir, "bol_admin3.shp"), quiet = TRUE) |>
  rename(NAME_3 = adm3_name, NAME_2 = adm2_name, NAME_1 = adm1_name)

cat("Loading OCHA admin2 (provinces)...\n")
gadm_adm2 <- st_read(file.path(ocha_dir, "bol_admin2.shp"), quiet = TRUE) |>
  rename(NAME_2 = adm2_name, NAME_1 = adm1_name)

cat("Loading OCHA admin1 (departments)...\n")
gadm_adm1 <- st_read(file.path(ocha_dir, "bol_admin1.shp"), quiet = TRUE) |>
  rename(NAME_1 = adm1_name)

cat("Loading OCHA admin0 (country outline)...\n")
gadm_adm0 <- st_read(file.path(ocha_dir, "bol_admin0.shp"), quiet = TRUE) |>
  st_make_valid()

dupe_muni_names <- gadm |>
  st_drop_geometry() |>
  count(NAME_3) |>
  filter(n > 1) |>
  pull(NAME_3)

cat("Loading municipality ID lookup table...\n")
muni_id_lookup_table <- readRDS("data/muni_id_lookup_table.rds")

cat("Loading fondos municipales (current boundaries)...\n")
fondos_cur <- st_read(
  "../bolivia-data/fondos/fondos_municipio_geo/fondos:municipio_geo.geojson",
  quiet = TRUE
) |> st_make_valid()

# Duplicate muni_anexo names — used for disambiguation in file naming.
dupe_anexo_names <- muni_id_lookup_table |>
  count(muni_anexo) |>
  filter(n > 1) |>
  pull(muni_anexo)

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

# Extract the interior hole (ring) closest to a target lon/lat from a polygon.
# Returns an sf polygon, or an empty sf if no holes exist.
extract_hole_near <- function(x, target_lon, target_lat) {
  geom <- st_geometry(x)[[1]]
  rings <- if (inherits(geom, "MULTIPOLYGON")) {
    unlist(lapply(geom, function(poly) {
      if (length(poly) > 1) poly[2:length(poly)] else list()
    }), recursive = FALSE)
  } else if (inherits(geom, "POLYGON") && length(geom) > 1) {
    geom[2:length(geom)]
  } else {
    list()
  }
  if (length(rings) == 0) return(st_sf(geometry = st_sfc(crs = st_crs(x))))

  # Find the ring whose centroid is closest to the target
  dists <- sapply(rings, function(r) {
    cx <- mean(r[, 1]); cy <- mean(r[, 2])
    sqrt((cx - target_lon)^2 + (cy - target_lat)^2)
  })
  best <- rings[[which.min(dists)]]
  st_sfc(st_polygon(list(best)), crs = st_crs(x)) |> st_as_sf()
}

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
  # OCHA has no "Lago Titicaca" municipality; guard against empty input
  mun_lake_s <- if (nrow(mun_lake) > 0) {
    ms_simplify(mun_lake, keep = p$simp_municipalities, keep_shapes = TRUE)
  } else {
    mun_lake
  }
  prov_s        <- ms_simplify(gadm_adm2 |> st_make_valid(),
                                keep = p$simp_bolivia_outline, keep_shapes = TRUE)
  dept_s        <- ms_simplify(gadm_adm1 |> st_make_valid(),
                                keep = p$simp_bolivia_outline, keep_shapes = TRUE)

  # Fondos municipales: GeoBolivia boundaries include salar/lake territory
  # that OCHA admin3 excludes.  Used to fill the target municipality's salar
  # portions red.  Keyed by c_ut (= INE id_muni).
  fondos_s <- ms_simplify(fondos_cur |> select(c_ut, geometry),
                           keep = p$simp_municipalities, keep_shapes = TRUE)

  # Bolivia cream fill and international border outline.
  # OCHA admin3 (municipalities) excludes salt flats and lakes, leaving a
  # 94-part multipolygon with gaps. OCHA admin0 (country outline) has no such
  # cutouts — it's a solid polygon covering all of Bolivia, and since it comes
  # from the same dataset the international border aligns with admin3.
  bol_cream     <- gadm_adm0 |> select(geometry)
  bol_outline_s <- ms_simplify(gadm_adm0 |> select(geometry),
                                keep = p$simp_bolivia_outline, keep_shapes = TRUE)

  # Lake Poopó and Lake Uru Uru: extract from OCHA holes so they align with
  # muni boundaries. Identified by centroid proximity.
  poopo   <- extract_hole_near(bol_outline_raw, target_lon = -67.0, target_lat = -18.9)
  uru_uru <- extract_hole_near(bol_outline_raw, target_lon = -67.1, target_lat = -18.1)

  # Salar areas: admin0 minus the municipality union — the gaps (salt flats,
  # dry lakes) that OCHA admin3 excludes.  Drawn as a slightly darker beige
  # with no borders.  Fondos red and the lake layers paint over them later.
  sf_use_s2(FALSE)
  salar_areas <- st_difference(
    gadm_adm0 |> select(geometry),
    bol_outline_raw
  ) |> st_make_valid() |> st_as_sf()
  sf_use_s2(TRUE)

  # Neighbour borders with Bolivia-facing segments removed.
  # Uses NE's own Bolivia polygon (not GADM) for coordinate consistency.
  # A small buffer removes Bolivia-facing segments cleanly, but clips a tiny
  # tail off Chile-Peru and Peru-Brazil borders near their Bolivia tripoints.
  # Those two borders are added back via direct polygon intersection, which
  # gives the exact shared edge with no Bolivia influence.
  ne_bolivia_buf <- ne_countries_10m |>
    filter(ADMIN == "Bolivia") |>
    st_make_valid() |>
    st_buffer(dist = 0.001)

  nb_borders <- ne_neighbors |>
    st_boundary() |>
    st_difference(ne_bolivia_buf)

  # Tripoint fix: the Bolivia buffer clips a small tail off the Chile-Peru and
  # Peru-Brazil borders near their tripoints with Bolivia. Recover those tails
  # by intersecting Peru's boundary with a wide buffer around each neighbour's
  # boundary. 0.20° is large enough to bridge the ~0.12° gap at both tripoints;
  # any tiny extra segment of Peru's Bolivia-facing border captured by the wide
  # buffer will be hidden under Bolivia's cream fill.
  shared_border <- function(anchor_country, buffer_country, buf = 0.20) {
    a <- ne_countries_10m |> filter(ADMIN == anchor_country) |> st_make_valid()
    b <- ne_countries_10m |> filter(ADMIN == buffer_country) |> st_make_valid()
    st_intersection(st_boundary(a), st_buffer(st_boundary(b), buf)) |>
      select(geometry)
  }

  nb_borders <- bind_rows(
    nb_borders |> select(geometry),
    shared_border("Peru", "Chile",  p$tripoint_buf_chile_peru),
    shared_border("Peru", "Brazil", p$tripoint_buf_peru_brazil)
  )

  # Gap fill: NE neighbour polygons don't perfectly reach GADM Bolivia's border,
  # leaving thin blue-background strips. Fix: buffer GADM Bolivia outward, then
  # subtract all NE polygons. Whatever remains is the uncovered gap — draw gray.
  # Use GEOS (planar) mode; s2 rejects the degenerate vertices that arise when
  # unioning polygons that share near-identical border segments.
  ne_bolivia_NE <- ne_countries_10m |> filter(ADMIN == "Bolivia") |> st_make_valid()
  sf_use_s2(FALSE)
  ne_all_union  <- st_union(st_union(ne_neighbors), ne_bolivia_NE)
  gap_fill <- st_difference(
    st_buffer(bol_outline_raw, p$bolivia_grey_buffer),
    ne_all_union
  ) |> st_make_valid() |> st_as_sf()
  sf_use_s2(TRUE)

  # Background rectangle covering the full bbox; drawn first so any gaps between
  # NE polygons fall back to the neighbor color rather than the blue background.
  bbox_bg <- st_as_sfc(st_bbox(c(
    xmin = p$bbox_xmin, xmax = p$bbox_xmax,
    ymin = p$bbox_ymin, ymax = p$bbox_ymax
  ), crs = 4326)) |> st_as_sf()

  # Ocean: bbox minus all land polygons. Captures the Pacific in the SW corner
  # (and any other non-land area within the bbox) to be drawn blue.
  sf_use_s2(FALSE)
  pacific <- st_difference(bbox_bg, ne_all_union) |> st_make_valid() |> st_as_sf()
  sf_use_s2(TRUE)

  list(
    bbox_bg          = bbox_bg,
    pacific          = pacific,
    ne_neighbors     = ne_neighbors,
    titicaca_full    = titicaca_full,
    mun_regular      = mun_regular_s,
    mun_lake         = mun_lake_s,
    fondos           = fondos_s,
    salar_areas      = salar_areas,
    poopo            = poopo,
    uru_uru          = uru_uru,
    prov_outline     = prov_s,
    dept_outline     = dept_s,
    bol_outline      = bol_outline_s,
    bol_cream        = bol_cream,
    neighbor_borders = nb_borders,
    gap_fill         = gap_fill
  )
}


# ==============================================================================
# §6 — MAP GENERATION FUNCTION
# ==============================================================================

generate_locator_map <- function(municipality, department, layers, p = params) {

  target <- layers$mun_regular |> filter(NAME_3 == municipality, NAME_1 == department)
  if (nrow(target) == 0) {
    warning("Municipality not found in GADM: ", municipality, " (", department, ")")
    return(invisible(NULL))
  }

  others <- layers$mun_regular |> filter(!(NAME_3 == municipality & NAME_1 == department))

  # Fondos polygon for the target municipality (includes salar territory).
  # Drawn before OCHA municipalities so cream covers any overflow in
  # non-salar areas; salar gaps in the OCHA layer let the fondos red show.
  target_id <- muni_id_lookup_table |>
    filter(muni_gadm == municipality, department == !!department) |>
    pull(id_muni)
  target_fondos <- layers$fondos |> filter(c_ut %in% target_id)

  # Map dimensions
  map_w <- (p$bbox_xmax - p$bbox_xmin) *
    cos(((p$bbox_ymin + p$bbox_ymax) / 2) * pi / 180) /
    (p$bbox_ymax - p$bbox_ymin) * p$map_height

  plot <- ggplot() +
    # 0. Full-bbox gray background — ensures any gap between NE polygons is gray
    geom_sf(data = layers$bbox_bg,
            fill = colors_2012$surrounding_external, color = NA) +
    # 1. Ocean (bbox minus all land) — Pacific in the SW corner
    geom_sf(data = layers$pacific,
            fill = colors_2012$water_bodies, color = NA) +
    # 2. Neighbouring countries (full NE resolution — no simplification on coasts)
    geom_sf(data = layers$ne_neighbors,
            fill = colors_2012$surrounding_external, color = NA) +
    # 3. Lake Titicaca incl. Peruvian waters (NE)
    geom_sf(data = layers$titicaca_full,
            fill = colors_2012$water_bodies, color = NA) +
    # 4. Gap fill: gray strips where NE neighbour polygons fall short of GADM Bolivia
    geom_sf(data = layers$gap_fill,
            fill = colors_2012$surrounding_external, color = NA) +
    # 4. Bolivia cream fill
    geom_sf(data = layers$bol_cream,
            fill = colors_2012$surrounding_internal, color = NA) +
    # 4b. Salar areas (darker beige, no border)
    geom_sf(data = layers$salar_areas,
            fill = colors_2012$salars, color = NA) +
    # 4c. Target fondos polygon (fills salar territory red)
    geom_sf(data = target_fondos,
            fill = colors_2012$territory_of_interest, color = NA) +
    # 5. Other municipalities (cream covers fondos red outside salar gaps)
    geom_sf(data = others,
            fill = colors_2012$surrounding_internal,
            color = colors_2012$borders, linewidth = p$lw_mun_borders) +
    # 5a. Lake Titicaca GADM polygons (water blue)
    geom_sf(data = layers$mun_lake,
            fill = colors_2012$water_bodies, color = NA) +
    # 5b. Lake Poopó and Lake Uru Uru (OCHA holes, water blue, no border)
    geom_sf(data = layers$poopo,
            fill = colors_2012$water_bodies, color = NA) +
    geom_sf(data = layers$uru_uru,
            fill = colors_2012$water_bodies, color = NA) +
    # 6. Target municipality
    geom_sf(data = target,
            fill = colors_2012$territory_of_interest,
            color = colors_2012$borders, linewidth = p$lw_target_border) +
    # 7. Provincial boundaries
    geom_sf(data = layers$prov_outline,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_prov_borders) +
    # 8. Departmental boundaries
    geom_sf(data = layers$dept_outline,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_dept_borders) +
    # 9. Neighbour borders (Bolivia side removed)
    geom_sf(data = layers$neighbor_borders,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_neighbor_borders) +
    # 10. Bolivia international border (GADM)
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

  # Resolve official INE name (muni_anexo); fall back to GADM name if no match.
  muni_anexo <- muni_id_lookup_table |>
    filter(muni_gadm == municipality, department == !!department) |>
    pull(muni_anexo)
  display_name <- if (length(muni_anexo) == 1L) muni_anexo else municipality

  clean_name <- stringi::stri_trans_general(display_name, "Latin-ASCII")
  clean_dept <- stringi::stri_trans_general(department,   "Latin-ASCII")
  if (display_name %in% dupe_anexo_names) {
    safe_name <- gsub("[^a-zA-Z0-9_()-]", "_",
                      paste0(clean_name, "_(", clean_dept, ")"))
  } else {
    safe_name <- gsub("[^a-zA-Z0-9_-]", "_", clean_name)
  }

  out_path <- file.path(p$output_dir, paste0(safe_name, "_muni_locator_map.svg"))
  ggsave(out_path, plot, device = "svg",
         width = map_w, height = p$map_height, units = "in")

  list(municipality = municipality, department = department,
       muni_anexo = display_name,
       file = out_path, size_kb = round(file.size(out_path) / 1024, 1))
}


# ==============================================================================
# §6b — EXTERNAL-ONLY DIAGNOSTIC MAP
# Renders just the neighboring countries and Titicaca — no Bolivia components.
# Useful for inspecting neighbor geometry, border trimming, and alignment
# against Bolivia's outline before layering in the full map.
# ==============================================================================

generate_locator_map_external <- function(layers, p = params) {

  map_w <- (p$bbox_xmax - p$bbox_xmin) *
    cos(((p$bbox_ymin + p$bbox_ymax) / 2) * pi / 180) /
    (p$bbox_ymax - p$bbox_ymin) * p$map_height

  plot <- ggplot() +
    # 0. Full-bbox gray background — ensures any gap between NE polygons is gray
    geom_sf(data = layers$bbox_bg,
            fill = colors_2012$surrounding_external, color = NA) +
    # 1. Ocean (bbox minus all land) — Pacific in the SW corner
    geom_sf(data = layers$pacific,
            fill = colors_2012$water_bodies, color = NA) +
    # 2. Neighbouring countries
    geom_sf(data = layers$ne_neighbors,
            fill = colors_2012$surrounding_external, color = NA) +
    # 3. Lake Titicaca (NE)
    geom_sf(data = layers$titicaca_full,
            fill = colors_2012$water_bodies, color = NA) +
    # 4. Gap fill: gray strips where NE polygons fall short of GADM Bolivia
    geom_sf(data = layers$gap_fill,
            fill = colors_2012$surrounding_external, color = NA) +
    # 4. Neighbour borders (Bolivia-facing segments removed per current params)
    geom_sf(data = layers$neighbor_borders,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_neighbor_borders) +
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
  out_path <- file.path(p$output_dir, "external_only_diagnostic.svg")
  ggsave(out_path, plot, device = "svg",
         width = map_w, height = p$map_height, units = "in")

  cat("External diagnostic map written to", out_path, "\n")
  invisible(out_path)
}


# ==============================================================================
# §7 — RUN
# ==============================================================================

# Build the municipality tibble
if (run_all) {
  muni_tbl <- gadm |>
    st_drop_geometry() |>
    filter(NAME_3 != "Lago Titicaca") |>
    distinct(municipality = NAME_3, department = NAME_1) |>
    arrange(department, municipality)
  cat("BATCH MODE:", nrow(muni_tbl), "municipalities\n")
} else {
  muni_tbl <- test_municipalities_tbl
  cat("TEST MODE:", nrow(muni_tbl), "municipalities\n")
}

# Prepare shared layers with default params
shared_layers <- prepare_shared_layers(params)

# Generate maps
results <- vector("list", nrow(muni_tbl))
t0 <- Sys.time()

for (i in seq_len(nrow(muni_tbl))) {
  mun_name  <- muni_tbl$municipality[i]
  dept_name <- muni_tbl$department[i]
  muni_key  <- paste0(mun_name, "|", dept_name)

  # Merge per-municipality overrides into params
  p_this <- params
  if (muni_key %in% names(per_muni_overrides)) {
    overrides <- per_muni_overrides[[muni_key]]
    for (nm in names(overrides)) p_this[[nm]] <- overrides[[nm]]

    # If simplification changed, re-prepare layers for this municipality
    simp_changed <- any(c("simp_municipalities", "simp_bolivia_outline") %in%
                          names(overrides))
    if (simp_changed) {
      cat("  [override] Re-simplifying layers for", mun_name, "(", dept_name, ")\n")
      layers_this <- prepare_shared_layers(p_this)
    } else {
      layers_this <- shared_layers
    }
  } else {
    layers_this <- shared_layers
  }

  results[[i]] <- generate_locator_map(mun_name, dept_name, layers_this, p_this)

  # Progress
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  rate    <- elapsed / i
  eta     <- rate * (nrow(muni_tbl) - i)
  cat(sprintf("[%3d/%d] %-40s %-15s  %5.1f KB  (ETA %s)\n",
              i, nrow(muni_tbl), mun_name, dept_name,
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


# ==============================================================================
# §8 — PROVINCIAL LOCATOR MAPS
# ==============================================================================
# Generates one locator map per province (112 total), highlighting all
# municipalities in the target province in red.  Municipality borders are shown
# within non-target areas; the target province boundary is redrawn boldly on
# top for clarity.  Reuses shared_layers from §7 (same bbox and simplification).
#
# Layer order (matches municipality maps):
#   0  gray bbox background
#   1  blue ocean (Pacific)
#   2  gray neighbouring countries
#   3  blue Lake Titicaca (NE)
#   4  gray gap fill
#   5  cream Bolivia fill
#   6  cream other municipalities  (with faint muni borders)
#   7  blue Lake Titicaca GADM polygons + Lake Poopó
#   8  red target-province municipalities  (no internal borders → clean fill)
#   9  all province outlines  (lw_prov_borders)
#  10  target province outline redrawn  (lw_target_border — makes it stand out)
#  11  departmental outlines  (lw_dept_borders)
#  12  neighbour borders
#  13  Bolivia international border


# ==============================================================================
# §8a — PARAMETERS & PROVINCE SELECTION
# ==============================================================================

params_prov <- modifyList(params, list(
  output_dir = "output/locator_maps/prov-maps-hd-3",
  lw_mun_borders       = 0.10,   # internal municipality boundaries
  lw_prov_borders      = 0.30,  # provincial boundaries
  lw_dept_borders      = 0.50   # departmental boundaries
  ))

# Province names that appear in more than one department — need dept disambiguator.
dupe_prov_names <- gadm_adm2 |>
  st_drop_geometry() |>
  count(NAME_2) |>
  filter(n > 1) |>
  pull(NAME_2)

prov_run_all <- TRUE

# Intentionally diverse test set: capital provinces, Cercado duplicate, large/small.
test_provinces_tbl <- tribble(
  ~province,                    ~department,
  "Cercado",                    "Cochabamba",   # duplicate name — triggers disambiguator
  "Cercado",                    "Oruro",
  "Oropeza",                    "Chuquisaca",   # includes Sucre
  "Murillo",                    "La Paz",       # includes La Paz city (OCHA name; full name: Pedro Domingo Murillo)
  "Andrés Ibáñez",              "Santa Cruz",   # includes Santa Cruz city
  "Tomás Frías",                "Potosí",       # includes Potosí city
  "Iténez",                     "Beni",         # lowland, large
  "Méndez",                     "Tarija"
)

# Per-province parameter overrides (same structure as per_muni_overrides).
# Keys are "province|department".
per_prov_overrides <- list()


# ==============================================================================
# §8b — PROVINCE MAP GENERATION FUNCTION
# ==============================================================================

generate_prov_locator_map <- function(province, department, layers, p = params_prov) {

  # All municipalities in the target province
  target <- layers$mun_regular |>
    filter(NAME_2 == province, NAME_1 == department)
  if (nrow(target) == 0) {
    warning("Province not found in layer data: ", province, " (", department, ")")
    return(invisible(NULL))
  }

  others <- layers$mun_regular |>
    filter(!(NAME_2 == province & NAME_1 == department))

  # Target province outline (for bold redraw on top of red fill)
  target_prov <- layers$prov_outline |>
    filter(NAME_2 == province, NAME_1 == department)

  # Fondos polygons for all municipalities in the target province
  target_ids <- muni_id_lookup_table |>
    filter(muni_gadm %in% target$NAME_3, department == !!department) |>
    pull(id_muni)
  target_fondos <- layers$fondos |> filter(c_ut %in% target_ids)

  map_w <- (p$bbox_xmax - p$bbox_xmin) *
    cos(((p$bbox_ymin + p$bbox_ymax) / 2) * pi / 180) /
    (p$bbox_ymax - p$bbox_ymin) * p$map_height

  plot <- ggplot() +
    # 0. Full-bbox gray background
    geom_sf(data = layers$bbox_bg,
            fill = colors_2012$surrounding_external, color = NA) +
    # 1. Ocean (Pacific)
    geom_sf(data = layers$pacific,
            fill = colors_2012$water_bodies, color = NA) +
    # 2. Neighbouring countries
    geom_sf(data = layers$ne_neighbors,
            fill = colors_2012$surrounding_external, color = NA) +
    # 3. Lake Titicaca (NE, incl. Peruvian waters)
    geom_sf(data = layers$titicaca_full,
            fill = colors_2012$water_bodies, color = NA) +
    # 4. Gap fill
    geom_sf(data = layers$gap_fill,
            fill = colors_2012$surrounding_external, color = NA) +
    # 5. Bolivia cream fill
    geom_sf(data = layers$bol_cream,
            fill = colors_2012$surrounding_internal, color = NA) +
    # 5b. Salar areas (darker beige, no border)
    geom_sf(data = layers$salar_areas,
            fill = colors_2012$salars, color = NA) +
    # 5c. Target province fondos polygons (fill salar territory red)
    geom_sf(data = target_fondos,
            fill = colors_2012$territory_of_interest, color = NA) +
    # 6. Other municipalities (cream covers fondos red outside salar gaps)
    geom_sf(data = others,
            fill = colors_2012$surrounding_internal,
            color = colors_2012$borders, linewidth = p$lw_mun_borders) +
    # 7a. Lake Titicaca GADM polygons
    geom_sf(data = layers$mun_lake,
            fill = colors_2012$water_bodies, color = NA) +
    # 7b. Lake Poopó and Lake Uru Uru (OCHA holes, water blue, no border)
    geom_sf(data = layers$poopo,
            fill = colors_2012$water_bodies, color = NA) +
    geom_sf(data = layers$uru_uru,
            fill = colors_2012$water_bodies, color = NA) +
    # 8. Target province municipalities (red, no internal borders)
    geom_sf(data = target,
            fill = colors_2012$territory_of_interest, color = NA) +
    # 9. All province outlines
    geom_sf(data = layers$prov_outline,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_prov_borders) +
    # 10. Target province outline redrawn boldly
    geom_sf(data = target_prov,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_target_border) +
    # 11. Departmental boundaries
    geom_sf(data = layers$dept_outline,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_dept_borders) +
    # 12. Neighbour borders (Bolivia side removed)
    geom_sf(data = layers$neighbor_borders,
            fill = NA, color = colors_2012$borders,
            linewidth = p$lw_neighbor_borders) +
    # 13. Bolivia international border
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

  clean_name <- stringi::stri_trans_general(province,   "Latin-ASCII")
  clean_dept <- stringi::stri_trans_general(department, "Latin-ASCII")
  if (province %in% dupe_prov_names) {
    safe_name <- gsub("[^a-zA-Z0-9_()-]", "_",
                      paste0(clean_name, "_(", clean_dept, ")"))
  } else {
    safe_name <- gsub("[^a-zA-Z0-9_-]", "_", clean_name)
  }

  out_path <- file.path(p$output_dir, paste0(safe_name, "_prov_locator_map.svg"))
  ggsave(out_path, plot, device = "svg",
         width = map_w, height = p$map_height, units = "in")

  list(province = province, department = department,
       file = out_path, size_kb = round(file.size(out_path) / 1024, 1))
}


# ==============================================================================
# §8c — RUN PROVINCIAL MAPS
# ==============================================================================

if (prov_run_all) {
  prov_tbl <- gadm_adm2 |>
    st_drop_geometry() |>
    distinct(province = NAME_2, department = NAME_1) |>
    arrange(department, province)
  cat("BATCH MODE:", nrow(prov_tbl), "provinces\n")
} else {
  prov_tbl <- test_provinces_tbl
  cat("TEST MODE:", nrow(prov_tbl), "provinces\n")
}

# Reuse shared_layers prepared in §7 (same bbox and simplification settings).
# If §7 has not been run yet, uncomment the next line:
# shared_layers <- prepare_shared_layers(params)

prov_results <- vector("list", nrow(prov_tbl))
t0_prov <- Sys.time()

for (i in seq_len(nrow(prov_tbl))) {
  prov_name <- prov_tbl$province[i]
  dept_name <- prov_tbl$department[i]
  prov_key  <- paste0(prov_name, "|", dept_name)

  p_this <- params_prov
  if (prov_key %in% names(per_prov_overrides)) {
    overrides <- per_prov_overrides[[prov_key]]
    for (nm in names(overrides)) p_this[[nm]] <- overrides[[nm]]

    simp_changed <- any(c("simp_municipalities", "simp_bolivia_outline") %in%
                          names(overrides))
    if (simp_changed) {
      cat("  [override] Re-simplifying layers for", prov_name, "(", dept_name, ")\n")
      layers_this <- prepare_shared_layers(p_this)
    } else {
      layers_this <- shared_layers
    }
  } else {
    layers_this <- shared_layers
  }

  prov_results[[i]] <- generate_prov_locator_map(prov_name, dept_name, layers_this, p_this)

  elapsed <- as.numeric(difftime(Sys.time(), t0_prov, units = "secs"))
  rate    <- elapsed / i
  eta     <- rate * (nrow(prov_tbl) - i)
  cat(sprintf("[%3d/%d] %-40s %-15s  %5.1f KB  (ETA %s)\n",
              i, nrow(prov_tbl), prov_name, dept_name,
              prov_results[[i]]$size_kb %||% NA,
              if (eta > 60) sprintf("%.0f min", eta / 60) else sprintf("%.0f s", eta)))
}

prov_results_df <- do.call(rbind, lapply(Filter(Negate(is.null), prov_results), as.data.frame))
cat("\n",
    nrow(prov_results_df), "maps generated |",
    "avg", round(mean(prov_results_df$size_kb), 0), "KB |",
    "total", round(sum(prov_results_df$size_kb) / 1024, 1), "MB |",
    round(as.numeric(difftime(Sys.time(), t0_prov, units = "secs")), 0), "sec\n")

prov_log_path <- file.path(params_prov$output_dir, "batch_log.csv")
write.csv(prov_results_df, prov_log_path, row.names = FALSE)
cat("Log written to", prov_log_path, "\n")
