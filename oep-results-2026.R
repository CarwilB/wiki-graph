library(reticulate)
library(dplyr)
library(purrr)
library(stringr)
library(stringi)
library(tidyr)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Convert one raw pdfplumber council panel table into a clean data frame.
# Includes a column-shift fix for when pdfplumber inserts a spurious blank
# first column at a box boundary (real data shifts right by one).
parse_council_table <- function(tbl, muni_name, prov_name) {
  tbl_mat <- do.call(rbind, lapply(tbl, function(row) {
    sapply(row, function(cell)
      if (is.null(cell) || trimws(as.character(cell)) == "") NA else as.character(cell))
  }))

  temp_df <- as.data.frame(tbl_mat, stringsAsFactors = FALSE)
  if (nrow(temp_df) <= 1 || ncol(temp_df) < 4) return(NULL)

  data_rows <- temp_df[2:nrow(temp_df), 1:4]
  colnames(data_rows) <- c("silla", "tipo", "nombre", "sigla")

  # Detect one-column right-shift: silla col all-NA but next col has integers
  if (ncol(temp_df) >= 5 &&
      all(is.na(data_rows$silla)) &&
      any(!is.na(suppressWarnings(as.integer(data_rows$tipo))))) {
    data_rows <- temp_df[2:nrow(temp_df), 2:5]
    colnames(data_rows) <- c("silla", "tipo", "nombre", "sigla")
  }

  clean_data <- data_rows |>
    fill(silla, sigla, .direction = "down") |>
    filter(!is.na(silla)) |>
    mutate(nombre = str_replace_all(nombre, "\n", " "))

  if (nrow(clean_data) == 0) return(NULL)

  data.frame(
    municipio = muni_name, provincia = prov_name, autoridad = "CONCEJO",
    silla = clean_data$silla, tipo = clean_data$tipo,
    nombre = clean_data$nombre, sigla = clean_data$sigla,
    stringsAsFactors = FALSE
  )
}

