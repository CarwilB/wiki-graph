# muni-article-functions.R
# Language-aware article-composition engine for the Bolivia municipality
# generators. Every function takes a `lang` argument ("en" or "es"); prose comes
# from muni-phrases.R (`phrases`), citations from muni-references.R (`refs`),
# labels/section headers from muni-i18n.R (`label()`), and translated data values
# from the transcats tables. Bolivia table builders live in bolivia-builders.R.
#
# The functions read several lookups from the global environment (built in the
# qmd setup chunk): muni_lookup, prov_lookup, prov_link_lookup,
# muni_province_context, alcaldes, concejal_expected, muni_concejal_ioc,
# roster_pages, wd_images, census_pop, lang_data, auto_data, pop_muni,
# pop_age_muni, and generate_poverty_service_tables().

library(dplyr)
library(purrr)
library(htmltools)
library(english)
library(glue)
library(stringr)

source(here::here("src", "bolivia-builders.R"))   # builders + muni-i18n (label/translate)
source(here::here("src", "muni-phrases.R"))        # phrases[[lang]]
source(here::here("src", "muni-references.R"))     # refs[[lang]], ref_with_page()

# ---- Generic string helpers ---------------------------------------------------

# Build a full Wikipedia URL from a page title (for in-page HTML previews).
wikipedia_url_for <- function(title, lang = "en") {
  paste0("https://", lang, ".wikipedia.org/wiki/", gsub(" ", "_", title))
}

# Title case that keeps a non-initial "de" lowercase.
title_case_preserve_de <- function(x) {
  words  <- strsplit(x, " ")[[1]]
  titled <- stringr::str_to_title(words)
  for (i in seq_along(titled)) {
    if (i > 1 && tolower(titled[i]) == "de") titled[i] <- "de"
  }
  paste(titled, collapse = " ")
}

# Spanish-aware title case: keeps particles (de, del, la, las, el, los, y)
# lowercase except when they are the first word.
spanish_title_case <- function(x) {
  x <- trimws(x)
  titled    <- stringr::str_to_title(x)
  particles <- c("De", "Del", "La", "Las", "El", "Los", "Y")
  pattern   <- paste0("(?<=\\s)(", paste(particles, collapse = "|"), ")\\b")
  stringr::str_replace_all(titled, pattern, tolower)
}

# ---- Link-target helpers ------------------------------------------------------

# Province wikilink target. English follows the "<Name> Province" convention;
# Spanish uses the actual es.wikipedia article title from prov_link_lookup,
# piping to hide any disambiguation parenthetical in the displayed text.
prov_link_target <- function(id_prov, lang) {
  if (lang == "en") {
    paste0(prov_lookup$province_anexo[prov_lookup$id_prov == id_prov], " Province")
  } else {
    es <- prov_link_lookup$es_link[prov_link_lookup$id_prov == id_prov]
    if (length(es) == 0 || is.na(es)) {
      prov <- prov_lookup$province_anexo[prov_lookup$id_prov == id_prov]
      return(paste0("Provincia de ", prov))
    }
    if (grepl(" \\(", es)) paste0(es, "|", sub(" \\(.*\\)$", "", es)) else es
  }
}

# ---- In-page display helpers --------------------------------------------------

