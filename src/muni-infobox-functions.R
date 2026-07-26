# muni-infobox-functions.R
# Language- and template-aware infobox engine for the Bolivia municipality
# infobox generators.
#
#   - English targets {{Infobox settlement}}.
#   - Spanish targets {{Ficha de entidad subnacional}} — a DIFFERENT template
#     with a different parameter schema, so this is a field-schema remap, not
#     merely value/label translation.
#
# Design: compute_infobox_data(id) returns a language-neutral list of raw facts
# (the single source of truth). infobox_specs[[lang]] describes the target
# template (name, field order, section-header comments, force-blank/excluded
# sets, and a data -> named-field-vector `build` mapper). render_infobox_wikitext()
# and render_infobox_merge_lines() are generic and read everything from the spec.
#
# Prose/labels come from phrases[[lang]] / label() (muni-phrases.R, muni-i18n.R),
# citations from refs[[lang]] (muni-references.R). Province links reuse
# prov_link_target() from muni-article-functions.R.
#
# Like the article engine, these functions read several lookups from the global
# environment (built in the qmd setup chunk): muni_lookup, prov_lookup,
# prov_link_lookup, pop_muni, pop_muni_ur, area_muni, alcaldes, muni_roster,
# commons_log, munis_with_p402, wd_images, wd_ine, auto_data, and (for merges)
# existing_infobox_blocks.
#
# The verbatim infobox-parsing helpers below (extract_infobox_wikitext,
# split_on_top_level_pipes, parse_infobox_blocks, has_real_content) are inlined
# copies: library(wikitools) exports extract_infobox()/clean_infobox_value(),
# but those flatten values into single-line strings, whereas the merge path needs
# each field's markup preserved EXACTLY (comments, spacing, newlines intact).

library(dplyr)
library(purrr)
library(htmltools)
library(stringr)
library(glue)
library(wikitools)

# prov_link_target(), spanish_title_case(), wikipedia_url_for(), and (transitively)
# phrases[[lang]], refs[[lang]], label(), translate_values().
source(here::here("src", "muni-article-functions.R"))

# ---- Inlined verbatim infobox-parsing helpers ---------------------------------

# Split on "|" not inside {{ }}, [[ ]], or <!-- --> comments (comments copied
# verbatim so a "|" inside one is not misread as a field delimiter).
split_on_top_level_pipes <- function(text) {
  parts <- character()
  depth <- 0
  current <- ""

  i <- 1
  n <- nchar(text)
  while (i <= n) {
    if (substr(text, i, i + 3) == "<!--") {
      match_pos <- regexpr("-->", substr(text, i, n), fixed = TRUE)
      if (match_pos == -1) {
        current <- paste0(current, substr(text, i, n))
        i <- n + 1
      } else {
        end <- i + match_pos + 1
        current <- paste0(current, substr(text, i, end))
        i <- end + 1
      }
      next
    }

    ch <- substr(text, i, i)

    if (ch == "{" && i < nchar(text) && substr(text, i + 1, i + 1) == "{") {
      depth <- depth + 1
      current <- paste0(current, "{{")
      i <- i + 2
      next
    }
    if (ch == "}" && i < nchar(text) && substr(text, i + 1, i + 1) == "}") {
      depth <- depth - 1
      current <- paste0(current, "}}")
      i <- i + 2
      next
    }
    if (ch == "[" && i < nchar(text) && substr(text, i + 1, i + 1) == "[") {
      depth <- depth + 1
      current <- paste0(current, "[[")
      i <- i + 2
      next
    }
    if (ch == "]" && i < nchar(text) && substr(text, i + 1, i + 1) == "]") {
      depth <- depth - 1
      current <- paste0(current, "]]")
      i <- i + 2
      next
    }

    if (ch == "|" && depth == 0) {
      parts <- c(parts, current)
      current <- ""
    } else {
      current <- paste0(current, ch)
    }
    i <- i + 1
  }
  if (nchar(current) > 0) parts <- c(parts, current)
  parts
}

# Isolate the complete infobox template (from {{ to matching }}). Matches
# English {{Infobox ...}}, Spanish {{Ficha de ...}}, Portuguese {{Info/ ...}}.
extract_infobox_wikitext <- function(wikitext) {
  if (is.null(wikitext)) return(NULL)

  infobox_start <- regexpr(
    "\\{\\{\\s*(?:[Ii]nfobox|[Ff]icha\\s+de|[Ii]nfo/)",
    wikitext, perl = TRUE
  )
  if (infobox_start == -1) return(NULL)

  txt <- substring(wikitext, infobox_start)
  depth <- 0
  end_pos <- NA
  i <- 1
  while (i <= nchar(txt)) {
    ch <- substr(txt, i, i)
    if (ch == "{" && i < nchar(txt) && substr(txt, i + 1, i + 1) == "{") {
      depth <- depth + 1
      i <- i + 2
      next
    }
    if (ch == "}" && i < nchar(txt) && substr(txt, i + 1, i + 1) == "}") {
      depth <- depth - 1
      if (depth == 0) {
        end_pos <- i + 1
        break
      }
      i <- i + 2
      next
    }
    i <- i + 1
  }

  if (is.na(end_pos)) return(NULL)
  substr(txt, 1, end_pos)
}

