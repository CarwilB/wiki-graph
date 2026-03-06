# wiki-refs-to-zotero.R
# Extract references from a Wikipedia article and import into Zotero.
#
# Handles two Wikipedia citation styles:
#   1. Inline <ref>{{Cite book|...}}</ref> tags
#   2. Author-date {{sfn}} with full entries in Sources/Works Cited sections
#   3. Mixed (both in the same article)

library(WikipediR)
library(tidyverse)
library(stringi)
library(httr2)
library(c2z)

# =============================================================================
# 1. Fetch wikitext
# =============================================================================

fetch_wikitext <- function(page_name, language = "en", project = "wikipedia") {
  page <- page_content(language, project, page_name = page_name, as_wikitext = TRUE)
  page$parse$wikitext$`*`
}

# =============================================================================
# 2. Template parser
# =============================================================================

# Find matching closing braces for a template starting at position `start`
# (start points to the first `{` of `{{`).
find_template_end <- function(text, start) {
  n <- nchar(text)
  depth <- 0
  i <- start
  while (i <= n) {
    ch <- substr(text, i, i)
    ch2 <- substr(text, i, i + 1)
    if (ch2 == "{{") {
      depth <- depth + 1
      i <- i + 2
    } else if (ch2 == "}}") {
      depth <- depth - 1
      if (depth == 0) return(i + 1) # position of char after `}}`
      i <- i + 2
    } else {
      i <- i + 1
    }
  }
  NA_integer_ # unmatched
}

# Extract all top-level templates matching a pattern from wikitext.
# Returns a character vector of full template strings (including {{ }}).
extract_templates <- function(text, pattern = "\\{\\{\\s*[Cc]ite\\s") {
  matches <- gregexpr(pattern, text, perl = TRUE, ignore.case = TRUE)[[1]]
  if (matches[1] == -1) return(character(0))

  # For each match, find the `{{` that starts just before
  templates <- character(length(matches))
  for (idx in seq_along(matches)) {
    pos <- matches[idx]
    # Walk back to find the opening `{{`
    start <- pos
    end_pos <- find_template_end(text, start)
    if (is.na(end_pos)) next
    templates[idx] <- substr(text, start, end_pos)
  }
  templates[nzchar(templates)]
}

# Parse a single template string into a named list.
# Handles nested templates by treating them as opaque strings.
parse_template_params <- function(template_str) {
  # Strip outer {{ and }}
  inner <- sub("^\\{\\{\\s*", "", template_str)
  inner <- sub("\\s*\\}\\}$", "", inner)

  # The template name is everything before the first `|`
  # But we need to handle nested templates in default/unnamed params
  # Strategy: split on `|` only at depth 0

  chars <- strsplit(inner, "")[[1]]
  n <- length(chars)
  brace_depth  <- 0L  # depth inside {{ }}
  bracket_depth <- 0L  # depth inside [[ ]]
  parts <- character(0)
  current <- ""

  for (i in seq_len(n)) {
    ch <- chars[i]
    ch_prev <- if (i > 1) chars[i - 1] else ""
    ch_next <- if (i < n) chars[i + 1] else ""

    if      (ch == "{" && ch_next == "{") { brace_depth  <- brace_depth  + 1L; current <- paste0(current, ch)
    } else if (ch == "{" && ch_prev == "{") {                                    current <- paste0(current, ch)
    } else if (ch == "}" && ch_next == "}") { brace_depth  <- brace_depth  - 1L; current <- paste0(current, ch)
    } else if (ch == "}" && ch_prev == "}") {                                    current <- paste0(current, ch)
    } else if (ch == "[" && ch_next == "[") { bracket_depth <- bracket_depth + 1L; current <- paste0(current, ch)
    } else if (ch == "[" && ch_prev == "[") {                                    current <- paste0(current, ch)
    } else if (ch == "]" && ch_next == "]") { bracket_depth <- bracket_depth - 1L; current <- paste0(current, ch)
    } else if (ch == "]" && ch_prev == "]") {                                    current <- paste0(current, ch)
    } else if (ch == "|" && brace_depth == 0L && bracket_depth == 0L) {
      parts <- c(parts, current)
      current <- ""
    } else {
      current <- paste0(current, ch)
    }
  }
  parts <- c(parts, current)

  template_name <- trimws(parts[1])
  params <- parts[-1]

  # Parse key=value pairs
  result <- list(.template = tolower(template_name))
  unnamed_idx <- 1
  for (p in params) {
    p <- trimws(p)
    if (p == "") next
    eq_pos <- regexpr("=", p, fixed = TRUE)
    if (eq_pos > 0) {
      key <- trimws(substr(p, 1, eq_pos - 1))
      val <- trimws(substr(p, eq_pos + 1, nchar(p)))
      result[[tolower(key)]] <- val
    } else {
      result[[paste0(".unnamed_", unnamed_idx)]] <- p
      unnamed_idx <- unnamed_idx + 1
    }
  }
  result
}

# =============================================================================
# 3. Extract all citation templates from wikitext
# =============================================================================

# Citation template names we recognize
cite_patterns <- c(
  "cite book", "cite journal", "cite web", "cite news",
  "cite encyclopedia", "cite odnb", "cite magazine", "cite thesis",
  "cite conference", "cite report", "cite press release",
  "cite av media", "cite podcast", "cite speech",
  "harvc"
)

