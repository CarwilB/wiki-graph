library(reticulate)
library(dplyr)
library(purrr)
library(stringr)
library(stringi)
library(tidyr)

# 1. Initialize pdfplumber and open the document
pdfplumber <- reticulate::import("pdfplumber")
pdf <- pdfplumber$open("data/23-04-2026-part-1-y-2-V6_compressed.pdf")

# --- Set up master data structures ---
muni_roster   <- data.frame(municipality = character(), province = character(), stringsAsFactors = FALSE)
muni_votes    <- list()
alcaldes_df   <- data.frame(municipio = character(), provincia = character(), autoridad = character(), nombre = character(), sigla = character(), stringsAsFactors = FALSE)
concejales_df <- data.frame(municipio = character(), provincia = character(), autoridad = character(), silla = character(), tipo = character(), nombre = character(), sigla = character(), stringsAsFactors = FALSE)

# Tracking failed pages or sections for logging
error_log <- data.frame(page = integer(), municipality_index = integer(), error_message = character(), stringsAsFactors = FALSE)

# Determine the total pages in the PDF dynamically
total_pages <- length(pdf$pages)

# 2. Outer Page Loop (Processing from Page 23 onwards)
for (page_num in 23:total_pages) {
  message(sprintf("Processing page %d of %d...", page_num, total_pages))

  # Safe page retrieval
  page <- tryCatch({
    pdf$pages[[page_num]]
  }, error = function(e) {
    error_log <<- rbind(error_log, data.frame(page = page_num, municipality_index = NA, error_message = paste("Failed to load page:", e$message)))
    return(NULL)
  })
  if (is.null(page)) next

  # Extract all words and coordinates safely
  words_df <- tryCatch({
    words_raw <- page$extract_words()
    map_dfr(words_raw, ~ as.data.frame(.x))
  }, error = function(e) {
    return(data.frame())
  })

  if (nrow(words_df) == 0) {
    message(sprintf("--> Skipping page %d (No text layout detected)", page_num))
    next
  }

  # Find coordinates for anchors
  top_anchors <- words_df %>% filter(text == "MUNICIPIO:") %>% pull(top)
  bottom_anchors <- words_df %>% filter(text %in% c("ALCALDE", "ALCALDESA")) %>% pull(top)

  # --- Alignment Validation Check ---
  if (length(top_anchors) != length(bottom_anchors)) {
    warning(sprintf("Anchor mismatch on Page %d: Found %d 'MUNICIPIO:' but %d 'ALCALDE/S'. Skipping page.",
                    page_num, length(top_anchors), length(bottom_anchors)))
    error_log <- rbind(error_log, data.frame(
      page = page_num,
      municipality_index = NA,
      error_message = sprintf("Anchor count mismatch (Top: %d, Bottom: %d)", length(top_anchors), length(bottom_anchors))
    ))
    next # Move to the next page safely
  }

  # 3. Inner Municipality Loop
  for (i in seq_along(top_anchors)) {

    # Wrap every individual municipality execution in an isolated tryCatch
    tryCatch({

      # Define the dynamic crop box
      dynamic_box <- c(0, top_anchors[i] - 5, page$width, bottom_anchors[i] - 5)
      table_crop  <- page$crop(dynamic_box)
      table_data  <- table_crop$extract_table()

      if (is.null(table_data) || length(table_data) == 0) stop("Top vote table missing or unreadable.")

      # 1. Convert python list of lists to matrix
      tbl_matrix <- do.call(rbind, lapply(table_data, function(row) {
        sapply(row, function(cell) if (is.null(cell)) NA else as.character(cell))
      }))

      # 2. Extract Municipality and Province
      header_text <- paste(tbl_matrix[1, ], collapse = " ")
      muni_name   <- str_match(header_text, "MUNICIPIO:\\s*(.*?)\\s*\\(PROVINCIA:")[, 2]
      prov_name   <- str_match(header_text, "PROVINCIA:\\s*(.*?)\\)")[, 2]

      if (is.na(muni_name)) muni_name <- "UNKNOWN_MUNI"
      if (is.na(prov_name)) prov_name <- "UNKNOWN_PROV"

      muni_roster <- rbind(muni_roster, data.frame(municipality = muni_name, province = prov_name, stringsAsFactors = FALSE))

      # 3. Isolate the Vote Table
      headers <- tbl_matrix[2, ]
      vote_df <- as.data.frame(tbl_matrix[3:4, ], stringsAsFactors = FALSE)
      colnames(vote_df) <- headers

      # 4. Clean Specific Column Names
      n_cols <- ncol(vote_df)
      if (n_cols >= 7) { # Safe structure boundary check
        cols_to_clean <- c(1, (n_cols - 5):n_cols)
        colnames(vote_df)[cols_to_clean] <- colnames(vote_df)[cols_to_clean] %>%
          str_to_lower() %>%
          stri_trans_general("Latin-ASCII")
      }

      muni_votes[[length(muni_votes) + 1]] <- vote_df

      # --- PROCESS ALCALDE TABLE ---
      section_bottom <- if (i < length(top_anchors)) top_anchors[i + 1] - 5 else page$height

      left_box     <- c(0, bottom_anchors[i] - 5, page$width / 3, section_bottom)
      left_column  <- page$crop(left_box)
      left_tables  <- left_column$extract_tables()

      if (length(left_tables) == 0) stop("Left column tables missing entirely.")

      alcalde_data   <- left_tables[[1]]
      alcalde_matrix <- do.call(rbind, lapply(alcalde_data, function(row) {
        sapply(row, function(cell) if (is.null(cell)) NA else as.character(cell))
      }))

      autoridad_val <- if(nrow(alcalde_matrix) >= 1) alcalde_matrix[1, 1] else NA
      nombre_val    <- if(nrow(alcalde_matrix) >= 3) alcalde_matrix[3, 1] else NA
      sigla_val     <- if(nrow(alcalde_matrix) >= 3 && ncol(alcalde_matrix) >= 2) alcalde_matrix[3, 2] else NA

      alcaldes_df <- rbind(alcaldes_df, data.frame(
        municipio = muni_name, provincia = prov_name, autoridad = autoridad_val,
        nombre = nombre_val, sigla = sigla_val, stringsAsFactors = FALSE
      ))

      # --- PROCESS CONCEJAL TABLES ---
      mid_box      <- c(page$width / 3, bottom_anchors[i] - 5, (page$width / 3) * 2, section_bottom)
      right_box    <- c((page$width / 3) * 2, bottom_anchors[i] - 5, page$width, section_bottom)

      mid_tables   <- page$crop(mid_box)$extract_tables()
      right_tables <- page$crop(right_box)$extract_tables()

      council_raw_list <- list()
      if (length(left_tables) >= 2) council_raw_list[[length(council_raw_list) + 1]] <- left_tables[[2]]
      if (length(mid_tables) >= 1)  council_raw_list[[length(council_raw_list) + 1]] <- mid_tables[[1]]
      if (length(right_tables) >= 1) council_raw_list[[length(council_raw_list) + 1]] <- right_tables[[1]]

      for (tbl in council_raw_list) {
        tbl_mat <- do.call(rbind, lapply(tbl, function(row) {
          sapply(row, function(cell) if (is.null(cell) || trimws(as.character(cell)) == "") NA else as.character(cell))
        }))

        temp_df <- as.data.frame(tbl_mat, stringsAsFactors = FALSE)
        if (nrow(temp_df) <= 1 || ncol(temp_df) < 4) next

        data_rows <- temp_df[2:nrow(temp_df), 1:4]
        colnames(data_rows) <- c("silla", "tipo", "nombre", "sigla")

        clean_data <- data_rows %>%
          fill(silla, sigla, .direction = "down") %>%
          filter(!is.na(nombre)) %>%
          mutate(nombre = str_replace_all(nombre, "\n", " "))

        concejales_df <- rbind(concejales_df, data.frame(
          municipio = muni_name, provincia = prov_name, autoridad = "CONSEJO",
          silla = clean_data$silla, tipo = clean_data$tipo,
          nombre = clean_data$nombre, sigla = clean_data$sigla, stringsAsFactors = FALSE
        ))
      }

    }, error = function(e) {
      # Log the failure cleanly but don't halt execution
      message(sprintf("   [!] Error parsing municipality %d on page %d: %s", i, page_num, e$message))
      error_log <<- rbind(error_log, data.frame(
        page = page_num,
        municipality_index = i,
        error_message = e$message,
        stringsAsFactors = FALSE
      ))
    })
  }
}

# Close the PDF object when finished
pdf$close()
