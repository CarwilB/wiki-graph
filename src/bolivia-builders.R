# bolivia-builders.R
# Bolivia-specific wikitext and HTML table builders for municipal data
# (councils, languages, ethnic identification)
#
# Dependencies: dplyr, stringr, tibble, knitr, htmltools

library(dplyr)
library(stringr)
library(tibble)
library(knitr)
library(htmltools)

# ---- Bolivia municipal council wikitable and HTML preview ----------------------

# Language label sets used by both the wikitable and kable builders.
.council_labels <- list(
  es = list(
    seat         = "N.\u00b0",
    type         = "Tipo",
    name         = "Nombre",
    party        = "Partido / Organizaci\u00f3n Pol\u00edtica",
    member       = "Titular",
    alt          = "Suplente",
    pending      = "Por definir",
    source_label = "Fuente"
  ),
  en = list(
    seat         = "Seat",
    type         = "Type",
    name         = "Name",
    party        = "Party / Political Organization",
    member       = "Member",
    alt          = "Alternate",
    pending      = "TBD",
    source_label = "Source"
  )
)

# Internal: build council wikitable for a given language
.build_council_wikitable <- function(id_muni_code, data, caption, source,
                                     source_refs, lang) {
  lb <- .council_labels[[lang]]

  df <- data |>
    filter(id_muni == id_muni_code) |>
    arrange(silla, if_else(tipo == "TITULAR", 1L, 2L))

  if (nrow(df) == 0) return("")

  nombre_cell <- function(row) {
    if (isTRUE(row$pendiente) || is.na(row$nombre) || row$nombre == "") {
      lb$pending
    } else {
      str_to_title(row$nombre)
    }
  }

  partido_cell <- function(row) {
    if (isTRUE(row$esp_ioc) && !is.na(row$pueblo) && row$pueblo != "") {
      str_to_title(row$pueblo)
    } else if (!is.na(row$sigla) && row$sigla != "") {
      row$sigla
    } else {
      ""
    }
  }

  lines <- '{| class="wikitable"'
  if (!is.null(caption)) lines <- c(lines, paste0("|+ ", caption))
  lines <- c(lines, sprintf("! %s !! %s !! %s !! %s",
                             lb$seat, lb$type, lb$name, lb$party))

  for (s in unique(df$silla)) {
    seat <- df[df$silla == s, ]
    n    <- nrow(seat)

    same_party <- n == 2 && {
      p1 <- partido_cell(seat[1, ]); p2 <- partido_cell(seat[2, ])
      p1 != "" && identical(p1, p2)
    }

    for (i in seq_len(n)) {
      row  <- seat[i, ]
      tipo <- if (row$tipo == "TITULAR") lb$member else lb$alt
      nom  <- nombre_cell(row)
      if (row$tipo == "SUPLENTE") nom <- paste0("''", nom, "''")
      part <- partido_cell(row)

      lines <- c(lines, "|-")

      if (n == 2 && i == 1) {
        if (same_party) {
          lines <- c(lines, sprintf('| rowspan="2" | %d || %s || %s || rowspan="2" | %s',
                                     s, tipo, nom, part))
        } else {
          lines <- c(lines, sprintf('| rowspan="2" | %d || %s || %s || %s',
                                     s, tipo, nom, part))
        }
      } else if (n == 2 && i == 2) {
        if (same_party) {
          lines <- c(lines, sprintf("| %s || %s", tipo, nom))
        } else {
          lines <- c(lines, sprintf("| %s || %s || %s", tipo, nom, part))
        }
      } else {
        lines <- c(lines, sprintf("| %d || %s || %s || %s", s, tipo, nom, part))
      }
    }
  }

  # Source row — mirrors get_wikitable() behaviour
  if (!is.null(source)) {
    source_text <- paste0("'''", lb$source_label, ":''' ", source)
    if (!is.null(source_refs)) {
      source_text <- paste0(source_text, "<ref>", source_refs, "</ref>")
    }
    lines <- c(lines, "|-", paste0('|colspan="4"|', source_text))
  }

  lines <- c(lines, "|}")
  paste(lines, collapse = "\n")
}