extract_all_citations <- function(wikitext) {
  # Pattern matches {{Cite book, {{cite journal, {{harvc, etc.
  # Case insensitive
  pattern <- paste0(
    "\\{\\{\\s*(",
    paste(gsub(" ", "\\\\s+", cite_patterns), collapse = "|"),
    ")\\s*\\|"
  )
  extract_templates(wikitext, pattern)
}

# Also extract bare <ref> tags that DON'T contain a cite template
extract_bare_refs <- function(wikitext) {
  # Find all <ref...>...</ref> blocks
  ref_pattern <- "<ref[^>]*>(.*?)</ref>"
  refs <- str_match_all(wikitext, regex(ref_pattern, dotall = TRUE))[[1]]
  if (nrow(refs) == 0) return(character(0))

  ref_contents <- refs[, 2]
  # Filter to those that don't contain a {{cite or {{Cite template
  is_bare <- !str_detect(ref_contents, regex("\\{\\{\\s*cite\\s", ignore_case = TRUE))
  ref_contents[is_bare & nzchar(trimws(ref_contents))]
}

# =============================================================================
# 4. Map parsed templates → reference tibble
# =============================================================================

# Strip Wikipedia markup from a string value:
#   [[Link|Display text]] → Display text
#   [[Display text]]      → Display text
#   ''italic''            → italic
#   {{Template|id|text}}  → text  (inline display templates)
# Returns NA_character_ for NULL or empty input.
clean_wiki <- function(x) {
  if (is.null(x) || !nzchar(trimws(x))) return(NA_character_)
  x <- str_replace_all(x, "\\{\\{!\\}\\}", "|")          # {{!}} → literal pipe
  x <- str_replace_all(x, "\\{\\{=\\}\\}", "=")          # {{=}} → literal equals
  # Inline display templates: {{Name|arg1|display text|...}} → display text (2nd positional arg)
  # If no 2nd positional arg, try 1st; if none, strip entirely.
  x <- str_replace_all(x,
    "\\{\\{[^|{}]+\\|[^|{}]+\\|([^|{}]+)(?:\\|[^{}]*)?\\}\\}",
    "\\1")
  x <- str_replace_all(x,
    "\\{\\{[^|{}]+\\|([^|{}]+)\\}\\}",
    "\\1")
  x <- str_replace_all(x, "\\{\\{[^{}]*\\}\\}", "")      # remaining bare templates
  x <- str_replace_all(x, "\\[\\[([^\\]|]+\\|)?([^\\]]+)\\]\\]", "\\2")  # wikilinks
  x <- str_replace_all(x, "''", "")                       # italic markup
  trimws(x)
}

# Normalize a template name to a Zotero itemType
template_to_itemtype <- function(tpl_name) {
  tpl <- tolower(trimws(tpl_name))
  case_when(
    str_detect(tpl, "^(cite )?book$") ~ "book",
    str_detect(tpl, "harvc")          ~ "bookSection",
    str_detect(tpl, "journal")        ~ "journalArticle",
    str_detect(tpl, "web")            ~ "webpage",
    str_detect(tpl, "news")           ~ "newspaperArticle",
    str_detect(tpl, "encyclopedia")   ~ "encyclopediaArticle",
    str_detect(tpl, "odnb")           ~ "encyclopediaArticle",
    str_detect(tpl, "magazine")       ~ "magazineArticle",
    str_detect(tpl, "thesis")         ~ "thesis",
    str_detect(tpl, "conference")     ~ "conferencePaper",
    str_detect(tpl, "report")         ~ "report",
    str_detect(tpl, "press release")  ~ "newspaperArticle",
    str_detect(tpl, "av media")       ~ "videoRecording",
    TRUE                              ~ "document"
  )
}

# Extract authors from parsed template params.
# Wikipedia uses last/first, last1/first1, last2/first2, ... or author=
extract_authors <- function(params) {
  authors <- tibble(creatorType = character(), lastName = character(), firstName = character())

  # Check for author/author1, last/first, last1/first1, ...
  # Also handle editor, translator
  for (role_prefix in c("", "editor", "translator")) {
    creator_type <- if (role_prefix == "") "author" else role_prefix

    # Wikipedia naming: last/first or last1/first1 etc.
    param_last <- if (role_prefix == "") "last" else paste0(role_prefix, "-last")
    param_first <- if (role_prefix == "") "first" else paste0(role_prefix, "-first")

    for (i in c("", as.character(1:10))) {
      lkey <- paste0(param_last, i)
      fkey <- paste0(param_first, i)

      # Also try lastN/firstN without hyphen for editors
      if (role_prefix != "" && is.null(params[[lkey]])) {
        lkey2 <- paste0(role_prefix, "-last", i)
        fkey2 <- paste0(role_prefix, "-first", i)
        if (!is.null(params[[lkey2]])) {
          lkey <- lkey2
          fkey <- fkey2
        }
      }

      last_val <- params[[lkey]]
      first_val <- params[[fkey]] %||% ""

      if (!is.null(last_val) && nzchar(last_val)) {
        authors <- bind_rows(authors, tibble(
          creatorType = creator_type,
          lastName  = clean_wiki(last_val)  %||% "",
          firstName = clean_wiki(first_val) %||% ""
        ))
      }
    }

    # Handle combined "author" param (single string)
    author_key <- if (role_prefix == "") "author" else role_prefix
    if (is.null(params[["last"]]) && is.null(params[["last1"]]) && !is.null(params[[author_key]])) {
      # Don't override if we already got last/first
      if (nrow(authors) == 0 || creator_type != "author") {
        val <- clean_wiki(params[[author_key]]) %||% params[[author_key]]
        # Try to split "Last, First" or just use as lastName
        if (str_detect(val, ",")) {
          parts <- str_split(val, ",\\s*", n = 2)[[1]]
          authors <- bind_rows(authors, tibble(
            creatorType = creator_type, lastName = parts[1], firstName = parts[2] %||% ""
          ))
        } else {
          authors <- bind_rows(authors, tibble(
            creatorType = creator_type, lastName = val, firstName = ""
          ))
        }
      }
    }
  }

  # Handle "others" param (translators, illustrators, etc.)
  if (!is.null(params[["others"]]) && nzchar(params[["others"]])) {
    authors <- bind_rows(authors, tibble(
      creatorType = "contributor",
      lastName = params[["others"]],
      firstName = ""
    ))
  }

  if (nrow(authors) == 0) {
    authors <- tibble(creatorType = "author", lastName = "", firstName = "")
  }
  authors
}

