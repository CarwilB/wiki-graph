# ── Diverging "butterfly" bar chart helpers ──
# Generalizable functions for creating two-sided diverging bar charts
# (e.g., CEL by urban/rural, identity-language alignment by mother tongue)
#
# Dependencies: tidyverse, ggplot2, ggrepel
#
# Core workflow:
# 1. prepare_butterfly_data() — aggregate, compute divergence
# 2. extract_bar_positions() — use ggplot_build to get accurate label midpoints
# 3. prepare_labels() — segment labels and totals with smart filtering
# 4. make_butterfly_plot() — construct the full ggplot

library(tidyverse)
library(ggplot2)
library(ggrepel)

# ── Utility: compact number formatting ──
#' Compact number formatting
#'
#' Formats numbers in millions, thousands, or units with abbreviated suffixes.
#'
#' @param x Numeric vector to format
#'
#' @return Character vector with formatted numbers (e.g., "1.2M", "456K", "123")
#' @examples
#' label_compact(1234567)  # "1.2M"
#' label_compact(45000)    # "45K"
#' label_compact(123)      # "123"
#' @keywords internal
label_compact <- function(x) {
  case_when(
    abs(x) >= 1e6 ~ paste0(round(abs(x) / 1e6, 1), "M"),
    abs(x) >= 1e3 ~ paste0(round(abs(x) / 1e3, 1), "K"),
    TRUE           ~ as.character(abs(x))
  )
}

# ── Step 1: Prepare diverging data structure ──
#' Prepare diverging bar data
#'
#' Aggregates counts, sets up left/right divergence, and creates y-axis labels.
#'
#' @param df Data frame with grouping, categorical, and count columns
#' @param group_var Name of grouping column (becomes y-axis)
#' @param category_var Name of categorical dimension (becomes fill)
#' @param n_var Name of count column (default: "n")
#' @param left_cats Character vector of category values for left side
#' @param right_cats Character vector of category values for right side
#' @param factor_order Explicit factor level order; if NULL, uses c(rev(right_cats), left_cats)
#'
#' @return List with components:
#'   - `data`: Prepared tibble with diverging structure
#'   - `y_labs`: Named vector of formatted y-axis labels
#'   - `left_cats`, `right_cats`, `factor_order`: Metadata
#'
#' @keywords internal
prepare_butterfly_data <- function(
    df,
    group_var,
    category_var,
    n_var = "n",
    left_cats = NULL,
    right_cats = NULL,
    factor_order = NULL
) {
  # Rename to standard names for easier processing
  df <- df |>
    rename(
      group_label = !!group_var,
      category = !!category_var,
      count = !!n_var
    )

  # Auto-compute sides if not specified
  if (is.null(left_cats) || is.null(right_cats)) {
    all_cats <- unique(df$category) |> sort()
    if (is.null(left_cats) && is.null(right_cats)) {
      # Default: split alphabetically (first half left, second half right)
      n_cats <- length(all_cats)
      left_cats <- all_cats[1:floor(n_cats / 2)]
      right_cats <- all_cats[(floor(n_cats / 2) + 1):n_cats]
    }
  }

  # Factor order
  if (is.null(factor_order)) {
    factor_order <- c(rev(right_cats), left_cats)
  }

  # Add side and diverge
  df <- df |>
    mutate(
      side = if_else(category %in% left_cats, "left", "right"),
      count_plot = if_else(side == "left", -count, count),
      category = factor(category, levels = factor_order)
    ) |>
    group_by(group_label) |>
    mutate(total = sum(count)) |>
    ungroup()

  # Add y-axis labels with totals
  y_labs <- df |>
    group_by(group_label) |>
    summarise(total = first(total), .groups = "drop") |>
    mutate(y_lab = paste0(group_label, "\nn = ", scales::comma(total))) |>
    pull(y_lab, name = group_label)

  df <- df |>
    mutate(group_label = factor(y_labs[as.character(group_label)], levels = y_labs))

  list(
    data = df,
    y_labs = y_labs,
    left_cats = left_cats,
    right_cats = right_cats,
    factor_order = factor_order
  )
}

