library(stringr)

extract_clean_fragments <- function(wikitext, keep_link_text = FALSE) {
  
  # 1. Remove References (<ref>...</ref> and <ref />)
  clean_text <- str_replace_all(wikitext, "(?s)<ref.*?>.*?</ref>", "")
  clean_text <- str_replace_all(clean_text, "<ref.*?/>", "")
  
  # 2. Remove Templates/Infoboxes ({{...}}) using recursive PCRE
  clean_text <- gsub("\\{\\{(?:[^{}]|(?R))*\\}\\}", "", clean_text, perl = TRUE)
  
  # 3. Remove Images and Files ([[File:..]] or [[Image:..]])
  # This must happen before general wikilink processing
  clean_text <- str_replace_all(clean_text, "(?i)\\[\\[(File|Image):.*?\\]\\]", "")
  
  # 4. Handle Wikilinks based on parameter
  if (keep_link_text) {
    # Pattern extracts 'Display' from [[Target|Display]] or 'Link' from [[Link]]
    # It replaces the whole [[...]] with just that text
    clean_text <- str_replace_all(clean_text, "\\[\\[(?:[^|\\]]*\\|)?([^\\]]+)\\]\\]", "\\1")
  } else {
    # Disregard any wikilinked text entirely
    clean_text <- str_replace_all(clean_text, "\\[\\[.*?\\]\\]", "")
  }
  
  # 5. Remove Headers (== Header ==)
  clean_text <- str_replace_all(clean_text, "==+.*?==+", "")
  
  # 6. Remove remaining formatting (Bold/Italics)
  clean_text <- str_replace_all(clean_text, "''+", "")
  
  # 7. Split into fragments by terminators or newlines
  fragments <- unlist(str_split(clean_text, "[\\.\\!\\?\\n\\r]"))
  
  # 8. Clean up whitespace
  fragments <- str_trim(fragments)
  fragments <- str_replace_all(fragments, "\\s+", " ")
  
  # 9. Filter: Must be at least 5 words
  final_list <- fragments[str_count(fragments, "\\w+") >= 5]
  
  return(unique(final_list))
}

library(WikipediR)

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
  
  res <- query(
    url = api_url,
    query = params,
    out_class = "list",
    clean_response = FALSE
  )
  
  tryCatch({
    page_id <- names(res$query$pages)[1]
    # Extract content from modern 'main' slot
    content <- res$query$pages[[page_id]]$revisions[[1]]$slots$main$content
    if (is.null(content)) content <- res$query$pages[[page_id]]$revisions[[1]]$slots$main[["*"]]
    return(content)
  }, error = function(e) return(NULL))
}

get_wikitext_by_revid <- function(article_name, revision_id, lang = "en") {
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
  
  params <- list(
    action = "query",
    prop = "revisions",
    revids = as.character(revision_id), # Using specific ID
    rvprop = "content",
    rvslots = "main",
    format = "json"
  )
  
  res <- query(
    url = api_url,
    query = params,
    out_class = "list",
    clean_response = FALSE
  )
  
  tryCatch({
    page_id <- names(res$query$pages)[1]
    content <- res$query$pages[[page_id]]$revisions[[1]]$slots$main$content
    if (is.null(content)) content <- res$query$pages[[page_id]]$revisions[[1]]$slots$main[["*"]]
    return(content)
  }, error = function(e) return(NULL))
}

library(httr)

get_wikitext_from_url <- function(url) {
  # 1. Parse the URL components
  parsed <- httr::parse_url(url)
  
  # 2. Extract Language (e.g., 'en' from 'en.wikipedia.org')
  lang <- str_split(parsed$hostname, "\\.")[[1]][1]
  
  # 3. Logic to determine if it's a specific revision or current page
  # Check if 'oldid' exists in the query parameters
  if (!is.null(parsed$query$oldid)) {
    message("Detected specific revision URL...")
    title <- parsed$query$title
    revid <- parsed$query$oldid
    return(get_wikitext_by_revid(title, revid, lang = lang))
    
  } else {
    # It's a standard URL (usually /wiki/Article_Name)
    message("Detected standard article URL...")
    # Extract title from the path (remove '/wiki/')
    title <- str_replace(parsed$path, "wiki/", "")
    return(get_wikitext_by_name(title, lang = lang))
  }
}

# --- Examples ---
# txt1 <- get_wikitext_from_url("https://en.wikipedia.org/wiki/Margaret_Mead")
# 
# # 2. Specific revision
# txt2 <- get_wikitext_from_url("https://en.wikipedia.org/w/index.php?title=Margaret_Mead&oldid=1316523564")