# Convert a parsed template to a one-row reference tibble
template_to_ref <- function(params) {
  item_type <- template_to_itemtype(params$.template)
  authors <- extract_authors(params)

  # Extract year from date field
  extract_year <- function(params) {
    yr <- params[["year"]] %||% params[["date"]]
    if (is.null(yr)) return(NA_character_)
    # Try to extract a 4-digit year
    m <- str_extract(yr, "\\d{4}")
    if (!is.na(m)) return(m)
    yr
  }

  # Helper: coalesce that treats NA as missing (unlike %||%)
  na_coalesce <- function(...) {
    args <- list(...)
    for (a in args) if (!is.na(a)) return(a)
    NA_character_
  }

  # Title: prefer title, fall back to script-title (for Japanese etc.)
  title <- na_coalesce(clean_wiki(params[["title"]]), clean_wiki(params[["script-title"]]))
  # For script-title, strip the language prefix like "ja:"
  if (!is.na(title)) title <- str_remove(title, "^[a-z]{2}:")

  # Trans-title: use if present
  trans_title <- clean_wiki(params[["trans-title"]])
  if (!is.na(trans_title) && !is.na(title)) {
    title <- paste0(title, " [", trans_title, "]")
  }

  # Chapter (for harvc / bookSection)
  chapter <- na_coalesce(clean_wiki(params[["chapter"]]), clean_wiki(params[["script-chapter"]]))
  if (!is.na(chapter)) chapter <- str_remove(chapter, "^[a-z]{2}:")

  # For bookSection (harvc), use chapter as the title if title is missing
  if (item_type == "bookSection" && is.na(title) && !is.na(chapter)) {
    title <- chapter
    chapter <- NA_character_
  }

  tibble(
    itemType         = item_type,
    title            = title %||% NA_character_,
    creators         = list(authors),
    date             = params[["date"]] %||% params[["year"]] %||% NA_character_,
    year             = extract_year(params),
    publisher        = clean_wiki(params[["publisher"]]) %||% NA_character_,
    place            = clean_wiki(params[["location"]]) %||% NA_character_,
    publicationTitle = clean_wiki(params[["journal"]] %||% params[["website"]] %||%
                                    params[["work"]] %||% params[["newspaper"]]) %||% NA_character_,
    volume           = params[["volume"]] %||% NA_character_,
    issue            = params[["issue"]] %||% NA_character_,
    pages            = params[["pages"]] %||% params[["page"]] %||%
                         params[["at"]] %||% NA_character_,
    ISBN             = params[["isbn"]] %||% NA_character_,
    ISSN             = params[["issn"]] %||% NA_character_,
    DOI              = params[["doi"]] %||% NA_character_,
    url              = params[["url"]] %||% NA_character_,
    language         = params[["language"]] %||% NA_character_,
    edition          = params[["edition"]] %||% NA_character_,
    series           = clean_wiki(params[["series"]]) %||% NA_character_,
    accessDate       = params[["access-date"]] %||% NA_character_,
    bookTitle        = if (item_type == "bookSection") {
                         # harvc uses "in" param to reference parent book
                         clean_wiki(params[["in"]]) %||% NA_character_
                       } else NA_character_,
    chapter          = chapter %||% NA_character_,
    # Raw template for debugging
    .template_name   = params$.template,
    .raw_template    = NA_character_
  )
}

# =============================================================================
# 5. Build reference data frame from wikitext
# =============================================================================

extract_refs_from_wikitext <- function(wikitext) {
  # Extract all citation templates
  cite_strings <- extract_all_citations(wikitext)

  if (length(cite_strings) == 0) {
    warning("No citation templates found in wikitext.")
    return(tibble())
  }

  # Parse each template
  parsed <- map(cite_strings, parse_template_params)

  # Convert to tibble rows
  refs <- map2_dfr(parsed, cite_strings, function(params, raw) {
    ref <- template_to_ref(params)
    ref$.raw_template <- raw
    ref
  })

  # Extract bare refs (non-template)
  bare <- extract_bare_refs(wikitext)
  if (length(bare) > 0) {
    bare_df <- tibble(
      itemType = "document",
      title = map_chr(bare, clean_wiki),
      creators = map(bare, ~ tibble(creatorType = "author", lastName = "", firstName = "")),
      date = NA_character_, year = NA_character_, publisher = NA_character_,
      place = NA_character_, publicationTitle = NA_character_,
      volume = NA_character_, issue = NA_character_, pages = NA_character_,
      ISBN = NA_character_, ISSN = NA_character_, DOI = NA_character_,
      url = NA_character_, language = NA_character_, edition = NA_character_,
      series = NA_character_, accessDate = NA_character_,
      bookTitle = NA_character_, chapter = NA_character_,
      .template_name = "bare_ref", .raw_template = bare
    )
    refs <- bind_rows(refs, bare_df)
  }

  # Add human-readable first_author for visual inspection (not used downstream)
  refs |>
    mutate(
      first_author = map_chr(creators, function(cr) {
        if (nrow(cr) == 0) return(NA_character_)
        last  <- cr$lastName[1]  %||% ""
        first <- cr$firstName[1] %||% ""
        if (!nzchar(last) && !nzchar(first)) return(NA_character_)
        if (nzchar(first)) paste0(last, ", ", first) else last
      }),
      .before = creators
    )
}

