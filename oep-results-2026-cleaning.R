library(dplyr)
library(purrr)
library(stringr)
library(tibble)
library(tidyr)

# ==============================================================================
# CHECK / LOAD RAW DATA
# ==============================================================================
.raw_objects <- c("muni_votes", "concejales_df", "alcaldes_df",
                  "muni_roster_df", "muni_concejal_ioc")
.missing <- .raw_objects[!sapply(.raw_objects, exists, envir = .GlobalEnv,
                                  inherits = FALSE)]

if (length(.missing) > 0) {
  message("Missing in memory: ", paste(.missing, collapse = ", "))
  .raw_path <- here::here("data", "oep2026_raw.rds")
  if (file.exists(.raw_path)) {
    .ans <- readline("Load from data/oep2026_raw.rds? [y/n]: ")
    if (tolower(trimws(.ans)) == "y") {
      list2env(readRDS(.raw_path), envir = .GlobalEnv)
      message("Loaded.")
    } else {
      stop("Raw data not loaded. Run oep-results-2026.R first.")
    }
  } else {
    stop("data/oep2026_raw.rds not found. Run oep-results-2026.R first.")
  }
}
rm(.raw_objects, .missing)

# ==============================================================================
# 1. CANONICAL SIGLA LOOKUP
# ==============================================================================
# Strategy: fingerprint each raw sigla (strip hyphens, spaces, newlines, lowercase),
# then pick the cleanest form per fingerprint group as the canonical value.

meta_cols <- c("autoridad", "validos", "blancos", "nulos", "emitidos",
               "habilitados", "participacion")

fingerprint <- function(x) {
  x |> str_to_lower() |> str_remove_all("[-\\s\n]")
}

meta_fp <- fingerprint(meta_cols)

sigla_lookup <- muni_votes |>
  map(colnames) |>
  unlist() |>
  unique() |>
  (\(x) tibble(raw = x))() |>
  mutate(
    fp            = fingerprint(raw),
    has_nl        = str_detect(raw, "\n"),
    is_upper      = str_detect(raw, "^[A-Z]"),
    has_space_hyp = str_detect(raw, " - ")   # prefer "APB-SÚMATE" over "APB - SÚMATE"
  ) |>
  filter(!fp %in% meta_fp) |>
  group_by(fp) |>
  arrange(has_nl, desc(is_upper), has_space_hyp, raw) |>
  slice(1) |>
  ungroup() |>
  select(fp, canonical = raw)

normalize_sigla <- function(x) {
  fp  <- fingerprint(x)
  idx <- match(fp, sigla_lookup$fp)
  can <- sigla_lookup$canonical[idx]
  fallback <- str_squish(str_replace_all(str_replace_all(x, "-\n", "-"), "\n", " "))
  result <- if_else(!is.na(can), can, fallback)
  # Final pass: clean residual newlines (e.g. when canonical was itself the only form)
  str_squish(str_replace_all(str_replace_all(result, "-\n", "-"), "\n", " "))
}

# ==============================================================================
# 2. CLEAN DATA OBJECTS
# ==============================================================================

# muni_votes: clean column names (party siglas)
muni_votes_clean <- muni_votes |>
  map(~ { colnames(.x) <- normalize_sigla(colnames(.x)); .x })

# concejales: filter artifact rows, normalize silla and sigla
concejales <- as_tibble(concejales_df) |>
  filter(silla != "N.º") |>
  mutate(
    silla  = as.integer(str_remove(silla, "\\.$")),
    sigla  = normalize_sigla(sigla),
    nombre = str_squish(nombre)
  )

# alcaldes: normalize sigla and nombre
alcaldes <- as_tibble(alcaldes_df) |>
  mutate(
    sigla  = normalize_sigla(sigla),
    nombre = str_squish(nombre)
  )

source(here::here("R", "id-for-muni-prov.R"))

# muni_roster: plain tibble
muni_roster <- as_tibble(muni_roster_df) |>
  mutate(num = row_number())

muni_roster_1 <- muni_roster |>
  filter(province=="CERCADO") |>
  filter(municipality != "SAN JAVIER") |>
  mutate(id_muni = id_for_municipality_vec(municipality)) |>
  mutate(id_dep = str_sub(id_muni, 1L, 2L)) |>
  left_join(dep_id_lookup_table) |>
  select(-id_dep) |>
  mutate(department = toupper(department) ) |>
  relocate(id_muni) |>
  relocate(department, .after=province)

