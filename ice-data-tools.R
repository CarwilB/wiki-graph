inspect_matching_columns <- function(tibble_list, pattern = "^inspections.*date") {
  # Function to get matching column types and content info from a single tibble
  get_matching_types <- function(df, df_name) {
    if (!is.data.frame(df)) {
      return(tibble(
        tibble_name = df_name,
        column_name = NA_character_,
        column_type = "Not a data frame",
        has_FY = NA,
        has_Scheduled = NA,
        sample_values = NA_character_
      ))
    }

    matching_cols <- names(df)[str_detect(names(df), pattern)]

    if (length(matching_cols) == 0) {
      return(tibble(
        tibble_name = df_name,
        column_name = "No matches",
        column_type = NA_character_,
        has_FY = NA,
        has_Scheduled = NA,
        sample_values = NA_character_
      ))
    }

    # Check each matching column for FY and Scheduled
    results <- map_dfr(matching_cols, ~ {
      col_data <- df[[.x]]
      col_data_char <- as.character(col_data)
      non_na_values <- col_data_char[!is.na(col_data_char)]

      tibble(
        tibble_name = df_name,
        column_name = .x,
        column_type = paste(class(col_data), collapse = ", "),
        has_FY = any(str_detect(non_na_values, "FY"), na.rm = TRUE),
        has_Scheduled = any(str_detect(non_na_values, "Scheduled"), na.rm = TRUE),
        sample_values = paste(head(non_na_values, 3), collapse = " | ")
      )
    })

    return(results)
  }

  # Apply to all tibbles in the list
  results <- map2_dfr(
    tibble_list,
    names(tibble_list) %||% paste0("tibble_", seq_along(tibble_list)),
    get_matching_types
  )

  return(results)
}

# Usage:
column_types <- inspect_matching_columns(facilities_data_list)
print(column_types)

# Filter to show only columns with FY or Scheduled:
column_types %>%
  filter(has_FY == TRUE | has_Scheduled == TRUE) %>%
  print(n = Inf)


#leftover data handling code
mutate(
  # 3. Handle the Mixed Date/Text Column
  #    First, extract the "Scheduled" text into a new column
  scheduled_inspection =if ("inspections_last_inspection_end_date" %in% names(.) &&
                            is.character(.data$inspections_last_inspection_end_date)) {
    case_when(
      !str_detect(inspections_last_inspection_end_date, "^[0-9]+$") ~ inspections_last_inspection_end_date,
      TRUE ~ NA_character_
    )
  },
  #    Then, convert the Excel serial numbers (e.g., "45321") to Date objects
  #    Non-numeric strings (like "Scheduled FY27") become NA here
  across(
    matches("^inspections.*date") & where(is.character),
    ~ case_when(
      str_detect(., "^[0-9]+$") ~
        as.Date(as.numeric(.), origin = "1899-12-30"),
      TRUE ~ as.Date(NA)
    )
  )

  ## --

  # Quick check for non-numeric values in inspections_guaranteed_minimum
  map_dfr(facilities_data_list, ~ {
    if ("inspections_guaranteed_minimum" %in% names(.x)) {
      col_values <- .x$inspections_guaranteed_minimum
      non_numeric <- col_values[is.na(suppressWarnings(as.numeric(col_values))) & !is.na(col_values)]

      if (length(non_numeric) > 0) {
        tibble(
          tibble_name = deparse(substitute(.x)),
          non_numeric_values = unique(non_numeric),
          count = map_int(unique(non_numeric), ~ sum(col_values == .x, na.rm = TRUE))
        )
      } else {
        tibble(
          tibble_name = deparse(substitute(.x)),
          non_numeric_values = "All values are numeric or NA",
          count = 0L
        )
      }
    } else {
      tibble(
        tibble_name = deparse(substitute(.x)),
        non_numeric_values = "Column not found",
        count = 0L
      )
    }
  }, .id = "list_index")
