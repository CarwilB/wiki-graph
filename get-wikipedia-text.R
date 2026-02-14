library(stringr)

extract_clean_fragments <- function(wikitext, keep_link_text = FALSE) {
  
  # 1. Remove References (<ref>...</ref> and <ref />)
  clean_text <- str_replace_all(wikitext, "(?s)<ref.*?>.*?</ref>", "")
  clean_text <- str_replace_all(clean_text, "<ref.*?/>", "")
  
  # 2. Remove Templates/Infoboxes ({{...}}) using recursive PCRE
  clean_text <- gsub("\\{\\{(?:[^{}]|(?R))*\\}\\}", "", clean_text, perl = TRUE)
  
  # 3. Remove Images and Files ([[File:..]] or [[Image:..]])
  clean_text <- str_replace_all(clean_text, "(?i)\\[\\[(File|Image):.*?\\]\\]", "")
  
  # 4. Handle Wikilinks
  if (keep_link_text) {
    # Flatten links: [[Target|Display]] -> Display
    clean_text <- str_replace_all(clean_text, "\\[\\[(?:[^|\\]]*\\|)?([^\\]]+)\\]\\]", "\\1")
  } else {
    # NEW LOGIC: Treat the link as a delimiter. 
    # Replace the [[...]] block with a newline to force a split.
    clean_text <- str_replace_all(clean_text, "\\[\\[.*?\\]\\]", "\n")
  }
  
  # 5. Remove Headers (== Header ==)
  clean_text <- str_replace_all(clean_text, "==+.*?==+", "")
  
  # 6. Remove remaining formatting (Bold/Italics)
  clean_text <- str_replace_all(clean_text, "''+", "")
  
  # 7. Split into fragments
  # Because Step 4 inserted \n, this split captures the text before/after links
  fragments <- unlist(str_split(clean_text, "[\\.\\!\\?\\n\\r]"))
  
  # 8. Clean up whitespace
  fragments <- str_trim(fragments)
  fragments <- str_replace_all(fragments, "\\s+", " ")
  
  # 9. Filter: Must be at least 5 words and not empty
  final_list <- fragments[str_count(fragments, "\\w+") >= 5]
  
  return(unique(final_list))
}
# Example usage:
# txt1 <- get_wikitext_from_url("https://en.wikipedia.org/wiki/Margaret_Mead")
# txt2 <- get_wikitext_from_url("https://en.wikipedia.org/w/index.php?title=Margaret_Mead&oldid=1316523564")
# margaret_mead_2025_before_revid <- 1316523564
# 
# sentences_mm_2024 <- extract_clean_fragments(txt2, keep_link_text = TRUE)
# sentences_mm_2024_8words <- stringr::word(sentences_mm_2024, 1, 8)

library(httr)
library(rvest)
library(dplyr)

get_plain_text <- function(title = NULL, revision_id = NULL, lang = "en") {
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
  
  # We use action=parse because it correctly supports historical 'oldid'
  params <- list(
    action = "parse",
    prop = "text", # We want the rendered HTML content
    format = "json"
  )
  
  if (!is.null(revision_id)) {
    params$oldid <- revision_id
    message(paste("Parsing historical Revision ID:", revision_id))
  } else if (!is.null(title)) {
    params$page <- title
    message(paste("Parsing current article:", title))
  } else {
    stop("You must provide either a title or a revision_id.")
  }
  
  # Execute request
  res <- GET(api_url, query = params)
  
  if (status_code(res) != 200) {
    stop("Failed to connect to Wikipedia API.")
  }
  
  data <- content(res, "parsed")
  
  str(data)  # Debug: Inspect the structure of the response
  
  # Extract the HTML from the nested response
  # Path: parse -> text -> *
  tryCatch({
    html_string <- data$parse$text[[1]]
    
    # Convert HTML to clean Plain Text
    # html_text2() mimics the browser rendering: 
    # - It keeps link text (e.g., [[A|B]] becomes B)
    # - It removes tags, scripts, and styles
    # - It handles line breaks and headers correctly
    plain_text <- read_html(html_string) %>%
      html_text2()
    
    return(plain_text)
    
  }, error = function(e) {
    warning("Could not parse content. The revision ID may be invalid or restricted.")
    return(NULL)
  })
}

get_title_from_revid <- function(revision_id, lang = "en") {
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
  
  params <- list(
    action = "query",
    revids = as.character(revision_id),
    format = "json"
  )
  
  # Use out_class = "list" to avoid the previous 'missing argument' error
  res <- query(
    url = api_url,
    query = params,
    out_class = "list",
    clean_response = FALSE
  )
  
  # Navigate the response: query -> pages -> [Page ID] -> title
  tryCatch({
    # The API returns a list where the key is the Page ID
    pages <- res$query$pages
    page_id <- names(pages)[1]
    
    # Extract the title
    title <- pages[[page_id]]$title
    
    if (is.null(title)) {
      warning("Revision ID not found or invalid.")
      return(NULL)
    }
    
    return(title)
    
  }, error = function(e) {
    message("Error retrieving title: ", e$message)
    return(NULL)
  })
}

wikitext_to_plain <- function(text) {
  # 1. Verify Pandoc is installed/accessible
  if (!rmarkdown::pandoc_available()) {
    stop("Pandoc is not found on this system. Please install Pandoc or check your RMarkdown setup.")
  }
  
  # 2. Create Temp Files for BOTH input and output
  # Using tempfile() ensures absolute paths and write permissions
  input_file  <- tempfile(fileext = ".wiki")
  output_file <- tempfile(fileext = ".txt")
  
  # 3. Cleanup: Ensure these files are deleted when the function exits
  on.exit(unlink(c(input_file, output_file)))
  
  # 4. Write Input
  # useBytes=TRUE prevents encoding errors on some systems
  writeLines(text, input_file, useBytes = TRUE)
  
  # 5. Convert
  # We wrap this in tryCatch in case Pandoc itself crashes (e.g., malformed syntax)
  tryCatch({
    rmarkdown::pandoc_convert(
      input = input_file, 
      from = "mediawiki", 
      to = "plain", 
      output = output_file
    )
  }, error = function(e) {
    stop("Pandoc conversion failed: ", e$message)
  })
  
  # 6. Check if file was actually created before reading
  if (!file.exists(output_file)) {
    stop("Pandoc ran but did not generate an output file.")
  }
  
  # 7. Read Result
  result <- readLines(output_file, warn = FALSE)
  return(paste(result, collapse = "\n"))
}

get_plain_text_revid <- function(revision_id, lang = "en") {
  article <- get_title_from_revid(revision_id, lang)
  wikitext <- get_wikitext_by_revid(article, revision_id, lang)
  
  wikitext_to_plain(wikitext)
}

# --- Examples ---
# 1. Get current plain text
# text_current <- get_plain_text(title = "Margaret Mead")

# 2. Get plain text of a specific historical revision
# text_old <- get_plain_text(revision_id = 123456789)