# =============================================================================
# 6. Deduplication
# =============================================================================

dedup_key <- function(title, year, last1) {
  # Normalize: lowercase, strip diacritics, strip punctuation
  norm <- function(x) {
    x <- tolower(x %||% "")
    x <- stri_trans_general(x, "Latin-ASCII")
    x <- str_replace_all(x, "[^a-z0-9 ]", "")
    trimws(x)
  }
  paste(norm(last1), norm(year), norm(title), sep = "|")
}

deduplicate_refs <- function(refs) {
  refs <- refs |>
    mutate(
      .last1 = map_chr(creators, ~ .x$lastName[1]),
      .dedup_key = dedup_key(title, year, .last1)
    )

  # Group by dedup key, keep first occurrence, count citations
  refs |>
    group_by(.dedup_key) |>
    mutate(n_citations = n()) |>
    slice(1) |>
    ungroup()
}

# =============================================================================
# 7. RIS export  (uses enriched refs if enrichment has been run)
# =============================================================================

itemtype_to_ris <- function(it) {
  switch(it,
    "book"                = "BOOK",
    "bookSection"         = "CHAP",
    "journalArticle"      = "JOUR",
    "webpage"             = "ELEC",
    "newspaperArticle"    = "NEWS",
    "encyclopediaArticle" = "ENCYC",
    "magazineArticle"     = "MGZN",
    "thesis"              = "THES",
    "conferencePaper"     = "CONF",
    "report"              = "RPRT",
    "videoRecording"      = "VIDEO",
    "document"            = "GEN",
    "GEN"
  )
}

ref_to_ris_lines <- function(row) {
  lines <- character(0)
  add <- function(tag, val) {
    if (!is.na(val) && nzchar(val)) {
      lines <<- c(lines, paste0(tag, "  - ", val))
    }
  }

  add("TY", itemtype_to_ris(row$itemType))
  add("TI", row$title)

  # Authors
  for (i in seq_len(nrow(row$creators[[1]]))) {
    cr <- row$creators[[1]][i, ]
    name <- if (nzchar(cr$firstName)) {
      paste0(cr$lastName, ", ", cr$firstName)
    } else {
      cr$lastName
    }
    tag <- switch(cr$creatorType,
      "editor" = "ED",
      "translator" = "A3",
      "AU"
    )
    if (nzchar(name)) add(tag, name)
  }

  add("PY", row$year)
  add("DA", row$date)
  add("PB", row$publisher)
  add("CY", row$place)
  add("JO", row$publicationTitle)
  add("T2", row$publicationTitle)
  add("VL", row$volume)
  add("IS", row$issue)

  # Pages: try to split "123–456" into SP/EP
  if (!is.na(row$pages)) {
    pg <- str_split(row$pages, "[–—-]", n = 2)[[1]]
    add("SP", trimws(pg[1]))
    if (length(pg) > 1) add("EP", trimws(pg[2]))
  }

  add("SN", row$ISBN)
  add("SN", row$ISSN)
  add("DO", row$DOI)
  add("UR", row$url)
  add("LA", row$language)
  add("ET", row$edition)
  add("T3", row$series)
  add("Y2", row$accessDate)

  if (row$itemType == "bookSection") {
    add("BT", row$bookTitle)
    add("T2", row$chapter)
  }

  lines <- c(lines, "ER  - ")
  lines
}

export_ris <- function(refs, file) {
  all_lines <- character(0)
  for (i in seq_len(nrow(refs))) {
    all_lines <- c(all_lines, ref_to_ris_lines(refs[i, ]), "")
  }
  writeLines(all_lines, file)
  message("Wrote ", nrow(refs), " references to ", file)
}

# =============================================================================
# 8. DOI / ISBN enrichment via c2z
# =============================================================================

