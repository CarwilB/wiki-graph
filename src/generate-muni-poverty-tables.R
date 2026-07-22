# Generate poverty and basic services tables (HTML kable + Wikitable) for a municipality
# Source this script and call generate_poverty_service_tables(ine_code) to get both formats
#
# Returns: list(kable = kable_html, wikitable = wikitext_string)
#
# USAGE:
#   source("src/generate-muni-poverty-tables.R")
#   tables <- generate_poverty_service_tables(ine_code = "020101", 
#                                             muni_display_name = "La Paz",
#                                             dept_display_name = "La Paz")
#   tables$kable  # Render in Quarto/RMarkdown
#   cat(tables$wikitable)  # Print Wikitable text
#
# REQUIRED DATA (must be available in parent session):
#   - poverty_nbi_muni — Municipality poverty data (RDS; requires: ine_code, municipality, department, 
#                        poor_total_2012, poor_total_2024, ref_pop_nbi_2012, ref_pop_nbi_2024)
#   - improved_water_muni — Municipality water access (RDS; requires: ine_code, municipality, 
#                           pct_unimproved_water_2001, pct_unimproved_water_2024)
#   - improved_sanitation_muni — Municipality sanitation (RDS; requires: ine_code, municipality, 
#                               pct_unimproved_sanitation_2001, pct_unimproved_sanitation_2024)
#   - final_table — Department summary table with Bolivia row (data.frame; requires: department, 
#                  poverty_pct_2012, poverty_pct_2024, poverty_change, water_lack_2001, water_lack_2024, 
#                  water_change, sanitation_lack_2001, sanitation_lack_2024, sanitation_change)
#
# REQUIRED LIBRARIES:
#   - tidyverse (dplyr, purrr)
#   - kableExtra
#   - glue

# ============================================================================
# Helper functions for Wikitable formatting
# ============================================================================

format_change_wt <- function(x) {
  if(is.na(x)) return("-")
  if(x > 0) {
    sprintf("{{Increase}} +%.0f%%", x)
  } else if(x < 0) {
    sprintf("{{Decrease}} %.0f%%", x)
  } else {
    "0.0%"
  }
}

wikitext_shade <- function(value_pct, color) {
  if(is.na(value_pct)) return("-")
  sprintf("{{shade|color=%s|%s}}", color, value_pct)
}

# ============================================================================
# Main function: Generate both kable and wikitable for a municipality
# ============================================================================

#' Generate poverty and basic services tables for a municipality
#'
#' @param ine_code Character. 6-digit INE municipality code (e.g., "020101")
#' @param muni_display_name Character. Display name for municipality in tables
#'                         (optional; if not provided, will be inferred from data)
#' @param dept_display_name Character. Display name for department in tables
#'                         (optional; if not provided, will be inferred from data)
#'
#' @return List with two elements:
#'   - `kable`: HTML kable object (ready to print/render)
#'   - `wikitable`: Character string containing complete Wikitable markup
#'
#' @details
#' This function assumes the following data frames are available in the parent environment:
#'   - `poverty_nbi_muni`: Municipality-level poverty data (NBI) with ine_code column
#'   - `improved_water_muni`: Municipality-level water access with ine_code column
#'   - `improved_sanitation_muni`: Municipality-level sanitation with ine_code column
#'   - `final_table`: Department-level summary (includes Bolivia national row)
#'
#' Each table shows 3 rows:
#'   1. Municipality
#'   2. Department
#'   3. Bolivia (national)
#'
#' With 10 columns total:
#'   - Poverty (NBI) 2012, 2024, Change
#'   - Lack of Water Access 2001, 2024, Change
#'   - Lack of Sanitation Access 2001, 2024, Change

