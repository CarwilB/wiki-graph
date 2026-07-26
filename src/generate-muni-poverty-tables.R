# Generate poverty and basic services tables (HTML kable + Wikitable) for a municipality
# Source this script and call generate_poverty_service_tables(ine_code) to get both formats.
#
# Returns: list(kable = kable_html, wikitable = wikitext_string)
#
# USAGE:
#   source("src/generate-muni-poverty-tables.R")
#   tables <- generate_poverty_service_tables("020101")
#   tables$kable        # Render in Quarto/RMarkdown
#   cat(tables$wikitable)  # Print wikitext
#
# REQUIRED LIBRARIES: tidyverse, kableExtra, glue

# ============================================================================
# Auto-load required datasets
# ============================================================================
# Builds poverty_data_dept and poverty_data_muni from the three raw RDS files
# if they are not already present in the session.

.build_poverty_data_dept <- function() {
  poverty_nbi_dept       <- readRDS("data/cpv2024/poverty_nbi_dept.rds")
  improved_water_dept    <- readRDS("data/cpv2024/improved_water_dept.rds")
  improved_sanitation_dept <- readRDS("data/cpv2024/improved_sanitation_dept.rds")

  poverty_tab <- poverty_nbi_dept |>
    mutate(
      poverty_pct_2012 = (poor_total_2012 / ref_pop_nbi_2012) * 100,
      poverty_pct_2024 = (poor_total_2024 / ref_pop_nbi_2024) * 100,
      poverty_change   = poverty_pct_2024 - poverty_pct_2012
    ) |>
    select(department, poverty_pct_2012, poverty_pct_2024, poverty_change)

  water_tab <- improved_water_dept |>
    mutate(
      water_lack_2001 = pct_unimproved_water_2001,
      water_lack_2024 = pct_unimproved_water_2024,
      water_change    = water_lack_2024 - water_lack_2001
    ) |>
    select(department, water_lack_2001, water_lack_2024, water_change)

  sanitation_tab <- improved_sanitation_dept |>
    mutate(
      sanitation_lack_2001 = pct_unimproved_sanitation_2001,
      sanitation_lack_2024 = pct_unimproved_sanitation_2024,
      sanitation_change    = sanitation_lack_2024 - sanitation_lack_2001
    ) |>
    select(department, sanitation_lack_2001, sanitation_lack_2024, sanitation_change)

  # National totals (weighted from counts, not mean of dept percentages)
  country_row <- poverty_nbi_dept |>
    summarise(
      poverty_pct_2012 = sum(poor_total_2012) / sum(ref_pop_nbi_2012) * 100,
      poverty_pct_2024 = sum(poor_total_2024) / sum(ref_pop_nbi_2024) * 100,
      poverty_change   = poverty_pct_2024 - poverty_pct_2012,
      department       = "Bolivia"
    ) |>
    left_join(
      improved_water_dept |>
        summarise(
          water_lack_2001 = sum(n_unimproved_water_2001) / sum(n_total_2001) * 100,
          water_lack_2024 = sum(n_unimproved_water_2024) / sum(n_total_2024) * 100,
          water_change    = water_lack_2024 - water_lack_2001,
          department      = "Bolivia"
        ),
      by = "department"
    ) |>
    left_join(
      improved_sanitation_dept |>
        summarise(
          sanitation_lack_2001 = sum(n_unimproved_sanitation_2001) / sum(n_total_2001) * 100,
          sanitation_lack_2024 = sum(n_unimproved_sanitation_2024) / sum(n_total_2024) * 100,
          sanitation_change    = sanitation_lack_2024 - sanitation_lack_2001,
          department           = "Bolivia"
        ),
      by = "department"
    )

  poverty_tab |>
    left_join(water_tab, by = "department") |>
    left_join(sanitation_tab, by = "department") |>
    bind_rows(country_row) |>
    mutate(sort_key = if_else(department == "Bolivia", 999L, 0L)) |>
    arrange(sort_key, department) |>
    select(-sort_key)
}