# Overlay fields from a c2z $data row onto our ref row, preferring c2z values
# for non-empty fields and falling back to wiki-parsed values.
.merge_enriched <- function(ref_row, enriched_row) {
  prefer <- function(new_val, old_val) {
    new_str <- if (is.null(new_val) || length(new_val) == 0) NA_character_
               else as.character(new_val[[1]])
    old_str <- if (is.null(old_val) || length(old_val) == 0) NA_character_
               else as.character(old_val[[1]])
    if (!is.na(new_str) && nzchar(new_str)) new_str else old_str
  }

  # Use [[ rather than $ to silently return NULL for columns absent from enriched_row
  # (item-type-specific columns like publicationTitle don't exist on book rows, etc.)
  ecol <- function(col) enriched_row[[col]]

  # creators: prefer enriched if it has at least one real author
  new_creators <- ecol("creators")[[1]]
  old_creators <- ref_row$creators[[1]]
  use_creators <- if (!is.null(new_creators) && nrow(new_creators) > 0 &&
                      any(nzchar(new_creators$lastName %||% ""))) {
    new_creators
  } else {
    old_creators
  }

  ref_row$itemType         <- prefer(ecol("itemType"),         ref_row$itemType)
  ref_row$title            <- prefer(ecol("title"),            ref_row$title)
  ref_row$creators         <- list(use_creators)
  ref_row$date             <- prefer(ecol("date"),             ref_row$date)
  ref_row$year             <- prefer(
    list(str_extract(as.character(ecol("date") %||% ""), "\\d{4}")),
    ref_row$year
  )
  ref_row$publisher        <- prefer(ecol("publisher"),        ref_row$publisher)
  ref_row$place            <- prefer(ecol("place"),            ref_row$place)
  ref_row$publicationTitle <- prefer(ecol("publicationTitle"), ref_row$publicationTitle)
  ref_row$volume           <- prefer(ecol("volume"),           ref_row$volume)
  ref_row$issue            <- prefer(ecol("issue"),            ref_row$issue)
  ref_row$ISBN             <- prefer(ecol("ISBN"),             ref_row$ISBN)
  ref_row$ISSN             <- prefer(ecol("ISSN"),             ref_row$ISSN)
  ref_row$DOI              <- prefer(ecol("DOI"),              ref_row$DOI)
  ref_row$url              <- prefer(ecol("url"),              ref_row$url)
  ref_row$language         <- prefer(ecol("language"),         ref_row$language)
  ref_row$edition          <- prefer(ecol("edition"),          ref_row$edition)
  ref_row$accessDate       <- prefer(ecol("accessDate"),       ref_row$accessDate)

  ref_row
}

# Try to enrich a single reference row via DOI or ISBN lookup.
# Returns the row with `.enrich_status` set to "doi", "isbn", "skipped", or "failed".
enrich_ref <- function(ref_row) {
  doi  <- ref_row$DOI
  isbn <- ref_row$ISBN

  # Skip if neither identifier is present
  if ((is.na(doi) || !nzchar(doi)) && (is.na(isbn) || !nzchar(isbn))) {
    ref_row$.enrich_status <- "skipped"
    return(ref_row)
  }

  # Try DOI first
  if (!is.na(doi) && nzchar(doi)) {
    result <- tryCatch(
      ZoteroDoi(doi, silent = TRUE),
      error = function(e) NULL
    )
    if (!is.null(result) && !is.null(result[["data"]]) && nrow(result[["data"]]) > 0) {
      ref_row <- .merge_enriched(ref_row, result[["data"]][1, ])
      ref_row$.enrich_status <- "doi"
      return(ref_row)
    }
  }

  # Fall back to ISBN
  if (!is.na(isbn) && nzchar(isbn)) {
    result <- tryCatch(
      ZoteroIsbn(isbn, silent = TRUE),
      error = function(e) NULL
    )
    if (!is.null(result) && !is.null(result[["data"]]) && nrow(result[["data"]]) > 0) {
      ref_row <- .merge_enriched(ref_row, result[["data"]][1, ])
      ref_row$.enrich_status <- "isbn"
      return(ref_row)
    }
  }

  ref_row$.enrich_status <- "failed"
  ref_row
}

# Enrich all refs in a tibble. Returns the tibble with an added `.enrich_status` column.
enrich_refs <- function(refs) {
  n_doi  <- sum(!is.na(refs$DOI)  & nzchar(refs$DOI  %||% ""), na.rm = TRUE)
  n_isbn <- sum(!is.na(refs$ISBN) & nzchar(refs$ISBN %||% ""), na.rm = TRUE)
  message("Enriching via c2z: ", n_doi, " DOI(s), ", n_isbn, " ISBN(s) to look up")

  enriched <- map(
    seq_len(nrow(refs)),
    \(i) enrich_ref(refs[i, ]),
    .progress = list(
      type  = "iterator",
      name  = "Enriching references",
      clear = FALSE
    )
  )

  result <- bind_rows(enriched)

  tab <- table(result$.enrich_status)
  get_n <- function(k) if (!is.na(tab[k])) tab[k] else 0L
  message(sprintf(
    "Enrichment: %d via DOI, %d via ISBN, %d failed, %d skipped (no identifier)",
    get_n("doi"), get_n("isbn"), get_n("failed"), get_n("skipped")
  ))

  result
}

# =============================================================================
# 10. Zotero import
# =============================================================================

# Parse access dates to ISO 8601 (YYYY-MM-DD) as required by the Zotero API.
.format_access_date <- function(x) {
  if (is.na(x) || !nzchar(x)) return("")
  fmts <- c("%d %B %Y", "%B %d, %Y", "%Y-%m-%d", "%Y/%m/%d")
  for (fmt in fmts) {
    d <- tryCatch(as.Date(x, format = fmt), error = function(e) NA)
    if (!is.na(d)) return(format(d, "%Y-%m-%d"))
  }
  "" # can't parse — omit rather than send a bad value
}