# Process one municipality (index i) from a page.
# anchors: list with top_anchors, bottom_anchors, left_anchors, column_top_anchors
# words_df: word-level extract for the page (used for IOC detection)
# Returns a list: muni_name, prov_name, vote_df, alcalde_row, concejal_rows, ioc_rows
process_municipality <- function(page, i, anchors, words_df) {
  top_anchors        <- anchors$top_anchors
  bottom_anchors     <- anchors$bottom_anchors
  left_anchors       <- anchors$left_anchors
  column_top_anchors <- anchors$column_top_anchors

  # --- Vote table (full-width header band) ---
  dynamic_box <- c(0, top_anchors[i] - 5, page$width, bottom_anchors[i] - 5)

  # CHANGE: Use extract_tables() plural to capture split horizontal tables
  vote_tables <- page$crop(dynamic_box)$extract_tables()

  if (length(vote_tables) == 0)
    stop("Top vote table missing or unreadable.")

  # 1. Parse the primary top table
  tbl_matrix1 <- do.call(rbind, lapply(vote_tables[[1]], function(row) {
    sapply(row, function(cell) if (is.null(cell)) NA else as.character(cell))
  }))

  header_text <- paste(tbl_matrix1[1, ], collapse = " ")
  muni_name   <- str_match(header_text, "MUNICIPIO:\\s*(.*?)\\s*\\(PROVINCIA:")[, 2]
  prov_name   <- str_match(header_text, "PROVINCIA:\\s*(.*?)\\)")[, 2]
  if (is.na(muni_name)) muni_name <- "UNKNOWN_MUNI"
  if (is.na(prov_name)) prov_name <- "UNKNOWN_PROV"

  headers <- tbl_matrix1[2, ]
  vote_df  <- as.data.frame(tbl_matrix1[3:4, ], stringsAsFactors = FALSE)
  colnames(vote_df) <- headers

  # 2. Merge any split continuation tables (handling the second horizontal table)
  if (length(vote_tables) > 1) {
    for (t in 2:length(vote_tables)) {
      tbl_matrix_sub <- do.call(rbind, lapply(vote_tables[[t]], function(row) {
        sapply(row, function(cell) if (is.null(cell)) NA else as.character(cell))
      }))

      # Ensure it's a valid continuation (Header row + 2 data rows)
      if (nrow(tbl_matrix_sub) >= 3) {
        headers_sub <- tbl_matrix_sub[1, ]
        vote_df_sub <- as.data.frame(tbl_matrix_sub[2:3, ], stringsAsFactors = FALSE)
        colnames(vote_df_sub) <- headers_sub

        # Drop the redundant 'AUTORIDAD' column to cleanly horizontal bind
        if (grepl("AUTORIDAD", headers_sub[1], ignore.case = TRUE)) {
          vote_df_sub <- vote_df_sub[, -1, drop = FALSE]
        }

        vote_df <- cbind(vote_df, vote_df_sub)
      }
    }
  }

  # 3. Clean specific column names
  # n_cols evaluates dynamically, so it always targets the true final 6 summary columns
  n_cols <- ncol(vote_df)
  if (n_cols >= 7) {
    cols_to_clean <- c(1, (n_cols - 5):n_cols)
    colnames(vote_df)[cols_to_clean] <- colnames(vote_df)[cols_to_clean] |>
      str_to_lower() |>
      stri_trans_general("Latin-ASCII")
  }

  # 4. Convert Bolivian formatted strings to R numerics
  # Applies to all columns except the first one (Autoridad)
  vote_df <- vote_df |>
    mutate(across(-1, ~ {
      .x |>
        str_remove_all("%") |>          # Strip percentage signs
        str_remove_all("\\.") |>        # Remove the thousands separator
        str_replace_all(",", ".") |>    # Swap the decimal comma to a period
        as.numeric()                    # Cast to double/numeric
    }))

  # --- Section boundaries (truncate above IOC table if present) ---
  true_section_bottom <- if (i < length(top_anchors)) top_anchors[i + 1] - 5 else page$height
  section_bottom      <- true_section_bottom

  indigenous_table_y <- words_df |>
    filter(text == "NACIONES", top > bottom_anchors[i], top < section_bottom) |>
    pull(top)
  has_ioc <- length(indigenous_table_y) > 0
  if (has_ioc) section_bottom <- min(indigenous_table_y) - 5

  # --- Box coordinates ---
  l_anch2 <- as.numeric(left_anchors[i, 2]) - 5
  l_anch3 <- as.numeric(left_anchors[i, 3]) - 5
  c_top1  <- as.numeric(column_top_anchors[i, 1]) - 8
  c_top2  <- as.numeric(column_top_anchors[i, 2]) - 8
  c_top3  <- as.numeric(column_top_anchors[i, 3]) - 8

  mayor_box <- c(0,           bottom_anchors[i] - 3, l_anch2 - 5, c_top1)
  left_box  <- c(0,           c_top1,                l_anch2 - 2, section_bottom)
  mid_box   <- c(l_anch2 - 3, c_top2,                l_anch3 - 2, section_bottom)
  right_box <- c(l_anch3 - 5, c_top3,                page$width,  section_bottom)

  # --- Alcalde ---
  mayor_tables <- page$crop(mayor_box)$extract_tables()
  if (length(mayor_tables) == 0) stop("Mayor table missing entirely.")

  alcalde_matrix <- do.call(rbind, lapply(mayor_tables[[1]], function(row) {
    sapply(row, function(cell) if (is.null(cell)) NA else as.character(cell))
  }))

  alcalde_row <- data.frame(
    municipio = muni_name,
    provincia = prov_name,
    autoridad = if (nrow(alcalde_matrix) >= 1) alcalde_matrix[1, 1] else NA,
    nombre    = if (nrow(alcalde_matrix) >= 3) alcalde_matrix[3, 1] else NA,
    sigla     = if (nrow(alcalde_matrix) >= 3 && ncol(alcalde_matrix) >= 2) alcalde_matrix[3, 2] else NA,
    stringsAsFactors = FALSE
  )

  # --- Concejales (three columns) ---
  left_tables  <- page$crop(left_box)$extract_tables()
  mid_tables   <- page$crop(mid_box)$extract_tables()
  right_tables <- page$crop(right_box)$extract_tables()

  council_raw_list <- list()
  if (length(left_tables)  >= 1) council_raw_list[[length(council_raw_list) + 1]] <- left_tables[[1]]
  if (length(mid_tables)   >= 1) council_raw_list[[length(council_raw_list) + 1]] <- mid_tables[[1]]
  if (length(right_tables) >= 1) council_raw_list[[length(council_raw_list) + 1]] <- right_tables[[1]]

  concejal_rows <- do.call(rbind, lapply(
    council_raw_list, parse_council_table,
    muni_name = muni_name, prov_name = prov_name
  ))

  # --- IOC concejales ---
  ioc_rows <- NULL
  if (has_ioc) {
    ioc_box    <- c(0, min(indigenous_table_y) - 5, page$width, true_section_bottom)
    ioc_tables <- page$crop(ioc_box)$extract_tables()

    if (length(ioc_tables) > 0) {
      ioc_mat <- do.call(rbind, lapply(ioc_tables[[1]], function(row) {
        sapply(row, function(cell)
          if (is.null(cell) || trimws(as.character(cell)) == "") NA else as.character(cell))
      }))

      ioc_df_temp <- as.data.frame(ioc_mat, stringsAsFactors = FALSE)

      if (nrow(ioc_df_temp) > 1) {
        while (ncol(ioc_df_temp) < 4) ioc_df_temp <- cbind(ioc_df_temp, NA)

        ioc_data_rows <- ioc_df_temp[2:nrow(ioc_df_temp), 1:4]
        colnames(ioc_data_rows) <- c("silla", "pueblo", "tipo", "nombre")

        clean_ioc <- ioc_data_rows |>
          filter(!grepl("TIT./SUP.", tipo, ignore.case = TRUE)) |>
          fill(silla, pueblo, .direction = "down") |>
          filter(!is.na(silla))

        ioc_rows_list <- list()
        for (r in seq_len(nrow(clean_ioc))) {
          r_silla      <- clean_ioc$silla[r]
          r_pueblo     <- str_replace_all(clean_ioc$pueblo[r], "\n", " ")
          r_tipo       <- clean_ioc$tipo[r]
          r_nombre     <- clean_ioc$nombre[r]
          is_pendiente <- grepl("PENDIENTE", paste(r_tipo, r_nombre), ignore.case = TRUE)

          if (is_pendiente) {
            ioc_rows_list[[length(ioc_rows_list) + 1]] <- data.frame(
              municipio = muni_name, provincia = prov_name, autoridad = "CONCEJO IOC",
              pueblo = r_pueblo, silla = r_silla, tipo = "TITULAR",
              nombre = NA, pendiente = TRUE, stringsAsFactors = FALSE
            )
            ioc_rows_list[[length(ioc_rows_list) + 1]] <- data.frame(
              municipio = muni_name, provincia = prov_name, autoridad = "CONCEJO IOC",
              pueblo = r_pueblo, silla = r_silla, tipo = "SUPLENTE",
              nombre = NA, pendiente = TRUE, stringsAsFactors = FALSE
            )
          } else if (!is.na(r_tipo) && !is.na(r_nombre)) {
            ioc_rows_list[[length(ioc_rows_list) + 1]] <- data.frame(
              municipio = muni_name, provincia = prov_name, autoridad = "CONCEJO IOC",
              pueblo = r_pueblo, silla = r_silla, tipo = r_tipo,
              nombre = str_replace_all(r_nombre, "\n", " "), pendiente = FALSE,
              stringsAsFactors = FALSE
            )
          }
        }
        ioc_rows <- do.call(rbind, ioc_rows_list)
      }
    }
  }

  list(
    muni_name     = muni_name,
    prov_name     = prov_name,
    vote_df       = vote_df,
    alcalde_row   = alcalde_row,
    concejal_rows = concejal_rows,
    ioc_rows      = ioc_rows,
    has_ioc       = has_ioc
  )
}

