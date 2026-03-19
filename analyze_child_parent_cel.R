# ── Parent-child CEL analysis function ──
source("cel_helpers.R")

analyze_child_parent_cel <- function(
    geo_codes,
    urban_rural = NULL,
    child_filter = "age_0_14",
    age_max = 14,
    age_min = 0,
    idioma_filter = NULL,
    persona_path = "../bolivia-data/Censo 2024/base_datos_csv_2024/Persona_CPV-2024.csv",
    vivienda_path = "../bolivia-data/Censo 2024/base_datos_csv_2024/Vivienda_CPV-2024.csv"
) {
  # child_filter: "age_0_14" (default) or "idioma" (use idioma_filter)
  # idioma_filter: character label to filter idioma_label (e.g., "No habla")

  result <- read_census_geo(geo_codes, urban_rural, persona_path = persona_path,
                             vivienda_path = vivienda_path)
  df <- result$data
  geo_label <- result$geo_label
  ur_label <- result$ur_label

  # ── Identify target children ──
  if (!is.null(idioma_filter)) {
    children <- df |> filter(idioma_label == idioma_filter)
    filter_desc <- paste0("idioma_mat = \"", idioma_filter, "\"")
  } else {
    children <- df |> filter(p26_edad >= age_min, p26_edad <= age_max)
    filter_desc <- paste0("age ", age_min, "-", age_max)
  }
  cat(sprintf("Target group (%s): %s persons.\n", filter_desc, format(nrow(children), big.mark = ",")))

  # ── Identify potential parents in the same dwelling ──
  # Parentesco codes: 1 = Head, 2 = Spouse, 3 = Child, 4 = Stepchild,
  #   6 = Grandchild, 9 = Parent (of head), 11 = Grandparent

  # Strategy: for each child (target person), find adults in same dwelling who
  # are plausible parents based on relationship to head:
  #
  # If child is p24=3 or 4 (child/stepchild of head): parents = p24 in {1, 2}
  # If child is p24=6 (grandchild of head): parents = p24 in {3, 4, 5} (children/in-laws of head)
  # If child is p24=1 (head, rare for 0-14): parents = p24 in {9} (parent of head)
  # Otherwise: no clear parent linkage

  target_dwellings <- unique(children$dwelling_key)

  adults_in_dwellings <- df |>
    filter(dwelling_key %in% target_dwellings, p26_edad >= 18)

  cat(sprintf("Adults (18+) in same dwellings: %s.\n", format(nrow(adults_in_dwellings), big.mark = ",")))

  # Build parent linkage
  children_slim <- children |>
    select(dwelling_key, p24_child = p24_parentes, cel_child = cel,
           cel_chr_child = cel_chr, idioma_child = idioma_label,
           age_child = p26_edad) |>
    mutate(
      parent_codes = case_when(
        p24_child %in% c(3L, 4L) ~ "head_spouse",   # child of head -> parents are head/spouse
        p24_child == 6L           ~ "gen2",           # grandchild -> parents are gen-2 (codes 3-5)
        p24_child == 1L           ~ "own_parent",     # child IS head -> look for code 9
        TRUE                      ~ "other"
      )
    )

  adults_slim <- adults_in_dwellings |>
    select(dwelling_key, p24_adult = p24_parentes, cel_adult = cel,
           cel_chr_adult = cel_chr, idioma_adult = idioma_label,
           age_adult = p26_edad, sex_adult = p25_sexo)

  # Join children to their plausible parents
  linked <- children_slim |>
    inner_join(adults_slim, by = "dwelling_key", relationship = "many-to-many") |>
    filter(
      (parent_codes == "head_spouse" & p24_adult %in% c(1L, 2L)) |
      (parent_codes == "gen2"        & p24_adult %in% c(3L, 4L, 5L)) |
      (parent_codes == "own_parent"  & p24_adult == 9L)
    )

  cat(sprintf("Child-parent links established: %s.\n", format(nrow(linked), big.mark = ",")))

  # ── Summary: linkage rates by child relationship type ──
  linkage_summary <- children_slim |>
    count(parent_codes, name = "n_children") |>
    left_join(
      linked |> distinct(dwelling_key, p24_child, age_child, parent_codes) |>
        count(parent_codes, name = "n_linked"),
      by = "parent_codes"
    ) |>
    mutate(n_linked = replace_na(n_linked, 0L),
           pct_linked = round(100 * n_linked / n_children, 1))

  cat("\n\u2500\u2500 Linkage summary \u2500\u2500\n")
  print(linkage_summary)

  # ── Aggregate: max parent CEL per child ──
  child_max_parent <- linked |>
    group_by(dwelling_key, p24_child, age_child, cel_child, cel_chr_child,
             idioma_child, parent_codes) |>
    summarise(
      max_parent_cel = max(cel_adult),
      min_parent_cel = min(cel_adult),
      n_parents = n(),
      .groups = "drop"
    ) |>
    mutate(
      max_parent_cel_chr = factor(as.character(max_parent_cel),
        levels = c("0", "1", "1.5", "2", "3", "4", "4.5", "5", "6", "7")),
      min_parent_cel_chr = factor(as.character(min_parent_cel),
        levels = c("0", "1", "1.5", "2", "3", "4", "4.5", "5", "6", "7"))
    )

  # ── Cross-tab: child CEL x max parent CEL ──
  cross <- child_max_parent |>
    count(cel_chr_child, max_parent_cel_chr) |>
    mutate(pct = round(100 * n / sum(n), 2))

  cat(sprintf("\n\u2500\u2500 Child CEL \u00d7 Max parent CEL (%s children with parents) \u2500\u2500\n",
              format(nrow(child_max_parent), big.mark = ",")))

  cross_wide <- cross |>
    select(-pct) |>
    pivot_wider(names_from = max_parent_cel_chr, values_from = n, values_fill = 0) |>
    arrange(cel_chr_child)

  print(cross_wide)

  # ── Heatmap with totals ──
  cel_levels <- c("0", "1", "1.5", "2", "3", "4", "4.5", "5", "6", "7")
  cel_colors <- c("0" = "#d9d9d9", "1" = "#fee0b6", "1.5" = "#fdb863",
                   "2" = "#e08214", "3" = "#b35806", "4" = "#cce5ff",
                   "4.5" = "#74add1", "5" = "#4393c3", "6" = "#2166ac",
                   "7" = "#053061")

  # Row totals (one per child CEL level, placed in "Total" column)
  row_totals <- cross |>
    group_by(cel_chr_child) |>
    summarise(n = sum(n), .groups = "drop") |>
    mutate(max_parent_cel_chr = "Total")

  # Column totals (one per parent CEL level, placed in "Total" row)
  col_totals <- cross |>
    group_by(max_parent_cel_chr) |>
    summarise(n = sum(n), .groups = "drop") |>
    mutate(cel_chr_child = "Total")

  # Grand total
  grand_total <- tibble(
    cel_chr_child = "Total",
    max_parent_cel_chr = "Total",
    n = sum(cross$n)
  )

  # Combine: main data + margins
  plot_main <- cross |> select(cel_chr_child, max_parent_cel_chr, n) |>
    mutate(is_margin = FALSE)
  plot_margins <- bind_rows(row_totals, col_totals, grand_total) |>
    mutate(is_margin = TRUE)
  plot_all <- bind_rows(plot_main, plot_margins)

  # x = max parent CEL (columns), y = child CEL (rows)
  # 0-7 at top/left, Total at bottom/right
  x_levels <- c(cel_levels, "Total")
  y_levels <- c(cel_levels, "Total")

  plot_all <- plot_all |>
    mutate(
      max_parent_cel_chr = factor(max_parent_cel_chr, levels = x_levels),
      cel_chr_child = factor(cel_chr_child, levels = c(cel_levels, "Total"))
    )

  # Color-coded axis labels
  # x-axis displays in factor order: 0..7, Total
  x_label_colors <- c(cel_colors, "Total" = "black")
  # y-axis is reversed by scale_y_discrete(limits = rev): Total, 7..0
  y_label_colors <- c("Total" = "black", rev(cel_colors))

  p_heat <- ggplot(plot_all, aes(x = max_parent_cel_chr, y = cel_chr_child)) +
    # Shaded tiles for main grid only
    geom_tile(data = plot_all |> filter(!is_margin),
              aes(fill = n), color = "white", linewidth = 0.5) +
    # Unshaded tiles for margins
    geom_tile(data = plot_all |> filter(is_margin),
              fill = "grey95", color = "white", linewidth = 0.5) +
    geom_text(aes(label = format(n, big.mark = ",")), size = 3.5) +
    scale_fill_gradient(low = "white", high = "#2166ac", guide = "none") +
    labs(
      x = "Max parent CEL", y = "Child CEL",
      title = paste0("Child vs. parent CEL \u2014 ", geo_label, ur_label),
      subtitle = paste0(filter_desc, " | ",
                        format(nrow(child_max_parent), big.mark = ","),
                        " children linked to co-resident parents")
    ) +
    scale_x_discrete(position = "top") +
    scale_y_discrete(limits = rev) +
    theme_minimal(base_size = 13) +
    theme(
      panel.grid = element_blank(),
      axis.text.x.top = element_text(color = x_label_colors, face = "bold"),
      axis.text.y = element_text(color = y_label_colors, face = "bold")
    )

  print(p_heat)

  # Return useful objects invisibly
  invisible(list(
    linked = linked,
    child_max_parent = child_max_parent,
    cross = cross,
    linkage_summary = linkage_summary,
    data = df,
    geo_label = geo_label,
    ur_label = ur_label,
    filter_desc = filter_desc
  ))
}

cat("analyze_child_parent_cel() defined.\n")

# Investigate 0-14 group in El Alto
el_alto_children <- analyze_child_parent_cel("020105")

geo_codes <- c("01", "02", "03", "04", "05", "06", "07", "08", "09")
all_children <- analyze_child_parent_cel(geo_codes, urban_rural = "Total")
rural_children <- analyze_child_parent_cel(geo_codes, urban_rural = "Rural")


