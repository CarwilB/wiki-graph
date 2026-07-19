# add_osm_relations_to_wikidata.R
# ──────────────────────────────────────────────────────────────────────────────
# Finds OSM boundary relations for Bolivian municipalities missing Wikidata P402
# (OpenStreetMap relation ID) and generates QuickStatements to add them.
#
# Matching strategy:
#   1. Query all admin_level=8 boundary relations in Bolivia from Overpass
#   2. Match via `wikidata` tag on OSM relations (most reliable)
#   3. Match by cleaned municipality name (Spanish label vs OSM name)
#   4. Manual matches for remaining discrepancies
#
# Prerequisites:
#   - data/municipalities_wd_p402.rds  (from get_wikidata_instances with P402)
#   - data/municipalities_wd_ine.rds   (QID ↔ INE crosswalk)
#   - R/create_quick_statement.R
# ──────────────────────────────────────────────────────────────────────────────

library(dplyr)
library(httr)
library(jsonlite)
library(stringr)

source("R/create_quick_statement.R")

# ── 1. Load Wikidata municipality data ────────────────────────────────────────

wd_ine <- readRDS("data/municipalities_wd_ine.rds") |>
  select(qid, ine_code, label_en, label_es)

## To refresh after running QuickStatements:
# wd_p402 <- get_wikidata_instances("Q1062710", property = "P402",
#                                     property_names = "osm_relation_id", country = "Q750")
# saveRDS(wd_p402, "data/municipalities_wd_p402.rds")

wd_p402 <- readRDS("data/municipalities_wd_p402.rds")

missing_p402 <- wd_p402 |>
  filter(is.na(osm_relation_id)) |>
  left_join(wd_ine |> select(qid, ine_code, label_es), by = "qid")

cat("Municipalities missing P402:", nrow(missing_p402), "\n")

# ── 2. Query OSM for all Bolivian municipal boundary relations ────────────────

overpass_query <- '
[out:json][timeout:180];
area["ISO3166-1"="BO"]->.bolivia;
relation["boundary"="administrative"]["admin_level"="8"](area.bolivia);
out tags;
'

resp <- POST(
  "https://overpass-api.de/api/interpreter",
  body = list(data = overpass_query),
  encode = "form"
)

osm_result <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                       simplifyVector = FALSE)

osm_munis <- purrr::map_dfr(osm_result$elements, function(el) {
  tags <- el$tags
  tibble(
    osm_id         = as.character(el$id),
    name           = tags$name %||% NA_character_,
    wikidata       = tags$wikidata %||% NA_character_,
    admin_level    = tags$admin_level %||% NA_character_,
    is_in_state    = tags[["is_in:state"]] %||% NA_character_,
    is_in_province = tags[["is_in:province"]] %||% NA_character_
  )
})

cat("OSM admin_level=8 relations found:", nrow(osm_munis), "\n")

# ── 3. Round 1: Match via wikidata tag on OSM relations ───────────────────────

osm_with_qid <- osm_munis |> filter(!is.na(wikidata))

matched_via_tag <- missing_p402 |>
  inner_join(osm_with_qid |> select(osm_id, wikidata), by = c("qid" = "wikidata"))

cat("Round 1 (wikidata tag):", nrow(matched_via_tag), "matched\n")

# ── 4. Round 2: Match by cleaned Spanish name ────────────────────────────────

still_missing <- missing_p402 |>
  filter(!qid %in% matched_via_tag$qid) |>
  mutate(
    name_es_clean = label_es |>
      str_remove("^Municipio( de)?\\s+") |>
      str_remove("\\s*\\(municipio\\)$")
  )

osm_unmatched <- osm_munis |>
  filter(!wikidata %in% wd_p402$qid | is.na(wikidata)) |>
  mutate(
    name_clean = name |>
      str_remove("^Municipio( de)?\\s+") |>
      str_remove("^Gobierno Aut\u00f3nomo Municipal( de)?\\s+")
  )

matched_by_name <- still_missing |>
  filter(!is.na(name_es_clean)) |>
  inner_join(
    osm_unmatched |> filter(!is.na(name_clean)) |> select(osm_id, name_clean),
    by = c("name_es_clean" = "name_clean")
  )

cat("Round 2 (name match):", nrow(matched_by_name), "matched\n")

# ── 5. Round 3: Manual matches ───────────────────────────────────────────────
# Names that diverge between Wikidata and OSM, or OSM relation has a different
# QID in its wikidata tag (typically a city QID vs municipality QID).

manual_osm_matches <- tribble(
  ~qid,          ~osm_id,
  "Q591120",     "4499870",   # La Paz = Municipio Nuestra Señora de La Paz
  "Q920327",     "4507915",   # Yamparáez = Municipio Yamparaez
  "Q1108295",    "4511328",   # Puerto Suárez
  "Q624485",     "4126929",   # Uncía Municipality (OSM tags Q1642052)
  "Q647748",     "4494694",   # Caracollo Municipality (OSM tags Q647907)
  "Q1153550",    "4511510",   # Mineros Municipality (OSM tags Q602690)
)

# Municipalities confirmed absent from OSM (no boundary relation exists):
not_in_osm <- c(
  "Q1552084",    # Tito Yupanqui
  "Q1544578",    # Nazacara de Pacajes
  "Q775675",     # Chuquihuta
  "Q1147210",    # Ckochas
  "Q520394",     # Copacabana
  "Q1819398",    # San Pedro de Tiquina
  "Q106409795"   # San Pedro de Macha
)

# ── 6. Combine and validate ──────────────────────────────────────────────────

all_osm_matches <- bind_rows(
  matched_via_tag |> select(qid, osm_id),
  matched_by_name |> select(qid, osm_id),
  manual_osm_matches
) |> distinct(qid, .keep_all = TRUE)

# Sanity checks
stopifnot("Duplicate osm_id assignments" =
            nrow(all_osm_matches |> count(osm_id) |> filter(n > 1)) == 0)
stopifnot("All municipalities accounted for" =
            nrow(all_osm_matches) + length(not_in_osm) == nrow(missing_p402))

cat("\nTotal matched:", nrow(all_osm_matches), "\n")
cat("Not in OSM:", length(not_in_osm), "\n")

# ── 7. Generate QuickStatements ──────────────────────────────────────────────

p402_statements <- all_osm_matches |>
  left_join(wd_ine |> select(qid, label_en, ine_code), by = "qid") |>
  add_quick_statement_column(qid, "P402", osm_id)

cat("\n", nrow(p402_statements), "QuickStatements generated.\n")
cat("Preview:\n")
head(p402_statements |> select(label_en, qid, osm_id), 5)

# Copy to clipboard or write to file:
# writeLines(p402_statements$quick_statement)
# writeLines(p402_statements$quick_statement, "output/p402_quickstatements.txt")
