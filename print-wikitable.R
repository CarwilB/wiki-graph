print_wikitable <- function(df, caption = NULL, class = "wikitable sortable",
                            column_names = NULL) {
  # 1. Start Table
  cat(paste0('{| class="', class, '"\n'))

  # 2. Add Caption (Optional)
  if (!is.null(caption)) {
    cat(paste0("|+ ", caption, "\n"))
  }

  # 3. Header Row
  if (!is.null(column_names)) {
    column_names <- names(df)
  }
  #    Use ! for headers, separating with !!
  cat("! ", paste(column_names, collapse = " !! "), "\n")

  # 4. Data Rows
  #    Loop through rows; start each with |-, separate cells with ||
  #    We apply a helper to escape any existing pipes '|' in the text to '{{!}}'
  #    so they don't break the wiki markup.

  formatted_rows <- apply(df, 1, function(row) {
    # Convert to character and escape pipes
    row_clean <- gsub("\\|", "{{!}}", as.character(row))
    # Replace NAs with empty string or specific text
    row_clean[is.na(row_clean)] <- ""

    paste0("| ", paste(row_clean, collapse = " || "))
  })

  # Print rows preceded by row separator
  cat(paste0("|-\n", formatted_rows, collapse = "\n"), "\n")

  # 5. End Table
  cat("|}\n")
}
