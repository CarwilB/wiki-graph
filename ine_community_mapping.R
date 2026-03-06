# INE excel sheet with list of communities, matched to larger administrative entities
ine_geog_2013 <- readxl::read_excel("data/CLASIF_UB_GEOG_COMUNIDAD.xlsx")
ine_geog_2013 <- ine_geog_2013 %>%
  rename(
    department = DEPARTAMENTO,
    province = PROVINCIA,
    municipality = MUNICIPIO) %>%
  mutate(cod.prov = paste0(DEP, PRO),
         cod.mun = paste0(DEP, PRO, MUN),
         cod.com = Codigo) %>%
  rename(cod.dep = DEP)
# saveRDS(ine_geog_2013, "data/ine_geog_2013.rds")
# ine_geog_2013 <- readRDS("data/ine_geog_2013.rds")

# ---------------------------------------------------------------------------
# GeoJSON point dataset: localizacion_poblaciones_2016
# Contains department-level names (nombre_dep) and community names (nombre_c_1),
# plus a unique identifier (id_unico) and point coordinates.
# ---------------------------------------------------------------------------
library(sf)
library(stringdist)

geo <- st_read("data/geocode/localizacion_poblaciones_2016.json", quiet = TRUE)

# Verify that both id fields are truly unique identifiers
stopifnot(n_distinct(geo$id_unico)         == nrow(geo))
stopifnot(n_distinct(ine_geog_2013$Codigo) == nrow(ine_geog_2013))

# ---------------------------------------------------------------------------
# Normalization helpers
# ---------------------------------------------------------------------------

# normalize_match_key: strips non-ASCII chars, collapses punctuation to spaces,
# uppercases — used as the join key to handle encoding artifacts.
normalize_match_key <- function(x) {
  x |>
    str_trim() |>
    str_squish() |>
    str_to_upper() |>
    str_replace_all("[^\x20-\x7E]", "") |>   # remove non-ASCII (encoding artifacts)
    str_replace_all("[^A-Z0-9 ]", " ") |>    # collapse punctuation/symbols to space
    str_squish()
}

# ---------------------------------------------------------------------------
# Prepare geo lookup table
# ---------------------------------------------------------------------------
geo_norm <- geo |>
  st_drop_geometry() |>
  mutate(
    nombre_c_1 = str_trim(nombre_c_1),
    match_key  = normalize_match_key(nombre_c_1)
  )

# ---------------------------------------------------------------------------
# Prepare INE names with match keys, applying known spelling corrections
# ---------------------------------------------------------------------------
# These are cases where the INE name differs from the geo name for the same
# place: encoding artifacts (º, °, ó), spacing, abbreviations, or municipality
# name aliases (Muyupampa = Villa Vaca Guzmán).
ine_norm <- ine_geog_2013 |>
  mutate(
    com_name  = str_trim(`CIUDAD/COMUNIDAD`),
    match_key = case_when(
      # Spelling / abbreviation corrections
      com_name == "OKINAWA 1"                       ~ normalize_match_key("OKINAWA UNO"),
      com_name == "3o GRUPO VALLE HERMOSO"           ~ normalize_match_key("3O GRUPO VALLE HERMOSO"),
      com_name == "TAIPIPLAYA"                       ~ normalize_match_key("TANIPLAYA"),
      com_name == "SINDICATO AGRARIO IMILLA IMILLA"  ~ normalize_match_key("SINDICATO AGRARIO IMILLA"),
      com_name == "VALLE SACTA (Disperso)"            ~ normalize_match_key("VALLE SACTA (DISPERSO)"),
      com_name == "VALLE DE CONCEPCION"              ~ normalize_match_key("CONCEPCION"),
      com_name == "VACAS K UCHU"                     ~ normalize_match_key("VACAS KUCHU"),
      # Municipality alias: Muyupampa = Villa Vaca Guzmán
      com_name == "MUYUPAMPA"                        ~ normalize_match_key("VILLA VACA GUZMAN"),
      # All other names: normalize encoding artifacts via key
      TRUE                                           ~ normalize_match_key(com_name)
    )
  )

# ---------------------------------------------------------------------------
# Join on department + match_key to build crosswalk
# ---------------------------------------------------------------------------
# Note: geo has no municipality column, so names repeated within a department
# produce ambiguous matches. These are flagged rather than excluded.

crosswalk_raw <- ine_norm |>
  select(Codigo, department, municipality, com_name, match_key) |>
  left_join(
    geo_norm |> select(nombre_dep, nombre_c_1, id_unico, match_key),
    by           = c("department" = "nombre_dep", "match_key"),
    relationship = "many-to-many"
  )