muni_roster_2 <- muni_roster |>
  filter(province=="CERCADO") |>
  filter(municipality == "SAN JAVIER") |>
  mutate(id_muni = "080102",
         department = "BENI") |>
  relocate(id_muni) |>
  relocate(department, .after=province)

muni_roster_3 <- muni_roster |>
  filter(province!="CERCADO") |>
  mutate(id_prov = id_for_province_vec(province)) |>
  mutate(id_dep = str_sub(id_prov, 1L, 2L)) |>
  left_join(dep_id_lookup_table) |>
  select(-id_dep, -id_prov) |>
  mutate(department = toupper(department) ) |>
  mutate(id_muni = id_for_municipality_vec(municipality, department)) |>
  relocate(id_muni) |>
  relocate(department, .after=province)

muni_roster <- bind_rows(muni_roster_1, muni_roster_2, muni_roster_3) |>
  arrange(num)

# ==============================================================================
# 3. COUNCIL SEAT SEQUENCE AUDIT
# ==============================================================================
# For each municipality, check whether titular and suplente seats form a clean
# unbroken sequence 1..n_sillas with no duplicates.

concejal_summary <- concejales |>
  group_by(municipio, provincia) |>
  summarise(
    n_sillas          = max(silla, na.rm = TRUE),
    n_titular         = sum(tipo == "TITULAR"),
    n_suplente        = sum(tipo == "SUPLENTE"),
    n_titular_blanco  = sum(tipo == "TITULAR"  & (is.na(nombre) | nombre == "")),
    n_suplente_blanco = sum(tipo == "SUPLENTE" & (is.na(nombre) | nombre == "")),
    titular_clean  = {
      seats <- silla[tipo == "TITULAR"]
      setequal(seats, seq_len(max(silla, na.rm = TRUE))) && !anyDuplicated(seats)
    },
    suplente_clean = {
      seats <- silla[tipo == "SUPLENTE"]
      setequal(seats, seq_len(max(silla, na.rm = TRUE))) && !anyDuplicated(seats)
    },
    .groups = "drop"
  ) |>
  arrange(provincia, municipio)

# Quick breakdown of problem types
concejal_summary |>
  filter(!titular_clean | !suplente_clean) |>
  mutate(
    issue = case_when(
      n_titular > n_sillas | n_suplente > n_sillas ~ "duplicates",
      n_titular < n_sillas | n_suplente < n_sillas ~ "gaps / missing",
      TRUE ~ "gap + duplicate"
    )
  ) |>
  count(issue) |>
  print()

concejal_summary |>
  filter(!titular_clean | !suplente_clean) |>
  mutate(
    issue = case_when(
      n_titular > n_sillas | n_suplente > n_sillas ~ "duplicates",
      n_titular < n_sillas | n_suplente < n_sillas ~ "gaps / missing",
      TRUE ~ "gap + duplicate"
    )
  ) |>
  filter(issue=="gap + duplicate")

concejal_summary |> count(n_sillas)

# Municipalities with special IOC council members
muni_concejal_ioc |> distinct(municipio) |>
  pull(municipio) -> ioc_munis

# Normal councils have odd numbers of members, but these
# with even numbers should have an extra IOC member.
concejal_summary |> filter(n_sillas %% 2 == 0)

concejal_summary |> filter(n_sillas %% 2 == 0) |>
  filter(!(municipio %in% ioc_munis)) -> truly_even_concejo

if(nrow(truly_even_concejo) > 0) {
  cat("There are ", nrow(truly_even_concejo), " municipalities with an ",
      "anomalous, even number of council members.")
  print(truly_even_concejo)
}

# ==============================================================================
# 4. COMBINED COUNCIL TABLE
# ==============================================================================
# muni_concejo_comb: all concejales plus IOC seats appended as seat n+1.
# esp_ioc = TRUE marks the added indigenous seats; FALSE for all regular seats.

ioc_next_silla <- concejal_summary |>
  filter(municipio %in% ioc_munis) |>
  select(municipio, n_sillas)

muni_concejo_comb <- bind_rows(
  concejales |>
    mutate(esp_ioc = FALSE),
  muni_concejal_ioc |>
    left_join(ioc_next_silla, by = "municipio") |>
    mutate(
      silla   = n_sillas + 1L,
      esp_ioc = TRUE
    ) |>
    select(-n_sillas)
)