# Parse an infobox's raw wikitext into an ordered list of field blocks,
# preserving each parameter's text EXACTLY as written.
parse_infobox_blocks <- function(infobox_text) {
  if (is.null(infobox_text)) return(list())

  inner <- sub(
    "^\\{\\{\\s*(?:[Ii]nfobox|[Ff]icha\\s+de|[Ii]nfo/)[^\\n|]*",
    "", infobox_text, perl = TRUE
  )
  inner <- sub("\\}\\}$", "", inner)

  parts <- split_on_top_level_pipes(inner)

  blocks <- list()
  for (part in parts) {
    if (!grepl("=", part)) next
    eq_pos <- regexpr("=", part)
    key <- trimws(substr(part, 1, eq_pos - 1))
    val_raw <- substr(part, eq_pos + 1, nchar(part))
    if (nchar(key) == 0) next
    blocks[[length(blocks) + 1]] <- list(field = key, raw_value = val_raw)
  }
  blocks
}

# Does a raw (possibly multi-line, comment-laden) field value have real content
# once HTML comments are notionally removed?
has_real_content <- function(raw_value) {
  no_comments <- gsub("<!--.*?-->", "", raw_value, perl = TRUE)
  nzchar(trimws(no_comments))
}

# ---- Citations (from the shared registry) -------------------------------------

# Population footnote (named ref) and its reuse tag.
ine_pop_ref_for   <- function(lang) paste0('<ref name="ine_pop">', refs[[lang]]$ine_pop, "</ref>")
ine_pop_ref_reuse <- '<ref name="ine_pop" />'

# OEP report cited per municipality by page; parameter name is language-specific.
oep_ref_with_page <- function(page, lang) {
  base <- sub("\\}\\}$", "", refs[[lang]]$oep_report)
  key  <- if (lang == "es") "p\u00e1gina" else "page"
  paste0("<ref>", base, "| ", key, " = ", page, "}}</ref>")
}

# ---- Ethnicities --------------------------------------------------------------

# Per-language wikilink maps for named ethnic groups. Keys are the raw census
# group names (as they appear in auto_data column names).
ethnicity_wikilinks <- list(
  en = c(
    "Quechua"       = "[[Quechua people|Quechua]]",
    "Aymara"        = "[[Aymara people|Aymara]]",
    "Chiquitano"    = "[[Chiquitano people|Chiquitano]]",
    "Guaran\u00ed"  = "[[Guaran\u00ed people|Guaran\u00ed]]",
    "Moje\u00f1o"   = "[[Moxo people|Moje\u00f1o]]",
    "Afroboliviano" = "[[Afro-Bolivians|Afroboliviano]]",
    "Uru"           = "[[Uru people|Uru]]",
    "Chipaya"       = "[[Chipaya people|Chipaya]]",
    "Yuracar\u00e9" = "[[Yuqui people|Yuracar\u00e9]]",
    "Movima"        = "[[Movima people|Movima]]",
    "Tacana"        = "[[Tacana people|Tacana]]",
    "Weenhayek"     = "[[Weenhayek people|Weenhayek]]",
    "Tsimane"       = "[[Tsimane|Tsimane]]",
    "Ayoreo"        = "[[Ayoreo people|Ayoreo]]",
    "Ese Ejja"      = "[[Ese Ejja people|Ese Ejja]]",
    "Leco"          = "[[Leco people|Leco]]",
    "Kallawaya"     = "[[Kallawaya people|Kallawaya]]",
    "Moseten"       = "[[Moset\u00e9n people|Moseten]]"
  ),
  # ES targets from es.wikipedia "Grupos \u00e9tnicos de Bolivia" (Etnia
  # ind\u00edgena table). Uru and Chipaya both point to [[Etnias urus]] for now.
  es = c(
    "Quechua"       = "[[Quechua sure\u00f1o|Quechua]]",
    "Aymara"        = "[[Aimaras|Aymara]]",
    "Chiquitano"    = "[[Pueblo chiquitano|Chiquitano]]",
    "Guaran\u00ed"  = "[[Guaran\u00edes|Guaran\u00ed]]",
    "Moje\u00f1o"   = "[[Moje\u00f1os|Moje\u00f1o]]",
    "Afroboliviano" = "[[Afroboliviano]]",
    "Uru"           = "[[Etnias urus|Uru]]",
    "Chipaya"       = "[[Etnias urus|Chipaya]]",
    "Yuracar\u00e9" = "[[Yuracar\u00e9s|Yuracar\u00e9]]",
    "Movima"        = "[[Movimas|Movima]]",
    "Tacana"        = "[[Pueblo tacana|Tacana]]",
    "Weenhayek"     = "[[Weenhayek]]",
    "Tsimane"       = "[[T'simanes|Tsimane]]",
    "Ayoreo"        = "[[Ayoreos|Ayoreo]]",
    "Ese Ejja"      = "[[Pueblo ese'ejja|Ese Ejja]]",
    "Leco"          = "[[Idioma leco|Leco]]",
    "Kallawaya"     = "[[Kallawaya]]",
    "Moseten"       = "[[Mosetenes|Moset\u00e9n]]"
  )
)

# Label for the combined non-specific self-identification bucket.
unspecified_indigenous_label <- c(
  en = "Unspecified Indigenous",
  es = "Ind\u00edgena sin especificar"
)