# Count distinct geo matches per INE record
match_counts <- crosswalk_raw |>
  filter(!is.na(id_unico)) |>
  group_by(Codigo) |>
  summarise(n_geo = n_distinct(id_unico), .groups = "drop")

# Final crosswalk: label each record with its match status
crosswalk_geo_ine <- crosswalk_raw |>
  left_join(match_counts, by = "Codigo") |>
  mutate(
    n_geo        = coalesce(n_geo, 0L),
    match_status = case_when(
      is.na(id_unico) ~ "unmatched",
      n_geo == 1       ~ "unique",
      n_geo > 1        ~ "ambiguous"
    )
  ) |>
  select(Codigo, department, municipality, com_name, id_unico, match_status, n_geo)

# ---------------------------------------------------------------------------
# Spatial join: assign geo points to INE municipalities via GADM boundaries
# to resolve ambiguous name matches (same community name in multiple municipalities)
# ---------------------------------------------------------------------------

# Download GADM Bolivia level-3 (municipality) boundaries if not cached
gadm_path <- "data/gadm41_BOL_3.gpkg"
if (!file.exists(gadm_path)) {
  download.file(
    "https://geodata.ucdavis.edu/gadm/gadm4.1/gpkg/gadm41_BOL.gpkg",
    destfile = gadm_path, mode = "wb", quiet = TRUE
  )
}
mun_boundaries <- st_read(gadm_path, layer = "ADM_ADM_3", quiet = TRUE)
# NAME_1 = department, NAME_2 = province, NAME_3 = municipality

# Build GADM lookup keyed on normalized names
gadm_lookup <- mun_boundaries |>
  st_drop_geometry() |>
  select(gadm_dep = NAME_1, gadm_prov = NAME_2, gadm_mun = NAME_3) |>
  mutate(dep_key = normalize_match_key(gadm_dep),
         mun_key = normalize_match_key(gadm_mun))

# INE municipality lookup with normalized keys
ine_mun_lookup <- ine_geog_2013 |>
  select(department, province, municipality, cod.mun) |>
  distinct() |>
  mutate(dep_key = normalize_match_key(department),
         mun_key = normalize_match_key(municipality))

# Direct name matches (295 of 339)
direct_match <- ine_mun_lookup |>
  inner_join(gadm_lookup |> select(dep_key, mun_key, gadm_mun, gadm_prov),
             by = c("dep_key", "mun_key"))

# Manual overrides for INE->GADM municipality name differences
# (different spellings, abbreviations, historical name changes)
mun_manual <- tribble(
  ~department,   ~ine_mun,                        ~gadm_mun,
  "La Paz",      "La Paz",                         "Nuestra Señora de La Paz",
  "La Paz",      "Callapa",                        "Santiago de Callapa",
  "La Paz",      "Pto. Carabuco",                  "Puerto Mayor de Carabuco",
  "La Paz",      "Guaqui",                         "Puerto Mayor de Guaqui",
  "La Paz",      "Jesús de Machaca",               "Jesús de Machaka",
  "La Paz",      "San Andrés de Machaca",          "La (Marka) San Andrés de Machaca",
  "La Paz",      "San Pedro Cuarahuara",           "San Pedro de Curahuara",
  "La Paz",      "Ancoraimes",                     "Villa Ancoraimes",
  "La Paz",      "Sica Sica",                      "Sicasica",
  "Oruro",       "Quillacas",                      "Santuario de Quillacas",
  "Oruro",       "Huari",                          "Santiago de Huari",
  "Oruro",       "Salinas de García Mendoza",      "Salinas de Garcí Mendoza",
  "Oruro",       "Santiago de Andamarca",          "Andamarca",
  "Oruro",       "San Pedro de Totora",            "Totora",
  "Oruro",       "Pari - Paria - Soracachi",       "Paria",
  "Oruro",       "Choque Cota",                    "Choquecota",
  "Oruro",       "Yunguyo de Litoral",             "Yunguyo del Litoral",
  "Potosi",      "Villa de Sacaca",                "Sacaca",
  "Potosi",      "San Pablo de Lipez",             "San Pablo",
  "Potosi",      "Vitichi",                        "Vitiche",
  "Potosi",      "Chuquiuta",                      "Chuquihuta Ayllu Jucumani",
  "Tarija",      "Villamontes",                    "Villa Montes",
  "Tarija",      "Villa San Lorenzo",              "San Lorenzo",
  "Chuquisaca",  "Muyupampa",                      "Villa Vaca Guzmán",
  "Chuquisaca",  "Villa Alcalá",                   "Villa Abecia",
  "Chuquisaca",  "Sopachuy",                       "Sopachui",
  "Chuquisaca",  "Icla",                           "Incahuasi",
  "Santa Cruz",  "San Ignacio de Velasco",         "San Ignacio",
  "Santa Cruz",  "San Miguel de Velasco",          "San Miguel",
  "Santa Cruz",  "San Juan de Yapacaní",           "San Juan",
  "Santa Cruz",  "San José de Chiquitos",          "San José",
  "Santa Cruz",  "Santa Rosa del Sara",            "Santa Rosa",
  "Santa Cruz",  "Gral. Saavedra",                 "General Saavedra",
  "Santa Cruz",  "Carmen Rivero Torrez",           "El Carmen Rivero Tórrez",
  "Santa Cruz",  "Ascensión de Guarayos",          "Ascención de Guarayos",
  "Santa Cruz",  "Postrer Valle",                  "Postrervalle",
  "Santa Cruz",  "Moro Moro",                      "Moromoro",
  "Beni",        "Rurrenabaque",                   "Puerto Menor de Rurrenabaque",
  "Beni",        "Santa Ana de Yacuma",            "Santa Ana",
  "Pando",       "Gonzalo Moreno",                 "Puerto Gonzalo Moreno",
  "Pando",       "Villa Nueva (Loma Alta)",         "Villa Nueva",
  # Municipalities where INE and GADM use different names for the same unit
  "Cochabamba",  "Independencia",                  "Ayopaya",                      # GADM uses province name
  "Cochabamba",  "Cuchumuela",                     "Villa Gualberto Villarroel",
  "Potosi",      "S.P. De Buena Vista",            "San Pedro"                     # Charcas province
)