# Internal: build council kable for a given language
.build_council_kable <- function(id_muni_code, data, lang) {
  lb <- .council_labels[[lang]]

  df <- data |>
    filter(id_muni == id_muni_code) |>
    arrange(silla, if_else(tipo == "TITULAR", 1L, 2L)) |>
    mutate(
      .name = case_when(
        isTRUE(pendiente) | is.na(nombre) | nombre == "" ~
          paste0("<em>", lb$pending, "</em>"),
        tipo == "SUPLENTE" ~ paste0("<em>", str_to_title(nombre), "</em>"),
        TRUE ~ str_to_title(nombre)
      ),
      .party = case_when(
        isTRUE(esp_ioc) & !is.na(pueblo) & pueblo != "" ~ str_to_title(pueblo),
        !is.na(sigla) & sigla != "" ~ sigla,
        TRUE ~ ""
      ),
      .type = if_else(tipo == "TITULAR", lb$member, lb$alt)
    )

  # Build column-name-safe data frame for kable
  out <- data.frame(
    seat  = df$silla,
    type  = df$.type,
    name  = df$.name,
    party = df$.party,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(out) <- c(lb$seat, lb$type, lb$name, lb$party)

  HTML(
    kable(out, format = "html", escape = FALSE,
          table.attr = 'class="table table-sm table-striped" style="font-size:11px;width:100%;"')
  )
}

#' Build Spanish MediaWiki council table
#'
#' @param id_muni_code Six-digit municipal code
#' @param data Council membership data frame with columns: id_muni, silla, tipo, nombre, sigla, pueblo, pendiente, esp_ioc
#' @param caption Optional table caption
#' @param source Optional source text
#' @param source_refs Optional reference tag content
#' @return MediaWiki wikitable string
build_council_wikitable_es <- function(id_muni_code, data = muni_concejo_comb,
                                       caption = NULL, source = NULL,
                                       source_refs = NULL) {
  .build_council_wikitable(id_muni_code, data, caption, source, source_refs,
                            lang = "es")
}

#' Build English MediaWiki council table
#'
#' @inheritParams build_council_wikitable_es
#' @return MediaWiki wikitable string
build_council_wikitable_en <- function(id_muni_code, data = muni_concejo_comb,
                                       caption = NULL, source = NULL,
                                       source_refs = NULL) {
  .build_council_wikitable(id_muni_code, data, caption, source, source_refs,
                            lang = "en")
}

#' Build Spanish HTML kable council table preview
#'
#' @param id_muni_code Six-digit municipal code
#' @param data Council membership data frame
#' @return HTML kable
build_council_kable_es <- function(id_muni_code, data = muni_concejo_comb) {
  .build_council_kable(id_muni_code, data, lang = "es")
}

#' Build English HTML kable council table preview
#'
#' @param id_muni_code Six-digit municipal code
#' @param data Council membership data frame
#' @return HTML kable
build_council_kable_en <- function(id_muni_code, data = muni_concejo_comb) {
  .build_council_kable(id_muni_code, data, lang = "en")
}

# Backward-compatible aliases
build_council_wikitable <- build_council_wikitable_es
build_council_kable     <- build_council_kable_en

# ---- Bolivia demographic tables (language use & ethnic identification) --------

# Internal helpers
.fmt_n   <- function(x) format(round(x), big.mark = ",", scientific = FALSE)
.fmt_pct <- function(x) sprintf("%.1f%%", x * 100)

# Translate an ethnic group column name to a display label.
# "Sin especificar" (detected as a substring) → "Unspecified Indigenous";
# any text that follows it in the string is ignored.
# All other names have trailing parenthetical footnote markers stripped.
.translate_ethnic_group <- function(g) {
  ifelse(grepl("Sin especificar", g, fixed = TRUE),
         "Unspecified Indigenous",
         trimws(sub("\\s*\\(.*", "", g)))
}

.clean_lang_name <- function(x) {
  x |>
    str_remove("_(2024|2012)$") |>
    str_replace_all("_", " ") |>
    str_to_title() |>
    str_replace("^Castellano$", "Spanish") |>
    str_replace("^Otras Declaraciones$", "Other")
}

# Internal: append optional source row spanning ncols columns
.append_source_row <- function(lines, ncols, source, source_refs, source_label) {
  if (!is.null(source)) {
    src_text <- paste0("'''", source_label, ":''' ", source)
    if (!is.null(source_refs))
      src_text <- paste0(src_text, "<ref>", source_refs, "</ref>")
    lines <- c(lines, "|-", paste0('|colspan="', ncols, '"|', src_text))
  }
  lines
}

#' Build a language-use wikitable for a municipality (English)
#'
#' Shows each indigenous/national language spoken by ≥ 1% of the population
#' in 2024 or 2012, with counts and percentages for both censuses.
#' Denominator: total resident population (not unique speakers).
#'
#' @param id_muni     Six-digit id_muni / ine_code string
#' @param lang_data   Data frame with language spoken counts by municipality
#' @param pop_data    Data frame with columns id_muni, pop_2024, pop_2012
#' @param caption     Optional wikitable caption
#' @param source,source_refs  Optional source row
#'
#' @return MediaWiki wikitable string
build_language_wikitable_en <- function(id_muni, lang_data, pop_data,
                                         caption = "Languages spoken",
                                         source = NULL, source_refs = NULL) {
  row <- lang_data |> filter(ine_code == id_muni,
                              nivel == "Municipio/TIOC") |>
         slice(1)
  if (nrow(row) == 0) return("")
  pop_row  <- pop_data |> filter(id_muni == .env$id_muni) |> slice(1)
  if (nrow(pop_row) == 0) return("")
  pop_2024 <- pop_row$pop_2024
  pop_2012 <- pop_row$pop_2012

  # Native + national language columns only (exclude _ext_ foreign languages)
  cols_2024 <- names(lang_data) |>
    str_subset("_2024$") |>
    str_subset("_ext_", negate = TRUE)
  cols_2012 <- str_replace(cols_2024, "_2024$", "_2012")
  # Keep only pairs that exist in 2012 as well
  valid     <- cols_2012 %in% names(lang_data)
  cols_2024 <- cols_2024[valid]; cols_2012 <- cols_2012[valid]

  langs <- tibble(
    language = .clean_lang_name(cols_2024),
    n_2024   = sapply(cols_2024, function(col) as.double(row[[col]])),
    n_2012   = sapply(cols_2012, function(col) as.double(row[[col]])),
    pct_2024 = n_2024 / pop_2024,
    pct_2012 = n_2012 / pop_2012
  ) |>
    filter(pct_2024 >= 0.01 | pct_2012 >= 0.01) |>
    arrange(desc(n_2024))

  if (nrow(langs) == 0) return("")

  lines <- c('{| class="wikitable"')
  if (!is.null(caption)) lines <- c(lines, paste0("|+ ", caption))
  lines <- c(lines,
    "! Language !! 2024 speakers !! 2024 % !! 2012 speakers !! 2012 %")

  for (i in seq_len(nrow(langs))) {
    r <- langs[i, ]
    lines <- c(lines, "|-",
               sprintf("| %s || %s || %s || %s || %s",
                       r$language,
                       .fmt_n(r$n_2024), .fmt_pct(r$pct_2024),
                       .fmt_n(r$n_2012), .fmt_pct(r$pct_2012)))
  }

  lines <- .append_source_row(lines, 5L, source, source_refs, "Source")
  lines <- c(lines, "|}")
  paste(lines, collapse = "\n")
}

#' Build an ethnic-identification wikitable for a municipality (English, 2024 only)
#'
#' Shows each group self-identified by ≥ 1% of the total population.
#' Denominator: total resident population.
#'
#' @param id_muni    Six-digit id_muni / ine_code string
#' @param auto_data  Data frame with ethnic self-identification counts
#' @param pop_data   Data frame with columns id_muni, pop_2024
#' @param caption    Optional wikitable caption
#' @param source,source_refs  Optional source row
#'
#' @return MediaWiki wikitable string
build_autoident_wikitable_en <- function(id_muni, auto_data, pop_data,
                                          caption = "Ethnic identification (2024)",
                                          source = NULL, source_refs = NULL) {
  row <- auto_data |> filter(ine_code == id_muni,
                              nivel == "Municipio/TIOC") |>
         slice(1)
  if (nrow(row) == 0) return("")
  pop_row  <- pop_data |> filter(id_muni == .env$id_muni) |> slice(1)
  if (nrow(pop_row) == 0) return("")
  pop_2024 <- pop_row$pop_2024

  meta_cols <- c("ine_code", "municipio", "provincia", "departamento",
                 "area", "nivel", "total",
                 "municipality", "province", "department", "level")

  grp_cols <- names(row)[!names(row) %in% meta_cols]
  groups <- tibble(
    group = grp_cols,
    n     = sapply(grp_cols, function(col) as.double(row[[col]]))
  ) |>
    mutate(pct = n / pop_2024) |>
    filter(pct >= 0.01) |>
    arrange(desc(n))

  if (nrow(groups) == 0) return("")

  lines <- c('{| class="wikitable"')
  if (!is.null(caption)) lines <- c(lines, paste0("|+ ", caption))
  lines <- c(lines, "! Group !! Population !! %")

  for (i in seq_len(nrow(groups))) {
    r <- groups[i, ]
    lines <- c(lines, "|-",
               sprintf("| %s || %s || %s",
                       .translate_ethnic_group(r$group), .fmt_n(r$n), .fmt_pct(r$pct)))
  }

  lines <- .append_source_row(lines, 3L, source, source_refs, "Source")
  lines <- c(lines, "|}")
  paste(lines, collapse = "\n")
}

#' HTML kable preview of language use
#'
#' @param id_muni Six-digit id_muni / ine_code string
#' @param lang_data Data frame with language spoken counts
#' @param pop_data Data frame with population columns
#'
#' @return HTML kable for display
build_language_kable_en <- function(id_muni, lang_data, pop_data) {
  row <- lang_data |> filter(ine_code == id_muni,
                              nivel == "Municipio/TIOC") |>
         slice(1)
  if (nrow(row) == 0) return(HTML(""))
  pop_row  <- pop_data |> filter(id_muni == .env$id_muni) |> slice(1)
  if (nrow(pop_row) == 0) return(HTML(""))
  pop_2024 <- pop_row$pop_2024; pop_2012 <- pop_row$pop_2012

  cols_2024 <- names(lang_data) |>
    str_subset("_2024$") |>
    str_subset("_ext_", negate = TRUE)
  cols_2012 <- str_replace(cols_2024, "_2024$", "_2012")
  valid     <- cols_2012 %in% names(lang_data)
  cols_2024 <- cols_2024[valid]; cols_2012 <- cols_2012[valid]

  n24 <- sapply(cols_2024, function(col) as.double(row[[col]]))
  n12 <- sapply(cols_2012, function(col) as.double(row[[col]]))

  df <- tibble(
    Language        = .clean_lang_name(cols_2024),
    `2024 speakers` = n24,
    `2024 %`        = sprintf("%.1f%%", n24 / pop_2024 * 100),
    `2012 speakers` = n12,
    `2012 %`        = sprintf("%.1f%%", n12 / pop_2012 * 100)
  ) |>
    filter(as.numeric(`2024 speakers`) / pop_2024 >= 0.01 |
           as.numeric(`2012 speakers`) / pop_2012 >= 0.01) |>
    arrange(desc(`2024 speakers`)) |>
    mutate(`2024 speakers` = .fmt_n(`2024 speakers`),
           `2012 speakers` = .fmt_n(`2012 speakers`))

  HTML(
    kable(df, format = "html", escape = TRUE,
          table.attr = 'class="table table-sm table-striped" style="font-size:11px;width:100%;"')
  )
}

#' HTML kable preview of ethnic identification
#'
#' @param id_muni Six-digit id_muni / ine_code string
#' @param auto_data Data frame with ethnic self-identification counts
#' @param pop_data Data frame with population columns
#'
#' @return HTML kable for display
build_autoident_kable_en <- function(id_muni, auto_data, pop_data) {
  row <- auto_data |> filter(ine_code == id_muni,
                              nivel == "Municipio/TIOC") |>
         slice(1)
  if (nrow(row) == 0) return(HTML(""))
  pop_row  <- pop_data |> filter(id_muni == .env$id_muni) |> slice(1)
  if (nrow(pop_row) == 0) return(HTML(""))
  pop_2024 <- pop_row$pop_2024

  meta_cols <- c("ine_code", "municipio", "provincia", "departamento",
                 "area", "nivel", "total",
                 "municipality", "province", "department", "level")

  grp_cols <- names(row)[!names(row) %in% meta_cols]
  df <- tibble(
    Group   = grp_cols,
    People  = sapply(grp_cols, function(col) as.double(row[[col]]))
  ) |>
    mutate(`%` = sprintf("%.1f%%", People / pop_2024 * 100)) |>
    filter(People / pop_2024 >= 0.01) |>
    arrange(desc(People)) |>
    mutate(Group  = .translate_ethnic_group(Group),
           People = .fmt_n(People))

  HTML(
    kable(df, format = "html", escape = TRUE,
          table.attr = 'class="table table-sm table-striped" style="font-size:11px;width:100%;"')
  )
}