# Language-aware integer / percentage formatters (Spanish uses "." thousands
# and "," decimals).
.fmt_int_lang <- function(n, lang) {
  if (lang == "es") {
    format(round(n), big.mark = ".", decimal.mark = ",", scientific = FALSE)
  } else {
    format(round(n), big.mark = ",", scientific = FALSE)
  }
}
.fmt_pct_lang <- function(p, lang) {
  s <- if (p >= 1) sprintf("%d%%", round(p)) else sprintf("%.1f%%", p)
  if (lang == "es") sub("\\.", ",", s) else s
}

# Wikitext of ethnic groups declared by >= threshold of population, translated
# and linked for `lang`. Returns "" if none / municipality not found.
get_top_ethnicities <- function(id, auto_data, pop_total, lang, threshold = 0.01) {
  row <- auto_data |> filter(ine_code == id) |> slice(1)
  if (nrow(row) == 0) return("")

  meta_cols <- c("ine_code", "municipio", "provincia", "departamento",
                 "area", "nivel", "total", "municipality", "province",
                 "department", "level", "row_num")
  grp_cols <- setdiff(names(row), meta_cols)

  groups <- tibble(
    group = grp_cols,
    n     = sapply(grp_cols, function(col) as.double(row[[col]]))
  )

  # "Campesino", "Originario", "Ind\u00edgena", and "Sin especificar" are all
  # non-specific categories; combine into a single "unspecified" total.
  is_unspecified <- groups$group %in% c("Campesino", "Originario", "Ind\u00edgena") |
    grepl("Sin especificar", groups$group, fixed = TRUE)
  unspecified_n <- sum(groups$n[is_unspecified], na.rm = TRUE)

  groups <- groups |> filter(!is_unspecified)

  if (unspecified_n > 0) {
    groups <- groups |> add_row(group = "__unspecified__", n = unspecified_n)
  }

  groups <- groups |>
    filter(n / pop_total >= threshold) |>
    arrange(desc(n))

  if (nrow(groups) == 0) return("")

  links <- ethnicity_wikilinks[[lang]]

  entries <- mapply(function(g, n) {
    label_txt <- if (g == "__unspecified__") {
      unspecified_indigenous_label[[lang]]
    } else if (g %in% names(links)) {
      links[[g]]
    } else {
      trimws(sub("\\s*\\(.*", "", g))
    }
    pct <- n / pop_total * 100
    sprintf("%s: %s (%s)", label_txt, .fmt_int_lang(n, lang), .fmt_pct_lang(pct, lang))
  }, groups$group, groups$n, SIMPLIFY = TRUE, USE.NAMES = FALSE)

  paste0(paste(entries, collapse = "<br>"), "<ref>", refs[[lang]]$ine_identity, "</ref>")
}

# ---- Neutral fact computation (single source of truth) ------------------------

# Returns a language-neutral list of raw municipality facts, or NULL if the
# municipality isn't in muni_lookup. Reads lookups from the global environment.
compute_infobox_data <- function(id) {
  ml <- muni_lookup |> filter(id_muni == id) |> slice(1)
  if (nrow(ml) == 0) return(NULL)

  id_prov <- ml$id_prov

  prov_row  <- prov_lookup |> filter(id_prov == .env$id_prov) |> slice(1)
  prov_name <- if (nrow(prov_row) > 0) {
    coalesce(prov_row$province_cpv2024, prov_row$province_anexo)
  } else NA_character_

  pop_row   <- pop_muni |> filter(id_muni == id) |> slice(1)
  pop_total <- if (nrow(pop_row) > 0) pop_row$pop_2024 else NA_real_

  urban_pop <- pop_muni_ur |> filter(id_muni == id, area == "Urbana") |>
    pull(pop_2024) |> (\(x) if (length(x) == 0) NA_real_ else x)()
  rural_pop <- pop_muni_ur |> filter(id_muni == id, area == "Rural") |>
    pull(pop_2024) |> (\(x) if (length(x) == 0) NA_real_ else x)()

  geo      <- area_muni |> filter(id_muni == id) |> slice(1)
  area_val <- if (nrow(geo) > 0 && !is.na(geo$area_sqkm)) geo$area_sqkm else NA_real_
  area_km2 <- if (!is.na(area_val)) round(area_val) else ""

  density_km2 <- if (!is.na(pop_total) && nrow(geo) > 0 && !is.na(geo$area_sqkm) && geo$area_sqkm > 0) {
    format(signif(pop_total / geo$area_sqkm, 2), scientific = FALSE, trim = TRUE)
  } else ""

  alc <- alcaldes |> filter(id_muni == id) |> slice(1)
  if (nrow(alc) > 0) {
    page_row     <- muni_roster |> filter(id_muni == id) |> slice(1)
    mayor_page   <- if (nrow(page_row) > 0) page_row$page else NA
    mayor_female <- isTRUE(grepl("ALCALDESA", alc$autoridad[1], ignore.case = TRUE))
    mayor <- list(present = TRUE, nombre = alc$nombre, sigla = alc$sigla,
                  page = mayor_page, female = mayor_female)
  } else {
    mayor <- list(present = FALSE)
  }

  map_row  <- commons_log |> filter(id_muni == id) |> slice(1)
  map_file <- if (nrow(map_row) > 0) map_row$commons_filename else ""

  qid_val <- if (exists("wd_ine")) {
    qr <- wd_ine |> filter(ine_code == id) |> slice(1)
    if (nrow(qr) > 0 && !is.na(qr$qid)) qr$qid else ""
  } else ""

  zoom_level <- if (!is.na(area_val)) {
    if      (area_val > 40000) 6L
    else if (area_val > 15000) 7L
    else if (area_val > 4000)  8L
    else if (area_val > 1000)  9L
    else                       10L
  } else 8L

  img_row   <- if (exists("wd_images")) wd_images |> filter(ine_code == id) |> slice(1) else tibble()
  flag_file <- if (nrow(img_row) > 0 && !is.na(img_row$flag_file)) img_row$flag_file else ""
  coat_file <- if (nrow(img_row) > 0 && !is.na(img_row$coat_file)) img_row$coat_file else ""
  seal_file <- if (nrow(img_row) > 0 && !is.na(img_row$seal_file)) img_row$seal_file else ""

  list(
    id          = id,
    muni_name   = ml$muni_anexo,
    department  = ml$department,
    id_prov     = id_prov,
    prov_name   = prov_name,
    pop_total   = pop_total,
    urban_pop   = urban_pop,
    rural_pop   = rural_pop,
    area_val    = area_val,
    area_km2    = area_km2,
    density_km2 = density_km2,
    mayor       = mayor,
    flag_file   = flag_file,
    coat_file   = coat_file,
    seal_file   = seal_file,
    map_file    = map_file,
    has_p402    = id %in% munis_with_p402,
    qid_val     = qid_val,
    zoom_level  = zoom_level,
    ocha_pcode  = paste0("BO", id)
  )
}

