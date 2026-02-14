# Install dependencies if missing
if (!require("wikipediR")) install.packages("wikipediR")
if (!require("stringr")) install.packages("stringr")

library(WikipediR)
library(stringr)


library(WikipediR)

get_history_fixed <- function(article, lang = "en") {
  
  # 1. Construct the API URL explicitly
  # The 'query' function in WikipediR requires this argument.
  api_url <- paste0("https://", lang, ".wikipedia.org/w/api.php")
  
  # 2. Define API parameters
  params <- list(
    action = "query",              # Required for generic queries
    prop = "revisions",            # We want revision history
    titles = article,
    rvprop = "ids|timestamp|user|comment", # Properties to grab
    rvlimit = "500",               # Max items per request
    format = "json"
  )
  
  # 3. Send the query
  # We pass 'api_url' as 'url' and our parameters list as 'query'
  raw_data <- query(
    url = api_url,      # Explicit URL fixes the error
    query = params,
    clean_response = FALSE
  )
  
  # 4. Parse the nested list
  # Path: query -> pages -> [page_id] -> revisions
  pages_list <- raw_data$query$pages
  
  # Extract the first page (since we only queried one title)
  page_content <- pages_list[[1]]
  
  # Check for valid revisions
  if (is.null(page_content$revisions)) {
    warning("No revisions found. Check if the page title is correct.")
    return(NULL)
  }
  
  # 5. Convert to Data Frame
  history_df <- do.call(rbind, lapply(page_content$revisions, function(x) {
    data.frame(
      revid = x$revid,
      user = ifelse(is.null(x$user), "Hidden", x$user),
      timestamp = x$timestamp,
      comment = ifelse(is.null(x$comment), "", x$comment),
      stringsAsFactors = FALSE
    )
  }))
  
  return(history_df)
}

# --- Usage ---
history <- get_history_fixed("R (programming language)")
# head(history)



 --- Helper 1: Get ALL Revision IDs (Metadata only) ---
# This handles the API pagination to get the full history list
get_all_revids <- function(article, lang = "en") {
  message("Fetching full revision history map...")
  
  all_revisions <- list()
  continue_token <- NULL
  
  repeat {
    # Fetch batch of 500 revisions (max allowed for standard users)
    res <- page_info(
      language = lang,
      project = "wikipedia",
      page = article,
      properties = c("ids", "timestamp", "user"),
      limit = 500,
      continue = continue_token,
      clean_response = TRUE
    )
    
    # Check if page exists
    if (length(res) == 0) stop("Article not found.")
    
    all_revisions <- c(all_revisions, res)
    
    # Check for continuation token (pagination)
    if (!is.null(attr(res, "continue"))) {
      continue_token <- attr(res, "continue")
    } else {
      break
    }
  }
  
  # Convert list to data frame for easy indexing
  # Structure: revid, timestamp, user
  df <- do.call(rbind, lapply(all_revisions, function(x) {
    data.frame(
      revid = x$revid, 
      timestamp = x$timestamp, 
      user = ifelse(is.null(x$user), "Hidden", x$user),
      stringsAsFactors = FALSE
    )
  }))
  
  # Ensure sorted by time (Oldest -> Newest) for binary search
  df <- df[order(df$timestamp), ]
  return(df)
}

# --- Helper 2: Check Content of a Specific Revision ---
has_text <- function(revid, search_string, lang = "en") {
  tryCatch({
    content <- revision_content(
      language = lang,
      project = "wikipedia",
      revisions = revid,
      clean_response = TRUE
    )
    
    # The API returns HTML/Wikitext. We search plain text.
    # Note: This is case-sensitive. Use ignore_case=TRUE in str_detect if preferred.
    return(stringr::str_detect(content$content, fixed(search_string)))
    
  }, error = function(e) {
    warning(paste("Failed to fetch revision", revid))
    return(FALSE)
  })
}

# --- Main Function: The Binary Search ---
wikiblame_r <- function(article, search_string, lang = "en") {
  
  # 1. Get the map
  history <- get_all_revids(article, lang)
  n <- nrow(history)
  message(paste("History mapped:", n, "revisions found."))
  
  # 2. Binary Search Setup
  left <- 1
  right <- n
  candidate_idx <- -1
  
  message("Starting binary search...")
  
  # 3. The Loop
  while (left <= right) {
    mid <- floor((left + right) / 2)
    current_revid <- history$revid[mid]
    
    message(paste("Checking revision", mid, "of", n, "...", "(ID:", current_revid, ")"))
    
    found <- has_text(current_revid, search_string, lang)
    
    if (found) {
      # Text IS present. 
      # It might have been added here, or earlier.
      candidate_idx <- mid  # Remember this as a valid location
      right <- mid - 1      # Look at the older half to see if it appeared earlier
    } else {
      # Text IS NOT present.
      # It must have been added later.
      left <- mid + 1
    }
    
    # Optional: small sleep to be polite to the API
    Sys.sleep(0.1)
  }
  
  # 4. Results
  if (candidate_idx != -1) {
    result <- history[candidate_idx, ]
    print(paste("FOUND!"))
    print(paste("Added by:", result$user))
    print(paste("Date:", result$timestamp))
    print(paste("Revision ID:", result$revid))
    print(paste("URL:", paste0("https://", lang, ".wikipedia.org/w/index.php?oldid=", result$revid)))
    return(result)
  } else {
    message("Text not found in any revision. Check casing or punctuation.")
    return(NULL)
  }
}

# --- Usage Example ---
result <- wikiblame_r("R (programming language)", "Ross Ihaka")
