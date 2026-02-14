library(stringr)
library(dplyr)
library(crayon)

highlight_prior_segments <- function(current_text, prior_text, min_words = 3, format = "html") {
  
  # 1. Clean and tokenize prior text into a set of normalized N-grams
  # We lowercase and remove punctuation only for the 'matching' step
  clean_prior <- str_to_lower(prior_text) %>% 
    str_replace_all("[[:punct:]]", "") %>% 
    str_split("\\s+") %>% 
    unlist()
  
  prior_ngrams <- sapply(1:(length(clean_prior) - min_words + 1), function(i) {
    paste(clean_prior[i:(i + min_words - 1)], collapse = " ")
  }) %>% unique()
  
  # 2. Tokenize current text, preserving original casing/punctuation for display
  # This regex splits by space but keeps the spaces/punctuation attached to the word
  current_tokens <- str_split(current_text, "(?<=\\s)")[[1]]
  
  # 3. Create a normalized version of current tokens for comparison
  norm_tokens <- current_tokens %>% 
    str_to_lower() %>% 
    str_replace_all("[[:punct:]]|\\s", "")
  
  # 4. Identify which tokens are part of a matching segment
  is_match <- rep(FALSE, length(current_tokens))
  
  for (i in 1:(length(norm_tokens) - min_words + 1)) {
    # Construct the n-gram from current text starting at i
    window <- paste(norm_tokens[i:(i + min_words - 1)], collapse = " ")
    
    if (window %in% prior_ngrams) {
      # Mark all words in this window as matches
      is_match[i:(i + min_words - 1)] <- TRUE
    }
  }
  
  # 5. Reconstruct the text with highlighting
  output <- ""
  in_highlight <- FALSE
  
  # Define tags based on format
  start_tag <- if(format == "html") "<mark style='background-color: #ffff00;'>" else crayon::yellow$bold
  end_tag   <- if(format == "html") "</mark>" else function(x) x # crayon is a wrapper
  
  for (i in seq_along(current_tokens)) {
    if (is_match[i] && !in_highlight) {
      if(format == "html") output <- paste0(output, start_tag)
      in_highlight <- TRUE
    } else if (!is_match[i] && in_highlight) {
      if(format == "html") output <- paste0(output, end_tag)
      in_highlight <- FALSE
    }
    
    # Add the actual text
    if (in_highlight && format != "html") {
      output <- paste0(output, start_tag(current_tokens[i]))
    } else {
      output <- paste0(output, current_tokens[i])
    }
  }
  
  # Close trailing tag
  if (in_highlight && format == "html") output <- paste0(output, end_tag)
  
  return(output)
}

library(stringr)
library(dplyr)
library(crayon)

highlight_new_segments <- function(current_text, prior_text, min_words = 3, format = "html") {
  
  # 1. Clean and tokenize prior text (The "Reference" Text)
  clean_prior <- str_to_lower(prior_text) %>% 
    str_replace_all("[[:punct:]]", "") %>% 
    str_split("\\s+") %>% 
    unlist()
  
  # Create set of unique N-grams from the OLD text
  prior_ngrams <- sapply(1:(length(clean_prior) - min_words + 1), function(i) {
    paste(clean_prior[i:(i + min_words - 1)], collapse = " ")
  }) %>% unique()
  
  # 2. Tokenize current text
  current_tokens <- str_split(current_text, "(?<=\\s)")[[1]]
  
  # 3. Normalize current tokens for comparison
  norm_tokens <- current_tokens %>% 
    str_to_lower() %>% 
    str_replace_all("[[:punct:]]|\\s", "")
  
  # 4. Identify OLD segments (We map what IS old, so we can invert it)
  is_old <- rep(FALSE, length(current_tokens))
  
  for (i in 1:(length(norm_tokens) - min_words + 1)) {
    window <- paste(norm_tokens[i:(i + min_words - 1)], collapse = " ")
    if (window %in% prior_ngrams) {
      is_old[i:(i + min_words - 1)] <- TRUE
    }
  }
  
  # 5. Reconstruct with INVERTED highlighting
  # We highlight if the text is NOT old (!is_old)
  
  output <- ""
  in_highlight <- FALSE
  
  # Green for additions in console, standard mark for HTML
  start_tag <- if(format == "html") "<mark style='background-color: #ccffcc;'>" else crayon::green$bold
  end_tag   <- if(format == "html") "</mark>" else function(x) x 
  
  for (i in seq_along(current_tokens)) {
    
    # LOGIC FLIP: Check if token is NEW (!is_old)
    is_new <- !is_old[i]
    
    if (is_new && !in_highlight) {
      if(format == "html") output <- paste0(output, start_tag)
      in_highlight <- TRUE
    } else if (!is_new && in_highlight) {
      if(format == "html") output <- paste0(output, end_tag)
      in_highlight <- FALSE
    }
    
    if (in_highlight && format != "html") {
      output <- paste0(output, start_tag(current_tokens[i]))
    } else {
      output <- paste0(output, current_tokens[i])
    }
  }
  
  if (in_highlight && format == "html") output <- paste0(output, end_tag)
  
  return(output)
}