ine_to_gadm_manual <- mun_manual |>
  mutate(dep_key = normalize_match_key(department),
         mun_key = normalize_match_key(gadm_mun)) |>
  left_join(gadm_lookup |> select(dep_key, mun_key, gadm_mun_actual = gadm_mun),
            by = c("dep_key", "mun_key")) |>
  left_join(ine_mun_lookup |> select(department, municipality, cod.mun),
            by = c("department", "ine_mun" = "municipality")) |>
  select(cod.mun, department, municipality = ine_mun, gadm_mun = gadm_mun_actual)

ine_to_gadm <- bind_rows(
  direct_match |> select(cod.mun, department, municipality, gadm_mun),
  ine_to_gadm_manual
)

# Attach INE cod.mun to GADM geometries (336 of 339 municipalities)
mun_sf <- mun_boundaries |>
  mutate(dep_key = normalize_match_key(NAME_1),
         mun_key = normalize_match_key(NAME_3)) |>
  inner_join(
    ine_to_gadm |> mutate(dep_key = normalize_match_key(department),
                           mun_key = normalize_match_key(gadm_mun)),
    by = c("dep_key", "mun_key")
  ) |>
  select(cod.mun, department, municipality)

# Spatial join: assign each geo point to a municipality polygon
geo_with_mun <- st_join(geo |> select(id_unico, nombre_dep, nombre_c_1),
                         mun_sf, join = st_within)

# Fallback: snap border/edge points to nearest polygon
unassigned <- geo_with_mun |> filter(is.na(cod.mun))
if (nrow(unassigned) > 0) {
  nearest_idx <- st_nearest_feature(unassigned, mun_sf)
  nearest_mun <- mun_sf |> st_drop_geometry() |> slice(nearest_idx)
  unassigned_fixed <- unassigned |> st_drop_geometry() |>
    mutate(cod.mun      = nearest_mun$cod.mun,
           department   = nearest_mun$department,
           municipality = nearest_mun$municipality)
  geo_mun_final <- bind_rows(
    geo_with_mun |> st_drop_geometry() |> filter(!is.na(cod.mun)),
    unassigned_fixed
  )
} else {
  geo_mun_final <- geo_with_mun |> st_drop_geometry()
}

# ---------------------------------------------------------------------------
# Resolve ambiguous crosswalk matches using spatial municipality assignment
# ---------------------------------------------------------------------------
ambiguous_raw <- crosswalk_raw |>
  left_join(match_counts, by = "Codigo") |>
  mutate(n_geo = coalesce(n_geo, 0L)) |>
  filter(!is.na(id_unico), n_geo > 1) |>
  left_join(ine_mun_lookup |> select(municipality, cod.mun), by = "municipality") |>
  left_join(geo_mun_final |> select(id_unico, cod.mun_geo = cod.mun),
            by = "id_unico", relationship = "many-to-many")

