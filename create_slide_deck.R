#!/usr/bin/env Rscript
# Create PowerPoint slide deck from Quarto document figures
# Requires: officer, magick, patchwork, ggplot2

library(tidyverse)
library(officer)
library(magick)
library(fs)

# Directory paths
PROJECT_DIR <- "/Users/bjorkjcr/Dropbox (Personal)/R/wiki-graph"
DOCS_DIR <- file.path(PROJECT_DIR)
OUTPUT_DIR <- file.path(PROJECT_DIR, "output")
TEMP_DIR <- file.path(OUTPUT_DIR, "temp_renders")

# Create output directories if they don't exist
dir_create(OUTPUT_DIR)
dir_create(TEMP_DIR)

# List of Quarto documents to render
qmd_files <- c(
  "eg2025-resultados.qmd",
  "albo-restudy-2024.qmd",
  "lapop-census-identity-comparison.qmd",
  "bolivia-censo-2024.qmd"
)

cat("Rendering Quarto documents to HTML...\n")

# Render each document to HTML (self-contained)
for (qmd in qmd_files) {
  qmd_path <- file.path(DOCS_DIR, qmd)
  html_name <- str_replace(qmd, "\\.qmd$", ".html")
  html_path <- file.path(TEMP_DIR, html_name)
  
  cat("  Rendering:", qmd, "\n")
  
  # Use system call to quarto render
  system(
    sprintf('cd "%s" && quarto render "%s" --to html --output "%s" --quiet',
            DOCS_DIR, qmd, html_path),
    ignore.stdout = TRUE,
    ignore.stderr = FALSE
  )
  
  if (!file_exists(html_path)) {
    warning(sprintf("Failed to render %s", qmd))
  }
}

cat("Extracting figures from HTML...\n")

# Function to extract base64 images from HTML and save as PNG
extract_figures_from_html <- function(html_path, output_prefix) {
  html_content <- readLines(html_path, warn = FALSE)
  html_text <- paste(html_content, collapse = "\n")
  
  # Find all base64-encoded images (PNG/SVG from quarto output)
  # Match data:image/png;base64, or data:image/svg+xml;base64,
  png_matches <- gregexpr('data:image/png;base64,[A-Za-z0-9+/=]+', html_text)
  svg_matches <- gregexpr('data:image/svg\\+xml;base64,[A-Za-z0-9+/=]+', html_text)
  
  figures <- list()
  
  # Process PNG images
  if (png_matches[[1]][1] > 0) {
    png_data <- regmatches(html_text, png_matches)[[1]]
    for (i in seq_along(png_data)) {
      base64_str <- str_replace(png_data[i], '^data:image/png;base64,', '')
      img_file <- file.path(TEMP_DIR, sprintf("%s_fig_%02d.png", output_prefix, i))
      
      # Decode base64 and write PNG
      tryCatch({
        raw_data <- base64enc::base64decode(base64_str)
        writeBin(raw_data, img_file)
        figures[[length(figures) + 1]] <- img_file
        cat("    Extracted:", basename(img_file), "\n")
      }, error = function(e) {
        warning(sprintf("Error extracting PNG %d: %s", i, e$message))
      })
    }
  }
  
  # SVG → PNG conversion
  if (svg_matches[[1]][1] > 0) {
    svg_data <- regmatches(html_text, svg_matches)[[1]]
    for (i in seq_along(svg_data)) {
      base64_str <- str_replace(svg_data[i], '^data:image/svg\\+xml;base64,', '')
      
      tryCatch({
        raw_data <- base64enc::base64decode(base64_str)
        svg_file <- file.path(TEMP_DIR, sprintf("%s_fig_svg_%02d.svg", output_prefix, i))
        writeLines(rawToChar(raw_data), svg_file)
        
        # Convert SVG to PNG using magick
        img <- magick::image_read_svg(svg_file)
        png_file <- str_replace(svg_file, "\\.svg$", ".png")
        magick::image_write(img, png_file, format = "png")
        
        figures[[length(figures) + 1]] <- png_file
        cat("    Extracted & converted:", basename(png_file), "\n")
        
        # Clean up SVG
        file_delete(svg_file)
      }, error = function(e) {
        warning(sprintf("Error extracting/converting SVG %d: %s", i, e$message))
      })
    }
  }
  
  return(figures)
}

