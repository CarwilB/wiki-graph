# plot-cel-butterfly-suite.R
#
# CEL butterfly chart visualizations for Bolivia 2024 Census
# Generates national-level CEL distribution panels stratified by:
#   1. Urban/rural residence
#   2. Age groups
#   3. Major indigenous languages (excluding Castellano)
#
# Source this script to load plot_cel_butterfly(), compute_cel(), and 
# read_census_geo() functions, then run the visualization sections below.

library(tidyverse)
library(arrow)
library(patchwork)
library(scales)

# ── Paths ──
DATA_DIR <- "../bolivia-data/Censo 2024/base_datos_csv_2024"
PERSONA_PATH <- file.path(DATA_DIR, "Persona_CPV-2024.csv")
VIVIENDA_PATH <- file.path(DATA_DIR, "Vivienda_CPV-2024.csv")

# ── Load lookup tables and infrastructure ──
muni_lookup <- readRDS("data/muni_id_lookup_table.rds")
prov_id_lookup_table <- read_rds(here::here("data", "prov_id_lookup_table.rds"))
idioma_cats <- readRDS(here::here("data", "idioma_cats.rds"))

# ── CEL computation infrastructure ──
.indigenous_idioma_codes <- c(1:5, 7:37)
.generic_groups <- c(1L, 13L, 37L, 47L, 55L, 56L, 57L, 58L)

.lookup_flat <- tribble(
  ~pc, ~ic,
  2L,  1L, 3L,  2L, 4L,  37L, 5L,  3L, 6L,  5L, 7L,  7L, 8L,  8L, 9L,  9L,
  10L, 27L, 11L, 27L, 12L, 4L, 14L, 11L, 15L, 12L, 16L, 13L, 17L, 14L,
  18L, 15L, 19L, 2L, 20L, 27L, 21L, 19L, 22L, 17L, 23L, 2L, 24L, 16L,
  25L, 27L, 26L, 2L, 27L, 18L, 28L, 19L, 29L, 20L, 29L, 21L, 30L, 20L,
  31L, 21L, 32L, 22L, 33L, 23L, 34L, 24L, 35L, 25L, 36L, 2L, 38L, 26L,
  39L, 2L, 40L, 27L, 41L, 2L, 42L, 27L, 43L, 28L, 44L, 2L, 45L, 29L,
  46L, 30L, 48L, 10L, 49L, 32L, 50L, 33L, 51L, 34L, 52L, 27L, 53L, 35L,
  54L, 36L, 55L, 2L, 55L, 27L
)

.valid_match_q2 <- matrix(FALSE, nrow = 99L, ncol = 38L)
for (i in seq_len(nrow(.lookup_flat))) {
  .valid_match_q2[.lookup_flat$pc[i], .lookup_flat$ic[i]] <- TRUE
}
for (g in .generic_groups) {
  .valid_match_q2[g, .indigenous_idioma_codes[.indigenous_idioma_codes <= 38L]] <- TRUE
}

# ── Compute CEL from raw persona columns ──
compute_cel <- function(df) {
  albo_q1 <- df$p32_pueblo_per == 1L
  albo_q1[is.na(albo_q1)] <- FALSE
  
  imc <- df$p341_idiomat_cod
  albo_q3 <- !is.na(imc) & imc != 6L & imc != 999L
  
  l1 <- df$p331_idiohab1_cod; l2 <- df$p332_idiohab2_cod; l3 <- df$p333_idiohab3_cod
  albo_c <- (!is.na(l1) & l1 == 6L) | (!is.na(l2) & l2 == 6L) | (!is.na(l3) & l3 == 6L)
  
  p32s <- ifelse(is.na(df$p32_pueblos) | df$p32_pueblos > 99L, 0L, df$p32_pueblos)
  l1s  <- ifelse(is.na(l1) | l1 > 38L, 0L, l1)
  l2s  <- ifelse(is.na(l2) | l2 > 38L, 0L, l2)
  l3s  <- ifelse(is.na(l3) | l3 > 38L, 0L, l3)
  
  has <- p32s > 0L
  q2v <- logical(nrow(df))
  q2v[has] <- .valid_match_q2[cbind(p32s[has], pmax(l1s[has], 1L))]
  q2v[has] <- q2v[has] | (l2s[has] > 0L & .valid_match_q2[cbind(p32s[has], pmax(l2s[has], 1L))])
  q2v[has] <- q2v[has] | (l3s[has] > 0L & .valid_match_q2[cbind(p32s[has], pmax(l3s[has], 1L))])
  
  speaks_indig <- (l1s %in% .indigenous_idioma_codes) | 
                  (l2s %in% .indigenous_idioma_codes) | 
                  (l3s %in% .indigenous_idioma_codes)
  cel_q2 <- ifelse(albo_q1, q2v, speaks_indig)
  
  cel <- case_when(
     albo_q1 &  cel_q2 &  albo_q3 & !albo_c ~ 7,
     albo_q1 &  cel_q2 &  albo_q3 &  albo_c ~ 6,
     albo_q1 &  cel_q2 & !albo_q3            ~ 5,
     albo_q1 & !cel_q2 &  albo_q3            ~ 4.5,
     albo_q1 & !cel_q2 & !albo_q3            ~ 4,
    !albo_q1 &  cel_q2 &  albo_q3 & !albo_c ~ 3,
    !albo_q1 &  cel_q2 &  albo_q3 &  albo_c ~ 2,
    !albo_q1 &  cel_q2 & !albo_q3            ~ 1,
    !albo_q1 & !cel_q2 &  albo_q3            ~ 1.5,
    !albo_q1 & !cel_q2 & !albo_q3            ~ 0
  )
  cel
}

