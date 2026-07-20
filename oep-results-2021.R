# install.packages(c("pdftools", "stringr", "dplyr", "purrr", "tibble"))
library(pdftools)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

pdf_url <- "https://web.oep.org.bo/wp-content/uploads/2021/05/Separata-Resultados-EDRM-2021.pdf"

# Read PDF text page by page
pages <- pdftools::pdf_text(pdf_url)

# Split each page into lines and keep page/line metadata
lines_tbl <- map2_dfr(
  pages,
  seq_along(pages),
  \(txt, pg) {
    tibble(
      page = pg,
      line_no = seq_along(str_split(txt, "\n")[[1]]),
      text = str_split(txt, "\n")[[1]]
    )
  }
) %>%
  mutate(
    text = str_squish(text),
    row_id = row_number()
  ) %>%
  filter(text != "")

# Helper: safely get nearby line text
get_text <- function(i) {
  if (i < 1 || i > nrow(lines_tbl)) return(NA_character_)
  lines_tbl$text[i]
}

# Find all mayor title rows
mayor_title_idx <- which(
  lines_tbl$text %in% c("ALCALDE TITULAR", "ALCALDESA TITULAR",
                        "Alcalde Titular", "Alcaldesa Titular")
)

# Function to parse one mayor block
parse_mayor_block <- function(idx) {
  # Usually the next non-header line after title and optional "NOMBRE SIGLA"
  next_lines_idx <- seq(idx + 1, min(idx + 6, nrow(lines_tbl)))
  next_lines <- lines_tbl$text[next_lines_idx]

  # Drop common headers
  candidate_lines <- next_lines[!next_lines %in% c("NOMBRE SIGLA", "Nombre Sigla")]

  # Take first line that does not look like a section header/stat row
  mayor_line <- candidate_lines[
    !str_detect(candidate_lines, "^AUTORIDADES\\b") &
    !str_detect(candidate_lines, "^Alcalde\\b") &
    !str_detect(candidate_lines, "^Concejales\\b") &
    !str_detect(candidate_lines, "^N°\\b")
  ][1]

  # Look backward for nearest municipality line
  prev_idx <- seq(max(1, idx - 12), idx - 1)
  prev_lines <- lines_tbl$text[prev_idx]

  municipio_line <- rev(prev_lines)[str_detect(rev(prev_lines), "^MUNICIPIO:\\s*")][1]

  # If not found before, look a little after title too, because layout varies on some pages
  if (is.na(municipio_line) || length(municipio_line) == 0) {
    fwd_idx <- seq(idx + 1, min(idx + 12, nrow(lines_tbl)))
    fwd_lines <- lines_tbl$text[fwd_idx]
    municipio_line <- fwd_lines[str_detect(fwd_lines, "^MUNICIPIO:\\s*")][1]
  }

  # Parse municipality and province
  municipality <- str_match(
    municipio_line,
    "^MUNICIPIO:\\s*(.*?)\\s*\\(PROVINCIA\\s+(.*?)\\)$"
  )[, 2]

  province <- str_match(
    municipio_line,
    "^MUNICIPIO:\\s*(.*?)\\s*\\(PROVINCIA\\s+(.*?)\\)$"
  )[, 3]

  # Parse mayor name + party from line like:
  # "ENRIQUE LEAÑO PALENQUE MAS-IPSP"
  # use last token/group as party
  party <- str_match(mayor_line, "(.+?)\\s+([[:alnum:]./-]+)$")[, 3]
  mayor_name <- str_match(mayor_line, "(.+?)\\s+([[:alnum:]./-]+)$")[, 2]

  tibble(
    municipality = municipality,
    province = province,
    mayor_name = mayor_name,
    mayor_party = party,
    source_page = lines_tbl$page[idx],
    mayor_title = lines_tbl$text[idx]
  )
}

result <- map_dfr(mayor_title_idx, parse_mayor_block) %>%
  filter(!is.na(municipality), !is.na(mayor_name)) %>%
  distinct()

result
