
library(c2z)


wiki_refs_pipeline("Elizabeth_Lyon_(criminal)",
                   ris_file = "data/lyon_refs.ris",
                   zotero_import = TRUE,
                   user_id = "1531198",
                   api_key = Sys.getenv("zotero_access_key"),
                   dry_run = FALSE)

meio_refs <- wiki_refs_pipeline("Meiō_incident",
                   ris_file = "data/lyon_refs.ris",
                   zotero_import = TRUE,
                   user_id = "1531198",
                   enrich = TRUE,
                   api_key = Sys.getenv("zotero_access_key"),
                   dry_run = FALSE)

post_refs_to_zotero(
  meio_refs,
  collection_name = "Meiō incident",
  user_id = "1531198",
  api_key = Sys.getenv("zotero_access_key_write")
)




genetic_variation_refs <- wiki_refs_pipeline("Human_genetic_variation",
                                             ris_file = "data/lyon_refs.ris",
                                             zotero_import = TRUE,
                                             user_id = "1531198",
                                             enrich = TRUE,
                                             api_key = Sys.getenv("zotero_access_key"),
                                             dry_run = FALSE)

genetic_variation_refs_k <- fetch_zotero_keys(genetic_variation_refs,
                                              user_id = "1531198",
                                              api_key = Sys.getenv("zotero_access_key"),
                                              collection_key = "FVGQ3ENK")

fetch_zotero_keys <- function(refs,
                              user_id = NULL, api_key = NULL,
                              user = TRUE, collection_key = NULL)

post_refs_to_zotero(
  genetic_variation_refs,
  collection_name = "Human_genetic_variation",
  user_id = "1531198",
  api_key = Sys.getenv("zotero_access_key_write")
)

# o look up an existing collection's key by name, you'd fetch all collections and filter:
zotero <- Zotero()


library(httr2)

collections_raw <- request("https://api.zotero.org") |>
  req_url_path_append("users", "1531198", "collections") |>
  req_headers(
    `Zotero-API-Version` = "3",
    Authorization = paste("Bearer", Sys.getenv("zotero_access_key_write"))
  ) |>
  req_perform() |>
  resp_body_json(simplifyVector = TRUE)

# Extract key + name as a tidy tibble
collections <- tibble(
  key  = collections_raw$key,
  name = collections_raw$data$name
)

collections |>
  filter(name == "Human_genetic_variation") |>
  pull(key)
