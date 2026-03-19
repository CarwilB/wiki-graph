# ── CEL computation infrastructure and census data loading ──
# Dependencies: tidyverse, arrow, here

library(tidyverse)
library(arrow)

# ── Lookup tables ──
muni_lookup <- readRDS("data/muni_id_lookup_table.rds")
prov_id_lookup_table <- readRDS("data/prov_id_lookup_table.rds")
idioma_cats <- readRDS("data/idioma_cats.rds")

# ── CEL color palette ──
cel_colors <- c(
  "0" = "#d9d9d9", "1" = "#fee0b6", "1.5" = "#fdb863",
  "2" = "#e08214", "3" = "#b35806", "4" = "#cce5ff",
  "4.5" = "#74add1", "5" = "#4393c3", "6" = "#2166ac",
  "7" = "#053061"
)

# ── Pueblos-to-idioma lookup matrix ──
# Maps p32_pueblos codes (rows) to idioma codes (columns) for Q2 matching
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

# ── Core function: compute CEL from raw persona columns ──
compute_cel <- function(df) {
  # df must have: p32_pueblo_per, p32_pueblos, p331_idiohab1_cod,
  #   p332_idiohab2_cod, p333_idiohab3_cod, p341_idiomat_cod

  albo_q1 <- df$p32_pueblo_per == 1L
  albo_q1[is.na(albo_q1)] <- FALSE

  # albo_q3: learned indigenous language as child
  imc <- df$p341_idiomat_cod
  albo_q3 <- !is.na(imc) & imc != 6L & imc != 999L

  # albo_c: speaks Castellano
  l1 <- df$p331_idiohab1_cod; l2 <- df$p332_idiohab2_cod; l3 <- df$p333_idiohab3_cod
  albo_c <- (!is.na(l1) & l1 == 6L) | (!is.na(l2) & l2 == 6L) | (!is.na(l3) & l3 == 6L)

  # albo_q2 (for identifiers): language matches declared identity
  p32s <- ifelse(is.na(df$p32_pueblos) | df$p32_pueblos > 99L, 0L, df$p32_pueblos)
  l1s  <- ifelse(is.na(l1) | l1 > 38L, 0L, l1)
  l2s  <- ifelse(is.na(l2) | l2 > 38L, 0L, l2)
  l3s  <- ifelse(is.na(l3) | l3 > 38L, 0L, l3)

  has <- p32s > 0L
  q2v <- logical(nrow(df))
  q2v[has] <- .valid_match_q2[cbind(p32s[has], pmax(l1s[has], 1L))]
  q2v[has] <- q2v[has] | (l2s[has] > 0L & .valid_match_q2[cbind(p32s[has], pmax(l2s[has], 1L))])
  q2v[has] <- q2v[has] | (l3s[has] > 0L & .valid_match_q2[cbind(p32s[has], pmax(l3s[has], 1L))])

  # cel_q2: for identifiers = albo_q2; for non-identifiers = speaks any indigenous language
  speaks_indig <- (l1s %in% .indigenous_idioma_codes) |
    (l2s %in% .indigenous_idioma_codes) |
    (l3s %in% .indigenous_idioma_codes)
  cel_q2 <- ifelse(albo_q1, q2v, speaks_indig)

  # CEL scale
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

# ── Load and filter census data by geography ──
read_census_geo <- function(
    geo_codes,
    urban_rural = NULL,
    extra_cols = character(),
    persona_path = "../bolivia-data/Censo 2024/base_datos_csv_2024/Persona_CPV-2024.csv",
    vivienda_path = "../bolivia-data/Censo 2024/base_datos_csv_2024/Vivienda_CPV-2024.csv"
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

  # Geo label
  geo_labels <- character()
  if (length(dept_codes) > 0)
    geo_labels <- c(geo_labels,
      muni_lookup |> filter(substr(id_muni, 1, 2) %in% dept_codes) |>
        distinct(department) |> pull(department))
  if (length(prov_codes) > 0)
    geo_labels <- c(geo_labels,
      paste0("Prov. ", prov_id_lookup_table |>
        filter(id_prov %in% prov_codes) |> pull(province_gb2014)))
  if (length(mun_codes) > 0)
    geo_labels <- c(geo_labels,
      muni_lookup |> filter(id_muni %in% mun_codes) |> pull(muni_gb2014))
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

  # Precise filter
  keep <- rep(FALSE, nrow(df))
  if (length(dept_ints) > 0) keep <- keep | (df$idep %in% dept_ints)
  if (!is.null(prov_tuples)) {
    for (i in seq_len(nrow(prov_tuples)))
      keep <- keep | (df$idep == prov_tuples$idep[i] & df$iprov == prov_tuples$iprov[i])
  }
  if (!is.null(mun_tuples)) {
    for (i in seq_len(nrow(mun_tuples)))
      keep <- keep | (df$idep == mun_tuples$idep[i] & df$iprov == mun_tuples$iprov[i] &
                        df$imun == mun_tuples$imun[i])
  }
  df <- df[keep, ]

  # Join urbrur from vivienda
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

  # Compute CEL
  df <- df |>
    mutate(
      cel = compute_cel(pick(everything())),
      cel_chr = factor(as.character(cel),
                       levels = c("0", "1", "1.5", "2", "3", "4", "4.5", "5", "6", "7")),
      age_group = cut(p26_edad, breaks = c(0, 15, 30, 45, 60, Inf),
                      labels = c("0-14", "15-29", "30-44", "45-59", "60+"),
                      right = FALSE, include.lowest = TRUE)
    )

  # Label idioma_mat
  idioma_lookup <- setNames(idioma_cats$label, as.character(idioma_cats$code))
  df <- df |>
    mutate(idioma_label = coalesce(idioma_lookup[as.character(idioma_mat)],
                                   paste0("Code ", idioma_mat)))

  cat(sprintf("%s%s: %s persons.\n", geo_label, ur_label, format(nrow(df), big.mark = ",")))

  # Create dwelling key for household linkage
  df <- df |>
    mutate(dwelling_key = paste(idep, iprov, imun, i00, sep = "_"))

  list(data = df, geo_label = geo_label, ur_label = ur_label)
}

cat("cel_helpers.R loaded: compute_cel(), read_census_geo(), lookup tables, cel_colors.\n")