# ---- EN field builder ({{Infobox settlement}}) --------------------------------

# Canonical Infobox settlement field order (unchanged from the pre-refactor qmd).
infobox_field_order <- c(
  "official_name", "other_name", "native_name", "native_name_lang", "name",
  "nickname", "motto", "settlement_type",
  "translit_lang1_info1",
  "image_skyline", "imagesize", "image_alt", "image_caption",
  "image_flag", "flag_size", "flag_alt",
  "image_seal", "seal_size",
  "image_shield", "shield_size", "shield_alt",
  "image_blank_emblem", "blank_emblem_type", "blank_emblem_size",
  "image_map", "mapsize", "map_caption",
  "image_map1", "mapsize1", "map_caption1",
  "image_dot_map",
  "pushpin_map", "pushpin_mapsize", "pushpin_label_position", "pushpin_map_caption",
  "coordinates", "coordinates_footnotes",
  "subdivision_type", "subdivision_name",
  "subdivision_type1", "subdivision_name1",
  "subdivision_type2", "subdivision_name2",
  "subdivision_type3", "subdivision_name3",
  "subdivision_type4", "subdivision_name4",
  "established_title", "established_date",
  "established_title1", "established_date1",
  "established_title2", "established_date2",
  "established_title3", "established_date3",
  "founder",
  "seat_type", "seat",
  "government_footnotes", "government_type",
  "leader_title", "leader_name",
  "leader_title1", "leader_name1",
  "leader_title2", "leader_name2",
  "leader_title3", "leader_name3",
  "unit_pref",
  "area_magnitude", "area_footnotes",
  "area_total_km2", "area_land_km2", "area_water_km2",
  "area_blank1_title", "area_blank1_km2",
  "area_note",
  "elevation_footnotes", "elevation_m",
  "population_footnotes", "population_as_of", "population_total",
  "population_density_km2",
  "population_urban_footnotes", "population_urban", "population_density_urban_km2",
  "population_rural_footnotes", "population_rural", "population_density_rural_km2",
  "population_blank1_title", "population_blank1", "population_density_blank1_km2",
  "population_blank2_title", "population_blank2",
  "population_demonym", "population_note",
  "demographics_type1", "demographics1_footnotes", "demographics1_title1", "demographics1_info1",
  "timezone", "utc_offset",
  "timezone1", "utc_offset1",
  "postal_code_type", "postal_code",
  "area_code_type", "area_code",
  "geocode",
  "blank_name", "blank_info",
  "website", "footnotes"
)

infobox_section_headers <- c(
  official_name         = "<!--See the Table at Infobox Settlement for all fields and descriptions of usage-->\n<!-- Basic info  ---------------->",
  image_skyline         = "<!-- Images, maps and coordinates  ----------->",
  subdivision_type      = "<!-- Location ------------------>",
  established_title     = "<!-- Established -------------------->",
  seat_type             = "<!-- Seat of government / smaller parts -->",
  government_footnotes  = "<!-- Politics ----------------->",
  unit_pref             = "<!-- Area    --------------------->",
  elevation_footnotes   = "<!-- Elevation -------------------->",
  population_footnotes  = "<!-- Population   ----------------------->",
  demographics_type1    = "<!-- Demographics ----------------->",
  timezone              = "<!-- General information  --------------->",
  postal_code_type      = "<!-- Area/postal codes & others -------->",
  website               = "<!-- Website, footnotes ---------->"
)

