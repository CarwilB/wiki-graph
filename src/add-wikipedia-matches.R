# Add Wikipedia search results to a tibble of place names.
#
# Uses the MediaWiki search API (action=query&list=search) via httr.
# Adds columns:
#   wikipedia_found   (logical)  : whether any search result was returned
#   wikipedia_match   (logical)  : whether the top result's title is an exact match (ignores case/space)
#   wikipedia_title   (chr / NA) : title of the top search result
#   wikipedia_url     (chr / NA) : URL to the top result page
#   wikipedia_snippet (chr / NA) : snippet returned by the search (may contain HTML)
#
# Usage:
#   result_aug <- add_wikipedia_matches(result, name_col = "name", lang = "en", delay = 0.5)
#
add_wikipedia_matches <- function(df, name_col = "name", lang = "en", delay = 0.5, limit = 5) {
  stopifnot(is.data.frame(df), name_col %in% names(df))
  names_vec <- as.character(df[[name_col]])

  search_wikipedia_one <- function(query, lang = "en", limit = 5) {
    if (is.na(query) || !nzchar(trimws(query))) {
      return(list(found = FALSE, title = NA_character_, url = NA_character_, snippet = NA_character_))
    }

    api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
    resp <- httr::GET(api_url, query = list(
      action   = "query",
      list     = "search",
      srsearch = query,
      srlimit  = limit,
      format   = "json"
    ))

    if (httr::status_code(resp) >= 400) {
      return(list(found = FALSE, title = NA_character_, url = NA_character_, snippet = NA_character_))
    }

    json <- jsonlite::fromJSON(
      httr::content(resp, as = "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
    hits <- json$query$search

    if (is.null(hits) || length(hits) == 0) {
      return(list(found = FALSE, title = NA_character_, url = NA_character_, snippet = NA_character_))
    }

    top       <- hits[[1]]
    top_title <- if (!is.null(top$title)) as.character(top$title) else NA_character_
    top_snip  <- if (!is.null(top$snippet)) as.character(top$snippet) else NA_character_
    url       <- paste0("https://", lang, ".wikipedia.org/wiki/",
                        utils::URLencode(gsub(" ", "_", top_title), reserved = TRUE))

    list(found = TRUE, title = top_title, url = url, snippet = top_snip)
  }

  results <- vector("list", length(names_vec))
  for (i in seq_along(names_vec)) {
    if (i > 1 && delay > 0) Sys.sleep(delay)

    res_i <- tryCatch(
      search_wikipedia_one(names_vec[[i]], lang = lang, limit = limit),
      error = function(e) list(found = FALSE, title = NA_character_, url = NA_character_, snippet = NA_character_)
    )

    matched <- FALSE
    if (isTRUE(res_i$found) && !is.na(res_i$title)) {
      norm_query <- tolower(gsub("\\s+", "", names_vec[[i]]))
      norm_title <- tolower(gsub("\\s+", "", res_i$title))
      matched <- nzchar(norm_query) && identical(norm_query, norm_title)
    }

    results[[i]] <- list(
      wikipedia_found   = isTRUE(res_i$found),
      wikipedia_match   = isTRUE(matched),
      wikipedia_title   = if (isTRUE(res_i$found)) res_i$title   else NA_character_,
      wikipedia_url     = if (isTRUE(res_i$found)) res_i$url     else NA_character_,
      wikipedia_snippet = if (isTRUE(res_i$found)) res_i$snippet else NA_character_
    )
  }

  results_df <- do.call(rbind, lapply(results, as.data.frame, stringsAsFactors = FALSE))
  if (inherits(df, "tbl_df")) results_df <- tibble::as_tibble(results_df)

  out <- cbind(df, results_df)
  out$wikipedia_found <- as.logical(out$wikipedia_found)
  out$wikipedia_match <- as.logical(out$wikipedia_match)
  out
}