# ── Step 2: Extract actual bar positions from ggplot ──
#' Extract bar positions from rendered plot
#'
#' Uses ggplot_build() to get accurate midpoints and widths for label placement,
#' avoiding fragile cumsum() logic that depends on ggplot stacking order.
#'
#' @param df Data frame with diverging bar structure
#' @param group_var_col Name of grouping column (default: "group_label")
#' @param category_var_col Name of category column (default: "category")
#' @param x_var_col Name of x-axis column with diverging values (default: "count_plot")
#' @param colors_map Named vector mapping hex colors to categories
#' @param y_labs Named vector of formatted y-axis labels
#'
#' @return Tibble with columns: mid, width, category, group_label, count, side, fill, xmin, xmax, y
#'
#' @keywords internal
extract_bar_positions <- function(
    df,
    group_var_col = "group_label",
    category_var_col = "category",
    x_var_col = "count_plot",
    colors_map = NULL,  # named vector: hex -> category
    y_labs = NULL       # named vector: original -> formatted labels (for axis mapping)
) {
  # Build bare plot
  p_bare <- ggplot(df, aes(x = .data[[x_var_col]], y = .data[[group_var_col]],
                           fill = .data[[category_var_col]])) +
    geom_col(width = 0.65) +
    {if (!is.null(colors_map)) scale_fill_manual(values = colors_map)}

  bd <- ggplot_build(p_bare)

  # Extract positions
  bar_pos <- bd$data[[1]] |>
    as_tibble() |>
    select(fill, xmin, xmax, y) |>
    mutate(
      mid = (xmin + xmax) / 2,
      width = abs(xmax - xmin),
      side = if_else(xmax <= 0, "left", "right")
    )

  # Map back to data columns
  if (!is.null(colors_map)) {
    color_to_cat <- setNames(names(colors_map), colors_map)
    bar_pos <- bar_pos |>
      mutate(category = color_to_cat[fill])
  }

  # Map y position back to group labels (if y_labs provided)
  if (!is.null(y_labs)) {
    y_levels <- levels(df[[group_var_col]])
    bar_pos <- bar_pos |>
      mutate(group_label = factor(y_levels[as.integer(y)], levels = y_levels))
  } else {
    bar_pos <- bar_pos |>
      mutate(group_label = df[[group_var_col]][as.integer(y)])
  }

  bar_pos |>
    mutate(count = as.integer(width)) |>
    select(-fill, -y)
}

# ── Step 3: Prepare labels (segment counts and totals) ──
#' Prepare smart-filtered labels for butterfly chart
#'
#' Separates segment labels into "inside" (wide bars, direct text) and "above"
#' (small bars, repelled) based on width thresholds. Computes left/right totals.
#'
#' @param bar_pos Tibble of bar positions (output from extract_bar_positions)
#' @param label_format_func Function to format count values (default: label_compact)
#' @param category_col Name of category column (default: "category")
#' @param group_col Name of group column (default: "group_label")
#' @param count_col Name of count column (default: "count")
#' @param side_col Name of side column (default: "side")
#' @param width_col Name of width column (default: "width")
#' @param mid_col Name of midpoint column (default: "mid")
#' @param inside_threshold Width threshold for inside labels (default: 0.06, as % of x_range)
#' @param above_threshold Minimum width to label at all (default: 0.005, as % of x_range)
#' @param text_colors Named vector mapping categories to text colors (white/grey20)
#'
#' @return List with components:
#'   - `inside`: Tibble of labels for direct placement
#'   - `above`: Tibble of labels needing repulsion
#'   - `left_totals`: Tibble of left-side totals per group
#'   - `right_totals`: Tibble of right-side totals per group
#'   - `x_range`: Maximum x-value (for threshold calculations)
#'
#' @keywords internal
prepare_butterfly_labels <- function(
    bar_pos,
    label_format_func = label_compact,
    category_col = "category",
    group_col = "group_label",
    count_col = "count",
    side_col = "side",
    width_col = "width",
    mid_col = "mid",
    inside_threshold = 0.06,   # % of x_range to be "wide enough"
    above_threshold = 0.005,   # minimum size to label at all
    text_colors = NULL         # named vector: category -> color (white/grey20)
) {
  x_range <- max(abs(bar_pos[[mid_col]]))

  bar_pos <- bar_pos |>
    mutate(
      label = label_format_func(.data[[count_col]]),
      text_col = if (!is.null(text_colors)) {
        text_colors[as.character(.data[[category_col]])]
      } else {
        "grey20"
      }
    )

  seg_inside <- bar_pos |>
    filter(.data[[width_col]] > x_range * inside_threshold)

  seg_above <- bar_pos |>
    filter(.data[[width_col]] <= x_range * inside_threshold,
           .data[[width_col]] > x_range * above_threshold)

  # Left and right totals
  left_totals <- bar_pos |>
    filter(.data[[side_col]] == "left") |>
    group_by(.data[[group_col]]) |>
    summarise(left_total = sum(.data[[count_col]]), .groups = "drop")

  right_totals <- bar_pos |>
    filter(.data[[side_col]] == "right") |>
    group_by(.data[[group_col]]) |>
    summarise(right_total = sum(.data[[count_col]]), .groups = "drop")

  list(
    inside = seg_inside,
    above = seg_above,
    left_totals = left_totals,
    right_totals = right_totals,
    x_range = x_range
  )
}