.build_poverty_data_muni <- function() {
  poverty_nbi_muni       <- readRDS("data/cpv2024/poverty_nbi_muni.rds")
  improved_water_muni    <- readRDS("data/cpv2024/improved_water_muni.rds")
  improved_sanitation_muni <- readRDS("data/cpv2024/improved_sanitation_muni.rds")

  poverty_tab <- poverty_nbi_muni |>
    mutate(
      poverty_pct_2012 = (poor_total_2012 / ref_pop_nbi_2012) * 100,
      poverty_pct_2024 = (poor_total_2024 / ref_pop_nbi_2024) * 100,
      poverty_change   = poverty_pct_2024 - poverty_pct_2012
    ) |>
    select(ine_code, municipality, department, poverty_pct_2012, poverty_pct_2024, poverty_change)

  water_tab <- improved_water_muni |>
    mutate(
      water_lack_2001 = pct_unimproved_water_2001,
      water_lack_2024 = pct_unimproved_water_2024,
      water_change    = water_lack_2024 - water_lack_2001
    ) |>
    select(ine_code, municipality, water_lack_2001, water_lack_2024, water_change)

  sanitation_tab <- improved_sanitation_muni |>
    mutate(
      sanitation_lack_2001 = pct_unimproved_sanitation_2001,
      sanitation_lack_2024 = pct_unimproved_sanitation_2024,
      sanitation_change    = sanitation_lack_2024 - sanitation_lack_2001
    ) |>
    select(ine_code, municipality, sanitation_lack_2001, sanitation_lack_2024, sanitation_change)

  poverty_tab |>
    left_join(water_tab, by = c("ine_code", "municipality")) |>
    left_join(sanitation_tab, by = c("ine_code", "municipality"))
}

if (!exists("poverty_data_dept")) {
  rds_path <- here::here("data", "cpv2024", "poverty_water_sanitation_dept.rds")
  if (file.exists(rds_path)) {
    message("Loading poverty_data_dept from RDS...")
    poverty_data_dept <- readRDS(rds_path)
  } else {
    message("Building poverty_data_dept from raw RDS files...")
    poverty_data_dept <- .build_poverty_data_dept()
  }
}

if (!exists("poverty_data_muni")) {
  rds_path <- here::here("data", "cpv2024", "poverty_water_sanitation_muni.rds")
  if (file.exists(rds_path)) {
    message("Loading poverty_data_muni from RDS...")
    poverty_data_muni <- readRDS(rds_path)
  } else {
    message("Building poverty_data_muni from raw RDS files...")
    poverty_data_muni <- .build_poverty_data_muni()
  }
}

# ============================================================================
# Formatting helpers
# ============================================================================

format_pct <- function(x) ifelse(is.na(x), "-", sprintf("%.0f%%", x))

format_chg <- function(x) {
  if (is.na(x)) return("-")
  paste0(if (x > 0) "+" else "", sprintf("%.0f%%", x))
}

format_change_wt <- function(x) {
  if (is.na(x)) return("-")
  if (x > 0) sprintf("{{Increase}} +%.0f%%", x)
  else if (x < 0) sprintf("{{Decrease}} %.0f%%", x)
  else "0.0%"
}

wikitext_shade <- function(value_pct, color) {
  if (is.na(value_pct)) return("-")
  numeric_val <- floor(as.numeric(gsub("%", "", value_pct)))
  sprintf("{{shade|color=%s|%s}}%%", color, numeric_val)
}

# ============================================================================
# Context table helpers (municipality | department | Bolivia)
# ============================================================================

