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

# Shared i18n layer: label() accessor + translate_values() + transcats tables.
source(here::here("src", "muni-i18n.R"))

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

# Internal helpers: number formatting with language-aware thousands separator.
# Spanish Wikipedia uses non-breaking space (&nbsp; in wikitext) as thousands separator;
# English uses comma. Decimal separator is always comma for Bolivian context.
.fmt_n <- function(x, lang = "en") {
  big_mark <- if (lang == "es") "&nbsp;" else ","
  format(round(x), big.mark = big_mark, scientific = FALSE)
}
.fmt_pct <- function(x) sprintf("%.1f%%", x * 100)

# Translate an ethnic-group column name to a display label in `lang`.
# Backed by the transcats "ethnic_group" translation table (data/translations/):
# trailing parenthetical footnote markers are stripped in both languages, and
# "Sin especificar" maps to "Unspecified Indigenous" (en) / "Indígena sin
# especificar" (es). Unknown values pass through unchanged.
.translate_ethnic_group <- function(g, lang = "en") {
  translate_values(g, "ethnic_group", lang)
}

# Translate a language column name (with or without a _2024/_2012 suffix) to a
# display label in `lang`, via the transcats "language" translation table.
.clean_lang_name <- function(x, lang = "en") {
  base <- str_remove(x, "_(2024|2012)$")
  translate_values(base, "language", lang)
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
# Internal: language-use wikitable for a given language
.build_language_wikitable <- function(id_muni, lang_data, pop_data,
                                       caption, source, source_refs, lang) {
  if (is.null(caption)) caption <- label("cap_languages", lang)
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
    language = .clean_lang_name(cols_2024, lang),
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
    sprintf("! %s !! %s !! %s !! %s !! %s",
            label("col_language", lang),      label("col_speakers_2024", lang),
            label("col_pct_2024", lang),      label("col_speakers_2012", lang),
            label("col_pct_2012", lang)))

  for (i in seq_len(nrow(langs))) {
    r <- langs[i, ]
    lines <- c(lines, "|-",
               sprintf("| %s || %s || %s || %s || %s",
                       r$language,
                       .fmt_n(r$n_2024, lang), .fmt_pct(r$pct_2024),
                       .fmt_n(r$n_2012, lang), .fmt_pct(r$pct_2012)))
  }

  lines <- .append_source_row(lines, 5L, source, source_refs,
                              label("lbl_source", lang))
  lines <- c(lines, "|}")
  paste(lines, collapse = "\n")
}

#' @rdname build_language_wikitable
#' @export
build_language_wikitable_en <- function(id_muni, lang_data, pop_data,
                                         caption = NULL,
                                         source = NULL, source_refs = NULL) {
  .build_language_wikitable(id_muni, lang_data, pop_data, caption,
                            source, source_refs, lang = "en")
}

