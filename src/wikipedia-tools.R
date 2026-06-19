# wikipedia-tools.R
# Compiled utility functions for working with the MediaWiki API and Wikipedia content.
# Sources: get-wikipedia-text-1.R, add-wikipedia-matches.R, import-ice-detention.qmd
#
# Dependencies: WikipediR, httr, jsonlite, stringr, purrr, tibble, dplyr

library(WikipediR)
library(httr)
library(jsonlite)
library(stringr)
library(purrr)
library(tibble)
library(dplyr)

# ---- Wikitext retrieval (from get-wikipedia-text-1.R) -------------------------

#' Fetch raw wikitext for a named article
get_wikitext_by_name <- function(article_name, lang = "en") {
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")

  params <- list(
    action = "query",
    prop = "revisions",
    titles = article_name,
    rvprop = "content",
    rvslots = "main",
    format = "json"
  )

  res <- query(url = api_url, query = params,
               out_class = "list", clean_response = FALSE)

  tryCatch({
    page_id <- names(res$query$pages)[1]
    content <- res$query$pages[[page_id]]$revisions[[1]]$slots$main$content
    if (is.null(content))
      content <- res$query$pages[[page_id]]$revisions[[1]]$slots$main[["*"]]
    return(content)
  }, error = function(e) return(NULL))
}

#' Fetch raw wikitext for a specific revision
get_wikitext_by_revid <- function(article_name, revision_id, lang = "en") {
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")

  params <- list(
    action = "query",
    prop = "revisions",
    revids = as.character(revision_id),
    rvprop = "content",
    rvslots = "main",
    format = "json"
  )

  res <- query(url = api_url, query = params,
               out_class = "list", clean_response = FALSE)

  tryCatch({
    page_id <- names(res$query$pages)[1]
    content <- res$query$pages[[page_id]]$revisions[[1]]$slots$main$content
    if (is.null(content))
      content <- res$query$pages[[page_id]]$revisions[[1]]$slots$main[["*"]]
    return(content)
  }, error = function(e) return(NULL))
}

#' Fetch wikitext from a full Wikipedia URL (standard or old-revision)
get_wikitext_from_url <- function(url) {
  parsed <- httr::parse_url(url)
  lang <- str_split(parsed$hostname, "\\.")[[1]][1]

  if (!is.null(parsed$query$oldid)) {
    title <- parsed$query$title
    revid <- parsed$query$oldid
    return(get_wikitext_by_revid(title, revid, lang = lang))
  } else {
    title <- str_replace(parsed$path, "wiki/", "")
    return(get_wikitext_by_name(title, lang = lang))
  }
}

# ---- Text extraction (from get-wikipedia-text-1.R) ----------------------------

#' Strip wikitext markup and split into sentence-like fragments (≥5 words)
extract_clean_fragments <- function(wikitext, keep_link_text = FALSE) {
  clean_text <- str_replace_all(wikitext, "(?s)<ref.*?>.*?</ref>", "")
  clean_text <- str_replace_all(clean_text, "<ref.*?/>", "")
  clean_text <- gsub("\\{\\{(?:[^{}]|(?R))*\\}\\}", "", clean_text, perl = TRUE)
  clean_text <- str_replace_all(clean_text, "(?i)\\[\\[(File|Image):.*?\\]\\]", "")

  if (keep_link_text) {
    clean_text <- str_replace_all(clean_text,
      "\\[\\[(?:[^|\\]]*\\|)?([^\\]]+)\\]\\]", "\\1")
  } else {
    clean_text <- str_replace_all(clean_text, "\\[\\[.*?\\]\\]", "")
  }

  clean_text <- str_replace_all(clean_text, "==+.*?==+", "")
  clean_text <- str_replace_all(clean_text, "''+", "")

  fragments <- unlist(str_split(clean_text, "[\\.\\!\\?\\n\\r]"))
  fragments <- str_trim(fragments)
  fragments <- str_replace_all(fragments, "\\s+", " ")
  final_list <- fragments[str_count(fragments, "\\w+") >= 5]
  unique(final_list)
}

# ---- Wikipedia search / match (from add-wikipedia-matches.R) ------------------