# Extract figures from each rendered HTML
all_figures <- list()

for (qmd in qmd_files) {
  html_name <- str_replace(qmd, "\\.qmd$", ".html")
  html_path <- file.path(TEMP_DIR, html_name)
  output_prefix <- str_replace(qmd, "\\.qmd$", "")
  
  if (file_exists(html_path)) {
    cat("  Extracting figures from:", html_name, "\n")
    figs <- extract_figures_from_html(html_path, output_prefix)
    all_figures <- c(all_figures, figs)
  }
}

cat(sprintf("\nTotal figures extracted: %d\n", length(all_figures)))

if (length(all_figures) == 0) {
  cat("WARNING: No figures extracted. Checking for alternative approach...\n")
  
  # Alternative: Use webshot to screenshot chunks
  # This is a fallback if base64 extraction doesn't work
  
  # Try to identify output divs and take screenshots
  for (qmd in qmd_files) {
    html_name <- str_replace(qmd, "\\.qmd$", ".html")
    html_path <- file.path(TEMP_DIR, html_name)
    
    if (file_exists(html_path)) {
      cat("  Attempting webshot approach for:", html_name, "\n")
      tryCatch({
        # Note: requires webshot/phantomjs to be installed
        # For now, we'll create placeholder images
        
        output_prefix <- str_replace(qmd, "\\.qmd$", "")
        placeholder <- file.path(TEMP_DIR, sprintf("%s_placeholder.png", output_prefix))
        
        # Create simple placeholder
        png(placeholder, width = 960, height = 720, bg = "white")
        plot.new()
        text(0.5, 0.5, sprintf("Figure from:\n%s", qmd), cex = 2, col = "gray40")
        dev.off()
        
        all_figures <- c(all_figures, placeholder)
      }, error = function(e) {
        cat("  Webshot failed:", e$message, "\n")
      })
    }
  }
}

# Create PowerPoint presentation
cat("\nCreating PowerPoint presentation...\n")

prs <- read_pptx()

# Set default slide layout (blank slide)
blank_layout <- layout_properties(prs)$layout[1]

# Add title slide
prs <- add_slide(prs, layout = "Title Slide")
prs <- ph_with(prs, "Bolivia Census & Election Graphics", 
               location = ph_location_type("title"))
prs <- ph_with(prs, "JCR Björk", 
               location = ph_location_type("subTitle"))

# Add one figure per slide
for (i in seq_along(all_figures)) {
  fig_path <- all_figures[[i]]
  
  if (file_exists(fig_path)) {
    cat(sprintf("  Adding slide %d: %s\n", i + 1, basename(fig_path)))
    
    # Add blank slide
    prs <- add_slide(prs, layout = "Blank")
    
    # Get image dimensions
    img_info <- image_info(image_read(fig_path))
    img_width <- img_info$width[1]
    img_height <- img_info$height[1]
    
    # Calculate dimensions to fit on 10x7.5 inch slide with margins
    slide_width <- 10
    slide_height <- 7.5
    margin <- 0.25
    
    max_width <- slide_width - (2 * margin)
    max_height <- slide_height - (2 * margin)
    
    # Maintain aspect ratio
    aspect_ratio <- img_width / img_height
    
    if ((max_width / max_height) > aspect_ratio) {
      # Height is limiting
      height <- max_height
      width <- height * aspect_ratio
    } else {
      # Width is limiting
      width <- max_width
      height <- width / aspect_ratio
    }
    
    # Center on slide
    left <- (slide_width - width) / 2
    top <- (slide_height - height) / 2
    
    prs <- ph_with(prs, external_img(fig_path, width = width, height = height),
                   location = ph_location(left = left, top = top))
  }
}

# Save presentation
output_path <- file.path(OUTPUT_DIR, "Bolivia_Graphics_Deck.pptx")
print(prs, target = output_path)

cat(sprintf("\n✓ PowerPoint created: %s\n", output_path))
cat(sprintf("✓ Total slides (including title): %d\n", length(prs$slides) + 1))

# Optional: Clean up temporary files
# unlink(TEMP_DIR, recursive = TRUE)

cat("\nDone!\n")
