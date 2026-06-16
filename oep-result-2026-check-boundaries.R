library(reticulate)
library(dplyr)
library(purrr)
library(stringr)

# Requires: concejal_summary, ioc_munis (from cleaning script)
# Run oep-results-2026.R + oep-results-2026-cleaning.R first.

pdfplumber <- reticulate::import("pdfplumber")
pdf        <- pdfplumber$open("data/23-04-2026-part-1-y-2-V6_compressed.pdf")

total_pages <- length(pdf$pages)

# ==============================================================================
# HELPER: build boxes for one municipality on a page
# Mirrors oep-results-2026.R exactly, including IOC truncation.
# words_df: word-level extract for the page (used for IOC detection)
# ==============================================================================
build_boxes <- function(page, i, top_anchors, bottom_anchors,
                        left_anchors, column_top_anchors, words_df) {
  true_section_bottom <- if (i < length(top_anchors)) top_anchors[i + 1] - 5 else page$height
  section_bottom      <- true_section_bottom

  # Detect IOC table (same logic as process_municipality)
  indigenous_table_y <- words_df |>
    filter(text == "NACIONES", top > bottom_anchors[i], top < section_bottom) |>
    pull(top)
  has_ioc <- length(indigenous_table_y) > 0
  if (has_ioc) section_bottom <- min(indigenous_table_y) - 5

  l_anch2 <- as.numeric(left_anchors[i, 2]) - 5
  l_anch3 <- as.numeric(left_anchors[i, 3]) - 5
  c_top1  <- as.numeric(column_top_anchors[i, 1]) - 8
  c_top2  <- as.numeric(column_top_anchors[i, 2]) - 8
  c_top3  <- as.numeric(column_top_anchors[i, 3]) - 8

  boxes <- list(
    muni_box  = list(0,           top_anchors[i] - 5,    page$width,   bottom_anchors[i] - 5),
    mayor_box = list(0,           bottom_anchors[i] - 3, l_anch2 - 5,  c_top1),
    left_box  = list(0,           c_top1,                l_anch2 - 2,  section_bottom),
    mid_box   = list(l_anch2 - 3, c_top2,                l_anch3 - 2,  section_bottom),
    right_box = list(l_anch3 - 5, c_top3,                page$width,   section_bottom),
    ioc_box   = if (has_ioc)
                  list(0, min(indigenous_table_y) - 5, page$width, true_section_bottom)
                else NULL
  )
  boxes
}

# ==============================================================================
# HELPER: extract anchors from a page's word list
# ==============================================================================
get_anchors <- function(page) {
  words_raw <- page$extract_words()
  words_df  <- map_dfr(words_raw, ~ as.data.frame(.x))

  top_anchors          <- words_df |> filter(text == "MUNICIPIO:") |> pull(top)
  bottom_anchors       <- words_df |> filter(text %in% c("ALCALDE", "ALCALDESA")) |> pull(top)
  left_anchors_raw     <- words_df |> filter(text %in% c("N.º", "N.°", "N°")) |> pull(x0)
  column_top_anch_raw  <- words_df |> filter(text %in% c("N.º", "N.°", "N°")) |> pull(top)

  # Validate
  n_muni <- length(top_anchors)
  if (length(bottom_anchors) != n_muni) return(NULL)
  if (length(column_top_anch_raw) != 3 * n_muni) return(NULL)

  left_anchors <- as_tibble(matrix(left_anchors_raw,    ncol = 3, byrow = TRUE)) |>
    relocate(V3) |> setNames(c("left_col", "center_col", "right_col"))
  column_top_anchors <- as_tibble(matrix(column_top_anch_raw, ncol = 3, byrow = TRUE)) |>
    relocate(V3) |> setNames(c("left_col", "center_col", "right_col"))

  list(
    words_df           = words_df,
    top_anchors        = top_anchors,
    bottom_anchors     = bottom_anchors,
    left_anchors       = left_anchors,
    column_top_anchors = column_top_anchors
  )
}

# ==============================================================================
# HELPER: draw boxes and save debug image for one page
# ==============================================================================
render_debug_page <- function(page, page_num, anchors, label = "") {
  img <- page$to_image(resolution = 150L)

  for (i in seq_along(anchors$top_anchors)) {
    boxes <- build_boxes(page, i,
                         anchors$top_anchors, anchors$bottom_anchors,
                         anchors$left_anchors, anchors$column_top_anchors,
                         anchors$words_df)
    img$draw_rect(boxes$muni_box,  stroke = "red",    stroke_width = 2L)
    img$draw_rect(boxes$mayor_box, stroke = "purple", stroke_width = 2L)
    img$draw_rect(boxes$left_box,  stroke = "blue",   stroke_width = 1L)
    img$draw_rect(boxes$mid_box,   stroke = "blue",   stroke_width = 1L)
    img$draw_rect(boxes$right_box, stroke = "green",  stroke_width = 2L)
    if (!is.null(boxes$ioc_box))
      img$draw_rect(boxes$ioc_box, stroke = "orange", stroke_width = 2L)
  }

  slug  <- if (nchar(label) > 0) paste0("_", str_replace_all(label, "[^A-Za-z0-9]", "_")) else ""
  fname <- sprintf("data/debug_page_%03d%s.png", page_num, slug)
  img$save(fname, format = "PNG")
  message(sprintf("  Saved: %s", fname))
  fname
}

# ==============================================================================
# MODE A — single page inspection (set target_page_num)
# ==============================================================================
target_page_num <- 71

page    <- pdf$pages[[target_page_num]]
anchors <- get_anchors(page)
result <- process_municipality(page, 4, anchors, anchors$words_df)
result$concejal_rows
if (is.null(anchors)) {
  message("Anchor mismatch on page ", target_page_num, " — skipping.")
} else {
  render_debug_page(page, target_page_num, anchors)
}

# ==============================================================================
# MODE B — render debug images for problem municipalities
# Requires: concejal_summary, ioc_munis, muni_roster (from cleaning script).
# muni_roster$page gives the PDF page for each municipality — no scanning needed.
# ==============================================================================

problem_munis_df <- concejal_summary |>
  filter(!(municipio %in% ioc_munis)) |>
  filter(!n_sillas %in% c(5, 7, 9, 11)) |>
  left_join(muni_roster, by = c("municipio" = "municipality",
                                 "provincia" = "province"))

message(sprintf("Rendering debug images for %d problem municipalities...",
                nrow(problem_munis_df)))

for (row in seq_len(nrow(problem_munis_df))) {
  muni     <- problem_munis_df$municipio[row]
  page_num <- problem_munis_df$page[row]

  if (is.na(page_num)) {
    message(sprintf("  No page found for %s — skipping.", muni))
    next
  }

  message(sprintf("  Page %d: %s", page_num, muni))
  page    <- pdf$pages[[page_num]]
  anchors <- get_anchors(page)

  if (is.null(anchors)) {
    message("    Anchor mismatch — skipping render.")
    next
  }

  render_debug_page(page, page_num, anchors, label = muni)
}

pdf$close()
message("Done.")