#' Search Wikipedia and add match columns to a data frame
add_wikipedia_matches <- function(df, name_col = "name", lang = "en",
                                  delay = 0.5, limit = 5) {
  stopifnot(is.data.frame(df), name_col %in% names(df))
  names_vec <- as.character(df[[name_col]])

  search_one <- function(query_str, lang = "en", limit = 5) {
    if (is.na(query_str) || nzchar(trimws(query_str)) == FALSE) {
      return(list(found = FALSE, title = NA_character_,
                  url = NA_character_, snippet = NA_character_))
    }

    res <- NULL
    try({
      res <- WikipediR::page_search(language = lang, project = "wikipedia",
                                    query = query_str, limit = limit)
    }, silent = TRUE)

    if (is.null(res) || !is.list(res) ||
        is.null(res$query) || is.null(res$query$search)) {
      api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
      resp <- httr::GET(api_url, query = list(
        action = "query", list = "search",
        srsearch = query_str, srlimit = limit, format = "json"
      ))
      if (httr::status_code(resp) >= 400) {
        return(list(found = FALSE, title = NA_character_,
                    url = NA_character_, snippet = NA_character_))
      }
      res <- fromJSON(content(resp, as = "text", encoding = "UTF-8"),
                      simplifyVector = FALSE)
    }

    search_hits <- res$query$search %||% res$search
    if (is.null(search_hits) || length(search_hits) == 0) {
      return(list(found = FALSE, title = NA_character_,
                  url = NA_character_, snippet = NA_character_))
    }

    top <- search_hits[[1]]
    top_title   <- as.character(top$title %||% NA_character_)
    top_snippet <- as.character(top$snippet %||% NA_character_)
    title_url   <- gsub(" ", "_", top_title)
    url <- paste0("https://", lang, ".wikipedia.org/wiki/",
                  utils::URLencode(title_url, reserved = TRUE))
    list(found = TRUE, title = top_title, url = url, snippet = top_snippet)
  }

  results <- vector("list", length(names_vec))
  for (i in seq_along(names_vec)) {
    if (i > 1 && delay > 0) Sys.sleep(delay)
    res_i <- tryCatch(
      search_one(names_vec[i], lang = lang, limit = limit),
      error = function(e) list(found = FALSE, title = NA_character_,
                               url = NA_character_, snippet = NA_character_)
    )
    matched <- FALSE
    if (isTRUE(res_i$found) && !is.na(res_i$title)) {
      norm_q <- tolower(gsub("\\s+", "", names_vec[i]))
      norm_t <- tolower(gsub("\\s+", "", res_i$title))
      matched <- nzchar(norm_q) && nzchar(norm_t) && identical(norm_q, norm_t)
    }
    results[[i]] <- list(
      wikipedia_found   = isTRUE(res_i$found),
      wikipedia_match   = isTRUE(matched),
      wikipedia_title   = if (isTRUE(res_i$found)) res_i$title else NA_character_,
      wikipedia_url     = if (isTRUE(res_i$found)) res_i$url   else NA_character_,
      wikipedia_snippet = if (isTRUE(res_i$found)) res_i$snippet else NA_character_
    )
  }

  results_df <- bind_rows(lapply(results, as_tibble))
  out <- bind_cols(df, results_df)
  out$wikipedia_found <- as.logical(out$wikipedia_found)
  out$wikipedia_match <- as.logical(out$wikipedia_match)
  out
}

# ---- Wikipedia URL helpers ----------------------------------------------------

#' Build a full Wikipedia URL from a page title
#'
#' @param title Page title (spaces are converted to underscores)
#' @param lang  Language code (default "en")
#' @return Character string URL
wikipedia_url_for <- function(title, lang = "en") {
  paste0("https://", lang, ".wikipedia.org/wiki/", gsub(" ", "_", title))
}

# ---- Bolivia municipal council wikitable --------------------------------------

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

  htmltools::HTML(
    knitr::kable(out, format = "html", escape = FALSE,
                 table.attr = 'class="table table-sm table-striped" style="font-size:11px;width:100%;"')
  )
}

#' @describeIn build_council_wikitable_es Spanish MediaWiki council table
build_council_wikitable_es <- function(id_muni_code, data = muni_concejo_comb,
                                       caption = NULL, source = NULL,
                                       source_refs = NULL) {
  .build_council_wikitable(id_muni_code, data, caption, source, source_refs,
                            lang = "es")
}

#' @describeIn build_council_wikitable_en English MediaWiki council table
build_council_wikitable_en <- function(id_muni_code, data = muni_concejo_comb,
                                       caption = NULL, source = NULL,
                                       source_refs = NULL) {
  .build_council_wikitable(id_muni_code, data, caption, source, source_refs,
                            lang = "en")
}