build_infobox_fields_en <- function(data) {
  muni_name  <- data$muni_name
  department <- data$department
  prov_name  <- data$prov_name

  dept_link <- sprintf("[[%s Department|%s]]", department, department)
  prov_link <- if (!is.na(prov_name)) sprintf("[[%s Province|%s]]", prov_name, prov_name) else ""

  pushpin_caption <- sprintf("Location of %s Municipality within Bolivia", muni_name)

  map_file    <- data$map_file
  map_caption <- if (nzchar(map_file)) {
    sprintf("Location of the %s Municipality within Bolivia", muni_name)
  } else ""

  mayor_str <- if (isTRUE(data$mayor$present)) {
    name_tc <- stringr::str_to_title(data$mayor$nombre)
    ref_str <- if (!is.na(data$mayor$page)) oep_ref_with_page(data$mayor$page, "en") else ""
    paste0(name_tc, " (", data$mayor$sigla, ", 2026)", ref_str)
  } else ""

  eth_str <- if (!is.na(data$pop_total)) get_top_ethnicities(data$id, auto_data, data$pop_total, "en") else ""

  map1_str <- if (data$has_p402) {
    id_part <- if (nzchar(data$qid_val)) paste0(" |id=", data$qid_val) else ""
    sprintf(
      "{{maplink |type=shape |stroke-width=3 |fill=#999999 |frame=yes |plain=yes |frame-align=center |zoom=%d%s}}",
      data$zoom_level, id_part
    )
  } else ""
  map1_caption <- if (nzchar(map1_str)) {
    sprintf("%s Municipality and its local surroundings", muni_name)
  } else ""

  fn <- function(x) if (is.na(x) || x == "") "" else format(as.numeric(x), big.mark = ",", scientific = FALSE)

  flag_file <- data$flag_file
  coat_file <- data$coat_file
  seal_file <- data$seal_file

  geocode_str <- paste0(
    data$id, " ([[National Institute of Statistics of Bolivia|INE code]])",
    "<br>",
    data$ocha_pcode, " ([[United Nations Office for the Coordination of Humanitarian Affairs|OCHA]] [[Place code|P-code]])"
  )

  c(
    official_name          = muni_name,
    other_name             = "",
    native_name            = "",
    nickname               = "",
    settlement_type        = "Municipality",
    motto                  = "",
    image_skyline          = "",
    image_flag             = flag_file,
    flag_size              = if (nzchar(flag_file)) "150px" else "",
    flag_alt               = if (nzchar(flag_file)) paste0("Flag of ", muni_name, " Municipality") else "",
    image_seal             = seal_file,
    seal_size              = if (nzchar(seal_file)) "100px" else "",
    image_shield           = coat_file,
    shield_size            = if (nzchar(coat_file)) "100px" else "",
    shield_alt             = if (nzchar(coat_file)) paste0("Coat of arms of ", muni_name, " Municipality") else "",
    image_blank_emblem     = "",
    blank_emblem_type      = "",
    blank_emblem_size      = "",
    image_map              = map_file,
    mapsize                = "300px",
    map_caption            = map_caption,
    image_map1             = map1_str,
    mapsize1               = "",
    map_caption1           = map1_caption,
    image_dot_map          = "",
    pushpin_map            = "Bolivia",
    pushpin_label_position = "bottom",
    pushpin_map_caption    = pushpin_caption,
    subdivision_type       = "Country",
    subdivision_name       = "[[Image:Flag of Bolivia.svg|25px]] [[Bolivia]]",
    subdivision_type1      = "[[Departments of Bolivia|Department]]",
    subdivision_name1      = dept_link,
    subdivision_type2      = "[[Provinces of Bolivia|Province]]",
    subdivision_name2      = prov_link,
    subdivision_type4      = "[[Cantons of Bolivia|Cantons]]",
    subdivision_name4      = "",
    government_footnotes   = "",
    government_type        = "",
    leader_title           = "Mayor",
    leader_name            = mayor_str,
    area_magnitude         = "",
    unit_pref              = "Metric",
    area_footnotes         = "",
    area_total_km2         = fn(data$area_km2),
    area_land_km2          = "",
    area_water_km2         = "",
    population_as_of               = "2024",
    population_footnotes           = ine_pop_ref_for("en"),
    population_note                = "[[2024 Bolivian census]]",
    population_total               = fn(data$pop_total),
    population_density_km2         = fn(data$density_km2),
    population_urban_footnotes     = ine_pop_ref_reuse,
    population_urban               = fn(data$urban_pop),
    population_rural_footnotes     = ine_pop_ref_reuse,
    population_rural               = fn(data$rural_pop),
    population_blank1_title        = "Indigenous ethnicities",
    population_blank1              = eth_str,
    timezone                = "[[Bolivia Time|BOT]]",
    utc_offset              = "-4",
    postal_code_type        = "",
    postal_code             = "",
    area_code                = "",
    geocode                  = geocode_str,
    footnotes                = ""
  )
}

# ---- ES field builder ({{Ficha de entidad subnacional}}) ----------------------

# Field order for the Spanish template (only populated fields are emitted).
ficha_field_order <- c(
  "nombre", "nombre_oficial", "nombre original", "unidad",
  "bandera", "bandera_tama\u00f1o",
  "escudo", "escudo_tama\u00f1o",
  "mapa", "tama\u00f1o_mapa", "pie_mapa",
  "mapa_loc", "pos_etiqueta_loc", "pie_mapa_loc",
  "pa\u00eds",
  "tipo_superior_1", "superior_1",
  "tipo_superior_2", "superior_2",
  "tipo_div_1", "div_1",
  "dirigentes_t\u00edtulos", "dirigentes_nombres",
  "superficie",
  "poblaci\u00f3n", "poblaci\u00f3n_a\u00f1o", "poblaci\u00f3n_notas",
  "densidad",
  "poblaci\u00f3n_urb",
  "campo1_nombre", "campo1",
  "campo2_nombre", "campo2",
  "horario",
  "nombre_c\u00f3digo1", "c\u00f3digo1",
  "nombre_c\u00f3digo2", "c\u00f3digo2",
  "p\u00e1gina web"
)

