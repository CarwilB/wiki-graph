library(httr)
library(rvest)
library(dplyr)
library(janitor)

# 1. Define URL
url <- "https://www.congress.gov/crs_external_products/RS/HTML/RS20844.web.html"
# manually saved to "data/RS20844.web.html" to bypass Cloudflare protection

library(rvest)
library(dplyr)
library(stringr)
library(janitor)

# 1. Read the local file
file_path <- "data/RS20844.web.html"
page_html <- read_html(file_path)

# 2. Extract the table containing "Afghanistan"
# This XPath finds the table that has 'Afghanistan' in any paragraph within a cell
tps_table <- page_html %>%
  html_element(xpath = "//table[descendant::p[contains(text(), 'Afghanistan')]]") %>%
  html_table(header = TRUE) %>%
  clean_names() %>%
  rename_with(~ str_sub(., end = -2), 3:5) %>% # remove final note character from variable name
  as_tibble()

# 3. Clean the 'Approved Individuals' column
# It likely contains commas and footnotes (e.g., "8,105 a")
crs_tps_clean <- tps_table %>%
  filter(!is.na(country), country != "Total") %>%
  mutate(
    # Remove footnotes like [a] or superscripts and commas
    approved_individuals = str_remove_all(approved_individuals, "[a-zA-Z]"),
    approved_individuals = as.numeric(str_remove_all(approved_individuals, ",")),

    # Clean footnote letters from date columns
    required_arrival_date  = str_remove(required_arrival_date , "\\s*[a-z]$"),
    expiration_date = str_remove(expiration_date, "\\s*[a-z]$"),

    required_arrival_date = as.Date(required_arrival_date, format = "%B %d, %Y"),
    expiration_date = as.Date(expiration_date, format = "%B %d, %Y")
  )  %>%
  mutate(country = if_else(country=="Burma",
                               "Burma (Myanmar)", country))

print(crs_tps_clean)

crs_tps_clean %>% select(country, required_arrival_date, approved_individuals)

source("print-wikitable.R")

crs_wiki_column_names <- c("Country", "Required Arrival Date", "Approved Individuals")
print_wikitable(crs_tps_clean %>% select(country, required_arrival_date, approved_individuals),
                caption = "People with Temporary Protected Status (TPS) as of March 31, 2026",
                column_names = crs_wiki_column_names)

library(rvest)
library(dplyr)
library(janitor)
library(stringr)

# 1. Read the local HTML file
file_path <- "data/justice-gov-eoir-temporary-protected-status.html"
page_html <- read_html(file_path)

table_node <- page_html %>%
  html_element(xpath = "//table[descendant::td[contains(text(), 'Afghanistan')]]")

# 3. Create the base tibble
doj_tps <- table_node %>%
  html_table(header = TRUE) %>%
  janitor::clean_names() %>%
  as_tibble()

links <- table_node %>%
  html_nodes("tr") %>%         # Get all rows
  magrittr::extract(-1) %>%    # Remove the header row
  html_node("td:nth-child(2) a") %>% # Target the 'a' tag in the 2nd column
  html_attr("href")            # Get the URL

doj_tps_clean <- doj_tps %>%
  mutate(link = links) %>%
  mutate(date = as.Date(date, format = "%B %d, %Y")) %>% # Convert date column to Date type
  mutate(under_presidency = case_when(
    date >= "2025-01-20" ~ "Trump",
    date >= "2021-01-20" ~ "Biden",
    date >= "2017-01-20" ~ "Trump",
    date >= "2009-01-20" ~ "Obama",
    date >= "2001-01-20" ~ "Bush",
  ))

# 4. Data Cleaning
# Trimming whitespace and removing common artifacts from gov table exports
doj_tps_clean <- doj_tps_clean %>%
  mutate(across(where(is.character), str_trim)) %>%
  # Filter out total/summary rows if they exist
  filter(!str_detect(str_to_lower(country), "total")) %>%
  rename(last_change_date = date) %>% # Rename 'date' to 'last_change_date' for clarity
  mutate(country = if_else((str_detect(title, "October 3, 2023") &
                              str_detect(country, "Venezuela")),
                           "Venezuela (2023)", country))


# View the results
print(doj_tps_clean)

tps_status <- left_join(crs_tps_clean, doj_tps_clean, by = "country")

