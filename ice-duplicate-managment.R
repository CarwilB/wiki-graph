library(stringdist)

find_fuzzy_duplicates <- function(names_vector, method = "jw", threshold = 0.1) {
  # Jaro-Winkler distance (good for facility names)
  distances <- stringdistmatrix(names_vector, method = method)

  # Find pairs with similarity above threshold (lower distance = more similar)
  similar_pairs <- which(distances <= threshold & distances > 0, arr.ind = TRUE)

  if (nrow(similar_pairs) > 0) {
    tibble(
      name1 = names_vector[similar_pairs[,1]],
      name2 = names_vector[similar_pairs[,2]],
      similarity = 1 - distances[similar_pairs]
    ) %>%
      filter(name1 != name2) %>%
      arrange(desc(similarity))
  } else {
    tibble(name1 = character(0), name2 = character(0), similarity = numeric(0))
  }
}

# Usage
fuzzy_dupes <- find_fuzzy_duplicates(all_facility_names, threshold = 0.2)

find_location_duplicates <- function(facilities_data_list) {
  # Combine all tibbles with source information
  all_facilities <- map2_dfr(facilities_data_list, names(facilities_data_list) %||% seq_along(facilities_data_list),
                             ~ {
                               df <- .x
                               source_name <- .y

                               # Check if required columns exist
                               required_cols <- c("facility_name", "facility_city", "facility_state")
                               existing_cols <- required_cols[required_cols %in% names(df)]

                               if (length(existing_cols) >= 2) {  # Need at least city/state or name/city or name/state
                                 df %>%
                                   select(any_of(required_cols)) %>%
                                   mutate(
                                     source_tibble = source_name,
                                     # Clean up for comparison
                                     clean_city = str_to_upper(str_trim(facility_city %||% "")),
                                     clean_state = str_to_upper(str_trim(facility_state %||% "")),
                                     clean_name = str_to_upper(str_trim(facility_name %||% ""))
                                   ) %>%
                                   filter(!is.na(clean_city) | !is.na(clean_state))  # Must have location info
                               } else {
                                 tibble()  # Return empty if missing required columns
                               }
                             }
  )

  # Find facilities in same city/state with different names
  location_groups <- all_facilities %>%
    filter(!is.na(clean_city), !is.na(clean_state)) %>%  # Must have both city and state
    group_by(clean_city, clean_state) %>%
    summarise(
      unique_names = list(unique(clean_name[!is.na(clean_name)])),
      sources = list(unique(source_tibble)),
      original_names = list(unique(facility_name[!is.na(facility_name)])),
      .groups = "drop"
    ) %>%
    filter(lengths(unique_names) > 1) %>%  # Multiple names in same location
    arrange(clean_city, clean_state)

  # Format results nicely
  results <- location_groups %>%
    rowwise() %>%
    mutate(
      location = paste(clean_city, clean_state, sep = ", "),
      name_variants = paste(original_names, collapse = " | "),
      source_tibbles = paste(sources, collapse = ", "),
      num_variants = length(unique_names)
    ) %>%
    select(location, num_variants, name_variants, source_tibbles) %>%
    arrange(desc(num_variants))

  return(results)
}

# Usage
location_duplicates <- find_location_duplicates(facilities_data_list)
print(location_duplicates)

# View detailed results
location_duplicates %>%
  filter(num_variants > 2) %>%  # Focus on locations with many name variants
  print(n = Inf)

location_duplicates %>%
  filter(num_variants == 2) %>%  # Focus on locations with many name variants
  print(n = Inf)


presence_matrix_facilities %>%
  filter((num_lists_present == 8) & (FY26)) %>%
  pull(facility_name) -> ice_eight_years

presence_matrix_facilities %>%
  filter((num_lists_present == 1) & (FY26)) %>%
  pull(facility_name) -> ice_one_years

names(facilities_data_list) <- names(clean_names_list)
facilities_data_list$FY26 %>%
  filter(facility_name %in% ice_eight_years) %>%
  select(facility_name, facility_city, facility_state, sum_criminality_levels) %>%
  arrange(desc(sum_criminality_levels))

facilities_data_list$FY26 %>%
  filter(facility_name %in% ice_one_years) %>%
  select(facility_name, facility_city, facility_state, sum_criminality_levels) %>%
  pull(sum_criminality_levels) %>% sum()