# The Spanish infobox has no section-comment headers.
ficha_section_headers <- setNames(character(0), character(0))

build_infobox_fields_es <- function(data) {
  muni_name  <- data$muni_name
  department <- data$department
  prov_name  <- data$prov_name
  p          <- phrases[["es"]]

  raw_num <- function(x) if (is.null(x) || length(x) == 0 || is.na(x) || identical(x, "")) "" else as.character(round(as.numeric(x)))

  # Single shield slot: prefer coat of arms; fall back to seal.
  shield_file <- if (nzchar(data$coat_file)) data$coat_file else data$seal_file

  mayor_title <- ""
  mayor_name  <- ""
  if (isTRUE(data$mayor$present)) {
    mayor_title <- if (isTRUE(data$mayor$female)) "Alcaldesa" else "Alcalde"
    name_tc <- spanish_title_case(data$mayor$nombre)
    ref_str <- if (!is.na(data$mayor$page)) oep_ref_with_page(data$mayor$page, "es") else ""
    mayor_name <- paste0(name_tc, " (", data$mayor$sigla, ", 2026)", ref_str)
  }

  eth_str <- if (!is.na(data$pop_total)) get_top_ethnicities(data$id, auto_data, data$pop_total, "es") else ""

  map_caption <- if (nzchar(data$map_file)) {
    sprintf("Ubicaci\u00f3n del municipio de %s en Bolivia", muni_name)
  } else ""
  pushpin_caption <- sprintf("Ubicaci\u00f3n del municipio de %s en Bolivia", muni_name)

  superior_1 <- sprintf("[[%s|%s]]", p$dept_link(department), department)
  superior_2 <- if (!is.na(prov_name)) paste0("[[", prov_link_target(data$id_prov, "es"), "]]") else ""

  fields <- c(
    nombre                 = muni_name,
    unidad                 = "[[Municipios de Bolivia|Municipio]]",
    bandera                = data$flag_file,
    "bandera_tama\u00f1o"  = if (nzchar(data$flag_file)) "150px" else "",
    escudo                 = shield_file,
    "escudo_tama\u00f1o"   = if (nzchar(shield_file)) "100px" else "",
    mapa                   = data$map_file,
    "tama\u00f1o_mapa"     = if (nzchar(data$map_file)) "300px" else "",
    pie_mapa               = map_caption,
    mapa_loc               = "Bolivia",
    pos_etiqueta_loc       = "bottom",
    pie_mapa_loc           = pushpin_caption,
    "pa\u00eds"            = "Bolivia",
    tipo_superior_1        = "[[Departamentos de Bolivia|Departamento]]",
    superior_1             = superior_1,
    tipo_superior_2        = "[[Provincias de Bolivia|Provincia]]",
    superior_2             = superior_2,
    "dirigentes_t\u00edtulos" = mayor_title,
    dirigentes_nombres     = mayor_name,
    superficie             = raw_num(data$area_km2),
    "poblaci\u00f3n"       = raw_num(data$pop_total),
    "poblaci\u00f3n_a\u00f1o" = if (!is.na(data$pop_total)) "2024" else "",
    "poblaci\u00f3n_notas" = if (!is.na(data$pop_total)) ine_pop_ref_for("es") else "",
    densidad               = if (nzchar(data$density_km2)) data$density_km2 else "",
    "poblaci\u00f3n_urb"   = raw_num(data$urban_pop),
    campo1_nombre          = if (!is.na(data$rural_pop)) "Poblaci\u00f3n rural" else "",
    campo1                 = raw_num(data$rural_pop),
    campo2_nombre          = if (nzchar(eth_str)) "Etnias ind\u00edgenas" else "",
    campo2                 = eth_str,
    horario                = "BOT / [[UTC-04:00|UTC\u22124]]",
    "nombre_c\u00f3digo1"  = "C\u00f3digo [[Instituto Nacional de Estad\u00edstica (Bolivia)|INE]]",
    "c\u00f3digo1"         = data$id,
    "nombre_c\u00f3digo2"  = "P-code [[Oficina de Coordinaci\u00f3n de Asuntos Humanitarios|OCHA]]",
    "c\u00f3digo2"         = data$ocha_pcode
  )

  # Emit only fields with real content.
  fields[nzchar(fields)]
}

# ---- Template specs -----------------------------------------------------------

infobox_specs <- list(
  en = list(
    template        = "Infobox settlement",
    field_order     = infobox_field_order,
    section_headers = infobox_section_headers,
    force_blank     = c("pushpin_map", "pushpin_label_position"),
    excluded        = c("Latitude", "Longitude", "commons"),
    build           = build_infobox_fields_en
  ),
  es = list(
    template        = "Ficha de entidad subnacional",
    field_order     = ficha_field_order,
    section_headers = ficha_section_headers,
    force_blank     = character(0),
    excluded        = character(0),
    build           = build_infobox_fields_es
  )
)