#' @describeIn build_council_kable_es Spanish HTML kable preview
build_council_kable_es <- function(id_muni_code, data = muni_concejo_comb) {
  .build_council_kable(id_muni_code, data, lang = "es")
}

#' @describeIn build_council_kable_en English HTML kable preview
build_council_kable_en <- function(id_muni_code, data = muni_concejo_comb) {
  .build_council_kable(id_muni_code, data, lang = "en")
}

# Backward-compatible aliases
build_council_wikitable <- build_council_wikitable_es
build_council_kable     <- build_council_kable_en

# ---- MediaWiki table formatter (from import-ice-detention.qmd) ----------------

#' Format a data frame as a MediaWiki wikitable string
get_wikitable <- function(df, caption = NULL, class = "wikitable sortable",
                          column_names = NULL, source = NULL, source_refs = NULL) {
  out <- c()
  out <- c(out, paste0('{| class="', class, '"'))
  if (!is.null(caption)) out <- c(out, paste0("|+ ", caption))

  if (is.null(column_names)) column_names <- names(df)
  out <- c(out, paste0("! ", paste(column_names, collapse = " !! ")))

  formatted_rows <- apply(df, 1, function(row) {
    row_clean <- gsub("\\|", "|", as.character(row))
    row_clean[is.na(row_clean)] <- ""
    paste0("| ", paste(row_clean, collapse = " || "))
  })

  # Paste data rows
  out <- c(out, paste0("|-\n", formatted_rows))

  # Append Source row if provided
  if (!is.null(source)) {
    source_text <- paste0("'''Source:''' ", source)

    # Append the reference tag if source_refs is provided
    if (!is.null(source_refs)) {
      source_text <- paste0(source_text, "<ref>", source_refs, "</ref>")
    }

    # Calculate colspan based on the number of columns
    num_cols <- length(column_names)
    out <- c(out, "|-", paste0('|colspan="', num_cols, '"|', source_text))
  }

  out <- c(out, "|}")
  paste(out, collapse = "\n")
}

# ---- Category helpers (new) ---------------------------------------------------

#' Get all members of a Wikipedia category (pages and/or subcategories)
#'
#' @param category Category name (with or without "Category:" prefix)
#' @param type "page", "subcat", or "page|subcat"
#' @param lang Language code
#' @return tibble with columns: pageid, ns, title
get_category_members <- function(category, type = "page", lang = "en") {
  if (!grepl("^Category:", category)) {
    category <- paste0("Category:", category)
  }
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")

  all_members <- list()
  cmcontinue <- NULL


  repeat {
    params <- list(
      action = "query",
      list = "categorymembers",
      cmtitle = category,
      cmtype = type,
      cmlimit = "500",
      format = "json"
    )
    if (!is.null(cmcontinue)) params$cmcontinue <- cmcontinue

    resp <- httr::GET(api_url, query = params,
                      user_agent("R-wikipedia-tools/1.0"))
    json <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                     simplifyVector = FALSE)

    members <- json$query$categorymembers
    if (length(members) > 0) {
      all_members <- c(all_members, members)
    }

    cmcontinue <- json$`continue`$cmcontinue
    if (is.null(cmcontinue)) break
  }

  if (length(all_members) == 0) return(tibble(pageid = integer(),
                                              ns = integer(),
                                              title = character()))
  bind_rows(lapply(all_members, function(m) {
    tibble(pageid = m$pageid, ns = m$ns, title = m$title)
  }))
}

#' Get subcategories of a category
get_subcategories <- function(category, lang = "en") {
  get_category_members(category, type = "subcat", lang = lang)
}

#' Get article pages in a category (non-recursive)
get_category_pages <- function(category, lang = "en") {
  get_category_members(category, type = "page", lang = lang)
}

# ---- Batch page info ----------------------------------------------------------