generate_poverty_service_tables <- function(ine_code, muni_display_name = NULL, dept_display_name = NULL) {

  # ========================================================================
  # 1. FETCH AND PREPARE DATA
  # ========================================================================

  # Get municipality data by INE code and compute poverty percentages
  muni_pov_raw <- poverty_nbi_muni |>
    filter(ine_code == !!ine_code) |>
    slice(1)

  # Compute poverty percentages if not already present
  if("poverty_pct_2012" %in% names(muni_pov_raw)) {
    # Already computed
    muni_pov <- muni_pov_raw
  } else {
    # Need to compute
    muni_pov <- muni_pov_raw |>
      mutate(
        poverty_pct_2012 = (poor_total_2012 / ref_pop_nbi_2012) * 100,
        poverty_pct_2024 = (poor_total_2024 / ref_pop_nbi_2024) * 100,
        poverty_change = poverty_pct_2024 - poverty_pct_2012
      )
  }

  # Get water access data (use pct_unimproved_water_* columns directly)
  muni_wat <- improved_water_muni |>
    filter(ine_code == !!ine_code) |>
    slice(1) |>
    select(ine_code, municipality, pct_unimproved_water_2001, pct_unimproved_water_2024) |>
    mutate(
      water_lack_2001 = pct_unimproved_water_2001,
      water_lack_2024 = pct_unimproved_water_2024,
      water_change = water_lack_2024 - water_lack_2001
    )

  # Get sanitation access data (use pct_unimproved_sanitation_* columns directly)
  muni_san <- improved_sanitation_muni |>
    filter(ine_code == !!ine_code) |>
    slice(1) |>
    select(ine_code, municipality, pct_unimproved_sanitation_2001, pct_unimproved_sanitation_2024) |>
    mutate(
      sanitation_lack_2001 = pct_unimproved_sanitation_2001,
      sanitation_lack_2024 = pct_unimproved_sanitation_2024,
      sanitation_change = sanitation_lack_2024 - sanitation_lack_2001
    )

  # If display names not provided, use data names
  if(is.null(muni_display_name)) muni_display_name <- muni_pov$municipality[1]
  if(is.null(dept_display_name)) dept_display_name <- muni_pov$department[1]

  # Get department data from final_table
  dept_pov <- final_table |>
    filter(department == dept_display_name) |>
    slice(1)

  # Get Bolivia national data
  bolivia_pov <- final_table |>
    filter(department == "Bolivia") |>
    slice(1)

  # Build base context table with raw values
  context_table <- tibble(
    location = c(muni_display_name, dept_display_name, "Bolivia"),
    poverty_pct_2012 = c(muni_pov$poverty_pct_2012[1], dept_pov$poverty_pct_2012[1], bolivia_pov$poverty_pct_2012[1]),
    poverty_pct_2024 = c(muni_pov$poverty_pct_2024[1], dept_pov$poverty_pct_2024[1], bolivia_pov$poverty_pct_2024[1]),
    poverty_change = c(muni_pov$poverty_change[1], dept_pov$poverty_change[1], bolivia_pov$poverty_change[1]),
    water_lack_2001 = c(muni_wat$water_lack_2001[1], dept_pov$water_lack_2001[1], bolivia_pov$water_lack_2001[1]),
    water_lack_2024 = c(muni_wat$water_lack_2024[1], dept_pov$water_lack_2024[1], bolivia_pov$water_lack_2024[1]),
    water_change = c(muni_wat$water_change[1], dept_pov$water_change[1], bolivia_pov$water_change[1]),
    sanitation_lack_2001 = c(muni_san$sanitation_lack_2001[1], dept_pov$sanitation_lack_2001[1], bolivia_pov$sanitation_lack_2001[1]),
    sanitation_lack_2024 = c(muni_san$sanitation_lack_2024[1], dept_pov$sanitation_lack_2024[1], bolivia_pov$sanitation_lack_2024[1]),
    sanitation_change = c(muni_san$sanitation_change[1], dept_pov$sanitation_change[1], bolivia_pov$sanitation_change[1])
  )

  # ========================================================================
  # 2. BUILD HTML KABLE
  # ========================================================================

  display_table <- context_table |>
    mutate(
      row_num = row_number(),
      p_12 = sprintf("%.0f%%", poverty_pct_2012),
      p_24 = sprintf("%.0f%%", poverty_pct_2024),
      p_ch = if_else(poverty_change > 0, sprintf("+%.0f%%", poverty_change), sprintf("%.0f%%", poverty_change)),
      w_01 = sprintf("%.0f%%", water_lack_2001),
      w_24 = sprintf("%.0f%%", water_lack_2024),
      w_ch = if_else(water_change > 0, sprintf("+%.0f%%", water_change), sprintf("%.0f%%", water_change)),
      s_01 = sprintf("%.0f%%", sanitation_lack_2001),
      s_24 = sprintf("%.0f%%", sanitation_lack_2024),
      s_ch = if_else(sanitation_change > 0, sprintf("+%.0f%%", sanitation_change), sprintf("%.0f%%", sanitation_change)),
      # Add " Department" suffix to row 2 (department) if names match
      location = case_when(
        row_num == 2 & muni_display_name == dept_display_name ~ paste0(location, " Department"),
        TRUE ~ location
      )
    ) |>
    select(location, p_12, p_24, p_ch, w_01, w_24, w_ch, s_01, s_24, s_ch) |>
    rename(`Location` = location)

  kable_html <- display_table |>
    kbl(
      caption = paste("Poverty and Basic Services:", muni_display_name, "Municipality"),
      col.names = c(
        "Location",
        "2012", "2024", "Change",
        "2001", "2024", "Change",
        "2001", "2024", "Change"
      ),
      align = "lcccccccccc",
      escape = FALSE
    ) |>
    kable_classic(full_width = FALSE) |>
    add_header_above(c(
      " " = 1,
      "Poverty (NBI)" = 3,
      "Lack of Water Access" = 3,
      "Lack of Sanitation Access" = 3
    )) |>
    column_spec(1, border_right = TRUE) |>
    column_spec(4, border_right = TRUE) |>
    column_spec(7, border_right = TRUE)

  # ========================================================================
  # 3. BUILD WIKITABLE
  # ========================================================================

  # Format raw values for Wikitable with color shading and change indicators
  wikitable_rows <- context_table |>
    mutate(
      p_12_wt = map_chr(poverty_pct_2012, ~wikitext_shade(sprintf("%.0f%%", .), "red")),
      p_24_wt = map_chr(poverty_pct_2024, ~wikitext_shade(sprintf("%.0f%%", .), "red")),
      p_ch_wt = map_chr(poverty_change, format_change_wt),
      w_01_wt = map_chr(water_lack_2001, ~wikitext_shade(sprintf("%.0f%%", .), "blue")),
      w_24_wt = map_chr(water_lack_2024, ~wikitext_shade(sprintf("%.0f%%", .), "blue")),
      w_ch_wt = map_chr(water_change, format_change_wt),
      s_01_wt = map_chr(sanitation_lack_2001, ~wikitext_shade(sprintf("%.0f%%", .), "green")),
      s_24_wt = map_chr(sanitation_lack_2024, ~wikitext_shade(sprintf("%.0f%%", .), "green")),
      s_ch_wt = map_chr(sanitation_change, format_change_wt)
    ) |>
    select(
      location,
      p_12_wt, p_24_wt, p_ch_wt,
      w_01_wt, w_24_wt, w_ch_wt,
      s_01_wt, s_24_wt, s_ch_wt
    )

  # Build Wikitable header
  wt_header <- paste0(
    "{| class=\"wikitable\"\n",
    "|+ ", muni_display_name, " Municipality: Poverty and Basic Service Access\n",
    "|-\n",
    "! align=left | Location !! colspan=3 | Poverty (NBI) !! colspan=3 | Lack of Water Access !! colspan=3 | Lack of Sanitation Access\n",
    "|-\n",
    "! align=left | !! 2012 !! 2024 !! Change !! 2001 !! 2024 !! Change !! 2001 !! 2024 !! Change\n"
  )

  # Build rows with municipality in bold
  wt_rows <- wikitable_rows |>
    mutate(
      row_num = row_number(),
      # Bold municipality name; add " Department" to department row if names match
      dept_display = case_when(
        row_num == 1 ~ paste0("'''", location, "'''"),  # First row: municipality in bold
        row_num == 2 & location == muni_display_name ~ paste0(location, " Department"),  # Second row: dept with suffix if matches muni
        TRUE ~ location
      )
    ) |>
    glue_data("|-\n| align=left | {dept_display} || {p_12_wt} || {p_24_wt} || {p_ch_wt} || {w_01_wt} || {w_24_wt} || {w_ch_wt} || {s_01_wt} || {s_24_wt} || {s_ch_wt}")

  # Source row with citations
  source_text <- "NBI indicates a Unsatisfied Basic Needs definition for poverty. '''Source:''' [[National Institute of Statistics of Bolivia|INE Bolivia]], 2024 Bolivian Census"
  source_refs <- '{{Cite| last = Instituto Nacional de Estadística| title = Pobreza: Tabulados por Municipio/TIOC| access-date = 2026-07-22| date = 2025| url = https://nube.ine.gob.bo/index.php/s/KQSoTrfdRQ5jldM/download}}<br/>{{Cite| last = Instituto Nacional de Estadística| title = Servicios Básicos: Tabulados por Municipio/TIOC| access-date = 2026-07-22| date = 2025| url = https://nube.ine.gob.bo/index.php/s/dEJeTU4j0czYIdG/download}}'
  source_line <- paste0('|-\n|colspan="10"|', source_text, '<ref>', source_refs, '</ref>')

  wt_footer <- paste0("\n", source_line, "\n|}")

  wikitable_text <- paste0(wt_header, paste(wt_rows, collapse = "\n"), wt_footer)

  # ========================================================================
  # 4. RETURN BOTH FORMATS
  # ========================================================================

  return(
    list(
      kable = kable_html,
      wikitable = wikitable_text
    )
  )
}
