# muni-references.R
# Per-language citation registry for the Bolivia municipality generators.
#
# `refs[[lang]][[key]]` holds a bare citation template string (no <ref> wrapper).
# The compose_*() functions wrap these in <ref>...</ref> where needed.
#
# ENGLISH strings are the canonical citations already used by the generator.
#
# SPANISH strings are MECHANICAL conversions ({{Cite}} -> {{Cita web}},
# {{Cite news}} -> {{Cita noticia}}, {{Cite report}} -> {{Cita publicación}}),
# reusing the (already-Spanish) INE/OEP source titles.
#   >>> [[TODO:es]] Every es citation below is UNVERIFIED — confirm template
#   >>> names and parameter names against es.wikipedia conventions before publishing.
#
# Reference keys:
#   ine_pop, ine_lang, ine_identity   INE 2024 census tabulations (population,
#                                      language, self-identification)
#   census_pop, census_1992           population table sources (2024, 1992)
#   geo_2013                          INE 2013 community geographic classification
#   oep_report                        OEP subnational-elections results report
#   council_law_news                  Los Tiempos article on council-seat law
#   source_label                      plain-text source attribution (not a ref)

refs <- list(
  en = list(
    ine_pop = paste0(
      "{{Cite",
      "| last = Instituto Nacional de Estad\u00edstica",
      "| title = Poblaci\u00f3n censada e indicadores demogr\u00e1ficos: Tabulados por Municipio/TIOC",
      "| url = https://nube.ine.gob.bo/index.php/s/0OrfPjzMB16fATQ/download",
      "| date = 2025}}"
    ),
    ine_lang = paste0(
      "{{Cite",
      "| last = Instituto Nacional de Estad\u00edstica",
      "| title = Idioma en segundo orden de uso, idioma en tercer orden de uso e idiomas hablados (independientemente del orden de uso) de la poblaci\u00f3n de 6 o m\u00e1s a\u00f1os de edad: Tabulados por Municipio/TIOC",
      "| url = https://nube.ine.gob.bo/index.php/s/BSHb8IVQGA997Pv/download",
      "| date = 2025}}"
    ),
    ine_identity = paste0(
      "{{Cite",
      "| last = Instituto Nacional de Estad\u00edstica",
      "| title = Autoidentificaci\u00f3n con alguna naci\u00f3n pueblo ind\u00edgena originario campesino y afroboliviano: Tabulados por Municipio/TIOC",
      "| url = https://nube.ine.gob.bo/index.php/s/Mu3eStaUZfi97Vp/download",
      "| date = 2025}}"
    ),
    census_pop = paste0(
      "{{Cite",
      "| last = Instituto Nacional de Estad\u00edstica",
      "| title = Poblaci\u00f3n censada e indicadores demogr\u00e1ficos: Tabulados por Municipio/TIOC",
      "| date = 2025",
      "| url = https://nube.ine.gob.bo/index.php/s/0OrfPjzMB16fATQ/download",
      "}}"
    ),
    census_1992 = paste0(
      "{{Cite",
      "| last = Instituto Nacional de Estad\u00edstica",
      "| title = CENSO NACIONAL DE POBLACI\u00d3N Y VIVIENDA 1992: Ficha Municipal",
      "| access-date = 2026-06-22",
      "| date = 2018-12-17",
      "| url = https://anda.ine.gob.bo/index.php/catalog/47",
      "}}"
    ),
    geo_2013 = paste0(
      "{{Cite| last = Instituto Nacional de Estad\u00edstica",
      "| title = Clasificaci\u00f3n de Ubicaci\u00f3n Geogr\u00e1fica a Nivel Comunidad",
      "| date = 2013-01-01 ",
      "| url = https://anda.ine.gob.bo/index.php/catalog/71/download/716 }}"
    ),
    oep_report = paste0(
      "{{Cite report| publisher = \u00d3rgano Electoral Plurinacional",
      "| last1 = \u00d3rgano Electoral Plurinacional",
      "| last2 = Tribunal Supremo Electoral",
      "| title = Publicaci\u00f3n de resultados Elecciones Subnacionales 2026: Elecci\u00f3n de Autoridades Pol\u00edticas Departamentales Regionales y Municipales 2026 (Primera y Segunda Vuelta Electoral)",
      "| series = Separata de informaci\u00f3n p\u00fablica| date = 2026-04-23}}"
    ),
    council_law_news = paste0(
      "{{Cite news| title = A m\u00e1s poblaci\u00f3n, los municipios tienen m\u00e1s concejales, seg\u00fan la ley",
      "| work = Los Tiempos| access-date = 2026-06-19| date = 2026-02-08",
      "| url = https://www.lostiempos.com/actualidad/pais/20260208/mas-poblacion-municipios-tienen-mas-concejales-ley}}"
    ),
    source_label = "Supreme Electoral Tribunal."
  ),

  es = list(
    ine_pop = paste0(
      "{{Cita web| apellido = Instituto Nacional de Estad\u00edstica",
      "| t\u00edtulo = Poblaci\u00f3n censada e indicadores demogr\u00e1ficos: Tabulados por Municipio/TIOC",
      "| fecha = 2025| a\u00f1o = 2025",
      "| url = https://nube.ine.gob.bo/index.php/s/0OrfPjzMB16fATQ/download}}"
    ),
    ine_lang = paste0(
      "{{Cita web| apellido = Instituto Nacional de Estad\u00edstica",
      "| t\u00edtulo = Idioma en segundo orden de uso, idioma en tercer orden de uso e idiomas hablados (independientemente del orden de uso) de la poblaci\u00f3n de 6 o m\u00e1s a\u00f1os de edad: Tabulados por Municipio/TIOC",
      "| fecha = 2025| a\u00f1o = 2025",
      "| url = https://nube.ine.gob.bo/index.php/s/BSHb8IVQGA997Pv/download}}"
    ),
    ine_identity = paste0(
      "{{Cita web| apellido = Instituto Nacional de Estad\u00edstica",
      "| t\u00edtulo = Autoidentificaci\u00f3n con alguna naci\u00f3n pueblo ind\u00edgena originario campesino y afroboliviano: Tabulados por Municipio/TIOC",
      "| fecha = 2025| a\u00f1o = 2025",
      "| url = https://nube.ine.gob.bo/index.php/s/Mu3eStaUZfi97Vp/download}}"
    ),
    census_pop = paste0(
      "{{Cita web| apellido = Instituto Nacional de Estad\u00edstica",
      "| t\u00edtulo = Poblaci\u00f3n censada e indicadores demogr\u00e1ficos: Tabulados por Municipio/TIOC",
      "| fecha = 2025| a\u00f1o = 2025",
      "| url = https://nube.ine.gob.bo/index.php/s/0OrfPjzMB16fATQ/download}}"
    ),
    census_1992 = paste0(
      "{{Cita web| apellido = Instituto Nacional de Estad\u00edstica",
      "| t\u00edtulo = CENSO NACIONAL DE POBLACI\u00d3N Y VIVIENDA 1992",
      "| fecha = 2018-12-17| a\u00f1o = 2018",
      "| url = https://anda.ine.gob.bo/index.php/catalog/47",
      "| fechaacceso = 2026-06-22}}"
    ),
    geo_2013 = paste0(
      "{{Cita| apellido = Instituto Nacional de Estad\u00edstica",
      "| t\u00edtulo = Clasificaci\u00f3n de Ubicaci\u00f3n Geogr\u00e1fica a Nivel Comunidad",
      "| fecha = 2013-01-01| a\u00f1o = 2013",
      "| url = https://anda.ine.gob.bo/index.php/catalog/71/download/716}}"
    ),
    oep_report = paste0(
      "{{Cita libro| apellido = \u00d3rgano Electoral Plurinacional",
      "| apellido2 = Tribunal Supremo Electoral",
      "| t\u00edtulo = Publicaci\u00f3n de resultados Elecciones Subnacionales 2026: Elecci\u00f3n de Autoridades Pol\u00edticas Departamentales Regionales y Municipales 2026 (Primera y Segunda Vuelta Electoral)",
      "| editorial = \u00d3rgano Electoral Plurinacional",
      "| serie = Separata de informaci\u00f3n p\u00fablica| fecha = 2026-04-23| a\u00f1o = 2026",
      "| url = https://web.oep.org.bo/wp-content/uploads/2026/04/23-04-2026-part-1-y-2-V6_compressed.pdf}}"
    ),
    council_law_news = paste0(
      "{{Cita noticia| t\u00edtulo = A m\u00e1s poblaci\u00f3n, los municipios tienen m\u00e1s concejales, seg\u00fan la ley",
      "| peri\u00f3dico = Los Tiempos| fecha = 2026-02-08| a\u00f1o = 2026",
      "| url = https://www.lostiempos.com/actualidad/pais/20260208/mas-poblacion-municipios-tienen-mas-concejales-ley",
      "| fechaacceso = 2026-06-19}}"
    ),
    source_label = "Tribunal Supremo Electoral."
  )
)

# Append a page number to a citation template (used for the OEP report, which
# is cited per municipality by page). Parameter name is language-specific.
ref_with_page <- function(ref, page_number, lang = "en") {
  key <- if (lang == "es") "p\u00e1gina" else "page"
  ref_minus_end <- sub("\\}\\}$", "", ref)
  paste0(ref_minus_end, " | ", key, " = ", page_number, " }}")
}
