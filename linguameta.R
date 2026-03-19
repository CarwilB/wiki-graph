# Linguameta is a dataset of languages and metadata about them, including their
# speakers

library(readr)
library(here)

linguameta_root_path <- "../url-nlp/linguameta"
linguameta_data_path <- "../url-nlp/linguameta/data"
linguameta_metadata <- read_tsv(file = file.path(linguameta_root_path, "linguameta.tsv"))

linguameta_metadata |>
  arrange(desc(estimated_number_of_speakers)) |>
  select(1, 13,3,5, 10, 11) |>
  print(n=100)
names(linguameta_metadata)


# This is a dataset from Kwet Yung Shim, reconstructing
# the largest 200 languages as catalogue in Ethnologue in 2024
# https://medium.com/@yung.shim618/most-spoken-languages-of-2024-nerding-out-over-the-ethnologue-200-901ab2141c47
# Also available:
# https://medium.com/@yung.shim618/most-spoken-languages-of-2025-nerding-out-over-the-ethnologue-200-689abb45424c


langs_df <- read_csv('data/data-Mww3K.csv')
langs_df


# SIL's Ethnologue provides a mapping among macrolanguages, which may be
# arenas of intercommunication across named languages.

library(readr)
library(dplyr)

# URL for the latest mapping (Check the SIL site for the current date version)
url <- "https://iso639-3.sil.org/sites/iso639-3/files/downloads/iso-639-3-macrolanguages.tab"
# also archived in "data/iso-639-3-macrolanguages.tab"

macrolanguages <- read_delim(url, delim = "\t")

# View members of the Quechua macrolanguage (relevant for your Bolivia research)
quechua_members <- macrolanguages %>%
  filter(M_Id == "que")

macrolanguage_ids <- unique(macrolanguages$M_Id)
macrolanguage_member_ids <- unique(macrolanguages$I_Id)

# What is the overlap between linguameta and the macrolanguages
intersect(macrolanguage_ids, unique(linguameta_metadata$bcp_47_code))
intersect(macrolanguage_member_ids, unique(linguameta_metadata$bcp_47_code))

# ============================================================================
# Merge with SIL Macrolanguage Reference Names
# ============================================================================
# See documentation/MACROLANGUAGES.md for detailed description of this merge
#
# This function creates a unified macrolanguages table by:
# 1. Extracting SIL reference names from ISO 639-3 website
# 2. Merging with linguameta metadata (speaker counts, endangerment, etc.)
# 3. Using SIL names as primary source, linguameta as fallback
# 4. Removing "(individual language)" suffix for consistency
# 5. Adding in_linguameta flag to indicate metadata availability
#
# Result: 459 rows (63 macrolanguages × constituent members) with full metadata

merge_with_sil_macrolanguages <- function() {
  library(rvest)
  library(stringr)

  # Fetch and parse SIL macrolanguage mappings page
  url <- "https://iso639-3.sil.org/code_tables/macrolanguage_mappings/read"
  page <- read_html(url)

  # Extract macrolanguage reference names from h4 headings
  # Format: "Akan [aka]" -> code = "aka", name = "Akan"
  macrolang_names <- page |>
    html_elements("h4.text-center a") |>
    html_text() |>
    tibble(full_text = _) |>
    mutate(
      macro_code = str_extract(full_text, "\\[[a-z]{3}\\]") |>
        str_remove_all("\\[|\\]"),
      macro_reference_name = str_trim(str_remove(full_text, "\\[[a-z]{3}\\]"))
    ) |>
    select(macro_code, macro_reference_name)

  # Extract individual member language names
  individual_rows <- page |> html_elements("tbody tr")
  sil_member_langs <- tibble()

  for (i in seq_along(individual_rows)) {
    row <- individual_rows[[i]]
    cells <- row |> html_elements("td")

    if (length(cells) >= 2) {
      codes <- cells |> html_text()
      if (length(codes) >= 2) {
        code <- codes[1] |> str_trim()
        name <- codes[2] |> str_trim()

        # Only add if code looks like a language code (3 chars) and not a header
        if (nchar(code) == 3 & !grepl("Identifier", code)) {
          sil_member_langs <- bind_rows(
            sil_member_langs,
            tibble(member_code = code, member_reference_name_sil = name)
          )
        }
      }
    }
  }

  # Clean SIL names: remove "(individual language)" suffix
  sil_member_langs_clean <- sil_member_langs |>
    mutate(
      member_reference_name_sil = str_remove(
        member_reference_name_sil,
        " \\(individual language\\)$"
      )
    )

  # Create the merged table
  macrolanguages_final <- macrolanguages |>
    # Add SIL macro reference names
    left_join(macrolang_names, by = c("M_Id" = "macro_code")) |>
    # Add full linguameta metadata
    left_join(
      linguameta_metadata,
      by = c("I_Id" = "bcp_47_code"),
      relationship = "many-to-one"
    ) |>
    # Add clean SIL member reference names
    left_join(
      sil_member_langs_clean,
      by = c("I_Id" = "member_code"),
      relationship = "many-to-one"
    ) |>
    # Use SIL names as primary, linguameta as fallback
    mutate(
      english_name_final = coalesce(member_reference_name_sil, english_name),
      in_linguameta = !is.na(english_name)
    ) |>
    # Select and order columns
    select(
      macro_code = M_Id,
      macro_name = macro_reference_name,
      member_code = I_Id,
      member_status = I_Status,
      english_name = english_name_final,
      endonym,
      iso_639_3_code,
      iso_639_2b_code,
      glottocode,
      wikidata_id,
      wikidata_description,
      estimated_number_of_speakers,
      endangerment_status,
      writing_systems,
      locales,
      cldr_official_status,
      in_linguameta
    ) |>
    rename(
      n_speakers = estimated_number_of_speakers,
      endangerment = endangerment_status
    ) |>
    arrange(macro_code, member_code)

  return(macrolanguages_final)
}

# Run the merge (optional - comment out or set to FALSE to skip)
if (FALSE) {
  macrolanguages_final <- merge_with_sil_macrolanguages()

  # Export results to data/ subfolder
  saveRDS(macrolanguages_final, here::here("data", "macrolanguages_final.rds"))
  write.csv(macrolanguages_final, here::here("data", "macrolanguages_final.csv"), row.names = FALSE)

  cat("Merged macrolanguages table created:\n")
  cat("  Rows:", nrow(macrolanguages_final), "\n")
  cat("  Columns:", ncol(macrolanguages_final), "\n")
  cat("  Coverage:", round(100 * sum(macrolanguages_final$in_linguameta) /
                           nrow(macrolanguages_final), 1), "% in linguameta\n")
}

