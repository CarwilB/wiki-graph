w_detention_facility_category_query <- pages_in_category("en", "wikipedia", categories = "Immigration_detention_centers_and_prisons_in_the_United_States")

# make a dataframe version
w_detention_facility_cat <- purrr::map_dfr(
  w_detention_facility_category_query$query$categorymembers, as_tibble)



##

w_detention_sites_tb %>%
  filter(!is.na(link)) %>%
  mutate(
    matches_cat = ((primary_name %in% w_detention_facility_cat$title) |
      (wiki_slug %in% w_detention_facility_cat$title)),
    wiki_page = str_glue("[{wiki_slug}]({link})")
    ) %>%
  select(primary_name, wiki_page, matches_cat ) %>%
  arrange(matches_cat, wiki_page) %>%
  kableExtra::kable()

w_detention_facility_cat %>%
  filter(title %in% facilities_data_current$facility_name)

facilities_data_current %>%
  filter(facility_name %in% w_detention_facility_cat$title)

# 1. Filter Wikipedia categories based on the first word of facilities_data_current
w_detention_facility_cat %>%
  filter(str_extract(title, "^\\w+") %in%
           str_extract(facilities_data_current$facility_name, "^\\w+"))

# 2. Filter current facility data based on the first word of the Wikipedia titles
facility_match_candidates <- facilities_data_current %>%
  filter(str_extract(facility_name, "^\\w+") %in%
           str_extract(w_detention_facility_cat$title, "^\\w+"))

# 1. Prepare the Wikipedia data with a matching key
w_cat_ready <- w_detention_facility_cat %>%
  mutate(first_word_key = str_extract(title, "^\\w+"))

# 2. Join the candidate list to the Wikipedia data
facility_match_joined <- facility_match_candidates %>%
  # Create the key on the fly for the left side
  mutate(first_word_key = str_extract(facility_name, "^\\w+")) %>%
  # Join by the new key
  left_join(w_cat_ready, by = "first_word_key",
            relationship = "many-to-many") %>%
  # Clean up the temporary key afterward
  select(-first_word_key)

facilities_data_merged$FY26 %>%
  filter(!is.na(wiki_match)) %>%
  pull(wiki_match) -> linked_from_fy26

facility_match_joined <- facility_match_joined %>%
  mutate(linked_fy26 = title %in% linked_from_fy26)

facility_match_joined %>%
  select(facility_name, title, linked_fy26) %>%
  filter(!is.na(title)) %>%
  arrange(facility_name, title) %>%
  mutate(row = row_number()) %>%
  relocate(row) %>%
  kableExtra::kable()

# by visual inspection…
correct_match_rows <- c(1, 3, 4, 6, 7, 8, 9, 10, 11, 14, 17, 18, 19, 23, 26, 29, 30)

facility_match_joined %>%
  select(facility_name, title, linked_fy26) %>%
  filter(!is.na(title)) %>%
  arrange(facility_name, title) %>%
  mutate(row = row_number()) %>%
  filter(row %in% correct_match_rows) %>%
  filter(!linked_fy26) %>% # not linked yet
  select(facility_name, title) -> match_table

match_table %>% nrow() # 10 new matches to link
dput(match_table)



facility_match_joined <- facility_match_joined %>%
  mutate(linked_fy26 = title %in% linked_from_fy26)