#' Fetch basic page info + Wikidata QID for a vector of titles
#'
#' @param titles Character vector of page titles
#' @param lang Language code
#' @return tibble with: title, pageid, length, wikidata_qid
get_page_info_batch <- function(titles, lang = "en") {
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
  results <- list()

  # API accepts up to 50 titles at once

  batches <- split(titles, ceiling(seq_along(titles) / 50))

  for (batch in batches) {
    params <- list(
      action = "query",
      prop = "pageprops|info",
      titles = paste(batch, collapse = "|"),
      format = "json",
      ppprop = "wikibase_item"
    )

    resp <- httr::GET(api_url, query = params,
                      user_agent("R-wikipedia-tools/1.0"))
    json <- fromJSON(content(resp, "text", encoding = "UTF-8"),
                     simplifyVector = FALSE)

    pages <- json$query$pages
    for (p in pages) {
      results <- c(results, list(tibble(
        title = p$title %||% NA_character_,
        pageid = p$pageid %||% NA_integer_,
        page_length = p$length %||% NA_integer_,
        wikidata_qid = p$pageprops$wikibase_item %||% NA_character_
      )))
    }
    Sys.sleep(0.2)
  }

  bind_rows(results)
}

# ---- Wikitext parsing helpers --------------------------------------------------

