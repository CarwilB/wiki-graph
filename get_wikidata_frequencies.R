my_qids <- wp_only$wikidata_qid

my_wikidata_df <- get_listed_wikidata_items(
  qid_list       = my_qids,
  property       = c("P31", "P131"),
  property_names = c("instance_of", "located_in"),
  languages      = c("en", "am", "om", "so", "ti", "aa")
)

# 3. View the resulting tibble
print(my_wikidata_df)

# Make sure your libraries are loaded
library(tidyverse)
library(WikidataR)
library(tidywikidatar)


#' Convert a list of Wikidata QIDs into a frequency tibble with labels
#'
#' @param qid_list A list or vector of Wikidata QIDs (e.g., Q12345)
#' @return A tibble with item, frequency, and item_name
get_wikidata_frequencies <- function(qid_list) {

  # 1. Unlist the input and generate the frequency table
  my_table <- qid_list |>
    unlist() |>
    table()

  # 2. Convert to a clean tibble
  freq_tibble <- tibble(
    item = names(my_table),
    frequency = as.integer(my_table)
  )

  # Safety check: If the input was empty, return an empty tibble immediately
  if (nrow(freq_tibble) == 0) {
    return(tibble(item = character(), frequency = integer(), item_name = character()))
  }

  # 3. Fetch labels using tidywikidatar
  # tw_get_label is vectorized and directly returns a character vector of labels
  final_tibble <- freq_tibble |>
    mutate(
      item_name = tw_get_label(id = item, language = "en")
    ) |>
    select(item, frequency, item_name) |>
    arrange(desc(frequency))

  return(final_tibble)
}

get_wikidata_frequencies(my_wikidata_df$instance_of...14)