# ── Step 4: Make the complete butterfly plot ──
#' Construct butterfly chart ggplot object
#'
#' Creates a complete, fully-themed diverging bar chart with proper positioning
#' of segment labels, totals, legends, and annotations.
#'
#' @param df Diverging data (output from prepare_butterfly_data)
#' @param labels Label list (output from prepare_butterfly_labels)
#' @param colors_map Named vector of colors (category -> hex)
#' @param category_labels Named vector of category descriptions for legend (optional)
#' @param x_var_col Name of x-axis column (default: "count_plot")
#' @param group_var_col Name of grouping column (default: "group_label")
#' @param category_var_col Name of category column (default: "category")
#' @param mid_col Name of midpoint column for labels (default: "mid")
#' @param title Plot title
#' @param subtitle Plot subtitle
#' @param arrow_left Left-side annotation text
#' @param arrow_right Right-side annotation text
#' @param left_arrow_color Hex color for left annotation
#' @param right_arrow_color Hex color for right annotation
#' @param base_size Base font size (all text scales from this)
#' @param seed Random seed for label repulsion
#'
#' @return ggplot object
#'
#' @keywords internal
make_butterfly_plot <- function(
    df,                 # the diverging data (output from prepare_butterfly_data()$data)
    labels,             # output from prepare_butterfly_labels()
    colors_map,         # named vector of colors (category -> hex)
    category_labels = NULL,  # named vector of category -> description (for legend)
    x_var_col = "count_plot",
    group_var_col = "group_label",
    category_var_col = "category",
    mid_col = "mid",
    title = "Diverging bar chart",
    subtitle = "",
    arrow_left = "← Left side",
    arrow_right = "Right side →",
    left_arrow_color = "#4a5568",
    right_arrow_color = "#2166ac",
    base_size = 14,
    fig_width = 14,
    fig_height = 5,
    seed = 7841
) {
  seg_inside <- labels$inside
  seg_above <- labels$above
  left_totals <- labels$left_totals
  right_totals <- labels$right_totals
  x_range <- labels$x_range

  # Calculate dimensions
  seg_label_size <- base_size * 0.22
  total_label_size <- base_size * 0.24
  arrow_text_size <- base_size * 0.22

  p <- ggplot(df, aes(x = .data[[x_var_col]], y = .data[[group_var_col]],
                      fill = .data[[category_var_col]])) +
    geom_col(width = 0.65, show.legend = TRUE) +
    geom_text(
      data = seg_inside,
      aes(x = .data[[mid_col]], y = .data[[group_var_col]], label = label, color = text_col),
      inherit.aes = FALSE, size = seg_label_size, fontface = "bold"
    ) +
    scale_color_identity() +
    geom_text_repel(
      data = seg_above,
      aes(x = .data[[mid_col]], y = .data[[group_var_col]], label = label),
      inherit.aes = FALSE, size = seg_label_size * 0.75,
      color = "grey30",
      direction = "x", nudge_y = 0.42,
      segment.size = 0.2, segment.color = "grey60",
      min.segment.length = 0,
      box.padding = 0.08, force = 6, max.overlaps = 30,
      seed = seed
    ) +
    geom_text(
      data = right_totals,
      aes(x = right_total * 1.02, y = .data[[group_var_col]],
          label = scales::comma(right_total)),
      inherit.aes = FALSE, hjust = 0, size = total_label_size, fontface = "bold",
      color = "grey30"
    ) +
    geom_text(
      data = left_totals,
      aes(x = -left_total * 1.02, y = .data[[group_var_col]],
          label = scales::comma(left_total)),
      inherit.aes = FALSE, hjust = 1, size = total_label_size, fontface = "bold",
      color = "grey30"
    ) +
    geom_vline(xintercept = 0, linewidth = 1.2, color = "grey20") +
    annotate("text", x = -x_range * 0.5, y = Inf, vjust = 1.1,
             label = arrow_left,
             size = arrow_text_size, fontface = "bold", color = left_arrow_color, hjust = 0.5) +
    annotate("text", x = x_range * 0.35, y = Inf, vjust = 1.1,
             label = arrow_right,
             size = arrow_text_size, fontface = "bold", color = right_arrow_color, hjust = 0.5) +
    scale_x_continuous(
      labels = function(x) scales::comma(abs(x)),
      expand = expansion(mult = c(0.14, 0.14))
    ) +
    scale_fill_manual(
      values = colors_map,
      labels = if (!is.null(category_labels)) category_labels else NULL,
      name = NULL,
      guide = guide_legend(nrow = 2, override.aes = list(size = 4))
    ) +
    coord_cartesian(clip = "off") +
    labs(
      title = title,
      subtitle = subtitle,
      x = NULL, y = NULL
    ) +
    theme_void(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = rel(1.35), margin = margin(b = 3)),
      plot.subtitle = element_text(color = "grey40", size = rel(0.8), margin = margin(b = 16)),
      plot.margin = margin(20, 30, 10, 10),
      axis.text.y = element_text(hjust = 1, color = "grey20",
                                 size = rel(0.85), margin = margin(r = 8)),
      axis.text.x = element_text(color = "grey50", size = rel(0.6), margin = margin(t = 5)),
      legend.position = "bottom",
      legend.text = element_text(size = rel(0.55)),
      legend.key.size = unit(0.4, "cm"),
      legend.spacing.x = unit(0.15, "cm"),
      legend.margin = margin(t = 10)
    )

  p
}

