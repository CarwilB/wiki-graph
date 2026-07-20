library(tidycensus)
library(dplyr)
library(stringr)
library(purrr)

#' Import and Label 2020 Census P1 Data
#' @param geography_level The scale of data (e.g., "state", "county", "tract", "place", "city")
#' @param state_abbr Two-letter postal abbreviation (e.g., "AL", "TN")
import_labeled_census_p1 <- function(geography_level, state_abbr) {
  
  # 1. Fetch 2020 PL 94-171 Data
  raw_census_data <- get_decennial(
    geography = geography_level,
    state = state_abbr,
    table = "P1",
    year = 2020,
    sumfile = "pl",
    cache = FALSE
  )
  
  # 2. Extract variable labels for Table P1
  table_p1_meta <- load_variables(2020, "pl", cache = TRUE) %>% 
    filter(str_sub(name, 1, 2) == "P1") %>%
    select(name, label) %>%
    rename(
      ref_name = name,
      description = label
    )
  
  # 3. Join metadata labels to the dataset and add state column
  labeled_data <- raw_census_data %>%
    left_join(table_p1_meta, by = c("variable" = "ref_name")) %>%
    mutate(state = state_abbr)
  
  # 4. Handle geography-specific parsing (Place/City)
  # We want to break down the NAME column for places/cities
  if (geography_level %in% c("place", "city")) {
    labeled_data <- labeled_data %>%
      mutate(
        # Extract the main part before the comma for further parsing
        main_name = str_remove(NAME, ",.*"),
        # Identify type (city, town, CDP)
        type = str_extract(main_name, "\\s(city|town|CDP)$") %>% str_trim(),
        # Identify place name (remove type from main_name)
        place = str_trim(str_remove(main_name, "\\s(city|town|CDP)$")),
        # Create the informative NAME: "Place, Type, State"
        NAME = case_when(
          !is.na(type) ~ paste0(place, ", ", type, ", ", state),
          TRUE ~ NAME
        )
      ) %>%
      select(-main_name)
  }
  
  # 5. Construct dynamic filename
  # Format: "data/al_county_census_2020_labeled.rds"
  output_file <- paste0(
    "data/", 
    tolower(state_abbr), "_", 
    geography_level, "_", 
    "census_2020_labeled.rds"
  )
  
  # 6. Save the RDS and return the data frame
  saveRDS(labeled_data, output_file)
  message(paste("Successfully saved to:", output_file))
  
  return(labeled_data)
}

#' Batch Import Census Data by Geography and State
#' @param geography_level The geographic scale ("county", "place", "tract", etc.)
#' @param target_states Character vector of state abbreviations
#' @param output_filename Path where the result list should be saved
#' @return Named list of tibbles, keyed by state abbreviation
import_census_data_by_state <- function(geography_level, target_states, output_filename) {
  
  result <- list()
  failed_states <- character()
  
  # First pass: attempt all states
  message(paste("Starting first pass on", length(target_states), "states for geography:", geography_level))
  for (state in target_states) {
    attempt <- try(
      {
        message(paste("Processing:", state))
        result[[state]] <- import_labeled_census_p1(
          geography_level = geography_level,
          state_abbr = state
        )
      },
      silent = TRUE
    )
    
    # Track states that failed
    if (inherits(attempt, "try-error")) {
      failed_states <- c(failed_states, state)
      message(paste("  FAILED:", state))
    }
  }
  
  # Second pass: retry any failed states
  if (length(failed_states) > 0) {
    message(paste("\nRetrying", length(failed_states), "failed state(s)..."))
    for (state in failed_states) {
      attempt <- try(
        {
          message(paste("Retrying:", state))
          result[[state]] <- import_labeled_census_p1(
            geography_level = geography_level,
            state_abbr = state
          )
        },
        silent = TRUE
      )
      
      if (!inherits(attempt, "try-error")) {
        failed_states <- setdiff(failed_states, state)
      }
    }
  }
  
  # Report final status
  if (length(failed_states) > 0) {
    message(paste("\nWarning: The following states could not be processed:", 
                  paste(failed_states, collapse = ", ")))
  } else {
    message("\nAll states processed successfully!")
  }
  
  # Save the result list
  saveRDS(result, output_filename)
  message(paste("Saved result list to:", output_filename))
  
  return(result)
}

# Example usage:
# tn_county_data <- import_labeled_census_p1("county", "TN")
# tn_place_data <- import_labeled_census_p1("place", "TN")

# Define the target states
target_states <- state.abb

# Import county-level race data for all states
county_race_data <- import_census_data_by_state(
  geography_level = "county",
  target_states = target_states,
  output_filename = "data/county-race-data-list.rds"
)

# Import place-level race data for all states
place_race_data <- import_census_data_by_state(
  geography_level = "place",
  target_states = target_states,
  output_filename = "data/place-race-data-list.rds"
)