# Process wikitext for HTML preview: <ref> -> numbered superscript, [[links]] ->
# anchors, everything else HTML-escaped. Returns list(html, refs).
process_for_display <- function(text, ref_offset = 0L, lang = "en") {
  refs <- character(0)

  processed <- stringr::str_replace_all(text, "<ref>(.*?)</ref>", function(m) {
    vapply(m, function(single_m) {
      n    <- length(refs) + 1L
      refs <<- c(refs, stringr::str_match(single_m, "<ref>(.*?)</ref>")[1, 2])
      sprintf("REFSUP_%d_END", n + ref_offset)
    }, character(1), USE.NAMES = FALSE)
  })

  escaped <- htmltools::htmlEscape(processed)

  escaped <- stringr::str_replace_all(
    escaped, "\\[\\[([^|\\]]+)\\|([^\\]]+)\\]\\]",
    function(m) {
      p <- stringr::str_match(m, "\\[\\[([^|\\]]+)\\|([^\\]]+)\\]\\]")
      paste0('<a href="', wikipedia_url_for(p[, 2], lang), '" target="_blank">', p[, 3], "</a>")
    }
  )
  escaped <- stringr::str_replace_all(
    escaped, "\\[\\[([^\\]]+)\\]\\]",
    function(m) {
      tgt <- stringr::str_match(m, "\\[\\[([^\\]]+)\\]\\]")[, 2]
      paste0('<a href="', wikipedia_url_for(tgt, lang), '" target="_blank">', tgt, "</a>")
    }
  )

  for (i in seq_along(refs)) {
    n_abs   <- i + ref_offset
    escaped <- stringr::str_replace_all(
      escaped, sprintf("REFSUP_%d_END", n_abs),
      sprintf('<sup style="color:#06c;font-size:9px;">[ref%d]</sup>', n_abs)
    )
  }

  list(html = escaped, refs = refs)
}

refs_footnotes <- function(refs, ref_offset = 0L) {
  if (length(refs) == 0) return(NULL)
  tags$div(
    style = "margin-top:5px; padding-top:4px; border-top:1px solid #e1e4e8;",
    lapply(seq_along(refs), function(i) {
      tags$p(
        tags$b(paste0("ref", i + ref_offset, ":")), " ", refs[[i]],
        style = "font-size:10px; font-family:monospace; margin:1px 0; color:#555; word-break:break-all;"
      )
    })
  )
}

wikitext_block <- function(id, label, content, lang = "en") {
  disp <- process_for_display(content, lang = lang)
  tagList(
    tags$button(
      class = "copy-btn", style = "margin-bottom:6px;",
      onclick = sprintf("copyTableToClipboard('%s', this)", id), label
    ),
    tags$pre(
      HTML(disp$html),
      style = paste(
        "background-color:#f6f8fa; padding:10px; border-radius:6px;",
        "overflow-x:auto; font-size:11px; white-space:pre; margin:0;"
      )
    ),
    refs_footnotes(disp$refs),
    tags$textarea(
      id = id,
      style = "position:absolute; left:-9999px; height:0; width:0; overflow:hidden;",
      readonly = TRUE, content
    )
  )
}

# ---- Prose composition --------------------------------------------------------

# Population-rank sentence (national top-2, department top-2, or province rank-1
# for 3+ municipality provinces). Returns NULL when none apply.
compose_pop_rank_sentence <- function(id_muni, muni_pc, lang) {
  row <- muni_pc[muni_pc$id_muni == id_muni, ]
  p   <- phrases[[lang]]
  wrap_ref <- function(s) paste0(s, "<ref>", refs[[lang]]$ine_pop, "</ref>")

  if (!is.na(row$nat_pop_rank) && row$nat_pop_rank <= 2) {
    return(wrap_ref(p$pop_rank_national(row$nat_pop_rank)))
  }
  if (!is.na(row$dept_pop_rank) && row$dept_pop_rank <= 2) {
    return(wrap_ref(p$pop_rank_dept(row$dept_pop_rank, p$dept_link(row$department))))
  }
  if (!is.na(row$pop_rank) && row$pop_rank == 1 && row$n_prov_munis >= 3) {
    id_prov <- stringr::str_sub(id_muni, 1, 4)
    return(wrap_ref(p$pop_rank_prov(prov_link_target(id_prov, lang))))
  }
  NULL
}