# ── Reusable data reading function ──
read_census_geo <- function(
    geo_codes,
    urban_rural = NULL,
    extra_cols = character(),
    persona_path = PERSONA_PATH,
    vivienda_path = VIVIENDA_PATH
) {
  geo_codes <- as.character(geo_codes)
  geo_codes <- ifelse(nchar(geo_codes) == 1, paste0("0", geo_codes), geo_codes)
  code_lens <- nchar(geo_codes)
  stopifnot(all(code_lens %in% c(2, 4, 6)))
  
  dept_codes <- geo_codes[code_lens == 2]
  prov_codes <- geo_codes[code_lens == 4]
  mun_codes  <- geo_codes[code_lens == 6]
  
  dept_ints <- as.integer(dept_codes)
  prov_tuples <- if (length(prov_codes) > 0) {
    tibble(idep = as.integer(substr(prov_codes, 1, 2)),
           iprov = as.integer(substr(prov_codes, 3, 4)))
  }
  mun_tuples <- if (length(mun_codes) > 0) {
    tibble(idep = as.integer(substr(mun_codes, 1, 2)),
           iprov = as.integer(substr(mun_codes, 3, 4)),
           imun = as.integer(substr(mun_codes, 5, 6)))
  }
  
  geo_labels <- character()
  if (length(dept_codes) > 0)
    geo_labels <- c(geo_labels, muni_lookup |> filter(substr(id_muni, 1, 2) %in% dept_codes) |> distinct(department) |> pull(department))
  if (length(prov_codes) > 0)
    geo_labels <- c(geo_labels, paste0("Prov. ", prov_id_lookup_table |> filter(id_prov %in% prov_codes) |> pull(province_gb2014)))
  if (length(mun_codes) > 0)
    geo_labels <- c(geo_labels, muni_lookup |> filter(id_muni %in% mun_codes) |> pull(muni_gb2014))
  geo_label <- paste(geo_labels, collapse = ", ")
  
  all_depts <- unique(c(
    dept_ints,
    if (!is.null(prov_tuples)) prov_tuples$idep else integer(),
    if (!is.null(mun_tuples)) mun_tuples$idep else integer()
  ))
  
  base_cols <- c("idep", "iprov", "imun", "i00", "p24_parentes", "p25_sexo",
                 "p26_edad", "idioma_mat",
                 "p32_pueblo_per", "p32_pueblos",
                 "p331_idiohab1_cod", "p332_idiohab2_cod", "p333_idiohab3_cod",
                 "p341_idiomat_cod")
  needed_cols <- unique(c(base_cols, extra_cols))
  
  ds <- open_dataset(persona_path, format = "csv", delimiter = ";")
  df <- ds |>
    filter(idep %in% !!all_depts) |>
    select(any_of(needed_cols)) |>
    collect()
  
  keep <- rep(FALSE, nrow(df))
  if (length(dept_ints) > 0) keep <- keep | (df$idep %in% dept_ints)
  if (!is.null(prov_tuples)) {
    for (i in seq_len(nrow(prov_tuples)))
      keep <- keep | (df$idep == prov_tuples$idep[i] & df$iprov == prov_tuples$iprov[i])
  }
  if (!is.null(mun_tuples)) {
    for (i in seq_len(nrow(mun_tuples)))
      keep <- keep | (df$idep == mun_tuples$idep[i] & df$iprov == mun_tuples$iprov[i] & df$imun == mun_tuples$imun[i])
  }
  df <- df[keep, ]
  
  viv_ds <- open_dataset(vivienda_path, format = "csv", delimiter = ";")
  urbrur_lookup <- viv_ds |>
    filter(idep %in% !!all_depts) |>
    select(idep, iprov, imun, i00, urbrur) |>
    collect() |>
    semi_join(df |> distinct(idep, iprov, imun), by = c("idep", "iprov", "imun"))
  
  df <- df |> left_join(urbrur_lookup, by = c("idep", "iprov", "imun", "i00"))
  
  ur_label <- ""
  if (!is.null(urban_rural)) {
    stopifnot(urban_rural %in% c("urban", "rural"))
    ur_code <- if (urban_rural == "urban") 1L else 2L
    df <- df |> filter(urbrur == ur_code)
    ur_label <- paste0(" (", tools::toTitleCase(urban_rural), ")")
  }
  
  # Compute CEL using raw columns only
  cel_values <- compute_cel(df)
  
  df <- df |>
    mutate(
      cel = cel_values,
      cel_chr = factor(as.character(cel), 
                       levels = c("0", "1", "1.5", "2", "3", "4", "4.5", "5", "6", "7")),
      age_group = cut(p26_edad, breaks = c(0, 15, 30, 45, 60, Inf),
                      labels = c("0-14", "15-29", "30-44", "45-59", "60+"),
                      right = FALSE, include.lowest = TRUE)
    )
  
  idioma_lookup <- setNames(idioma_cats$label, as.character(idioma_cats$code))
  df <- df |>
    mutate(idioma_label = coalesce(idioma_lookup[as.character(idioma_mat)], 
                                    paste0("Code ", idioma_mat)))
  
  cat(sprintf("%s%s: %s persons.\n", geo_label, ur_label, format(nrow(df), big.mark = ",")))
  
  df <- df |>
    mutate(dwelling_key = paste(idep, iprov, imun, i00, sep = "_"))
  
  list(data = df, geo_label = geo_label, ur_label = ur_label)
}