# Build a one-row Zotero item tibble with only the fields valid for that type.
# Field names follow the Zotero API schema strictly.
#
# Key mappings that differ from our internal schema:
#   book/thesis      : pages  → numPages
#   webpage          : publicationTitle → websiteTitle
#   encyclopediaArticle : publicationTitle → encyclopediaTitle
#   thesis           : publisher → university
ref_to_zotero_item <- function(row) {
  acc <- .format_access_date(row$accessDate %||% "")

  # Fields present on every item type
  base <- list(
    key        = ZoteroKey(),
    version    = 0L,
    itemType   = row$itemType,
    title      = row$title    %||% "",
    creators   = row$creators,
    date       = row$date     %||% "",
    language   = row$language %||% "",
    url        = row$url      %||% "",
    accessDate = acc
  )

  # Type-specific fields (only include what the API allows for each type)
  extra <- switch(row$itemType,

    book = list(
      publisher = row$publisher %||% "",
      place     = row$place     %||% "",
      ISBN      = row$ISBN      %||% "",
      ISSN      = row$ISSN      %||% "",   # added: now valid for books
      DOI       = row$DOI       %||% "",   # added: now valid for books
      edition   = row$edition   %||% "",
      series    = row$series    %||% "",
      volume    = row$volume    %||% "",
      numPages  = row$pages     %||% ""    # pages → numPages for books
    ),

    bookSection = list(
      bookTitle = row$bookTitle %||% "",
      publisher = row$publisher %||% "",
      place     = row$place     %||% "",
      ISBN      = row$ISBN      %||% "",
      ISSN      = row$ISSN      %||% "",   # added
      DOI       = row$DOI       %||% "",   # added
      pages     = row$pages     %||% "",
      edition   = row$edition   %||% "",
      series    = row$series    %||% "",
      volume    = row$volume    %||% ""
    ),

    journalArticle = list(
      publicationTitle = row$publicationTitle %||% "",
      volume           = row$volume           %||% "",
      issue            = row$issue            %||% "",
      pages            = row$pages            %||% "",
      DOI              = row$DOI              %||% "",
      ISSN             = row$ISSN             %||% "",
      series           = row$series           %||% ""
    ),

    webpage = list(
      websiteTitle = row$publicationTitle %||% "",  # publicationTitle → websiteTitle
      publisher    = row$publisher        %||% "",  # added
      place        = row$place            %||% "",  # added
      DOI          = row$DOI              %||% ""   # added
    ),

    newspaperArticle = list(
      publicationTitle = row$publicationTitle %||% "",
      publisher        = row$publisher        %||% "",  # added
      place            = row$place            %||% "",
      volume           = row$volume           %||% "",  # added
      issue            = row$issue            %||% "",  # added
      edition          = row$edition          %||% "",  # added
      pages            = row$pages            %||% "",
      ISSN             = row$ISSN             %||% "",
      DOI              = row$DOI              %||% ""   # added
    ),

    encyclopediaArticle = list(
      encyclopediaTitle = row$publicationTitle %||% "",  # publicationTitle → encyclopediaTitle
      publisher         = row$publisher        %||% "",
      place             = row$place            %||% "",
      ISBN              = row$ISBN             %||% "",
      DOI               = row$DOI              %||% "",  # added
      pages             = row$pages            %||% "",
      edition           = row$edition          %||% "",
      series            = row$series           %||% "",
      volume            = row$volume           %||% ""
    ),

    magazineArticle = list(
      publicationTitle = row$publicationTitle %||% "",
      publisher        = row$publisher        %||% "",  # added
      place            = row$place            %||% "",  # added
      volume           = row$volume           %||% "",
      issue            = row$issue            %||% "",
      pages            = row$pages            %||% "",
      ISSN             = row$ISSN             %||% "",
      DOI              = row$DOI              %||% ""   # added
    ),

    thesis = list(
      university = row$publisher %||% "",   # publisher → university for theses
      place      = row$place     %||% "",
      numPages   = row$pages     %||% "",
      DOI        = row$DOI       %||% "",   # added
      ISBN       = row$ISBN      %||% "",   # added
      ISSN       = row$ISSN      %||% "",   # added
      series     = row$series    %||% ""    # added
    ),

    conferencePaper = list(
      proceedingsTitle = row$publicationTitle %||% "",  # publicationTitle → proceedingsTitle
      publisher        = row$publisher        %||% "",
      place            = row$place            %||% "",
      pages            = row$pages            %||% "",
      volume           = row$volume           %||% "",
      DOI              = row$DOI              %||% "",
      ISBN             = row$ISBN             %||% "",
      ISSN             = row$ISSN             %||% "",  # added
      series           = row$series           %||% ""
    ),

    report = list(
      institution = row$publisher %||% "",  # publisher → institution for reports
      place       = row$place     %||% "",
      pages       = row$pages     %||% "",
      DOI         = row$DOI       %||% "",  # added
      ISBN        = row$ISBN      %||% "",  # added
      ISSN        = row$ISSN      %||% ""   # added
    ),

    # document and any unrecognised type
    list(
      publisher = row$publisher %||% "",
      place     = row$place     %||% "",  # added
      DOI       = row$DOI       %||% ""   # added
    )
  )

  as_tibble(c(base, extra))
}

refs_to_zotero_items <- function(refs) {
  map_dfr(seq_len(nrow(refs)), function(i) ref_to_zotero_item(refs[i, ]))
}

import_to_zotero <- function(refs, collection_name,
                              user_id = NULL, api_key = NULL,
                              user = TRUE, group_id = NULL,
                              dry_run = FALSE) {
  # Set up Zotero connection
  id <- if (user) user_id else group_id
  zotero <- Zotero(user = user, id = id, api = api_key)

  # Generate the collection key upfront so we can embed it in each item
  collection_key <- ZoteroKey()

  zotero$collections <- tibble(
    key              = collection_key,
    version          = 0L,
    name             = collection_name,
    parentCollection = "FALSE"
  )

  # Convert refs to Zotero items and assign them all to the new collection.
  # The Zotero API requires each item to carry the key(s) of its collection(s).
  zotero$items <- refs_to_zotero_items(refs) |>
    mutate(collections = map(seq_len(n()), \(i) collection_key))

  if (dry_run) {
    message("DRY RUN: Would post ", nrow(zotero$items), " items to collection '",
            collection_name, "'")
    return(zotero)
  }

  # Post to Zotero
  result <- ZoteroPost(
    zotero,
    post.collections = TRUE,
    post.items = TRUE,
    post.attachments = FALSE
  )

  result
}