# Province-context sentence for 1- or 2-municipality provinces; NULL otherwise.
compose_province_context <- function(id_muni, muni_pc, prov_lkp, lang) {
  row       <- muni_pc[muni_pc$id_muni == id_muni, ]
  id_prov   <- stringr::str_sub(id_muni, 1, 4)
  muni_name <- row$muni_anexo
  prov_link <- prov_link_target(id_prov, lang)
  p         <- phrases[[lang]]
  n         <- row$n_prov_munis

  if (n == 1) return(as.character(p$prov_context_only(muni_name, prov_link)))
  if (n == 2 && !is.na(row$area_rank) && !is.na(row$pop_rank)) {
    return(as.character(p$prov_context_two(
      muni_name, prov_link, row$area_rank == 1, row$pop_rank == 1
    )))
  }
  NULL
}

# Full lead sentence: location + optional rank + optional province context.
compose_lead_sentence <- function(id_muni, muni_lkp, prov_lkp, lang) {
  muni_row <- muni_lkp[muni_lkp$id_muni == id_muni, ]
  id_prov  <- substr(id_muni, 1, 4)
  prov_row <- prov_lkp[prov_lkp$id_prov == id_prov, ]
  muni_num <- as.integer(substr(id_muni, 5, 6))
  p        <- phrases[[lang]]

  lead <- as.character(p$lead(
    muni      = muni_row$muni_anexo,
    ordinal   = p$ordinal(muni_num),
    prov_link = prov_link_target(id_prov, lang),
    dept_link = p$dept_link(prov_row$department)
  ))

  pop_rank <- compose_pop_rank_sentence(id_muni, muni_province_context, lang)
  context  <- compose_province_context(id_muni, muni_province_context, prov_lkp, lang)

  parts <- c(lead, pop_rank, context)
  paste(parts[!sapply(parts, is.null)], collapse = " ")
}

# Mayor sentence. Gender is taken from alcaldes$autoridad ("ALCALDESA" = female).
compose_mayor_sentence <- function(id_muni, muni_name, alcaldes_data,
                                    page_number, lang) {
  row    <- alcaldes_data[alcaldes_data$id_muni == id_muni, ]
  nombre <- spanish_title_case(row$nombre[1])
  female <- grepl("ALCALDESA", row$autoridad[1], ignore.case = TRUE)
  ref    <- paste0("<ref>", ref_with_page(refs[[lang]]$oep_report, page_number, lang), "</ref>")
  paste0(as.character(phrases[[lang]]$mayor(muni_name, nombre, female)), ref)
}

# Council intro: one sentence (non-IOC) or two (IOC).
compose_council_sentence <- function(id_muni, muni_name, concejal_exp,
                                       ioc_data, lang) {
  row <- concejal_exp[concejal_exp$id_muni == id_muni, ]
  p   <- phrases[[lang]]

  range_phrase <- p$council_range(row$es_capital, row$pop_2024)
  n_word       <- p$number_word(row$sillas_esperadas)
  s1 <- paste0(as.character(p$council_seats(muni_name, n_word, range_phrase)),
               "<ref>", refs[[lang]]$council_law_news, "</ref>")

  ioc_rows <- ioc_data[ioc_data$id_muni == id_muni, ]
  if (nrow(ioc_rows) > 0) {
    pueblo <- spanish_title_case(ioc_rows$pueblo[1])
    paste(s1, as.character(p$council_ioc(pueblo)))
  } else {
    s1
  }
}

# ---- Table builders (population + pyramid) ------------------------------------