resolved <- ambiguous_raw |>
  filter(cod.mun == cod.mun_geo) |>
  group_by(Codigo) |>
  mutate(n_after = n_distinct(id_unico)) |>
  ungroup()

# Final crosswalk with five match statuses:
#   unique              – direct 1-to-1 name match
#   unique_via_spatial  – ambiguous name resolved by spatial municipality
#   ambiguous           – multiple geo candidates remain after spatial filter
#   ambiguous_no_spatial– no spatial municipality could be assigned
#   unmatched           – no geo entry found at all
crosswalk_geo_ine <- bind_rows(
  # Original unique matches
  crosswalk_raw |>
    left_join(match_counts, by = "Codigo") |>
    mutate(n_geo = coalesce(n_geo, 0L)) |>
    filter(n_geo == 1) |>
    mutate(match_status = "unique"),
  # Ambiguous resolved to 1 by spatial join
  resolved |>
    filter(n_after == 1) |>
    mutate(match_status = "unique_via_spatial") |>
    select(Codigo, department, municipality, com_name, id_unico, match_status, n_geo),
  # Still ambiguous after spatial filter
  resolved |>
    filter(n_after > 1) |>
    mutate(match_status = "ambiguous") |>
    select(Codigo, department, municipality, com_name, id_unico, match_status, n_geo),
  # Ambiguous with no spatial municipality assigned
  crosswalk_raw |>
    left_join(match_counts, by = "Codigo") |>
    mutate(n_geo = coalesce(n_geo, 0L)) |>
    filter(n_geo > 1, !Codigo %in% resolved$Codigo) |>
    mutate(match_status = "ambiguous_no_spatial"),
  # Unmatched
  crosswalk_raw |>
    left_join(match_counts, by = "Codigo") |>
    mutate(n_geo = coalesce(n_geo, 0L)) |>
    filter(is.na(id_unico)) |>
    mutate(match_status = "unmatched")
) |>
  select(Codigo, department, municipality, com_name, id_unico, match_status, n_geo)

# ---------------------------------------------------------------------------
# Name-lookup fallback for ambiguous_no_spatial records
# ---------------------------------------------------------------------------
# Some geo points fell outside GADM polygon boundaries (nearest-feature placed
# them in an adjacent municipality). For INE records where the community name
# is unambiguous within the department (appears in exactly one municipality),
# pick the geo candidate closest to that municipality's centroid.

# Department+name combinations that uniquely identify one INE municipality
ine_name_to_mun <- ine_norm |>
  select(department, match_key, municipality, cod.mun) |>
  distinct() |>
  group_by(department, match_key) |>
  filter(n_distinct(municipality) == 1) |>
  ungroup() |>
  select(department, match_key, municipality_ine = municipality, cod.mun_ine = cod.mun)

# Municipality centroids (for picking the closest geo candidate)
mun_centroids_all <- mun_sf |>
  mutate(centroid_lon = st_coordinates(st_centroid(mun_sf))[,1],
         centroid_lat = st_coordinates(st_centroid(mun_sf))[,2]) |>
  st_drop_geometry() |>
  select(cod.mun, centroid_lon, centroid_lat)

geo_coords <- geo |>
  st_drop_geometry() |>
  mutate(lon = st_coordinates(geo)[,1],
         lat = st_coordinates(geo)[,2]) |>
  select(id_unico, lon, lat)

name_fallback_resolved <- crosswalk_geo_ine |>
  filter(match_status == "ambiguous_no_spatial") |>
  left_join(ine_norm |> select(Codigo, match_key), by = "Codigo") |>
  left_join(ine_name_to_mun, by = c("department", "match_key")) |>
  filter(!is.na(municipality_ine)) |>      # only unambiguous names
  left_join(geo_coords, by = "id_unico") |>
  left_join(mun_centroids_all, by = c("cod.mun_ine" = "cod.mun")) |>
  mutate(dist_to_centroid = sqrt((lon - centroid_lon)^2 + (lat - centroid_lat)^2)) |>
  group_by(Codigo) |>
  slice_min(dist_to_centroid, n = 1, with_ties = FALSE) |>
  ungroup() |>
  mutate(match_status = "unique_via_name") |>
  select(Codigo, department, municipality, com_name, id_unico, match_status, n_geo)