# ── Convenience wrapper: one-call butterfly chart ──
#' Create a complete butterfly (diverging) bar chart
#'
#' One-function interface for creating two-sided diverging bar charts.
#' Handles all steps: data preparation, bar position extraction, label placement, plotting.
#'
#' @param df Data frame with group, category, and count columns
#' @param group_var Name of grouping column (y-axis)
#' @param category_var Name of categorical column (fill color)
#' @param n_var Name of count column (default: "n")
#' @param left_cats Character vector of categories for left side
#' @param right_cats Character vector of categories for right side
#' @param factor_order Explicit factor level order (if NULL, uses c(rev(right_cats), left_cats))
#' @param colors_map Named vector of colors (category -> hex)
#' @param category_labels Named vector of descriptions for legend (optional)
#' @param text_colors Named vector of text colors for labels (white/grey20)
#' @param title Plot title
#' @param subtitle Plot subtitle
#' @param arrow_left Left-side annotation
#' @param arrow_right Right-side annotation
#' @param left_arrow_color Hex color for left annotation
#' @param right_arrow_color Hex color for right annotation
#' @param base_size Base font size
#' @param seed Random seed for label repulsion
#'
#' @return ggplot object
#'
#' @details
#' This function combines the full butterfly chart pipeline:
#' 1. Prepare diverging data structure
#' 2. Extract accurate bar positions via ggplot_build()
#' 3. Filter labels (inside bars vs. above bars)
#' 4. Construct complete ggplot with theming
#'
#' @examples
#' \dontrun{
#' make_butterfly(
#'   cel_urbrur,
#'   group_var = "urbrur_label",
#'   category_var = "cel_chr",
#'   left_cats = c("0", "1", "1.5", "2", "3"),
#'   right_cats = c("4", "4.5", "5", "6", "7"),
#'   colors_map = cel_colors,
#'   category_labels = cel_labels_int,
#'   title = "CEL distribution by urban/rural"
#' )
#' }
#'
#' @export
make_butterfly <- function(
    df,
    group_var,
    category_var,
    n_var = "n",
    left_cats = NULL,
    right_cats = NULL,
    factor_order = NULL,
    colors_map = NULL,
    category_labels = NULL,
    text_colors = NULL,
    title = "Diverging bar chart",
    subtitle = "",
    arrow_left = "← Left side",
    arrow_right = "Right side →",
    left_arrow_color = "#4a5568",
    right_arrow_color = "#2166ac",
    base_size = 14,
    seed = 7841
) {
  # Step 1: prepare data
  prep <- prepare_butterfly_data(
    df,
    group_var = group_var,
    category_var = category_var,
    n_var = n_var,
    left_cats = left_cats,
    right_cats = right_cats,
    factor_order = factor_order
  )
  div_df <- prep$data
  y_labs <- prep$y_labs

  # Step 2: extract bar positions
  bar_pos <- extract_bar_positions(
    div_df,
    group_var_col = "group_label",
    category_var_col = "category",
    x_var_col = "count_plot",
    colors_map = colors_map,
    y_labs = y_labs
  )

  # Step 3: prepare labels
  labels <- prepare_butterfly_labels(
    bar_pos,
    category_col = "category",
    group_col = "group_label",
    count_col = "count",
    side_col = "side",
    width_col = "width",
    mid_col = "mid",
    text_colors = text_colors
  )

  # Step 4: make plot
  p <- make_butterfly_plot(
    div_df,
    labels = labels,
    colors_map = colors_map,
    category_labels = category_labels,
    x_var_col = "count_plot",
    group_var_col = "group_label",
    category_var_col = "category",
    mid_col = "mid",
    title = title,
    subtitle = subtitle,
    arrow_left = arrow_left,
    arrow_right = arrow_right,
    left_arrow_color = left_arrow_color,
    right_arrow_color = right_arrow_color,
    base_size = base_size,
    seed = seed
  )

  p
}

