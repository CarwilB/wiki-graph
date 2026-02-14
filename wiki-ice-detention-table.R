library(httr)
library(rvest)
library(tidyverse)

# 1. Define URL and Fetch Page
url <- "https://en.wikipedia.org/w/index.php?title=List_of_immigrant_detention_sites_in_the_United_States&oldid=1334453072"
response <- GET(url)
page <- read_html(content(response, as = "text"))

# 2. Select the target table node
table_node <- html_element(page, "table.wikitable")

# 3. Extract the standard table text
detention_sites_tb <- html_table(table_node)

# 4. Extract links from the first column specifically
# We select all rows, then extract the 'href' from the 'a' tag in the first 'td'
rows <- html_elements(table_node, "tr")

# Note: We use map_chr to ensure we handle rows without links (like headers) correctly
links <- map_chr(rows, function(row) {
  # Look for the first data cell, then an anchor tag inside it
  link_node <- html_element(row, "td:first-child a")
  href <- html_attr(link_node, "href")

  if (is.na(href)) {
    return(NA_character_)
  } else {
    # Construct full URL
    return(paste0("https://en.wikipedia.org", href))
  }
})

# 5. Clean and Merge
# Remove the first element of links if it corresponds to the header row
if (length(links) > nrow(detention_sites_tb)) {
  links <- links[(length(links) - nrow(detention_sites_tb) + 1):length(links)]
}

detention_sites_tb <- detention_sites_tb %>%
  add_column(link = links, .after = 1) %>%
  as_tibble()

# Optional: Final cleanup of text and brackets
detention_sites_tb <- detention_sites_tb %>%
  mutate(across(where(is.character), ~ gsub("\\[\\d+\\]", "", .)))

print(detention_sites_tb)




