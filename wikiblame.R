library(WikipediR)
library(stringr)

get_revision_history_map <- function(article, lang = "en") {
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
  
  all_revisions <- list()
  continue_token <- NULL
  
  message("Mapping revision history (this may take a moment for long articles)...")
  
  repeat {
    params <- list(
      action = "query",
      prop = "revisions",
      titles = article,
      rvprop = "ids|timestamp|user",
      rvlimit = "500",
      format = "json"
    )
    
    # Add continuation token if it exists from previous loop
    if (!is.null(continue_token)) {
      params$rvcontinue <- continue_token
    }
    
    # The fix: added out_class = "list"
    res <- query(
      url = api_url,
      query = params,
      out_class = "list", 
      clean_response = FALSE
    )
    
    page_id <- names(res$query$pages)[1]
    revs <- res$query$pages[[page_id]]$revisions
    
    if (is.null(revs)) break
    
    all_revisions <- c(all_revisions, revs)
    
    # Check for more revisions
    if (!is.null(res$continue$rvcontinue)) {
      continue_token <- res$continue$rvcontinue
    } else {
      break
    }
  }
  
  # Convert to a data frame and sort Oldest to Newest
  df <- do.call(rbind, lapply(all_revisions, function(x) {
    data.frame(revid = x$revid, timestamp = x$timestamp, user = x$user, stringsAsFactors = FALSE)
  }))
  
  return(df[order(df$timestamp), ]) # Sort ascending for binary search
}

# --- Robust Content Fetcher ---
# This bypasses the wrapper to handle modern Wikipedia 'slots'
get_revision_text_safe <- function(revid, lang = "en") {
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
  
  params <- list(
    action = "query",
    prop = "revisions",
    revids = as.character(revid),
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
  
  # Navigate the response with safe indexing
  tryCatch({
    page_id <- names(res$query$pages)[1]
    rev_data <- res$query$pages[[page_id]]$revisions[[1]]
    
    # 1. Try modern slot-based content
    content <- rev_data$slots$main$content
    
    # 2. If modern slot is missing, try the old-style '*' field
    if (is.null(content)) {
      content <- rev_data$slots$main[["*"]]
    }
    
    # 3. If still missing, check if it's at the top level (very old API style)
    if (is.null(content)) {
      content <- rev_data[["*"]]
    }
    
    return(content)
  }, error = function(e) {
    return(NULL)
  })
}

find_sentence_insertion <- function(article, sentence, lang = "en", history_map = NULL) {
  
  if (is.null(history_map)) {
    # 1. Map the history (Reuse your working function here)
    history_map <- get_revision_history_map(article, lang)
    }
  
  n <- nrow(history_map)
  if (n == 0) stop("No revisions found.")
  
  low <- 1
  high <- n
  found_idx <- -1
  
  message(paste("Searching through", n, "revisions using binary search..."))
  
  while (low <= high) {
    mid <- floor((low + high) / 2)
    target_revid <- history_map$revid[mid]
    
    # Fetch content using our new safe function
    text <- get_revision_text_safe(target_revid, lang)
    
    # Safety Check: If text is NULL, skip or mark as not found to avoid error
    if (is.null(text)) {
      message(paste("Warning: Could not retrieve text for revision", target_revid))
      exists <- FALSE
    } else {
      exists <- str_detect(text, fixed(sentence))
    }
    
    if (isTRUE(exists)) {
      found_idx <- mid
      high <- mid - 1 # Look earlier
    } else {
      low <- mid + 1  # Look later
    }
    
    # Optional: progress indicator
    cat(".") 
  }
  
  if (found_idx != -1) {
    result <- history_map[found_idx, ]
    message("\n\nSUCCESS: Sentence first found!")
    cat("User: ", result$user, "\n")
    cat("Date: ", result$timestamp, "\n")
    cat("Link: ", paste0("https://", lang, ".wikipedia.org/w/index.php?oldid=", result$revid), "\n")
    return(result)
  } else {
    message("\n\nSentence not found. Note: Wikipedia search is case-sensitive and literal.")
    return(NULL)
  }
}
# Example Usage:
# result <- find_sentence_insertion("Albert Einstein", "Life is like riding a bicycle.",
#                                 lang = "en")
# print(result)
result <- find_sentence_insertion("Anthropology", "the scientific study")

# margaret_mead_map <- get_revision_history_map("Margaret Mead", "en")
# result <- find_sentence_insertion("Margaret Mead", "since it claimed that females are dominant",
#                                 lang = "en", history_map = margaret_mead_map)

library(purrr)
library(dplyr)

# --- Helper: Search using a pre-fetched history map ---
# This is a modified version of our previous search to be "purrr-friendly"
find_sentence_with_map <- function(sentence, article, history_map, lang = "en") {
  message(paste("\nSearching for:", substr(sentence, 1, 30), "..."))
  
  low <- 1
  high <- nrow(history_map)
  found_idx <- -1
  
  while (low <= high) {
    mid <- floor((low + high) / 2)
    target_revid <- history_map$revid[mid]
    
    text <- get_revision_text_safe(target_revid, lang)
    exists <- if (!is.null(text)) stringr::str_detect(text, stringr::fixed(sentence)) else FALSE
    
    if (isTRUE(exists)) {
      found_idx <- mid
      high <- mid - 1
    } else {
      low <- mid + 1
    }
  }
  
  if (found_idx != -1) {
    return(history_map[found_idx, ])
  } else {
    # Return a blank row with the same structure if not found
    return(data.frame(revid = NA, timestamp = NA, user = NA, stringsAsFactors = FALSE))
  }
}

# --- Main Function: The purrr Wrapper ---
track_wikipedia_sentences <- function(article, sentence_list, lang = "en") {
  
  # 1. Fetch the history map once for the whole article
  history_map <- get_revision_history_map(article, lang)
  
  # 2. Use purrr to iterate over the sentences
  # map_dfr automatically binds the results into a single table
  results_table <- sentence_list %>%
    purrr::map_dfr(function(s) {
      
      # Run the search for this specific sentence
      res <- find_sentence_with_map(s, article, history_map, lang)
      
      # Return a data frame where the first column is the sentence
      # We use tibble/data.frame to ensure the output is row-bindable
      data.frame(
        original_sentence = s,
        added_by = res$user,
        date_added = res$timestamp,
        revision_id = res$revid,
        stringsAsFactors = FALSE
      )
    })
  
  return(results_table)
}

# --- Usage Example ---
# my_sentences <- c(
#   "is the scientific study of humanity",
#   "There was an immediate rush to bring it into the social sciences",
#   "developed much through the end of the 19th century", 
#   "a method of analysing social or cultural interaction",
#   "distinguishes ethnography from anthropology"
# )
# 
# final_report <- track_wikipedia_sentences("Anthropology", my_sentences)
# print(final_report)