# Rebuild crosswalk incorporating the name-fallback resolutions
crosswalk_geo_ine <- bind_rows(
  crosswalk_geo_ine |> filter(match_status != "ambiguous_no_spatial"),
  name_fallback_resolved,
  crosswalk_geo_ine |>
    filter(match_status == "ambiguous_no_spatial",
           !Codigo %in% name_fallback_resolved$Codigo)
) |>
  select(Codigo, department, municipality, com_name, id_unico, match_status, n_geo)

# ---------------------------------------------------------------------------
# USCA polygon spatial join: resolve remaining ambiguous entries
# ---------------------------------------------------------------------------
# usca_final.shp contains community-level multipolygon boundaries keyed by
# a 10-digit INE code (cod10dig). Padding with a leading zero gives the
# 11-digit Codigo used here. For each still-ambiguous INE Codigo, if exactly
# one of its candidate IGM points falls inside the matching USCA polygon,
# that point is assigned as unique_via_usca.

usca_valid <- st_make_valid(
  st_read("data/igm_localizacion_2016/../etnicidad_tenencia/usca_final.shp", quiet = TRUE)
)

# Spatial join: each IGM point gets the USCA cod10dig of the polygon it falls within
igm_spatial_ine <- st_join(
  geo |> select(id_unico),
  usca_valid |> select(cod10dig),
  join = st_within
) |>
  st_drop_geometry() |>
  # De-duplicate: keep first match for points on polygon boundaries
  distinct(id_unico, .keep_all = TRUE) |>
  # Pad to 11-digit Codigo format
  mutate(spatial_ine = if_else(!is.na(cod10dig), paste0("0", cod10dig), NA_character_)) |>
  select(id_unico, spatial_ine)

# Identify still-ambiguous entries
still_ambiguous_codes <- crosswalk_geo_ine |>
  filter(match_status %in% c("ambiguous", "ambiguous_no_spatial"))

# For each Codigo, keep the one candidate whose spatial_ine matches Codigo exactly,
# but only when that match is unique among candidates.
usca_resolved <- still_ambiguous_codes |>
  left_join(igm_spatial_ine, by = "id_unico") |>
  group_by(Codigo) |>
  mutate(n_exact_match = sum(spatial_ine == Codigo, na.rm = TRUE)) |>
  ungroup() |>
  filter(n_exact_match == 1, spatial_ine == Codigo) |>
  mutate(match_status = "unique_via_usca") |>
  select(Codigo, department, municipality, com_name, id_unico, match_status, n_geo)

# Rebuild crosswalk incorporating USCA resolutions
crosswalk_geo_ine <- bind_rows(
  crosswalk_geo_ine |> filter(!match_status %in% c("ambiguous", "ambiguous_no_spatial")),
  usca_resolved,
  still_ambiguous_codes |> filter(!Codigo %in% usca_resolved$Codigo)
) |>
  select(Codigo, department, municipality, com_name, id_unico, match_status, n_geo)

# ---------------------------------------------------------------------------
# Detect canton-split groups: INE codes that share an identical set of IGM
# candidate points because the same community was renumbered across cantons
# ---------------------------------------------------------------------------

# Build a signature for each Codigo's candidate id_unico set
id_set_sig <- crosswalk_geo_ine |>
  filter(match_status == "ambiguous", !is.na(id_unico)) |>
  group_by(Codigo) |>
  summarise(id_key = paste(sort(unique(id_unico)), collapse = "|"), .groups = "drop")

# Group Codigos that share the same candidate set
canton_split_map <- id_set_sig |>
  group_by(id_key) |>
  filter(n() > 1) |>
  mutate(canton_split_group = min(Codigo)) |>  # canonical group ID = lowest code
  ungroup() |>
  select(Codigo, canton_split_group)

# Apply: relabel ambiguous_canton_split and attach group ID
crosswalk_geo_ine <- crosswalk_geo_ine |>
  left_join(canton_split_map, by = "Codigo") |>
  mutate(
    match_status = if_else(
      match_status == "ambiguous" & !is.na(canton_split_group),
      "ambiguous_canton_split",
      match_status
    )
  )

# crosswalk_geo_ine |> count(match_status)
# unique:                  13,998  (direct name match)
# unique_via_spatial:       4,077  (resolved by GADM municipality spatial join)
# unique_via_name:             23  (unambiguous name, closest to correct municipality centroid)
# unique_via_usca:            142  (resolved by USCA community polygon spatial join)
# ambiguous_canton_split:   1,518  (same community renumbered across cantons; N codes -> same IGM pool)
# ambiguous:                  584  (genuinely repeated name within municipality; manual review needed)
# ambiguous_no_spatial:       617  (name also repeated across municipalities in INE)
# unmatched:                    5  (no geo entry exists)

