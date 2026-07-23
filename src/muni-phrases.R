# muni-phrases.R
# Per-language phrase dictionary for the Bolivia municipality generators.
#
# `phrases[[lang]]` is a list of small functions, each returning a piece of
# article PROSE (wikitext) for language `lang`. Citations (<ref> tags) are NOT
# added here; the calling compose_*() functions append them from muni-references.R.
#
# Grammar and gender are isolated in this file so they can be reviewed in one
# place. Supported languages: "en", "es".
#
# Dependencies: glue, english

library(glue)
library(english)

# ---- Spanish helpers ----------------------------------------------------------

# Feminine ordinals (agreeing with "sección municipal"); fallback "{n}.ª".
.es_ordinals_fem <- c(
  "primera", "segunda", "tercera", "cuarta", "quinta", "sexta", "s\u00e9ptima",
  "octava", "novena", "d\u00e9cima", "und\u00e9cima", "duod\u00e9cima",
  "decimotercera", "decimocuarta", "decimoquinta", "decimosexta",
  "decimos\u00e9ptima", "decimoctava", "decimonovena", "vig\u00e9sima"
)
.es_ordinal_fem <- function(n) {
  if (!is.na(n) && n >= 1 && n <= length(.es_ordinals_fem)) .es_ordinals_fem[n]
  else paste0(n, ".\u00aa")
}

# Cardinal number words; fallback to the digits.
.es_numbers <- c("uno", "dos", "tres", "cuatro", "cinco", "seis", "siete",
                 "ocho", "nueve", "diez", "once", "doce", "trece", "catorce",
                 "quince", "diecis\u00e9is", "diecisiete", "dieciocho",
                 "diecinueve", "veinte")
.es_number_word <- function(n) {
  if (!is.na(n) && n >= 1 && n <= length(.es_numbers)) .es_numbers[n]
  else as.character(n)
}

# Spanish department article-link targets (es.wikipedia titles).
.es_dept_link <- function(dept) {
  if (identical(dept, "Beni")) "Departamento del Beni"
  else paste0("Departamento de ", dept)
}

# ---- Phrase dictionary --------------------------------------------------------