# Horizontal "Population in Recent Censuses" wikitable. 1992 column included only
# for municipalities whose province was not subdivided since 2002.
build_census_pop_wikitable <- function(id, census_data, lang) {
  row <- census_data[census_data$id_muni == id, ]
  if (nrow(row) == 0) return(NULL)
  row <- row[1, ]

  fmt      <- function(x) formatC(x, format = "d", big.mark = ",")
  has_1992 <- !is.na(row$pop_1992)

  ref_main <- paste0("<ref>", refs[[lang]]$census_pop, "</ref>")
  ref_1992 <- if (has_1992) paste0("<ref>", refs[[lang]]$census_1992, "</ref>") else ""

  years <- if (has_1992)
    paste0("! 1992", ref_1992, " !! 2001 !! 2012 !! 2024", ref_main)
  else
    paste0("! 2001 !! 2012 !! 2024", ref_main)

  vals <- if (has_1992)
    paste0("|| ", fmt(row$pop_1992), " || ", fmt(row$pop_2001),
           " || ", fmt(row$pop_2012), "\n|| ", fmt(row$pop_2024))
  else
    paste0("|| ", fmt(row$pop_2001), " || ", fmt(row$pop_2012),
           "\n|| ", fmt(row$pop_2024))

  paste0(
    '{| class="wikitable"\n',
    "|+ ", label("cap_censuspop", lang), "\n",
    "|-\n", years, "\n",
    "|-\n", vals, "\n",
    "|}"
  )
}

# Population pyramid template with 5-year age bins from the 2024 census.
# English: {{Population pyramid}} with |m (male) and |f (female) parameters
# Spanish: {{Pirámide de población}} with |m (male/varón) and |v (female/mujer) parameters
build_pop_pyramid <- function(id, pop_data, lang) {
  d <- pop_data |> filter(ine_code == id, area == "Total", age_group != "Total")
  if (nrow(d) == 0) return(NULL)

  total_pop <- pop_data |>
    filter(ine_code == id, area == "Total", age_group == "Total") |>
    pull(pop_2024_total)

  bin_map <- c(
    "0 a 4" = 0, "5 a 9" = 5, "10 a 14" = 10, "15 a 19" = 15,
    "20 a 24" = 20, "25 a 29" = 25, "30 a 34" = 30, "35 a 39" = 35,
    "40 a 44" = 40, "45 a 49" = 45, "50 a 54" = 50, "55 a 59" = 55,
    "60 a 64" = 60, "65 a 69" = 65, "70 a 74" = 70, "75 a 79" = 75,
    "80 a 84" = 80, "85 a 89" = 85, "90 a 94" = 85, "95 o m\u00e1s" = 85
  )

  d <- d |>
    mutate(bin = bin_map[age_group]) |>
    summarise(male = sum(pop_2024_male, na.rm = TRUE),
              female = sum(pop_2024_female, na.rm = TRUE), .by = bin) |>
    mutate(m_pct = round(male / total_pop * 100, 1),
           f_pct = round(female / total_pop * 100, 1)) |>
    arrange(bin)

  # Language-specific template and parameter names
  if (lang == "es") {
    template_name <- "Pir\u00e1mide de poblaci\u00f3n"
    title_param <- "t\u00edtulo"
    year_param <- "a\u00f1o"
    male_param <- "m"      # varón (male)
    female_param <- "v"    # mujer/femenino (female)
    fmax_param <- "vmax"
  } else {
    template_name <- "Population pyramid"
    title_param <- "title"
    year_param <- "year"
    male_param <- "m"      # male
    female_param <- "f"    # female
    fmax_param <- "fmax"
  }

  m_parts <- paste0("|", male_param, d$bin, "=", d$m_pct, collapse = " ")
  f_parts <- paste0("|", female_param, d$bin, "=", d$f_pct, collapse = " ")
  mmax <- ceiling(max(d$m_pct) * 2) / 2
  fmax <- ceiling(max(d$f_pct) * 2) / 2

  paste0(
    "{{", template_name, "\n",
    "|", title_param, "=\n",
    "|", year_param, "=2024<ref>", refs[[lang]]$census_pop, "</ref>\n",
    m_parts, " ",
    f_parts, "\n",
    "|mmax=", mmax, " |", fmax_param, "=", fmax, "\n",
    "}}"
  )
}

# ---- Communities --------------------------------------------------------------

