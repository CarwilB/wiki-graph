#!/usr/bin/env Rscript
# Extract figures from rendered HTML documents and create PowerPoint slide deck

library(tidyverse)
library(officer)
library(magick)
library(xml2)

PROJECT_DIR <- "/Users/bjorkjcr/Dropbox (Personal)/R/wiki-graph"
OUTPUT_DIR <- file.path(PROJECT_DIR, "output")
TEMP_DIR <- file.path(OUTPUT_DIR, "extracted_images")

dir.create(OUTPUT_DIR, showWarnings = FALSE)
dir.create(TEMP_DIR, showWarnings = FALSE)

# List of rendered HTML files
html_files <- c(
  "eg2025-resultados.html",
  "albo-restudy-2024.html",
  "lapop-census-identity-comparison.html",
  "bolivia-censo-2024.html"
)

# Function to extract base64 images and convert to PNG
extract_images_from_html <- function(html_file, output_prefix) {
  cat(sprintf("Extracting from: %s\n", html_file))
  
  html_path <- file.path(PROJECT_DIR, html_file)
  
  if (!file.exists(html_path)) {
    warning(sprintf("File not found: %s", html_path))
    return(NULL)
  }
  
  # Read HTML
  html_text <- paste(readLines(html_path, warn = FALSE), collapse = "\n")
  
  # Extract PNG base64 data URIs
  png_pattern <- 'data:image/png;base64,([A-Za-z0-9+/=]+)'
  png_matches <- gregexpr(png_pattern, html_text)
  
  images <- character()
  img_count <- 0
  
  if (png_matches[[1]][1] > 0) {
    png_strings <- regmatches(html_text, png_matches)[[1]]
    
    for (i in seq_along(png_strings)) {
      # Extract base64 data
      base64_str <- sub('^data:image/png;base64,', '', png_strings[i])
      
      tryCatch({
        # Decode base64 to raw bytes
        raw_data <- base64enc::base64decode(base64_str)
        
        # Write to PNG file
        img_count <- img_count + 1
        png_file <- file.path(TEMP_DIR, sprintf("%s_%03d.png", output_prefix, img_count))
        writeBin(raw_data, png_file)
        
        # Verify file was written
        if (file.exists(png_file) && file.size(png_file) > 0) {
          cat(sprintf("  ✓ Extracted: %s (%d bytes)\n", basename(png_file), file.size(png_file)))
          images <- c(images, png_file)
        }
      }, error = function(e) {
        cat(sprintf("  ✗ Error extracting image %d: %s\n", i, e$message))
      })
    }
  }
  
  # Also try SVG to PNG conversion
  svg_pattern <- 'data:image/svg\\+xml;base64,([A-Za-z0-9+/=]+)'
  svg_matches <- gregexpr(svg_pattern, html_text)
  
  if (svg_matches[[1]][1] > 0) {
    svg_strings <- regmatches(html_text, svg_matches)[[1]]
    
    for (i in seq_along(svg_strings)) {
      base64_str <- sub('^data:image/svg\\+xml;base64,', '', svg_strings[i])
      
      tryCatch({
        raw_data <- base64enc::base64decode(base64_str)
        
        img_count <- img_count + 1
        svg_file <- file.path(TEMP_DIR, sprintf("%s_svg_%03d.svg", output_prefix, img_count))
        writeLines(rawToChar(raw_data), svg_file)
        
        # Convert SVG to PNG
        img <- image_read_svg(svg_file)
        png_file <- str_replace(svg_file, "\\.svg$", ".png")
        image_write(img, png_file, format = "png")
        
        if (file.exists(png_file)) {
          cat(sprintf("  ✓ Converted SVG: %s\n", basename(png_file)))
          images <- c(images, png_file)
        }
        
        unlink(svg_file)
      }, error = function(e) {
        cat(sprintf("  ✗ Error converting SVG %d: %s\n", i, e$message))
      })
    }
  }
  
  return(images)
}

cat("Extracting images from HTML documents...\n\n")

all_images <- character()

for (html_file in html_files) {
  output_prefix <- sub("\\.html$", "", html_file)
  images <- extract_images_from_html(html_file, output_prefix)
  all_images <- c(all_images, images)
}

cat(sprintf("\nTotal images extracted: %d\n", length(all_images)))

if (length(all_images) == 0) {
  cat("ERROR: No images extracted from HTML files.\n")
  cat("This may mean the Quarto rendering didn't include figures.\n")
  quit(status = 1)
}

# Create PowerPoint presentation
cat("\nCreating PowerPoint presentation...\n")

prs <- read_pptx()

# Add title slide
blank_slide_layout <- prs$slide_layouts[[6]]  # Blank layout
prs <- add_slide(prs, blank_slide_layout)

# Add title manually
prs <- ph_with(prs, "Bolivia Census & Election Graphics",
               location = ph_location(left = 0.5, top = 2.5, width = 9, height = 1))

prs <- ph_with(prs, "JCR Björk",
               location = ph_location(left = 0.5, top = 4, width = 9, height = 0.5))

# Add one image per slide
for (i in seq_along(all_images)) {
  img_path <- all_images[i]
  
  cat(sprintf("  [%d/%d] Adding: %s\n", i, length(all_images), basename(img_path)))
  
  # Get image dimensions
  img_info <- image_info(image_read(img_path))
  img_width_px <- as.numeric(img_info$width[1])
  img_height_px <- as.numeric(img_info$height[1])
  
  # PowerPoint slide is 10 x 7.5 inches
  slide_width <- 10
  slide_height <- 7.5
  margin <- 0.25
  
  max_width <- slide_width - (2 * margin)
  max_height <- slide_height - (2 * margin)
  
  aspect_ratio <- img_width_px / img_height_px
  
  if ((max_width / max_height) > aspect_ratio) {
    # Height is limiting
    img_height_in <- max_height
    img_width_in <- img_height_in * aspect_ratio
  } else {
    # Width is limiting
    img_width_in <- max_width
    img_height_in <- img_width_in / aspect_ratio
  }
  
  # Center on slide
  left_in <- (slide_width - img_width_in) / 2
  top_in <- (slide_height - img_height_in) / 2
  
  # Add blank slide and image
  prs <- add_slide(prs, blank_slide_layout)
  prs <- ph_with(prs,
                 external_img(img_path, width = img_width_in, height = img_height_in),
                 location = ph_location(left = left_in, top = top_in))
}

# Save presentation
output_path <- file.path(OUTPUT_DIR, "Bolivia_Graphics_Deck.pptx")
print(prs, target = output_path)

cat(sprintf("\n✓ PowerPoint created successfully!\n"))
cat(sprintf("  Path: %s\n", output_path)  )
cat(sprintf("  Total slides: %d\n", length(prs$slides)))

cat("\nDone!\n")