# ── Municipality-level case studies: 3 butterfly charts ──
#' Create three butterfly charts for a municipality
#'
#' Generates a set of three diverging bar charts showing indigenous language
#' distribution for a specified municipality by:
#' 1. Age group (0-14, 15-29, 30-44, 45-59, 60+)
#' 2. Urban/rural residence
#' 3. Current speaker status vs. heritage-only
#'
#' All three charts use dual-scale design (large languages vs. small) when applicable.
#'
#' @param geo_code Geographic code (2/4/6 digits: department, province, municipality)
#' @param persona_path Path to Persona CSV file
#' @param vivienda_path Path to Vivienda CSV file
#' @param idioma_cats Lookup table for language labels (default: from session)
#' @param min_speakers Minimum speaker count to include a language (default: 100)
#'
#' @return List with three components:
#'   - `$age_groups`: Butterfly chart by age
#'   - `$urban_rural`: Butterfly chart by urban/rural
#'   - `$speaker_status`: Butterfly chart by current speaker vs. heritage-only
#'
#' @keywords internal
make_municipality_butterflies <- function(
    geo_code,
    persona_path = "../bolivia-data/Censo 2024/base_datos_csv_2024/Persona_CPV-2024.csv",
    vivienda_path = "../bolivia-data/Censo 2024/base_datos_csv_2024/Vivienda_CPV-2024.csv",
    idioma_cats = NULL,
    min_speakers = 100
) {
  library(arrow)
  library(tidyverse)

  # Get geo label using read_census_geo logic
  geo_codes_chr <- as.character(geo_code)
  geo_codes_chr <- ifelse(nchar(geo_codes_chr) == 1, paste0("0", geo_codes_chr), geo_codes_chr)
  code_len <- nchar(geo_codes_chr)
  stopifnot("geo_code must be 2, 4, or 6 digits" = code_len %in% c(2, 4, 6))

  # Extract dept, prov, mun codes
  if (code_len == 2) {
    idep <- as.integer(geo_codes_chr)
    iprov <- NA_integer_
    imun <- NA_integer_
  } else if (code_len == 4) {
    idep <- as.integer(substr(geo_codes_chr, 1, 2))
    iprov <- as.integer(substr(geo_codes_chr, 3, 4))
    imun <- NA_integer_
  } else {
    idep <- as.integer(substr(geo_codes_chr, 1, 2))
    iprov <- as.integer(substr(geo_codes_chr, 3, 4))
    imun <- as.integer(substr(geo_codes_chr, 5, 6))
  }

  # Use default idioma_cats if not provided
  if (is.null(idioma_cats)) {
    if (!exists("idioma_cats", where = parent.frame())) {
      stop("idioma_cats not found in environment; please provide as argument")
    }
    idioma_cats <- get("idioma_cats", envir = parent.frame())
  }

  # Load persona data for this geography
  ds <- open_dataset(persona_path, format = "csv", delimiter = ";")
  df <- ds |>
    filter(idep == !!idep) |>
    select(idep, iprov, imun, i00, p26_edad, p25_sexo,
           idioma_mat, p331_idiohab1_cod, p332_idiohab2_cod, p333_idiohab3_cod) |>
    collect()

  # Precise filter by province and/or municipality
  if (!is.na(iprov)) {
    df <- df |> filter(iprov == !!iprov)
  }
  if (!is.na(imun)) {
    df <- df |> filter(imun == !!imun)
  }

  # Load vivienda for urban/rural
  ds_viv <- open_dataset(vivienda_path, format = "csv", delimiter = ";")
  urbrur_data <- ds_viv |>
    filter(idep == !!idep) |>
    select(idep, iprov, imun, i00, urbrur) |>
    collect()

  if (!is.na(iprov)) {
    urbrur_data <- urbrur_data |> filter(iprov == !!iprov)
  }
  if (!is.na(imun)) {
    urbrur_data <- urbrur_data |> filter(imun == !!imun)
  }

  df <- df |>
    left_join(urbrur_data, by = c("idep", "iprov", "imun", "i00"))

  # Filter to indigenous languages (codes 1-5, 7-37)
  indigenous_codes <- c(1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37)

  df <- df |>
    filter(idioma_mat %in% indigenous_codes) |>
    mutate(
      age_group = case_when(
        p26_edad < 15 ~ "0-14",
        p26_edad < 30 ~ "15-29",
        p26_edad < 45 ~ "30-44",
        p26_edad < 60 ~ "45-59",
        TRUE ~ "60+"
      ),
      urbrur_label = if_else(urbrur == 1, "Urban", "Rural"),
      # Current speaker: any of p331/p332/p333 matches idioma_mat
      # Only classify if at least one language column is non-NA
      is_current_speaker = case_when(
        is.na(p331_idiohab1_cod) & is.na(p332_idiohab2_cod) & is.na(p333_idiohab3_cod) ~ NA,
        (p331_idiohab1_cod == idioma_mat | p332_idiohab2_cod == idioma_mat | p333_idiohab3_cod == idioma_mat) ~ TRUE,
        TRUE ~ FALSE
      ),
      speaker_status = if_else(is_current_speaker, "Current speaker",
                               if_else(!is.na(is_current_speaker), "Heritage only", NA_character_))
    )

  # Get language names and filter to >min_speakers
  lang_summary <- df |>
    group_by(idioma_mat) |>
    count() |>
    filter(n > min_speakers) |>
    pull(idioma_mat)

  df_filtered <- df |> filter(idioma_mat %in% lang_summary)

  # Add language labels
  df_filtered <- df_filtered |>
    left_join(idioma_cats |> rename(idioma_mat = code), by = "idioma_mat") |>
    filter(!is.na(label)) |>
    rename(language = label)

  # Get geo label
  geo_label <- if (!is.na(imun)) {
    muni_lookup |> filter(id_muni == sprintf("%02d%02d%02d", idep, iprov, imun)) |> pull(muni_gb2014) |> first()
  } else if (!is.na(iprov)) {
    prov_id_lookup_table |> filter(id_prov == sprintf("%02d%02d", idep, iprov)) |> pull(province_gb2014) |> first()
  } else {
    paste0("Department ", idep)
  }

  # Color scheme for languages
  lang_colors <- c(
    "Aymara" = "#d62728", "Quechua" = "#ff7f0e",
    "Guaraní" = "#1f77b4", "Tsimane´" = "#2ca02c",
    "Gwarayu" = "#9467bd", "Weenhayek" = "#8c564b",
    "Araona" = "#e377c2", "Baure" = "#7f7f7f",
    "Canichana" = "#bcbd22", "Kabineña" = "#17becf"
  )

  age_order <- c("0-14", "15-29", "30-44", "45-59", "60+")

  # ── Chart 1: By age group ──
  age_data <- df_filtered |>
    group_by(age_group, language) |>
    count() |>
    mutate(age_group = factor(age_group, levels = age_order)) |>
    rename(n_speakers = n)

  # Separate large (Aymara/Quechua) from small
  large_langs <- c("Aymara", "Quechua")
  has_large <- any(unique(age_data$language) %in% large_langs)

  if (has_large) {
    age_large <- age_data |> filter(language %in% large_langs)
    age_small <- age_data |> filter(!language %in% large_langs)

    if (nrow(age_large) > 0) {
      p_age_large <- make_butterfly(
        age_large,
        group_var = "age_group",
        category_var = "language",
        n_var = "n_speakers",
        left_cats = "Aymara",
        right_cats = "Quechua",
        colors_map = lang_colors[c("Aymara", "Quechua")],
        title = paste0(geo_label, ": Aymara & Quechua by age"),
        subtitle = paste0("n = ", format(sum(age_large$n_speakers), big.mark = ",")),
        arrow_left = "← Aymara",
        arrow_right = "Quechua →",
        base_size = 11
      )
    } else {
      p_age_large <- NULL
    }

    if (nrow(age_small) > 0) {
      n_small_langs <- length(unique(age_small$language))
      p_age_small <- make_butterfly(
        age_small,
        group_var = "age_group",
        category_var = "language",
        n_var = "n_speakers",
        left_cats = unique(age_small$language)[1:(n_small_langs %/% 2)],
        right_cats = unique(age_small$language)[(n_small_langs %/% 2 + 1):n_small_langs],
        colors_map = lang_colors[unique(age_small$language)],
        title = paste0(geo_label, ": Other indigenous languages by age"),
        subtitle = paste0("n = ", format(sum(age_small$n_speakers), big.mark = ",")),
        base_size = 11
      )
    } else {
      p_age_small <- NULL
    }

    if (!is.null(p_age_large) && !is.null(p_age_small)) {
      p_age <- p_age_large / p_age_small
    } else if (!is.null(p_age_large)) {
      p_age <- p_age_large
    } else {
      p_age <- p_age_small
    }
  } else {
    # No Aymara/Quechua, just single plot
    n_langs <- length(unique(age_data$language))
    p_age <- make_butterfly(
      age_data,
      group_var = "age_group",
      category_var = "language",
      n_var = "n_speakers",
      left_cats = unique(age_data$language)[1:(n_langs %/% 2)],
      right_cats = unique(age_data$language)[(n_langs %/% 2 + 1):n_langs],
      colors_map = lang_colors[unique(age_data$language)],
      title = paste0(geo_label, ": Indigenous languages by age"),
      subtitle = paste0("n = ", format(sum(age_data$n_speakers), big.mark = ",")),
      base_size = 11
    )
  }

  # ── Chart 2: By urban/rural ──
  ur_data <- df_filtered |>
    filter(!is.na(urbrur_label)) |>
    group_by(urbrur_label, language) |>
    count() |>
    rename(n_speakers = n)

  if (nrow(ur_data) > 0) {
    # Check if we have both urban/rural
    if (length(unique(ur_data$urbrur_label)) > 1) {
      ur_order <- c("Urban", "Rural")
      has_large_ur <- any(unique(ur_data$language) %in% large_langs)

      if (has_large_ur) {
        ur_large <- ur_data |> filter(language %in% large_langs) |>
          mutate(urbrur_label = factor(urbrur_label, levels = ur_order))
        ur_small <- ur_data |> filter(!language %in% large_langs) |>
          mutate(urbrur_label = factor(urbrur_label, levels = ur_order))

        if (nrow(ur_large) > 0) {
          p_ur_large <- make_butterfly(
            ur_large,
            group_var = "urbrur_label",
            category_var = "language",
            n_var = "n_speakers",
            left_cats = "Aymara",
            right_cats = "Quechua",
            colors_map = lang_colors[c("Aymara", "Quechua")],
            title = paste0(geo_label, ": Aymara & Quechua by residence"),
            subtitle = paste0("n = ", format(sum(ur_large$n_speakers), big.mark = ",")),
            arrow_left = "← Aymara",
            arrow_right = "Quechua →",
            base_size = 11
          )
        } else {
          p_ur_large <- NULL
        }

        if (nrow(ur_small) > 0) {
          n_small_langs <- length(unique(ur_small$language))
          p_ur_small <- make_butterfly(
            ur_small,
            group_var = "urbrur_label",
            category_var = "language",
            n_var = "n_speakers",
            left_cats = unique(ur_small$language)[1:(n_small_langs %/% 2)],
            right_cats = unique(ur_small$language)[(n_small_langs %/% 2 + 1):n_small_langs],
            colors_map = lang_colors[unique(ur_small$language)],
            title = paste0(geo_label, ": Other indigenous languages by residence"),
            subtitle = paste0("n = ", format(sum(ur_small$n_speakers), big.mark = ",")),
            base_size = 11
          )
        } else {
          p_ur_small <- NULL
        }

        if (!is.null(p_ur_large) && !is.null(p_ur_small)) {
          p_ur <- p_ur_large / p_ur_small
        } else if (!is.null(p_ur_large)) {
          p_ur <- p_ur_large
        } else {
          p_ur <- p_ur_small
        }
      } else {
        n_langs <- length(unique(ur_data$language))
        p_ur <- make_butterfly(
          ur_data |> mutate(urbrur_label = factor(urbrur_label, levels = ur_order)),
          group_var = "urbrur_label",
          category_var = "language",
          n_var = "n_speakers",
          left_cats = unique(ur_data$language)[1:(n_langs %/% 2)],
          right_cats = unique(ur_data$language)[(n_langs %/% 2 + 1):n_langs],
          colors_map = lang_colors[unique(ur_data$language)],
          title = paste0(geo_label, ": Indigenous languages by residence"),
          subtitle = paste0("n = ", format(sum(ur_data$n_speakers), big.mark = ",")),
          base_size = 11
        )
      }
    } else {
      p_ur <- NULL  # Only one urban/rural category
    }
  } else {
    p_ur <- NULL
  }

  # ── Chart 3: By speaker status (current vs. heritage) ──
  status_data <- df_filtered |>
    filter(!is.na(speaker_status)) |>
    group_by(speaker_status, language) |>
    count() |>
    rename(n_speakers = n)

  if (nrow(status_data) > 0 && length(unique(status_data$speaker_status)) > 1) {
    status_order <- c("Heritage only", "Current speaker")
    has_large_status <- any(unique(status_data$language) %in% large_langs)

    if (has_large_status) {
      status_large <- status_data |> filter(language %in% large_langs) |>
        mutate(speaker_status = factor(speaker_status, levels = status_order))
      status_small <- status_data |> filter(!language %in% large_langs) |>
        mutate(speaker_status = factor(speaker_status, levels = status_order))

      if (nrow(status_large) > 0) {
        p_status_large <- make_butterfly(
          status_large,
          group_var = "speaker_status",
          category_var = "language",
          n_var = "n_speakers",
          left_cats = "Aymara",
          right_cats = "Quechua",
          colors_map = lang_colors[c("Aymara", "Quechua")],
          title = paste0(geo_label, ": Aymara & Quechua by speaker status"),
          subtitle = paste0("n = ", format(sum(status_large$n_speakers), big.mark = ",")),
          arrow_left = "← Aymara",
          arrow_right = "Quechua →",
          base_size = 11
        )
      } else {
        p_status_large <- NULL
      }

      if (nrow(status_small) > 0) {
        n_small_langs <- length(unique(status_small$language))
        p_status_small <- make_butterfly(
          status_small,
          group_var = "speaker_status",
          category_var = "language",
          n_var = "n_speakers",
          left_cats = unique(status_small$language)[1:(n_small_langs %/% 2)],
          right_cats = unique(status_small$language)[(n_small_langs %/% 2 + 1):n_small_langs],
          colors_map = lang_colors[unique(status_small$language)],
          title = paste0(geo_label, ": Other indigenous languages by speaker status"),
          subtitle = paste0("n = ", format(sum(status_small$n_speakers), big.mark = ",")),
          base_size = 11
        )
      } else {
        p_status_small <- NULL
      }

      if (!is.null(p_status_large) && !is.null(p_status_small)) {
        p_status <- p_status_large / p_status_small
      } else if (!is.null(p_status_large)) {
        p_status <- p_status_large
      } else {
        p_status <- p_status_small
      }
    } else {
      n_langs <- length(unique(status_data$language))
      p_status <- make_butterfly(
        status_data |> mutate(speaker_status = factor(speaker_status, levels = status_order)),
        group_var = "speaker_status",
        category_var = "language",
        n_var = "n_speakers",
        left_cats = unique(status_data$language)[1:(n_langs %/% 2)],
        right_cats = unique(status_data$language)[(n_langs %/% 2 + 1):n_langs],
        colors_map = lang_colors[unique(status_data$language)],
        title = paste0(geo_label, ": Indigenous languages by speaker status"),
        subtitle = paste0("n = ", format(sum(status_data$n_speakers), big.mark = ",")),
        base_size = 11
      )
    }
  } else {
    p_status <- NULL  # No variation in speaker status
  }

  list(
    age_groups = p_age,
    urban_rural = p_ur,
    speaker_status = p_status,
    geo_label = geo_label,
    n_total = nrow(df_filtered)
  )
}

cat("butterfly_helpers.R loaded: prepare_butterfly_data(), extract_bar_positions(),",
    "prepare_butterfly_labels(), make_butterfly_plot(), make_butterfly(),",
    "and make_municipality_butterflies().\n")