# Community list (built once at source time from the 2013 INE classification).
.ine_geog_2013 <- readxl::read_excel(here::here("data", "CLASIF_UB_GEOG_COMUNIDAD.xlsx")) |>
  rename(department = DEPARTAMENTO, province = PROVINCIA,
         municipality = MUNICIPIO, community = 8) |>
  mutate(cod.prov = paste0(DEP, PRO), cod.mun = paste0(DEP, PRO, MUN),
         cod.com = Codigo) |>
  rename(cod.dep = DEP)

community_list_df <- .ine_geog_2013 |>
  mutate(community = sapply(community, spanish_title_case)) |>
  group_by(cod.mun) |>
  summarise(
    n_communities = n_distinct(community),
    communities   = paste0("* ", paste0(community, collapse = "\n* ")),
    communities_html = paste0(
      "<ul style='column-count: 3; column-width: 18em; margin: 0; padding-left: 20px;'>",
      paste0("<li>", community, "</li>", collapse = ""), "</ul>")
  ) |>
  ungroup()

compose_community_list_wikitext <- function(id_muni, lang) {
  row <- community_list_df |> filter(cod.mun == id_muni)
  if (nrow(row) == 0) return(NULL)

  p          <- phrases[[lang]]
  header     <- paste0("== ", label("sec_communities", lang), " ==\n")
  header_h3  <- paste0("<h3>", label("sec_communities", lang), "</h3>")
  ref        <- paste0("<ref>", refs[[lang]]$geo_2013, "</ref>")

  # Colquechaca / San Pedro de Macha special case (2019 split).
  if (id_muni %in% c("050405", "050401")) {
    row   <- community_list_df |> filter(cod.mun == "050401")
    intro <- as.character(p$communities_intro_colquechaca())
    return(list(
      wikitext = paste0(header, intro, ref, "\n",
                        "{{div col|colwidth=18em}}\n", row$communities,
                        "\n{{div col end}}\n\n"),
      html = paste0(header_h3, "<p>", intro, "</p>", row$communities_html)
    ))
  }

  intro <- as.character(p$communities_intro())
  list(
    wikitext = paste0(header, intro, ref, "\n",
                      "{{div col|colwidth=18em}}\n", row$communities,
                      "\n{{div col end}}\n\n"),
    html = paste0(header_h3, "<p>", intro, "</p>", row$communities_html)
  )
}

# ---- Per-municipality block ---------------------------------------------------