# ---- Rendering ----------------------------------------------------------------

# Render a named field vector as template wikitext, in the spec's field order,
# with section-header comments inserted.
render_infobox_wikitext <- function(fields, spec) {
  order           <- spec$field_order
  section_headers <- spec$section_headers

  present <- order[order %in% names(fields)]
  extra   <- setdiff(names(fields), order)
  present <- c(present, extra)

  lines <- character(0)
  for (f in present) {
    if (f %in% names(section_headers)) lines <- c(lines, section_headers[[f]])
    lines <- c(lines, sprintf("|%-24s= %s", f, fields[[f]]))
  }
  paste0("{{", spec$template, "\n", paste(lines, collapse = "\n"), "\n}}")
}

# Fresh scaffold for a municipality with no existing article.
build_infobox <- function(id, lang) {
  data <- compute_infobox_data(id)
  if (is.null(data)) return(NULL)
  spec   <- infobox_specs[[lang]]
  fields <- spec$build(data)
  render_infobox_wikitext(fields, spec)
}

# Merge computed fields with an existing article's verbatim raw field blocks.
# Rule: a non-blank computed value wins (rendered as a clean single line);
# otherwise the existing block's ORIGINAL raw text is carried over byte-for-byte.
render_infobox_merge_lines <- function(new_fields, existing_blocks, spec) {
  order           <- spec$field_order
  section_headers <- spec$section_headers
  force_blank     <- spec$force_blank
  excluded        <- spec$excluded

  trim_one_trailing_newline <- function(x) sub("\n$", "", x)

  existing_by_field <- list()
  for (b in existing_blocks) existing_by_field[[b$field]] <- b$raw_value
  existing_by_field[excluded] <- NULL

  new_fields <- new_fields[setdiff(names(new_fields), excluded)]

  new_names      <- names(new_fields)
  existing_names <- names(existing_by_field)

  field_has_content <- function(f) {
    new_val <- if (f %in% new_names) new_fields[[f]] else NA
    has_new <- !is.na(new_val) && nzchar(trimws(new_val))
    if (has_new) return(TRUE)
    old_raw <- existing_by_field[[f]]
    !is.null(old_raw) && has_real_content(old_raw)
  }

  candidate_names <- union(new_names, existing_names)
  active_names    <- union(force_blank,
                           candidate_names[vapply(candidate_names, field_has_content, logical(1))])
  present_order   <- c(order[order %in% active_names], setdiff(active_names, order))

  lines_out <- character(0)
  origin    <- setNames(character(length(present_order)), present_order)

  append_line <- function(x) {
    is_comment_only <- grepl("^\\s*<!--.*-->\\s*$", x)
    if (is_comment_only && length(lines_out) > 0 &&
        trimws(lines_out[length(lines_out)]) == trimws(x)) {
      return(invisible(NULL))
    }
    lines_out <<- c(lines_out, x)
  }

  for (f in present_order) {
    header <- if (f %in% names(section_headers)) section_headers[[f]] else NULL

    if (f %in% force_blank) {
      if (!is.null(header)) append_line(header)
      append_line(sprintf("|%-24s= ", f))
      origin[[f]] <- "blanked"
      next
    }

    new_val <- if (f %in% new_names) new_fields[[f]] else NA
    has_new <- !is.na(new_val) && nzchar(trimws(new_val))

    if (has_new) {
      if (!is.null(header)) append_line(header)
      append_line(sprintf("|%-24s= %s", f, new_val))
      origin[[f]] <- "new"
      next
    }

    old_raw <- existing_by_field[[f]]
    has_old <- !is.null(old_raw) && has_real_content(old_raw)

    if (has_old) {
      if (!is.null(header)) append_line(header)
      field_line <- sprintf("|%-24s=%s", f, trim_one_trailing_newline(old_raw))
      sub_lines  <- strsplit(field_line, "\n")[[1]]
      for (i in seq_along(sub_lines)) {
        if (i == 1) lines_out <- c(lines_out, sub_lines[i]) else append_line(sub_lines[i])
      }
      origin[[f]] <- "existing"
      next
    }

    if (!is.null(header)) append_line(header)
    append_line(sprintf("|%-24s= ", f))
    origin[[f]] <- "blank"
  }

  list(
    wikitext = paste0("{{", spec$template, "\n", paste(lines_out, collapse = "\n"), "\n}}"),
    origin   = origin
  )
}

# Prose note describing which fields were carried over from the existing article.
describe_preserved_fields <- function(origin, lang = "en") {
  preserved <- names(origin)[origin == "existing"]
  if (lang == "es") {
    if (length(preserved) == 0) {
      return("No se conserv\u00f3 ning\u00fan campo del art\u00edculo existente; todos los campos coincidentes se actualizaron con datos citados.")
    }
    tagged    <- sprintf("`%s`", preserved)
    field_txt <- if (length(tagged) == 1) tagged
      else if (length(tagged) == 2) paste(tagged, collapse = " y ")
      else paste0(paste(tagged[-length(tagged)], collapse = ", "), " y ", tagged[length(tagged)])
    return(sprintf("Importados sin cambios del art\u00edculo existente: %s.", field_txt))
  }
  if (length(preserved) == 0) {
    return("No fields were preserved from the existing article \u2014 every overlapping field was refreshed with new sourced data.")
  }
  tagged    <- sprintf("`%s`", preserved)
  field_txt <- if (length(tagged) == 1) tagged
    else if (length(tagged) == 2) paste(tagged, collapse = " and ")
    else paste0(paste(tagged[-length(tagged)], collapse = ", "), ", and ", tagged[length(tagged)])
  sprintf("Imported unchanged from the existing article: %s.", field_txt)
}

