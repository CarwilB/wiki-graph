# extract-infobox.R
# Bilingual infobox extraction (English, Spanish, Portuguese)
# Kept locally because it handles Spanish templates (ficha de, info/)
# that are not covered by the wikitools package version.
#
# Dependencies: stringr, purrr

library(stringr)
library(purrr)

#' Extract the raw wikitext of the main infobox template
#'
#' Isolates the complete infobox template (from {{ to matching }}) from wikitext.
#' Handles nested templates via recursive brace matching.
#' Returns NULL if no infobox found.
#'
#' Supports English {{Infobox ..., Spanish {{Ficha de ...,
#' and Portuguese {{Info/ ... templates.
#'
#' @param wikitext The raw wikitext string
#' @return A string containing the full infobox template wikitext, or NULL
extract_infobox_wikitext <- function(wikitext) {
  if (is.null(wikitext)) return(NULL)

  # Find the start of an infobox template.
  # Handles:
  #   English  {{Infobox ...
  #   Spanish  {{Ficha de ...
  #   Portuguese {{Info/ ...   (e.g. {{Info/Município do Brasil)
  infobox_start <- regexpr(
    "\\{\\{\\s*(?:[Ii]nfobox|[Ff]icha\\s+de|[Ii]nfo/)",
    wikitext, perl = TRUE
  )
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
#'
#' @param wikitext The raw wikitext string
#' @return A named list of infobox parameters, or NULL
extract_infobox <- function(wikitext) {
  if (is.null(wikitext)) return(NULL)

  infobox_text <- extract_infobox_wikitext(wikitext)
  if (is.null(infobox_text)) return(NULL)

  # Parse pipe-delimited parameters
  # Remove the outer {{ and }} and the template name line.
  # Handles English {{Infobox, Spanish {{Ficha de, Portuguese {{Info/
  inner <- sub(
    "^\\{\\{\\s*(?:[Ii]nfobox|[Ff]icha\\s+de|[Ii]nfo/)[^\\n|]*",
    "", infobox_text, perl = TRUE
  )
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

  # Clean all values using wikitools::clean_infobox_value and remove those that become empty/NA
  cleaned <- map_chr(infobox_raw, wikitools::clean_infobox_value)

  # Keep only non-empty/non-NA elements
  keep <- !is.na(cleaned) & cleaned != ""

  if (!any(keep)) return(NULL)

  # Return as a named character vector
  as.character(cleaned[keep][names(cleaned)[keep]])
}

#' Split a string on "|" characters that are not inside {{ }}, [[ ]], or
#' <!-- --> comments. HTML comments don't nest and can legitimately contain
#' "|" (e.g. a commented-out wikilink like <!--[File:X.png|thumb]-->), so
#' their entire span is copied verbatim before resuming normal scanning —
#' otherwise a "|" inside a comment gets misread as a field delimiter and
#' corrupts extraction of that field and the next one.
#'
#' @param text The string to split
#' @return A character vector of parts split on top-level pipes
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
        # Unclosed comment (pre-existing malformed wikitext): consume the
        # remainder verbatim rather than let it corrupt further splitting.
        current <- paste0(current, substr(text, i, n))
        i <- n + 1
      } else {
        end <- i + match_pos + 1  # end index of the closing "-->"
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

#' Parse an infobox's raw wikitext into an ordered list of field blocks,
#' preserving each parameter's text EXACTLY as written (no trimming, no
#' comment stripping, internal newlines intact). Use this instead of
#' extract_infobox() when the raw markup itself (including embedded HTML
#' comments and their exact placement) needs to be carried through a merge
#' rather than flattened into cleaned single-line values.
#'
#' @param infobox_text Raw infobox wikitext, e.g. from extract_infobox_wikitext()
#' @return A list of list(field = <name>, raw_value = <verbatim text after "=">)
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

#' Does a raw (possibly multi-line, comment-laden) infobox field value have
#' any real content once HTML comments are notionally removed?
#'
#' Used only to decide whether a field block should be treated as "blank"
#' for merge purposes -- never used to alter text that gets emitted.
#'
#' @param raw_value The raw infobox field value
#' @return Logical, TRUE if the value has non-comment content
has_real_content <- function(raw_value) {
  no_comments <- gsub("<!--.*?-->", "", raw_value, perl = TRUE)
  nzchar(trimws(no_comments))
}