# ==============================================================================
# 5. PARTY SUMMARY FUNCTION
# ==============================================================================
# Aggregates vote share, elected alcaldes, elected concejal titulares, and
# municipalities represented, for a given scope of municipalities.
#
# Arguments:
#   id_munis   - character vector of id_muni codes (takes priority)
#   department - character scalar/vector of department names (case-insensitive)
# If both NULL, aggregates across all municipalities.
#
# Returns a tibble with one row per party (sigla), sorted by n_concejales desc.
# Depends on: muni_votes_clean, alcaldes, concejales, muni_roster (global env).

party_summary <- function(id_munis = NULL, department = NULL) {
  # Determine scope
  scope <- muni_roster
  if (!is.null(id_munis)) {
    scope <- scope |> filter(id_muni %in% id_munis)
  } else if (!is.null(department)) {
    scope <- scope |> filter(toupper(.data$department) %in% toupper(department))
  }

  muni_names  <- scope$municipality
  meta_cols_v <- c("autoridad", "validos", "blancos", "nulos", "emitidos",
                   "habilitados", "participacion")

  # Parse Bolivian-format numeric strings: "6.457" (thousands sep) → 6457
  parse_num <- function(x) as.numeric(str_remove_all(as.character(x), "\\."))

  # Build tidy vote frame: one row per municipality × race × party
  votes_tidy <- map_dfr(scope$num, function(idx) {
    df         <- muni_votes_clean[[idx]]
    party_cols <- setdiff(colnames(df), meta_cols_v)

    df |>
      select(autoridad, validos, all_of(party_cols)) |>
      mutate(
        validos = parse_num(validos),
        across(all_of(party_cols), parse_num)
      ) |>
      pivot_longer(all_of(party_cols), names_to = "sigla", values_to = "votes") |>
      mutate(
        municipio = scope$municipality[scope$num == idx],
        race = case_when(
          str_detect(autoridad, regex("alcalde",  ignore_case = TRUE)) ~ "alcalde",
          str_detect(autoridad, regex("concejal", ignore_case = TRUE)) ~ "concejal",
          TRUE ~ NA_character_
        )
      ) |>
      filter(!is.na(race))
  })

  # Total valid votes per race (denominators for share)
  validos_by_race <- votes_tidy |>
    distinct(municipio, race, validos) |>
    group_by(race) |>
    summarise(total_validos = sum(validos, na.rm = TRUE), .groups = "drop")

  alcalde_validos  <- validos_by_race |> filter(race == "alcalde")  |> pull(total_validos)
  concejal_validos <- validos_by_race |> filter(race == "concejal") |> pull(total_validos)

  # Party vote totals by race, pivoted wide
  vote_totals <- votes_tidy |>
    group_by(sigla, race) |>
    summarise(total_votes = sum(votes, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(names_from = race, values_from = total_votes,
                names_prefix = "votes_",
                values_fill  = 0)

  # Elected alcaldes per party
  mayor_counts <- alcaldes |>
    filter(municipio %in% muni_names) |>
    count(sigla, name = "n_alcaldes")

  # Elected concejal titulares per party (excludes IOC seats)
  concejal_counts <- concejales |>
    filter(municipio %in% muni_names, tipo == "TITULAR") |>
    count(sigla, name = "n_concejales")

  # Municipalities where party holds alcalde or ≥1 concejal titular
  muni_repr <- bind_rows(
    alcaldes  |> filter(municipio %in% muni_names) |> select(sigla, municipio),
    concejales |> filter(municipio %in% muni_names, tipo == "TITULAR") |> select(sigla, municipio)
  ) |>
    distinct() |>
    count(sigla, name = "n_munis")

  vote_totals |>
    full_join(mayor_counts,    by = "sigla") |>
    full_join(concejal_counts, by = "sigla") |>
    full_join(muni_repr,       by = "sigla") |>
    mutate(
      vote_share_alcalde  = votes_alcalde  / alcalde_validos,
      vote_share_concejal = votes_concejal / concejal_validos,
      across(c(n_alcaldes, n_concejales, n_munis), ~ replace_na(.x, 0L))
    ) |>
    arrange(desc(n_concejales), desc(vote_share_concejal)) |>
    select(sigla, vote_share_concejal, vote_share_alcalde,
           n_alcaldes, n_concejales, n_munis)
}