.create_muni_context_table <- function(ine_code, muni_display_name=NULL, dept_display_name=NULL) {
  # Resolve display names from data if not supplied
  if (is.null(muni_display_name) || is.null(dept_display_name)) {
    muni_meta <- poverty_data_muni |>
      filter(ine_code == !!ine_code) |>
      slice(1)
    if (is.null(muni_display_name)) muni_display_name <- muni_meta$municipality
    if (is.null(dept_display_name)) dept_display_name <- muni_meta$department
  }

  muni_row <- poverty_data_muni |>
    filter(ine_code == !!ine_code) |>
    slice(1) |>
    select(-ine_code, -municipality, -department) |>
    mutate(location = muni_display_name)

  dept_row <- poverty_data_dept |>
    filter(department == dept_display_name) |>
    slice(1) |>
    select(-department) |>
    mutate(location = dept_display_name)

  bolivia_row <- poverty_data_dept |>
    filter(department == "Bolivia") |>
    slice(1) |>
    select(-department) |>
    mutate(location = "Bolivia")

  bind_rows(muni_row, dept_row, bolivia_row) |>
    select(location, everything())
}

.format_muni_context <- function(df) {
  df |>
    mutate(
      p_12 = map_chr(poverty_pct_2012, format_pct),
      p_24 = map_chr(poverty_pct_2024, format_pct),
      p_ch = map_chr(poverty_change,   format_chg),
      w_01 = map_chr(water_lack_2001,  format_pct),
      w_24 = map_chr(water_lack_2024,  format_pct),
      w_ch = map_chr(water_change,     format_chg),
      s_01 = map_chr(sanitation_lack_2001, format_pct),
      s_24 = map_chr(sanitation_lack_2024, format_pct),
      s_ch = map_chr(sanitation_change,    format_chg)
    ) |>
    select(location, p_12, p_24, p_ch, w_01, w_24, w_ch, s_01, s_24, s_ch)
}

.format_muni_wikitable <- function(df) {
  df |>
    mutate(
      p_12_wt = map_chr(poverty_pct_2012,    ~wikitext_shade(format_pct(.), "red")),
      p_24_wt = map_chr(poverty_pct_2024,    ~wikitext_shade(format_pct(.), "red")),
      p_ch_wt = map_chr(poverty_change,       format_change_wt),
      w_01_wt = map_chr(water_lack_2001,     ~wikitext_shade(format_pct(.), "blue")),
      w_24_wt = map_chr(water_lack_2024,     ~wikitext_shade(format_pct(.), "blue")),
      w_ch_wt = map_chr(water_change,         format_change_wt),
      s_01_wt = map_chr(sanitation_lack_2001, ~wikitext_shade(format_pct(.), "green")),
      s_24_wt = map_chr(sanitation_lack_2024, ~wikitext_shade(format_pct(.), "green")),
      s_ch_wt = map_chr(sanitation_change,    format_change_wt)
    ) |>
    select(location, p_12_wt, p_24_wt, p_ch_wt, w_01_wt, w_24_wt, w_ch_wt, s_01_wt, s_24_wt, s_ch_wt)
}

# ============================================================================
# Main function
# ============================================================================

#' Generate poverty and basic services tables for a municipality
#'
#' @param ine_code          6-digit INE code (e.g., "020101")
#' @param muni_display_name Display name for municipality (defaults to data value)
#' @param dept_display_name Display name for department (defaults to data value)
#'
#' @return list(kable = <kable HTML>, wikitable = <wikitext string>)
#'
#' @details Each table shows 3 rows (Municipality / Department / Bolivia) and
#'   10 columns (Poverty NBI 2012/2024/Change, Water Lack 2001/2024/Change,
#'   Sanitation Lack 2001/2024/Change).