# ---------------------------------------------------------------------------
# Dispersed settlement pools: reclassify ambiguous cases where every candidate
# IGM point is tipo_area == "dis" (dispersed settlement).
# The IGM dataset records multiple points for the same dispersed community;
# all candidates are valid coordinates — downstream code should treat them as a pool.
# ---------------------------------------------------------------------------
pure_dis_codes <- crosswalk_geo_ine |>
  filter(match_status %in% c("ambiguous", "ambiguous_no_spatial"), !is.na(id_unico)) |>
  left_join(
    geo |> st_drop_geometry() |> select(id_unico, tipo_area),
    by = "id_unico"
  ) |>
  group_by(Codigo) |>
  filter(all(tipo_area == "dis")) |>
  pull(Codigo) |>
  unique()

crosswalk_geo_ine <- crosswalk_geo_ine |>
  mutate(match_status = if_else(
    match_status %in% c("ambiguous", "ambiguous_no_spatial") & Codigo %in% pure_dis_codes,
    "ambiguous_dispersed",
    match_status
  ))

# ---------------------------------------------------------------------------
# Cross-municipality adjacency splitting for ambiguous_no_spatial cases
# ---------------------------------------------------------------------------
# Some ambiguous_no_spatial communities have the same name in two municipalities
# that are NOT geographically adjacent. In those cases, the candidate IGM points
# can be divided into two separate pools by which municipality polygon they fall
# in — resolving the ambiguity without manual review.
#
# Approach:
#   1. Find ambiguous_no_spatial groups spanning exactly 2 municipalities.
#   2. Check whether the municipality pairs are adjacent (st_touches).
#   3. For non-adjacent pairs, spatially assign each candidate point to one of
#      the two municipalities (st_within, with st_nearest_feature fallback).
#   4. Reassign each Codigo's candidate pool to only the points in its municipality.
#   5. Reclassify: n_geo == 1 → unique_via_spatial; n_geo > 1 → ambiguous_dispersed.

cross_mun_groups <- crosswalk_geo_ine |>
  filter(match_status == "ambiguous_no_spatial") |>
  left_join(ine_geog_2013 |> select(Codigo, province), by = "Codigo") |>
  group_by(department, com_name) |>
  summarise(
    municipalities = list(sort(unique(municipality))),
    codigos        = list(unique(Codigo)),
    ids            = list(unique(id_unico)),
    n_mun          = n_distinct(municipality),
    .groups = "drop"
  ) |>
  filter(n_mun == 2)

# For each group, check municipality adjacency and split if non-adjacent
split_results <- list()

for (i in seq_len(nrow(cross_mun_groups))) {
  grp  <- cross_mun_groups[i, ]
  muns <- grp$municipalities[[1]]
  dept <- grp$department

  # Look up GADM cod.mun for each municipality name
  mun_rows <- mun_sf |> st_drop_geometry() |>
    filter(department == dept, municipality %in% muns)

  if (nrow(mun_rows) != 2) next  # safety: skip if GADM match is ambiguous

  cod1 <- mun_rows$cod.mun[1]; cod2 <- mun_rows$cod.mun[2]

  # Skip adjacent municipalities — splitting wouldn't be justified
  adjacent <- st_touches(
    mun_sf |> filter(cod.mun == cod1),
    mun_sf |> filter(cod.mun == cod2),
    sparse = FALSE
  )[1, 1]
  if (adjacent) next

  # Spatially assign each candidate point to one of the two municipality polygons
  pts   <- geo |> filter(id_unico %in% grp$ids[[1]]) |> select(id_unico)
  polys <- mun_sf |> filter(cod.mun %in% c(cod1, cod2))

  assigned <- st_join(pts, polys |> select(cod.mun, municipality), join = st_within)
  unassigned_pts <- assigned |> filter(is.na(cod.mun))
  if (nrow(unassigned_pts) > 0) {
    nearest_idx <- st_nearest_feature(unassigned_pts, polys)
    assigned$cod.mun[is.na(assigned$cod.mun)]         <- polys$cod.mun[nearest_idx]
    assigned$municipality[is.na(assigned$municipality)] <- polys$municipality[nearest_idx]
  }
  assigned <- assigned |> st_drop_geometry()

  # Map each Codigo to the points in its municipality
  codigo_mun <- crosswalk_geo_ine |>
    filter(Codigo %in% grp$codigos[[1]]) |>
    distinct(Codigo, municipality)

  split_results[[i]] <- assigned |>
    left_join(codigo_mun, by = "municipality") |>
    filter(!is.na(Codigo)) |>
    select(Codigo, id_unico)
}