# =============================================================================
# 11. Standalone Zotero post (use after a dry run)
# =============================================================================

#' Post a refs tibble to Zotero without re-running the full pipeline.
#'
#' Use this when you have already built and inspected a refs tibble (e.g. from
#' a previous `wiki_refs_pipeline()` call with `dry_run = TRUE`) and want to
#' push it to Zotero without fetching Wikipedia again.
#'
#' @param refs A refs tibble as returned by `wiki_refs_pipeline()`.
#' @param collection_name Name for the new Zotero collection.
#' @param user_id Zotero user ID.
#' @param api_key Zotero API key.
#' @param user If FALSE, treat `user_id` as a group ID. Default TRUE.
#' @return The c2z zotero list returned by `ZoteroPost()`.
post_refs_to_zotero <- function(refs, collection_name,
                                 user_id = NULL, api_key = NULL,
                                 user = TRUE) {
  import_to_zotero(refs, collection_name,
                   user_id  = user_id,
                   api_key  = api_key,
                   user     = user,
                   dry_run  = FALSE)
}

# =============================================================================
# 12. Fetch citation keys from Zotero
# =============================================================================

#' Look up Zotero item keys for each row in a refs tibble.
#'
#' Queries the Zotero REST API directly (via httr2) to fetch top-level items
#' from the library or a specific collection, then matches each row back using
#' DOI → ISBN → normalised title + year (in that priority order). Handles
#' pagination automatically and retries on 429 / 503 responses, honouring the
#' Zotero `Backoff` header.
#'
#' The result is the original tibble with two new columns appended:
#'   - `zotero_key`   : Zotero item key (e.g. "A3D88AEA"), NA if unmatched
#'   - `zotero_match` : how the match was made ("doi", "isbn", "title_year",
#'                      or "unmatched")
#'
#' @param refs A refs tibble (as returned by `wiki_refs_pipeline()` or
#'   `extract_refs_from_wikitext()`).
#' @param user_id Zotero user ID (character or numeric).
#' @param api_key Zotero API key.
#' @param user Logical; if FALSE treat `user_id` as a group ID. Default TRUE.
#' @param collection_key Optional Zotero collection key (8-char string). If
#'   supplied, only items in that collection are fetched; otherwise the whole
#'   library is searched.
#' @return `refs` with `zotero_key` and `zotero_match` columns added.
fetch_zotero_keys <- function(refs,
                               user_id = NULL, api_key = NULL,
                               user = TRUE, collection_key = NULL) {
  entity    <- if (user) "users" else "groups"
  item_path <- if (!is.null(collection_key))
    paste0("collections/", collection_key, "/items/top")
  else
    "items/top"
  endpoint <- paste0(
    "https://api.zotero.org/", entity, "/", user_id, "/", item_path
  )

  # Base request template: auth headers + retry logic
  base_req <- request(endpoint) |>
    req_headers(
      "Zotero-API-Key"     = api_key,
      "Zotero-API-Version" = "3"
    ) |>
    req_retry(
      max_tries    = 4,
      is_transient = \(r) resp_status(r) %in% c(429, 503),
      # Honour Zotero's Backoff header; fall back to exponential backoff
      after        = \(r) {
        val <- resp_header(r, "Backoff") %||% resp_header(r, "Retry-After")
        if (!is.null(val)) as.numeric(val) else NULL
      }
    )

  # Fetch one page (start = 0-indexed offset)
  fetch_page <- function(start) {
    base_req |>
      req_url_query(limit = 100, start = start) |>
      req_perform() |>
      resp_body_json(simplifyVector = FALSE)
  }

  message(
    "Fetching Zotero items",
    if (!is.null(collection_key)) paste0(" (collection: ", collection_key, ")")
    else " (full library)", "..."
  )

  # First page — also read Total-Results to know if we need to paginate
  first_resp <- base_req |>
    req_url_query(limit = 100, start = 0) |>
    req_perform()

  total <- as.integer(resp_header(first_resp, "Total-Results") %||% "0")
  raw   <- resp_body_json(first_resp, simplifyVector = FALSE)

  if (total > 100) {
    offsets <- seq(100, total - 1, by = 100)
    more    <- map(offsets, fetch_page)
    raw     <- c(raw, list_flatten(more))
  }

  message("Fetched ", length(raw), " item(s).")

  if (length(raw) == 0) {
    warning("No items returned from Zotero; all rows will be unmatched.")
    return(mutate(refs, zotero_key = NA_character_, zotero_match = "unmatched"))
  }

  # Extract key fields from each item's `data` sub-object
  pluck_field <- function(item, field) {
    v <- item$data[[field]]
    if (is.null(v) || !nzchar(v)) NA_character_ else as.character(v)
  }

  lookup <- tibble(
    key   = map_chr(raw, \(x) x$key),
    title = map_chr(raw, \(x) pluck_field(x, "title")),
    DOI   = map_chr(raw, \(x) pluck_field(x, "DOI")),
    ISBN  = map_chr(raw, \(x) pluck_field(x, "ISBN")),
    date  = map_chr(raw, \(x) pluck_field(x, "date"))
  )

  # Normalise: lowercase → strip diacritics → keep alphanumerics only
  norm <- function(x) {
    x <- tolower(coalesce(as.character(x), ""))
    x <- stri_trans_general(x, "Latin-ASCII")
    str_replace_all(x, "[^a-z0-9]", "")
  }

  lookup <- lookup |>
    mutate(
      doi_norm   = norm(DOI),
      isbn_norm  = norm(ISBN),
      title_norm = norm(title),
      year_norm  = coalesce(str_extract(coalesce(date, ""), "\\d{4}"), "")
    )

  # Match a single refs row → c(key, match_type)
  match_row <- function(ref) {
    doi  <- norm(ref$DOI)
    isbn <- norm(ref$ISBN)
    titl <- norm(ref$title)
    yr   <- ref$year %||% ""

    if (nzchar(doi)) {
      hit <- filter(lookup, doi_norm == doi)
      if (nrow(hit)) return(c(hit$key[1], "doi"))
    }

    if (nzchar(isbn)) {
      hit <- filter(lookup, isbn_norm == isbn)
      if (nrow(hit)) return(c(hit$key[1], "isbn"))
    }

    if (nzchar(titl)) {
      hit <- filter(lookup, title_norm == titl)
      if (nrow(hit)) {
        if (nzchar(yr)) {
          hit_yr <- filter(hit, year_norm == yr)
          if (nrow(hit_yr)) return(c(hit_yr$key[1], "title_year"))
        }
        return(c(hit$key[1], "title_year"))
      }
    }

    c(NA_character_, "unmatched")
  }

  results <- map(seq_len(nrow(refs)), \(i) match_row(refs[i, ]))

  refs$zotero_key   <- map_chr(results, 1)
  refs$zotero_match <- map_chr(results, 2)

  tab  <- table(refs$zotero_match)
  getn <- function(k) if (k %in% names(tab)) tab[[k]] else 0L
  message(sprintf(
    "Matched %d / %d refs  (doi: %d, isbn: %d, title_year: %d, unmatched: %d)",
    sum(refs$zotero_match != "unmatched"), nrow(refs),
    getn("doi"), getn("isbn"), getn("title_year"), getn("unmatched")
  ))

  refs
}