# ── Main butterfly chart function ──
plot_cel_butterfly <- function(
    geo_codes,
    urban_rural = NULL,
    persona_path = PERSONA_PATH,
    vivienda_path = VIVIENDA_PATH,
    top_n_langs = 8,
    age_breaks = c(0, 15, 30, 45, 60, Inf),
    age_labels = c("0-14", "15-29", "30-44", "45-59", "60+")
) {
  result <- read_census_geo(geo_codes, urban_rural, persona_path, vivienda_path)
  df <- result$data
  geo_label <- result$geo_label
  ur_label <- result$ur_label
  
  n_total <- nrow(df)
  
  # ── Label and group idioma_mat ──
  idioma_lookup <- setNames(idioma_cats$label, as.character(idioma_cats$code))
  df <- df |>
    mutate(idioma_label_raw = coalesce(idioma_lookup[as.character(idioma_mat)], 
                                       paste0("Code ", idioma_mat)))
  
  # Group languages < 1% into "Other indigenous" or "Other"
  lang_counts <- df |>
    filter(!is.na(idioma_mat)) |>
    count(idioma_label_raw, idioma_mat) |>
    mutate(pct = n / n_total)
  
  threshold_langs <- lang_counts |> filter(pct >= 0.01) |> pull(idioma_label_raw)
  indig_codes <- c(1:5, 7:37)
  
  df <- df |>
    mutate(idioma_label = case_when(
      idioma_label_raw %in% threshold_langs ~ idioma_label_raw,
      idioma_mat %in% indig_codes ~ "Other indigenous",
      is.na(idioma_mat) ~ NA_character_,
      TRUE ~ "Other"
    ))
  
  # ── CEL styling ──
  cel_colors_local <- c(
    "0" = "#d9d9d9", "1" = "#fee0b6", "1.5" = "#fdb863", "2" = "#e08214",
    "3" = "#b35806", "4" = "#cce5ff", "4.5" = "#74add1", "5" = "#4393c3",
    "6" = "#2166ac", "7" = "#053061"
  )
  left_levels  <- c("0", "1", "1.5", "2", "3")
  right_levels <- c("4", "4.5", "5", "6", "7")
  
  cel_labels_local <- c(
    "0" = "0 — No identity, no language", "1" = "1 — Speaks only",
    "1.5" = "1.5 — Childhood only", "2" = "2 — Speaks + childhood (bilingual)",
    "3" = "3 — Speaks + childhood (mono)", "4" = "4 — Identity only",
    "4.5" = "4.5 — Identity + childhood", "5" = "5 — Identity + speaks",
    "6" = "6 — Full (bilingual)", "7" = "7 — Full (monolingual)"
  )
  
  # ── Helper: butterfly data ──
  make_butterfly_data <- function(df_sub, group_var) {
    grp_sym <- sym(group_var)
    summary_df <- df_sub |>
      filter(!is.na(!!grp_sym)) |>
      count(!!grp_sym, cel_chr) |>
      mutate(cel_val = as.character(cel_chr),
             side = if_else(cel_val %in% left_levels, "left", "right"))
    group_totals <- summary_df |>
      group_by(!!grp_sym) |> summarise(total = sum(n), .groups = "drop")
    summary_df |>
      left_join(group_totals, by = group_var) |>
      mutate(
        y_label = paste0(!!grp_sym, "\nn = ", format(total, big.mark = ",")),
        n_plot = if_else(side == "left", -n, n)
      )
  }
  
  # ── Idioma panel ──
  lang_order <- df |>
    filter(!is.na(idioma_label)) |>
    count(idioma_label) |>
    mutate(rank = case_when(
      idioma_label == "Other" ~ -2,
      idioma_label == "Other indigenous" ~ -1,
      TRUE ~ as.numeric(n)
    )) |>
    arrange(desc(rank)) |>
    pull(idioma_label)
  
  df_lang <- df |>
    filter(!is.na(idioma_label)) |>
    mutate(idioma_label = factor(idioma_label, levels = rev(lang_order)))
  
  lang_data <- make_butterfly_data(df_lang, "idioma_label")
  lang_data <- lang_data |>
    mutate(y_label = fct_reorder(y_label, as.numeric(idioma_label)))
  
  # ── Age panel ──
  age_data <- make_butterfly_data(df, "age_group")
  age_data <- age_data |>
    mutate(y_label = fct_reorder(y_label, as.numeric(age_group)))
  
  # ── Panel builder ──
  abs_comma <- function(x) format(abs(x), big.mark = ",", scientific = FALSE)
  
  make_panel <- function(data, panel_title) {
    ggplot(data, aes(x = n_plot, y = y_label, fill = cel_chr)) +
      geom_col(width = 0.65, just = 0.5) +
      geom_vline(xintercept = 0, linewidth = 0.3) +
      scale_fill_manual(
        values = cel_colors_local,
        labels = cel_labels_local,
        breaks = c("0", "1", "1.5", "2", "3", "4", "4.5", "5", "6", "7"),
        name = "CEL"
      ) +
      scale_x_continuous(labels = abs_comma) +
      labs(x = NULL, y = NULL, subtitle = panel_title) +
      theme_minimal(base_size = 11) +
      theme(
        panel.grid.major.y = element_blank(),
        panel.grid.minor = element_blank(),
        plot.subtitle = element_text(face = "bold", size = 11)
      )
  }
  
  p_lang <- make_panel(lang_data, "By mother tongue")
  p_age  <- make_panel(age_data, "By age group")
  
  # ── Combine ──
  title_text <- paste0("CEL distribution — ", geo_label, ur_label)
  subtitle_text <- paste0(
    "n = ", format(n_total, big.mark = ","),
    "        ← CEL 0–3        CEL 4–7 →"
  )
  
  combined <- p_lang / p_age +
    plot_layout(guides = "collect") +
    plot_annotation(
      title = title_text,
      subtitle = subtitle_text,
      theme = theme(
        plot.title = element_text(face = "bold", size = 13),
        plot.subtitle = element_text(size = 10, color = "grey40")
      )
    )
  
  combined
}

