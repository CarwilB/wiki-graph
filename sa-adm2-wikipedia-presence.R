# sa-adm2-wikipedia-presence.R
#
# Retrieve Wikipedia presence matrices for second-level administrative divisions
# (ADM2) of every South American country via Wikidata.
#
# Strategy
# --------
# Each country/class pair is treated as one cache entry. The first run fetches
# from the API; interrupted runs resume from the partial cache via
# resume_wikidata_instance_wikipedia_presence(). A complete run is effectively
# a no-op resume (the function skips already-fetched QIDs).
#
# Argentina is split into two classes (departments / partidos) because Buenos
# Aires Province uses a distinct class from all other provinces.
#
# Brazil is in a separate section at the bottom because its ~5,570 municipalities
# make it far larger than any other country and should be run independently.
#
# Output
# ------
# Per-entry cache:  data/sa_adm2_<slug>.rds   (full presence list)
# Combined result:  data/sa_adm2_all.rds       (data frame, all non-Brazil entries)
# Brazil result:    data/sa_adm2_brazil.rds    (data frame)
#
# Known gap: Guyana — Wikidata's P150 hierarchy for Guyana is not populated,
# and the neighbourhood council class QID is unclear. Omitted for now.
# ============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(stringr)
library(purrr)
library(tidyr)

source("wikidata_presence_matrix.R")
source("R/get_wikidata_instances.R")

# ---- 1. ADM2 registry -------------------------------------------------------
#
# Each row is one fetch unit (one Wikidata class). Countries with multiple
# classes at the same administrative level get multiple rows.
#
# Columns:
#   country      — display name
#   country_qid  — Wikidata QID of the country
#   class_qid    — Wikidata QID of the ADM2 class
#   class_label  — human-readable class name
#   n_expected   — approximate Wikidata instance count (from prior research)
#   slug         — used for cache filenames

sa_adm2_registry <- tribble(
  ~country,    ~country_qid, ~class_qid,   ~class_label,                       ~n_expected, ~slug,
  "Argentina", "Q414",       "Q952274",    "department of Argentina",           386,         "argentina_dept",
  "Argentina", "Q414",       "Q13997861",  "partido of Buenos Aires Province",  135,         "argentina_partido",
  "Bolivia",   "Q750",       "Q1062593",   "province of Bolivia",               111,         "bolivia_prov",
  "Chile",     "Q298",       "Q1153408",   "province of Chile",                 56,          "chile_prov",
  "Colombia",  "Q739",       "Q2555896",   "municipality of Colombia",          1106,        "colombia_muni",
  "Ecuador",   "Q736",       "Q1724017",   "canton of Ecuador",                 221,         "ecuador_canton",
  "Paraguay",  "Q733",       "Q917092",    "municipality of Paraguay",          268,         "paraguay_muni",
  "Peru",      "Q419",       "Q509686",    "province of Peru",                  195,         "peru_prov",
  "Suriname",  "Q730",       "Q1539014",   "ressort of Suriname",               64,          "suriname_ressort",
  "Uruguay",   "Q77",        "Q3685434",   "municipality of Uruguay",           126,         "uruguay_muni",
  "Venezuela", "Q717",       "Q3327920",   "municipality of Venezuela",         332,         "venezuela_muni"
)

# ---- 2. Fetch helper --------------------------------------------------------
#
# For each registry entry: load from cache if present (resuming any partial
# fetch), or start fresh. Saves after every successful fetch.

cache_dir <- "data/cache"

fetch_or_resume <- function(class_qid, slug, n_expected,
                            languages  = NULL,
                            batch_size = 20,
                            limit      = 2000) {
  cache_file <- file.path(cache_dir, paste0("sa_adm2_", slug, ".rds"))

  if (file.exists(cache_file)) {
    partial <- readRDS(cache_file)
    n_done  <- nrow(partial$instances)
    message(slug, ": cache found (", n_done, "/~", n_expected,
            " items). Resuming if incomplete...")
    result <- resume_wikidata_instance_wikipedia_presence(
      partial_result = partial,
      class_qid      = class_qid,
      languages      = languages,
      limit          = limit,
      batch_size     = batch_size
    )
  } else {
    message(slug, ": no cache found. Starting fresh fetch...")
    result <- wikidata_instance_wikipedia_presence(
      class_qid  = class_qid,
      languages  = languages,
      limit      = limit,
      batch_size = batch_size
    )
  }

  saveRDS(result, cache_file)
  message(slug, ": done. ", nrow(result$data), " items saved to ", cache_file)
  result
}