# ==============================================================================
# IMPORT
# ==============================================================================

pdfplumber <- reticulate::import("pdfplumber")
pdf        <- pdfplumber$open("data/23-04-2026-part-1-y-2-V6_compressed.pdf")

# Master data structures
muni_roster_df     <- data.frame(municipality = character(), province = character(),
                                page = integer(), stringsAsFactors = FALSE)
muni_votes       <- list()
alcaldes_df      <- data.frame(municipio = character(), provincia = character(),
                                autoridad = character(), nombre = character(),
                                sigla = character(), stringsAsFactors = FALSE)
concejales_df    <- data.frame(municipio = character(), provincia = character(),
                                autoridad = character(), silla = character(),
                                tipo = character(), nombre = character(),
                                sigla = character(), stringsAsFactors = FALSE)
muni_concejal_ioc_df <- data.frame(municipio = character(), provincia = character(),
                                autoridad = character(), pueblo = character(),
                                silla = character(), tipo = character(),
                                nombre = character(), pendiente = logical(),
                                stringsAsFactors = FALSE)
error_log        <- data.frame(page = integer(), municipality_index = integer(),
                                error_message = character(), stringsAsFactors = FALSE)

total_pages <- length(pdf$pages)

for (page_num in 24:total_pages - 1) {
  message(sprintf("Processing page %d of %d...", page_num, total_pages))

  page <- tryCatch(pdf$pages[[page_num]], error = function(e) {
    error_log <<- rbind(error_log, data.frame(
      page = page_num, municipality_index = NA,
      error_message = paste("Failed to load page:", e$message), stringsAsFactors = FALSE))
    NULL
  })
  if (is.null(page)) next

  words_df <- tryCatch({
    map_dfr(page$extract_words(), ~ as.data.frame(.x))
  }, error = function(e) data.frame())

  if (nrow(words_df) == 0) {
    message(sprintf("--> Skipping page %d (no text layout detected)", page_num))
    next
  }

  top_anchors         <- words_df |> filter(text == "MUNICIPIO:") |> pull(top)
  bottom_anchors      <- words_df |> filter(text %in% c("ALCALDE", "ALCALDESA")) |> pull(top)
  # Extract N.º anchors, excluding any that align with IOC table headers
  n_anchors_df <- words_df |> filter(text %in% c("N.º", "N.°", "N°"))
  special_y_coords <- words_df |>
    filter(text %in% c("PUEBLO", "NACIÓN", "PUEBLOS", "NACIONES")) |>
    pull(top)
  if (length(special_y_coords) > 0) {
    valid_rows <- sapply(n_anchors_df$top, function(y) {
      !any(abs(y - special_y_coords) < 10)
    })
    n_anchors_df <- n_anchors_df[valid_rows, ]
  }
  left_anchors_raw    <- n_anchors_df |> pull(x0)
  column_top_anch_raw <- n_anchors_df |> pull(top)

  if (length(top_anchors) != length(bottom_anchors)) {
    warning(sprintf("Anchor mismatch on page %d: %d MUNICIPIO vs %d ALCALDE/S. Skipping.",
                    page_num, length(top_anchors), length(bottom_anchors)))
    error_log <- rbind(error_log, data.frame(
      page = page_num, municipality_index = NA,
      error_message = sprintf("Anchor count mismatch (Top: %d, Bottom: %d)",
                              length(top_anchors), length(bottom_anchors)),
      stringsAsFactors = FALSE))
    next
  }

  if (length(column_top_anch_raw) != 3 * length(top_anchors)) {
    warning(sprintf("Mismatch: 3 columns expected per municipality on page %d. Found: %d, groups: %d. Skipping.",
                    page_num, length(column_top_anch_raw), length(top_anchors)))
    error_log <- rbind(error_log, data.frame(
      page = page_num, municipality_index = NA,
      error_message = sprintf("Column anchor mismatch (Found: %d, Expected: %d)",
                              length(column_top_anch_raw), 3 * length(top_anchors)),
      stringsAsFactors = FALSE))
    next
  }

  left_anchors <- as_tibble(matrix(left_anchors_raw, ncol = 3, byrow = TRUE)) |>
    relocate(V3) |> setNames(c("left_col", "center_col", "right_col"))
  column_top_anchors <- as_tibble(matrix(column_top_anch_raw, ncol = 3, byrow = TRUE)) |>
    relocate(V3) |> setNames(c("left_col", "center_col", "right_col"))

  anchors <- list(
    top_anchors        = top_anchors,
    bottom_anchors     = bottom_anchors,
    left_anchors       = left_anchors,
    column_top_anchors = column_top_anchors
  )

  for (i in seq_along(top_anchors)) {
    tryCatch({
      result <- process_municipality(page, i, anchors, words_df)

      muni_roster_df <- rbind(muni_roster_df, data.frame(
        municipality = result$muni_name, province = result$prov_name,
        page = page_num, stringsAsFactors = FALSE))
      muni_votes[[length(muni_votes) + 1]] <- result$vote_df
      alcaldes_df <- rbind(alcaldes_df, result$alcalde_row)
      if (!is.null(result$concejal_rows))
        concejales_df <- rbind(concejales_df, result$concejal_rows)
      if (!is.null(result$ioc_rows))
        muni_concejal_ioc_df <- rbind(muni_concejal_ioc_df, result$ioc_rows)

    }, error = function(e) {
      message(sprintf("   [!] Error parsing municipality %d on page %d: %s",
                      i, page_num, e$message))
      error_log <<- rbind(error_log, data.frame(
        page = page_num, municipality_index = i,
        error_message = e$message, stringsAsFactors = FALSE))
    })
  }
}

pdf$close()

# ==============================================================================
# SAVE RAW RESULTS
# ==============================================================================
saveRDS(
  list(
    muni_votes        = muni_votes,
    concejales_df     = concejales_df,
    alcaldes_df       = alcaldes_df,
    muni_roster_df    = muni_roster_df,
    muni_concejal_ioc_df = muni_concejal_ioc_df,
    error_log         = error_log
  ),
  here::here("data", "oep2026_raw.rds")
)
message("Raw results saved to data/oep2026_raw.rds")