muni_block <- function(id_muni, muni_name, department, concejo, lang) {
  out_dir <- here::here("output", "bolivia-municipality-wikitext", lang)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  page <- roster_pages$page[roster_pages$id_muni == id_muni]
  src  <- ref_with_page(refs[[lang]]$oep_report, page, lang)

  # Lead
  lead_wt   <- compose_lead_sentence(id_muni, muni_lookup, prov_lookup, lang)
  lead_disp <- process_for_display(lead_wt, lang = lang)

  # Government
  mayor_wt   <- compose_mayor_sentence(id_muni, muni_name, alcaldes, page, lang)
  council_wt <- compose_council_sentence(id_muni, muni_name, concejal_expected,
                                          muni_concejal_ioc, lang)
  intro_wt   <- paste0(mayor_wt, "\n\n", council_wt)
  mayor_disp    <- process_for_display(mayor_wt, ref_offset = 0L, lang = lang)
  council_disp  <- process_for_display(council_wt,
                                        ref_offset = length(mayor_disp$refs), lang = lang)
  all_intro_refs <- c(mayor_disp$refs, council_disp$refs)

  # Wikitext sections
  council_wikitable <- do.call(paste0("build_council_wikitable_", lang),
                               list(id_muni, data = concejo,
                                    source = refs[[lang]]$source_label, source_refs = src))
  autoident_wt <- do.call(paste0("build_autoident_wikitable_", lang),
                          list(id_muni, auto_data, pop_muni,
                               source = label("src_census2024", lang),
                               source_refs = refs[[lang]]$ine_identity))
  lang_wt <- do.call(paste0("build_language_wikitable_", lang),
                     list(id_muni, lang_data, pop_muni,
                          source = label("src_census2024", lang),
                          source_refs = refs[[lang]]$ine_lang))
  census_pop_wt <- build_census_pop_wikitable(id_muni, census_pop, lang)
  pyramid_wt    <- build_pop_pyramid(id_muni, pop_age_muni, lang)
  comm          <- compose_community_list_wikitext(id_muni, lang)
  reflist_wt    <- paste0("== ", label("sec_references", lang), " ==\n{{Reflist}}\n\n")

  commons_cat_row <- wd_images |> filter(ine_code == id_muni) |> slice(1)
  commons_cat_val <- if (nrow(commons_cat_row) > 0 && !is.na(commons_cat_row$commons_cat))
    commons_cat_row$commons_cat else " "
  commons_cat_wt <- sprintf("{{Commons category|%s}}", commons_cat_val)

  poverty_tables <- generate_poverty_service_tables(
    ine_code = id_muni, muni_display_name = muni_name, dept_display_name = department
  )
  poverty_wt <- poverty_tables$wikitable

  full_page_wt <- paste0(
    lead_wt, "\n\n",
    "==", label("sec_government", lang), "==\n",
    mayor_wt, "\n\n", council_wt, "\n\n", council_wikitable, "\n\n",
    "==", label("sec_population", lang), "==\n",
    if (!is.null(census_pop_wt)) paste0(census_pop_wt, "\n\n") else "",
    if (!is.null(pyramid_wt))    paste0(pyramid_wt,    "\n\n") else "",
    "==", label("sec_languages_identity", lang), "==\n",
    autoident_wt, "\n\n", lang_wt,
    if (!is.null(comm)) paste0("\n\n", comm$wikitext) else "",
    poverty_wt, "\n\n",
    reflist_wt, "\n",
    "==", label("sec_external_links", lang), "==\n",
    commons_cat_wt, "\n"
  )
  writeLines(full_page_wt, file.path(out_dir, paste0(id_muni, ".txt")))

  sfx <- function(prefix) paste0(prefix, "_", lang, "_", id_muni)

  tagList(
    tags$details(
      tags$summary(
        tags$strong(muni_name),
        tags$span(paste0(" \u2014 ", department),
                  style = "color: #586069; font-weight: normal;"),
        tags$code(paste0(" [", id_muni, "]"),
                  style = "font-size: 11px; color: #999; margin-left: 6px;")
      ),
      # Lead
      tags$div(
        style = "margin-top:8px; margin-bottom:10px;",
        tags$button(class = "copy-btn", style = "margin-bottom:6px;",
                    onclick = sprintf("copyTableToClipboard('%s', this)", sfx("lead")),
                    label("btn_lead", lang)),
        tags$p(HTML(lead_disp$html), style = "font-size:12px; margin:4px 0 0; color:#333;"),
        tags$textarea(id = sfx("lead"),
                      style = "position:absolute; left:-9999px; height:0; width:0; overflow:hidden;",
                      readonly = TRUE, lead_wt)
      ),
      # Government
      tags$div(
        style = "margin-top:8px; margin-bottom:10px;",
        tags$button(class = "copy-btn", style = "margin-bottom:6px;",
                    onclick = sprintf("copyTableToClipboard('%s', this)", sfx("intro")),
                    label("btn_government", lang)),
        tags$p(HTML(mayor_disp$html),  style = "font-size:12px; margin:4px 0 4px; color:#333;"),
        tags$p(HTML(council_disp$html), style = "font-size:12px; margin:0 0 0;    color:#333;"),
        refs_footnotes(all_intro_refs),
        tags$textarea(id = sfx("intro"),
                      style = "position:absolute; left:-9999px; height:0; width:0; overflow:hidden;",
                      readonly = TRUE, intro_wt)
      ),
      # Council: kable | wikitable
      tags$div(
        style = "display:flex; gap:14px; align-items:flex-start; font-size:12px; margin-bottom:8px;",
        tags$div(style = "flex:1 1 0; min-width:0; overflow-x:auto;",
                 do.call(paste0("build_council_kable_", lang), list(id_muni, data = concejo))),
        tags$div(style = "flex:1 1 0; min-width:0;",
                 wikitext_block(sfx("concejo"), label("btn_council", lang),
                                council_wikitable, lang))
      ),
      # Communities
      if (!is.null(comm)) {
        tags$div(
          style = "margin-top:8px; margin-bottom:10px;",
          tags$button(class = "copy-btn", style = "margin-bottom:6px;",
                      onclick = sprintf("copyTableToClipboard('%s', this)", sfx("communities")),
                      label("btn_communities", lang)),
          HTML(comm$html),
          tags$textarea(id = sfx("communities"),
                        style = "position:absolute; left:-9999px; height:0; width:0; overflow:hidden;",
                        readonly = TRUE, comm$wikitext)
        )
      },
      # Identity: kable | wikitable
      tags$div(
        style = "display:flex; gap:14px; align-items:flex-start; font-size:12px; margin-bottom:8px;",
        tags$div(style = "flex:1 1 0; min-width:0; overflow-x:auto;",
                 do.call(paste0("build_autoident_kable_", lang), list(id_muni, auto_data, pop_muni))),
        tags$div(style = "flex:1 1 0; min-width:0;",
                 wikitext_block(sfx("autoident"), label("btn_identity", lang), autoident_wt, lang))
      ),
      # Language: kable | wikitable
      tags$div(
        style = "display:flex; gap:14px; align-items:flex-start; font-size:12px; margin-bottom:8px;",
        tags$div(style = "flex:1 1 0; min-width:0; overflow-x:auto;",
                 do.call(paste0("build_language_kable_", lang), list(id_muni, lang_data, pop_muni))),
        tags$div(style = "flex:1 1 0; min-width:0;",
                 wikitext_block(sfx("lang"), label("btn_language", lang), lang_wt, lang))
      ),
      # Census population
      if (!is.null(census_pop_wt)) {
        tags$div(style = "font-size:12px;",
                 wikitext_block(sfx("censuspop"), label("btn_population", lang), census_pop_wt, lang))
      },
      # Pyramid
      if (!is.null(pyramid_wt)) {
        tags$div(style = "font-size:12px;",
                 wikitext_block(sfx("pyramid"), label("btn_pyramid", lang), pyramid_wt, lang))
      },
      # Poverty
      tags$div(
        style = "margin-top:16px; padding-top:12px; border-top:1px solid #e1e4e8;",
        tags$h4(label("sec_poverty", lang), style = "margin:0 0 8px 0;"),
        tags$div(
          style = "display:flex; gap:14px; align-items:flex-start; font-size:12px;",
          tags$div(style = "flex:1 1 0; min-width:0; overflow-x:auto;",
                   HTML(as.character(poverty_tables$kable))),
          tags$div(style = "flex:1 1 0; min-width:0;",
                   wikitext_block(sfx("poverty"), label("btn_poverty", lang),
                                  poverty_tables$wikitable, lang))
        )
      )
    ),
    tags$hr(style = "border:none; border-top:1px solid #e1e4e8; margin:4px 0;")
  )
}

render_muni_blocks <- function(lookup, concejo, lang) {
  ids <- lookup |>
    filter(id_muni %in% unique(concejo$id_muni)) |>
    arrange(id_muni) |>
    select(id_muni, muni_anexo, department)

  tagList(pmap(ids, function(id_muni, muni_anexo, department) {
    muni_block(id_muni, muni_anexo, department, concejo, lang)
  }))
}