phrases <- list(
  en = list(
    ordinal     = function(n) english::ordinal(n),
    number_word = function(n) as.character(english::words(n)),
    dept_link   = function(dept) paste0(dept, " Department"),

    lead = function(muni, ordinal, prov_link, dept_link) {
      glue("'''{muni} Municipality''' is the {ordinal} ",
           "[[Municipalities of Bolivia|municipal section]] of the ",
           "[[{prov_link}]] in the [[{dept_link}]] in [[Bolivia]].")
    },

    pop_rank_national = function(rank) {
      ord <- if (rank == 1) "most" else "second most"
      glue("It is the {ord} populous municipality in [[Bolivia]].")
    },
    pop_rank_dept = function(rank, dept_link) {
      ord <- if (rank == 1) "most" else "second most"
      glue("It is the {ord} populous municipality in [[{dept_link}]].")
    },
    pop_rank_prov = function(prov_link) {
      glue("It is the most populous municipality in [[{prov_link}]].")
    },

    prov_context_only = function(muni, prov_link) {
      glue("{muni} Municipality is the only municipality in ",
           "[[{prov_link}]] and its boundaries are identical.")
    },
    prov_context_two = function(muni, prov_link, larger, more_pop) {
      if (larger && more_pop)
        glue("{muni} Municipality is the larger and more populous of the two ",
             "municipalities in [[{prov_link}]].")
      else if (larger && !more_pop)
        glue("{muni} Municipality covers the larger area of the two ",
             "municipalities in [[{prov_link}]], but it is less populous.")
      else if (!larger && more_pop)
        glue("{muni} Municipality is the more populous of the two ",
             "municipalities in [[{prov_link}]], but it covers a smaller area.")
      else
        glue("{muni} Municipality is the smaller and less populous of the two ",
             "municipalities in [[{prov_link}]].")
    },

    mayor = function(muni, nombre, female) {
      glue("The Mayor of {muni} is {nombre}, who was elected in the ",
           "[[2026 Bolivian regional elections|March 2026 elections]].")
    },

    council_range = function(es_capital, pop) {
      dplyr::case_when(
        es_capital & pop > 75000 ~
          "department capitals and municipalities with populations over 75,000",
        es_capital               ~ "department capitals",
        pop > 75000              ~ "municipalities with populations over 75,000",
        pop > 50000              ~ "municipalities with populations between 50,001 and 75,000",
        pop > 15000              ~ "municipalities with populations between 15,001 and 50,000",
        TRUE                     ~ "municipalities with populations up to 15,000"
      )
    },
    council_seats = function(muni, n_word, range_phrase) {
      glue("{muni} has a municipal council with {n_word} seats, as do all ",
           "{range_phrase}.")
    },
    council_ioc = function(pueblo) {
      glue("One of those seats is an Indigenous seat assigned by the ",
           "{pueblo} according to its own norms and procedures.")
    },

    communities_intro = function() {
      "The following communities are located within the municipality:"
    },
    communities_intro_colquechaca = function() {
      paste0("Communities were divided between San Pedro de Macha and Colquechaca ",
             "when the municipalities were split in 2019. The following communities ",
             "were in the original municipality of Colquechaca:")
    }
  ),

  es = list(
    ordinal     = .es_ordinal_fem,
    number_word = .es_number_word,
    dept_link   = .es_dept_link,

    lead = function(muni, ordinal, prov_link, dept_link) {
      glue("'''{muni}''' es la {ordinal} ",
           "[[Municipios de Bolivia|secci\u00f3n municipal]] de la ",
           "[[{prov_link}]] en el [[{dept_link}]] en [[Bolivia]].")
    },

    pop_rank_national = function(rank) {
      ord <- if (rank == 1) "m\u00e1s" else "segundo m\u00e1s"
      glue("Es el municipio {ord} poblado de [[Bolivia]].")
    },
    pop_rank_dept = function(rank, dept_link) {
      ord <- if (rank == 1) "m\u00e1s" else "segundo m\u00e1s"
      glue("Es el municipio {ord} poblado del [[{dept_link}]].")
    },
    pop_rank_prov = function(prov_link) {
      glue("Es el municipio m\u00e1s poblado de la [[{prov_link}]].")
    },

    prov_context_only = function(muni, prov_link) {
      glue("{muni} es el \u00fanico municipio de la [[{prov_link}]] y ",
           "sus l\u00edmites son id\u00e9nticos.")
    },
    prov_context_two = function(muni, prov_link, larger, more_pop) {
      if (larger && more_pop)
        glue("{muni} es el m\u00e1s grande y m\u00e1s poblado de los dos ",
             "municipios de la [[{prov_link}]].")
      else if (larger && !more_pop)
        glue("{muni} abarca la mayor superficie de los dos municipios de la ",
             "[[{prov_link}]], pero es menos poblado.")
      else if (!larger && more_pop)
        glue("{muni} es el m\u00e1s poblado de los dos municipios de la ",
             "[[{prov_link}]], pero abarca una superficie menor.")
      else
        glue("{muni} es el m\u00e1s peque\u00f1o y menos poblado de los dos ",
             "municipios de la [[{prov_link}]].")
    },

    # `female` selects gendered title + participle agreement.
    mayor = function(muni, nombre, female) {
      if (isTRUE(female))
        glue("La alcaldesa de {muni} es {nombre}, elegida en las ",
             "[[Elecciones subnacionales de Bolivia de 2026|elecciones de marzo de 2026]].")
      else
        glue("El alcalde de {muni} es {nombre}, elegido en las ",
             "[[Elecciones subnacionales de Bolivia de 2026|elecciones de marzo de 2026]].")
    },

    council_range = function(es_capital, pop) {
      dplyr::case_when(
        es_capital & pop > 75000 ~
          "las capitales departamentales y los municipios con m\u00e1s de 75.000 habitantes",
        es_capital               ~ "las capitales departamentales",
        pop > 75000              ~ "los municipios con m\u00e1s de 75.000 habitantes",
        pop > 50000              ~ "los municipios con entre 50.001 y 75.000 habitantes",
        pop > 15000              ~ "los municipios con entre 15.001 y 50.000 habitantes",
        TRUE                     ~ "los municipios con hasta 15.000 habitantes"
      )
    },
    council_seats = function(muni, n_word, range_phrase) {
      glue("{muni} tiene un concejo municipal con {n_word} esca\u00f1os, ",
           "al igual que {range_phrase}.")
    },
    council_ioc = function(pueblo) {
      glue("Uno de esos esca\u00f1os es un esca\u00f1o ind\u00edgena asignado por el ",
           "pueblo {pueblo} seg\u00fan sus propias normas y procedimientos.")
    },

    communities_intro = function() {
      "Las siguientes comunidades se encuentran dentro del municipio:"
    },
    communities_intro_colquechaca = function() {
      paste0("Las comunidades se dividieron entre San Pedro de Macha y Colquechaca ",
             "cuando los municipios se separaron en 2019. Las siguientes comunidades ",
             "estaban en el municipio original de Colquechaca:")
    }
  )
)