split_map <- bind_rows(split_results)

if (nrow(split_map) > 0) {
  # Codigos involved in a split
  split_codigos <- unique(split_map$Codigo)

  # Build replacement rows
  resolved_cross_mun <- crosswalk_geo_ine |>
    filter(Codigo %in% split_codigos) |>
    # Keep only candidate rows whose id_unico was assigned to this Codigo
    semi_join(split_map, by = c("Codigo", "id_unico")) |>
    group_by(Codigo) |>
    mutate(n_geo = n_distinct(id_unico)) |>
    ungroup() |>
    mutate(match_status = if_else(n_geo == 1, "unique_via_spatial", "ambiguous_dispersed"))

  crosswalk_geo_ine <- bind_rows(
    crosswalk_geo_ine |> filter(!Codigo %in% split_codigos),
    resolved_cross_mun
  )
}

# ---------------------------------------------------------------------------
# Mixed-type resolution: remaining ambiguous cases with at least one non-dis point
# ---------------------------------------------------------------------------
# Among the still-ambiguous codes, any candidate with tipo_area %in% c("cp","cpd","ci")
# is a named population centre — a better representative than dispersed points.
# Resolution rules:
#   - Exactly 1 non-dis candidate → select it as unique_via_spatial.
#   - 2+ non-dis candidates of different types → prefer cp/cpd over ci.
#   - 2+ non-dis candidates of the same type → leave ambiguous (cannot determine
#     the correct point without external data; e.g. SANTA ANA in San Javier).

# Attach tipo_area to all remaining ambiguous candidates
amb_remaining <- crosswalk_geo_ine |>
  filter(match_status %in% c("ambiguous", "ambiguous_no_spatial")) |>
  left_join(
    geo |> st_drop_geometry() |> select(id_unico, tipo_area, tipo_pobla),
    by = "id_unico"
  )

# Find codes that have at least one non-dis candidate
mixed_type_codes <- amb_remaining |>
  group_by(Codigo) |>
  filter(any(tipo_area != "dis")) |>
  ungroup()

# For each code, identify the single best non-dis point
# Priority: cp/cpd (population centre) > ci (urban centre)
best_nondis <- mixed_type_codes |>
  filter(tipo_area != "dis") |>
  mutate(type_rank = case_when(
    tipo_area %in% c("cp", "cpd") ~ 1L,
    tipo_area == "ci"             ~ 2L,
    TRUE                          ~ 3L
  )) |>
  group_by(Codigo) |>
  arrange(type_rank, .by_group = TRUE) |>
  mutate(
    n_non_dis      = n(),
    top_rank       = first(type_rank),
    n_at_top_rank  = sum(type_rank == top_rank)
  ) |>
  ungroup()