#' Extract the raw wikitext of the main infobox template
#'
#' Isolates the complete infobox template (from {{ to matching }}) from wikitext.
#' Handles nested templates via recursive brace matching.
#' Returns NULL if no infobox found.
#'
#' @param wikitext The raw wikitext string
#' @return A string containing the full infobox template wikitext, or NULL
extract_infobox_wikitext <- function(wikitext) {
  if (is.null(wikitext)) return(NULL)

  # Find the start of an infobox template
  infobox_start <- regexpr("\\{\\{\\s*[Ii]nfobox", wikitext)
  if (infobox_start == -1) return(NULL)

  # Walk forward from start, counting braces to find the matching close
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

#' Extract the main infobox from wikitext as a named list
#'
#' Parses the raw infobox wikitext (obtained via extract_infobox_wikitext)
#' into a named list of field-value pairs.
#' Returns NULL if no infobox found.
extract_infobox <- function(wikitext) {
  if (is.null(wikitext)) return(NULL)

  infobox_text <- extract_infobox_wikitext(wikitext)
  if (is.null(infobox_text)) return(NULL)

  # Parse pipe-delimited parameters
  # Remove the outer {{ and }} and the template name line
  inner <- sub("^\\{\\{\\s*[Ii]nfobox[^\\n|]*", "", infobox_text)
  inner <- sub("\\}\\}$", "", inner)

  # Split on top-level pipes (not inside nested {{ }})
  params <- split_on_top_level_pipes(inner)

  result <- list()
  for (param in params) {
    param <- str_trim(param)
    if (param == "" || !grepl("=", param)) next

    # Split on first "="
    eq_pos <- regexpr("=", param)
    key <- str_trim(substr(param, 1, eq_pos - 1))
    val <- str_trim(substr(param, eq_pos + 1, nchar(param)))

    if (nchar(key) > 0) {
      result[[key]] <- val
    }
  }
  result
}

#' Extract infobox as a named list of cleaned text values
#'
#' @param wikitext The raw wikitext string
#' @return A named character vector of cleaned values, or NULL if no infobox found
extract_infobox_as_list <- function(wikitext) {
  infobox_raw <- extract_infobox(wikitext)
  if (is.null(infobox_raw)) return(NULL)

  # Clean all values and remove those that become empty/NA
  cleaned <- map_chr(infobox_raw, clean_infobox_value)

  # Keep only non-empty/non-NA elements
  keep <- !is.na(cleaned) & cleaned != ""

  if (!any(keep)) return(NULL)

  # Return as a named character vector
  as.character(cleaned[keep][names(cleaned)[keep]])
}

#' Split a string on "|" characters that are not inside {{ }}
split_on_top_level_pipes <- function(text) {
  parts <- character()
  depth <- 0
  current <- ""

  i <- 1
  while (i <= nchar(text)) {
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
    # Also handle [[ ]] nesting
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

#' Clean wikitext markup from an infobox value
#'
#' Strips wikilinks, templates, HTML tags, and refs, leaving plain text.
clean_infobox_value <- function(val) {
  if (is.null(val) || is.na(val)) return(NA_character_)
  # Remove <ref>...</ref> and <ref />
  val <- str_replace_all(val, "(?s)<ref[^>]*>.*?</ref>", "")
  val <- str_replace_all(val, "<ref[^/]*/\\s*>", "")
  # Remove HTML tags
  val <- str_replace_all(val, "<[^>]+>", "")
  # Resolve wikilinks: [[Target|Display]] -> Display, [[Link]] -> Link
  val <- str_replace_all(val, "\\[\\[(?:[^|\\]]*\\|)?([^\\]]+)\\]\\]", "\\1")
  # Resolve common simple templates before stripping all templates:
  # {{flag|X}} -> X, {{flagicon|X}} -> X, {{convert|N|unit}} -> N unit
  val <- str_replace_all(val, "\\{\\{(?:flag|flagicon|flagcountry)\\|([^{}|]+)(?:\\|[^{}]*)??\\}\\}", "\\1")
  val <- str_replace_all(val, "\\{\\{convert\\|([^{}|]+)\\|([^{}|]+)(?:\\|[^{}]*)?\\}\\}", "\\1 \\2")
  # {{nowrap|X}} -> X
  val <- str_replace_all(val, "\\{\\{nowrap\\|([^{}]+)\\}\\}", "\\1")
  # Remove remaining templates (nested)
  val <- gsub("\\{\\{(?:[^{}]|(?R))*\\}\\}", "", val, perl = TRUE)
  # Remove external links [url text] -> text
  val <- str_replace_all(val, "\\[https?://\\S+\\s+([^\\]]+)\\]", "\\1")
  val <- str_replace_all(val, "\\[https?://\\S+\\]", "")
  # Clean whitespace
  val <- str_trim(str_squish(val))
  if (nchar(val) == 0) NA_character_ else val
}

#' Count citation templates in wikitext
count_citations <- function(wikitext) {
  if (is.null(wikitext)) return(0L)
  # Count {{cite ...}} and {{Citation}} templates
  cite_pattern <- "\\{\\{\\s*[Cc]it(e|ation)\\s"
  length(str_extract_all(wikitext, cite_pattern)[[1]])
}

#' Count total <ref> tags in wikitext (includes non-templated refs)
count_refs <- function(wikitext) {
  if (is.null(wikitext)) return(0L)
  # Count opening <ref> tags (both <ref> and <ref name=...>)
  ref_pattern <- "<ref[\\s>]"
  # Also count self-closing <ref name="..." />
  self_closing <- "<ref\\s[^>]*/>"
  length(str_extract_all(wikitext, ref_pattern)[[1]]) +
    length(str_extract_all(wikitext, self_closing)[[1]])
}

#' Extract census years referenced in wikitext
#'
#' Looks for patterns like "census of YYYY", "YYYY census", "CPV YYYY",
#' and "Censo YYYY" (common in Bolivian municipality articles).
extract_census_years <- function(wikitext) {
  if (is.null(wikitext)) return(character(0))
  patterns <- c(
    "(?i)\\b(\\d{4})\\s+census\\b",
    "(?i)\\b(\\d{4})\\s+\\w+\\s+census\\b",
    "(?i)\\bcensus\\s+(?:of\\s+)?(\\d{4})\\b",
    "(?i)\\bcenso\\s+(?:de\\s+)?(\\d{4})\\b",
    "(?i)\\bCPV\\s+(\\d{4})\\b",
    "(?i)\\bcensus_year\\s*=\\s*(\\d{4})",
    "(?i)\\bpopulation_as_of\\s*=\\s*(\\d{4})"
  )
  years <- character(0)
  for (pat in patterns) {
    matches <- str_match_all(wikitext, pat)[[1]]
    if (nrow(matches) > 0) {
      # The year is in the first capture group
      extracted <- matches[, 2]
      years <- c(years, extracted)
    }
  }
  sort(unique(years[!is.na(years) & nchar(years) == 4]))
}

# ---- Caching helpers -----------------------------------------------------------

#' Cache wikitext to a local file; load from cache if available
#'
#' @param title Page title
#' @param cache_dir Directory path for cached files
#' @param lang Language code
#' @return Wikitext string (NULL if page doesn't exist)
cache_wikitext <- function(title, cache_dir, lang = "en") {
  # Sanitise filename: replace / and other problematic chars
  safe_name <- gsub("[/:*?\"<>|]", "_", title)
  cache_path <- file.path(cache_dir, paste0(safe_name, ".txt"))

  if (file.exists(cache_path)) {
    return(paste(readLines(cache_path, warn = FALSE), collapse = "\n"))
  }

  wikitext <- get_wikitext_by_name(title, lang = lang)
  if (!is.null(wikitext)) {
    writeLines(wikitext, cache_path)
  }
  wikitext
}