# ---- 3. Main fetch loop (all countries except Brazil) -----------------------
#
# languages = NULL auto-discovers all Wikipedia language codes present in
# sitelinks for each class. This produces wide, per-class matrices that may
# differ in columns; they are aligned when combining below.
#
# Increase batch_size to 50 for smaller countries to speed things up;
# keep it lower (20) if you hit rate-limit errors.

sa_adm2_results <- list()

for (i in seq_len(nrow(sa_adm2_registry))) {
  entry <- sa_adm2_registry[i, ]
  message("\n=== ", entry$country, " — ", entry$class_label, " ===")
  sa_adm2_results[[entry$slug]] <- fetch_or_resume(
    class_qid  = entry$class_qid,
    slug       = entry$slug,
    n_expected = entry$n_expected,
    languages  = NULL,
    batch_size = 30,
    limit      = 2000
  )
}

# ---- 4. Combine into one data frame -----------------------------------------
#
# Each $data tibble has columns: qid, label_en, label_es, <lang1>, <lang2>, ...
# Different classes may have different language columns, so we full-join on
# column names and fill missing languages with 0.

combine_presence_data <- function(results_list, registry) {
  imap_dfr(results_list, function(result, slug) {
    meta <- registry |> filter(slug == !!slug)
    result$data |>
      mutate(
        country     = meta$country,
        country_qid = meta$country_qid,
        class_qid   = meta$class_qid,
        class_label = meta$class_label,
        slug        = slug,
        .before     = everything()
      )
  }) |>
  # Fill any language columns that are absent in some classes with 0
  mutate(across(where(is.integer), ~ replace_na(.x, 0L)))
}

sa_adm2_all <- combine_presence_data(sa_adm2_results, sa_adm2_registry)

saveRDS(sa_adm2_all, file.path(cache_dir, "sa_adm2_all.rds"))
message("\nCombined result: ", nrow(sa_adm2_all), " ADM2 units across ",
        n_distinct(sa_adm2_all$country), " countries.")

# ---- 5. Quick coverage summary ----------------------------------------------

sa_adm2_all |>
  group_by(country, class_label) |>
  summarise(
    n_units = n(),
    en      = sum(en,  na.rm = TRUE),
    es      = sum(es,  na.rm = TRUE),
    pt      = if ("pt" %in% names(pick(everything()))) sum(pt,  na.rm = TRUE) else NA_integer_,
    fr      = if ("fr" %in% names(pick(everything()))) sum(fr,  na.rm = TRUE) else NA_integer_,
    qu      = if ("qu" %in% names(pick(everything()))) sum(qu,  na.rm = TRUE) else NA_integer_,
    .groups = "drop"
  ) |>
  mutate(
    pct_en = round(100 * en / n_units, 1),
    pct_es = round(100 * es / n_units, 1)
  ) |>
  print(n = 20)

# =============================================================================
# BRAZIL — separate run
# =============================================================================
#
# Brazil has ~5,570 municipalities and no intermediate ADM2 between states and
# municipalities. Run this block independently when you have time; it will take
# 20–40 minutes depending on API speed.
#
# The cache/resume pattern is the same as above — safe to interrupt and restart.

