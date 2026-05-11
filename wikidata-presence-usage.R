library(httr)
library(jsonlite)
library(dplyr)
library(stringr)
library(purrr)
library(tidyr)

country_wiki_presence <- wikidata_instance_wikipedia_presence(
       class_qid  = "Q6256",
       languages  = NULL, # all languages
       limit      = 500,
       batch_size = 20
  )

country_wiki_presence$data |> skimr::skim()

country_per_wikipedia <- country_wiki_presence$data %>%
  summarise(across(where(is.numeric), sum, na.rm = TRUE)) %>%
  pivot_longer(everything(), names_to="wikipedia", values_to= "n_countries")

country_wiki_presence$data <- country_wiki_presence$data |>
  mutate(n_wikipedias = rowSums(across(where(is.numeric))))
country_wiki_presence$data |> arrange(desc(n_wikipedias)) |>
  select(1, 2, n_wikipedias) |> print(n=20)
country_wiki_presence$data |> arrange(desc(n_wikipedias)) |>
  select(1, 2, n_wikipedias) |> tail(20)


colSums (country_wiki_presence$data[4:342], na.rm = FALSE, dims = 1)



country_per_wikipedia |> arrange(desc(n_countries)) |> head(20)


country_per_wikipedia |> arrange((n_countries)) |> head(20)

country_per_wikipedia |> count(n_countries)

country_wiki_presence$data |> filter(ar & !en) |> pull(1, 2)


country_details <- get_wikidata_instances(
  class_qid = "Q6256",
  property = c("P297", "P2046"),
  property_names = c("iso_code", "area")
)

country_details <- country_details |>
  mutate(iso_code = purrr::map_chr(iso_code, function(x) {
    if (length(x) == 0) return(NA_character_)
    paste(x, collapse = ", ")
  }))

library(dplyr)
library(ggplot2)
library(sf)
library(rnaturalearth)

# 1. Join your datasets on QID
# We use the cleaned iso_code for the map join later
map_data_prepared <- country_details |>
  dplyr::inner_join(
    country_wiki_presence$data |> dplyr::select(qid, n_wikipedias),
    by = "qid"
  ) |>
  # In case iso_code has multiple values, take the first for mapping
  dplyr::mutate(iso_map = stringr::str_extract(iso_code, "^[^, ]+"))

# 2. Get world spatial data
world_sf <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf")

# 3. Join spatial data with your wiki presence stats
# Mapping your ISO codes to the 'iso_a2' field in rnaturalearth
world_joined <- world_sf |>
  dplyr::left_join(map_data_prepared, by = c("iso_a2" = "iso_map"))

# 4. Plot the Choropleth
ggplot(data = world_joined) +
  geom_sf(aes(fill = n_wikipedias), color = "white", size = 0.1) +
  scale_fill_distiller(
    palette = "BuGn",
    direction = 1,      # 1 puts light colors at the low end; -1 reverses it
    name = "Wikipedia Editions",
    na.value = "#eeeeee",
    labels = scales::comma
  ) +
  labs(
    title = "Global Wikipedia Presence by Country",
    caption = "Grey areas indicate missing ISO matches or zero data"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    panel.grid = element_blank(),
    axis.text = element_blank()
  )

# Extract the names of countries that have no Wikipedia count data
grey_areas <- world_joined |>
  dplyr::filter(is.na(n_wikipedias)) |>
  dplyr::select(name, iso_a2) |>
  # Converting from sf to a regular tibble for easier viewing
  sf::st_drop_geometry() |>
  dplyr::as_tibble()

print(grey_areas, n = 50)

# Have to solve this weird skipping behavior for 14 countries:
# Found 213 instances. Retrieving details in batches of 50...
# Batch 1/5 (50 items)...
# Item Q32 missing or not found; skipping.
# Item Q33 missing or not found; skipping.
# Item Q38 missing or not found; skipping.
# Batch 2/5 (50 items)...
# Item Q228 missing or not found; skipping.
# Item Q229 missing or not found; skipping.
# Item Q232 missing or not found; skipping.
# Item Q233 missing or not found; skipping.
# Item Q238 missing or not found; skipping.
# Item Q236 missing or not found; skipping.
# Item Q237 missing or not found; skipping.
# Item Q242 missing or not found; skipping.
# Item Q241 missing or not found; skipping.
# Item Q244 missing or not found; skipping.
# Item Q252 missing or not found; skipping.
# Batch 3/5 (50 items)...
# Batch 4/5 (50 items)...
# Batch 5/5 (13 items)...
# Successfully retrieved 199 items

library(httr)
library(jsonlite)

qid <- "Q32"
r <- GET("https://www.wikidata.org/w/api.php",
         query = list(action="wbgetentities", ids=qid, format="json",
                      props="labels|descriptions|claims|sitelinks"))
status_code(r)
txt <- content(r, "text", encoding = "UTF-8")
cat(substr(txt, 1, 1000), "\n")
obj <- fromJSON(txt)

names(obj$entities[[qid]])
obj$entities[[qid]]$missing

# Solved!

bo_department_wiki_presence <- wikidata_instance_wikipedia_presence(
  class_qid  = "Q250050",
  languages  = NULL, # all languages
  limit      = 500,
  batch_size = 20
)

# Select the 10 largest Wikipedias and the ten most common languages in
# Bolivia, only four of which have Wikipedias.
bo_department_wiki_presence$data |> select(1:3, es, qu, ay, gn,
       en, fr, de, it, ja, ru, zh, id, pl,)
# Universal coverage in these languages, but only 5 have Litoral Department



# Wikidata instance-of classes
BOLIVIA_QID            <- "Q750"
DEPARTMENT_CLASS_QID   <- "Q250050"  # department of Bolivia
PROVINCE_CLASS_QID     <- "Q1062593" # province of Bolivia
MUNICIPALITY_CLASS_QID <- "Q1062710" # municipality of Bolivia

bo_province_wiki_presence <- wikidata_instance_wikipedia_presence(
  class_qid  = PROVINCE_CLASS_QID   ,
  languages  = NULL, # all languages
  limit      = 500,
  batch_size = 20
)

bo_province_wiki_presence$data |> select(1:3, es, qu, ay, #gn, because no pages in Guaraní
                                         en, fr, de, it, ja, ru, zh, id, pl)
# gn errors, so no pages in Guaraní

# column sums
bo_province_wiki_presence$data |> select(1:3, es, qu, ay, #gn, because no pages in Guaraní
                                         en, fr, de, it, ja, ru, zh, id, pl) |>
  select(-qid, -label_en, -label_es) |> colSums(na.rm = TRUE)

bo_municipality_wiki_presence <- wikidata_instance_wikipedia_presence(
  class_qid  = MUNICIPALITY_CLASS_QID   ,
  languages  = NULL, # all languages
  limit      = 500,
  batch_size = 20
)

bo_municipality_wiki_presence$data |> select(1:3, es, qu, ay, # gn,
                                         en, fr, de, it, ja, zh, pl) # ru, id because no pages in Russian or Indonesian


bo_municipality_wiki_presence$data |> select(1:3, es, qu, ay,
                                             en, fr, de, it, ja, zh, pl)  |>
  select(-qid, -label_en, -label_es) |> colSums(na.rm = TRUE)

