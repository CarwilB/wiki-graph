library(here)
library(readr)

provinces_table <- read_csv(here::here("data","provinces-table-cleaned.csv"))
provinces_canton_table <- provinces_table %>%
  rename(
    department = Departamento,
    province   = Provincia,
    capital    = Capital,
    municipality = Municipio,
    canton     = Cantón
  ) %>%
  separate_rows(canton, sep = ",\\s*")

canton_wikitext <- function(municipality, department, data = provinces_canton_table) {
  cantons <- data |>
    dplyr::filter(municipality == !!municipality, department == !!department) |>
    dplyr::pull(canton)

  if (length(cantons) == 0) {
    stop("No cantons found for municipality '", municipality, "' in department '", department, "'.")
  }

  n <- length(cantons)
  count_word <- c(
    "one", "two", "three", "four", "five", "six", "seven", "eight",
    "nine", "ten", "eleven", "twelve"
  )
  n_str <- if (n <= 12) count_word[n] else as.character(n)
  canton_noun <- if (n == 1) "canton" else "cantons"

  if (n == 1) {
    return(paste0(
      "The municipality is divided into one canton: ", cantons, " Canton."
    ))
  }

  items <- paste0("* ", cantons, " Canton", collapse = "\n")

  paste0(
    "The municipality is divided into ", n_str, " ", canton_noun, ". They are:\n\n",
    items
  )
}

