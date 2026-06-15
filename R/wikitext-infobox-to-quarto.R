library(stringr)
library(purrr)
library(dplyr)
library(htmltools)

#' Parse Wikitext Infobox into a Quarto-compatible HTML table
#' @param wikitext A single string containing the raw Wikitext of an infobox
#' @return An htmltools object representing the infobox
parse_wiki_infobox <- function(wikitext) {
  
  # 1. Clean and split the wikitext by the pipe delimiter that denotes a new row
  #    Using a regex that looks for a newline followed by optional space and a pipe
  lines <- stringr::str_split(wikitext, "\\n\\s*\\|")[[1]]
  
  # 2. Extract the title (looks for 'name = ' or 'title = ')
  title_match <- stringr::str_match(wikitext, "(?i)\\|\\s*(name|title)\\s*=\\s*(.*?)\\n")
  infobox_title <- if (!is.na(title_match[1,3])) {
    stringr::str_trim(title_match[1,3])
  } else {
    "Event Summary"
  }
  
  # 3. Parse key-value pairs into a tibble
  kv_lines <- lines[stringr::str_detect(lines, "=")]
  
  parsed_data <- purrr::map_dfr(kv_lines, function(line) {
    parts <- stringr::str_split_fixed(line, "=", 2)
    key <- stringr::str_trim(parts[1])
    val_raw <- stringr::str_trim(parts[2])
    
    # 4. Clean Wikitext syntax from the values
    # Converts [[Link|Display Text]] or [[Display Text]] into just "Display Text"
    val_clean <- stringr::str_replace_all(val_raw, "\\[\\[(?:[^|\\]]*\\|)?([^\\]]+)\\]\\]", "\\1")
    
    # Strip lingering template braces (like {{cite web|...}}) for this static version
    val_clean <- stringr::str_replace_all(val_clean, "\\{\\{.*?\\}\\}", "")
    
    tibble::tibble(key = key, value = val_clean)
  }) |> 
    dplyr::filter(value != "", key != "name", key != "title") # Drop empty fields and title
  
  # 5. Map internal wiki keys to nice display labels (expand this dictionary as needed)
  label_map <- c(
    "location" = "Location",
    "date" = "Date",
    "target" = "Target",
    "type" = "Attack type",
    "deaths" = "Deaths",
    "perps" = "Perpetrators",
    "perpetrators" = "Perpetrators"
  )
  
  # 6. Build the HTML rows using htmltools
  rows <- purrr::map2(parsed_data$key, parsed_data$value, function(k, v) {
    display_label <- if (k %in% names(label_map)) label_map[[k]] else stringr::str_to_title(k)
    
    htmltools::tags$tr(
      htmltools::tags$th(scope = "row", display_label),
      htmltools::tags$td(v)
    )
  })
  
  # 7. Construct the final table structure
  htmltools::tags$table(class = "infobox",
    htmltools::tags$tbody(
      htmltools::tags$tr(
        htmltools::tags$th(colspan = "2", class = "infobox-title", infobox_title)
      ),
      rows
    )
  )
}