# =============================================================================
# 13. Main pipeline
# =============================================================================

#' Extract Wikipedia references and optionally import to Zotero
#'
#' @param page_name Wikipedia page name (as in URL, e.g. "Elizabeth_Lyon_(criminal)")
#' @param language Wikipedia language code, default "en"
#' @param ris_file Path to write RIS file (NULL to skip)
#' @param enrich Whether to enrich refs with richer metadata via DOI/ISBN lookups
#'   using c2z's ZoteroDoi/ZoteroIsbn. Default TRUE.
#' @param zotero_import Whether to import to Zotero. Default FALSE.
#' @param collection_name Zotero collection name (default: page title with
#'   underscores replaced by spaces)
#' @param user_id Zotero user ID.
#' @param api_key Zotero API key (write access).
#' @param read_api_key Zotero API key for reading items back after import. If
#'   NULL, falls back to `api_key`. Useful when write and read keys differ.
#' @param fetch_keys If TRUE (default) and `zotero_import = TRUE` and
#'   `dry_run = FALSE`, call `fetch_zotero_keys()` after import to add
#'   `zotero_key` and `zotero_match` columns to the returned tibble.
#' @param dry_run If TRUE, don't actually post to Zotero. Default TRUE.
#' @return A tibble of deduplicated (and optionally enriched) references, with
#'   `zotero_key` / `zotero_match` columns when keys were fetched.
wiki_refs_pipeline <- function(page_name,
                                language = "en",
                                ris_file = NULL,
                                enrich = TRUE,
                                zotero_import = FALSE,
                                collection_name = NULL,
                                user_id = NULL,
                                api_key = NULL,
                                read_api_key = NULL,
                                fetch_keys = TRUE,
                                dry_run = TRUE) {
  message("Fetching wikitext for: ", page_name)
  wikitext <- fetch_wikitext(page_name, language = language)

  message("Extracting citations...")
  refs <- extract_refs_from_wikitext(wikitext)
  message("Found ", nrow(refs), " citation templates (before dedup)")

  message("Deduplicating...")
  refs <- deduplicate_refs(refs)
  message("Unique references: ", nrow(refs))

  # Summary
  message("\nReference types:")
  print(count(refs, itemType, sort = TRUE))

  if (enrich) {
    message("\nEnriching metadata via DOI/ISBN...")
    refs <- enrich_refs(refs)
  }

  if (!is.null(ris_file)) {
    export_ris(refs, ris_file)
  }

  imported_collection_key <- NULL

  if (zotero_import) {
    cname <- collection_name %||% str_replace_all(page_name, "_", " ")
    message("\nImporting to Zotero collection: ", cname)
    result <- import_to_zotero(refs, cname,
                               user_id = user_id, api_key = api_key,
                               dry_run = dry_run)
    if (!dry_run && !is.null(result$collections)) {
      imported_collection_key <- result$collections$key[1]
    }
  }

  if (fetch_keys && !dry_run && !is.null(imported_collection_key)) {
    message("\nFetching Zotero keys for imported items...")
    refs <- fetch_zotero_keys(
      refs,
      user_id        = user_id,
      api_key        = read_api_key %||% api_key,
      collection_key = imported_collection_key
    )
  }

  refs
}