#' @rdname build_language_wikitable
#' @export
build_language_wikitable_es <- function(id_muni, lang_data, pop_data,
                                         caption = NULL,
                                         source = NULL, source_refs = NULL) {
  .build_language_wikitable(id_muni, lang_data, pop_data, caption,
                            source, source_refs, lang = "es")
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
# Internal: ethnic-identification wikitable for a given language (2024 only)
.build_autoident_wikitable <- function(id_muni, auto_data, pop_data,
                                        caption, source, source_refs, lang) {
  if (is.null(caption)) caption <- label("cap_autoident", lang)
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
  lines <- c(lines, sprintf("! %s !! %s !! %s",
                             label("col_group", lang),
                             label("col_population", lang),
                             label("col_pct", lang)))

  for (i in seq_len(nrow(groups))) {
    r <- groups[i, ]
    lines <- c(lines, "|-",
               sprintf("| %s || %s || %s",
                       .translate_ethnic_group(r$group, lang),
                       .fmt_n(r$n, lang), .fmt_pct(r$pct)))
  }

  lines <- .append_source_row(lines, 3L, source, source_refs,
                              label("lbl_source", lang))
  lines <- c(lines, "|}")
  paste(lines, collapse = "\n")
}

#' @rdname build_autoident_wikitable
#' @export
build_autoident_wikitable_en <- function(id_muni, auto_data, pop_data,
                                          caption = NULL,
                                          source = NULL, source_refs = NULL) {
  .build_autoident_wikitable(id_muni, auto_data, pop_data, caption,
                             source, source_refs, lang = "en")
}

#' @rdname build_autoident_wikitable
#' @export
build_autoident_wikitable_es <- function(id_muni, auto_data, pop_data,
                                          caption = NULL,
                                          source = NULL, source_refs = NULL) {
  .build_autoident_wikitable(id_muni, auto_data, pop_data, caption,
                             source, source_refs, lang = "es")
}

#' HTML kable preview of language use
#'
#' @param id_muni Six-digit id_muni / ine_code string
#' @param lang_data Data frame with language spoken counts
#' @param pop_data Data frame with population columns
#'
#' @return HTML kable for display
# Internal: language-use kable preview for a given language
.build_language_kable <- function(id_muni, lang_data, pop_data, lang) {
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
    language  = .clean_lang_name(cols_2024, lang),
    spk_2024  = n24,
    pct_2024  = sprintf("%.1f%%", n24 / pop_2024 * 100),
    spk_2012  = n12,
    pct_2012  = sprintf("%.1f%%", n12 / pop_2012 * 100)
  ) |>
    filter(as.numeric(spk_2024) / pop_2024 >= 0.01 |
           as.numeric(spk_2012) / pop_2012 >= 0.01) |>
    arrange(desc(spk_2024)) |>
    mutate(spk_2024 = .fmt_n(spk_2024, lang),
           spk_2012 = .fmt_n(spk_2012, lang))

  names(df) <- c(label("col_language", lang),  label("col_speakers_2024", lang),
                 label("col_pct_2024", lang),  label("col_speakers_2012", lang),
                 label("col_pct_2012", lang))

  HTML(
    kable(df, format = "html", escape = TRUE,
          table.attr = 'class="table table-sm table-striped" style="font-size:11px;width:100%;"')
  )
}

#' @rdname build_language_kable
#' @export
build_language_kable_en <- function(id_muni, lang_data, pop_data) {
  .build_language_kable(id_muni, lang_data, pop_data, lang = "en")
}

#' @rdname build_language_kable
#' @export
build_language_kable_es <- function(id_muni, lang_data, pop_data) {
  .build_language_kable(id_muni, lang_data, pop_data, lang = "es")
}

#' HTML kable preview of ethnic identification
#'
#' @param id_muni Six-digit id_muni / ine_code string
#' @param auto_data Data frame with ethnic self-identification counts
#' @param pop_data Data frame with population columns
#'
#' @return HTML kable for display
# Internal: ethnic-identification kable preview for a given language
.build_autoident_kable <- function(id_muni, auto_data, pop_data, lang) {
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
    group   = grp_cols,
    people  = sapply(grp_cols, function(col) as.double(row[[col]]))
  ) |>
    mutate(pct = sprintf("%.1f%%", people / pop_2024 * 100)) |>
    filter(people / pop_2024 >= 0.01) |>
    arrange(desc(people)) |>
    mutate(group  = .translate_ethnic_group(group, lang),
           people = .fmt_n(people, lang))

  names(df) <- c(label("col_group", lang), label("col_people", lang),
                 label("col_pct", lang))

  HTML(
    kable(df, format = "html", escape = TRUE,
          table.attr = 'class="table table-sm table-striped" style="font-size:11px;width:100%;"')
  )
}

#' @rdname build_autoident_kable
#' @export
build_autoident_kable_en <- function(id_muni, auto_data, pop_data) {
  .build_autoident_kable(id_muni, auto_data, pop_data, lang = "en")
}

#' @rdname build_autoident_kable
#' @export
build_autoident_kable_es <- function(id_muni, auto_data, pop_data) {
  .build_autoident_kable(id_muni, auto_data, pop_data, lang = "es")
}
