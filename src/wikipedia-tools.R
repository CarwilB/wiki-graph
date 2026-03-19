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

# ---- MediaWiki table formatter (from import-ice-detention.qmd) ----------------

#' Format a data frame as a MediaWiki wikitable string
get_wikitable <- function(df, caption = NULL, class = "wikitable sortable",
                          column_names = NULL) {
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
  out <- c(out, paste0("|-\n", formatted_rows))
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

#' Extract the main infobox from wikitext as a named list
#'
#' Handles nested templates via recursive brace matching.
#' Returns NULL if no infobox found.
extract_infobox <- function(wikitext) {
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
  infobox_text <- substr(txt, 1, end_pos)

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