if (FALSE) {  # Change to TRUE (or run this block manually) when ready

  brazil_cache <- file.path(cache_dir, "sa_adm2_brazil.rds")

  if (file.exists(brazil_cache)) {
    brazil_partial <- readRDS(brazil_cache)
    message("Brazil cache found (",  nrow(brazil_partial$instances),
            "/~5570 items). Resuming...")
    brazil_result <- resume_wikidata_instance_wikipedia_presence(
      partial_result = brazil_partial,
      class_qid      = "Q3184121",   # municipality of Brazil
      languages      = NULL,
      limit          = 6000,
      batch_size     = 20
    )
  } else {
    message("Brazil: starting fresh fetch (~5570 items, expect 20-40 minutes)...")
    brazil_result <- wikidata_instance_wikipedia_presence(
      class_qid  = "Q3184121",       # municipality of Brazil
      languages  = NULL,
      limit      = 6000,
      batch_size = 20
    )
  }

  saveRDS(brazil_result, brazil_cache)
  message("Brazil done: ", nrow(brazil_result$data), " municipalities saved.")

  # Attach metadata and save as flat data frame
  brazil_df <- brazil_result$data |>
    mutate(
      country     = "Brazil",
      country_qid = "Q155",
      class_qid   = "Q3184121",
      class_label = "municipality of Brazil",
      slug        = "brazil_muni",
      .before     = everything()
    )
  saveRDS(brazil_df, file.path(cache_dir, "sa_adm2_brazil_df.rds"))

  # Quick summary
  brazil_df |>
    summarise(
      n_units  = n(),
      en       = sum(en, na.rm = TRUE),
      es       = sum(es, na.rm = TRUE),
      pt       = sum(pt, na.rm = TRUE)
    ) |>
    mutate(pct_en = round(100 * en / n_units, 1),
           pct_pt = round(100 * pt / n_units, 1))
}


# ---

new_countries <- tribble(
  ~name,                ~qid,
  "Mexico",             "Q96",
  "Guatemala",          "Q774",
  "Belize",             "Q242",
  "El Salvador",        "Q792",
  "Honduras",           "Q783",
  "Nicaragua",          "Q811",
  "Costa Rica",         "Q800",
  "Panama",             "Q804",
  "Cuba",               "Q241",
  "Dominican Republic", "Q786",
  "Haiti",              "Q790",
  "Puerto Rico",        "Q1183"
)

# message("Querying ADM2 classes via P150 for new countries...")
#
# sparql_query <- function(query) {
#   r <- GET(
#     "https://query.wikidata.org/sparql",
#     query = list(query = query, format = "json"),
#     user_agent("WikidataR-admin-division-research")
#   )
#   if (status_code(r) != 200) stop("SPARQL failed: ", status_code(r))
#   res <- fromJSON(content(r, "text", encoding = "UTF-8"))
#   if (length(res$results$bindings) == 0) return(tibble())
#   as_tibble(res$results$bindings) |>
#     mutate(across(everything(), ~ .x$value))
# }


# Better approach: use P150 (contains administrative territorial entity)
# which is the explicit "subdivided into" property on Wikidata
# This directly models the administrative hierarchy

get_second_level_classes_v2 <- function(country_qid, country_name) {
  Sys.sleep(2)
  q <- sprintf('
SELECT ?class ?classLabel (COUNT(DISTINCT ?item) AS ?n) WHERE {
  # First-level divisions: items directly listed as P150 of the country
  wd:%s wdt:P150 ?adm1 .
  # Second-level: items listed as P150 of a first-level division
  ?adm1 wdt:P150 ?item .
  ?item wdt:P31  ?class .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
GROUP BY ?class ?classLabel
ORDER BY DESC(?n)
LIMIT 10
', country_qid)

  tryCatch({
    res <- sparql_query(q)
    if (nrow(res) == 0) {
      return(tibble(
        country = country_name,
        class = NA_character_,
        classLabel = NA_character_,
        n = NA_integer_
      ))
    }
    res |> mutate(
      country = country_name,
      class   = str_extract(class, "Q\\d+$"),
      n       = as.integer(n)
    ) |> select(country, class, classLabel, n)
  }, error = function(e) {
    message(country_name, ": ", e$message)
    tibble(country = country_name, class = NA_character_, classLabel = NA_character_, n = NA_integer_)
  })
}

sa_countries <- bind_rows(new_countries)

message("Querying via P150 (contains administrative territorial entity)...")
second_level_v2 <- purrr::map2_dfr(sa_countries$qid, sa_countries$name,
                                   get_second_level_classes_v2)

second_level_v2 |> print(n = 60)

