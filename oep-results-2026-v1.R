library(reticulate)
library(dplyr)
library(purrr)
library(stringr)
library(stringi) # For robust accent removal



# py_install("pdfplumber")
# 1. Initialize pdfplumber and open the document
pdfplumber <- reticulate::import("pdfplumber")
pdf <- pdfplumber$open("data/23-04-2026-part-1-y-2-V6_compressed.pdf")

# Let's look at page 23 (R uses 1-based indexing for lists)
page <- pdf$pages[[23]]

# 2. Extract all words and their coordinates into a dataframe
words_raw <- page$extract_words()
words_df <- map_dfr(words_raw, ~ as.data.frame(.x))

# 3. Find the Y-coordinates for the Top Anchors ("MUNICIPIO:")
top_anchors <- words_df %>%
  filter(text == "MUNICIPIO:") %>%
  pull(top)

# 4. Find the Y-coordinates for the Bottom Anchors ("ALCALDE" or "ALCALDESA")
# We use grepl to catch both variants
bottom_anchors <- words_df %>%
  filter(text %in% c("ALCALDE", "ALCALDESA")) %>%
  pull(top)

# --- Set up data structures before the extraction loop ---
muni_roster <- data.frame(municipality = character(),
                          province = character(),
                          stringsAsFactors = FALSE)
muni_votes <- list()

alcaldes_df <- data.frame(
  municipio = character(),
  provincia = character(),
  autoridad = character(),
  nombre = character(),
  sigla = character(),
  stringsAsFactors = FALSE
)

concejales_df <- data.frame(
  municipio = character(),
  provincia = character(),
  autoridad = character(),
  silla = character(),
  tipo = character(),      # Added column for Titular/Suplente
  nombre = character(),
  sigla = character(),
  stringsAsFactors = FALSE
)