# ---- HTML blocks --------------------------------------------------------------

# Copyable wikitext block (raw <pre>, hidden textarea for the copy button).
ib_wikitext_block <- function(id, label, content) {
  tagList(
    tags$button(
      class = "copy-btn",
      style = "margin-bottom: 6px;",
      onclick = sprintf("copyTableToClipboard('%s', this)", id),
      label
    ),
    tags$pre(
      tags$code(content),
      style = paste(
        "background-color: #f6f8fa; padding: 10px; border-radius: 6px;",
        "overflow-x: auto; font-size: 11px; white-space: pre; margin: 0;"
      )
    ),
    tags$textarea(
      id = id,
      style = "position: absolute; left: -9999px; height: 0; width: 0; overflow: hidden;",
      readonly = TRUE,
      content
    )
  )
}

ib_muni_block <- function(id_muni, muni_name, department, infobox_wikitext,
                          lang = "en", note = NULL, copy_label = "Copy infobox",
                          page_label = "Copy page Wikitext") {
  # Prefer output/bolivia-municipality-wikitext/<lang>/[id].txt; fall back to the
  # legacy flat path for English.
  page_wt_path <- here::here("output", "bolivia-municipality-wikitext", lang,
                             paste0(id_muni, ".txt"))
  if (!file.exists(page_wt_path) && lang == "en") {
    page_wt_path <- here::here("output", "bolivia-municipality-wikitext",
                               paste0(id_muni, ".txt"))
  }
  page_wt <- if (file.exists(page_wt_path)) {
    paste(readLines(page_wt_path, warn = FALSE), collapse = "\n")
  } else NULL

  tagList(
    tags$details(
      tags$summary(
        tags$strong(muni_name),
        tags$span(
          paste0(" \u2014 ", department),
          style = "color: #586069; font-weight: normal;"
        ),
        tags$code(
          paste0(" [", id_muni, "]"),
          style = "font-size: 11px; color: #999; margin-left: 6px;"
        )
      ),
      tags$div(
        style = "margin-top: 8px; font-size: 12px;",
        if (!is.null(note)) tags$p(
          note,
          style = "color: #586069; margin: 0 0 6px 0; font-style: italic;"
        ),
        ib_wikitext_block(
          id      = paste0("infobox_", id_muni),
          label   = copy_label,
          content = infobox_wikitext
        ),
        if (!is.null(page_wt)) tagList(
          tags$div(style = "margin-top: 8px;"),
          tags$button(
            class   = "copy-btn",
            onclick = sprintf("copyTableToClipboard('page_%s_%s', this)", lang, id_muni),
            page_label
          ),
          tags$textarea(
            id       = paste0("page_", lang, "_", id_muni),
            style    = "position: absolute; left: -9999px; height: 0; width: 0; overflow: hidden;",
            readonly = TRUE,
            page_wt
          )
        )
      )
    ),
    tags$hr(style = "border:none; border-top:1px solid #e1e4e8; margin:4px 0;")
  )
}

# ---- Render blocks ------------------------------------------------------------

# Municipalities without an existing article (fresh scaffold).
render_new_blocks <- function(lookup, lang, copy_label = "Copy infobox",
                              page_label = "Copy page Wikitext") {
  ids <- lookup |> arrange(id_muni) |> select(id_muni, muni_anexo, department)
  tagList(pmap(ids, function(id_muni, muni_anexo, department) {
    ib <- build_infobox(id_muni, lang)
    if (is.null(ib)) return(NULL)
    ib_muni_block(id_muni, muni_anexo, department, ib, lang = lang,
                  copy_label = copy_label, page_label = page_label)
  }))
}

# Municipalities with an existing article (merged infobox). Requires
# `existing_infobox_blocks` in the global environment (keyed by id_muni).
render_existing_blocks <- function(lookup, lang, no_infobox_note,
                                   copy_label = "Copy infobox",
                                   page_label = "Copy page Wikitext") {
  spec <- infobox_specs[[lang]]
  ids  <- lookup |> arrange(id_muni) |> select(id_muni, muni_anexo, department)

  tagList(pmap(ids, function(id_muni, muni_anexo, department) {
    existing_blocks <- existing_infobox_blocks[[id_muni]]

    if (is.null(existing_blocks) || length(existing_blocks) == 0) {
      ib <- build_infobox(id_muni, lang)
      if (is.null(ib)) return(NULL)
      return(ib_muni_block(id_muni, muni_anexo, department, ib, lang = lang,
                           note = no_infobox_note, copy_label = copy_label,
                           page_label = page_label))
    }

    data <- compute_infobox_data(id_muni)
    if (is.null(data)) return(NULL)
    new_fields <- spec$build(data)

    merged <- render_infobox_merge_lines(new_fields, existing_blocks, spec)
    note   <- describe_preserved_fields(merged$origin, lang)

    ib_muni_block(id_muni, muni_anexo, department, merged$wikitext, lang = lang,
                  note = note, copy_label = copy_label, page_label = page_label)
  }))
}