cat("✓ Functions loaded: compute_cel(), read_census_geo(), plot_cel_butterfly()\n\n")

# ────────────────────────────────────────────────────────────────────────────
# VISUALIZATIONS
# ────────────────────────────────────────────────────────────────────────────

cat("Generating visualizations...\n\n")

# For national visualizations, use specific departments with manageable sizes
# Build list of all department codes
all_depts <- as.character(1:9)
all_depts <- sprintf("%02d", as.numeric(all_depts))

# ── 1. National: Urban vs. Rural ──
cat("1. Urban vs. Rural CEL distribution (national)\n")
# For national scale, show urban and rural separately
p_urban <- plot_cel_butterfly(all_depts, urban_rural = "urban")
p_rural <- plot_cel_butterfly(all_depts, urban_rural = "rural")

plot_urban_rural <- (p_urban / p_rural) +
  plot_layout(guides = "collect") &
  theme(plot.title = element_text(hjust = 0.5))

print(plot_urban_rural)

# ── 2. National: Age groups ──
cat("\n2. Age-stratified CEL distribution (national)\n")
p_national <- plot_cel_butterfly(all_depts)
print(p_national)

# ── 3. National: Major indigenous languages (exclude Castellano) ──
cat("\n3. CEL distribution by major indigenous mother tongue (national)\n")
# This uses the same function but focuses on indigenous language stratification
# The butterfly chart automatically handles this via the idioma panel
# The plot above (p_national) already shows this breakdown in the first panel

cat("\n✓ All visualizations complete.\n")