# Resolvable: codes where the top-ranked non-dis type appears exactly once
resolvable_mixed <- best_nondis |>
  filter(n_at_top_rank == 1) |>
  group_by(Codigo) |>
  slice_min(type_rank, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(Codigo, department, municipality, com_name, id_unico, n_geo) |>
  mutate(
    match_status       = "unique_via_spatial",
    canton_split_group = NA_character_,
    n_geo              = 1L
  )

# Apply
crosswalk_geo_ine <- bind_rows(
  crosswalk_geo_ine |> filter(!Codigo %in% resolvable_mixed$Codigo),
  resolvable_mixed
)

# crosswalk_geo_ine |> count(match_status)
# unique:                  13,998  (direct name match)
# unique_via_spatial:       4,138  (resolved by GADM, adjacency split, or population-centre selection)
# unique_via_name:             23  (unambiguous name, closest to correct municipality centroid)
# unique_via_usca:            142  (resolved by USCA community polygon spatial join)
# ambiguous_canton_split:   1,518  (same community renumbered across cantons; N codes -> same IGM pool)
# ambiguous_dispersed:        992  (all candidates are dispersed-type points; treat as coordinate pool)
# ambiguous_no_spatial:         8  (SANTA ANA/San Javier: two cp points 133 km apart; unresolvable)
# unmatched:                    5  (no geo entry exists)

# Save crosswalk for use in downstream scripts
saveRDS(crosswalk_geo_ine, "data/crosswalk_ine_igm.rds")
write.csv(crosswalk_geo_ine, "data/crosswalk_ine_igm.csv", row.names = FALSE)

# ---------------------------------------------------------------------------
# ine_match_status(): look up the crosswalk status for an INE community code
# ---------------------------------------------------------------------------
# Accepts both 10-digit (cod10dig style, no leading zero) and 11-digit (Codigo
# style, leading zero) forms. Returns a human-readable summary.
#
# match_status values:
#   unique                 – one IGM geo point matched by name within department
#   unique_via_spatial     – ambiguous name resolved by GADM municipality boundary
#   unique_via_name        – ambiguous name resolved by proximity to municipality centroid
#   unique_via_usca        – ambiguous name resolved by USCA community polygon
#   ambiguous_canton_split – same community listed under multiple canton codes due to
#                            administrative reorganisation; all codes in the group share
#                            the same IGM candidate pool (many-to-one is intentional)
#   ambiguous_dispersed    – all IGM candidates are tipo_area == "dis" (dispersed settlement);
#                            the IGM dataset recorded multiple points for the same dispersed
#                            community; treat all candidates as a valid coordinate pool
#   ambiguous              – multiple IGM candidates remain after all spatial steps;
#                            the community name appears in more than one distinct location
#                            within the same municipality; manual review needed
#   ambiguous_no_spatial   – same as ambiguous, but the name also recurs across
#                            multiple municipalities and no spatial disambiguation succeeded
#   unmatched              – no IGM geo point found with a matching name
#   not_found              – the code does not exist in the INE community list

ine_match_status <- function(codigo, crosswalk = crosswalk_geo_ine) {
  # Normalise to 11-digit form (pad with leading zero if 10 digits)
  codigo <- as.character(codigo)
  codigo <- ifelse(nchar(codigo) == 10, paste0("0", codigo), codigo)

  rows <- crosswalk[crosswalk$Codigo == codigo, ]

  if (nrow(rows) == 0) {
    cat("Code", codigo, "not found in crosswalk.\n")
    return(invisible(NULL))
  }

  status      <- rows$match_status[1]
  com_name    <- rows$com_name[1]
  mun         <- rows$municipality[1]
  dep         <- rows$department[1]
  split_group <- rows$canton_split_group[1]

  explanation <- switch(status,
    unique =
      "Uniquely matched: one IGM geo point shares this community's name within its department.",
    unique_via_spatial =
      "Uniquely matched via GADM spatial join: an ambiguous name match was resolved by confirming the geo point lies within the correct municipality boundary.",
    unique_via_name =
      "Uniquely matched via name proximity: an ambiguous match was resolved by selecting the geo point closest to the correct municipality centroid.",
    unique_via_usca =
      "Uniquely matched via USCA polygon: an ambiguous match was resolved by confirming the geo point falls inside the USCA community boundary for this INE code.",
    ambiguous_canton_split = {
      grp_codes <- sort(unique(crosswalk$Codigo[
        !is.na(crosswalk$canton_split_group) &
        crosswalk$canton_split_group == split_group
      ]))
      paste0(
        "Canton-split duplicate: this community appears under ", length(grp_codes),
        " INE codes (", paste(grp_codes, collapse = ", "), ") because canton boundaries ",
        "were reorganised over time. All codes in this group point to the same pool of ",
        n_distinct(rows$id_unico), " IGM geo candidate(s). ",
        "Many-to-one mapping (several codes -> same IGM points) is expected here."
      )
    },
    ambiguous_dispersed = paste0(
      "Dispersed settlement pool: ", n_distinct(rows$id_unico), " IGM geo points all typed ",
      "as 'dis' (dispersed) share this community's name. The IGM dataset recorded multiple ",
      "points for the same dispersed community. All candidates are valid coordinates for ",
      "this community — use them as a pool rather than selecting one."
    ),
    ambiguous = paste0(
      "Ambiguous: ", rows$n_geo[1], " IGM geo points share this community's name within ",
      mun, " municipality. The correct point cannot be determined automatically. ",
      "Manual review or additional data is needed."
    ),
    ambiguous_no_spatial = paste0(
      "Ambiguous (cross-municipality): ", rows$n_geo[1], " IGM geo points share this ",
      "community's name and it recurs across multiple municipalities. No spatial ",
      "disambiguation was possible. Manual review is needed."
    ),
    unmatched =
      "Unmatched: no IGM geo point with a matching name was found for this community.",
    paste("Unknown status:", status)
  )

  cat(sprintf(
    "Code:        %s\nCommunity:   %s\nMunicipality:%s (%s)\nStatus:      %s\n\n%s\n",
    codigo, com_name, mun, dep, status, explanation
  ))

  invisible(rows)
}