# 5. Build dynamic bounding boxes
# Assuming the lists match up (e.g., 5 municipalities on the page = 5 top/bottom pairs)
for (i in seq_along(top_anchors)) {

  # Define the dynamic crop box: (Left, Top, Right, Bottom)
  # We add/subtract a tiny bit of padding to the Y coordinates so we don't slice the text
  dynamic_box <- c(
    0,                     # Left edge of page
    top_anchors[i] - 5,    # Just above "MUNICIPIO:"
    page$width,            # Right edge of page
    bottom_anchors[i] - 5  # Just above "ALCALDE..."
  )

  # Crop the page to just this specific full-width table
  table_crop <- page$crop(dynamic_box)

  # Extract the data
  table_data <- table_crop$extract_table()

  # 1. Convert python list of lists into a standard R matrix
  # We replace NULLs with NAs so R doesn't drop empty columns
  tbl_matrix <- do.call(rbind, lapply(table_data, function(row) {
    sapply(row, function(cell) if (is.null(cell)) NA else as.character(cell))
  }))

  # 2. Extract Municipality and Province
  # Collapse the first row into a single string to ignore where column dividers fall
  header_text <- paste(tbl_matrix[1, ], collapse = " ")

  # Use regex capture groups (...) to extract the text between specific words
  muni_name <- str_match(header_text, "MUNICIPIO:\\s*(.*?)\\s*\\(PROVINCIA:")[, 2]
  prov_name <- str_match(header_text, "PROVINCIA:\\s*(.*?)\\)")[, 2]

  # Append to our roster dataframe
  muni_roster <- rbind(muni_roster, data.frame(municipality = muni_name,
                                               province = prov_name,
                                               stringsAsFactors = FALSE))

  # 3. Isolate the Vote Table (Row 2 is Headers, Rows 3 & 4 are Data)
  headers <- tbl_matrix[2, ]
  vote_df <- as.data.frame(tbl_matrix[3:4, ], stringsAsFactors = FALSE)
  colnames(vote_df) <- headers

  # 4. Clean Specific Column Names
  n_cols <- ncol(vote_df)

  # Target the 1st column and the last 6 columns
  cols_to_clean <- c(1, (n_cols - 5):n_cols)

  # Apply lowercasing and accent removal to ONLY those specific targets
  colnames(vote_df)[cols_to_clean] <- colnames(vote_df)[cols_to_clean] %>%
    str_to_lower() %>%
    stri_trans_general("Latin-ASCII") # Replaces Á/É/Í/Ó/Ú with A/E/I/O/U

  # Append the cleaned dataframe to our list
  muni_votes[[length(muni_votes) + 1]] <- vote_df

  # --- INSIDE THE LOOP ---

  # 1. Determine the bottom boundary for this municipality's entire section
  # If it's the last municipality on the page, the bottom is the page height
  section_bottom <- if (i < length(top_anchors)) top_anchors[i + 1] - 5 else page$height

  # 2. Define the bounding box for the left-most column
  left_box <- c(
    0,                     # Left edge of page
    bottom_anchors[i] - 5, # Top: just above "ALCALDE..." / "ALCALDESA..."
    page$width / 3,        # Right: crop at one-third of the page width
    section_bottom         # Bottom: next municipality or bottom of page
  )

  # 3. Crop the left column and extract its tables
  left_column <- page$crop(left_box)
  left_tables <- left_column$extract_tables()

  # The ALCALDE/ALCALDESA table is guaranteed to be the first table in this column slice
  alcalde_data <- left_tables[[1]]

  # 4. Convert the python list-of-lists into a clean R matrix
  alcalde_matrix <- do.call(rbind, lapply(alcalde_data, function(row) {
    sapply(row, function(cell) if (is.null(cell)) NA else as.character(cell))
  }))

  # 5. Extract the specific cell values
  # Based on the visual layout:
  # Row 1 is the Title ("ALCALDE ELECTO"), Row 2 is Headers, Row 3 is the Data
  autoridad_val <- alcalde_matrix[1, 1]
  nombre_val    <- alcalde_matrix[3, 1]
  sigla_val     <- alcalde_matrix[3, 2]

  # 6. Append to the alcaldes dataframe
  alcaldes_df <- rbind(alcaldes_df, data.frame(
    municipio = muni_name,   # Reusing the variable extracted earlier in the loop
    provincia = prov_name,   # Reusing the variable extracted earlier in the loop
    autoridad = autoridad_val,
    nombre = nombre_val,
    sigla = sigla_val,
    stringsAsFactors = FALSE
  ))

  # --- INSIDE THE LOOP ---

  # 1. Define bounding boxes for the Middle and Right columns
  # We use the same Y-coordinates (bottom_anchors[i] to section_bottom) as the left column
  mid_box <- c(page$width / 3, bottom_anchors[i] - 5, (page$width / 3) * 2, section_bottom)
  right_box <- c((page$width / 3) * 2, bottom_anchors[i] - 5, page$width, section_bottom)

  # 2. Crop and Extract
  mid_column <- page$crop(mid_box)
  right_column <- page$crop(right_box)

  mid_tables <- mid_column$extract_tables()
  right_tables <- right_column$extract_tables()

  # 3. Gather all the Council tables into a temporary list
  council_raw_list <- list()

  # The council table is always the 2nd table in the left column (below the Alcalde table)
  if (length(left_tables) >= 2) {
    council_raw_list[[1]] <- left_tables[[2]]
  }
  # For the middle and right columns, it will be the 1st table (if they exist)
  if (length(mid_tables) >= 1) {
    council_raw_list[[2]] <- mid_tables[[1]]
  }
  if (length(right_tables) >= 1) {
    council_raw_list[[3]] <- right_tables[[1]]
  }

  # 4. Process each captured table
  # 4. Process each captured table
  for (tbl in council_raw_list) {

    # Convert python list to R matrix, converting NULLs and empty strings to NA
    tbl_mat <- do.call(rbind, lapply(tbl, function(row) {
      sapply(row, function(cell) {
        if (is.null(cell) || trimws(as.character(cell)) == "") NA else as.character(cell)
      })
    }))

    temp_df <- as.data.frame(tbl_mat, stringsAsFactors = FALSE)

    # Ensure the table actually captured data
    if (nrow(temp_df) > 1) {

      # Isolate the data rows (skip the header row)
      data_rows <- temp_df[2:nrow(temp_df), ]

      # Ensure we don't exceed column bounds
      if (ncol(data_rows) >= 4) {
        data_rows <- data_rows[, 1:4]
        colnames(data_rows) <- c("silla", "tipo", "nombre", "sigla")

        # Fill the empty cells, filter blanks, and clean the newlines in names
        clean_data <- data_rows %>%
          fill(silla, sigla, .direction = "down") %>%
          filter(!is.na(nombre)) %>%
          mutate(nombre = str_replace_all(nombre, "\n", " ")) # Replace \n with a space

        # 5. Format and append to the master dataframe
        final_append <- data.frame(
          municipio = muni_name,
          provincia = prov_name,
          autoridad = "CONSEJO",
          silla     = clean_data$silla,
          tipo      = clean_data$tipo,     # Keep the titular/suplente designation
          nombre    = clean_data$nombre,
          sigla     = clean_data$sigla,
          stringsAsFactors = FALSE
        )

        concejales_df <- rbind(concejales_df, final_append)
      }
    }
  }
}