generate_poverty_service_tables <- function(ine_code,
                                            muni_display_name = NULL,
                                            dept_display_name = NULL) {
  # Resolve display names from data if not supplied
  if (is.null(muni_display_name) || is.null(dept_display_name)) {
    muni_meta <- poverty_data_muni |>
      filter(ine_code == !!ine_code) |>
      slice(1)
    if (is.null(muni_display_name)) muni_display_name <- muni_meta$municipality
    if (is.null(dept_display_name)) dept_display_name <- muni_meta$department
  }

  # Department row label: add " Department" suffix when names collide (e.g., La Paz / La Paz)
  dept_label <- if (muni_display_name == dept_display_name) {
    paste0(dept_display_name, " Department")
  } else {
    dept_display_name
  }

  ctx <- .create_muni_context_table(ine_code, muni_display_name, dept_display_name)

  # Apply dept_label to row 2 (department row)
  ctx_labeled <- ctx |>
    mutate(location = if_else(row_number() == 2L, dept_label, location))

  # ---- HTML kable ----
  kable_html <- ctx_labeled |>
    .format_muni_context() |>
    rename(Location = location) |>
    kbl(
      caption   = paste("Poverty and Basic Services:", muni_display_name, "Municipality"),
      col.names = c("Location",
                    "2012", "2024", "Change",
                    "2001", "2024", "Change",
                    "2001", "2024", "Change"),
      align  = "lcccccccccc",
      escape = FALSE
    ) |>
    kable_classic(full_width = FALSE) |>
    add_header_above(c(" " = 1,
                       "Poverty (NBI)" = 3,
                       "Lack of Water Access" = 3,
                       "Lack of Sanitation Access" = 3)) |>
    column_spec(1, border_right = TRUE) |>
    column_spec(4, border_right = TRUE) |>
    column_spec(7, border_right = TRUE)

  # ---- Wikitable ----
  wt_rows_df <- ctx_labeled |>
    .format_muni_wikitable() |>
    # Bold the municipality (row 1)
    mutate(display = if_else(row_number() == 1L, paste0("'''", location, "'''"), location))

  wt_header <- paste0(
    "{| class=\"wikitable\"\n",
    "|+ ", muni_display_name, " Municipality: Poverty and Basic Service Access\n",
    "|-\n",
    "! align=left | Location",
    " !! colspan=3 | Poverty (NBI)",
    " !! colspan=3 | Lack of Water Access",
    " !! colspan=3 | Lack of Sanitation Access\n",
    "|-\n",
    "! align=left | !! 2012 !! 2024 !! Change !! 2001 !! 2024 !! Change !! 2001 !! 2024 !! Change\n"
  )

  wt_body <- wt_rows_df |>
    glue::glue_data(
      "|-\n| align=left | {display}",
      " || {p_12_wt} || {p_24_wt} || {p_ch_wt}",
      " || {w_01_wt} || {w_24_wt} || {w_ch_wt}",
      " || {s_01_wt} || {s_24_wt} || {s_ch_wt}"
    )

  source_text <- paste0(
    "NBI indicates a Unsatisfied Basic Needs definition for poverty. ",
    "'''Source:''' [[National Institute of Statistics of Bolivia|INE Bolivia]], 2024 Bolivian Census"
  )
  source_refs <- paste0(
    '{{Cite| last = Instituto Nacional de Estadística',
    '| title = Pobreza: Tabulados por Municipio/TIOC',
    '| access-date = 2026-07-22| date = 2025',
    '| url = https://nube.ine.gob.bo/index.php/s/KQSoTrfdRQ5jldM/download}}',
    '<br/>',
    '{{Cite| last = Instituto Nacional de Estadística',
    '| title = Servicios Básicos: Tabulados por Municipio/TIOC',
    '| access-date = 2026-07-22| date = 2025',
    '| url = https://nube.ine.gob.bo/index.php/s/dEJeTU4j0czYIdG/download}}'
  )
  source_line <- paste0('|-\n|colspan="10"|', source_text, '<ref>', source_refs, '</ref>')

  wikitable_text <- paste0(
    wt_header,
    paste(wt_body, collapse = "\n"),
    "\n", source_line, "\n|}"
  )

  list(kable = kable_html, wikitable = wikitable_text)
}
